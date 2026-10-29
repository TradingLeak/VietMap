#!/usr/bin/env python3
"""Stream OSM PBF sang sáu tệp JSON tương thích build_seed.py (cần pyosmium)."""
import argparse
import json
from pathlib import Path
import osmium

FILES = ('camera_data_vn.json', 'traffic_signals_vn.json', 'speed_limits_vn.json',
         'residential_zones_vn.json', 'toll_booths_vn.json', 'railway_crossings_vn.json')

class Writer:
    def __init__(self, directory):
        self.files = {name: (directory / name).open('x', encoding='utf-8') for name in FILES}
        self.first = {name: True for name in FILES}
        for f in self.files.values(): f.write('[\n')
    def add(self, name, record):
        f = self.files[name]
        if not self.first[name]: f.write(',\n')
        self.first[name] = False
        json.dump(record, f, ensure_ascii=False, separators=(',', ':'))
    def close(self):
        for f in self.files.values(): f.write('\n]\n'); f.close()

class Handler(osmium.SimpleHandler):
    def __init__(self, writer):
        super().__init__(); self.out = writer; self.missing_way_geometry = 0
    def node(self, node):
        if not node.location.valid(): return
        tags = dict(node.tags)
        targets = []
        if tags.get('highway') == 'speed_camera': targets.append('camera_data_vn.json')
        if tags.get('barrier') == 'toll_booth': targets.append('toll_booths_vn.json')
        if tags.get('railway') == 'level_crossing': targets.append('railway_crossings_vn.json')
        # highway=traffic_signals là đèn giao thông, KHÔNG phải camera vượt đèn đỏ.
        for name in targets:
            self.out.add(name, {'id': node.id, 'lat': node.location.lat, 'lon': node.location.lon, 'tags': tags})
    def way(self, way):
        tags = dict(way.tags)
        if 'maxspeed' not in tags: return
        try:
            geometry = [{'lat': n.location.lat, 'lon': n.location.lon} for n in way.nodes if n.location.valid()]
            if len(geometry) != len(way.nodes) or len(geometry) < 2:
                self.missing_way_geometry += 1; return
            self.out.add('speed_limits_vn.json', {'id': way.id, 'tags': tags, 'geometry': geometry})
        except (RuntimeError, ValueError):
            self.missing_way_geometry += 1

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pbf', type=Path); parser.add_argument('output', type=Path)
    args = parser.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    writer = Writer(args.output)
    try:
        handler = Handler(writer); handler.apply_file(str(args.pbf), locations=True)
    finally: writer.close()
    if handler.missing_way_geometry:
        raise SystemExit(f'{handler.missing_way_geometry} ways thiếu node geometry; không phát hành dữ liệu này')
    print('Đã xuất JSON; chưa phân loại tín hiệu thành camera và không suy diễn khu dân cư.')
if __name__ == '__main__': main()
