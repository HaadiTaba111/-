"""Tests for the parametric config, daily logs, session memory, themes, plugins."""

import curses
import json
import os
import sys
import time

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from twinpane import config as config_mod          # noqa: E402
from twinpane import logging_setup                 # noqa: E402
from twinpane import plugins                       # noqa: E402
from twinpane import session as session_mod        # noqa: E402
from twinpane import themes as theme_mod           # noqa: E402


# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------

def test_schema_has_core_sections():
    sections = {p.section for p in config_mod.SCHEMA.values()}
    assert {"appearance", "behaviour", "logging", "archives"} <= sections


def test_config_defaults_and_set_get(tmp_path):
    cfg = config_mod.Config(path=str(tmp_path / "config.json"))
    assert cfg.get("ui.theme") == "classic"
    assert cfg.set("ui.theme", "gruvbox") == "gruvbox"
    assert cfg.get("ui.theme") == "gruvbox"


def test_config_rejects_unknown_choice(tmp_path):
    cfg = config_mod.Config(path=str(tmp_path / "config.json"))
    assert cfg.set("ui.theme", "not-a-theme") == "classic"


def test_config_persists_and_reloads(tmp_path):
    path = tmp_path / "config.json"
    cfg = config_mod.Config(path=str(path))
    cfg.set("ui.theme", "nord")
    cfg.set("logging.keep_days", 3)
    assert path.exists()
    again = config_mod.Config(path=str(path))
    assert again.get("ui.theme") == "nord"
    assert again.get("logging.keep_days") == 3


def test_config_toggle_and_cycle(tmp_path):
    cfg = config_mod.Config(path=str(tmp_path / "c.json"))
    before = cfg.get("ui.show_hidden")
    assert cfg.toggle("ui.show_hidden") is (not before)
    first = cfg.get("ui.theme")
    second = cfg.cycle("ui.theme", 1)
    assert second != first
    names = config_mod.SCHEMA["ui.theme"].choices
    assert names.index(second) == (names.index(first) + 1) % len(names)


def test_config_coerces_types():
    param = config_mod.SCHEMA["logging.keep_days"]
    assert param.coerce("7") == 7
    assert param.coerce("junk") == param.default
    flag = config_mod.SCHEMA["ui.show_size"]
    assert flag.coerce("off") is False
    assert flag.coerce("yes") is True


def test_config_survives_corrupt_file(tmp_path):
    path = tmp_path / "config.json"
    path.write_text("{ this is not json", encoding="utf-8")
    cfg = config_mod.Config(path=str(path))
    assert cfg.get("ui.theme") == "classic"       # defaults, no crash
    assert cfg.load_errors                         # and it says why


def test_config_ignores_unknown_keys(tmp_path):
    path = tmp_path / "config.json"
    path.write_text(json.dumps({"ui.theme": "classic", "bogus.key": 1}), encoding="utf-8")
    cfg = config_mod.Config(path=str(path))
    assert cfg.get("ui.theme") == "classic"
    assert any("bogus.key" in e for e in cfg.load_errors)


def test_describe_covers_every_setting(tmp_path):
    cfg = config_mod.Config(path=str(tmp_path / "c.json"))
    rows = cfg.describe()
    assert len(rows) == len(config_mod.SCHEMA)
    assert [r[0] for r in rows][0] == "appearance"


def test_state_dir_honours_env(monkeypatch, tmp_path):
    monkeypatch.setenv("TWINPANE_STATE_DIR", str(tmp_path / "st"))
    monkeypatch.setenv("TWINPANE_CONFIG_DIR", str(tmp_path / "cf"))
    assert config_mod.state_dir() == str(tmp_path / "st")
    assert config_mod.config_dir() == str(tmp_path / "cf")
    assert config_mod.config_path().endswith("config.json")


# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------

def test_log_writes_actions_to_daily_file(tmp_path):
    log = logging_setup.ActivityLog(directory=str(tmp_path), keep_days=0)
    log.action("copy", "/a/b.txt", dest="/c", files=2, bytes=128)
    log.session_start(version="1.1.0")
    log.session_end("quit")
    log.close()
    files = os.listdir(tmp_path)
    activity = [f for f in files if f.startswith("activity-")]
    assert len(activity) == 1
    body = (tmp_path / activity[0]).read_text(encoding="utf-8")
    assert "copy" in body and "/a/b.txt" in body
    assert "dest=/c" in body and "files=2" in body
    assert "session start" in body and "session end" in body


