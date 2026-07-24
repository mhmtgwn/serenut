$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$keyConfig = Join-Path $workspace 'config/signing_public_keys.json'

if (-not (Test-Path -LiteralPath $keyConfig)) {
  throw "Missing public signing-key configuration: $keyConfig"
}

Push-Location $workspace
try {
  flutter pub get
  flutter build windows --release --dart-define-from-file="$keyConfig"
} finally {
  Pop-Location
}
