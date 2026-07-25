// server/src/modules/release_v2/models/update-telemetry.dto.ts
// Serenut Platform — Server Telemetry Event DTO (schemaVersion = 1)

export type UpdateEventTypeStr =
  | 'CHECK_STARTED'
  | 'MANIFEST_VERIFIED'
  | 'PRECHECK_PASSED'
  | 'PRECHECK_FAILED'
  | 'DOWNLOAD_STARTED'
  | 'DOWNLOAD_COMPLETED'
  | 'VERIFICATION_FAILED'
  | 'DRAIN_STARTED'
  | 'BOOTSTRAPPER_LAUNCHED'
  | 'POST_INSTALL_STARTED'
  | 'HEALTH_CHECK_PASSED'
  | 'HEALTH_CHECK_FAILED'
  | 'INSTALL_SUCCESS'
  | 'INSTALL_FAILED'
  | 'ROLLBACK_EXECUTED';

export interface UpdateTelemetryEventDTO {
  schemaVersion: 1;
  correlationId: string;
  deviceId: string;
  companyId?: string | null;
  fromVersion: string;
  toVersion: string;
  eventType: UpdateEventTypeStr;
  errorCode?: string | null;
  errorMessage?: string | null;
  systemSpecs?: Record<string, any> | null;
  timestamp: string;
}

export function validateUpdateTelemetryEventDTO(data: any): { valid: boolean; errors: string[] } {
  const errors: string[] = [];

  if (data?.schemaVersion !== 1) {
    errors.push('Invalid schemaVersion: must be 1');
  }
  if (!data?.correlationId || typeof data.correlationId !== 'string') {
    errors.push('Missing correlationId');
  }
  if (!data?.deviceId || typeof data.deviceId !== 'string') {
    errors.push('Missing deviceId');
  }
  if (!data?.eventType || typeof data.eventType !== 'string') {
    errors.push('Missing eventType');
  }

  return { valid: errors.length === 0, errors };
}
