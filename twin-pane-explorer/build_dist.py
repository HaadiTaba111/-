#!/usr/bin/env python3
"""Build the distributable artefacts for Twin-Pane Explorer.

Produces, in ``dist/``:

* ``twinpane_<ver>_all.deb``  - a real Termux/Debian package.  ``pkg install
  ./twinpane_*.deb`` puts ``twinpane`` on $PATH with a man-style help page and
  pulls Python + ncurses in as dependencies.  This is the *native* Android
  install: no root, no Termux:API, no Android SDK needed.
* ``twinpane-<ver>.zip``      - a portable bundle that runs from anywhere
  (``unzip && ./twinpane/run.sh``); handy for other distros and for pushing to
  a phone with ``termux-setup-storage``.
* ``SHA256SUMS``              - checksums for both.

A note on APKs: an ``.apk`` is a signed Android application package.  Building
one needs the Android SDK + build-tools (aapt2, d8, apksigner) and, for a
Python/curses program, python-for-android plus Kivy - curses cannot be embedded
in an Android app without a terminal emulator.  The honest, working route for a
TUI on Android is a native Termux package, which is what this script builds.
``.github/workflows/build-apk-tui.yml`` documents the alternative (a
python-for-android launcher that shell-outs into Termux).
"""
from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
DIST = os.path.join(ROOT, "dist")
PKG = "twinpane"
SUMMARY = "Two-panel (Norton Commander style) file manager for Termux"
DESCRIPTION = (
    "Twin-Pane Explorer is a two-panel terminal file manager built for Termux "
    "on Android: browse, copy, move, zip and extract between the Termux home "
    "and the shared phone storage. Includes touch/mouse drag-copy, an adaptive "
    "single-panel phone layout, ten colour themes, daily activity/error logs, "
    "session resume, a parametric config file and a small plugin API."
)


def version() -> str:
    sys.path.insert(0, ROOT)
    from twinpane import __version__
    return __version__.strip()


def iter_sources():
    """Every file that belongs in the package, relative to ROOT."""
    skip_dirs = {"__pycache__", ".git", "dist", "build", ".pytest_cache",
                 ".mypy_cache", "docs/preview", "node_modules"}
    for base, dirs, files in os.walk(ROOT):
        rel_base = os.path.relpath(base, ROOT)
        rel_base = "" if rel_base == "." else rel_base
        dirs[:] = sorted(d for d in dirs if d not in skip_dirs
                         and not rel_base.startswith("docs/preview"))
        for name in sorted(files):
            if name.endswith((".pyc", ".pyo")):
                continue
            rel = os.path.join(rel_base, name) if rel_base else name
            yield rel


# ---------------------------------------------------------------------------
# .deb
# ---------------------------------------------------------------------------

