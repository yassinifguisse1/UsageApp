# Security policy

UsageApp runs a helper inside Claude Code's status line, edits `~/.claude/settings.json` during guided setup, starts the Codex CLI as a child process, and writes owner-private files in `~/Library/Application Support/UsageApp`. Problems in any of these areas are in scope, for example:

- The status-line helper changing the wrapped command's input, output, or exit status, or running something other than the configured command
- Guided setup or Undo Setup writing outside the reviewed change, following symlinks, or losing an existing status line
- Files that are readable by other users, or that can be redirected by another local user
- The update check opening a URL that isn't one of this project's GitHub releases

## Reporting a vulnerability

Report it privately through [GitHub Security Advisories](https://github.com/yassinifguisse1/UsageApp/security/advisories/new). Don't open a public issue. Include the macOS version, the UsageApp version, and steps to reproduce.

You can expect an acknowledgement within a week. Fixes are released as a new version, with credit in the changelog unless you'd rather stay anonymous.

## Supported versions

Only the latest release gets security fixes.
