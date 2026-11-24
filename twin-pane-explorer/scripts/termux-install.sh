#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
#  Twin-Pane Explorer - نصب و اجرای خودکار در Termux
#
#  یک دستور، همه‌چیز: کلون می‌کند، وابستگی‌ها را نصب می‌کند، دسترسی حافظه
#  می‌گیرد و برنامه را اجرا می‌کند.
#
#  استفاده:
#     bash termux-install.sh              # نصب + اجرا
#     bash termux-install.sh --install    # فقط نصب (بدون اجرا)
#     bash termux-install.sh --update     # فقط به‌روزرسانی کد و اجرا
#     bash termux-install.sh --run        # فقط اجرا (اگر نصب شده)
#     bash termux-install.sh --uninstall  # حذف
#     bash termux-install.sh --doctor     # عیب‌یابی محیط
#
#  نیازی به APK نیست. این راه، راه رسمی و تست‌شده است.
# =============================================================================
set -eu

REPO="${TWINPANE_REPO:-https://github.com/HaadiTaba111/-.git}"
SRC_DIR="${TWINPANE_SRC:-$HOME/twinpane-src}"
APP_SUBDIR="twin-pane-explorer"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BIN="$PREFIX/bin/twinpane"
BRIDGE_BIN="$PREFIX/bin/twinpane-bridge"
SERVICE_DIR="$PREFIX/var/service/twinpane-bridge"
LIB="$PREFIX/lib/twinpane"
BRIDGE_DIR="/sdcard/TwinPane/bridge"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- environment
in_termux() {
    [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ]
}

need_pkg() {
    for name in "$@"; do
        if ! dpkg -s "$name" >/dev/null 2>&1; then
            MISSING="$MISSING $name"
        fi
    done
    [ -z "${MISSING:-}" ]
}

install_deps() {
    say "بررسی پیش‌نیازها"
    if ! in_termux; then
        warn "این ترمکس نیست - از pip/npm رد می‌شوم و فقط پایتون را چک می‌کنم"
        command -v python3 >/dev/null || die "پایتون نصب نیست"
        ok "python3 موجود است"
        return
    fi
    command -v pkg >/dev/null || die "'pkg' پیدا نشد - مطمئن شو داخل Termux هستی"
    MISSING=""
    need_pkg python git ncurses-utils || true
    if [ -n "${MISSING:-}" ]; then
        say "نصب:$MISSING"
        # --no-install-recommends keeps the download small on mobile data
        pkg install -y $MISSING || die "pkg install $MISSING شکست خورد"
    fi
    ok "python $(python -c 'import sys;print(sys.version.split()[0])')"
    ok "git $(git --version | awk '{print $3}')"
}

storage_ok() {
    [ -d "$HOME/storage/shared" ] || [ -d /sdcard/Download ]
}

storage_access() {
    if storage_ok; then
        ok "دسترسی به حافظه‌ی گوشی برقرار است"
        return 0
    fi

    say "دسترسی به حافظه‌ی گوشی (لازم است)"
    if ! command -v termux-setup-storage >/dev/null 2>&1; then
        warn "termux-setup-storage نیست"
        return 1
    fi
    warn "اندروید یک پنجره نشان می‌دهد - Allow را بزن"
    termux-setup-storage >/dev/null 2>&1 || true

    # The dialog is asynchronous: give Android a moment to write the symlinks.
    attempt=0
    while [ $attempt -lt 20 ]; do
        storage_ok && { ok "دسترسی برقرار شد"; return 0; }
        sleep 0.5
        attempt=$((attempt + 1))
    done

    printf '\n'
    printf '\033[1;31m  ✗ اجازه‌ی حافظه داده نشد\033[0m\n'
    printf '\n'
    printf '  بدون این اجازه، برنامه نمی‌تواند فایل‌های گوشی را ببیند و\n'
    printf '  worker ترمکس هیچ راهی برای حرف‌زدن با اپ ندارد.\n'
    printf '\n'
    printf '  یک بار این را بزن، در پنجره‌ی اندروید Allow را انتخاب کن،\n'
    printf '  بعد همین نصب‌کننده را دوباره اجرا کن:\n'
    printf '\n'
    printf '      termux-setup-storage\n'
    printf '\n'
    return 1
}

