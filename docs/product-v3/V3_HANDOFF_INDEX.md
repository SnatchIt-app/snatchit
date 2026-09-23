# V3 handoff index — C consumes from here

**Branch:** `design/frontend-audit-20260917` (worktree `/Users/josetascon/snatchit-audit`).
**Design target:** release source **`5b255838`** on `release/production-gate-20260918`.
**C's implementation branch:** `v3/midnight-app`.

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
| — | **Findings reconciliation** | `V3_FINDINGS_RECONCILED.md` | — | `a538e53b` | ✅ **supersedes the findings table in the matrix** |

## Remaining packages

| # | Package | Scope | Status |
|---|---|---|---|
| 2 | Discovery → bidding → checkout | bid entry, checkout, payment outcomes, listing dialogs, outbid toast, status banner | ⬜ next |
| 3 | Selling and listing management | Create (5 sections, 3 pickers, 8 alerts), My listings, Edit, payout setup/return/refresh | ⬜ inventory complete |
| 4 | Orders, transfers and support | Send transfer, report/dispute, support, the blocked `expired`/`reversed` buyer states | ⬜ inventory complete |
| 5 | Tickets, account, settings, auth | Tickets, Profile, 10 settings routes, auth, security notice, error boundary | ⬜ inventory complete |

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
