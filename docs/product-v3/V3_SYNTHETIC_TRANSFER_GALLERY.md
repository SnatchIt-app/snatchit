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

## 2 · Access — a new narrow route, not the existing dev tools

**Do not widen `app/_dev/foundation.tsx`.** It is `__DEV__`-gated and carries the whole primitive gallery;
opening it in a `preview` build would expose far more than these cases.

**Add `app/_dev/transfer-states.tsx`** — one route, these cases only.

```
Gate:  EXPO_PUBLIC_APP_ENV === 'sandbox'   (compiled in by the eas.json `preview` profile)
Else:  <Redirect href="/" />  — the same shape foundation.tsx already uses
```

**Required proof that production cannot reach it:**

1. The env check is the **first** thing the module does — before any import with a side effect.
2. **No navigation entry point anywhere** — no link, no tab, no settings row. It is reached by typing the
   path, and only in a sandbox build.
3. A test asserting the redirect when `EXPO_PUBLIC_APP_ENV !== 'sandbox'`, including the production value.
4. **Authentication and payment guards are untouched.** The gate is additive; it weakens nothing.

---

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
| 13–14 | **Held payout** | `payout_review_status === 'held'` with `payout_hold_until` **non-null**, and with **null** — the second must render **nothing** |
| 15–16 | **Buyer review deadline** | `auto_release_at` present, and **null** — the second must render **nothing** |

**× both appearances = 32 renders.** Large text is a spot check across the four worst wrappers, not all 32.

**The negative cases matter most.** 14 and 16 are where a screen invents a date; if either renders anything,
that is the finding.

---

## 5 · Acceptance

1. Route redirects unless `EXPO_PUBLIC_APP_ENV === 'sandbox'`, asserted by test.
2. No navigation reaches it; no auth or payment guard changed.
3. Every case is produced by the real mapping functions — **no second implementation**.
4. No write, no payment setup, no notification, no actionable control.
5. All 16 cases render in both appearances; the two null cases render nothing.
6. The result is recorded in the words of §1.
