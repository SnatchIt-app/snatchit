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
  The only pending redefinitions of edge-called functions are in `20260906100000/110000/130000`, all
  signature-preserving.
- **pgTAP on the production-order database: 5339 / 5347 pass.** The 8 failures are exactly the assertions in
  **184 (2) and 186 (6) that carry "(126)" in their names**; applying 126 to a copy makes 184 90/90, 186 27/27 and
  193 65/65 pass. So the evidence set for this manifest excludes 184, 186 (126-coupled), 189 (121), 190 (125),
  193 (126); every other file passes.
- Switches after apply: `refund_resolution_detector_enabled=false`, `alert_delivery_enabled=false`,
  `detectors_enabled=true`, `actions_enabled=true` (the last two equal production today).
- Forward-back-forward rollback battery on the same database: **PASS — §7.**

## 4. Why 125 and 126 are omitted
- No pending file after 125 redefines `venue.sync_scan_device_manifest`; scanning is dark. Separable.
- 144 only *calls* `ops.refresh_metrics()` / `ops.build_daily_summary()` (existing since 115/120); it redefines
  none of 126's objects. `20260906120000`'s only match is a `rollback_archive` table name. The live console runs
  against production's pre-126 bodies today. Separable at the database level; the coupling is test-only (§3).
- Owner decision D-1 is therefore not needed for this release; 126 remains B/D's optional track.

## 5. Preflight (the day of the apply; each a read unless marked)
1. Owner's fresh AUTODEPLOY-1 dashboard confirmation (gate → nothing merges to `main` in this manifest anyway).
2. Ledger read = exactly the 135 rows, max numeric 120, 0 rows ≥ 121 (✓ 2026-09-22).
3. Body hashes of the seven baseline functions equal §3's values (✓ 2026-09-22; re-read on the day).
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
redefined body, grants vs `expected_grants.txt`, census. **Stop on the first non-matching read-back.** Effects that
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
