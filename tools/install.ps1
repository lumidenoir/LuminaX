<#
.SYNOPSIS
    LuminaX Automated PowerShell Installer for Windows
.DESCRIPTION
    Installs LuminaX visionOS glass theme, modules, fonts, and configurations for mpv.
    Includes comprehensive auto-detection and fallbacks for mpv and FFmpeg.
#>

[CmdletBinding()]
param(
    [string]$TargetDir = "",
    [string]$MpvPath = "",
    [string]$FFmpegPath = "",
    [switch]$NonInteractive,
    [switch]$AutoCopyFFmpeg = $true,
    [switch]$RegisterUserFonts = $true,
    [switch]$AddToPath
)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # ignore if console does not support setting encoding
}

# Safe character representations
$CheckMark = "$([char]0x2713)"
$CrossMark = "$([char]0x2717)"
$WarnMark  = "$([char]0x26A0)"
$InfoMark  = "$([char]0x2139)"
$StarMark  = "$([char]0x2605)"

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "  $CheckMark $Message" -ForegroundColor Green
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "  $WarnMark $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "  $CrossMark $Message" -ForegroundColor Red
}

function Write-InfoMsg {
    param([string]$Message)
    Write-Host "  $InfoMark $Message" -ForegroundColor Gray
}

function Add-FolderToUserPath {
    param([string]$FolderPath)
    if (-not $FolderPath -or -not (Test-Path $FolderPath)) { return $false }
    $resolved = (Resolve-Path $FolderPath).Path
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", [System.EnvironmentVariableTarget]::User)
    $cleanUserPath = if ($userPath) { $userPath } else { "" }
    $existingItems = $cleanUserPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
    
    foreach ($item in $existingItems) {
        if ($item.Trim().TrimEnd('\') -ieq $resolved.TrimEnd('\')) {
            return $false
        }
    }
    
    $newPath = if ($cleanUserPath.Length -gt 0) { "$cleanUserPath;$resolved" } else { $resolved }
    [System.Environment]::SetEnvironmentVariable("PATH", $newPath, [System.EnvironmentVariableTarget]::User)
    $env:PATH = "$env:PATH;$resolved"
    return $true
}

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  $StarMark LuminaX Automated Windows Installer for mpv" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Resolve Package Root
# -----------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (Test-Path (Join-Path $ScriptDir "scripts\LuminaX")) {
    $PackageRoot = (Resolve-Path $ScriptDir).Path
} elseif (Test-Path (Join-Path $ScriptDir "..\scripts\LuminaX")) {
    $PackageRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
} else {
    Write-ErrorMsg "Cannot locate LuminaX source files (scripts\LuminaX)."
    Write-Host "Please ensure you run this installer from within the LuminaX folder or git repository." -ForegroundColor Yellow
    exit 1
}

Write-InfoMsg "LuminaX Source Package: $PackageRoot"

# -----------------------------------------------------------------------------
# 2. Locate MPV Installation & Determine Target Directory
# -----------------------------------------------------------------------------
Write-Step "1/5: Detecting mpv Installation"

$discoveredMpvExe = $null

if ($MpvPath -and (Test-Path $MpvPath)) {
    if (Test-Path (Join-Path $MpvPath "mpv.exe")) {
        $discoveredMpvExe = (Resolve-Path (Join-Path $MpvPath "mpv.exe")).Path
    } else {
        $discoveredMpvExe = (Resolve-Path $MpvPath).Path
    }
}

if (-not $discoveredMpvExe) {
    # Check running process
    $proc = Get-Process mpv -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -First 1
    if ($proc -and (Test-Path $proc)) {
        $discoveredMpvExe = $proc
    }
}

if (-not $discoveredMpvExe) {
    # Check PATH
    $cmd = Get-Command "mpv.exe" -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path $cmd.Source)) {
        $discoveredMpvExe = $cmd.Source
    }
}

if (-not $discoveredMpvExe) {
    # Check parent/sibling directories
    $localCandidates = @(
        (Join-Path $PackageRoot "mpv.exe"),
        (Join-Path $PackageRoot "..\mpv.exe")
    )
    foreach ($cand in $localCandidates) {
        if (Test-Path $cand) {
            $discoveredMpvExe = (Resolve-Path $cand).Path
            break
        }
    }
}

