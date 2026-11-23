"""The bridge: let the Android app drive the Termux copy engine.

Why this exists
---------------
Termux can read everything: its own home (``~``) *and* the phone's storage
(``~/storage/shared`` == ``/sdcard``). A normal Android app can only see
``/sdcard``. So the moment a file has to move between Termux and the phone, the
only program that can actually do it is the one inside Termux.

The bridge is a deliberately boring file protocol in a folder both sides can
read (``/sdcard/TwinPane/bridge``)::

    requests/  <id>.json    the app writes what it wants
    work/      <id>.json     the worker claims a request by renaming it here
    results/   <id>.json     the worker writes the outcome

A rename on the same filesystem is atomic, which is what makes "claim the
request" safe even if two workers ever ran at once. No sockets, no ports, no
server that has to keep running, no root.

Design rules
------------
* **Never trust the request blindly.** Paths are resolved and checked, items
  that do not exist are reported instead of crashing the worker.
* **Never lose data.** The engine reuses :mod:`twinpane.fsops`, which already
  handles cross-filesystem moves, conflicts and cancellation.
* **Never leave a request half-read.** Results are written to a temp name and
  renamed into place.
* **Stay quiet when there is nothing to do.** One directory listing per poll.
"""
from __future__ import annotations

import json
import os
import time
import traceback
from typing import Any, Dict, List, Optional

from . import fsops

BRIDGE_DIRNAME = "TwinPane/bridge"
HEARTBEAT_NAME = "worker.json"
MAX_RESULTS = 200


# ---------------------------------------------------------------------------
# paths
# ---------------------------------------------------------------------------

def default_bridge_dir() -> str:
    """``/sdcard/TwinPane/bridge``, or a Termux-only fallback."""
    candidates = [
        "/sdcard/" + BRIDGE_DIRNAME,
        os.path.expanduser("~/storage/shared/" + BRIDGE_DIRNAME),
        os.path.expanduser("~/TwinPane/bridge"),
    ]
    for candidate in candidates:
        parent = os.path.dirname(os.path.dirname(candidate))
        if os.path.isdir(parent):
            return candidate
    # Nothing is mounted: keep it inside the Termux home so the worker still runs.
    return os.path.expanduser("~/TwinPane/bridge")


class Bridge:
    """A folder of JSON files shared between the app and this worker."""

    def __init__(self, root: Optional[str] = None) -> None:
        self.root = os.path.abspath(root or default_bridge_dir())
        self.requests = os.path.join(self.root, "requests")
        self.work = os.path.join(self.root, "work")
        self.results = os.path.join(self.root, "results")

    # -- setup -----------------------------------------------------------
    def ensure(self) -> None:
        for folder in (self.root, self.requests, self.work, self.results):
            os.makedirs(folder, exist_ok=True)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return "Bridge(%r)" % self.root

    # -- requests --------------------------------------------------------
    def pending(self) -> List[str]:
        """Request ids waiting to be claimed, oldest first."""
        try:
            names = os.listdir(self.requests)
        except OSError:
            return []
        ids = [name[:-5] for name in names if name.endswith(".json")]
        ids.sort(key=lambda item: os.path.getmtime(
            os.path.join(self.requests, item + ".json"))
            if os.path.exists(os.path.join(self.requests, item + ".json")) else 0)
        return ids

    def claim(self, request_id: str) -> Optional[Dict[str, Any]]:
        """Atomically take a request. Returns None if it is gone or unreadable."""
        source = os.path.join(self.requests, request_id + ".json")
        claimed = os.path.join(self.work, request_id + ".json")
        try:
            os.replace(source, claimed)
        except OSError:
            return None                      # another worker got there first
        try:
            with open(claimed, encoding="utf-8") as handle:
                return json.load(handle)
        except (OSError, ValueError):
            # A corrupt request still has to produce a result, or the app waits
            # forever. Answer it with an error and move on.
            return {"op": "?", "corrupt": True}

    def finish(self, request_id: str, payload: Dict[str, Any]) -> None:
        payload = dict(payload)
        payload.setdefault("id", request_id)
        payload["finished"] = time.time()
        target = os.path.join(self.results, request_id + ".json")
        temporary = target + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
        os.replace(temporary, target)
        try:
            os.unlink(os.path.join(self.work, request_id + ".json"))
        except OSError:
            pass

    # -- housekeeping ----------------------------------------------------
    def heartbeat(self, extra: Optional[Dict[str, Any]] = None) -> None:
        """Tell the app a worker is alive, and where its stuff lives."""
        payload = {
            "pid": os.getpid(),
            "version": _version(),
            "home": os.path.expanduser("~"),
            "shared": shared_root(),
            "bridge": self.root,
            "time": time.time(),
        }
        if extra:
            payload.update(extra)
        target = os.path.join(self.root, HEARTBEAT_NAME)
        temporary = target + ".tmp"
        try:
            with open(temporary, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, ensure_ascii=False)
            os.replace(temporary, target)
        except OSError:
            pass

    def prune(self, keep: int = MAX_RESULTS) -> int:
        """Drop old results so the folder cannot grow without bound."""
        try:
            names = [name for name in os.listdir(self.results)
                     if name.endswith(".json")]
        except OSError:
            return 0
        if len(names) <= keep:
            return 0
        paths = [os.path.join(self.results, name) for name in names]
        paths.sort(key=lambda path: os.path.getmtime(path))
        removed = 0
        for path in paths[:len(paths) - keep]:
            try:
                os.unlink(path)
                removed += 1
            except OSError:
                pass
        return removed


