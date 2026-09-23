# 🌟 LuminaX for mpv

**LuminaX** transforms **mpv** into a modern media player. It features translucent floating glass controls, interactive menus, and an Infuse/Apple TV-grade pause screensaver with real-time movie logos, metadata cards, and finish times.

Unlike older mpv scripts, **LuminaX requires ZERO external language dependencies—no Python, no Pillow, and no pip installs are needed.** It runs with 100% native hardware-accelerated FFmpeg.

---

## 📸 Key Features

* **Frosted VisionOS Glass Interface:** Translucent blurred controls with specular highlights, hover-expanding volume slider, and fluid micro-animations.
* **Infuse / Apple TV Cinema Screensaver:** Triggers when paused, displaying high-resolution movie/series logos, star ratings, genres, directors, plot summaries, and wall-clock finish times (`Ends 10:45 PM`).
* **Zero-Dependency Native FFmpeg Engine:** Automatic 3-tier Lanczos logo scaling (`380px`, `520px`, `680px`) and BGRA hardware overlay generation running directly inside mpv in ~0.02s.
* **Auto-Inversion for Dark Logos:** Automatically samples pixel luminance. Pure black or dark logos (e.g. *Secret Level*) are dynamically inverted into crisp, luminous white text so they are never lost on dark backgrounds.
* **Interactive Glass Menus:** Built-in floating menus for Playlists, Chapters, Audio Tracks, and Subtitles with smooth keyboard and mouse navigation.
* **Real-Time Tag Cleaner & Editor:** Built-in modal input box with full multi-byte UTF-8 support (Tamil, Hindi, Japanese, Accents, Emojis). Strips messy torrent group watermarks (`[1TamilMV]`, `YTS.MX`, `WEB-DL`) with one click and purges stale caches.
* **Responsive Window Scaling:** Dynamically adapts from compact 720p tiled windows up to 4K/8K fullscreen displays without layout clipping.
* **Stream & Offline Guards:** Plays YouTube, Twitch, HLS streams, and offline local files with specialized ambient cards and zero network hang.

---

## 🚀 Step-by-Step Installation Guide

### Option A: Linux & macOS Installation

#### 1-Command Automated Install:
Open your terminal in the extracted release folder (or cloned repository) and run:
* **From Release Package (`.tar.gz`):**
  ```bash
  ./install.sh
  ```
* **From Git Clone:**
  ```bash
  ./tools/install.sh
  ```
The installer automatically:
1. Detects `~/.config/mpv` or `$XDG_CONFIG_HOME/mpv` (or `~/Library/Application Support/mpv` on macOS).
2. Copies `scripts/LuminaX/` and UI fonts (`Inter`, `uosc_icons`).
3. Sets up `script-opts/osc.conf` (preserving your existing API key if present).
4. Configures `mpv.conf` with `osc=no` and `osd-bar=no` to prevent dual-controller collisions.
5. Configures `input.conf` with LuminaX menu shortcuts (`Tab`, `p`, `c`, `a`, `s`).
6. Updates your user font cache via `fc-cache`.

#### Manual Linux Install:
```bash
# 1. Create target folders
mkdir -p ~/.config/mpv/scripts/LuminaX
mkdir -p ~/.config/mpv/fonts
mkdir -p ~/.config/mpv/script-opts

# 2. Copy scripts & fonts
cp -r scripts/LuminaX/* ~/.config/mpv/scripts/LuminaX/
cp fonts/* ~/.config/mpv/fonts/

# 3. Copy configuration & keybindings
cp script-opts/osc.conf ~/.config/mpv/script-opts/osc.conf
cp input.conf ~/.config/mpv/input.conf

# 4. Ensure mpv.conf disables default controls
echo -e "\nosc=no\nosd-bar=no\nosd-font=\"Inter\"" >> ~/.config/mpv/mpv.conf
```

---

### Option B: Windows Installation

#### 1-Click Automated Install:
* **From Release Package (`.zip`):**
  * **Batch:** Double-click `install.bat`
  * **PowerShell:** Right-click `install.ps1` and select **Run with PowerShell**
* **From Git Clone:**
  * **Batch:** Double-click `tools\install.bat`
  * **PowerShell:** Right-click `tools\install.ps1` and select **Run with PowerShell**

#### Manual Windows Install (Takes less than 3 minutes):
1. **Locate your mpv config folder:**
   * **Standard / Scoop / Chocolatey:** Press `Win + R`, type `%APPDATA%\mpv` and press `Enter` (`C:\Users\<YourUsername>\AppData\Roaming\mpv`).
   * **Portable mpv (`portable_config`):** Inside your mpv directory where `mpv.exe` lives, open the `portable_config` folder.
