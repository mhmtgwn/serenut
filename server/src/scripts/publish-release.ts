import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { pgPool } from '../config/database';
import {
  assertReleaseSigningContinuity,
  loadReleaseSigningKey,
  loadReleaseSigningPolicy,
  signReleaseHash,
  verifyReleaseHashSignature,
} from '../security/release-signing';

async function sha256(filePath: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(filePath);
    stream.on('data', chunk => hash.update(chunk));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', reject);
  });
}

function getReleaseSigningKey(): crypto.KeyObject {
  return loadReleaseSigningKey(
    [process.env.RELEASE_RSA_PRIVATE_KEY],
    [
    process.env.RELEASE_RSA_PRIVATE_KEY_FILE,
    '/run/secrets/serenut_release_private_key',
    path.join(process.cwd(), '.release-private.pem'),
    ],
  );
}

type ReleasePlatform = 'android' | 'windows';
type PreparedRelease = {
  platform: ReleasePlatform;
  versionCode: string;
  temporaryPath: string;
  finalPath: string;
  hash: string;
  signature: string;
  size: number;
  reusedExistingFile: boolean;
  isMandatory: boolean;
};

async function prepareRelease(
  platform: ReleasePlatform,
  versionCode: string,
  incomingPath: string,
  privateKey: crypto.KeyObject,
  isMandatory: boolean,
): Promise<PreparedRelease> {
  if (!fs.existsSync(incomingPath)) throw new Error(`Release file not found: ${incomingPath}`);
  const ext = path.extname(incomingPath).toLowerCase();
  const expectedExt = platform === 'android' ? '.apk' : '.exe';
  if (ext !== expectedExt) throw new Error(`Expected ${expectedExt}, received ${ext}`);

  const releaseDir = path.join(
    process.env.RELEASES_DIR || '/var/www/serenut-api/releases',
    platform,
    'stable',
  );
  fs.mkdirSync(releaseDir, { recursive: true });
  const finalPath = path.join(releaseDir, `SerenutOS-${versionCode}${ext}`);
  const temporaryPath = path.join(
    releaseDir,
    `.${path.basename(finalPath)}.${process.pid}.${Date.now()}.tmp`,
  );

  try {
    fs.copyFileSync(incomingPath, temporaryPath, fs.constants.COPYFILE_EXCL);
    const hash = await sha256(temporaryPath);
    const signature = signReleaseHash(hash, privateKey);
    if (!verifyReleaseHashSignature(hash, signature, crypto.createPublicKey(privateKey))) {
      throw new Error('Release signature self-check failed; publishing was aborted.');
    }
    const size = fs.statSync(temporaryPath).size;
    let reusedExistingFile = false;
    if (fs.existsSync(finalPath)) {
      const existingHash = await sha256(finalPath);
      if (existingHash !== hash) {
        console.warn(
          `[publish-release] Updating release ${platform} ${versionCode}: file content changed, overwriting existing file.`,
        );
        fs.unlinkSync(finalPath);
      } else {
        fs.unlinkSync(temporaryPath);
        reusedExistingFile = true;
      }
    }
    return {
      platform,
      versionCode,
      temporaryPath,
      finalPath,
      hash,
      signature,
      size,
      reusedExistingFile,
      isMandatory,
    };
  } catch (error) {
    if (fs.existsSync(temporaryPath)) fs.unlinkSync(temporaryPath);
    throw error;
  }
}

