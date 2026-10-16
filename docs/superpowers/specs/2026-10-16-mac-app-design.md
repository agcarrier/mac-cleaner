# Spruce: design

2026-10-16. **Spruce** ("spruce up your Mac") is a native macOS app on top of the existing `MacCleanerCore` engine.
Bundle ID `dev.andrewcarrier.spruce`, matching Andrew's other app (`dev.andrewcarrier.boudreaux`). The CLI keeps its `mac-cleaner` name. Read with [SPEC.md](../../../SPEC.md), which holds the
cleaning rules the engine already enforces and tests.

## Why

Andrew didn't want to pay for CleanMyMac, so the CLI was built from a clean-room teardown of it. The CLI now works and has cleaned
his real Mac (about 400 MB of leftovers and 24 GB of package caches) without a mistake. The app is the next step: CleanMyMac's
breadth in an Apple-feeling window. It's for Andrew now and may be shared with others later, so nothing should assume a
single user's accounts or paths.

## Goals

- CleanMyMac's feature set minus malware protection (full list under **Tools**).
- Looks and feels like an app Apple could ship.
- The CLI keeps working; the app and CLI share one engine and one set of rules.

## Anti-goals (from Andrew, in his order)

1. **Deleting something that shouldn't be deleted.** This outranks every other goal. Concretely:
   - Nothing is ever permanently deleted. Files go to the Trash; services' own trash for cloud and mail.
   - Only items the engine is sure about are pre-checked (the ✓ rules in SPEC.md). Uncertain items (○) are shown unchecked.
     Report-only items (·) and admin-only items have no checkbox at all.
   - Every clean is preceded by a review screen listing exactly what will move, with sizes.
   - The app never calls a cleaning path the CLI's tests don't cover. New rules get tests before UI.
2. **Nagging.** No alerts, badges, scare banners ("Your Mac is at risk!"), upsell-style prompts, or automatic scans, unless the user
   turns on an option that implies them. No fake "speed up" or "free RAM" claims.
3. **Heaviness.** Native SwiftUI only; no web views, Electron, or analytics. Nothing runs in the background unless the user enables
   the menu bar monitor. Scans run off the main thread with live progress and can be cancelled. Launch to usable window should feel instant.

## Non-goals

