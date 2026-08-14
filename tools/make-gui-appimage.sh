#!/usr/bin/env bash
# make-gui-appimage.sh — build a Linux AppImage of the JTAGx GUI.
#
# Host-python variant: the AppImage bundles the app code (gui-spike/jtagx/tools/profiles/openocd/docs)
# read-only and launches it with the TARGET's python3 + PySide6 (needs python3-pyside6.qtwidgets on
# Kali/Debian). This keeps the image small (~a few MB of code); a fully self-contained build (bundling
# Python + Qt via python-appimage/linuxdeploy) is a future step — see packaging/.
#
# Usage:
#   tools/make-gui-appimage.sh                 # assemble the AppDir; package if appimagetool is present
#   FETCH=1 tools/make-gui-appimage.sh         # also download appimagetool if it's missing, then package
#   OUT=/tmp/x tools/make-gui-appimage.sh      # choose the output dir (default: dist/)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
OUT="${OUT:-dist}"
APPDIR="$OUT/JTAGx.AppDir"

echo "== assembling AppDir: $APPDIR =="
rm -rf "$APPDIR"
mkdir -p "$APPDIR/opt/jtagx" \
         "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/scalable/apps"

# read-only runtime tree the GUI touches
for d in gui-spike jtagx tools profiles openocd; do
    cp -r "$d" "$APPDIR/opt/jtagx/$d"
done
mkdir -p "$APPDIR/opt/jtagx/docs/transport"
cp docs/transport/adapter-catalog.md "$APPDIR/opt/jtagx/docs/transport/" 2>/dev/null || true
# per-engagement output dirs (populated at runtime, not shipped with data)
mkdir -p "$APPDIR/opt/jtagx/reports" "$APPDIR/opt/jtagx/dumps"
# drop bulky __pycache__
find "$APPDIR/opt/jtagx" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true

install -m 0755 packaging/AppRun        "$APPDIR/AppRun"
install -m 0644 packaging/jtagx.desktop "$APPDIR/jtagx.desktop"
install -m 0644 packaging/jtagx.desktop "$APPDIR/usr/share/applications/jtagx.desktop"
install -m 0644 packaging/jtagx.svg     "$APPDIR/jtagx.svg"
install -m 0644 packaging/jtagx.svg     "$APPDIR/usr/share/icons/hicolor/scalable/apps/jtagx.svg"
cp packaging/jtagx.svg "$APPDIR/.DirIcon"

SZ=$(du -sh "$APPDIR" | awk '{print $1}')
echo "== AppDir ready ($SZ) =="

# fully-bundled (Python + Qt) build via linuxdeploy-plugin-qt — see packaging/BUNDLED.md
if [ "${BUNDLE:-0}" = "1" ]; then
    echo "== fully-bundled build requested =="
    if command -v linuxdeploy >/dev/null 2>&1 && command -v linuxdeploy-plugin-qt >/dev/null 2>&1; then
        exec linuxdeploy --appdir "$APPDIR" --plugin qt --output appimage
    fi
    echo "  needs linuxdeploy + linuxdeploy-plugin-qt on PATH (or python-appimage) — see packaging/BUNDLED.md."
    echo "  the (host-python) AppDir is assembled at $APPDIR."
    exit 0
fi

# package with appimagetool
TOOL="$(command -v appimagetool || true)"
if [ -z "$TOOL" ] && [ "${FETCH:-0}" = "1" ]; then
    echo "== fetching appimagetool =="
    curl -fL -o "$OUT/appimagetool" \
        https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x "$OUT/appimagetool"
    TOOL="$OUT/appimagetool"
fi
if [ -z "$TOOL" ]; then
    echo ""
    echo "appimagetool not found — AppDir is assembled but not packaged."
    echo "  Finish with:  FETCH=1 tools/make-gui-appimage.sh"
    echo "  or install appimagetool and run:  appimagetool '$APPDIR' '$OUT/JTAGx-x86_64.AppImage'"
    exit 0
fi
echo "== packaging =="
ARCH=x86_64 "$TOOL" "$APPDIR" "$OUT/JTAGx-x86_64.AppImage"
echo "built: $OUT/JTAGx-x86_64.AppImage"
