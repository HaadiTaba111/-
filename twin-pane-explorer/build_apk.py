#!/usr/bin/env python3
"""Stage everything the Android app needs, then build the APK.

Two equally valid ways to use this:

  Local (needs JDK 17 + Android SDK on PATH):
      python build_apk.py            # -> android/app/build/outputs/apk/debug/app-debug.apk

  CI (no SDK locally - the normal case):
      .github/workflows/build-apk.yml does exactly this on ubuntu-latest,
      which ships the SDK.  This script is the "prepare" step of that job and
      can also be run on its own to check the assets are right:

      python build_apk.py --prepare-only

The APK is a *launcher*: it embeds the single-file Python build as an asset,
installs it into Termux on first launch and then hands the terminal over.  A
TUI cannot run in a plain Android activity - it needs a real terminal, and
Termux is that terminal.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
ANDROID = os.path.join(ROOT, "android")
APP = os.path.join(ANDROID, "app")
ASSETS = os.path.join(APP, "src", "main", "assets")


def version() -> str:
    sys.path.insert(0, ROOT)
    from twinpane import __version__
    return __version__.strip()


def ensure_standalone(ver: str) -> str:
    """Build dist/twinpane-<ver>-standalone.py if it is not there yet."""
    target = os.path.join(ROOT, "dist", "twinpane-%s-standalone.py" % ver)
    if os.path.exists(target):
        return target
    print("[prepare] dist/ is empty - running build_dist.py")
    subprocess.run([sys.executable, os.path.join(ROOT, "build_dist.py")],
                   check=True, cwd=ROOT)
    if not os.path.exists(target):
        raise SystemExit("build_dist.py did not produce %s" % target)
    return target


def stage_assets(ver: str) -> str:
    payload = ensure_standalone(ver)
    os.makedirs(ASSETS, exist_ok=True)
    for name in os.listdir(ASSETS):
        os.unlink(os.path.join(ASSETS, name))
    target = os.path.join(ASSETS, "twinpane-standalone.py")
    shutil.copy2(payload, target)
    size = os.path.getsize(target)
    print("[prepare] embedded %s (%.1f KB)" % (os.path.basename(target), size / 1024))
    if size < 4096:
        raise SystemExit("payload looks wrong (%d bytes)" % size)
    # a hash so the app can tell when the payload changed and re-install
    import hashlib
    digest = hashlib.sha256(open(target, "rb").read()).hexdigest()[:16]
    with open(os.path.join(ASSETS, "payload.sha256"), "w") as handle:
        handle.write(digest + "\n")
    print("[prepare] sha256 %s" % digest)
    return target


def build(ver: str) -> int:
    stage_assets(ver)
    gradlew = os.path.join(ANDROID, "gradlew")
    if not os.path.exists(gradlew):
        print("[build] no gradlew in android/ - running with the system gradle")
        command = ["gradle"]
    else:
        command = [gradlew]
    command += ["assembleDebug", "--no-daemon", "--stacktrace"]
    print("[build]", " ".join(command))
    result = subprocess.run(command, cwd=ANDROID)
    apk = os.path.join(APP, "build", "outputs", "apk", "debug", "app-debug.apk")
    if result.returncode == 0 and os.path.exists(apk):
        print("\nAPK ready: %s (%.1f MB)"
              % (apk, os.path.getsize(apk) / (1024 * 1024)))
    return result.returncode


def main(argv) -> int:
    ver = version()
    if "--prepare-only" in argv:
        stage_assets(ver)
        return 0
    return build(ver)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
