"""The bridge is the only place where data can be lost, so it gets real tests.

Every test drives the file protocol exactly the way the Android app does: drop
a JSON request into ``requests/``, run one poll, read ``results/``.
"""
import json
import os

import pytest

from twinpane import bridge, fsops


@pytest.fixture()
def wired(tmp_path):
    """A bridge plus two folders, standing in for Termux home and /sdcard."""
    engine = bridge.Bridge(str(tmp_path / "bridge"))
    engine.ensure()
    termux_home = tmp_path / "home"
    phone = tmp_path / "sdcard"
    termux_home.mkdir()
    phone.mkdir()
    return engine, termux_home, phone


_counter = [0]


def ask(engine, op, **payload):
    """Write a request the way the app would, run it, return the result."""
    payload["op"] = op
    # A real id has to be unique even when a previous request has already been
    # claimed (and therefore removed from requests/), which is exactly how the
    # app names them: a timestamp plus a counter.
    request_id = "r%06d-%d" % (len(os.listdir(engine.results)) + 1,
                               int(_counter[0]))
    _counter[0] += 1
    path = os.path.join(engine.requests, request_id + ".json")
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)
    assert bridge.poll_once(engine, verbose=False) == 1
    with open(os.path.join(engine.results, request_id + ".json"),
              encoding="utf-8") as handle:
        return json.load(handle)


# ---------------------------------------------------------------- protocol

def test_request_folder_is_created(wired):
    engine, _, _ = wired
    assert os.path.isdir(engine.requests)
    assert os.path.isdir(engine.work)
    assert os.path.isdir(engine.results)


def test_heartbeat_says_where_things_are(wired):
    engine, home, phone = wired
    ask(engine, "ping")
    with open(os.path.join(engine.root, bridge.HEARTBEAT_NAME),
              encoding="utf-8") as handle:
        beat = json.load(handle)
    assert beat["pid"] == os.getpid()
    assert os.path.isdir(beat["home"])
    assert "bridge" in beat and beat["bridge"] == engine.root


def test_each_request_leaves_exactly_one_result(wired):
    engine, home, _ = wired
    ask(engine, "ping")
    ask(engine, "ping")
    assert os.listdir(engine.work) == []            # nothing left claimed
    assert os.listdir(engine.requests) == []        # nothing left pending
    assert len(os.listdir(engine.results)) == 2


def test_corrupt_request_still_gets_an_answer(wired):
    engine, _, _ = wired
    with open(os.path.join(engine.requests, "broken.json"), "w") as handle:
        handle.write("{not json")
    assert bridge.poll_once(engine, verbose=False) == 1
    with open(os.path.join(engine.results, "broken.json"), encoding="utf-8") as handle:
        result = json.load(handle)
    assert result["ok"] is False


def test_unknown_operation_is_reported_not_crashed(wired):
    engine, _, _ = wired
    result = ask(engine, "teleport", path="~")
    assert result["ok"] is False
    assert "unknown op" in result["error"]


# ------------------------------------------------------------------- list

def test_list_returns_folders_and_files(wired):
    engine, home, _ = wired
    (home / "notes.txt").write_text("hello")
    (home / "projects").mkdir()
    result = ask(engine, "list", path=str(home))
    assert result["ok"] is True
    names = [row["name"] for row in result["entries"]]
    assert names[:2] == ["projects", "notes.txt"]        # folders first
    assert result["entries"][0]["dir"] is True
    assert result["entries"][1]["size"] == 5


def test_list_rejects_a_file(wired):
    engine, home, _ = wired
    (home / "x.txt").write_text("x")
    result = ask(engine, "list", path=str(home / "x.txt"))
    assert result["ok"] is False
    assert "not a folder" in result["error"]


def test_list_expands_tilde(wired, monkeypatch):
    engine, home, _ = wired
    monkeypatch.setenv("HOME", str(home))
    (home / "inside.txt").write_text("x")
    result = ask(engine, "list", path="~")
    assert result["ok"] is True
    assert any(row["name"] == "inside.txt" for row in result["entries"])


# ------------------------------------------------------------------ copy

def test_copy_one_file(wired):
    engine, home, phone = wired
    (home / "a.txt").write_text("payload")
    result = ask(engine, "copy", items=[str(home / "a.txt")], dest=str(phone))
    assert result["ok"] is True
    assert (phone / "a.txt").read_text() == "payload"
    assert (home / "a.txt").exists()                     # copy keeps the source


def test_copy_is_byte_exact(wired):
    engine, home, phone = wired
    blob = bytes(range(256)) * 400
    (home / "binary.bin").write_bytes(blob)
    ask(engine, "copy", items=[str(home / "binary.bin")], dest=str(phone))
    assert (phone / "binary.bin").read_bytes() == blob


def test_copy_a_folder_recursively(wired):
    engine, home, phone = wired
    tree = home / "project"
    (tree / "src").mkdir(parents=True)
    (tree / "src" / "main.py").write_text("print(1)")
    (tree / "README").write_text("hi")
    result = ask(engine, "copy", items=[str(tree)], dest=str(phone))
    assert result["ok"] is True
    assert (phone / "project" / "src" / "main.py").read_text() == "print(1)"
    assert (phone / "project" / "README").read_text() == "hi"


def test_copy_several_at_once(wired):
    engine, home, phone = wired
    for name in ("one", "two", "three"):
        (home / name).write_text(name)
    result = ask(engine, "copy",
                 items=[str(home / name) for name in ("one", "two", "three")],
                 dest=str(phone))
    assert result["ok"] is True
    assert sorted(p.name for p in phone.iterdir()) == ["one", "three", "two"]


