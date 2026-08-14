# Fully self-contained AppImage (Python + Qt bundled)

`tools/make-gui-appimage.sh` (default) builds a **host-python** AppImage: small (~2 MB), but the target
needs `python3-pyside6.qtwidgets` installed. For a **truly standalone** AppImage that bundles the Python
runtime + PySide6/Qt (target needs nothing), use one of the two standard toolchains below. Both need
network to fetch the tooling — that's why the bundled build can't be produced in the offline dev
sandbox; the app tree it packages is the same `opt/jtagx` the script already assembles.

## Option A — python-appimage (simplest for a Python app)
```bash
pip install python-appimage
printf 'PySide6\n' > packaging/requirements.txt
# packaging/appimage-app/__main__.py just execs gui-spike/jtagx_app.py against the bundled opt/jtagx tree
python-appimage build app --python-version 3.11 --name JTAGx packaging/appimage-app/
```
Bakes CPython + PySide6 into the AppImage (~120–180 MB). Fully self-contained.

## Option B — linuxdeploy + linuxdeploy-plugin-qt (bundles the system Qt)
```bash
# fetch linuxdeploy + linuxdeploy-plugin-qt (both are AppImages), put them on PATH, then:
BUNDLE=1 tools/make-gui-appimage.sh          # the script calls linuxdeploy --plugin qt automatically
# equivalently:
linuxdeploy --appdir dist/JTAGx.AppDir --plugin qt --output appimage
```
The `qt` plugin gathers `libQt6*.so` + the `platforms/`/`imageformats/` plugins that a manual copy misses.

## Notes
- Writable data: the app reads `reports/`, `dumps/` relative to its tree. In a read-only AppImage,
  point those at a working dir (run the AppImage from the engagement dir, or set a data-dir env) —
  a small follow-up in `jtagx_app.py`/`AppRun` if fully-portable data handling is wanted.
- The host-python variant is the one validated in-repo (`make-gui-appimage.sh` assembles the AppDir and
  the bundled app builds from it offscreen).
