#!/usr/bin/env python3
"""Print the UDID of an available iPhone on the newest installed iOS runtime."""
import json
import re
import sys


def select(data):
    choices = []
    for runtime, devices in data.get("devices", {}).items():
        match = re.search(r"\.iOS-(\d+)(?:-(\d+))?(?:-(\d+))?$", runtime)
        if not match or int(match[1]) < 17:
            continue
        version = tuple(int(value or 0) for value in match.groups())
        for device in devices:
            if device.get("isAvailable", False) and device.get("name", "").startswith("iPhone"):
                choices.append((version, device.get("state") == "Booted", device["name"], device["udid"]))
    if not choices:
        raise ValueError("No available iPhone simulator with iOS >= 17. Install an iOS runtime in Xcode.")
    return sorted(choices, reverse=True)[0][-1]


if __name__ == "__main__":
    try:
        print(select(json.load(sys.stdin)))
    except (ValueError, KeyError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
