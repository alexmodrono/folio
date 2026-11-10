#!/bin/sh
# Builds, checks, packages and notarizes a Folio release as dist/Folio-<version>.dmg.
# Notarization uses the keychain profile $NOTARY_PROFILE (default folio-notary).
set -eu
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: CORREDURIA DE SEGUROS SURE SERVICE SA (54WRV8QX2U)"
TEAM=54WRV8QX2U
PROFILE="${NOTARY_PROFILE:-folio-notary}"
DERIVED="$PWD/build/release"
APP="$DERIVED/Products/Release/Folio.app"
BIN="$APP/Contents/MacOS/Folio"

fail() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

# 1. Clean Release build in its own derived data folder.
step "Building Release"
rm -rf "$APP"
FOLIO_DERIVED_DATA="$DERIVED" scripts/build.sh Release
[ -x "$BIN" ] || fail "build failed, no $BIN"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
echo "Folio $VERSION ($BUILD)"

# Xcode adds get-task-allow (a debugging entitlement notarization rejects) unless
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS is NO. If it slipped in, re-sign with just our entitlements.
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "com.apple.security.get-task-allow"; then
  echo "Re-signing without get-task-allow"
  codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    --entitlements Folio/Resources/Folio.entitlements "$APP"
fi

# 2. Signature: valid, Developer ID, hardened runtime, secure timestamp, right entitlements.
step "Checking signature"
codesign --verify --deep --strict --verbose=2 "$APP"
INFO=$(codesign -dvv "$APP" 2>&1)
echo "$INFO" | grep -q "^Authority=Developer ID Application: .*($TEAM)" || fail "not signed with Developer ID ($TEAM)"
echo "$INFO" | grep -q "^TeamIdentifier=$TEAM" || fail "wrong team identifier"
echo "$INFO" | grep -Eq "^CodeDirectory .*flags=.*runtime" || fail "hardened runtime is off"
echo "$INFO" | grep -q "^Timestamp=" || fail "no secure timestamp"
ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)
echo "$ENTITLEMENTS" | grep -q "com.apple.security.device.audio-input" || fail "audio-input entitlement missing"
if echo "$ENTITLEMENTS" | grep -q "com.apple.security.get-task-allow"; then fail "get-task-allow is set (debug entitlement)"; fi
echo "Developer ID, hardened runtime, timestamp, audio-input entitlement: ok"

# 3. No debug leftovers in the binary: DebugHooks, the FOLIO_FINDLE preview switch, web inspector.
step "Checking for debug code"
STRINGS=$(strings -a "$BIN")
for needle in FOLIO_DEBUG app.folio.debug FOLIO_FINDLE setInspectable: DebugHooks; do
  if echo "$STRINGS" | grep -q -- "$needle"; then fail "Release binary contains '$needle'"; fi
done
if nm -a "$BIN" 2>/dev/null | grep -q DebugHooks; then fail "Release binary has DebugHooks symbols"; fi
# Debug builds split code into Folio.debug.dylib and __preview.dylib; Release must not ship them.
if ls "$APP/Contents/MacOS" | grep -q '\.dylib$'; then fail "dylibs in Contents/MacOS (debug build layout)"; fi
echo "no FOLIO_DEBUG, app.folio.debug, FOLIO_FINDLE, setInspectable:, DebugHooks, debug dylibs: ok"

# 4. DMG with the app and an /Applications link, signed with the same identity.
step "Creating DMG"
DMG="dist/Folio-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Folio.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
rm -f "$DMG"
hdiutil create -quiet -volname "Folio $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
echo "$DMG"

# 5. Notarize and staple. Stops here with a signed, un-notarized DMG if no credentials are stored.
step "Notarizing"
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  cat >&2 <<EOF

No notary credentials in keychain profile "$PROFILE".
$DMG is signed but NOT notarized; don't publish it.

One-time setup (prompts for an app-specific password from account.apple.com):
  xcrun notarytool store-credentials $PROFILE --apple-id <email> --team-id $TEAM

Then run scripts/release.sh again.
EOF
  exit 2
fi
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait | tee dist/notary.log
grep -q "status: Accepted" dist/notary.log || fail "notarization was not accepted, see: xcrun notarytool log <id> --keychain-profile $PROFILE"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# 6. Gatekeeper's view of the DMG and of the app inside it.
step "Gatekeeper"
spctl -a -t open --context context:primary-signature -v "$DMG"
MOUNT=$(mktemp -d)
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
spctl -a -vv "$MOUNT/Folio.app" || { hdiutil detach -quiet "$MOUNT"; fail "Gatekeeper rejects the app"; }
hdiutil detach -quiet "$MOUNT"

# 7. Publishing is left to you.
step "Done"
cat <<EOF
$DMG is signed, notarized and stapled. To publish:

  gh release create v$VERSION $DMG --repo alexmodrono/folio \\
    --title "Folio $VERSION" --notes "Folio $VERSION for macOS 26 and later."
EOF
