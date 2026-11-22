"""Drive the real curses UI inside a pseudo-terminal and check the screen.

Run with:  python -m pytest tests/test_ui.py
Needs:     pexpect + pyte  (pip install pexpect pyte)
"""
import os
import sys
import time

import pytest

pexpect = pytest.importorskip("pexpect")
pyte = pytest.importorskip("pyte")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV = dict(os.environ)
ENV.update({
    "TERM": "xterm-256color",
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8",
    "PYTHONPATH": ROOT,
    "TWINPANE_ASCII": "",
    "ESCDELAY": "25",
})


class Screen:
    def __init__(self, cols=110, rows=32):
        self.stream = pyte.Stream()
        self.screen = pyte.Screen(cols, rows)
        self.stream.attach(self.screen)

    def pump(self, child, seconds=0.6):
        end = time.time() + seconds
        while time.time() < end:
            try:
                data = child.read_nonblocking(65536, timeout=0.05)
            except pexpect.TIMEOUT:
                continue
            except pexpect.EOF:
                break
            self.stream.feed(data.decode("utf-8", "replace"))

    def text(self):
        return "\n".join(self.screen.display)

    def line(self, n):
        return self.screen.display[n]


def start(tmp_path, left, right, extra_env=None):
    env = dict(ENV)
    if extra_env:
        env.update(extra_env)
    child = pexpect.spawn(
        sys.executable, ["-m", "twinpane", "-l", str(left), "-r", str(right), "-q"],
        cwd=ROOT, env=env, dimensions=(32, 110), timeout=10)
    scr = Screen(110, 32)
    scr.pump(child, 1.2)
    return child, scr


@pytest.fixture()
def tree(tmp_path):
    # short paths so they fit inside the 110-column panel titles
    termux = tmp_path / "home"
    sdcard = tmp_path / "sdcard"
    termux.mkdir()
    sdcard.mkdir()
    (termux / "notes.txt").write_text("hello from termux\n")
    (termux / "report.pdf").write_text("%PDF-fake")
    proj = termux / "project"
    proj.mkdir()
    (proj / "main.py").write_text("print('hi')\n")
    (termux / ".bashrc").write_text("export A=1\n")
    return termux, sdcard


def test_starts_and_shows_both_panels(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        text = scr.text()
        assert "Twin-Pane Explorer" in text
        assert "home" in text and "sdcard" in text
        assert "notes.txt" in text
        assert "[project]" in text
        assert "<DIR>" in text
        assert "5 Copy" in text
        assert "Tab=switch" in text
    finally:
        child.send("q")
        child.close(force=True)


def test_enter_opens_folder_then_backspace_goes_up(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        # cursor starts on 'project' because folders sort first
        child.send("\r")
        scr.pump(child)
        assert "[main.py]" in scr.text() or "main.py" in scr.text()
        child.send("\x7f")  # backspace -> parent
        scr.pump(child)
        assert "notes.txt" in scr.text()
        assert "main.py" not in scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_tab_moves_focus_between_panels(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        assert "(empty folder)" in scr.text()
        child.send("\t")          # focus right (empty) panel
        scr.pump(child, 0.5)
        child.send("\r")          # Enter in empty panel -> parent folder
        scr.pump(child, 0.6)
        assert "[home]" in scr.text() or "[sdcard]" in scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_copy_file_to_other_panel_with_keyboard(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        # cursor starts on 'project' (folders first). Move to notes.txt.
        for _ in range(2):
            child.send("\x1b[B")   # Down
            scr.pump(child, 0.2)
        # select it; select moves down automatically
        child.send(" ")
        scr.pump(child, 0.3)
        child.send("c")           # copy
        scr.pump(child, 0.8)
        child.send("y")           # confirm dialog default yes
        scr.pump(child, 1.5)
        # any post-transfer key to clear message
        assert (sdcard / "notes.txt").exists(), scr.text()
        assert (sdcard / "notes.txt").read_text() == "hello from termux\n"
        assert (termux / "notes.txt").exists()   # copy keeps source
    finally:
        child.send("\x1b")
        scr.pump(child, 0.2)
        child.send("q")
        child.close(force=True)


def test_delete_with_confirmation(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        for _ in range(2):
            child.send("\x1b[B")
            scr.pump(child, 0.2)
        child.send(" ")
        scr.pump(child, 0.3)
        child.send("\x1b[19~")    # F8
        scr.pump(child, 0.8)
        assert "Delete" in scr.text()
        child.send("y")
        scr.pump(child, 1.2)
        assert not (termux / "notes.txt").exists(), scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_new_folder_via_f7(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        child.send("\x1b[18~")   # F7
        scr.pump(child, 0.7)
        assert "New folder" in scr.text()
        child.send("my_new_dir")
        scr.pump(child, 0.3)
        child.send("\r")
        scr.pump(child, 1.0)
        assert (termux / "my_new_dir").is_dir(), scr.text()
        assert "my_new_dir" in scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_help_overlay_and_quit(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        child.send("\x1bOP")   # F1
        scr.pump(child, 1.0)
        assert "MOVING AROUND" in scr.text() or "Help" in scr.text()
        child.send("q")
        scr.pump(child, 0.4)
        assert "Twin-Pane" in scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_move_across_panels(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        for _ in range(2):
            child.send("\x1b[B")
            scr.pump(child, 0.2)
        child.send(" ")
        scr.pump(child, 0.3)
        child.send("m")
        scr.pump(child, 0.8)
        child.send("y")
        scr.pump(child, 1.5)
        assert (sdcard / "notes.txt").exists(), scr.text()
        assert not (termux / "notes.txt").exists(), scr.text()
    finally:
        child.send("\x1b")
        scr.pump(child, 0.2)
        child.send("q")
        child.close(force=True)


def test_escape_clears_selection(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        child.send("\x1b[B")
        scr.pump(child, 0.3)
        child.send(" ")
        scr.pump(child, 0.4)
        assert "*1*" in scr.text()
        child.send("\x1b")
        scr.pump(child, 0.4)
        assert "*1*" not in scr.text()
        assert "Selection cleared" in scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_refuses_tiny_terminal(tree):
    termux, sdcard = tree
    child = pexpect.spawn(
        sys.executable, ["-m", "twinpane", "-l", str(termux), "-r", str(sdcard), "-q"],
        cwd=ROOT, env=ENV, dimensions=(6, 20), timeout=10)
    scr = Screen(20, 6)
    scr.pump(child, 1.2)
    try:
        assert "too small" in scr.text().lower()
        child.send("q")
        child.close(force=True)
        assert child.exitstatus in (0, None) or child.signalstatus is not None
    finally:
        child.close(force=True)