2. **Copy the files:**
   * Copy `scripts\LuminaX` into `mpv\scripts\`
   * Copy all files from `fonts\` into `mpv\fonts\`
   * Copy `script-opts\osc.conf` into `mpv\script-opts\osc.conf`
   * Copy `input.conf` into `mpv\input.conf`
3. **Configure `mpv.conf`:**
   Open `mpv.conf` in Notepad (create it if missing) and ensure these lines are present:
   ```ini
   osc=no
   osd-bar=no
   osd-font="Inter"
   ```
4. **Ensure `ffmpeg.exe` is available:**
   Make sure `ffmpeg.exe` is either in your Windows `PATH` or placed directly in the same folder as `mpv.exe`.

---

## 🔑 Adding Your Free TMDB API Key

To enable high-resolution movie logos, backdrop art, star ratings, and plot summaries on the pause screensaver:

1. Register for a free account at [themoviedb.org](https://www.themoviedb.org/signup).
2. Go to **Settings → API** and generate a free Developer API key.
3. Open `script-opts/osc.conf` in any text editor.
4. Set line 42 with your 32-character key:
   ```ini
   tmdb_api_key=your_32_character_api_key_here
   screensaver_enabled=yes
   screensaver_delay=3
   screensaver_align=center
   logo_engine=auto
   ```
5. Save the file.

> [!TIP]
> If no TMDB key is provided, or when playing network streams / offline files, LuminaX automatically falls back to the **Ambient Info Card** showing file duration, finish clock time, resolution quality, and audio specs with zero crashes.

---

## 🎮 Keybindings & Navigation Cheat Sheet

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| **`Space`** / **`Left Click`** | Play / Pause | Pausing triggers the screensaver countdown (3s default) |
| **`Tab`** | Toggle OSC Visibility | Cycle visibility between Auto, Always-On, and Hidden |
| **`p`** | **Playlist Menu** | Floating glass popup list with mouse and keyboard navigation |
| **`c`** | **Chapters Menu** | Interactive chapter selector |
| **`a`** | **Audio Tracks Menu** | Audio track switcher (showing language, codecs, channels) |
| **`s`** | **Subtitles Menu** | Subtitle track selector |
| **`T`** / **`Ctrl + t`** | **Tag Editor & Cleaner** | Modal input box to clean tracker junk or rename title in-place |
| **`Esc`** | Dismiss | Closes active menus or dismisses screensaver without exiting fullscreen |
| **`Mouse Move`** | Wake Player | Smoothly fades out screensaver and reveals visionOS glass controls |
| **`[` / `]`** | Speed Adjustment | Fluid pitch-corrected playback speed (±10%) |
| **`Backspace`** | Reset Speed | Reset playback speed to 1.0x |
| **`n` / `N`** | Anime Intro Skip | Skip forward/backward 85 seconds (Standard OP/ED length) |
| **`Up` / `Down`** | Volume Control | Adjust volume by 5% |
| **`m`** | Mute | Toggle audio mute |
| **`S`** / **`Ctrl + s`** | Screenshot | Capture frame with subtitles (`S`) or clean raw video (`Ctrl+s`) |

---

## 🛠️ Troubleshooting & Easy Fixes Guide

### 1. Two controllers appear on screen (overlapping bars)
* **Symptom:** The default stock mpv bottom bar overlaps with the visionOS glass controller.
* **Cause:** Default mpv OSC was not disabled in `mpv.conf`.
* **Fix:** Open `mpv.conf` and verify the following lines are present:
  ```ini
  osc=no
  osd-bar=no
  ```
  Save and restart mpv.

---

### 2. Buttons show empty boxes `[]` or broken icons
* **Symptom:** Media buttons display missing font glyphs or rectangular boxes.
* **Cause:** mpv cannot locate the custom Material Icons Round font.
* **Fix:**
  1. Ensure `uosc_icons.otf` is present inside your `mpv/fonts/` folder.
  2. On Windows, right-click `fonts\uosc_icons.otf` and select **Install for all users**.
  3. On Linux, run `fc-cache -f ~/.local/share/fonts` after placing the font files.

---

### 3. Movie title is messy (e.g. `[1TamilMV.vip] Movie (2026) 1080p WEB-DL`)
* **Symptom:** File title has torrent site watermarks, codec tags, or website domains.
* **Fix:**
  1. Press **`T`** on your keyboard while playing the video.
  2. Select **"Clean All Junk Watermarks"** to instantly strip release group tags from title and audio/subtitle tracks.
  3. Or select **"Edit Movie Title"** to type the exact title.
  4. LuminaX will purge old cache entries and immediately re-query TMDB with the clean name.

---

### 4. Screensaver shows styled text instead of official movie logo
* **Cause A (Expected):** The movie or TV show does not have a transparent PNG logo uploaded on TMDB in English. In this case, LuminaX automatically renders high-resolution typography with subtitle shadow as an elegant fallback.
* **Cause B:** `ffmpeg` is not found on your system.
* **Fix:** Open a terminal / command prompt and type:
  ```bash
  ffmpeg -version
  ```
  If it outputs an error, install FFmpeg or place `ffmpeg.exe` in the same directory as `mpv.exe`.

---

### 5. Screensaver shows "Offline Ambient Card" instead of plot summary
* **Cause A:** TMDB API key is missing or invalid in `script-opts/osc.conf`.
  * **Fix:** Verify `tmdb_api_key` has your valid 32-character key without extra quotes or spaces.
* **Cause B:** You are playing an online network stream (YouTube, Twitch, live HLS).
  * **Note:** LuminaX includes a built-in **Stream Guard** that intentionally bypasses TMDB searches on streams and displays stream domain, resolution, and live status.
* **Cause C:** Network firewall or proxy is blocking `curl`.
  * **Fix:** Test connection in terminal: `curl -I https://api.themoviedb.org`.

