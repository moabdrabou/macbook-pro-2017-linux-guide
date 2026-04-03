#!/bin/bash
#
# reinstall-audio-driver.sh
# Reinstalls the snd_hda_macbookpro CS8409 audio driver after a kernel update.
# Run this script every time the kernel is updated on MBP14,x (T1 chip).
#
# Usage: sudo bash reinstall-audio-driver.sh
#

set -e

RED="\033[0;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
ENDCOLOR="\033[0m"

# ── Checks ────────────────────────────────────────────────────────────────────

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: run this script with sudo.${ENDCOLOR}"
    exit 1
fi

DRIVER_DIR="/home/$SUDO_USER/snd_hda_macbookpro"
if [ ! -d "$DRIVER_DIR" ]; then
    echo -e "${RED}Error: driver directory not found at $DRIVER_DIR${ENDCOLOR}"
    echo "Clone it first: git clone https://github.com/davidjo/snd_hda_macbookpro.git ~/snd_hda_macbookpro"
    exit 1
fi

# ── Detect versions ───────────────────────────────────────────────────────────

KVER=$(uname -r | cut -d- -f1)
KFULL=$(uname -r)
echo -e "${GREEN}Running kernel: $KFULL${ENDCOLOR}"

# Find the installed linux-source package
SRC_PKG=$(apt-cache search linux-source | grep "^linux-source-[0-9]" | awk '{print $1}' | sort -V | tail -1)
if [ -z "$SRC_PKG" ]; then
    echo -e "${RED}Error: no linux-source package found.${ENDCOLOR}"
    echo "Install one with: sudo apt install linux-source-X.XX.X"
    exit 1
fi

SRC_VER="${SRC_PKG//linux-source-/}"
SRC_TARBALL="/usr/src/linux-source-${SRC_VER}/linux-source-${SRC_VER}.tar.bz2"

echo -e "${GREEN}Using kernel source: $SRC_PKG (version $SRC_VER)${ENDCOLOR}"

# ── Install source package if missing ─────────────────────────────────────────

if [ ! -f "$SRC_TARBALL" ]; then
    echo -e "${YELLOW}Installing $SRC_PKG...${ENDCOLOR}"
    apt install -y "$SRC_PKG"
fi

if [ ! -f "$SRC_TARBALL" ]; then
    echo -e "${RED}Error: source tarball not found at $SRC_TARBALL${ENDCOLOR}"
    exit 1
fi

# ── Create symlinks for the installer ─────────────────────────────────────────

TARGET_TARBALL="/usr/src/linux-source-${KVER}.tar.bz2"
TARGET_DIR="/usr/src/linux-source-${KVER}"

if [ ! -e "$TARGET_TARBALL" ]; then
    echo -e "${YELLOW}Creating symlink: $TARGET_TARBALL${ENDCOLOR}"
    ln -s "$SRC_TARBALL" "$TARGET_TARBALL"
else
    echo -e "${GREEN}Symlink already exists: $TARGET_TARBALL${ENDCOLOR}"
fi

mkdir -p "$TARGET_DIR"
if [ ! -e "$TARGET_DIR/linux-source-${KVER}.tar.bz2" ]; then
    echo -e "${YELLOW}Creating symlink in directory: $TARGET_DIR${ENDCOLOR}"
    ln -s "$SRC_TARBALL" "$TARGET_DIR/linux-source-${KVER}.tar.bz2"
fi

# ── Patch the installer for the source version ────────────────────────────────

INSTALLER="$DRIVER_DIR/install.cirrus.driver.sh"

# Always re-apply the patch (idempotent — sed won't fail if already patched)
sed -i "s|linux-source-[0-9.]*\/sound\/hda|linux-source-${SRC_VER}/sound/hda|g" "$INSTALLER"

PATCHED=$(grep "sound/hda" "$INSTALLER")
echo -e "${GREEN}Installer patch applied: $PATCHED${ENDCOLOR}"

# ── Run the installer ─────────────────────────────────────────────────────────

echo -e "${YELLOW}Running audio driver installer...${ENDCOLOR}"
cd "$DRIVER_DIR"
bash install.cirrus.driver.sh

# ── Verify ────────────────────────────────────────────────────────────────────

KO_PATH="/lib/modules/${KFULL}/updates/codecs/cirrus/snd-hda-codec-cs8409.ko"
if [ -f "$KO_PATH" ]; then
    echo -e "${GREEN}✅ Driver installed successfully: $KO_PATH${ENDCOLOR}"
    echo -e "${YELLOW}Reboot to activate the new driver.${ENDCOLOR}"
else
    echo -e "${RED}❌ Driver file not found after install — check output above for errors.${ENDCOLOR}"
    exit 1
fi
