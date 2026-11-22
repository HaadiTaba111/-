#!/usr/bin/env python3
"""Render an HTML page with the real TUI screens (for docs/preview).

Usage:  python3 tools_render.py > /tmp/preview.html
Requires pexpect + pyte (pip install pexpect pyte) and a UTF-8 locale.
"""
import html
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


def capture(keys, left, right, settle=1.2):
    env = dict(os.environ)
    env.update({"TERM": "xterm-256color", "LANG": "C.UTF-8",
                "PYTHONPATH": ROOT})
    child = pexpect.spawn(sys.executable,
                          ["-m", "twinpane", "-l", left, "-r", right, "-q"],
                          cwd=ROOT, env=env,
                          dimensions=(ROWS, COLS), timeout=15)
    screen = pyte.Screen(COLS, ROWS)
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
    child.send("q")
    child.close(force=True)
    return text.rstrip()


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
    SCREENS.append(("Two panels", "خانه‌ی Termux در چپ، حافظه‌ی گوشی /sdcard در راست",
                    capture([], home, card)))
    SCREENS.append(("Selection", "انتخاب چند فایل با Space، سپس F5",
                    capture(["\x1b[B", "\x1b[B", " ", "\x1b[B", " "], home, card)))
    SCREENS.append(("Copy confirm", "تاییدیه‌ی کپی با نمایش مبدأ و مقصد",
                    capture(["\x1b[B", "\x1b[B", " ", "\x1b[B", " ", "c"],
                            home, card)))
    SCREENS.append(("Help", "راهنمای کلیدها با F1",
                    capture(["\x1bOP"], home, card, settle=1.4)))


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
</style>
<h1>Twin-Pane Explorer</h1>
<p class="sub">Termux two-panel file manager - real screens captured from the running app</p>
{sections}
"""


def main():
    build()
    sections = []
    for title, note, text in SCREENS:
        sections.append("<section><h2>%s</h2><p class='note'>%s</p><pre>%s</pre></section>"
                        % (html.escape(title), note, html.escape(text)))
    sys.stdout.write(PAGE.format(sections="\n".join(sections)))


if __name__ == "__main__":
    main()