def shared_root() -> Optional[str]:
    """The phone storage path as seen from Termux, when it exists."""
    for candidate in ("/sdcard", os.path.expanduser("~/storage/shared")):
        if os.path.isdir(candidate):
            return candidate
    return None


def _version() -> str:
    try:
        from . import __version__
        return __version__
    except Exception:                          # pragma: no cover
        return "?"


# ---------------------------------------------------------------------------
# operations
# ---------------------------------------------------------------------------

LIST_LIMIT = 4000


def resolve(path: str) -> str:
    """Expand ``~`` and make the path absolute, without requiring existence."""
    if not path:
        raise ValueError("empty path")
    expanded = os.path.expanduser(str(path))
    return os.path.abspath(expanded)


def operation_list(payload: Dict[str, Any]) -> Dict[str, Any]:
    """List one folder. The app calls this for the Termux panel."""
    path = resolve(payload.get("path") or "~")
    show_hidden = bool(payload.get("hidden", False))
    if not os.path.isdir(path):
        return {"ok": False, "error": "not a folder: %s" % path}
    entries, errors = fsops.list_dir(path, show_hidden=show_hidden)
    entries = fsops.sort_entries(entries, key="name")
    rows = []
    for entry in entries[:LIST_LIMIT]:
        rows.append({
            "name": entry.name,
            "path": entry.path,
            "dir": bool(entry.is_dir),
            "size": int(entry.size),
            "mtime": float(entry.mtime),
            "link": bool(entry.is_link),
        })
    parent = os.path.dirname(path)
    return {
        "ok": True,
        "path": path,
        "parent": parent if parent != path else None,
        "entries": rows,
        "truncated": len(entries) > LIST_LIMIT,
        "errors": errors[:20],
        "places": places(),
    }


def places() -> List[Dict[str, str]]:
    """Shortcuts the app can offer in its jump menu."""
    found = []
    candidates = [
        ("Termux home  ~", os.path.expanduser("~")),
        ("Phone storage  /sdcard", shared_root() or ""),
        ("Downloads", os.path.expanduser("~/storage/downloads")),
        ("DCIM", os.path.expanduser("~/storage/dcim")),
        ("Pictures", os.path.expanduser("~/storage/pictures")),
        ("shared  (TwinPane)", os.path.join(shared_root() or "", "TwinPane")),
    ]
    seen = set()
    for label, path in candidates:
        if not path or path in seen or not os.path.isdir(path):
            continue
        seen.add(path)
        found.append({"label": label, "path": path})
    return found


def is_inside(child: str, parent: str) -> bool:
    """True when *parent* is *child* or lives inside it (data-loss guard)."""
    child = os.path.abspath(child)
    parent = os.path.abspath(parent)
    return parent == child or parent.startswith(child + os.sep)


