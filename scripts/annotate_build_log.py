#!/usr/bin/env python3
"""Publish concise Xcode/XCTest failures as GitHub annotations (no log blob access needed)."""
from __future__ import annotations

from pathlib import Path
import re
import sys

PATTERN = re.compile(r"^(.*?\.swift):(\d+):(?:(\d+):)?\s*error:\s*(.*)$")


def escape(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def annotations(text: str, root: Path):
    result = []
    seen = set()
    for line in text.splitlines():
        match = PATTERN.match(line)
        if match:
            path, number, column, message = match.groups()
            try:
                relative = Path(path).resolve().relative_to(root.resolve()).as_posix()
            except ValueError:
                relative = None
            if relative:
                attributes = f" file={escape(relative)},line={number}" + (f",col={column}" if column else "")
            else:
                attributes = ""
            value = f"::error{attributes}::{escape(message[:3500])}"
        elif (re.search(r"(?:^|\s)error:", line, re.IGNORECASE) or ("Test Case" in line and "failed" in line) or line.startswith("ld:")):
            value = f"::error::{escape(line[:3500])}"
        else:
            continue
        if value not in seen:
            seen.add(value)
            result.append(value)
        if len(result) == 30:
            break
    return result


if __name__ == "__main__":
    for name in sys.argv[1:]:
        path = Path(name)
        if path.is_file():
            for annotation in annotations(path.read_text(errors="replace"), Path.cwd()):
                print(annotation)
