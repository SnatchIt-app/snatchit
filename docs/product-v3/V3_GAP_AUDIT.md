# V3 gap audit — what is still undesigned, blocked, unimplemented or unverified

**B · 2026-09-22.** Reconciled against the repository at release source `5b255838` and C's branch
`v3/midnight-app` @ `31819593`.

> **The redesign is NOT complete.** Five packages are delivered and committed, but **two consumer surfaces are
> still undesigned**, three transfer cells are blocked on A and C, and **nothing at all has been verified on a
> device**. Those categories are listed here in full rather than folded into a completion claim.

---

## 1 · Route coverage — 36 route files

| Designed with drawn artifacts (23) | Package |
|---|---|
| `(tabs)/home`, `(tabs)/create`, `(tabs)/tickets`, `(tabs)/profile` | 2, 3, 5 |
| `listing/[id]`, `bid/[id]`, `checkout/[id]` | 2 |
| `my-listings`, `listing/edit/[id]`, `settings/payout-setup`, `payout-return`, `payout-refresh` | 3 |
| `transfer/send/[id]`, `transfer/receive/[id]`, `report/[type]/[id]`, `settings/support` | 4 |
| `(auth)/login`, `(auth)/signup`, `(auth)/reset-password`, `profile/[id]`, `settings/index`, `settings/notifications` | 5 |

| Covered in writing, no drawn screen (7) | Why |
|---|---|
| `settings/edit-profile` | form fields, validation strings and avatar states specified in Package 5 §3; reuses the Input and MediaUpload patterns from Packages 1 and 3 |
| `settings/verify-phone` | three states specified; reuses the auth code-entry pattern already drawn |
| `settings/preferences` | chip grid + autosave + rollback + leave-while-saving dialog specified |
| `settings/blocked-users` | list, empty, load-failed and unblock confirm specified |
| `settings/legal`, `settings/privacy` | long static documents; type scale and collapsible sections come from Package 1 |
| `checkout/index` | the entry route into `checkout/[id]`; no separate surface |

**These seven are not "hidden behind a pattern" — each has its states, copy and rules written down in its
package — but none has a rendered image, and that is a gap, not a completion.**

| ⛔ Undesigned — substantive (2) | Consequence |
|---|---|
| **`(tabs)/bids.tsx` — the Bids tab** | A **primary destination in the dock** with no V3 design. It shows the buyer's bid history and routes into transfers. `BidCard.tsx` and `src/lib/bids/**` were inventoried but never drawn. **This is the largest single gap.** |
| **`listing/[id]` — the `ActionKind` × role dialog matrix** | The listing base screen is approved, but the screen carries **23 `Alert.alert` dialogs** and a role/state action machine (`detailState` → `ActionKind`) that was deferred from Package 2 into Package 4 and then not completed. Every other flow's dialogs are drawn; this one's are not. |

| Out of scope, stated (4) | Reason |
|---|---|
| `app/_dev/foundation.tsx` | developer preview, not consumer-facing |
| `(tabs)/index`, `(tabs)/explore` | hidden via `href: null`; reachable only by `router.push`. **C to confirm whether they are dead** |
| `app/_layout.tsx`, `(tabs)/_layout.tsx`, `(auth)/_layout.tsx` | layout shells, no visual surface of their own |

**Also undrawn:** `src/components/ErrorBoundary.tsx` (the last-resort crash screen),
`listing/OutbidToast.tsx` and `listing/ListingStatusBanner.tsx`. All three are inventoried in the matrix and
none has an artifact.

---

## 2 · Blocked — waiting on someone else

| # | What | Blocked on | Why it cannot be designed around |
|---|---|---|---|
| **B-1** | `expired` — **buyer** state block | **A** then B | Status alone is not payment evidence. Neutral copy is drafted and explicitly **not approved** |
| **B-2** | `reversed` — **buyer** state block | **A** then B | Same, plus the status noun itself is undecided |
| **B-3** | `reversed` — **seller** state block (**F-17c**, found this round) | **A** then B | `sellerWindowView` handles only `expired`; the seller sees nothing |
| **B-4** | The order screen's automatic-release sentence (**O-1**) | **A + C** | Never called approved anywhere; blocking for that screen only |
| **B-5** | The buyer's review-deadline row (**F-22**) | **C** | `auto_release_at` is not in the buyer's select list. Designed, with four verification questions attached |

