# Hand-off: build Spruce Supporter

2026-10-25. For a new Claude Code chat. Paste the prompt at the bottom.

## Where things stand

Spruce is Andrew's free, clean-room CleanMyMac alternative (SwiftUI, macOS 14+). Repo: `~/Documents/Claude/projects/Tools/mac-cleaner`
(private GitHub `agcarrier/mac-cleaner`, branch `main`). Everything below is merged and pushed.

- **Built and hands-on checked:** phases 1–7 (Smart Care, Cleanup, Space + Disk Map, Applications + uninstaller + Updater,
  Performance, My Clutter, Screen Clean, menu bar monitor), a polish pass, and a safety/security pass (protected-path guard
  inside `trash()`, full command paths, https-only links, hardened runtime). 75 tests pass.
- **On hold:** Cloud & Mail (Andrew won't use it).
- **Next:** the Spruce Supporter unlock. Designed and approved, plan written, **nothing built yet.**

## Read first

1. `docs/superpowers/specs/2026-10-25-spruce-supporter-design.md` — the approved design (why, goals, anti-goals, flow, the seven extras).
2. `docs/superpowers/plans/2026-10-25-spruce-supporter.md` — the 9-task plan to execute.
3. `docs/superpowers/specs/2026-10-16-mac-app-design.md` — the app's anti-goals (never delete the wrong thing, no nagging, light).
4. `SPEC.md` — cleaning, safety and security rules. `README.md` — build and install.

## Decisions Andrew made (don't reopen)

- Everything that cleans, uninstalls or keeps a Mac safe stays free forever. Paying unlocks thank-you extras only.
- Pay what you want: $3 minimum, $5 suggested, one time, **worldwide**.
- **Stripe only** (his existing account), no Lemon Squeezy/Paddle. He accepts handling taxes as the seller (EU OSS, UK VAT,
  Stripe Tax alerts); that's his paperwork, not the build's.
- All seven extras ship: seasonal icons, accent themes, your forest, leaf fall + rustle, Screen Clean scenes, thank-you list,
  direct line.
- Flow: Stripe Payment Link → Cloudflare Worker confirms payment and shows an Ed25519-signed key → Spruce verifies offline.

## Still open (ask Andrew when the plan reaches them)

- The Worker's address (suggested `spruce.carrierpigeonai.dev`) and the feedback email for the direct line.
- Picking the seasonal icons from generated options (plan task 6; uses his fal.ai credits).
- His Stripe test-mode setup (plan task 9).
- Execution method: native was recommended (as phases 1–7 ran): implement the tasks in-session, one fresh whole-branch review
  at the end, then hands-on check, then merge to main locally and push. Confirm with him.

## How Andrew works (gotchas)

- Build and test **only** with `--scratch-path ~/Library/Caches/MacCleaner/spm` (the repo is in iCloud-synced Documents).
  Tests: `swift test --scratch-path ~/Library/Caches/MacCleaner/spm`. Install: `tools/bundle-spruce.sh --install`
  (signs with his Apple Development cert so Full Disk Access survives rebuilds).
- Work on a branch (`spruce-supporter`), TDD (tests fail first), then offer **merge to main locally + push** as every phase did.
  Put exact hands-on steps in the message for him; he checks on his Mac before merging.
- Restart Spruce after installing: `osascript -e 'tell application id "dev.andrewcarrier.spruce" to quit'; open /Applications/Spruce.app`.
- Things learned the hard way: `sfltool dumpbtm` asks for an admin password when Spruce runs it (only from a click);
  `FileManager.trashItem` refuses files other apps created, so `trash()` falls back to moving into `~/.Trash`; a drawn NSImage
  inside `Text` vanishes in the menu bar (use `Image(nsImage:)`); the window still grows a little when Applications opens
  (search field in the toolbar), not yet fixed.
- Never put secrets in the repo or the vault. The Stripe secret key and the license private key go only into
  `wrangler secret put`.
- Vault page: `projects/mac-cleaner.md` in his Obsidian vault. Update it when status changes, then run `~/.claude/brain/brain sync`.

## Prompt to paste into the new chat

> Build Spruce Supporter for my Mac cleaner app. Repo: ~/Documents/Claude/projects/Tools/mac-cleaner. Start by reading
> docs/HANDOFF-supporter.md, then the approved design and the plan it points to, and follow the plan task by task on a
> `spruce-supporter` branch. Ask me about the open items when you reach them.
