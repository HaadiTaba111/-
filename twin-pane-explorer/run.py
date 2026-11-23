#!/usr/bin/env python3
"""Allow running the checkout as `./run.py`.

Also the single entry point the Termux launchers use:

    run.py            the two-panel terminal UI
    run.py --bridge   the copy engine that serves the Android app
"""
import sys

if __name__ == "__main__":
    if "--bridge" in sys.argv:
        from twinpane.bridge import main as bridge_main
        sys.exit(bridge_main([a for a in sys.argv[1:] if a != "--bridge"]))
    from twinpane.ui import main
    sys.exit(main())
