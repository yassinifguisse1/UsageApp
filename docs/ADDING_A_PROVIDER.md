# Adding a provider

A provider turns some local, documented source of allowance data into a `ProviderReading`. Codex is the best worked example: it asks the local CLI over a documented interface and never handles credentials itself.

Before writing code, open a provider request that answers these questions:

- Where does the data come from, and is that source documented or stable?
- Does reading it need credentials? UsageApp must never store or ask for them.
- Which windows does it report (for example a 5-hour and a 7-day window), and does each include a reset time?

## 1. Declare the provider

In `Sources/UsageCore/Provider.swift`, add a case to `Provider` with its display `name` and `staleAfter`. Choose `staleAfter` from how often the source updates. Codex uses five minutes and Claude Code fifteen.

The compiler then points to every `switch` that needs the new case, including the colors and logo asset in `App/PanelAppearance.swift`. Add the logo to `App/ProviderArtwork.xcassets` only if its brand guidelines allow it, and credit its source in the README.

## 2. Parse the data

Add a parser beside `CodexUsageParser.swift` that turns the source's response into `[UsageWindow]`.

- Give each window a stable `id`, a human `label`, `usedPercent` between 0 and 100, and `resetsAt` if the source reports one. Mark the main short window `isPrimary`.
- Reject malformed fields one at a time with the `ProviderJSON` helpers, rather than failing the whole response.
- Never treat a missing value as zero.
- Add a `reportsLimits` check, like Codex and Claude Code have, so a response in an unknown shape returns `.unavailable(provider.unrecognizedFormatMessage)` instead of an empty reading.

Add parser tests to `Tests/UsageCoreTests/ParserTests.swift` with real (anonymized) response shapes, including partial and malformed ones.

## 3. Implement `UsageProvider`

Add `YourProvider: UsageProvider` with `func read() async -> ProviderReading`. Return:

- `.sample(UsageSample)` with the parsed windows,
- `.setupRequired(message)` with a `ProviderSetupAction` when the user must install, sign in, or update something,
- `.waiting(message)` when setup is done but no data has arrived yet,
- `.unavailable(message)` for anything else.

Messages are shown in the UI, so keep each one short and say what to do next. Bound any subprocess or file read with a timeout, and support cancellation. `CodexProvider.read()` shows the pattern.

## 4. Wire it into the model

In `App/UsageModel.swift`:

- Inject the read function through `init` like `readCodex`, so tests can supply fake readings.
- Add a `refreshYourProvider()` modeled on `refreshCodex()`, with its own task, generation check, and next-read time, and call it from `refresh()` and `tick(visible:)`.
- Seed an initial `.waiting` reading in `resetLiveReadings()`.

Add sample readings to `App/DemoUsage.swift` so the provider appears in demo mode.

## 5. Add setup controls

Add a `YourProviderConnectionControls` view in `App` and show it from the `switch` in `App/SetupView.swift`. Follow `CodexConnectionControls.swift`: state what is connected, offer one clear next action, and include **Check Connection**.

## 6. Document it

Add a "Connect YourProvider" section to the README covering what the user installs, what UsageApp reads, where any data is stored, and a link to the source's documentation. Add a line to `CHANGELOG.md`.

Register every new file in `UsageApp.xcodeproj`, then run both test commands from CONTRIBUTING.md.
