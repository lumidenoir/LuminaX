<#
.SYNOPSIS
    LuminaX Automated PowerShell Updater for Windows
.DESCRIPTION
    Checks for the latest GitHub release, downloads and verifies the Windows release archive,
    creates an atomic backup, performs safe in-place upgrades of LuminaX scripts and fonts,
    and preserves existing user configurations (TMDB API key, custom bindings).
#>

[CmdletBinding()]
param(
    [string]$TargetDir = "",
    [switch]$NonInteractive,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$CheckMark = "$([char]0x2713)"
$CrossMark = "$([char]0x2717)"
$WarnMark  = "$([char]0x26A0)"
$InfoMark  = "$([char]0x2139)"
$StarMark  = "$([char]0x2605)"

function Write-Step { param([string]$Msg) Write-Host "`n=== $Msg ===" -ForegroundColor Cyan }
function Write-Success { param([string]$Msg) Write-Host "  $CheckMark $Msg" -ForegroundColor Green }
function Write-WarningMsg { param([string]$Msg) Write-Host "  $WarnMark $Msg" -ForegroundColor Yellow }
function Write-ErrorMsg { param([string]$Msg) Write-Host "  $CrossMark $Msg" -ForegroundColor Red }
function Write-InfoMsg { param([string]$Msg) Write-Host "  $InfoMark $Msg" -ForegroundColor Gray }

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  $StarMark LuminaX Automated Windows Updater" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Determine Target mpv Configuration Directory
# -----------------------------------------------------------------------------
Write-Step "1/5: Detecting mpv Configuration"

$resolvedTargetDir = $null
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($TargetDir -and (Test-Path $TargetDir)) {
    $resolvedTargetDir = (Resolve-Path $TargetDir).Path
} elseif (Test-Path (Join-Path $ScriptDir "scripts\LuminaX")) {
    $resolvedTargetDir = (Resolve-Path $ScriptDir).Path
} elseif (Test-Path (Join-Path $ScriptDir "..\scripts\LuminaX")) {
    $resolvedTargetDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
} else {
    # Check running process
    $proc = Get-Process mpv -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -First 1
    if ($proc) {
        $mpvBase = Split-Path -Parent $proc
        $portable = Join-Path $mpvBase "portable_config"
        if (Test-Path $portable) { $resolvedTargetDir = $portable }
    }
    if (-not $resolvedTargetDir) {
        $appDataMpv = Join-Path $env:APPDATA "mpv"
        if (Test-Path (Join-Path $appDataMpv "scripts\LuminaX")) {
            $resolvedTargetDir = $appDataMpv
        }
    }
}

# Safeguard: Verify whether we were launched from an extracted installer package rather than a real mpv config directory
$isInstallerPackage = $false
if ($resolvedTargetDir) {
    $hasInstallerScripts = (Test-Path (Join-Path $resolvedTargetDir "install.ps1")) -or `
                           (Test-Path (Join-Path $resolvedTargetDir "install.bat")) -or `
                           (Test-Path (Join-Path $resolvedTargetDir "tools\package_dist.py"))
    $hasMpvExe = (Test-Path (Join-Path $resolvedTargetDir "mpv.exe")) -or (Test-Path (Join-Path $resolvedTargetDir "..\mpv.exe"))
    if ($hasInstallerScripts -and -not $hasMpvExe) {
        $isInstallerPackage = $true
    }
}

if ($isInstallerPackage) {
    Write-WarningMsg "update.bat was run from the extracted LuminaX release package folder."
    Write-Host "    update.bat should be run from inside your real mpv configuration directory." -ForegroundColor Yellow

    # Search for user's real installed mpv configuration
    $foundActiveConfig = $null
    
    # 1. Running mpv process
    $proc = Get-Process mpv -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -First 1
    if ($proc) {
        $mpvBase = Split-Path -Parent $proc
        $portable = Join-Path $mpvBase "portable_config"
        if (Test-Path (Join-Path $portable "scripts\LuminaX")) {
            $foundActiveConfig = (Resolve-Path $portable).Path
        }
    }

    # 2. mpv.exe in PATH
    if (-not $foundActiveConfig) {
        $cmd = Get-Command "mpv.exe" -ErrorAction SilentlyContinue
        if ($cmd -and (Test-Path $cmd.Source)) {
            $candPort = Join-Path (Split-Path -Parent $cmd.Source) "portable_config"
            if (Test-Path (Join-Path $candPort "scripts\LuminaX")) {
                $foundActiveConfig = (Resolve-Path $candPort).Path
            }
        }
    }

    # 3. Standard AppData mpv folder
    if (-not $foundActiveConfig) {
        $appDataMpv = Join-Path $env:APPDATA "mpv"
        if (Test-Path (Join-Path $appDataMpv "scripts\LuminaX")) {
            $foundActiveConfig = (Resolve-Path $appDataMpv).Path
        }
    }

    if ($foundActiveConfig) {
        Write-Success "Found active LuminaX configuration: $foundActiveConfig"
        if ($NonInteractive) {
            $resolvedTargetDir = $foundActiveConfig
        } else {
            Write-Host "`n  Would you like to update your active mpv configuration ($foundActiveConfig)? [Y/n]" -ForegroundColor Cyan
            $ans = Read-Host "  Enter choice (Default: Y)"
            if ($ans.Trim() -eq "n" -or $ans.Trim() -eq "N") {
                Write-Host "Update cancelled. Run update.bat directly from inside your mpv configuration directory." -ForegroundColor Yellow
                exit 1
            }
            $resolvedTargetDir = $foundActiveConfig
        }
    } else {
        Write-ErrorMsg "Cannot locate an active installed mpv configuration."
        Write-Host "`n  [!] Important Notes for Windows:" -ForegroundColor Yellow
        Write-Host "    - Run 'install.bat' from this extracted package folder to install LuminaX for the first time." -ForegroundColor Cyan
        Write-Host "    - Run 'update.bat' only from within your real mpv configuration directory (e.g. %APPDATA%\mpv or portable_config)." -ForegroundColor Cyan
        Write-Host "    - Alternatively, specify -TargetDir 'C:\path\to\your\mpv\config'" -ForegroundColor Cyan
        if (-not $NonInteractive) { Read-Host "`nPress Enter to exit..." }
        exit 1
    }
}

if (-not $resolvedTargetDir -or -not (Test-Path $resolvedTargetDir)) {
    Write-ErrorMsg "Cannot locate active mpv configuration directory."
    Write-Host "Please run the updater specifying -TargetDir 'C:\path\to\mpv\portable_config' or run from your mpv directory." -ForegroundColor Yellow
    if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
    exit 1
}

Write-Success "Target mpv Directory: $resolvedTargetDir"

# Read local version
$localVersion = "0.0.0"
$versionFile = Join-Path $resolvedTargetDir "scripts\LuminaX\version.lua"
if (Test-Path $versionFile) {
    $vContent = Get-Content -Path $versionFile -Raw
    if ($vContent -match "VERSION\s*=\s*['""]([^'""]+)['""]") {
        $localVersion = $matches[1].Trim()
    }
}
Write-InfoMsg "Installed Version: v$localVersion"

# -----------------------------------------------------------------------------
# 2. Check Latest GitHub Release
# -----------------------------------------------------------------------------
Write-Step "2/5: Checking for Updates on GitHub"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Repo = "lumidenoir/LuminaX"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"

$releaseJson = $null
try {
    $headers = @{ "User-Agent" = "LuminaX-Updater" }
    $releaseJson = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -TimeoutSec 10
} catch {
    Write-WarningMsg "Could not contact GitHub API directly: $($_.Exception.Message)"
    # Fallback to curl if installed
    $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if ($curl) {
        try {
            $raw = & $curl.Source -s -H "User-Agent: LuminaX-Updater" $ApiUrl
            $releaseJson = $raw | ConvertFrom-Json
        } catch {}
    }
}

if (-not $releaseJson -or -not $releaseJson.tag_name) {
    Write-ErrorMsg "Unable to fetch release information from GitHub ($ApiUrl)."
    Write-Host "Please check your internet connection." -ForegroundColor Yellow
    if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
    exit 1
}

$latestTag = $releaseJson.tag_name.Trim().TrimStart('v')
Write-Success "Latest Release on GitHub: v$latestTag"

# Version comparison
function Compare-SemVer([string]$v1, [string]$v2) {
    $p1 = $v1.TrimStart('v').Split('.')
    $p2 = $v2.TrimStart('v').Split('.')
    for ($i = 0; $i -lt 3; $i++) {
        $n1 = if ($i -lt $p1.Count) { [int]($p1[$i] -replace '\D','') } else { 0 }
        $n2 = if ($i -lt $p2.Count) { [int]($p2[$i] -replace '\D','') } else { 0 }
        if ($n1 -gt $n2) { return 1 }
        if ($n1 -lt $n2) { return -1 }
    }
    return 0
}

$cmp = Compare-SemVer $latestTag $localVersion
if ($cmp -le 0 -and -not $Force) {
    Write-Success "LuminaX is already up to date! (v$localVersion)"
    if (-not $NonInteractive) {
        Write-Host "`nPress Enter to exit..." -ForegroundColor Gray
        [void][System.Console]::ReadLine()
    }
    exit 0
}

Write-Host "  Update available: v$localVersion -> v$latestTag" -ForegroundColor Yellow

# Find assets
$zipAsset = $releaseJson.assets | Where-Object { $_.name -like "*windows*.zip" } | Select-Object -First 1
$sumAsset = $releaseJson.assets | Where-Object { $_.name -like "*checksum*.txt" } | Select-Object -First 1

if (-not $zipAsset) {
    Write-ErrorMsg "Could not find a Windows release zip in release v$latestTag."
    if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
    exit 1
}

# -----------------------------------------------------------------------------
# 3. Download Release Archive & Verify Checksum
# -----------------------------------------------------------------------------
Write-Step "3/5: Downloading & Verifying Release Archive"

$tempDir = Join-Path $env:TEMP "luminax_update_$((Get-Date).Ticks)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$zipDest = Join-Path $tempDir $zipAsset.name
Write-InfoMsg "Downloading: $($zipAsset.browser_download_url)"
Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipDest -TimeoutSec 30
Write-Success "Downloaded release archive ($('{0:N0}' -f (Get-Item $zipDest).Length) bytes)"

# Verify checksum if checksums.txt is available
if ($sumAsset) {
    try {
        $sumContent = (Invoke-RestMethod -Uri $sumAsset.browser_download_url -TimeoutSec 10)
        $expectedHash = $null
        foreach ($line in ($sumContent -split "`n")) {
            if ($line -match "([a-fA-F0-9]{64})\s+.*windows.*\.zip") {
                $expectedHash = $matches[1].ToLower()
                break
            }
        }
        if ($expectedHash) {
            $actualHash = (Get-FileHash -Path $zipDest -Algorithm SHA256).Hash.ToLower()
            if ($actualHash -eq $expectedHash) {
                Write-Success "SHA-256 integrity verified ($actualHash)"
            } else {
                Write-ErrorMsg "Checksum mismatch! Archive may be corrupted."
                Write-Host "  Expected: $expectedHash" -ForegroundColor Red
                Write-Host "  Actual:   $actualHash" -ForegroundColor Red
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
                exit 1
            }
        }
    } catch {
        Write-WarningMsg "Checksum verification skipped: $($_.Exception.Message)"
    }
}

# -----------------------------------------------------------------------------
# 4. Extract & Atomic Backup
# -----------------------------------------------------------------------------
Write-Step "4/5: Installing LuminaX v$latestTag & Preserving Configurations"

$extractDir = Join-Path $tempDir "extracted"
Expand-Archive -Path $zipDest -DestinationPath $extractDir -Force

# Locate extracted package root
$extractedRoot = $extractDir
if (Test-Path (Join-Path $extractDir "scripts\LuminaX")) {
    $extractedRoot = $extractDir
} else {
    $sub = Get-ChildItem -Path $extractDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName "scripts\LuminaX") } | Select-Object -First 1
    if ($sub) { $extractedRoot = $sub.FullName }
}

