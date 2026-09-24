# Two items raised on the 2026-09-23 release night — assessed 2026-09-24 (A) and RETRACTED AS FINDINGS by D (2026-09-24 ~03:30Z)

**Status: neither is a finding.** F-1 is the house pattern (D: 69 kernel functions carry `authenticated` EXECUTE on the same auth.uid()-derived basis, including admin_refund, grant_platform_role and release_payout; granting service_role would make auth.uid() null and the verb raise). F-2 is housekeeping. Both records below stand as the evidence for that conclusion.

Owner instruction: "record the exact affected object, practical consequence, evidence and owner. Assess urgency from the actual access and detection paths; prepare bounded fixes where warranted, without applying production changes." No production change was made or is proposed here.

## F-1. `kernel.resolve_dispute_native` — EXECUTE granted to `authenticated`, not `service_role`

| | |
|---|---|
| **Exact object** | `kernel.resolve_dispute_native(p_dispute_id uuid, p_outcome text, p_reason_code text, p_command_key text) returns jsonb`, SECURITY DEFINER, `search_path = ''` — defined and granted by `088_market_native_rail.sql:913` (grant at :1850). Siblings `kernel.record_dispute_native(...)` and `kernel.mark_dispute_state(...)` are granted to `service_role` (:1859–1860). |
| **What it actually does** | Authority first: `auth.uid()` required, then `kernel.is_platform(array['platform_risk','platform_support','platform_admin'])` (077: a `kernel.platform_role` row for the caller, or `public.admin_users` membership for `platform_admin`) — else `42501`. Then input validation and a `kernel.dispute_native` existence check. Then it **always raises** `precondition_failed: dual_control_unavailable` (PFA-31, "PARKED FAIL-CLOSED … ZERO mutation"; header 088:905–912). It resolves nothing, by design, until the dual-control mechanism exists. |
| **Practical consequence** | None today. The grant is the design, not an inconsistency: the record/mark verbs are edge (service-role) writers; `resolve` is a human platform-staff verb (identity-checked like its "identity twin", 096 header), so `authenticated` is the correct grantee and `service_role` is deliberately absent. `kernel` is PostgREST-exposed, so any logged-in user can *call* it — and receives `42501` unless they hold a platform role; a platform-role holder receives `dual_control_unavailable`. No mutation is reachable by any caller. No edge, admin, venue or client code references it (grep across `supabase/functions`, `admin/`, `venue/`, `src/`, `app/` at the gate: none); `kernel.dispute_native` holds 0 rows (D, production read 02:29Z). |
| **Evidence** | Source lines above (gate `5b255838`, which production's kernel schema matches per the 2026-09-22 release read-backs); D's grant and row-count reads from production 2026-09-24 02:29Z. |
| **Owner** | B (kernel / native rail design, PFA-31) with the owner for the un-park decision (DISPUTE_DUAL_CONTROL). |
| **Urgency** | None. Access path: platform roles only, and even they cannot mutate. Detection path: not applicable. **No fix warranted.** The one thing to carry: when the native dispute handling is ever wired into stripe-webhook (edge, service role), it must call `record_dispute_native` / `mark_dispute_state`, never `resolve_dispute_native` — the grant split enforces that. |

## F-2. Open ops case `650e7344…` "watched by no detector"

| | |
|---|---|
| **Exact object** | `ops."case"` id `650e7344-27f2-4b5c-a4c7-9d4b2cbf3f0e`: `case_type = 'manual'`, `subject_kind = 'none'`, no subject, `priority p3`, `detector = 'manual'`, status `open`, created and last seen 2026-09-08 01:42:03Z, unassigned, title **"Acceptance probe G7 — synthetic case (safe to dismiss)"**; four events (created, action_requested, note_added, action_outcome). Read 2026-09-24 02:52Z. |
| **Practical consequence** | It is a synthetic case created by the admin-console acceptance probe G7 (2026-09-08, the console go-live) and left open. `manual` cases are, by definition, never re-detected or auto-resolved (only detector-owned case types go through `ops.detect_sweep` → `ops.case_auto_resolve`), so "no detector watches it" is the designed behaviour for its type, not a detection gap. Effect: it counts as 1 of the 19 open cases and shows in the console's open list; no money, alert, or customer impact; no alert row is tied to it. |
| **Evidence** | Production read above; 115/117 source: `case_auto_resolve` is invoked per detector case type from `detect_sweep`; `manual` has no detector. (Note for the record: a substring probe for detectors mentioning the type matched `detect_payout_review` only because its source contains `manual_review` — a false match, discarded.) |
| **Owner** | D (console acceptance; the probe's author) to dismiss it through the console's own audited action (`ops.case_dismiss`/dismiss with a note), or the owner. |
| **Urgency** | None. **Bounded fix:** one operator dismissal in the console, with note "acceptance probe G7 — synthetic". It is a production write (an audited runtime action, not SQL), so it is NOT performed under this instruction; it is queued for whoever the owner designates. No code change. |

## Not a finding, but adjacent and worth one line
The three "present but inert" features (native dispute wiring; b2 push challenge; 139 report dedupe) and their independent dependencies are recorded in SPRINT_STATUS_20260917.md (2026-09-24 entries). F-1 above is the grant note that belongs with the first of them.

## Additions from D's retraction (2026-09-24)
- **PFA-31 park = a third, independent reason the native dispute feature does nothing**, separate from the missing edge import (nothing imports native-dispute.ts) and from the notify-exposure question (irrelevant to it): native dispute RESOLUTION is parked fail-closed until a dual-control mechanism exists (DISPUTE_DUAL_CONTROL). Recorded in the inert list.
- Open-case composition at 02:29Z (D): 19 = 5 dispute_open + 8 paid_unsettled + 3 report_review + 2 refund_pending + 1 synthetic probe (650e7344). `ops-detect-tick` runs `run_all_detectors` every 5 minutes over 13 named detectors, none of which emits type `manual`.
- Rule applied: an edge function must never call resolve_dispute_native with the service key; it forwards the operator's own JWT (EA-1, as delete-account does).

## F-DISPUTE-SELLERWIN-1 — a seller-win dispute resolution has no payout path (A, 2026-09-24; source-verified at gate `5b255838`; D confirmed the anchors independently)

**Object.**
- `public.resolve_transfer_dispute` (065:119-129) with outcome `seller_win` sets status `'buyer_confirmed'`, clears
  `disputed_at`, sets `dispute_resolution='resolved_seller_paid'`, and leaves `buyer_confirmed_at` NULL.

**Why no payout follows.**
- **Selection:** the payout sweep (`enforce-transfer-expiry` Phase 2b, gate :1180-1182; the same filter is on main
  :804-806) takes status `'buyer_confirmed'` only with `buyer_confirmed_at` older than 15 minutes, so a NULL never
  matches.
- **Console:** `ops.execute_action` `payout_release` (144:813) accepts only `seller_sent`.
- **The protocol would allow it:** `claim_payout_attempt` (20260906120000, lines 56-60) accepts `'buyer_confirmed'`,
  explicitly allows `dispute_resolution='resolved_seller_paid'`, and needs no `buyer_confirmed_at`. The defect is
  **selection only**.

**Practical consequence.**
- The seller is never paid for a dispute they won. The money stays on the platform; it is not lost.
- An ops `release_stuck` case is expected to surface it.
- **Affected today: 0 rows**, because no dispute has ever been resolved (`dispute_resolutions` 0 rows), while **5
  disputes are open** [D's production read]. The first seller-win resolution will hit it.

**Second defect on the same transition, from the trace.**
- `notify_transfer_state_inbox` (058) fires on any change of status to `'buyer_confirmed'`. It gives the seller an
  in-app "Buyer confirmed receipt — The buyer confirmed they received the tickets" row.
- After a seller-win resolution that statement is false; the buyer disputed.
- Only the web app reads those rows today.

**Bounded fix — proposed, NOT implemented.** Payouts are a stop-and-ask area, and the fix needs an edge deploy.
1. **Selection, in the edge function:** add a third disjunct to the Phase 2b filter, `and(status.eq.buyer_confirmed,
   dispute_resolution.eq.resolved_seller_paid, dispute_resolved_at.lt.<stale>)`. The 15-minute quiet period then
   applies to the resolution time, and `claim_payout_attempt` stays the only authority on eligibility.
   - Tests: a seller-win row is selected after 15 minutes and not before; a buyer-win row is never selected.
   - Negative control: remove the disjunct, and the seller-win test must fail.
2. **Notification, in a migration:** in `notify_transfer_state_inbox`, skip the `transfer_confirmed` row when
   `NEW.dispute_resolution = 'resolved_seller_paid'`, and emit a truthful "dispute resolved in your favour" row
   instead, or none.
3. **Optional, console:** let `payout_release` accept status `'buyer_confirmed'` with `resolved_seller_paid`, as a
   manual path.

**The compound, D's point, verified at source by both A and D (058:189-191, 065:129).** One transition does both
things at once: the seller is told the *buyer* confirmed receipt, and the transfer lands in the one state nothing
pays. The false reassurance gives the seller a specific reason not to chase the missing payout, which makes this the
combination most likely to go unreported. Both defects are at 0 instances for the same reason; the first seller-win
resolution fires both.

**Two separate owner decisions, not one:**
- **(a) Payout selection**, fix 1 (with the optional 3). A payouts stop-and-ask decision, plus interim handling
  (checklist P6).
- **(b) Truthful notification**, fix 2. A product-copy ruling that touches C's lane: either the trigger distinguishes
  an operator-resolved transition from a genuine buyer confirmation, or the resolution uses a status that does not mean
  "the buyer confirmed". Established only server-side at 058:191; whether any client code also hardcodes the string was
  not checked.

## F-LISTING-CRITICAL-TIER-1 — the "critical" risk tier blocks listing creation only in the client (raised by C, verified by A at source, gate `aadf996e`, 2026-09-24)

**Object.**
- `public.can_create_listing` (013:8-68) returns `allowed = false, reason 'critical_risk'` for `seller_risk_scores.risk_tier = 'critical'`. It is advisory: the clients call it before inserting.
- The server-side enforcement is:
  - `listings: auth insert` (070:36-39): own `seller_id`, `stripe_onboarding_complete`, `phone_verified()`;
  - the `119_listing_block_insert_guard` BEFORE INSERT trigger, which refuses only `is_listing_blocked = true`.
- Neither reads `risk_tier`.

**Consequence.** A seller at the critical tier who is not admin-blocked is refused by the app, but can create a listing with a direct PostgREST insert using their own session.

**Related (C).** `refresh_seller_risk_score` has no scheduler in the repo. Its only automatic caller is `get_auto_release_candidates`, so tier changes, including the "back to medium after 30 clean days" self-heal, depend on a seller having a seller_sent transfer past auto-release.

**Evidence limits.**
- Source only.
- Whether any production seller is at the critical tier is unknown; no production read.
- Whether 119 is applied in production was not re-read here.

**Bounded fix, proposed, NOT implemented.** Extend the 119 guard to also refuse `risk_tier = 'critical'`, matching `can_create_listing`, with a pgTAP case and a negative control. It is a listing-restriction policy change, so it is an owner decision.

## F-CR-148-SHARED — `confirm-and-release` must not be redeployed from a tree containing #92 until `payoutDeferred` is fixed (A, 2026-09-24; D traced both branches independently)

- `confirm-and-release` bundles `_shared/payouts.ts`. #92 adds `PAYOUT_HELD` and `PAYOUT_UNDER_REVIEW` to
  `PAYOUT_NOT_ELIGIBLE_REASONS`.
- With #92's file, a claim refused for a held seller-win row becomes `not_eligible` → `payoutDeferred`
  (`confirm-and-release/index.ts:345-376`). That inserts a `payout_decisions` row with `buyer_confirmed true`,
  `reason_codes ['BUYER_CONFIRMED', <code>]`, `dispute_open false` and `risk_tier 'low'`, all hard-coded. This is an
  operator-facing record saying the buyer confirmed, on a transfer the buyer disputed and lost.
- **Deployed v37, unchanged (the R1 plan):** `rpcReason` does not know the codes, so the outcome is `db_error` at stage
  `claim`. The function logs with `console.error`, returns 200 "processing", moves no money and writes nothing. This is
  expected log noise until the fix ships.
- **Constraint:** no `confirm-and-release` deploy from `release/production-gate-20260918` once #92 has merged into it,
  and none from any other tree containing #92, until `payoutDeferred` handles these two codes without a
  confirmation claim.

## Reader sweep — everything that treats `status='buyer_confirmed'` as buyer confirmation (A's read-only subagent, 2026-09-24; SERVER = #92 head `e73553d2`, CLIENT = `404bce38`)

This is the enumeration behind F-DISPUTE-SELLERWIN-1. The subagent's search patterns are recorded in its report. D's
earlier count of "five" came from D's own reads. D asked that its five be checked against this list, and that the
list be trusted where they differ.

| # | Class | Where | Status |
|---|---|---|---|
| a1 | (a) false record | `confirm-and-release` `payoutDeferred` (`:345-379`) → `payout_decisions` `BUYER_CONFIRMED` / `buyer_confirmed true` | unfixed; reachable only via a redeploy (F-CR-148-SHARED) |
| a2 | (a) false record | `confirm-and-release` `:401-421`: the `release` audit row on a buyer-called payout of a seller-win, reason `BUYER_CONFIRMED`, `buyer_confirmed true` | unfixed; predates #92; direct API call only (current clients offer confirm only on `seller_sent`) |
| a3 | (a) false record | `record_payout_attempt_result` (`20260906120000:823`): the `reversal_required` decision sets `buyer_confirmed := status='buyer_confirmed'` | unfixed |
| a4 | (a) false record | `flag_payout_reversal_required` (`20260906120000:894`): the same expression | unfixed |
| a5 | (a) operator label | admin `src/lib/format.ts:78` "Buyer confirmed", shown on orders list, detail, marketplace, money and filter | unfixed (D's lane) |
| a6 | (a) operator label | admin `orders/[paymentId]/page.tsx:539-542` shows the stored `buyer_confirmed` flag, which is false only because a1–a4 wrote it | unfixed (D's lane) |
| a7 | (a) user copy | web `TransferStatusBadge.tsx:8` "Transfer Complete", `purchases/page.tsx:28-30` "Confirmed", `BuyerTransferPanel.tsx:195-196` "Transfer complete. Enjoy the show." | unfixed. The web equivalent of C's mobile fix; the web is a private preview (Vercel builds ignored) |
| a8 | (a) seller notice | `notify_transfer_state_inbox` (058 `:189`) | **fixed by #92** |
| a9 | (a) mobile copy | badge, status copy, Bids, payout line | **fixed by C** (`ca27d282`, `aee15697`, `404bce38`) |
| a10 | (a) | mobile `src/components/TransferStatusBadge.tsx:8` "Tickets Received" | dead code: not imported |
| b1 | (b) decision | `confirm-and-release:207` treats an "already buyer_confirmed" RPC error as "the buyer's goal is met" and pays at once, skipping (d)'s 15-minute wait | partly: #92's claim now enforces holds; the inference is unchanged |
| b2 | (b) detector | `ops.detect_release_stuck` (117 `:288-300`) treats the status as a due release with no hold or manual-review exclusion. After #92 it would open false "Seller funds release stuck" cases for **held** seller-win rows (dated by `coalesce(buyer_confirmed_at, auto_release_at)`, never checked when that is NULL) | unfixed |
| b3 | (b) | `claim_payout_attempt`: seller-win inherited the genuine-confirmation hold override | **fixed by #92** |
| b4 | (b) | Phase 2b (a)+(b) never selected seller-win rows | **fixed by #92** with (d). Legacy runbook rows (no timestamp, no resolution) remain unselected |

- **Class (c)** is about 20 benign uses, listed in the subagent report and not repeated here.
- One adjacent copy question for C and the owner: after a seller-win payout, the losing buyer receives "Order complete …"
  (push, `enforce-transfer-expiry:917-921`) and the in-app "…Enjoy the event!" (148 `:250-255`). Both fire on
  `payout_released_at`, as for any payout.
- **Bearing on R1: none blocking.** #92's (d) path writes only `buyer_confirmed: false` decisions
  (`enforce-transfer-expiry:883-897`), so it adds no false record.

## F-PROD-REPO-DRIFT-1 — 12 production functions differ from the repository's migration chain (A and D, 2026-09-24; OPEN)

- **Evidence:** the 2026-09-23 ~03:11Z production capture `apply_5b255838/out/prod_untouched_fns.txt`, of functions
  the 24-file release did not redefine, as md5(`pg_get_functiondef`) 8-character prefixes. Compared with the gate
  chain's replay, **12 of 61 differ**:
  - with 148's premise: `resolve_transfer_dispute`, `admin_resolve_dispute`;
  - payment path: `record_transfer_payout`, `claim_stripe_webhook_event`, `complete_stripe_webhook_event`,
    `fail_stripe_webhook_event`, `finalize_auction`;
  - others: `auto_finalize_expired_auctions`, `validate_and_apply_bid`, `guard_listing_identity_columns`,
    `handle_new_user`, `handle_new_user_notification_prefs`.
- **Offline decomposition is negative.** Nine attribute-only variants of the local definitions (search_path
  `''` / `public,pg_temp` / `public,extensions` / none; SECURITY DEFINER removed or added; a trailing newline; CRLF;
  as-is) reproduced **none** of the twelve production prefixes. So the difference is most likely in the bodies.
- `resolve_transfer_dispute` has exactly one definition in git: 065, `c11c8b45`, never edited. So production was not
  built purely from this repository's chain for at least that function.
- **What is production-verified, by hash or bytes, for tonight's work:**
  - `claim_payout_attempt` (defn `d3cd9fdd` equal);
  - `notify_transfer_state_inbox` (`37a46d03` equal);
  - 147's `get_unsettled_payments` (D's production read);
  - the deployed `enforce-transfer-expiry` source (09-22/23 byte download).
- **Source-only, and therefore provisional until R0-wide:**
  - the F-DISPUTE-SELLERWIN-1 writer shape;
  - the legacy refund and payout tracing;
  - reasoning that rests on `record_transfer_payout` (the two-generations account of the 23 transfer ids);
  - the `finalize_auction` and webhook-claim reasoning.
  These are not known to be wrong. They rest on an assumption this finding puts in question.
- **Resolution path:** R0-wide (package §8), one definitions-only production read, compared by `r0_read.sh`, then a
  ranked diff. Expect some drift to be benign, and rank it so that it does not bury the one that matters.

### F-PROD-REPO-DRIFT-1 — RESOLVED by R0-wide (2026-09-24 16:33Z; owner-authorised definitions-only read)

- 11 of 12 are **logically identical** to the repo.
  - Comments only (8): `resolve_transfer_dispute`, `admin_resolve_dispute`, `record_transfer_payout`,
    `claim_/complete_/fail_stripe_webhook_event`, `finalize_auction`, `validate_and_apply_bid`.
  - Keyword case and comments (3): `auto_finalize_expired_auctions`, `guard_listing_identity_columns`,
    `handle_new_user_notification_prefs`.
  - The production bodies were applied through a route that dropped comments or re-cased keywords. The route used since
    2026-09-22 preserves both.
- **The provisional source-only conclusions stand:** the writer shape, `record_transfer_payout`, the webhook claim
  functions and `finalize_auction`.
- **One real difference, F-BASELINE-HANDLE-NEW-USER-1.** Production's `handle_new_user` inserts `full_name`,
  `display_name` and `avatar_url` from `raw_user_meta_data`. The repo's only definition, `000_baseline_schema.sql:21`,
  inserts `id` only. 041's own comments ("avatar_url is set once, server-side, by handle_new_user()") describe the
  production behaviour, so the baseline reconstruction is incomplete; production is not wrong.
  - **Impact:** fresh replays, CI and local rehearsal DBs create profiles without those three fields, so any test that
    depends on them passes or fails for a reason production does not share.
  - **Not a production change, and not #92's concern.** The fix is a repo-side decision (a numbered migration
    restating production's body, applied as a verified no-op), for the owner and A later.
  - **Direction matters (D):** production is *richer* than the repo. Anyone rebuilding or restoring production from this
    repository's chain would ship a `handle_new_user` that silently stops populating `full_name`, `display_name` and
    `avatar_url` for new sign-ups, and no repo test would fail, because the tests know only the repo's version. This is
    a restore and disaster-recovery risk, not only a test-fidelity one.
- D reviewed the R0 result independently and gave a PASS, with the same classification (§12 of the #92 package).

