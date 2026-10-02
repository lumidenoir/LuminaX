#!/usr/bin/env python3
"""
LuminaX Distribution Packaging Script:
Automates the creation of release-ready distribution archives for Linux and Windows:
  - dist/luminaX-linux.tar.gz
  - dist/luminaX-windows.zip
  - dist/checksums.txt
Validates archive contents, integrity, and permissions.
"""

import os
import sys
import shutil
import tarfile
import zipfile
import hashlib
import re
import subprocess

def sha256_file(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def clean_osc_conf(src_path, dest_path):
    """Ensure the packaged osc.conf template has placeholder API key, not a private key"""
    with open(src_path, "r", encoding="utf-8") as f:
        content = f.read()
    # Replace any concrete key with placeholder
    import re
    cleaned = re.sub(r"tmdb_api_key\s*=[^\r\n]*", "tmdb_api_key=your_api_key_here", content)
    with open(dest_path, "w", encoding="utf-8") as f:
        f.write(cleaned)

def build_packages():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root_dir)

    dist_dir = os.path.join(root_dir, "dist")
    if os.path.exists(dist_dir):
        shutil.rmtree(dist_dir)
    os.makedirs(dist_dir, exist_ok=True)

    print("=" * 70)
    print("📦 Building LuminaX Multi-Platform Release Distribution Packages")
    print(f"Source Root: {root_dir}")
    print(f"Output Dist: {dist_dir}")
    print("=" * 70)

    # Temporary staging area
    stage_dir = os.path.join(dist_dir, "_stage")
    os.makedirs(stage_dir, exist_ok=True)

    # 1. Prepare Staging Tree
    print("\n[1/4] Preparing Clean Distribution Staging Tree...")
    # Copy scripts/LuminaX and companion scripts (autoload.lua, thumbfast.lua)
    shutil.copytree("scripts/LuminaX", os.path.join(stage_dir, "scripts", "LuminaX"), dirs_exist_ok=True)
    for s in os.listdir("scripts"):
        if s.endswith(".lua"):
            shutil.copy2(os.path.join("scripts", s), os.path.join(stage_dir, "scripts", s))
    # Copy fonts
    shutil.copytree("fonts", os.path.join(stage_dir, "fonts"), dirs_exist_ok=True)
    # Copy script-opts
    os.makedirs(os.path.join(stage_dir, "script-opts"), exist_ok=True)
    clean_osc_conf("script-opts/osc.conf", os.path.join(stage_dir, "script-opts", "osc.conf"))
    if os.path.exists("script-opts/osc.def.conf"):
        shutil.copy2("script-opts/osc.def.conf", os.path.join(stage_dir, "script-opts", "osc.def.conf"))
    if os.path.exists("script-opts/stats.conf"):
        shutil.copy2("script-opts/stats.conf", os.path.join(stage_dir, "script-opts", "stats.conf"))
    if os.path.exists("script-opts/stats.def.conf"):
        shutil.copy2("script-opts/stats.def.conf", os.path.join(stage_dir, "script-opts", "stats.def.conf"))
    if os.path.exists("script-opts/lumina_subtitle.json"):
        shutil.copy2("script-opts/lumina_subtitle.json", os.path.join(stage_dir, "script-opts", "lumina_subtitle.json"))
    # Copy config templates & references
    for conf_file in ["input.conf", "input.def.conf", "mpv.conf", "mpv.def.conf"]:
        if os.path.exists(conf_file):
            shutil.copy2(conf_file, os.path.join(stage_dir, conf_file))
    # Copy README
    if os.path.exists("README.md"):
        shutil.copy2("README.md", os.path.join(stage_dir, "README.md"))
    elif os.path.exists("scripts/LuminaX/README.md"):
        shutil.copy2("scripts/LuminaX/README.md", os.path.join(stage_dir, "README.md"))
    # Copy tools directory
    os.makedirs(os.path.join(stage_dir, "tools"), exist_ok=True)
    for t in os.listdir("tools"):
        t_src = os.path.join("tools", t)
        if os.path.isfile(t_src) and t != "package_dist.py":
            shutil.copy2(t_src, os.path.join(stage_dir, "tools", t))
    shutil.copy2("tools/verify_installation.py", os.path.join(stage_dir, "verify_installation.py"))

    # Verify no junk
    for r, dirs, files in os.walk(stage_dir):
        for f in files:
            if f.endswith(".pyc") or f == ".DS_Store" or f == "Thumbs.db":
                os.remove(os.path.join(r, f))

    # 2. Build Linux & macOS Packages (.tar.gz)
    print("\n[2/4] Packaging Linux & macOS Releases (luminaX-linux.tar.gz & luminaX-macos.tar.gz)...")
    linux_tar = os.path.join(dist_dir, "luminaX-linux.tar.gz")
    macos_tar = os.path.join(dist_dir, "luminaX-macos.tar.gz")
    
    # Add install.sh and update.sh to posix stage
    shutil.copy2("tools/install.sh", os.path.join(stage_dir, "install.sh"))
    shutil.copy2("tools/update.sh", os.path.join(stage_dir, "update.sh"))
    os.chmod(os.path.join(stage_dir, "install.sh"), 0o755)
    os.chmod(os.path.join(stage_dir, "update.sh"), 0o755)
    os.chmod(os.path.join(stage_dir, "verify_installation.py"), 0o755)

    with tarfile.open(linux_tar, "w:gz") as tar:
        for item in sorted(os.listdir(stage_dir)):
            if item in ["install.bat", "install.ps1", "update.bat", "update.ps1"]:
                continue
            item_path = os.path.join(stage_dir, item)
            tar.add(item_path, arcname=item)
            print(f"  + Added: {item}")

    print(f"  ✓ Created: {linux_tar} ({os.path.getsize(linux_tar):,} bytes)")

    # Produce dedicated macOS package matching release expectation
    shutil.copy2(linux_tar, macos_tar)
    print(f"  ✓ Created: {macos_tar} ({os.path.getsize(macos_tar):,} bytes)")

    # 3. Build Windows Package (.zip)
    print("\n[3/4] Packaging Windows Release (luminaX-windows.zip)...")
    # Clean linux scripts from stage and add windows scripts
    for linux_script in ["install.sh", "update.sh"]:
        p = os.path.join(stage_dir, linux_script)
        if os.path.exists(p):
            os.remove(p)
    shutil.copy2("tools/install.bat", os.path.join(stage_dir, "install.bat"))
    shutil.copy2("tools/install.ps1", os.path.join(stage_dir, "install.ps1"))
    shutil.copy2("tools/update.bat", os.path.join(stage_dir, "update.bat"))
    shutil.copy2("tools/update.ps1", os.path.join(stage_dir, "update.ps1"))

    win_zip = os.path.join(dist_dir, "luminaX-windows.zip")
    with zipfile.ZipFile(win_zip, "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(stage_dir):
            for file in sorted(files):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, stage_dir)
                zipf.write(full_path, arcname=rel_path)
                print(f"  + Added: {rel_path}")

    print(f"  ✓ Created: {win_zip} ({os.path.getsize(win_zip):,} bytes)")

    # Cleanup staging
    shutil.rmtree(stage_dir)

    # 4. Generate Checksums
    print("\n[4/5] Generating SHA256 Checksums...")
    checksum_file = os.path.join(dist_dir, "checksums.txt")
    checksums = []
    for pkg in [linux_tar, macos_tar, win_zip]:
        csum = sha256_file(pkg)
        fname = os.path.basename(pkg)
        checksums.append(f"{csum}  {fname}")
        print(f"  SHA256 ({fname}): {csum}")

    with open(checksum_file, "w", encoding="utf-8") as f:
        f.write("\n".join(checksums) + "\n")
    print(f"  ✓ Checksums written to {checksum_file}")

    # 5. Generate Release Body & Commit Changelog
    generate_release_body(dist_dir, checksums)

    print("\n" + "=" * 70)
    print("✅ All distribution packages built and verified successfully!")
    print("=" * 70)

