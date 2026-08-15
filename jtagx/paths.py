#!/usr/bin/env python3
"""
jtagx.paths — resolve the read-only code root vs the user-writable data dir.

An installed / AppImage build mounts the code read-only, so dumps/reports/captures cannot be
written next to the scripts (the mount is squashfs). This centralizes the split so the GUI and
tools stop assuming "write into the repo tree":

  repo_root()  -> where code/profiles/openocd/tools live (read-only when packaged)
  data_dir()   -> user-writable base for outputs (XDG when packaged; the repo tree in dev)
  dumps_dir()/reports_dir() -> the standard output subdirs under data_dir()
  data_path(rel) -> absolutize a data-relative path ('dumps/os-live.bin' -> <data>/dumps/...)
  localize(cmd)  -> rewrite dumps//reports/ tokens in a shell command to the writable dir
                    (no-op in dev, where data_dir()==repo_root()).

Env overrides (set by the AppImage AppRun): JTAGX_ROOT pins the code root; JTAGX_DATA pins the
writable base; APPDIR/APPIMAGE (or JTAGX_PACKAGED) flip packaged mode on. Directories are created
on demand — importing this module has no side effects.
"""
import os
import re


def _first_env(*names):
    for n in names:
        v = os.environ.get(n)
        if v:
            return v
    return None


def repo_root():
    """Absolute path to the code tree (profiles/openocd/tools/jtagx)."""
    env = _first_env("JTAGX_ROOT")
    if env:
        return os.path.abspath(env)
    # jtagx/paths.py -> jtagx/ -> repo root
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def is_packaged():
    """True when running from an AppImage / installed bundle (code mount is read-only)."""
    return bool(_first_env("APPDIR", "APPIMAGE", "JTAGX_PACKAGED"))


def data_dir():
    """User-writable base for outputs. XDG (~/.local/share/jtagx) when packaged; the repo tree in dev."""
    env = _first_env("JTAGX_DATA")
    if env:
        base = env
    elif is_packaged():
        xdg = _first_env("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
        base = os.path.join(xdg, "jtagx")
    else:
        base = repo_root()          # dev: keep writing dumps/ and reports/ in-tree (unchanged)
    base = os.path.abspath(base)
    os.makedirs(base, exist_ok=True)
    return base


def _sub(name):
    p = os.path.join(data_dir(), name)
    os.makedirs(p, exist_ok=True)
    return p


def dumps_dir():
    return _sub("dumps")


def reports_dir():
    return _sub("reports")


def data_path(rel):
    """Absolutize a data-relative path under the writable data dir, creating its parent."""
    p = os.path.join(data_dir(), rel)
    parent = os.path.dirname(p)
    if parent:
        os.makedirs(parent, exist_ok=True)
    return p


# match a leading dumps/ or reports/ path token not already part of a longer path/word
_DATA_TOK = re.compile(r"(?<![\w./-])(dumps|reports)/")


def localize(cmd, data=None, root=None):
    """Rewrite `dumps/…` / `reports/…` tokens in a shell command to absolute writable paths.

    No-op in dev (data_dir()==repo_root()), so existing in-tree behavior is unchanged; when packaged
    (JTAGX_DATA / XDG differs from the read-only code root) the command's outputs land in the writable
    dir instead of failing against the squashfs mount. Code paths (openocd/…, tools/…) are left alone.
    """
    data = data or data_dir()
    root = root or repo_root()
    if os.path.abspath(data) == os.path.abspath(root):
        return cmd
    return _DATA_TOK.sub(lambda m: f"{data}/{m.group(1)}/", cmd)
