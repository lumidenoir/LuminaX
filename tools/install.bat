@echo off
rem ==============================================================================
rem LuminaX Automated Windows Batch Installer
rem Installs LuminaX scripts, visionOS glass theme, and fonts to mpv configuration
rem ==============================================================================

setlocal enabledelayedexpansion

echo ======================================================================
echo 🌟 LuminaX Windows Installer for mpv
echo ======================================================================

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

rem Detect package root whether running from repository (tools\..) or extracted release archive (.)
if exist "%SCRIPT_DIR%\scripts\LuminaX" (
    set "PACKAGE_ROOT=%SCRIPT_DIR%"
) else if exist "%SCRIPT_DIR%\..\scripts\LuminaX" (
    pushd "%SCRIPT_DIR%\.."
    set "PACKAGE_ROOT=!CD!"
    popd
) else (
    echo [ERROR] Cannot find LuminaX source files (scripts\LuminaX).
    echo Make sure you are running install.bat from within the LuminaX folder.
    pause
    exit /b 1
)

rem 1. Determine target directory
if "%~1"=="" (
    if exist "%PACKAGE_ROOT%\portable_config" (
        set "TARGET_DIR=%PACKAGE_ROOT%\portable_config"
    ) else if exist "%PACKAGE_ROOT%\..\portable_config" (
        set "TARGET_DIR=%PACKAGE_ROOT%\..\portable_config"
    ) else (
        set "TARGET_DIR=%APPDATA%\mpv"
    )
) else (
    set "TARGET_DIR=%~1"
)

echo Installing to: %TARGET_DIR%

rem 2. Create destination directories
if not exist "%TARGET_DIR%\scripts\LuminaX\modules" mkdir "%TARGET_DIR%\scripts\LuminaX\modules"
if not exist "%TARGET_DIR%\fonts" mkdir "%TARGET_DIR%\fonts"
if not exist "%TARGET_DIR%\script-opts" mkdir "%TARGET_DIR%\script-opts"

rem 3. Copy scripts and fonts (skip if target is identical to package root)
if /i "%PACKAGE_ROOT%"=="%TARGET_DIR%" (
    echo Target directory is identical to source package root; files already in place.
) else (
    echo Copying LuminaX script files...
    xcopy /E /Y /I "%PACKAGE_ROOT%\scripts\LuminaX" "%TARGET_DIR%\scripts\LuminaX" >nul

    echo Copying UI and icon fonts to mpv\fonts...
    xcopy /E /Y /I "%PACKAGE_ROOT%\fonts" "%TARGET_DIR%\fonts" >nul

    rem 5. Copy configuration
    if not exist "%TARGET_DIR%\script-opts\osc.conf" (
        echo Copying osc.conf template...
        copy /Y "%PACKAGE_ROOT%\script-opts\osc.conf" "%TARGET_DIR%\script-opts\osc.conf" >nul
    ) else (
        echo Preserving existing %TARGET_DIR%\script-opts\osc.conf
    )
)

rem 6. Configure mpv.conf (Disable default osc & osd-bar)
set "MPV_CONF=%TARGET_DIR%\mpv.conf"
if not exist "%MPV_CONF%" (
    echo Creating mpv.conf...
    (
        echo # Disable stock mpv controls for LuminaX
        echo osc=no
        echo osd-bar=no
        echo osd-font="Inter"
    ) > "%MPV_CONF%"
) else (
    findstr /I "osc=no" "%MPV_CONF%" >nul
    if errorlevel 1 (
        echo Adding osc=no to %MPV_CONF%...
        echo.>> "%MPV_CONF%"
        echo # Disable stock mpv controls for LuminaX>> "%MPV_CONF%"
        echo osc=no>> "%MPV_CONF%"
    )
    findstr /I "osd-bar=no" "%MPV_CONF%" >nul
    if errorlevel 1 (
        echo Adding osd-bar=no to %MPV_CONF%...
        echo osd-bar=no>> "%MPV_CONF%"
    )
)

rem 7. Configure input.conf
set "INPUT_CONF=%TARGET_DIR%\input.conf"
if not exist "%INPUT_CONF%" (
    if exist "%PACKAGE_ROOT%\input.conf" (
        copy /Y "%PACKAGE_ROOT%\input.conf" "%INPUT_CONF%" >nul
        echo Created input.conf with LuminaX keybindings.
    )
) else (
    if /i not "%PACKAGE_ROOT%"=="%TARGET_DIR%" (
        findstr /I "menu-playlist" "%INPUT_CONF%" >nul
        if errorlevel 1 (
            echo Adding LuminaX menu shortcuts to %INPUT_CONF%...
            (
                echo.
                echo # LuminaX Interactive Glass Menus ^& OSD
                echo tab               script-binding LuminaX/visibility
                echo p                 script-binding LuminaX/menu-playlist
                echo c                 script-binding LuminaX/menu-chapters
                echo a                 script-binding LuminaX/menu-audio
                echo s                 script-binding LuminaX/menu-sub
            ) >> "%INPUT_CONF%"
        )
    )
)

echo.
echo ======================================================================
echo 🎉 LuminaX has been successfully installed on your Windows system!
echo ======================================================================
echo.
echo Next steps:
echo 1. Open %TARGET_DIR%\script-opts\osc.conf and enter your TMDB API key.
echo 2. Make sure ffmpeg.exe is in your PATH or in your mpv directory.
echo 3. Play any video in mpv!
echo.
pause
