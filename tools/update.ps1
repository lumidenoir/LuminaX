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

    # 4.3 Preserve & Merge script-opts\osc.conf (Zero-Clobber Guarantee)
    $oscConfDest = Join-Path $resolvedTargetDir "script-opts\osc.conf"
    $templateOsc = Join-Path $extractedRoot "script-opts\osc.conf"
    if (-not (Test-Path $templateOsc)) { $templateOsc = Join-Path $extractedRoot "script-opts\osc.def.conf" }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if (Test-Path $oscConfDest) {
        $existingOsc = Get-Content -Path $oscConfDest -Raw
        $existingKey = $null
        if ($existingOsc -match '(?m)^\s*tmdb_api_key\s*=\s*([^\r\n]+)') {
            $extractedKey = $matches[1].Trim().Trim('"').Trim("'")
            if ($extractedKey -and $extractedKey -ne "your_api_key_here") {
                $existingKey = $extractedKey
            }
        }

        # Check for new settings in template (e.g. tmdb_cache_max_mb)
        if (Test-Path $templateOsc) {
            $newSettings = @()
            $templateLines = Get-Content -Path $templateOsc
            foreach ($line in $templateLines) {
                if ($line -match '^\s*([a-zA-Z0-9_\-]+)\s*=') {
                    $settingName = $matches[1]
                    if ($existingOsc -notmatch "(?m)^\s*$settingName\s*=") {
                        $newSettings += $line
                    }
                }
            }
            if ($newSettings.Count -gt 0) {
                $appendBlock = "`n# Newly added settings from v$latestTag`n" + ($newSettings -join "`n")
                [System.IO.File]::AppendAllText($oscConfDest, $appendBlock, $utf8NoBom)
                Write-Success "Merged $($newSettings.Count) new settings into script-opts\osc.conf"
            }
        }
        if ($existingKey) {
            Write-Success "Preserved existing TMDB API key in osc.conf"
        }
    } elseif (Test-Path $templateOsc) {
        Copy-Item -Path $templateOsc -Destination $oscConfDest -Force
        Write-Success "Created script-opts\osc.conf from template"
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
    Copy-Item -Path $PSCommandPath -Destination (Join-Path $destTools "update.ps1") -Force -ErrorAction SilentlyContinue

    # Deploy reference configs & stats.conf if missing
    foreach ($defConf in @("osc.def.conf", "stats.def.conf")) {
        $srcDef = Join-Path $extractedRoot "script-opts\$defConf"
        if (Test-Path $srcDef) {
            Copy-Item -Path $srcDef -Destination (Join-Path $resolvedTargetDir "script-opts\$defConf") -Force -ErrorAction SilentlyContinue
        }
    }
    $statsDest = Join-Path $resolvedTargetDir "script-opts\stats.conf"
    if (-not (Test-Path $statsDest)) {
        $srcStats = Join-Path $extractedRoot "script-opts\stats.conf"
        if (-not (Test-Path $srcStats)) { $srcStats = Join-Path $extractedRoot "script-opts\stats.def.conf" }
        if (Test-Path $srcStats) {
            Copy-Item -Path $srcStats -Destination $statsDest -Force -ErrorAction SilentlyContinue
        }
    }
    $subJsonDest = Join-Path $resolvedTargetDir "script-opts\lumina_subtitle.json"
    if (-not (Test-Path $subJsonDest)) {
        $srcSub = Join-Path $extractedRoot "script-opts\lumina_subtitle.json"
        if (Test-Path $srcSub) {
            Copy-Item -Path $srcSub -Destination $subJsonDest -Force -ErrorAction SilentlyContinue
        }
    }

    # Place convenient 1-click update.bat in root of target directory
    $rootUpdateBat = Join-Path $resolvedTargetDir "update.bat"
    $batCode = @"
@echo off
rem LuminaX 1-Click Desktop & Portable Updater
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; & '%~dp0tools\update.ps1' -TargetDir '%~dp0' %* }"
pause
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
