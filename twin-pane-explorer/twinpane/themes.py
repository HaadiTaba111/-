"""Themes and frame styles - the *design* part of the parametrisation.

A theme is plain data: a dict of *role* -> (foreground, background, attrs).
Roles are what the UI actually asks for ("panel", "current", "title", ...),
so adding a theme is a data edit, not a code edit.

Colours are either curses colour constants, an ``int`` 0-255 (for terminals
with 256 colours), or ``-1`` for "terminal default".  Attributes are OR'ed
curses flags expressed as a list of names so themes can be written in JSON
(see ``themes/custom.json`` in a user's state dir).

Border styles change the frame glyphs: unicode, double, rounded, ascii, none.
Both are selected purely through the config keys ``ui.theme`` and
``ui.border``.
"""
from __future__ import annotations

import curses
import json
import os
from typing import Dict, Optional, Tuple

# canonical attribute names -> curses flags (resolved lazily: some are missing
# on minimal curses builds)
ATTR_NAMES = ("bold", "reverse", "underline", "dim", "blink", "italic",
              "standout")


def attr_value(names) -> int:
    value = 0
    for name in names or ():
        if name == "bold":
            value |= curses.A_BOLD
        elif name == "reverse":
            value |= curses.A_REVERSE
        elif name == "underline":
            value |= curses.A_UNDERLINE
        elif name == "dim":
            value |= curses.A_DIM
        elif name == "blink":
            value |= curses.A_BLINK
        elif name == "standout":
            value |= curses.A_STANDOUT
        elif name == "italic":
            value |= getattr(curses, "A_ITALIC", 0)
    return value


def color_value(spec) -> int:
    """Accept 'blue', 'COLOR_BLUE', 4, '4', -1, 'default'."""
    if spec is None:
        return -1
    if isinstance(spec, int):
        return spec
    text = str(spec).strip()
    if text.lower() in ("default", "-1", ""):
        return -1
    upper = text.upper()
    if not upper.startswith("COLOR_"):
        upper = "COLOR_" + upper
    value = getattr(curses, upper, None)
    if isinstance(value, int):
        return value
    try:
        return int(text)
    except ValueError:
        return -1


# Roles the UI uses.  Every theme must define them; anything missing falls
# back to the classic values so a partial custom theme still works.
ROLES = ("panel", "panel_border", "panel_dim", "current", "title", "dialog",
         "dialog_input", "func_bar", "progress", "hotkey", "warning", "dim",
         "link", "header", "status_bar", "selected_mark", "menu_bar")

# role -> (fg, bg, [attrs])
Theme = Dict[str, Tuple[object, object, Tuple[str, ...]]]

