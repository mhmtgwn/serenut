import { Router, Request, Response } from 'express';
import express from 'express';
import fs from 'fs/promises';
import path from 'path';
import {
  storeProductImage,
  resolveProductImagePath,
} from './product-image.service';

const router = Router();

// Middleware to parse raw binary body for image uploads
const rawBodyParser = express.raw({
  type: ['image/*', 'application/octet-stream', 'application/binary'],
  limit: '10mb',
});

// JSON body parser for base64 uploads if passed as JSON
const jsonBodyParser = express.json({ limit: '12mb' });

async function handleImageUpload(req: Request, res: Response) {
  try {
    let buffer: Buffer | null = null;
    const expectedImageId =
      (req.header('x-image-id') as string) ||
      (req.query.image_id as string) ||
      (req.body && typeof req.body === 'object' && req.body.image_id);

    if (Buffer.isBuffer(req.body)) {
      buffer = req.body;
    } else if (req.body && typeof req.body === 'object' && req.body.data) {
      // Base64 payload
      const base64Data = String(req.body.data).replace(/^data:image\/\w+;base64,/, '');
      buffer = Buffer.from(base64Data, 'base64');
    }

    if (!buffer || buffer.length === 0) {
      return res.status(400).json({
        error: 'empty_image_payload',
        message: 'Görsel içeriği boş olamaz.',
      });
    }

    const result = await storeProductImage(buffer, expectedImageId);
    return res.status(201).json({
      success: true,
      imageId: result.imageId,
      url: result.url,
    });
  } catch (error: any) {
    if (error.message === 'checksum_mismatch') {
      return res.status(400).json({
        error: 'checksum_mismatch',
        message: 'Gönderilen görselin SHA-256 sağlama değeri beklenen değer ile uyuşmuyor.',
      });
    }
    if (error.message === 'payload_too_large') {
      return res.status(413).json({
        error: 'payload_too_large',
        message: 'Görsel boyutu izin verilen sınırı aşıyor (maks. 10MB).',
      });
    }
    if (error.message === 'invalid_image_id_format') {
      return res.status(400).json({
        error: 'invalid_image_id_format',
        message: 'Geçersiz görsel ID formatı.',
      });
    }
    return res.status(500).json({
      error: 'image_store_failed',
      message: 'Görsel kaydedilirken bir hata oluştu.',
    });
  }
}

// Support both POST / and POST /image
router.post('/', rawBodyParser, jsonBodyParser, handleImageUpload);
router.post('/image', rawBodyParser, jsonBodyParser, handleImageUpload);

async function handleGetImage(req: Request, res: Response) {
  const imageId = (req.params.imageId || '').trim().toLowerCase();
  const filePath = resolveProductImagePath(imageId);

  if (!filePath) {
    return res.status(400).json({
      error: 'invalid_image_id',
      message: 'Geçersiz görsel ID formatı.',
    });
  }

  try {
    const stat = await fs.stat(filePath);
    if (!stat.isFile()) {
      return res.status(404).json({
        error: 'not_found',
        message: 'Görsel bulunamadı.',
      });
    }

    const ext = path.extname(filePath).toLowerCase().replace('.', '');
    const mimeSubtype = ext === 'jpg' ? 'jpeg' : ext;
    res.setHeader('Content-Type', `image/${mimeSubtype}`);
    res.setHeader('Content-Length', String(stat.size));
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    return res.sendFile(filePath);
  } catch {
    return res.status(404).json({
      error: 'not_found',
      message: 'Görsel bulunamadı.',
    });
  }
}

// Support both GET /:imageId and GET /image/:imageId
router.get('/:imageId', handleGetImage);
router.get('/image/:imageId', handleGetImage);

export default router;
