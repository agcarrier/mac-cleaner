# Spruce Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working Spruce.app with Smart Care, Cleanup, Space (lists) and the Applications uninstaller, all review-then-Trash on the existing engine.

**Architecture:** The engine (`MacCleanerCore`) gains thresholds, a shared preselection rule, stable finding IDs, progress, and an
installed-apps list. A new UI-free library, `SpruceKit`, holds the observable models (scan → review → clean state machine) so they
can be unit tested. The `Spruce` executable target is thin SwiftUI on top, bundled into a signed `.app` by a script.

**Tech Stack:** Swift 6 package (tools 6.0), SwiftUI + Observation, AppKit for icons and workspace, Swift Testing, fal.ai for the icon.

**Spec:** `docs/superpowers/specs/2026-10-16-mac-app-design.md` (design) and `SPEC.md` (cleaning rules).

## Global Constraints

- Builds and tests always use `--scratch-path ~/Library/Caches/MacCleaner/spm`; the repo is iCloud-synced.
- Minimum macOS 14, Apple Silicon. No third-party dependencies.
- Bundle ID `dev.andrewcarrier.spruce`, app name `Spruce`. The CLI stays `mac-cleaner` and must keep working.
- Nothing is permanently deleted: every clean goes through `perform(_:)` (Trash) and nothing else.
- Preselected (✓) = actionable and `.high`. ○ items start unchecked. `.report` items have no checkbox and are never acted on.
- No alerts, badges, scare copy, or automatic scans. Copy is calm and plain.
- Look: direction C. Sidebar with SF Symbols in colored rounded tiles; each tool view has a soft radial wash and large
  rounded-square glyph in its tool color; one pill-shaped primary button. System font, light and dark mode.
- Scans run off the main thread, show progress, and can be cancelled.

## Review Focus

1. **Files changed between scan and clean** (a cache already gone, an app the user just launched): the clean continues, and the
   item is reported as failed with the reason. Pinned in Task 2 (`partialFailureIsReported`) and Task 2 (`preflightBlocksClean`).
2. **Clean pressed twice, or during a scan:** only one clean runs; scanning can't be cleaned. Pinned in Task 2 (`cleanOnlyFromReview`).
3. **Cancel mid-scan:** back to idle with no results, so nothing stale can be cleaned. Pinned in Task 2 (`cancelDiscardsResults`).
4. **Everything unchecked:** Clean does nothing (the button is disabled, and the model ignores it). Pinned in Task 2 (`emptySelectionDoesNothing`).
5. **A root-owned app that can't be trashed:** the uninstall reports it and the UI offers "Show in Finder". Pinned in Task 2
   (`partialFailureIsReported` asserts the failure keeps its `Finding`); the button is in Task 5.

---

### Task 1: Engine: thresholds, preselection, IDs, progress, installed apps

**Files:**
- Modify: `Sources/MacCleanerCore/Scanners.swift` (Context, Finding, scan)
- Modify: `Sources/MacCleanerCore/Space.swift` (`scanDownloads`, `scanNodeModules` read thresholds)
- Modify: `Sources/MacCleanerCore/Uninstaller.swift` (extract `installedApps`, add `lastUsedDate`)
- Modify: `Sources/mac-cleaner/main.swift` (use `isActionable` / `isPreselected` instead of its local rules)
- Test: `Tests/MacCleanerCoreTests/MacCleanerCoreTests.swift`

