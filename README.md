# Folio

Folio is a small native PDF reader for macOS with ChatGPT in a side panel. The panel is chatgpt.com, signed in with your own ChatGPT account. Folio can attach the open PDF to the composer and quote the text you select, with the page number, so you can ask about what you're reading without leaving it. It keeps your PDFs in a plain folder (`~/Documents/Folio` by default) and can show your Moodle courses if you use [Findle](https://github.com/alexmodrono/Findle).

Not affiliated with OpenAI.

## Requirements

macOS 26 or later, and a ChatGPT account.

## Install

Download the latest `Folio-<version>.dmg` from [GitHub Releases](https://github.com/alexmodrono/folio/releases/latest), open it and drag Folio to Applications. Releases are signed with a Developer ID and notarized by Apple.

## Build from source

Needs Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml`.

```sh
scripts/build.sh            # Debug build into build/Products/Debug/Folio.app
scripts/build.sh Release    # Release build (needs the Developer ID certificate)
scripts/run.sh              # build and launch the Debug app, logs in the terminal
scripts/test.sh             # unit tests
```

## Releasing

1. Set `MARKETING_VERSION` (and bump `CURRENT_PROJECT_VERSION`) in `project.yml`.
2. One time only, store notarization credentials in the keychain. This asks for an app-specific password from [account.apple.com](https://account.apple.com):

   ```sh
   xcrun notarytool store-credentials folio-notary --apple-id <email> --team-id 54WRV8QX2U
   ```

3. Run `scripts/release.sh`. It builds Release, checks the signature (Developer ID, hardened runtime, timestamp, microphone entitlement) and that no debug code is in the binary, then creates `dist/Folio-<version>.dmg`, signs it, notarizes it, staples the ticket and checks it with Gatekeeper. Set `NOTARY_PROFILE` to use a different keychain profile.
4. Publish the DMG with the `gh release create` command the script prints. The app's update check reads the latest release of [alexmodrono/folio](https://github.com/alexmodrono/folio/releases), so publish it there and don't mark it as a pre-release.

## Privacy

Folio has no accounts, servers, analytics or tracking. What you send in the chat panel goes to OpenAI under their terms. The only other network request Folio makes on its own is a daily check of GitHub for a new release, which you can turn off in Settings. Details: [pdf.amodrono.com/privacy](https://pdf.amodrono.com/privacy.html).

## Problems

Use Help > Report a Problem in the app, or [open an issue](https://github.com/alexmodrono/folio/issues).
