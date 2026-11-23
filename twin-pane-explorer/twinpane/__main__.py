"""Allow `python -m twinpane` and `python -m twinpane --bridge`."""
import sys

if __name__ == "__main__":
    if "--bridge" in sys.argv:
        from .bridge import main as bridge_main
        sys.exit(bridge_main([a for a in sys.argv[1:] if a != "--bridge"]))
    from .ui import main
    sys.exit(main())