**Interfaces:**
- Produces:
  - `public struct Thresholds: Sendable, Equatable { public var installerDays = 30; public var idleProjectDays = 60; public init(installerDays: Int = 30, idleProjectDays: Int = 60) }`
  - `Context.init(home: URL, installed: Set<String>, running: Set<String>, thresholds: Thresholds = .init())` and `public let thresholds: Thresholds`
  - `extension Finding: Identifiable { public var id: String }`: `"\(category.rawValue)|"` plus the action's paths joined by `"|"` for `.trash`,
    the args joined by `" "` for `.run`, and `title|detail` for `.report`.
  - `extension Finding { public var isActionable: Bool { get } /* false for .report */; public var isPreselected: Bool { get } /* isActionable && confidence == .high */ }`
  - `extension Finding: Equatable`, comparing `id` only.
  - `public func scan(_ categories: Set<Category>, _ c: Context, progress: @Sendable (Category) -> Void = { _ in }) -> [Finding]`:
    calls `progress` before each category; stops early (returns what it has) when `Task.isCancelled`.
  - `public func installedApps(home: URL) -> [AppInfo]`: the same top-level filter `findApps` uses today, sorted by `name` (case-insensitive). `findApps` calls it.
  - `public func lastUsedDate(_ url: URL) -> Date?`: Spotlight `kMDItemLastUsedDate` via `MDItemCreateWithURL`/`MDItemCopyAttribute`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func thresholdsAreParameters() throws {
    // Temp home with Downloads/New.pkg modified 3 days ago (same touch helper as spaceRules).
    let c = Context(home: home, installed: [], running: [], thresholds: Thresholds(installerDays: 2, idleProjectDays: 60))
    #expect(scanDownloads(c, now: now).first { $0.title == "New.pkg" }?.confidence == .high)
}

@Test func preselectionAndIDs() {
    let trash = Finding(category: .caches, title: "a", detail: "", size: 1, confidence: .high, action: .trash([URL(filePath: "/tmp/a")]))
    let low = Finding(category: .caches, title: "b", detail: "", size: 1, confidence: .low, action: .trash([URL(filePath: "/tmp/b")]))
    let report = Finding(category: .large, title: "c", detail: "d", size: 1, confidence: .high, action: .report)
    #expect(trash.isPreselected && !low.isPreselected && !report.isPreselected)
    #expect(!report.isActionable)
    #expect(trash.id == "caches|/tmp/a" && report.id == "large|c|d")
    #expect(Set([trash.id, low.id, report.id]).count == 3)
}
```

`Finding`'s memberwise init is internal; tests use `@testable import`, which already works.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`
Expected: compile errors (`Thresholds`, `isPreselected`, `id` not found).