def build_deb(ver: str, output: str) -> str:
    work = tempfile.mkdtemp(prefix="twinpane-deb-")
    try:
        stage = os.path.join(work, "stage")
        lib = os.path.join(stage, "data/data/com.termux/files/usr/lib/twinpane")
        bindir = os.path.join(stage, "data/data/com.termux/files/usr/bin")
        counter = 0
        for rel in iter_sources():
            src = os.path.join(ROOT, rel)
            if rel.startswith("tests/") or rel.startswith("tools_"):
                continue
            if os.path.basename(rel) == ".gitignore":
                continue
            dest = os.path.join(lib, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(src, dest)
            counter += 1
        os.makedirs(bindir, exist_ok=True)
        launcher = os.path.join(bindir, PKG)
        with open(launcher, "w", encoding="utf-8") as handle:
            handle.write('#!/data/data/com.termux/files/usr/bin/sh\n'
                         'exec python "$PREFIX/lib/twinpane/run.py" "$@"\n')
        os.chmod(launcher, 0o755)

        size_kb = sum(os.path.getsize(os.path.join(base, f))
                      for base, _d, fs in os.walk(lib) for f in fs) // 1024 + 1
        control_dir = os.path.join(stage, "DEBIAN")
        os.makedirs(control_dir, exist_ok=True)
        with open(os.path.join(control_dir, "control"), "w", encoding="utf-8") as handle:
            handle.write(
                "Package: %s\nVersion: %s\nArchitecture: all\n"
                "Maintainer: Twin-Pane Explorer <twinpane@example.com>\n"
                "Installed-Size: %d\nDepends: python, ncurses-utils\n"
                "Section: utils\nPriority: optional\n"
                "Homepage: https://github.com/HaadiTaba111/-\n"
                "Description: %s\n %s\n" % (PKG, ver, size_kb, SUMMARY,
                                            DESCRIPTION.replace("\n", "\n ")))
        os.chmod(os.path.join(control_dir, "control"), 0o644)

        os.makedirs(DIST, exist_ok=True)
        target = os.path.join(DIST, output)
        if os.path.exists(target):
            os.unlink(target)
        if shutil.which("dpkg-deb"):
            subprocess.run(["dpkg-deb", "--build", "--root-owner-group",
                            stage, target], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        else:                                   # Termux has no dpkg-deb by default
            _build_ar_deb(stage, target, ver)
        del counter
        return target
    finally:
        shutil.rmtree(work, ignore_errors=True)


def _build_ar_deb(stage: str, target: str, ver: str) -> None:
    """Write a .deb (an ``ar`` archive) without dpkg-deb."""
    tmp = tempfile.mkdtemp(prefix="twinpane-ar-")
    try:
        control_tar = os.path.join(tmp, "control.tar.gz")
        data_tar = os.path.join(tmp, "data.tar.gz")
        with tarfile.open(control_tar, "w:gz") as tar:
            tar.add(os.path.join(stage, "DEBIAN"), arcname=".")
        with tarfile.open(data_tar, "w:gz") as tar:
            for name in sorted(os.listdir(stage)):
                if name == "DEBIAN":
                    continue
                tar.add(os.path.join(stage, name), arcname=name)
        debian_binary = os.path.join(tmp, "debian-binary")
        with open(debian_binary, "w") as handle:
            handle.write("2.0\n")
        files = [debian_binary, control_tar, data_tar]
        names = ["debian-binary", "control.tar.gz", "data.tar.gz"]
        with open(target, "wb") as out:
            out.write(b"!<arch>\n")
            for path, name in zip(files, names):
                size = os.path.getsize(path)
                header = ("%-16s%-12s%-6s%-6s%-8s%-10s" % (
                    name, "0", "0", "0", "100644", size)).encode()
                out.write(header + b"`\n")
                with open(path, "rb") as handle:
                    out.write(handle.read())
                if size % 2:
                    out.write(b"\n")
        del ver
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# single-file portable app (one file to copy to the phone)
# ---------------------------------------------------------------------------

STUB = r'''#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Twin-Pane Explorer __VER__ - single-file edition.

Copy THIS ONE FILE anywhere (USB, Telegram, email, cloud) and run it:

    python twinpane-__VER__-standalone.py            # run straight away
    python twinpane-__VER__-standalone.py --install  # add a `twinpane` command
    python twinpane-__VER__-standalone.py --version
    python twinpane-__VER__-standalone.py --uninstall

Everything the program needs is inside this file (a base64 zip payload), so
there is nothing to unzip and nothing to download.
"""
import base64
import os
import shutil
import sys
import tempfile
import zipfile

VERSION = "__VER__"
PAYLOAD = """\
__PAYLOAD__"""


def _extract():
    """Unpack the payload once into a per-version cache folder."""
    base = os.environ.get("TWINPANE_CACHE") or os.path.join(
        tempfile.gettempdir(), "twinpane-" + VERSION)
    marker = os.path.join(base, "twinpane", "ui.py")
    if os.path.exists(marker):
        return base
    os.makedirs(base, exist_ok=True)
    raw = base64.b64decode(PAYLOAD)
    with tempfile.TemporaryFile() as handle:
        handle.write(raw)
        handle.seek(0)
        with zipfile.ZipFile(handle) as archive:
            archive.extractall(base)
    return base


def _install():
    prefix = os.environ.get("PREFIX")
    if not prefix:
        print("PREFIX is not set - run this inside Termux.")
        return 2
    root = _extract()
    dest = os.path.join(prefix, "lib", "twinpane")
    shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(os.path.join(root, "twinpane"),
                    os.path.join(dest, "twinpane"))
    for name in ("run.py", "termux-widget.sh"):
        src = os.path.join(root, name)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(dest, name))
    binary = os.path.join(prefix, "bin", "twinpane")
    os.makedirs(os.path.dirname(binary), exist_ok=True)
    with open(binary, "w") as handle:
        handle.write("#!/data/data/com.termux/files/usr/bin/sh\n")
        handle.write('exec python "' + dest + '/run.py" "$@"\n')
    os.chmod(binary, 0o755)
    shortcuts = os.path.expanduser("~/.shortcuts")
    os.makedirs(shortcuts, exist_ok=True)
    widget = os.path.join(dest, "termux-widget.sh")
    if os.path.exists(widget):
        target = os.path.join(shortcuts, "explorer.sh")
        shutil.copy2(widget, target)
        os.chmod(target, 0o755)
        print("Home-screen shortcut: ~/.shortcuts/explorer.sh")
        print("  (pkg install termux-widget, then add the Termux:Widget widget)")
    print("Installed. Start it with:  twinpane")
    return 0


def _uninstall():
    prefix = os.environ.get("PREFIX", "")
    shutil.rmtree(os.path.join(prefix, "lib", "twinpane"), ignore_errors=True)
    try:
        os.unlink(os.path.join(prefix, "bin", "twinpane"))
    except OSError:
        pass
    print("Removed.")
    return 0


def main():
    argv = sys.argv[1:]
    if argv and argv[0] == "--install":
        return _install()
    if argv and argv[0] == "--uninstall":
        return _uninstall()
    if argv and argv[0] in ("--version", "-V"):
        print("twinpane " + VERSION + " (standalone)")
        return 0
    root = _extract()
    os.environ.setdefault("PYTHONPATH", root)
    sys.path.insert(0, root)
    from twinpane.ui import main as run
    return run(argv)


if __name__ == "__main__":
    sys.exit(main())
'''


def build_standalone(ver: str, output: str) -> str:
    """One file to copy to the phone - no unzip, no git, no internet."""
    import base64
    os.makedirs(DIST, exist_ok=True)
    target = os.path.join(DIST, output)
    buffer = tempfile.NamedTemporaryFile(suffix=".zip", delete=False)
    buffer.close()
    try:
        with zipfile.ZipFile(buffer.name, "w", zipfile.ZIP_DEFLATED) as zf:
            for rel in iter_sources():
                if rel.startswith(("dist/", "tests/", "docs/preview/")) or \
                        rel in ("build_dist.py", "tools_render.py",
                                "build-exe.bat", "TwinPane.bat", "README.md"):
                    continue
                zf.write(os.path.join(ROOT, rel), rel)
        with open(buffer.name, "rb") as handle:
            encoded = base64.encodebytes(handle.read()).decode("ascii")
        body = (STUB.replace("__VER__", ver)
                .replace("__PAYLOAD__", encoded))
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(body)
        os.chmod(target, 0o755)
        return target
    finally:
        os.unlink(buffer.name)


# ---------------------------------------------------------------------------
# portable zip
# ---------------------------------------------------------------------------

def build_zip(ver: str, output: str) -> str:
    os.makedirs(DIST, exist_ok=True)
    target = os.path.join(DIST, output)
    prefix = "%s-%s" % (PKG, ver)
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as zf:
        for rel in iter_sources():
            if rel.startswith("dist/"):
                continue
            arc = os.path.join(prefix, rel)
            info = zipfile.ZipInfo(arc)
            info.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if rel.endswith(".sh") or rel == "run.py" else 0o644
            info.external_attr = (mode | 0o100000) << 16
            with open(os.path.join(ROOT, rel), "rb") as handle:
                zf.writestr(info, handle.read())
        zf.writestr(os.path.join(prefix, "QUICKSTART.txt"),
                    "Twin-Pane Explorer %s\n"
                    "=========================\n\n"
                    "Termux (recommended):\n"
                    "  pkg install python\n"
                    "  termux-setup-storage\n"
                    "  cd %s && ./run.py\n"
                    "or install the .deb:\n"
                    "  pkg install ./twinpane_%s_all.deb\n\n"
                    "Settings: python -m twinpane.config --json\n"
                    "Logs:     ~/.local/state/twinpane/logs/\n"
                    % (ver, prefix, ver))
    return target


# ---------------------------------------------------------------------------

def checksums(paths) -> str:
    lines = []
    for path in paths:
        digest = hashlib.sha256()
        with open(path, "rb") as handle:
            for chunk in iter(lambda: handle.read(1 << 20), b""):
                digest.update(chunk)
        lines.append("%s  %s" % (digest.hexdigest(), os.path.basename(path)))
    text = "\n".join(lines) + "\n"
    with open(os.path.join(DIST, "SHA256SUMS"), "w", encoding="utf-8") as handle:
        handle.write(text)
    return text


def main() -> int:
    ver = version()
    print("Twin-Pane Explorer %s" % ver)
    deb = build_deb(ver, "twinpane_%s_all.deb" % ver)
    print("  deb :", os.path.relpath(deb, ROOT),
          "%.1f KB" % (os.path.getsize(deb) / 1024))
    zipped = build_zip(ver, "twinpane-%s.zip" % ver)
    print("  zip :", os.path.relpath(zipped, ROOT),
          "%.1f KB" % (os.path.getsize(zipped) / 1024))
    standalone = build_standalone(ver, "twinpane-%s-standalone.py" % ver)
    print("  one file:", os.path.relpath(standalone, ROOT),
          "%.1f KB" % (os.path.getsize(standalone) / 1024))
    print(checksums([deb, zipped, standalone]), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
