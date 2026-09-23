# V3 handoff index — C consumes from here.

**Status: the freeze was REOPENED by the owner on 2026-09-23 for an app-wide copy and hierarchy correction
(Package 7).** Ordinary copy simplification is authorised across all six packages without further approval.
Package 7 is **authoritative over the earlier packages wherever they conflict**, including the requirement to
repeat amounts in button labels.
B's role from here is **targeted design support and review of implemented screens** — no further broad
exploration, no new packages. Ask B for a specific surface, a correction, or a review of what C has built.

**Branch:** `design/frontend-audit-20260917` (worktree `/Users/josetascon/snatchit-audit`).
Direct session-to-session delivery is unavailable from B's session, so **this file is the delivery
mechanism**. Pull the branch and read down the tables; nothing needs forwarding.

**Commits reviewed, pinned:**

| Ref | Exact commit | What was read from it |
|---|---|---|
| Release source | **`5b255838dea3d39561714554a547a6121ab2c8ff`** (`release/production-gate-20260918`) | every finding in `V3_FINDINGS_RECONCILED.md`; the transfer render paths; the fee model; the dialog and action inventories |
| C's V3 branch | **`31819593ec7a616985abbac0f258e8c3208d3f82`** (`v3/midnight-app`) | cross-check that F-17b, F-18, F-21, F-22 are present there too; confirmation that O-2, O-3, O-5 are implemented |

Re-pin both if either ref moves; every ① label is measured against these two commits and nothing else.

---

## Read in this order

| Order | Document | Why |
|---|---|---|
| 0 | **`V3_PACKAGE_7_COPY_CORRECTION.md`** | The app-wide copy correction. **Read first — it overrides earlier package text wherever that text caused clutter.** §9 lists what C must change in code already written |
| 1 | **`V3_FREEZE_RECONCILIATION_20260922.md`** | The two corrections made at the freeze. **Read before the packages** — it supersedes the dialog count and the colour rule in Package 6 |
| 2 | `V3_COVERAGE_MATRIX.md` §"Reconciliation" | Every surface in four independent states |
| 3 | `V3_PACKAGE_1…6_*_FOR_C.md` | The work itself, in flow order |
| 4 | `V3_FINDINGS_RECONCILED.md` | 27 findings, each labelled ①–⑤. **Not redesign work** |
| 5 | **`V3_GAP_AUDIT.md`** | What is still blocked, unimplemented or unverified. **Read before any completion claim** |

---

## Completed packages

| # | Package | Documents | Artifacts | Commit | Status |
|---|---|---|---|---|---|
| — | Approved visual direction | `V3_ROUND3_TYPOGRAPHY_NAV_AND_APPROVAL_20260922.md` | `midnight-{home,search,listing,order}-{clean,annotated}.png`, 5 state images, 2 comparison sheets | `404744a7` | ✅ owner-approved |
| — | First handoff to C | `V3_DESIGN_PACKAGE_FOR_C_20260922.md`, `HANDOFF_NOTE_TO_C_20260922.md` | — | `404744a7`, `d420a28f` | ✅ consumed — O-2, O-3, O-5 implemented |
| **1** | Shared foundations, navigation, reusable states | `V3_PACKAGE_1_FOUNDATIONS_FOR_C.md` | `pkg1-foundations.png`, `pkg1-components.png`, `pkg1-states.png` | `d6a757ab` | ✅ ready |
| **2** | Discovery → bidding → checkout | `V3_PACKAGE_2_BIDDING_CHECKOUT_FOR_C.md` | `pkg2-bid-entry-*`, `pkg2-checkout-*`, `pkg2-checkout-states.png` | `01fe02ed` | ✅ ready |
| **3** | Selling, creation, editing, listing management | `V3_PACKAGE_3_SELLING_FOR_C.md` | `pkg3-create-*`, `pkg3-my-listings-*`, `pkg3-selling-dialogs.png` | `6cb26a4d` | ✅ ready |
| **4** | Orders, transfers, disputes, support | `V3_PACKAGE_4_TRANSFERS_SUPPORT_FOR_C.md` | `pkg4-send-*`, `pkg4-transfer-matrix.png`, `pkg4-dispute-support.png` | `63d252c4` | ✅ ready; 3 cells blocked |
| **5** | Tickets, profile, settings, auth, security notice | `V3_PACKAGE_5_ACCOUNT_FOR_C.md` | `pkg5-auth.png`, `pkg5-tickets-profile.png`, `pkg5-settings-account.png` | `965c46ad` | ✅ ready |
| **6** | Completion: Bids tab, role/action matrix, listing dialogs, 7 settings surfaces, system surfaces | `V3_PACKAGE_6_COMPLETION_FOR_C.md` | `pkg6-bids-*`, `pkg6-listing-action-matrix.png`, `pkg6-listing-dialogs.png`, `pkg6-settings-surfaces.png`, `pkg6-system-surfaces.png` | `c5c7282e` | ✅ ready — **superseded in two places by the freeze reconciliation** |
| **FREEZE** | **Dialog-count and colour-semantics reconciliation** | **`V3_FREEZE_RECONCILIATION_20260922.md`** | `pkg6-listing-dialogs.png` and `pkg6-listing-action-matrix.png` **re-rendered** | **`77a122b4`** | ✅ **authoritative over Package 6 §2 and §3** |
| **7** | **Copy and hierarchy correction (app-wide)** | `V3_PACKAGE_7_COPY_CORRECTION.md` | `pkg7-bid-comparison.png`, `pkg7-listing-checkout-comparison.png`, `pkg7-order-comparison.png`, `pkg7-selling-comparison.png`, + after/annotated sheets | `14a6c3e6` (bid) · `03dbc240` (listing+checkout) · `659465ba` (order) · `b24ad197` (create+send) · this commit (search + sweep) | ✅ **authoritative over packages 1–6 on copy** |
| — | Coverage matrix (living) | `V3_COVERAGE_MATRIX.md` | — | reconciled `074776d0`, freeze update `77a122b4` | 🟡 living |
| — | Findings register | `V3_FINDINGS_RECONCILED.md` | — | `a538e53b`, + F-25/F-26/F-27 in `77a122b4` | ✅ supersedes the matrix's own findings table |
| — | **GAP AUDIT — read before claiming completion** | `V3_GAP_AUDIT.md` | — | `01822004`, `074776d0`, `c641c3c4`, `77a122b4` | ⛔ **3 cells blocked · 5 awaiting A/C · 8 device checks · nothing verified** |

