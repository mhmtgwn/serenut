@echo off
title SERENUT OS - STAGE 10.12.94 NUTOPIA CANLI GECIS
color 0A
cls
echo ================================================================
echo    SERENUT OS - STAGE 10.12.94
echo    Nutopia Canli Yedekleme, Delta Esitleme ve Pilot Dogrulama
echo ================================================================
echo.

cd /d "C:\Users\notop\AndroidStudioProjects\shaman_new"

set "PYTHON_EXE="
if exist "C:\Program Files\Python313\python.exe" (
    set "PYTHON_EXE=C:\Program Files\Python313\python.exe"
) else (
    where py >nul 2>&1 && set "PYTHON_EXE=py" || set "PYTHON_EXE=python"
)

echo [1/2] Calistirici motor baglandi: %PYTHON_EXE%
echo [2/2] Canli aktarim, yedekleme ve mutabakat yurutuluyor...
echo ----------------------------------------------------------------
echo.

"%PYTHON_EXE%" scripts\stage10_12_94_live_backup_and_delta.py

echo.
echo ================================================================
echo Islem tamamlandi!
echo ================================================================
echo.
pause