- [ ] **Step 3: Implement the interfaces above.** `scanDownloads` uses `c.thresholds.installerDays` in place of `30`;
  `scanNodeModules` uses `c.thresholds.idleProjectDays` in place of `60`. In `main.swift`, replace the local `isReport`/`isSelected`
  closures with `isActionable`/`isPreselected` (keeping `--include-low`: selected = `isActionable && (isPreselected || includeLow)`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`
Expected: all tests pass (6 existing + 2 new).

- [ ] **Step 5: Check the CLI is unchanged**

Run: `swift build -c release --scratch-path ~/Library/Caches/MacCleaner/spm && ~/Library/Caches/MacCleaner/spm/release/mac-cleaner space | tail -2`
Expected: same output shape as before, ending in `Dry run: … would go to the Trash.`

- [ ] **Step 6: Commit** `git commit -am "Engine: thresholds, shared preselection rule, finding IDs, scan progress, installed apps"`

---

### Task 2: SpruceKit: the scan → review → clean model

**Files:**
- Modify: `Package.swift`: add `.target(name: "SpruceKit", dependencies: ["MacCleanerCore"])` and
  `.testTarget(name: "SpruceKitTests", dependencies: ["SpruceKit"])`
- Create: `Sources/SpruceKit/ScanModel.swift`
- Create: `Sources/SpruceKit/Live.swift`
- Test: `Tests/SpruceKitTests/ScanModelTests.swift`

**Interfaces:**
- Consumes: Task 1's `scan(_:_:progress:)`, `Finding.id`, `isActionable`, `isPreselected`, `Thresholds`, `perform(_:)`.
- Produces:

```swift
public typealias Scanner = @Sendable (_ progress: @escaping @Sendable (Category) -> Void) async -> [Finding]
public typealias Performer = @Sendable (Action) throws -> Void

public struct CleanFailure: Equatable { public let finding: Finding; public let message: String }  // Finding gets Equatable via id
public struct CleanSummary: Equatable { public let cleaned: Int; public let bytes: Int64; public let failures: [CleanFailure] }

@MainActor @Observable public final class ScanModel {
    public enum Phase: Equatable { case idle, scanning(Category?), review, cleaning, done(CleanSummary) }
    public private(set) var phase: Phase
    public private(set) var findings: [Finding]          // sorted by size, largest first
    public var selection: Set<Finding.ID>
    public var selectedBytes: Int64 { get }
    public var selectedFindings: [Finding] { get }
    public init(onlyPreselected: Bool = false, scanner: @escaping Scanner, performer: @escaping Performer = perform,
                preflight: @escaping @Sendable () -> String? = { nil })
    public func scan()                 // from idle/review/done; runs scanner in a Task; on completion → review with selection = preselected IDs
    public func cancel()               // scanning → idle; findings emptied
    public func toggle(_ id: Finding.ID)   // ignored for non-actionable findings
    public func clean() async          // only from review with a non-empty selection; preflight non-nil → stays in review, sets blockedReason
    public private(set) var blockedReason: String?
}
```

`Live.swift` (not unit tested; thin): `public func liveContext(thresholds: Thresholds, includeInstalled: Bool) -> Context`
(running IDs from `NSWorkspace.shared.runningApplications`, installed from `installedBundleIDs` when asked), and
`public func liveScanner(_ categories: Set<Category>, thresholds: @escaping @Sendable () -> Thresholds) -> Scanner`, which
builds the context and calls `scan` on a detached task. `includeInstalled` is false only when every category is in `Category.space`.
Also `public func isRunning(_ app: AppInfo) -> Bool` (bundle ID among `NSWorkspace.shared.runningApplications`, case-insensitive).

- [ ] **Step 1: Write the failing tests** in `ScanModelTests.swift`. Fixtures: `high`, `low`, `report` findings as in Task 1, and a
  `Recorder` actor or locked box that collects performed actions.

```swift
@Test @MainActor func preselectsOnlyHighActionable() async { /* scan with [high, low, report] → selection == [high.id] */ }
@Test @MainActor func onlyPreselectedFilters() async { /* onlyPreselected: true → findings == [high] */ }
@Test @MainActor func toggleIgnoresReports() async { /* toggle(report.id) → selection unchanged */ }
@Test @MainActor func emptySelectionDoesNothing() async { /* deselect all, clean() → phase == .review, recorder empty */ }
@Test @MainActor func partialFailureIsReported() async {
    // performer throws for `high`, succeeds for `low` (both selected)
    // → phase == .done(summary); summary.cleaned == 1; summary.failures.map(\.finding.id) == [high.id]; failure message non-empty
}
@Test @MainActor func cleanOnlyFromReview() async { /* clean() while idle or scanning → nothing performed; two concurrent clean() calls → each action performed once */ }
@Test @MainActor func cancelDiscardsResults() async { /* scanner suspends until released; cancel() → phase == .idle, findings empty, even after release */ }
@Test @MainActor func preflightBlocksClean() async { /* preflight returns "Quit Foo first." → phase stays .review, blockedReason == that, nothing performed */ }
@Test @MainActor func cleanActsOnlyOnSelection() async { /* select only low → recorder holds exactly low's action */ }
```

Wait for a scan with a small helper that polls `phase` until it isn't `.scanning` (bounded, e.g. 2 s).

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --scratch-path ~/Library/Caches/MacCleaner/spm --filter SpruceKitTests`
Expected: compile error (`ScanModel` not found).

- [ ] **Step 3: Implement `ScanModel` and `Live.swift`.** Run performer calls off the main actor (one at a time, largest first),
  then return to it to set `.done`. A cancelled scan's late results must be dropped: keep the scan `Task` and compare identity.

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`
Expected: all tests pass.

- [ ] **Step 5: Commit** `git commit -am "SpruceKit: scan-review-clean model with tests"`

---

### Task 3: The app shell: window, sidebar, look, Settings, bundling

**Files:**
- Modify: `Package.swift`: add `.executableTarget(name: "Spruce", dependencies: ["SpruceKit"])`
- Create: `Sources/Spruce/SpruceApp.swift`: `@main`, `WindowGroup` + `Settings` scenes, default size 900×600, min 760×520
- Create: `Sources/Spruce/Tool.swift`
- Create: `Sources/Spruce/Theme.swift`: `ToolHeader`, `PillButton`, `SidebarTile`
- Create: `Sources/Spruce/SettingsView.swift`
- Create: `tools/bundle-spruce.sh`
- Modify: `.gitignore` if needed (build output stays in `~/Library/Caches/MacCleaner`)

**Interfaces:**
- Consumes: Task 1's `Thresholds`.
- Produces:
  - `enum Tool: String, CaseIterable, Identifiable { case smartCare, cleanup, space, applications }` with
    `title`, `symbol`, `tint`, `subtitle`, exactly:

    | case | title | symbol | tint | subtitle |
    |---|---|---|---|---|
    | smartCare | Smart Care | `sparkles` | `.green` | One scan across everything. You review before anything moves. |
    | cleanup | Cleanup | `bubbles.and.sparkles` | `.orange` | Leftovers from deleted apps, caches, and broken launch items. |
    | space | Space | `chart.pie.fill` | `.indigo` | Package caches, old installers, idle projects, and your largest files. |
    | applications | Applications | `square.grid.2x2.fill` | `.blue` | Remove an app and everything it leaves behind. |

  - `struct ToolHeader: View { init(tool: Tool) }`: radial wash in `tool.tint` (opacity ~0.25 at top center, fading to the window
    background), a 72-pt rounded-square glyph (corner radius ~18, gradient in the tint, white SF Symbol), title, subtitle.
  - `struct PillButton: View { init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) }`: capsule, primary color fill.
  - `struct SidebarTile: View { init(tool: Tool) }`: 20-pt rounded square in the tint with a white symbol, plus the title.
  - `@AppStorage` keys `installerDays` (default 30) and `idleProjectDays` (default 60); `func currentThresholds() -> Thresholds` reads them.
  - Settings: two `Stepper`s (1…365 days) under a "Cleaning" section with one-line explanations; nothing else in phase 1.
- Bundle script `tools/bundle-spruce.sh`: same shape as Boudreaux's `tools/bundle.sh` (read it). Output `~/Library/Caches/MacCleaner/Spruce.app`,
  `CFBundleIdentifier` `dev.andrewcarrier.spruce`, `CFBundleName`/`CFBundleExecutable` `Spruce`, `CFBundleIconFile` `Spruce`
  (copy `art/Spruce.icns` only if it exists; Task 6 adds it), `LSMinimumSystemVersion` 14.0, no `LSUIElement`. Sign with the
  Apple Development identity when present, else ad-hoc, because Full Disk Access is tied to a stable signature. `--install` copies to `/Applications`.

The detail area shows `ToolHeader` plus a placeholder `Text` per tool in this task; Tasks 4 and 5 replace them.

- [ ] **Step 1: Build**

Run: `swift build -c release --scratch-path ~/Library/Caches/MacCleaner/spm`
Expected: `Build complete!` with no warnings from `Sources/Spruce`.

- [ ] **Step 2: Bundle and launch**

Run: `tools/bundle-spruce.sh && open ~/Library/Caches/MacCleaner/Spruce.app && sleep 2 && pgrep -x Spruce`
Expected: a PID is printed; `plutil -extract CFBundleIdentifier raw ~/Library/Caches/MacCleaner/Spruce.app/Contents/Info.plist` prints `dev.andrewcarrier.spruce`.

- [ ] **Step 3: Andrew checks the look** against the direction-C mockup: sidebar tiles, glow header, light and dark mode, Settings (⌘,) steppers.
  Agents can't screenshot his screen; ask him.

- [ ] **Step 4: Commit** `git add -A && git commit -m "Spruce: app shell, sidebar, direction-C look, Settings, bundle script"`

---

### Task 4: Smart Care, Cleanup and Space views

**Files:**
- Create: `Sources/Spruce/FindingsView.swift`: shared results list, used by all three tools
- Create: `Sources/Spruce/ScanToolView.swift`: header + state-driven body for a `ScanModel`
- Create: `Sources/Spruce/PermissionNote.swift`
- Modify: `Sources/Spruce/SpruceApp.swift`: an `@Observable AppState` (or `@State` in the root) owning one `ScanModel` per tool, so results survive switching tools within a session

**Interfaces:**
- Consumes: `ScanModel` (Task 2), `liveScanner` (Task 2), `Tool`, `ToolHeader`, `PillButton`, `currentThresholds()` (Task 3), `canReadContainers(home:)`.
- Model wiring, exactly:
  - Smart Care: `ScanModel(onlyPreselected: true, scanner: liveScanner(Set(Category.scannable).union([.devcaches, .downloads]), …))`
  - Cleanup: `ScanModel(scanner: liveScanner(Set(Category.scannable), …))`
  - Space: `ScanModel(scanner: liveScanner(Set(Category.space), …))`
- `FindingsView`: grouped by `Category` (section title = `category.title`, with section total), rows show a checkbox
  (none for non-actionable), title, detail (secondary), size (`ByteCountFormatter`, `.file`). Clicking a row toggles it.
- `ScanToolView` per phase: idle → header + `PillButton("Scan")`; scanning → `ProgressView` with "Scanning <category.title>…" and a Cancel
  button; review → `FindingsView` + footer "N selected · X" + `PillButton("Clean")` disabled when the selection is empty;
  cleaning → progress; done → "Moved X to the Trash." plus any failures listed with their messages, and a "Scan Again" button.
  Review with nothing found → "Nothing to clean." (calm, no celebration copy).
- **Confirmation sheet** on Clean: title "Move N items to the Trash?", the exact list (title + size), total, buttons "Cancel" and
  "Move to Trash" (default). Only "Move to Trash" calls `clean()`.
- `PermissionNote`: shown in Smart Care and Cleanup when `canReadContainers(home:)` is false. Text: "Sandboxed apps were skipped
  because Spruce doesn't have Full Disk Access." Button "Open Privacy Settings" opens
  `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. Inline, secondary styling; never a modal.

