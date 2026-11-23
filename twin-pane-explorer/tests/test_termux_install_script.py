"""Guards for the one-command Termux installer.

The script itself runs on Android, so these tests check its *static* contract:
that it exists, stays executable, keeps the flags documented in the help text,
and installs into $PREFIX without needing root.
"""
import os
import re
import stat

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "scripts", "termux-install.sh")


@pytest.fixture(scope="module")
def source():
    with open(SCRIPT, encoding="utf-8") as handle:
        return handle.read()


def test_script_exists_and_is_executable():
    assert os.path.isfile(SCRIPT)
    mode = os.stat(SCRIPT).st_mode
    assert mode & stat.S_IXUSR, "installer must be executable"


def test_has_bash_shebang(source):
    # Termux's bash lives in $PREFIX; a /bin/bash shebang would not resolve.
    first = source.splitlines()[0]
    assert first.startswith("#!"), "missing shebang"
    assert "bash" in first


@pytest.mark.parametrize("flag", [
    "--install", "--update", "--run", "--uninstall", "--doctor", "--help",
])
def test_documented_flags_are_handled(source, flag):
    assert flag in source, f"{flag} is not handled"
    # every documented flag must appear in the dispatch block
    assert re.search(r"^\s*%s[\|\)]" % re.escape(flag), source, re.M), flag


def test_installs_into_prefix_without_root(source):
    assert "$PREFIX/bin/twinpane" in source
    assert "sudo" not in source.split("--help")[0]
    # the launcher must call the interpreter, not assume the +x bit survives
    assert "exec python" in source


def test_clone_is_shallow(source):
    # whole history would be tens of MB on mobile data
    assert "--depth 1" in source


def test_never_deletes_user_data(source):
    # only the app's own lib dir may be cleared
    assert 'rm -rf "$SRC_DIR"' in source
    for dangerous in ('rm -rf "$HOME"', 'rm -rf ~', "rm -rf /"):
        assert dangerous not in source


def test_setup_storage_is_offered(source):
    assert "termux-setup-storage" in source


def test_selftest_exercises_zip(source):
    assert "extract_archive" in source
