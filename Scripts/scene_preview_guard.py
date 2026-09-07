#!/usr/bin/env python3
"""Keep rejected scene recipes reproducible without overwriting app resources.

This is a destination guard, NOT visual acceptance. A successful encode or this
check never promotes a preview to a release asset.
"""
import argparse
from pathlib import Path


def validate_destination(output: str) -> Path:
    destination = Path(output).expanduser().resolve()
    parts = destination.parts
    if any(parts[i:i + 2] == ("App", "Resources") for i in range(len(parts) - 1)):
        raise ValueError("Rejected scene recipes cannot write to App/Resources; use a separate preview directory.")
    return destination


def require_preview(output: str, explicitly_requested: bool) -> Path:
    if not explicitly_requested:
        raise ValueError("This recipe was rejected by visual review. Pass --rejected-preview for diagnostic reproduction only.")
    return validate_destination(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rejected-preview", action="store_true")
    parser.add_argument("output")
    args = parser.parse_args()
    try:
        require_preview(args.output, args.rejected_preview)
    except ValueError as error:
        parser.error(str(error))
