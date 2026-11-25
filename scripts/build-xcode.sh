#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple developer Team ID}"
signing=()
if [ -n "${SIGNING_IDENTITY:-}" ]; then signing=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGNING_IDENTITY"); fi
xcodebuild -project WiFiAtlas.xcodeproj -scheme WiFiAtlas -configuration "${CONFIGURATION:-Release}" -derivedDataPath .build/xcode DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" "${signing[@]}" build
mkdir -p dist
python3 - <<'CLEAN'
from pathlib import Path
import shutil
path = Path('dist/WiFi Atlas.app')
if path.exists(): shutil.rmtree(path)
CLEAN
ditto ".build/xcode/Build/Products/${CONFIGURATION:-Release}/WiFi Atlas.app" "dist/WiFi Atlas.app"
codesign --verify --deep --strict "dist/WiFi Atlas.app"
