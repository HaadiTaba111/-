"""Unit tests for the hand-written mouse/key escape decoders.

These are pure functions, so they can be tested without a terminal and they
protect the exact bug class that breaks mouse support in the wild: terminals
emit SGR in application mode, X10 in normal mode, and arrow keys in either
CSI (ESC [ A) or SS3 (ESC O A) flavour.
"""
import curses
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from twinpane.ui import (decode_escape, decode_mouse_sgr,  # noqa: E402
                         decode_mouse_x10)


# ---------------------------------------------------------------- arrows / F-keys

@pytest.mark.parametrize("tail,name", [
    ("[A", "KEY_UP"), ("[B", "KEY_DOWN"), ("[C", "KEY_RIGHT"), ("[D", "KEY_LEFT"),
    ("OA", "KEY_UP"), ("OB", "KEY_DOWN"), ("OC", "KEY_RIGHT"), ("OD", "KEY_LEFT"),
    ("[Z", "KEY_BTAB"), ("[H", "KEY_HOME"), ("[F", "KEY_END"),
    ("[1~", "KEY_HOME"), ("[3~", "KEY_DC"), ("[4~", "KEY_END"),
    ("[5~", "KEY_PPAGE"), ("[6~", "KEY_NPAGE"),
    ("[11~", "KEY_F1"), ("[15~", "KEY_F5"), ("[20~", "KEY_F9"), ("[21~", "KEY_F10"),
    ("OP", "KEY_F1"), ("OQ", "KEY_F2"),
])
def test_decode_escape(tail, name):
    assert decode_escape(tail) == getattr(curses, name)


def test_decode_escape_rejects_junk():
    assert decode_escape("") is None
    assert decode_escape("[999~") is None


# ---------------------------------------------------------------- SGR mouse

def test_sgr_left_press_and_release():
    press = decode_mouse_sgr("[<0;5;5M")
    assert press == (0, 4, 4, 0, curses.BUTTON1_PRESSED)
    release = decode_mouse_sgr("[<0;5;5m")
    assert release[4] == curses.BUTTON1_RELEASED


def test_sgr_drag_motion():
    motion = decode_mouse_sgr("[<32;60;4M")
    assert motion[1] == 59 and motion[2] == 3
    moved = getattr(curses, "BUTTON1_MOVED", 0) or getattr(
        curses, "REPORT_MOUSE_POSITION", 0)
    assert motion[4] == moved


def test_sgr_wheel():
    up = decode_mouse_sgr("[<64;3;5M")
    down = decode_mouse_sgr("[<65;3;5M")
    assert up[4] == curses.BUTTON4_PRESSED
    assert down[4] == getattr(curses, "BUTTON5_PRESSED", 0)


def test_sgr_right_button():
    assert decode_mouse_sgr("[<2;3;5M")[4] == curses.BUTTON3_PRESSED


def test_sgr_modifiers_are_ignored_for_the_button():
    # shift+ctrl+left press: 0 | 4 | 16 = 20
    state = decode_mouse_sgr("[<20;9;9M")
    assert state[4] == curses.BUTTON1_PRESSED
    assert state[1] == 8 and state[2] == 8


def test_sgr_rejects_garbage():
    assert decode_mouse_sgr("[<0;5M") is None
    assert decode_mouse_sgr("[<a;b;cM") is None
    assert decode_mouse_sgr("[A") is None


# ---------------------------------------------------------------- X10 mouse

def test_x10_left_press():
    payload = "[M" + chr(32) + chr(37) + chr(37)      # b=0, x=5, y=5
    assert decode_mouse_x10(payload) == (0, 4, 4, 0, curses.BUTTON1_PRESSED)


def test_x10_wheel_up():
    payload = "[M" + chr(96) + chr(37) + chr(37)      # b=64 -> wheel
    assert decode_mouse_x10(payload)[4] == curses.BUTTON4_PRESSED


def test_x10_motion():
    payload = "[M" + chr(64) + chr(50) + chr(40)      # b=32 -> motion, left held
    moved = getattr(curses, "BUTTON1_MOVED", 0) or getattr(
        curses, "REPORT_MOUSE_POSITION", 0)
    assert decode_mouse_x10(payload)[4] == moved


def test_x10_rejects_short_payload():
    assert decode_mouse_x10("[M") is None
    assert decode_mouse_x10("[Mab") is None
