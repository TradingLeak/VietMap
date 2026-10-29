#!/usr/bin/env python3
"""Extract tagged OSM features for inspection; this is not a warning engine."""
import json
import os
import sqlite3
import struct
import sys
import unicodedata
from datetime import datetime, timezone
import osmium

source, dest = sys.argv[1:]
os.makedirs(dest, exist_ok=True)
db = sqlite3.connect(os.path.join(dest, 'vietnam-traffic.sqlite'))
db.executescript('''CREATE TABLE features (osm_type TEXT NOT NULL, osm_id INTEGER NOT NULL, category TEXT NOT NULL, latitude REAL, longitude REAL, tags TEXT NOT NULL, geometry TEXT, PRIMARY KEY(osm_type, osm_id)); CREATE INDEX features_category ON features(category); CREATE INDEX features_position ON features(latitude, longitude); CREATE TABLE places (osm_type TEXT NOT NULL, osm_id INTEGER NOT NULL, name TEXT NOT NULL, normalized TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, kind TEXT NOT NULL, PRIMARY KEY(osm_type, osm_id)); CREATE INDEX places_normalized ON places(normalized); CREATE TABLE enforcement_relations (osm_id INTEGER PRIMARY KEY, tags TEXT NOT NULL, members TEXT NOT NULL); CREATE TABLE road_ways (osm_id INTEGER PRIMARY KEY, tags TEXT NOT NULL, nodes BLOB NOT NULL); CREATE TABLE turn_restrictions (osm_id INTEGER PRIMARY KEY, tags TEXT NOT NULL, members TEXT NOT NULL);''')
counts = {}
def normalized(text):
    text = text.casefold().replace('đ', 'd')
    return ''.join(c for c in unicodedata.normalize('NFD', text) if not unicodedata.combining(c))

class Extract(osmium.SimpleHandler):
    def save(self, obj, typ):
        tags = {t.k: t.v for t in obj.tags}
        categories = []
        if tags.get('highway') == 'speed_camera': categories.append('speed_camera')
        if tags.get('enforcement') in ('maxspeed', 'traffic_signals', 'average_speed'): categories.append('enforcement')
        if tags.get('traffic_sign') or tags.get('traffic_sign:forward') or tags.get('traffic_sign:backward'): categories.append('traffic_sign')
        if any(k == 'maxspeed' or k.startswith('maxspeed:') for k in tags): categories.append('maxspeed')
        name = tags.get('name:vi') or tags.get('name')
        searchable = bool(name and any(key in tags for key in ('place', 'amenity', 'shop', 'tourism', 'leisure', 'building', 'highway', 'railway', 'historic', 'office', 'craft', 'public_transport')))
        road = typ == 'way' and bool(tags.get('highway'))
        if not categories and not searchable and not road: return
        lat = lon = None
        geometry = None
        if typ == 'node':
            if not obj.location.valid(): return
            lat, lon = obj.location.lat, obj.location.lon
        else:
            coords = []
            road_nodes = bytearray()
            for node in obj.nodes:
                if not node.location.valid(): return
                coords.append([round(node.location.lon, 7), round(node.location.lat, 7)])
                if road:
                    road_nodes += struct.pack('<qii', node.ref, round(node.location.lon * 10_000_000), round(node.location.lat * 10_000_000))
            if not coords: return
            geometry = json.dumps(coords, separators=(',', ':'))
            lon, lat = coords[len(coords)//2]
        if road and len(coords) >= 2:
            db.execute('INSERT INTO road_ways VALUES (?, ?, ?)', (obj.id, json.dumps(tags, ensure_ascii=False, separators=(',', ':')), bytes(road_nodes)))
            counts['road_ways'] = counts.get('road_ways', 0) + 1
        if categories:
            # Multiple classifications are retained in category as JSON.
            db.execute('INSERT INTO features VALUES (?, ?, ?, ?, ?, ?, ?)', (typ, obj.id, json.dumps(categories), lat, lon, json.dumps(tags, ensure_ascii=False, separators=(',', ':')), geometry))
            for c in categories: counts[c] = counts.get(c, 0) + 1
        if searchable:
            kind = next((tags[k] for k in ('place', 'amenity', 'shop', 'tourism', 'leisure', 'building', 'highway', 'railway', 'historic', 'office', 'craft', 'public_transport') if k in tags), '')
            db.execute('INSERT INTO places VALUES (?, ?, ?, ?, ?, ?, ?)', (typ, obj.id, name, normalized(name), lat, lon, kind))
            counts['places'] = counts.get('places', 0) + 1
    def node(self, n): self.save(n, 'node')
    def way(self, w): self.save(w, 'way')
    def relation(self, rel):
        tags = {t.k: t.v for t in rel.tags}
        relation_type = tags.get('type', '')
        if relation_type != 'enforcement' and not relation_type.startswith('restriction'): return
        members = [{'type': m.type, 'ref': m.ref, 'role': m.role} for m in rel.members]
        table = 'enforcement_relations' if relation_type == 'enforcement' else 'turn_restrictions'
        db.execute(f'INSERT INTO {table} VALUES (?, ?, ?)', (rel.id, json.dumps(tags, ensure_ascii=False, separators=(',', ':')), json.dumps(members, ensure_ascii=False, separators=(',', ':'))))
        counts[table] = counts.get(table, 0) + 1

Extract().apply_file(source, locations=True)
db.commit()
db.execute('PRAGMA integrity_check')
if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok': raise RuntimeError('SQLite integrity check failed')
db.close()
summary = {'generated_at_utc': datetime.now(timezone.utc).isoformat(), 'source': 'https://download.geofabrik.de/asia/vietnam.html', 'license': 'OpenStreetMap contributors, ODbL', 'counts': counts, 'note': 'Raw OSM tags and enforcement relation members; not verified or interpreted, not suitable for navigation or safety warnings.'}
if not counts: raise RuntimeError('No matching OSM features extracted')
with open(os.path.join(dest, 'traffic-summary.json'), 'w', encoding='utf-8') as f: json.dump(summary, f, ensure_ascii=False, indent=2)
print(json.dumps(summary, ensure_ascii=False, indent=2))
