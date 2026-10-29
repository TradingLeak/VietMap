#!/usr/bin/env python3
import hashlib, json, os, sys
from datetime import datetime, timezone

path, tag, output = sys.argv[1:]
if not tag.startswith('traffic-') or not os.path.isfile(path):
    raise SystemExit('invalid tag or file')
size = os.path.getsize(path)
if size < 100 or size > 1800 * 1024 * 1024:
    raise SystemExit(f'invalid database size: {size} bytes')
hash_value = hashlib.sha256()
with open(path, 'rb') as f:
    for block in iter(lambda: f.read(1024 * 1024), b''): hash_value.update(block)
manifest = {'schema': 4, 'version': tag, 'generated_at_utc': datetime.now(timezone.utc).isoformat(), 'size': size, 'sha256': hash_value.hexdigest()}
with open(output, 'w', encoding='utf-8') as f: json.dump(manifest, f, indent=2)
