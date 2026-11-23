#!/usr/bin/env python3
"""Render an HTML page with the real TUI screens (for docs/preview).

Usage:  python3 tools_render.py > /tmp/preview.html
Requires pexpect + pyte (pip install pexpect pyte) and a UTF-8 locale.
"""
import html
import json
import os
import sys
import tempfile
import time

try:
    import pexpect
    import pyte
except ImportError:
    sys.exit("pip install pexpect pyte")

ROOT = os.path.dirname(os.path.abspath(__file__))
COLS, ROWS = 96, 22


def capture(keys, left, right, settle=1.2, layout=None, cols=None, rows=None,
            state=None, setup_config=None):
    cols = cols or COLS
    rows = rows or ROWS
    env = dict(os.environ)
    # isolated state so the preview never touches (or resumes) real folders
    scratch = tempfile.mkdtemp(prefix="twinpane-preview-state-")
    if state is None:
        state = os.path.join(scratch, "state")
    env.update({"TERM": "xterm-256color", "LANG": "C.UTF-8",
                "PYTHONPATH": ROOT, "TWINPANE_STATE_DIR": state,
                "TWINPANE_CONFIG_DIR": os.path.join(scratch, "config"),
                "HOME": scratch})
    if setup_config:
        cfg_dir = os.path.join(scratch, "config")
        os.makedirs(cfg_dir, exist_ok=True)
        with open(os.path.join(cfg_dir, "config.json"), "w") as fh:
            json.dump(setup_config, fh)
    argv = [sys.executable, "-m", "twinpane", "-l", left, "-r", right, "-q"]
    if layout:
        argv += ["--layout", layout]
    child = pexpect.spawn(argv[0], argv[1:], cwd=ROOT, env=env,
                          dimensions=(rows, cols), timeout=15)
    screen = pyte.Screen(cols, rows)
    stream = pyte.Stream()
    stream.attach(screen)
    deadline = time.time() + settle
    while time.time() < deadline:
        try:
            stream.feed(child.read_nonblocking(65536, timeout=0.03)
                        .decode("utf-8", "replace"))
        except pexpect.TIMEOUT:
            pass
        except pexpect.EOF:
            break
    for key in keys:
        child.send(key)
        deadline = time.time() + 0.35
        while time.time() < deadline:
            try:
                stream.feed(child.read_nonblocking(65536, timeout=0.02)
                            .decode("utf-8", "replace"))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break
    text = "\n".join(screen.display)
    coloured = _colour_rows(screen)
    child.send("q")
    child.close(force=True)
    return text.rstrip(), coloured


def _colour_rows(screen):
    """Render the pyte buffer as HTML spans, keeping foreground/background.

    pyte already resolves SGR colours to hex (or leaves them as ``default``),
    so this is a straight translation into inline CSS.
    """
    def css(colour):
        if colour in (None, "default"):
            return ""
        text = str(colour).strip()
        if text.startswith("#"):
            return text
        if len(text) == 6 and all(ch in "0123456789abcdefABCDEF" for ch in text):
            return "#" + text.lower()          # pyte style: 'ff8700'
        if text.isdigit():
            return "#%02x%02x%02x" % ((int(text) >> 16) & 255,
                                      (int(text) >> 8) & 255,
                                      int(text) & 255)
        return ""

    rows = []
    for y in range(screen.lines):
        line = screen.buffer[y]
        out = []
        for x in range(screen.columns):
            cell = line[x]
            bg = css(cell.bg)
            if not cell.data or not cell.data.strip():
                if bg:
                    out.append("<span style='background:%s'>&nbsp;</span>" % bg)
                else:
                    out.append(" ")
                continue
            style = []
            fg = css(cell.fg)
            if fg:
                style.append("color:%s" % fg)
            if bg:
                style.append("background:%s" % bg)
            if cell.bold:
                style.append("font-weight:700")
            if cell.italics:
                style.append("font-style:italic")
            if cell.underscore:
                style.append("text-decoration:underline")
            if cell.reverse:
                style.append("filter:invert(1)")
            text = html.escape(cell.data)
            if style:
                out.append("<span style='%s'>%s</span>" % (";".join(style), text))
            else:
                out.append(text)
        rows.append("".join(out).rstrip())
    while rows and not rows[-1].strip():
        rows.pop()
    return rows


def make_demo_tree():
    base = tempfile.mkdtemp(prefix="twinpane-preview-")
    home = os.path.join(base, "home")
    card = os.path.join(base, "sdcard")
    for path in (os.path.join(home, "Download"), os.path.join(home, "projects"),
                 os.path.join(card, "DCIM", "Camera"), os.path.join(card, "Download")):
        os.makedirs(path, exist_ok=True)
    files = {
        os.path.join(home, "notes.txt"): "salam from termux\n",
        os.path.join(home, "backup.tar.gz"): "x" * 2400000,
        os.path.join(home, "setup.sh"): "#!/bin/sh\n",
        os.path.join(card, "download.zip"): "y" * 4300000,
        os.path.join(card, "DCIM", "Camera", "photo.jpg"): "z" * 890000,
        os.path.join(card, "Download", "report.pdf"): "%PDF\n",
    }
    for path, content in files.items():
        with open(path, "w") as fh:
            fh.write(content)
    os.chmod(os.path.join(home, "setup.sh"), 0o755)
    with open(os.path.join(home, ".bashrc"), "w") as fh:
        fh.write("export PATH=$PATH:$HOME/bin\n")
    return home, card


