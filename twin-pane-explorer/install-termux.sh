#!/data/data/com.termux/files/usr/bin/bash
# Twin-Pane Explorer - one-shot installer for Termux (no root needed).
#
#   bash install-termux.sh              # install from this checkout
#   bash install-termux.sh --deb        # install the prebuilt .deb
#   bash install-termux.sh --uninstall  # remove it again
#
# It installs python + ncurses, sets up shared-storage access, then puts a
# `twinpane` command on $PATH.  Re-running it upgrades in place.

set -eu

APP=twinpane
HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
DEB=$(ls "$HERE"/dist/twinpane_*_all.deb 2>/dev/null | tail -1 || true)

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

need_termux() {
    [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ] || \
        warn "This does not look like Termux - continuing anyway."
}

uninstall() {
    say "Removing $APP"
    rm -f "$PREFIX/bin/$APP"
    rm -rf "$PREFIX/lib/$APP"
    say "Removed. Config in ~/.config/twinpane was left alone."
    exit 0
}

install_deb() {
    [ -n "$DEB" ] || die "No .deb found in $HERE/dist - run: python build_dist.py"
    say "Installing $(basename "$DEB")"
    if command -v pkg >/dev/null 2>&1; then
        pkg install -y "$DEB"
    else
        dpkg -i "$DEB"
    fi
}

install_source() {
    say "Installing from $HERE"
    mkdir -p "$PREFIX/lib/$APP"
    # copy the program, skipping caches, tests and build output
    ( cd "$HERE" && tar -cf - \
        --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' \
        --exclude='dist' --exclude='tests' --exclude='docs/preview' \
        --exclude='.pytest_cache' run.py twinpane 2>/dev/null ) \
        | ( cd "$PREFIX/lib/$APP" && tar -xf - )
    cat > "$PREFIX/bin/$APP" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec python "$PREFIX/lib/$APP/run.py" "\$@"
EOF
    chmod 755 "$PREFIX/bin/$APP"
}

bootstrap() {
    say "Installing dependencies (python, ncurses-utils)"
    if command -v pkg >/dev/null 2>&1; then
        pkg update -y >/dev/null 2>&1 || true
        pkg install -y python ncurses-utils || die "pkg install failed"
    else
        warn "No 'pkg' command - install python3 + ncurses yourself."
    fi
}

storage() {
    if [ ! -d "$HOME/storage/shared" ]; then
        say "Granting access to phone storage (Android will ask once)"
        if command -v termux-setup-storage >/dev/null 2>&1; then
            termux-setup-storage || warn "Storage setup cancelled - you can re-run it later."
        else
            warn "termux-setup-storage missing (pkg install termux-tools)."
        fi
    fi
}

keyboard() {
    # The extra-keys row makes F5/F6/F8 reachable on a phone soft keyboard.
    local props="$HOME/.termux/termux.properties"
    if [ -f "$HERE/docs/termux.properties" ]; then
        mkdir -p "$HOME/.termux"
        if grep -q 'Twin-Pane Explorer' "$props" 2>/dev/null; then
            say "Extra-keys already configured"
        else
            say "Adding Twin-Pane extra keys to $props"
            if [ -f "$props" ]; then cp "$props" "$props.bak.$$"; fi
            cat "$HERE/docs/termux.properties" >> "$props"
            command -v termux-reload-settings >/dev/null 2>&1 && \
                termux-reload-settings || warn "Reopen Termux to load the extra keys."
        fi
    fi
}

selftest() {
    say "Self-test"
    python - "$PREFIX/lib/$APP" <<'PY'
import os, sys, tempfile, zipfile
root = sys.argv[1]
sys.path.insert(0, root)
from twinpane import fsops, config
print("  version   :", __import__("twinpane").__version__)
print("  config    :", config.config_path())
tmp = tempfile.mkdtemp()
src = os.path.join(tmp, "a.txt")
open(src, "w").write("hello\n")
arc = os.path.join(tmp, "t.zip")
with zipfile.ZipFile(arc, "w") as z:
    z.write(src, "a.txt")
out = os.path.join(tmp, "out")
os.makedirs(out)
fsops.extract_archive(arc, out, overwrite="always")
assert os.path.exists(os.path.join(out, "a.txt")), "extract failed"
print("  zip/unzip : ok")
print("  Result    : ready")
PY
}

main() {
    case "${1:-}" in
        --uninstall) uninstall ;;
        --deb)       need_termux; bootstrap; install_deb ;;
        --help|-h)   sed -n '2,12p' "$0"; exit 0 ;;
        *)           need_termux; bootstrap; storage; install_source; keyboard ;;
    esac
    selftest
    say "Done. Start it with:  twinpane"
    say "Settings:  python -m twinpane.config --json     Logs: ~/.local/state/twinpane/logs"
}

main "$@"
