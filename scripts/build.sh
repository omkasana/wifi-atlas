#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/atlas-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/atlas-swift-cache"
configuration="${CONFIGURATION:-release}"
swift build --build-system native -c "$configuration" --arch arm64 --cache-path "${TMPDIR:-/tmp}/atlas-spm-cache" --config-path "${TMPDIR:-/tmp}/atlas-spm-config" --security-path "${TMPDIR:-/tmp}/atlas-spm-security" --disable-sandbox
app=".build/package-bundle/WiFi Atlas.app"
python3 - <<'CLEAN'
from pathlib import Path
import shutil
path = Path('.build/package-bundle')
if path.exists(): shutil.rmtree(path)
CLEAN
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/arm64-apple-macosx/$configuration/WiFiAtlas" "$app/Contents/MacOS/WiFiAtlas"
mkdir -p .build/Atlas.iconset
swift scripts/icon.swift .build/Atlas.iconset "$app/Contents/Resources/Atlas.icns"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [ -n "${SIGNING_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
mkdir -p dist
python3 - <<'CLEAN'
from pathlib import Path
import shutil
path = Path('dist/WiFi Atlas.app')
if path.exists(): shutil.rmtree(path)
CLEAN
ditto "$app" "dist/WiFi Atlas.app"
printf 'Built %s\n' "dist/WiFi Atlas.app"
