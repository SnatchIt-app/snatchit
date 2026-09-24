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
- **Correction (2026-09-24 ~17:35Z, D's finding, verified by A at `5b255838` and `e73553d2`): keeping v37 does not
  contain the false record. It only avoids two new routes into it.** Given a seller-win row, a buyer call already
  reaches `payoutDeferred` on the live v37:
  - `confirm_transfer_received` raises "…from current status: buyer_confirmed" (`0550:202`), which trips the
    `alreadyConfirmed` bypass (`confirm-and-release:207-209`).
  - The §5 guards pass: status `buyer_confirmed`, `disputed_at` null after a resolution (the row shape rehearsal 6
    produced with production's writer bodies), not released.
  - `executePayoutAttempt` (`:386`) then refuses with a code v37 already knows: after 148's hold checks, `PAYMENT_NOT_SUCCEEDED`, `PAYMENT_NOT_LIVE`,
    `PAYMENT_PARTIALLY_REFUNDED`, `SELLER_NOT_ONBOARDED` or `PAYOUT_AMOUNT_INVALID` (148 `:123-155`; before 148 the
    same set without the hold checks).
  - That becomes `not_eligible` (`:481-490`), then `payoutDeferred`, then a `payout_decisions` row with
    `buyer_confirmed true`.
  - If the claim does not refuse, a2's `release` audit row carries the same false flag.
  **Limits:**
  - Source only. The production body of `confirm_transfer_received` was not in R0's twelve.
  - Needs a seller-win row (0 today) and a buyer call that current clients do not offer on a resolved transfer
    (E-6). Older builds were not checked, and a direct API call remains possible.
  - Prospective, not urgent. **It needs its own fix, not the `confirm-and-release` deploy decision:** `payoutDeferred`
    and the `:401-421` audit must not assert a buyer confirmation when `buyer_confirmed_at` is NULL.
- **Follow-up (2026-09-24 ~17:45Z, D's second pass; A verified each point):**
  - **Only the genuine buyer can trip the bypass.** `0550:201` checks buyer identity before `:202` checks status, and
    §5 checks `buyer_id` again.
  - **The mechanism, not just the rehearsal row:** a seller-win is 065's unfreeze branch (`065:120-124`), and
    `065:151` sets `disputed_at` to NULL on unfreeze.
  - **Rank a2 (`:401-421`) above a1.** a2 is on the success path, so money has moved. It needs no hold: after 148,
    an unheld seller-win row claims cleanly and pays.
  - **Correction to D's "the falsity is confined to `confirm-and-release`":**
    - The edge writers in the deployed `enforce-transfer-expiry` are clean. `logDecision` (`:821-852`, called only
      from Phase 2 at `:1061/1075/1084`) and `recordManualReviewOnce` (`:870-897`) both write `buyer_confirmed:
      false`.
    - But (d) reaches `executePayoutAttempt`, which calls the DB writer a3 (`record_payout_attempt_result`,
      `20260906120000:814-823`). a3 sets `buyer_confirmed := v_t.status = 'buyer_confirmed'`.
    - For a seller-win row, `PAID_DURING_DISPUTE` is excluded explicitly (`:789`), so only `DUPLICATE_TRANSFER`
      (`:793-798`, two real Stripe transfers for one obligation) reaches it.
    - a4 (`flag_payout_reversal_required`, called by `stripe-webhook:681` on a chargeback lost after payout) uses
      the same expression. It becomes reachable for any seller-win row that (d) has paid.
    - Both routes are rare anomalies, but **deploying (d) did extend a3/a4 to seller-win rows through an automated
      path.**
  - **Fix scope is therefore all four writers, a1–a4.** Each must derive `buyer_confirmed` from
    `buyer_confirmed_at IS NOT NULL`, never from `status`, and none may prepend `BUYER_CONFIRMED` without it.
  - **Observation (D; not a finding):** a successful Phase 2b sweep writes no `payout_decisions` row. `sweepOne`
    only counts `'paid'`, and Phase 2b's only decision writer is the manual-review one. This predates #92, but (d)
    now carries operator-decided payouts, whose only record is then `payout_attempts` plus
    `transfers.payout_released_at`.
- **Complete writer inventory (D's exhaustive sweep, independently reproduced by A at `e73553d2`; 2026-09-24 ~17:55Z).**
  Every writer of `payout_decisions` in `supabase/migrations`, `supabase/functions`, `admin/src`, `web/src` and `src`
  is below. Every other mention is a read (116), a grant (074) or a comment. No `UPDATE`/`DELETE` writer exists.

  | Site | `buyer_confirmed` | Seller-win row |
  |---|---|---|
  | a1 `confirm-and-release:357-368` (`payoutDeferred`) | hard-coded `true` | **false record** |
  | a2 `confirm-and-release:401-418` (release audit) | hard-coded `true` | **false record** (ranked first) |
  | a3 `20260906120000:815-823` (`record_payout_attempt_result`) | `v_t.status = 'buyer_confirmed'` | **false record** (`DUPLICATE_TRANSFER` only) |
  | a4 `20260906120000:889-894` (`flag_payout_reversal_required`) | same expression | **false record** (after a (d) payout plus a lost chargeback) |
  | `enforce-transfer-expiry:825-846` (`logDecision`) and `:883-892` (`recordManualReviewOnce`) | hard-coded `false` | truthful |
  | `admin_release_held_payout`, `039:304`, redefined `0551:94` (the latest definer) | omitted, so the default `false` applies (`039:88`) | unreachable: `0551:88` returns false unless `status = 'seller_sent'` |

  **The fix scope a1–a4 is complete.** **FIXED IN PRODUCTION 2026-09-24 20:31Z:** migration 149 applied and `confirm-and-release` v38 deployed from gate `037092f0` (#93 package §12). Existing audit rows are not rewritten. **Fix drafted: SnatchIt-app/snatchit#93** (head `9fb450eb`, registry 149 and
  pgTAP 216, plus the `confirm-and-release` edge change). (Superseded: "draft only". Merged as `037092f0`; executed in production 20:31Z.)
  - a3 and a4 already have `buyer_confirmed_at` in `v_t`.
  - a1 and a2 also need the column **added to §5's select** (`5b255838:233` does not select it). Swapping the literal
    alone is not enough (D).
  - **Limit:** this is a repo-source sweep. Production's bodies for a3, a4 and `admin_release_held_payout` were not
    among R0's twelve, and R0-wide showed that production can drift from the repo.
  - **Narrowed from files, with no production read (D; A reproduced every value):**
    - At the gate, `claim_payout_attempt`, a3 and a4 each have exactly one repo definer, the same file
      `20260906120000`.
    - The claim body extracted from that file hashes to `083bf9a3…`. That is production's `claim_prosrc_md5` in
      148's P3 prestate (16:55:40Z), so production stored that file's claim text verbatim, comments included.
    - This rules out "the whole file drifted". It does not prove a3 or a4 individually, because an out-of-band
      replacement of one function is still possible.
    - One query would settle it: `md5(prosrc)` for the two functions against the repo bodies
      `6a8372b4ee470d7a6ab9c1e0754765da` (a3; 5,599 characters, 5,603 bytes, because of two em dashes) and
      `d86c2b36f40c83835624bbacee716d38` (a4; 1,741 bytes). **Not requested and not run.**
  - **Reading R0 correctly:**
    - All twelve of R0-wide's functions have their last repo definer in files `000`–`065`: `000` ×5, `047`, `0564`,
      `064` ×3, `065` ×2. None is in `20260906120000`.
    - The twelve were chosen *because* they differed on 2026-09-23. So R0 shows that drift exists among older
      functions; it does not show that production differs generally.
    - Functions applied by the Management-API path (147, 148) and this file's claim read back verbatim.

## Reader sweep — everything that treats `status='buyer_confirmed'` as buyer confirmation (A's read-only subagent, 2026-09-24; SERVER = #92 head `e73553d2`, CLIENT = `404bce38`)

This is the enumeration behind F-DISPUTE-SELLERWIN-1. The subagent's search patterns are recorded in its report. D's
earlier count of "five" came from D's own reads. D asked that its five be checked against this list, and that the
list be trusted where they differ.

| # | Class | Where | Status |
|---|---|---|---|
| a1 | (a) false record | `confirm-and-release` `payoutDeferred` (`:345-379`) → `payout_decisions` `BUYER_CONFIRMED` / `buyer_confirmed true` | **FIXED 2026-09-24 20:31Z** (149 + `confirm-and-release` v38; #93 package §12). History: unfixed. **Reachable on the live v37 today, given a seller-win row** (corrected 2026-09-24 after D; the earlier "reachable only via a redeploy" was wrong): any refusal v37 already recognises → `not_eligible` → `payoutDeferred`. F-CR-148-SHARED adds two more routes (see its correction) |
| a2 | (a) false record | `confirm-and-release` `:401-421`: the `release` audit row on a buyer-called payout of a seller-win, reason `BUYER_CONFIRMED`, `buyer_confirmed true` | **FIXED 2026-09-24 20:31Z** (149 + `confirm-and-release` v38; #93 package §12). History: unfixed; predates #92; direct API call only (current clients offer confirm only on `seller_sent`) |
| a3 | (a) false record | `record_payout_attempt_result` (`20260906120000:823`): the `reversal_required` decision sets `buyer_confirmed := status='buyer_confirmed'` | **FIXED 2026-09-24 20:31Z** (149 + `confirm-and-release` v38; #93 package §12). History: unfixed |
| a4 | (a) false record | `flag_payout_reversal_required` (`20260906120000:894`): the same expression | **FIXED 2026-09-24 20:31Z** (149 + `confirm-and-release` v38; #93 package §12). History: unfixed |
| a5 | (a) operator label | admin `src/lib/format.ts:78` "Buyer confirmed", shown on orders list, detail, marketplace, money and filter | unfixed (D's lane) |
| a6 | (a) operator label | admin `orders/[paymentId]/page.tsx:539-542` shows the stored `buyer_confirmed` flag, which is false only because a1–a4 wrote it | unfixed (D's lane) |
| a7 | (a) user copy | web `TransferStatusBadge.tsx:8` "Transfer Complete", `purchases/page.tsx:28-30` "Confirmed", `BuyerTransferPanel.tsx:195-196` "Transfer complete. Enjoy the show." | unfixed. The web equivalent of C's mobile fix; the web is a private preview (Vercel builds ignored) |
| a8 | (a) seller notice | `notify_transfer_state_inbox` (058 `:189`) | **fixed by #92** |
| a9 | (a) mobile copy | badge, status copy, Bids, payout line | **fixed by C** (`ca27d282`, `aee15697`, `404bce38`) |
| a10 | (a) | mobile `src/components/TransferStatusBadge.tsx:8` "Tickets Received" | dead code: not imported |
| b1 | (b) decision | `confirm-and-release:207` treats an "already buyer_confirmed" RPC error as "the buyer's goal is met" and pays at once, skipping (d)'s 15-minute wait | partly: #92's claim now enforces holds; the inference is unchanged |
| b2 | (b) detector | **CORRECTED 2026-09-24 (D's finding, verified by A at 117:289-303): the defect is UNDER-detection, not false cases.** `ops.detect_release_stuck` dates a `buyer_confirmed` row by `coalesce(buyer_confirmed_at, auto_release_at)` (:291). A seller-win row has both NULL, so `:303` `continue`s: **a genuinely stuck seller-win payout is never flagged.** Fix (A implements, D reviews): date seller-win rows by `dispute_resolved_at`, the (d) anchor, and EXCLUDE live holds and manual review. pgTAP: a stuck seller-win (positive), a held row (negative), a NULL anchor (regression). The earlier headline (false cases for held seller-win rows) is withdrawn. | open |
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

