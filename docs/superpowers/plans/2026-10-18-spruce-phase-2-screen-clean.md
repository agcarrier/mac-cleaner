# Spruce Phase 2 Implementation Plan: Screen Clean

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Screen Clean tool that locks every keyboard and pointing device behind a full-screen dark overlay with a countdown,
so Andrew can wipe the keyboard, trackpad and screen. It unlocks on a key combo (default ⌃⌥⌘U) or by itself when the countdown ends.

**Architecture:** The rules that decide when the lock ends (does this key press match the combo, has the time run out) are pure
values in `SpruceKit`, unit tested first. The `Spruce` target holds the parts that need a real Mac: a `CGEventTap` that swallows
input, one borderless window per screen, the sidebar tool and Settings.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSWindow`, `NSEvent` for recording the combo), CoreGraphics event taps,
ApplicationServices (`AXIsProcessTrusted`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-16-mac-app-design.md`, tool 8 "Screen Clean", and the Settings and Permissions sections.

## Global Constraints

Phase 1's constraints stand (scratch path, macOS 14, no dependencies, no nagging, direction C). Added for this phase:

- **The lock must always end.** Three ways out, any one is enough: the combo, the countdown, and macOS itself disabling a tap
  whose callback stalls. The overlay is only shown after the tap exists, so a failed tap never leaves a window over the screen
  with nothing listening.
- The countdown runs on a main-run-loop timer that is independent of the tap; the tap callback does no work beyond a comparison.
- Accessibility is asked for only from the Screen Clean view, after a plain explanation, and only when Andrew clicks.
  No alert, no prompt at launch, no repeat.
- The combo must use at least two of ⌃ ⌥ ⇧ ⌘, so wiping the keyboard can't unlock it by accident.

## Review Focus

1. **Stuck locked.** The tap is created before the overlay appears, `stop()` is idempotent, and the timer calls it whatever the tap
   is doing. Pinned by `expiresAtDuration`.
2. **Unlock by accident while wiping.** The combo needs exact modifiers: extra modifiers don't match, missing ones don't match,
   and a combo with fewer than two modifiers is refused in Settings. Pinned by `exactModifiersOnly` and `needsTwoModifiers`.
3. **Caps Lock, Fn or the numeric-pad flag on.** Those flags are ignored, so the combo still works. Pinned by `ignoresLockAndDeviceFlags`.
4. **Bad stored settings** (hand-edited defaults, an old format): fall back to ⌃⌥⌘U and 2 minutes. Pinned by `rawValueRoundTrip`
   and `durationIsClamped`.

---

### Task 1: SpruceKit: the combo and the countdown

**Files:**
- Create: `Sources/SpruceKit/ScreenLock.swift`
- Test: `Tests/SpruceKitTests/ScreenLockTests.swift`

**Interfaces (produces):**
- `public struct KeyCombo: Equatable, Sendable, RawRepresentable` with `keyCode: Int64`, `modifiers: CGEventFlags` (only
  ⌃ ⌥ ⇧ ⌘ kept), `key: String` (what to show, e.g. `"U"`).
  - `static let standard` = ⌃⌥⌘U (`kVK_ANSI_U` is 32).
  - `matches(keyCode:flags:)`: same key code and exactly the same four modifier flags; every other flag is ignored.
  - `isValid`: at least two modifiers.
  - `display`: modifiers in Apple's order ⌃⌥⇧⌘, then `key`.
  - `rawValue`: `"keyCode:modifiers:key"`; `init?(rawValue:)` returns nil for anything else or an invalid combo.
- `public struct ScreenLock: Sendable` with `combo`, `ends: Date`.
  - `init(combo:duration:start:)` clamps `duration` to `ScreenLock.durations` (30 s … 10 min).
  - `remaining(at:) -> TimeInterval` (never negative), `isExpired(at:)`, `countdown(at:) -> String` ("1:05", rounded up so it
    reads 0:01 until the end, then 0:00).
  - `static let defaultDuration: TimeInterval = 120`.