- [ ] **Step 1: Build, bundle, launch** (commands as in Task 3, Steps 1–2). Expected: builds clean, app launches.

- [ ] **Step 2: Andrew runs Scan in each tool** and checks: progress names categories; Cancel returns to the start; Smart Care lists
  only ✓ items; ○ items in Cleanup/Space start unchecked; `·` items in Space have no checkbox; the sheet lists exactly the selected items.

- [ ] **Step 3: Planted-file clean test** (agent can do this): plant `~/Library/Preferences/dev.macclean.fakeapp.plist` and
  `~/Library/Saved Application State/dev.macclean.fakeapp.savedState/x`. Andrew scans Cleanup, unchecks everything except the two
  `dev.macclean.fakeapp` rows, and cleans. Expected: both paths gone (`ls` fails) and present in the Trash (Finder AppleScript, as the CLI tests did).

- [ ] **Step 4: Commit** `git add -A && git commit -m "Spruce: Smart Care, Cleanup and Space with review-then-Trash"`

---

### Task 5: Applications: list and uninstall

**Files:**
- Create: `Sources/Spruce/ApplicationsView.swift`
- Create: `Sources/Spruce/UninstallSheet.swift`

**Interfaces:**
- Consumes: `installedApps(home:)`, `lastUsedDate(_:)`, `allocatedSize(_:)`, `uninstallFindings(for:_:)`, `systemItems(for:)`,
  `AppInfo.isApple` (Task 1 / existing), `ScanModel` with `preflight` (Task 2), `FindingsView`, `PillButton`, `PermissionNote` (Task 4).
