import { Router, Request, Response } from 'express';
import { pgPool } from '../../config/database';
import fs from 'fs';
import path from 'path';

const router = Router();

function parseVersionString(v: string | null | undefined) {
  if (!v) return { major: 0, minor: 0, patch: 0, build: 0 };
  // URL query params convert '+' into space (' '). Normalize space back to '+' before build number.
  const normalized = v.trim().replace(/\s+(\d+)/, '+$1');
  const [verPart, buildPart] = normalized.split('+');
  const nums = (verPart || '').split('.').map(x => Number.parseInt(x, 10) || 0);
  return {
    major: nums[0] || 0,
    minor: nums[1] || 0,
    patch: nums[2] || 0,
    build: Number.parseInt(buildPart || '0', 10) || 0
  };
}

function compareVersions(aStr: string, bStr: string): number {
  const a = parseVersionString(aStr);
  const b = parseVersionString(bStr);

  if (a.major !== b.major) return a.major - b.major;
  if (a.minor !== b.minor) return a.minor - b.minor;
  if (a.patch !== b.patch) return a.patch - b.patch;
  return a.build - b.build;
}

function resolveReleaseFilePath(filePath: string | null): string | null {
  if (!filePath) return null;
  if (fs.existsSync(filePath)) return filePath;
  const baseName = path.basename(filePath);
  const candidates = [
    filePath,
    path.resolve('/var/www/serenut-api/releases', baseName),
    path.resolve('/var/www/serenut/server/releases', baseName),
    path.resolve(process.cwd(), 'releases', baseName),
    path.resolve(process.cwd(), filePath),
    path.resolve(process.cwd(), 'server', filePath),
    path.resolve(process.cwd(), 'public/website/downloads', baseName),
    path.resolve(process.cwd(), 'server/public/website/downloads', baseName)
  ];
  for (const candidate of candidates) {
    if (candidate && fs.existsSync(candidate)) return candidate;
  }
  return null;
}

type DownloadRelease = {
  file_path: string;
  version_code: string;
  sha256_hash: string | null;
};

async function sendReleaseFile(
  req: Request,
  res: Response,
  platform: string,
  release: DownloadRelease,
  immutable: boolean,
) {
  const resolvedPath = resolveReleaseFilePath(release.file_path);
  if (!resolvedPath) {
    return res.status(404).json({ error: 'release_file_not_found' });
  }

  const fileStat = await fs.promises.stat(resolvedPath);
  const fileSize = fileStat.size;
  const rangeHeader = req.headers.range;
  let start = 0;
  let end = fileSize - 1;
  let statusCode = 200;

  res.setHeader('Accept-Ranges', 'bytes');
  res.setHeader(
    'Cache-Control',
    immutable ? 'public, max-age=31536000, immutable' : 'no-store',
  );
  if (release.sha256_hash) {
    res.setHeader('ETag', `"sha256-${release.sha256_hash}"`);
    res.setHeader('X-File-SHA256', release.sha256_hash);
  }

  if (rangeHeader) {
    const match = /^bytes=(\d+)-(\d*)$/.exec(rangeHeader.trim());
    if (!match) {
      res.setHeader('Content-Range', `bytes */${fileSize}`);
      return res.status(416).end();
    }
    start = Number.parseInt(match[1], 10);
    end = match[2] ? Number.parseInt(match[2], 10) : fileSize - 1;
    if (start >= fileSize || end < start) {
      res.setHeader('Content-Range', `bytes */${fileSize}`);
      return res.status(416).end();
    }
    end = Math.min(end, fileSize - 1);
    statusCode = 206;
    res.setHeader('Content-Range', `bytes ${start}-${end}/${fileSize}`);
  }

  res.status(statusCode);
  res.setHeader('Content-Length', end - start + 1);
  res.setHeader(
    'Content-Type',
    platform === 'windows'
      ? 'application/vnd.microsoft.portable-executable'
      : 'application/vnd.android.package-archive',
  );
  const ext = path.extname(resolvedPath);
  const cleanVersion = release.version_code.split('+')[0];
  const filename = platform === 'windows'
    ? `SerenutOS-Setup-v${cleanVersion}${ext}`
    : `SerenutOS-v${cleanVersion}${ext}`;
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  if (req.method === 'HEAD') return res.end();

  const stream = fs.createReadStream(resolvedPath, { start, end });
  stream.on('error', (streamError) => {
    console.error('Public download stream error:', streamError);
    if (!res.headersSent) res.status(500).end();
    else res.destroy(streamError);
  });
  stream.pipe(res);
}

