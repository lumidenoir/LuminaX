#!/usr/bin/env bash
# ==============================================================================
# LuminaX Automated Linux / macOS Updater
# Fetches latest release, verifies checksums, backs up, and updates LuminaX
# with 100% preservation of TMDB API key and custom user configs.
# ==============================================================================

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN}🌟 LuminaX Automated Linux & macOS Updater${NC}"
echo -e "${CYAN}======================================================================${NC}"

# Parse flags
FORCE=false
NON_INTERACTIVE=false
CUSTOM_TARGET=""

for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=true ;;
        --non-interactive|-y) NON_INTERACTIVE=true ;;
        -*) ;;
        *) if [ -z "$CUSTOM_TARGET" ]; then CUSTOM_TARGET="$arg"; fi ;;
    esac
done

# 1. Determine mpv Target Directory
if [ -n "$CUSTOM_TARGET" ]; then
    TARGET_DIR="$CUSTOM_TARGET"
elif [ -n "${XDG_CONFIG_HOME:-}" ] && [ -d "$XDG_CONFIG_HOME/mpv/scripts/LuminaX" ]; then
    TARGET_DIR="$XDG_CONFIG_HOME/mpv"
elif [ "$(uname -s)" = "Darwin" ] && [ -d "$HOME/Library/Application Support/mpv/scripts/LuminaX" ]; then
    TARGET_DIR="$HOME/Library/Application Support/mpv"
elif [ -d "$HOME/.config/mpv/scripts/LuminaX" ]; then
    TARGET_DIR="$HOME/.config/mpv"
elif [ -d "./scripts/LuminaX" ]; then
    TARGET_DIR="$(pwd)"
elif [ -d "../scripts/LuminaX" ]; then
    TARGET_DIR="$(cd .. && pwd)"
else
    TARGET_DIR="$HOME/.config/mpv"
fi

echo -e "Target mpv Directory: ${GREEN}$TARGET_DIR${NC}"

# Read local version
LOCAL_VER="0.0.0"
VERSION_FILE="$TARGET_DIR/scripts/LuminaX/version.lua"
if [ -f "$VERSION_FILE" ]; then
    LOCAL_VER=$(grep -oE "VERSION\s*=\s*['\"][^'\"]+['\"]" "$VERSION_FILE" | head -n1 | sed -E "s/VERSION\s*=\s*['\"]([^'\"]+)['\"]/\1/")
fi
echo -e "Currently Installed: ${CYAN}v$LOCAL_VER${NC}"

# 2. Query GitHub Releases API
echo -e "\n=== Checking for updates on GitHub ==="
API_URL="https://api.github.com/repos/lumidenoir/LuminaX/releases/latest"

RELEASE_DATA=$(curl -s -4 --connect-timeout 5 --max-time 10 -H "User-Agent: LuminaX-Updater" "$API_URL" || true)

if [ -z "$RELEASE_DATA" ] || ! echo "$RELEASE_DATA" | grep -q '"tag_name":'; then
    echo -e "${RED}Error: Unable to fetch release data from GitHub.${NC}" >&2
    echo -e "Please check your network connection: $API_URL" >&2
    exit 1
fi

LATEST_TAG=$(echo "$RELEASE_DATA" | grep -oE '"tag_name":\s*"[^"]+"' | head -n1 | cut -d'"' -f4 | sed 's/^v//')
echo -e "Latest Release on GitHub: ${GREEN}v$LATEST_TAG${NC}"

# SemVer comparator
ver_gt() {
    # Returns 0 (true) if $1 > $2
    [ "$1" = "$2" ] && return 1
    local v1=$(echo "$1" | sed 's/^v//')
    local v2=$(echo "$2" | sed 's/^v//')
    if printf '%s\n%s\n' "1.0" "2.0" | sort -V >/dev/null 2>&1; then
        [ "$(printf '%s\n' "$v1" "$v2" | sort -V | tail -n1)" = "$v1" ]
    else
        local IFS=.
        local i ver1=($v1) ver2=($v2)
        for ((i=0; i<3; i++)); do
            local n1=${ver1[i]:-0}
            local n2=${ver2[i]:-0}
            if [ "$n1" -gt "$n2" ] 2>/dev/null; then return 0; fi
            if [ "$n1" -lt "$n2" ] 2>/dev/null; then return 1; fi
        done
        return 1
    fi
}

if ! ver_gt "$LATEST_TAG" "$LOCAL_VER" && [ "$FORCE" = false ]; then
    echo -e "\n${GREEN}✓ LuminaX is already up to date! (v$LOCAL_VER)${NC}"
    exit 0
fi

echo -e "${YELLOW}Update available: v$LOCAL_VER -> v$LATEST_TAG${NC}"

