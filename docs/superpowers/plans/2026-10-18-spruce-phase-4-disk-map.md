# Spruce Phase 4 Implementation Plan: Space disk map

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Disk Map inside the Space tool, like CleanMyMac's Space Lens. Pick a folder (Home by default), Spruce measures it,
and a treemap shows what's inside by size. Click a folder to go into it, use the breadcrumb to come back out, and right-click
anything to reveal it in Finder.

**Architecture:** `MacCleanerCore/DiskMap.swift` holds the measuring walk (`diskTree`) and the squarified treemap layout
(`treemap`), both unit tested first. `SpruceKit/DiskMapModel.swift` is the idle → measuring → map state machine with the
drill-down path, also tested. The `Spruce` target draws it: `SpaceView` puts a Findings / Disk Map switch in the toolbar.

**Tech Stack:** Swift 6 structured concurrency (`TaskGroup`), Foundation URL resource values, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-16-mac-app-design.md`, tool 3 "Space" (the visual disk map), and Anti-goals.

## Calls made (builder's)

- **Treemap, not sunburst.** Rectangles use the whole area, so small windows still show many readable items. Squarified layout
  (Bruls, Huizing, van Wijk) keeps tiles close to square.
- **View only.** The map never deletes anything. Anti-goal 1 says every clean goes through a reviewed path the tests cover;
  the map's job is to show where space went. It reveals items in Finder.
- **One level at a time.** Each screen shows the current folder's children. Drilling is a click.

## Global Constraints

Phase 1's constraints stand. Added for this phase:

- **Responsive on a full home folder** (~290 GB, ~2.2 M items on Andrew's Mac, 45 s for `du`; Spruce's walk takes ~19 s). The walk runs off the main
  actor, folders in the top three levels are measured in parallel, the UI shows a running item count, and Cancel stops it.
  The result lives in `AppState`, so switching tools doesn't throw it away.
- **Bounded memory.** Each folder keeps at most 60 children of 1 MB or more. The rest become one "N smaller items" tile that
  still counts toward the size. Sizes are exact; only the detail is trimmed.
- Symlinks are never followed, and other volumes (mount points) are skipped, so nothing is counted twice or loops.
- Folders macOS won't let Spruce read count as their visible size (usually 0). No errors are shown for them.

## Review Focus

1. **Wrong totals.** A folder's size is the sum of everything under it, including what was lumped. Pinned by `treeSizesAddUp`.
2. **Loops and double counting.** Symlinks to folders count as the link only (`symlinksNotFollowed`), and a hard-linked file
   counts once, like `du` (`hardLinksCountedOnce`). Found live: Spotlight's index keeps 84,000 files with up to 8 links each,
   which first made Home read 339 GB against `du`'s 290 GB. After the fix the two agree to 4 MB.
3. **Stale results after Cancel.** Cancel returns to idle with no tree. Pinned by `cancelDiscardsMap`.
4. **Layout bugs** (gaps, overlaps, tiles outside the view, zero-size items drawn). Pinned by `treemapTilesTheRect`.

---

### Task 1: Core: the walk and the layout

**Files:** Create `Sources/MacCleanerCore/DiskMap.swift`; test `Tests/MacCleanerCoreTests/DiskMapTests.swift`.

**Interfaces (produces):**
- `DiskNode` (`url`, `name`, `size`, `isDirectory`, `children` largest first, `lumped` = how many small items a lump tile stands for).
- `ItemCounter` (lock-protected count the UI polls for progress).
- `diskTree(_:counter:) async -> DiskNode?` (nil when cancelled).
- `treemap(_ sizes: [Double], in: CGRect) -> [CGRect]` (sizes largest first; one rect per size, `.zero` for sizes ≤ 0).

- [x] Step 1: failing tests (`treeSizesAddUp`, `smallItemsAreLumped`, `symlinksNotFollowed`, `hardLinksCountedOnce`, `cancelledWalkReturnsNil`, `treemapTilesTheRect`, `treemapEdgeCases`).
- [x] Step 2: run, expect a compile failure.
- [x] Step 3: implement.
- [x] Step 4: whole suite green.

### Task 2: SpruceKit: `DiskMapModel`

`@MainActor @Observable`: `phase` (`.idle`, `.measuring(URL)`, `.map`), `itemsMeasured`, `root`, `path` (drill stack),
`current`; `map(_:)` (ignored while measuring), `cancel()`, `open(_:)` (folders with children only), `up(to:)`, `reset()`.
The tree function is injected for tests.

- [x] Failing tests (`mapThenDrill`, `cancelDiscardsMap`, `openIgnoresFilesAndLumps`), then implement.

### Task 3: The view

- `SpaceView`: Findings / Disk Map segmented control in the toolbar; Findings is the existing `ScanToolView`.
- `DiskMapView`: idle (header, "Map Home Folder" pill, "Choose Folder…"), measuring (count, Cancel), map (breadcrumb,
  treemap, a footer naming the hovered tile with its size and share, "New Map").
- Tiles: folders in Space's indigo, files gray, the lump tile faint. Name and size drawn when the tile is big enough.
  Click a folder to open it; right-click → Reveal in Finder.

### Task 4: Build, bundle, hand-off

- [x] `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`: all green.
- [x] `tools/bundle-spruce.sh --install`.
- [x] **Andrew checks on his Mac** (passed 2026-10-18, all five steps):
  1. Spruce → Space → Disk Map → Map Home Folder. The count climbs, the window stays usable (switch tools and back), and the map appears.
  2. The biggest tiles make sense (compare with `du -sh ~/* ~/.[a-z]* | sort -h | tail`).
  3. Click into a folder, then two more levels; the breadcrumb takes you back.
  4. Right-click a tile → Reveal in Finder.
  5. New Map → Choose Folder… → pick a small folder; Cancel a home-folder scan midway and confirm it returns to the start.
- [x] Commit on `spruce-phase-4-disk-map`; update the vault page and run `~/.claude/brain/brain sync`.

## Known limits

- APFS clones share blocks but are separate files, so each clone counts in full (`du` does the same). A folder of clones can look
  bigger than the space it really uses.
- iCloud files that are only in the cloud take no local space and show as tiny.