if (-not $discoveredMpvExe) {
    # Check common locations & Downloads directory
    $searchRoots = @(
        (Join-Path $env:USERPROFILE "Downloads"),
        "C:\mpv",
        "C:\tools\mpv",
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"),
        (Join-Path $env:USERPROFILE "scoop\apps\mpv\current")
    )
    foreach ($root in $searchRoots) {
        if (Test-Path $root) {
            if (Test-Path (Join-Path $root "mpv.exe")) {
                $discoveredMpvExe = (Resolve-Path (Join-Path $root "mpv.exe")).Path
                break
            }
            # Search one level of subdirectories (e.g. Downloads\mpv-x86_64-*)
            $found = Get-ChildItem -Path $root -Filter "mpv.exe" -Recurse -Depth 2 -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $discoveredMpvExe = $found.FullName
                break
            }
        }
    }
}

# Determine target directory
$resolvedTargetDir = $null

if ($TargetDir) {
    $resolvedTargetDir = [System.IO.Path]::GetFullPath($TargetDir)
} elseif ($discoveredMpvExe) {
    $mpvFolder = Split-Path -Parent $discoveredMpvExe
    $portableConfig = Join-Path $mpvFolder "portable_config"
    Write-Success "Found mpv executable: $discoveredMpvExe"

    if (Test-Path $portableConfig) {
        $resolvedTargetDir = $portableConfig
        Write-InfoMsg "Using existing portable config: $resolvedTargetDir"
    } else {
        # Check if user already has an %APPDATA%\mpv configuration
        $appDataMpv = Join-Path $env:APPDATA "mpv"
        if (Test-Path $appDataMpv) {
            # Both exist: ask user or default to portable
            if ($NonInteractive) {
                $resolvedTargetDir = $portableConfig
            } else {
                Write-Host "`n  Where would you like to install LuminaX?" -ForegroundColor Cyan
                Write-Host "    [1] Portable config inside mpv folder (Recommended for portable mpv):"
                Write-Host "        $portableConfig" -ForegroundColor Green
                Write-Host "    [2] User profile config:"
                Write-Host "        $appDataMpv" -ForegroundColor Gray
                $choice = Read-Host "  Enter choice [1/2] (Default: 1)"
                if ($choice.Trim() -eq "2") {
                    $resolvedTargetDir = $appDataMpv
                } else {
                    $resolvedTargetDir = $portableConfig
                }
            }
        } else {
            $resolvedTargetDir = $portableConfig
            Write-InfoMsg "Configuring portable mode at: $resolvedTargetDir"
        }
    }
} else {
    $resolvedTargetDir = Join-Path $env:APPDATA "mpv"
    Write-InfoMsg "mpv.exe not found in PATH or standard folders. Defaulting to: $resolvedTargetDir"
}

Write-Success "Target mpv configuration directory: $resolvedTargetDir"

# Ensure target directories exist
$subDirs = @(
    (Join-Path $resolvedTargetDir "scripts\LuminaX\modules"),
    (Join-Path $resolvedTargetDir "fonts"),
    (Join-Path $resolvedTargetDir "script-opts")
)
foreach ($d in $subDirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# -----------------------------------------------------------------------------
# 3. Detect and Configure FFmpeg
# -----------------------------------------------------------------------------
Write-Step "2/5: Detecting & Configuring FFmpeg (Native Logo & Hardware Overlay Engine)"

$discoveredFFmpeg = $null

if ($FFmpegPath -and (Test-Path $FFmpegPath)) {
    if (Test-Path (Join-Path $FFmpegPath "ffmpeg.exe")) {
        $discoveredFFmpeg = (Resolve-Path (Join-Path $FFmpegPath "ffmpeg.exe")).Path
    } else {
        $discoveredFFmpeg = (Resolve-Path $FFmpegPath).Path
    }
}

# Check PATH
if (-not $discoveredFFmpeg) {
    $cmd = Get-Command "ffmpeg.exe" -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path $cmd.Source)) {
        $discoveredFFmpeg = $cmd.Source
    }
}

# Check if ffmpeg is in the mpv directory (mpv can natively invoke it on Windows)
if (-not $discoveredFFmpeg -and $discoveredMpvExe) {
    $mpvFolder = Split-Path -Parent $discoveredMpvExe
    $localFFmpeg = Join-Path $mpvFolder "ffmpeg.exe"
    if (Test-Path $localFFmpeg) {
        $discoveredFFmpeg = (Resolve-Path $localFFmpeg).Path
    }
}

