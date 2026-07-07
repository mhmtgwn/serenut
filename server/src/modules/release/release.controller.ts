import { Router, Request, Response, NextFunction } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import { pgPool } from '../../config/database';
import { authenticateUser, AuthenticatedRequest, requireRole } from '../../middleware/auth.middleware';

const router = Router();

// ── MULTER STORAGE SETUP ────────────────────────────────────────────────────
const RELEASES_BASE_DIR = process.env.RELEASES_DIR || '/var/www/serenut-api/releases';
const ALLOWED_EXTENSIONS = ['.apk', '.aab', '.exe', '.msix'];
const MAX_FILE_SIZE_MB = 150;

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const { platform, channel } = (req as any).body;
    const uploadDir = path.join(RELEASES_BASE_DIR, platform || 'android', channel || 'stable');
    fs.mkdirSync(uploadDir, { recursive: true });
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const timestamp = Date.now();
    const ext = path.extname(file.originalname);
    cb(null, `${timestamp}${ext}`);
  }
});

const upload = multer({
  storage,
  limits: { fileSize: MAX_FILE_SIZE_MB * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (ALLOWED_EXTENSIONS.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error(`invalid_file_type: Only ${ALLOWED_EXTENSIONS.join(', ')} allowed`));
    }
  }
});

// Helper: compute SHA-256 of a local file
function computeFileSha256(filePath: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(filePath);
    stream.on('data', (data) => hash.update(data));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', reject);
  });
}

// Helper: RLS bypass for admin queries
async function runBypassingRLS(sql: string, params: any[] = []) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const res = await client.query(sql, params);
    await client.query('COMMIT');
    return res;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// Helper: determine rollout eligibility for a device
function isDeviceInRollout(deviceId: string, rolloutPercentage: number): boolean {
  if (rolloutPercentage >= 100) return true;
  if (rolloutPercentage <= 0) return false;
  // Deterministic hash-based bucketing — same device always gets same answer
  const hash = crypto.createHash('md5').update(deviceId).digest('hex');
  const bucket = parseInt(hash.substring(0, 4), 16) % 100;
  return bucket < rolloutPercentage;
}

// ── 0. PUBLIC RELEASE HISTORY (Called by website release notes) ──────────────
router.get('/history', async (req: Request, res: Response) => {
  try {
    const list = await pgPool.query(`
      SELECT version_code, platform, release_notes, created_at
      FROM app_versions
      WHERE status = 'active' AND channel = 'stable'
      ORDER BY created_at DESC
    `);
    return res.json(list.rows);
  } catch (err) {
    console.error('Release history error:', err);
    return res.status(500).json({ error: 'server_error', message: 'Sürüm geçmişi alınamadı.' });
  }
});

