"""Tappable bars for a phone: a key bar, a project bar, and hit testing.

Why a separate module
---------------------
``ui.py`` is already the biggest file in the project. The "which rectangle did
the finger land in" maths is self-contained, so it lives here and is unit
tested without curses.

The layout is deliberately boring: a bottom bar of equally wide cells, and an
optional project bar sitting directly above it. Both are described as plain
data (:class:`Button`), so the drawing code and the hit test cannot disagree -
they read the same list.

Widths are in terminal cells. A phone in portrait has about 44 of them, so the
bar switches to two rows below :data:`TWO_ROW_WIDTH` and drops the labels that
have a short form (``Copy`` instead of ``5 Copy``).
"""
from __future__ import annotations

from typing import List, Optional, Tuple

#: Below this many columns the key bar wraps onto two rows.
TWO_ROW_WIDTH = 60

#: Short labels keep two-row mode readable in 44 columns.
SHORT_LABELS = {
    "help": "Help", "refresh": "Rfr", "view": "View", "edit": "Edit",
    "copy": "Copy", "move": "Move", "mkdir": "Dir", "delete": "Del",
    "menu": "Menu", "projects": "Proj", "quit": "Quit",
}


class Button:
    """One tappable cell: where it is, what it says, what it does."""

    __slots__ = ("action", "label", "x", "width", "row", "enabled")

    def __init__(self, action: str, label: str, x: int, width: int,
                 row: int = 0, enabled: bool = True) -> None:
        self.action = action
        self.label = label
        self.x = x
        self.width = width
        self.row = row
        self.enabled = enabled

    def contains(self, mx: int, my: int, bar_top: int) -> bool:
        if not self.enabled:
            return False
        if my != bar_top + self.row:
            return False
        return self.x <= mx < self.x + self.width

    def render(self) -> str:
        if len(self.label) >= self.width:
            return self.label[:self.width]
        left = (self.width - len(self.label)) // 2
        return " " * left + self.label + " " * (self.width - len(self.label) - left)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return "Button(%s, %r, x=%d, w=%d, row=%d)" % (
            self.action, self.label, self.x, self.width, self.row)


#: (action, long label). Order is left-to-right on the bar.
KEY_ACTIONS: List[Tuple[str, str]] = [
    ("help", "Help"),
    ("refresh", "Rfr"),
    ("view", "View"),
    ("copy", "Copy"),
    ("move", "Move"),
    ("mkdir", "Dir"),
    ("delete", "Del"),
    ("projects", "Proj"),
    ("menu", "Menu"),
    ("quit", "Quit"),
]


def layout_keys(width: int, project_running: bool = False) -> List[Button]:
    """Lay the key bar out for *width* columns.

    One row when there is room, two when there is not. Every button is at least
    4 cells wide; when the terminal is too narrow for that many, the least
    important actions are dropped rather than made untappable.
    """
    actions = list(KEY_ACTIONS)
    width = max(1, width)

    # Try one row first.
    if width >= len(actions) * 5:
        cell = width // len(actions)
        buttons = []
        x = 0
        for index, (action, label) in enumerate(actions):
            last = index == len(actions) - 1
            span = (width - x) if last else cell
            buttons.append(Button(action, _decorate(action, label, project_running),
                                  x, span))
            x += span
        return buttons

    # Two rows, split roughly in half.
    per_row = max(3, len(actions) // 2 + (len(actions) % 2))
    rows = [actions[:per_row], actions[per_row:]]
    buttons = []
    for row_index, row_actions in enumerate(rows):
        if not row_actions:
            continue
        cell = width // len(row_actions)
        x = 0
        for index, (action, label) in enumerate(row_actions):
            last = index == len(row_actions) - 1
            span = (width - x) if last else cell
            if span < 4:
                continue                        # untappable: leave it out
            buttons.append(Button(action, _decorate(action, label, project_running),
                                  x, span, row=row_index))
            x += span
    return buttons


def _decorate(action: str, label: str, project_running: bool) -> str:
    """Add the little state glyphs that make the bar readable at a glance."""
    if action == "projects" and project_running:
        return "Proj*"
    if action == "copy":
        return "\u2192" + label              # an arrow reads better than the word
    return label


def rows_needed(width: int) -> int:
    """How many terminal rows the key bar occupies at this width."""
    buttons = layout_keys(width)
    return 1 + max((button.row for button in buttons), default=0)


class ProjectBar:
    """The project strip: name, kind, running state, and one tap target.

    Returns None when the folder is not a project - the caller then draws no
    bar at all, so ordinary folders look exactly as before.
    """

    __slots__ = ("text", "button", "path")

    def __init__(self, text: str, button: Optional[Button], path: str) -> None:
        self.text = text
        self.button = button
        self.path = path

    @classmethod
    def build(cls, project, status, width: int) -> "ProjectBar":
        """*project* is a projects.Project, *status* its Runner.status()."""
        if project is None:
            return cls("", None, "")
        running = bool(status.get("running"))
        port = int(status.get("port") or 0)
        name = project.name
        kind = project.kind or "project"

        if running:
            badge = "\u25cf run"
            port_text = " :%d " % port if port else " "
        elif project.command:
            badge = "\u25b6 run"
            port_text = ""
        else:
            badge = "no cmd"
            port_text = ""

        # Right-hand side: the action button, always tappable.
        button_label = " %s " % badge
        button_width = max(8, len(button_label))
        left = width - button_width

        pieces = [name, kind]
        if port_text.strip():
            pieces.append(port_text.strip())
        if project.git:
            pieces.append("git" + (":" + project.branch if project.branch else ""))

        head = ""
        for piece in pieces:
            candidate = (head + "  " + piece) if head else piece
            if len(candidate) + 1 > left:
                break
            head = candidate

        text = head
        if len(text) < left:
            text = text + " " * (left - len(text))
        text = text[:left]
        text = text + button_label[:button_width]
        text = text + " " * max(0, width - len(text))

        enabled = bool(running or project.command)
        button = Button("project", button_label.strip() or "run",
                        left, button_width, row=0, enabled=enabled)
        return cls(text, button, project.path)
