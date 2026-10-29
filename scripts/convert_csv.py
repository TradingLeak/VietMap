#!/usr/bin/env python3
"""Convert your legally licensed traffic CSV files to a validated VietMap v1 JSON file."""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import os
from pathlib import Path
import sys
import tempfile

from data_schema import MAX_BYTES, encode_dataset, sha256


def rows(path, required):
    if not path:
        return []
    if path.stat().st_size > MAX_BYTES:
        raise ValueError(f"CSV exceeds 32 MB: {path}")
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not set(required).issubset(reader.fieldnames or []):
            raise ValueError(f"{path}: required columns: {', '.join(required)}")
        result = []
        for row in reader:
            if len(result) >= 100_000:
                raise ValueError("CSV exceeds 100,000 records")
            if None in row or any(value is None for value in row.values()):
                raise ValueError(f"Malformed row {reader.line_num} in {path}")
            result.append({key: value.strip() for key, value in row.items()})
        return result


def optional_int(value):
    return int(value) if value else None


def boolean(value):
    if value.lower() in ("true", "1"):
        return True
    if value.lower() in ("false", "0"):
        return False
    raise ValueError(f"Boolean must be true/false or 1/0, not {value!r}")


def convert(args):
    roads = []
    for row in rows(args.roads, ["id", "name", "start_lat", "start_lon", "end_lat", "end_lon", "speed_limit", "direction"]):
        roads.append(dict(id=row["id"], name=row["name"], start=dict(latitude=float(row["start_lat"]), longitude=float(row["start_lon"])),
                          end=dict(latitude=float(row["end_lat"]), longitude=float(row["end_lon"])), speedLimit=optional_int(row["speed_limit"]), direction=row["direction"]))
    hazards = []
    for row in rows(args.hazards, ["id", "kind", "name", "lat", "lon", "heading", "speed_limit", "road_id", "is_end"]):
        hazards.append(dict(id=row["id"], kind=row["kind"], name=row["name"], coordinate=dict(latitude=float(row["lat"]), longitude=float(row["lon"])),
                            heading=float(row["heading"]) if row["heading"] else None, speedLimit=optional_int(row["speed_limit"]), roadID=row["road_id"] or None, isEnd=boolean(row["is_end"])))
    dataset = dict(schemaVersion=1, id=args.id, version=args.version, name=args.name, updatedAt=args.updated_at,
                   source=dict(name=args.source_name, url=args.source_url, license=args.license, attribution=args.attribution),
                   isDemo=args.demo, roads=roads, hazards=hazards)
    raw = encode_dataset(dataset)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=args.output.parent, prefix=".vietmap-", suffix=".tmp", delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, args.output)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()
    return sha256(raw)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roads", type=Path)
    parser.add_argument("--hazards", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    for name in ("id", "version", "name", "source-name", "source-url", "license", "attribution"):
        parser.add_argument("--" + name, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--demo", action="store_true", help="Synthetic/non-driving data")
    mode.add_argument("--real-data", action="store_true", help="I confirm this is licensed, verified real data (never use this on the example fixtures)")
    parser.add_argument("--updated-at", default=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    args = parser.parse_args()
    if not (args.roads or args.hazards):
        parser.error("At least one of --roads / --hazards is required")
    try:
        digest = convert(args)
    except (ValueError, OSError, csv.Error) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    print(f"SHA-256: {digest}")
    print(f"Saved {args.output} ({'DEMO ONLY' if args.demo else 'user-supplied real data'})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