async function main() {
  const args = process.argv.slice(2);
  const privateKey = getReleaseSigningKey();
  const signingPolicy = loadReleaseSigningPolicy([
    process.env.RELEASE_SIGNING_POLICY_FILE,
    path.join(process.cwd(), 'release-signing-policy.json'),
  ]);
  assertReleaseSigningContinuity(privateKey, signingPolicy);
  if (args[0] === 'verify-policy') {
    console.log(
      `Release signer continuity policy: PASS (${signingPolicy.trustedSinceVersion})`,
    );
    return;
  }
  const inputs: Array<{
    platform: ReleasePlatform;
    versionCode: string;
    incomingPath: string;
    isMandatory: boolean;
  }> = args[0] === 'batch'
    ? [
        { platform: 'android', versionCode: args[1], incomingPath: args[2], isMandatory: args[4] === 'true' },
        { platform: 'windows', versionCode: args[1], incomingPath: args[3], isMandatory: args[4] === 'true' },
      ]
    : [{
        platform: args[0] as ReleasePlatform,
        versionCode: args[1],
        incomingPath: args[2],
        isMandatory: args[3] === 'true',
      }];
  if (inputs.some((input) =>
    !['android', 'windows'].includes(input.platform)
    || !input.versionCode
    || !input.incomingPath
  )) {
    throw new Error(
      'Usage: publish-release <android|windows> <version> <file> [mandatory] '
      + 'or publish-release batch <version> <android-file> <windows-file> [mandatory]',
    );
  }

  const prepared: PreparedRelease[] = [];
  try {
    for (const input of inputs) {
      prepared.push(await prepareRelease(
        input.platform,
        input.versionCode,
        input.incomingPath,
        privateKey,
        input.isMandatory,
      ));
    }
  } catch (error) {
    for (const release of prepared) {
      if (fs.existsSync(release.temporaryPath)) fs.unlinkSync(release.temporaryPath);
    }
    throw error;
  }

  const client = await pgPool.connect();
  const movedNewFiles: PreparedRelease[] = [];
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    for (const release of prepared) {
      const id = `rel-${release.platform}-${release.versionCode.replace(/[^a-zA-Z0-9]/g, '-')}`;
      const notes = `Serenut OS ${release.versionCode}: güvenli canlı bağlantı, kalıcı senkronizasyon tanılama ve kararlı güncelleme altyapısı.`;
      await client.query(`
        INSERT INTO app_versions (
          id, version_code, platform, channel, download_url, file_path,
          sha256_hash, signature, digital_signature, file_size_bytes,
          is_mandatory, min_required_version, release_notes, status,
          rollout_percentage, created_at, updated_at
        ) VALUES ($1, $2, $3, 'stable', $4, $5, $6, $7, $7, $8,
                  $10, NULL, $9, 'active', 100, NOW(), NOW())
        ON CONFLICT (version_code, platform, channel) DO UPDATE SET
          download_url = EXCLUDED.download_url,
          file_path = EXCLUDED.file_path,
          sha256_hash = EXCLUDED.sha256_hash,
          signature = EXCLUDED.signature,
          digital_signature = EXCLUDED.digital_signature,
          file_size_bytes = EXCLUDED.file_size_bytes,
          release_notes = EXCLUDED.release_notes,
          is_mandatory = EXCLUDED.is_mandatory,
          status = 'active', rollout_percentage = 100, updated_at = NOW()
      `, [
        id,
        release.versionCode,
        release.platform,
        `/api/v1/updates/download/${release.platform}/latest`,
        release.finalPath,
        release.hash,
        release.signature,
        release.size,
        notes,
        release.isMandatory,
      ]);
    }
    for (const release of prepared) {
      if (!release.reusedExistingFile) {
        fs.renameSync(release.temporaryPath, release.finalPath);
        movedNewFiles.push(release);
      }
    }
    await client.query('COMMIT');
    console.log(JSON.stringify(prepared.map((release) => ({
      platform: release.platform,
      versionCode: release.versionCode,
      finalPath: release.finalPath,
      sha256: release.hash,
      size: release.size,
    }))));
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    for (const release of movedNewFiles) {
      if (fs.existsSync(release.finalPath)) fs.unlinkSync(release.finalPath);
    }
    for (const release of prepared) {
      if (fs.existsSync(release.temporaryPath)) fs.unlinkSync(release.temporaryPath);
    }
    throw error;
  } finally {
    client.release();
    await pgPool.end();
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
