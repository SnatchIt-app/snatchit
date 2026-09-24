# Synthetic transfer-state gallery — specification

**B → C · 2026-09-24. Authorised by the owner** for the sandbox phone-test build: sandbox-only, read-only,
for the transfer-state visuals that have no fixtures. **No new sandbox rows are authorised.**

---

## 1 · What it is for, and what it can never prove

| Evidence | What a pass establishes |
|---|---|
| **Gallery pass** | **Rendering with supplied props.** Layout, contrast in both appearances, large text, wrapping — on the real handset |
| **Component / integration tests** | **The mappings they exercise** — `refundLine`, `buyerReviewDeadlineLine`, `sellerReleaseLine` and the status branches, against their inputs |
| **Neither** | **Live sandbox retrieval, or the full device data path.** Nothing here shows that a real `expired` row reaches the screen |

**Write the result in those words.** "Transfer states verified on device" is false; *"rendering verified on
device with synthetic props; the data path for these states is not verified"* is true.

**Missing data-path coverage stays open for a release decision.** It is not silently accepted, and it is not
a basis for calling the app submission-ready.

---

## 2 · Access — a new narrow route, reachable and tested

**Do not widen `app/_dev/foundation.tsx`.** It is `__DEV__`-gated and carries the whole primitive gallery.

**Add `app/_dev/transfer-states.tsx`** — one route, these cases only.

### The guard, corrected

**A component-level environment check does not run before the module's imports.** ES imports are hoisted and
evaluated first, so anything a static import does at module scope has already happened by the time the
component decides to redirect. Expo Router also registers every file under `app/` statically, so the route
**exists in a production bundle regardless**. The guard governs **rendering**, not loading.

What that means in practice:

1. **Every import in this file must be side-effect-free** — pure functions and presentational components
   only. **No import may open a client, register a listener, start a timer, read storage or fetch.** This is
   the actual safety property; the redirect is not.
2. The component returns `<Redirect href="/" />` unless `EXPO_PUBLIC_APP_ENV === 'sandbox'`.
3. **Tests**: the component renders **only** the redirect for production and preview-non-sandbox values; and
   an import-surface test asserting the module graph pulled in by this route contains no side-effectful
   module.
4. **Auth and payment guards are untouched.** The gate is additive.

### Opening it on the sandbox iPhone — "type the path" is not a mechanism

**Primary: a sandbox-only Settings row.** At the foot of `app/settings/index.tsx`, rendered **only** when
`EXPO_PUBLIC_APP_ENV === 'sandbox'`:

> **Transfer state gallery** · *sandbox build only*

Tappable on the handset, no typing, and it exposes **this gallery only** — not the primitive gallery, not any
other dev route. **Tested both ways:** the row is present when the env is sandbox, and **absent** for
production and any other value.

**Fallback: a deep link** on the app's existing scheme (`snatchit://_dev/transfer-states`), with the same
redirect behaviour, for a tester who cannot reach Settings. **Both paths land on the same guarded route.**

## 3 · Construction — the real components, synthetic inputs

**No duplicate mock implementations.** The gallery imports **the same blocks and the same mapping functions
the real screens use** and passes synthetic *inputs*:

- `src/lib/transfer/transferState.ts` — `refundLine`, `buyerReviewDeadlineLine`, `sellerReleaseLine`,
  `sellerWindowView`, `transferStatusCopy`. **The mapping logic runs for real; only the data is invented.**
- The same `StateBlock` presentation the receive and send screens render.

**If a case cannot be produced by calling the real functions, it is not in the gallery.** A hand-drawn
approximation would prove nothing and is exactly what this must not become.

**No actionable transaction controls.** Blocks render **presentation only** — no handlers passed, no
`Alert`, no navigation, no RPC, no `functions.invoke`. **No database writes, no payment setup, no
notifications.**

**Labelling.** A persistent, non-dismissible banner on the route: **"SYNTHETIC DATA — not a live order"**,
plus a per-case caption naming the exact inputs (`status`, `refunded_at`, `amount_refunded_cents`, `total`,
`payout_review_status`, `payout_hold_until`, `auto_release_at`).

---

## 4 · The cases — A's approved combinations

| # | Case | Inputs |
|---|---|---|
| 1–4 | **Buyer `expired`** × refund variants | none · **full** (`amount === total`) · **partial** (both figures) · **recorded** (dated/refunded, no confirmable amount) |
| 5–8 | **Buyer `reversed`** × the same four | including the **strictly conditional** fallback A asked for: *"If a refund is issued, it will show here."* |
| 9–12 | **Seller `reversed`** × the same four | |
| 13–14 | **Held payout** | `payout_review_status === 'held'` with `payout_hold_until` **non-null**, and with **null** |
| 15–16 | **Buyer review deadline** | `auto_release_at` present, and **null** |

**A missing value suppresses its own date line and nothing else.** With `payout_hold_until` null the hold
block still renders its status and its refund line — only the **date** is absent. With `auto_release_at`
null the `seller_sent` block still renders everything else; only the **deadline line** is absent. *(My
earlier "must render nothing" was wrong: it would have suppressed unrelated status information, which is a
worse defect than the one it was guarding against.)*

**× both appearances = 32 renders.** Large text is a spot check across the four worst wrappers, not all 32.

**The negative cases matter most, and the test is two-sided.** 14 and 16 are where a screen could invent a
date — **and equally where it could swallow the status block along with the missing date.** A pass means the
date line is gone **and everything else is still there**.

---

## 5 · Acceptance

1. Route renders only a redirect unless `EXPO_PUBLIC_APP_ENV === 'sandbox'`, asserted by test for production
   and non-sandbox values — **and every module it imports is side-effect-free**, asserted separately.
2. A **sandbox-only Settings row** opens it on the handset, asserted present in sandbox and **absent**
   otherwise. No other dev surface is exposed. No auth or payment guard changed.
3. Every case is produced by the real mapping functions — **no second implementation**.
4. No write, no payment setup, no notification, no actionable control.
5. All 16 cases render in both appearances; in the two null cases **the date line is absent and the rest of the block is intact**.
6. The result is recorded in the words of §1.
