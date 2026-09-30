#!/usr/bin/env bash
#
# Builds, signs, notarizes and staples Janus, then packages it as a DMG.
#
# One-time setup:
#   1. Join the Apple Developer Program, then create a "Developer ID Application"
#      certificate in Xcode > Settings > Accounts > Manage Certificates.
#      `security find-identity -v -p codesigning` must list it.
#   2. Store an app-specific password for notarytool (make one at
#      https://appleid.apple.com > Sign-In and Security > App-Specific Passwords):
#
#        xcrun notarytool store-credentials janus-notary \
#          --apple-id "you@example.com" \
#          --team-id "YOURTEAMID" \
#          --password "abcd-efgh-ijkl-mnop"
#
#   3. Export TEAM_ID below, or pass it in the environment.
#
# Usage: TEAM_ID=YOURTEAMID ./scripts/release.sh

set -euo pipefail

APP_NAME="Janus"
SCHEME="cursor-toolbar"
PROJECT="cursor-toolbar.xcodeproj"
NOTARY_PROFILE="${NOTARY_PROFILE:-janus-notary}"
BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG="$BUILD_DIR/$APP_NAME.dmg"

if [[ -z "${TEAM_ID:-}" ]]; then
  echo "error: TEAM_ID is not set. Find it with:" >&2
  echo "  security find-identity -v -p codesigning   # the value in parentheses" >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "error: no 'Developer ID Application' certificate in the keychain." >&2
  echo "       An 'Apple Development' cert is NOT sufficient for distribution." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  | grep -E "error:|warning:|SUCCEEDED|FAILED" || true

echo "==> Exporting a Developer ID build"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <!-- Notarization requires a secure timestamp on the signature. -->
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

APP="$EXPORT_DIR/$APP_NAME.app"

echo "==> Verifying the signature before submitting"
codesign --verify --deep --strict --verbose=2 "$APP"
# Hardened runtime is mandatory for notarization; fail loudly if it regressed.
if ! codesign -d --verbose=2 "$APP" 2>&1 | grep -q "flags=.*runtime"; then
  echo "error: hardened runtime is not enabled on the signed app." >&2
  exit 1
fi

echo "==> Packaging DMG"
DMG_STAGE="$BUILD_DIR/dmg"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG"

echo "==> Notarizing (this usually takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Verifying Gatekeeper acceptance"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

echo
echo "Done: $DMG"