// ── 1. CHECK FOR UPDATES (Public — called by Flutter app on startup) ─────────
router.get('/check', async (req: Request, res: Response) => {
  const { platform, current_version, channel, device_id, company_id } = req.query as Record<string, string>;

  if (!platform || !current_version) {
    return res.status(400).json({ error: 'missing_parameters', message: 'platform ve current_version zorunludur.' });
  }

  const releaseChannel = channel || 'stable';

  try {
    // Fetch latest active release for this platform + channel
    const releasesRes = await pgPool.query(`
      SELECT av.*, 
             (SELECT COUNT(*) FROM update_targets ut WHERE ut.release_id = av.id) as target_count
      FROM app_versions av
      WHERE av.platform = $1 
        AND av.channel = $2 
        AND av.status = 'active'
      ORDER BY av.created_at DESC
      LIMIT 5
    `, [platform, releaseChannel]);

    if (releasesRes.rows.length === 0) {
      return res.json({
        latestVersion: current_version,
        minRequiredVersion: current_version,
        isForceUpdate: false,
        downloadUrl: null,
        sha256Hash: null,
        fileSizeBytes: null,
        releaseNotes: null,
        hasUpdate: false,
      });
    }

    // Find the first release this device qualifies for
    let eligibleRelease = null;
    for (const release of releasesRes.rows) {
      // Check rollout percentage
      if (device_id && !isDeviceInRollout(device_id, release.rollout_percentage)) continue;

      // Check targeting — if no targets defined, this release is public
      if (parseInt(release.target_count, 10) > 0 && device_id && company_id) {
        const targetCheck = await pgPool.query(`
          SELECT id FROM update_targets
          WHERE release_id = $1 AND (
            (target_type = 'company' AND target_value = $2) OR
            (target_type = 'device' AND target_value = $3)
          )
        `, [release.id, company_id, device_id]);

        if (targetCheck.rows.length === 0) {
          // Check license tier targeting
          const tierCheck = await pgPool.query(`
            SELECT ut.id FROM update_targets ut
            JOIN licenses l ON l.company_id = $1 AND l.tier = ut.target_value AND l.status = 'active'
            WHERE ut.release_id = $2 AND ut.target_type = 'license_tier'
            LIMIT 1
          `, [company_id, release.id]);
          if (tierCheck.rows.length === 0) continue;
        }
      }

      eligibleRelease = release;
      break;
    }

    if (!eligibleRelease) {
      return res.json({
        latestVersion: current_version,
        minRequiredVersion: current_version,
        isForceUpdate: false,
        downloadUrl: null,
        sha256Hash: null,
        fileSizeBytes: null,
        releaseNotes: null,
        hasUpdate: false,
      });
    }

    const hasUpdate = eligibleRelease.version_code !== current_version;

    // Determine force update — if device version is below min_required
    let isForceUpdate = false;
    if (eligibleRelease.is_mandatory && hasUpdate) {
      isForceUpdate = true;
    }
    if (eligibleRelease.min_required_version && current_version < eligibleRelease.min_required_version) {
      isForceUpdate = true;
    }

    // Build secure download URL (token-protected endpoint)
    const downloadUrl = hasUpdate
      ? `/api/v1/releases/download/${eligibleRelease.id}`
      : null;

    return res.json({
      latestVersion: eligibleRelease.version_code,
      minRequiredVersion: eligibleRelease.min_required_version || current_version,
      isForceUpdate,
      downloadUrl,
      sha256Hash: hasUpdate ? eligibleRelease.sha256_hash : null,
      fileSizeBytes: hasUpdate ? eligibleRelease.file_size_bytes : null,
      releaseNotes: eligibleRelease.release_notes || null,
      hasUpdate,
      channel: releaseChannel,
    });
  } catch (err) {
    console.error('Release check error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 2. SECURE DOWNLOAD (Auth Required) ──────────────────────────────────────
router.get('/download/:releaseId', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { releaseId } = req.params;
  const deviceId = req.query.device_id as string;

  try {
    // Fetch release info
    const releaseRes = await pgPool.query(
      "SELECT * FROM app_versions WHERE id = $1 AND status = 'active'",
      [releaseId]
    );

    if (releaseRes.rows.length === 0) {
      return res.status(404).json({ error: 'release_not_found' });
    }

    const release = releaseRes.rows[0];

    // Verify user has active license
    const licenseCheck = await pgPool.query(
      "SELECT id FROM licenses WHERE company_id = $1 AND status = 'active' LIMIT 1",
      [user.company_id]
    );
    if (licenseCheck.rows.length === 0) {
      return res.status(403).json({ error: 'no_active_license' });
    }

    // Verify file exists on disk
    if (!release.file_path || !fs.existsSync(release.file_path)) {
      return res.status(503).json({ error: 'file_not_available', message: 'Dosya sunucuda bulunamadı.' });
    }

    // Log download start
    const logId = `dl-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
    pgPool.query(
      `INSERT INTO update_download_logs (id, release_id, device_id, company_id, status)
       VALUES ($1, $2, $3, $4, 'started')`,
      [logId, releaseId, deviceId || null, user.company_id]
    ).catch(() => {});

    const ext = path.extname(release.file_path);
    const filename = `serenut-${release.version_code}-${release.platform}${ext}`;

    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('X-File-SHA256', release.sha256_hash);
    res.setHeader('X-Release-Id', releaseId);
    res.setHeader('X-Download-Log-Id', logId);

    if (release.file_size_bytes) {
      res.setHeader('Content-Length', release.file_size_bytes);
    }

    const stream = fs.createReadStream(release.file_path);
    stream.pipe(res);

    stream.on('end', () => {
      // Mark download as completed
      pgPool.query(
        "UPDATE update_download_logs SET status = 'completed', completed_at = NOW() WHERE id = $1",
        [logId]
      ).catch(() => {});
    });

    stream.on('error', (err) => {
      console.error('File stream error:', err);
      pgPool.query(
        "UPDATE update_download_logs SET status = 'failed', error_message = $1 WHERE id = $2",
        [err.message, logId]
      ).catch(() => {});
    });
  } catch (err) {
    console.error('Download error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 3. REPORT DEVICE VERSION (Called on app startup) ────────────────────────
router.post('/report-version', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { device_id, platform, current_version, channel } = req.body;

  if (!device_id || !platform || !current_version) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  try {
    await pgPool.query(`
      INSERT INTO device_app_versions (device_id, company_id, platform, current_version, channel, last_reported_at)
      VALUES ($1, $2, $3, $4, $5, NOW())
      ON CONFLICT (device_id) DO UPDATE SET
        current_version = EXCLUDED.current_version,
        channel = EXCLUDED.channel,
        last_reported_at = NOW()
    `, [device_id, user.company_id, platform, current_version, channel || 'stable']);

    return res.json({ success: true });
  } catch (err) {
    console.error('Report version error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 4. CONFIRM DOWNLOAD SUCCESS (Verification callback from device) ──────────
router.post('/confirm-download', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const { log_id, verified } = req.body;
  if (!log_id) {
    return res.status(400).json({ error: 'missing_log_id' });
  }

  try {
    const newStatus = verified ? 'verified' : 'verification_failed';
    await pgPool.query(
      'UPDATE update_download_logs SET status = $1 WHERE id = $2',
      [newStatus, log_id]
    );
    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 5. UPLOAD NEW RELEASE (Sysadmin Only) ───────────────────────────────────
router.post(
  '/upload',
  authenticateUser,
  requireRole('sysadmin'),
  upload.single('file'),
  async (req: AuthenticatedRequest, res: Response) => {
    const file = (req as any).file;
    if (!file) {
      return res.status(400).json({ error: 'no_file', message: 'Dosya yüklenmedi.' });
    }

    const {
      version_code, platform, channel, min_required_version,
      release_notes, is_mandatory, client_sha256
    } = req.body;

    if (!version_code || !platform) {
      fs.unlinkSync(file.path);
      return res.status(400).json({ error: 'missing_fields', message: 'version_code ve platform zorunludur.' });
    }

    try {
      // Server-side SHA-256 computation
      const serverSha256 = await computeFileSha256(file.path);

      // Verify against client-provided hash if given
      if (client_sha256 && client_sha256 !== serverSha256) {
        fs.unlinkSync(file.path);
        return res.status(400).json({
          error: 'checksum_mismatch',
          message: 'SHA-256 doğrulaması başarısız. Dosya bütünlüğü sağlanamadı.',
          expected: client_sha256,
          computed: serverSha256
        });
      }

      const releaseId = `rel-${Date.now()}`;
      const fileSizeBytes = file.size;

      await runBypassingRLS(`
        INSERT INTO app_versions (
          id, version_code, platform, channel, download_url, file_path,
          sha256_hash, file_size_bytes, is_mandatory, min_required_version,
          release_notes, status, rollout_percentage, published_by
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'active', 100, $12)
      `, [
        releaseId,
        version_code,
        platform,
        channel || 'stable',
        `/api/v1/releases/download/${releaseId}`,
        file.path,
        serverSha256,
        fileSizeBytes,
        is_mandatory === 'true' || is_mandatory === true,
        min_required_version || null,
        release_notes || null,
        req.user!.id
      ]);

      return res.status(201).json({
        success: true,
        release_id: releaseId,
        sha256_hash: serverSha256,
        file_size_bytes: fileSizeBytes,
        version_code,
        platform,
        channel: channel || 'stable',
      });
    } catch (err: any) {
      // Clean up uploaded file on DB error
      if (file.path && fs.existsSync(file.path)) {
        fs.unlinkSync(file.path);
      }
      if (err.message?.includes('unique') || err.message?.includes('idx_app_versions')) {
        return res.status(409).json({ error: 'duplicate_version', message: 'Bu sürüm kodu bu kanal için zaten mevcut.' });
      }
      console.error('Upload error:', err);
      return res.status(500).json({ error: 'server_error' });
    }
  }
);

// ── 6. LIST ALL RELEASES (Admin) ─────────────────────────────────────────────
router.get('/list', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  try {
    const list = await runBypassingRLS(`
      SELECT av.*,
             u.name as published_by_name,
             (SELECT COUNT(*) FROM update_download_logs dl WHERE dl.release_id = av.id) as total_downloads,
             (SELECT COUNT(*) FROM update_download_logs dl WHERE dl.release_id = av.id AND dl.status = 'verified') as verified_installs
      FROM app_versions av
      LEFT JOIN users u ON av.published_by = u.id
      ORDER BY av.created_at DESC
    `);
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 7. UPDATE RELEASE (rollout %, status change) ─────────────────────────────
router.put('/:id', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { rollout_percentage, status, is_mandatory, min_required_version } = req.body;

  try {
    await runBypassingRLS(`
      UPDATE app_versions
      SET rollout_percentage = COALESCE($1, rollout_percentage),
          status = COALESCE($2, status),
          is_mandatory = COALESCE($3, is_mandatory),
          min_required_version = COALESCE($4, min_required_version),
          updated_at = NOW()
      WHERE id = $5
    `, [
      rollout_percentage !== undefined ? parseInt(rollout_percentage, 10) : null,
      status || null,
      is_mandatory !== undefined ? is_mandatory : null,
      min_required_version || null,
      req.params.id
    ]);

    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 8. YANK RELEASE (Emergency Withdrawal) ──────────────────────────────────
router.post('/:id/yank', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { reason } = req.body;

  try {
    const existing = await runBypassingRLS('SELECT * FROM app_versions WHERE id = $1', [req.params.id]);
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: 'release_not_found' });
    }

    await runBypassingRLS(
      "UPDATE app_versions SET status = 'yanked', yanked_reason = $1, updated_at = NOW() WHERE id = $2",
      [reason || 'Admin tarafından geri alındı.', req.params.id]
    );

    return res.json({ success: true, message: `Sürüm ${existing.rows[0].version_code} geri alındı.` });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 9. RELEASE STATISTICS ────────────────────────────────────────────────────
router.get('/:id/stats', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  try {
    const release = await runBypassingRLS('SELECT * FROM app_versions WHERE id = $1', [req.params.id]);
    if (release.rows.length === 0) {
      return res.status(404).json({ error: 'release_not_found' });
    }

    const downloadStats = await runBypassingRLS(`
      SELECT 
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE status = 'completed') as completed,
        COUNT(*) FILTER (WHERE status = 'verified') as verified,
        COUNT(*) FILTER (WHERE status = 'failed') as failed,
        COUNT(*) FILTER (WHERE status = 'verification_failed') as verification_failed
      FROM update_download_logs
      WHERE release_id = $1
    `, [req.params.id]);

    const deviceStats = await runBypassingRLS(`
      SELECT dl.device_id, d.name as device_name, c.name as company_name, dl.status, dl.started_at, dl.completed_at
      FROM update_download_logs dl
      LEFT JOIN devices d ON dl.device_id = d.id
      LEFT JOIN companies c ON dl.company_id = c.id
      WHERE dl.release_id = $1
      ORDER BY dl.started_at DESC
      LIMIT 50
    `, [req.params.id]);

    return res.json({
      release: release.rows[0],
      summary: downloadStats.rows[0],
      downloads: deviceStats.rows
    });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 10. ADD TARGETING RULE ────────────────────────────────────────────────────
router.post('/:id/targets', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { target_type, target_value } = req.body;

  if (!target_type || !target_value) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  const id = `tgt-${Date.now()}`;
  try {
    await runBypassingRLS(
      'INSERT INTO update_targets (id, release_id, target_type, target_value) VALUES ($1, $2, $3, $4)',
      [id, req.params.id, target_type, target_value]
    );
    return res.status(201).json({ success: true, target_id: id });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 11. DEVICE VERSION MONITOR (Admin) ────────────────────────────────────────
router.get('/monitor', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  try {
    // Get latest stable version per platform
    const latestVersions = await runBypassingRLS(`
      SELECT platform, version_code FROM app_versions
      WHERE status = 'active' AND channel = 'stable'
      ORDER BY created_at DESC
    `);

    const latestMap: Record<string, string> = {};
    for (const row of latestVersions.rows) {
      if (!latestMap[row.platform]) {
        latestMap[row.platform] = row.version_code;
      }
    }

    // Count devices per version status
    const deviceVersions = await runBypassingRLS(`
      SELECT dav.platform, dav.current_version, dav.channel,
             COUNT(*) as device_count,
             c.name as company_name
      FROM device_app_versions dav
      JOIN companies c ON dav.company_id = c.id
      GROUP BY dav.platform, dav.current_version, dav.channel, c.name
      ORDER BY dav.platform, device_count DESC
    `);

    const totalDevices = deviceVersions.rows.reduce((sum: number, r: any) => sum + parseInt(r.device_count, 10), 0);
    let upToDate = 0;
    let outdated = 0;

    for (const row of deviceVersions.rows) {
      const latest = latestMap[row.platform];
      const count = parseInt(row.device_count, 10);
      if (latest && row.current_version === latest) {
        upToDate += count;
      } else {
        outdated += count;
      }
    }

    const failedDownloads = await runBypassingRLS(
      "SELECT COUNT(*) FROM update_download_logs WHERE status = 'failed' AND started_at >= NOW() - INTERVAL '7 days'"
    );
    const totalDownloads = await runBypassingRLS(
      "SELECT COUNT(*) FROM update_download_logs WHERE started_at >= NOW() - INTERVAL '7 days'"
    );

    const failCount = parseInt(failedDownloads.rows[0].count, 10);
    const totalCount = parseInt(totalDownloads.rows[0].count, 10);
    const failureRate = totalCount > 0 ? ((failCount / totalCount) * 100).toFixed(1) : '0.0';

    return res.json({
      summary: {
        totalDevices,
        upToDate,
        outdated,
        unknown: Math.max(0, totalDevices - upToDate - outdated),
        failureRate: parseFloat(failureRate),
      },
      latestVersions: latestMap,
      deviceBreakdown: deviceVersions.rows
    });
  } catch (err) {
    console.error('Monitor error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