- Malware scanning or real-time protection (deliberately out of scope).
- Proton Mail (Andrew's own mail): Proton has no API for this; its paid Bridge is out of scope.
- Mac App Store distribution. A cleaner can't run sandboxed.
- Cleaning on a schedule or without a review step.

## Look and feel

Andrew picked **direction C, "native with a glow"** from three mockups:
- Standard macOS sidebar (`NavigationSplitView`) with SF Symbols in small colored rounded tiles, like System Settings.
- Each tool's detail view has its own soft radial color wash at the top and a large rounded-square glyph in that tool's color,
  like Apple's newer apps (Journal, Freeform). Body content is native lists, `Form`s, and cards with hairline borders.
- Primary action is one pill button (Scan, then Clean). Light and dark mode both supported. System font only.
- **App icon:** a spruce tree, generated with fal.ai (Andrew gave permission to use his account), in Apple's current icon
  style (rounded square, soft depth, green on the green Smart Care glow). Generate a few options and let Andrew pick. No other generated imagery is required. Tool art is SF Symbols plus color.

The mockup is in `.superpowers/brainstorm/` (gitignored) if a reference is needed.

## Tools (sidebar order)

Tool color in brackets is the builder's call, unless Andrew objects.

1. **Smart Care** [green]: one Scan across the safe parts of Cleanup and Space, a combined review list, one Clean. The default view.
2. **Cleanup** [orange]: the CLI's scan: leftovers from deleted apps, app caches, broken launch agents, Xcode junk.
3. **Space** [indigo]: the CLI's `space` scan (package caches, old installers, idle `node_modules`, largest files) plus a
   **visual disk map** like CleanMyMac's Space Lens. You pick a folder, it shows sizes as an interactive chart, and you drill down.
   Builder picks the chart (sunburst or treemap). It must stay responsive on a full home folder.
4. **Applications** [blue]:
   - Installed apps with size and last-used date; **uninstall** using the CLI's uninstaller rules, including its system-wide
     report-only items with their `sudo` commands.
   - **Updater:** finds apps with a newer version. v1 detects and links (opens the app's own updater, the App Store page, or the
     download page). It does not download or install updates itself. Sources are the builder's call; candidates are Sparkle
     appcast feeds (`SUFeedURL` in the app's Info.plist), the Mac App Store lookup API, and Homebrew's cask API.
5. **Performance** [pink]: login items and background items (user launch agents can be disabled or enabled; others link to
   System Settings → Login Items), plus a few maintenance actions (flush DNS cache, rebuild Spotlight index, and similar). Any
   action that needs admin asks for the password only when the user clicks that action.
6. **My Clutter** [teal]:
   - **Duplicates:** exact duplicates in chosen folders (default: Desktop, Documents, Downloads, Pictures), matched by size,
     then a partial hash, then a full hash. In each group one copy is kept unchecked; which one is the builder's call
     (e.g. the oldest, or the one in the most "home" location), shown clearly.
   - **Similar photos:** visually similar images in the same folders, using Apple's Vision framework. Always ○ (unchecked);
     the user picks. The Photos library itself is out of v1.
7. **Cloud & Mail** [sky]: for Google Drive, Dropbox, OneDrive, Gmail, and Outlook. Finds large or old files and old large
   attachments, and moves picks to that service's trash. Each needs a developer app registration (OAuth client) with that
   company. The app must let a user enter their own client credentials, and must not ship anyone's secrets.
   Lowest priority; built last.
8. **Screen Clean** [gray]: locks the keyboard and trackpad so you can wipe them and the screen.
   - Unlock with a key combo, **default ⌃⌥⌘U**, configurable in Settings.
   - **Auto-unlock after 2 minutes** (configurable) as a failsafe, with a visible countdown.
   - Shows a full-screen dark overlay while locked (helps when wiping the screen).
   - Needs the macOS Accessibility permission, requested the first time the mode is used, with a plain explanation.
9. **Menu bar monitor**: off by default; turned on in Settings. Shows CPU, memory, and free disk at a glance. Must use
   negligible CPU itself.

**Settings:** the unlock combo and timeout, the age thresholds the CLI hard-codes today (installers 30 days, node_modules
60 days), the menu bar toggle, cloud credentials.

## Permissions

- **Full Disk Access** is needed for sandboxed apps' data (`~/Library/Containers`, `Group Containers`). Without it the app
  still works and says, in a calm inline note, what was skipped and how to grant access. This is a note, not a nag.
  Detection already exists (`canReadContainers`).
- **Accessibility** is needed only for Screen Clean.
- **Admin:** never at launch, only when the user clicks an admin-only action.

## Engine changes the app will need

The builder decides the details; these are the known gaps.
- Scans are synchronous today. They need progress reporting and cancellation for the UI.
- Thresholds are constants. They need to become parameters, so Settings can change them.
- New engine features (duplicates, similar photos, disk map, updater, login items, cloud) go in `MacCleanerCore` (or
  sibling libraries) with unit tests, so the CLI can gain them too.

## Build and distribution

- Same Swift package; the app is a new executable target, bundled into a `.app` by a script. Builds use a scratch path outside
  the iCloud-synced repo (`~/Library/Caches/MacCleaner/spm`), the same gotcha as Andrew's Boudreaux app.
- Personal use now: ad-hoc signed and installed to `/Applications`. Sharing later: Developer ID signing and notarization
  (needs the paid Apple Developer Program), not the App Store.
- Minimum macOS: builder's call. Andrew runs macOS 27 on Apple Silicon. Don't go lower than the core's macOS 14 without a reason.

## Phases

Each phase ends with something Andrew can open and use.
1. **Shell:** app window, sidebar, direction-C styling, app icon, Settings, permission notes. Smart Care, Cleanup, Space
   (lists only), and the Applications uninstaller wired to the existing engine, with review-then-Trash.
2. **Screen Clean.**
3. **Performance.**
4. **Space disk map.**
5. **My Clutter** (duplicates, then similar photos).
6. **Updater.**
7. **Menu bar monitor.**
8. **Cloud & Mail.**

## Calls made while writing this (Claude's, for Andrew to check)

- **Smart Care = the CLI's ✓ items** from Cleanup plus Space's package caches and old installers, so the same 24 GB-style caches
  Andrew already cleaned with the CLI come pre-checked. ○ and · items stay out of Smart Care; they're in the individual tools.
- **Screen Clean blocks all keyboards and pointing devices**, built-in and external, not just the built-in ones.
- **Root-owned apps that can't be trashed** (some installer-based apps) get a "Drag to Trash in Finder" fallback, as the CLI prints today.
- **Last scan results aren't kept between launches** in phase 1; each visit starts fresh. History and stats can come later.

## Left to the builder

Tool colors, the disk-map chart type, which duplicate copy is kept, updater sources, maintenance-action list, minimum macOS,
internal architecture, and how the engine reports progress. Any of these can be revisited with Andrew after he sees it working.
