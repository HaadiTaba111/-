"""Core filesystem operations for Twin-Pane Explorer.

This module deliberately has **no curses imports**: every operation used by
the TUI (listing, copy, move, delete, rename, chmod, symlinks) lives here, so
it can be unit-tested and reused from plain scripts.

Design notes
------------
* Everything is POSIX / Android(Termux) friendly.
* Transfers are cancellable, report progress and never abort the whole batch
  because of a single unreadable file: errors are collected per path.
* Moving across filesystems (the normal case for ``$HOME`` -> ``/sdcard``
  because Android's /sdcard is a FUSE mount) automatically degrades to
  copy + delete.
* Conflict handling (overwrite / skip / rename / apply-to-all) is delegated
  to a callback supplied by the UI.
"""
from __future__ import annotations

import errno
import fnmatch
import os
import pwd
import re
import shutil
import stat as stat_mod
import time
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Tuple

CHUNK = 256 * 1024
EXDEV = getattr(errno, "EXDEV", 18)

# Conflict policies exchanged between the engine and the UI.
OVERWRITE = "overwrite"
SKIP = "skip"
RENAME = "rename"
OVERWRITE_ALL = "overwrite_all"
SKIP_ALL = "skip_all"
CANCEL = "cancel"

SORT_KEYS = ("name", "size", "mtime", "ext")


class Cancelled(Exception):
    """Raised internally when the user aborts a running transfer."""


class TransferError(Exception):
    """Invalid transfer request (destination is a file, self copy, ...)."""


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

_UNITS = ("B", "K", "M", "G", "T", "P")


def human_size(n: int) -> str:
    """1023 -> '1023B', 2048 -> '2.0K', 15_728_640 -> '15M'."""
    if n is None or n < 0:
        return "?"
    value = float(n)
    idx = 0
    while value >= 1024 and idx < len(_UNITS) - 1:
        value /= 1024.0
        idx += 1
    if idx == 0:
        return "%dB" % int(value)
    if value >= 10:
        return "%.0f%s" % (value, _UNITS[idx])
    return "%.1f%s" % (value, _UNITS[idx])


def format_time(ts: float) -> str:
    """Compact date: 'Nov 22 10:12' for this year, '2021-04-02' otherwise."""
    if not ts:
        return ""
    try:
        lt = time.localtime(ts)
        now = time.localtime()
        if lt.tm_year == now.tm_year:
            return time.strftime("%b %d %H:%M", lt)
        return time.strftime("%Y-%m-%d", lt)
    except (OverflowError, OSError, ValueError):
        return "?"


def natural_key(text: str):
    """Sort key that orders 'file2' before 'file10' (numbers compared as ints)."""
    parts = re.split(r"(\d+)", text.lower())
    return tuple((1, int(p)) if p.isdigit() else (0, p) for p in parts)


def path_expand(text: str, base: str) -> str:
    """Expand ~ / $VARS and make a path absolute relative to *base*."""
    text = (text or "").strip()
    if not text:
        text = "~"
    text = os.path.expandvars(os.path.expanduser(text))
    if not os.path.isabs(text):
        text = os.path.join(base, text)
    return os.path.normpath(text)


def validate_name(name: str) -> str:
    """Validate a new file/folder name; returns it or raises ValueError."""
    name = (name or "").strip()
    if not name:
        raise ValueError("Name cannot be empty")
    if os.sep in name or (os.altsep and os.altsep in name):
        raise ValueError("Name cannot contain '/'")
    if name in (".", ".."):
        raise ValueError("'%s' is not a valid name" % name)
    if "\x00" in name:
        raise ValueError("Name contains a NUL byte")
    return name


def mode_string(mode: int) -> str:
    """'-rw-r--r--'-style string, '' when mode is unknown."""
    if not mode:
        return ""
    try:
        return stat_mod.filemode(mode)
    except (TypeError, ValueError):
        return ""


def owner_name(uid: int) -> str:
    try:
        return pwd.getpwuid(uid).pw_name
    except (KeyError, OSError):
        return str(uid)


def group_name(gid: int) -> str:
    try:
        import grp

        return grp.getgrgid(gid).gr_name
    except (KeyError, OSError, ImportError):
        return str(gid)


def disk_free(path: str):
    """(total, used, free) bytes for the filesystem holding *path* or None."""
    probe = path
    while probe and not os.path.exists(probe):
        nxt = os.path.dirname(probe)
        if nxt == probe:
            return None
        probe = nxt
    try:
        return shutil.disk_usage(probe)
    except OSError:
        return None


def unique_path(dst: str) -> str:
    """'a.txt' -> 'a (1).txt' -> 'a (2).txt' ... first free name."""
    if not os.path.lexists(dst):
        return dst
    base, ext = os.path.splitext(dst)
    counter = 1
    while True:
        candidate = "%s (%d)%s" % (base, counter, ext)
        if not os.path.lexists(candidate):
            return candidate
        counter += 1


# ---------------------------------------------------------------------------
# Directory listing
# ---------------------------------------------------------------------------

