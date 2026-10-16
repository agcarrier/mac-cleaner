# mac-cleaner

Clean-room Mac cleaner CLI. Dry run by default; cleaning moves things to the Trash, never hard-deletes.
How it decides what's safe: [SPEC.md](SPEC.md).

```bash
mac-cleaner                     # leftovers from deleted apps, app caches, broken launch agents, Xcode junk
mac-cleaner space               # package caches, old installers, idle node_modules, largest files
mac-cleaner uninstall Spotify   # an app plus everything it owns
```

Add `--clean` to act on the ✓ items, `--include-low` to include ○ items, `--filter=text` to limit to matching names.
`·` items are listed only and never cleaned.

## Install

```bash
./install.sh
```

Builds a release binary and copies it to `~/.local/bin/mac-cleaner` (pass another folder as the first argument to change that).
This folder is iCloud-synced, so the build happens in `~/Library/Caches/MacCleaner/spm`.

Tests: `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`

## Full Disk Access

Sandboxed apps keep their data in `~/Library/Containers` and `~/Library/Group Containers`, which macOS blocks without
Full Disk Access. Without it, those checks are skipped with a warning. Grant it to whatever runs the command: your terminal app,
or for Claude Code in the Claude desktop app, the `claude.app` inside `~/Library/Application Support/Claude/claude-code/<version>/`
(Claude.app itself doesn't pass it on, and a Claude Code update means granting it again).
