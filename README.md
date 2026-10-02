# LuminaX for mpv

LuminaX is an interface and screensaver script for mpv. It replaces the stock on-screen controller with rounded floating menus, timeline controls, interactive drawers for video, audio, and subtitles, and a pause screensaver that fetches metadata and logos from The Movie Database (TMDB).

Written in Lua with native FFmpeg integration. Requires no external Python runtime or pip dependencies.

---

## Features

* **Rounded Controller:** Floating bottom control bar with smooth timeline scrubbing, hover-expanding volume slider, and dynamic media format badges.
* **Pause Screensaver:** When paused, automatically fetches and displays official titles or logos, plot synopsis, release year, genres, ratings, and estimated finish time.
* **Video Picture Tuning Drawer (`V`):** Quick-access drawer for contrast, brightness, gamma, saturation, hue, zoom, debanding, and aspect ratio with a one-click reset to neutral values.
* **Audio Enhancements & Night Mode (`a`):** Track switcher with built-in Night Mode (dynamic dialogue normalization) and audio delay stepper.
* **Subtitle Studio (`Alt+s`):** Styling drawer docked to the screen edge with a live preview capsule, font size, colors, borders, shadows, and sync delay controls.
* **Tag Editor & Title Cleaner (`T`):** Strips release group tags, tracker watermarks, and resolution text from media filenames to ensure accurate TMDB matching.
* **Notification HUDs:** Capsule-style overlays for volume adjustments, seeking, subtitle and audio delays, and screenshots.
* **In-Player Updates (`U`):** Automatic background update checks every 3 days. Completely silent during playback when up to date. Provides one-click update installation when a new version is available.

---

## Installation

LuminaX release archives contain the required scripts, fonts, and configuration templates. Download the appropriate archive for your operating system from GitHub Releases:

* Linux: `luminaX-linux.tar.gz`
* macOS: `luminaX-macos.tar.gz`
* Windows: `luminaX-windows.zip`

### Automated Installation

1. Extract the downloaded archive.
2. Open a terminal or shell inside the extracted folder:

* **Linux & macOS:**
  ```bash
  bash tools/install.sh
  ```
  *(Or run `./install.sh` from the extracted directory)*

* **Windows:**
  Right-click `tools\install.bat` and select **Run as administrator** (or run `tools\install.ps1` in PowerShell):
  ```powershell
  powershell -ExecutionPolicy Bypass -File tools\install.ps1
  ```

The installer copies scripts, fonts, and options to your mpv configuration directory, enables required settings in `mpv.conf`, and registers default keybindings.

---

### Manual Installation

If you prefer to install files manually, place the extracted components into your mpv configuration folder:

* **Linux:** `~/.config/mpv/`
* **macOS:** `~/.config/mpv/` or `~/Library/Application Support/mpv/`
* **Windows (Standard):** `%APPDATA%\mpv\`
* **Windows (Portable):** `mpv\portable_config\`

#### Directory Layout

```
mpv/
├── mpv.conf
├── input.conf
├── fonts/
│   ├── Inter-Bold.ttf
│   ├── Inter-Medium.ttf
│   ├── Inter-Regular.ttf
│   ├── Inter-SemiBold.ttf
│   └── uosc_icons.otf
├── script-opts/
│   ├── osc.conf
│   ├── osc.def.conf
│   ├── stats.conf
│   ├── stats.def.conf
│   └── lumina_subtitle.json
├── scripts/
│   ├── autoload.lua
│   ├── thumbfast.lua
│   └── LuminaX/
│       ├── main.lua
│       ├── version.lua
│       └── modules/
│           ├── huds.lua
│           ├── menu.lua
│           ├── osc.lua
│           ├── screensaver.lua
│           ├── subtitle.lua
│           ├── tag_editor.lua
│           ├── updater.lua
│           └── utils.lua
└── tools/
    ├── install.sh
    ├── install.ps1
    ├── update.sh
    ├── update.ps1
    └── verify_installation.py
