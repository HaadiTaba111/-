"""Layered configuration for Twin-Pane Explorer.

Every tunable of the application is declared once, in ``SCHEMA`` below, with
type, default, allowed values and a human description.  That single place is
what makes the app *parametric*:

* the settings screen is generated from the schema (no duplicated UI code)
* ``twinpane --set key=value`` works for every key without extra plumbing
* a future plugin can add its own keys by calling :func:`register`
* values are validated and coerced on load, so a hand-edited JSON file can
  never crash the UI with a bad type

Precedence (highest first):  CLI flags  >  environment info  >  config file
                              >  SCHEMA defaults
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from typing import Any, Dict, List, Optional, Tuple

APP_NAME = "twinpane"
CONFIG_VERSION = 1

# ---------------------------------------------------------------------------
# value types
# ---------------------------------------------------------------------------

class Param:
    """One configurable knob."""

    __slots__ = ("key", "default", "kind", "choices", "help", "section")

    def __init__(self, key: str, default: Any, kind: str = "str",
                 choices: Optional[List[Any]] = None, help: str = "",
                 section: str = "general"):
        self.key = key
        self.default = default
        self.kind = kind            # bool|int|float|str|choice
        self.choices = choices
        self.help = help
        self.section = section

    def coerce(self, value: Any) -> Any:
        """Best-effort conversion; falls back to the default on garbage."""
        try:
            if self.kind == "bool":
                if isinstance(value, bool):
                    return value
                if isinstance(value, str):
                    low = value.strip().lower()
                    if low in ("1", "true", "yes", "on", "y"):
                        return True
                    if low in ("0", "false", "no", "off", "n"):
                        return False
                    return self.default
                return bool(value)
            if self.kind == "int":
                return int(value)
            if self.kind == "float":
                return float(value)
            if self.kind == "choice":
                if self.choices and value not in self.choices:
                    return self.default
                return value
            return "" if value is None else str(value)
        except (TypeError, ValueError):
            return self.default

    def label(self) -> str:
        return self.key.split(".", 1)[-1].replace("_", " ")


# ---------------------------------------------------------------------------
# the schema: this *is* the parameter list of the application
# ---------------------------------------------------------------------------

SCHEMA: Dict[str, Param] = {}


def register(param: Param) -> Param:
    SCHEMA[param.key] = param
    return param


def _p(*args, **kwargs) -> None:
    register(Param(*args, **kwargs))


# -- look & feel -------------------------------------------------------------
_p("ui.theme", "classic", "choice",
   ["classic", "midnight", "amber", "forest", "mono", "solarized", "paper",
    "dracula", "nord", "gruvbox"],
   "Colour theme (any file in themes/ can add its own)", "appearance")
_p("ui.border", "auto", "choice", ["auto", "unicode", "ascii", "double", "rounded", "none"],
   "Frame style: auto picks unicode unless the locale is not UTF-8", "appearance")
_p("ui.density", "comfortable", "choice", ["comfortable", "compact"],
   "compact hides the column header and the in-panel footer", "appearance")
_p("ui.show_size", True, "bool", None, "Show the Size column", "appearance")
_p("ui.show_date", True, "bool", None, "Show the Modified column", "appearance")
_p("ui.date_format", "auto", "choice", ["auto", "iso", "short"],
   "auto: 'Nov 23 06:40' this year, ISO elsewhere", "appearance")
_p("ui.selected_marker", "\u2022", "str", None,
   "Glyph marking a selected entry (ASCII fallback is used automatically)", "appearance")
_p("ui.progress_style", "bar", "choice", ["bar", "blocks", "percent", "ascii"],
   "Style of the transfer progress indicator", "appearance")
_p("ui.show_hidden", True, "bool", None, "Start with hidden files visible", "appearance")
_p("ui.sort_key", "name", "choice", ["name", "size", "mtime", "ext"],
   "Initial sort order", "appearance")
_p("ui.sort_reverse", False, "bool", None, "Sort descending", "appearance")
_p("ui.layout", "auto", "choice", ["auto", "split", "stack"],
   "Panel layout: side-by-side, one panel, or automatic by width", "appearance")

# -- behaviour ---------------------------------------------------------------
_p("behaviour.restore_session", True, "bool", None,
   "Reopen the folders you were in when you quit", "behaviour")
_p("behaviour.auto_refresh", True, "bool", None,
   "Re-read a folder when something else changes it", "behaviour")
_p("behaviour.confirm_copy", True, "bool", None,
   "Ask before copying/moving a batch", "behaviour")
_p("behaviour.confirm_delete", True, "bool", None,
   "Ask before deleting (strongly recommended)", "behaviour")
_p("behaviour.mouse", True, "bool", None,
   "Enable mouse/touch reporting", "behaviour")
_p("behaviour.quit_clears_screen", False, "bool", None,
   "Clear the terminal when leaving (classic NC behaviour)", "behaviour")
_p("behaviour.update_interval", 1.0, "float", None,
   "Seconds between background redraw checks (0 disables)", "behaviour")

# -- logging -----------------------------------------------------------------
_p("logging.enabled", True, "bool", None, "Write a daily activity/error log", "logging")
_p("logging.level", "info", "choice", ["error", "info", "debug"],
   "info logs actions, debug also logs keystrokes", "logging")
_p("logging.keep_days", 14, "int", None, "Delete log files older than N days (0 = keep forever)",
   "logging")
_p("logging.dir", "", "str", None,
   "Log folder (empty = state dir, e.g. ~/.local/state/twinpane/logs)", "logging")
_p("logging.echo", False, "bool", None,
   "Also print log lines to stderr (for pipes/CI)", "logging")

# -- archives ----------------------------------------------------------------
_p("archive.default_format", "zip", "choice", ["zip", "tar.gz"],
   "Format used by the one-key compress action", "archives")
_p("archive.overwrite", "ask", "choice", ["ask", "always", "never"],
   "What extraction does when a file already exists", "archives")

# -- startup -----------------------------------------------------------------
_p("startup.left", "~", "str", None, "Folder for the left panel on a fresh start", "startup")
_p("startup.right", "", "str", None,
   "Folder for the right panel (empty = /sdcard when it exists)", "startup")
_p("startup.preselect", "last", "choice", ["last", "first", "none"],
   "Which entry has the cursor after opening a folder", "startup")


# ---------------------------------------------------------------------------
# paths
# ---------------------------------------------------------------------------

def _home() -> str:
    return os.path.expanduser("~") or os.getcwd()


def state_dir() -> str:
    """Per-user writable state folder, platform aware."""
    override = os.environ.get("TWINPANE_STATE_DIR")
    if override:
        return os.path.expanduser(override)
    if os.name == "nt":
        base = os.environ.get("LOCALAPPDATA") or os.environ.get("APPDATA") \
            or os.path.join(_home(), "AppData", "Local")
        return os.path.join(base, APP_NAME)
    xdg = os.environ.get("XDG_STATE_HOME")
    if xdg:
        return os.path.join(os.path.expanduser(xdg), APP_NAME)
    return os.path.join(_home(), ".local", "state", APP_NAME)


def config_dir() -> str:
    override = os.environ.get("TWINPANE_CONFIG_DIR")
    if override:
        return os.path.expanduser(override)
    if os.name == "nt":
        base = os.environ.get("APPDATA") or os.path.join(_home(), "AppData", "Roaming")
        return os.path.join(base, APP_NAME)
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        return os.path.join(os.path.expanduser(xdg), APP_NAME)
    return os.path.join(_home(), ".config", APP_NAME)


def config_path() -> str:
    return os.path.join(config_dir(), "config.json")


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

class Config:
    """Dict-like configuration with dotted keys and validation."""

    def __init__(self, path: Optional[str] = None, values: Optional[dict] = None):
        self.path = path or config_path()
        self.values: Dict[str, Any] = {key: param.default for key, param in SCHEMA.items()}
        self.load_errors: List[str] = []
        if values:
            self.update(values)
        self.load()

    # -- io -------------------------------------------------------------
    def load(self) -> "Config":
        self.load_errors = []
        try:
            with open(self.path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except FileNotFoundError:
            return self
        except (OSError, ValueError) as exc:
            self.load_errors.append("cannot read %s: %s" % (self.path, exc))
            return self
        if not isinstance(data, dict):
            self.load_errors.append("%s: top level must be a JSON object" % self.path)
            return self
        for key, value in data.items():
            if key.startswith("_"):      # comments / metadata
                continue
            self.update({key: value}, record=True)   # unknown keys -> warning
        return self

    def save(self) -> bool:
        """Atomic write; returns True on success."""
        folder = os.path.dirname(self.path) or "."
        try:
            os.makedirs(folder, exist_ok=True)
            payload = {"_app": APP_NAME, "_version": CONFIG_VERSION}
            payload.update(self.values)
            fd, tmp = tempfile.mkstemp(prefix=".config-", dir=folder)
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    json.dump(payload, handle, indent=2, ensure_ascii=False)
                    handle.write("\n")
                os.replace(tmp, self.path)
            finally:
                if os.path.exists(tmp):
                    try:
                        os.unlink(tmp)
                    except OSError:
                        pass
            return True
        except OSError as exc:
            self.load_errors.append("cannot write %s: %s" % (self.path, exc))
            return False

    # -- access ---------------------------------------------------------
    def get(self, key: str, default: Any = None) -> Any:
        if key in self.values:
            return self.values[key]
        param = SCHEMA.get(key)
        return param.default if param else default

    def set(self, key: str, value: Any, save: bool = True) -> Any:
        param = SCHEMA.get(key)
        if param is None:
            # unknown keys are still stored: forward compatibility for plugins
            self.values[key] = value
        else:
            self.values[key] = param.coerce(value)
        if save:
            self.save()
        return self.values[key]

    def update(self, mapping: Dict[str, Any], record: bool = True) -> None:
        for key, value in mapping.items():
            param = SCHEMA.get(key)
            if param is None:
                self.values[key] = value
                if record:
                    self.load_errors.append("unknown setting ignored: %s" % key)
            else:
                self.values[key] = param.coerce(value)

    def toggle(self, key: str) -> Any:
        current = self.get(key)
        if isinstance(current, bool):
            return self.set(key, not current)
        return current

    def cycle(self, key: str, step: int = 1) -> Any:
        param = SCHEMA.get(key)
        if param is None or param.kind != "choice":
            return self.get(key)
        choices = list(param.choices or [])
        if not choices:
            return self.get(key)
        try:
            idx = choices.index(self.get(key))
        except ValueError:
            idx = 0
        return self.set(key, choices[(idx + step) % len(choices)])

    # -- introspection for the settings screen --------------------------
    def describe(self) -> List[Tuple[str, Param, Any]]:
        """[(section, param, current_value)] ordered the way the UI shows it."""
        order = ["appearance", "behaviour", "logging", "archives", "startup", "general"]
        rows = []
        for section in order:
            for key in sorted(SCHEMA):
                param = SCHEMA[key]
                if param.section != section:
                    continue
                rows.append((section, param, self.get(key)))
        return rows

    def param_choices(self, key: str):
        param = SCHEMA.get(key)
        return list(param.choices or []) if param else []

    def as_dict(self) -> Dict[str, Any]:
        return dict(self.values)


# ---------------------------------------------------------------------------
# convenience singleton used by the UI
# ---------------------------------------------------------------------------

_config: Optional[Config] = None


def get_config(reload: bool = False) -> Config:
    global _config
    if _config is None or reload:
        _config = Config()
    return _config


def main(argv: Optional[List[str]] = None) -> int:
    """`python -m twinpane.config` - inspect/edit settings from the shell."""
    import argparse

    parser = argparse.ArgumentParser(
        prog="twinpane-config",
        description="Show or change Twin-Pane Explorer settings.")
    parser.add_argument("--path", action="store_true", help="print config file path")
    parser.add_argument("--schema", action="store_true", help="print every tunable")
    parser.add_argument("--json", action="store_true", help="dump current values as JSON")
    parser.add_argument("--set", action="append", default=[], metavar="KEY=VALUE",
                        help="change a value (repeatable)")
    parser.add_argument("--reset", action="store_true", help="restore defaults")
    args = parser.parse_args(argv)
    cfg = get_config()
    if args.path:
        print(cfg.path)
        return 0
    if args.schema:
        for section, param, value in cfg.describe():
            choices = " | ".join(str(c) for c in param.choices) if param.choices else param.kind
            print("%-12s %-28s %-26s %s" % (section, param.key, "(%s)" % choices,
                                            param.help))
        return 0
    for pair in args.set:
        if "=" not in pair:
            sys.stderr.write("expected KEY=VALUE, got %r\n" % pair)
            return 2
        key, value = pair.split("=", 1)
        print("%s = %r" % (key, cfg.set(key.strip(), value.strip())))
    if args.reset:
        for key, param in SCHEMA.items():
            cfg.values[key] = param.default
        cfg.save()
        print("defaults restored")
    if args.json:
        print(json.dumps(cfg.as_dict(), indent=2, ensure_ascii=False))
    if not any((args.set, args.reset, args.json)):
        for section, param, value in cfg.describe():
            print("%-12s %-28s %r" % (section, param.key, value))
        print("\nfile: %s" % cfg.path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