@dataclass
class Entry:
    name: str
    path: str
    is_dir: bool
    size: int = 0
    mtime: float = 0.0
    mode: int = 0
    uid: int = 0
    gid: int = 0
    is_link: bool = False
    link_broken: bool = False
    pseudo: bool = False  # synthetic '..' row


def list_dir(path: str, show_hidden: bool = True,
             pattern: str = "") -> Tuple[List[Entry], List[str]]:
    """List *path* (without '.'/'..'), returns (entries, errors)."""
    entries: List[Entry] = []
    errors: List[str] = []
    with os.scandir(path) as it:
        for de in it:
            name = de.name
            if name in (".", ".."):
                continue
            if not show_hidden and name.startswith("."):
                continue
            if pattern and not fnmatch.fnmatchcase(name.lower(), pattern.lower()):
                continue
            try:
                st = de.stat(follow_symlinks=False)
            except OSError as exc:
                errors.append("%s: %s" % (name, exc.strerror or exc))
                continue
            is_link = stat_mod.S_ISLNK(st.st_mode)
            is_dir = stat_mod.S_ISDIR(st.st_mode)
            broken = False
            if is_link:
                try:
                    is_dir = de.is_dir(follow_symlinks=True)
                except OSError:
                    is_dir = False
                try:
                    broken = not os.path.exists(de.path)
                except OSError:
                    broken = False
            size = 0 if is_dir else st.st_size
            entries.append(Entry(
                name=name, path=de.path, is_dir=is_dir,
                size=size, mtime=st.st_mtime, mode=st.st_mode,
                uid=st.st_uid, gid=st.st_gid,
                is_link=is_link, link_broken=broken,
            ))
    return entries, errors


def sort_entries(entries: List[Entry], key: str = "name",
                 reverse: bool = False, dirs_first: bool = True) -> List[Entry]:
    """Sort in-place (returns the list) with optional reverse and dirs-first."""
    if key == "size":
        def kfn(e):
            return (0 if e.is_dir else 1, e.size, natural_key(e.name))
    elif key == "mtime":
        def kfn(e):
            return (e.mtime, natural_key(e.name))
    elif key == "ext":
        def kfn(e):
            return (os.path.splitext(e.name)[1].lower(), natural_key(e.name))
    else:
        def kfn(e):
            return natural_key(e.name)
    entries.sort(key=kfn, reverse=reverse)
    if dirs_first:
        # Stable sort keeps the order inside the dirs / files groups.
        entries.sort(key=lambda e: 0 if e.is_dir else 1)
    return entries


# ---------------------------------------------------------------------------
# Simple one-shot operations (used by the dialogs)
# ---------------------------------------------------------------------------

def make_dir(dirpath: str, name: str) -> str:
    name = validate_name(name)
    target = os.path.join(dirpath, name)
    os.mkdir(target)
    return target


def make_file(dirpath: str, name: str) -> str:
    name = validate_name(name)
    target = os.path.join(dirpath, name)
    fd = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    os.close(fd)
    return target


def make_symlink(dirpath: str, name: str, target: str) -> str:
    name = validate_name(name)
    if not (target or "").strip():
        raise ValueError("Link target cannot be empty")
    link = os.path.join(dirpath, name)
    os.symlink(target, link)
    return link


def rename_entry(path: str, new_name: str) -> str:
    new_name = validate_name(new_name)
    new_path = os.path.join(os.path.dirname(path) or ".", new_name)
    if new_path == path:
        return path
    if os.path.lexists(new_path):
        raise FileExistsError("'%s' already exists" % new_name)
    os.rename(path, new_path)
    return new_path


def chmod_entry(path: str, numeric: str) -> int:
    text = (numeric or "").strip()
    if not re.fullmatch(r"[0-7]{3,4}", text):
        raise ValueError("Use an octal mode such as 644 or 755")
    mode = int(text, 8)
    os.chmod(path, mode)
    return mode


def read_symlink(path: str) -> str:
    try:
        return os.readlink(path)
    except OSError:
        return ""


# ---------------------------------------------------------------------------
# Transfer engine
# ---------------------------------------------------------------------------

@dataclass
class TransferResult:
    kind: str = ""
    files: int = 0
    dirs: int = 0
    bytes_: int = 0
    skipped: int = 0
    errors: List[str] = field(default_factory=list)
    cancelled: bool = False
    seconds: float = 0.0

    def summary(self) -> str:
        verb = self.kind.capitalize() if self.kind else "Done"
        parts = [verb]
        if self.files:
            parts.append("%d file%s" % (self.files, "" if self.files == 1 else "s"))
        if self.dirs:
            parts.append("%d folder%s" % (self.dirs, "" if self.dirs == 1 else "s"))
        if self.bytes_:
            parts.append(human_size(self.bytes_))
        if self.skipped:
            parts.append("%d skipped" % self.skipped)
        if self.errors:
            parts.append("%d error%s" % (len(self.errors),
                                         "" if len(self.errors) == 1 else "s"))
        if self.cancelled:
            parts.append("CANCELLED")
        if self.seconds:
            parts.append("%.1fs" % self.seconds)
        return " \u00b7 ".join(parts)


