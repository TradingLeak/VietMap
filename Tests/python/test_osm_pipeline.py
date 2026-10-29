import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class PipelineTests(unittest.TestCase):
    def test_pbf_to_sqlite_without_mislabeling_signal(self):
        try:
            import osmium
        except ImportError:
            self.skipTest('install pyosmium to test PBF conversion')
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            xml = tmp / 'fixture.osm'
            xml.write_text('''<?xml version="1.0"?><osm version="0.6">
                <node id="1" lat="21.01" lon="105.01"><tag k="highway" v="speed_camera"/></node>
                <node id="2" lat="21.02" lon="105.02"><tag k="highway" v="traffic_signals"/></node>
                <node id="3" lat="21.03" lon="105.03"><tag k="barrier" v="toll_booth"/></node>
                <node id="4" lat="21.04" lon="105.04"><tag k="traffic_sign" v="VN:P.123a"/></node>
                <node id="5" lat="21.05" lon="105.05"><tag k="traffic_sign" v="VN:P.123b"/></node>
                <node id="6" lat="21.06" lon="105.06"><tag k="traffic_sign" v="VN:P.124a"/></node>
                <way id="100"><nd ref="1"/><nd ref="2"/><tag k="maxspeed" v="50"/></way>
                <way id="101"><nd ref="2"/><nd ref="3"/><tag k="maxspeed" v="40 mph"/></way>
                </osm>''')
            pbf = tmp / 'fixture.osm.pbf'
            writer = osmium.SimpleWriter(str(pbf))
            class Copy(osmium.SimpleHandler):
                def node(self, obj): writer.add_node(obj)
                def way(self, obj): writer.add_way(obj)
            Copy().apply_file(str(xml)); writer.close()
            out = tmp / 'json'
            subprocess.run([sys.executable, str(ROOT/'Tools/PBFConverter/convert_pbf.py'), str(pbf), str(out)], check=True)
            self.assertEqual(json.loads((out/'traffic_signals_vn.json').read_text()), [])
            dbfile = tmp/'seed.sqlite'
            subprocess.run([sys.executable, str(ROOT/'Tools/TrafficDatabaseBuilder/build_seed.py'), '--input', str(out), '--output', str(dbfile)], check=True)
            with sqlite3.connect(dbfile) as db:
                self.assertEqual(db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
                self.assertEqual(db.execute('SELECT type FROM traffic_nodes ORDER BY osm_id').fetchall(), [('SPEED_CAMERA',), ('TOLL_BOOTH',), ('NO_LEFT_TURN',), ('NO_RIGHT_TURN',)])
                self.assertEqual(db.execute('SELECT max_speed FROM road_segments').fetchall(), [(50,)])
                self.assertEqual(db.execute('SELECT COUNT(*) FROM traffic_nodes_rtree').fetchone()[0], 4)
            # Không ghi đè artifact có sẵn.
            again = subprocess.run([sys.executable, str(ROOT/'Tools/TrafficDatabaseBuilder/build_seed.py'), '--input', str(out), '--output', str(dbfile)], capture_output=True)
            self.assertNotEqual(again.returncode, 0)

if __name__ == '__main__': unittest.main()