SCREENS = []


def build():
    home, card = make_demo_tree()
    SCREENS.append(("Two panels",
                    "چپ: خانه‌ی Termux — راست: /sdcard. دوصفحه، دقیقاً مثل NC.",
                    capture([], home, card)))
    SCREENS.append(("Selection",
                    "با Space چند فایل انتخاب شده (•) و شمارنده *2* بالای پنل.",
                    capture(["\x1b[B", "\x1b[B", " ", "\x1b[B", " "], home, card)))
    SCREENS.append(("Copy confirm",
                    "قبل از هر کپی، مبدأ و مقصد نشان داده می‌شود.",
                    capture(["\x1b[B", "\x1b[B", " ", "\x1b[B", " ", "c"],
                            home, card)))
    SCREENS.append(("Drag between panels",
                    "کشیدن با انگشت/ماوس از پنل چپ به راست = کپی (با تایید).",
                    capture(["\x1b[<0;5;6M", "\x1b[<32;30;6M",
                             "\x1b[<32;60;6M", "\x1b[<32;90;6M"], home, card)))
    SCREENS.append(("Quick menu (Q)",
                    "همه‌ی دستورها در یک لیست — برای گوشی که F-key ندارد.",
                    capture(["Q"], home, card, settle=1.4)))
    SCREENS.append(("zip / unzip menu (x)",
                    "فشرده‌سازی zip و tar.gz، استخراج، و پیش‌نمایش محتوا.",
                    capture(["x"], home, card, settle=1.4)))
    SCREENS.append(("Phone layout (stacked)",
                    "در عرض کم، یک پنل تمام‌عرض با سوئیچر بالای آن.",
                    capture([], home, card, layout="stack", cols=56, rows=24)))
    SCREENS.append(("Help (F1)",
                    "راهنمای کامل کلیدها و ماوس.",
                    capture(["\x1bOP"], home, card, settle=1.4)))
    SCREENS.append(("Settings - every knob (S)",
                    "صفحه‌ی تنظیمات از روی schema ساخته می‌شود: ۲۹ پارامتر، "
                    "بدون کد تکراری. Enter = تغییر، Esc = برگشت.",
                    capture(["S"], home, card, settle=1.8, rows=34)))
    SCREENS.append(("Activity log - daily (G)",
                    "لاگ روزانه: هر اقدام با ساعت، هدف و جزئیات. "
                    "لاگ خطاها فایل جدا با traceback کامل دارد.",
                    capture(["\r", "G"], home, card, settle=1.6)))
    for theme, note in [("midnight", "سرمه‌ای"),
                        ("amber", "کهربایی - شبیه ترمینال‌های قدیمی"),
                        ("dracula", "دراکولا"),
                        ("paper", "روشن برای آفتاب"),
                        ("gruvbox", "گراو‌باکس")]:
        SCREENS.append(("Theme: %s" % theme,
                        "t = تم بعدی، یا از Settings. این تم %s است." % note,
                        capture([], home, card, settle=1.3,
                                setup_config={"ui.theme": theme})))


PAGE = """<!doctype html>
<meta charset="utf-8">
<title>Twin-Pane Explorer - preview</title>
<style>
  body {{ background:#11151c; color:#d7dee8; font-family:ui-sans-serif,system-ui,sans-serif;
          margin:0; padding:32px; }}
  h1 {{ font-size:22px; margin:0 0 4px; }}
  p.sub {{ color:#8b98a8; margin:0 0 28px; font-size:14px; }}
  section {{ margin-bottom:34px; }}
  h2 {{ font-size:15px; color:#9ecbff; margin:0 0 2px; }}
  .note {{ color:#8b98a8; font-size:12.5px; margin:0 0 8px; }}
  pre {{ background:#0b0f14; border:1px solid #1e2733; border-radius:8px;
         padding:14px 16px; overflow-x:auto; font:13px/1.25 "JetBrains Mono",
         "Cascadia Code", ui-monospace, monospace; color:#cfd8e3; }}
  pre.term {{ background:#000; padding:10px 0; line-height:1.2; }}
  pre.term span {{ border-radius:0; }}
  h2 {{ margin-top:6px; }}
  .tag {{ display:inline-block; font-size:11px; color:#7ee787; border:1px solid #1f6f3f;
          border-radius:99px; padding:1px 8px; margin-left:8px; vertical-align:2px; }}
</style>
<h1>Twin-Pane Explorer</h1>
<p class="sub">Termux two-panel file manager - real screens captured from the running app</p>
{sections}
"""


def main():
    build()
    sections = []
    for entry in SCREENS:
        title, note, shot = entry
        plain, coloured = shot
        body = "\n".join(coloured) if coloured else html.escape(plain)
        sections.append(
            "<section><h2>%s</h2><p class='note'>%s</p>"
            "<pre class='term'>%s</pre></section>"
            % (html.escape(title), note, body))
    sys.stdout.write(PAGE.format(sections="\n".join(sections)))


if __name__ == "__main__":
    main()