- [ ] **Step 1: Write the failing tests** (`ScreenLockTests.swift`): standard combo matches ⌃⌥⌘ + 32 only; extra ⇧ or missing ⌥
  doesn't match; Caps Lock / Fn / numeric-pad flags are ignored; a different key code doesn't match; validity needs two modifiers;
  display is `⌃⌥⌘U`; raw value round-trips and junk returns nil; remaining/expired/countdown at start, mid-way and past the end;
  duration clamps.
- [ ] **Step 2: Run, expect a compile failure** (`swift test --scratch-path ~/Library/Caches/MacCleaner/spm --filter ScreenLock`).
- [ ] **Step 3: Implement `ScreenLock.swift`.**
- [ ] **Step 4: Run the whole suite, expect all passing.**

### Task 2: The lock itself

**Files:**
- Create: `Sources/Spruce/ScreenCleaner.swift`: `@MainActor @Observable final class ScreenCleaner`
  - `start(combo:duration:) -> String?` returns why it couldn't start (no Accessibility, tap refused) or nil.
    Creates a `.cghidEventTap` head-insert tap over every event type, then one borderless, black, `.screenSaver`-level window
    per `NSScreen`, hides the cursor, and starts a 0.25 s timer that updates `now` and calls `stop()` once expired.
  - The tap callback: re-enables itself on `tapDisabledByTimeout`/`ByUserInput`; on a key-down matching the combo, schedules
    `stop()` on the main queue; returns `nil` (swallows) for every event while locked.
  - `stop()`: idempotent; removes the tap and its run-loop source, closes the windows, shows the cursor, invalidates the timer.
- Create: `Sources/Spruce/ScreenCleanView.swift`: header, a short "how it works" card (combo + timeout from Settings),
  and either the Accessibility explanation with "Allow Accessibility…" (calls `AXIsProcessTrustedWithOptions` with the prompt
  option, then opens the Accessibility pane), or the "Start Screen Clean" pill. Rechecks trust when the app becomes active.
  The overlay content: big countdown, "Locked for cleaning", "Press ⌃⌥⌘U to unlock".

### Task 3: Sidebar and Settings

- Modify `Tool.swift`: `case screenClean`, "Screen Clean", symbol `keyboard`, tint `.gray`,
  subtitle "Lock the keyboard and trackpad so you can wipe them and the screen."
- Modify `SpruceApp.swift`: route `.screenClean` to `ScreenCleanView`; one `ScreenCleaner` in `AppState`.
- Modify `SettingsView.swift`: a "Screen Clean" section with the combo recorder (click "Change…", press the new combo; refused
  with a one-line reason unless it has two modifiers; "Reset" back to ⌃⌥⌘U) and a picker for the timeout
  (30 s, 1, 2, 3, 5, 10 min). Keys `unlockCombo` (KeyCombo raw value) and `screenCleanSeconds`.

### Task 4: Build, bundle, hand-off

- [ ] `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`: all green.
- [ ] `tools/bundle-spruce.sh --install`.
- [ ] **Andrew checks on his Mac** (an agent can't grant Accessibility or press real keys for him):
  1. Open Spruce → Screen Clean → Allow Accessibility…, switch Spruce on in System Settings, come back.
  2. Start Screen Clean. Typing, clicking, scrolling and swipes do nothing; the countdown runs.
  3. Press ⌃⌥⌘U: it unlocks at once.
  4. Settings (⌘,) → Screen Clean → set 30 seconds, start again, touch nothing: it unlocks itself at 0:00.
- [ ] Commit on `spruce-phase-2-screen-clean`; update the vault page and run `~/.claude/brain/brain sync`.

## Known limits (not fixable from an app)

- The power button / Touch ID and the keyboard brightness keys handled in firmware can't be blocked. Pressing power briefly may
  sleep the display; the lock is still running when it wakes.
- Secure input (a password field focused in another app) doesn't apply here: Spruce's overlay is frontmost.
