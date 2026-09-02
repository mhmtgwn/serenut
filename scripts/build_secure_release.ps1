param(
    [ValidateSet('all', 'windows', 'android')]
    [string]$Target = 'all'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$keys = Get-Content 'config\signing_public_keys.json' -Raw | ConvertFrom-Json
$signingPolicy = Get-Content 'server\release-signing-policy.json' -Raw | ConvertFrom-Json
$licenseModulus = [string]$keys.LICENSE_RSA_MODULUS
$activeReleaseModulus = [string]$keys.RELEASE_RSA_MODULUS
$trustedReleaseModuli = @($keys.RELEASE_RSA_TRUSTED_MODULI | ForEach-Object { [string]$_ })

if ([string]::IsNullOrWhiteSpace($licenseModulus)) {
    throw 'LICENSE_RSA_MODULUS is missing.'
}
if ([string]::IsNullOrWhiteSpace($activeReleaseModulus)) {
    throw 'RELEASE_RSA_MODULUS is missing.'
}
if ($trustedReleaseModuli.Count -lt 1 -or $trustedReleaseModuli[0] -ne $activeReleaseModulus) {
    throw 'The active release modulus must be the first trusted key.'
}
if (($trustedReleaseModuli | Select-Object -Unique).Count -ne $trustedReleaseModuli.Count) {
    throw 'RELEASE_RSA_TRUSTED_MODULI contains duplicate keys.'
}

$releaseKeyring = $trustedReleaseModuli -join ','
if ([string]$keys.RELEASE_RSA_MODULI -ne $releaseKeyring) {
    throw 'RELEASE_RSA_MODULI must exactly match RELEASE_RSA_TRUSTED_MODULI in the same order.'
}
$activeModulusBytes = [Text.Encoding]::UTF8.GetBytes($activeReleaseModulus)
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha256.ComputeHash($activeModulusBytes)
$activeModulusFingerprint = [BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
if ($activeModulusFingerprint -ne [string]$signingPolicy.requiredUpgradeSignerModulusSha256) {
    throw 'The active client key does not match the required upgrade signer policy.'
}
$defines = @(
    '--dart-define=ENVIRONMENT=prod',
    "--dart-define=LICENSE_RSA_MODULUS=$licenseModulus",
    "--dart-define=RELEASE_RSA_MODULI=$releaseKeyring"
)

flutter test test\services\release_manager_test.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Target -in @('all', 'windows')) {
    flutter build windows --release @defines
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
    if (-not (Test-Path $iscc)) { throw "Inno Setup compiler not found: $iscc" }
    & $iscc 'windows\installer.iss'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($Target -in @('all', 'android')) {
    flutter build apk --release --target-platform android-arm64 @defines
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $buildTools = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -eq $buildTools) { throw 'Android build-tools not found.' }
    & (Join-Path $buildTools.FullName 'apksigner.bat') verify --verbose --print-certs `
        'build\app\outputs\flutter-apk\app-release.apk'
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host 'Secure release build completed.' -ForegroundColor Green