def test_copy_conflict_keeps_both_by_default(wired):
    engine, home, phone = wired
    (home / "a.txt").write_text("new")
    (phone / "a.txt").write_text("old")
    ask(engine, "copy", items=[str(home / "a.txt")], dest=str(phone))
    assert (phone / "a.txt").read_text() == "old"        # untouched
    kept = [p.name for p in phone.iterdir() if p.name.startswith("a (")]
    assert len(kept) == 1, kept                          # the original survives
    assert (phone / kept[0]).read_text() == "new"


def test_copy_conflict_can_overwrite(wired):
    engine, home, phone = wired
    (home / "a.txt").write_text("new")
    (phone / "a.txt").write_text("old")
    ask(engine, "copy", items=[str(home / "a.txt")], dest=str(phone),
        conflict="overwrite")
    assert (phone / "a.txt").read_text() == "new"


def test_copy_conflict_can_skip(wired):
    engine, home, phone = wired
    (home / "a.txt").write_text("new")
    (phone / "a.txt").write_text("old")
    result = ask(engine, "copy", items=[str(home / "a.txt")], dest=str(phone),
                 conflict="skip")
    assert result["ok"] is True
    assert (phone / "a.txt").read_text() == "old"


def test_copy_refuses_folder_into_itself(wired):
    engine, home, _ = wired
    outer = home / "outer"
    (outer / "inner").mkdir(parents=True)
    result = ask(engine, "copy", items=[str(outer)], dest=str(outer / "inner"))
    assert result["ok"] is False
    assert "inside itself" in result["error"]


def test_copy_reports_a_missing_source(wired):
    engine, home, phone = wired
    result = ask(engine, "copy", items=[str(home / "ghost")], dest=str(phone))
    assert result["ok"] is False
    assert "missing" in result["error"]


def test_copy_needs_a_folder_destination(wired):
    engine, home, _ = wired
    (home / "a.txt").write_text("x")
    result = ask(engine, "copy", items=[str(home / "a.txt")],
                 dest=str(home / "a.txt"))
    assert result["ok"] is False
    assert "not a folder" in result["error"]


def test_copy_with_no_items_is_rejected(wired):
    engine, _, phone = wired
    result = ask(engine, "copy", items=[], dest=str(phone))
    assert result["ok"] is False
    assert "no items" in result["error"]


# ------------------------------------------------------------------ move

def test_move_removes_the_source(wired):
    engine, home, phone = wired
    (home / "a.txt").write_text("data")
    result = ask(engine, "move", items=[str(home / "a.txt")], dest=str(phone))
    assert result["ok"] is True
    assert (phone / "a.txt").read_text() == "data"
    assert not (home / "a.txt").exists()


def test_move_a_folder(wired):
    engine, home, phone = wired
    (home / "box" / "deep").mkdir(parents=True)
    (home / "box" / "deep" / "f.txt").write_text("x")
    result = ask(engine, "move", items=[str(home / "box")], dest=str(phone))
    assert result["ok"] is True
    assert (phone / "box" / "deep" / "f.txt").read_text() == "x"
    assert not (home / "box").exists()


def test_move_between_different_paths_is_still_complete(wired):
    """The typical phone→Termux direction: same volume, different folders."""
    engine, home, phone = wired
    (phone / "download.zip").write_bytes(b"PK\x03\x04" + b"x" * 500)
    ask(engine, "move", items=[str(phone / "download.zip")], dest=str(home))
    assert (home / "download.zip").read_bytes().startswith(b"PK\x03\x04")
    assert not (phone / "download.zip").exists()


# ---------------------------------------------------------------- delete

def test_delete_a_file(wired):
    engine, home, _ = wired
    (home / "trash.txt").write_text("x")
    result = ask(engine, "delete", items=[str(home / "trash.txt")])
    assert result["ok"] is True
    assert not (home / "trash.txt").exists()


def test_delete_a_folder_recursively(wired):
    engine, home, _ = wired
    (home / "old" / "deep").mkdir(parents=True)
    (home / "old" / "deep" / "f").write_text("x")
    ask(engine, "delete", items=[str(home / "old")])
    assert not (home / "old").exists()


# ----------------------------------------------------------------- mkdir

def test_mkdir_creates_the_folder(wired):
    engine, home, _ = wired
    result = ask(engine, "mkdir", path=str(home), name="reports")
    assert result["ok"] is True
    assert (home / "reports").is_dir()
    assert result["path"] == str(home / "reports")


def test_mkdir_rejects_an_empty_name(wired):
    engine, home, _ = wired
    result = ask(engine, "mkdir", path=str(home), name="   ")
    assert result["ok"] is False


# ------------------------------------------------------------------ guard

def test_is_inside_knows_the_difference():
    assert bridge.is_inside("/a/b", "/a/b") is True
    assert bridge.is_inside("/a/b", "/a/b/c") is True
    assert bridge.is_inside("/a/b", "/a/c") is False
    # the classic prefix trap: /a/bc must not count as inside /a/b
    assert bridge.is_inside("/a/b", "/a/bc") is False


def test_prune_keeps_the_newest(wired):
    engine, _, _ = wired
    for index in range(10):
        bridge.Bridge.finish(engine, "x%02d" % index, {"ok": True})
    removed = engine.prune(keep=4)
    assert removed == 6
    assert len(os.listdir(engine.results)) == 4


def test_conflict_constants_exist():
    assert fsops.OVERWRITE and fsops.SKIP and fsops.RENAME
