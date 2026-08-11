const assert = require('assert');
const crypto = require('crypto');
const http = require('http');
const { verifyPlatform } = require('./verify_published_release');

async function main() {
  const version = '9.8.7+654';
  const platform = 'android';
  const artifact = Buffer.from('immutable-release-artifact');
  const hash = crypto.createHash('sha256').update(artifact).digest('hex');
  const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
  });
  const signature = crypto.sign('RSA-SHA256', Buffer.from(hash), privateKey).toString('base64');
  let corruptDownload = false;
  let baseUrl;
  const server = http.createServer((req, res) => {
    if (req.url.startsWith('/api/v1/updates/check')) {
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({
        latestVersion: version,
        downloadUrl: `${baseUrl}/api/v1/updates/download/${platform}/version/${encodeURIComponent(version)}`,
        sha256_hash: hash,
        signature,
        file_size_bytes: artifact.length,
      }));
    }
    if (req.url.startsWith(`/api/v1/updates/download/${platform}/version/`)) {
      return res.end(corruptDownload ? Buffer.from('corrupt') : artifact);
    }
    res.statusCode = 404;
    res.end();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;

  try {
    await verifyPlatform(baseUrl, version, platform, [publicKey]);
    corruptDownload = true;
    await assert.rejects(
      () => verifyPlatform(baseUrl, version, platform, [publicKey]),
      /published bytes mismatch/,
    );
    console.log('Published release verifier contract: PASS');
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