class Transfer:
    """Copy / move / delete with progress, cancellation and conflict callbacks.

    Callbacks
    ---------
    conflict_cb(dst_path) -> one of OVERWRITE, SKIP, RENAME,
                             OVERWRITE_ALL, SKIP_ALL, CANCEL
    progress_cb(phase, done_bytes, total_bytes, rate_bps, current_name)
    """

    def __init__(self) -> None:
        self.cancel = False
        self.conflict_cb: Optional[Callable[[str], str]] = None
        self.progress_cb: Optional[Callable[[str, int, int, float, str], None]] = None
        self.result = TransferResult()
        self._overwrite_all = False
        self._skip_all = False
        self._total_bytes = 0
        self._done_bytes = 0
        self._last_emit = 0.0
        self._t0 = 0.0
        self._src_stats: Dict[str, Tuple[int, int, int]] = {}

    # -- infrastructure ---------------------------------------------------
    def _check(self) -> None:
        if self.cancel:
            raise Cancelled()

    def _emit(self, phase: str, name: str = "") -> None:
        now = time.monotonic()
        if now - self._last_emit < 0.1:
            return
        self._last_emit = now
        if self.progress_cb:
            elapsed = max(now - self._t0, 1e-6)
            rate = self._done_bytes / elapsed
            self.progress_cb(phase, self._done_bytes, self._total_bytes,
                             rate, name)

    def _error(self, path: str, exc: BaseException) -> None:
        reason = getattr(exc, "strerror", None) or str(exc)
        msg = "%s: %s" % (path, reason)
        if isinstance(exc, PermissionError) and (
                path.startswith("/sdcard") or "/storage/" in path
                or "storage/shared" in path):
            msg += '  [hint: run "termux-setup-storage" and allow access]'
        self.result.errors.append(msg)

    def _conflict(self, dst: str) -> str:
        if self._overwrite_all:
            return OVERWRITE
        if self._skip_all:
            return SKIP
        if not self.conflict_cb:
            return SKIP
        answer = self.conflict_cb(dst) or SKIP
        if answer == CANCEL:
            self.cancel = True
            return SKIP
        if answer == OVERWRITE_ALL:
            self._overwrite_all = True
            return OVERWRITE
        if answer == SKIP_ALL:
            self._skip_all = True
            return SKIP
        if answer not in (OVERWRITE, SKIP, RENAME):
            return SKIP
        return answer

    def _remove(self, path: str) -> None:
        if os.path.islink(path) or not os.path.isdir(path):
            os.unlink(path)
        else:
            shutil.rmtree(path)

    # -- preflight / scan -------------------------------------------------
    def _preflight(self, sources: List[str], dest_dir: str) -> List[Tuple[str, str]]:
        if not sources:
            raise TransferError("Nothing selected")
        if not os.path.isdir(dest_dir):
            raise TransferError("Destination is not a directory: %s" % dest_dir)
        plan: List[Tuple[str, str]] = []
        dest_abs = os.path.abspath(dest_dir)
        for src in sources:
            src_abs = os.path.abspath(src)
            dst = os.path.join(dest_dir, os.path.basename(src_abs))
            if src_abs == os.path.abspath(dst):
                raise TransferError("Source and destination are the same: %s" % src)
            if os.path.isdir(src_abs) and not os.path.islink(src_abs):
                prefix = src_abs.rstrip(os.sep) + os.sep
                if (dest_abs + os.sep).startswith(prefix):
                    raise TransferError(
                        "Cannot put '%s' inside itself" % os.path.basename(src_abs))
            plan.append((src_abs, dst))
        return plan

    def _scan(self, sources: List[str]) -> None:
        """Populate progress totals and per-source statistics."""
        total = 0
        self._src_stats = {}
        for src in sources:
            try:
                st = os.lstat(src)
            except OSError:
                continue
            if stat_mod.S_ISLNK(st.st_mode):
                self._src_stats[src] = (0, 0, 0)
                continue
            if stat_mod.S_ISREG(st.st_mode):
                self._src_stats[src] = (st.st_size, 1, 0)
                total += st.st_size
                continue
            if not stat_mod.S_ISDIR(st.st_mode):
                self._src_stats[src] = (0, 0, 0)
                continue
            size = files = dirs = 0
            for root, dirnames, filenames in os.walk(src):
                self._check()
                dirs += len(dirnames)
                files += len(filenames)
                for fname in filenames:
                    try:
                        fst = os.lstat(os.path.join(root, fname))
                    except OSError:
                        continue
                    if stat_mod.S_ISREG(fst.st_mode):
                        size += fst.st_size
                self._emit("scan", src)
            self._src_stats[src] = (size, files, dirs)
            total += size
        self._total_bytes = total

    # -- copy -------------------------------------------------------------
    def run_copy(self, sources: List[str], dest_dir: str) -> TransferResult:
        self.result = TransferResult(kind="copy")
        t0 = time.monotonic()
        self._t0 = t0
        self._done_bytes = 0
        try:
            plan = self._preflight(sources, dest_dir)
            self._scan([src for src, _ in plan])
            for src, dst in plan:
                self._check()
                self._copy_item(src, dst)
        except Cancelled:
            self.result.cancelled = True
        finally:
            self.result.seconds = time.monotonic() - t0
            if self.progress_cb:
                self.progress_cb("done", self._done_bytes, self._total_bytes,
                                 0.0, "")
        return self.result

    def _copy_item(self, src: str, dst: str) -> None:
        try:
            st = os.lstat(src)
        except OSError as exc:
            self._error(src, exc)
            return
        try:
            if stat_mod.S_ISLNK(st.st_mode):
                if os.path.lexists(dst):
                    action = self._conflict(dst)
                    if action == SKIP:
                        self.result.skipped += 1
                        return
                    if action == RENAME:
                        dst = unique_path(dst)
                    else:
                        self._remove(dst)
                os.symlink(os.readlink(src), dst)
                self.result.files += 1
                return

            if stat_mod.S_ISDIR(st.st_mode):
                if os.path.lexists(dst):
                    if not os.path.isdir(dst) or os.path.islink(dst):
                        action = self._conflict(dst)
                        if action == SKIP:
                            self.result.skipped += 1
                            return
                        if action == RENAME:
                            dst = unique_path(dst)
                        else:
                            self._remove(dst)
                self._copy_dir(src, dst)
                return

            if stat_mod.S_ISREG(st.st_mode):
                if os.path.lexists(dst):
                    action = self._conflict(dst)
                    if action == SKIP:
                        self.result.skipped += 1
                        return
                    if action == RENAME:
                        dst = unique_path(dst)
                    else:
                        self._remove(dst)
                self._copy_file(src, dst)
                return

            self.result.errors.append("%s: special file skipped" % src)
        except Cancelled:
            raise
        except OSError as exc:
            self._error(src, exc)

    def _copy_dir(self, src: str, dst: str) -> None:
        if not os.path.isdir(dst):
            os.makedirs(dst, exist_ok=True)
            self.result.dirs += 1
        try:
            names = sorted(os.listdir(src), key=natural_key)
        except OSError as exc:
            self._error(src, exc)
            names = []
        for name in names:
            self._check()
            self._copy_item(os.path.join(src, name), os.path.join(dst, name))
        try:
            shutil.copystat(src, dst)
        except OSError:
            pass  # read-only FUSE mounts (/sdcard) reject utime/chmod

    def _copy_file(self, src: str, dst: str) -> None:
        copied = 0
        try:
            with open(src, "rb") as fsrc:
                fdst = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                try:
                    with os.fdopen(fdst, "wb") as fdst_w:
                        while True:
                            self._check()
                            chunk = fsrc.read(CHUNK)
                            if not chunk:
                                break
                            fdst_w.write(chunk)
                            copied += len(chunk)
                            self._done_bytes += len(chunk)
                            self._emit("copy", os.path.basename(src))
                except BaseException:
                    raise
        except BaseException:
            try:
                os.unlink(dst)  # never leave truncated half-copied files
            except OSError:
                pass
            raise
        try:
            shutil.copystat(src, dst)
        except OSError:
            pass
        self.result.files += 1
        self.result.bytes_ += copied

    # -- move -------------------------------------------------------------
    def run_move(self, sources: List[str], dest_dir: str) -> TransferResult:
        self.result = TransferResult(kind="moved")
        t0 = time.monotonic()
        self._t0 = t0
        self._done_bytes = 0
        try:
            plan = self._preflight(sources, dest_dir)
            self._scan([src for src, _ in plan])
            for src, dst in plan:
                self._check()
                self._move_one(src, dst)
        except Cancelled:
            self.result.cancelled = True
        finally:
            self.result.seconds = time.monotonic() - t0
            if self.progress_cb:
                self.progress_cb("done", self._done_bytes, self._total_bytes,
                                 0.0, "")
        return self.result

    def _count_renamed(self, src: str) -> None:
        size, files, dirs = self._src_stats.get(src, (0, 0, 0))
        self.result.bytes_ += size
        self.result.files += files
        self.result.dirs += dirs + (1 if os.path.isdir(src) else 0)
        self._done_bytes += size
        self._emit("move", os.path.basename(src))

    def _move_one(self, src: str, dst: str) -> None:
        try:
            if os.path.lexists(dst):
                if (os.path.isdir(src) and not os.path.islink(src)
                        and os.path.isdir(dst) and not os.path.islink(dst)):
                    self._move_tree(src, dst)  # merge-into
                    return
                action = self._conflict(dst)
                if action == SKIP:
                    self.result.skipped += 1
                    return
                if action == RENAME:
                    dst = unique_path(dst)
                else:
                    self._remove(dst)
            try:
                os.rename(src, dst)
                self._count_renamed(src)
                return
            except OSError as exc:
                if exc.errno == errno.ENOENT:
                    raise
                # EXDEV (cross-device) or FUSE refusing rename -> copy+delete
                before = len(self.result.errors)
                self._copy_item(src, dst)
                if (not self.cancel and len(self.result.errors) == before
                        and os.path.lexists(dst)):
                    self._delete_path(src)
        except Cancelled:
            raise
        except OSError as exc:
            self._error(src, exc)

    def _move_tree(self, src: str, dst: str) -> None:
        """Move the contents of directory *src* into the existing directory *dst*."""
        try:
            names = sorted(os.listdir(src), key=natural_key)
        except OSError as exc:
            self._error(src, exc)
            return
        for name in names:
            self._check()
            child_src = os.path.join(src, name)
            child_dst = os.path.join(dst, name)
            try:
                if os.path.lexists(child_dst):
                    if (os.path.isdir(child_src) and not os.path.islink(child_src)
                            and os.path.isdir(child_dst)
                            and not os.path.islink(child_dst)):
                        self._move_tree(child_src, child_dst)
                        continue
                    action = self._conflict(child_dst)
                    if action == SKIP:
                        self.result.skipped += 1
                        continue
                    if action == RENAME:
                        child_dst = unique_path(child_dst)
                    else:
                        self._remove(child_dst)
                try:
                    is_dir = os.path.isdir(child_dst) and not os.path.islink(child_dst)
                    os.rename(child_src, child_dst)
                    if is_dir:
                        self.result.dirs += 1
                    else:
                        self.result.files += 1
                        try:
                            self._done_bytes += os.lstat(child_dst).st_size
                        except OSError:
                            pass
                    self._emit("move", name)
                except OSError:
                    before = len(self.result.errors)
                    self._copy_item(child_src, child_dst)
                    if (not self.cancel and len(self.result.errors) == before
                            and os.path.lexists(child_dst)):
                        self._delete_path(child_src)
            except Cancelled:
                raise
            except OSError as exc:
                self._error(child_src, exc)
        try:
            if not os.listdir(src):
                os.rmdir(src)
        except OSError:
            pass

    # -- delete -----------------------------------------------------------
    def run_delete(self, sources: List[str]) -> TransferResult:
        self.result = TransferResult(kind="deleted")
        t0 = time.monotonic()
        self._t0 = t0
        self._done_bytes = 0
        try:
            self._scan(sources)
            for src in sources:
                self._check()
                self._delete_path(src)
        except Cancelled:
            self.result.cancelled = True
        finally:
            self.result.seconds = time.monotonic() - t0
            if self.progress_cb:
                self.progress_cb("done", self._done_bytes, self._total_bytes,
                                 0.0, "")
        return self.result

    def _delete_path(self, path: str) -> None:
        try:
            st = os.lstat(path)
        except OSError as exc:
            self._error(path, exc)
            return
        try:
            if stat_mod.S_ISDIR(st.st_mode) and not stat_mod.S_ISLNK(st.st_mode):
                for name in sorted(os.listdir(path), key=natural_key):
                    self._check()
                    self._delete_path(os.path.join(path, name))
                os.rmdir(path)
                self.result.dirs += 1
            else:
                os.unlink(path)
                self.result.files += 1
                self.result.bytes_ += st.st_size if stat_mod.S_ISREG(st.st_mode) else 0
                self._done_bytes += st.st_size if stat_mod.S_ISREG(st.st_mode) else 0
                self._emit("delete", os.path.basename(path))
        except Cancelled:
            raise
        except OSError as exc:
            # One retry after adding write permission. Read-only folders are
            # common when files come from git checkouts or backups, and on
            # Android deleting the entry only needs a writable *parent*.
            try:
                parent = os.path.dirname(path) or "."
                try:
                    pst = os.stat(parent)
                    if not pst.st_mode & stat_mod.S_IWUSR:
                        os.chmod(parent, stat_mod.S_IMODE(pst.st_mode) | 0o700)
                except OSError:
                    pass
                if not stat_mod.S_ISLNK(st.st_mode) and not os.access(
                        path, os.W_OK):
                    try:
                        os.chmod(path, stat_mod.S_IMODE(st.st_mode) | 0o600)
                    except OSError:
                        pass
                if stat_mod.S_ISDIR(st.st_mode) and not stat_mod.S_ISLNK(st.st_mode):
                    shutil.rmtree(path)
                    self.result.dirs += 1
                else:
                    os.unlink(path)
                    self.result.files += 1
            except OSError:
                self._error(path, exc)