```

#### Required `mpv.conf` Settings

Disable mpv's default controller to avoid overlapping interfaces:

```ini
osc=no
osd-bar=no
osd-font="Inter"
```

---

## Configuration & TMDB API Setup

LuminaX configuration is stored in `script-opts/osc.conf`.

### Adding a TMDB API Key

To enable logos, plot synopses, and metadata in the pause screensaver:

1. Create a free account at [themoviedb.org](https://www.themoviedb.org/signup).
2. Navigate to **Settings -> API** and request a free Developer API key.
3. Open `script-opts/osc.conf` in a text editor and enter your key:
   ```ini
   tmdb_api_key=your_api_key_here
   screensaver_enabled=yes
   screensaver_delay=5
   screensaver_align=center
   ```
4. Save the file.

### Reference Configuration Files

LuminaX provides reference definition files containing documentation and defaults for all available settings:

* `script-opts/osc.def.conf`: Controller and screensaver options
* `script-opts/stats.def.conf`: Hardware stats options
* `input.def.conf`: Default keybindings reference
* `mpv.def.conf`: Recommended player profiles

---

## Keybindings

| Key | Action |
| :--- | :--- |
| `Tab` | Toggle controller visibility (auto / always / never) |
| `Space` | Play / Pause (activates screensaver after pause delay) |
| `Left` / `Right` | Seek backward / forward 10 seconds |
| `Shift + Left` / `Shift + Right` | Seek exact 1 second |
| `Up` / `Down` | Volume up / down 5% |
| `m` | Toggle mute |
| `p` | Open Playlist menu (with live search filter) |
| `c` | Open Chapters menu |
| `a` | Open Audio Tracks drawer (Night Mode & audio sync) |
| `s` | Open Subtitle selection menu |
| `Alt + s` | Open Subtitle Studio (real-time styling & position) |
| `v` | Toggle subtitle visibility |
| `V` | Open Video Picture Tuning drawer |
| `T` / `Ctrl + t` | Open Tag Editor & Title Cleaner |
| `z` / `Z` | Adjust subtitle delay (-100ms / +100ms) |
| `Ctrl + Shift + Left` / `Right` | Adjust audio delay (-100ms / +100ms) |
| `U` | Check for updates / Install pending update |
| `i` | Toggle hardware and codec statistics |
| `h` | Toggle frame timeline graph |
| `S` | Take screenshot with subtitles |
| `Ctrl + s` | Take raw video screenshot without subtitles |
| `Esc` | Close open menu / Dismiss screensaver |

---

## Updates

LuminaX includes an automated updater that preserves your existing configurations and TMDB key.

* **Automatic Check:** Checks GitHub releases once every 3 days in the background. If you are up to date, it remains silent. If a new version is detected, an update button appears on the control bar and a notification pill is shown.
* **Manual Trigger:** Press `U` at any time to check for updates manually or apply a pending update.
* **Offline / Script Trigger:** Run `tools/update.sh` (Linux/macOS) or `tools/update.ps1` (Windows) directly from your terminal.

---

## Frequently Asked Questions & Troubleshooting

### Two controllers are showing on screen at the same time
* **Cause:** The default mpv controller is still enabled.
* **Solution:** Add `osc=no` and `osd-bar=no` to your `mpv.conf` file, then restart mpv.

### Buttons show empty boxes or question marks
* **Cause:** The icon font `uosc_icons.otf` is missing or not indexed.
* **Solution:** Verify that `fonts/uosc_icons.otf` is present inside your mpv `fonts/` folder. On Windows, you can also double-click `uosc_icons.otf` and click "Install".

### The screensaver shows text but no official movie logo
* **Cause 1:** The media title does not have an official logo uploaded to TMDB in English. LuminaX automatically falls back to formatted typography.
* **Cause 2:** `ffmpeg` is not accessible in your system PATH.
* **Solution:** Verify that running `ffmpeg -version` in your terminal succeeds. If not, install FFmpeg or place `ffmpeg.exe` in your mpv directory.

### Screensaver shows "Offline Ambient Card" and no movie metadata
* **Cause:** The TMDB API key is missing or invalid, or outbound HTTP requests are blocked.
* **Solution:**
  1. Check `script-opts/osc.conf` and confirm that `tmdb_api_key` has your 32-character key without quotes.
  2. Confirm your system can reach TMDB by running: `curl -I https://api.themoviedb.org`

### Film title has tracker noise (e.g. `Movie.2024.1080p.WEBRip.x264-[Group]`)
* **Solution:** Press `T` during playback. Select "Clean All Junk Watermarks" to automatically strip common tags, or select "Edit Movie Title" to type the correct title. LuminaX will refresh metadata immediately.

### Will updating overwrite my customized settings or API key?
* **Answer:** No. The update script checks your existing `osc.conf`, preserves all modified values (including your TMDB key), and only appends newly introduced default settings. User keybindings in `input.conf` and video options in `mpv.conf` are left untouched.

---

## Verification

To verify that your installation has all required modules, fonts, and configurations in place, run the verification script from your terminal:

```bash
python3 tools/verify_installation.py
```
