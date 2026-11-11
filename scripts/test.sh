#!/bin/sh
# Runs the unit tests (FolioTests), regardless of the DerivedData location set in Xcode.
# Exits with xcodebuild's status, so CI fails when a test does. Extra arguments go to xcodebuild.
set -eu
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null && xcodegen generate --quiet
DERIVED="${FOLIO_DERIVED_DATA:-$PWD/build}"
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
STATUS=0
xcodebuild -project Folio.xcodeproj -scheme Folio -configuration Debug \
  -derivedDataPath "$DERIVED" -IDECustomDerivedDataLocation="$DERIVED" \
  SYMROOT="$DERIVED/Products" OBJROOT="$DERIVED/Intermediates.noindex" \
  "$@" test > "$LOG" 2>&1 || STATUS=$?
grep -E "^/.*error:|✔|✘|Test run|TEST (SUCCEEDED|FAILED)" "$LOG" || tail -40 "$LOG"
exit "$STATUS"
