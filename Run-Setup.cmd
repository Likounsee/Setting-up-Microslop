@echo off
setlocal
title Windows Setup and Debloat
cd /d "%~dp0"

echo ================================================================
echo             WINDOWS SETUP ^& DEBLOAT
echo ================================================================
echo.
echo Starting the setup script. Administrator approval may be requested.
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-Setup.ps1"
set "SETUP_EXIT=%ERRORLEVEL%"

echo.
echo ================================================================
if not "%SETUP_EXIT%"=="0" (
    echo Setup finished with errors. Exit code: %SETUP_EXIT%
) else (
    echo Setup finished. Exit code: 0
)
echo.
echo Logs are available in: "%~dp0Logs"
echo This window will stay open until you press a key.
pause >nul
exit /b %SETUP_EXIT%
