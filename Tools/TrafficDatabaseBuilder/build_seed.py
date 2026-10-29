#!/usr/bin/env python3
"""Tạo seed từ JSON do OSMDataFetcher xuất; không tải mạng hoặc suy diễn dữ liệu thiếu."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / 'VietNav/Resources/InitialData/schema_v1.sql'
POINT_FILES = [
    ('camera_data_vn.json', 'SPEED_CAMERA'),
    ('traffic_signals_vn.json', 'RED_LIGHT_CAMERA'),
    ('toll_booths_vn.json', 'TOLL_BOOTH'),
    ('railway_crossings_vn.json', 'RAILWAY_CROSSING'),
]
ALL_FILES = [name for name, _ in POINT_FILES] + ['speed_limits_vn.json', 'residential_zones_vn.json']


def position(lat, lon):
    return (isinstance(lat, (int, float)) and isinstance(lon, (int, float))
            and math.isfinite(lat) and math.isfinite(lon) and -90 <= lat <= 90 and -180 <= lon <= 180)


def numeric_speed(raw):
    # Chỉ maxspeed số nguyên không đơn vị hoặc km/h; không đoán mph, biến thiên hay điều kiện.
    if not isinstance(raw, str) or not re.fullmatch(r'\s*[0-9]{1,3}\s*(?:km/h)?\s*', raw, re.IGNORECASE):
        return None
    value = int(re.search(r'[0-9]+', raw).group())
    return value if 0 < value <= 200 else None


def build(source, destination):
    # Kiểm tra đủ file trước khi tạo DB; nội dung có thể chỉ là một vùng: người vận hành phải xác nhận.
    datasets = {name: json.loads((source / name).read_text(encoding='utf-8')) for name in ALL_FILES}
    if any(not isinstance(v, list) for v in datasets.values()):
        raise ValueError('Mỗi file đầu vào phải là một JSON array')
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise FileExistsError('Không ghi đè seed đã tồn tại: ' + str(destination))
    fd, temp = tempfile.mkstemp(prefix='.traffic-', suffix='.sqlite', dir=destination.parent)
    os.close(fd)
    counts = {'nodes': 0, 'duplicate_nodes': 0, 'segments': 0, 'skipped_segments': 0,
              'residential_unclassified': len(datasets['residential_zones_vn.json'])}
    try:
        with sqlite3.connect(temp) as db:
            db.executescript(SCHEMA.read_text(encoding='utf-8'))
            db.execute('CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)')
            db.execute('INSERT INTO grdb_migrations VALUES (?)', ('v1_traffic',))
            now = int(time.time())
            for filename, kind in POINT_FILES:
                for item in datasets[filename]:
                    lat, lon, osm_id = item['lat'], item['lon'], item['id']
                    if not position(lat, lon) or not isinstance(osm_id, int):
                        raise ValueError(f'Tọa độ/id không hợp lệ trong {filename}')
                    tags = item.get('tags') or {}
                    cur = db.execute('''INSERT OR IGNORE INTO traffic_nodes
                        (osm_id,type,latitude,longitude,speed_limit,road_name,road_ref,source,created_at,updated_at)
                        VALUES (?,?,?,?,?,?,?,?,?,?)''',
                        (osm_id, kind, lat, lon, numeric_speed(tags.get('maxspeed')), tags.get('name'), tags.get('ref'), 'OSM', now, now))
                    counts['nodes' if cur.rowcount else 'duplicate_nodes'] += 1
            for way in datasets['speed_limits_vn.json']:
                tags = way.get('tags') or {}
                speed = numeric_speed(tags.get('maxspeed'))
                geo = way.get('geometry') or []
                if speed is None or len(geo) < 2:
                    counts['skipped_segments'] += 1
                    continue
                if not all(position(p.get('lat'), p.get('lon')) for p in geo):
                    raise ValueError(f"Geometry không hợp lệ cho way {way.get('id')}")
                lats, lons = [p['lat'] for p in geo], [p['lon'] for p in geo]
                geometry = json.dumps({'type': 'LineString', 'coordinates': [[p['lon'], p['lat']] for p in geo]}, separators=(',', ':'))
                db.execute('''INSERT INTO road_segments
                    (osm_way_id,road_name,road_type,max_speed,geometry,min_lat,max_lat,min_lon,max_lon)
                    VALUES (?,?,?,?,?,?,?,?,?)''',
                    (way['id'], tags.get('name'), tags.get('highway'), speed, geometry, min(lats), max(lats), min(lons), max(lons)))
                counts['segments'] += 1
            # Không suy diễn dấu vào/ra khu dân cư từ tag không rõ hướng.
            db.execute('PRAGMA user_version = 1')
        # Đồng bộ seed đầy đủ, không copy WAL; rename độc lập với mọi DB đang sử dụng.
        os.replace(temp, destination)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return counts


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True, help='Thư mục chứa đủ sáu file JSON đã export')
    parser.add_argument('--output', type=Path, required=True, help='Đường dẫn file .sqlite mới')
    args = parser.parse_args()
    print(json.dumps(build(args.input, args.output), ensure_ascii=False, indent=2))