# ---------------------------------------------------------------------------
# Archives: zip / tar.*  (zipfile and tarfile are part of the stdlib, so this
# works on Termux with no extra packages; never shell out to `zip`/`unzip`)
# ---------------------------------------------------------------------------

import tarfile  # noqa: E402  (kept at the bottom to keep the core imports tidy)
import zipfile  # noqa: E402

ZIP_EXTS = (".zip", ".apk", ".jar", ".xpi", ".epub", ".whl", ".docx", ".xlsx")
TAR_EXTS = (".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tar.xz", ".txz",
            ".tar.zst", ".tgz".replace("tgz", "tar.Z"))


def archive_kind(path: str) -> Optional[str]:
    """Return 'zip', 'tar' or None for *path*."""
    name = os.path.basename(path).lower()
    if name.endswith(ZIP_EXTS):
        return "zip"
    if name.endswith(TAR_EXTS) or name.endswith(".tar.zst"):
        return "tar"
    return None


def looks_like_zip(path: str) -> bool:
    try:
        with open(path, "rb") as fh:
            return fh.read(2) == b"PK"
    except OSError:
        return False


def is_archive(path: str) -> bool:
    if not os.path.isfile(path):
        return False
    if archive_kind(path):
        return True
    return looks_like_zip(path)


def _safe_member(name: str):
    """Clean a member path and reject absolute / traversal paths.

    Zip-slip and tar-slip are the classic archive attacks: a member named
    '../../etc/passwd' must never be written outside the destination.
    Returns the cleaned relative path, or None when the member is unsafe.
    """
    name = name.replace("\\", "/")
    while name.startswith("./"):
        name = name[2:]
    if not name or name in (".", "/"):
        return None
    if name.startswith("/") or re.match(r"^[A-Za-z]:/", name):
        return None
    parts = [p for p in name.split("/") if p not in ("", ".")]
    if any(p == ".." for p in parts):
        return None
    return "/".join(parts)


