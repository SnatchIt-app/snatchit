# Production apply manifest — refund/payout safety release (A, 2026-09-22)

**Status: EXECUTABLE ONCE ITS PREFLIGHT PASSES; NOT YET APPLIED.** Owner's execution authorisation (2026-09-22)
covers applying the verified required migrations; every preflight item below must hold on the day. This file is the
single ordered list. Everything else (plan v3, registry) points here.

## 1. Source and versions
- Release gate `release/production-gate-20260918` @ **`c836bc43`** (after the reviewed merges: #86 → #85 auto,
  #83, #84, #81; #82 closed as landed). CI green at that head. Executable content identical to A's integration
  proof `3da63d9b` (tsc 0, lint 0, vitest 127 files / 2498) — only docs/local scripts differ.
- Migration files are the blobs at that head; the ledger rows to add are the 24 versions below.

## 2. The 24 files, in apply order (pending-file order = numbered before timestamped)

| # | File (`supabase/migrations/`) | Rollback (`supabase/rollbacks/`) | Class |
|---|---|---|---|
| 1 | `123_transfers_profiles_fk_parity.sql` | `123_transfers_profiles_fk_parity_rollback.sql` | parity (no-op expected; prove with [L2]) |
| 2 | `124_bids_profiles_fk_parity.sql` | `124_…_rollback.sql` | parity (+ fresh orphan count [L10]) |
| 3 | `127_release_reservation_guards.sql` | `127_…_rollback.sql` | required (RC edges) |
| 4 | `128_register_push_token_secure_rebind.sql` | `128_…_rollback.sql` | required (app push) |
| 5 | `129_public_revoke_push_token.sql` | `129_…_rollback.sql` | required (app sign-out) |
| 6 | `130_checkout_supersede_claim.sql` | `130_…_rollback.sql` | required (RC edge) |
| 7 | `131_session_bound_push_bindings.sql` | `131_…_rollback.sql` | required (push chain) |
| 8 | `132_checkout_group_claim.sql` | `132_…_rollback.sql` | required (RC edge) |
| 9 | `133_functions_base_url_from_config.sql` | `133_…_rollback.sql` | required; **Vault ceremony precondition** |
| 10 | `135_push_token_proof_of_possession.sql` | `135_…_rollback.sql` | required (app push; owner D-2) |
| 11 | `136_public_security_notices_read.sql` | `136_…_rollback.sql` | required (app) |
| 12 | `139_notify_report_delivery_claims.sql` | `139_…_rollback.sql` | required (notify-report edge) |
| 13 | `140_proof_upload_repair.sql` | `140_…_rollback.sql` | required (app send screen) |
| 14 | `142_payments_amount_refunded_cents.sql` | `142_…_rollback.sql` | required (app checkout read) |
| 15 | `143_ops_cron_history_bounded_reads.sql` | `143_…_rollback.sql` | safety package |
| 16 | `144_ops_refund_resolution_detector.sql` | `144_…_rollback.sql` | safety package (switch seeded off) |
| 17 | `145_ops_job_not_running_detection.sql` | `145_…_rollback.sql` | safety package — **live on apply, no switch** |
| 18 | `146_ops_alert_delivery_and_ack.sql` | `146_…_rollback.sql` | safety package (switch seeded off; nothing scheduled) |
| 19 | `20260906100000_checkout_reservation_authority.sql` | `…_rollback.sql` | RC (redefines `mark_listing_sold`, `complete_auction_payment`, `reserve_buy_now`) |
| 20 | `20260906110000_settle_verified_payment.sql` | `…_rollback.sql` | RC (redefines `cleanup_expired_reservations`) |
| 21 | `20260906120000_payout_attempts_and_refund_monotonic.sql` | `…_rollback.sql` | RC (payout attempt ledger) |
| 22 | `20260906130000_deletion_sweep_live_rail_obligations.sql` | `…_rollback.sql` | RC (redefines `kernel.sweep_deletion_pending`) |
| 23 | `20260909000000_kernel_my_tickets_read.sql` | `…_rollback.sql` | required (Tickets tab) |
| 24 | `20260916000000_processing_sweep_arm.sql` | `…_rollback.sql` | required (RC `enforce-transfer-expiry`) |

All 24 rollback files exist at `c836bc43` (checked by blob). **Excluded, deliberately:** `121` (deferred — applied only
under `AUTHORIZE PFA-18C MIGRATION 121`); `125`, `126` (optional track — **omitted as safely separable**, §4);
`137`, `138`, `141` (not in the tree). Ledger note: omitting 125/126 leaves them below the tip; a later apply of either
needs a targeted apply, never `db push`.

## 3. Production-order rehearsal evidence (run 3, 2026-09-22, gate-tree harness)
- Pre-apply world built in **production's historical order** (000–075, the 4 site-form timestamped files, 075–092, the
  relist RPC, 092–109, **115–120 before 110–114**, = 135 rows) on the canonical bootstrap + fidelity supplements.