---

## What the freeze corrected — both supersede Package 6

1. **The listing dialog set is 23 call sites / 24 copy variants, not 17.** Six were missing from the first
   board — **not consolidated away, simply absent**: `Cannot delete` (L824), `Delete listing?` (L830),
   `Cancel listing?` both bodies (L871a/b), `More actions` (L951), `Block {seller}?` (L976) and `Blocked`
   (L994). All six are restored, and every card now carries its **source line**.
   **New rule: a CONFIRM dialog (two buttons, destructive) may never be folded into a reporting pattern.**
2. **Red marks the buying path, not "money moves on tap".** None of the four red actions charges anything —
   three navigate and `buy_now` takes a reservation. The hierarchy is unchanged; the stated meaning now
   matches `runAction`. **Consequence is carried by labels and confirmations, never by colour.**

---

## Three distinctions that travel with every package

1. **"Implemented on C's branch" does not mean shipped or deployed.** `v3/midnight-app` is isolated: not in the
   release source, not in a build, not in production.
2. **Displaying a partial refund does not mean the system automatically resolves partial-refund obligations.**
   Refund status and refund amount are separate facts, and neither may be inferred from a transfer status.
3. **Nothing is device-verified.** Every artifact is a static image. No build, no simulator, no production read.

---

## What C acts on now

0. **Apply Package 7 §9 to code already written** — the bid screen's button label and its removed lines, the
   listing breakdown, the checkout kicker, the create review card. **O-2 is withdrawn**: it was my direction,
   C implemented it faithfully, and the owner has ruled against it. Nothing C built was wrong at the time.
1. **Implement Packages 1–6 in flow order**, reading Package 7 and then the freeze reconciliation first. Implement **complete
   flows** — dialogs, validation, errors and recovery — not only the main screens.
2. **Preserve, explicitly:** payment-state ordering in `payControl.ts` · repeated-tap protection (the
   single-flight lock, not a state guard) · reservation rules · role restrictions · truthful unknown-result
   handling · `pendingLabel="Reserving…"` on Buy now · `OutbidToast`'s `pointerEvents="none"` and below-header
   position.
3. **Rule on the three freeze findings:** **F-25** (divergent destructive-dialog copy across my-listings and
   listing detail — unifying it is a behaviour change, not a restyle) · **F-26** (`More actions` platform
   split; do not unify it into a custom sheet) · **F-27** (no failure path refetches; the fix is drawn
   **PROPOSED**).
4. **Validate the ① client findings:** F-1, F-5, F-6, F-16, F-20, F-21, and whether `expired`/`reversed` are
   reachable in practice.
5. **Own B-5** — the review-deadline field: authoritative field, applicable states, missing-value behaviour,
   refresh behaviour. Four questions are written out in `V3_FINDINGS_RECONCILED.md`.
6. **Do not implement the proposed `expired`/`reversed` buyer copy.** Drafted for review, explicitly not
   approved. Status alone is not payment evidence.

## What A acts on now

- **B-1 / B-2 / B-3** — what `expired` and `reversed` each establish about payment, and what payment evidence
  is readable on the transfer row. Buyer expired, buyer reversed and seller reversed are **three separate
  cells**; seller expired is already covered in the reviewed release (F-17a).
- **O-1 / B-4** — the automatic-release wording, with C.
- **F-23** — should transfer/dispute/expiry pushes respect notification preferences?

**Sequence for the three blocked cells:** A establishes what each server state proves and what evidence exists
→ C maps that evidence to the UI and confirms what renders → **B supplies the visual treatment**. No design
infers a full refund or a completed payout from a transfer status.

---

## Before requesting a device build

C completes a coherent implementation and runs the relevant checks, then provides **one consolidated device
plan** covering the eight recorded checks (D-1…D-8 in `V3_GAP_AUDIT.md`), actual screen-to-design comparisons,
and any remaining acceptance gaps. **A new build still requires its own explicit authorization.**

Report progress in four separate states — **designed · implemented · reviewed · device-verified** — and do not
call V3 complete or shipped until the corresponding evidence exists.

## Standing constraints

- No changes to payment, reservation, refund, payout, transfer, security or ownership rules.
- No new caching, query, notification or backend capability without separate approval; any dependency is
  called out as proposed work.
- Saved delivery preferences remain **proposed, not built**.
- V3 stays on an isolated branch, out of the production safety release. No deployment, release build or store
  submission.
