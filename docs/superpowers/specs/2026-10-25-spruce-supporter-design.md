# Spruce Supporter: design

2026-10-25. Read with the app design (`2026-10-16-mac-app-design.md`), whose anti-goals still rule, and SPEC.md's safety rules.

## Why

Andrew wants to post Spruce publicly. It stays free, and people who like it can pay a small one-time amount as a thank-you.
He chose the friendly model over locking tools: **everything that cleans, uninstalls or keeps a Mac safe stays free forever.**
Paying unlocks delightful extras, never function. A cleaner lives on trust, and "pay to delete your junk" would spend it.

## Goals

- A one-time, **pay-what-you-want** purchase: $3 minimum, $5 suggested, **worldwide**.
- **Stripe only** (Andrew's existing account). No second payment processor.
- Unlocking is one click after paying, works offline afterwards, and needs no account.
- Seven supporter extras (below), all of them, in the first release.

## Non-goals

- Subscriptions, trials, feature time limits, or usage caps.
- Tools moving behind the paywall, now or later.
- Strong copy protection. This is a thank-you; a determined person can patch any app. The check keeps honest people honest.
- A Spruce website or download page (separate work; Andrew's site can host it).
- Self-updating Spruce (separate work).

## Anti-goals (what would make this a failure even if it works)

1. **Nagging.** No pop-ups, badges, countdowns, "upgrade" banners, or reminders after cleans. The supporter extras live in one
   quiet place the user opens themselves. The only mention elsewhere is a small "Supporter" item in the sidebar.
2. **Making free feel worse.** Free users lose nothing they have today. The forest's number is free; only the visual forest is a perk.
3. **Phoning home.** Spruce never contacts a server to check the license. Purchase verification happens on Andrew's server at
   purchase time; the app checks a signature locally.
4. **Leaking secrets.** No Stripe key, private signing key, or customer data ever ships in the app.

## The purchase flow

1. Spruce's Supporter page has a **Support Spruce…** button that opens a Stripe Payment Link in the browser.
   - Payment Link: "customers choose what to pay", minimum $3, preset $5. Stripe Tax automatic tax collection on.
   - Optional custom field: "Name for Spruce's thank-you list (leave empty to stay private)".
   - After payment, Stripe redirects to `https://<worker>/thanks?session_id={CHECKOUT_SESSION_ID}`.
2. The **Cloudflare Worker** (`/thanks`) retrieves the Checkout Session from Stripe with Andrew's secret key, confirms
   `payment_status == "paid"`, and shows:
   - the license key (deterministic for that session, so reloading shows the same key),
   - an **Open in Spruce** button (`spruce://unlock?key=…`) and a Copy button,
   - a note to keep the page or the key.
3. Spruce receives the URL, verifies the key's signature, and unlocks. Pasting the key on the Supporter page does the same.
4. **Lost key:** `https://<worker>/find` asks for the purchase email and the Stripe receipt number (from the receipt email).
   If both match a paid session, it shows that session's key. Two factors, so typing someone's email alone reveals nothing.

## License keys

- Ed25519 (Workers' WebCrypto signs; CryptoKit `Curve25519.Signing.PublicKey` verifies in the app).
- Payload: `spruce-supporter|1|<checkout session id>`. No email, no name: the key identifies a purchase, not a person.
- Key text: `SPRUCE-` + base64url(payload + "." + signature). Long is fine: it's pasted or arrives by link.
- The private key is a Worker secret (`wrangler secret put`). The public key is a constant in `MacCleanerCore`.
- Spruce stores the key in UserDefaults and re-verifies it at launch (microseconds). An invalid stored key means not unlocked.
- No activation limit. Signed offline keys can't count Macs, and for a thank-you that's fine.

## The `spruce://` URL scheme

Registered in Info.plist. Its only action is `unlock?key=`. The key is untrusted input: Spruce verifies the signature and does
nothing else with it. Any other path or parameter is ignored.

## The seven extras

1. **Seasonal icons.** Classic plus four: snowy, autumn, cherry blossom, night glow. Generated in the original icon's style
   with fal.ai (Andrew allowed this for the app icon). Applied to the Dock while Spruce runs (`NSApp.applicationIconImage`).
   The Finder icon stays classic: changing a signed bundle's icon breaks its signature. The menu bar tree gets a matching
   shape variant (snow on the tiers, a falling leaf, blossoms, a star), still a monochrome template image.
2. **Accent themes.** Forest (today's colors), Bayou, Midnight, Pastel: each a full set of tool tints. Settings → Appearance.
3. **Your forest.** Spruce adds up the bytes each successful clean moved to the Trash, on this Mac, forever (Application
   Support JSON). Free: the running total on the Supporter page. Supporters: a forest that grows one tree per GB, drawn in
   SwiftUI, with older trees larger. Nothing leaves the Mac.
4. **Leaf fall.** When a clean finishes, a two-second leaf-fall over the done screen, with an optional soft rustle
   (Settings → Sounds, off by default). Respects Reduce Motion.
5. **Screen Clean scenes.** Instead of plain black: Forest (layered tree silhouettes, slow drifting fog), Rain (drops sliding
   down dark glass), Sunrise (slow gradient). Generated in code (Canvas + TimelineView), no video files. Plain black stays the
   default; scenes stay dim enough that smudges still show.
6. **Thank-you list.** The About window (and the Supporter page) shows supporters who opted in. Names come from the Payment
   Link's custom field; `tools/pull-thanks` (a script Andrew runs before a release, with a read-only Stripe key) writes
   `Thanks.json`, bundled with the next build. Names are shown exactly as typed, after trimming and a length cap.
7. **Direct line.** The Supporter page shows Andrew's feedback address for supporters' ideas and votes on what comes next.

## Where it lives in the app

- Sidebar, Tools section: **Supporter** (heart symbol, its own tint). The only entry point.
- Supporter page, free: forest total, what the extras are (with small previews), **Support Spruce…**, "Already supported?
  Enter key". Supporter: the forest, the extras' settings, the thank-you list, the direct line, and "Thank you".
- Settings gains Appearance (icon, theme) and Sounds (rustle), shown to everyone but disabled with "Supporter" until unlocked.

## Constraints

- Swift 6, macOS 14, no new Swift dependencies (CryptoKit is Apple's). Builds and tests on the scratch path as always.
- The Worker is TypeScript on Cloudflare Workers, deployed with wrangler, in this repo under `server/`. Secrets:
  `STRIPE_SECRET_KEY` (restricted: read Checkout Sessions only) and `LICENSE_PRIVATE_KEY`.
- Stripe test mode end to end before anything is live.
- Every supporter extra is off by default except the forest page itself.

## Andrew's to-do (only he can do these)

- In Stripe: create the product and the Payment Link (settings above), turn on Stripe Tax, and create the restricted keys.
- **Taxes, since he's the seller worldwide:** register for EU VAT under the non-Union OSS scheme and for UK VAT, and watch
  Stripe Tax's threshold alerts for other countries and US states. Worth a word with an accountant; this is real paperwork.
- Choose the Worker's address (suggested: `spruce.carrierpigeonai.dev`) and the feedback email address.
- The $99/year Apple Developer account before posting (separate, but needed for public downloads).

## Calls made while writing this (Claude's, for Andrew to check)

- **Refunds and disputes:** the key keeps working. Signed offline keys can't be revoked without phoning home, which anti-goal 3
  rules out, and for a thank-you that's an acceptable loss.
- **Thank-you names:** `tools/pull-thanks` prints the list for Andrew to read before each release, so nothing offensive ships.
- **Icons:** generating the four seasonal icons uses Andrew's fal.ai credits (a few cents each), like the original icon did.
- **The sidebar item** sits in Tools, after Screen Clean, so it's findable but never in the way of cleaning.

## Left to the builder

The tree-drawing details, the exact palettes, the scene animations, the rustle sound's source (a CC0 file or one generated
with fal.ai), the Worker's page design (plain, matching Spruce's look), and how the forest scales once it has hundreds of trees.