**For all five:** no design promises an automatic refund, a completed payout or a guaranteed timeline.
**Displaying a partial refund elsewhere in the app does not mean the system automatically resolves
partial-refund obligations** — those are separate facts and no screen conflates them.

---

## 3 · Unimplemented — designed but not built anywhere

Everything in Packages 1–5 is **design only**. What exists in code today is limited to what C has landed on
`v3/midnight-app`:

| Implemented on C's branch | Status |
|---|---|
| The type-rule amendment (comment-only, both mirrors) | on the branch |
| Five mixed-case name tokens, leading provisional pending O-4 | on the branch |
| Bid CTAs (O-2) — listing opens entry, bid screen submits with the all-in total | on the branch |
| The "You" item showing the signed-in user's photo (O-5) | on the branch |
| Truthful reporting, failed-read copy, scrim curve (O-3) | on the branch |

> **"Implemented on C's branch" does not mean shipped or deployed.** `v3/midnight-app` is an isolated branch.
> None of it is in the release source, none is in a build, and none is in production.

**Not implemented anywhere:** every token amendment (A-1 neutral hairlines, A-2 mixed-case sentence headings,
A-3 `radius.media` / `radius.chrome`), every component restyle, all four state screens, the inline failure
banner, and every screen in Packages 2–5.

---

## 4 · Awaiting device verification — nothing is verified

**No claim in any package is device-verified. I have run no build, no simulator and no device check, and I have
made no production read.** Every artifact is a static image.

| # | What needs a device | Owner |
|---|---|---|
| **D-1** | **Mixed-case Oswald leading (O-4).** `MIN_LINE_HEIGHT_RATIO = 1.25` was derived for uppercase: (810 + 377)/1000 = 1.187 em. Mixed case gives 1.702 em on win metrics and 1.482 em on hhea. My boards use ~1.16× as a **drawn value, not a token** | C |
| **D-2** | **Contrast over real seller artwork.** All seven text bands pass against *generated* placeholders (worst 5.17:1). Real uploads are the only proof | C |
| **D-3** | Enlarged text at the display-scale cap across every form and row | C |
| **D-4** | Narrowest supported width, including the `StickyBar` stacked form below 352pt | C |
| **D-5** | Keyboard behaviour on Create, bid entry, auth and the delivery form | C |
| **D-6** | Avatar across sign-out and account switching — a previous user's photo must never survive | C |
| **D-7** | Whether `expired` / `reversed` are reachable in practice | C |
| **D-8** | Whether the Tickets RPC migration is applied — it decides whether the tab shows the empty state or the error state | C |

**I am not claiming the redesign preserves behaviour.** The annotations state intent. Preservation is
established on a device against the release source, by C.

---

## 5 · Functional findings still open

**24 findings, all ① present in the release source** except **F-17a and F-19 (② already fixed)** and **F-6,
F-16 (⑤ unverified)**. **None is ③** — F-17b, F-17c, F-18, F-21 and F-22 were measured on C's branch too and
are present there as well. **None is fixed by any design package.**

The four most consequential: **F-17b/c** (expired and reversed render nothing) · **F-22** (the buyer never sees
the date that decides whether their payment leaves) · **F-21** (raw PostgREST text reaches the buyer) ·
**F-23** (`send-push` ignores notification preferences).

---

## 6 · What "complete" would require

1. Design and draw **the Bids tab** and **the listing-detail dialog matrix**.
2. Render the seven written-but-undrawn settings surfaces, plus the error boundary, outbid toast and status banner.
3. A and C resolve **B-1…B-5**; B writes the copy from those facts.
4. C implements and **device-verifies D-1…D-8**.
5. C reviews the handoff for implementation gaps — the owner's stated condition, not yet done.

**Until all five are true, this redesign is not complete, and this audit is the list of what is missing.**
