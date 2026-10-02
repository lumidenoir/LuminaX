@echo off
rem ==============================================================================
rem LuminaX 1-Click Windows Batch Updater
rem Launches the PowerShell updater with ExecutionPolicy bypass and argument forwarding
rem ==============================================================================

setlocal

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "PS_SCRIPT="
if exist "%SCRIPT_DIR%\update.ps1" set "PS_SCRIPT=%SCRIPT_DIR%\update.ps1"
if not defined PS_SCRIPT if exist "%SCRIPT_DIR%\tools\update.ps1" set "PS_SCRIPT=%SCRIPT_DIR%\tools\update.ps1"

if not defined PS_SCRIPT (
    echo [ERROR] Could not find update.ps1 in "%SCRIPT_DIR%"
    echo Please make sure you are running update.bat from your LuminaX / mpv folder.
    pause
    exit /b 1
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] powershell.exe was not found in your system PATH.
    echo LuminaX updater requires PowerShell on Windows.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if %EXIT_CODE% neq 0 (
    echo [!] Update process encountered an issue - Exit Code: %EXIT_CODE%
    pause
)

exit /b %EXIT_CODE%