- List: searchable (`.searchable`, matches name or bundle ID), rows with `NSWorkspace.shared.icon(forFile:)`, name, last used
  ("Last used 3 months ago" via `RelativeDateTimeFormatter`, or "Never opened"), and size, which loads lazily per row on a background
  task and shows a placeholder until ready. Apple apps aren't listed.
- Selecting an app and pressing "Uninstall…" opens `UninstallSheet` with
  `ScanModel(scanner: { _ in uninstallFindings(for: app, liveContext(...)) }, preflight: { isRunning(app) ? "Quit \(app.name) first." : nil })`.
  It scans immediately and shows `FindingsView` (✓/○ rules apply). Below it, a "Needs your admin password" section lists `systemItems(for:)`,
  each with its command in a monospaced, selectable `Text` and a Copy button; never executed by Spruce.
- If the app is running when the sheet opens, the Uninstall button is disabled with "Quit <name> to uninstall it."
- After cleaning, if a failure's `finding.detail == "the app"`, show "Spruce couldn't move <name>.app. It may need an admin password."
  with a "Show in Finder" button (`NSWorkspace.shared.activateFileViewerSelecting([app.url])`).

- [ ] **Step 1: Build, bundle, launch.** Expected: clean build; Applications lists Andrew's apps alphabetically with icons; sizes fill in.