# Check common portable/download locations
if (-not $discoveredFFmpeg) {
    $ffmpegSearchRoots = @(
        (Join-Path $env:USERPROFILE "Downloads"),
        "C:\ffmpeg",
        "C:\Program Files\ffmpeg",
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"),
        (Join-Path $env:USERPROFILE "scoop\shims")
    )
    foreach ($root in $ffmpegSearchRoots) {
        if (Test-Path $root) {
            $found = Get-ChildItem -Path $root -Filter "ffmpeg.exe" -Recurse -Depth 3 -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $discoveredFFmpeg = $found.FullName
                break
            }
        }
    }
}

if ($discoveredFFmpeg) {
    Write-Success "Found FFmpeg at: $discoveredFFmpeg"

    # If mpv is portable and ffmpeg is elsewhere, offer to copy ffmpeg.exe to the mpv folder
    if ($discoveredMpvExe) {
        $mpvFolder = Split-Path -Parent $discoveredMpvExe
        $mpvFFmpeg = Join-Path $mpvFolder "ffmpeg.exe"
        if (-not (Test-Path $mpvFFmpeg) -and ($discoveredFFmpeg -ne $mpvFFmpeg)) {
            $shouldCopy = $AutoCopyFFmpeg
            if (-not $NonInteractive -and -not $AutoCopyFFmpeg) {
                $copyPrompt = Read-Host "  Copy ffmpeg.exe into your mpv directory for zero-config native playback? [Y/n]"
                $shouldCopy = ($copyPrompt.Trim() -ne "n" -and $copyPrompt.Trim() -ne "N")
            }
            if ($shouldCopy) {
                try {
                    Copy-Item -Path $discoveredFFmpeg -Destination $mpvFFmpeg -Force
                    Write-Success "Linked FFmpeg to mpv folder: $mpvFFmpeg"
                } catch {
                    Write-WarningMsg "Could not copy ffmpeg.exe to mpv directory: $($_.Exception.Message)"
                }
            }
        }
    }
} else {
    Write-WarningMsg "ffmpeg.exe was not detected in PATH, mpv directory, or Downloads."
    Write-Host "    LuminaX screensaver uses FFmpeg for zero-dependency high-speed Lanczos logo scaling." -ForegroundColor Gray

    # Check if winget is available for 1-click install
    $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if ($winget -and -not $NonInteractive) {
        Write-Host "`n  Would you like to install FFmpeg automatically using winget?" -ForegroundColor Cyan
        $installChoice = Read-Host "  Install Gyan.FFmpeg via winget now? [Y/n]"
        if ($installChoice.Trim() -ne "n" -and $installChoice.Trim() -ne "N") {
            Write-Host "  Running 'winget install Gyan.FFmpeg'..." -ForegroundColor Cyan
            try {
                Start-Process -FilePath "winget.exe" -ArgumentList "install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements" -NoNewWindow -Wait
                $cmdNew = Get-Command "ffmpeg.exe" -ErrorAction SilentlyContinue
                if ($cmdNew) {
                    Write-Success "FFmpeg successfully installed via winget!"
                } else {
                    Write-InfoMsg "FFmpeg installed. Please restart your terminal/mpv after setup to refresh PATH."
                }
            } catch {
                Write-WarningMsg "winget installation failed: $($_.Exception.Message)"
            }
        }
    } else {
        Write-InfoMsg "To enable movie logos, download FFmpeg from: https://www.gyan.dev/ffmpeg/builds/"
        Write-InfoMsg "and place ffmpeg.exe directly into your mpv directory."
    }
}

# Check curl
$curlBin = Get-Command "curl.exe" -ErrorAction SilentlyContinue
if ($curlBin) {
    Write-Success "Found curl: $($curlBin.Source)"
} else {
    Write-WarningMsg "curl.exe not found in Windows system PATH. TMDB cloud queries may fail."
}

