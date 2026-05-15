#!/usr/bin/env bash
#
# Build, sign, notarize and package HyperXRGB as a DMG ready for distribution.
#
# Usage:
#   Scripts/build-release.sh <version>
#
# Environment:
#   SIGNING_IDENTITY            Codesign identity (e.g. "Developer ID Application: Name (TEAMID)").
#                               Set to "-" to do an ad-hoc unsigned build and skip notarization.
#   APPLE_TEAM_ID               10-char Apple team ID. Required when signing.
#   APP_STORE_CONNECT_KEY_ID    App Store Connect API key ID. Required for notarization.
#   APP_STORE_CONNECT_ISSUER_ID App Store Connect issuer ID. Required for notarization.
#   APP_STORE_CONNECT_KEY_P8    Contents of the .p8 API key file. Required for notarization.
#   GITHUB_RUN_NUMBER           Build number; defaults to 1 if unset.
#
set -euo pipefail

VERSION="${1:?usage: Scripts/build-release.sh <version>}"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO_ROOT/dist"
ARCHIVE="$DIST/HyperXRGB.xcarchive"
EXPORT_DIR="$DIST/export"
DMG_PATH="$DIST/HyperXRGB-$VERSION.dmg"
AUTH_KEY="$DIST/AuthKey.p8"

cleanup() { rm -f "$AUTH_KEY"; }
trap cleanup EXIT

rm -rf "$DIST"
mkdir -p "$DIST"

cd "$REPO_ROOT"

echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild archive ad-hoc ($VERSION build $BUILD_NUMBER)"
# Always archive ad-hoc. xcodebuild's manual signing lookup is unreliable in
# CI (it can fail to match cert+team even when find-identity sees the cert);
# we re-sign with codesign directly below when a real identity is provided.
xcodebuild archive \
  -project HyperXRGB.xcodeproj \
  -scheme HyperXRGB \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-"

echo "==> extract .app from archive"
mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE/Products/Applications/HyperXRGB.app" "$EXPORT_DIR/HyperXRGB.app"

if [[ "$SIGNING_IDENTITY" != "" && "$SIGNING_IDENTITY" != "-" ]]; then
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID required when signing}"
  echo "==> codesign .app with Developer ID"
  codesign --force --deep \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --entitlements "$REPO_ROOT/App/HyperXRGB/HyperXRGB.entitlements" \
    --timestamp \
    "$EXPORT_DIR/HyperXRGB.app"
  codesign --verify --deep --strict --verbose=2 "$EXPORT_DIR/HyperXRGB.app"
fi

echo "==> create-dmg"
# create-dmg occasionally returns non-zero even on success (when it can't set the
# volume icon via AppleScript headless). Tolerate that as long as the DMG exists.
set +e
create-dmg \
  --volname "HyperX RGB $VERSION" \
  --window-size 540 380 \
  --icon-size 96 \
  --icon "HyperXRGB.app" 140 180 \
  --app-drop-link 400 180 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$EXPORT_DIR/HyperXRGB.app"
DMG_STATUS=$?
set -e
if [[ ! -f "$DMG_PATH" ]]; then
  echo "ERROR: create-dmg failed (exit $DMG_STATUS) and DMG not produced" >&2
  exit 1
fi

if [[ "$SIGNING_IDENTITY" == "" || "$SIGNING_IDENTITY" == "-" ]]; then
  echo "==> Skipping signing/notarization (no Developer ID)"
  echo "Built: $DMG_PATH"
  exit 0
fi

echo "==> codesign DMG"
codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

echo "==> notarytool submit (waiting for Apple)"
: "${APP_STORE_CONNECT_KEY_ID:?APP_STORE_CONNECT_KEY_ID required for notarization}"
: "${APP_STORE_CONNECT_ISSUER_ID:?APP_STORE_CONNECT_ISSUER_ID required for notarization}"
: "${APP_STORE_CONNECT_KEY_P8:?APP_STORE_CONNECT_KEY_P8 required for notarization}"

printf "%s" "$APP_STORE_CONNECT_KEY_P8" > "$AUTH_KEY"
chmod 600 "$AUTH_KEY"

xcrun notarytool submit "$DMG_PATH" \
  --key "$AUTH_KEY" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "==> stapler staple"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "Built and notarized: $DMG_PATH"
