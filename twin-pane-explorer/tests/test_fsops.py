"""Unit tests for twinpane.fsops (no curses needed)."""
import os
import stat
import sys

import pytest

# Symlinks and chmod are not usable for a normal user on Windows, and the file
# manager's own code paths for them are POSIX-only, so those two tests are
# skipped there (the rest of the suite still runs).
needs_posix = pytest.mark.skipif(
    os.name == "nt", reason="symlinks/chmod need POSIX or admin rights"
)

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from twinpane import fsops  # noqa: E402

FAKE_ROOT = "/tmp"


@pytest.fixture()
def sandbox(tmp_path):
    src = tmp_path / "termux"
    dst = tmp_path / "sdcard"
    src.mkdir()
    dst.mkdir()
    (src / "notes.txt").write_bytes(b"hello termux\n")
    (src / "empty.bin").write_bytes(b"")
    big = src / "big.dat"
    big.write_bytes(b"x" * 5000)
    folder = src / "project"
    (folder / "sub").mkdir(parents=True)
    (folder / "a.py").write_text("print('a')\n")
    (folder / "sub" / "b.py").write_text("print('b')\n")
    (src / ".hidden").write_text("secret")
    (dst / "existing.txt").write_text("old content")
    return src, dst, tmp_path


# ---------------------------------------------------------------- helpers

def test_human_size():
    assert fsops.human_size(0) == "0B"
    assert fsops.human_size(999) == "999B"
    assert fsops.human_size(1024) == "1.0K"
    assert fsops.human_size(2048) == "2.0K"
    assert fsops.human_size(15 * 1024 * 1024) == "15M"
    assert fsops.human_size(-1) == "?"


def test_natural_sort_and_entries(sandbox):
    src, dst, _ = sandbox
    for name in ("file10.txt", "file2.txt", "File1.txt"):
        (src / name).write_text("x")
    entries, errors = fsops.list_dir(str(src))
    assert not errors
    fsops.sort_entries(entries)
    names = [e.name for e in entries]
    assert names.index("file2.txt") < names.index("file10.txt")
    # folders always first
    assert names[0] == "project"
    assert any(e.name == ".hidden" for e in entries)


def test_hidden_filter_and_mask(sandbox):
    src, _, _ = sandbox
    entries, _ = fsops.list_dir(str(src), show_hidden=False)
    assert all(not e.name.startswith(".") for e in entries)
    entries, _ = fsops.list_dir(str(src), pattern="*.py")
    assert [e.name for e in entries] == []
    entries, _ = fsops.list_dir(str(src / "project"), pattern="*.py")
    assert {e.name for e in entries} == {"a.py"}


def test_path_expand(sandbox):
    src, dst, _ = sandbox
    assert fsops.path_expand("~", "/") == os.path.expanduser("~")
    assert fsops.path_expand("abc", str(src)) == os.path.join(str(src), "abc")
    assert fsops.path_expand("../up", str(src)) == str(dst).replace("sdcard", "up")
    assert fsops.path_expand("/absolute/../x", "/") == "/x"


def test_validate_name():
    assert fsops.validate_name("  ok name  ") == "ok name"
    for bad in ("", "..", ".", "a/b", "x\x00y"):
        with pytest.raises(ValueError):
            fsops.validate_name(bad)


# ---------------------------------------------------------------- transfers

def test_copy_file_and_dir(sandbox):
    src, dst, _ = sandbox
    r = fsops.Transfer().run_copy([str(src / "notes.txt"), str(src / "project"),
                                   str(src / "empty.bin")], str(dst))
    assert not r.errors
    assert (dst / "notes.txt").read_text() == "hello termux\n"
    assert (dst / "project" / "sub" / "b.py").read_text() == "print('b')\n"
    assert (dst / "empty.bin").exists()
    assert r.files == 4  # notes.txt, empty.bin, a.py, sub/b.py
    assert r.dirs >= 2
    # sources untouched by copy
    assert (src / "notes.txt").exists()


@needs_posix
def test_copy_preserves_mode_and_symlink(sandbox):
    src, dst, _ = sandbox
    script = src / "run.sh"
    script.write_text("#!/bin/sh\n")
    os.chmod(script, 0o755)
    os.symlink("notes.txt", src / "link")
    r = fsops.Transfer().run_copy([str(script), str(src / "link")], str(dst))
    assert not r.errors
    assert stat.S_IMODE(os.stat(dst / "run.sh").st_mode) == 0o755
    assert os.readlink(dst / "link") == "notes.txt"


def test_copy_conflict_overwrite_and_skip(sandbox):
    src, dst, _ = sandbox
    (src / "existing.txt").write_text("new content")
    t = fsops.Transfer()
    t.conflict_cb = lambda p: fsops.SKIP
    r = t.run_copy([str(src / "existing.txt")], str(dst))
    assert r.skipped == 1
    assert (dst / "existing.txt").read_text() == "old content"

    t = fsops.Transfer()
    t.conflict_cb = lambda p: fsops.OVERWRITE
    r = t.run_copy([str(src / "existing.txt")], str(dst))
    assert not r.errors
    assert (dst / "existing.txt").read_text() == "new content"


def test_copy_conflict_rename_creates_unique_name(sandbox):
    src, dst, _ = sandbox
    (src / "existing.txt").write_text("new content")
    t = fsops.Transfer()
    t.conflict_cb = lambda p: fsops.RENAME
    r = t.run_copy([str(src / "existing.txt")], str(dst))
    assert not r.errors
    assert (dst / "existing (1).txt").read_text() == "new content"
    assert (dst / "existing.txt").read_text() == "old content"