def list_archive(path: str):
    """[(name, is_dir, size)] for display, safe to call on any file."""
    items = []
    try:
        kind = archive_kind(path) or ("zip" if looks_like_zip(path) else None)
        if kind == "zip":
            with zipfile.ZipFile(path) as zf:
                for info in zf.infolist():
                    items.append((info.filename, info.is_dir(), info.file_size))
        elif kind == "tar":
            with tarfile.open(path, "r:*") as tf:
                for member in tf.getmembers():
                    items.append((member.name, member.isdir(), member.size))
    except (OSError, zipfile.BadZipFile, tarfile.TarError):
        return []
    items.sort(key=lambda item: natural_key(item[0]))
    return items


def suggest_archive_target(src_path: str, parent: str = None) -> str:
    """Where to unpack *src_path* by default: a sibling folder with its stem.

    The name is made unique so extracting never silently mixes into an
    existing folder that happens to have the same name.
    """
    base = os.path.basename(src_path)
    for ext in (".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tgz", ".tbz2",
                ".txz", ".zip", ".tar", ".apk", ".jar"):
        if base.lower().endswith(ext):
            base = base[: -len(ext)]
            break
    else:
        base = os.path.splitext(base)[0]
    folder = parent if parent is not None else (os.path.dirname(src_path) or ".")
    return unique_path(os.path.join(folder, base or "extracted"))


