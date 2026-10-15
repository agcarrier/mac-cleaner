# Mac Cleaner — clean-room spec

Feature teardown of CleanMyMac 5 (MAS build, `/Applications/CleanMyMac_5_MAS.app`), 2026-10-15.
Source of truth: symbol and string inventory of its scanning frameworks only. No code was decompiled or copied.
Out of scope and untouched: licensing, activation, purchase flow, `license_plan`, and the encrypted rule DB `info.cmmkb`.

**What this means for the build:** the *categories* and *techniques* below are fair game. The curated per-app rule data
in `info.cmmkb` is theirs, so we build our own rules from public macOS conventions.

## Architecture observed

- One framework per scanner (`SystemJunkScanning`, `UninstallerScanning`, `TrashJunkScanning`,
  `UnusedDiskImagesScanning`, `DownloadsScanning`, `SpaceLensScanning`, …), sharing a `ScanningCore` / `CleaningCore`.
- Each scanner is a set of small `*ScanTask` / `*Fetcher` classes, each owning one location or one rule.
  Compound tasks group them (`CMUserCachesCompoundTask`, `CMSystemCachesCompoundTask`).
- Rules live in a "knowledge base" (`CMCachesKnowledgeBase`, `CMLogsKnowledgeBase`, `CMXcodeJunkKnowledgeBaseType`,
  `CMUniversalBinariesKnowledgeBaseType`) loaded from `info.cmmkb`, an encrypted 290 KB blob. The logic is generic; the safe/unsafe lists are data.
- Removal is a separate step from scanning (`LogsRemover`, `XcodeSimulatorRemover`, `BrokenPreferencesRemover`),
  and some removals go through a privileged helper (`PrivilegedOperationsPerformerService`).

**Design takeaway:** scan → list of `(path, size, category, removable)` → user reviews → remove. Keep that split.

## System Junk categories (`SystemJunkScanning`)

