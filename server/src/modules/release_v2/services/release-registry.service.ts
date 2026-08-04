// server/src/modules/release_v2/services/release-registry.service.ts
import { Pool } from 'pg';
import crypto from 'crypto';
import { ReleaseAuditService } from './release-audit.service';
import { ReleaseManifestDTO, validateReleaseManifestDTO } from '../models/release-manifest.dto';

function stableJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.entries(value as Record<string, unknown>)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, entry]) => `${JSON.stringify(key)}:${stableJson(entry)}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export class ReleaseRegistryService {
  private auditService: ReleaseAuditService;

  constructor(private pool: Pool) {
    this.auditService = new ReleaseAuditService(pool);
  }

  /**
   * Publishes a release manifest and its artifacts atomically in a single transaction.
   * Calculates ADR-011 artifact_set_hash.
   */
  async publishRelease(
    manifest: ReleaseManifestDTO,
    canonicalManifestJson: string,
    manifestSignature: string,
    buildCommit: string,
    buildPipelineId: string,
    actorId: string
  ): Promise<{ success: boolean; releaseId: string; artifactSetHash: string; error?: string }> {
    const client = await this.pool.connect();
    try {
      const validation = validateReleaseManifestDTO(manifest);
      if (!validation.valid) throw new Error(`invalid_manifest:${validation.errors.join(',')}`);
      let parsedCanonical: unknown;
      try { parsedCanonical = JSON.parse(canonicalManifestJson); }
      catch (_) { throw new Error('invalid_canonical_manifest_json'); }
      if (stableJson(parsedCanonical) !== stableJson(manifest)) {
        throw new Error('canonical_manifest_mismatch');
      }
      const configuredKey = process.env.RELEASE_SIGNING_PUBLIC_KEY;
      if (!configuredKey) throw new Error('release_signing_public_key_not_configured');
      const publicKey = configuredKey.includes('BEGIN PUBLIC KEY')
        ? configuredKey.replace(/\\n/g, '\n')
        : Buffer.from(configuredKey, 'base64').toString('utf8');
      const signature = Buffer.from(manifestSignature, 'base64');
      if (!signature.length || !crypto.verify('RSA-SHA256', Buffer.from(canonicalManifestJson, 'utf8'), publicKey, signature)) {
        throw new Error('invalid_manifest_signature');
      }
      for (const artifact of manifest.artifacts) {
        const artifactSignature = Buffer.from(artifact.signature, 'base64');
        if (!artifactSignature.length ||
            !crypto.verify('RSA-SHA256', Buffer.from(artifact.sha256.toLowerCase(), 'utf8'), publicKey, artifactSignature)) {
          throw new Error(`invalid_artifact_signature:${artifact.filename}`);
        }
      }
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      // 1. Calculate ADR-011: artifact_set_hash
      // Sort artifact hashes by type and filename to ensure determinism
      const sortedArtifacts = [...manifest.artifacts].sort((a, b) => {
        const typeCompare = a.type.localeCompare(b.type);
        if (typeCompare !== 0) return typeCompare;
        return a.filename.localeCompare(b.filename);
      });

      const manifestHash = crypto.createHash('sha256').update(canonicalManifestJson).digest('hex');
      const artifactHashes = sortedArtifacts.map(art => art.sha256);
      
      const compositeHashData = [
        manifestHash,
        ...artifactHashes
      ].join('|');

      const artifactSetHash = crypto.createHash('sha256').update(compositeHashData).digest('hex');

      // 2. Insert core release record
      await client.query(`
        INSERT INTO releases (
          release_id, version_code, channel, current_state, manifest_sha256, manifest_signature, build_commit, build_pipeline_id, artifact_set_hash
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        ON CONFLICT (release_id) DO UPDATE SET
          current_state = EXCLUDED.current_state,
          manifest_sha256 = EXCLUDED.manifest_sha256,
          manifest_signature = EXCLUDED.manifest_signature,
          build_commit = EXCLUDED.build_commit,
          build_pipeline_id = EXCLUDED.build_pipeline_id,
          artifact_set_hash = EXCLUDED.artifact_set_hash,
          updated_at = NOW()
      `, [
        manifest.releaseId,
        manifest.version,
        manifest.channel,
        'draft', // Initial state is always draft
        manifestHash,
        manifestSignature,
        buildCommit,
        buildPipelineId,
        artifactSetHash
      ]);

      // 3. Clear existing artifacts for this release to maintain idempotence
      await client.query('DELETE FROM release_artifacts WHERE release_id = $1', [manifest.releaseId]);

      // 4. Insert artifact records
      for (const art of manifest.artifacts) {
        await client.query(`
          INSERT INTO release_artifacts (
            release_id, type, filename, download_url, size_bytes, sha256, signature
          ) VALUES ($1, $2, $3, $4, $5, $6, $7)
        `, [
          manifest.releaseId,
          art.type,
          art.filename,
          art.downloadUrl,
          art.sizeBytes,
          art.sha256,
          art.signature
        ]);
      }

      // 5. Store manifest canonical JSON
      await client.query(`
        INSERT INTO release_manifest_store (
          release_id, canonical_manifest_json, manifest_sha256, manifest_signature
        ) VALUES ($1, $2, $3, $4)
        ON CONFLICT (release_id) DO UPDATE SET
          canonical_manifest_json = EXCLUDED.canonical_manifest_json,
          manifest_sha256 = EXCLUDED.manifest_sha256,
          manifest_signature = EXCLUDED.manifest_signature
      `, [
        manifest.releaseId,
        canonicalManifestJson,
        manifestHash,
        manifestSignature
      ]);

      // 6. Seed initial 100% promotion setup
      await client.query(`
        INSERT INTO release_promotions (release_id, rollout_percentage)
        VALUES ($1, 100)
        ON CONFLICT (release_id) DO NOTHING
      `, [manifest.releaseId]);

      // 7. Log publication audit event
      await this.auditService.log({
        releaseId: manifest.releaseId,
        actorId,
        action: 'PUBLISH',
        fromState: null,
        toState: 'draft',
        payload: { artifactSetHash, manifestHash, artifactCount: manifest.artifacts.length }
      });

      await client.query('COMMIT');
      return {
        success: true,
        releaseId: manifest.releaseId,
        artifactSetHash
      };
    } catch (err: any) {
      await client.query('ROLLBACK');
      return {
        success: false,
        releaseId: manifest.releaseId,
        artifactSetHash: '',
        error: err.message || String(err)
      };
    } finally {
      client.release();
    }
  }
}