---

### 6. Black or dark logos are unreadable ("Black Label" issue)
* **Symptom:** Some TMDB logos (like *Secret Level*) are uploaded as pure black text.
* **Fix:** LuminaX includes automated luminance detection. It samples non-transparent pixels and automatically inverts pure black text into luminous white (`output_lum ~ 224`). Make sure `logo_engine=auto` or `logo_engine=ffmpeg` is set in `osc.conf`.

---

### 7. Tag editing displays: `mkvpropedit not found`
* **Note:** `mkvpropedit` is completely optional. If MKVToolNix is not installed, LuminaX will automatically apply your title changes in-memory using mpv's native `force-media-title` for the current session.
* **Fix (For permanent MKV file modification):**
  * **Windows:** Download [MKVToolNix Portable](https://mkvtoolnix.download/) and place `mkvpropedit.exe` in your mpv folder or in your Windows PATH.
  * **Linux:** Install via package manager: `sudo apt install mkvtoolnix` or `sudo pacman -S mkvtoolnix-cli`.

---

### 8. Text input with Tamil, Hindi, Japanese, accents, or emojis
* **Behavior:** The LuminaX Tag Editor modal has native multi-byte UTF-8 support.
* **Usage:**
  * Type in any language (Tamil `நாயகன்`, Hindi `दृश्यम`, Japanese `君の名は。`, Accents `Amélie`, Emojis `🎬🍿`).
  * Use **Arrow keys**, **Home**, **End**, **Backspace**, and **Delete**—the cursor respects multi-byte UTF-8 boundaries and will never slice characters in half.
  * Press **Ctrl+v** to paste clipboard text (newlines and invalid control characters are automatically sanitized).

---

### 9. Volume slider visibility mode
* **Behavior:** By default, the volume slider smoothly expands when hovering over the speaker icon.
* **Customization:** In `script-opts/osc.conf`:
  * `volume_slider_mode=hover`  - Minimalist (default)
  * `volume_slider_mode=always` - Permanently expanded slider
  * `volume_slider_mode=never`  - Speaker mute icon only

---

## 🔍 System Verification & Diagnostics

LuminaX includes a cross-platform diagnostic utility to verify your installation at any time:

```bash
# From Release Package:
python3 verify_installation.py

# From Git Clone:
python3 tools/verify_installation.py
```
This utility automatically checks:
* System platform (Linux, Windows, macOS)
* mpv, FFmpeg, curl, and mkvpropedit binary paths and versions
* Complete LuminaX module directory structure
* Required UI fonts presence
* `mpv.conf` conflict detection (`osc=no`, `osd-bar=no`)
* TMDB cloud network reachability

---

## 🧪 Automated Test Suite

To run the complete automated test suite (including UTF-8 navigation, state machine transitions, Spacebar pause spamming, 3-tier window geometry, and headless mpv IPC runtime tests):

```bash
python3 tests/run_all_tests.py
```
* **7 Test Suites**
* **251 Automated Assertions**

---

## 📦 Building Distribution Release Packages

To package LuminaX for distribution across Windows and Linux:

```bash
python3 tools/package_dist.py
```
Outputs release archives into `dist/`:
* `luminaX-linux.tar.gz` (with automated installer `install.sh`)
* `luminaX-windows.zip` (with automated installers `install.bat` and `install.ps1`)
* `checksums.txt` (SHA256 verification hashes)

---

## 📄 Reference Configuration Files

* [script-opts/osc.def.conf]: Exhaustive reference of all LuminaX flags and defaults.
* [mpv.def.conf]: High-performance GPU rendering, debanding, subtitle, and audio options.
* [input.def.conf]: Keybindings reference for window control, seeking, speed, and menus.
* [script-opts/stats.def.conf]: Styling reference for visionOS-themed mpv stats overlay (`i` / `Shift+i`).
