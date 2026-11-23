"""Daily activity and error logging for Twin-Pane Explorer.

Design goals
------------
* **Zero risk to the UI**: logging never raises, never blocks on a broken
  filesystem (a read-only /sdcard, a full disk), and silently disables itself.
* **Daily files**: ``activity-YYYY-MM-DD.log`` and ``errors-YYYY-MM-DD.log``
  in the state dir, so "what did I do today" is a single file to open.
* **Readable**: one line per event, ISO timestamp, level, action and the
  details that matter (paths, sizes, durations).
* **Bounded**: old logs are pruned (``logging.keep_days``) and daily files
  are capped in size so a runaway loop cannot fill the phone.

Exposed API
-----------
    log = ActivityLog(enabled=True, level="info", directory=..., keep_days=14)
    log.action("copy", "12 files", src=..., dst=...)
    log.error("cannot open archive", exc=exc)
    log.debug("key", key="F5")
    log.close()

The module also installs a ``sys.excepthook`` helper (:func:`install_crash_hook`)
so an unexpected crash is written to the error log before the terminal is
restored.
"""
from __future__ import annotations

import datetime as _dt
import os
import sys
import traceback
from typing import Optional

MAX_BYTES_PER_DAY = 2 * 1024 * 1024   # 2 MB per file per day
LEVELS = {"error": 0, "info": 1, "debug": 2}


def _now() -> _dt.datetime:
    return _dt.datetime.now()


