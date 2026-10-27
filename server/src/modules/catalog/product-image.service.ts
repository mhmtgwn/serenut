import crypto from 'crypto';
import fs from 'fs/promises';
import path from 'path';

export const PRODUCT_IMAGES_DIR =
  process.env.PRODUCT_IMAGES_DIR || path.join(process.cwd(), 'uploads', 'product-images');

export const IMAGE_ID_REGEX = /^[a-f0-9]{64}\.(?:jpg|jpeg|png|webp)$/;

export function detectExtension(buffer: Buffer): 'jpg' | 'png' | 'webp' | null {
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return 'jpg';
  }
  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47 &&
    buffer[4] === 0x0d &&
    buffer[5] === 0x0a &&
    buffer[6] === 0x1a &&
    buffer[7] === 0x0a
  ) {
    return 'png';
  }
  if (
    buffer.length >= 12 &&
    buffer.subarray(0, 4).toString('ascii') === 'RIFF' &&
    buffer.subarray(8, 12).toString('ascii') === 'WEBP'
  ) {
    return 'webp';
  }
  return null;
}

export async function storeProductImage(
  buffer: Buffer,
  expectedImageId?: string,
): Promise<{ imageId: string; url: string }> {
  if (!buffer || buffer.length === 0) {
    throw new Error('empty_image_payload');
  }
  if (buffer.length > 10 * 1024 * 1024) {
    throw new Error('payload_too_large');
  }

  const hash = crypto.createHash('sha256').update(buffer).digest('hex');
  const detectedExt = detectExtension(buffer);

  let ext = detectedExt;
  if (expectedImageId) {
    const cleanExpected = expectedImageId.trim().toLowerCase();
    if (!IMAGE_ID_REGEX.test(cleanExpected)) {
      throw new Error('invalid_image_id_format');
    }
    const expectedHash = cleanExpected.substring(0, 64);
    if (expectedHash !== hash) {
      throw new Error('checksum_mismatch');
    }
    ext = cleanExpected.split('.')[1] as 'jpg' | 'png' | 'webp';
  }

  if (!ext) {
    ext = 'jpg';
  }

  const imageId = `${hash}.${ext}`;
  await fs.mkdir(PRODUCT_IMAGES_DIR, { recursive: true });

  const finalPath = path.join(PRODUCT_IMAGES_DIR, imageId);
  try {
    await fs.access(finalPath);
    // Already exists — content-addressed files are immutable
    return { imageId, url: `/uploads/product-images/${imageId}` };
  } catch {
    // File does not exist yet; write atomically via temp file
  }

  const tempPath = path.join(PRODUCT_IMAGES_DIR, `${imageId}.part-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`);
  await fs.writeFile(tempPath, buffer);
  await fs.rename(tempPath, finalPath);

  return { imageId, url: `/uploads/product-images/${imageId}` };
}

export function resolveProductImagePath(imageId: string): string | null {
  const clean = imageId.trim().toLowerCase();
  if (!IMAGE_ID_REGEX.test(clean)) {
    return null;
  }
  return path.join(PRODUCT_IMAGES_DIR, clean);
}