def suggest_archive_name(sources: List[str], packed: bool = True) -> str:
    """`photos` for one folder, `photos-and-2-more` for several items."""
    stems = []
    for src in sources:
        stem = os.path.basename(src.rstrip(os.sep)) or "item"
        stems.append(stem)
    if len(stems) == 1:
        return stems[0] + (".zip" if packed else ".tar.gz")
    first = stems[0] + "-and-%d-more" % (len(stems) - 1)
    return first + (".zip" if packed else ".tar.gz")


class ArchiveConflict:
    """Outcome of a would-be overwrite during extraction."""

    def __init__(self, path: str):
        self.path = path


def _unique_file(path: str) -> str:
    return unique_path(path)

def _plan_archive(sources: List[str], counter: "Transfer"):
    """[(abs_path, arcname, is_dir)] for every member to store."""
    plan = []
    for src in sources:
        src_abs = os.path.abspath(src)
        if os.path.islink(src_abs) or os.path.isfile(src_abs):
            plan.append((src_abs, os.path.basename(src_abs), False))
        elif os.path.isdir(src_abs):
            root_name = os.path.basename(src_abs) or "root"
            plan.append((src_abs, root_name, True))
            for walk_root, dirnames, filenames in os.walk(src_abs):
                dirnames.sort(key=natural_key)
                rel_root = os.path.relpath(walk_root, src_abs)
                if rel_root == ".":
                    rel_root = ""
                for dname in dirnames:
                    arcname = root_name + "/"
                    if rel_root:
                        arcname += rel_root.replace(os.sep, "/") + "/"
                    plan.append((os.path.join(walk_root, dname), arcname + dname, True))
                for fname in sorted(filenames, key=natural_key):
                    arcname = root_name + "/"
                    if rel_root:
                        arcname += rel_root.replace(os.sep, "/") + "/"
                    plan.append((os.path.join(walk_root, fname), arcname + fname, False))
            counter._check()
    return plan


# -- compression --------------------------------------------------------------

