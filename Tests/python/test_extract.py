import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / 'scripts' / 'extract_osm.py'
class ExtractionTest(unittest.TestCase):
    def test_nodes_and_ways_preserve_tags_and_geometry(self):
        osm = '''<osm version="0.6" generator="test"><node id="1" lat="21" lon="105"><tag k="highway" v="speed_camera"/><tag k="maxspeed" v="50"/></node><node id="2" lat="21.1" lon="105.1"><tag k="name" v="Đền Trần"/><tag k="tourism" v="attraction"/></node><way id="3"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/><tag k="maxspeed:forward" v="40"/></way></osm>'''
        with tempfile.TemporaryDirectory() as d:
            source = Path(d) / 'test.osm'; source.write_text(osm)
            out = Path(d) / 'out'
            subprocess.run([sys.executable, str(SCRIPT), str(source), str(out)], check=True, capture_output=True)
            summary = json.loads((out / 'traffic-summary.json').read_text())
            self.assertEqual(summary['counts']['maxspeed'], 2)
            self.assertEqual(summary['counts']['speed_camera'], 1)
            db = sqlite3.connect(out / 'vietnam-traffic.sqlite')
            rows = db.execute('SELECT osm_type, tags, geometry FROM features ORDER BY osm_type').fetchall()
            self.assertEqual(len(rows), 2)
            self.assertEqual(json.loads(rows[0][1])['highway'], 'speed_camera')
            self.assertEqual(len(json.loads(rows[1][2])), 2)
            self.assertEqual(db.execute('SELECT name, normalized FROM places').fetchone(), ('Đền Trần', 'den tran'))
            self.assertEqual(summary['counts']['places'], 1)
            self.assertEqual(db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
            db.close()
    def test_empty_data_is_not_published(self):
        with tempfile.TemporaryDirectory() as d:
            source = Path(d) / 'test.osm'; source.write_text('<osm version="0.6" generator="test"><node id="1" lat="21" lon="105"/></osm>')
            result = subprocess.run([sys.executable, str(SCRIPT), str(source), str(Path(d) / 'out')], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
if __name__ == '__main__': unittest.main()
