# mac-cleaner

Clean-room Mac cleaner CLI: leftovers from deleted apps, app caches, broken launch agents, and Xcode junk, plus `mac-cleaner uninstall <app>` to remove an app and everything it owns.
Dry run by default. Cleaning moves things to the Trash, never hard-deletes. How it decides what's safe: [SPEC.md](SPEC.md).

This folder is iCloud-synced, so build outside it:

```bash
swift build -c release --scratch-path ~/Library/Caches/MacCleaner/spm
```

```bash
~/Library/Caches/MacCleaner/spm/release/mac-cleaner --help
```

Tests: `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`

Reading other apps' containers needs Full Disk Access for your terminal. Without it, container-based checks are skipped.
