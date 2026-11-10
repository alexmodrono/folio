#!/bin/sh
# Builds Folio into ./build (or $FOLIO_DERIVED_DATA), regardless of the DerivedData location set in Xcode.
set -eu
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null && xcodegen generate --quiet
CONFIG="${1:-Debug}"
DERIVED="${FOLIO_DERIVED_DATA:-$PWD/build}"
xcodebuild -project Folio.xcodeproj -scheme Folio -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -IDECustomDerivedDataLocation="$DERIVED" \
  SYMROOT="$DERIVED/Products" OBJROOT="$DERIVED/Intermediates.noindex" \
  build | grep -E "^/.*(error|warning):|BUILD" || true
echo "$DERIVED/Products/$CONFIG/Folio.app"
