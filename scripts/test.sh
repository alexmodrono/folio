#!/bin/sh
# Runs the unit tests (FolioTests), regardless of the DerivedData location set in Xcode.
set -eu
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null && xcodegen generate --quiet
DERIVED="${FOLIO_DERIVED_DATA:-$PWD/build}"
xcodebuild -project Folio.xcodeproj -scheme Folio -configuration Debug \
  -derivedDataPath "$DERIVED" -IDECustomDerivedDataLocation="$DERIVED" \
  SYMROOT="$DERIVED/Products" OBJROOT="$DERIVED/Intermediates.noindex" \
  test 2>&1 | grep -E "^/.*error:|✔|✘|Test run|TEST (SUCCEEDED|FAILED)" || true