def test_log_errors_go_to_separate_file_with_traceback(tmp_path):
    log = logging_setup.ActivityLog(directory=str(tmp_path), keep_days=0)
    try:
        raise ValueError("boom")
    except ValueError as exc:
        log.error("copy failed", exc=exc, path="/x")
    log.close()
    errors = [f for f in os.listdir(tmp_path) if f.startswith("errors-")]
    assert len(errors) == 1
    body = (tmp_path / errors[0]).read_text(encoding="utf-8")
    assert "boom" in body and "Traceback" in body
    assert "ValueError" in body


def test_log_disabled_writes_nothing(tmp_path):
    log = logging_setup.ActivityLog(enabled=False, directory=str(tmp_path))
    log.action("copy", "/a")
    log.error("nope")
    assert os.listdir(tmp_path) == []
    assert log.enabled is False


def test_log_level_filters_debug(tmp_path):
    log = logging_setup.ActivityLog(directory=str(tmp_path), level="info")
    log.debug("key", key="a")
    log.action("cd", "/tmp")
    log.close()
    body = "".join((tmp_path / f).read_text(encoding="utf-8")
                   for f in os.listdir(tmp_path))
    assert "cd" in body and "key=a" not in body


def test_log_never_raises_on_bad_directory(tmp_path):
    blocker = tmp_path / "file"
    blocker.write_text("x", encoding="utf-8")
    log = logging_setup.ActivityLog(directory=str(blocker / "nested"))
    log.action("copy", "/a")            # must not raise
    log.error("x")
    assert log.enabled is False


def test_log_prunes_old_files(tmp_path):
    old = tmp_path / "activity-2001-01-01.log"
    old.write_text("ancient", encoding="utf-8")
    keep = tmp_path / "activity-2999-01-01.log"
    keep.write_text("future", encoding="utf-8")
    log = logging_setup.ActivityLog(directory=str(tmp_path), keep_days=14)
    log.close()
    assert not old.exists()
    assert keep.exists()


def test_tail_reads_last_lines(tmp_path):
    path = tmp_path / "activity-2026-01-01.log"
    path.write_text("\n".join("line %d" % i for i in range(500)), encoding="utf-8")
    text = logging_setup.tail(str(path), lines=5)
    assert "line 499" in text and "line 0" not in text


def test_crash_hook_records_error(tmp_path):
    log = logging_setup.ActivityLog(directory=str(tmp_path), keep_days=0)
    old_hook = sys.excepthook
    logging_setup.install_crash_hook(log)
    try:
        try:
            raise RuntimeError("kaboom")
        except RuntimeError:
            sys.excepthook(*sys.exc_info())
    finally:
        sys.excepthook = old_hook
        log.close()
    body = "".join((tmp_path / f).read_text(encoding="utf-8")
                   for f in os.listdir(tmp_path) if f.startswith("errors-"))
    assert "kaboom" in body


# ---------------------------------------------------------------------------
# session
# ---------------------------------------------------------------------------

def test_session_roundtrip(tmp_path):
    sess = session_mod.Session(str(tmp_path))
    payload = {"left": {"path": str(tmp_path), "cursor": "a.txt",
                        "sort": "size", "reverse": True},
               "right": {"path": str(tmp_path), "cursor": "b", "sort": "name",
                         "reverse": False},
               "active": 1, "layout": "stack"}
    assert sess.save(payload) is True
    again = session_mod.Session(str(tmp_path))
    assert again.folder(0) == str(tmp_path)
    assert again.cursor(0) == "a.txt"
    assert again.sort(0) == ("size", True)
    assert again.active() == 1
    assert again.layout() == "stack"


def test_session_ignores_vanished_folders(tmp_path):
    gone = tmp_path / "deleted"
    sess = session_mod.Session(str(tmp_path / "state"))
    sess.save({"left": {"path": str(gone)}, "right": {}, "active": 0})
    again = session_mod.Session(str(tmp_path / "state"))
    assert again.folder(0) is None


def test_session_clears_corrupt_file(tmp_path):
    path = tmp_path / "session.json"
    path.write_text("<<<nonsense", encoding="utf-8")
    sess = session_mod.Session(str(tmp_path))
    assert sess.loaded is False
    assert sess.load_error
    assert sess.folder(0) is None


def test_session_defaults_when_empty(tmp_path):
    sess = session_mod.Session(str(tmp_path))
    assert sess.active() == 0
    assert sess.layout() is None
    assert sess.cursor(1) == ""
    assert sess.sort(0) is None


# ---------------------------------------------------------------------------
# themes
# ---------------------------------------------------------------------------

