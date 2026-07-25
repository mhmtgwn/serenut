// server/src/modules/release_v2/models/release-manifest.dto.ts
// Serenut Platform — Server Release Manifest DTO (schemaVersion = 1)

export interface BuildMetadataDTO {
  commitHash: string;
  buildNumber: number;
  buildDate: string;
  signatureAlgorithm: 'RSA-SHA256';
}

export interface ReleaseCompatibilityDTO {
  minClientVersion: string;
  minimumUpdaterVersion: string;
  requiredBootstrapper: string;
  requiredPreVersion?: string | null;
  migrationRequired: boolean;
  targetSchemaVersion: number;
}

export interface ReleaseRulesDTO {
  isMandatory: boolean;
  allowRollback: boolean;
  minFreeDiskMb: number;
  minRamMb: number;
  supportedArchitectures: string[];
}

export interface ReleaseArtifactDTO {
  type: string;
  filename: string;
  downloadUrl: string;
  sizeBytes: number;
  sha256: string;
  signature: string;
}

export interface ReleaseManifestDTO {
  schemaVersion: 1;
  manifestVersion: string;
  releaseId: string;
  version: string;
  channel: 'stable' | 'beta' | 'rc';
  publishedAt: string;
  buildMetadata: BuildMetadataDTO;
  compatibility: ReleaseCompatibilityDTO;
  rules: ReleaseRulesDTO;
  artifacts: ReleaseArtifactDTO[];
}

export function validateReleaseManifestDTO(data: any): { valid: boolean; errors: string[] } {
  const errors: string[] = [];

  if (data?.schemaVersion !== 1) {
    errors.push('Invalid schemaVersion: must be 1');
  }
  if (!data?.releaseId || typeof data.releaseId !== 'string') {
    errors.push('Missing or invalid releaseId');
  }
  if (!data?.version || typeof data.version !== 'string') {
    errors.push('Missing or invalid version');
  }
  if (!Array.isArray(data?.artifacts) || data.artifacts.length === 0) {
    errors.push('artifacts must be a non-empty array');
  } else {
    data.artifacts.forEach((art: any, index: number) => {
      if (!art.sha256 || !/^[a-fA-F0-9]{64}$/.test(art.sha256)) {
        errors.push(`artifacts[${index}].sha256 is not a valid 64-char hex string`);
      }
      if (!art.signature || typeof art.signature !== 'string') {
        errors.push(`artifacts[${index}].signature is missing`);
      }
    });
  }

  return { valid: errors.length === 0, errors };
}
