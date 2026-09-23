# V3 handoff index — C consumes from here

**Branch:** `design/frontend-audit-20260917` (worktree `/Users/josetascon/snatchit-audit`).

**Commits reviewed, pinned:**

| Ref | Exact commit | What was read from it |
|---|---|---|
| Release source | **`5b255838dea3d39561714554a547a6121ab2c8ff`** (`release/production-gate-20260918`) | every finding in `V3_FINDINGS_RECONCILED.md`; the transfer render paths; the fee model |
| C's V3 branch | **`31819593ec7a616985abbac0f258e8c3208d3f82`** (`v3/midnight-app`) | cross-check that F-17b, F-18, F-21 and F-22 are present there too; confirmation that O-2, O-3 and O-5 are implemented |

Re-pin both if either ref moves; every ① label in the register is measured against these two commits and
nothing else.

Direct session-to-session delivery is unavailable from B's session, so **this file is the delivery mechanism**.
Every completed package is listed here with its commit. Pull the branch and read down the table; nothing needs
forwarding.

---

## Completed packages

| # | Package | Documents | Artifacts | Commit | Status |
|---|---|---|---|---|---|
| — | Approved visual direction | `V3_ROUND3_TYPOGRAPHY_NAV_AND_APPROVAL_20260922.md` | `mockups-v3/midnight-{home,search,listing,order}-{clean,annotated}.png`, 5 state images, 2 comparison sheets | `404744a7` | ✅ owner-approved 2026-09-22 |
| — | First handoff to C | `V3_DESIGN_PACKAGE_FOR_C_20260922.md`, `HANDOFF_NOTE_TO_C_20260922.md` | — | `404744a7`, `d420a28f` | ✅ consumed — O-2, O-3, O-5 implemented on `v3/midnight-app` |
| **1** | **Shared foundations, navigation, reusable states** | `V3_PACKAGE_1_FOUNDATIONS_FOR_C.md` | `pkg1-foundations.png`, `pkg1-components.png`, `pkg1-states.png` | `d6a757ab` | ✅ ready to implement |
| — | Coverage matrix (living) | `V3_COVERAGE_MATRIX.md` | — | `d6a757ab`, baseline corrected in `a538e53b` | 🟡 living document |
| — | **Findings reconciliation** | `V3_FINDINGS_RECONCILED.md` | — | `a538e53b` | ✅ **supersedes the findings table in the matrix**; copy corrected per owner 2026-09-22 |
| **2** | **Discovery → bidding → checkout** | `V3_PACKAGE_2_BIDDING_CHECKOUT_FOR_C.md` | `pkg2-bid-entry-{clean,annotated,submitting}.png`, `pkg2-checkout-{clean,annotated}.png`, `pkg2-checkout-states.png` | `01fe02ed` | ✅ ready to implement |

| **3** | **Selling, creation, editing, listing management** | `V3_PACKAGE_3_SELLING_FOR_C.md` | `pkg3-create-{clean,annotated,invalid}.png`, `pkg3-my-listings-{clean,annotated,empty}.png`, `pkg3-selling-dialogs.png` | `6cb26a4d` | ✅ ready to implement |
| **4** | **Orders, transfers, disputes, support** | `V3_PACKAGE_4_TRANSFERS_SUPPORT_FOR_C.md` | `pkg4-send-{clean,pending,seller_sent,expired}.png`, `pkg4-transfer-matrix.png`, `pkg4-dispute-support.png` | `63d252c4` | ✅ ready; 3 cells blocked on A/C |
| **5** | **Tickets, profile, settings, auth, security notice** | `V3_PACKAGE_5_ACCOUNT_FOR_C.md` | `pkg5-auth.png`, `pkg5-tickets-profile.png`, `pkg5-settings-account.png` | `965c46ad` | ✅ ready to implement |
| **6** | **Completion: Bids tab, listing role/action matrix + 17 dialogs, 7 settings surfaces, system surfaces** | `V3_PACKAGE_6_COMPLETION_FOR_C.md` | `pkg6-bids-*.png`, `pkg6-listing-action-matrix.png`, `pkg6-listing-dialogs.png`, `pkg6-settings-surfaces.png`, `pkg6-system-surfaces.png` | `c5c7282e` | ✅ ready to implement |
| — | **GAP AUDIT — read this before claiming completion** | `V3_GAP_AUDIT.md` | — | `01822004` | ⛔ **2 surfaces undesigned, 5 blocked, 8 device checks outstanding** |

