#!/usr/bin/env python3
"""Extract tagged OSM features for inspection; this is not a warning engine."""
import json
import os
import sqlite3
import sys
import unicodedata
from datetime import datetime, timezone
import osmium

source, dest = sys.argv[1:]
os.makedirs(dest, exist_ok=True)
db = sqlite3.connect(os.path.join(dest, 'vietnam-traffic.sqlite'))
db.executescript('''CREATE TABLE features (osm_type TEXT NOT NULL, osm_id INTEGER NOT NULL, category TEXT NOT NULL, latitude REAL, longitude REAL, tags TEXT NOT NULL, geometry TEXT, PRIMARY KEY(osm_type, osm_id)); CREATE INDEX features_category ON features(category); CREATE TABLE places (osm_type TEXT NOT NULL, osm_id INTEGER NOT NULL, name TEXT NOT NULL, normalized TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, kind TEXT NOT NULL, PRIMARY KEY(osm_type, osm_id)); CREATE INDEX places_normalized ON places(normalized);''')
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
        if not categories and not searchable: return
        lat = lon = None
        geometry = None
        if typ == 'node':
            if not obj.location.valid(): return
            lat, lon = obj.location.lat, obj.location.lon
        else:
            coords = []
            for node in obj.nodes:
                if not node.location.valid(): return
                coords.append([round(node.location.lon, 7), round(node.location.lat, 7)])
            if not coords: return
            geometry = json.dumps(coords, separators=(',', ':'))
            lon, lat = coords[len(coords)//2]
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

Extract().apply_file(source, locations=True)
db.commit()
db.execute('PRAGMA integrity_check')
if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok': raise RuntimeError('SQLite integrity check failed')
db.close()
summary = {'generated_at_utc': datetime.now(timezone.utc).isoformat(), 'source': 'https://download.geofabrik.de/asia/vietnam.html', 'license': 'OpenStreetMap contributors, ODbL', 'counts': counts, 'note': 'Raw OSM tags; not verified, no relation extraction, not suitable for navigation or safety warnings.'}
if not counts: raise RuntimeError('No matching OSM features extracted')
with open(os.path.join(dest, 'traffic-summary.json'), 'w', encoding='utf-8') as f: json.dump(summary, f, ensure_ascii=False, indent=2)
print(json.dumps(summary, ensure_ascii=False, indent=2))
