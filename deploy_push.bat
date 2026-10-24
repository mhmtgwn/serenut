@echo off
setlocal
cd /d "%~dp0"

echo ===================================================
echo Serenut OS - Deploy and Push Pipeline
echo ===================================================

echo.
echo [1/4] Running Architecture Guard...
call node tool\architecture_guard.mjs
if errorlevel 1 (
    echo [ERROR] Architecture Guard failed!
    pause
    exit /b 1
)

echo.
echo [2/4] Verifying Release Key Continuity...
call node scripts\verify_release_key_continuity.js origin/main
if errorlevel 1 (
    echo [ERROR] Release key continuity verification failed!
    pause
    exit /b 1
)

echo.
echo [3/4] Running Release Manager Test...
call flutter test test\services\release_manager_test.dart
if errorlevel 1 (
    echo [ERROR] Release Manager test failed!
    pause
    exit /b 1
)

echo.
echo [4/4] Pushing to Git (origin main)...
git push origin main
if errorlevel 1 (
    echo [ERROR] Git push failed or was cancelled!
    pause
    exit /b 1
)

echo.
echo ===================================================
echo SUCCESS! Release triggered via GitHub Actions.
echo Check progress at: https://github.com/mhmtgwn/serenut/actions
echo ===================================================
pause