| Category | Where we'd look | Notes |
|---|---|---|
| User caches | `~/Library/Caches/*` | Per-app subfolders; skip apps that are currently running |
| System caches | `/Library/Caches/*` | Needs admin; v1 can skip |
| Darwin user caches | `getconf DARWIN_USER_CACHE_DIR` | CMM has a separate task for this |
| Sandbox container caches | `~/Library/Containers/*/Data/Library/Caches` | String `Data/Library/Caches` confirms it |
| User logs | `~/Library/Logs`, `~/Library/Containers/*/Data/Library/Logs` | |
| System/diagnostic logs | `/Library/Logs`, `/Library/Logs/DiagnosticReports` | Admin |
| Quarantine logs | `QuarantineEventsV2` DB | Privacy-ish, optional |
| Broken preferences | `~/Library/Preferences/*.plist` that fail to parse | `BrokenPreferencesRemover`; check with `PropertyListSerialization` |
| App Store download cache | MAS download manifest | Low value, skip |
| Universal binaries | Apps with an unused arch slice | `UniversalBinaryThinner` (lipo). **Breaks code signatures.** Skip. |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` | Big win for you |
| Xcode Archives | `~/Library/Developer/Xcode/Archives` | Old ones only, confirm |
| Xcode device support | `~/Library/Developer/Xcode/{iOS,macOS} DeviceSupport` | |
| Xcode module/doc caches | `ModuleCache.noindex`, documentation cache | |
| Xcode device logs | `~/Library/Developer/Xcode/iOS Device Logs` | |
| Simulators | `xcrun simctl list` → `simctl delete unavailable` | CMM shells out to `simctl` too; never `rm` the folders |
| Simulator runtimes | `xcrun simctl runtime list` / `delete` | |
| CoreSimulator caches | `~/Library/Developer/CoreSimulator/Caches` | |

## App Uninstaller leftovers (`UninstallerScanning`)

One fetcher per leftover type, all keyed by **bundle ID** (with app name as a fallback):

- `~/Library/Application Support/<bundleID|name>`
- `~/Library/Caches/<bundleID>` and Darwin user caches
- `~/Library/Preferences/<bundleID>*.plist` (incl. `ByHost/`)
- `~/Library/Saved Application State/<bundleID>.savedState`
- `~/Library/Containers/<bundleID>` and `~/Library/Group Containers/*<teamID>*` (sandboxed apps)
- `~/Library/Application Scripts/<bundleID>`
- `~/Library/Cookies/<bundleID>.binarycookies`, `~/Library/HTTPStorages/<bundleID>`, `~/Library/WebKit/<bundleID>`
- `~/Library/Logs/<name>`, crash logs in `DiagnosticReports/<name>_*`
- `~/Library/LaunchAgents/*.plist` and `/Library/Launch{Agents,Daemons}` whose `Label` or `Program` points at the app
- Login items (SMAppService / legacy)
- Receipts: `pkgutil --pkgs` matching the bundle ID → `pkgutil --files`
- Plugins: audio plugins (`/Library/Audio/Plug-Ins`, Avid), PDF Services, internet plugins
- Dock icon

`LeftoverCandidate` / `LeftoverUninstallerApplication` = **orphan mode**: leftovers whose app is no longer installed.
Technique: collect every bundle ID that owns a container/pref/cache, subtract installed apps (`mdfind kMDItemCFBundleIdentifier`
or a walk of `/Applications`), and what's left is orphaned. That's the most useful feature to clone.

### How matching actually works (decompiled, 2026-10-15)

Ghidra 12.1.4 via REA, arm64 slice of `UninstallerScanning`. "Observed" means read directly in pseudocode.
"Inferred" means it's my reading of stripped helpers whose strings or arguments I couldn't fully resolve.

**Caches** (`-[CMCachesFetcher directoryFinderRequestsForApplication:]` @ `0xaf00`, observed). Four lookups, in both
`~/Library/Caches` and the Darwin user cache dir:
1. Folder named exactly `<bundleID>`, `matchByWords: NO`. Skipped when the bundle ID equals the app name.
2. Folder matching the app *name* with `matchByWords: YES`, i.e. word-level fuzzy match, so "Visual Studio Code" can hit `VisualStudioCode`-ish names.
   We pick the fuzz rule ourselves. Start strict (normalized case, spaces/dashes/dots stripped) and loosen only with tests.

**Launch agents/daemons** (`matchedLaunchAgentsFrom:forBundleID:` @ `0xec88` → `isPlistHasAssociatedBundleIdentifier:forBundleID:` @ `0xee10`, observed).
Loads each plist and checks the **`AssociatedBundleIdentifiers`** key, which can be a string or an array, for an exact
bundle ID match. That's Apple's own key for linking a launch item to its app (SMAppService / Login Items UI).
No name guessing at this step, so it's safe to auto-select.

**Orphaned leftovers** (`LeftoversFetcher.fetchLeftovers()` @ `0x1f97c` and helpers, observed + inferred).
- Candidate sources (inferred from the calls): `~/Library/Containers`, reading each container's
  `.com.apple.containermanagerd.metadata.plist` for its real owner (that string is in the binary), plus `~/Library/Preferences` plists.
- Installed-app set (`0x200e8`, observed loop over apps → `bundleID`). Name lookups use the templates
  `/Applications/%@.app` and `~/Applications/%@.app`.
- Per candidate (`0x20b94`, observed calls): `bundleIDsForFileURL:` → `applicationNameFor:` → **`isIgnoreOrSystemItemFileWithPath:`**
  (skip Apple and system items) → keep it if the owner isn't installed.
- Dedup by bundle ID via a Swift `Set.insert` (`0x37730`, observed), then a user ignore list (`isAppIgnoredWithBundleId:`, observed)
  before emitting `(bundleID, appName, path)` records.

**Rules this gives us:**
- Bundle-ID matches are high confidence, so pre-check them. Name/word matches are low confidence, so show them unchecked.
- Container ownership comes from the container's metadata plist, not the folder name.
- Always skip `com.apple.*` and system items, and keep a user ignore list.
- Orphan = owner bundle ID not found among installed apps (check `/Applications`, `~/Applications`, and Spotlight).

Not looked at (out of scope): the encrypted knowledge base contents, and the word-matching implementation in `CMDirectoryFileFinderRequest`.

## Other scanners

- **Trash:** user trash, mounted volumes' `.Trashes`, Mail trash.
- **Unused disk images:** `.dmg`/`.iso` found via Spotlight, sized by `kMDItemPhysicalSize`, probably filtered by last-used date.
- **Downloads:** reads Safari, Chrome and Slack download history to flag old downloads.

## Rules for our build

1. Move to Trash (`FileManager.trashItem`), never hard delete.
2. Dry-run by default; show sizes before anything moves.
3. Skip anything owned by a running app.
4. No `lipo` thinning, no SIP-protected paths, no admin in v1.
5. Our own allow/deny list, written from scratch, versioned in the repo.