def create_archive(sources: List[str], dest_file: str,
                   on_conflict: Optional[Callable[[str], str]] = None,
                   transfer: Optional["Transfer"] = None) -> TransferResult:
    """Create a .zip or .tar.* archive at *dest_file* holding *sources*.

    *sources* may be files or folders; folders are stored recursively with
    their own name as the top-level member, exactly like `zip -r`.
    """
    result = TransferResult(kind="archived")
    t0 = time.monotonic()
    counter = transfer or Transfer()
    dest_abs = os.path.abspath(dest_file)
    parent = os.path.dirname(dest_abs) or "."
    if not os.path.isdir(parent):
        raise TransferError("Destination folder does not exist: %s" % parent)
    if not sources:
        raise TransferError("Nothing selected")
    for src in sources:
        src_abs = os.path.abspath(src)
        if src_abs == dest_abs:
            raise TransferError("Cannot put an archive inside itself")
        if os.path.isdir(src_abs) and not os.path.islink(src_abs) and \
                (dest_abs + os.sep).startswith(src_abs.rstrip(os.sep) + os.sep):
            raise TransferError("Cannot create the archive inside '%s'"
                                % os.path.basename(src_abs))

    kind = archive_kind(dest_abs)
    if kind is None:
        raise TransferError("Use a .zip or .tar.gz name for the archive")

    try:
        plan = _plan_archive(sources, counter)
    except Cancelled:
        result.cancelled = True
        result.seconds = time.monotonic() - t0
        return result

    if on_conflict is not None and os.path.lexists(dest_abs):
        action = on_conflict(dest_abs)
        if action in (SKIP, SKIP_ALL):
            result.skipped += 1
            result.seconds = time.monotonic() - t0
            return result
        if action in (CANCEL,):
            result.cancelled = True
            result.seconds = time.monotonic() - t0
            return result
        if action == RENAME:
            dest_abs = _unique_file(dest_abs)

    tmp_path = dest_abs + ".part"
    try:
        if kind == "zip":
            _write_zip(plan, tmp_path, counter, result)
        else:
            _write_tar(plan, tmp_path, counter, result)
        os.replace(tmp_path, dest_abs)
    except Cancelled:
        result.cancelled = True
    except (OSError, zipfile.BadZipFile, tarfile.TarError) as exc:
        result.errors.append("%s: %s" % (os.path.basename(dest_abs), exc))
    finally:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except OSError:
            pass
        result.seconds = time.monotonic() - t0
        if counter.progress_cb:
            counter.progress_cb("done", result.bytes_, result.bytes_, 0.0, "")
    return result


def _write_zip(plan, tmp_path: str, counter: "Transfer", result: TransferResult) -> None:
    written = set()
    with zipfile.ZipFile(tmp_path, "w", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=6, allowZip64=True) as zf:
        for src, arcname, is_dir in plan:
            counter._check()
            arcname = arcname.replace(os.sep, "/")
            if is_dir:
                if not arcname.endswith("/"):
                    arcname += "/"
                if arcname not in written:
                    info = zipfile.ZipInfo(arcname)
                    info.external_attr = (0o40755 << 16) | 0x10
                    zf.writestr(info, b"")
                    written.add(arcname)
                    result.dirs += 1
                continue
            if os.path.islink(src):
                target = os.readlink(src)
                info = zipfile.ZipInfo(arcname)
                info.external_attr = (0o120777 << 16) | 0x10
                zf.writestr(info, target)
                written.add(arcname)
                result.files += 1
                continue
            try:
                info = zipfile.ZipInfo.from_file(src, arcname)
            except OSError as exc:
                counter._error(src, exc)
                continue
            info.compress_type = zipfile.ZIP_DEFLATED
            try:
                with open(src, "rb") as fh, zf.open(info, "w") as out:
                    while True:
                        counter._check()
                        chunk = fh.read(CHUNK)
                        if not chunk:
                            break
                        out.write(chunk)
                        result.bytes_ += len(chunk)
                        counter._emit("archive", arcname)
                result.files += 1
            except OSError as exc:
                counter._error(src, exc)


def _write_tar(plan, tmp_path: str, counter: "Transfer", result: TransferResult) -> None:
    mode = "w:gz"
    low = tmp_path.lower()
    if low.endswith(".tar.bz2") or low.endswith(".tbz2"):
        mode = "w:bz2"
    elif low.endswith(".tar.xz") or low.endswith(".txz"):
        mode = "w:xz"
    elif low.endswith(".tar"):
        mode = "w"
    with tarfile.open(tmp_path, mode, format=tarfile.PAX_FORMAT) as tf:
        added = set()
        for src, arcname, is_dir in plan:
            counter._check()
            try:
                info = tf.gettarinfo(src, arcname=arcname)
            except OSError as exc:
                counter._error(src, exc)
                continue
            if arcname in added:
                continue
            added.add(arcname)
            if info is None:
                continue
            if info.isreg():
                with open(src, "rb") as fh:
                    tf.addfile(info, fh)
                result.files += 1
                result.bytes_ += info.size
                counter._emit("archive", arcname)
            else:
                tf.addfile(info)
                if info.isdir():
                    result.dirs += 1
                else:
                    result.files += 1


# -- extraction ---------------------------------------------------------------

def _target_for(root: str, member: str) -> str:
    return os.path.join(root, member.replace("/", os.sep))


