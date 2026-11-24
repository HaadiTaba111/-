"""Panel sorting.

Sorting is one of those things that looks trivial and is not: folders first,
natural numbers in names, a direction that flips when you pick the same key
twice, and a choice that survives a restart. All of that is tested here.
"""
import ast
import os

import pytest

from twinpane import fsops
from twinpane.fsops import Entry


def entry(name, is_dir=False, size=0, mtime=0.0):
    return Entry(name=name, path="/x/" + name, is_dir=is_dir,
                 size=size, mtime=mtime)


def names(entries):
    return [item.name for item in entries]


# ------------------------------------------------------------------- by name

def test_sorts_alphabetically():
    items = [entry("c.txt"), entry("a.txt"), entry("b.txt")]
    assert names(fsops.sort_entries(items, "name")) == ["a.txt", "b.txt", "c.txt"]


def test_folders_come_first():
    items = [entry("zebra.txt"), entry("apple", is_dir=True),
             entry("banana.txt"), entry("kiwi", is_dir=True)]
    result = names(fsops.sort_entries(items, "name"))
    assert result[:2] == ["apple", "kiwi"]


def test_folders_first_can_be_turned_off():
    items = [entry("zebra.txt"), entry("apple", is_dir=True)]
    result = names(fsops.sort_entries(items, "name", dirs_first=False))
    assert result == ["apple", "zebra.txt"]


def test_natural_numbers_not_lexicographic():
    """file2 must come before file10 - lexicographic order gets this wrong."""
    items = [entry("file10.txt"), entry("file2.txt"), entry("file1.txt")]
    assert names(fsops.sort_entries(items, "name")) == [
        "file1.txt", "file2.txt", "file10.txt"]


def test_reverse_reverses_the_files_but_keeps_folders_first():
    items = [entry("a.txt"), entry("z.txt"), entry("folder", is_dir=True)]
    result = names(fsops.sort_entries(items, "name", reverse=True))
    assert result[0] == "folder"
    assert result[1:] == ["z.txt", "a.txt"]


def test_hidden_files_sort_with_the_rest():
    items = [entry(".bashrc"), entry("aaa.txt")]
    assert names(fsops.sort_entries(items, "name")) == [".bashrc", "aaa.txt"]


# ------------------------------------------------------------------- by size

def test_sorts_by_size():
    items = [entry("big", size=900), entry("small", size=10),
             entry("mid", size=100)]
    assert names(fsops.sort_entries(items, "size")) == ["small", "mid", "big"]


def test_folders_stay_first_when_sorting_by_size():
    items = [entry("huge.txt", size=99999), entry("dir", is_dir=True)]
    assert names(fsops.sort_entries(items, "size"))[0] == "dir"


def test_size_descending():
    items = [entry("a", size=1), entry("b", size=50)]
    assert names(fsops.sort_entries(items, "size", reverse=True)) == ["b", "a"]


# ------------------------------------------------------------------- by date

def test_sorts_by_date_oldest_first():
    items = [entry("new", mtime=300), entry("old", mtime=100),
             entry("mid", mtime=200)]
    assert names(fsops.sort_entries(items, "mtime")) == ["old", "mid", "new"]


def test_date_descending_is_newest_first():
    items = [entry("old", mtime=100), entry("new", mtime=300)]
    assert names(fsops.sort_entries(items, "mtime", reverse=True)) == ["new", "old"]


# -------------------------------------------------------------------- by type

def test_sorts_by_extension():
    items = [entry("a.zip"), entry("b.txt"), entry("c.py")]
    assert names(fsops.sort_entries(items, "ext")) == ["c.py", "b.txt", "a.zip"]


def test_files_without_extension_sort_first():
    items = [entry("x.txt"), entry("Makefile")]
    assert names(fsops.sort_entries(items, "ext"))[0] == "Makefile"


# ------------------------------------------------------------- the UI contract

def test_every_sort_key_in_the_menu_exists_in_fsops():
    """The menu offers keys; fsops must understand all of them."""
    from twinpane.ui import App
    keys = [key for key, _label in App.SORT_LABELS]
    assert keys == ["name", "size", "mtime", "ext"]
    items = [entry("b", size=2, mtime=2), entry("a", size=1, mtime=1)]
    for key in keys:
        assert len(fsops.sort_entries(list(items), key)) == 2


def test_sort_labels_are_human_readable():
    from twinpane.ui import App
    for _key, label in App.SORT_LABELS:
        assert label and label[0].isupper()


def test_the_config_schema_allows_every_sort_key():
    from twinpane import config
    allowed = config.SCHEMA["ui.sort_key"].choices
    from twinpane.ui import App
    for key, _label in App.SORT_LABELS:
        assert key in allowed


