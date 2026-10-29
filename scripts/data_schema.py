"""Validation contract shared by repository checks and the licensed-data CSV importer."""
from __future__ import annotations

from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import re
from urllib.parse import urlsplit

MAX_BYTES = 32 * 1024 * 1024
KINDS = {"camera", "speedLimit", "residential", "noOvertaking", "toll", "trafficLight", "danger", "restArea", "tunnel"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def text(value, maximum=200, required=True):
    return isinstance(value, str) and len(value) <= maximum and (bool(value.strip()) or not required)


def coordinate(value):
    require(isinstance(value, dict), "Coordinate must be an object")
    lat, lon = value.get("latitude"), value.get("longitude")
    require(type(lat) in (int, float) and type(lon) in (int, float), "Coordinates must be numbers")
    require(math.isfinite(lat) and math.isfinite(lon) and -85 <= lat <= 85 and -180 <= lon <= 180, "Coordinate outside supported range")
    return lat, lon


def distance(a, b):
    lat1, lon1 = coordinate(a)
    lat2, lon2 = coordinate(b)
    dlat, dlon = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    h = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2) ** 2
    return 2 * 6_371_000 * math.asin(math.sqrt(max(0, min(1, h))))


def valid_limit(value):
    return value is None or (type(value) is int and 5 <= value <= 160)


def validate_dataset(data):
    require(isinstance(data, dict), "Dataset must be an object")
    require(type(data.get("schemaVersion")) is int and data["schemaVersion"] == 1, "Unsupported schemaVersion")
    for field, maximum in (("id", 128), ("name", 200), ("version", 64)):
        require(text(data.get(field), maximum), f"Invalid {field}")
    require(type(data.get("isDemo")) is bool, "isDemo must explicitly be true or false")
    updated = data.get("updatedAt", "")
    require(isinstance(updated, str) and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:Z|[+-]\d\d:\d\d)", updated), "updatedAt must be ISO-8601 with a timezone and without fractional seconds")
    datetime.fromisoformat(updated.replace("Z", "+00:00"))
    source = data.get("source")
    require(isinstance(source, dict), "Missing source metadata")
    for field in ("name", "url", "license", "attribution"):
        require(text(source.get(field), 2000), f"Invalid source.{field}")
    url = urlsplit(source["url"])
    require(url.scheme == "https" and url.hostname and url.username is None and url.password is None, "Source URL must be HTTPS without credentials")
    roads, hazards = data.get("roads"), data.get("hazards")
    require(isinstance(roads, list) and isinstance(hazards, list), "roads and hazards must be arrays")
    require(len(roads) <= 100_000 and len(hazards) <= 100_000 and (roads or hazards), "Empty or oversized dataset")
    road_ids = set()
    for road in roads:
        require(isinstance(road, dict), "Road must be an object")
        rid = road.get("id")
        require(text(rid, 128) and rid not in road_ids, f"Invalid or duplicate road ID: {rid}")
        road_ids.add(rid)
        require(text(road.get("name"), required=False), f"Invalid road name: {rid}")
        coordinate(road.get("start")); coordinate(road.get("end"))
        require(abs(road["start"]["longitude"] - road["end"]["longitude"]) <= 1, "Split long/antimeridian roads into smaller segments")
        require(1 <= distance(road["start"], road["end"]) <= 5000, f"Road must be 1–5000m long: {rid}")
        require(road.get("direction") in {"both", "forward", "backward"}, f"Invalid direction: {rid}")
        require(valid_limit(road.get("speedLimit")), f"Invalid limit: {rid}")
    hazard_ids = set()
    for hazard in hazards:
        require(isinstance(hazard, dict), "Hazard must be an object")
        hid = hazard.get("id")
        require(text(hid, 128) and hid not in hazard_ids, f"Invalid or duplicate hazard ID: {hid}")
        hazard_ids.add(hid)
        require(hazard.get("kind") in KINDS and text(hazard.get("name"), required=False), f"Invalid hazard type/name: {hid}")
        coordinate(hazard.get("coordinate"))
        heading = hazard.get("heading")
        require(heading is None or (type(heading) in (int, float) and math.isfinite(heading) and 0 <= heading < 360), f"Invalid travel heading: {hid}")
        require(valid_limit(hazard.get("speedLimit")), f"Invalid hazard limit: {hid}")
        require(hazard.get("roadID") is None or hazard["roadID"] in road_ids, f"Unknown roadID: {hid}")
        require(type(hazard.get("isEnd")) is bool, f"isEnd must be boolean: {hid}")
    return data


def load_dataset(path: Path):
    require(path.stat().st_size <= MAX_BYTES, "Dataset exceeds 32 MB")
    raw = path.read_bytes()
    require(len(raw) <= MAX_BYTES, "Dataset exceeds 32 MB")
    return validate_dataset(json.loads(raw, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"Invalid JSON number: {value}"))))


def encode_dataset(data):
    validate_dataset(data)
    raw = (json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode()
    require(len(raw) <= MAX_BYTES, "Output exceeds 32 MB; split into regions")
    return raw


def sha256(data):
    return hashlib.sha256(data).hexdigest()
