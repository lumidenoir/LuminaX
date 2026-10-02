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
elif [ "$(uname -s)" = "Darwin" ]; then
    if [ -d "$HOME/Library/Application Support/mpv" ] || [ ! -d "$HOME/.config/mpv" ]; then
        TARGET_DIR="$HOME/Library/Application Support/mpv"
    else
        TARGET_DIR="$HOME/.config/mpv"
    fi
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
    echo "Installing LuminaX modules & companion scripts..."
    mkdir -p "$TARGET_DIR/scripts"

    # Detect and disable conflicting third-party OSC controllers to prevent dual-controller collision
    for cos in uosc.lua osc.lua modernx.lua mpv-osc-modern.lua osc-tethys.lua; do
        if [ -f "$TARGET_DIR/scripts/$cos" ]; then
            mv "$TARGET_DIR/scripts/$cos" "$TARGET_DIR/scripts/$cos.disabled.bak"
            echo -e "${YELLOW}⚠ Detected conflicting OSC script '$cos' - backed up to '$cos.disabled.bak'${NC}"
        fi
    done
    if [ -d "$TARGET_DIR/scripts/uosc" ]; then
        rm -rf "$TARGET_DIR/scripts/uosc.disabled.bak"
        mv "$TARGET_DIR/scripts/uosc" "$TARGET_DIR/scripts/uosc.disabled.bak"
        echo -e "${YELLOW}⚠ Detected conflicting 'uosc' directory - backed up to 'uosc.disabled.bak'${NC}"
    fi

    cp -r "$PACKAGE_ROOT/scripts/LuminaX/"* "$TARGET_DIR/scripts/LuminaX/"
    for script in "$PACKAGE_ROOT/scripts/"*.lua; do
        if [ -f "$script" ]; then
            cp "$script" "$TARGET_DIR/scripts/"
        fi
    done

    echo "Installing UI & icon fonts to mpv/fonts/..."
    cp -r "$PACKAGE_ROOT/fonts/"* "$TARGET_DIR/fonts/"

    echo "Installing updater tools & diagnostics..."
    mkdir -p "$TARGET_DIR/tools"
    if [ -d "$PACKAGE_ROOT/tools" ]; then
        cp -r "$PACKAGE_ROOT/tools/"* "$TARGET_DIR/tools/" 2>/dev/null || true
    fi
    for t in "$PACKAGE_ROOT/update.sh" "$PACKAGE_ROOT/verify_installation.py"; do
        if [ -f "$t" ]; then cp "$t" "$TARGET_DIR/tools/"; fi
    done
    # Remove installer and release packaging scripts from target tools folder
    for inst in install.sh install.bat install.ps1 package_dist.py; do
        rm -f "$TARGET_DIR/tools/$inst" 2>/dev/null || true
    done
    chmod +x "$TARGET_DIR/tools/"*.sh 2>/dev/null || true

    # Place convenient 1-click update.sh in target root
    cp "$TARGET_DIR/tools/update.sh" "$TARGET_DIR/update.sh" 2>/dev/null || true
    chmod +x "$TARGET_DIR/update.sh" 2>/dev/null || true
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

# 4. Install script-opts configs & presets
OSC_CONF_DEST="$TARGET_DIR/script-opts/osc.conf"
if [ "$CANON_PKG" != "$CANON_TARGET" ]; then
    SRC_OSC=""
    if [ -f "$PACKAGE_ROOT/script-opts/osc.def.conf" ]; then
        SRC_OSC="$PACKAGE_ROOT/script-opts/osc.def.conf"
    elif [ -f "$PACKAGE_ROOT/script-opts/osc.conf" ]; then
        SRC_OSC="$PACKAGE_ROOT/script-opts/osc.conf"
    fi

    if [ -f "$OSC_CONF_DEST" ]; then
        cp "$OSC_CONF_DEST" "$OSC_CONF_DEST.bak"
        echo "  Backed up existing osc.conf -> osc.conf.bak"
        EXISTING_KEY=$(grep "^tmdb_api_key=" "$OSC_CONF_DEST" | cut -d= -f2- || true)
        if [ -n "$EXISTING_KEY" ] && [ "$EXISTING_KEY" != '""' ] && [ "$EXISTING_KEY" != "your_api_key_here" ]; then
            echo -e "${GREEN}✓ Preserving your existing TMDB API key in osc.conf${NC}"
            # Portable POSIX sed stream without in-place flag difference across BSD/GNU
            if [ -n "$SRC_OSC" ]; then
                sed "s|^tmdb_api_key=.*|tmdb_api_key=$EXISTING_KEY|" "$SRC_OSC" > "$OSC_CONF_DEST.new"
                mv "$OSC_CONF_DEST.new" "$OSC_CONF_DEST"
            fi
        else
            echo "Updating script-opts/osc.conf..."
            if [ -n "$SRC_OSC" ]; then
                cp "$SRC_OSC" "$OSC_CONF_DEST"
            fi
        fi
    else
        echo "Creating script-opts/osc.conf..."
        if [ -n "$SRC_OSC" ]; then
            cp "$SRC_OSC" "$OSC_CONF_DEST"
        fi
    fi

    # Deploy stats.conf
    STATS_CONF_DEST="$TARGET_DIR/script-opts/stats.conf"
    if [ -f "$STATS_CONF_DEST" ]; then
        cp "$STATS_CONF_DEST" "$STATS_CONF_DEST.bak"
        echo "  Backed up existing stats.conf -> stats.conf.bak"
    fi
    if [ -f "$PACKAGE_ROOT/script-opts/stats.def.conf" ]; then
        cp "$PACKAGE_ROOT/script-opts/stats.def.conf" "$STATS_CONF_DEST"
        echo "Installed visionOS stats configuration (script-opts/stats.conf)"
    elif [ -f "$PACKAGE_ROOT/script-opts/stats.conf" ]; then
        cp "$PACKAGE_ROOT/script-opts/stats.conf" "$STATS_CONF_DEST"
        echo "Installed visionOS stats configuration"
    fi

    # Deploy subtitle preset lumina_subtitle.json if not already present
    if [ ! -f "$TARGET_DIR/script-opts/lumina_subtitle.json" ] && [ -f "$PACKAGE_ROOT/script-opts/lumina_subtitle.json" ]; then
        cp "$PACKAGE_ROOT/script-opts/lumina_subtitle.json" "$TARGET_DIR/script-opts/lumina_subtitle.json"
        echo "Installed visionOS subtitle presets (script-opts/lumina_subtitle.json)"
    fi

    # Deploy reference definitions
    for def in osc.def.conf stats.def.conf; do
        if [ -f "$PACKAGE_ROOT/script-opts/$def" ]; then
            cp "$PACKAGE_ROOT/script-opts/$def" "$TARGET_DIR/script-opts/$def"
        fi
    done
