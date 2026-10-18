# Spruce Phase 6 Implementation Plan: Updater

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Updates view in the Applications tool. When Andrew clicks Check for Updates, Spruce finds apps with a newer version
and links to the right place: the App Store page, or the app itself (its own updater runs) plus release notes or its website.
It never downloads or installs anything.

**Architecture:** `MacCleanerCore/Updater.swift`, unit tested first: version comparison, the Sparkle appcast parser, the App Store
lookup parser, the Homebrew cask index, and `checkUpdates` with the network injected. The `Spruce` target adds an
Installed / Updates switch to the Applications toolbar and an `UpdatesView`.

**Tech Stack:** Swift 6, `URLSession`, `XMLParser`, `JSONSerialization`, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-16-mac-app-design.md`, tool 4 "Applications" → Updater, and Anti-goals.

## Calls made (builder's)

Sources, first match wins (on Andrew's Mac: 10 App Store apps, 9 Sparkle, most of the remaining 23 in Homebrew):
1. **App Store:** the app has `Contents/_MASReceipt`. `itunes.apple.com/lookup?bundleId=…&country=<region>` gives the version
   and store page. Apple's own apps return nothing there, so they show as "can't check".
2. **Sparkle:** `SUFeedURL` in Info.plist. The newest item with no `sparkle:channel` (betas) whose `minimumSystemVersion` this Mac
   meets. Compared the way Sparkle does: `sparkle:version` against `CFBundleVersion`; shown as `shortVersionString`.
3. **Homebrew:** `formulae.brew.sh/api/cask.json` (2 MB), matched by the app's file name. Skipped when the name matches more than
   one cask (`Buzz.app` matches two different products), for `@` variants (betas, LTS), deprecated or disabled casks, and
   `latest` versions. Text after a comma in a cask version (build hashes) is ignored.

Versions compare by their numeric parts (`1.14.4` > `1.8.10`; letters ignored). Nothing is "available" unless it's strictly newer.

## Global Constraints

Phase 1's constraints stand. Added for this phase:

- **No network unless clicked.** The first network use in Spruce. Nothing checks at launch or on a timer. Requests go only to
  Apple, each app's own feed, and Homebrew's API, and carry nothing but what the URL needs.
- **No false "update available".** Unparseable or ambiguous data means "can't check", never "update".
- Requests run in parallel (8 at a time), each with a 15 s timeout. One failure doesn't stop the rest.

## Review Focus

1. **Version maths.** Pinned by `versionOrder`.
2. **Betas and too-new macOS releases offered as updates.** Pinned by `appcastPicksNewestEligible`.
3. **Wrong Homebrew match.** Pinned by `caskIndexSkipsAmbiguous`.
4. **Source priority and failure handling** (offline feed, App Store with no result). Pinned by `checkUpdatesUsesRightSource`.

---

### Task 1: Core

**Files:** Create `Sources/MacCleanerCore/Updater.swift`; test `Tests/MacCleanerCoreTests/UpdaterTests.swift`.

**Interfaces (produces):** `isNewer(_:than:)`; `AppcastItem` + `parseAppcast(_:os:)`; `parseAppStoreLookup(_:)`;
`Cask` + `caskIndex(_:)`; `UpdateSource` (`.appStore`, `.sparkle`, `.homebrew`); `AvailableUpdate`; `UpdateReport`
(`available`, `upToDate`, `unchecked`); `checkUpdates(_:fetch:progress:) async -> UpdateReport`; `liveFetch`.

- [x] Failing tests for the four pins; run; implement; whole suite green.

### Task 2: The view

- `ApplicationsView`: Installed / Updates switch in the toolbar (same pattern as Space and My Clutter).
- Apple's own apps are left out of the check (they update through Apple, and the store lookup doesn't answer for them).
- `UpdatesView`: idle (explanation that it contacts Apple, the apps' own feeds and Homebrew; "Check for Updates" pill),
  checking ("Checked 12 of 40"), results (one row per update: icon, name, `1.8.10 → 1.14.4`, source; buttons "App Store" or
  "Open App" + "Release Notes"/"Website"), and a footer "N up to date · M can't be checked" with the unchecked names on hover.
  Results live in `AppState` for the session.

### Task 3: Build, bundle, hand-off

- [x] `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`: all green.
- [x] `tools/bundle-spruce.sh --install`.
- [ ] **Andrew checks on his Mac:**
  1. Applications → Updates → Check for Updates. It finishes in a few seconds.
  2. The list matches reality for a couple of apps (e.g. Obsidian, Chrome, Docker): open one with "Open App" and use its own
     Check for Updates.
  3. An App Store app with an update (if any) opens its App Store page.
  4. Nothing listed is a beta or an app you already updated.
- [ ] Commit on `spruce-phase-6-updater`; update the vault page and run `~/.claude/brain/brain sync`.

## Known limits

- Apps that set their Sparkle feed in code (not Info.plist), Apple's own apps, and apps outside Homebrew can't be checked.
- Homebrew sometimes lags a release by a day or two; then the app shows as up to date until it catches up.

## Live numbers (2026-10-18)

64 installed apps (helpers in subfolders included): 2.4 s, 11 updates (Blender, Discord, Docker, Chrome, NordPass from the App Store, Notion, Obsidian 1.8.10 → 1.14.4, Rectangle 0.89 → 2.0.3, Telegram, Warp, WhatsApp), 18 up to date. Rectangle confirmed by hand: build 95 installed, feed's newest 110.