def test_the_sort_button_is_on_the_touch_bar():
    from twinpane import touchbar
    actions = [action for action, _label in touchbar.KEY_ACTIONS]
    assert "sort" in actions


def test_every_touch_action_has_a_handler():
    """A button that dispatches to nothing is worse than no button."""
    from twinpane import touchbar
    src = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "twinpane", "ui.py")
    with open(src, encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    handled = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == "run_key_action":
            for inner in ast.walk(node):
                if isinstance(inner, ast.Dict):
                    for key in inner.keys:
                        if isinstance(key, ast.Constant):
                            handled.add(key.value)
    for action, _label in touchbar.KEY_ACTIONS:
        assert action in handled, "the bar has a dead button: %s" % action


def test_quick_menu_labels_and_actions_stay_in_step():
    """A label with no action is an IndexError the moment you tap it."""
    src = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "twinpane", "ui.py")
    with open(src, encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == "quick_menu":
            sizes = {}
            for inner in node.body:
                if isinstance(inner, ast.Assign) and isinstance(inner.value, ast.List):
                    sizes[inner.targets[0].id] = len(inner.value.elts)
            assert sizes.get("labels") == sizes.get("actions"), sizes
            return
    pytest.fail("quick_menu not found")

def test_main_menu_labels_and_actions_are_aligned():
    """Every F9 row must run the action that matches its label.

    A previous edit inserted "Sort panel" into the label list but put its
    handler one row too early, so "Switch layout", "Show/hide hidden files",
    "Go to /sdcard" ... all ran the wrong command. Compare label i with the
    action at index i, by name.
    """
    import ast
    import inspect

    from twinpane import ui as ui_module

    src = inspect.getsource(ui_module)
    tree = ast.parse(src)
    func = next(n for n in ast.walk(tree)
                if isinstance(n, ast.FunctionDef) and n.name == "main_menu")

    lists = [n for n in ast.walk(func) if isinstance(n, ast.List)]
    labels = [elt.value for elt in lists[0].elts]
    actions = [ast.unparse(elt) for elt in lists[1].elts]

    expected = {
        "Switch layout: left-right / stacked": "cycle_layout",
        "Show/hide hidden files": "toggle_hidden",
        "Sort panel": "sort_menu",
        "Go to /sdcard": "go_to",
        "Go to Termux home": "go_to",
        "Settings  (theme, borders, behaviour)...": "settings_menu",
        "Quit": "request_quit",
    }
    by_label = dict(zip(labels, actions))
    for label, wanted in expected.items():
        assert label in by_label, "menu lost the row: %r" % label
        assert wanted in by_label[label], (
            "row %r runs %r, expected something with %r"
            % (label, by_label[label], wanted))
    assert len(labels) == len(actions)

@pytest.mark.parametrize("width", [36, 40, 44, 50, 59, 60, 72, 80, 110])
def test_touch_bar_buttons_never_overlap_or_overflow(width):
    """A phone finger must land on one button only, and see all its label.

    The bar used to size every cell equally, so the two extra cells taken by
    the "->Copy" glyph pushed the next label sideways and left a visible hole.
    """
    from twinpane import touchbar

    buttons = touchbar.layout_keys(width)
    assert buttons, "no buttons at width %d" % width
    by_row = {}
    for button in buttons:
        by_row.setdefault(button.row, []).append(button)
        assert button.width >= 4, "untappable %r at %d" % (button.action, width)
        assert len(button.label) <= button.width, (
            "%r label does not fit its cell at %d" % (button.action, width))
    for row, row_buttons in by_row.items():
        row_buttons.sort(key=lambda b: b.x)
        assert row_buttons[0].x == 0, "row %d does not start at column 0" % row
        for left, right in zip(row_buttons, row_buttons[1:]):
            assert left.x + left.width == right.x, (
                "gap/overlap between %r and %r at width %d"
                % (left.action, right.action, width))
        last = row_buttons[-1]
        assert last.x + last.width == width, "bar does not fill width %d" % width


@pytest.mark.parametrize("width", [36, 44, 59])
def test_phone_widths_use_two_rows_and_keep_every_action(width):
    """A phone must still reach Sort/Copy/Move/Proj without an F-key."""
    from twinpane import touchbar

    buttons = touchbar.layout_keys(width)
    actions = {button.action for button in buttons}
    assert {"sort", "copy", "move", "menu", "quit"} <= actions
    assert max(button.row for button in buttons) == 1, "expected two rows"


def test_wide_screen_puts_the_whole_bar_on_one_row():
    from twinpane import touchbar

    buttons = touchbar.layout_keys(110)
    assert {button.row for button in buttons} == {0}
