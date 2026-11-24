"""Detection, running and ports.

The runner starts real processes, so these tests use tiny throwaway servers
(python -m http.server) rather than mocking. A mock would pass while the real
thing quietly stopped working.
"""
import json
import os
import sys
import time

import pytest

from twinpane import projects

pytestmark = pytest.mark.skipif(sys.platform == "win32",
                                reason="uses POSIX process groups")


# ---------------------------------------------------------------- detection

def test_detects_django(tmp_path):
    (tmp_path / "manage.py").write_text("#!/usr/bin/env python\n")
    found = projects.detect(str(tmp_path))
    assert found is not None
    assert found.kind == "django"
    assert found.port == 8000
    assert "runserver" in found.command


def test_detects_next_js(tmp_path):
    (tmp_path / "next.config.js").write_text("module.exports = {}\n")
    found = projects.detect(str(tmp_path))
    assert found.kind == "next"
    assert found.port == 3000


def test_detects_vite(tmp_path):
    (tmp_path / "vite.config.ts").write_text("export default {}\n")
    assert projects.detect(str(tmp_path)).kind == "vite"


def test_detects_fastapi(tmp_path):
    (tmp_path / "requirements.txt").write_text("fastapi\nuvicorn\n")
    (tmp_path / "main.py").write_text(
        "from fastapi import FastAPI\napp = FastAPI()\n")
    found = projects.detect(str(tmp_path))
    assert found.kind == "fastapi"
    assert "uvicorn" in found.command


def test_plain_python_folder_is_not_a_server(tmp_path):
    (tmp_path / "requirements.txt").write_text("requests\n")
    found = projects.detect(str(tmp_path))
    # It falls back to something harmless rather than claiming to be an app.
    assert "http.server" in found.command


def test_package_json_without_scripts_is_skipped(tmp_path):
    (tmp_path / "package.json").write_text(json.dumps({"name": "lib"}))
    assert projects.detect(str(tmp_path)) is None


def test_package_json_prefers_dev_script(tmp_path):
    (tmp_path / "package.json").write_text(json.dumps(
        {"scripts": {"build": "x", "dev": "next dev"}}))
    found = projects.detect(str(tmp_path))
    assert "npm run dev" in found.command


def test_package_json_falls_back_to_start(tmp_path):
    (tmp_path / "package.json").write_text(json.dumps(
        {"scripts": {"start": "node index.js"}}))
    assert "npm start" in projects.detect(str(tmp_path)).command


def test_self_descriptor_wins(tmp_path):
    (tmp_path / "package.json").write_text(json.dumps({"scripts": {"dev": "x"}}))
    (tmp_path / "twinpane.project").write_text(json.dumps(
        {"run": "my-server --port %(port)d", "port": 9999, "kind": "custom"}))
    found = projects.detect(str(tmp_path))
    assert found.command == "my-server --port %(port)d"
    assert found.port == 9999


def test_venv_python_is_used(tmp_path):
    (tmp_path / "requirements.txt").write_text("fastapi\n")
    (tmp_path / "main.py").write_text("from fastapi import FastAPI\n")
    venv = tmp_path / ".venv" / "bin"
    venv.mkdir(parents=True)
    (venv / "python").write_text("")
    found = projects.detect(str(tmp_path))
    assert found.command.startswith(".venv/bin/python") or \
        found.command.startswith("./.venv/bin/python")


def test_git_folder_without_marker_is_still_reported(tmp_path):
    (tmp_path / ".git").mkdir()
    (tmp_path / ".git" / "HEAD").write_text("ref: refs/heads/main\n")
    found = projects.detect(str(tmp_path))
    assert found is not None and found.kind == "git"


def test_non_project_folder_returns_none(tmp_path):
    (tmp_path / "notes.txt").write_text("hi")
    assert projects.detect(str(tmp_path)) is None


def test_broken_json_does_not_crash(tmp_path):
    (tmp_path / "package.json").write_text("{not json")
    # No crash is the whole assertion; a library folder is simply not a project.
    projects.detect(str(tmp_path))


def test_detect_is_safe_on_a_missing_folder(tmp_path):
    assert projects.detect(str(tmp_path / "nope")) is None


# -------------------------------------------------------------------- ports

def test_find_free_port_skips_the_busy_one():
    import socket
    busy = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    busy.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    busy.bind(("0.0.0.0", 0))
    busy.listen(1)
    taken = busy.getsockname()[1]
    try:
        assert not projects.port_is_free(taken)
        chosen = projects.find_free_port(taken)
        assert chosen > taken
    finally:
        busy.close()


