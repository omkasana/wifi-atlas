#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool keychain profile}"
if [ "${WITH_WIDGETS:-0}" = "1" ]; then
    ./scripts/build-xcode.sh
else
    ./scripts/build.sh
fi
ditto -c -k --keepParent "dist/WiFi Atlas.app" dist/WiFiAtlas-notarization.zip
xcrun notarytool submit dist/WiFiAtlas-notarization.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "dist/WiFi Atlas.app"
xcrun stapler validate "dist/WiFi Atlas.app"
spctl --assess --type execute --verbose "dist/WiFi Atlas.app"
python3 - <<'CLEAN'
from pathlib import Path
import shutil
path = Path('dist/dmg-content')
if path.exists(): shutil.rmtree(path)
path.mkdir(parents=True)
CLEAN
ditto "dist/WiFi Atlas.app" "dist/dmg-content/WiFi Atlas.app"
if [ ! -L dist/dmg-content/Applications ]; then ln -s /Applications dist/dmg-content/Applications; fi
hdiutil create -volname "WiFi Atlas" -srcfolder dist/dmg-content -ov -format UDZO dist/WiFiAtlas.dmg
codesign --sign "$SIGNING_IDENTITY" --timestamp dist/WiFiAtlas.dmg
xcrun notarytool submit dist/WiFiAtlas.dmg --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple dist/WiFiAtlas.dmg
