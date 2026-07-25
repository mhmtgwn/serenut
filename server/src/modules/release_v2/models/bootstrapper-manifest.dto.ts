// server/src/modules/release_v2/models/bootstrapper-manifest.dto.ts
// Serenut Platform — Server Bootstrapper Manifest DTO (schemaVersion = 1)

export interface BootstrapperManifestDTO {
  schemaVersion: 1;
  correlationId: string;
  appPid: number;
  targetVersion: string;
  installerPath: string;
  targetDir: string;
  backupDir: string;
  postLaunchExe: string;
}

export function validateBootstrapperManifestDTO(data: any): { valid: boolean; errors: string[] } {
  const errors: string[] = [];

  if (data?.schemaVersion !== 1) {
    errors.push('Invalid schemaVersion: must be 1');
  }
  if (!data?.correlationId || typeof data.correlationId !== 'string') {
    errors.push('Missing correlationId');
  }
  if (!data?.appPid || typeof data.appPid !== 'number' || data.appPid <= 0) {
    errors.push('appPid must be a positive integer');
  }

  return { valid: errors.length === 0, errors };
}