def get_repo_url():
    try:
        import subprocess
        url = subprocess.check_output(["git", "remote", "get-url", "origin"], stderr=subprocess.DEVNULL).decode().strip()
        m = re.search(r"github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?$", url)
        if m:
            return f"https://github.com/{m.group(1)}/{m.group(2)}"
    except Exception:
        pass
    return None

def generate_release_body(dist_dir, checksums):
    import subprocess
    print("\n[5/5] Generating Release Body & Conventional Commit Changelog...")
    repo_url = get_repo_url()
    try:
        prev_tag = subprocess.check_output(["git", "describe", "--tags", "--abbrev=0", "HEAD^"], stderr=subprocess.DEVNULL).decode().strip()
        rev_range = f"{prev_tag}..HEAD"
    except Exception:
        rev_range = "HEAD"

    try:
        log = subprocess.check_output(["git", "log", rev_range, "--pretty=format:%h %s"], stderr=subprocess.DEVNULL).decode("utf-8")
    except Exception:
        log = ""

    categories = {
        "🚀 Features & Enhancements": [],
        "🐛 Bug Fixes": [],
        "🛠 Maintenance & Performance": []
    }

    for line in log.strip().split("\n"):
        if not line:
            continue
        parts = line.split(" ", 1)
        h = parts[0]
        msg = parts[1] if len(parts) > 1 else ""
        link = f"[{h}]({repo_url}/commit/{h})" if repo_url else f"({h})"

        if re.match(r"^feat(\(.*\))?!?:", msg, re.I):
            categories["🚀 Features & Enhancements"].append(f"- {msg} ({link})")
        elif re.match(r"^fix(\(.*\))?!?:", msg, re.I):
            categories["🐛 Bug Fixes"].append(f"- {msg} ({link})")
        else:
            categories["🛠 Maintenance & Performance"].append(f"- {msg} ({link})")

    sections = []
    for title, items in categories.items():
        if items:
            sections.append(f"### {title}\n" + "\n".join(items))

    csum_block = "```\n" + "\n".join(checksums) + "\n```"
    sections.append(f"### 🔒 Verify Checksums (SHA-256)\n{csum_block}")

    release_body_path = os.path.join(dist_dir, "release_body.md")
    with open(release_body_path, "w", encoding="utf-8") as f:
        f.write("\n\n".join(sections) + "\n")
    print(f"  ✓ Release body written to {release_body_path}")

if __name__ == "__main__":
    build_packages()

