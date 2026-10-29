#!/usr/bin/env python3
"""Fail closed unless an IPA contains one unsigned arm64 iOS app with the expected ID."""
from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import plistlib
import re
import struct
import sys
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(path: Path, expected_bundle_id: str | None = None):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate ZIP entries")
        apps = set()
        for name in names:
            parts = PurePosixPath(name).parts
            require(parts and parts[0] == "Payload" and ".." not in parts and not name.startswith("/") and "\\" not in name, "Unsafe/non-Payload ZIP path")
            if len(parts) >= 2:
                require(parts[1].endswith(".app"), "Unexpected file beside the app")
                apps.add(parts[1])
            require("_CodeSignature" not in parts and parts[-1] != "embedded.mobileprovision", "IPA must be unsigned; signing belongs in ESign")
        require(len(apps) == 1, "Expected exactly one app")
        app = next(iter(apps))
        prefix = f"Payload/{app}/"
        info_entry = archive.getinfo(prefix + "Info.plist")
        require(info_entry.file_size < 1_048_576, "Oversized Info.plist")
        info = plistlib.loads(archive.read(info_entry))
        bundle_id = info.get("CFBundleIdentifier", "")
        require(isinstance(bundle_id, str) and re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle_id), "Invalid bundle ID")
        if expected_bundle_id:
            require(bundle_id == expected_bundle_id, f"Bundle ID mismatch: {bundle_id}")
        require(info.get("CFBundlePackageType") == "APPL", "Not an application")
        require("iPhoneOS" in info.get("CFBundleSupportedPlatforms", []), "Not a device build")
        minimum = info.get("MinimumOSVersion", "")
        require(isinstance(minimum, str) and minimum.split(".")[0].isdigit() and int(minimum.split(".")[0]) >= 17, "Unexpected minimum iOS version")
        executable = info.get("CFBundleExecutable", "")
        require(isinstance(executable, str) and executable not in ("", ".", "..") and "/" not in executable and "\\" not in executable, "Invalid executable name")
        entry = archive.getinfo(prefix + executable)
        require(entry.file_size < 256 * 1024 * 1024, "Oversized executable")
        require((entry.external_attr >> 16) & 0o111, "Executable mode not preserved")
        binary = archive.read(entry)
        require(len(binary) >= 32, "Truncated Mach-O")
        magic, cpu = struct.unpack_from("<II", binary)
        require(magic == 0xFEEDFACF and cpu == 0x0100000C, "Expected a thin 64-bit arm64 Mach-O (not an iOS Simulator app)")
        commands = struct.unpack_from("<I", binary, 16)[0]
        offset = 32
        has_device_platform = False
        for _ in range(commands):
            require(offset + 8 <= len(binary), "Truncated load command")
            command, size = struct.unpack_from("<II", binary, offset)
            require(size >= 8 and offset + size <= len(binary), "Malformed load command")
            if command == 0x1D:
                require(size >= 16 and struct.unpack_from("<I", binary, offset + 12)[0] == 0, "Embedded Mach-O code signature remains")
            if command == 0x32:
                require(size >= 24, "Truncated build-version command")
                platform, minimum_binary = struct.unpack_from("<II", binary, offset + 8)
                require(platform == 2 and minimum_binary >= (17 << 16), "Binary is not an iOS device build targeting iOS >= 17")
                has_device_platform = True
            offset += size
        require(has_device_platform, "Missing iOS device platform in Mach-O")
        return {"bundle_id": bundle_id, "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"), "minimum_ios": minimum, "architecture": "arm64", "signed": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--bundle-id")
    args = parser.parse_args()
    try:
        metadata = verify(args.ipa, args.bundle_id)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f"Invalid IPA: {error}", file=sys.stderr)
        return 1
    print("IPA verified:", metadata)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
