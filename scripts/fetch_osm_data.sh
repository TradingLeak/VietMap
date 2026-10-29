#!/usr/bin/env bash
# Tải Overpass qua CLI hiện có. Toàn quốc là tải lớn: hãy chọn endpoint phù hợp.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
exec swift run OSMDataFetcher "$@"
