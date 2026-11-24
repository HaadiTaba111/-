"""The tappable bars.

These are pure maths on purpose: on a phone a button that misses by one cell is
a button that does not work, so the geometry gets its own tests.
"""
import pytest

from twinpane import touchbar


# ------------------------------------------------------------------ layout

@pytest.mark.parametrize("width", [44, 50, 60, 80, 110, 132])
def test_every_button_can_be_hit(width):
    buttons = touchbar.layout_keys(width)
    assert buttons, "a bar with no buttons is useless"
    for button in buttons:
        mid = button.x + button.width // 2
        assert button.contains(mid, button.row, bar_top=0) is True


def test_narrow_phone_gets_two_rows():
    # 44 columns is what a phone in portrait actually gives Termux
    assert touchbar.rows_needed(44) == 2


def test_wide_terminal_gets_one_row():
    assert touchbar.rows_needed(100) == 1


def test_buttons_never_overlap():
    buttons = touchbar.layout_keys(80)
    for row in {button.row for button in buttons}:
        spans = sorted((b.x, b.x + b.width) for b in buttons if b.row == row)
        for (a_start, a_end), (b_start, _b_end) in zip(spans, spans[1:]):
            assert a_end <= b_start


def test_buttons_fill_the_width():
    for width in (44, 80, 100):
        buttons = touchbar.layout_keys(width)
        right = max(b.x + b.width for b in buttons if b.row == 0)
        assert right == width


def test_untappable_widths_are_dropped_not_squeezed():
    # 10 actions in 20 columns cannot each have 4 cells; the tail is dropped
    buttons = touchbar.layout_keys(20)
    for button in buttons:
        assert button.width >= 4


def test_tap_outside_the_bar_hits_nothing():
    buttons = touchbar.layout_keys(80)
    first = buttons[0]
    assert first.contains(first.x, 1, bar_top=0) is False    # wrong row
    assert first.contains(-5, 0, bar_top=0) is False


def test_the_bar_follows_the_screen_rows():
    """A tap is resolved against wherever the bar was actually drawn."""
    buttons = touchbar.layout_keys(80)
    first = buttons[0]
    assert first.contains(first.x, 20, bar_top=20) is True
    assert first.contains(first.x, 20, bar_top=19) is False


def test_actions_cover_everything_a_phone_needs():
    actions = {action for action, _label in touchbar.KEY_ACTIONS}
    for needed in ("copy", "move", "delete", "mkdir", "menu", "quit"):
        assert needed in actions


def test_disabled_buttons_do_not_respond():
    button = touchbar.Button("run", "run", 0, 10, row=0, enabled=False)
    assert button.contains(5, 0, bar_top=0) is False


def test_render_is_exactly_the_cell_width():
    button = touchbar.Button("x", "Copy", 0, 10)
    assert len(button.render()) == 10


def test_render_truncates_rather_than_overflowing():
    button = touchbar.Button("x", "a-very-long-label", 0, 6)
    assert len(button.render()) == 6


# --------------------------------------------------------------- project bar

class FakeProject:
    name = "my-api"
    kind = "fastapi"
    command = "uvicorn main:app"
    port = 8000
    git = True
    branch = "main"
    path = "/home/u/my-api"


def test_no_project_means_no_bar():
    bar = touchbar.ProjectBar.build(None, {}, 80)
    assert bar.button is None


def test_stopped_project_offers_run():
    bar = touchbar.ProjectBar.build(FakeProject(), {"running": False}, 80)
    assert bar.button is not None
    assert "run" in bar.text


def test_running_project_shows_the_port():
    bar = touchbar.ProjectBar.build(
        FakeProject(), {"running": True, "port": 8001}, 80)
    assert "8001" in bar.text


def test_project_bar_shows_the_branch():
    bar = touchbar.ProjectBar.build(FakeProject(), {"running": False}, 80)
    assert "git:main" in bar.text


def test_project_bar_fits_narrow_screens():
    for width in (34, 44, 60):
        bar = touchbar.ProjectBar.build(FakeProject(), {"running": True,
                                                        "port": 3000}, width)
        assert len(bar.text) == width, (width, bar.text)
        assert bar.button is not None
        assert bar.button.x + bar.button.width <= width


def test_project_bar_button_is_tappable():
    bar = touchbar.ProjectBar.build(FakeProject(), {"running": False}, 80)
    button = bar.button
    mid = button.x + button.width // 2
    # The project bar is drawn one row above the key bar, so its own row is 0
    # relative to bar_top - which is exactly what the caller passes in.
    assert button.contains(mid, 32, bar_top=32) is True
    assert button.contains(mid, 31, bar_top=32) is False


def test_project_without_a_command_cannot_be_run():
    class NoCommand(FakeProject):
        command = ""
        kind = "git"
    bar = touchbar.ProjectBar.build(NoCommand(), {"running": False}, 80)
    assert bar.button.enabled is False
