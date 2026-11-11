#!/bin/sh
# Builds Folio into ./build (or $FOLIO_DERIVED_DATA), regardless of the DerivedData location set in Xcode.
# Usage: scripts/build.sh [Debug|Release] [build settings for xcodebuild, e.g. MARKETING_VERSION=1.1]
set -eu
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null && xcodegen generate --quiet
CONFIG="${1:-Debug}"
[ $# -gt 0 ] && shift
DERIVED="${FOLIO_DERIVED_DATA:-$PWD/build}"
xcodebuild -project Folio.xcodeproj -scheme Folio -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -IDECustomDerivedDataLocation="$DERIVED" \
  SYMROOT="$DERIVED/Products" OBJROOT="$DERIVED/Intermediates.noindex" \
  "$@" build | grep -E "^/.*(error|warning):|BUILD" || true
echo "$DERIVED/Products/$CONFIG/Folio.app"
