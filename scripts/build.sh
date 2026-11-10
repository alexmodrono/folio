#!/bin/sh
# Builds Folio into ./build, regardless of the DerivedData location set in Xcode.
set -eu
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null && xcodegen generate --quiet
CONFIG="${1:-Debug}"
xcodebuild -project Folio.xcodeproj -scheme Folio -configuration "$CONFIG" \
  -derivedDataPath "$PWD/build" -IDECustomDerivedDataLocation="$PWD/build" \
  SYMROOT="$PWD/build/Products" OBJROOT="$PWD/build/Intermediates.noindex" \
  build | grep -E "^/.*(error|warning):|BUILD" || true
echo "build/Products/$CONFIG/Folio.app"
