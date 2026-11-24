"""Project detection, running, and the port registry.

What this is for
----------------
A phone terminal is a bad place to remember commands. When you walk into a
folder that is a project, the app should already know how to start it, whether
a newer version lives on GitHub, and which port it is squatting on.

Three separate concerns, kept separate on purpose:

* **Detect** (:func:`detect`) - look at the files in a folder and decide what
  kind of project it is. Pure function, no side effects, easy to test.
* **Run** (:class:`Runner`) - start and stop a process, remember its pid, keep
  a log. Uses plain ``subprocess``; no daemons, no root.
* **Ports** (:class:`PortRegistry`) - who is listening, and how to free a port.
  Reads ``/proc/net/tcp`` on Linux/Termux so it does not depend on ``ss`` or
  ``lsof`` being installed.

Everything here must work with no network. The "is there a newer version"
check shells out to ``git`` and is allowed to fail quietly.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import signal
import socket
import subprocess
import time
from typing import Any, Dict, List, Optional

# ---------------------------------------------------------------------------
# detection
# ---------------------------------------------------------------------------

#: Marker file -> what to do with it. Ordered: the first match wins, and more
#: specific markers come first so a Django project is not mistaken for "Python".
SIGNATURES = [
    # (marker file, kind, command template, default port)
    ("manage.py", "django", "python manage.py runserver 0.0.0.0:%(port)d", 8000),
    ("next.config.js", "next", "npm run dev -- -H 0.0.0.0 -p %(port)d", 3000),
    ("next.config.mjs", "next", "npm run dev -- -H 0.0.0.0 -p %(port)d", 3000),
    ("next.config.ts", "next", "npm run dev -- -H 0.0.0.0 -p %(port)d", 3000),
    ("vite.config.js", "vite", "npm run dev -- --host 0.0.0.0 --port %(port)d", 5173),
    ("vite.config.ts", "vite", "npm run dev -- --host 0.0.0.0 --port %(port)d", 5173),
    ("docker-compose.yml", "docker", "docker compose up", 0),
    ("docker-compose.yaml", "docker", "docker compose up", 0),
    ("compose.yaml", "docker", "docker compose up", 0),
    ("pyproject.toml", "python", "python -m uvicorn main:app --host 0.0.0.0 --port %(port)d "
                                "--reload", 8000),
    ("requirements.txt", "python", "python -m http.server %(port)d", 8000),
    ("app.py", "flask", "python app.py", 5000),
    ("main.py", "python", "python main.py", 8000),
    ("package.json", "node", "npm start", 3000),
    ("server.js", "node", "node server.js", 3000),
    ("index.js", "node", "node index.js", 3000),
    ("go.mod", "go", "go run .", 8080),
    ("Cargo.toml", "rust", "cargo run", 8080),
    ("Gemfile", "ruby", "bundle exec ruby app.rb", 4567),
]

#: A file a project can drop into its own folder to say exactly how to run.
SELF_DESCRIPTOR = "twinpane.project"


class Project:
    """What was found in one folder. Everything is optional."""

    def __init__(self, path: str, kind: str, command: str, port: int) -> None:
        self.path = path
        self.kind = kind
        self.command = command
        self.port = port
        self.name = os.path.basename(path.rstrip(os.sep)) or path
        self.marker = ""
        self.note = ""
        self.git = False
        self.branch = ""
        self.remote = ""

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return "Project(%s, %s, port=%d)" % (self.name, self.kind, self.port)

    def as_dict(self) -> Dict[str, Any]:
        return {
            "path": self.path, "name": self.name, "kind": self.kind,
            "command": self.command, "port": self.port, "marker": self.marker,
            "git": self.git, "branch": self.branch, "remote": self.remote,
            "note": self.note,
        }


def _read_json(path: str) -> Optional[Dict[str, Any]]:
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def _package_scripts(folder: str) -> Dict[str, str]:
    data = _read_json(os.path.join(folder, "package.json")) or {}
    scripts = data.get("scripts")
    return scripts if isinstance(scripts, dict) else {}


def _fastapi_in(path: str) -> bool:
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            head = handle.read(4000)
    except OSError:
        return False
    return "FastAPI(" in head or "fastapi import" in head


def detect(folder: str) -> Optional[Project]:
    """Decide whether *folder* is a project, and how to start it.

    Returns None for a folder that is not a project. Never raises: a broken
    file in a project must not stop the file manager from opening.
    """
    if not folder or not os.path.isdir(folder):
        return None
    folder = os.path.abspath(folder)

    # 1. A project that describes itself always wins.
    descriptor = os.path.join(folder, SELF_DESCRIPTOR)
    if os.path.isfile(descriptor):
        data = _read_json(descriptor) or {}
        project = Project(
            folder,
            str(data.get("kind") or "custom"),
            str(data.get("run") or data.get("command") or ""),
            int(data.get("port") or 0),
        )
        project.marker = SELF_DESCRIPTOR
        project.note = str(data.get("note") or "")
        _fill_git(project)
        return project

    # 2. Signature files, most specific first.
    for marker, kind, template, port in SIGNATURES:
        if not os.path.exists(os.path.join(folder, marker)):
            continue

        command = template
        # Refine where the generic template would be wrong.
        if marker == "package.json":
            scripts = _package_scripts(folder)
            if "dev" in scripts:
                command = "npm run dev"
            elif "start" in scripts:
                command = "npm start"
            else:
                continue                       # a library, not an app
        if marker == "pyproject.toml" and not _fastapi_in(
                os.path.join(folder, "main.py")):
            # No main:app to serve; fall back to something that always works.
            command = "python -m http.server %(port)d"
        if marker == "requirements.txt":
            if _fastapi_in(os.path.join(folder, "main.py")):
                command = ("python -m uvicorn main:app --host 0.0.0.0 "
                           "--port %(port)d --reload")
                kind = "fastapi"
            elif os.path.exists(os.path.join(folder, "manage.py")):
                continue                       # django is handled above
        if marker == "main.py" and _fastapi_in(os.path.join(folder, "main.py")):
            command = ("python -m uvicorn main:app --host 0.0.0.0 "
                       "--port %(port)d --reload")
            kind = "fastapi"

        # Use the project's own virtualenv when it has one.
        if kind in ("python", "fastapi", "flask", "django"):
            for candidate in (".venv/bin/python", "venv/bin/python", "env/bin/python"):
                if os.path.exists(os.path.join(folder, candidate)):
                    command = command.replace("python ", candidate + " ", 1)
                    break

        project = Project(folder, kind, command, port)
        project.marker = marker
        _fill_git(project)
        return project

    # 3. A git checkout with a README is often a project even without a marker.
    if os.path.isdir(os.path.join(folder, ".git")):
        project = Project(folder, "git", "", 0)
        project.marker = ".git"
        project.note = "no run command detected"
        _fill_git(project)
        return project
    return None


def _fill_git(project: Project) -> None:
    git_dir = os.path.join(project.path, ".git")
    if not os.path.isdir(git_dir):
        return
    project.git = True
    head = os.path.join(git_dir, "HEAD")
    try:
        with open(head, encoding="utf-8") as handle:
            line = handle.readline().strip()
        if line.startswith("ref: refs/heads/"):
            project.branch = line[len("ref: refs/heads/"):]
    except OSError:
        pass
    config = os.path.join(git_dir, "config")
    try:
        with open(config, encoding="utf-8") as handle:
            text = handle.read()
        match = re.search(r'\[remote "origin"\][^\[]*?url\s*=\s*(\S+)', text, re.S)
        if match:
            project.remote = match.group(1)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# ports
# ---------------------------------------------------------------------------

def listening_ports() -> Dict[int, Dict[str, Any]]:
    """Ports with a listener, read from /proc so nothing extra is needed.

    Returns ``{port: {"addr": ..., "inode": ...}}``. Empty on a platform
    without /proc (the caller then falls back to trying the socket).
    """
    found: Dict[int, Dict[str, Any]] = {}
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, encoding="ascii", errors="replace") as handle:
                next(handle, None)                     # header
                for line in handle:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    if state != "0A":                  # 0A == LISTEN
                        continue
                    try:
                        port = int(local.rsplit(":", 1)[1], 16)
                    except (IndexError, ValueError):
                        continue
                    found[port] = {"addr": local.rsplit(":", 1)[0],
                                   "inode": fields[9],
                                   "table": table}
        except OSError:
            continue
    return found


def port_is_free(port: int) -> bool:
    if not port:
        return True
    if port in listening_ports():
        return False
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("127.0.0.1", port))
        return True
    except OSError:
        return False
    finally:
        sock.close()


def find_free_port(start: int, tries: int = 40) -> int:
    """The next port at or after *start* that nothing is listening on."""
    port = max(1, int(start or 8000))
    for _ in range(tries):
        if port_is_free(port):
            return port
        port += 1
    return port


def free_port(port: int) -> bool:
    """Ask whatever owns *port* to stop. Returns True if it is gone."""
    if not port:
        return True
    if port_is_free(port):
        return True
    # Try the tools Termux usually has, then fall back to /proc + kill.
    for command in (
        ["fuser", "-k", "%d/tcp" % port],
        ["sh", "-c", "kill $(lsof -t -i:%d) 2>/dev/null" % port],
    ):
        if shutil.which(command[0]) is None:
            continue
        try:
            subprocess.run(command, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=4)
        except (OSError, subprocess.SubprocessError):
            continue
        if port_is_free(port):
            return True
    return port_is_free(port)


class PortRegistry:
    """Which of *our* projects claimed which port, so `stop` can free it."""

    def __init__(self, path: Optional[str] = None) -> None:
        from . import config as config_mod
        self.path = path or os.path.join(
            config_mod.state_dir(), "projects-ports.json")

    def _load(self) -> Dict[str, Any]:
        try:
            with open(self.path, encoding="utf-8") as handle:
                data = json.load(handle)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def _save(self, data: Dict[str, Any]) -> None:
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        temporary = self.path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=1)
        os.replace(temporary, self.path)

    def assign(self, path: str, port: int) -> None:
        data = self._load()
        data[os.path.abspath(path)] = {"port": int(port), "since": time.time()}
        self._save(data)

    def release(self, path: str) -> None:
        data = self._load()
        data.pop(os.path.abspath(path), None)
        self._save(data)

    def port_of(self, path: str) -> int:
        entry = self._load().get(os.path.abspath(path)) or {}
        try:
            return int(entry.get("port") or 0)
        except (TypeError, ValueError):
            return 0

    def all(self) -> Dict[str, Any]:
        return self._load()


# ---------------------------------------------------------------------------
# git: is there something newer?
# ---------------------------------------------------------------------------

def git_state(folder: str) -> Dict[str, Any]:
    """Local vs remote for *folder*, without touching the network if possible.

    ``git fetch`` is the only networked call and is allowed to fail - the file
    manager must stay usable on a phone with no data.
    """
    state: Dict[str, Any] = {"repo": False, "branch": "", "dirty": False,
                             "ahead": 0, "behind": 0, "remote": "", "error": ""}
    git = os.path.join(folder, ".git")
    if not os.path.isdir(git):
        return state
    state["repo"] = True
    if shutil.which("git") is None:
        state["error"] = "git is not installed"
        return state

    def run(*args: str, timeout: float = 6.0) -> str:
        try:
            done = subprocess.run(
                ["git", "-C", folder] + list(args),
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                timeout=timeout, check=False)
            return done.stdout.decode("utf-8", "replace").strip()
        except (OSError, subprocess.SubprocessError):
            return ""

    state["branch"] = run("rev-parse", "--abbrev-ref", "HEAD")
    state["dirty"] = bool(run("status", "--porcelain"))
    state["remote"] = run("config", "--get", "remote.origin.url")
    if not state["remote"]:
        return state

    # Ask the remote. Blocking a UI for long would be wrong, so this is only
    # called from a "check for updates" action, never from draw().
    run("fetch", "--quiet", "--depth", "1", timeout=20)
    counts = run("rev-list", "--left-right", "--count", "HEAD...@{upstream}")
    if counts:
        parts = counts.split()
        if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
            state["ahead"], state["behind"] = int(parts[0]), int(parts[1])
    return state


def pull(folder: str) -> Dict[str, Any]:
    """``git pull --ff-only``: never creates a merge commit behind your back."""
    if not os.path.isdir(os.path.join(folder, ".git")):
        return {"ok": False, "error": "not a git checkout"}
    try:
        done = subprocess.run(
            ["git", "-C", folder, "pull", "--ff-only"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=120, check=False)
    except (OSError, subprocess.SubprocessError) as error:
        return {"ok": False, "error": str(error)}
    output = done.stdout.decode("utf-8", "replace").strip()
    return {"ok": done.returncode == 0, "output": output[-1500:],
            "error": "" if done.returncode == 0 else output[-400:]}


def clone(url: str, dest: str) -> Dict[str, Any]:
    """Shallow clone, so a phone is not made to download a decade of history."""
    if not url:
        return {"ok": False, "error": "no repository URL"}
    if os.path.exists(dest) and os.listdir(dest):
        return {"ok": False, "error": "%s is not empty" % dest}
    if shutil.which("git") is None:
        return {"ok": False, "error": "git is not installed"}
    try:
        done = subprocess.run(
            ["git", "clone", "--depth", "1", url, dest],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=600, check=False)
    except (OSError, subprocess.SubprocessError) as error:
        return {"ok": False, "error": str(error)}
    return {"ok": done.returncode == 0,
            "output": done.stdout.decode("utf-8", "replace")[-1500:],
            "error": "" if done.returncode == 0
            else done.stdout.decode("utf-8", "replace")[-400:]}


# ---------------------------------------------------------------------------
# running
# ---------------------------------------------------------------------------

class Runner:
    """Start and stop project servers, keeping a pid and a log per project."""

    def __init__(self, state_dir: Optional[str] = None) -> None:
        from . import config as config_mod
        self.dir = state_dir or os.path.join(config_mod.state_dir(), "servers")
        os.makedirs(self.dir, exist_ok=True)
        self.ports = PortRegistry()

    # -- files -----------------------------------------------------------
    def _key(self, path: str) -> str:
        safe = re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.abspath(path))
        return safe.strip("_")[:120]

    def _meta_path(self, path: str) -> str:
        return os.path.join(self.dir, self._key(path) + ".json")

    def log_path(self, path: str) -> str:
        return os.path.join(self.dir, self._key(path) + ".log")

    def _meta(self, path: str) -> Dict[str, Any]:
        return _read_json(self._meta_path(path)) or {}

    def _write_meta(self, path: str, data: Dict[str, Any]) -> None:
        temporary = self._meta_path(path) + ".tmp"
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=1)
        os.replace(temporary, self._meta_path(path))

    # -- process ---------------------------------------------------------
    @staticmethod
    def _alive(pid: int) -> bool:
        if not pid:
            return False
        try:
            os.kill(pid, 0)
        except OSError:
            return False
        # A zombie still answers signal 0; check the state field.
        try:
            with open("/proc/%d/stat" % pid, encoding="ascii",
                      errors="replace") as handle:
                return handle.read().split(") ", 1)[1][:1] != "Z"
        except (OSError, IndexError):
            return True

    def status(self, path: str) -> Dict[str, Any]:
        meta = self._meta(path)
        pid = int(meta.get("pid") or 0)
        running = self._alive(pid)
        port = int(meta.get("port") or 0)
        return {
            "running": running,
            "pid": pid if running else 0,
            "port": port,
            "url": ("http://localhost:%d" % port) if port else "",
            "command": meta.get("command", ""),
            "started": meta.get("started", 0),
            "log": self.log_path(path),
            "in_use": bool(port) and not port_is_free(port),
        }

    def start(self, path: str, command: str, port: int = 0,
              prefer_new_port: bool = True) -> Dict[str, Any]:
        """Start *command* inside *path*.

        If the wanted port is taken, a free one is chosen automatically and
        reported back - that is the whole answer to "the browser cache is in my
        way, just give me another port".
        """
        path = os.path.abspath(path)
        current = self.status(path)
        if current["running"]:
            return {"ok": True, "already": True, **current}

        wanted = int(port or 0)
        chosen = wanted
        if wanted:
            if not port_is_free(wanted) and prefer_new_port:
                chosen = find_free_port(wanted + 1)
            elif not port_is_free(wanted):
                return {"ok": False,
                        "error": "port %d is in use (free it first)" % wanted}
        command = command.replace("%(port)d", str(chosen or wanted))
        if not command.strip():
            return {"ok": False, "error": "no run command"}

        log = self.log_path(path)
        try:
            handle = open(log, "ab", buffering=0)
        except OSError as error:
            return {"ok": False, "error": "cannot open the log: %s" % error}

        handle.write(("\n=== %s  %s  (port %s) ===\n"
                      % (time.strftime("%Y-%m-%d %H:%M:%S"), command,
                         chosen or "-")).encode("utf-8"))
        try:
            process = subprocess.Popen(
                ["sh", "-c", command],
                cwd=path, stdout=handle, stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL, start_new_session=True)
        except OSError as error:
            handle.close()
            return {"ok": False, "error": str(error)}

        # Written before anything is waited on: all() finds projects through
        # this file, so a command that dies instantly must still leave one.
        self._write_meta(path, {
            "path": path, "pid": process.pid, "port": chosen,
            "command": command, "started": time.time(), "log": log,
        })
        if chosen:
            self.ports.assign(path, chosen)

        # Give it a moment: a server that dies immediately should say so now,
        # not silently look "running" forever.
        for _ in range(12):
            time.sleep(0.1)
            if process.poll() is not None:
                break
        if process.poll() is not None:
            tail = self.tail(path, 12)
            return {"ok": False, "error": "it exited at once",
                    "log": "\n".join(tail)}
        return {"ok": True, "pid": process.pid, "port": chosen,
                "url": ("http://localhost:%d" % chosen) if chosen else "",
                "log": log}

    def stop(self, path: str, free: bool = True) -> Dict[str, Any]:
        meta = self._meta(path)
        pid = int(meta.get("pid") or 0)
        port = int(meta.get("port") or 0)
        killed = False
        if self._alive(pid):
            for attempt in (signal.SIGTERM, signal.SIGTERM, signal.SIGKILL):
                try:
                    os.killpg(os.getpgid(pid), attempt)
                except OSError:
                    try:
                        os.kill(pid, attempt)
                    except OSError:
                        break
                for _ in range(10):
                    if not self._alive(pid):
                        killed = True
                        break
                    time.sleep(0.1)
                if killed:
                    break
        stopped_port = False
        if free and port:
            stopped_port = free_port(port)
            self.ports.release(path)
        try:
            os.unlink(self._meta_path(path))
        except OSError:
            pass
        return {"ok": True, "killed": killed, "port": port,
                "port_freed": stopped_port}

    def tail(self, path: str, lines: int = 40) -> List[str]:
        try:
            with open(self.log_path(path), encoding="utf-8",
                      errors="replace") as handle:
                content = handle.readlines()
        except OSError:
            return []
        return [line.rstrip("\n") for line in content[-lines:]]

    def all(self) -> List[Dict[str, Any]]:
        """Every project this app has a record of, running or not."""
        found = []
        try:
            names = os.listdir(self.dir)
        except OSError:
            return found
        for name in names:
            if not name.endswith(".json"):
                continue
            meta = _read_json(os.path.join(self.dir, name)) or {}
            path = meta.get("path") or ""
            if not path:
                continue
            state = self.status(path)
            state["path"] = path
            state["name"] = os.path.basename(path.rstrip(os.sep)) or path
            found.append(state)
        found.sort(key=lambda item: item.get("name", ""))
        return found
