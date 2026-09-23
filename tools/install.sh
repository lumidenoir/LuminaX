#!/usr/bin/env bash
# ==============================================================================
# LuminaX Automated Linux / macOS Installer
# Installs LuminaX scripts, visionOS glass theme, and fonts to mpv configuration
# ==============================================================================

set -euo pipefail

# ANSI Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN}🌟 LuminaX Installer for Linux & macOS${NC}"
echo -e "${CYAN}======================================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect package root whether running from repository (tools/..) or extracted release archive (.)
if [ -d "$SCRIPT_DIR/scripts/LuminaX" ]; then
    PACKAGE_ROOT="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/../scripts/LuminaX" ]; then
    PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    echo -e "${RED}Error: Cannot find LuminaX source files (scripts/LuminaX).${NC}" >&2
    echo -e "Make sure you are running the installer from within the extracted release archive or repository.${NC}" >&2
    exit 1
fi

# 1. Determine mpv config destination
if [ -n "${1:-}" ]; then
    TARGET_DIR="$1"
elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
    TARGET_DIR="$XDG_CONFIG_HOME/mpv"
elif [ "$(uname -s)" = "Darwin" ] && [ -d "$HOME/Library/Application Support/mpv" ]; then
    TARGET_DIR="$HOME/Library/Application Support/mpv"
else
    TARGET_DIR="$HOME/.config/mpv"
fi

echo -e "Installing to target mpv directory: ${GREEN}$TARGET_DIR${NC}"

# Canonical paths for comparison
CANON_PKG="$(cd "$PACKAGE_ROOT" 2>/dev/null && pwd -P || echo "$PACKAGE_ROOT")"
mkdir -p "$TARGET_DIR"
CANON_TARGET="$(cd "$TARGET_DIR" 2>/dev/null && pwd -P || echo "$TARGET_DIR")"

# Create directories
mkdir -p "$TARGET_DIR/scripts/LuminaX/modules"
mkdir -p "$TARGET_DIR/fonts"
mkdir -p "$TARGET_DIR/script-opts"

# 2. Copy scripts & fonts (skip copy if target is identical to package root)
if [ "$CANON_PKG" = "$CANON_TARGET" ]; then
    echo -e "${YELLOW}Target directory is identical to source package root; files already in place.${NC}"
else
    echo "Installing LuminaX modules..."
    cp -r "$PACKAGE_ROOT/scripts/LuminaX/"* "$TARGET_DIR/scripts/LuminaX/"

    echo "Installing UI & icon fonts to mpv/fonts/..."
    cp -r "$PACKAGE_ROOT/fonts/"* "$TARGET_DIR/fonts/"
fi

# Optional: also install to system/user fonts
if [ "$(uname -s)" = "Darwin" ]; then
    MAC_FONT_DIR="$HOME/Library/Fonts"
    if [ -d "$MAC_FONT_DIR" ] || mkdir -p "$MAC_FONT_DIR" 2>/dev/null; then
        cp -r "$PACKAGE_ROOT/fonts/"* "$MAC_FONT_DIR/" 2>/dev/null || true
    fi
else
    USER_FONT_DIR="$HOME/.local/share/fonts"
    if [ -d "$USER_FONT_DIR" ] || mkdir -p "$USER_FONT_DIR" 2>/dev/null; then
        cp -r "$PACKAGE_ROOT/fonts/"* "$USER_FONT_DIR/" 2>/dev/null || true
        if command -v fc-cache >/dev/null 2>&1; then
            fc-cache -f "$USER_FONT_DIR" >/dev/null 2>&1 || true
        fi
    fi
fi

