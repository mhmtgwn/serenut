import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';

const router = Router();
const catalogDir = process.env.READY_CATALOG_DIR || path.join(process.cwd(), 'catalogs');
const catalogFileName = process.env.READY_CATALOG_FILE || 'Katalog.zip';

function resolveCatalogPath(): string {
  return path.join(catalogDir, path.basename(catalogFileName));
}

router.get('/ready', async (_req, res) => {
  const filePath = resolveCatalogPath();
  try {
    const stat = await fs.promises.stat(filePath);
    if (!stat.isFile()) throw new Error('not_a_file');
    const checksumPath = `${filePath}.sha256`;
    const checksum = await fs.promises
      .readFile(checksumPath, 'utf8')
      .then((value) => value.trim().split(/\s+/)[0])
      .catch(() => null);
    return res.json({
      available: true,
      name: 'Serenut Hazır Ürün Kataloğu',
      fileName: path.basename(filePath),
      sizeBytes: stat.size,
      productCount: 15173,
      sha256: checksum,
      updatedAt: stat.mtime.toISOString(),
      downloadUrl: '/api/v1/catalogs/ready/download',
    });
  } catch {
    return res.status(503).json({
      available: false,
      error: 'catalog_unavailable',
      message: 'Hazır katalog şu anda sunucuda bulunamıyor.',
    });
  }
});

router.get('/ready/download', async (_req, res) => {
  const filePath = resolveCatalogPath();
  try {
    const stat = await fs.promises.stat(filePath);
    if (!stat.isFile()) throw new Error('not_a_file');
    res.setHeader('Content-Type', 'application/zip');
    res.setHeader('Content-Length', String(stat.size));
    res.setHeader('Content-Disposition', 'attachment; filename="Serenut-Hazir-Katalog.zip"');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    return res.sendFile(filePath);
  } catch {
    return res.status(503).json({
      error: 'catalog_unavailable',
      message: 'Hazır katalog şu anda indirilemiyor.',
    });
  }
});

export default router;
