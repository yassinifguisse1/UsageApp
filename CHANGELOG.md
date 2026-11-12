# Changelog

All notable changes to UsageApp are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Hover over the floating panel gear to open the UsageApp menu. It closes when the pointer leaves the gear and menu.

## [1.0.0]

First public release.

### Added

- Edge panel with Claude Code, Codex, and Perplexity allowance rings, hover and pinned detail cards, and a demo mode.
- Codex readings through the CLI's documented app-server interface.
- Claude Code readings through a status-line helper, with guided setup that shows the proposed `settings.json` change before applying it, preserves an existing status line, and can be undone.
- Manual Perplexity Computer credit tracking (beta).
- The panel hides at the display edge behind a slim tab and slides out with an animation when you point at the edge. It can also stay out all the time.
- **Open UsageApp at login** option.
- Notifications when a Claude Code or Codex window passes 75, 90, or 95 % and at 100 %, plus an optional notification when a window resets.
- A sparkline of the headline window for the current period in each card.
- Options to hide providers from the panel and to set the Codex refresh interval.
- An optional daily check for a newer GitHub release, shown in the menu.
- A clear message when Claude Code or Codex reports limits in a format this version can't read.
- Universal build for Apple silicon and Intel, signed with a Developer ID, notarized, and installable with `brew install --cask yassinifguisse1/tap/usageapp`.

[Unreleased]: https://github.com/yassinifguisse1/UsageApp/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yassinifguisse1/UsageApp/releases/tag/v1.0.0
