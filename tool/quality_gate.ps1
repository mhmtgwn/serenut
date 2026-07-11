$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Running Serenut POS Quality Gate Checklist" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Run Flutter Analyze (Assertive Fail: Fail on both errors and warnings)
Write-Host "`n[1/2] Running Flutter Analyze..." -ForegroundColor Yellow
$analyzeOutput = flutter analyze --fatal-warnings
$analyzeExitCode = $LASTEXITCODE

if ($analyzeExitCode -ne 0) {
    Write-Host "❌ Flutter Analyze found issues! Details:" -ForegroundColor Red
    Write-Host $analyzeOutput
    exit 1
} else {
    Write-Host "✅ Flutter Analyze completed with 0 errors/warnings!" -ForegroundColor Green
}

# 2. Run Flutter Test
Write-Host "`n[2/2] Running Flutter Tests..." -ForegroundColor Yellow
$testOutput = flutter test
$testExitCode = $LASTEXITCODE

if ($testExitCode -ne 0) {
    Write-Host "❌ Flutter Tests failed!" -ForegroundColor Red
    Write-Host $testOutput
    exit 1
} else {
    Write-Host "✅ All Flutter tests passed successfully!" -ForegroundColor Green
}

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "🎉 Quality Gate Passed Successfully!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
exit 0
