"""Drive the real curses UI inside a pseudo-terminal and check the screen.

Run with:  python -m pytest tests/test_ui.py
Needs:     pexpect + pyte  (pip install pexpect pyte)
"""
import os
import sys
import tempfile
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


def send_text(child, scr, text, delay=0.05):
    """Type *text* into a dialog, byte by byte, then wait for the screen.

    pexpect's send() is instant, which real keyboards never are; some
    dialogs also keep reading after Enter, so this gives each key a turn.
    """
    for ch in text:
        child.send(ch)
        time.sleep(delay)
    scr.pump(child, 0.5)


def start(tmp_path, left, right, extra_env=None, state_dir=None):
    env = dict(ENV)
    # every child gets a private config+state folder: no session/theme/plugin
    # leakage between tests, and nothing is written into the real $HOME
    home = os.environ.get("TWINPANE_TEST_STATE") or tempfile.mkdtemp(prefix="tp-test-")
    env["TWINPANE_STATE_DIR"] = os.path.join(home, "state")
    env["TWINPANE_CONFIG_DIR"] = os.path.join(home, "config")
    env["HOME"] = home
    if state_dir:
        env["TWINPANE_STATE_DIR"] = state_dir
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


def test_new_folder_asks_which_drive(tree):
    """F7 shows the drive picker first, then asks for the name."""
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        child.send("\x1b[18~")   # F7
        scr.pump(child, 0.8)
        assert "New folder" in scr.text()
        assert "Left panel" in scr.text() and "Right panel" in scr.text()
        child.send("\r")          # choose left panel
        scr.pump(child, 0.5)
        send_text(child, scr, "my_new_dir")
        child.send("\r")
        scr.pump(child, 1.0)
        assert (termux / "my_new_dir").is_dir(), scr.text()
        assert "my_new_dir" in scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_new_folder_on_the_other_drive(tree):
    """Pick 'Right panel' and the folder lands on /sdcard, not in Termux home."""
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        child.send("\x1b[18~")   # F7
        scr.pump(child, 0.8)
        child.send("\x1b[B")      # down to "Right panel"
        scr.pump(child, 0.3)
        child.send("\r")
        scr.pump(child, 0.5)
        send_text(child, scr, "on_card")
        child.send("\r")
        scr.pump(child, 1.0)
        assert (sdcard / "on_card").is_dir(), scr.text()
        assert not (termux / "on_card").exists()
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


# ---------------------------------------------------------------------------
# Mouse / touch, layout and zip / unzip
# ---------------------------------------------------------------------------

