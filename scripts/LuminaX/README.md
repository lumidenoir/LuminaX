# 🌟 LuminaX for mpv
### Next-Generation Apple visionOS Glass Interface & Infuse-Style TMDB Cinema Screensaver

**LuminaX** transforms **mpv** into a luxury, Apple visionOS-inspired media player. It features translucent floating glass controls, interactive menus, and an Infuse/Apple TV-grade pause screensaver with real-time movie logos, metadata cards, and wall-clock finish times.

Unlike older mpv scripts, **LuminaX requires ZERO external language dependencies—no Python, no Pillow, and no pip installs are needed.** It runs with 100% native hardware-accelerated FFmpeg.

---

## 📸 Features at a Glance

* **Frosted VisionOS Glass Interface:** Translucent blurred controls with specular highlights, hover-expanding volume slider, and smooth animations.
* **Infuse / Apple TV Cinema Screensaver:** Triggers when paused, displaying high-resolution movie/series logos, star ratings, genres, directors, plot summaries, and wall-clock end times (`Ends 10:45 PM`).
* **Zero-Dependency Native FFmpeg Engine:** Automatic 3-tier Lanczos logo scaling (`380px`, `520px`, `680px`) and BGRA hardware overlay generation running directly inside mpv in ~0.02 seconds.
* **Auto-Inversion for Dark Logos:** Automatically samples pixel luminance. Pure black or dark logos (e.g. *Secret Level*) are dynamically inverted into crisp, luminous white text so they are never lost on dark backgrounds.
* **Interactive Glass Menus:** Built-in floating menus for Playlists, Chapters, Audio Tracks, and Subtitles with smooth keyboard and mouse navigation.
* **Real-Time Tag Cleaner & Editor:** Built-in modal input box with full multi-byte UTF-8 support (Tamil, Hindi, Japanese, Accents, Emojis). Strips messy torrent group watermarks (`[1TamilMV]`, `YTS.MX`, `WEB-DL`) with one click and purges stale caches.
* **Responsive Window Scaling:** Dynamically adapts from compact 720p tiled windows up to 4K/8K fullscreen displays without layout clipping.

---

## 🚀 Step-by-Step Windows Installation Guide

Installation takes less than **3 minutes** and requires no developer tools.

### Step 1: Locate your mpv Configuration Folder

Depending on how you installed mpv on Windows, your config directory is located at:

* **Standard / Installer / Scoop:**
  Press `Win + R`, type `%APPDATA%\mpv` and press `Enter`.
  *(Full path: `C:\Users\<YourUsername>\AppData\Roaming\mpv`)*
* **Portable mpv (`portable_config`):**
  Inside your mpv folder where `mpv.exe` lives, open the `portable_config` folder.

If the folder does not exist yet, create it.

---

### Step 2: Install LuminaX Files

Inside your mpv config folder (`%APPDATA%\mpv` or `portable_config`), set up the following folders:

```
mpv/
├── mpv.conf                     <-- Core player settings
├── input.conf                   <-- Keybindings
├── fonts/                       <-- UI & Icon Fonts
│   ├── Inter-Bold.ttf
│   ├── Inter-Medium.ttf
│   ├── Inter-Regular.ttf
│   ├── Inter-SemiBold.ttf
│   └── uosc_icons.otf           <-- Material Icons Round font
├── script-opts/
│   └── osc.conf                 <-- LuminaX configuration & TMDB key
└── scripts/
    └── LuminaX/                 <-- The entire LuminaX script folder
        ├── main.lua
        └── modules/
            ├── huds.lua
            ├── menu.lua
            ├── osc.lua
            ├── screensaver.lua
            ├── tag_editor.lua
            └── utils.lua
```

1. Copy the **`LuminaX`** directory into `mpv/scripts/`.
2. Copy the fonts from **`fonts/`** into `mpv/fonts/`. *(Optional: You can also right-click `uosc_icons.otf` and `Inter-*.ttf` and click **"Install for all users"**).*
3. Copy **`osc.conf`** into `mpv/script-opts/`.

---

### Step 3: Configure `mpv.conf` (Critical!)