def test_every_theme_is_complete_and_loads():
    names = theme_mod.theme_names()
    assert len(names) >= 10
    for name in names:
        theme = theme_mod.load_theme(name)
        for role in theme_mod.ROLES:
            assert role in theme, "%s missing %s" % (name, role)


def test_unknown_theme_falls_back():
    theme = theme_mod.load_theme("no-such-theme")
    assert theme == theme_mod.load_theme(theme_mod.FALLBACK)


def test_custom_theme_from_json(tmp_path):
    path = tmp_path / "solar.json"
    path.write_text(json.dumps({
        "name": "solar",
        "roles": {"panel": ["white", "blue"], "current": ["black", "cyan"]}
    }), encoding="utf-8")
    loaded = theme_mod.load_custom_theme(str(path))
    assert loaded is not None
    name, theme = loaded
    assert name == "solar"
    assert theme["panel"] == ("white", "blue", ())
    for role in theme_mod.ROLES:           # missing roles inherit the fallback
        assert role in theme


def test_custom_theme_rejects_garbage(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text("{oops", encoding="utf-8")
    assert theme_mod.load_custom_theme(str(bad)) is None
    bad2 = tmp_path / "bad2.json"
    bad2.write_text(json.dumps({"roles": "nope"}), encoding="utf-8")
    assert theme_mod.load_custom_theme(str(bad2)) is None


def test_borders_and_ascii_fallback():
    unicode_spec = theme_mod.border("unicode")
    ascii_spec = theme_mod.border("ascii")
    assert unicode_spec["h"] == "\u2500"
    assert ascii_spec["h"] == "-" and ascii_spec["v"] == "|"
    assert theme_mod.resolve_border("auto", True) == "unicode"
    assert theme_mod.resolve_border("auto", False) == "ascii"
    none_spec = theme_mod.border("none")
    assert none_spec["h"] == " " and none_spec["v"] == " "


def test_attr_value_and_colour_conversion():
    assert theme_mod.attr_value(["bold"]) == curses.A_BOLD
    assert theme_mod.attr_value(["bold", "underline"]) == curses.A_BOLD | curses.A_UNDERLINE
    assert theme_mod.attr_value([]) == 0
    assert theme_mod.color_value("red") == curses.COLOR_RED
    assert theme_mod.color_value("COLOR_GREEN") == curses.COLOR_GREEN
    assert theme_mod.color_value(42) == 42
    assert theme_mod.color_value("default") == -1
    assert theme_mod.color_value("not-a-colour") == -1


# ---------------------------------------------------------------------------
# plugins
# ---------------------------------------------------------------------------

def test_plugin_hooks_fire_in_order(tmp_path):
    registry = plugins.Registry(logging_setup.NullLog())
    seen = []

    class FakeAPI:
        pass

    api = plugins.PluginAPI(registry, "demo")
    api.hook("copy")(lambda sources, dest: seen.append(("first", dest)))
    api.hook("copy")(lambda sources, dest: seen.append(("second", dest)))
    registry.fire("copy", sources=["/a"], dest="/b")
    assert seen == [("first", "/b"), ("second", "/b")]


def test_plugin_failure_is_isolated():
    registry = plugins.Registry(logging_setup.NullLog())
    survived = []

    def boom(**kwargs):
        raise RuntimeError("plugin bug")

    registry.add_hook("navigate", boom)
    registry.add_hook("navigate", lambda folder, **kw: survived.append(folder))
    registry.fire("navigate", folder="/tmp")      # must not raise
    assert survived == ["/tmp"]


def test_unknown_hook_name_is_refused():
    registry = plugins.Registry(logging_setup.NullLog())
    with pytest.raises(ValueError):
        registry.add_hook("not_an_event", lambda **k: None)


def test_plugin_directory_is_loaded(tmp_path):
    plugin = tmp_path / "hello.py"
    plugin.write_text(
        "def register(api):\n"
        "    api.command('Say hello', lambda app=None: None)\n"
        "    api.hook('startup')(lambda app=None, config=None: None)\n",
        encoding="utf-8")
    registry = plugins.Registry(logging_setup.NullLog())
    registry.load_directory(str(tmp_path))
    assert any(label == "Say hello" for label, _h, _s in registry.commands())


def test_broken_plugin_does_not_stop_the_app(tmp_path):
    (tmp_path / "broken.py").write_text("raise RuntimeError('nope')\n", encoding="utf-8")
    (tmp_path / "fine.py").write_text(
        "def register(api):\n    api.command('Fine', lambda: None)\n", encoding="utf-8")
    registry = plugins.Registry(logging_setup.NullLog())
    registry.load_directory(str(tmp_path))
    assert any(label == "Fine" for label, _h, _s in registry.commands())


def test_param_setting_registers_new_key():
    registry = plugins.Registry(logging_setup.NullLog())
    api = plugins.PluginAPI(registry, "demo")
    param = config_mod.Param("demo.enabled", True, "bool", section="general")
    api.setting(param)
    assert param.key in config_mod.SCHEMA
    try:
        assert config_mod.SCHEMA["demo.enabled"].default is True
    finally:
        config_mod.SCHEMA.pop("demo.enabled", None)


# ---------------------------------------------------------------------------
# end-to-end: the real curses app, driven through a pty
# ---------------------------------------------------------------------------

def _app(tmp_path, keys, wait=1.8, args_extra=(), no_args=False):
    """Run the app in a pty with a private HOME, send keys, return the screen."""
    pexpect = pytest.importorskip("pexpect")
    pyte = pytest.importorskip("pyte")
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    home = tmp_path / "user"
    home.mkdir(exist_ok=True)
    (home / "docs").mkdir(exist_ok=True)
    (home / "docs" / "a.txt").write_text("x", encoding="utf-8")
    (home / "pics").mkdir(exist_ok=True)
    # state/config live *outside* the browsed folder so the panels stay clean
    env = dict(os.environ, TERM="xterm-256color", LANG="C.UTF-8", LC_ALL="C.UTF-8",
               PYTHONPATH=root, ESCDELAY="25", HOME=str(home),
               TWINPANE_STATE_DIR=str(tmp_path / ".state"),
               TWINPANE_CONFIG_DIR=str(tmp_path / ".config"))
    argv = ["-m", "twinpane"]
    if not no_args:
        argv += ["-l", str(home), "-r", str(home)]
    argv += list(args_extra)
    child = pexpect.spawn(sys.executable, argv, cwd=root, env=env,
                          dimensions=(30, 104), timeout=10)
    scr = pyte.Screen(104, 30)
    stream = pyte.Stream()
    stream.attach(scr)

    def pump(seconds):
        end = time.time() + seconds
        while time.time() < end:
            try:
                data = child.read_nonblocking(65536, timeout=0.05)
            except pexpect.TIMEOUT:
                continue
            except pexpect.EOF:
                break
            stream.feed(data.decode("utf-8", "replace"))

    pump(wait)
    for key in keys:
        child.send(key)
        pump(0.45)
    text = "\n".join(scr.display)
    child.send("\x11")          # Ctrl+Q, flow control now disabled
    pump(1.0)
    child.close(force=True)
    return text, home


def test_navigation_is_saved_to_the_session(tmp_path):
    _app(tmp_path, ["\r"], wait=2.0)          # enter 'docs'
    payload = json.loads((tmp_path / ".state" / "session.json")
                         .read_text(encoding="utf-8"))
    assert payload["left"]["path"].endswith("docs")
    assert payload["left"]["cursor"] == "a.txt"


def test_second_run_resumes_the_saved_folder(tmp_path):
    _app(tmp_path, ["\r"], wait=2.0)                      # enter 'docs', quit
    text, _home = _app(tmp_path, [], no_args=True, wait=2.2)   # plain restart
    assert "Resumed your last session" in text
    assert "docs" in text


def test_explicit_folder_beats_the_session(tmp_path):
    _app(tmp_path, ["\r"], wait=2.0)                     # saves 'docs' as the left folder
    text, _home = _app(tmp_path, [], no_args=False, wait=2.0)
    assert "Resumed your last session" not in text       # -l/-r wins, no resume


def test_daily_log_records_the_session(tmp_path):
    _app(tmp_path, ["\r", "\x1b[B"], wait=2.0)
    logs = list((tmp_path / ".state" / "logs").glob("activity-*.log"))
    assert logs, "no daily log was written"
    body = logs[0].read_text(encoding="utf-8")
    assert "session start" in body and "session end" in body
    assert "cd" in body


def test_theme_key_changes_the_theme_and_persists(tmp_path):
    _app(tmp_path, ["t"], wait=2.0)
    cfg = json.loads((tmp_path / ".config" / "config.json")
                     .read_text(encoding="utf-8"))
    assert cfg["ui.theme"] != "classic"


def test_settings_screen_opens(tmp_path):
    text, _home = _app(tmp_path, ["S"], wait=2.0)
    assert "Settings" in text
    assert "ui.theme" in text or "theme" in text.lower()


def test_log_viewer_shows_todays_lines(tmp_path):
    text, _home = _app(tmp_path, ["\r", "G"], wait=2.2)
    assert "session start" in text or "Log" in text
