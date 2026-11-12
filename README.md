# UsageApp

UsageApp puts Claude Code and Codex allowance rings at the right edge of your Mac display. Each ring shows the main short window when available. Hover to see all reported windows, or click to keep the detail card open. Click again to dismiss it. The menu bar gives you the same readings in **Usage & Setup**, plus display selection, show/hide, and refresh.

## Build and try the demo

Use macOS 14 or later and Xcode 16 or later. Open **UsageApp.xcodeproj**, select the **UsageApp** scheme with **My Mac** as the destination, and press **Run**. The app appears in the menu bar and opens a panel marked **Demo** on the primary display. Demo readings work without either CLI or a sign-in. Choose **Switch to Live Usage** from the UsageApp menu when ready to connect.

To build and test from the repository root:

```sh
xcodebuild -project UsageApp.xcodeproj -scheme UsageApp -destination 'platform=macOS' -derivedDataPath DerivedData build
xcodebuild -project UsageApp.xcodeproj -scheme UsageApp -destination 'platform=macOS' -derivedDataPath DerivedData test
```

The shared scheme builds the app, its bundled status-line helper, and the test suite. The app builds with an ad hoc signature for local use. You can also run the provider and state tests with `swift test`.

## CI and releases

GitHub Actions runs the Swift package tests, tests the Xcode project, and packages a universal app on pull requests and pushes to `main`. Get the app ZIP and its SHA-256 checksum from [GitHub Releases](https://github.com/yassinifguisse1/UsageApp/releases) or download the `UsageApp-macos-universal` artifact from a successful [workflow run](https://github.com/yassinifguisse1/UsageApp/actions/workflows/macos.yml).

With both files in the same directory, run `shasum -a 256 -c UsageApp-macos-universal.zip.sha256`. Unzip the app and move it to Applications. The build supports Apple silicon and Intel Macs running macOS 14 or later. The app is ad hoc signed and has no Apple notarization, so macOS may block it on first launch.

To publish a release, push a `vMAJOR.MINOR.PATCH` tag from `main` that matches the app's `MARKETING_VERSION` in Xcode. The workflow repeats the checks and publishes the ZIP and checksum to GitHub Releases after they pass.

## Connect Codex

1. Install a current Codex CLI that supports `codex app-server`. Run `codex login` in Terminal and sign in with ChatGPT. UsageApp asks for ChatGPT allowance windows. API key billing and plans without reported allowance windows may show no percentage.
2. Switch to **Live Usage** and choose **Refresh Now**. UsageApp looks for the CLI in standard install locations, including `~/.local/bin` and Homebrew’s bin directories. If it cannot find it, run `command -v codex` in Terminal, then use **Usage & Setup → Choose Codex Executable…**.
3. If you use a non-default `CODEX_HOME`, launch the built app executable from a Terminal session with that variable exported so the CLI child inherits it.

UsageApp asks the local CLI for account limits through the documented app-server interface. Codex uses its own sign-in and contacts OpenAI to fetch the allowance. Refresh Now, wake, and the two-minute refresh while usage is visible all use this route. [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt)

## Connect Claude Code

Use a current Claude Code release with status-line rate-limit fields. A supported Claude subscription or a Claude apps gateway with a spend limit can report data after the first API response in an interactive session. Claude Code supplies the timing of updates. Refresh Now in UsageApp rereads the latest local capture.

1. Copy the app's bundled helper to a stable path so rebuilding or moving the app does not change your status-line command. For a local Debug build, set `app=DerivedData/Build/Products/Debug/UsageApp.app` in the command below.

   ```sh
   app=/Applications/UsageApp.app
   mkdir -p "$HOME/.local/bin"
   install -m 755 "$app/Contents/MacOS/usageapp-claude-status" \
     "$HOME/.local/bin/usageapp-claude-status"
   ```

2. Use Claude Code’s `/status` to see which settings files are active. For a personal status line this is usually `~/.claude/settings.json`, or `settings.json` in your `CLAUDE_CONFIG_DIR`. If a project has its own command, use the effective editable setting for that project. Save the original `statusLine.command` value before changing it. Follow organization policy for managed settings.
3. If you already have a status-line script, wrap it by passing its path and arguments after `--`. Keep the original `statusLine` options such as padding or refresh interval. For example, change only the `command` value if the existing script is at `~/.claude/my-status-line.sh`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "\"$HOME/.local/bin/usageapp-claude-status\" -- \"$HOME/.claude/my-status-line.sh\""
     }
   }
   ```

   For an existing command that uses shell expressions or a pipeline, put the original command verbatim in an executable script with the appropriate shell as its shebang. Pass that script after `--`. The helper runs it from the same working directory and forwards the original stdin, stdout, stderr, and exit status. For a script that previously relied on an explicit interpreter, pass its absolute path and the original arguments after `--`.

   If you have no status line, merge this entry into your settings. The helper captures usage quietly in this configuration.

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "\"$HOME/.local/bin/usageapp-claude-status\""
     }
   }
   ```

4. Open an interactive Claude Code session in a trusted project and wait for an assistant response in your normal workflow. Switch UsageApp to **Live Usage**. If the ring remains unavailable, check for a newer CLI, a settings override, a workspace trust prompt, or a plan that does not report subscription limits. [Claude Code status-line documentation](https://code.claude.com/docs/en/statusline)

To undo setup, restore the original `statusLine.command` in the same file, or remove the `statusLine` entry if you added it. You can then remove `~/.local/bin/usageapp-claude-status` and the UsageApp Application Support directory.

## Readings and local data

- **Setup required** means the app needs a CLI sign-in or a Claude bridge callback. **Unavailable** means it could not obtain a usable reading. **Stale** shows an older reading with its capture time. Codex marks readings stale after a failed refresh or five minutes. Claude Code marks them stale after 15 minutes.
- When a reported reset passes, the app withholds that window’s percentage until the provider reports a new period. Other windows can remain available. A reading without a reset timestamp says **Reset not provided**.
- `~/Library/Application Support/UsageApp/claude-usage.json` holds one owner-private snapshot with window IDs, percentages, reset times, and a capture time. A local lock file coordinates writes from concurrent Claude sessions. Codex readings stay in memory. macOS preferences hold the selected mode, panel visibility, display choice, and optional CLI path. UsageApp stores no credentials, prompts, transcripts, or raw provider payloads and sends no app telemetry.

## Manual verification on macOS

- Launch in Demo mode with both CLIs absent. Hover and pin each card, then try the same readings from the menu with VoiceOver or keyboard navigation.
- Compare live readings with the **Claude Code Usage** view and the **Codex usage dashboard** or CLI `/status`. If Codex shows remaining percentage, compare its complement to UsageApp’s percentage used. Compare reset timestamps in the same time zone. Verify the original Claude status line still works after connecting and after undoing setup.
- Type in an editor while hovering and clicking the panel. Switch between apps, Spaces, and a native full-screen editor. Select an external display, disconnect it, and reconnect it. Confirm the panel falls back to the primary display and returns to the preferred display without taking keyboard focus.

The edge notch and usage card are inspired by [Codenotch](https://github.com/vinzdg/codenotch).

UsageApp is an independent project distributed under the [MIT license](LICENSE).


The provider icons identify their respective services and are excluded from the MIT license. The Claude Code icon comes from [Anthropic’s Claude Code documentation](https://code.claude.com/docs/en/overview). The Codex icons come from the [official OpenAI desktop app](https://openai.com/codex/). Before distributing builds with these icons, review the [Claude Code logo terms](https://code.claude.com/docs/en/legal-and-compliance) and the [OpenAI brand guidelines](https://openai.com/brand/).
