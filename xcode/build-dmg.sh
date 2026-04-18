#!/usr/bin/env bash
# Build Release (universal) and create ../Later-<version>.dmg next to this folder.
# Version is controlled by LATER_VERSION below; bump together with Info.plist.
set -euo pipefail

LATER_VERSION="2.5.0"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
DERIVED="$ROOT/DerivedDataDMG"
OUT_DMG="$(cd "$ROOT/.." && pwd)/Later-${LATER_VERSION}.dmg"

echo "==> Building Later (Release, universal)…"
rm -rf "$DERIVED"
xcodebuild \
  -project Later.xcodeproj \
  -scheme Later \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH=$(find "$DERIVED" -name "Later.app" -type d | head -n 1)
if [[ -z "${APP_PATH}" ]]; then
  echo "error: Later.app not found under $DERIVED" >&2
  exit 1
fi

echo "==> Packaging $(basename "$APP_PATH")…"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_PATH" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"

rm -f "$OUT_DMG"
hdiutil create \
  -srcfolder "$STAGE" \
  -volname "Later Installer" \
  -format UDZO \
  -o "$OUT_DMG"

echo "==> Created: $OUT_DMG"
/usr/bin/stat -f "%z bytes" "$OUT_DMG" 2>/dev/null || true
