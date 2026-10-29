from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from data_schema import encode_dataset, load_dataset, validate_dataset, sha256
from convert_csv import convert
from generate_project import generate_project, generate_scheme
from select_simulator import select
from verify_ipa import verify


class SchemaTests(unittest.TestCase):
    def setUp(self):
        self.value = load_dataset(ROOT / "VietMap/Resources/demo-traffic.json")

    def test_demo_valid_and_roundtrip(self):
        self.assertTrue(self.value["isDemo"])
        self.assertEqual(validate_dataset(json.loads(encode_dataset(self.value))), self.value)

    def test_explicit_demo_flag_required(self):
        del self.value["isDemo"]
        with self.assertRaises(ValueError):
            validate_dataset(self.value)

    def test_duplicate_ids_rejected(self):
        self.value["roads"].append(copy.deepcopy(self.value["roads"][0]))
        with self.assertRaises(ValueError):
            validate_dataset(self.value)

    def test_outside_coordinate_range_rejected(self):
        self.value["hazards"][0]["coordinate"]["latitude"] = 91
        with self.assertRaises(ValueError):
            validate_dataset(self.value)

    def test_nan_coordinate_rejected(self):
        self.value["roads"][0]["start"]["longitude"] = float("nan")
        with self.assertRaises(ValueError):
            validate_dataset(self.value)

    def test_invalid_speed_and_heading_rejected(self):
        self.value["hazards"][0]["heading"] = 360
        with self.assertRaises(ValueError):
            validate_dataset(self.value)
        self.value["hazards"][0]["heading"] = 0
        self.value["roads"][0]["speedLimit"] = True
        with self.assertRaises(ValueError):
            validate_dataset(self.value)

    def test_unknown_road_rejected(self):
        self.value["hazards"][0]["roadID"] = "missing"
        with self.assertRaises(ValueError):
            validate_dataset(self.value)

    def test_missing_license_and_credential_url_rejected(self):
        self.value["source"]["license"] = ""
        with self.assertRaises(ValueError):
            validate_dataset(self.value)
        self.value["source"]["license"] = "CC0"
        self.value["source"]["url"] = "https://user:password@example.com"
        with self.assertRaises(ValueError):
            validate_dataset(self.value)

    def test_sha256_known_vector(self):
        self.assertEqual(sha256(b"abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")


class ConverterTests(unittest.TestCase):
    def test_conversion_and_failed_validation_preserve_old_file(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            roads = folder / "roads.csv"
            roads.write_text("id,name,start_lat,start_lon,end_lat,end_lon,speed_limit,direction\nr1,Example,20,106,20.001,106,60,both\n")
            output = folder / "traffic.json"
            args = argparse.Namespace(roads=roads, hazards=None, output=output, id="test", version="1", name="Test", updated_at="2026-10-29T00:00:00Z", source_name="Tests", source_url="https://example.com", license="CC0", attribution="Synthetic", demo=True)
            digest = convert(args)
            original = output.read_bytes()
            self.assertEqual(sha256(original), digest)
            self.assertTrue(load_dataset(output)["isDemo"])
            roads.write_text(roads.read_text().replace(",60,both", ",999,both"))
            with self.assertRaises(ValueError):
                convert(args)
            self.assertEqual(output.read_bytes(), original)
            self.assertEqual(list(folder.glob(".vietmap-*")), [])

    def test_malformed_csv_rejected(self):
        from convert_csv import rows
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "bad.csv"
            path.write_text("id,name\na,b,extra\n")
            with self.assertRaises(ValueError):
                rows(path, ["id", "name"])


class ProjectTests(unittest.TestCase):
    def test_checked_in_project_is_current(self):
        self.assertEqual(generate_project(), (ROOT / "VietMap.xcodeproj/project.pbxproj").read_text())
        self.assertEqual(generate_scheme(), (ROOT / "VietMap.xcodeproj/xcshareddata/xcschemes/VietMap.xcscheme").read_text())

    def test_simulator_selection_uses_newest_available_iphone(self):
        data = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [{"name": "iPhone 16", "udid": "old", "isAvailable": True}],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [{"name": "iPad Pro", "udid": "ipad", "isAvailable": True}, {"name": "iPhone 17", "udid": "new", "isAvailable": True}],
        }}
        self.assertEqual(select(data), "new")
        with self.assertRaises(ValueError):
            select({"devices": {}})


class IPATests(unittest.TestCase):
    def make_ipa(self, folder, *, cpu=0x0100000C, platform=2, signed=False, extra=None, executable=True):
        path = Path(folder) / "test.ipa"
        info = dict(CFBundleIdentifier="vn.tradingleak.vietmap", CFBundlePackageType="APPL", CFBundleSupportedPlatforms=["iPhoneOS"], MinimumOSVersion="17.0", CFBundleExecutable="VietMap", CFBundleShortVersionString="1.0.0", CFBundleVersion="1")
        binary = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0) + struct.pack("<6I", 0x32, 24, platform, 17 << 16, 18 << 16, 0)
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Payload/VietMap.app/Info.plist", plistlib.dumps(info))
            entry = zipfile.ZipInfo("Payload/VietMap.app/VietMap")
            entry.external_attr = (0o100755 if executable else 0o100644) << 16
            archive.writestr(entry, binary)
            if signed:
                archive.writestr("Payload/VietMap.app/_CodeSignature/CodeResources", "signature")
            if extra:
                archive.writestr(extra, "unexpected")
        return path

    def test_valid_unsigned_device_ipa(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertFalse(verify(self.make_ipa(temp), "vn.tradingleak.vietmap")["signed"])

    def test_simulator_cpu_or_platform_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                verify(self.make_ipa(temp, cpu=0x01000007))
            with self.assertRaises(ValueError):
                verify(self.make_ipa(temp, platform=7))

    def test_signed_ipa_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                verify(self.make_ipa(temp, signed=True))

    def test_traversal_missing_execute_mode_or_wrong_id_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                verify(self.make_ipa(temp, extra="Payload/../outside"))
            with self.assertRaises(ValueError):
                verify(self.make_ipa(temp, executable=False))
            with self.assertRaises(ValueError):
                verify(self.make_ipa(temp), "wrong.bundle.id")


if __name__ == "__main__":
    unittest.main()
