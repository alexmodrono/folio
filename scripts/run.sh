#!/bin/sh
# Builds the Debug app, quits any running Folio, and launches the new build.
# Pass --no-build to launch the last build as is. Logs go to the terminal; Ctrl-C quits the app.
set -eu
cd "$(dirname "$0")/.."
[ "${1:-}" = "--no-build" ] || scripts/build.sh Debug >/dev/null
pkill -x Folio 2>/dev/null && sleep 1 || true
exec build/Products/Debug/Folio.app/Contents/MacOS/Folio
