// server/src/modules/update/update.repository.ts
import { pgPool } from '../../config/database';

export interface DownloadRelease {
  file_path: string;
  version_code: string;
  sha256_hash: string | null;
}

export interface ReleaseMetadataRow {
  id: string;
  version_code: string;
  platform: string;
  sha256_hash: string | null;
  file_size_bytes: number | null;
  release_notes: string | null;
  created_at: Date;
  file_path: string;
}

export interface ReleaseCheckRow {
  version_code: string;
  platform: string;
  download_url: string;
  sha256_hash: string | null;
  signature: string | null;
  file_size_bytes: number | null;
  is_mandatory: boolean;
  release_notes: string | null;
  file_path: string;
}

export class UpdateRepository {
  async getReleaseByVersion(platform: string, version: string): Promise<DownloadRelease | null> {
    const result = await pgPool.query<DownloadRelease>(`
      SELECT file_path, version_code, sha256_hash
      FROM app_versions
      WHERE platform = $1 AND version_code = $2
        AND status = 'active' AND channel = 'stable'
        AND (SELECT COUNT(*) FROM update_targets ut WHERE ut.release_id = app_versions.id) = 0
      LIMIT 50
    `, [platform, version]);
    return result.rows[0] || null;
  }

  async getLatestCandidates(platform: string): Promise<DownloadRelease[]> {
    const query = `
      SELECT file_path, version_code, sha256_hash
      FROM app_versions
      WHERE platform = $1 AND status = 'active' AND channel = 'stable'
        AND (SELECT COUNT(*) FROM update_targets ut WHERE ut.release_id = app_versions.id) = 0
      ORDER BY created_at DESC
      LIMIT 50
    `;
    const result = await pgPool.query<DownloadRelease>(query, [platform]);
    return result.rows;
  }

  async getActiveStableMetadata(): Promise<ReleaseMetadataRow[]> {
    const query = `
      SELECT id, version_code, platform, sha256_hash, file_size_bytes, release_notes, created_at, file_path
      FROM app_versions
      WHERE status = 'active' AND channel = 'stable'
        AND (SELECT COUNT(*) FROM update_targets ut WHERE ut.release_id = app_versions.id) = 0
    `;
    const result = await pgPool.query<ReleaseMetadataRow>(query);
    return result.rows;
  }

  async getCheckReleases(platform: string): Promise<ReleaseCheckRow[]> {
    const query = `
      SELECT version_code, platform, download_url, sha256_hash, signature, file_size_bytes, is_mandatory, release_notes, file_path
      FROM app_versions
      WHERE platform = $1 AND status = 'active' AND channel = 'stable'
        AND (SELECT COUNT(*) FROM update_targets ut WHERE ut.release_id = app_versions.id) = 0
    `;
    const result = await pgPool.query<ReleaseCheckRow>(query, [platform]);
    return result.rows;
  }
}

export const updateRepository = new UpdateRepository();
