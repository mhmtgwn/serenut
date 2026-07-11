// server/src/utils/telemetry.ts
// Serenut OS — Advanced SRE Telemetry & Metrics Store

let jwtFailures = 0;
let licenseSuccess = 0;
let licenseFailures = 0;
let slowQueries = 0;

export function incrementJwtFailures() {
  jwtFailures++;
}

export function getJwtFailuresCount(): number {
  return jwtFailures;
}

export function incrementLicenseValidation(success: boolean) {
  if (success) {
    licenseSuccess++;
  } else {
    licenseFailures++;
  }
}

export function getLicenseSuccessCount(): number {
  return licenseSuccess;
}

export function getLicenseFailuresCount(): number {
  return licenseFailures;
}

export function incrementSlowQueries() {
  slowQueries++;
}

export function getSlowQueriesCount(): number {
  return slowQueries;
}
