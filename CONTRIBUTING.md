# Contributing to UsageApp

Thanks for helping. Bug reports, provider requests, and pull requests are all welcome.

## Build and test

You need macOS 14 or later and Xcode 16 or later.

```sh
swift test
xcodebuild -project UsageApp.xcodeproj -scheme UsageApp -destination 'platform=macOS' -derivedDataPath DerivedData test
```

`swift test` covers the `UsageCore` package. The Xcode test target also compiles `UsageModel` and runs its tests, so run both before opening a pull request.

To try UI changes without either CLI or a sign-in, run the app and stay in **Demo** mode. To force demo mode for one launch without changing your saved setting, run:

```sh
open -n DerivedData/Build/Products/Debug/UsageApp.app --args -demoMode YES
```

## Project layout

- `Sources/UsageCore` holds providers, parsers, reading history, alerts, trends, and the update check. Everything here is unit tested and has no UI.
- `Sources/ClaudeStatus` is the status-line helper that Claude Code runs. It must never change the wrapped status line's output or exit status.
- `App` is the AppKit and SwiftUI app: the edge panel, the cards, and Settings.

The Xcode project is maintained by hand. When you add a source file, add it to `UsageApp.xcodeproj` as well as to the folder, and check that both `swift test` and `xcodebuild … test` still pass.

## Code style

Match the surrounding code: 4-space indentation, lines that stay readable without wrapping, and comments only where the reason isn't obvious from the code. `.editorconfig` covers whitespace. The project doesn't run an automatic formatter because the layout is hand-tuned.

User-facing text is short, specific, and in sentence case. A reading is never invented: show a labeled state instead of a fake 0%.

## Privacy rules

UsageApp stores no credentials, prompts, transcripts, or raw provider payloads, and sends no telemetry. Its only network request of its own is the optional GitHub release check. A change that adds a network request, stores new data, or edits files outside the app's own directories needs a README update and a note in the pull request.

## Adding a provider

See [docs/ADDING_A_PROVIDER.md](docs/ADDING_A_PROVIDER.md). Open a provider request first so the data source can be discussed before you write code.

## Screenshots

`docs/images/` holds the README screenshots. Capture them in demo mode in both light and dark appearance, at the default display scale, with only the panel and one pinned card in view.

## Releases

Maintainers release by adding an entry to `CHANGELOG.md`, setting `MARKETING_VERSION` in the Xcode project, and pushing a matching `vMAJOR.MINOR.PATCH` tag from `main`. The workflow needs these repository secrets:

| Secret | Contents |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | The Developer ID Application certificate and private key, exported as .p12, then `base64 -i cert.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | The .p12 export password |
| `APPLE_TEAM_ID` | The 10-character Apple Developer team ID |
| `NOTARY_KEY_P8_BASE64` | An App Store Connect API key (.p8) with Developer access, base64 encoded |
| `NOTARY_KEY_ID` | That API key's ID |
| `NOTARY_ISSUER_ID` | The App Store Connect issuer ID |
| `HOMEBREW_TAP_TOKEN` | Optional. A fine-grained token with Contents read and write access to `homebrew-tap` only |

Without the signing secrets, a release tag fails instead of publishing an unsigned build. Without `HOMEBREW_TAP_TOKEN`, the release publishes but the cask isn't updated.