Open your `mpv.conf` file in Notepad (create it if it doesn't exist) and add this line:

```ini
# Disable stock mpv on-screen controller so LuminaX takes over
osc=no
osd-bar=no
```

#### Recommended `mpv.conf` settings for the best experience:
```ini
osc=no
osd-bar=no
osd-font="Inter"
osd-font-size=18
cursor-autohide=1000
keep-open=yes
save-position-on-quit=yes
```

---

### Step 4: Add Your Free TMDB API Key (For Logos & Plot Summaries)

To allow the pause screensaver to fetch movie logos, backdrops, and cast info from The Movie Database (TMDB):

1. Go to [themoviedb.org](https://www.themoviedb.org/signup) and create a free account.
2. Go to **Settings → API** and generate a free Developer API key.
3. Open `mpv/script-opts/osc.conf` in Notepad.
4. Paste your key on line 42:
   ```ini
   tmdb_api_key=your_api_key_here
   screensaver_enabled=yes
   screensaver_delay=3
   screensaver_align=center
   logo_engine=auto
   ```
5. Save the file.

---

## 🎮 Keybindings & Navigation

| Key | Action |
| :--- | :--- |
| **`Tab`** | Toggle OSC visibility mode (Show / Auto / Hide) |
| **`p`** | Open **Playlist Menu** (Glass popup list with mouse & arrow keys) |
| **`c`** | Open **Chapters Menu** |
| **`a`** | Open **Audio Tracks Menu** |
| **`s`** | Open **Subtitles Menu** |
| **`T`** / **`Ctrl + t`** | Open **Tag Editor & Title Cleaner** |
| **`Space`** | Pause / Play (After 3s pause, screensaver activates) |
| **`Esc`** | Dismiss Screensaver / Close Menu |
| **`Mouse Move`** | Wakes player from screensaver and shows controls |

---

## 🛠️ Windows Troubleshooting Guide

If something doesn't look or work as expected, check these quick fixes:

### 1. Two controllers appear on screen (overlapping bars)
* **Cause:** The default stock mpv OSC was not disabled.
* **Fix:** Open `mpv.conf` and ensure `osc=no` is present. Restart mpv.

### 2. Buttons show blank boxes `[]` or broken icons
* **Cause:** mpv cannot find the Material Icons font.
* **Fix:**
  1. Make sure `uosc_icons.otf` (or `MaterialIconsRound-Regular.otf`) is placed inside `mpv/fonts/`.
  2. Alternatively, open `uosc_icons.otf` in Windows Explorer and click **Install**.

### 3. Screensaver shows movie details, but logo is missing (styled text fallback)
* **Cause A:** The movie or TV show does not have an official logo uploaded to TMDB in English. In this case, LuminaX automatically renders high-resolution typography with subtitle shadow.
* **Cause B:** `ffmpeg.exe` is not found in your system PATH or mpv directory.
* **Fix:** Open Command Prompt (`cmd.exe`) and type:
  ```cmd
  ffmpeg -version
  ```
  If it says *"'ffmpeg' is not recognized"*, download FFmpeg or place `ffmpeg.exe` in the same directory where `mpv.exe` is located.

### 4. Screensaver does not show any TMDB metadata ("Offline Ambient Card" appears)
* **Cause A:** Invalid or missing TMDB API key.
  * **Fix:** Open `script-opts/osc.conf` and verify `tmdb_api_key` has your valid 32-character key without extra spaces.
* **Cause B:** Windows Firewall is blocking `curl.exe`.
  * **Fix:** In Command Prompt, test:
    ```cmd
    curl -I https://api.themoviedb.org
    ```
    If connection fails, check your antivirus or network proxy.

### 5. Black or dark logos are unreadable ("Black Label" issue)
* **Cause:** Some logos on TMDB (like *Secret Level*) are uploaded as pure black text.
* **Fix:** LuminaX includes automated luminance detection. It evaluates non-transparent pixels and automatically inverts black text into luminous white (`output_lum ~ 224`). Make sure you are using the latest version of LuminaX.

### 6. Movie title is messy (e.g. `[1TamilMV] Movie (2026) 1080p WEB-DL`)
* **Fix:** Press **`T`** on your keyboard while the video is playing:
  * Select **"Clean All Junk Watermarks"** to strip tracker tags.
  * Select **"Edit Movie Title"** to type the exact title.
  LuminaX will instantly purge old cache entries and re-query TMDB with the cleaned title.

### 7. Tag editing gives error: `mkvpropedit not found`
* **Note:** `mkvpropedit` is 100% optional. If you do not have MKVToolNix installed, LuminaX will automatically apply your title changes in-memory using mpv's native `force-media-title`.
* **Fix (For permanent MKV file writing):** Download [MKVToolNix Portable](https://mkvtoolnix.download/) and place `mkvpropedit.exe` in your mpv folder or in your Windows PATH.

---

## ⚙️ Configuration Reference (`script-opts/osc.conf`)

| Option | Default | Description |
| :--- | :--- | :--- |
| `tmdb_api_key` | `""` | Your TMDB API v3 key |
| `screensaver_enabled` | `yes` | Enables the Infuse/Apple TV style pause screensaver |
| `screensaver_delay` | `3` | Seconds of pause before the screensaver fades in |
| `screensaver_align` | `center` | Layout alignment: `center` (cinema centered), `split`, `left` |
| `logo_engine` | `auto` | Logo processing engine: `auto` (native FFmpeg with python fallback), `ffmpeg` (pure native FFmpeg) |
| `volume_slider_mode` | `hover` | Volume slider behavior: `hover`, `always`, or `never` |
| `jumpamount` | `10` | Seconds to skip on jump buttons (`5`, `10`, `30`) |
| `min_scale` | `0.70` | Minimum adaptive scaling factor for tiled windows |
| `max_scale` | `1.05` | Maximum adaptive scaling factor for fullscreen |
