"""Twin-Pane Explorer - a Norton-Commander style file manager for Termux.

Keys
----
  Up/Down            move cursor          Tab / Left/Right  switch panel
  Enter              open folder          Backspace / ..    go to parent
  Space              select, then move    + / -             select all / none
  PgUp/PgDn/Home/End                       i                 item details
  c                  COPY  -> other panel m                 MOVE -> other panel
  F5                 copy (same as c)      F6                move (same as m)
  F7                 new folder            F8 / Del          delete
  F3 / v             view file             F4                edit config
  r / Ctrl+R         rename                o                 actions menu
  a / Ctrl+H         hidden files          z / f             list filter
  /  or Ctrl+G       go to path            F2                refresh
  F9                 menu                  F10 / q           quit
  Esc                cancel / clear selection
"""
from __future__ import annotations

import argparse
import curses
import os
import shutil
import subprocess
import sys
import time

from . import fsops
from .fsops import Entry

APP_TITLE = "Twin-Pane Explorer"
MIN_H, MIN_W = 10, 34


# ---------------------------------------------------------------------------
# Text / drawing helpers
# ---------------------------------------------------------------------------

ASCII_MODE = False

_EASCII = str.maketrans({
    "\u2500": "-", "\u2502": "|", "\u250c": "+", "\u2510": "+",
    "\u2514": "+", "\u2518": "+", "\u2550": "=", "\u2551": "|",
    "\u2016": "|", "\u2026": "...", "\u00b7": "-", "\u2022": "*",
    "\u2191": "^", "\u2193": "v", "\u2192": ">", "\u2190": "<",
    "\u2588": "#", "\u2591": ".",
})


def T(text: str) -> str:
    return text.translate(_EASCII) if ASCII_MODE else text


def safe_addstr(win, y: int, x: int, text: str, attr: int = 0) -> None:
    """addstr() that tolerates the bottom-right cell and clipped windows."""
    if not text:
        return
    try:
        maxy, maxx = win.getmaxyx()
    except curses.error:
        return
    if y < 0 or y >= maxy or x >= maxx - 0:
        return
    room = maxx - x
    if room <= 0:
        return
    try:
        win.addstr(y, x, text[:room], attr)
    except curses.error:
        try:
            win.insstr(y, x, text[:room], attr)
        except curses.error:
            pass