class ActivityLog:
    """Append-only daily log writer that can never take the app down."""

    def __init__(self, enabled: bool = True, level: str = "info",
                 directory: Optional[str] = None, keep_days: int = 14,
                 echo: bool = False, clock=None):
        self.enabled = bool(enabled)
        self.level = level if level in LEVELS else "info"
        self.directory = directory
        self.keep_days = int(keep_days or 0)
        self.echo = bool(echo)
        self._clock = clock or _now
        self._day = None
        self._activity_path = None
        self._error_path = None
        self.disabled_reason = ""
        self.writes = 0
        if self.enabled:
            self._prepare()

    # -- setup ----------------------------------------------------------
    def _prepare(self) -> None:
        try:
            os.makedirs(self.directory, exist_ok=True)
            probe = os.path.join(self.directory, ".write-test")
            with open(probe, "w") as handle:
                handle.write("ok")
            os.unlink(probe)
        except (OSError, TypeError) as exc:
            self.enabled = False
            self.disabled_reason = str(exc)
            return
        self._rotate()
        self._prune()

    def _paths_for(self, day: str):
        base = self.directory or "."
        return (os.path.join(base, "activity-%s.log" % day),
                os.path.join(base, "errors-%s.log" % day))

    def _rotate(self) -> None:
        day = self._clock().strftime("%Y-%m-%d")
        if day == self._day:
            return
        self._day = day
        self._activity_path, self._error_path = self._paths_for(day)

    def _prune(self) -> None:
        if self.keep_days <= 0 or not self.directory:
            return
        cutoff = self._clock() - _dt.timedelta(days=self.keep_days)
        try:
            names = os.listdir(self.directory)
        except OSError:
            return
        for name in names:
            if not (name.startswith("activity-") or name.startswith("errors-")):
                continue
            if not name.endswith(".log"):
                continue
            stamp = name[len("activity-"):-4] if name.startswith("activity-") \
                else name[len("errors-"):-4]
            try:
                when = _dt.datetime.strptime(stamp, "%Y-%m-%d")
            except ValueError:
                continue
            if when < cutoff:
                try:
                    os.unlink(os.path.join(self.directory, name))
                except OSError:
                    pass

    # -- writing --------------------------------------------------------
    def _write(self, path: str, level: str, message: str) -> None:
        if not self.enabled or not path:
            return
        if LEVELS.get(level, 9) > LEVELS.get(self.level, 1):
            return
        self._rotate()
        line = "%s %-5s %s\n" % (self._clock().strftime("%Y-%m-%d %H:%M:%S"),
                                 level.upper(), message.rstrip())
        try:
            try:
                if os.path.getsize(path) > MAX_BYTES_PER_DAY:
                    return          # cap: stop writing rather than fill the disk
            except OSError:
                pass
            with open(path, "a", encoding="utf-8", errors="replace") as handle:
                handle.write(line)
            self.writes += 1
            if self.echo:
                sys.stderr.write(line)
                sys.stderr.flush()
        except OSError as exc:
            # a vanished/read-only dir must not break the session
            self.enabled = False
            self.disabled_reason = str(exc)

    @staticmethod
    def _fmt(details) -> str:
        parts = []
        for key, value in (details or {}).items():
            if value is None:
                continue
            text = str(value).replace("\n", " ")
            if " " in text:
                text = '"%s"' % text
            parts.append("%s=%s" % (key, text))
        return ("  " + " ".join(parts)) if parts else ""

    # -- public API -----------------------------------------------------
    def action(self, action: str, target: str = "", **details) -> None:
        self._write(self._activity_path, "info",
                    "%-14s %s%s" % (action, target, self._fmt(details)))

    def info(self, message: str, **details) -> None:
        self._write(self._activity_path, "info", message + self._fmt(details))

    def debug(self, message: str, **details) -> None:
        self._write(self._activity_path, "debug", message + self._fmt(details))

    def error(self, message: str, exc: Optional[BaseException] = None,
              **details) -> None:
        if exc is not None:
            details.setdefault("error", "%s: %s" % (type(exc).__name__, exc))
            tb = "".join(traceback.format_exception(type(exc), exc,
                                                    exc.__traceback__)).strip()
            self._write(self._error_path, "error", message + self._fmt(details))
            for line in tb.splitlines():
                self._write(self._error_path, "error", "    " + line)
            # keep a short marker in the activity log so the timeline is complete
            self._write(self._activity_path, "error",
                        "%-14s %s%s" % ("error", message, self._fmt(details)))
        else:
            self._write(self._error_path, "error", message + self._fmt(details))

    # -- helpers used by the app ---------------------------------------
    def session_start(self, **details) -> None:
        self.info("--- session start ---", **details)

    def session_end(self, reason: str = "quit", **details) -> None:
        self.info("--- session end ---", reason=reason, **details)

    def close(self) -> None:
        self.enabled = False

    @property
    def activity_file(self) -> str:
        self._rotate()
        return self._activity_path or ""

    @property
    def error_file(self) -> str:
        self._rotate()
        return self._error_path or ""


class NullLog(ActivityLog):
    """A log that swallows everything - used before config is loaded."""

    def __init__(self):
        super().__init__(enabled=False)


def install_crash_hook(log: ActivityLog) -> None:
    """Write uncaught exceptions to the error log, then defer to the default."""
    previous = sys.excepthook

    def hook(exc_type, exc, tb):
        try:
            if exc is None:                      # some interpreters pass None
                exc = exc_type()
                exc.__traceback__ = tb
            log.error("uncaught exception", exc=exc,
                      where="%s:%s" % (os.path.basename(tb.tb_frame.f_code.co_filename),
                                       tb.tb_lineno))
        except Exception:
            pass
        if previous:
            previous(exc_type, exc, tb)

    sys.excepthook = hook


def tail(path: str, lines: int = 40, max_bytes: int = 256 * 1024) -> str:
    """Last *lines* lines of a text file, safe for the in-app viewer."""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as handle:
            if size > max_bytes:
                handle.seek(-max_bytes, os.SEEK_END)
                handle.readline()          # drop the partial first line
            data = handle.read()
        text = data.decode("utf-8", "replace")
        return "\n".join(text.splitlines()[-lines:])
    except OSError as exc:
        return "cannot read %s: %s" % (path, exc)
