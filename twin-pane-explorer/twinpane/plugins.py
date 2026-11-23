"""Tiny hook and command registry - the *modularity* part of the design.

Two extension points, both optional and both failure-isolated:

1. **Hooks** - named events the app fires (``startup``, ``quit``, ``copy``,
   ``delete``, ``archive``, ``navigate``, ``key``).  A hook handler is a plain
   callable receiving keyword arguments; if one raises, the error is logged and
   the other handlers still run.  Handlers can return a string to replace the
   command's result message.

2. **Commands** - named actions a plugin can add to the UI (they show up in the
   F9 menu automatically).  A command is ``(label, callable)`` where callable
   takes the app object.

Third-party plugins are small Python files in ``<config dir>/plugins/*.py``::

    # ~/.config/twinpane/plugins/my_sync.py
    def register(api):
        @api.hook("copy")
        def after_copy(sources, dest, result):
            api.log.action("my-sync", dest, files=result.files)
            return None

        api.command("Sync to Nextcloud", lambda app: app.info("todo"))

Load order is deterministic (sorted by file name) and each file is sandboxed:
an import error is logged and skipped, never fatal.
"""
from __future__ import annotations

import importlib.util
import os
import sys
from typing import Callable, Dict, List, Optional, Tuple

HOOK_NAMES = ("startup", "quit", "navigate", "copy", "move", "delete",
              "archive", "extract", "key", "theme_change", "config_change")


class PluginAPI:
    """The object handed to a plugin's ``register(api)``."""

    def __init__(self, registry: "Registry", name: str):
        self._registry = registry
        self.name = name
        self.log = registry.log

    def hook(self, event: str):
        if event not in HOOK_NAMES:
            self.log.error("plugin %s: unknown hook %r" % (self.name, event))
        def decorator(func: Callable):
            self._registry.add_hook(event, func, self.name)
            return func
        return decorator

    def command(self, label: str, handler: Callable) -> None:
        self._registry.add_command(label, handler, self.name)

    def setting(self, param) -> None:
        """Register a config Param so it appears in the settings screen."""
        from .config import register
        register(param)


class Registry:
    def __init__(self, log):
        self.log = log
        self.hooks: Dict[str, List[Tuple[str, Callable]]] = {name: [] for name in HOOK_NAMES}
        self._commands: List[Tuple[str, Callable, str]] = []
        self.loaded: List[str] = []
        self.failed: List[str] = []

    # -- registration ---------------------------------------------------
    def add_hook(self, event: str, func: Callable, source: str = "core") -> None:
        if event not in HOOK_NAMES:
            raise ValueError("unknown hook %r (known: %s)"
                             % (event, ", ".join(HOOK_NAMES)))
        self.hooks.setdefault(event, []).append((source, func))

    def add_command(self, label: str, handler: Callable, source: str = "core") -> None:
        self._commands.append((label, handler, source))

    def commands(self):
        """[(label, handler, source)] - source names the plugin for the UI."""
        return list(self._commands)

    # -- firing ---------------------------------------------------------
    def fire(self, event: str, **kwargs):
        """Run every handler for *event*; returns the first non-None result."""
        result = None
        for source, func in list(self.hooks.get(event, ())):
            try:
                value = func(**kwargs)
                if value is not None and result is None:
                    result = value
            except Exception as exc:          # isolation: one plugin cannot
                self.log.error("hook %s from %s failed" % (event, source), exc=exc)
        return result

    # -- loading --------------------------------------------------------
    def load_directory(self, directory: str) -> None:
        try:
            names = sorted(n for n in os.listdir(directory) if n.endswith(".py")
                           and not n.startswith("_"))
        except OSError:
            return
        for name in names:
            path = os.path.join(directory, name)
            module_name = "twinpane_plugin_%s" % os.path.splitext(name)[0]
            try:
                spec = importlib.util.spec_from_file_location(module_name, path)
                if spec is None or spec.loader is None:
                    raise ImportError("cannot load %s" % path)
                module = importlib.util.module_from_spec(spec)
                sys.modules[module_name] = module
                spec.loader.exec_module(module)
                register = getattr(module, "register", None)
                if not callable(register):
                    self.failed.append("%s: no register(api) function" % name)
                    self.log.error("plugin %s has no register(api)" % name)
                    continue
                register(PluginAPI(self, name))
                self.loaded.append(name)
                self.log.info("plugin loaded", plugin=name)
            except Exception as exc:
                self.failed.append("%s: %s" % (name, exc))
                self.log.error("plugin %s failed to load" % name, exc=exc)


_registry: Optional[Registry] = None


def get_registry(log=None) -> Registry:
    global _registry
    if _registry is None:
        _registry = Registry(log)
    elif log is not None:
        _registry.log = log
    return _registry