def clip(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width == 1:
        return text[:1]
    return text[: width - 1] + "\u2026"


def clip_left(text: str, width: int) -> str:
    """Keep the *end* of a long path ('.../deep/folder') - the useful part."""
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width == 1:
        return text[-1:]
    return "\u2026" + text[-(width - 1):]


def draw_box(win, attr: int) -> None:
    """Frame a window.

    Unicode box drawing is written explicitly (not via the terminal's ACS
    alternate charset) because that renders identically in Termux, in screen/
    tmux and in every modern terminal, and stays single-width.  When the
    locale is not UTF-8 or --ascii was given, a pure ASCII frame is used.
    """
    h, w = win.getmaxyx()
    if h < 2 or w < 2:
        return
    if ASCII_MODE:
        horiz, vert, tl, tr, bl, br = "=", "|", "+", "+", "+", "+"
    else:
        horiz, vert, tl, tr, bl, br = "\u2500", "\u2502", "\u250c", "\u2510", "\u2514", "\u2518"
    try:
        win.attrset(attr)
    except curses.error:
        pass
    safe_addstr(win, 0, 0, tl + horiz * max(0, w - 2) + tr, attr)
    safe_addstr(win, h - 1, 0, bl + horiz * max(0, w - 2) + br, attr)
    for y in range(1, h - 1):
        safe_addstr(win, y, 0, vert, attr)
        safe_addstr(win, y, w - 1, vert, attr)


# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------

class Colors:
    def __init__(self, use_color: bool):
        self.colors_on = use_color
        if not use_color:
            self.panel = curses.A_NORMAL
            self.panel_border = curses.A_NORMAL
            self.current = curses.A_REVERSE
            self.title = curses.A_REVERSE
            self.dialog = curses.A_NORMAL
            self.dialog_input = curses.A_REVERSE
            self.func_bar = curses.A_REVERSE
            self.progress = curses.A_REVERSE
            self.hotkey = curses.A_BOLD
            self.warning = curses.A_REVERSE | curses.A_BOLD
            self.dim = curses.A_DIM
            self.link = curses.A_UNDERLINE
            self.header = curses.A_UNDERLINE
            self.status_bar = curses.A_DIM
            self.selected_mark = curses.A_BOLD
            return
        pairs = {
            "panel": (curses.COLOR_WHITE, curses.COLOR_BLUE),
            "current": (curses.COLOR_BLACK, curses.COLOR_CYAN),
            "title": (curses.COLOR_BLACK, curses.COLOR_CYAN),
            "dialog": (curses.COLOR_BLACK, curses.COLOR_WHITE),
            "input": (curses.COLOR_WHITE, curses.COLOR_BLUE),
            "bar": (curses.COLOR_BLACK, curses.COLOR_WHITE),
        }
        ids = {}
        for num, (name, (fg, bg)) in enumerate(pairs.items(), start=1):
            ids[name] = num
            try:
                curses.init_pair(num, fg, bg)
            except curses.error:
                ids[name] = 0
        def cp(name):
            return curses.color_pair(ids[name]) if ids[name] else curses.A_NORMAL
        self.panel = cp("panel")
        self.panel_border = cp("panel") | curses.A_BOLD
        self.current = cp("current")
        self.title = cp("title") | curses.A_BOLD
        self.dialog = cp("dialog")
        self.dialog_input = cp("input")
        self.func_bar = cp("bar")
        self.progress = cp("panel") | curses.A_BOLD
        self.hotkey = curses.A_BOLD
        self.warning = curses.A_REVERSE | curses.A_BOLD
        self.dim = curses.A_DIM
        self.link = curses.A_UNDERLINE
        self.header = curses.A_UNDERLINE
        self.status_bar = curses.A_DIM
        self.selected_mark = curses.A_BOLD


# ---------------------------------------------------------------------------
# Panel
# ---------------------------------------------------------------------------

class Panel:
    def __init__(self, path: str = "~"):
        self.path = fsops.path_expand(path, os.getcwd())
        self.entries: list = []
        self.index = 0
        self.top = 0
        self.show_hidden = True
        self.sort_key = "name"
        self.sort_reverse = False
        self.selected: set = set()
        self.pattern = ""
        self.error = ""
        self.cursor_name = ""

    # -- data --------------------------------------------------------------
    def refresh(self, keep_cursor: bool = True) -> None:
        if self.entries and 0 <= self.index < len(self.entries):
            self.cursor_name = self.entries[self.index].name
        try:
            entries, errors = fsops.list_dir(self.path, self.show_hidden, self.pattern)
            fsops.sort_entries(entries, self.sort_key, self.sort_reverse)
            self.entries = entries
            self.error = errors[0] if errors else ""
        except FileNotFoundError:
            self.entries, self.error = [], "Folder not found: %s" % self.path
        except PermissionError:
            self.entries, self.error = [], "Permission denied"
        except NotADirectoryError:
            self.entries, self.error = [], "Not a folder"
        except OSError as exc:
            self.entries, self.error = [], str(exc)
        names = {e.name for e in self.entries}
        self.selected &= names
        if keep_cursor and self.cursor_name:
            for i, entry in enumerate(self.entries):
                if entry.name == self.cursor_name:
                    self.index = i
                    break
            else:
                self.index = 0
        else:
            self.index = 0
        if self.entries:
            self.index = min(self.index, len(self.entries) - 1)
        else:
            self.index = 0

    def current(self) -> "Entry | None":
        if 0 <= self.index < len(self.entries):
            return self.entries[self.index]
        return None

    # -- movement ----------------------------------------------------------
    def move(self, delta: int) -> None:
        if self.entries:
            self.index = max(0, min(len(self.entries) - 1, self.index + delta))

    def jump(self, end: bool) -> None:
        if self.entries:
            self.index = len(self.entries) - 1 if end else 0

    def chdir(self, path: str) -> None:
        target = fsops.path_expand(path, self.path)
        if not os.path.isdir(target):
            self.error = "Not a folder: %s" % target
            return
        self.path = target
        self.selected.clear()
        self.pattern = ""
        self.cursor_name = ""
        self.refresh(keep_cursor=False)

    def go_up(self) -> None:
        parent = os.path.dirname(self.path)
        if parent and parent != self.path:
            self.chdir(parent)

    def enter(self) -> bool:
        entry = self.current()
        if entry is None:
            self.go_up()
            return True
        if entry.is_dir:
            self.chdir(entry.path)
            return True
        return False

    # -- geometry for mouse/touch ------------------------------------------
    ROW_TITLE, ROW_HEADER, ROW_FIRST = 0, 1, 2

    def row_at(self, window_row: int, height: int = None):
        """Index of the entry drawn on *window_row* inside this panel window.

        Row 0 is the border+title, row 1 the column header, row 2 the first
        entry and the last usable row is height-2 (the footer line above the
        bottom border).  Returns None for anything that is not an entry.
        """
        if window_row < self.ROW_FIRST:
            return None
        if height is not None and window_row > self.last_visible_row(height):
            return None
        idx = self.top + (window_row - self.ROW_FIRST)
        if 0 <= idx < len(self.entries):
            return idx
        return None

    def last_visible_row(self, height: int) -> int:
        return height - 2

    # -- selection ---------------------------------------------------------
    def toggle_select(self) -> None:
        entry = self.current()
        if entry is None:
            return
        if entry.name in self.selected:
            self.selected.discard(entry.name)
        else:
            self.selected.add(entry.name)
        self.move(1)

    def mark_all(self, on: bool) -> None:
        self.selected = {e.name for e in self.entries} if on else set()

    def selected_entries(self) -> list:
        if self.selected:
            return [e for e in self.entries if e.name in self.selected]
        entry = self.current()
        return [entry] if entry is not None else []

    def selected_paths(self) -> list:
        return [e.path for e in self.selected_entries()]

    # -- rendering ---------------------------------------------------------
    def draw(self, win, focused: bool, cs: Colors) -> None:
        win.erase()
        win.bkgd(" ", cs.panel if focused else cs.panel)
        h, w = win.getmaxyx()
        draw_box(win, cs.panel_border if focused else cs.dim | cs.panel)
        inner_h = h - 3
        inner_w = w - 3  # never paint into a window's last column
        # title = current path
        head = " %s " % clip_left(self.path, w - (14 if self.selected else 4))
        safe_addstr(win, 0, 1, "\u2500", cs.panel_border if focused else cs.dim | cs.panel)
        safe_addstr(win, 0, 2, head, cs.title if focused else cs.dim | cs.panel)
        safe_addstr(win, 0, 2 + len(head), "\u2500" * max(0, w - 3 - len(head) -
                    (8 if self.selected else 0)),
                    cs.panel_border if focused else cs.dim | cs.panel)
        if self.selected:
            mark = " *%d* " % len(self.selected)
            safe_addstr(win, 0, max(2, w - len(mark) - 2), mark,
                        cs.title if focused else cs.dim | cs.panel)
        if self.pattern:
            safe_addstr(win, 0, 2 + len(head), " [%s] " % self.pattern,
                        cs.header | cs.panel)
        # scroll window
        if self.index < self.top:
            self.top = self.index
        elif self.index >= self.top + max(1, inner_h - 1):
            self.top = self.index - max(1, inner_h - 1) + 1
        max_top = max(0, len(self.entries) - max(1, inner_h - 1))
        self.top = max(0, min(self.top, max_top))
        # columns: leading marker(1) + name + size(10) + gap(2) + date(12)
        compact = inner_w < 44
        if compact:
            name_w = max(4, inner_w - 1)
            hdr = " %-*s" % (name_w, "Name")
        else:
            name_w = max(6, inner_w - 1 - 10 - 2 - 12)
            hdr = " %-*s%10s  %-12s" % (name_w, "Name", "Size", "Modified")
        safe_addstr(win, 1, 1, clip(hdr, inner_w), cs.panel | cs.header)
        # rows
        y = 2
        last_row = h - 2
        for i in range(self.top, len(self.entries)):
            if y >= last_row:
                break
            entry = self.entries[i]
            is_cur = i == self.index
            attr = cs.panel
            if is_cur:
                attr = cs.current if focused else cs.panel | cs.dim
            if entry.is_link:
                attr |= cs.dim if entry.link_broken else cs.link
            if entry.is_dir:
                label = "[" + entry.name + "]"
            else:
                label = " " + entry.name
            lead = "\u2022" if entry.name in self.selected else " "
            line = "%s%-*s" % (lead, name_w, clip(T(label), name_w))
            if not compact:
                size_text = "<DIR>" if entry.is_dir else (
                    fsops.human_size(entry.size) if entry.size else "")
                line += "%10s  %-12s" % (size_text, fsops.format_time(entry.mtime))
            safe_addstr(win, y, 1, clip(line, inner_w), attr)
            if entry.name in self.selected and not is_cur:
                safe_addstr(win, y, 1, lead, attr | cs.selected_mark)
            y += 1
        if not self.entries:
            msg = self.error or "(empty folder)"
            safe_addstr(win, 2, 2, clip(msg, inner_w - 2),
                        cs.panel | (cs.warning if self.error else cs.dim))
        # footer inside panel: mode + item info, and a sort indicator on the right
        entry = self.current()
        sort_txt = " %s%s%s " % (
            {"name": "N", "size": "S", "mtime": "T", "ext": "E"}[self.sort_key],
            "v" if self.sort_reverse else "^",
            "" if self.show_hidden else " .",
        )
        room = max(0, inner_w - len(sort_txt) - 1)
        if entry is not None and room > 6:
            info = fsops.mode_string(entry.mode)
            if entry.is_link:
                info += " " + entry.name + " \u2192 " + fsops.read_symlink(entry.path)
            elif entry.is_dir:
                try:
                    info += " %s  (%d items)" % (entry.name, len(os.listdir(entry.path)))
                except OSError:
                    info += " " + entry.name
            else:
                info += " %s  %s" % (entry.name, fsops.human_size(entry.size))
            safe_addstr(win, h - 2, 1, clip(T(info), room), cs.panel | cs.dim)
        safe_addstr(win, h - 2, max(1, w - len(sort_txt) - 1), sort_txt,
                    cs.panel | cs.dim)
        win.noutrefresh()


# ---------------------------------------------------------------------------
# Modal dialogs
# ---------------------------------------------------------------------------

class Dialog:
    def __init__(self, app: "App"):
        self.app = app

    def make_window(self, height: int, width: int, title: str, min_width=30):
        maxy, maxx = self.app.stdscr.getmaxyx()
        height = max(3, min(height, maxy - 1))
        width = max(min_width, min(width, maxx - 2))
        y = max(0, (maxy - height) // 2)
        x = max(0, (maxx - width) // 2)
        win = curses.newwin(height, width, y, x)
        win.keypad(True)
        try:
            win.bkgd(" ", self.app.cs.dialog)
        except curses.error:
            pass
        draw_box(win, self.app.cs.dialog)
        safe_addstr(win, 0, 2, " %s " % title, self.app.cs.title)
        win.refresh()
        return win

    def close(self, win) -> None:
        del win
        self.app.touch_all()

    # -- text input --------------------------------------------------------
    def ask(self, title: str, prompt: str, default: str = "",
            password: bool = False) -> "str | None":
        win = self.make_window(5, 76, title, min_width=40)
        h, w = win.getmaxyx()
        safe_addstr(win, 1, 2, clip(prompt, w - 4), self.app.cs.dialog)
        safe_addstr(win, h - 2, 2, "Enter = OK    Esc = Cancel",
                    self.app.cs.status_bar | self.app.cs.dialog)
        buf = list(default)
        cursor = len(buf)
        curses.curs_set(1)
        try:
            while True:
                shown = "*" * len(buf) if password else "".join(buf)
                safe_addstr(win, 2, 2, clip(shown, w - 5).ljust(w - 5),
                            self.app.cs.dialog_input)
                try:
                    win.move(2, min(2 + cursor, w - 3))
                except curses.error:
                    pass
                win.refresh()
                key = win.get_wch()
                if key in ("\n", "\r", curses.KEY_ENTER):
                    self.close(win)
                    return "".join(buf)
                if key == "\x1b":
                    self.close(win)
                    return None
                if key in (curses.KEY_BACKSPACE, "\x7f", "\b"):
                    if cursor > 0:
                        del buf[cursor - 1]
                        cursor -= 1
                elif key == curses.KEY_DC:
                    if cursor < len(buf):
                        del buf[cursor]
                elif key == curses.KEY_LEFT:
                    cursor = max(0, cursor - 1)
                elif key == curses.KEY_RIGHT:
                    cursor = min(len(buf), cursor + 1)
                elif key in (curses.KEY_HOME, "\x01"):
                    cursor = 0
                elif key in (curses.KEY_END, "\x05"):
                    cursor = len(buf)
                elif key == "\x15":
                    buf, cursor = [], 0
                elif isinstance(key, str) and key.isprintable():
                    buf.insert(cursor, key)
                    cursor += 1
        finally:
            curses.curs_set(0)

    # -- yes / no ----------------------------------------------------------
    def confirm(self, title: str, lines, default_yes: bool = False) -> bool:
        if isinstance(lines, str):
            lines = [lines]
        height = min(len(lines) + 4, 18)
        win = self.make_window(height, 78, title, min_width=40)
        h, w = win.getmaxyx()
        for i, line in enumerate(lines[: h - 4]):
            safe_addstr(win, 1 + i, 2, clip(line, w - 4), self.app.cs.dialog)
        prompt = "[Y]es    [N]o" if not default_yes else "[Y]es    [n]o"
        safe_addstr(win, h - 2, 2, prompt.center(w - 4),
                    self.app.cs.hotkey | self.app.cs.dialog)
        win.refresh()
        while True:
            ch = win.get_wch()
            if ch == "\x1b":
                ch = "\x1b"
            if ch in ("y", "Y"):
                self.close(win)
                return True
            if ch in ("n", "N", "\x1b"):
                self.close(win)
                return False
            if ch in ("\n", "\r", curses.KEY_ENTER):
                self.close(win)
                return default_yes

    # -- conflict ----------------------------------------------------------
    def conflict(self, dst: str) -> str:
        maxx = self.app.stdscr.getmaxyx()[1]
        win = self.make_window(7, min(maxx - 2, 100), "Item already exists", min_width=40)
        h, w = win.getmaxyx()
        safe_addstr(win, 1, 1, clip(" Already exists: %s" % os.path.basename(dst),
                                    w - 3), self.app.cs.warning)
        safe_addstr(win, 2, 1, clip(" Path: %s" % dst, w - 3),
                    self.app.cs.dialog | self.app.cs.dim)
        options = ["O overwrite", "S skip", "R rename", "A all", "K keep both", "C cancel"]
        if w >= 74:
            text = "  ".join(options)
        elif w >= 50:
            text = "  ".join(options[:3]) + "   " + "  ".join(options[3:])
        else:
            text = " ".join(o.split()[0] for o in options)
        safe_addstr(win, 4, 1, clip(text.center(max(0, w - 2)), w - 2),
                    self.app.cs.hotkey | self.app.cs.dialog)
        win.refresh()
        mapping = {
            "o": fsops.OVERWRITE, "s": fsops.SKIP, "r": fsops.RENAME,
            "a": fsops.OVERWRITE_ALL, "k": fsops.SKIP_ALL,
            "c": fsops.CANCEL, "\x1b": fsops.CANCEL,
        }
        while True:
            ch = win.get_wch()
            low = ch.lower() if isinstance(ch, str) else ""
            if low in mapping:
                self.close(win)
                return mapping[low]


class Progress:
    """Progress window; also polls the keyboard so Esc cancels the transfer."""

    def __init__(self, app: "App", title: str):
        self.app = app
        self.win = Dialog(app).make_window(7, 76, title, min_width=44)
        self.phase = ""
        self.name = ""
        self.done = 0
        self.total = 0
        self.rate = 0.0
        self.cancelled = False

    def __call__(self, phase, done, total, rate, name):
        self.phase, self.done, self.total = phase, done, total
        self.rate, self.name = rate, name
        self._poll()
        self._draw()

    def _poll(self):
        if self.cancelled:
            return
        self.win.nodelay(True)
        try:
            for _ in range(16):
                try:
                    ch = self.win.get_wch()
                except curses.error:
                    break
                if ch in ("\x1b", "\x03", "c", "C"):
                    self.cancelled = True
                    self.app.transfer.cancel = True
        finally:
            self.win.nodelay(False)

    def _draw(self):
        cs = self.app.cs
        h, w = self.win.getmaxyx()
        pct = (self.done / self.total) if self.total else 0.0
        bar_w = max(8, w - 26)
        filled = int(bar_w * pct)
        bar = T("\u2588") * filled + T("\u2591") * (bar_w - filled)
        labels = {"scan": "Scanning", "copy": "Copying", "move": "Moving",
                  "delete": "Deleting", "done": "Done"}
        line = "%-9s %s / %s" % (labels.get(self.phase, self.phase.capitalize()),
                                fsops.human_size(self.done),
                                fsops.human_size(self.total))
        safe_addstr(self.win, 1, 2, clip(line, w - 4).ljust(w - 5), cs.dialog)
        safe_addstr(self.win, 2, 2, bar[:bar_w], cs.progress)
        rate = fsops.human_size(int(self.rate)) + "/s" if self.rate else ""
        right = "%3d%%  %-9s" % (int(pct * 100), rate)
        safe_addstr(self.win, 2, max(2, w - 3 - len(right)), right, cs.dim)
        safe_addstr(self.win, 3, 2, clip(T(self.name), w - 4), cs.dim)
        hint = "Esc = cancel" if not self.cancelled else "cancelling\u2026"
        safe_addstr(self.win, h - 2, 2, hint.center(w - 4),
                    cs.status_bar | cs.dialog)
        self.win.refresh()

    def finish(self) -> None:
        del self.win
        self.app.touch_all()


# ---------------------------------------------------------------------------
# Menus / text viewer
# ---------------------------------------------------------------------------

def menu(app: "App", title: str, labels, width: int = 64) -> "int | None":
    height = min(len(labels) + 3, app.stdscr.getmaxyx()[0] - 1)
    win = Dialog(app).make_window(height, width, title, min_width=34)
    h, w = win.getmaxyx()
    index = 0
    top = 0
    visible = h - 3
    selectable = [i for i, label in enumerate(labels) if label != "---"]
    if not selectable:
        Dialog(app).close(win)
        return None
    if index not in selectable:
        index = selectable[0]
    while True:
        if index < top:
            top = index
        elif index >= top + visible:
            top = index - visible + 1
        for row in range(visible):
            i = top + row
            if i >= len(labels):
                break
            if labels[i] == "---":
                safe_addstr(win, 1 + row, 2, (" " + "\u2500" * max(0, w - 6)).ljust(w - 4),
                            app.cs.dialog | app.cs.dim)
                continue
            attr = app.cs.current if i == index else app.cs.dialog
            safe_addstr(win, 1 + row, 2, (" %2d. %s" % (i + 1, labels[i])).ljust(w - 4),
                        attr)
        safe_addstr(win, h - 2, 2, " Enter = select    Esc = back",
                    app.cs.status_bar | app.cs.dialog)
        win.refresh()
        key = win.get_wch()
        if key == "\x1b":
            tail = []
            win.timeout(45)
            try:
                while len(tail) < 12:
                    try:
                        ch = win.get_wch()
                    except curses.error:
                        break
                    tail.append(ch)
                    if not isinstance(ch, str) or ch.isalpha():
                        break
            finally:
                win.timeout(-1)
            seq = "".join(tail)
            mapped = decode_escape(seq) if seq else None
            if mapped is not None:
                key = mapped
            elif seq:
                continue        # unknown sequence: ignore rather than act on it
            else:
                key = "\x1b"    # a real, bare Escape press
        if isinstance(key, str) and key.isdigit():
            num = int(key)
            if 1 <= num <= len(labels) and labels[num - 1] != "---":
                Dialog(app).close(win)
                return num - 1
        if key in (curses.KEY_UP, "k"):
            pos = selectable.index(index) if index in selectable else 0
            index = selectable[(pos - 1) % len(selectable)]
        elif key in (curses.KEY_DOWN, "j", "\t"):
            pos = selectable.index(index) if index in selectable else 0
            index = selectable[(pos + 1) % len(selectable)]
        elif key == curses.KEY_PPAGE:
            pos = selectable.index(index) if index in selectable else 0
            index = selectable[max(0, pos - visible)]
        elif key == curses.KEY_NPAGE:
            pos = selectable.index(index) if index in selectable else 0
            index = selectable[min(len(selectable) - 1, pos + visible)]
        elif key in ("\n", "\r", curses.KEY_ENTER):
            Dialog(app).close(win)
            return index
        elif key in ("\x1b", "q", "Q", curses.KEY_LEFT):
            Dialog(app).close(win)
            return None


def view_text(app: "App", title: str, text: str) -> None:
    lines = text.expandtabs(4).splitlines() or [""]
    maxy, maxx = app.stdscr.getmaxyx()
    height, width = maxy - 1, maxx - 1
    win = curses.newwin(height, width, 0, 0)
    win.keypad(True)
    inner_h = height - 2
    top = 0
    try:
        while True:
            win.erase()
            win.bkgd(" ", app.cs.panel)
            draw_box(win, app.cs.panel_border | app.cs.panel)
            safe_addstr(win, 0, 2, " %s " % title, app.cs.title)
            for row in range(inner_h):
                idx = top + row
                if idx >= len(lines):
                    break
                safe_addstr(win, 1 + row, 1,
                            lines[idx][: width - 2].ljust(width - 2), app.cs.panel)
            pos = ("%d/%d   Up/Down  PgUp/PgDn  Home/End   q/Esc close"
                   % (min(top + 1, len(lines)), len(lines)))
            safe_addstr(win, height - 1, 1, clip(pos, width - 2),
                        app.cs.status_bar | app.cs.panel)
            win.refresh()
            key = win.get_wch()
            if key == "\x1b":
                tail = []
                win.timeout(45)
                try:
                    while len(tail) < 12:
                        try:
                            ch = win.get_wch()
                        except curses.error:
                            break
                        tail.append(ch)
                        if not isinstance(ch, str) or ch.isalpha():
                            break
                finally:
                    win.timeout(-1)
                seq = "".join(tail)
                mapped = decode_escape(seq) if seq else None
                if mapped is not None:
                    key = mapped
                elif seq:
                    continue
                else:
                    key = "\x1b"
            if key in (curses.KEY_DOWN, "j"):
                top = min(max(0, len(lines) - 1), top + 1)
            elif key in (curses.KEY_UP, "k"):
                top = max(0, top - 1)
            elif key in (curses.KEY_NPAGE, " "):
                top = min(max(0, len(lines) - inner_h), top + inner_h)
            elif key == curses.KEY_PPAGE:
                top = max(0, top - inner_h)
            elif key in (curses.KEY_HOME, "g"):
                top = 0
            elif key in (curses.KEY_END, "G"):
                top = max(0, len(lines) - inner_h)
            elif key in ("q", "Q", "\x1b", "\n", "\r", "\x03"):
                break
    finally:
        del win
    app.touch_all()


HELP_TEXT = """\
Twin-Pane Explorer - a two-panel file manager made for Termux/Android.

MOUSE / TOUCH
  click / tap            select an entry (focuses that panel first)
  double click / tap     open folder, or view a file
  drag between panels    copy the entry to the other panel (asks first)
  swipe up / down        scroll a list (stacked phone layout)
  mouse wheel            scroll
  right click            jump to the other panel
  Note: tap = one deliberate click.  A quick double tap opens.

MOVING AROUND
  Up / Down / PgUp / PgDn / Home / End     move the cursor
  Enter                                    open folder (or view file)
  Backspace                                go to parent folder
  Tab, Left, Right                         switch active panel
  /  or Ctrl+G                             go to any path (~ / $VARS work)
  z  or f                                  filter this panel's list (*.jpg)
  a  or Ctrl+H                             show/hide hidden files
  i                                        details of the item (perms, size...)

LAYOUT
  L or F9 -> Switch layout                 auto: side-by-side on a wide
                                           terminal, stacked on a phone
  --layout split      two columns          --layout stack    one panel
  On a narrow screen the active panel fills the width and the line above
  it shows which panel you are in; Tab switches.

TRANSFERS
  Space                    select current item and move down
  + / -                    select all / clear selection
  c or F5                  COPY selected -> other panel
  m or F6                  MOVE selected -> other panel
  F8 or Del                DELETE selected
  F7                       new folder (asks WHICH drive first)
  n                        new empty file (asks which drive first)
  r or Ctrl+R              rename
  Esc                      cancel a running transfer

ZIP / UNZIP  (no extra packages needed)
  Z        compress the selection to .zip on the other panel
  x        zip / unzip menu   (tar.gz, preview contents, extract here)
  u        extract the archive under the cursor into the other panel
  Extracting is zip-slip safe: members with ../ or absolute paths are
  refused, and nothing is written outside the target folder.

OTHER
  Q or F1       quick menu (every command, one list) / help
  v or F3       view file              F2   refresh both panels
  F4            edit ~/.twinpanerc
  F10 or q      quit                   Ctrl+L  redraw screen

TIPS FOR ANDROID
  The right panel starts in /sdcard when that folder exists, so you can
  copy between Termux and shared storage with F5 or a drag.
  If /sdcard gives "Permission denied", run `termux-setup-storage` once
  in Termux and tap Allow.
  Moving across the two filesystems (EXDEV) is done as copy+delete
  automatically, and only after the copy finished without errors.
"""


# ---------------------------------------------------------------------------
# Escape-sequence decoding (normal-mode and application-mode cursor keys)
# ---------------------------------------------------------------------------

_CSI_KEYS = {
    "A": "KEY_UP", "B": "KEY_DOWN", "C": "KEY_RIGHT", "D": "KEY_LEFT",
    "H": "KEY_HOME", "F": "KEY_END", "Z": "KEY_BTAB",
    "1~": "KEY_HOME", "2~": "KEY_IC", "3~": "KEY_DC", "4~": "KEY_END",
    "5~": "KEY_PPAGE", "6~": "KEY_NPAGE", "7~": "KEY_HOME", "8~": "KEY_END",
    "11~": "KEY_F1", "12~": "KEY_F2", "13~": "KEY_F3", "14~": "KEY_F4",
    "15~": "KEY_F5", "17~": "KEY_F6", "18~": "KEY_F7", "19~": "KEY_F8",
    "20~": "KEY_F9", "21~": "KEY_F10", "23~": "KEY_F11", "24~": "KEY_F12",
    "P": "KEY_F1", "Q": "KEY_F2", "R": "KEY_F3", "S": "KEY_F4",
}


def decode_escape(tail: str):
    """Map the characters following ESC to a curses key constant."""
    if not tail:
        return None
    if tail[0] in "[O":
        body = tail[1:]
    else:
        body = tail
    # Drop modifiers such as '1;5A' -> 'A' but keep the number in '6~'.
    if ";" in body:
        body = body.rsplit(";", 1)[1]
    if body and body[-1] in "ABCDHFZ":
        body = body.lstrip("0123456789")
    name = _CSI_KEYS.get(body) or _CSI_KEYS.get(body.lstrip("0123456789;"))
    if name is None:
        # try longest suffix, e.g. '15~' out of '015~'
        for candidate in sorted(_CSI_KEYS, key=len, reverse=True):
            if body.endswith(candidate):
                name = _CSI_KEYS[candidate]
                break
    if name is None:
        return None
    return getattr(curses, name, None)


MOUSE_KEY = "<mouse>"  # sentinel returned by read_key() for mouse reports

DEBUG_LOG = None


def dbg(*parts) -> None:
    """Write a line to $TWINPANE_DEBUG when set; otherwise a no-op."""
    if not DEBUG_LOG:
        return
    try:
        with open(DEBUG_LOG, "a") as handle:
            handle.write(" ".join(str(p) for p in parts) + "\n")
    except OSError:
        pass

# SGR mouse bit flags
_SGR_SHIFT, _SGR_META, _SGR_CTRL = 4, 8, 16
_SGR_MOTION, _SGR_WHEEL = 32, 64
_SGR_BUTTONS = {0: "left", 1: "middle", 2: "right"}


def decode_mouse_x10(tail: str):
    """Decode a legacy X10 report: 'ESC [ M' + 3 bytes (b, x, y each +32)."""
    if len(tail) < 5 or not tail.startswith("[M"):
        return None
    b, x, y = (ord(ch) for ch in tail[2:5])
    b -= 32
    x -= 33
    y -= 33
    if x < 0 or y < 0:
        return None
    bstate = 0
    low = b & 3
    motion = b & 32
    wheel = b & 64
    if wheel:
        bstate |= curses.BUTTON4_PRESSED if low == 0 else getattr(
            curses, "BUTTON5_PRESSED", curses.BUTTON4_PRESSED)
    elif low == 0:
        if motion:
            bstate |= getattr(curses, "BUTTON1_MOVED", 0) or getattr(
                curses, "REPORT_MOUSE_POSITION", 0)
        else:
            bstate |= curses.BUTTON1_PRESSED
    elif low == 1:
        bstate |= curses.BUTTON2_PRESSED
    else:
        bstate |= curses.BUTTON3_PRESSED
    return (0, x, y, 0, bstate)


def decode_mouse_sgr(tail: str):
    """Decode 'ESC [ < b ; x ; y M' (SGR) into a curses-like mouse state.

    Returns (id, x, y, z, bstate) with 0-based coordinates, or None.
    """
    if not tail.startswith("[<") or len(tail) < 6:
        return None
    body = tail[2:]
    final = body[-1]
    if final not in "Mm":
        return None
    parts = body[:-1].split(";")
    if len(parts) != 3:
        return None
    try:
        code, x, y = (int(v) for v in parts)
    except ValueError:
        return None
    x -= 1
    y -= 1
    bstate = 0
    base = code & ~(_SGR_MOTION | _SGR_WHEEL | _SGR_SHIFT | _SGR_META | _SGR_CTRL)
    if code & _SGR_WHEEL:
        if base == 0:
            bstate |= curses.BUTTON4_PRESSED
        else:
            bstate |= getattr(curses, "BUTTON5_PRESSED", 0)
    else:
        button = "left" if base not in (1, 2) else _SGR_BUTTONS[base]
        if button == "left":
            if final == "m":
                bstate |= curses.BUTTON1_RELEASED
            elif code & _SGR_MOTION:
                # not every curses build defines BUTTON1_MOVED; fall back to
                # the generic "position" event so drags still arrive
                bstate |= getattr(curses, "BUTTON1_MOVED", 0) or getattr(
                    curses, "REPORT_MOUSE_POSITION", 0)
            else:
                bstate |= curses.BUTTON1_PRESSED
        elif button == "right":
            bstate |= curses.BUTTON3_PRESSED if final == "M" else curses.BUTTON3_RELEASED
        else:
            bstate |= curses.BUTTON2_PRESSED if final == "M" else curses.BUTTON2_RELEASED
    return (0, x, y, 0, bstate)


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

class App:
    def __init__(self, stdscr, args):
        self.stdscr = stdscr
        self.args = args
        self.transfer = None
        self.msg = ""
        self.msg_kind = "info"
        self.quit = False
        self._wins = None
        self._win_geom = None
        self._geom_state = {}
        self._mode_override = "auto"
        self._dir_stamps = {}
        self._dragging = False
        self._drag_accum = ""
        self._drag_x = None
        self._press_x = None
        self._press_y = None
        self._drag_from_x = None
        self._drag_from_y = None
        self._press_t = 0.0
        self._mouse_down = False
        stdscr.keypad(True)
        try:
            curses.curs_set(0)
        except curses.error:
            pass
        try:
            # 1003 = report motion while a button is held (drag between panels)
            curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
            curses.mouseinterval(250)
        except (curses.error, AttributeError):
            pass
        self._enable_mouse_reporting()
        if args.color == "never":
            use_color = False
        else:
            use_color = bool(curses.has_colors())
            if use_color:
                try:
                    curses.start_color()
                    try:
                        curses.use_default_colors()
                    except curses.error:
                        pass
                except curses.error:
                    use_color = False
        self.cs = Colors(use_color)
        global ASCII_MODE
        want_ascii = bool(args.ascii or os.environ.get("TWINPANE_ASCII"))
        enc = (getattr(sys.stdout, "encoding", "") or "").lower()
        utf8 = "utf" in enc
        ASCII_MODE = want_ascii or not utf8
        left = args.left or "~"
        if args.right:
            right = args.right
        elif os.path.isdir("/sdcard"):
            right = "/sdcard"
        elif os.path.isdir(os.path.expanduser("~/storage/shared")):
            right = os.path.expanduser("~/storage/shared")
        else:
            right = os.getcwd()
        self.panels = [Panel(left), Panel(right)]
        self._mode_override = args.layout
        self.active = 0
        self.dialog = Dialog(self)
        for panel in self.panels:
            panel.refresh(keep_cursor=False)
        if not args.quiet:
            self.info("F5 copy  F6 move  F8 delete  F1 help   |   right panel: %s"
                      % right)

    # -- terminal modes -----------------------------------------------------
    def _enable_mouse_reporting(self) -> None:
        """Ask the terminal for all motion + SGR coordinates.

        xterm 1002/1006 covers Termux, iTerm, gnome-terminal, alacritty and
        every modern terminal; 1015 is the urxvt fallback.
        """
        if not self.args.mouse:
            return
        try:
            sys.stdout.write("\x1b[?1000;1002;1003;1006;1015h")
            sys.stdout.flush()
        except (OSError, ValueError, AttributeError):
            pass

    def _disable_mouse_reporting(self) -> None:
        try:
            sys.stdout.write("\x1b[?1000;1002;1003;1006;1015l")
            sys.stdout.flush()
        except (OSError, ValueError, AttributeError):
            pass

    # -- helpers -----------------------------------------------------------
    @property
    def panel(self) -> Panel:
        return self.panels[self.active]

    @property
    def other(self) -> Panel:
        return self.panels[1 - self.active]

    def info(self, text: str, kind: str = "info") -> None:
        self.msg, self.msg_kind = text, kind

    def touch_all(self) -> None:
        try:
            self.stdscr.touchwin()
        except curses.error:
            pass
        if self._wins:
            for win in self._wins:
                try:
                    win.touchwin()
                except curses.error:
                    pass
        self.draw()

    # -- geometry ----------------------------------------------------------
    def _layout_mode(self):
        """'split' (side by side), 'stack' (one panel on screen) or 'auto'."""
        if self._mode_override in ("split", "stack"):
            return self._mode_override
        maxy, maxx = self.stdscr.getmaxyx()
        if maxx < 64 and maxy > 14:
            return "stack"
        return "split"

    def _layout(self):
        """Return (body_top, body_h, usable_w)."""
        maxy, maxx = self.stdscr.getmaxyx()
        body_top = 1
        body_h = max(3, maxy - 3 - body_top)
        usable_w = maxx - 1
        return body_top, body_h, usable_w

    def _ensure_windows(self, body_top: int, body_h: int, usable_w: int):
        mode = self._layout_mode()
        geom = (body_top, body_h, usable_w, mode)
        if self._wins is not None and self._win_geom == geom:
            return self._wins
        if self._wins:
            for win in self._wins:
                del win
            self._wins = None
        self._win_geom = geom
        self._wins = []
        if mode == "stack":
            # One panel at a time, as tall as the terminal: the other one is a
            # Tab away.  This is the usable mode on phones in portrait.
            win = curses.newwin(body_h, usable_w, body_top, 0)
            self._wins = [win]
            self._stack_slot = 0
        else:
            left_w = max(10, usable_w // 2)
            right_w = usable_w - left_w
            self._wins = [curses.newwin(body_h, left_w, body_top, 0),
                          curses.newwin(body_h, right_w, body_top, left_w)]
        # remember the geometry so mouse clicks can be mapped back to entries
        self._geom_state = {
            "mode": mode, "top": body_top, "h": body_h, "w": usable_w,
            "left_w": (usable_w if mode == "stack" else max(10, usable_w // 2)),
        }
        return self._wins

    # -- drawing -----------------------------------------------------------
    def draw(self) -> None:
        stdscr = self.stdscr
        stdscr.erase()
        maxy, maxx = stdscr.getmaxyx()
        if maxy < MIN_H or maxx < MIN_W:
            safe_addstr(stdscr, 0, 0, "Terminal too small (need %dx%d)" % (MIN_W, MIN_H),
                        curses.A_BOLD)
            stdscr.noutrefresh()
            curses.doupdate()
            return
        cs = self.cs
        usable_w = maxx - 1
        safe_addstr(stdscr, 0, 0, clip(" %s " % T(APP_TITLE), max(18, usable_w - 44)),
                    cs.title)
        right_hint = "Tab:switch  F1:help  F10:quit "
        safe_addstr(stdscr, 0, max(0, usable_w - len(right_hint)), right_hint, cs.title)
        body_top, body_h, usable_w = self._layout()
        status = self.msg or ("Tab=switch  c/F5=copy  m/F6=move  Z=zip  u=unzip  "
                              "Q=menu  F10=quit   |   selected: %d"
                              % len(self.panel.selected))
        if self.transfer is not None:
            # keep the panels readable while a transfer runs in the background
            safe_addstr(stdscr, maxy - 2, 0, clip(status, usable_w), cs.dim)
            busy = " * transferring - Esc cancels "
            safe_addstr(stdscr, maxy - 2, max(0, usable_w - len(busy)), busy,
                        cs.progress)
        elif self.msg_kind == "error":
            safe_addstr(stdscr, maxy - 2, 0, clip(status, usable_w), cs.warning)
        elif self.msg_kind == "ok":
            safe_addstr(stdscr, maxy - 2, 0, clip(status, usable_w), curses.A_BOLD)
        else:
            safe_addstr(stdscr, maxy - 2, 0, clip(status, usable_w), cs.dim)
        keys = ("1 Help  2 Refresh  3 View  4 Edit  5 Copy  6 Move  7 MkDir  8 Delete  9 Menu  10 Quit")
        safe_addstr(stdscr, maxy - 1, 0, clip(keys, usable_w), cs.func_bar)
        # Paint order matters: stdscr.erase() blanks the whole virtual screen,
        # so stdscr must be copied to newscr *before* the overlapping panel
        # windows, otherwise the blank stdscr lines win and panels vanish.
        stdscr.noutrefresh()
        wins = self._ensure_windows(body_top, body_h, usable_w)
        mode = self._layout_mode()
        if mode == "stack":
            # show the active panel, with a one-line switcher above it
            self._draw_panel_switcher(stdscr, body_top, usable_w, cs)
            idx = self.active
            win = wins[0]
            win.mvwin(body_top + 1, 0)
            win.resize(body_h - 1, usable_w)
            self.panels[idx].draw(win, True, cs)
            self._geom_state["top"] = body_top + 1
            self._geom_state["h"] = body_h - 1
        else:
            for idx, (panel, win) in enumerate(zip(self.panels, wins)):
                panel.draw(win, idx == self.active, cs)
        if self._dragging:
            self._draw_drag_bar(stdscr, body_top, body_h, usable_w, cs)
        curses.doupdate()

    def _draw_panel_switcher(self, stdscr, body_top: int, usable_w: int, cs) -> None:
        labels = []
        for idx, panel in enumerate(self.panels):
            label = " %s %s " % ("\u25b6" if idx == self.active else "\u25b8",
                                 clip_left(panel.path, max(8, usable_w // 2 - 8)))
            labels.append(label)
        x = 0
        for idx, label in enumerate(labels):
            attr = cs.title if idx == self.active else cs.dim
            safe_addstr(stdscr, body_top, x, clip(label, max(4, usable_w - x)), attr)
            x += len(label) + 1
            if x >= usable_w:
                break
        hint = " Tab: next panel  F9: layout "
        safe_addstr(stdscr, body_top, max(0, usable_w - len(hint)), hint, cs.dim)

    def _draw_drag_bar(self, stdscr, body_top: int, body_h: int, usable_w: int, cs) -> None:
        """Visual feedback while a finger/mouse is dragging between panels."""
        acc = self._drag_accum
        if not acc:
            return
        if self._layout_mode() == "stack":
            n = acc.count("\x00up") + acc.count("\x00down")
            label = " scrolling %d line(s) " % max(1, n)
            safe_addstr(stdscr, body_top, max(0, usable_w - len(label)), label, cs.progress)
            return
        if self._drag_x is None:
            return
        x = max(1, min(usable_w - 2, self._drag_x))
        for y in range(body_top + 1, min(body_top + body_h, stdscr.getmaxyx()[0] - 1)):
            safe_addstr(stdscr, y, x, "\u2502", cs.progress)
        # put the hint on the status line so it never covers a panel title
        label = " release to copy into the other panel "
        safe_addstr(stdscr, stdscr.getmaxyx()[0] - 2, 0,
                    clip(label.center(usable_w), usable_w), cs.progress)

    # -- input -------------------------------------------------------------
    def _read_escape_tail(self, max_chars: int = 48, timeout_ms: int = 45) -> str:
        """Collect the rest of a CSI/SS3 sequence after a lone ESC.

        Termux keyboards, hardware keyboards and screen/tmux sessions do not
        always emit the exact terminfo string curses expects (ESC [ A while
        curses waits for ESC O A).  SGR mouse reports are far longer than key
        sequences, so the limit is generous and reading stops on the
        terminating byte.
        """
        chars = []
        self.stdscr.timeout(timeout_ms)
        try:
            while len(chars) < max_chars:
                try:
                    ch = self.stdscr.get_wch()
                except curses.error:
                    break
                if not isinstance(ch, str):
                    break
                chars.append(ch)
                joined = "".join(chars)
                if joined.startswith("[<"):
                    # SGR mouse: ESC [ < b ; x ; y M|m -- only M/m terminate,
                    # and only after the y coordinate (two semicolons).
                    if joined.count(";") >= 2 and ch in "Mm":
                        break
                    continue
                if joined.startswith("[M"):
                    # legacy X10: ESC [ M + exactly three raw coordinate bytes
                    if len(chars) >= 5:
                        break
                    continue
                if ch.isalpha() or ch == "~":
                    break
                if len(chars) > 2 and joined.startswith("[") and ch not in "0123456789;<":
                    break
        finally:
            self.stdscr.timeout(-1)
        return "".join(chars)

    def read_key(self):
        while True:
            try:
                key = self.stdscr.get_wch()
            except KeyboardInterrupt:
                if self.transfer is not None:
                    self.transfer.cancel = True
                    return None
                return "\x03"
            except curses.error:
                continue
            if key == curses.KEY_MOUSE:
                try:
                    return MOUSE_KEY, curses.getmouse()
                except curses.error:
                    continue
            if key != "\x1b":
                return key
            tail = self._read_escape_tail()
            if not tail:
                return "\x1b"  # a real, bare Escape press
            mouse = decode_mouse_sgr(tail) or decode_mouse_x10(tail)
            if mouse is not None:
                return MOUSE_KEY, mouse
            mapped = decode_escape(tail)
            if mapped is not None:
                return mapped
            continue  # unknown sequence: swallow it, never act on its letters

    # -- mouse / touch -----------------------------------------------------
    def handle_mouse(self, state) -> None:
        """Turn a mouse/touch event into navigation, drag-to-copy or a tap."""
        try:
            _id, mx, my, _mz, bstate = state
        except (TypeError, ValueError):
            return
        mode = self._layout_mode()
        panel = self.panel
        release = (curses.BUTTON1_RELEASED | getattr(curses, "BUTTON1_CLICKED", 0))
        press = (curses.BUTTON1_PRESSED | getattr(curses, "BUTTON1_CLICKED", 0))

        if bstate & getattr(curses, "BUTTON1_DOUBLE_CLICKED", 0):
            self._mouse_down = False
            self._drag_from_x = self._drag_from_y = None
            self._handle_tap(mx, my, open_double=True)
            self._press_x = self._press_y = None
            self._dragging = False
            self._drag_accum = ""
            return

        if bstate & release:
            self._mouse_down = False
            scroll = self._drag_accum
            big = scroll.count("\x00") >= 2
            moved = (self._press_x is not None
                     and abs(mx - self._press_x) + abs(my - (self._press_y or my)) >= 3)
            self._dragging = False
            self._drag_accum = ""
            self._drag_x = None
            px, py = self._drag_from_x, self._drag_from_y
            self._press_x = self._press_y = None
            self._drag_from_x = self._drag_from_y = None
            if big or (moved and mode == "split"):
                self._finish_drag(px, py, mx, my, scroll)
            else:
                self._handle_tap(mx, my)
            return

        # Some curses builds lack BUTTON1_MOVED and report plain motion as 0,
        # so a coordinate change while the button is held *is* the drag signal.
        if self._mouse_down and self._press_x is not None and (
                max(abs(mx - self._press_x), abs(my - (self._press_y or my))) >= 2) \
                and not (bstate & (release | press | curses.BUTTON4_PRESSED)):
            bstate = bstate | getattr(curses, "REPORT_MOUSE_POSITION", 0) or bstate

        if bstate & press:
            self._mouse_down = True
            row, target_panel, _ = self._hit_test(mx, my)
            if target_panel is not None and target_panel is not panel:
                self.active = self.panels.index(target_panel)
                panel = target_panel
            if row is not None:
                panel.index = row
                panel.cursor_name = panel.entries[row].name
            self._press_x, self._press_y = mx, my
            self._drag_from_x, self._drag_from_y = mx, my
            self._dragging = True
            self._drag_accum = ""
            self._drag_x = mx
            self.draw()
            return

        moved_mask = getattr(curses, "BUTTON1_MOVED", 0) | getattr(
            curses, "REPORT_MOUSE_POSITION", 0)
        if moved_mask and bstate & moved_mask:
            # Terminals differ: some report a dedicated MOVED bit, most only
            # send REPORT_MOUSE_POSITION while a button is held.  Track the
            # button state ourselves so a drag is never mistaken for a hover.
            if not self._mouse_down or self._press_x is None or self._press_y is None:
                return
            self._dragging = True
            self._drag_x = mx
            dy = my - self._press_y
            if mode == "stack":
                # vertical swipe in one panel = scroll the list
                if abs(dy) >= 2:
                    panel.move(1 if dy > 0 else -1)
                    self._drag_accum += "\x00down" if dy > 0 else "\x00up"
                    self._press_y = my
                    self.draw()
            else:
                dx = mx - self._press_x
                if abs(dx) >= 2:
                    self._drag_accum += "\x00right" if dx > 0 else "\x00left"
                    self._press_x = mx
                    self.draw()
            return

        if bstate & curses.BUTTON4_PRESSED:        # wheel up
            for _ in range(3):
                panel.move(-1)
            self.draw()
            return
        if bstate & getattr(curses, "BUTTON5_PRESSED", 0):  # wheel down
            for _ in range(3):
                panel.move(1)
            self.draw()
            return
        if bstate & (curses.BUTTON3_PRESSED | curses.BUTTON3_CLICKED):  # right click
            self.active = self.panels.index(self.other)
            self.info("Panel: %s" % self.panel.path)
            self.draw()
            return

    def _hit_test(self, mx: int, my: int):
        """(entry_index, panel, window_row) for an absolute screen coordinate."""
        g = self._geom_state or {}
        top = g.get("top", 1)
        h = g.get("h", 10)
        if not (top <= my < top + h):
            return None, None, None
        window_row = my - top
        if g.get("mode", "split") == "stack":
            row = self.panel.row_at(window_row, h)
            dbg("hit", mx, my, "stack row=", row, "geom=", g)
            return row, self.panel, window_row
        left_w = g.get("left_w", 40)
        panel = self.panels[0] if mx < left_w else self.panels[1]
        row = panel.row_at(window_row, h)
        dbg("hit", mx, my, "row=", row, "winrow=", window_row, "geom=", g)
        return row, panel, window_row

    def _handle_tap(self, mx: int, my: int, open_double: bool = False) -> None:
        row, panel, _row_in_win = self._hit_test(mx, my)
        if panel is None:
            return
        if panel is not self.panel:
            self.active = self.panels.index(panel)
        panel = self.panel
        if row is None:
            self.msg = ""
            self.draw()
            return
        panel.index = row
        panel.cursor_name = panel.entries[row].name
        if open_double:
            opened = panel.enter()
            self.touch_all()
            if not opened and panel.current() is not None:
                self.view_file(panel.current())
            return
        self.draw()

    def _finish_drag(self, px, py, mx: int, my: int, scroll: str) -> None:
        if self._layout_mode() == "stack":
            return  # vertical swipes only scroll in stacked mode
        g = self._geom_state or {}
        left_w = g.get("left_w", 40)
        if px is None or py is None:
            return
        src_idx = 0 if px < left_w else 1
        dst_idx = 0 if mx < left_w else 1
        if src_idx == dst_idx:
            return
        src_panel = self.panels[src_idx]
        dst_panel = self.panels[dst_idx]
        if not src_panel.entries:
            return
        paths = src_panel.selected_paths()
        if not paths:
            idx = min(src_panel.index, len(src_panel.entries) - 1)
            paths = [src_panel.entries[idx].path]
        names = ", ".join(os.path.basename(p) for p in paths[:2])
        if len(paths) > 2:
            names += "  +%d" % (len(paths) - 2)
        if not self.dialog.confirm(
                "Drag to copy",
                ["Copy  %s" % names, "", "from: %s" % src_panel.path,
                 "to:   %s" % dst_panel.path], True):
            self.touch_all()
            return
        self._run_transfer("copy", paths, dst_panel.path)
        self._finish_fs_change()

    # -- main loop ---------------------------------------------------------
    def run(self) -> None:
        try:
            while not self.quit:
                if self.transfer is None:
                    self.auto_refresh()
                self.draw()
                key = self.read_key()
                if key is None:
                    continue
                try:
                    if isinstance(key, tuple) and key and key[0] == MOUSE_KEY:
                        self.handle_mouse(key[1])
                    else:
                        self.handle(key)
                except Exception as exc:  # never let a bug take the UI down
                    try:
                        self.info("Error: %s" % exc, "error")
                    except Exception:
                        pass
        finally:
            self._disable_mouse_reporting()

    def handle(self, key) -> None:
        panel = self.panel
        if key in (curses.KEY_UP, "k"):
            panel.move(-1)
            self.msg = ""
        elif key in (curses.KEY_DOWN, "j"):
            panel.move(1)
            self.msg = ""
        elif key == curses.KEY_PPAGE:
            panel.move(-12)
        elif key == curses.KEY_NPAGE:
            panel.move(12)
        elif key == curses.KEY_HOME:
            panel.jump(False)
        elif key == curses.KEY_END:
            panel.jump(True)
        elif key == "\t" or key == curses.KEY_BTAB:
            self.active = 1 - self.active
            self.msg = ""
        elif key in (curses.KEY_LEFT, curses.KEY_RIGHT):
            self.active = 1 - self.active
            self.msg = ""
        elif key in ("\n", "\r", curses.KEY_ENTER):
            opened = panel.enter()
            self.touch_all()
            if not opened and panel.current() is not None:
                self.view_file(panel.current())
        elif key in (curses.KEY_BACKSPACE, "\x7f"):
            panel.go_up()
            self.touch_all()
        elif key == " ":
            panel.toggle_select()
            self.msg = ""
        elif key in ("+", "="):
            panel.mark_all(True)
            self.info("%d item(s) selected" % len(panel.selected), "ok")
        elif key in ("-", "_"):
            panel.mark_all(False)
            self.info("Selection cleared")
        elif key in ("a", "\x08"):
            panel.show_hidden = not panel.show_hidden
            panel.refresh()
            self.info("Hidden files %s" % ("shown" if panel.show_hidden else "hidden"))
        elif key in ("z", "f"):
            pattern = self.dialog.ask("Filter list", "Mask (e.g. *.jpg; empty = all):",
                                      panel.pattern)
            if pattern is not None:
                panel.pattern = pattern.strip()
                panel.refresh(keep_cursor=False)
                self.touch_all()
        elif key in ("/", "\x07"):
            path = self.dialog.ask("Go to path", "Path:", panel.path)
            if path:
                panel.chdir(path)
                self.touch_all()
        elif key == "i":
            self.show_details(panel.current())
        elif key in ("o",):
            self.actions_menu()
        elif key in ("c",):
            self.transfer_files("copy")
        elif key in ("m",):
            self.transfer_files("move")
        elif key in ("r",):
            self.rename()
        elif key in ("n", "N"):
            self.new_file()
        elif key in ("u", "U"):
            self.extract_archive(panel.current(), to_other=True)
        elif key in ("Z",):
            self.create_archive(".zip")
        elif key in ("x", "X"):
            self.archive_menu()
        elif key in ("v",):
            self.view_file(panel.current())
        elif key in ("q",):
            self.request_quit()
        elif key in ("Q",):
            self.quick_menu()
        elif key == "\x0c":  # Ctrl+L
            self.stdscr.clear()
            self.touch_all()
        elif key == curses.KEY_F1 or key in ("?", "h"):
            self.show_help()
        elif key == curses.KEY_F2 or key == "\x12":
            panel.refresh()
            self.touch_all()
        elif key == curses.KEY_F3:
            self.view_file(panel.current())
        elif key == curses.KEY_F4:
            self.edit_config()
        elif key == curses.KEY_F5:
            self.transfer_files("copy")
        elif key == curses.KEY_F6:
            self.transfer_files("move")
        elif key == curses.KEY_F7:
            self.new_folder()
        elif key == curses.KEY_F8 or key == curses.KEY_DC:
            self.delete_files()
        elif key == curses.KEY_F9:
            self.main_menu()
        elif key == curses.KEY_F10 or key == "\x11":
            self.request_quit()
        elif key == curses.KEY_RESIZE:
            self._wins = None
            self._win_geom = None
            try:
                self.stdscr.clear()
            except curses.error:
                pass
            self.touch_all()
        elif key == "\x1b":
            if panel.selected:
                panel.selected.clear()
                self.info("Selection cleared")
            else:
                self.msg = ""
        elif key == "L":
            self.cycle_layout()
        elif key == curses.KEY_MOUSE:
            try:
                self.handle_mouse(curses.getmouse())
            except curses.error:
                pass

    # -- layout -----------------------------------------------------------
    def cycle_layout(self) -> None:
        order = ["auto", "split", "stack"]
        nxt = order[(order.index(self._mode_override) + 1) % len(order)]
        self._mode_override = nxt
        self._wins = None
        self._win_geom = None
        labels = {"auto": "automatic (side-by-side / stacked by width)",
                  "split": "two columns (left / right)",
                  "stack": "one panel at a time (top / bottom, Tab to switch)"}
        self.info("Layout: %s" % labels[nxt], "ok")
        try:
            self.stdscr.clear()
        except curses.error:
            pass
        self.touch_all()

    def auto_refresh(self) -> bool:
        """Re-read folders that changed on disk since the last draw.

        Cheap: one stat() per panel per keypress.  Returns True when a panel
        was refreshed, so the caller can avoid a second redraw.
        """
        changed = False
        for panel in self.panels:
            try:
                st = os.stat(panel.path)
            except OSError:
                continue
            key = (st.st_mtime_ns, len(panel.entries))
            previous = self._dir_stamps.get(panel.path)
            self._dir_stamps[panel.path] = key
            if previous is not None and previous != key:
                panel.refresh()
                changed = True
        return changed

    # -- dialogs that choose a target drive / panel -------------------------
    def _choose_target(self, title: str, ask_name: str, action) -> None:
        """Let the user pick *which* drive (panel) the new item goes to."""
        labels = [
            "Left panel   %s" % self.panels[0].path,
            "Right panel  %s" % self.panels[1].path,
            "Other drive...",
        ]
        choice = menu(self, title, labels, width=min(78, self.stdscr.getmaxyx()[1] - 2))
        if choice is None:
            return
        if choice == 2:
            path = self.dialog.ask(title, "Folder for the new item (e.g. /sdcard/Download):",
                                   self.panel.path)
            if not path:
                return
            target = fsops.path_expand(path, self.panel.path)
            if not os.path.isdir(target):
                self.info("Not a folder: %s" % target, "error")
                return
        else:
            target = self.panels[choice].path
        name = self.dialog.ask(title, ask_name % target)
        if not name:
            return
        try:
            created = action(target, name)
            self.info("Created %s" % created, "ok")
            self._refresh_all()
        except (OSError, ValueError) as exc:
            self.info("failed: %s" % exc, "error")
            self.touch_all()

    def new_folder(self) -> None:
        self._choose_target("New folder", "Folder name in %s:", fsops.make_dir)

    def new_file(self) -> None:
        self._choose_target("New file", "File name in %s:", fsops.make_file)

    def _refresh_all(self) -> None:
        for panel in self.panels:
            panel.refresh()
        self.touch_all()

    # -- transfer helpers ---------------------------------------------------
    def _run_transfer(self, mode: str, sources, dest: str):
        transfer = fsops.Transfer()
        self.transfer = transfer
        progress = Progress(self, "%s..." % mode.capitalize())
        transfer.progress_cb = progress
        transfer.conflict_cb = self.dialog.conflict
        try:
            if mode == "copy":
                result = transfer.run_copy(sources, dest)
            elif mode == "move":
                result = transfer.run_move(sources, dest)
            else:
                result = transfer.run_delete(sources)
        except fsops.TransferError as exc:
            result = None
            self.info(str(exc), "error")
        finally:
            progress.finish()
            self.transfer = None
        if result is not None:
            self.report(result)

    def report(self, result: fsops.TransferResult) -> None:
        if result.errors:
            first = result.errors[0]
            extra = "" if len(result.errors) == 1 else "  (+%d more)" % (len(result.errors) - 1)
            self.info("%s%s" % (first, extra), "error")
        elif result.cancelled:
            self.info(result.summary(), "error")
        else:
            self.info(result.summary(), "ok")

    def _finish_fs_change(self) -> None:
        self.panel.selected.clear()
        self.panel.refresh()
        self.other.refresh()
        self.touch_all()

    # -- commands -----------------------------------------------------------
    def transfer_files(self, mode: str) -> None:
        sources = self.panel.selected_paths()
        if not sources:
            self.info("Select something first (Space) or move the cursor to it", "error")
            return
        dest = self.other.path
        verb = "Copy" if mode == "copy" else "Move"
        lines = ["%s %d item(s)" % (verb, len(sources)), ""]
        lines += ["  " + clip(src, 68) for src in sources[:3]]
        if len(sources) > 3:
            lines.append("  ... and %d more" % (len(sources) - 3))
        lines += ["", "to: %s" % dest]
        if not self.dialog.confirm("%s to other panel" % verb, lines, True):
            return
        self._run_transfer(mode, sources, dest)
        self._finish_fs_change()

    def delete_files(self) -> None:
        sources = self.panel.selected_paths()
        if not sources:
            self.info("Nothing to delete", "error")
            return
        lines = ["Delete %d item(s) permanently?" % len(sources), ""]
        lines += ["  " + clip(path, 68) for path in sources[:5]]
        if len(sources) > 5:
            lines.append("  ... and %d more" % (len(sources) - 5))
        if not self.dialog.confirm("Delete", lines, False):
            return
        self._run_transfer("delete", sources, self.panel.path)
        self._finish_fs_change()

    def rename(self, entry: "Entry | None" = None) -> None:
        entry = entry or self.panel.current()
        if entry is None:
            self.info("Nothing under the cursor", "error")
            return
        name = self.dialog.ask("Rename", "New name for '%s':" % entry.name, entry.name)
        if not name or name == entry.name:
            return
        try:
            new_path = fsops.rename_entry(entry.path, name)
            self.info("Renamed to '%s'" % os.path.basename(new_path), "ok")
            self.panel.cursor_name = os.path.basename(new_path)
        except (OSError, ValueError) as exc:
            self.info("rename failed: %s" % exc, "error")
        self.panel.refresh()
        self.touch_all()

    def chmod(self, entry: "Entry | None" = None) -> None:
        entry = entry or self.panel.current()
        if entry is None:
            self.info("Nothing under the cursor", "error")
            return
        current = oct(entry.mode & 0o777)[2:]
        text = self.dialog.ask("Permissions", "Octal mode for '%s' (now %s):"
                               % (entry.name, current), current)
        if not text:
            return
        try:
            mode = fsops.chmod_entry(entry.path, text)
            self.info("%s -> %s" % (entry.name, oct(mode)[2:]), "ok")
        except (OSError, ValueError) as exc:
            self.info("chmod failed: %s" % exc, "error")
        self.panel.refresh()
        self.touch_all()

    # -- zip / unzip --------------------------------------------------------
    def archive_menu(self, entry: "Entry | None" = None) -> None:
        entry = entry or self.panel.current()
        archive_here = entry is not None and fsops.is_archive(entry.path)
        labels = [
            "Extract archive -> other panel" if archive_here else "Extract archive...",
            "Extract archive -> same folder (here)",
            "---",
            "Compress selection (zip) -> other panel",
            "Compress selection (tar.gz) -> other panel",
            "Preview archive contents",
        ]
        choice = menu(self, "zip / unzip", labels)
        if choice is None:
            return
        if choice in (0, 1):
            self.extract_archive(entry, to_other=(choice == 0))
        elif choice == 3:
            self.create_archive(".zip")
        elif choice == 4:
            self.create_archive(".tar.gz")
        elif choice == 5:
            self.preview_archive(entry)

    def create_archive(self, suffix: str) -> None:
        paths = self.panel.selected_paths()
        if not paths:
            self.info("Select something first (Space) or point at an item", "error")
            return
        default = fsops.suggest_archive_name(paths, packed=(suffix == ".zip"))
        dest_dir = self.other.path
        dest = self.dialog.ask(
            "Create archive",
            "Archive path (in the other panel by default):", os.path.join(dest_dir, default))
        if not dest:
            return
        dest = fsops.path_expand(dest, dest_dir)
        if fsops.archive_kind(dest) is None:
            dest += suffix
        transfer = fsops.Transfer()
        self.transfer = transfer
        progress = Progress(self, "Compressing...")
        transfer.progress_cb = progress
        try:
            result = fsops.create_archive(paths, dest, self.dialog.conflict, transfer)
        except fsops.TransferError as exc:
            progress.finish()
            self.transfer = None
            self.info(str(exc), "error")
            self.touch_all()
            return
        finally:
            try:
                progress.finish()
            except Exception:
                pass
            self.transfer = None
        self.report(result)
        self._finish_fs_change()

    def extract_archive(self, entry: "Entry | None", to_other: bool = True) -> None:
        if entry is None or entry.is_dir:
            self.info("Put the cursor on an archive file first", "error")
            return
        if not fsops.is_archive(entry.path):
            self.info("%s is not a zip/tar archive" % entry.name, "error")
            return
        # default: a uniquely-named folder inside the other panel's folder
        default = fsops.suggest_archive_target(entry.path, self.other.path)
        dest = self.dialog.ask("Extract archive",
                               "Extract '%s' into:" % clip(entry.name, 40), default)
        if not dest:
            return
        dest = fsops.path_expand(dest, self.panel.path)
        if os.path.lexists(dest) and not os.path.isdir(dest):
            self.info("Destination exists and is not a folder", "error")
            return
        overwrite = False
        if os.path.isdir(dest) and os.listdir(dest):
            answer = self.dialog.confirm(
                "Extract archive",
                ["%s already contains files." % dest, "",
                 "Overwrite files that already exist?"], False)
            overwrite = answer
        transfer = fsops.Transfer()
        self.transfer = transfer
        progress = Progress(self, "Extracting...")
        transfer.progress_cb = progress
        try:
            result = fsops.extract_archive(entry.path, dest,
                                           transfer=transfer, overwrite=overwrite)
        finally:
            try:
                progress.finish()
            except Exception:
                pass
            self.transfer = None
        self.report(result)
        self._finish_fs_change()

    def preview_archive(self, entry: "Entry | None") -> None:
        if entry is None:
            self.info("Put the cursor on an archive file first", "error")
            return
        if not fsops.is_archive(entry.path):
            self.info("%s is not a zip/tar archive" % entry.name, "error")
            return
        items = fsops.list_archive(entry.path)
        if not items:
            self.info("Archive is empty or unreadable", "error")
            return
        lines = ["%d member(s) in %s" % (len(items), entry.name), ""]
        for name, is_dir, size in items[:400]:
            prefix = "[dir] " if is_dir else "      "
            size_text = fsops.human_size(size) if not is_dir else ""
            lines.append("%s%s  %s" % (prefix, name, size_text))
        if len(items) > 400:
            lines.append("... and %d more" % (len(items) - 400))
        self.show_message_window("Archive - %s" % entry.name, lines)

    def symlink(self) -> None:
        name = self.dialog.ask("New symlink", "Link name inside %s:" % self.panel.path)
        if not name:
            return
        default = self.other.current().path if self.other.current() else ""
        target = self.dialog.ask("New symlink", "Target (path to point to):", default)
        if not target:
            return
        try:
            fsops.make_symlink(self.panel.path, name, target)
            self.info("Symlink created", "ok")
        except (OSError, ValueError) as exc:
            self.info("symlink failed: %s" % exc, "error")
        self.panel.refresh()
        self.touch_all()

    # -- popups -------------------------------------------------------------
    def show_message_window(self, title: str, lines) -> None:
        maxy = self.stdscr.getmaxyx()[0]
        height = min(len(lines) + 3, max(5, maxy - 1))
        win = self.dialog.make_window(height, 78, title, min_width=40)
        h, w = win.getmaxyx()
        for i, line in enumerate(lines[: h - 3]):
            safe_addstr(win, 1 + i, 2, clip(line, w - 4), self.cs.dialog)
        safe_addstr(win, h - 2, 2, "press any key", self.cs.status_bar | self.cs.dialog)
        win.refresh()
        win.get_wch()
        self.dialog.close(win)

    def show_details(self, entry: "Entry | None") -> None:
        if entry is None:
            self.info("Nothing under the cursor", "error")
            return
        try:
            st = os.lstat(entry.path)
            kind = ("symlink -> %s" % fsops.read_symlink(entry.path)
                    if entry.is_link else "folder" if entry.is_dir else "file")
            lines = [
                "Name        : %s" % entry.name,
                "Path        : %s" % entry.path,
                "Type        : %s" % kind,
                "Size        : %s bytes  (%s)" % ("{:,}".format(st.st_size),
                                                  fsops.human_size(st.st_size)),
                "Modified    : %s" % time.strftime("%Y-%m-%d %H:%M:%S",
                                                   time.localtime(st.st_mtime)),
                "Permissions : %s  (%s)" % (fsops.mode_string(st.st_mode),
                                            oct(st.st_mode & 0o777)[2:]),
                "Owner       : %s (uid %d), group %s (gid %d)"
                % (fsops.owner_name(st.st_uid), st.st_uid,
                   fsops.group_name(st.st_gid), st.st_gid),
                "Links       : %d" % st.st_nlink,
                "Inode       : %d" % st.st_ino,
            ]
        except OSError as exc:
            lines = ["Cannot stat: %s" % exc]
        self.show_message_window("Details - %s" % entry.name, lines)

    def show_help(self) -> None:
        view_text(self, "Help", HELP_TEXT)

    def actions_menu(self) -> None:
        labels = ["Open folder / view file", "Rename", "Permissions (chmod)",
                  "New folder...", "New empty file...", "New symlink", "View file",
                  "Open with termux-open", "zip / unzip...", "Switch layout"]
        choice = menu(self, "Actions", labels)
        if choice is None:
            return
        actions = [
            self.actions_open, lambda: self.rename(), lambda: self.chmod(),
            self.new_folder, self.new_file, self.symlink,
            lambda: self.view_file(self.panel.current()), self.actions_external,
            self.archive_menu, self.cycle_layout,
        ]
        actions[choice]()
        self.touch_all()

    def quick_menu(self) -> None:
        """One flat menu - handy on a phone where F-keys are unreachable."""
        labels = [
            "Copy selection -> other panel",
            "Move selection -> other panel",
            "Delete selection",
            "Rename",
            "New folder (choose drive)",
            "New file (choose drive)",
            "zip   - compress selection",
            "unzip - extract archive",
            "View / open",
            "Switch layout (left-right / stacked)",
            "Switch panel (Tab)",
            "Refresh both panels",
            "Help",
            "Quit",
        ]
        choice = menu(self, "Quick menu", labels)
        if choice is None:
            return
        actions = [
            lambda: self.transfer_files("copy"),
            lambda: self.transfer_files("move"),
            self.delete_files,
            lambda: self.rename(),
            self.new_folder,
            self.new_file,
            lambda: self.create_archive(".zip"),
            lambda: self.extract_archive(self.panel.current(), True),
            self.actions_open,
            self.cycle_layout,
            self._swap_panel,
            self._refresh_all,
            self.show_help,
            self.request_quit,
        ]
        actions[choice]()
        self.touch_all()

    def _swap_panel(self) -> None:
        self.active = 1 - self.active
        self.touch_all()

    def actions_open(self) -> None:
        if not self.panel.enter():
            self.view_file(self.panel.current())
        self.touch_all()

    def actions_external(self) -> None:
        entry = self.panel.current()
        if entry is None:
            return
        opener = shutil.which("termux-open") or shutil.which("xdg-open")
        if not opener:
            self.info("No termux-open available (pkg install termux-tools)", "error")
            return
        try:
            subprocess.Popen([opener, entry.path],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.info("Sent to %s" % os.path.basename(opener), "ok")
        except OSError as exc:
            self.info("open failed: %s" % exc, "error")

    def main_menu(self) -> None:
        labels = ["Help", "Quick menu (everything)", "Refresh panel",
                  "Copy to other panel", "Move to other panel",
                  "New folder...", "New file...", "Delete", "Rename",
                  "Change permissions", "zip / unzip...",
                  "Switch layout: left-right / stacked",
                  "Show/hide hidden files", "Sort panel",
                  "Go to /sdcard", "Go to Termux home", "Quit"]
        choice = menu(self, "Menu", labels)
        if choice is None:
            return
        actions = [
            self.show_help, self.quick_menu,
            lambda: (self.panel.refresh(), self.touch_all()),
            lambda: self.transfer_files("copy"),
            lambda: self.transfer_files("move"),
            self.new_folder, self.new_file, self.delete_files,
            lambda: self.rename(), lambda: self.chmod(), self.archive_menu,
            self.cycle_layout, self.toggle_hidden, self.sort_menu,
            lambda: self.go_to("/sdcard"), lambda: self.go_to("~"),
            self.request_quit,
        ]
        actions[choice]()

    def go_to(self, path: str) -> None:
        self.panel.chdir(path)
        self.touch_all()

    def toggle_hidden(self) -> None:
        self.panel.show_hidden = not self.panel.show_hidden
        self.panel.refresh()
        self.touch_all()

    def sort_menu(self) -> None:
        labels = ["By name", "By size", "By date", "By extension"]
        keys = ["name", "size", "mtime", "ext"]
        choice = menu(self, "Sort by", labels)
        if choice is None:
            return
        key = keys[choice]
        if self.panel.sort_key == key:
            self.panel.sort_reverse = not self.panel.sort_reverse
        else:
            self.panel.sort_key, self.panel.sort_reverse = key, False
        self.panel.refresh()
        self.touch_all()

    def edit_config(self) -> None:
        editor = (os.environ.get("EDITOR") or shutil.which("nano")
                  or shutil.which("vi") or "vi")
        curses.endwin()
        try:
            subprocess.call([editor, os.path.expanduser("~/.twinpanerc")])
        except OSError as exc:
            sys.stdout.write("Cannot run %s: %s\n" % (editor, exc))
            sys.stdout.flush()
            time.sleep(1.5)
        finally:
            curses.doupdate()
        self.touch_all()

    def view_file(self, entry: "Entry | None") -> None:
        if entry is None:
            self.info("Nothing to view", "error")
            return
        if entry.is_dir:
            self.panel.chdir(entry.path)
            self.touch_all()
            return
        limit = 8 * 1024 * 1024
        try:
            size = os.stat(entry.path).st_size
        except OSError as exc:
            self.info("Cannot open: %s" % exc, "error")
            return
        if size > limit and not self.dialog.confirm(
                "View file", ["%s is %s - showing the first 8 MB only."
                              % (entry.name, fsops.human_size(size))], True):
            return
        try:
            with open(entry.path, "rb") as fh:
                data = fh.read(limit)
                if b"\x00" in data:
                    self.info("Binary file - not shown", "error")
                    return
                text = data.decode("utf-8", "replace")
        except OSError as exc:
            self.info("Cannot open: %s" % exc, "error")
            return
        view_text(self, "View - %s" % entry.name, text)

    def request_quit(self) -> None:
        if self.transfer is not None:
            if not self.dialog.confirm("Quit", "A transfer is running. Quit anyway?", False):
                return
            self.transfer.cancel = True
        self.quit = True


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="twinpane",
        description="Twin-Pane Explorer: a Norton-Commander style two-panel "
                    "file manager for Termux/Android.")
    parser.add_argument("-l", "--left", help="left panel start folder (default: ~)")
    parser.add_argument("-r", "--right",
                        help="right panel start folder (default: /sdcard if present)")
    parser.add_argument("--ascii", action="store_true",
                        help="ASCII boxes only (old terminals)")
    parser.add_argument("--color", choices=["auto", "never"], default="auto",
                        help="colour mode (default: auto)")
    parser.add_argument("--layout", choices=["auto", "split", "stack"], default="auto",
                        help="panel layout: side-by-side, one-panel (phones), or auto")
    parser.add_argument("--mouse", dest="mouse", action="store_true", default=True,
                        help="enable mouse/touch support (default: on)")
    parser.add_argument("--no-mouse", dest="mouse", action="store_false",
                        help="disable mouse reporting (old SSH clients)")
    parser.add_argument("-q", "--quiet", action="store_true",
                        help="no start-up hint")
    parser.add_argument("--version", action="version", version="twinpane 1.0.0")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if not sys.stdout.isatty():
        sys.stderr.write("twinpane must run in an interactive terminal.\n")
        return 2
    os.environ.setdefault("ESCDELAY", "25")
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    global DEBUG_LOG
    DEBUG_LOG = os.environ.get("TWINPANE_DEBUG") or None
    app = {}

    def traceback_safe(scr):
        instance = App(scr, args)
        app["instance"] = instance
        instance.run()

    try:
        curses.wrapper(traceback_safe)
    except KeyboardInterrupt:
        return 130
    finally:
        # Mouse reporting and keypad modes must never leak into the shell.
        try:
            sys.stdout.write("\x1b[?1000;1002;1003;1006;1015l\x1b[?25h\x1b[?1l\x1b>")
            sys.stdout.flush()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