THEMES: Dict[str, Theme] = {
    "classic": {                       # Norton Commander blue
        "panel": ("white", "blue", ()),
        "panel_border": ("cyan", "blue", ("bold",)),
        "panel_dim": ("cyan", "blue", ("dim",)),
        "current": ("black", "cyan", ()),
        "title": ("black", "cyan", ("bold",)),
        "menu_bar": ("black", "cyan", ()),
        "dialog": ("black", "white", ()),
        "dialog_input": ("white", "blue", ()),
        "func_bar": ("black", "white", ()),
        "progress": ("white", "blue", ("bold",)),
        "hotkey": ("black", "white", ("bold",)),
        "warning": ("white", "red", ("bold",)),
        "dim": ("white", "blue", ("dim",)),
        "link": ("cyan", "blue", ("underline",)),
        "header": ("cyan", "blue", ("underline",)),
        "status_bar": ("cyan", "blue", ("dim",)),
        "selected_mark": ("yellow", "blue", ("bold",)),
    },
    "midnight": {                      # dark blue / grey
        "panel": (252, 235, ()),
        "panel_border": (39, 235, ("bold",)),
        "panel_dim": (244, 235, ("dim",)),
        "current": (235, 39, ()),
        "title": (235, 39, ("bold",)),
        "menu_bar": (235, 39, ()),
        "dialog": (235, 252, ()),
        "dialog_input": (252, 235, ()),
        "func_bar": (252, 235, ()),
        "progress": (252, 235, ("bold",)),
        "hotkey": (235, 252, ("bold",)),
        "warning": (252, 196, ("bold",)),
        "dim": (244, 235, ("dim",)),
        "link": (111, 235, ("underline",)),
        "header": (111, 235, ("underline",)),
        "status_bar": (244, 235, ("dim",)),
        "selected_mark": (214, 235, ("bold",)),
    },
    "amber": {                         # retro terminal
        "panel": (214, "black", ()),
        "panel_border": (214, "black", ("bold",)),
        "panel_dim": (130, "black", ("dim",)),
        "current": ("black", 214, ()),
        "title": ("black", 214, ("bold",)),
        "menu_bar": ("black", 214, ()),
        "dialog": (214, 233, ()),
        "dialog_input": ("black", 214, ()),
        "func_bar": ("black", 214, ()),
        "progress": (214, "black", ("bold",)),
        "hotkey": (214, 233, ("bold",)),
        "warning": (196, "black", ("bold",)),
        "dim": (130, "black", ("dim",)),
        "link": (220, "black", ("underline",)),
        "header": (220, "black", ("underline",)),
        "status_bar": (130, "black", ("dim",)),
        "selected_mark": (220, "black", ("bold",)),
    },
    "forest": {
        "panel": (150, 22, ()),
        "panel_border": (114, 22, ("bold",)),
        "panel_dim": (65, 22, ("dim",)),
        "current": (22, 114, ()),
        "title": (22, 114, ("bold",)),
        "menu_bar": (22, 114, ()),
        "dialog": (150, 233, ()),
        "dialog_input": (22, 114, ()),
        "func_bar": (22, 114, ()),
        "progress": (150, 22, ("bold",)),
        "hotkey": (22, 233, ("bold",)),
        "warning": (203, 22, ("bold",)),
        "dim": (65, 22, ("dim",)),
        "link": (80, 22, ("underline",)),
        "header": (114, 22, ("underline",)),
        "status_bar": (65, 22, ("dim",)),
        "selected_mark": (220, 22, ("bold",)),
    },
    "mono": {                          # no colour at all
        "panel": ("default", "default", ()),
        "panel_border": ("default", "default", ("bold",)),
        "panel_dim": ("default", "default", ("dim",)),
        "current": ("default", "default", ("reverse",)),
        "title": ("default", "default", ("reverse", "bold")),
        "menu_bar": ("default", "default", ("reverse",)),
        "dialog": ("default", "default", ()),
        "dialog_input": ("default", "default", ("reverse",)),
        "func_bar": ("default", "default", ("reverse",)),
        "progress": ("default", "default", ("bold",)),
        "hotkey": ("default", "default", ("bold",)),
        "warning": ("default", "default", ("reverse", "bold")),
        "dim": ("default", "default", ("dim",)),
        "link": ("default", "default", ("underline",)),
        "header": ("default", "default", ("underline",)),
        "status_bar": ("default", "default", ("dim",)),
        "selected_mark": ("default", "default", ("bold",)),
    },
    "solarized": {
        "panel": (245, 235, ()),
        "panel_border": (37, 235, ("bold",)),
        "panel_dim": (240, 235, ("dim",)),
        "current": (235, 37, ()),
        "title": (235, 37, ("bold",)),
        "menu_bar": (235, 37, ()),
        "dialog": (240, 254, ()),
        "dialog_input": (235, 37, ()),
        "func_bar": (235, 37, ()),
        "progress": (245, 235, ("bold",)),
        "hotkey": (235, 254, ("bold",)),
        "warning": (160, 235, ("bold",)),
        "dim": (240, 235, ("dim",)),
        "link": (33, 235, ("underline",)),
        "header": (33, 235, ("underline",)),
        "status_bar": (240, 235, ("dim",)),
        "selected_mark": (136, 235, ("bold",)),
    },
    "paper": {                         # light background, dark text
        "panel": (235, 255, ()),
        "panel_border": (24, 255, ("bold",)),
        "panel_dim": (245, 255, ("dim",)),
        "current": (255, 24, ()),
        "title": (255, 24, ("bold",)),
        "menu_bar": (255, 24, ()),
        "dialog": (235, 255, ()),
        "dialog_input": (255, 24, ()),
        "func_bar": (255, 24, ()),
        "progress": (235, 255, ("bold",)),
        "hotkey": (235, 255, ("bold",)),
        "warning": (255, 160, ("bold",)),
        "dim": (245, 255, ("dim",)),
        "link": (25, 255, ("underline",)),
        "header": (25, 255, ("underline",)),
        "status_bar": (245, 255, ("dim",)),
        "selected_mark": (130, 255, ("bold",)),
    },
    "dracula": {
        "panel": (253, 236, ()),
        "panel_border": (141, 236, ("bold",)),
        "panel_dim": (103, 236, ("dim",)),
        "current": (236, 141, ()),
        "title": (236, 141, ("bold",)),
        "menu_bar": (236, 141, ()),
        "dialog": (255, 61, ()),
        "dialog_input": (236, 141, ()),
        "func_bar": (236, 141, ()),
        "progress": (253, 236, ("bold",)),
        "hotkey": (255, 61, ("bold",)),
        "warning": (255, 95, ("bold",)),
        "dim": (103, 236, ("dim",)),
        "link": (117, 236, ("underline",)),
        "header": (117, 236, ("underline",)),
        "status_bar": (103, 236, ("dim",)),
        "selected_mark": (228, 236, ("bold",)),
    },
    "nord": {
        "panel": (255, 236, ()),
        "panel_border": (110, 236, ("bold",)),
        "panel_dim": (66, 236, ("dim",)),
        "current": (236, 110, ()),
        "title": (236, 110, ("bold",)),
        "menu_bar": (236, 110, ()),
        "dialog": (236, 255, ()),
        "dialog_input": (236, 110, ()),
        "func_bar": (236, 110, ()),
        "progress": (255, 236, ("bold",)),
        "hotkey": (236, 255, ("bold",)),
        "warning": (191, 236, ("bold",)),
        "dim": (66, 236, ("dim",)),
        "link": (112, 236, ("underline",)),
        "header": (112, 236, ("underline",)),
        "status_bar": (66, 236, ("dim",)),
        "selected_mark": (215, 236, ("bold",)),
    },
    "gruvbox": {
        "panel": (223, 237, ()),
        "panel_border": (142, 237, ("bold",)),
        "panel_dim": (245, 237, ("dim",)),
        "current": (237, 108, ()),
        "title": (237, 108, ("bold",)),
        "menu_bar": (237, 108, ()),
        "dialog": (223, 239, ()),
        "dialog_input": (237, 108, ()),
        "func_bar": (237, 108, ()),
        "progress": (223, 237, ("bold",)),
        "hotkey": (223, 239, ("bold",)),
        "warning": (167, 237, ("bold",)),
        "dim": (245, 237, ("dim",)),
        "link": (109, 237, ("underline",)),
        "header": (109, 237, ("underline",)),
        "status_bar": (245, 237, ("dim",)),
        "selected_mark": (214, 237, ("bold",)),
    },
}

