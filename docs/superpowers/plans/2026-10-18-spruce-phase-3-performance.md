# Spruce Phase 3 Implementation Plan: Performance

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Performance tool that lists what starts with the Mac (apps that open at login, apps' background helpers, launch agents
and daemons), lets Andrew switch his own launch agents (`~/Library/LaunchAgents`) off and back on, links everything else to
System Settings → Login Items, and offers four maintenance actions, asking for the admin password only when he clicks one that needs it.

**Architecture:** All the rules go in `MacCleanerCore/Performance.swift`, unit tested first: reading launch agent plists,
parsing `launchctl print-disabled`, `launchctl list` and `sfltool dumpbtm`, the exact `launchctl` commands for off/on, and the
maintenance commands with their admin wrapper. The `Spruce` target only shows them: `PerformanceView` with a segmented picker
(Login & Background / Maintenance).

**Tech Stack:** Swift 6, SwiftUI, `launchctl`, `sfltool`, `osascript` for the standard macOS admin password dialog, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-16-mac-app-design.md`, tool 5 "Performance", Permissions and Anti-goals.

## Global Constraints

Phase 1's constraints stand (scratch path, macOS 14, no dependencies, no nagging, direction C). Added for this phase:

- **Turning an agent off is reversible and never touches the file.** Off = `launchctl disable gui/<uid>/<label>` (launchd keeps
  that override in its own database) then `bootout` to stop it now. On = `launchctl enable` then `bootstrap` from the same plist.
  The plist stays in `~/Library/LaunchAgents`. The row says "Off" plainly, and turning the switch back on restores it.
- Only `~/Library/LaunchAgents` items are switchable, and never a `com.apple.*` label. `/Library/LaunchAgents`,
  `/Library/LaunchDaemons` and apps' own helpers (from the Background Task Management list) are read-only with a link to
  System Settings → Login Items.
- `sfltool dumpbtm` is undocumented. If it fails or its format changes, those sections are simply missing and the
  System Settings link still works. It takes ~4 s, so it loads after the launch agents.
- Admin is asked for only by the click on an admin action, through macOS's own password dialog. Cancelling it is silent.
- No "speed up" claims. Each action says what it really does and when it helps.

## Review Focus

1. **Switching the wrong thing.** Only user agents with a readable `Label` that isn't `com.apple.*` get a switch; the command
   targets that exact label in the user's own `gui/<uid>` domain. Pinned by `launchAgentScopes` and `toggleCommands`.
2. **Reversibility.** Off then on gives back an enabled, loaded agent; the first command (`disable`/`enable`) must succeed, the
   second (`bootout`/`bootstrap`) is best effort because it fails when the agent is already stopped or already loaded.
   Pinned by `toggleCommands`.
3. **Misreading state.** Both `print-disabled` formats (`=> disabled` on older macOS, `=> true`) parse; a label not listed is on.
   Pinned by `parsesDisabled`, `parsesLoaded`.
4. **Another user's items, or Apple's.** BTM parsing keeps only the current UID's section and only registered (`enabled`)
   apps, login items and app agents. Legacy agents come from the plists instead, so nothing shows twice. Pinned by `parsesBTM`.
5. **Admin wrapper injection.** The shell command is escaped inside the AppleScript string. Pinned by `adminWrapperEscapes`.

---

### Task 1: Core: listing, state, commands

**Files:**
- Create: `Sources/MacCleanerCore/Performance.swift`
- Test: `Tests/MacCleanerCoreTests/PerformanceTests.swift`

**Interfaces (produces):**
- `LaunchAgent` (`label`, `url`, `program`, `scope: .user | .allUsers | .daemon`, `isSwitchable`); `launchAgents(home:systemRoot:)`.
- `parseDisabled(_:) -> Set<String>`, `parseLoaded(_:) -> [String: Bool]` (label → running).
- `BackgroundItem` (`name`, `kind: .opensAtLogin | .loginItem | .agent`, `label`, `appPath`, `parentName`, `allowed`);
  `parseBTM(_:uid:) -> [BackgroundItem]`, and `legacyDisallowed(_:uid:) -> Set<String>` for the note on user agents.
- `toggleCommands(label:plist:uid:enable:) -> [[String]]`; `setAgent(_:enabled:uid:) throws`; `liveLaunchState(uid:)`, `liveBackgroundItems(uid:)`.
- `Maintenance` (`.dns`, `.spotlight`, `.launchServices`, `.quickLook`) with `title`, `detail`, `needsAdmin`, `command`;
  `adminWrapped(_:)`; `runMaintenance(_:) throws -> MaintenanceResult` (`.done`, `.cancelled`).

- [x] **Step 1: Write the failing tests** for the five pins above plus the maintenance list (admin flags, every command non-empty).
- [x] **Step 2: Run, expect a compile failure** (`swift test --scratch-path ~/Library/Caches/MacCleaner/spm --filter Performance`).
- [x] **Step 3: Implement `Performance.swift`.**
- [x] **Step 4: Run the whole suite, expect all passing.**

### Task 2: The Performance tool

- Modify `Tool.swift`: `case performance` between Applications and Screen Clean, "Performance", symbol `gauge.with.dots.needle.67percent`,
  tint `.pink`, subtitle "What starts with your Mac, and a few maintenance tasks."
- Modify `SpruceApp.swift`: route `.performance` to `PerformanceView`.
- Create `Sources/Spruce/PerformanceView.swift`:
  - **Login & Background:** sections "Open at login", "Apps' background helpers", "Your launch agents" (switches),
    "For all users" (read-only). Status per agent: Running / Loaded / Not loaded / Off. Help text on the switch says the file
    stays put. A line under the list: "Open Login Items Settings…".
  - **Maintenance:** one row per action with a Run button; Spotlight asks to confirm first (search is incomplete while it reindexes);
    a lock badge on admin actions; the result line ("Done", or the error) under the row.

### Task 3: Build, bundle, hand-off

- [x] `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`: all green.
- [x] `tools/bundle-spruce.sh --install`.
- [x] **Andrew checks on his Mac** (passed 2026-10-18: listing matches System Settings, steamclean off/on round-trips, Open With rebuild and DNS flush both Done, cancel is silent) (an agent can't type his admin password or judge what he wants running):
  1. Open Spruce → Performance. "Open at login" matches System Settings → General → Login Items.
  2. Under "Your launch agents", switch `com.valvesoftware.steamclean` off: it reads "Off". Run
     `launchctl print-disabled gui/$(id -u) | grep steamclean` → `disabled`/`true`; the plist is still in `~/Library/LaunchAgents`.
  3. Switch it back on: status returns to Loaded/Not loaded, and the same command shows `enabled`/`false`.
  4. Maintenance → Rebuild the “Open With” menu → Run: “Done” after a few seconds (no password).
  5. Maintenance → Flush DNS cache → macOS asks for the password; cancel once (nothing happens), then run it for real: "Done".
- [x] Commit on `spruce-phase-3-performance`; update the vault page and run `~/.claude/brain/brain sync`.

## Found later (2026-10-19)

When Spruce runs it, `sfltool dumpbtm` makes macOS ask for an administrator password (from a terminal it didn't), and the tab
ran it on every open, so the prompt appeared every time. That broke the "admin only on click" rule. Now the Open at login and
helpers sections show a Show… button that says a password is coming; one successful read is kept until Spruce quits, and a
cancelled prompt shows Try Again. Launch agents still load at once with no prompt.

## Known limits

- Apps' helpers and "Open at login" apps are read-only: macOS lets only System Settings (or the app itself) change them.
- System-wide agents and daemons need admin to change, so they link to System Settings, which handles that.
