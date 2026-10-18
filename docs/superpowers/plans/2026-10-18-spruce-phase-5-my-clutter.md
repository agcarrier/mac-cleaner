# Spruce Phase 5 Implementation Plan: My Clutter

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A My Clutter tool with two scans over chosen folders (default Desktop, Documents, Downloads, Pictures):
**Duplicates** (exact copies; one copy in each group is kept and can't be selected, loose extra copies start checked) and
**Similar Photos** (visually alike images found with Apple's Vision framework; nothing starts checked). Both go through the
existing review → confirm → Trash flow.

**Architecture:** `MacCleanerCore/Clutter.swift`: the folder walk, `findDuplicates` (size → first-64 KB hash → full hash) and
`findSimilarPhotos` (Vision feature prints, greedy clustering), returning ordinary `Finding`s with a new `group` key. Unit tested
first. `ScanModel` keeps each group together when sorting. `FindingsView` shows one section per group. The `Spruce` target
adds the tool, a toolbar switch between the two scans, and a folder list.

**Tech Stack:** Swift 6, CryptoKit (SHA-256), Vision (`VNGenerateImageFeaturePrintRequest`), SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-16-mac-app-design.md`, tool 6 "My Clutter", and Anti-goals.

## Calls made (builder's)

- **Which copy is kept:** the one not in Downloads, then the oldest (creation date), then the shortest path. Shown as a
  "Kept" row with no checkbox, so a group can never lose every copy.
- **Only loose copies start checked (✓)**: copies in Downloads, or in the same folder as the kept file. Copies in other folders
  start unchecked (○). Changed after the first live run: Andrew's Documents holds Divinity campaign data and two site kits
  that keep the same files in several folders on purpose, and trashing one would break them.
- **Similar photos are always ○.** Grouped greedily: a photo joins a group when it is close to that group's first photo, so
  loose chains don't merge everything. Photos are compared within the same folder only.
- **Skipped while walking:** hidden files and folders, packages (apps, Photos libraries), `Library`, `node_modules`,
  folders inside a git repository (copies there are usually on purpose and trashing one breaks the project), iCloud files that
  aren't downloaded (reading them would download them), and files under 100 KB.

## Global Constraints

Phase 1's constraints stand. Added for this phase:

- Every clean re-runs the scan first (the existing `ScanModel` rule), so a copy is trashed only if it is still a duplicate and
  its kept copy still exists. Similar photos are rechecked the same way.
- Nothing is read that isn't on disk already: dataless iCloud files are skipped, never downloaded.
- Nothing starts automatically. Changing the folder list drops old results.

## Review Focus

1. **Losing the last copy.** The kept copy is report-only. If it disappears before the clean, the rescan picks a new kept copy
   and that one is skipped as "changed". Pinned by `duplicatesKeepOne` and `keptCopyRules`. Copies that may belong to a project
   or an app start unchecked: `onlyLooseCopiesPreselected`.
2. **False duplicates.** Same size and same first 64 KB but different later bytes are not duplicates. Pinned by `fullHashDecides`.
3. **Wandering into places that break things** (repos, bundles, Library, cloud-only files). Pinned by `walkSkips`.
4. **Groups split apart in the list.** Pinned by `groupsStayTogether` (SpruceKit).
5. **Similar photo threshold.** A resized/recompressed copy matches, a different picture doesn't. Pinned by `similarPhotosGroup`.

---

### Task 1: Core: walk and duplicates

**Files:** Create `Sources/MacCleanerCore/Clutter.swift`; test `Tests/MacCleanerCoreTests/ClutterTests.swift`.
Modify `Scanners.swift`: `Category` gains `.duplicates` and `.similar`; `Finding` gains `group: String?` (default nil).

- [x] Failing tests: `walkSkips`, `duplicatesKeepOne`, `keptCopyRules`, `fullHashDecides`, `onlyLooseCopiesPreselected`; run; implement; whole suite green.

### Task 2: Core: similar photos

- [x] Failing test `similarPhotosGroup` (draws test images with CoreGraphics: a picture, the same picture scaled and saved as
  JPEG, and a different picture); implement; green. Threshold 0.45, calibrated on the AAVA foster photos (same animal
  0.22–0.45, a 600 px quality-50 copy 0.43, different animals mostly above 0.45).

### Task 3: SpruceKit and the list

- `ScanModel.finishScan` sorts groups by their total size and keeps members together, kept copy first. Test `groupsStayTogether`.
- `FindingsView`: findings with a `group` get one section each, titled by the group's first item, with the extra size in the header.
- `Live.swift`: `liveClutterScanner(_:folders:)`.

### Task 4: The tool

- `Tool.myClutter`, "My Clutter", `doc.on.doc.fill`, teal, after Performance. Toolbar switch Duplicates / Similar Photos,
  each its own `ScanModel` in `AppState`. A folder row under the header (Add Folder…, remove, Reset), stored in UserDefaults
  key `clutterFolders`; changing it resets both models.

### Task 5: Build, bundle, hand-off

- [x] `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`: all green.
- [x] `tools/bundle-spruce.sh --install`.
- [x] **Andrew checks on his Mac** (passed 2026-10-18; step 3 first failed, fixed by the Trash fallback below, then passed):
  1. Make a test folder: `mkdir -p ~/Desktop/dupetest && cp ~/Downloads/<some file over 100 KB> ~/Desktop/dupetest/a && cp ~/Desktop/dupetest/a ~/Desktop/dupetest/b`.
  2. My Clutter → Duplicates → Scan. The dupetest group shows one "Kept" row (green shield) and one checked copy. Groups
     spread across project folders (e.g. the site-kit stock files) show their copies unchecked.
  3. Clean → confirm → the copy is in the Trash, the kept file is still there.
  4. Similar Photos → Scan. Groups look like real near-duplicates; nothing is checked.
  5. Remove Documents from the folder list, then Reset: results clear each time.
- [x] Commit on `spruce-phase-5-my-clutter`; update the vault page and run `~/.claude/brain/brain sync`.

## Found in the hands-on check

Cleaning `b.bin` failed with "you don't have permission to access it". `FileManager.trashItem` refuses files another app created
(they carry `com.apple.provenance`; here, files made in Claude's terminal pane), while a plain move into `~/.Trash` works.
`perform` now falls back to that move, on the same volume only, with a free name ("b 2.bin"). It covers every clean, not just
My Clutter. Pinned by `trashFallsBackToMovingIntoTrash`; proven on a real terminal-made file. Finder's "Put Back" doesn't know
where such a file came from.

## Known limits

- Similar photos compares within each folder only; near-duplicates split across folders aren't grouped.
- The Photos library is out of scope (spec).

## Live numbers (2026-10-18, Andrew's four default folders)

682 files over 100 KB after the skips; duplicates in 0.2 s (40 groups, 100 extra copies, 123 MB); similar photos in 2.3 s (53 groups, 160 photos).
