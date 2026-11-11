# Build from source

Folio is a native AppKit app with no third-party dependencies. You need **Xcode 26** and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Get the code

```sh
brew install xcodegen
git clone https://github.com/alexmodrono/folio.git
cd folio
```

The Xcode project is generated from `project.yml`. Don't edit `Folio.xcodeproj` by hand; the build script regenerates it.

## Build and run

```sh
scripts/build.sh            # Debug build into build/Products/Debug/Folio.app
scripts/run.sh              # build and launch the Debug app, logs in the terminal
scripts/test.sh             # unit tests
```

`scripts/build.sh Release` makes a Release build, which needs a Developer ID certificate.

## Try it without your library

Point a Debug build at a scratch folder so it doesn't touch `~/Documents/Folio`:

```sh
defaults write app.folio.Folio libraryPath ~/Desktop/folio-test
scripts/run.sh
defaults delete app.folio.Folio
```

## When chatgpt.com changes

The selectors Folio uses on chatgpt.com are at the top of `Folio/Resources/chatgpt-bridge.js`. The bridge tests run it against saved copies of chatgpt.com's markup in `FolioTests/Fixtures/`. Update both when the page changes.
