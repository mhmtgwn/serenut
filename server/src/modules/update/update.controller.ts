import { Router, Request, Response } from 'express';
import { pgPool } from '../../config/database';
import fs from 'fs';
import path from 'path';

const router = Router();

function compareVersions(a: string, b: string): number {
  const parts = (value: string) => value.replace(/\+.*/, '').split('.').map(x => Number.parseInt(x, 10) || 0);
  const left = parts(a); const right = parts(b);
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const diff = (left[i] || 0) - (right[i] || 0);
    if (diff !== 0) return diff;
  }
  return (Number.parseInt(a.split('+')[1] || '0', 10) || 0) - (Number.parseInt(b.split('+')[1] || '0', 10) || 0);
}

function resolveReleaseFilePath(filePath: string | null): string | null {
  if (!filePath) return null;
  if (fs.existsSync(filePath)) return filePath;
  const p1 = path.resolve(process.cwd(), filePath);
  if (fs.existsSync(p1)) return p1;
  const p2 = path.resolve(process.cwd(), 'server', filePath);
  if (fs.existsSync(p2)) return p2;
  const baseName = path.basename(filePath);
  const p3 = path.resolve(process.cwd(), 'public/website/downloads', baseName);
  if (fs.existsSync(p3)) return p3;
  const p4 = path.resolve(process.cwd(), 'server/public/website/downloads', baseName);
  if (fs.existsSync(p4)) return p4;
  return null;
}

router.get('/download/:platform/latest', async (req: Request, res: Response) => {
  const { platform } = req.params;
  
  if (platform !== 'android' && platform !== 'windows') {
    return res.status(400).json({ error: 'invalid_platform', message: 'Geçersiz platform.' });
  }

  try {
    const query = `
      SELECT file_path, version_code
      FROM app_versions
      WHERE platform = $1 AND status = 'active' AND channel = 'stable'
      ORDER BY created_at DESC
      LIMIT 1
    `;
    const result = await pgPool.query(query, [platform]);
    if (result.rows.length === 0 || !result.rows[0].file_path) {
      return res.status(404).send(`
        <div style="font-family: sans-serif; text-align: center; margin-top: 100px;">
          <h2 style="color: #ef4444;">Dosya Bulunamadı</h2>
          <p>${platform} için henüz yüklenmiş bir release dosyası bulunmamaktadır.</p>
          <a href="/" style="color: #10b981; text-decoration: none; font-weight: bold;">Ana Sayfaya Dön</a>
        </div>
      `);
    }

    const release = result.rows[0];
    const resolvedPath = resolveReleaseFilePath(release.file_path);

    if (!resolvedPath) {
      return res.status(404).send(`
        <div style="font-family: sans-serif; text-align: center; margin-top: 100px;">
          <h2 style="color: #ef4444;">Dosya Bulunamadı</h2>
          <p>${platform} için henüz yüklenmiş bir release dosyası bulunmamaktadır.</p>
          <a href="/" style="color: #10b981; text-decoration: none; font-weight: bold;">Ana Sayfaya Dön</a>
        </div>
      `);
    }

    const ext = path.extname(resolvedPath);
    const filename = `serenut-${release.version_code}-${platform}${ext}`;

    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    const stream = fs.createReadStream(resolvedPath);
    stream.pipe(res);
  } catch (err) {
    console.error('Public download error:', err);
    return res.status(500).send('Sunucu hatası.');
  }
});

router.get('/latest-metadata', async (req: Request, res: Response) => {
  try {
    const query = `
      (SELECT id, version_code, platform, sha256_hash, file_size_bytes, release_notes, created_at
       FROM app_versions
       WHERE platform = 'windows' AND status = 'active' AND channel = 'stable'
       ORDER BY created_at DESC LIMIT 1)
      UNION ALL
      (SELECT id, version_code, platform, sha256_hash, file_size_bytes, release_notes, created_at
       FROM app_versions
       WHERE platform = 'android' AND status = 'active' AND channel = 'stable'
       ORDER BY created_at DESC LIMIT 1)
    `;
    const result = await pgPool.query(query);
    return res.json(result.rows);
  } catch (err: any) {
    console.error('Latest metadata error:', err);
    return res.status(500).json({ error: 'server_error', message: err.message });
  }
});



router.get('/check', async (req: Request, res: Response) => {
  const platform = req.query.platform as string;
  const current_version = req.query.current_version as string;

  if (!platform || !current_version) {
    return res.status(400).json({ error: 'missing_parameters', message: 'Platform ve current_version parametreleri zorunludur.' });
  }

  try {
    const query = `
      SELECT version_code, platform, download_url, sha256_hash, signature, file_size_bytes, is_mandatory, release_notes
      FROM app_versions
      WHERE platform = $1 AND status = 'active' AND channel = 'stable'
      ORDER BY created_at DESC
      LIMIT 1
    `;
    const result = await pgPool.query(query, [platform]);
    
    if (result.rows.length === 0) {
      return res.json({
        latestVersion: current_version,
        minRequiredVersion: current_version,
        isForceUpdate: false,
        downloadUrl: '',
        sha256_hash: '',
        signature: null,
        file_size_bytes: null,
        releaseNotes: 'Uygulama güncel.'
      });
    }

    const latest = result.rows[0];

    // Simple comparison logic: if latest version code is different, suggest update
    const hasUpdate = compareVersions(current_version, latest.version_code) < 0;

    const host = req.get('host');
    const protocol = req.headers['x-forwarded-proto'] || req.protocol || 'https';
    let absoluteDownloadUrl = '';
    if (hasUpdate && latest.download_url) {
      absoluteDownloadUrl = latest.download_url.startsWith('http')
        ? latest.download_url
        : `${protocol}://${host}${latest.download_url}`;
    }

    return res.json({
      latestVersion: latest.version_code,
      minRequiredVersion: latest.is_mandatory ? latest.version_code : current_version,
      isForceUpdate: latest.is_mandatory && hasUpdate,
      downloadUrl: absoluteDownloadUrl,
      sha256_hash: hasUpdate ? latest.sha256_hash : '',
      signature: hasUpdate ? latest.signature : null,
      file_size_bytes: hasUpdate ? latest.file_size_bytes : null,
      releaseNotes: latest.release_notes || ''
    });
  } catch (err) {
    console.error('Update check error:', err);
    return res.status(500).json({ error: 'server_error', message: 'Güncelleme kontrolü esnasında hata oluştu.' });
  }
});

export default router;
