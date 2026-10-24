@echo off
chcp 65001 >nul
echo ===================================================
echo 🚀 Serenut OS - Guvenli Deploy ^& Push Pipeline
echo ===================================================

echo.
echo [1/4] Mimari Borc Kontrolu (Architecture Guard)...
node tool\architecture_guard.mjs
if %ERRORLEVEL% neq 0 (
    echo ❌ Architecture Guard basarisiz oldu!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [2/4] OTA Release Anahtar Surekliligi Kontrolu...
node scripts\verify_release_key_continuity.js HEAD~3
if %ERRORLEVEL% neq 0 (
    echo ❌ Release key continuity dogrulamasi basarisiz!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [3/4] Release Manager Kritik Testi...
call flutter test test\services\release_manager_test.dart
if %ERRORLEVEL% neq 0 (
    echo ❌ Release Manager testi basarisiz!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [4/4] Git Push origin main (CI/CD Tetikleme)...
git push origin main
if %ERRORLEVEL% neq 0 (
    echo ❌ Git push basarisiz oldu veya iptal edildi!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ===================================================
echo 🎉 Basariyla push edildi!
echo GitHub Actions uzerinde yayinlama basladi:
echo https://github.com/mhmtgwn/serenut/actions
echo ===================================================
pause