- [ ] **Step 2: Fake-app uninstall test** (agent prepares, Andrew clicks): build the signed fake app exactly as in the CLI test
  (`~/Applications/MacCleanFake.app`, bundle ID `dev.macclean.fakeapp`, app-group entitlement `TESTTEAM.dev.macclean.fakeapp`),
  plant its pref, container folder `~/Library/Containers/dev.macclean.fakeapp` (the container manager adopts it), and group folders
  `TESTTEAM.dev.macclean.fakeapp` and `TESTTEAM.dev.macclean`. Andrew uninstalls MacCleanFake in Spruce. Expected: app, pref, container and
  the app-named group are gone; `TESTTEAM.dev.macclean` (○) remains. Remove the leftover test folder afterwards.

- [ ] **Step 3: Refusal check:** with Claude or another open app selected, Uninstall is disabled with the quit message.

- [ ] **Step 4: Commit** `git add -A && git commit -m "Spruce: Applications list and uninstaller"`

---

### Task 6: App icon, install, and hand-off

**Files:**
- Create: `art/Spruce.icns`, `art/icon-options/*.png` (the generated options, kept for reference)
- Modify: `README.md`: a "Spruce app" section (bundle, install, Full Disk Access for Spruce.app)
- Modify: the vault page `projects/mac-cleaner.md`, then `~/.claude/brain/brain sync`

- [ ] **Step 1: Generate 4 icon options with fal.ai** (Andrew approved using his account). Use the fal MCP flow (`recommend_model`, then
  run). Brief: "macOS app icon, Apple Big Sur style, rounded-square squircle, a stylized spruce tree in soft gradient greens with
  gentle depth and a subtle glow on a light mint background, centered, no text, 1024×1024." Save each to `art/icon-options/`.

- [ ] **Step 2: Andrew picks one.** Show the options (SendUserFile or the browser companion) and wait for his choice.

- [ ] **Step 3: Make the .icns** from the chosen PNG: `sips` to an `.iconset` (16, 32, 128, 256, 512 at 1x and 2x), then
  `iconutil -c icns -o art/Spruce.icns`. If the image has a background outside the squircle, mask it to the squircle first.

- [ ] **Step 4: Bundle and install**

Run: `tools/bundle-spruce.sh --install && open /Applications/Spruce.app`
Expected: Spruce opens from `/Applications` with the new icon in the Dock.

- [ ] **Step 5: Andrew grants Full Disk Access to `/Applications/Spruce.app`**, quits and reopens it, and the permission note disappears from Cleanup.

- [ ] **Step 6: Final test run and commit**

Run: `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`
Expected: all tests pass. Then `git add -A && git commit -m "Spruce: app icon, install, docs" && git push`, and update the vault page.
