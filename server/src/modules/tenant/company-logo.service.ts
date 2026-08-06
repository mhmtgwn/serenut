import crypto from 'crypto';
import fs from 'fs/promises';
import path from 'path';
import sharp from 'sharp';

const LOGO_ROOT = process.env.COMPANY_LOGOS_DIR ||
  path.join(process.cwd(), 'public', 'uploads', 'company-logos');

export interface StoredCompanyLogo {
  hash: string;
  originalPath: string;
  displayPath: string;
  printPath: string;
}

export function publicLogoUrl(relativePath: string, fallbackBase = ''): string {
  const base = (process.env.PUBLIC_BASE_URL || fallbackBase).replace(/\/$/, '');
  return base ? `${base}${relativePath}` : relativePath;
}

export async function storeCompanyLogo(
  companyId: string,
  input: Buffer,
): Promise<StoredCompanyLogo> {
  const image = sharp(input, { failOn: 'error', limitInputPixels: 25_000_000 });
  const metadata = await image.metadata();
  if (!metadata.width || !metadata.height || !metadata.format) {
    throw new Error('invalid_image');
  }
  if (!['jpeg', 'png', 'webp'].includes(metadata.format)) {
    throw new Error('unsupported_image_format');
  }

  const hash = crypto.createHash('sha256').update(input).digest('hex');
  const safeCompanyId = companyId.replace(/[^a-zA-Z0-9_-]/g, '');
  if (!safeCompanyId) throw new Error('invalid_company_id');
  const directory = path.join(LOGO_ROOT, safeCompanyId, hash);
  await fs.mkdir(directory, { recursive: true });

  const extension = metadata.format === 'jpeg' ? 'jpg' : metadata.format;
  const originalFile = `original.${extension}`;
  await fs.writeFile(path.join(directory, originalFile), input, { flag: 'wx' })
    .catch((error: NodeJS.ErrnoException) => {
      if (error.code !== 'EEXIST') throw error;
    });

  await sharp(input)
    .rotate()
    .resize({ width: 512, height: 512, fit: 'inside', withoutEnlargement: true })
    .webp({ quality: 82, effort: 4 })
    .toFile(path.join(directory, 'display.webp'));

  await sharp(input)
    .rotate()
    .flatten({ background: '#ffffff' })
    .resize({ width: 576, height: 192, fit: 'inside', withoutEnlargement: true })
    .grayscale()
    .normalize()
    .threshold(160)
    .png({ compressionLevel: 9, palette: true })
    .toFile(path.join(directory, 'print.png'));

  const basePath = `/uploads/company-logos/${safeCompanyId}/${hash}`;
  return {
    hash,
    originalPath: `${basePath}/${originalFile}`,
    displayPath: `${basePath}/display.webp`,
    printPath: `${basePath}/print.png`,
  };
}

export function decodeDataImage(value: string): Buffer | null {
  const match = /^data:image\/(png|jpeg|jpg|webp);base64,([a-zA-Z0-9+/=\r\n]+)$/.exec(value);
  if (!match) return null;
  return Buffer.from(match[2], 'base64');
}
