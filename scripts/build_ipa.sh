#!/usr/bin/env bash
# Build on macOS + Xcode. No certificates, profiles, ESign accounts or secrets enter CI.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v xcodebuild >/dev/null || { echo 'Cần macOS với Xcode để tạo IPA.' >&2; exit 1; }
BUNDLE_ID="${BUNDLE_ID:-vn.tradingleak.vietmap}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_VERSION="${APP_VERSION:-1.0.0}"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || { echo 'Bundle ID không hợp lệ.' >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]{1,9}$ ]] || { echo 'Build number không hợp lệ.' >&2; exit 1; }
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Version phải có dạng 1.0.0.' >&2; exit 1; }
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/artifacts}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/vietmap-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
RESULT="$OUTPUT_DIR/Archive-${BUILD_NUMBER}-$(date +%s).xcresult"
python3 scripts/generate_project.py --check
xcodebuild -version
xcodebuild archive \
  -project VietMap.xcodeproj -scheme VietMap -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath "$WORK/VietMap.xcarchive" -derivedDataPath "$WORK/DerivedData" \
  -resultBundlePath "$RESULT" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 'CODE_SIGN_IDENTITY=' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" MARKETING_VERSION="$APP_VERSION" \
  2>&1 | tee "$OUTPUT_DIR/archive.log"
APP="$WORK/VietMap.xcarchive/Products/Applications/VietMap.app"
[[ -d "$APP" ]] || { echo 'Archive không có VietMap.app' >&2; exit 1; }
# Some linkers may emit ad-hoc signatures. Remove them, including embedded frameworks.
while IFS= read -r -d '' executable; do
  if /usr/bin/codesign -d "$executable" >/dev/null 2>&1; then
    /usr/bin/codesign --remove-signature "$executable"
  fi
done < <(find "$APP" -type f -perm -111 -print0)
if /usr/bin/codesign -d "$APP" >/dev/null 2>&1; then /usr/bin/codesign --remove-signature "$APP"; fi
find "$APP" -type d -name _CodeSignature -prune -exec rm -rf {} +
find "$APP" -name embedded.mobileprovision -type f -delete
mkdir -p "$WORK/Staging/Payload"
/usr/bin/ditto "$APP" "$WORK/Staging/Payload/VietMap.app"
IPA="$OUTPUT_DIR/VietMap-unsigned.ipa"
# ditto preserves executable bits and the required Payload/<App>.app layout.
/usr/bin/ditto -c -k --norsrc --keepParent "$WORK/Staging/Payload" "$IPA"
python3 scripts/verify_ipa.py "$IPA" --bundle-id "$BUNDLE_ID"
if [[ -d "$WORK/VietMap.xcarchive/dSYMs" ]]; then
  /usr/bin/ditto -c -k --norsrc --keepParent "$WORK/VietMap.xcarchive/dSYMs" "$OUTPUT_DIR/VietMap-dSYMs.zip"
fi
cp docs/ESIGN.md "$OUTPUT_DIR/ESIGN.md"
python3 - "$OUTPUT_DIR" "$BUNDLE_ID" "$APP_VERSION" "$BUILD_NUMBER" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
out = Path(sys.argv[1])
ipa = out / 'VietMap-unsigned.ipa'
digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
(out / 'SHA256SUMS.txt').write_text(f'{digest}  {ipa.name}\n')
info = dict(bundleID=sys.argv[2], version=sys.argv[3], build=sys.argv[4], unsigned=True, architecture='arm64',
            commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
            xcode=subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
            builtAt=datetime.now(timezone.utc).isoformat(), sha256=digest)
(out / 'build-info.json').write_text(json.dumps(info, indent=2) + '\n')
print(f'IPA: {ipa}\nSHA-256: {digest}\nChưa ký; cần ký hợp lệ bằng ESign trước khi cài.')
PY