# 4. Install script-opts/osc.conf (preserve existing TMDB API key if set)
OSC_CONF_DEST="$TARGET_DIR/script-opts/osc.conf"
if [ "$CANON_PKG" != "$CANON_TARGET" ]; then
    if [ -f "$OSC_CONF_DEST" ]; then
        EXISTING_KEY=$(grep "^tmdb_api_key=" "$OSC_CONF_DEST" | cut -d= -f2- || true)
        if [ -n "$EXISTING_KEY" ] && [ "$EXISTING_KEY" != '""' ] && [ "$EXISTING_KEY" != "your_api_key_here" ]; then
            echo -e "${GREEN}✓ Preserving your existing TMDB API key in osc.conf${NC}"
            # Copy template but restore key
            cp "$PACKAGE_ROOT/script-opts/osc.conf" "$OSC_CONF_DEST.new"
            sed -i "s|^tmdb_api_key=.*|tmdb_api_key=$EXISTING_KEY|" "$OSC_CONF_DEST.new"
            mv "$OSC_CONF_DEST.new" "$OSC_CONF_DEST"
        else
            echo "Updating script-opts/osc.conf..."
            cp "$PACKAGE_ROOT/script-opts/osc.conf" "$OSC_CONF_DEST"
        fi
    else
        echo "Creating script-opts/osc.conf..."
        cp "$PACKAGE_ROOT/script-opts/osc.conf" "$OSC_CONF_DEST"
    fi
fi

# 5. Check and configure mpv.conf (Critical for disabling stock controller)
MPV_CONF="$TARGET_DIR/mpv.conf"
touch "$MPV_CONF"

if ! grep -q "^osc=no" "$MPV_CONF" && ! grep -q "^osc = no" "$MPV_CONF"; then
    echo "Adding 'osc=no' to $MPV_CONF..."
    echo -e "\n# Disable default mpv OSC for LuminaX\nosc=no" >> "$MPV_CONF"
fi

if ! grep -q "^osd-bar=no" "$MPV_CONF" && ! grep -q "^osd-bar = no" "$MPV_CONF"; then
    echo "Adding 'osd-bar=no' to $MPV_CONF..."
    echo "osd-bar=no" >> "$MPV_CONF"
fi

# 6. Check and configure input.conf (for LuminaX glass menu keybindings)
INPUT_CONF="$TARGET_DIR/input.conf"
if [ ! -f "$INPUT_CONF" ]; then
    if [ -f "$PACKAGE_ROOT/input.conf" ]; then
        echo "Creating input.conf with LuminaX keybindings..."
        cp "$PACKAGE_ROOT/input.conf" "$INPUT_CONF"
    fi
elif [ "$CANON_PKG" != "$CANON_TARGET" ]; then
    if ! grep -q "menu-playlist" "$INPUT_CONF"; then
        echo "Adding LuminaX menu shortcuts (Tab, p, c, a, s) to $INPUT_CONF..."
        cat << 'EOF' >> "$INPUT_CONF"

# LuminaX Interactive Glass Menus & OSD
tab               script-binding LuminaX/visibility
p                 script-binding LuminaX/menu-playlist
c                 script-binding LuminaX/menu-chapters
a                 script-binding LuminaX/menu-audio
s                 script-binding LuminaX/menu-sub
EOF
    fi
fi

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${GREEN}🎉 LuminaX successfully installed!${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "Next steps:"
echo -e "1. Open ${CYAN}$OSC_CONF_DEST${NC} and enter your free TMDB API key."
echo -e "2. Launch any video in mpv to experience visionOS glass UI and cinema screensaver."

VERIFY_SCRIPT=""
if [ -f "$PACKAGE_ROOT/verify_installation.py" ]; then
    VERIFY_SCRIPT="$PACKAGE_ROOT/verify_installation.py"
elif [ -f "$PACKAGE_ROOT/tools/verify_installation.py" ]; then
    VERIFY_SCRIPT="$PACKAGE_ROOT/tools/verify_installation.py"
fi

if [ -n "$VERIFY_SCRIPT" ]; then
    echo -e "3. Run ${CYAN}python3 \"$VERIFY_SCRIPT\" \"$TARGET_DIR\"${NC} anytime to verify system health."
fi