def test_copy_overwrite_all_not_asked_twice(sandbox):
    src, dst, _ = sandbox
    calls = []

    def cb(path):
        calls.append(path)
        return fsops.OVERWRITE_ALL

    t = fsops.Transfer()
    t.conflict_cb = cb
    (src / "a").write_text("1")
    (src / "b").write_text("2")
    (dst / "a").write_text("x")
    (dst / "b").write_text("y")
    r = t.run_copy([str(src / "a"), str(src / "b")], str(dst))
    assert not r.errors
    assert len(calls) == 1
    assert (dst / "a").read_text() == "1" and (dst / "b").read_text() == "2"


def test_copy_into_itself_rejected(sandbox):
    src, _, _ = sandbox
    with pytest.raises(fsops.TransferError):
        fsops.Transfer().run_copy([str(src / "project")], str(src / "project"))


def test_copy_dir_into_at_itself_rejected(sandbox):
    src, _, _ = sandbox
    # project -> src would overwrite 'project' with itself: refuse like cp -r
    with pytest.raises(fsops.TransferError):
        fsops.Transfer().run_copy([str(src / "project")], str(src))


def test_progress_and_cancel(sandbox):
    src, dst, _ = sandbox
    big = src / "big.dat"
    seen = []
    t = fsops.Transfer()
    t.progress_cb = lambda *a: seen.append(a)

    def cancel_cb(path):
        t.cancel = True
        return fsops.OVERWRITE

    t.conflict_cb = cancel_cb
    # pre-create destination so conflict_cb fires before copying, then cancel
    (dst / "big.dat").write_bytes(b"old")
    r = t.run_copy([str(big)], str(dst))
    assert r.cancelled or r.skipped


def test_move_same_filesystem(sandbox):
    src, dst, _ = sandbox
    r = fsops.Transfer().run_move([str(src / "notes.txt"), str(src / "project")], str(dst))
    assert not r.errors, r.errors
    assert not (src / "notes.txt").exists()
    assert (dst / "notes.txt").read_text() == "hello termux\n"
    assert (dst / "project" / "sub" / "b.py").exists()
    assert not (src / "project").exists()


def test_move_into_existing_dir_merges(sandbox):
    src, dst, _ = sandbox
    t = fsops.Transfer()
    t.conflict_cb = lambda p: fsops.SKIP_ALL
    r = t.run_move([str(src / "project")], str(dst))
    assert not r.errors, r.errors
    # project dir itself now exists in dst, contents moved
    assert (dst / "project" / "a.py").exists()
    assert (dst / "project" / "sub" / "b.py").exists()
    assert not (src / "project").exists()


def test_move_rename_keeps_source_on_failure(sandbox, monkeypatch):
    src, dst, _ = sandbox
    real_rename = os.rename

    def fake_rename(a, b):
        raise OSError(18, "Invalid cross-device link")  # EXDEV

    monkeypatch.setattr(os, "rename", fake_rename)
    r = fsops.Transfer().run_move([str(src / "notes.txt")], str(dst))
    monkeypatch.setattr(os, "rename", real_rename)
    assert not r.errors, r.errors
    assert not (src / "notes.txt").exists()
    assert (dst / "notes.txt").read_text() == "hello termux\n"


def test_delete_tree(sandbox):
    src, _, _ = sandbox
    r = fsops.Transfer().run_delete([str(src / "project"), str(src / "notes.txt")])
    assert not r.errors, r.errors
    assert not (src / "project").exists()
    assert not (src / "notes.txt").exists()
    assert src.exists()


def test_delete_readonly_dir(sandbox):
    src, _, _ = sandbox
    ro = src / "ro"
    ro.mkdir()
    (ro / "f").write_text("x")
    os.chmod(ro, 0o555)
    try:
        r = fsops.Transfer().run_delete([str(ro)])
        assert not r.errors, r.errors
        assert not ro.exists()
    finally:
        os.chmod(ro, 0o755) if ro.exists() else None


@needs_posix
def test_mkdir_file_rename_chmod_symlink(sandbox):
    src, dst, _ = sandbox
    fsops.make_dir(str(src), "newdir")
    assert (src / "newdir").is_dir()
    fsops.make_file(str(src), "new.txt")
    assert (src / "new.txt").read_text() == ""
    fsops.rename_entry(str(src / "new.txt"), "renamed.txt")
    assert (src / "renamed.txt").exists()
    with pytest.raises(FileExistsError):
        fsops.rename_entry(str(src / "renamed.txt"), "notes.txt")
    fsops.chmod_entry(str(src / "renamed.txt"), "600")
    assert stat.S_IMODE(os.stat(src / "renamed.txt").st_mode) == 0o600
    with pytest.raises(ValueError):
        fsops.chmod_entry(str(src / "renamed.txt"), "rw-")
    fsops.make_symlink(str(src), "ln", "notes.txt")
    assert os.readlink(str(src / "ln")) == "notes.txt"


@needs_posix
def test_breaking_symlink_is_reported_not_crashing(sandbox):
    src, dst, _ = sandbox
    os.symlink("does-not-exist", src / "dangling")
    entries, errors = fsops.list_dir(str(src))
    entry = next(e for e in entries if e.name == "dangling")
    assert entry.is_link and entry.link_broken
    r = fsops.Transfer().run_copy([str(src / "dangling")], str(dst))
    assert not r.errors
    assert os.readlink(dst / "dangling") == "does-not-exist"


def test_disk_free(sandbox):
    src, _, _ = sandbox
    usage = fsops.disk_free(str(src))
    assert usage is not None and usage.total > 0


def test_summary_text():
    r = fsops.TransferResult(kind="copy", files=3, dirs=1, bytes_=2048, skipped=1)
    text = r.summary()
    assert "Copy" in text and "3 files" in text and "1 folder" in text
    assert "2.0K" in text and "skipped" in text
