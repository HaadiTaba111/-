"""Twin-Pane Explorer - Termux two-panel file manager."""

__version__ = "1.1.1"

__all__ = ["__version__", "main"]


def main(*args, **kwargs):  # lazy: importing the package must not pull in curses
    from .ui import main as _main
    return _main(*args, **kwargs)
