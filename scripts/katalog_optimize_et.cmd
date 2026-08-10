@echo off
setlocal
cd /d "%~dp0\.."
if "%~1"=="" (
  python scripts\optimize_catalog.py
) else (
  python scripts\optimize_catalog.py "%~1"
)
set "result=%errorlevel%"
echo.
if not "%result%"=="0" echo Islem basarisiz oldu. Yukaridaki hata mesajini kontrol edin.
pause
exit /b %result%