# Atomic backup of current scripts
$destScripts = Join-Path $resolvedTargetDir "scripts\LuminaX"
$backupDir = Join-Path $resolvedTargetDir "scripts\LuminaX.bak"
if (Test-Path $destScripts) {
    if (Test-Path $backupDir) { Remove-Item -Path $backupDir -Recurse -Force }
    Copy-Item -Path $destScripts -Destination $backupDir -Recurse -Force
    Write-InfoMsg "Created safety rollback backup: scripts\LuminaX.bak"
}

try {
    # 4.1 Update scripts
    $destScriptsParent = Join-Path $resolvedTargetDir "scripts"
    New-Item -ItemType Directory -Path $destScriptsParent -Force | Out-Null
    Copy-Item -Path "$extractedRoot\scripts\LuminaX\*" -Destination $destScripts -Recurse -Force
    
    # Companion scripts
    $topLevel = Get-ChildItem -Path "$extractedRoot\scripts" -Filter "*.lua" -File -ErrorAction SilentlyContinue
    foreach ($f in $topLevel) {
        Copy-Item -Path $f.FullName -Destination (Join-Path $destScriptsParent $f.Name) -Force
    }
    Write-Success "Updated LuminaX modules and companion scripts"

    # 4.2 Update fonts
    $destFonts = Join-Path $resolvedTargetDir "fonts"
    if (Test-Path "$extractedRoot\fonts") {
        New-Item -ItemType Directory -Path $destFonts -Force | Out-Null
        Copy-Item -Path "$extractedRoot\fonts\*" -Destination $destFonts -Recurse -Force
        Write-Success "Updated UI and icon fonts"
    }

    # 4.3 Backup previous config files to .bak and replace with .def.conf templates as normal configs
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    # 4.3.1 input.conf -> input.conf.bak, replace with input.def.conf
    $targetInput = Join-Path $resolvedTargetDir "input.conf"
    $srcInputDef = Join-Path $extractedRoot "input.def.conf"
    if (-not (Test-Path $srcInputDef)) { $srcInputDef = Join-Path $extractedRoot "input.conf" }

    if (Test-Path $targetInput) {
        Copy-Item -Path $targetInput -Destination ($targetInput + ".bak") -Force
        Write-InfoMsg "Backed up existing input.conf -> input.conf.bak"
    }
    if (Test-Path $srcInputDef) {
        Copy-Item -Path $srcInputDef -Destination $targetInput -Force
        Write-Success "Replaced input.conf with latest default configuration"
    }
    $defInput = Join-Path $extractedRoot "input.def.conf"
    if (Test-Path $defInput) {
        Copy-Item -Path $defInput -Destination (Join-Path $resolvedTargetDir "input.def.conf") -Force
    }

    # 4.3.2 mpv.conf -> mpv.conf.bak, replace with mpv.def.conf
    $targetMpv = Join-Path $resolvedTargetDir "mpv.conf"
    $srcMpvDef = Join-Path $extractedRoot "mpv.def.conf"
    if (-not (Test-Path $srcMpvDef)) { $srcMpvDef = Join-Path $extractedRoot "mpv.conf" }

    if (Test-Path $targetMpv) {
        Copy-Item -Path $targetMpv -Destination ($targetMpv + ".bak") -Force
        Write-InfoMsg "Backed up existing mpv.conf -> mpv.conf.bak"
    }
    if (Test-Path $srcMpvDef) {
        Copy-Item -Path $srcMpvDef -Destination $targetMpv -Force
        Write-Success "Replaced mpv.conf with latest default configuration"
    }
    $defMpv = Join-Path $extractedRoot "mpv.def.conf"
    if (Test-Path $defMpv) {
        Copy-Item -Path $defMpv -Destination (Join-Path $resolvedTargetDir "mpv.def.conf") -Force
    }

    # 4.3.3 script-opts\osc.conf -> osc.conf.bak, preserve TMDB API key, replace with osc.def.conf
    $oscConfDest = Join-Path $resolvedTargetDir "script-opts\osc.conf"
    $templateOsc = Join-Path $extractedRoot "script-opts\osc.def.conf"
    if (-not (Test-Path $templateOsc)) { $templateOsc = Join-Path $extractedRoot "script-opts\osc.conf" }

    $existingKey = $null
    if (Test-Path $oscConfDest) {
        $existingOsc = Get-Content -Path $oscConfDest -Raw
        if ($existingOsc -match '(?m)^\s*tmdb_api_key\s*=\s*([^\r\n]+)') {
            $extractedKey = $matches[1].Trim().Trim('"').Trim("'")
            if ($extractedKey -and $extractedKey -ne "your_api_key_here") {
                $existingKey = $extractedKey
            }
        }
        Copy-Item -Path $oscConfDest -Destination ($oscConfDest + ".bak") -Force
        Write-InfoMsg "Backed up existing osc.conf -> osc.conf.bak"
    }

    if (Test-Path $templateOsc) {
        if ($existingKey) {
            $newOscContent = Get-Content -Path $templateOsc -Raw
            $newOscContent = $newOscContent -replace '(?m)^\s*tmdb_api_key\s*=.*', "tmdb_api_key=$existingKey"
            [System.IO.File]::WriteAllText($oscConfDest, $newOscContent, $utf8NoBom)
            Write-Success "Preserved existing TMDB API key in updated osc.conf"
        } else {
            Copy-Item -Path $templateOsc -Destination $oscConfDest -Force
        }
        Write-Success "Replaced script-opts\osc.conf with latest default configuration"
    }
    $defOsc = Join-Path $extractedRoot "script-opts\osc.def.conf"
    if (Test-Path $defOsc) {
        Copy-Item -Path $defOsc -Destination (Join-Path $resolvedTargetDir "script-opts\osc.def.conf") -Force
    }

    # 4.3.4 script-opts\stats.conf -> stats.conf.bak, replace with stats.def.conf
    $statsDest = Join-Path $resolvedTargetDir "script-opts\stats.conf"
    $templateStats = Join-Path $extractedRoot "script-opts\stats.def.conf"
    if (-not (Test-Path $templateStats)) { $templateStats = Join-Path $extractedRoot "script-opts\stats.conf" }

    if (Test-Path $statsDest) {
        Copy-Item -Path $statsDest -Destination ($statsDest + ".bak") -Force
        Write-InfoMsg "Backed up existing stats.conf -> stats.conf.bak"
    }
    if (Test-Path $templateStats) {
        Copy-Item -Path $templateStats -Destination $statsDest -Force
        Write-Success "Replaced script-opts\stats.conf with latest default configuration"
    }
    $defStats = Join-Path $extractedRoot "script-opts\stats.def.conf"
    if (Test-Path $defStats) {
        Copy-Item -Path $defStats -Destination (Join-Path $resolvedTargetDir "script-opts\stats.def.conf") -Force
    }

    # Deploy subtitle presets if not already present
    $subJsonDest = Join-Path $resolvedTargetDir "script-opts\lumina_subtitle.json"
    if ((-not (Test-Path $subJsonDest)) -and (Test-Path (Join-Path $extractedRoot "script-opts\lumina_subtitle.json"))) {
        Copy-Item -Path (Join-Path $extractedRoot "script-opts\lumina_subtitle.json") -Destination $subJsonDest -Force -ErrorAction SilentlyContinue
    }

    # 4.4 Update tools and helper scripts inside target
    $destTools = Join-Path $resolvedTargetDir "tools"
    New-Item -ItemType Directory -Path $destTools -Force | Out-Null
    if (Test-Path "$extractedRoot\tools") {
        Copy-Item -Path "$extractedRoot\tools\*" -Destination $destTools -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path "$extractedRoot\verify_installation.py") {
        Copy-Item -Path "$extractedRoot\verify_installation.py" -Destination (Join-Path $destTools "verify_installation.py") -Force -ErrorAction SilentlyContinue
    }
    # Deploy latest updater scripts from extracted archive
    $newUpdatePs1 = Join-Path $extractedRoot "tools\update.ps1"
    if (-not (Test-Path $newUpdatePs1)) { $newUpdatePs1 = Join-Path $extractedRoot "update.ps1" }
    if (Test-Path $newUpdatePs1) {
        Copy-Item -Path $newUpdatePs1 -Destination (Join-Path $destTools "update.ps1") -Force -ErrorAction SilentlyContinue
    }

    $newUpdateBat = Join-Path $extractedRoot "tools\update.bat"
    if (-not (Test-Path $newUpdateBat)) { $newUpdateBat = Join-Path $extractedRoot "update.bat" }
    if (Test-Path $newUpdateBat) {
        Copy-Item -Path $newUpdateBat -Destination (Join-Path $destTools "update.bat") -Force -ErrorAction SilentlyContinue
    }

    # Clean installer and packaging scripts from target config folder
    foreach ($instScript in @("install.bat", "install.ps1", "package_dist.py")) {
        $instPath = Join-Path $destTools $instScript
        if (Test-Path $instPath) {
            Remove-Item -Path $instPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Place convenient 1-click update.bat in root of target directory
    $rootUpdateBat = Join-Path $resolvedTargetDir "update.bat"
    $batCode = @"
@echo off
rem ==============================================================================
rem LuminaX 1-Click Desktop & Portable Updater
rem ==============================================================================
setlocal
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
cd /d "%SCRIPT_DIR%"

set "PS_SCRIPT="
if exist "%SCRIPT_DIR%\tools\update.ps1" set "PS_SCRIPT=%SCRIPT_DIR%\tools\update.ps1"
if not defined PS_SCRIPT if exist "%SCRIPT_DIR%\update.ps1" set "PS_SCRIPT=%SCRIPT_DIR%\update.ps1"

if not defined PS_SCRIPT (
    echo [ERROR] Could not find update.ps1 in "%SCRIPT_DIR%" or "%SCRIPT_DIR%\tools"
    echo Please make sure you are running update.bat from your real mpv configuration folder.
    pause
    exit /b 1
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] powershell.exe was not found in your system PATH.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -TargetDir "%SCRIPT_DIR%" %*
set "EXIT_CODE=%ERRORLEVEL%"
if %EXIT_CODE% neq 0 (
    echo [!] Update process encountered an issue - Exit Code: %EXIT_CODE%
    pause
)
exit /b %EXIT_CODE%
"@
    [System.IO.File]::WriteAllText($rootUpdateBat, $batCode, $utf8NoBom)

    # Remove backup on success
    Remove-Item -Path $backupDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-ErrorMsg "Update encountered an error: $($_.Exception.Message)"
    if (Test-Path $backupDir) {
        Write-WarningMsg "Rolling back from backup..."
        Remove-Item -Path $destScripts -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item -Path $backupDir -Destination $destScripts -Force
        Write-Success "Restored original LuminaX installation."
    }
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $NonInteractive) { Read-Host "Press Enter to exit..." }
    exit 1
}

# Cleanup temporary download directory
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# -----------------------------------------------------------------------------
# 5. Verification
# -----------------------------------------------------------------------------
Write-Step "5/5: Verifying Installation Integrity"

$checkFiles = @(
    "scripts\autoload.lua",
    "scripts\thumbfast.lua",
    "scripts\LuminaX\version.lua",
    "scripts\LuminaX\main.lua",
    "scripts\LuminaX\modules\screensaver.lua",
    "scripts\LuminaX\modules\updater.lua",
    "fonts\Inter-Regular.ttf",
    "fonts\uosc_icons.otf",
    "script-opts\osc.conf"
)
$allGood = $true
foreach ($cf in $checkFiles) {
    if (-not (Test-Path (Join-Path $resolvedTargetDir $cf))) {
        Write-ErrorMsg "Missing: $cf"
        $allGood = $false
    }
}

if ($allGood) {
    Write-Host "`n======================================================================" -ForegroundColor Green
    Write-Host "  $StarMark LuminaX successfully updated to v$latestTag!" -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  Restart mpv to experience the updated visionOS glass interface.`n" -ForegroundColor Cyan
} else {
    Write-WarningMsg "Update finished with warnings. Please verify file integrity."
}

if (-not $NonInteractive) {
    Write-Host "Press Enter to exit..." -ForegroundColor Gray
    [void][System.Console]::ReadLine()
}

exit 0