# 3. Locate release assets
TAR_URL=""
if [ "$(uname -s)" = "Darwin" ]; then
    TAR_URL=$(echo "$RELEASE_DATA" | grep -oE '"browser_download_url":\s*"[^"]*macos\.tar\.gz"' | head -n1 | cut -d'"' -f4 || true)
fi
if [ -z "$TAR_URL" ]; then
    TAR_URL=$(echo "$RELEASE_DATA" | grep -oE '"browser_download_url":\s*"[^"]*linux\.tar\.gz"' | head -n1 | cut -d'"' -f4 || true)
fi
SUM_URL=$(echo "$RELEASE_DATA" | grep -oE '"browser_download_url":\s*"[^"]*checksums\.txt"' | head -n1 | cut -d'"' -f4 || true)

if [ -z "$TAR_URL" ]; then
    echo -e "${RED}Error: Could not locate release tar.gz in release v$LATEST_TAG.${NC}" >&2
    exit 1
fi

# 4. Download & Verify Checksum
TMP_DIR=$(mktemp -d -t luminax_update_XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE_NAME=$(basename "$TAR_URL")
echo -e "\n=== Downloading Release Archive ==="
TAR_FILE="$TMP_DIR/$ARCHIVE_NAME"
echo "Fetching: $TAR_URL"
curl -s -L -4 --connect-timeout 5 --max-time 30 "$TAR_URL" -o "$TAR_FILE"

EXPECTED_HASH=""
if [ -n "$SUM_URL" ]; then
    SUM_FILE="$TMP_DIR/checksums.txt"
    curl -s -L -4 --connect-timeout 4 --max-time 10 "$SUM_URL" -o "$SUM_FILE" || true
    if [ -f "$SUM_FILE" ]; then
        EXPECTED_HASH=$(grep "$ARCHIVE_NAME" "$SUM_FILE" | awk '{print $1}' | tr '[:upper:]' '[:lower:]' || true)
    fi
fi

# Fallback: check if SHA256 was included in the release notes body (e.g. initial releases)
if [ -z "$EXPECTED_HASH" ]; then
    EXPECTED_HASH=$(echo "$RELEASE_DATA" | grep -iE "SHA256.*$ARCHIVE_NAME" | grep -oE '[a-fA-F0-9]{64}' | head -n1 | tr '[:upper:]' '[:lower:]' || true)
fi

if [ -n "$EXPECTED_HASH" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL_HASH=$(sha256sum "$TAR_FILE" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
    elif command -v shasum >/dev/null 2>&1; then
        ACTUAL_HASH=$(shasum -a 256 "$TAR_FILE" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
    else
        ACTUAL_HASH=$(python3 -c "import hashlib; print(hashlib.sha256(open('$TAR_FILE','rb').read()).hexdigest())" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
    fi

    if [ "$ACTUAL_HASH" = "$EXPECTED_HASH" ]; then
        echo -e "  ${GREEN}✓ SHA-256 integrity verified ($ACTUAL_HASH)${NC}"
    else
        echo -e "  ${RED}✗ Checksum mismatch!${NC}" >&2
        echo -e "    Expected: $EXPECTED_HASH" >&2
        echo -e "    Actual:   $ACTUAL_HASH" >&2
        exit 1
    fi
fi

# 5. Extract & Atomic Backup
echo -e "\n=== Applying LuminaX v$LATEST_TAG ==="
EXTRACT_DIR="$TMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$TAR_FILE" -C "$EXTRACT_DIR"

EXTRACTED_ROOT="$EXTRACT_DIR"
if [ ! -d "$EXTRACT_DIR/scripts/LuminaX" ]; then
    SUBDIR=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)
    if [ -n "$SUBDIR" ] && [ -d "$SUBDIR/scripts/LuminaX" ]; then
        EXTRACTED_ROOT="$SUBDIR"
    fi
fi

# Backup current scripts
BACKUP_DIR="$TARGET_DIR/scripts/LuminaX.bak"
if [ -d "$TARGET_DIR/scripts/LuminaX" ]; then
    rm -rf "$BACKUP_DIR"
    cp -r "$TARGET_DIR/scripts/LuminaX" "$BACKUP_DIR"
    echo -e "  Created safety rollback backup: ${CYAN}scripts/LuminaX.bak${NC}"
fi

# Install new files
mkdir -p "$TARGET_DIR/scripts/LuminaX"
mkdir -p "$TARGET_DIR/fonts"
mkdir -p "$TARGET_DIR/script-opts"
mkdir -p "$TARGET_DIR/tools"

cp -r "$EXTRACTED_ROOT/scripts/LuminaX/"* "$TARGET_DIR/scripts/LuminaX/"

# Companion scripts
for s in "$EXTRACTED_ROOT/scripts/"*.lua; do
    if [ -f "$s" ]; then cp "$s" "$TARGET_DIR/scripts/"; fi
done

# Fonts
if [ -d "$EXTRACTED_ROOT/fonts" ]; then
    cp -r "$EXTRACTED_ROOT/fonts/"* "$TARGET_DIR/fonts/"
    echo "  Updated UI & icon fonts"
fi

# 6. Preserve osc.conf & Merge new settings
OSC_CONF="$TARGET_DIR/script-opts/osc.conf"
TEMPLATE_OSC="$EXTRACTED_ROOT/script-opts/osc.conf"
[ ! -f "$TEMPLATE_OSC" ] && TEMPLATE_OSC="$EXTRACTED_ROOT/script-opts/osc.def.conf"

if [ -f "$OSC_CONF" ]; then
    EXISTING_KEY=$(grep -E '^[[:space:]]*tmdb_api_key[[:space:]]*=' "$OSC_CONF" | head -n1 | sed -E 's/^[[:space:]]*tmdb_api_key[[:space:]]*=[[:space:]]*//' | tr -d '\r' | sed -E 's/^["'\'']//; s/["'\'']$//' || true)
    if [ -n "$EXISTING_KEY" ] && [ "$EXISTING_KEY" != "your_api_key_here" ]; then
        echo -e "  ${GREEN}✓ Preserved your existing TMDB API key in osc.conf${NC}"
    fi

    # Merge newly added keys without modifying existing user values
    if [ -f "$TEMPLATE_OSC" ]; then
        NEW_KEYS=0
        while IFS= read -r line || [ -n "$line" ]; do
            clean_line=$(echo "$line" | tr -d '\r')
            [[ "$clean_line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$clean_line" ]] && continue
            if [[ "$clean_line" =~ ^[[:space:]]*([a-zA-Z0-9_\-]+)[[:space:]]*= ]]; then
                setting_key="${BASH_REMATCH[1]}"
                if ! grep -qE "^[[:space:]]*$setting_key[[:space:]]*=" "$OSC_CONF"; then
                    echo "$clean_line" >> "$OSC_CONF"
                    echo -e "  + Merged new default setting: ${CYAN}$setting_key${NC}"
                    NEW_KEYS=$((NEW_KEYS + 1))
                fi
            fi
        done < "$TEMPLATE_OSC"
        if [ "$NEW_KEYS" -gt 0 ]; then
            echo -e "  ${GREEN}✓ Merged $NEW_KEYS new default setting(s) into osc.conf${NC}"
        fi
    fi
elif [ -f "$TEMPLATE_OSC" ]; then
    cp "$TEMPLATE_OSC" "$OSC_CONF"
fi

# Deploy stats.conf if not already present
if [ ! -f "$TARGET_DIR/script-opts/stats.conf" ]; then
    if [ -f "$EXTRACTED_ROOT/script-opts/stats.conf" ]; then
        cp "$EXTRACTED_ROOT/script-opts/stats.conf" "$TARGET_DIR/script-opts/stats.conf"
    elif [ -f "$EXTRACTED_ROOT/script-opts/stats.def.conf" ]; then
        cp "$EXTRACTED_ROOT/script-opts/stats.def.conf" "$TARGET_DIR/script-opts/stats.conf"
    fi
fi

# Deploy subtitle presets if not already present
if [ ! -f "$TARGET_DIR/script-opts/lumina_subtitle.json" ] && [ -f "$EXTRACTED_ROOT/script-opts/lumina_subtitle.json" ]; then
    cp "$EXTRACTED_ROOT/script-opts/lumina_subtitle.json" "$TARGET_DIR/script-opts/lumina_subtitle.json"
fi

# Deploy reference definitions
for def in osc.def.conf stats.def.conf; do
    if [ -f "$EXTRACTED_ROOT/script-opts/$def" ]; then
        cp "$EXTRACTED_ROOT/script-opts/$def" "$TARGET_DIR/script-opts/$def"
    fi
done

# Update tools & diagnostics
if [ -d "$EXTRACTED_ROOT/tools" ]; then
    cp -r "$EXTRACTED_ROOT/tools/"* "$TARGET_DIR/tools/" 2>/dev/null || true
fi
if [ -f "$EXTRACTED_ROOT/verify_installation.py" ]; then
    cp "$EXTRACTED_ROOT/verify_installation.py" "$TARGET_DIR/tools/" 2>/dev/null || true
fi

# Copy updater into tools and root
cp "$0" "$TARGET_DIR/tools/update.sh" 2>/dev/null || true
chmod +x "$TARGET_DIR/tools/"*.sh 2>/dev/null || true
cp "$TARGET_DIR/tools/update.sh" "$TARGET_DIR/update.sh" 2>/dev/null || true
chmod +x "$TARGET_DIR/update.sh" 2>/dev/null || true

# Remove backup on success
rm -rf "$BACKUP_DIR"

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${GREEN}🎉 LuminaX successfully updated to v$LATEST_TAG!${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "Restart mpv to experience the updated visionOS interface.\n"
