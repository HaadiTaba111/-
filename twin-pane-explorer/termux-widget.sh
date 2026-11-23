#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  Home-screen shortcut: one tap opens Twin-Pane Explorer
#
#  Two ways to get an icon (both work without root and without an APK):
#
#  A) Termux:Widget  (pkg install termux-widget - from F-Droid)
#       mkdir -p ~/.shortcuts
#       cp termux-widget.sh ~/.shortcuts/explorer.sh
#       chmod +x ~/.shortcuts/explorer.sh
#     then long-press the home screen -> Widgets -> Termux:Widget -> "explorer"
#
#  B) Termux:API "Termux:Tasker" style tile / Shortcuts app:
#       ~/.shortcuts/tasks/ is used for background runs; this file is meant for
#       ~/.shortcuts/ so it gets a foreground terminal.
#
#  Optional environment knobs:
#     TWINPANE_RIGHT=/sdcard/Download   right panel folder
#     TWINPANE_LEFT=~/Download          left panel folder
# =============================================================================
set -u

# Resolve the app folder: installed package first, then the script's own folder.
APP_DIR="${TWINPANE_HOME:-}"
if [ -z "$APP_DIR" ]; then
    if [ -f "$PREFIX/lib/twinpane/run.py" ]; then
        APP_DIR="$PREFIX/lib/twinpane"
    else
        APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
fi

LEFT="${TWINPANE_LEFT:-$HOME}"
RIGHT="${TWINPANE_RIGHT:-}"
if [ -z "$RIGHT" ]; then
    for candidate in /sdcard "$HOME/storage/shared" "$HOME/storage/downloads"; do
        [ -d "$candidate" ] && RIGHT="$candidate" && break
    done
fi
[ -z "$RIGHT" ] && RIGHT="$HOME"

# A widget can fire before storage permission is granted; tell the user once.
if [ "$RIGHT" = "$HOME" ] && [ ! -d "$HOME/storage" ]; then
    echo "Tip: run 'termux-setup-storage' once to reach your phone storage."
    sleep 2
fi

cd "$APP_DIR" || exit 1
exec python -m twinpane -l "$LEFT" -r "$RIGHT" "$@"