def extract_archive(path: str, dest_dir: str,
                    on_conflict: Optional[Callable[[str], bool]] = None,
                    transfer: Optional["Transfer"] = None,
                    overwrite: bool = False) -> TransferResult:
    """Extract a zip/tar into *dest_dir* with zip-slip protection.

    Returns a result whose ``errors`` list also receives unsafe members.
    """
    result = TransferResult(kind="extracted")
    t0 = time.monotonic()
    counter = transfer or Transfer()
    if not os.path.isdir(dest_dir):
        os.makedirs(dest_dir, exist_ok=True)
    try:
        kind = archive_kind(path) or ("zip" if looks_like_zip(path) else None)
        if kind is None:
            raise TransferError("Not a supported archive: %s" % os.path.basename(path))
        if kind == "zip":
            _extract_zip(path, dest_dir, counter, result, overwrite)
        else:
            _extract_tar(path, dest_dir, counter, result, overwrite)
    except Cancelled:
        result.cancelled = True
    except (OSError, zipfile.BadZipFile, tarfile.TarError) as exc:
        result.errors.append("%s: %s" % (os.path.basename(path), exc))
    finally:
        result.seconds = time.monotonic() - t0
        if counter.progress_cb:
            counter.progress_cb("done", result.bytes_, result.bytes_, 0.0, "")
    return result


def _extract_zip(path: str, dest_dir: str, counter: "Transfer",
                 result: TransferResult, overwrite: bool) -> None:
    with zipfile.ZipFile(path) as zf:
        members = zf.infolist()
        counter._total_bytes = sum(max(0, m.file_size) for m in members)
        for info in members:
            counter._check()
            member = _safe_member(info.filename)
            if member is None:
                result.errors.append("unsafe path skipped: %s" % info.filename)
                continue
            target = _target_for(dest_dir, member)
            if info.is_dir():
                try:
                    os.makedirs(target, exist_ok=True)
                    result.dirs += 1
                except OSError as exc:
                    counter._error(target, exc)
                continue
            os.makedirs(os.path.dirname(target) or dest_dir, exist_ok=True)
            mode = (info.external_attr >> 16) & 0o777
            if overwrite and os.path.lexists(target):
                try:
                    if os.path.isdir(target) and not os.path.islink(target):
                        shutil.rmtree(target)
                    else:
                        os.unlink(target)
                except OSError:
                    pass
            if os.path.lexists(target):
                result.skipped += 1
                continue
            try:
                with zf.open(info) as src, open(target, "wb") as out:
                    while True:
                        counter._check()
                        chunk = src.read(CHUNK)
                        if not chunk:
                            break
                        out.write(chunk)
                        counter._done_bytes += len(chunk)
                        result.bytes_ += len(chunk)
                        counter._emit("extract", member)
                if mode:
                    try:
                        os.chmod(target, mode)
                    except OSError:
                        pass
                result.files += 1
            except OSError as exc:
                counter._error(target, exc)


def _extract_tar(path: str, dest_dir: str, counter: "Transfer",
                 result: TransferResult, overwrite: bool) -> None:
    with tarfile.open(path, "r:*") as tf:
        members = tf.getmembers()
        counter._total_bytes = sum(max(0, m.size) for m in members if m.isfile())
        for member in members:
            counter._check()
            member_name = _safe_member(member.name)
            if member_name is None:
                result.errors.append("unsafe path skipped: %s" % member.name)
                continue
            target = _target_for(dest_dir, member_name)
            if member.isdir():
                try:
                    os.makedirs(target, exist_ok=True)
                    result.dirs += 1
                except OSError as exc:
                    counter._error(target, exc)
                continue
            if member.issym():
                # only allow links whose target stays inside the destination
                link_target = member.linkname.replace("\\", "/")
                resolved = os.path.normpath(os.path.join(os.path.dirname(member_name),
                                                         link_target))
                if resolved.startswith("..") or os.path.isabs(link_target):
                    result.errors.append("unsafe link skipped: %s" % member.name)
                    continue
                os.makedirs(os.path.dirname(target) or dest_dir, exist_ok=True)
                if not os.path.lexists(target):
                    try:
                        os.symlink(member.linkname, target)
                        result.files += 1
                    except OSError as exc:
                        counter._error(target, exc)
                else:
                    result.skipped += 1
                continue
            if not member.isfile():
                continue  # devices, fifos: never create them
            os.makedirs(os.path.dirname(target) or dest_dir, exist_ok=True)
            if overwrite and os.path.lexists(target):
                try:
                    if os.path.isdir(target) and not os.path.islink(target):
                        shutil.rmtree(target)
                    else:
                        os.unlink(target)
                except OSError:
                    pass
            if os.path.lexists(target):
                result.skipped += 1
                continue
            try:
                source = tf.extractfile(member)
                if source is None:
                    continue
                with source, open(target, "wb") as out:
                    while True:
                        counter._check()
                        chunk = source.read(CHUNK)
                        if not chunk:
                            break
                        out.write(chunk)
                        counter._done_bytes += len(chunk)
                        result.bytes_ += len(chunk)
                        counter._emit("extract", member_name)
                try:
                    os.chmod(target, member.mode & 0o777)
                except OSError:
                    pass
                result.files += 1
            except (OSError, tarfile.TarError) as exc:
                counter._error(target, exc)