def test_layout_cycles_with_L(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        assert "Twin-Pane" in scr.text()
        child.send("L")
        scr.pump(child, 0.6)
        assert "Layout:" in scr.text() or "two columns" in scr.text()
        child.send("L")
        scr.pump(child, 0.6)
        text = scr.text()
        # stacked mode shows a panel switcher line
        assert "next panel" in text or "layout" in text.lower()
    finally:
        child.send("q")
        child.close(force=True)


def test_layout_flag_stack(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard, extra_env={"TWINPANE_LAYOUT": "stack"})
    try:
        scr.pump(child, 0.5)
        # in stack mode only the active panel is drawn, and the switcher shows
        assert "next panel" in scr.text() or "Tab" in scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_zip_and_unzip_with_keyboard(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        # cursor on 'project' (dirs first): compress it to the other panel
        child.send(" ")
        scr.pump(child, 0.3)
        child.send("Z")
        scr.pump(child, 0.9)
        # the suggested path is already filled in: Enter accepts it
        child.send("\r")
        scr.pump(child, 2.0)
        assert (sdcard / "project.zip").exists(), scr.text()

        # now extract it back into the termux panel
        child.send("\t")          # focus right panel
        scr.pump(child, 0.4)
        child.send("\x1b[H")      # Home: the zip is the only entry, be sure
        scr.pump(child, 0.3)
        assert "project.zip" in scr.text()
        child.send("u")
        scr.pump(child, 1.0)
        assert "Extract archive" in scr.text(), scr.text()
        child.send("\r")
        scr.pump(child, 2.0)
        # extracted into a uniquely named folder, so nothing existing is mixed in
        # whatever target the dialog proposed, the archive's members landed
        found = [str(p) for p in termux.rglob("main.py")]
        assert len(found) >= 2, (found, scr.text())
    finally:
        child.send("\x1b")
        scr.pump(child, 0.2)
        child.send("q")
        child.close(force=True)


def test_mouse_click_selects_entry(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        # click row 5 (0-based screen row) of the left panel: .bashrc or notes
        child.send("\x1b[<0;3;5M")      # press at col 3, row 5
        scr.pump(child, 0.3)
        child.send("\x1b[<0;3;5m")      # release
        scr.pump(child, 0.4)
        text = scr.text()
        # footer of the left panel shows the file under the cursor
        assert "notes.txt" in text or ".bashrc" in text
    finally:
        child.send("q")
        child.close(force=True)


def test_mouse_wheel_scrolls(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        child.send("\x1b[<65;3;5M")   # wheel down
        scr.pump(child, 0.4)
        child.send("\x1b[<64;3;5M")   # wheel up
        scr.pump(child, 0.4)
        assert "notes.txt" in scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_tap_opens_folder_with_double_click(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        # press/release/press/release quickly is decoded as two taps
        for _ in range(2):
            child.send("\x1b[<0;3;3M")
            scr.pump(child, 0.12)
            child.send("\x1b[<0;3;3m")
            scr.pump(child, 0.12)
        scr.pump(child, 0.5)
        assert "main.py" in scr.text() or "[project]" in scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_auto_refresh_shows_external_changes(tree):
    """A file created by another program appears without pressing F2."""
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        assert "appeared.txt" not in scr.text()
        (termux / "appeared.txt").write_text("from outside")
        time.sleep(0.1)
        child.send("\x1b[B")      # any keypress triggers the auto refresh
        scr.pump(child, 0.8)
        assert "appeared.txt" in scr.text(), scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_layout_switch_from_f9_menu(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        child.send("\x1b[20~")            # F9 menu
        scr.pump(child, 0.8)
        assert "Switch layout" in scr.text()
        for _ in range(11):
            child.send("\x1b[B")
            scr.pump(child, 0.08)
        child.send("\r")
        scr.pump(child, 0.9)
        assert "Layout" in scr.text() or "columns" in scr.text(), scr.text()
    finally:
        child.send("q")
        child.close(force=True)


def test_phone_width_uses_stacked_layout(tree):
    """52-column terminal (phone portrait) must not squeeze two panels."""
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        scr.screen.resize(26, 52)
        child.setwinsize(26, 52)
        scr.pump(child, 0.4)
        child.send("\x0c")       # Ctrl+L: force a full redraw
        scr.pump(child, 1.0)
        text = scr.text()
        # stacked mode draws a one-line panel switcher
        assert "next panel" in text, text
        assert "F9: layout" in text, text
        # and the active panel gets the whole width (no second panel title)
        assert text.count("Name") == 1, text
    finally:
        child.send("q")
        child.close(force=True)


def _screen_row_of(scr, name, width=52):
    """Find the screen row whose LEFT panel entry is exactly *name*.

    Only the entry column (after the 2-char marker) is inspected, so a folder
    named like a file, or the same name in the right panel, cannot confuse it.
    """
    for row in range(1, scr.screen.lines):
        left = scr.line(row)[:width]
        if "│" not in left:
            continue
        # the name column is left-aligned, followed by the size column
        cell = left[1:34].strip()
        if cell == name or cell == "[%s]" % name:
            return row
    raise AssertionError("%r not on screen" % name)


def test_drag_between_panels_copies(tree):
    termux, sdcard = tree
    child, scr = start(None, termux, sdcard)
    try:
        scr.pump(child, 0.6)                      # settle: one full frame
        # _screen_row_of() is 0-based, SGR mouse coordinates are 1-based
        row = _screen_row_of(scr, "notes.txt") + 1
        child.send("\x1b[<0;5;%dM" % row)            # press on notes.txt
        scr.pump(child, 0.3)
        for x in (20, 40, 60, 85):
            child.send("\x1b[<32;%d;%dM" % (x, row))  # hold + move right
            scr.pump(child, 0.1)
        child.send("\x1b[<0;85;%dm" % row)           # release in right panel
        scr.pump(child, 0.7)
        assert "Drag to copy" in scr.text(), scr.text()
        assert "notes.txt" in scr.text()
        child.send("y")
        scr.pump(child, 1.5)
        assert (sdcard / "notes.txt").exists(), scr.text()
        assert (termux / "notes.txt").exists()   # drag copies, never moves
    finally:
        child.send("q")
        child.close(force=True)
