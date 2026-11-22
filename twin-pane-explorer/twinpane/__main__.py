"""Allow `python -m twinpane`."""
import sys

from .ui import main

if __name__ == "__main__":
    sys.exit(main())
