# Building and publishing a release

Local source builds and CI artifacts are ad hoc signed. For public downloads, use a Developer ID Application certificate and notarization. See [Apple’s distribution guidance](https://developer.apple.com/macos/distribution/).

## Local app

```sh
./scripts/build.sh
open "dist/WiFi Atlas.app"
```

The package-based bundle includes menu bar widgets and floating panels. It deliberately omits the WidgetKit extension. Full Xcode is not needed for this build if compatible Apple Command Line Tools are installed.

## Build system widgets with Xcode

Full Xcode and a signing team are required to build/install the embedded WidgetKit extension. Widget registration, signing, refresh, and deep links must be validated using full Xcode.

```sh
open WiFiAtlas.xcodeproj
# Set your team for WiFiAtlas and AtlasWidgets, then run the WiFiAtlas scheme.
```

Or:

```sh
DEVELOPMENT_TEAM=YOURTEAMID ./scripts/build-xcode.sh
```

Both targets use the macOS App Group `$(DEVELOPMENT_TEAM).com.wifiatlas.shared`, matching their `AtlasAppGroup` Info.plist values and entitlements. Choose your own bundle IDs/group suffix before distributing publicly; use the same group in both targets. With Developer ID signing, macOS supports this team-prefixed group format without registering an iOS-style group.

The checked-in Xcode project uses a local Swift Package product for AtlasCore. After adding/removing app source files, regenerate it with:

```sh
python3 scripts/generate-xcode-project.py
```

Shared WiFiAtlas and AtlasWidgets schemes are included. Use the extension scheme with Xcode’s widget debugging tools; validate widgets outside the debugger as well. Package-only builds deliberately omit the extension and replace earlier generated bundles cleanly.


## Prepare signing and notarization

1. Install/select full Xcode and sign in to your Apple Developer account.
2. In Xcode → Settings → Accounts → Manage Certificates, create a **Developer ID Application** certificate for distribution outside the Mac App Store.
3. Set your bundle identifiers, App Group, version, and build number before publishing a fork or a release. Keep the main/extension version numbers consistent. The project generator owns Xcode build settings; update it rather than editing generated settings alone.
4. Find the certificate name and store a notarization profile interactively:

```sh
security find-identity -v -p codesigning
xcrun notarytool store-credentials "wifiatlas-notary"
```

Enter your Team ID, Apple Account, and app-specific password when prompted. Do not put secrets in command files, issue reports, commits, or screenshots.

## Signed distribution

Set a Developer ID identity and an existing notarization keychain profile. Package-only release:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="your-profile" ./scripts/release.sh
```

Full app with system widgets:

```sh
WITH_WIDGETS=1 DEVELOPMENT_TEAM=YOURTEAMID \
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="your-profile" ./scripts/release.sh
```

The scripts build/sign the relevant bundle, notarize/staple the app, assess Gatekeeper, and produce a signed/notarized/stapled DMG. Credentials are never stored in the repository. Local ad hoc builds are not notarized public releases.

The completed download is `dist/WiFiAtlas.dmg`. The script includes an Applications shortcut. It does not create a GitHub Release or upload a downloadable build automatically.

## Release checklist

- Run the tests and build from a clean checkout.
- Verify network-name permission allowed/denied, Wi-Fi off, real speed-test cancellation/data limits, IPv4/IPv6 details, VPN/Ethernet context, mesh roaming, and sleep/wake.
- Exercise layout editing, survey resume, room comparisons, imports, and CSV/PNG/PDF exports.
- Check light/dark appearance, keyboard navigation, VoiceOver, Increase Contrast, and Reduce Motion on supported systems.
- For widget releases, verify actual installation, App Group sharing, configuration, stale snapshots, and deep links outside the debugger.
- Profile idle and live-panel resource use; the eight-hour memory and idle CPU/memory targets are not yet validated claims.
- Confirm notarization status is **Accepted**. Review the notary log if it fails; do not publish a rejected submission.
- Validate the final artifact:

```sh
xcrun stapler validate "dist/WiFi Atlas.app"
xcrun stapler validate dist/WiFiAtlas.dmg
codesign --verify --deep --strict "dist/WiFi Atlas.app"
spctl --assess --type execute --verbose "dist/WiFi Atlas.app"
shasum -a 256 dist/WiFiAtlas.dmg
```

Download and install the DMG on another Mac. Then create a release at <https://github.com/omkasana/wifi-atlas/releases>, attach the notarized DMG, and include its SHA-256 checksum, version, requirements, changes, and known limitations. Generated binaries belong in release assets, not Git history.
