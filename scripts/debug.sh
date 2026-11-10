#!/bin/sh
# Sends a command to a running Debug build (see Folio/App/DebugHooks.swift), e.g. scripts/debug.sh probe
set -eu
osascript -l JavaScript - "$1" <<'JS' >/dev/null
function run(argv) {
  ObjC.import('Foundation');
  $.NSDistributedNotificationCenter.defaultCenter
    .postNotificationNameObjectUserInfoDeliverImmediately('app.folio.debug', argv[0], $(), true);
}
JS