router.get('/download/:platform/version/:version', async (req: Request, res: Response) => {
  const { platform, version } = req.params;
  if (!['android', 'windows'].includes(platform)) {
    return res.status(400).json({ error: 'invalid_platform' });
  }
  try {
    const result = await pgPool.query<DownloadRelease>(`
      SELECT file_path, version_code, sha256_hash
      FROM app_versions
      WHERE platform = $1 AND version_code = $2
        AND status = 'active' AND channel = 'stable'
      LIMIT 1
    `, [platform, version]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'release_not_found' });
    }
    return sendReleaseFile(req, res, platform, result.rows[0], true);
  } catch (err) {
    console.error('Versioned public download error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.get('/download/:platform/latest', async (req: Request, res: Response) => {
  const { platform } = req.params;
  res.setHeader('Cache-Control', 'no-store');
  
  if (platform !== 'android' && platform !== 'windows') {
    return res.status(400).json({ error: 'invalid_platform', message: 'Geçersiz platform.' });
  }

  try {
    const query = `
      SELECT file_path, version_code, sha256_hash
      FROM app_versions
      WHERE platform = $1 AND status = 'active' AND channel = 'stable'
      ORDER BY created_at DESC
      LIMIT 1
    `;
    const result = await pgPool.query(query, [platform]);
    let resolvedPath: string | null = null;
    let versionCode = '1.1.9';

    if (result.rows.length > 0 && result.rows[0].file_path) {
      const release = result.rows[0];
      versionCode = release.version_code || versionCode;
      resolvedPath = resolveReleaseFilePath(release.file_path);
      if (resolvedPath) {
        return sendReleaseFile(req, res, platform, release, false);
      }
    }

    // Fallback: check static public downloads folder if DB query returns empty or file is missing on server disk
    if (!resolvedPath) {
      const staticFileName = platform === 'windows' ? 'SerenutOSSetup.exe' : 'serenut.apk';
      const staticCandidates = [
        path.resolve(process.cwd(), 'public/website/downloads', staticFileName),
        path.resolve(process.cwd(), 'server/public/website/downloads', staticFileName),
        `/var/www/serenut-api/public/website/downloads/${staticFileName}`,
        `/var/www/serenut/server/public/website/downloads/${staticFileName}`,
        `/var/www/serenut/public/website/downloads/${staticFileName}`,
        path.resolve(__dirname, '../../../public/website/downloads', staticFileName),
        path.resolve(__dirname, '../../public/website/downloads', staticFileName)
      ];
      for (const candidate of staticCandidates) {
        if (fs.existsSync(candidate)) {
          resolvedPath = candidate;
          break;
        }
      }
    }

    if (!resolvedPath) {
      return res.status(404).send(`
        <div style="font-family: sans-serif; text-align: center; margin-top: 100px;">
          <h2 style="color: #ef4444;">Dosya Bulunamadı</h2>
          <p>${platform} için henüz yüklenmiş bir release dosyası bulunmamaktadır.</p>
          <a href="/" style="color: #10b981; text-decoration: none; font-weight: bold;">Ana Sayfaya Dön</a>
        </div>
      `);
    }

    const fileStat = await fs.promises.stat(resolvedPath);
    const fileSize = fileStat.size;
    const rangeHeader = req.headers.range;
    let start = 0;
    let end = fileSize - 1;
    let statusCode = 200;

    res.setHeader('Accept-Ranges', 'bytes');

    if (rangeHeader) {
      const match = /^bytes=(\d+)-(\d*)$/.exec(rangeHeader.trim());
      if (!match) {
        res.setHeader('Content-Range', `bytes */${fileSize}`);
        return res.status(416).end();
      }

      start = Number.parseInt(match[1], 10);
      end = match[2] ? Number.parseInt(match[2], 10) : fileSize - 1;
      if (start >= fileSize || end < start) {
        res.setHeader('Content-Range', `bytes */${fileSize}`);
        return res.status(416).end();
      }
      end = Math.min(end, fileSize - 1);
      statusCode = 206;
      res.setHeader('Content-Range', `bytes ${start}-${end}/${fileSize}`);
    }

    const contentLength = end - start + 1;
    res.status(statusCode);
    res.setHeader('Content-Length', contentLength);
    res.setHeader(
      'Content-Type',
      platform === 'windows'
        ? 'application/vnd.microsoft.portable-executable'
        : 'application/vnd.android.package-archive'
    );

    const ext = path.extname(resolvedPath);
    const cleanVersion = (versionCode || '').split('+')[0];
    const filename = platform === 'windows'
      ? `SerenutOS-Setup-v${cleanVersion}${ext}`
      : `SerenutOS-v${cleanVersion}${ext}`;

    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    if (req.method === 'HEAD') {
      return res.end();
    }

    const stream = fs.createReadStream(resolvedPath, { start, end });
    stream.on('error', (streamError) => {
      console.error('Public download stream error:', streamError);
      if (!res.headersSent) {
        res.status(500).end();
      } else {
        res.destroy(streamError);
      }
    });
    stream.pipe(res);
  } catch (err) {
    console.error('Public download error:', err);
    return res.status(500).send('Sunucu hatası.');
  }
});

router.get('/latest-metadata', async (req: Request, res: Response) => {
  res.setHeader('Cache-Control', 'no-store');
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
  res.setHeader('Cache-Control', 'no-store');
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
      minRequiredVersion: (latest.is_mandatory && hasUpdate) ? latest.version_code : current_version,
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
