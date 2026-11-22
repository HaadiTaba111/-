#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  Optional: home-screen shortcut for Termux:Widget
#
#  Termux:Widget runs scripts from ~/.shortcuts/ with one tap on the home
#  screen.  Copy this file there (install-termux.sh can do it for you):
#
#      mkdir -p ~/.shortcuts
#      cp twin-pane-explorer/termux-widget.sh ~/.shortcuts/explorer.sh
#      chmod +x ~/.shortcuts/explorer.sh
#
#  Then add the "Termux:Widget" widget on your launcher and pick "explorer".
#  Note: widgets run in the background terminal; the best experience is the
#  Termux "open new session" action, which this script requests itself.
# =============================================================================
set -e
APP_DIR="${TWINPANE_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export PYTHONPATH="$APP_DIR${PYTHONPATH:+:$PYTHONPATH}"

# Ask Termux to run the UI in a foreground session so the keyboard works.
if command -v termux-reload-settings >/dev/null 2>&1 && [ -z "$TWINPANE_IN_SESSION" ]; then
    if command -v am >/dev/null 2>&1; then
        # Fallback: run directly if am is unavailable.
        :
    fi
fi

exec python3 -m twinpane -l "$HOME" -r "${TWINPANE_RIGHT:-/sdcard}" "$@"
