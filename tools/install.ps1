<#
.SYNOPSIS
    LuminaX Automated PowerShell Installer for Windows
.DESCRIPTION
    Installs LuminaX scripts, visionOS glass theme, and fonts to mpv configuration.
#>

param(
    [string]$TargetDir = ""
)

$ErrorActionPreference = "Stop"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "🌟 LuminaX Windows PowerShell Installer for mpv" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Detect package root whether running from repository (tools\..) or extracted release archive (.)
if (Test-Path "$ScriptDir\scripts\LuminaX") {
    $PackageRoot = (Resolve-Path "$ScriptDir").Path
} elseif (Test-Path "$ScriptDir\..\scripts\LuminaX") {
    $PackageRoot = (Resolve-Path "$ScriptDir\..").Path
} else {
    Write-Error "Cannot find LuminaX source files (scripts\LuminaX). Please run the script from the extracted LuminaX release folder or repository."
    exit 1
}

# 1. Determine mpv config destination
if (-not $TargetDir) {
    if (Test-Path "$PackageRoot\portable_config") {
        $TargetDir = (Resolve-Path "$PackageRoot\portable_config").Path
    } elseif (Test-Path "$PackageRoot\..\portable_config") {
        $TargetDir = (Resolve-Path "$PackageRoot\..\portable_config").Path
    } else {
        $TargetDir = Join-Path $env:APPDATA "mpv"
    }
}

Write-Host "Target MPV Directory: $TargetDir" -ForegroundColor Green

# 2. Ensure directories exist
$dirs = @(
    (Join-Path $TargetDir "scripts\LuminaX\modules"),
    (Join-Path $TargetDir "fonts"),
    (Join-Path $TargetDir "script-opts")
)
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# Check if target is identical to package root
$resolvedTarget = (Resolve-Path $TargetDir).Path

if ($PackageRoot -eq $resolvedTarget) {
    Write-Host "Target directory is identical to source package root; files already in place." -ForegroundColor Yellow
} else {
    # 3. Copy scripts
    Write-Host "Copying LuminaX scripts..."
    Copy-Item -Path "$PackageRoot\scripts\LuminaX\*" -Destination (Join-Path $TargetDir "scripts\LuminaX") -Recurse -Force

    # 4. Copy fonts
    Write-Host "Copying UI and icon fonts to mpv\fonts..."
    Copy-Item -Path "$PackageRoot\fonts\*" -Destination (Join-Path $TargetDir "fonts") -Recurse -Force

    # 5. Configuration (script-opts/osc.conf)
    $oscConfDest = Join-Path $TargetDir "script-opts\osc.conf"
    if (-not (Test-Path $oscConfDest)) {
        Write-Host "Copying script-opts\osc.conf..."
        Copy-Item -Path "$PackageRoot\script-opts\osc.conf" -Destination $oscConfDest -Force
    } else {
        Write-Host "Preserving existing $oscConfDest" -ForegroundColor Yellow
    }
}

# 6. Configure mpv.conf
$mpvConf = Join-Path $TargetDir "mpv.conf"
$linesToAdd = @()
if (-not (Test-Path $mpvConf)) {
    $content = @"
# Disable default mpv OSC for LuminaX
osc=no
osd-bar=no
osd-font="Inter"
"@
    Set-Content -Path $mpvConf -Value $content -Encoding UTF8
    Write-Host "Created $mpvConf with required settings." -ForegroundColor Green
} else {
    $existing = Get-Content -Path $mpvConf -Raw -ErrorAction SilentlyContinue
    if ($existing -notmatch '(?m)^\s*osc\s*=\s*no') {
        Add-Content -Path $mpvConf -Value "`n# Disable stock mpv controls for LuminaX`nosc=no" -Encoding UTF8
        Write-Host "Added osc=no to $mpvConf" -ForegroundColor Green
    }
    if ($existing -notmatch '(?m)^\s*osd-bar\s*=\s*no') {
        Add-Content -Path $mpvConf -Value "osd-bar=no" -Encoding UTF8
        Write-Host "Added osd-bar=no to $mpvConf" -ForegroundColor Green
    }
}

# 7. Configure input.conf
$inputConf = Join-Path $TargetDir "input.conf"
if (-not (Test-Path $inputConf)) {
    $srcInput = Join-Path $PackageRoot "input.conf"
    if (Test-Path $srcInput) {
        Copy-Item -Path $srcInput -Destination $inputConf -Force
        Write-Host "Created $inputConf with LuminaX keybindings." -ForegroundColor Green
    }
} elseif ($PackageRoot -ne $resolvedTarget) {
    $existingInput = Get-Content -Path $inputConf -Raw -ErrorAction SilentlyContinue
    if ($existingInput -notmatch 'LuminaX/menu-playlist' -and $existingInput -notmatch 'menu-playlist') {
        $menuBindings = @"

# LuminaX Interactive Glass Menus & OSD
tab               script-binding LuminaX/visibility
p                 script-binding LuminaX/menu-playlist
c                 script-binding LuminaX/menu-chapters
a                 script-binding LuminaX/menu-audio
s                 script-binding LuminaX/menu-sub
"@
        Add-Content -Path $inputConf -Value $menuBindings -Encoding UTF8
        Write-Host "Added LuminaX menu shortcuts to $inputConf" -ForegroundColor Green
    }
}

# 8. Check binaries
Write-Host "`nEnvironment Check:" -ForegroundColor Cyan
$bins = @("mpv", "ffmpeg", "curl", "mkvpropedit")
foreach ($b in $bins) {
    $cmd = Get-Command $b -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "  ✓ Found $b in PATH: $($cmd.Source)" -ForegroundColor Green
    } else {
        if ($b -eq "mkvpropedit") {
            Write-Host "  ℹ $b not found (Optional: MKV tag writing will use session fallback)" -ForegroundColor Yellow
        } else {
            Write-Host "  ⚠ $b not found in PATH" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n======================================================================" -ForegroundColor Green
Write-Host "🎉 LuminaX successfully installed!" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
Write-Host "1. Edit $oscConfDest to add your TMDB API key."
Write-Host "2. Launch mpv and enjoy the visionOS glass interface!"
