# Contributing to Folio

Thanks for helping. Bug reports work best through **Help › Report a Problem…** in the app, which fills in the version, macOS and recent log lines for you. For code, open a pull request against `main`. CI runs the tests, and every pull request gets an automated review.

## Build and test

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

- `scripts/build.sh [Debug|Release]` regenerates the project and builds into `build/Products/<config>/Folio.app`. The `.xcodeproj` is generated from `project.yml`; don't edit it by hand.
- `scripts/run.sh` builds and launches the Debug app with its log in the terminal.
- `scripts/test.sh` runs the unit tests (`FolioTests`, Swift Testing). Tests use temporary files, never your library or questions. The bridge tests run `chatgpt-bridge.js` in a web view against synthetic pages and sanitized captures in `FolioTests/Fixtures/`. Recapture those when chatgpt.com's markup changes.
- To try a build without touching your library: `defaults write app.folio.Folio libraryPath <folder>`, then `defaults delete app.folio.Folio` afterwards.
- The documentation site is in `docs-site/`: `npm ci && npm run dev` serves it at http://127.0.0.1:4320/, and `npm run build && npm run check` validates it. Keep the guides in step with the app's labels and behavior.

## Rules for the chat panel

These keep Folio a reader that sits next to chatgpt.com, not an automated client of it. See [docs/openai-terms.md](docs/openai-terms.md).

- **The person always sends.** Folio may edit the composer, but only the person's Enter or Send click sends a message. No queued, batched, scheduled or retried sends.
- Don't read or export ChatGPT's replies, and don't call chatgpt.com's private APIs (`/backend-api`). Reading the person's own sent messages to render quote chips and find attachments is fine.
- Opening a PDF never uploads it. A PDF is uploaded at most once per conversation.
- The bridge runs only on chatgpt.com pages, never on sign-in pages (Google, Apple, Microsoft, auth.openai.com).
- "ChatGPT" only names the service ("Ask ChatGPT"). Keep it out of the app's name, icon and taglines, and say Folio isn't affiliated with OpenAI wherever it's presented.

## Architecture

- AppKit for the app: `NSSplitViewController`, `NSOutlineView` sidebar, `PDFView` reader, `WKWebView` chat panel, menus in `MainMenu.swift`. SwiftUI only for self-contained views hosted in `NSHostingController` (Home, Settings).
- `LibraryStore` is the single source of truth for files on disk. Views key items by URL path, never by object identity.
- `ChatGPTSession` owns one web view per chat card. All composer edits go through `Folio/Resources/chatgpt-bridge.js`, which runs in an isolated content world. Its chatgpt.com selectors are at the top of that file; when chatgpt.com changes, fix them there first.
- The reader stays with what PDFKit offers. No annotation or editing tools. The one exception is question bubbles: a record of what was asked on a page, drawn by Folio and never saved into the PDF.
- The Findle folder (`~/Library/CloudStorage/Findle-*`) is read-only. Never rename, move or delete there, and never read a placeholder except to open or download it.
- Updates come from [Sparkle](https://sparkle-project.org), the only third-party dependency. Debug builds never start it.

## Conventions

- Swift 6 with `MainActor` as the default isolation. Mark background work `nonisolated` and run it in `Task.detached`.
- Keep the app small and fast to launch. Create the web view only when the chat panel first opens.
- Semantic system colors and fonts only, spacing on the 4 pt scale (`Folio/Support/Theme.swift`). Keep copy short and plain.
- English and Spanish: new UI strings need Spanish in `Folio/Resources/Localizable.xcstrings`. Text that goes into chat messages or is parsed back stays English.

## Releasing

1. Merge what's going out into `main` and let CI pass.
2. Tag the commit with an annotated tag. Its message becomes the release notes on GitHub and in the update window:

   ```sh
   git tag -a v1.1 -m "Folio 1.1" -m "- What changed, in a line or two"
   git push origin v1.1
   ```

3. The [Release workflow](.github/workflows/release.yml) builds, signs, notarizes and staples `Folio-<version>.dmg`, signs it for Sparkle, and publishes it with `appcast.xml` as the latest GitHub release. Installed copies pick it up from there within a day.

The workflow needs these repository secrets: `CERTIFICATE_P12_BASE64` and `CERTIFICATE_PASSWORD` (the Developer ID Application certificate), `APPLE_ID` and `NOTARIZATION_PASSWORD` (an app-specific password), and `SPARKLE_PRIVATE_ED_KEY`. `scripts/release.sh` does the same on a Mac with the certificate, the `folio-notary` keychain profile and the Sparkle key in the login keychain.