fi

# 5. Check and configure mpv.conf (Critical for disabling stock controller)
MPV_CONF="$TARGET_DIR/mpv.conf"
if [ -f "$MPV_CONF" ]; then
    cp "$MPV_CONF" "$MPV_CONF.bak"
    echo "  Backed up existing mpv.conf -> mpv.conf.bak"
else
    if [ -f "$PACKAGE_ROOT/mpv.def.conf" ]; then
        echo "Creating mpv.conf from reference template..."
        cp "$PACKAGE_ROOT/mpv.def.conf" "$MPV_CONF"
    elif [ -f "$PACKAGE_ROOT/mpv.conf" ]; then
        echo "Creating mpv.conf from template..."
        cp "$PACKAGE_ROOT/mpv.conf" "$MPV_CONF"
    else
        touch "$MPV_CONF"
    fi
fi

if [ -f "$PACKAGE_ROOT/mpv.def.conf" ]; then
    cp "$PACKAGE_ROOT/mpv.def.conf" "$TARGET_DIR/mpv.def.conf"
fi

if ! grep -q "^osc=no" "$MPV_CONF" && ! grep -q "^osc = no" "$MPV_CONF"; then
    echo "Adding 'osc=no' to $MPV_CONF..."
    echo -e "\n# Disable default mpv OSC for LuminaX\nosc=no" >> "$MPV_CONF"
fi

if ! grep -q "^osd-bar=no" "$MPV_CONF" && ! grep -q "^osd-bar = no" "$MPV_CONF"; then
    echo "Adding 'osd-bar=no' to $MPV_CONF..."
    echo "osd-bar=no" >> "$MPV_CONF"
fi

if ! grep -q "^osd-font=" "$MPV_CONF" && ! grep -q '^osd-font[[:space:]]*=' "$MPV_CONF"; then
    echo 'osd-font="Inter"' >> "$MPV_CONF"
fi

if ! grep -q "^audio-fallback-to-null=" "$MPV_CONF" && ! grep -q '^audio-fallback-to-null[[:space:]]*=' "$MPV_CONF"; then
    echo "audio-fallback-to-null=yes" >> "$MPV_CONF"
fi

# 6. Check and configure input.conf (for LuminaX glass menu keybindings)
INPUT_CONF="$TARGET_DIR/input.conf"
if [ -f "$INPUT_CONF" ]; then
    cp "$INPUT_CONF" "$INPUT_CONF.bak"
    echo "  Backed up existing input.conf -> input.conf.bak"
    if ! grep -q "menu-sub-config" "$INPUT_CONF" || ! grep -q "menu-playlist" "$INPUT_CONF"; then
        echo "Adding LuminaX menu shortcuts (Tab, p, c, a, s, Alt+s, V, T, U) to $INPUT_CONF..."
        cat << 'EOF' >> "$INPUT_CONF"

# LuminaX Interactive Glass Menus & OSD
tab               script-binding LuminaX/visibility
p                 script-binding LuminaX/menu-playlist
c                 script-binding LuminaX/menu-chapters
a                 script-binding LuminaX/menu-audio
s                 script-binding LuminaX/menu-sub
Alt+s             script-binding LuminaX/menu-sub-config
V                 script-binding LuminaX/menu-video
T                 script-binding LuminaX/toggle-tags-menu
Ctrl+t            script-binding LuminaX/toggle-tags-menu-ctrl
U                 script-binding LuminaX/check-update
EOF
    fi
else
    if [ -f "$PACKAGE_ROOT/input.def.conf" ]; then
        echo "Creating input.conf from canonical reference template..."
        cp "$PACKAGE_ROOT/input.def.conf" "$INPUT_CONF"
    elif [ -f "$PACKAGE_ROOT/input.conf" ]; then
        echo "Creating input.conf with LuminaX keybindings..."
        cp "$PACKAGE_ROOT/input.conf" "$INPUT_CONF"
    fi
fi

if [ -f "$PACKAGE_ROOT/input.def.conf" ]; then
    cp "$PACKAGE_ROOT/input.def.conf" "$TARGET_DIR/input.def.conf"
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
