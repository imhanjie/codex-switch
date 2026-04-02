#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/codex-switch.xcodeproj}"
SCHEME="${SCHEME:-codex-switch}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/release/DerivedData}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/dist}"
VERSION="${VERSION:-$(git -C "$ROOT_DIR" describe --tags --always --dirty)}"
APP_NAME="${APP_NAME:-Codex Switch}"
DMG_NAME="${DMG_NAME:-CodexSwitch-${VERSION}.dmg}"
ZIP_NAME="${ZIP_NAME:-CodexSwitch-${VERSION}.zip}"
RUN_TESTS="${RUN_TESTS:-1}"

rm -rf "$DERIVED_DATA_PATH"
rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

if [[ "$RUN_TESTS" == "1" ]]; then
  swift test --package-path "$ROOT_DIR"
fi

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build

PRODUCTS_DIR="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
APP_PATH="$(find "$PRODUCTS_DIR" -maxdepth 1 -name '*.app' -print -quit)"

if [[ -z "$APP_PATH" ]]; then
  echo "No .app bundle found in $PRODUCTS_DIR" >&2
  exit 1
fi

APP_BUNDLE_NAME="$(basename "$APP_PATH")"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/build/release/staging.XXXXXX")"
DMG_ROOT="$STAGING_DIR/$APP_NAME"
mkdir -p "$DMG_ROOT"

ditto "$APP_PATH" "$DMG_ROOT/$APP_BUNDLE_NAME"
ln -s /Applications "$DMG_ROOT/Applications"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARTIFACT_DIR/$ZIP_NAME"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  "$ARTIFACT_DIR/$DMG_NAME"

rm -rf "$STAGING_DIR"

echo "Created artifacts:"
echo "$ARTIFACT_DIR/$ZIP_NAME"
echo "$ARTIFACT_DIR/$DMG_NAME"
