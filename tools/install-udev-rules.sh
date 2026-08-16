#!/usr/bin/env bash
# install-udev-rules.sh — grant non-root USB access to every JTAG/SWD adapter this toolkit knows
# about (openocd/adapters/99-jtagx-kit.rules), and put the invoking user in the `plugdev` group.
# Fixes the classic "adapter detected but LIBUSB_ERROR_ACCESS / Permission denied" wall without
# needing `sudo openocd` for every run. One-time setup; safe to re-run.
#
# Usage: sudo bash tools/install-udev-rules.sh          (from a dev checkout)
#        sudo bash install-udev-rules.sh                (from inside a built kit -- see below)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "error: needs root (writes /etc/udev/rules.d/ and edits group membership)." >&2
    echo "  re-run: sudo bash $0" >&2
    exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
# resolve the rules file whether run from a dev checkout (tools/../openocd/adapters/) or from
# inside a built kit (this script sits at the kit root, openocd/adapters/ alongside it)
for candidate in "$HERE/../openocd/adapters/99-jtagx-kit.rules" "$HERE/openocd/adapters/99-jtagx-kit.rules"; do
    if [ -f "$candidate" ]; then
        RULES="$candidate"
        break
    fi
done
if [ -z "${RULES:-}" ]; then
    echo "error: can't find openocd/adapters/99-jtagx-kit.rules relative to this script." >&2
    exit 1
fi

echo ">> installing $RULES -> /etc/udev/rules.d/99-jtagx-kit.rules"
cp "$RULES" /etc/udev/rules.d/99-jtagx-kit.rules

echo ">> reloading udev rules"
udevadm control --reload-rules
udevadm trigger

# the user who ran `sudo` (fall back to root if run directly as root, e.g. inside a container)
TARGET_USER="${SUDO_USER:-root}"
if [ "$TARGET_USER" != "root" ]; then
    if id -nG "$TARGET_USER" 2>/dev/null | grep -qw plugdev; then
        echo ">> $TARGET_USER is already in the plugdev group"
    else
        echo ">> adding $TARGET_USER to the plugdev group"
        usermod -aG plugdev "$TARGET_USER"
        echo "   NOTE: log out and back in (or reboot) for the new group membership to take effect."
    fi
fi

echo ""
echo "Done. Unplug and replug your adapter now — a udev rule only applies to the NEXT device-add"
echo "event, not devices already attached. Then confirm with: lsusb (no sudo) and check"
echo "'python3 tools/first-contact.py' or the preflight check no longer flags a permissions blocker."