## Two distinctions that travel with every package

1. **"Implemented on C's branch" does not mean shipped or deployed.** `v3/midnight-app` is isolated: not in the
   release source, not in a build, not in production.
2. **Displaying a partial refund does not mean the system automatically resolves partial-refund obligations.**
   Refund status and refund amount are separate facts, and neither may be inferred from a transfer status.

## Package 2 — what C must verify about the restyled pay control

The six progress states were restyled from red primaries to neutral status lines. C verifies that the restyle
preserves, unchanged:

- the **payment-state ordering** in `payControl.ts` (a lost hold outranks a ready payment; an unknown payment
  status outranks both);
- **repeated-tap protection** — the single-flight lock and the disabled/loading gating;
- **retry behaviour** for `Check again` and `Try again`;
- **accessible status announcements** — `accessibilityState={{ disabled, busy }}` and the pending label being
  what a screen reader hears.

**Every existing pay-control state has an explicit design mapping on `pkg2-checkout-states.png`. None may
disappear during restyling.**

## Remaining packages

All five packages are delivered. **What remains is in `V3_GAP_AUDIT.md`:**

| | Outstanding | Owner |
|---|---|---|
| ✅ | The Bids tab, the listing role/action matrix, all 17 listing dialogs, the seven settings surfaces, error boundary, outbid notice, status banner | **done — Package 6 `c5c7282e`** |
| 🚫 | `expired` / `reversed` state blocks (3 cells) and the release wording | A, then B |
| 🚫 | The buyer review-deadline field | C |
| 🔍 | Eight device checks — **nothing is device-verified** | C |

---

## What C should act on now

1. **Package 1** — `V3_PACKAGE_1_FOUNDATIONS_FOR_C.md`, 10 acceptance criteria. The three foundation
   amendments are **owner-approved**: neutral decorative hairlines, mixed-case sentence headings, and rounded
   controls **applied by component role — not globally**. Radius 0 stays for rules, dividers, the underlined
   Input and Badge; `media: 8` for artwork; `chrome: 22` for Button, Chip, Sheet and the search field; the dock
   keeps 33. **Keep both mirrored token definitions consistent** (`src/theme/v2.ts` and
   `packages/design-tokens/src/brand.ts`).
2. **Validate the client findings** labelled ① in `V3_FINDINGS_RECONCILED.md`: F-1, F-5, F-6, F-16, F-20, F-21,
   and whether `expired`/`reversed` are reachable in practice.
3. **Do not implement the proposed `expired`/`reversed` buyer copy** — it is drafted for review and explicitly
   not approved. Status alone is not payment evidence.

## What A should act on now

- **O-1** — the automatic-release wording on the order screen (still blocking that screen).
- **F-22** — is `auto_release_at` the right date to show a buyer, and may it be shown?
- **F-23** — should transfer/dispute/expiry pushes respect notification preferences?
- The proposed neutral copy for `expired` / `reversed`, and whether a refund field exists that would let the
  sentence be split into a definite and a neutral form.

## Standing constraints

- No changes to payment, reservation, refund, payout, transfer, security or ownership rules.
- No new caching, query, notification or backend capability without separate approval; any dependency is
  called out as proposed work.
- Saved delivery preferences remain **proposed, not built**.
- V3 stays on an isolated branch, out of the production safety release. No deployment, release build or store
  submission.