def operation_transfer(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Copy or move a list of paths into one destination folder."""
    sources = [resolve(item) for item in payload.get("items") or []]
    if not sources:
        return {"ok": False, "error": "no items given"}
    dest = resolve(payload.get("dest") or "")
    if not os.path.isdir(dest):
        return {"ok": False, "error": "destination is not a folder: %s" % dest}
    # The app sends "op": "copy"/"move"; older callers may send "mode".
    # Reading only one of them silently turned every move into a copy - the
    # tests caught it, so both spellings are accepted here.
    mode = str(payload.get("mode") or payload.get("op") or "copy").lower()
    if mode not in ("copy", "move"):
        return {"ok": False, "error": "mode must be copy or move"}

    missing = [path for path in sources if not os.path.exists(path)]
    if missing:
        return {"ok": False, "error": "missing: " + ", ".join(missing[:5]),
                "missing": missing[:50]}
    for path in sources:
        if is_inside(path, dest):
            return {"ok": False,
                    "error": "cannot put a folder inside itself: %s" % path}

    conflict = str(payload.get("conflict") or "rename").lower()
    if conflict not in ("rename", "overwrite", "skip"):
        conflict = "rename"
    conflict_map = {"rename": fsops.RENAME, "overwrite": fsops.OVERWRITE,
                    "skip": fsops.SKIP}

    job = fsops.Transfer()
    job.conflict_cb = lambda _dst: conflict_map[conflict]
    try:
        if mode == "move":
            result = job.run_move(sources, dest)
        else:
            result = job.run_copy(sources, dest)
    except Exception as error:                       # pragma: no cover
        return {"ok": False, "error": "%s: %s" % (type(error).__name__, error)}
    return {
        "ok": True,
        "mode": mode,
        "dest": dest,
        "files": result.files,
        "dirs": result.dirs,
        "bytes": result.bytes_,
        "skipped": result.skipped,
        "errors": result.errors[:20],
        "summary": result.summary(),
    }


def operation_delete(payload: Dict[str, Any]) -> Dict[str, Any]:
    sources = [resolve(item) for item in payload.get("items") or []]
    if not sources:
        return {"ok": False, "error": "no items given"}
    job = fsops.Transfer()
    result = job.run_delete(sources)
    return {
        "ok": True,
        "files": result.files,
        "dirs": result.dirs,
        "errors": result.errors[:20],
        "summary": result.summary(),
    }


def operation_mkdir(payload: Dict[str, Any]) -> Dict[str, Any]:
    parent = resolve(payload.get("path") or "")
    name = str(payload.get("name") or "").strip()
    if not name:
        return {"ok": False, "error": "empty name"}
    try:
        created = fsops.make_dir(parent, name)
    except Exception as error:
        return {"ok": False, "error": str(error)}
    return {"ok": True, "path": created, "summary": "Created %s" % name}


OPERATIONS = {
    "list": operation_list,
    "copy": operation_transfer,
    "move": operation_transfer,
    "delete": operation_delete,
    "mkdir": operation_mkdir,
    "ping": lambda payload: {"ok": True, "pong": True,
                             "bridge": payload.get("_bridge")},
}


def handle(bridge: Bridge, request_id: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    """Run one request and always return something the app can act on."""
    operation = str(payload.get("op") or payload.get("operation") or "").lower()
    handler = OPERATIONS.get(operation)
    if handler is None:
        return {"ok": False, "op": operation, "error": "unknown op: %r" % operation}
    started = time.time()
    try:
        result = handler(payload)
    except Exception as error:
        result = {"ok": False, "op": operation,
                  "error": "%s: %s" % (type(error).__name__, error),
                  "trace": traceback.format_exc(limit=3)}
    result.setdefault("op", operation)
    result["seconds"] = round(time.time() - started, 3)
    return result


# ---------------------------------------------------------------------------
# worker loop
# ---------------------------------------------------------------------------

def poll_once(bridge: Bridge, verbose: bool = False) -> int:
    """Claim and run every pending request. Returns how many ran."""
    bridge.ensure()
    bridge.heartbeat({"state": "working"})
    done = 0
    for request_id in bridge.pending():
        payload = bridge.claim(request_id)
        if payload is None:
            continue
        if payload.get("corrupt"):
            bridge.finish(request_id, {"ok": False, "error": "unreadable request"})
            done += 1
            continue
        if verbose:
            print("  -> %s %s" % (payload.get("op"), request_id))
        result = handle(bridge, request_id, payload)
        bridge.finish(request_id, result)
        done += 1
    bridge.prune()
    bridge.heartbeat({"state": "idle", "time": time.time()})
    return done


def serve(interval: float = 0.6, verbose: bool = True,
          stop_after: Optional[float] = None,
          bridge_dir: Optional[str] = None) -> int:
    """Watch the bridge folder until interrupted.

    Started by ``twinpane-bridge`` (a Termux service or a plain background
    command). Deliberately dumb: sleep, look, work, sleep.
    """
    bridge = Bridge(bridge_dir)
    bridge.ensure()
    if verbose:
        print("Twin-Pane bridge")
        print("  folder : %s" % bridge.root)
        print("  terminal home : %s" % os.path.expanduser("~"))
        print("  phone storage : %s" % (shared_root() or "not mounted"))
        print("  waiting for requests… (Ctrl-C to stop)")
    started = time.monotonic()
    interval = max(0.2, float(interval))
    try:
        while True:
            poll_once(bridge, verbose=verbose)
            if stop_after is not None and time.monotonic() - started >= stop_after:
                return 0
            time.sleep(interval)
    except KeyboardInterrupt:
        if verbose:
            print("\nstopped")
        return 0


def main(argv: Optional[List[str]] = None) -> int:
    """``python -m twinpane.bridge [--once] [--dir PATH] [--interval SECS]``."""
    import argparse

    parser = argparse.ArgumentParser(
        prog="twinpane-bridge",
        description="Serve copy/move requests from the Twin-Pane Android app.")
    parser.add_argument("--dir", help="bridge folder (default: /sdcard/TwinPane/bridge)")
    parser.add_argument("--interval", type=float, default=0.6,
                        help="seconds between polls (default: 0.6)")
    parser.add_argument("--once", action="store_true",
                        help="handle what is queued, then exit")
    parser.add_argument("--stop-after", type=float, default=None,
                        help="exit after this many seconds (for tests)")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    if args.once:
        bridge = Bridge(args.dir)
        count = poll_once(bridge, verbose=not args.quiet)
        if not args.quiet:
            print("handled %d request%s" % (count, "" if count == 1 else "s"))
        return 0
    return serve(interval=args.interval, verbose=not args.quiet,
                 stop_after=args.stop_after, bridge_dir=args.dir)


if __name__ == "__main__":                     # pragma: no cover
    raise SystemExit(main())
