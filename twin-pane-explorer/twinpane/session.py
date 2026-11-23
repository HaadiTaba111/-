"""Session state: reopen the same folders (and cursor) after a restart.

Kept deliberately small and crash-safe: the state file is written atomically
after every navigation, so a phone that kills Termux mid-session still restores
the last folder you were in.

File layout (``<state dir>/session.json``)::

    {
      "_app": "twinpane",
      "saved_at": "2026-11-23T06:40:11",
      "left":  {"path": "/data/.../home", "cursor": "projects", "sort": "name"},
      "right": {"path": "/sdcard/Download", "cursor": "x.zip", "sort": "size"},
      "active": 0,
      "layout": "auto"
    }
"""
from __future__ import annotations

import json
import os
import tempfile
import time
from typing import Dict, Optional

FILE_NAME = "session.json"


class Session:
    def __init__(self, directory: str):
        self.path = os.path.join(directory, FILE_NAME)
        self.data: Dict = {}
        self.loaded = False
        self.load_error = ""
        self.load()

    # -- io -------------------------------------------------------------
    def load(self) -> None:
        try:
            with open(self.path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
            if isinstance(data, dict):
                self.data = data
                self.loaded = True
        except FileNotFoundError:
            pass
        except (OSError, ValueError) as exc:
            # a corrupt file must never stop the app from starting
            self.load_error = str(exc)
            self.data = {}

    def save(self, payload: Dict) -> bool:
        self.data = dict(payload)
        folder = os.path.dirname(self.path) or "."
        try:
            os.makedirs(folder, exist_ok=True)
            body = {"_app": "twinpane",
                    "saved_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
            body.update(payload)
            fd, tmp = tempfile.mkstemp(prefix=".session-", dir=folder)
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    json.dump(body, handle, indent=2, ensure_ascii=False)
                os.replace(tmp, self.path)
            finally:
                if os.path.exists(tmp):
                    try:
                        os.unlink(tmp)
                    except OSError:
                        pass
            return True
        except (OSError, TypeError):
            return False

    def clear(self) -> None:
        self.data = {}
        try:
            os.unlink(self.path)
        except OSError:
            pass

    # -- lookups ---------------------------------------------------------
    def panel(self, index: int) -> Optional[Dict]:
        key = "left" if index == 0 else "right"
        value = self.data.get(key)
        return value if isinstance(value, dict) else None

    def folder(self, index: int) -> Optional[str]:
        """The saved folder for panel *index*, if it still exists."""
        entry = self.panel(index)
        if not entry:
            return None
        path = entry.get("path")
        if isinstance(path, str) and os.path.isdir(path):
            return path
        return None

    def cursor(self, index: int) -> str:
        entry = self.panel(index) or {}
        name = entry.get("cursor")
        return name if isinstance(name, str) else ""

    def sort(self, index: int):
        entry = self.panel(index) or {}
        key = entry.get("sort")
        reverse = bool(entry.get("reverse"))
        if key in ("name", "size", "mtime", "ext"):
            return key, reverse
        return None

    def active(self) -> int:
        try:
            value = int(self.data.get("active", 0))
        except (TypeError, ValueError):
            return 0
        return 0 if value == 0 else 1

    def layout(self) -> Optional[str]:
        value = self.data.get("layout")
        return value if value in ("auto", "split", "stack") else None
