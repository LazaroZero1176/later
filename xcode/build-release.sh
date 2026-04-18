#!/usr/bin/env bash
# Release-Build (lokal ausführen): arm64, ohne Codesignatur wie in CI-Workflows.
# Ergebnis: ./.build/Build/Products/Release/Later.app
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
DERIVED="$ROOT/.build"
mkdir -p "$DERIVED"
xcodebuild \
  -project Later.xcodeproj \
  -scheme Later \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS" \
  ARCHS="arm64" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
echo "Built: $DERIVED/Build/Products/Release/Later.app"