def test_listening_ports_sees_a_real_listener(tmp_path):
    runner = projects.Runner(str(tmp_path / "servers"))
    port = projects.find_free_port(43210)
    started = runner.start(str(tmp_path), "python3 -m http.server %(port)d", port)
    try:
        assert started["ok"], started
        time.sleep(0.6)
        assert port in projects.listening_ports()
    finally:
        runner.stop(str(tmp_path))
    assert projects.port_is_free(port)


# ------------------------------------------------------------------- runner

def test_start_and_stop(tmp_path):
    runner = projects.Runner(str(tmp_path / "servers"))
    folder = tmp_path / "app"
    folder.mkdir()
    port = projects.find_free_port(43300)
    started = runner.start(str(folder), "python3 -m http.server %(port)d", port)
    assert started["ok"] is True
    assert started["pid"] > 0

    state = runner.status(str(folder))
    assert state["running"] is True
    assert state["port"] == port

    stopped = runner.stop(str(folder))
    assert stopped["killed"] is True
    assert runner.status(str(folder))["running"] is False


def test_port_conflict_moves_to_a_free_one(tmp_path):
    runner = projects.Runner(str(tmp_path / "servers"))
    first = tmp_path / "one"
    second = tmp_path / "two"
    first.mkdir()
    second.mkdir()
    port = projects.find_free_port(43400)

    assert runner.start(str(first), "python3 -m http.server %(port)d", port)["ok"]
    try:
        time.sleep(0.4)
        # Asking for the same port must not fail: it must move.
        moved = runner.start(str(second), "python3 -m http.server %(port)d", port)
        try:
            assert moved["ok"] is True
            assert moved["port"] != port
        finally:
            runner.stop(str(second))
    finally:
        runner.stop(str(first))


def test_a_command_that_dies_is_reported(tmp_path):
    runner = projects.Runner(str(tmp_path / "servers"))
    folder = tmp_path / "broken"
    folder.mkdir()
    result = runner.start(str(folder), "exit 3")
    assert result["ok"] is False
    assert "exited" in result["error"]


def test_log_captures_output(tmp_path):
    runner = projects.Runner(str(tmp_path / "servers"))
    folder = tmp_path / "logger"
    folder.mkdir()
    runner.start(str(folder), "echo hello-from-the-server")
    time.sleep(0.3)
    lines = runner.tail(str(folder))
    assert any("hello-from-the-server" in line for line in lines)


def test_starting_twice_does_not_start_twice(tmp_path):
    runner = projects.Runner(str(tmp_path / "servers"))
    folder = tmp_path / "twice"
    folder.mkdir()
    port = projects.find_free_port(43500)
    first = runner.start(str(folder), "python3 -m http.server %(port)d", port)
    try:
        second = runner.start(str(folder), "python3 -m http.server %(port)d", port)
        assert second.get("already") is True
        assert second["pid"] == first["pid"]
    finally:
        runner.stop(str(folder))


def test_stop_frees_the_port(tmp_path):
    runner = projects.Runner(str(tmp_path / "servers"))
    folder = tmp_path / "freer"
    folder.mkdir()
    port = projects.find_free_port(43600)
    runner.start(str(folder), "python3 -m http.server %(port)d", port)
    time.sleep(0.5)
    assert not projects.port_is_free(port)
    runner.stop(str(folder))
    time.sleep(0.4)
    assert projects.port_is_free(port)


def test_all_lists_known_projects(tmp_path):
    runner = projects.Runner(str(tmp_path / "servers"))
    folder = tmp_path / "listed"
    folder.mkdir()
    runner.start(str(folder), "true")
    time.sleep(0.4)
    names = [item["name"] for item in runner.all()]
    assert "listed" in names


# -------------------------------------------------------------- port registry

def test_registry_remembers_and_forgets(tmp_path):
    registry = projects.PortRegistry(str(tmp_path / "ports.json"))
    registry.assign("/a/b", 1234)
    assert registry.port_of("/a/b") == 1234
    registry.release("/a/b")
    assert registry.port_of("/a/b") == 0


def test_registry_survives_a_corrupt_file(tmp_path):
    path = tmp_path / "ports.json"
    path.write_text("{broken")
    registry = projects.PortRegistry(str(path))
    assert registry.port_of("/x") == 0
    registry.assign("/x", 55)
    assert registry.port_of("/x") == 55
