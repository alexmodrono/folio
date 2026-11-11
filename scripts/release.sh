#!/bin/sh
# Builds, checks, packages and notarizes a Folio release:
#   dist/Folio-<version>.dmg   signed with Developer ID, notarized and stapled
#   dist/appcast.xml           Sparkle feed offering that DMG, signed with Folio's EdDSA key
# Runs locally and in .github/workflows/release.yml. Optional environment:
#   FOLIO_VERSION               overrides MARKETING_VERSION from project.yml
#   FOLIO_BUILD                 build number (default: the number of commits, so it always grows)
#   FOLIO_KEYCHAIN              keychain with the Developer ID identity and the notary profile (CI)
#   NOTARY_PROFILE              notarytool keychain profile (default folio-notary)
#   SPARKLE_PRIVATE_ED_KEY      Sparkle private key; otherwise the "folio" account in the login keychain
#   FOLIO_RELEASE_NOTES         Markdown file shown in the update window
set -eu
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: CORREDURIA DE SEGUROS SURE SERVICE SA (54WRV8QX2U)"
TEAM=54WRV8QX2U
REPO=alexmodrono/folio
PROFILE="${NOTARY_PROFILE:-folio-notary}"
DERIVED="$PWD/build/release"
APP="$DERIVED/Products/Release/Folio.app"
BIN="$APP/Contents/MacOS/Folio"
FW="$APP/Contents/Frameworks/Sparkle.framework"
SIGN_UPDATE="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
KEYCHAIN_ARGS=""
[ -n "${FOLIO_KEYCHAIN:-}" ] && KEYCHAIN_ARGS="--keychain $FOLIO_KEYCHAIN"

fail() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }
# KEYCHAIN_ARGS is empty or two words, so it's left unquoted on purpose.
sign() { codesign --force --sign "$IDENTITY" --options runtime --timestamp $KEYCHAIN_ARGS "$@"; }

# 1. Clean Release build in its own derived data folder.
step "Building Release"
rm -rf "$APP"
# Sparkle compares build numbers, so every release needs a higher one: the commit count always grows on main.
[ -n "${FOLIO_BUILD:-}" ] || FOLIO_BUILD=$(git rev-list --count HEAD)
set --
[ -n "${FOLIO_VERSION:-}" ] && set -- "$@" "MARKETING_VERSION=$FOLIO_VERSION"
[ -n "${FOLIO_BUILD:-}" ] && set -- "$@" "CURRENT_PROJECT_VERSION=$FOLIO_BUILD"
FOLIO_DERIVED_DATA="$DERIVED" scripts/build.sh Release "$@"
[ -x "$BIN" ] || fail "build failed, no $BIN"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
echo "Folio $VERSION ($BUILD)"

# Xcode signs Sparkle.framework when it copies it in, but not the helpers inside it, and notarization
# needs our Developer ID on those too. Sign them inside out, then the app with just our entitlements
# (Xcode would otherwise add get-task-allow, a debugging entitlement notarization rejects).
step "Signing Sparkle and the app"
[ -d "$FW" ] || fail "Sparkle.framework is missing"
sign "$FW/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign --entitlements Folio/Resources/Folio.entitlements "$APP"

# 2. Signature: valid, Developer ID, hardened runtime, secure timestamp, right entitlements, update key.
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
for helper in Versions/B/Autoupdate Versions/B/Updater.app Versions/B/XPCServices/Installer.xpc; do
  codesign -dvv "$FW/$helper" 2>&1 | grep -q "^TeamIdentifier=$TEAM" || fail "Sparkle's $helper isn't signed by $TEAM"
done
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP/Contents/Info.plist" 2>/dev/null || true)
[ -n "$PUBLIC_KEY" ] || fail "SUPublicEDKey is missing from Info.plist"
echo "Developer ID, hardened runtime, timestamp, audio-input entitlement, Sparkle helpers, update key: ok"

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
rm -f "$DMG" dist/appcast.xml
hdiutil create -quiet -volname "Folio $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --force --sign "$IDENTITY" --timestamp $KEYCHAIN_ARGS "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
echo "$DMG"

# 5. Notarize and staple. Stops here with a signed, un-notarized DMG if no credentials are stored.
step "Notarizing"
NOTARY_ARGS="--keychain-profile $PROFILE $KEYCHAIN_ARGS"
if ! xcrun notarytool history $NOTARY_ARGS >/dev/null 2>&1; then
  cat >&2 <<EOF

No notary credentials in keychain profile "$PROFILE".
$DMG is signed but NOT notarized; don't publish it.

One-time setup (prompts for an app-specific password from account.apple.com):
  xcrun notarytool store-credentials $PROFILE --apple-id <email> --team-id $TEAM

Then run scripts/release.sh again.
EOF
  exit 2
fi
xcrun notarytool submit "$DMG" $NOTARY_ARGS --wait | tee dist/notary.log
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

# 7. Sparkle: sign the stapled DMG (stapling changes it, so this comes last) and write the feed.
step "Sparkle appcast"
[ -x "$SIGN_UPDATE" ] || fail "no sign_update at $SIGN_UPDATE"
if [ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
  ENCLOSURE=$(printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | "$SIGN_UPDATE" --ed-key-file - "$DMG")
else
  ENCLOSURE=$("$SIGN_UPDATE" --account folio "$DMG")
fi
echo "$ENCLOSURE" | grep -q 'sparkle:edSignature=' || fail "sign_update gave no signature"
NOTES="Folio $VERSION for macOS 26 and later."
[ -n "${FOLIO_RELEASE_NOTES:-}" ] && NOTES=$(cat "$FOLIO_RELEASE_NOTES")
MINIMUM=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")
PUB_DATE=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")
cat > dist/appcast.xml <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Folio</title>
    <link>https://github.com/$REPO/releases/latest/download/appcast.xml</link>
    <language>en</language>
    <item>
      <title>Folio $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
      <link>https://github.com/$REPO/releases/tag/v$VERSION</link>
      <description sparkle:format="markdown"><![CDATA[$NOTES]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/Folio-$VERSION.dmg" type="application/octet-stream" $ENCLOSURE/>
    </item>
  </channel>
</rss>
APPCAST
xmllint --noout dist/appcast.xml
echo dist/appcast.xml

# 8. Publishing is left to you, or to the release workflow.
step "Done"
cat <<EOF
$DMG is signed, notarized and stapled, and dist/appcast.xml offers it to Sparkle. To publish:

  gh release create v$VERSION $DMG dist/appcast.xml --repo $REPO --title "Folio $VERSION" --notes "$NOTES"
EOF
