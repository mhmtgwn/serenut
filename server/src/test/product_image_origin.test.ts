import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {
  detectExtension,
  storeProductImage,
  resolveProductImagePath,
} from '../modules/catalog/product-image.service';

async function runTests() {
  console.log('🧪 Starting Product Image Cloud Origin Tests...');

  // 1. Extension Detection
  const jpegHeader = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
  assert.equal(detectExtension(jpegHeader), 'jpg');

  const pngHeader = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assert.equal(detectExtension(pngHeader), 'png');

  const webpHeader = Buffer.concat([
    Buffer.from('RIFF', 'ascii'),
    Buffer.alloc(4),
    Buffer.from('WEBP', 'ascii'),
  ]);
  assert.equal(detectExtension(webpHeader), 'webp');

  const textPayload = Buffer.from('not an image');
  assert.equal(detectExtension(textPayload), null);
  console.log('  ✓ Image format detection verified');

  // 2. Storage & Content Addressing
  const sampleData = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  ]);
  const expectedHash = crypto.createHash('sha256').update(sampleData).digest('hex');
  const expectedImageId = `${expectedHash}.png`;

  const result = await storeProductImage(sampleData);
  assert.equal(result.imageId, expectedImageId);
  assert.equal(result.url, `/uploads/product-images/${expectedImageId}`);

  const filePath = resolveProductImagePath(result.imageId);
  assert(filePath !== null, 'Resolved file path should not be null');
  assert(fs.existsSync(filePath), 'Stored file should exist on disk');

  // Verify content was correctly written
  const onDiskContent = fs.readFileSync(filePath);
  assert.deepEqual(onDiskContent, sampleData);
  console.log('  ✓ Image content-addressed storage verified');

  // 3. Expected image ID verification and checksum mismatch protection
  const invalidExpectedId = `${'0'.repeat(64)}.png`;
  await assert.rejects(
    async () => {
      await storeProductImage(sampleData, invalidExpectedId);
    },
    { message: 'checksum_mismatch' },
  );
  console.log('  ✓ Checksum mismatch protection verified');

  // 4. Server Route Mounting Contract
  const serverCode = fs.readFileSync(path.join(__dirname, '../server.ts'), 'utf8');
  assert.match(serverCode, /app\.use\('\/api\/v1\/products', productImageRouter\)/);
  assert.match(serverCode, /app\.use\('\/api\/v4\/products', productImageRouter\)/);
  assert.match(serverCode, /app\.use\('\/uploads\/product-images'/);
  console.log('  ✓ Server route contract verified');

  // Clean up test file
  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
  }

  console.log('✅ All Product Image Cloud Origin Tests PASSED!');
}

runTests().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
