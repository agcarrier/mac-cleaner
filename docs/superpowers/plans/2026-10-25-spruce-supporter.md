# Spruce Supporter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pay-what-you-want "Spruce Supporter" unlock (Stripe Payment Link → Cloudflare Worker that issues a signed key →
Spruce verifies it offline) and the seven thank-you extras, with every cleaning feature staying free.

**Architecture:** License keys are Ed25519-signed strings: the Worker (`server/`, TypeScript on Cloudflare Workers) signs after
confirming payment with Stripe; `MacCleanerCore/License.swift` verifies with an embedded public key, and one shared test vector
proves both sides agree. `SpruceKit` holds the testable state (supporter status, the forest ledger, URL parsing, thank-you
names). The `Spruce` target adds the Supporter page and the extras.

**Tech Stack:** Swift 6, CryptoKit (`Curve25519.Signing`), SwiftUI (Canvas, TimelineView), AppKit (`NSApp.applicationIconImage`,
`NSSound`), Cloudflare Workers + wrangler, WebCrypto Ed25519, Vitest, Stripe REST API, fal.ai (icons), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-25-spruce-supporter-design.md` (approved 2026-10-25), plus the app design's anti-goals.

## Global Constraints

- Everything that cleans, uninstalls or keeps a Mac safe stays free. Paying unlocks extras, never function.
- Pay what you want: **$3 minimum, $5 suggested**, one time, **worldwide**, **Stripe only**, Stripe Tax on.
- No nagging: no pop-ups, badges, countdowns or reminders. The only entry point is the **Supporter** sidebar item (Tools section,
  after Screen Clean). Settings' supporter options show to everyone, disabled with a "Supporter" label until unlocked.
- Spruce never contacts a server about the license. Keys are verified locally against the embedded public key.
- No Stripe key, private signing key or customer data in the app or the repo. Worker secrets via `wrangler secret put`:
  `STRIPE_SECRET_KEY` (restricted, read-only) and `LICENSE_PRIVATE_KEY`.
- Key payload `spruce-supporter|1|<checkout session id>`; key text `SPRUCE-<base64url(payload)>.<base64url(signature)>`.
- Every extra is off by default except the forest page itself. Respect Reduce Motion.
- macOS 14, no new Swift dependencies; builds and tests with `--scratch-path ~/Library/Caches/MacCleaner/spm`.
- Stripe test mode end to end before anything is live.

## Review Focus

1. **A pasted key with spaces, line breaks or a missing `SPRUCE-` prefix** (email clients wrap long strings): trimmed and
   whitespace removed before verifying; a truly bad key says "That key doesn't look right" and changes nothing. Test
   `keyWithWhitespaceVerifies` in Task 1.
2. **A stored key that no longer verifies** (hand-edited defaults, a key from another build's test keypair): treated as not a
   supporter, never a crash. Test `badStoredKeyIsNotSupporter` in Task 3.
3. **Reloading or sharing the thanks page:** the same session always shows the same key; an unpaid or unknown session shows
   "We couldn't find a finished payment" and no key. Tests `thanksIsDeterministic` and `unpaidSessionGetsNoKey` in Task 2.
4. **Someone guessing emails on the find page:** an email alone never reveals a key; a wrong receipt number gets the same reply
   as an unknown email. Test `findNeedsReceiptNumber` in Task 2.
5. **A corrupt or missing forest file:** starts from zero, never crashes, never shows a negative total. Test `corruptLedgerStartsEmpty`
   in Task 4.

---

### Task 1: License format and verification (core)

**Files:**
- Create: `Sources/MacCleanerCore/License.swift`
- Create: `tools/make-license-keys.swift` (prints a new keypair as base64: private for the Worker secret, public for `License.swift`)
- Create: `Tests/MacCleanerCoreTests/LicenseTests.swift`, `Tests/MacCleanerCoreTests/license-vector.json`

**Interfaces (produces):**
- `public enum License` with `static let publicKey: Curve25519.Signing.PublicKey` (from a base64 constant; until Andrew
  runs the key tool, a placeholder key whose private half is not in the repo).
- `public static func payload(sessionID: String) -> String` → `"spruce-supporter|1|\(sessionID)"`.
- `public static func make(sessionID: String, signer: Curve25519.Signing.PrivateKey) -> String` (tests and tooling).
- `public static func verify(_ key: String, with publicKey: Curve25519.Signing.PublicKey = License.publicKey) -> Bool`.
  Normalizes first (trim, remove all whitespace, add a missing `SPRUCE-` prefix), then splits on the last `.`, decodes
  base64url, requires the payload to start with `spruce-supporter|1|` and a non-empty session id, and checks the signature.

- [ ] **Step 1: Write the failing tests** in `LicenseTests.swift`: `roundTrip` (make with a fresh private key → verify with its
  public key is true); `tamperedFails` (flip one character in the payload part → false; in the signature part → false);
  `wrongKeyFails` (verify with another public key → false); `otherPayloadFails` (a validly signed `"other-app|1|x"` → false);
  `keyWithWhitespaceVerifies` (insert `"\n  "` mid-key and drop the `SPRUCE-` prefix → true); `garbageFails` (`""`,
  `"SPRUCE-"`, `"SPRUCE-abc"`, `"hello"` → false); `workerVectorVerifies` (reads `license-vector.json`
  `{publicKey, sessionID, key}` written by Task 2 and verifies `key` with `publicKey`; until Task 2 exists, the test vector is
  generated by `make` and Task 2 must reproduce it byte for byte).
- [ ] **Step 2: Run** `swift test --scratch-path ~/Library/Caches/MacCleaner/spm --filter License` → compile failure.
- [ ] **Step 3: Implement `License`**, and `make-license-keys.swift` (`swift tools/make-license-keys.swift` prints
  `PRIVATE (wrangler secret put LICENSE_PRIVATE_KEY): …` and `PUBLIC (paste into License.swift): …`).
- [ ] **Step 4: Run the whole suite** → green. **Commit.**

### Task 2: The Worker (`server/`)

**Files:**
- Create: `server/package.json` (wrangler, vitest, typescript as dev dependencies), `server/wrangler.jsonc`
  (name `spruce-supporter`, route `spruce.carrierpigeonai.dev/*` unless Andrew picks another), `server/tsconfig.json`
- Create: `server/src/license.ts` — `sign(sessionID: string, privateKeyB64: string): Promise<string>` producing the exact key
  format (WebCrypto `Ed25519`, deterministic).
- Create: `server/src/stripe.ts` — `getPaidSession(id, key)` (`GET /v1/checkout/sessions/{id}`; returns the session only when
  `payment_status === "paid"`) and `findByEmailAndReceipt(email, receipt, key)` (list Checkout Sessions filtered by
  `customer_details[email]`, expand `data.payment_intent.latest_charge`, match `receipt_number` exactly, case-insensitive,
  ignoring a leading `#`). Check both calls against Stripe's current docs (`stripe:stripe-docs` skill) before writing them.
- Create: `server/src/index.ts` — routes `GET /thanks?session_id=`, `GET /find` (form), `POST /find`; anything else 404.
  Pages are small, server-rendered HTML in Spruce's look (system font, green glow), every interpolated value HTML-escaped,
  `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'`, no scripts except the Copy button's inline
  handler (then allow its hash, not `unsafe-inline`). The thanks page shows the key, **Open in Spruce**
  (`spruce://unlock?key=<urlencoded key>`), **Copy**, and "Keep this page or the key".
- Create: `server/test/*.test.ts`, `server/test/vector.json` (copied to `Tests/MacCleanerCoreTests/license-vector.json`).

- [ ] **Step 1: Write failing tests** (Stripe calls stubbed by replacing `fetch`): `signMatchesVector` (fixed test private key +
  session `cs_test_vector` → the exact key in `vector.json`); `thanksIsDeterministic` (two requests → identical key);
  `unpaidSessionGetsNoKey` (`payment_status: "unpaid"` and a 404 from Stripe → page says "We couldn't find a finished payment",
  contains no `SPRUCE-`); `findNeedsReceiptNumber` (right email + wrong receipt, and unknown email, → identical body without a
  key; right email + right receipt → key); `escapesInput` (session id `<script>` never appears unescaped).
- [ ] **Step 2: Run** `cd server && npx vitest run` → failures.
- [ ] **Step 3: Implement** the three files. Regenerate the test vector with the test private key and copy it to the Swift tests.
- [ ] **Step 4: Run** `npx vitest run` and the Swift suite → green. **Commit.** (Deploying is Task 9.)

### Task 3: Supporter state, the URL scheme and the Supporter page

**Files:**
- Create: `Sources/SpruceKit/Supporter.swift`, `Tests/SpruceKitTests/SupporterTests.swift`
- Create: `Sources/Spruce/SupporterView.swift`
- Modify: `Sources/Spruce/Tool.swift` (`case supporter`, "Supporter", symbol `heart.fill`, tint `.pink`, subtitle
  "Spruce is free. If it helps you, you can say thanks.", last in the Tools section), `Sources/Spruce/SpruceApp.swift`
  (one `SupporterModel` in `AppState`, `.environment` it, route the tool, `.onOpenURL`), `tools/bundle-spruce.sh`
  (`CFBundleURLTypes` with scheme `spruce`)

**Interfaces (produces):**
- `@MainActor @Observable public final class SupporterModel` — `init(defaults: UserDefaults = .standard, publicKey: … = License.publicKey)`,
  `public private(set) var isSupporter: Bool` (re-verified from the stored key at init), `public func unlock(_ key: String) -> Bool`
  (stores the normalized key under `supporterKey` only when it verifies).
- `public func unlockKey(from url: URL) -> String?` — non-nil only for scheme `spruce`, host `unlock`, a `key` query item.
- `public static let paymentLink: URL` and `findKeyPage: URL` on `SupporterModel` (Andrew's real links filled in Task 9).

- [ ] **Step 1: Write failing tests:** `unlockStoresOnlyValidKeys`, `supporterSurvivesRelaunch` (new model, same defaults suite
  → still a supporter), `badStoredKeyIsNotSupporter` (garbage under `supporterKey` → false), `urlParsing`
  (`spruce://unlock?key=X` → X; `spruce://other?key=X`, `https://unlock?key=X`, `spruce://unlock` → nil). Use a throwaway
  `UserDefaults(suiteName:)` and a test keypair.
- [ ] **Step 2: Run → compile failure. Step 3: Implement.**
- [ ] **Step 4: `SupporterView`** — free state: the forest total (Task 4), the seven extras as small preview cards, the
  **Support Spruce…** pill (opens `paymentLink`), "Already supported? Enter your key" field + Unlock (inline error
  "That key doesn't look right"), "Lost your key?" link (`findKeyPage`). Supporter state: "Thank you" header, the forest, links
  to the extras' settings, the thank-you list (Task 8), and the direct line (`mailto:` Andrew's address, Task 9).
  `.onOpenURL`: parse with `unlockKey(from:)`, unlock, select the Supporter tool.
- [ ] **Step 5: Whole suite green, app builds. Commit.**

### Task 4: Your forest

**Files:**
- Create: `Sources/SpruceKit/Forest.swift`, `Tests/SpruceKitTests/ForestTests.swift`, `Sources/Spruce/ForestView.swift`
- Modify: `Sources/SpruceKit/ScanModel.swift` (init gains `onCleaned: @escaping @MainActor (CleanSummary) -> Void = { _ in }`,
  called once when a clean finishes with `bytes > 0`), `Sources/Spruce/SpruceApp.swift` and `Sources/Spruce/UninstallSheet.swift`
  (pass `{ forest.record($0.bytes) }`)

**Interfaces (produces):**
- `public struct ForestLedger: Codable, Equatable` — `freedBytes: Int64`, `treesPlanted: [Date]`;
  `public mutating func record(_ bytes: Int64, at: Date)` appends one date per whole GB (1,000,000,000 bytes) crossed.
- `@MainActor @Observable public final class ForestStore` — `init(file: URL)`, `public private(set) var ledger`,
  `public func record(_ bytes: Int64)` (saves atomically). Live file: `~/Library/Application Support/Spruce/forest.json`.

- [ ] **Step 1: Failing tests:** `treesPerGigabyte` (0.6 GB then 0.6 GB → 1 tree, 1.2 GB total; 2.5 GB → 3 trees total),
  `ignoresNonPositive`, `persists` (store, record, new store on same file → same ledger), `corruptLedgerStartsEmpty`, and in
  `ScanModelTests`: `cleanReportsBytesOnce`.
- [ ] **Step 2: Run → fail. Step 3: Implement.**
- [ ] **Step 4: `ForestView`** — Canvas: one tree per entry in `treesPlanted`, drawn with the menu bar tree's shape language,
  green shades varying by a seeded hash of the date, older trees larger, laid out in rows on a soft ground line; past 300 trees,
  draw 300 and caption the rest ("+ 42 more"). Free users see only the total and "Supporters see their forest grow here".
- [ ] **Step 5: Green; commit.**

### Task 5: Leaf fall and the rustle

**Files:** Create `Sources/Spruce/LeafFall.swift`, `art/rustle.caf` (a CC0 recording, with its source and license in
`art/CREDITS.md`, or one generated with fal.ai); modify `ScanToolView.swift` (done state), `SettingsView.swift`
(Sounds: "Rustle when a clean finishes", key `rustleSound`, default off), `tools/bundle-spruce.sh` (copy `rustle.caf`).

- [ ] **Step 1:** `LeafFall` — TimelineView + Canvas, ~24 leaves in the tool's tint, 2 s, then removed; nothing when
  Reduce Motion is on or the user isn't a supporter. Play `rustle.caf` once with `NSSound` when enabled.
- [ ] **Step 2:** Build, install, clean a test file in Smart Care with supporter on/off and Reduce Motion on/off. **Commit.**

### Task 6: Seasonal icons and accent themes

**Files:**
- Create: `art/icons/{snowy,autumn,blossom,night}.png` (1024 px, generated with fal.ai in the original icon's style: same
  rounded square, soft depth, same tree; Andrew picks from a few options per season), `Sources/Spruce/Appearance.swift`
- Modify: `Tool.swift` (`tint` reads the active theme), `MenuBarMonitor.swift` (`spruceIcon(variant:)` adds snow dots, a falling
  leaf, blossoms or a star to the template tree), `SettingsView.swift` (Appearance section), `tools/bundle-spruce.sh`
  (copy `art/icons/*.png` into Resources)

**Interfaces (produces):** `enum SeasonalIcon: String, CaseIterable { case classic, snowy, autumn, blossom, night }` with
`var image: NSImage?` and `func apply()` (sets `NSApp.applicationIconImage`; classic resets to nil); `enum AccentTheme: String,
CaseIterable { case forest, bayou, midnight, pastel }` with `func tint(for: Tool) -> Color`. Keys `seasonalIcon`, `accentTheme`;
both only take effect for supporters (anyone else gets classic and forest).

- [ ] **Step 1:** Generate icon options with fal.ai, show them to Andrew, keep his picks.
- [ ] **Step 2:** Implement, applying the icon at launch and on change. **Step 3:** Build, install, try every icon and theme.
  **Commit.**

### Task 7: Screen Clean scenes

**Files:** Create `Sources/Spruce/ScreenScenes.swift`; modify `ScreenCleaner.swift` (`OverlayView` draws the chosen scene
under the countdown), `SettingsView.swift` (Screen Clean → Scene: Black, Forest, Rain, Sunrise; key `screenCleanScene`,
default Black; non-black options need Supporter).

- [ ] **Step 1:** `enum ScreenScene` and its views (TimelineView + Canvas): Forest (three layers of tree silhouettes, slow fog),
  Rain (drops sliding down dark glass), Sunrise (slow gradient). Peak brightness stays low (≤ 25%) so smudges still show.
  Reduce Motion: draw a still frame.
- [ ] **Step 2:** Build, install, run each scene for 30 s; Spruce's CPU stays modest in Activity Monitor. **Commit.**

### Task 8: Thank-you list

**Files:** Create `tools/pull-thanks.sh` (reads a restricted Stripe key from `STRIPE_READ_KEY`, lists paid Checkout Sessions
from the Supporter Payment Link, prints the custom-field names for Andrew to review, then writes `art/Thanks.json` only after
he types `yes`), `Sources/SpruceKit/Thanks.swift`, `Tests/SpruceKitTests/ThanksTests.swift`; modify `SupporterView.swift` and the
About panel (`.commands` → About shows the list), `tools/bundle-spruce.sh` (copy `Thanks.json`).

**Interfaces (produces):** `public func cleanThanksNames(_ raw: [String]) -> [String]` (trim, collapse spaces, drop empty, cap
40 characters, case-insensitive dedupe, sorted); `public func bundledThanks() -> [String]`.

- [ ] **Step 1: Failing test** `namesAreCleaned` with `["  Ana  ", "ana", "", String(repeating: "x", count: 60), "Bo   B"]`
  → `["Ana", "Bo B", "xxxx…" (40 chars)]`. **Step 2:** fail. **Step 3:** implement. **Step 4:** green, commit.

### Task 9: Go live in test mode, hand-off

- [ ] Andrew (Stripe test mode): product "Spruce Supporter"; Payment Link with "customers choose what to pay" (minimum $3,
  preset $5), Stripe Tax on, optional custom field "Name for Spruce's thank-you list (leave empty to stay private)", success URL
  `https://<worker>/thanks?session_id={CHECKOUT_SESSION_ID}`; a restricted key with read access to Checkout Sessions,
  PaymentIntents and Charges. Choose the Worker address and the feedback email.
- [ ] Run `swift tools/make-license-keys.swift`; `wrangler secret put LICENSE_PRIVATE_KEY` and `STRIPE_SECRET_KEY`; paste the
  public key into `License.swift`; fill `paymentLink`, `findKeyPage` and the feedback address; regenerate the test vector.
- [ ] `cd server && npx wrangler deploy`; `swift test …` green; `tools/bundle-spruce.sh --install`.
- [ ] **Andrew checks on his Mac:**
  1. Supporter → Support Spruce… → pay with test card 4242 4242 4242 4242 at $3, and try $2 (refused).
  2. The thanks page shows a key; Open in Spruce unlocks and selects the Supporter page.
  3. Quit and reopen: still a supporter. Turn on each extra: icon, theme, rustle, leaf fall, Screen Clean scene, forest.
  4. Find-my-key page: email + receipt number shows the key; email + wrong number shows nothing.
  5. Nothing else in Spruce changed for a non-supporter (try a fresh macOS user, or delete `supporterKey` with
     `defaults delete dev.andrewcarrier.spruce supporterKey`).
- [ ] Commit on `spruce-supporter`; update the vault page and run `~/.claude/brain/brain sync`. Switching Stripe to live mode
  (and the tax registrations) is Andrew's step when he's ready to post.
