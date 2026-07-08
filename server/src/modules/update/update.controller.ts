import { Router, Request, Response } from 'express';
import { pgPool } from '../../config/database';
import fs from 'fs';
import path from 'path';

const router = Router();

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
    
    const release = result.rows[0];
    const resolvedPath = path.isAbsolute(release.file_path) 
      ? release.file_path 
      : path.resolve(process.cwd(), release.file_path);

    if (result.rows.length === 0 || !release.file_path || !fs.existsSync(resolvedPath)) {
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

router.get('/check', async (req: Request, res: Response) => {
  const platform = req.query.platform as string;
  const current_version = req.query.current_version as string;

  if (!platform || !current_version) {
    return res.status(400).json({ error: 'missing_parameters', message: 'Platform ve current_version parametreleri zorunludur.' });
  }

  try {
    const query = `
      SELECT version_code, platform, download_url, sha256_hash, is_mandatory, release_notes
      FROM app_versions
      WHERE platform = $1
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
        releaseNotes: 'Uygulama güncel.'
      });
    }

    const latest = result.rows[0];

    // Simple comparison logic: if latest version code is different, suggest update
    const hasUpdate = latest.version_code !== current_version;

    return res.json({
      latestVersion: latest.version_code,
      minRequiredVersion: latest.is_mandatory ? latest.version_code : current_version,
      isForceUpdate: latest.is_mandatory && hasUpdate,
      downloadUrl: hasUpdate ? latest.download_url : '',
      sha256_hash: hasUpdate ? latest.sha256_hash : '',
      releaseNotes: latest.release_notes || ''
    });
  } catch (err) {
    console.error('Update check error:', err);
    return res.status(500).json({ error: 'server_error', message: 'Güncelleme kontrolü esnasında hata oluştu.' });
  }
});

export default router;