FALLBACK = "classic"


def theme_names():
    return sorted(THEMES)


def load_theme(name: str) -> Theme:
    """Look up a theme, never raising: unknown names fall back to classic."""
    return THEMES.get(name) or THEMES[FALLBACK]


def load_custom_theme(path: str) -> Optional[Tuple[str, Theme]]:
    """Read a JSON theme file: {"name": "...", "roles": {"panel": [...]}}.

    Values may be colour names, 256-colour indexes, or -1 for default.
    """
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    name = str(data.get("name") or os.path.splitext(os.path.basename(path))[0])
    roles = data.get("roles") or data.get("colors") or {}
    if not isinstance(roles, dict):
        return None
    theme: Theme = dict(THEMES[FALLBACK])
    for role, spec in roles.items():
        if role not in ROLES:
            continue
        if isinstance(spec, dict):
            fg = spec.get("fg", "default")
            bg = spec.get("bg", "default")
            attrs = tuple(spec.get("attrs") or ())
        elif isinstance(spec, (list, tuple)):
            fg = spec[0] if len(spec) > 0 else "default"
            bg = spec[1] if len(spec) > 1 else "default"
            attrs = tuple(spec[2] if len(spec) > 2 else ())
        else:
            continue
        theme[role] = (fg, bg, attrs)
    THEMES[name] = theme
    return name, theme


# ---------------------------------------------------------------------------
# frame styles
# ---------------------------------------------------------------------------

BORDERS = {
    "unicode":  {"tl": "\u250c", "tr": "\u2510", "bl": "\u2514", "br": "\u2518",
                 "h": "\u2500", "v": "\u2502", "lt": "\u251c", "rt": "\u2524"},
    "double":   {"tl": "\u2554", "tr": "\u2557", "bl": "\u255a", "br": "\u255d",
                 "h": "\u2550", "v": "\u2551", "lt": "\u2560", "rt": "\u2563"},
    "rounded":  {"tl": "\u256d", "tr": "\u256e", "bl": "\u2570", "br": "\u256f",
                 "h": "\u2500", "v": "\u2502", "lt": "\u251c", "rt": "\u2524"},
    "ascii":    {"tl": "+", "tr": "+", "bl": "+", "br": "+", "h": "-", "v": "|",
                 "lt": "+", "rt": "+"},
    "none":     {"tl": " ", "tr": " ", "bl": " ", "br": " ", "h": " ",
                 "v": " ", "lt": " ", "rt": " "},
}


def resolve_border(style: str, utf8: bool) -> str:
    """Pick the concrete style for 'auto' and downgrade unicode if needed."""
    if style in (None, "", "auto"):
        style = "unicode" if utf8 else "ascii"
    if not utf8 and style != "ascii":
        return "ascii"
    return style if style in BORDERS else "unicode"


def border(style: str) -> Dict[str, str]:
    return BORDERS.get(style) or BORDERS["unicode"]