- **Baseline body hashes of the pre-apply world EQUAL production's, read the same day:** `ops.job_health` `5621b447…`,
  `ops.detect_jobs` `b0d6497f…`, `ops.alert_fire` `dfcb1956…`, `mark_listing_sold` `7eb5525c…`,
  `complete_auction_payment` `d35ee07c…`, `kernel.check_signing_key_invariants` `928a4516…`, both `mark_transfer_sent`
  overloads → `void`; production also shows `ops.alert` = 8 columns, `net.http_request_queue` = 0 rows.
- **APPLY 24/24 ok**, one transaction each, all sub-second. Census after apply **32|108|37|38** — identical to the
  LC_ALL=C gate replay, so omitting 121/125/126 changes no public object count.
- **Compatibility window (deployed edges keep working between apply and function deploy):** after the apply, every
  RPC the deployed functions call resolves with the same identity arguments they use — `mark_listing_sold(p_listing_id
  uuid, p_user_id uuid)`, `complete_auction_payment(…)`, `release_reservation(p_listing_id, p_user_id)` (stripe-webhook
  v41); `record_transfer_payout(p_transfer_id uuid, p_stripe_transfer_id text)`, `get_auto_release_candidates()`,
  `apply_auto_release/apply_payout_hold/apply_manual_review`, `enforce_transfer_expiry()` (enforce-transfer-expiry
  v39 — none of these is redefined by the set); `check_rate_limit(…)`, `claim/complete/fail_stripe_webhook_event`,
  `freeze_transfer_for_dispute`, `mark_transfer_reversed` (unchanged). `mark_transfer_sent` becomes `jsonb` (140): no
  deployed edge calls it; the installed app never reads its return (C, Build 9 line-by-line; Build 22 fail-closed).
  **Correction (D's verification, 2026-09-22):** the pending redefinitions of edge-called functions are in
  `127` (`public.release_reservation(p_listing_id uuid, p_user_id uuid) → void`, identical to the applied 0590
  signature — 127's header builds on 0590) **and** `20260906100000/110000/130000`; all signature-preserving. The
  earlier enumeration omitted 127; the conclusion (window signature-safe) stands.
- **pgTAP on the production-order database: 5339 / 5347 pass.** The 8 failures are exactly the assertions in
  **184 (2) and 186 (6) that carry "(126)" in their names**; applying 126 to a copy makes 184 90/90, 186 27/27 and
  193 65/65 pass. So the evidence set for this manifest excludes 184, 186 (126-coupled), 189 (121), 190 (125),
  193 (126); every other file passes.
- Switches after apply: `refund_resolution_detector_enabled=false`, `alert_delivery_enabled=false`,
  `detectors_enabled=true`, `actions_enabled=true` (the last two equal production today).
- Forward-back-forward rollback battery on the same database: **PASS — §7.** Independence: D independently ran the
  143–146 quadrant (reverse application, identity md5s returning, history preserved) and cross-checks §7's identity
  values; the full 24-file reverse battery is A's run only unless D re-runs it (offered).
- §3a. **Widened baseline (18 bodies / 19 rows) — production vs the production-order pre-apply world, 2026-09-22:
  18 IDENTICAL** (incl. the three notify triggers 133 replaces and its rollback restores, `ops.action_dispatch` and
  `ops.execute_action` at 118's bodies, `run_job`, `run_all_detectors`, `kernel.sweep_deletion_pending`,
  `release_reservation`, `reserve_buy_now`, both `mark_transfer_sent` overloads); **ONE DIFFERENT:**
  `public.cleanup_expired_reservations()` — production `ecc0afc0…` vs repo `95c21a0e…`. Read and diffed: the
  bodies are the **same statements with different keyword casing** (BEGIN/PERFORM/UPDATE… vs lowercase) and a
  trailing blank line; the `app.bypass_listing_guard` line is present in both. Nothing in production calls it
  (no cron job, no deployed edge, zero recorded calls since the 2025-12-08 stats reset; 0 expired reservations).
  Manifest #20 redefines it with the bypass kept; #20's rollback restores the lowercase body — semantically
  identical to production's. **Benign for behaviour; #20's rollback made truthful, not environment-specific:** the rollback embedded the repo's 000
  text and *verified itself against the 000 hash*, so a production rollback would install a casing variant and pass its
  own check. A first amendment embedded production's captured text — **withdrawn on D's objection** (a shared rollback
  carrying one environment's bytes installs a body every other environment never had, breaks exact identity checks on
  the rehearsal database, and CI never executes rollbacks). Final shape, PR #90 @ `0d445a70` (D verification pending):
  the 000 body stays; the verification states the 000 values it expects, records production's pre-apply casing variant
  and hashes (capture kept at `docs/release/captures/…_20260922.sql`), and says a production rollback leaves a
  semantically identical body that hashes as the repo body. **Optional, production-only, manifest step (owner's choice;
  default: not run):** if #20's rollback is ever executed on production and byte-exact restoration is wanted, run the
  captured statement from that file afterwards. D's item-3 finding is what made this read
  cover the right set; a real hotfix would have surfaced exactly this way.

## 4. Why 125 and 126 are omitted
- No pending file after 125 redefines `venue.sync_scan_device_manifest`; scanning is dark. Separable.
- 144 only *calls* `ops.refresh_metrics()` / `ops.build_daily_summary()` (existing since 115/120); it redefines
  none of 126's objects. `20260906120000`'s only match is a `rollback_archive` table name. The live console runs
  against production's pre-126 bodies today. Separable at the database level; the coupling is test-only (§3).
- Owner decision D-1 is therefore not needed for this release; 126 remains B/D's optional track.
- **Stated for the owner (D):** this release ships the refund-resolution *detector* without 126's refund
  *exactness* — the console's refund figures do not become more exact with it. Not a regression; a scope statement.

## 5. Preflight (the day of the apply; each a read unless marked)
1. Owner's fresh AUTODEPLOY-1 dashboard confirmation (gate → nothing merges to `main` in this manifest anyway).
2. Ledger read = exactly the 135 rows, max numeric 120, 0 rows ≥ 121 (✓ 2026-09-22).
3. **Body hashes of all 18 pre-existing bodies the 24 files redefine** equal the production-order pre-apply world's
   (D's enumeration of every CREATE [OR REPLACE] FUNCTION across the 24 filtered to pre-121 definitions): the seven
   in §3 plus `kernel.sweep_deletion_pending`, `ops.action_dispatch`, `ops.execute_action`, `ops.run_all_detectors`,
   `ops.run_job`, `public.cleanup_expired_reservations`, `public.notify_bid_placed`, `public.notify_moderation_event`,
   `public.notify_transfer_event`, `public.release_reservation`, `public.reserve_buy_now`. The three notify triggers
   are the ones 133 replaces and its rollback restores byte-for-byte — a production body that differs from the
   rehearsal's would make that rollback restore the wrong body. Result of the widened read: see §3a.
4. **Vault ceremony (owner/credential action):** insert `project_url` = `https://hqycwntpfoztoinemqns.supabase.co`
   into Vault; then **read it back and assert string equality with that exact host** before file #9 — the purge guard
   in 133 keys on it (D). `service_role_key` is present in production's Vault (✓ names read 2026-09-22), so 133's own
   `REFUSED` guard is live if the ceremony is skipped: the migration fails closed, it does not go silent.
5. `net.http_request_queue` row count (0 on 2026-09-22): 133's purge deletes production-host rows; confirm none are
   legitimately pending.
6. Fresh backup exists (owner).
7. **Edge secrets preflight (✓ 2026-09-22, witnessed — 3–10 env names per function):** every secret the 10 gate
   functions read exists in production's secret names, except two read with defaults: `EMAIL_ENABLED` (absent =
   email off; owner item) and `EXPO_PUSH_URL` (absent = Expo's default endpoint). No deploy blocker.
8. Reviewer sign-offs on record: 133 — D (behaviour preservation, measured diffs) + A; B's invariant set not reopened.
   127/128/130/131/132/135/139/140 — D passes on record; 143–146 — A ×2; 142 — A; RC unit — payments RC review line.

## 6. Apply method (per file, the sandbox-window method)
Targeted apply = the file + its ledger row, never `db push`; read back per file: the ledger row, md5 of each new or
redefined body, grants vs `expected_grants.txt`, census. **Stop on the first non-matching read-back.**
**Pre-committed post-apply reference (D, fresh LC_ALL=C replay of gate `56acf516`, sent BEFORE any production read —
`md5(pg_get_functiondef)`):** `kernel.check_signing_key_invariants()` `480d42fd…` · `kernel.sweep_deletion_pending(integer)`
`d7217537…` · `ops.action_dispatch(ops.action)` `a1b6c7f6…` · `ops.alert_fire(text,text,jsonb)` `d42f697b…` ·
`ops.detect_jobs()` `37574d2c…` · `ops.execute_action(…)` `e59c1584…` · `ops.job_health()` `da349c0b…` ·
`ops.run_all_detectors()` `d42b1260…` · `ops.run_job(text,text)` `916408cb…` · `public.cleanup_expired_reservations()`
`0271dca2…` · `public.complete_auction_payment(uuid,uuid)` `2d157aef…` · `public.mark_listing_sold(uuid,uuid)` `e03bae57…` ·
`public.notify_bid_placed()` `c67f22fc…` · `public.notify_moderation_event()` `0dfa7ad1…` · `public.notify_transfer_event()`
`3546027f…` · `public.release_reservation(uuid,uuid)` `083b70d7…` · `public.reserve_buy_now(uuid,uuid,integer)` `5e01af4e…` ·
`public.mark_transfer_sent(uuid,uuid,text)` `d9addfdb…` · `public.mark_transfer_sent(uuid,uuid)` `f7a46322…`. Caveats (D):
the three 133 bodies read the Vault URL at run time, so their definition hashes are environment-independent and
**must** match; check the `(uuid,uuid)` overload exists before comparing (140 recreates both → jsonb). A's production-
order run agrees on every value it computed (143/145/146/133/RC bodies, both jsonb overloads). Effects that
begin at apply time, by design: 143 (bounded reads; "last run" = newest run), **145 (job-not-running detection on
the next scheduled tick — and a manual "Run job now" bypasses `detectors_enabled`, `job_state.enabled` and backoff
alike)**, 144/146 vocabulary/columns (inert while their switches are off). The RC bodies change under the deployed
legacy edges for the window until the RC functions deploy (§3 shows the window is signature-safe).

## 7. Rollback / disable
Per-file rollbacks restore the applied prior bodies (143 → 116/117 verbatim; 145 → 143's `detect_jobs`; 146 → 117's
`alert_fire`, 9 columns dropped, alert rows kept, delivery/ack bookkeeping lost; 144 → disable path when history
exists, no case deleted). **Forward-back-forward battery (2026-09-22, copy of the production-order database):**
all 24 rollbacks applied in reverse order (24/24); afterwards every baseline identity returned **exactly** to
production's pre-apply values (the seven body hashes, both `mark_transfer_sent` overloads → `void`, `ops.alert` 8
columns, `amount_refunded_cents` absent); the second forward apply (24/24) reproduced the first apply's identities
exactly (143 `da349c0b…`, 145 `37574d2c…`, 146 `d42f697b…`, 133 `480d42fd…`, jsonb overloads, 17 columns). pgTAP on the
re-applied database 5228/5230: the 2 failures are `132_replay_parity` D-5/8 and D-5/9, whose assertion text shows the
cause — the stand-in `cron.job` row carries the database name it was scheduled under (the template source
`prodorder3_rehears`) while the test expects the current database's name; command bytes and md5 identical. A
`createdb -T` artefact, not a rollback residue (the first-forward database passes 132 11/11).

## 8. After the apply (separate acts, in order)
**Edge deploy set — measured 2026-09-22 by byte comparison of every deployed bundle (CLI download, verified
byte-faithful: the pre-deploy v38 download equals `origin/main` exactly) against the gate, per function's own import
closure:** 10 functions change and are deployed after the DB apply — `enforce-transfer-expiry` (RC body, supersedes
v39; also `_shared/payouts.ts`, `_shared/payout-logic.ts`), `confirm-and-release` (same shared files),
`stripe-webhook`, `create-payment-intent`, `confirm-payment`, `create-connect-account`, `delete-account`,
`notify-report` (gains `ops_alert`), `notify-transfer`, `send-push`. **Unchanged, not redeployed:**
`auto-finalize-auctions`, and B's `credential-sign`, `door-manifest`, `door-session` (byte-identical to the gate — no
B change rides). **In the gate but not deployed and out of scope:** `connect-onboarding`, `ops-refund-execute`,
`payout-execute`, `primary-checkout`, `refund-execute`. Deployed→gate diffs are generated (A's scratchpad `edge_diffs/`, sizes: enforce-transfer-expiry +1094/−304,
confirm-and-release +633/−353, create-payment-intent +680/−42, stripe-webhook +393/−331, send-push +203/−2,
notify-report +170/−20, confirm-payment +142/−118, delete-account +86/−17, create-connect-account and
notify-transfer +2/−2). The gate's edge tree equals the reviewed candidate `e191cbfa` plus exactly the two changes
reviewed this round (#83's Phase 2b hunk, #86's `notify-report` `ops_alert` branch) — see §8 check. Each deploy is
preceded by an exact-source confirmation against the platform API (as for v38) → console release (owner: Ignored-Build-Step pin or
`vercel --prod`) → verification window → recipient verification → detector flip → dispatcher schedule + delivery
flip. None of these is part of this manifest.