# Optional: Add mpv & FFmpeg directory to Windows User PATH
if ($discoveredMpvExe) {
    $mpvFolder = Split-Path -Parent $discoveredMpvExe
    $isInPath = $false
    $allPaths = ($env:PATH).Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
    foreach ($p in $allPaths) {
        if ($p.Trim().TrimEnd('\') -ieq $mpvFolder.TrimEnd('\')) {
            $isInPath = $true
            break
        }
    }
    if ($isInPath) {
        Write-Success "mpv directory is in PATH: $mpvFolder"
    } else {
        $shouldAdd = $AddToPath
        if (-not $NonInteractive -and -not $AddToPath) {
            Write-Host "`n  Would you like to add your mpv directory to Windows User PATH?" -ForegroundColor Cyan
            Write-Host "  (Enables running 'mpv' and 'ffmpeg' from any Command Prompt or PowerShell terminal)" -ForegroundColor Gray
            $pathPrompt = Read-Host "  Add $mpvFolder to User PATH? [Y/n]"
            $shouldAdd = ($pathPrompt.Trim() -ne "n" -and $pathPrompt.Trim() -ne "N")
        }
        if ($shouldAdd) {
            $added = Add-FolderToUserPath -FolderPath $mpvFolder
            if ($added) {
                Write-Success "Added to Windows User PATH: $mpvFolder"
            }
        } else {
            Write-InfoMsg "PATH unchanged (mpv will run from its portable folder)."
        }
    }
}

# -----------------------------------------------------------------------------
# 4. Deploy LuminaX Scripts & Fonts
# -----------------------------------------------------------------------------
Write-Step "3/5: Deploying LuminaX Modules & UI Fonts"

# Copy scripts
$scriptsBaseDir = Join-Path $resolvedTargetDir "scripts"
if (-not (Test-Path $scriptsBaseDir)) {
    New-Item -ItemType Directory -Path $scriptsBaseDir -Force | Out-Null
}

# Copy companion scripts (autoload.lua, thumbfast.lua) directly to scripts/
$topLevelScripts = Get-ChildItem -Path "$PackageRoot\scripts" -Filter "*.lua" -File
foreach ($s in $topLevelScripts) {
    Copy-Item -Path $s.FullName -Destination (Join-Path $scriptsBaseDir $s.Name) -Force
    Write-Host "  Copied helper script: $($s.Name)" -ForegroundColor DarkGray
}

$destScripts = Join-Path $scriptsBaseDir "LuminaX"
Write-Host "  Copying LuminaX modules..."
Copy-Item -Path "$PackageRoot\scripts\LuminaX\*" -Destination $destScripts -Recurse -Force
Write-Success "Installed scripts to: $scriptsBaseDir"

# Copy fonts to mpv/fonts
$destFonts = Join-Path $resolvedTargetDir "fonts"
Write-Host "  Copying fonts to mpv fonts directory..."
Copy-Item -Path "$PackageRoot\fonts\*" -Destination $destFonts -Recurse -Force
Write-Success "Installed fonts to: $destFonts"

# Optional: Register fonts in Windows User Fonts (prevents missing glyph boxes [] in libass)
if ($RegisterUserFonts) {
    try {
        $userFontDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
        if (-not (Test-Path $userFontDir)) {
            New-Item -ItemType Directory -Path $userFontDir -Force | Out-Null
        }
        $fontFiles = Get-ChildItem -Path "$PackageRoot\fonts" -Include "*.ttf", "*.otf" -File
        $regKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
        foreach ($ff in $fontFiles) {
            $destFontPath = Join-Path $userFontDir $ff.Name
            Copy-Item -Path $ff.FullName -Destination $destFontPath -Force
            # Add registry key
            $valName = "$($ff.BaseName) (TrueType)"
            Set-ItemProperty -Path $regKey -Name $valName -Value $destFontPath -ErrorAction SilentlyContinue
        }
        Write-Success "Registered UI fonts in Windows User Font Registry"
    } catch {
        Write-InfoMsg "User font registration skipped (fonts are still available to mpv locally)."
    }
}

# -----------------------------------------------------------------------------
# 5. Configure mpv.conf, input.conf, and osc.conf
# -----------------------------------------------------------------------------
Write-Step "4/5: Configuring mpv & Glass Controls"

# 5.1 script-opts/osc.conf (Preserve existing TMDB API key if set)
$oscConfDest = Join-Path $resolvedTargetDir "script-opts\osc.conf"
$srcOscConf = $null
foreach ($cand in @((Join-Path $PackageRoot "script-opts\osc.conf"), (Join-Path $PackageRoot "script-opts\osc.def.conf"))) {
    if (Test-Path $cand) {
        $srcOscConf = $cand
        break
    }
}
$existingKey = $null

if (Test-Path $oscConfDest) {
    $existingContent = Get-Content -Path $oscConfDest -Raw -ErrorAction SilentlyContinue
    if ($existingContent -match '(?m)^\s*tmdb_api_key\s*=\s*([^\r\n]+)') {
        $extracted = $matches[1].Trim().Trim('"').Trim("'")
        if ($extracted -and $extracted -ne "your_api_key_here" -and $extracted -ne "your_32_character_api_key_here") {
            $existingKey = $extracted
        }
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if ($srcOscConf -and (Test-Path $srcOscConf)) {
    if ($existingKey) {
        $newContent = Get-Content -Path $srcOscConf -Raw
        $newContent = $newContent -replace '(?m)^\s*tmdb_api_key\s*=.*', "tmdb_api_key=$existingKey"
        [System.IO.File]::WriteAllText($oscConfDest, $newContent, $utf8NoBom)
        Write-Success "Preserved existing TMDB API key in script-opts\osc.conf"
    } elseif (-not (Test-Path $oscConfDest)) {
        Copy-Item -Path $srcOscConf -Destination $oscConfDest -Force
        Write-Success "Created script-opts\osc.conf"
    } else {
        Write-InfoMsg "Preserving existing $oscConfDest"
    }
}

# Optional: script-opts/stats.conf
$srcStatsConf = $null
foreach ($cand in @((Join-Path $PackageRoot "script-opts\stats.conf"), (Join-Path $PackageRoot "script-opts\stats.def.conf"))) {
    if (Test-Path $cand) {
        $srcStatsConf = $cand
        break
    }
}
$statsConfDest = Join-Path $resolvedTargetDir "script-opts\stats.conf"
if ($srcStatsConf -and (-not (Test-Path $statsConfDest))) {
    Copy-Item -Path $srcStatsConf -Destination $statsConfDest -Force
    Write-Success "Created script-opts\stats.conf"
}

# 5.2 mpv.conf (Disable default mpv OSC to prevent dual-controller collision)
$mpvConf = Join-Path $resolvedTargetDir "mpv.conf"
$srcMpv = $null
foreach ($cand in @((Join-Path $PackageRoot "mpv.conf"), (Join-Path $PackageRoot "mpv.def.conf"))) {
    if (Test-Path $cand) {
        $srcMpv = $cand
        break
    }
}

if (-not (Test-Path $mpvConf)) {
    if ($srcMpv) {
        Copy-Item -Path $srcMpv -Destination $mpvConf -Force
        Write-Success "Created mpv.conf from reference template"
    } else {
        $mpvDefaults = @"
# ==============================================================================
# LuminaX mpv Configuration
# ==============================================================================
osc=no
osd-bar=no
osd-font="Inter"
audio-fallback-to-null=yes
autofit-larger=85%x85%
geometry=50%:50%
"@
        [System.IO.File]::WriteAllText($mpvConf, $mpvDefaults, $utf8NoBom)
        Write-Success "Created mpv.conf with LuminaX settings"
    }
}

$existingMpv = Get-Content -Path $mpvConf -Raw -ErrorAction SilentlyContinue
$appendLines = @()
if ($existingMpv -notmatch '(?m)^\s*osc\s*=\s*no') {
    $appendLines += "`n# Disable stock mpv controls for LuminaX`nosc=no"
}
if ($existingMpv -notmatch '(?m)^\s*osd-bar\s*=\s*no') {
    $appendLines += "osd-bar=no"
}
if ($existingMpv -notmatch '(?m)^\s*osd-font\s*=') {
    $appendLines += 'osd-font="Inter"'
}
if ($existingMpv -notmatch '(?m)^\s*audio-fallback-to-null\s*=') {
    $appendLines += 'audio-fallback-to-null=yes'
}
if ($appendLines.Count -gt 0) {
    [System.IO.File]::AppendAllText($mpvConf, "`n" + ($appendLines -join "`n"), $utf8NoBom)
    Write-Success "Configured osc=no, osd-bar=no, and osd-font in $mpvConf"
} else {
    Write-Success "mpv.conf is properly configured (osc=no, osd-bar=no present)"
}

# 5.3 input.conf (Interactive Glass Menu Keybindings)
$inputConf = Join-Path $resolvedTargetDir "input.conf"
$srcInput = $null
foreach ($cand in @((Join-Path $PackageRoot "input.conf"), (Join-Path $PackageRoot "input.def.conf"))) {
    if (Test-Path $cand) {
        $srcInput = $cand
        break
    }
}

$menuBindings = @"

# ==============================================================================
# LuminaX Interactive Glass Menus & Keybindings
# ==============================================================================
tab               script-binding LuminaX/visibility
p                 script-binding LuminaX/menu-playlist
c                 script-binding LuminaX/menu-chapters
a                 script-binding LuminaX/menu-audio
s                 script-binding LuminaX/menu-sub
t                 script-binding LuminaX/tag-editor
"@

if (-not (Test-Path $inputConf)) {
    if ($srcInput) {
        Copy-Item -Path $srcInput -Destination $inputConf -Force
    } else {
        [System.IO.File]::WriteAllText($inputConf, $menuBindings.TrimStart(), $utf8NoBom)
    }
    Write-Success "Created input.conf with LuminaX keybindings"
} else {
    $existingInput = Get-Content -Path $inputConf -Raw -ErrorAction SilentlyContinue
    if ($existingInput -notmatch 'LuminaX/menu-playlist' -and $existingInput -notmatch 'menu-playlist') {
        [System.IO.File]::AppendAllText($inputConf, "`n" + $menuBindings, $utf8NoBom)
        Write-Success "Added LuminaX menu shortcuts (Tab, p, c, a, s, t) to input.conf"
    } else {
        Write-Success "input.conf already contains LuminaX shortcuts"
    }
}

# -----------------------------------------------------------------------------
# 6. Verification & Health Diagnostic Check
# -----------------------------------------------------------------------------
Write-Step "5/5: Running System Health & Installation Verification"

$verifyFiles = @(
    "scripts\autoload.lua",
    "scripts\thumbfast.lua",
    "scripts\LuminaX\main.lua",
    "scripts\LuminaX\modules\utils.lua",
    "scripts\LuminaX\modules\osc.lua",
    "scripts\LuminaX\modules\huds.lua",
    "scripts\LuminaX\modules\menu.lua",
    "scripts\LuminaX\modules\screensaver.lua",
    "scripts\LuminaX\modules\tag_editor.lua",
    "fonts\Inter-Regular.ttf",
    "fonts\uosc_icons.otf",
    "script-opts\osc.conf",
    "mpv.conf"
)

$allOk = $true
foreach ($vf in $verifyFiles) {
    $fullPath = Join-Path $resolvedTargetDir $vf
    if (Test-Path $fullPath) {
        $size = (Get-Item $fullPath).Length
        Write-Host "  $CheckMark $($vf.PadRight(35)) ($('{0:N0}' -f $size) bytes)" -ForegroundColor Green
    } else {
        Write-Host "  $CrossMark $($vf.PadRight(35)) MISSING!" -ForegroundColor Red
        $allOk = $false
    }
}

# Test TMDB cloud reachability via curl
$curlOk = $false
if ($curlBin) {
    try {
        $res = & $curlBin.Source -I -s --connect-timeout 4 "https://api.themoviedb.org" 2>&1
        if ($res -match "HTTP/" -or $res -match "200" -or $res -match "401" -or $res -match "301") {
            $curlOk = $true
            Write-Success "Successfully connected to TMDB API cloud (api.themoviedb.org)"
        }
    } catch {
        # ignore network probe error
    }
}

if (-not $curlOk) {
    Write-InfoMsg "TMDB cloud check skipped or unreachable (Ambient offline cards will be used)."
}

Write-Host "`n======================================================================" -ForegroundColor Green
if ($allOk) {
    Write-Host "  $StarMark LuminaX has been successfully installed and verified!" -ForegroundColor Green
} else {
    Write-Host "  $WarnMark LuminaX installation completed with warnings." -ForegroundColor Yellow
}
Write-Host "======================================================================" -ForegroundColor Green

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  1. Add your free TMDB API key to enable high-resolution movie logos:"
Write-Host "     $oscConfDest" -ForegroundColor White
Write-Host "  2. Play any video in mpv to experience the visionOS glass interface!"
Write-Host "  3. Keybindings: [Space] Pause screensaver | [Tab] Toggle controls | [p] Playlist | [c] Chapters`n"

if (-not $NonInteractive) {
    Write-Host "Press Enter to exit..." -ForegroundColor Gray
    [void][System.Console]::ReadLine()
}
