@echo off
rem ==============================================================================
rem LuminaX 1-Click Windows Batch Updater
rem Launches the PowerShell updater with ExecutionPolicy bypass and argument forwarding
rem ==============================================================================

setlocal

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
cd /d "%SCRIPT_DIR%"

set "PS_SCRIPT="
if exist "%SCRIPT_DIR%\update.ps1" set "PS_SCRIPT=%SCRIPT_DIR%\update.ps1"
if not defined PS_SCRIPT if exist "%SCRIPT_DIR%\tools\update.ps1" set "PS_SCRIPT=%SCRIPT_DIR%\tools\update.ps1"

if not defined PS_SCRIPT (
    echo [ERROR] Could not find update.ps1 in "%SCRIPT_DIR%" or "%SCRIPT_DIR%\tools"
    echo Please make sure you are running update.bat from your real mpv configuration folder.
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

rem Resolve configuration directory context
set "TARGET_DIR=%SCRIPT_DIR%"
if exist "%SCRIPT_DIR%\..\scripts\LuminaX" set "TARGET_DIR=%SCRIPT_DIR%\.."

rem Pass TargetDir if not already specified by user
set "HAS_TARGET=0"
echo "%*" | findstr /i "TargetDir" >nul && set "HAS_TARGET=1"

if "%HAS_TARGET%"=="1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -TargetDir "%TARGET_DIR%" %*
)
set "EXIT_CODE=%ERRORLEVEL%"

if %EXIT_CODE% neq 0 (
    echo [!] Update process encountered an issue - Exit Code: %EXIT_CODE%
    pause
)

exit /b %EXIT_CODE%