fetch_source() {
    if [ -d "$SRC_DIR/.git" ]; then
        say "به‌روزرسانی کد در $SRC_DIR"
        git -C "$SRC_DIR" fetch --depth 1 origin main >/dev/null 2>&1 || true
        git -C "$SRC_DIR" reset --hard origin/main >/dev/null 2>&1 || \
            git -C "$SRC_DIR" pull --ff-only >/dev/null 2>&1 || \
            warn "به‌روزرسانی نشد - از نسخه‌ی موجود استفاده می‌کنم"
        ok "کد به‌روز شد"
    else
        say "کلون از $REPO"
        rm -rf "$SRC_DIR"
        # --depth 1: only the current snapshot, ~1MB instead of the whole history
        git clone --depth 1 "$REPO" "$SRC_DIR" || die "کلون شکست خورد (اینترنت؟)"
        ok "کلون شد در $SRC_DIR"
    fi
    [ -d "$SRC_DIR/$APP_SUBDIR/twinpane" ] || \
        die "پوشه‌ی برنامه در کلون نبود: $SRC_DIR/$APP_SUBDIR"
}

install_app() {
    fetch_source
    say "نصب در $LIB"
    mkdir -p "$LIB"
    # start clean, keep the folder itself
    find "$LIB" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    ( cd "$SRC_DIR/$APP_SUBDIR" && tar -cf - \
        --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' \
        --exclude='dist' --exclude='tests' --exclude='docs/preview' \
        run.py twinpane termux-widget.sh 2>/dev/null ) \
        | ( cd "$LIB" && tar -xf - )

    cat > "$BIN" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec python "$LIB/run.py" "\$@"
EOF
    chmod 755 "$BIN"
    ok "دستور twinpane نصب شد"

    # The bridge worker: what makes the Android app able to move files
    # between Termux and the phone. It reads a folder both sides can see.
    cat > "$BRIDGE_BIN" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec python "$LIB/run.py" --bridge "\$@"
EOF
    chmod 755 "$BRIDGE_BIN"
    ok "دستور twinpane-bridge نصب شد"

    mkdir -p "$BRIDGE_DIR"/{requests,work,results} 2>/dev/null || true
    if [ -d "$BRIDGE_DIR" ]; then
        ok "پوشه‌ی bridge: $BRIDGE_DIR"
    else
        warn "پوشه‌ی bridge ساخته نشد - termux-setup-storage را بزن"
    fi

    # Optional background service (termux-services). Not required: the app
    # can also start the worker itself for one batch.
    if [ -d "$PREFIX/var/service" ] || command -v sv >/dev/null 2>&1; then
        mkdir -p "$SERVICE_DIR"
        cat > "$SERVICE_DIR/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec 2>&1
exec twinpane-bridge
EOF
        chmod 755 "$SERVICE_DIR/run"
        ok "سرویس پس‌زمینه: sv-enable twinpane-bridge"
    fi

    # home-screen shortcut for Termux:Widget, when available
    mkdir -p "$HOME/.shortcuts"
    if [ -f "$LIB/termux-widget.sh" ]; then
        cp "$LIB/termux-widget.sh" "$HOME/.shortcuts/explorer.sh"
        chmod 755 "$HOME/.shortcuts/explorer.sh"
        ok "شورتکات صفحه‌ی خانه: ~/.shortcuts/explorer.sh"
    fi
}

selftest() {
    say "تست سریع"
    python - "$LIB" <<'PY'
import os, sys, tempfile, zipfile
sys.path.insert(0, sys.argv[1])
from twinpane import fsops
import twinpane
print("    version   :", twinpane.__version__)
tmp = tempfile.mkdtemp()
src = os.path.join(tmp, "a.txt")
open(src, "w").write("hello\n")
arc = os.path.join(tmp, "t.zip")
with zipfile.ZipFile(arc, "w") as z:
    z.write(src, "a.txt")
out = os.path.join(tmp, "out")
os.makedirs(out)
fsops.extract_archive(arc, out, overwrite="always")
assert os.path.exists(os.path.join(out, "a.txt"))
print("    zip/unzip : ok")
PY
    ok "برنامه سالم است"
}

run_app() {
    say "اجرای Twin-Pane Explorer"
    say "  پنل چپ = خانه‌ی ترمکس، پنل راست = حافظه‌ی گوشی"
    say "  راهنما: F1    منو: F9    خروج: F10"
    echo
    exec twinpane "$@"
}

doctor() {
    say "عیب‌یابی"
    echo "  TERMUX_VERSION : ${TERMUX_VERSION:-<خالی>}"
    echo "  PREFIX         : $PREFIX"
    echo "  HOME           : $HOME"
    echo "  TERM           : ${TERM:-<خالی>}"
    echo "  LANG           : ${LANG:-<خالی>}"
    command -v python >/dev/null && echo "  python         : $(python -c 'import sys;print(sys.version.split()[0])')" || echo "  python         : ندارد"
    command -v git >/dev/null && echo "  git            : $(git --version|awk '{print $3}')" || echo "  git            : ندارد"
    [ -x "$BIN" ] && echo "  twinpane       : نصب شده" || echo "  twinpane       : نصب نشده"
    [ -x "$BRIDGE_BIN" ] && echo "  twinpane-bridge: نصب شده" || echo "  twinpane-bridge: نصب نشده"
    [ -d "$BRIDGE_DIR" ] && echo "  bridge folder  : ✅ $BRIDGE_DIR" || echo "  bridge folder  : ❌"
    [ -f "$BRIDGE_DIR/worker.json" ] \
        && echo "  worker heartbeat: ✅" || echo "  worker heartbeat: ❌ (ترمکس: twinpane-bridge)"
    [ -d "$HOME/storage/shared" ] && echo "  storage        : ✅" || echo "  storage        : ❌ (termux-setup-storage)"
    [ -d /sdcard ] && echo "  /sdcard        : ✅" || echo "  /sdcard        : ❌"
    if [ -f "$HOME/.termux/termux.properties" ]; then
        grep -q "allow-external-apps=true" "$HOME/.termux/termux.properties" \
            && echo "  external-apps  : ✅" || echo "  external-apps  : ❌ (برای APK لازم است)"
    else
        echo "  termux.properties : ندارد"
    fi
    # can we actually read the phone storage?
    if [ -d "$HOME/storage/shared" ]; then
        ls "$HOME/storage/shared" >/dev/null 2>&1 \
            && echo "  read storage   : ✅" || echo "  read storage   : ❌ Permission denied"
    fi
}

uninstall() {
    say "حذف"
    rm -f "$BIN"
    rm -rf "$LIB" "$HOME/.shortcuts/explorer.sh"
    ok "حذف شد (کد منبع در $SRC_DIR باقی ماند)"
}

# --------------------------------------------------------------------- main
case "${1:-}" in
    --help|-h)  sed -n '2,20p' "$0"; exit 0 ;;
    --uninstall) uninstall; exit 0 ;;
    --doctor)   doctor; exit 0 ;;
    --run)      shift; command -v twinpane >/dev/null || die "اول نصب کن: bash $0 --install"; run_app "$@" ;;
    --install)  install_deps
                if ! storage_access; then
                    die "نصب متوقف شد - اول termux-setup-storage را اجرا کن"
                fi
                install_app; selftest
                echo; ok "تمام. اجرا با: twinpane" ;;
    --update)   install_deps; fetch_source; install_app; selftest; shift || true; run_app ;;
    *)
        install_deps
        if ! storage_access; then
            printf '\n  اگر می‌خواهی بدون دسترسی حافظه ادامه بدهم: bash %s --install --no-storage\n\n' "$0"
            die "نصب متوقف شد - اول termux-setup-storage را اجرا کن"
        fi
        install_app
        selftest
        echo
        run_app "$@"
        ;;
esac
