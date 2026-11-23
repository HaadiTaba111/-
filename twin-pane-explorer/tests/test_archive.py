"""Tests for zip/tar creation and extraction (twinpane.fsops archives)."""
import os
import stat
import sys
import tarfile
import zipfile

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from twinpane import fsops  # noqa: E402


@pytest.fixture()
def tree(tmp_path):
    work = tmp_path / "work"
    proj = work / "project"
    (proj / "sub").mkdir(parents=True)
    (proj / "a.txt").write_text("hello")
    (proj / "sub" / "b.txt").write_text("world" * 200)
    (proj / "run.sh").write_text("#!/bin/sh\n")
    os.chmod(proj / "run.sh", 0o755)
    os.symlink("a.txt", proj / "link")
    (work / "single.txt").write_text("lonely")
    return work, proj


def test_archive_kind_detection(tree):
    work, _ = tree
    assert fsops.archive_kind("x.zip") == "zip"
    assert fsops.archive_kind("x.APK") == "zip"
    assert fsops.archive_kind("x.tar.gz") == "tar"
    assert fsops.archive_kind("x.tgz") == "tar"
    assert fsops.archive_kind("x.tar.bz2") == "tar"
    assert fsops.archive_kind("x.txt") is None


def test_create_and_extract_zip(tree):
    work, proj = tree
    archive = str(work / "out.zip")
    result = fsops.create_archive([str(proj)], archive)
    assert not result.errors, result.errors
    assert result.files == 4  # a.txt, sub/b.txt, run.sh, and the symlink
    assert os.path.getsize(archive) > 0

    dest = work / "unzipped"
    result = fsops.extract_archive(archive, str(dest))
    assert not result.errors, result.errors
    assert (dest / "project" / "a.txt").read_text() == "hello"
    assert (dest / "project" / "sub" / "b.txt").read_text() == "world" * 200
    # permissions survive
    assert stat.S_IMODE(os.stat(dest / "project" / "run.sh").st_mode) == 0o755


def test_create_and_extract_targz(tree):
    work, proj = tree
    archive = str(work / "out.tar.gz")
    result = fsops.create_archive([str(proj)], archive)
    assert not result.errors, result.errors
    dest = work / "untarred"
    result = fsops.extract_archive(archive, str(dest))
    assert not result.errors, result.errors
    assert (dest / "project" / "sub" / "b.txt").read_text() == "world" * 200
    # symlink inside the archive is recreated, not followed
    assert os.path.islink(dest / "project" / "link")
    assert os.readlink(dest / "project" / "link") == "a.txt"


def test_archive_multiple_items_and_single_file(tree):
    work, proj = tree
    archive = str(work / "many.zip")
    result = fsops.create_archive([str(proj), str(work / "single.txt")], archive)
    assert not result.errors, result.errors
    names = sorted(name for name, is_dir, _ in fsops.list_archive(archive))
    assert "project/a.txt" in names
    assert "single.txt" in names

    dest = work / "many"
    fsops.extract_archive(archive, str(dest))
    assert (dest / "single.txt").read_text() == "lonely"


def test_zip_slip_members_are_refused(tree):
    work, _ = tree
    evil = str(work / "evil.zip")
    with zipfile.ZipFile(evil, "w") as zf:
        zf.writestr("../../pwned.txt", "bad")
        zf.writestr("/absolute.txt", "bad")
        zf.writestr("good.txt", "fine")
    dest = work / "safe"
    result = fsops.extract_archive(evil, str(dest))
    assert (dest / "good.txt").read_text() == "fine"
    assert not (work / "pwned.txt").exists()
    assert any("unsafe" in err for err in result.errors)
    assert len(result.errors) == 2


def test_tar_slip_members_are_refused(tree):
    work, _ = tree
    evil = str(work / "evil.tar")
    payload = work / "payload.txt"
    payload.write_text("x")
    with tarfile.open(evil, "w") as tf:
        tf.add(str(payload), arcname="../escape.txt")
        info = tarfile.TarInfo("ok.txt")
        data = b"fine"
        info.size = len(data)
        import io
        tf.addfile(info, io.BytesIO(data))
    dest = work / "safe-tar"
    result = fsops.extract_archive(evil, str(dest))
    assert (dest / "ok.txt").read_text() == "fine"
    assert not (work / "escape.txt").exists()
    assert any("unsafe" in err for err in result.errors)


