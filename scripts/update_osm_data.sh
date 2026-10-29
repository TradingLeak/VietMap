#!/usr/bin/env bash
# Tạo seed mới offline; không ghi đè DB người dùng và không upload ngầm.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
usage() { echo "Usage: $0 OUTPUT_DIR [--input vietnam.osm.pbf] [--upload s3://bucket/path]" >&2; exit 2; }
[[ $# -ge 1 ]] || usage
OUT=$1; shift
INPUT=""; UPLOAD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) [[ $# -ge 2 ]] || usage; INPUT=$2; shift 2 ;;
    --upload) [[ $# -ge 2 ]] || usage; UPLOAD=$2; shift 2 ;;
    *) usage ;;
  esac
done
for cmd in python3 osmium; do command -v "$cmd" >/dev/null || { echo "Missing: $cmd" >&2; exit 1; }; done
python3 -c 'import osmium' || { echo 'Install pyosmium in an isolated environment: python3 -m pip install osmium' >&2; exit 1; }
if [[ -n "$UPLOAD" ]]; then
  [[ "$UPLOAD" == s3://* ]] || { echo 'Upload must be an s3:// URI' >&2; exit 1; }
  command -v aws >/dev/null || { echo 'Missing aws CLI' >&2; exit 1; }
fi
mkdir -p "$OUT"
[[ ! -e "$OUT/vietnam_traffic.sqlite" && ! -e "$OUT/manifest.json" ]] || { echo 'Output already exists; choose an empty directory' >&2; exit 1; }
WORK=$(mktemp -d "$OUT/.build.XXXXXXXX")
trap 'rm -rf "$WORK"' EXIT
if [[ -z "$INPUT" ]]; then
  command -v curl >/dev/null || { echo 'Missing curl' >&2; exit 1; }
  echo 'Downloading Geofabrik Vietnam extract; review terms and license.'
  curl --fail --location --retry 3 --output "$WORK/vietnam.osm.pbf" https://download.geofabrik.de/asia/vietnam-latest.osm.pbf
  INPUT="$WORK/vietnam.osm.pbf"
fi
[[ -f "$INPUT" ]] || { echo 'PBF not found' >&2; exit 1; }
# Không dùng --omit-referenced: cần node tọa độ cho ways.
osmium tags-filter "$INPUT" n/highway=speed_camera n/highway=traffic_signals n/barrier=toll_booth n/railway=level_crossing 'n/traffic_sign=VN:P.123a,VN:P.123b' w/maxspeed -o "$WORK/traffic.osm.pbf"
python3 "$ROOT/Tools/PBFConverter/convert_pbf.py" "$WORK/traffic.osm.pbf" "$WORK/json"
python3 "$ROOT/Tools/TrafficDatabaseBuilder/build_seed.py" --input "$WORK/json" --output "$WORK/vietnam_traffic.sqlite"
python3 - "$WORK/vietnam_traffic.sqlite" "$WORK/manifest.json" <<'PY'
import hashlib, json, sqlite3, sys
from datetime import datetime, timezone
from pathlib import Path
p=Path(sys.argv[1]); h=hashlib.sha256()
with p.open('rb') as f:
    for chunk in iter(lambda:f.read(1024*1024), b''): h.update(chunk)
with sqlite3.connect(f'file:{p}?mode=ro', uri=True) as db:
    if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok': raise SystemExit('SQLite integrity check failed')
    counts = {t: db.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0] for t in ('traffic_nodes','road_segments')}
    if db.execute('SELECT COUNT(*) FROM traffic_nodes').fetchone()[0] == 0: raise SystemExit('No traffic nodes; refusing to publish')
manifest={'version': datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'), 'schema':1, 'file':p.name, 'sha256':h.hexdigest(), 'size':p.stat().st_size, 'counts':counts, 'source':'OpenStreetMap via Geofabrik'}
Path(sys.argv[2]).write_text(json.dumps(manifest,indent=2)+'\n')
PY
mv "$WORK/vietnam_traffic.sqlite" "$OUT/vietnam_traffic.sqlite"
mv "$WORK/manifest.json" "$OUT/manifest.json"
if [[ -n "$UPLOAD" ]]; then
  echo 'Uploading explicitly requested artifacts; verify access controls and ODbL compliance.'
  aws s3 cp "$OUT/vietnam_traffic.sqlite" "${UPLOAD%/}/vietnam_traffic.sqlite"
  aws s3 cp "$OUT/manifest.json" "${UPLOAD%/}/manifest.json"
fi
printf 'Artifact: %s/vietnam_traffic.sqlite\n' "$OUT"
