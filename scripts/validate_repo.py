#!/usr/bin/env python3
"""Linux-safe structural checks. This does NOT replace compiling with Xcode."""
from pathlib import Path
import json
import plistlib
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET

from data_schema import load_dataset

ROOT = Path(__file__).resolve().parents[1]


def check(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    subprocess.run([sys.executable, str(ROOT / "scripts/generate_project.py"), "--check"], check=True)
    info = plistlib.loads((ROOT / "VietMap/Info.plist").read_bytes())
    check(info["CFBundleIdentifier"] == "$(PRODUCT_BUNDLE_IDENTIFIER)", "Bundle ID must be configurable")
    check(info["UIBackgroundModes"] == ["location", "audio"], "Only navigation location/audio background modes are expected")
    check(info.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads") is not True, "Do not disable HTTPS enforcement")
    check(info["NSLocationWhenInUseUsageDescription"] and info["NSLocationAlwaysAndWhenInUseUsageDescription"], "Missing location purpose strings")
    check(not info["UIFileSharingEnabled"], "Private trip storage must not be exposed by default")
    privacy = plistlib.loads((ROOT / "VietMap/Resources/PrivacyInfo.xcprivacy").read_bytes())
    check(privacy["NSPrivacyTracking"] is False, "No tracking is expected")
    check(privacy["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"] == ["CA92.1"], "Review UserDefaults required-reason declaration")
    demo = load_dataset(ROOT / "VietMap/Resources/demo-traffic.json")
    check(demo["isDemo"] is True, "Bundled traffic data must NEVER be marked real")
    check(all(item["id"].startswith("demo-") for item in demo["hazards"] + demo["roads"]), "Demo IDs must be unmistakable")
    for path in (ROOT / "VietMap/Resources/Assets.xcassets").rglob("Contents.json"):
        content = json.loads(path.read_text())
        for image in content.get("images", []):
            if "filename" in image:
                check((path.parent / image["filename"]).is_file(), f"Missing asset: {image['filename']}")
    icon = (ROOT / "VietMap/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png").read_bytes()
    check(icon[:8] == b"\x89PNG\r\n\x1a\n", "Icon is not a PNG")
    width, height, depth, color = struct.unpack_from(">IIBB", icon, 16)
    check((width, height, depth, color) == (1024, 1024, 8, 2), "App icon must be an opaque 1024x1024 RGB PNG")
    scheme = ET.parse(ROOT / "VietMap.xcodeproj/xcshareddata/xcschemes/VietMap.xcscheme")
    check(len(scheme.findall(".//TestableReference")) == 2, "Scheme must include app and UI tests")
    for doc in ("README.md", "docs/ESIGN.md", "docs/DATA_FORMAT.md", "docs/COMMERCIAL_READINESS.md", "docs/TESTING.md", "docs/PROVENANCE.md"):
        check((ROOT / doc).is_file(), f"Missing documentation: {doc}")
    files = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=ROOT, text=True).splitlines()
    forbidden = {".ipa", ".p12", ".pfx", ".mobileprovision", ".cer", ".key", ".pem"}
    check(not any(Path(path).suffix.lower() in forbidden for path in files), "Do not store IPA files or signing credentials in Git")
    print(f"Structure, demo schema, assets, privacy declarations and scheme valid ({len(files)} files).")
    print("Native Swift compilation and iOS execution still require the macOS CI job.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"Validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