def test_tar_symlink_escape_refused(tree):
    work, _ = tree
    evil = str(work / "links.tar")
    with tarfile.open(evil, "w") as tf:
        info = tarfile.TarInfo("out")
        info.type = tarfile.SYMTYPE
        info.linkname = "../../../../etc/passwd"
        tf.addfile(info)
        info2 = tarfile.TarInfo("inner")
        info2.type = tarfile.SYMTYPE
        info2.linkname = "ok.txt"
        tf.addfile(info2)
    dest = work / "links-out"
    result = fsops.extract_archive(evil, str(dest))
    assert not (dest / "out").exists()
    assert os.path.islink(dest / "inner") if os.path.lexists(dest / "inner") else True
    assert any("unsafe link" in err for err in result.errors)


def test_extract_skips_existing_without_overwrite(tree):
    work, proj = tree
    archive = str(work / "again.zip")
    fsops.create_archive([str(proj)], archive)
    dest = work / "dest"
    (dest / "project").mkdir(parents=True)
    (dest / "project" / "a.txt").write_text("keep me")
    result = fsops.extract_archive(archive, str(dest))
    assert not result.errors, result.errors
    assert (dest / "project" / "a.txt").read_text() == "keep me"
    assert result.skipped >= 1
    # with overwrite=True the file is replaced
    result = fsops.extract_archive(archive, str(dest), overwrite=True)
    assert (dest / "project" / "a.txt").read_text() == "hello"


def test_create_archive_rejects_self_containment(tree):
    work, proj = tree
    with pytest.raises(fsops.TransferError):
        fsops.create_archive([str(proj)], str(proj / "self.zip"))
    with pytest.raises(fsops.TransferError):
        fsops.create_archive([str(proj)], str(work / "x.rar"))
    with pytest.raises(fsops.TransferError):
        fsops.create_archive([], str(work / "empty.zip"))


def test_cancellable_archive(tree, monkeypatch):
    work, proj = tree
    transfer = fsops.Transfer()
    result = fsops.create_archive([str(proj)], str(work / "cancel.zip"),
                                  transfer=transfer)
    assert not result.errors
    transfer2 = fsops.Transfer()
    transfer2.cancel = True
    result = fsops.create_archive([str(proj)], str(work / "cancel2.zip"),
                                  transfer=transfer2)
    assert result.cancelled
    assert not os.path.exists(str(work / "cancel2.zip"))


def test_suggestions(tree):
    work, proj = tree
    assert fsops.suggest_archive_name([str(proj)]) == "project.zip"
    assert fsops.suggest_archive_name([str(proj)], packed=False) == "project.tar.gz"
    assert fsops.suggest_archive_name(
        [str(proj), str(work / "single.txt")]) == "project-and-1-more.zip"
    archive = work / "photos.tar.gz"
    archive.write_text("x")
    assert fsops.suggest_archive_target(str(archive)) == str(work / "photos")
    (work / "a").mkdir()
    assert fsops.suggest_archive_target(str(work / "a.zip")) == str(work / "a (1)")
    assert fsops.suggest_archive_target(str(archive), str(work)) == str(work / "photos")


def test_list_archive_and_is_archive(tree):
    work, proj = tree
    archive = str(work / "list.zip")
    fsops.create_archive([str(proj)], archive)
    items = fsops.list_archive(archive)
    names = [name for name, _, _ in items]
    assert "project/a.txt" in names and "project/sub/" in names
    assert fsops.is_archive(archive)
    assert not fsops.is_archive(str(work / "single.txt"))
    assert fsops.list_archive(str(work / "single.txt")) == []


def test_extract_into_missing_dest_creates_it(tree):
    work, proj = tree
    archive = str(work / "deep.zip")
    fsops.create_archive([str(proj)], archive)
    dest = work / "nested" / "deeper" / "out"
    result = fsops.extract_archive(archive, str(dest))
    assert not result.errors, result.errors
    assert (dest / "project" / "a.txt").exists()


def test_archive_empty_folder(tree):
    work, _ = tree
    empty = work / "empty-dir"
    empty.mkdir()
    archive = str(work / "empty.zip")
    result = fsops.create_archive([str(empty)], archive)
    assert not result.errors
    dest = work / "empty-out"
    fsops.extract_archive(archive, str(dest))
    assert (dest / "empty-dir").is_dir()
