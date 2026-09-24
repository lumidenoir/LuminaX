#!/usr/bin/env python3
"""
LuminaX Cross-Platform Health & Installation Verifier:
Inspects local system configuration, dependencies, fonts, scripts, and config files
for both Windows and Linux environments, printing clear diagnostics and recommendations.
"""

import os
import sys
import shutil
import subprocess

def run_command(cmd):
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5)
        return res.returncode == 0, res.stdout.strip(), res.stderr.strip()
    except Exception as e:
        return False, "", str(e)

def main():
    print("=" * 70)
    print("🔍 LuminaX Installation & Environment Diagnostic Verifier")
    print("=" * 70)

    is_windows = sys.platform.startswith("win") or (os.name == "nt")
    platform_name = "Windows" if is_windows else ("macOS" if sys.platform == "darwin" else "Linux")
    print(f"Platform: {platform_name} ({sys.platform})")

    # 1. Determine mpv Directory & Base Environment
    cwd = os.getcwd()
    if len(sys.argv) > 1 and sys.argv[1].strip():
        mpv_dir = os.path.abspath(sys.argv[1].strip())
    elif os.path.exists(os.path.join(cwd, "mpv.conf")):
        mpv_dir = cwd
    elif os.path.exists(os.path.join(cwd, "portable_config")):
        mpv_dir = os.path.abspath(os.path.join(cwd, "portable_config"))
    elif is_windows:
        cand_portable = os.path.abspath(os.path.join(cwd, "..", "portable_config"))
        if os.path.exists(cand_portable):
            mpv_dir = cand_portable
        else:
            mpv_dir = os.path.expandvars(r"%APPDATA%\mpv")
    elif sys.platform == "darwin":
        mac_support = os.path.expanduser("~/Library/Application Support/mpv")
        if os.path.exists(mac_support) and not os.path.exists(os.path.expanduser("~/.config/mpv")):
            mpv_dir = mac_support
        else:
            mpv_dir = os.path.expanduser("~/.config/mpv")
    else:
        xdg = os.environ.get("XDG_CONFIG_HOME")
        if xdg and os.path.isdir(xdg):
            mpv_dir = os.path.join(xdg, "mpv")
        else:
            mpv_dir = os.path.expanduser("~/.config/mpv")

    print(f"Target mpv Directory: {mpv_dir}")

    # 2. Check binaries
    print("\n[1/5] Checking Required Binaries...")
    binaries = {
        "mpv": {"req": True, "ver_flag": "--version"},
        "ffmpeg": {"req": True, "ver_flag": "-version"},
        "curl": {"req": True, "ver_flag": "--version"},
        "mkvpropedit": {"req": False, "ver_flag": "--version"},
    }

    all_req_bins = True
    for b, meta in binaries.items():
        path = shutil.which(b)
        if not path and is_windows:
            # Check mpv folder and portable local dir
            cand_paths = [
                f"{b}.exe",
                os.path.join(".", f"{b}.exe"),
                os.path.join(mpv_dir, f"{b}.exe"),
                os.path.join(os.path.dirname(mpv_dir), f"{b}.exe"),
            ]
            for cand in cand_paths:
                if os.path.exists(cand):
                    path = os.path.abspath(cand)
                    break
        if path:
            ok, out, _ = run_command([path, meta["ver_flag"]])
            first_line = out.split("\n")[0] if out else "installed"
            print(f"  ✓ {b:<12} Found at: {path} ({first_line[:45]})")
        else:
            if meta["req"]:
                all_req_bins = False
                print(f"  ✗ {b:<12} NOT FOUND in PATH or mpv directory! (Required)")
            else:
                print(f"  ℹ {b:<12} Not found (Optional: used for permanent MKV file tag writing)")

    # 3. Check mpv Directory & Scripts
    print("\n[2/5] Checking LuminaX Directory Structure...")

    required_files = [
        os.path.join("scripts", "autoload.lua"),
        os.path.join("scripts", "thumbfast.lua"),
        os.path.join("scripts", "LuminaX", "main.lua"),
        os.path.join("scripts", "LuminaX", "modules", "utils.lua"),
        os.path.join("scripts", "LuminaX", "modules", "osc.lua"),
        os.path.join("scripts", "LuminaX", "modules", "huds.lua"),
        os.path.join("scripts", "LuminaX", "modules", "menu.lua"),
        os.path.join("scripts", "LuminaX", "modules", "screensaver.lua"),
        os.path.join("scripts", "LuminaX", "modules", "tag_editor.lua"),
    ]

    all_scripts_ok = True
    for rf in required_files:
        p = os.path.join(mpv_dir, rf)
        if os.path.exists(p) and os.path.getsize(p) > 0:
            print(f"  ✓ {rf:<42} ({os.path.getsize(p):,} bytes)")
        else:
            all_scripts_ok = False
            print(f"  ✗ {rf:<42} MISSING or EMPTY!")

    # 3. Check Fonts
    print("\n[3/5] Checking UI & Icon Fonts...")
    font_files = [
        "Inter-Bold.ttf",
        "Inter-Medium.ttf",
        "Inter-Regular.ttf",
        "Inter-SemiBold.ttf",
        "uosc_icons.otf",
    ]
    all_fonts_ok = True
    for f in font_files:
        fp = os.path.join(mpv_dir, "fonts", f)
        if os.path.exists(fp) and os.path.getsize(fp) > 0:
            print(f"  ✓ {f:<25} Found ({os.path.getsize(fp):,} bytes)")
        else:
            all_fonts_ok = False
            print(f"  ✗ {f:<25} MISSING from mpv/fonts/!")

    # 4. Check Config & mpv.conf flags
    print("\n[4/5] Checking Configuration & Dual-Controller Conflict...")
    mpv_conf_p = os.path.join(mpv_dir, "mpv.conf")
    osc_conf_p = os.path.join(mpv_dir, "script-opts", "osc.conf")

    if os.path.exists(osc_conf_p):
        print(f"  ✓ {os.path.relpath(osc_conf_p, mpv_dir)} Found")
    else:
        print(f"  ⚠ {os.path.relpath(osc_conf_p, mpv_dir)} Not found (Defaults will be used)")

    mpv_conf_ok = False
    if os.path.exists(mpv_conf_p):
        with open(mpv_conf_p, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        has_osc_no = "osc=no" in content or "osc = no" in content
        has_bar_no = "osd-bar=no" in content or "osd-bar = no" in content
        if has_osc_no and has_bar_no:
            print("  ✓ mpv.conf correctly disables default OSC and OSD-bar (osc=no, osd-bar=no)")
            mpv_conf_ok = True
        else:
            print("  ⚠ mpv.conf found, but 'osc=no' or 'osd-bar=no' is missing! This may cause overlapping controls.")
    else:
        print("  ⚠ mpv.conf not found. Ensure 'osc=no' and 'osd-bar=no' are added to your mpv.conf.")

    # 5. Check Network & TMDB connectivity
    print("\n[5/5] Checking TMDB Cloud Connectivity...")
    curl_bin = shutil.which("curl") or ("curl.exe" if is_windows else "curl")
    ok, out, _ = run_command([curl_bin, "-I", "-s", "--connect-timeout", "4", "https://api.themoviedb.org"])
    if ok and ("200" in out or "301" in out or "302" in out or "401" in out or "404" in out or "HTTP/" in out):
        print("  ✓ Successfully connected to TMDB API endpoint (api.themoviedb.org)")
    else:
        print("  ⚠ Could not connect to TMDB endpoint. Check your internet connection or firewall.")

    print("\n" + "=" * 70)
    if all_req_bins and all_scripts_ok and all_fonts_ok:
        print("✅ LuminaX environment is HEALTHY and ready to run!")
    else:
        print("⚠ Some components require attention. Please review the items marked with ✗ above.")
    print("=" * 70)

if __name__ == "__main__":
    main()
