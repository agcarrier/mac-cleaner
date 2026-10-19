# Spruce Phase 7 Implementation Plan: Menu bar monitor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An optional menu bar item, off by default and switched on in Settings, that shows CPU use at a glance and, when
clicked, CPU, memory and free disk space with small bars. It must use negligible CPU itself.

**Architecture:** `SpruceKit/SystemStats.swift` holds the readers (Mach `host_statistics` for CPU ticks and VM pages, URL
resource values for the disk) and the pure maths (CPU share from two tick samples, memory used from page counts), unit tested
first. The `Spruce` target adds a SwiftUI `MenuBarExtra` whose `isInserted` follows the Settings toggle, and a small
`SystemMonitor` that samples on a timer only while the item is shown.

**Tech Stack:** Swift 6, Mach host APIs (`host_statistics`, `host_statistics64`), SwiftUI `MenuBarExtra` (macOS 13+), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-16-mac-app-design.md`, tool 9 "Menu bar monitor", Settings, and Anti-goals 2 and 3.

## Calls made (builder's)

- **What the menu bar shows:** a gauge symbol and CPU percent. Memory and disk go in the panel, so the item stays narrow.
- **Memory used** = app memory (internal − purgeable pages) + wired + compressed, the same parts Activity Monitor adds up.
- **Disk free** = the startup volume's "available for important usage" (what Finder shows, purgeable space included).
- **Sampling:** CPU and memory every 3 s, disk every 30 s, and only while the item is in the menu bar. Off means no timer at all.
- No alerts, colors that warn, or "your Mac is slow" copy. Just numbers.
- Only while Spruce is running. Opening Spruce at login is not in this phase.

## Review Focus

1. **Wrong CPU numbers** (first sample, a counter wrap after long uptime). Pinned by `cpuShare`.
2. **Memory maths.** Pinned by `memoryUsedAddsTheRightParts`; readers sanity-checked live by `liveReadersArePlausible`.
3. **Cost.** A sample must take well under a millisecond; checked by `sampleIsCheap` (1,000 samples).
4. **Off really means off.** Sampling lives in the menu bar label's `.task`; with the item removed there's no label and no task.

---

### Task 1: SpruceKit readers and maths

**Files:** Create `Sources/SpruceKit/SystemStats.swift`; test `Tests/SpruceKitTests/SystemStatsTests.swift`.

**Interfaces (produces):** `CPUTicks` (`busy`, `total`), `cpuShare(from:to:) -> Double`, `memoryUsed(internal:purgeable:wired:compressed:pageSize:)`,
`readCPUTicks()`, `readMemory() -> (used, total)?`, `readDisk() -> (free, total)?`.

- [x] Failing tests (`cpuShare`, `memoryUsedAddsTheRightParts`, `liveReadersArePlausible`, `sampleIsCheap`); implement; green.

### Task 2: The menu bar item

- `SettingsView`: section "Menu bar" with "Show CPU, memory and free disk in the menu bar" (key `menuBarMonitor`, default off).
- `SystemMonitor` (`@MainActor @Observable`): `cpu`, `memory`, `disk`; `run()` is an async loop started by the label's `.task`,
  so SwiftUI cancels it when the item leaves the menu bar. No `Timer`, nothing to forget to stop.
- `SpruceApp`: `MenuBarExtra(isInserted:)` bound to the setting, `.window` style. Label: gauge symbol + CPU %. Panel: three rows
  with a thin bar each, then "Open Spruce". The monitor starts and stops with the setting.

### Task 3: Build, bundle, hand-off

- [x] `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`: all green.
- [x] `tools/bundle-spruce.sh --install`.
- [ ] **Andrew checks on his Mac:**
  1. Spruce has nothing in the menu bar at first.
  2. Settings (⌘,) → Menu bar → switch on: the gauge and CPU % appear; click it for CPU, memory and disk.
  3. Compare with Activity Monitor (CPU and Memory tabs) and Finder's free space: close enough.
  4. Activity Monitor → Spruce's own CPU stays around 0–1 % with only the menu bar item open.
  5. Switch it off: the item disappears.
- [ ] Commit on `spruce-phase-7-menu-bar`; update the vault page and run `~/.claude/brain/brain sync`.

## Known limits

- The item lives only while Spruce runs. Quitting Spruce removes it; a later phase could add "Open at login".
