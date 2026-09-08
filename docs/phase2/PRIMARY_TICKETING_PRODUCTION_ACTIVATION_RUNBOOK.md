# PRIMARY TICKETING — PRODUCTION ACTIVATION RUNBOOK (migrations 093–099, native rail, sale → refund → payout)

**NOT EXECUTED. NOTHING IN THIS DOCUMENT IS AUTHORIZED.**

**This runbook authorizes nothing.** It is executable only under a NEW, explicit owner deployment
authorization that names this file, the `<PINNED_SHA>` below, and the train (§0.3). Authored 2026-09-03
by documentation agent R against `feature/venue-native-and-product-v2` @ `609e0f4` (093/094/095 authored;
096–099 designed, not yet in the repo at authoring time — see PRE-11). Derived from
`docs/phase2/_impl/KI_activation_sequencing.md` (normative sequence), `KJ_kms_runbook_monitor.md` §4.6,
the 096 / 097–099 design memos, `docs/release/PHASE2_PRODUCTION_RUNBOOK.md` (house shape) and
`docs/phase2/PRIMARY_TICKETING_ACTIVATION_MATRIX.md` (critical path + hazards).

---

## 0. Status, authority, conventions

### 0.1 Authority order (highest first)
1. `docs/operations/DEPLOYMENT_PATHS.md` — what may reach production and how (Path B is NOT an apply path).
2. `docs/architecture/PHASE_2_ARCHITECTURE_FREEZE.md` §4 → `_governance/POST_FREEZE_AMENDMENTS.md` → frozen corpus → **shipped migration bytes** (bytes beat prose).
3. Signed owner rulings: `FINAL_ACTIVATION_BLOCKER_RULINGS.md` signature block (G1–G5), `G4_PROMOTER_REVERSAL_RULING.md`, `G5_POST_PAYOUT_EXPOSURE_RULING.md`. **All are DRAFT / NOT SIGNED at authoring time.**
4. `KI_activation_sequencing.md` (the derived order) — this runbook re-derives it and disagrees with the matrix where KI proved the matrix wrong (P1-2, P1-4, P1-5).
5. This runbook. Where it and any of the above disagree, the higher wins and this file is wrong.

### 0.2 Markers
Every step carries exactly ONE primary marker (`PRIMARY:`), optionally followed by secondary markers:
`READ ONLY` · `PRODUCTION MIGRATION` · `PRODUCTION CONFIG` · `EDGE DEPLOY` · `SUPABASE DASHBOARD` ·
`STRIPE MUTATION` · `KMS MUTATION` · `PRODUCTION DB MUTATION` · `OWNER APPROVAL REQUIRED` ·
`TWO-PERSON REQUIRED` · `IRREVERSIBLE AFTER MINT`.

### 0.3 Placeholders (no secrets, no example keys, ever)
`$PROD_DB_URL` (postgres role, owner's shell only) · `$SUPABASE_URL` = `https://hqycwntpfoztoinemqns.supabase.co` ·
`$ANON` / `$SERVICE_KEY` (never pasted into a document or transcript) · `<ORG>` `<SESSION>` `<BUYER>` `<ORDER>` `<S>` (uuids) ·
`<ck>` = a fresh command key per call (`^[A-Za-z0-9._:-]{1,64}$`) · `<request_id>` = the parked approval row ·
`<OWNER_VALUE:G1>` = `ticket.expiry_grace` (owner direction: `"72 hours"`) · `<OWNER_VALUE:G2>` = `payout.settlement_maturity_interval` (direction: `"7 days"`) ·
`<OWNER_VALUE:HOLD_HOURS>` = `deletion.post_event_hold_hours` (FABR gives none) · `<OWNER_VALUE:FEE_BPS>` · `<OWNER_VALUE:HOLD_CAP>` · `<OWNER_VALUE:HOLD_TTL>` ·
`<EXPECTED_PUBLIC_KEY_FINGERPRINT>` / `<PRODUCTION_KEY_NOT_AFTER>` come from the ceremony evidence pack (KMS §9.1), never from this file.
Admin roles: `ADMIN-1` and `ADMIN-2` are two DISTINCT `platform_admin` humans on aal2 (parked keys need both).

### 0.4 PIN table (orchestrator fills; the apply is refused if any cell is blank or differs from `git`/`md5`)
| Item | Value | Proof |
|---|---|---|
| Source tip | `<PINNED_SHA>` | `git rev-parse origin/<branch>` = value; CI green on that head; migrations-guard `Immutability + ordering` green |
| 093 | `<MD5_093>` | `md5 -q supabase/migrations/093_primary_ticketing.sql` |
| 094 | `<MD5_094>` | same |
| 095 | `<MD5_095>` | same |
| 096 | `<MD5_096>` | `096_payout_reversal_and_obligation_recovery.sql` |
| 097 | `<MD5_097>` | `097_settlement_scope_and_shortfall.sql` |
| 098 | `<MD5_098>` | `098_promoter_prorata_funding.sql` |
| 099 | `<MD5_099>` | `099_signing_monitor_and_executor_invokers.sql` |
| Ledger before / after | 107 / **114** | `select count(*) from supabase_migrations.schema_migrations` |
| Config keys before / after | 49 / **54** | 099 seeds `signing.expected_key_fingerprint`, `signing.expected_max_not_after`, `signing.monitor_enabled`, `refund.executor_enabled`, `payout.executor_enabled` (DESIGN_097_099 §4.1–4.3) |
| Cron jobs before / after | 19 / **22** | `monitor-signing-key-invariants`, `refund-execute-tick`, `payout-execute-tick` |

---

## 1. PRECONDITIONS — all must be TRUE before §2 S-1. Any FALSE ⇒ STOP.

| # | Precondition | Proving artifact / query (READ ONLY unless stated) | Primary marker |
|---|---|---|---|
| PRE-1 | **The 24 h observation of 076–092 is CLOSED ON EVIDENCE.** A close-out file EXISTS at `docs/release/PHASE2_OBSERVATION_CLOSEOUT_20260903.md` (or a `## OBSERVATION CYCLE — close-out` section appended to `PHASE2_DEPLOYMENT_RECORD_20260902.md`) recording, from live reads taken at/after 2026-09-03T20:45Z: `cron.job_run_details` failed = 0 since apply; `notify.outbox` dead = 0; ledger = 107; legacy counts unchanged; tag `prod/phase2-apply-20260902` cut. **Elapsed time is not a PASS. If the file does not exist, STOP.** | `test -f docs/release/PHASE2_OBSERVATION_CLOSEOUT_20260903.md`; `git tag -l 'prod/phase2-apply-*'` non-empty | `READ ONLY` |
| PRE-2 | Owner signatures: **G1** (`<OWNER_VALUE:G1>`), **G2** (`<OWNER_VALUE:G2>`), **G3** (ceremony, D1–D7 filled), and **ratification of `kernel.claim_refunds_for_execution`** (H1 §5.4 — hard gate before any apply) | `FINAL_ACTIVATION_BLOCKER_RULINGS.md` signature block filled and dated; a ratification line naming the claim verb | `OWNER APPROVAL REQUIRED` |
| PRE-3 | **Gate-M re-attested** (C29/C30/C31) as REQUIRED for venue payout activation — 094's own deploy precondition | dated attestation under `docs/phase2/` naming C29/C30/C31 | `OWNER APPROVAL REQUIRED` |
| PRE-4 | **G5 signed** before ANY §3 payout step; **G4 HELD** (no promoter release, no promoter payout) — recorded as a standing prohibition | G5 signature; G4 status line = HELD | `OWNER APPROVAL REQUIRED` |
| PRE-5 | AUTODEPLOY-VERIFIED-OFF on every migration-bearing PR of this train **and** `supabase branches list` shows `git_branch` empty | PR body `AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD`; owner's visual dashboard confirmation (DEPLOYMENT_PATHS.md "Required sequence" step 3) | `SUPABASE DASHBOARD` + `OWNER APPROVAL REQUIRED` |
| PRE-6 | **Production ledger verified = 107** and `db push --dry-run` lists exactly seven files | `psql "$PROD_DB_URL" -c "select count(*) from supabase_migrations.schema_migrations"` → 107; S-2 plan | `READ ONLY` |
| PRE-7 | **No P0 open** in KA–KJ, KM1–KM4 reports or Sentry against the deployed edges; no open incident on Stripe webhooks | grep `P0` across `docs/phase2/_impl/K*.md` resolved; Sentry clean | `READ ONLY` |
| PRE-8 | **093 forward-only acknowledged in writing by the owner** OR `supabase/rollbacks/093_*_rollback.sql` exists with a zero-`native_primary`-rows guard and battery diff 0 (KI P0-3: no 093 rollback exists; 094's rollback restores `close_settlement` to 093 text, so it presumes 093 stays) | signed line in the apply authorization, or the file + battery output | `OWNER APPROVAL REQUIRED` |
| PRE-9 | **Phase-2b release scripts EXIST and are green locally** — deliverables of this train: `scripts/release/phase2b_preflight.sql` (L1: no `09[3-9]` in ledger; L2: ledger = 107), `scripts/release/phase2b_postapply_verify.sql` (V1 ledger = 114; V7 keys = 54; V6 cron = 22; V8 flags 5/5 false; V9 owner-unset keys null incl. `deletion.post_event_hold_hours`; V10 data plane empty; V3/V4 relation/routine counts pinned from the local rehearsal — not from this file), `scripts/release/local_rollback_battery_093_099.sh` (094–099 rollbacks, identity-0; 093 excluded per PRE-8). **If any is absent at run time, STOP.** The 076–092 scripts are 092-scoped by literal (KI P0-4) and must NOT be reused. | `ls scripts/release/phase2b_preflight.sql scripts/release/phase2b_postapply_verify.sql scripts/release/local_rollback_battery_093_099.sh`; outputs attached to the PR | `READ ONLY` |
| PRE-10 | On-demand production backup < 24 h before the apply; Stripe Connect branding set; `VENUE_CONNECT_RETURN_URL`/`REFRESH_URL` routes exist (`curl -sI <return url>` ≠ 404) | Dashboard → Backups id recorded; curl output | `SUPABASE DASHBOARD` |
| PRE-11 | **096, 097, 098, 099 authored, immutable-gated and green in CI** with their rollbacks (`096_*`, `097_*`, `098_*`, `099_*_rollback.sql`), pgTAP 162–165, and reports `KM1_096`, `KM2_097`, `KM3_098`, `KM4_099` under `docs/phase2/_impl/`; 098's PFA entry recorded as PENDING OWNER SIGNATURE and **signed before apply** (DESIGN_097_099 §3.5 — "a deploy precondition, exactly as 094's Gate-M row") | file presence; CI run id; PFA signature | `OWNER APPROVAL REQUIRED` |
| PRE-12 | KMS ceremony booked: provider (D1), two named operators with separated IAM (A, B), window; KMS runbook §1.2 countersigned | countersigned table | `TWO-PERSON REQUIRED` |
| PRE-13 | Two DISTINCT `platform_admin` holders on aal2 exist (ADMIN-1, ADMIN-2) — the parked keys in S-10/S-12/P-6 cannot be approved by one person (`kernel.approve_refund_request` `config.set_money_key` arm requires a second, distinct admin — 085) | `select count(*) from kernel.platform_role where role='platform_admin' and …` per the corpus' role table; two humans named | `READ ONLY` |

---

## 2. SALE ACTIVATION — the ordered sequence (re-derived)

Derivation, in one line: owner paper → migrations (everything downstream needs 093's objects) → edges that need
those objects, in the order of what each WRITES (`connect_transfers_active` first, then the webhook that keeps it
true and finalizes orders, then refund execution, then the alert egress) → one org (reversible) → the irreversible
key (parallel, before config) → monitors and invokers PROVEN → config in refusal-ladder order → the outermost gate
(exposure) as LATE as possible → the only PI minter → the flag → one sale → one refund. Nothing in §2 moves venue
money out.

Refusal ladder (`venue.create_primary_checkout`, 093 §3), in code order — each config/step below is placed by which
refusal it clears: `feature_disabled` (`reserve_primary_inventory`, 081; flag) → `hold_cap_exceeded` → `hold_ttl_unset`
→ `org_not_active` → `payout_not_ready` (both Connect columns, 093 §1/§2) → `no_active_signing_key` → `service_fee_unset`.

| Step | PRIMARY marker (+ secondary) | Command / query (placeholders) | Verification — expected | Dependency reason (code) |
|---|---|---|---|---|
| **S-0 Owner rulings + Gate-M** | `OWNER APPROVAL REQUIRED` | PRE-2, PRE-3, PRE-4, PRE-8, PRE-11 signatures in hand; authorization names `<PINNED_SHA>` | signature block dated; attestation file present | 094 header: Gate-M is its deploy precondition; 098 PFA likewise; G1/G2 are values the setter will store in S-10 |
| **S-1 Preflight ×3** (T-24H, T-1H, T-15M) | `READ ONLY` | `psql "$PROD_DB_URL" -f scripts/release/phase2b_preflight.sql` | zero FAIL; ledger 107; `select count(*) from kernel.signing_key` = 0; exposed schemas still `public,graphql_public,kernel`; `select count(*) from cron.job` = 19 | `db push --include-all` resumes at the first unapplied file — a drifted ledger changes the plan |
| **S-2 Dry-run plan** | `READ ONLY` | `supabase db push --db-url "$PROD_DB_URL" --include-all --dry-run` | plan lists **exactly** `093, 094, 095, 096, 097, 098, 099` — nothing else. Any other list ⇒ STOP | house gate (PHASE2_PRODUCTION_RUNBOOK APPLY) |
| **S-3 Apply 093→099 in ONE push** | `PRODUCTION MIGRATION` + `OWNER APPROVAL REQUIRED` (093 forward-only, PRE-8) | `supabase db push --db-url "$PROD_DB_URL" --include-all` (start just after an even minute; the */2 jobs are quiet) | seven applied; each file is one transaction — a failure leaves a clean prefix: fix forward, do not re-run blindly | order is forced by bodies: 094 re-creates `kernel.close_settlement` over 093 10d; 095 re-creates `get_payout_execution_context` (10n) body-only; 096 adds `kernel.payout_reversal`, `record_payout_reversal`, `organization_obligation_recovery`, `reconcile_payout_transfer` on 094/095 objects; 097 re-creates `settlement_royalty_lines` (10h), `settlement_primary_lines` (10b), `record_organization_obligation` (094), `close_settlement` (094 text), `settlement_payout_maturity` (10m), `record_dispute_native`/`mark_dispute_state` (088); 098 re-creates `settlement_commission_lines` (10e), `pay_promoter_commission` (090), `mark_payout_transfer_state` (085); 099 adds `kernel.check_signing_key_invariants` + 3 cron rows + 5 seeds |
| **S-4 Post-apply verify** | `READ ONLY` | `psql "$PROD_DB_URL" -f scripts/release/phase2b_postapply_verify.sql` | ALL PASS: ledger 114; keys 54, every new key version 1 (`refund.executor_enabled=false`, `payout.executor_enabled=false`, `signing.monitor_enabled=false`); cron 22 by exact name; `select command from cron.job where jobname in ('refund-execute-tick','payout-execute-tick')` each reads its key and is inert; flags 5/5 false; `kernel.signing_key` 0; triggers `tg_payout_org_payable_guard`, `tg_settlement_forward_only` present; `kernel.payout_reversal`, `kernel.organization_obligation_recovery` exist and empty; `kernel.organization_obligation.venue_id` exists; **`select command from cron.job where jobname='refund-execute-tick'` contains `"action":"sweep"`** (the sweep arm of `refund-execute` is `action === 'sweep'`; a body without it 400s and the tick proves nothing) | the verifier is the release gate; V3/V4 values are whatever the local rehearsal pinned |
| **S-5 Deploy `connect-onboarding`** | `EDGE DEPLOY` | `supabase secrets set VENUE_CONNECT_RETURN_URL=<url> VENUE_CONNECT_REFRESH_URL=<url>` then `supabase functions deploy connect-onboarding` (verify_jwt ON) | no-JWT POST → 401; staff JWT + `{status_only:true}` on a test org → 200, no `connect_state_unavailable` | only minter of an org `acct_` and the FIRST writer of `connect_transfers_active` via `kernel.sync_org_connect_state` (093 §2, service_role); reads `get_org_connect_state` (093 §6), `stage_org_connect_ref` (093 §2b), `set_org_connect_ref` (093 §4) — all land in S-3 |
| **S-6 Deploy `stripe-webhook`** (native dispute + reversal branches) | `EDGE DEPLOY` | `supabase functions deploy stripe-webhook` (same verify-jwt posture as v39; verifies `STRIPE_WEBHOOK_SECRET` itself; env unchanged); Stripe endpoint must also deliver `charge.dispute.created/updated/closed/funds_withdrawn/funds_reinstated`, `transfer.reversed` (add subscriptions if absent — dashboard act) | Stripe → send test `account.updated` for a LEGACY account → 200, legacy arm logged, `public.stripe_webhook_events` row completed; a test `charge.dispute.created` with null `payment_intent` → legacy only, no native write; Sentry: no new class | ongoing writer of `connect_transfers_active` (account.updated org arm); only caller of `venue.finalize_primary_order` (085); native dispute arm calls `kernel.record_dispute_native` / `mark_dispute_state` (097 rail guard `not_native_rail`); `transfer.reversed` native path calls `kernel.record_payout_reversal` (096). Safe before any native PI: dispatch is `metadata.rail === 'native_primary'` (native.ts). MUST precede S-16 (a native PI on v39 → `unknown_mode` → 500 retried 3 days, buyer charged, no ticket) |
| **S-7 Deploy `refund-execute`** | `EDGE DEPLOY` | `supabase functions deploy refund-execute --no-verify-jwt` (self-authenticating: `sweep` = `INTERNAL_CRON_SECRET` or service key; `execute`/`record`/`admin_refund` = JWT); `supabase secrets list` shows `INTERNAL_CRON_SECRET` or set one | `POST {"action":"sweep"}` with `Bearer $SERVICE_KEY` → `{"status":"ok","attempted":0}` (NOT 501 `claim_rpc_missing`); wrong bearer → 401 | needs `kernel.claim_refunds_for_execution` (10i) + `get_refund_execution_context` (10g) → after S-3. A9 requires it BEFORE any sale |
| **S-8 Deploy `notify-report`** (monitor egress) | `EDGE DEPLOY` | `supabase functions deploy notify-report` (auth unchanged; new `signing_invariant_alert` branch per KJ §4.5 / DESIGN 4.4) | existing moderation branch smoke unchanged; a synthetic `signing_invariant_alert` body from the service key → push to `admin_users` + `captureException` | `kernel.check_signing_key_invariants` (099) posts its alerts here; arming the monitor (S-11) before this deploy alerts nobody |
| **S-9 Onboard ONE organization** | `STRIPE MUTATION` + `PRODUCTION DB MUTATION` (via the edge) | org_owner (aal2) → `POST connect-onboarding {org_id:<ORG>}` → hosted onboarding → return → `{status_only:true}` | `select stripe_connect_account_ref, connect_transfers_active, connect_state_synced_at from kernel.organization where org_id='<ORG>'` → `acct_…`, `true`, recent; `select count(*) from kernel.admin_audit where subject_id='<ORG>' and action like 'connect.%'` ≥ 2 | `payout_not_ready` (093 §3) needs BOTH columns; binding alone leaves `connect_transfers_active=false` (KI C3). Reversible: no money |
| **S-10 KMS ceremony + bootstrap row** (parallelisable with S-5..S-9; MUST finish before S-12) | `KMS MUTATION` + `PRODUCTION DB MUTATION` `TWO-PERSON REQUIRED` `OWNER APPROVAL REQUIRED` `IRREVERSIBLE AFTER MINT` | KMS runbook §3→§7 verbatim; `psql "$PROD_DB_URL" -v PUBLIC_KEY_PEM="$(cat pub.pem)" -v KMS_HANDLE_REF="$(cat handle.txt)" -v EXPECTED_FINGERPRINT="$(cat fingerprint.txt)" -f signing_key_bootstrap.sql` | three `NOTICE`s + `COMMIT`; §7.4 census `1|1|0|0`; §7.5 update attempt → `append_only`; evidence pack signed by A, B, owner | `no_active_signing_key` is refusal #6 (093 §3) and the mint gate (`kernel.issue_ticket_atoms`, 093 §8). Reversible until the first atom (KMS §10/§11) |
| **S-11 Arm the KMS invariant monitor** (KJ §4.6) | `PRODUCTION CONFIG` + `OWNER APPROVAL REQUIRED` | as ADMIN-1 (aal2, PostgREST or authenticated psql — never `postgres`): `select catalog.set_platform_config('signing.expected_key_fingerprint', to_jsonb('<EXPECTED_PUBLIC_KEY_FINGERPRINT>'::text),'ceremony_b_bootstrap','<ck>')`; if D6 chose a not_after: `('signing.expected_max_not_after', to_jsonb('<PRODUCTION_KEY_NOT_AFTER>'::text),…)`; then `('signing.monitor_enabled','true'::jsonb,'ceremony_b_bootstrap','<ck>')` | each returns `{"status":"ok",…,"version":2}` (`signing.%` is NOT in the dual-control prefix set — single admin, KJ Q3 accepted gap); then as postgres READ ONLY: `select kernel.check_signing_key_invariants()` → `{"status":"ok","alerts":[],"fingerprint":"match",…}`; anything else ⇒ STOP, evidence pack not signable; next 05:23Z run: `cron.job_run_details` for `monitor-signing-key-invariants` = `succeeded` | matrix hazard row: a monitor that exists only in a runbook is not a control — arming is a launch blocker; needs 099 (S-3) + S-8 + S-10 |
| **S-12 Arm the refund invoker + PROVE the tick** | `PRODUCTION CONFIG` + `TWO-PERSON REQUIRED` `OWNER APPROVAL REQUIRED` | ADMIN-1: `select catalog.set_platform_config('refund.executor_enabled','true'::jsonb,'a9_option_a','<ck>')` → `{"status":"parked",…}` (boolean under `refund.%`, no declared polarity ⇒ parks in BOTH directions); ADMIN-2: `select kernel.approve_refund_request('<request_id>','approve','a9_option_a','<ck>')` | `select value from catalog.platform_config where key='refund.executor_enabled' order by version desc limit 1` = `true`; within 2 min: `select status from cron.job_run_details where jobid=(select jobid from cron.job where jobname='refund-execute-tick') order by start_time desc limit 1` = `succeeded`; edge log for `refund-execute` shows one `sweep` invocation with `claimed:0`; `kernel.approval_request` pending for `config.set_money_key` = 0 | 099 tick is inert while the key is false (DESIGN 4.2); `svcOk` in `refund-execute` accepts the Vault `service_role_key` bearer. A9 disjunct 1 is met only by deploy (S-7) + a proven automated invoker. MUST precede S-13(5) and S-16 |
| **S-13 Owner config, refusal-ladder order** | `PRODUCTION CONFIG` + `TWO-PERSON REQUIRED` for (3)–(6) | as ADMIN-1 aal2: (1) `select catalog.set_platform_config('inventory.per_user_active_hold_max','<OWNER_VALUE:HOLD_CAP>'::jsonb,'activation','<ck>')` → ok; (2) `('inventory.hold_ttl_interval','"<OWNER_VALUE:HOLD_TTL>"'::jsonb,…)` → ok; (3) `('ticket.expiry_grace','"<OWNER_VALUE:G1>"'::jsonb,…)` → parked → ADMIN-2 approves; (4) `('payout.settlement_maturity_interval','"<OWNER_VALUE:G2>"'::jsonb,…)` → parked → approve; (5) **only after S-12 proven**: `('deletion.post_event_hold_hours','<OWNER_VALUE:HOLD_HOURS>'::jsonb,…)` → parked → approve; (6) `('fee.buyer_service_bps','<OWNER_VALUE:FEE_BPS>'::jsonb,…)` → parked → approve | latest version per key equals the value; `select count(*) from kernel.approval_request where action='config.set_money_key' and state='pending'` = 0; (3)/(4) are jsonb STRINGS (a bare number is refused `bad_value … SECONDS` by the interval type guard in `catalog.set_platform_config`) | (1)/(2) clear `hold_cap_exceeded`/`hold_ttl_unset` in `reserve_primary_inventory`; (4) is one conjunct of nine in `settlement_payout_maturity` (10m, 097 adds `dispute_unabsorbed`) and harmless before any settlement; (5) stops BP-12 arm 2 blocking — only safe once refunds cannot strand (S-12); (6) clears the LAST refusal `service_fee_unset` — set last so nothing earlier can quote |
| **S-14 Expose `catalog` + `venue`** (LATE, KI P1-4) | `SUPABASE DASHBOARD` + `TWO-PERSON REQUIRED` | Dashboard → Settings → API → Exposed schemas: `public,graphql_public,kernel,catalog,venue` (second person watches) | `curl "$SUPABASE_URL/rest/v1/rpc/create_primary_checkout" -H "apikey: $ANON"` no auth → 401 (not `PGRST106`); anon → 42501; ledger/keys unchanged | `venue.create_primary_checkout` is granted to `authenticated`: the instant `venue` is exposed the SQL ladder is the only gate — every clause except the flag is now green by design, so exposure sits here, not at matrix step 2 |
| **S-15 Deploy `primary-checkout`** | `EDGE DEPLOY` | `supabase functions deploy primary-checkout` (verify_jwt ON; env present) | no-JWT → 401; staff JWT + empty items → 400 `no items`, no PI minted | the only PaymentIntent minter (platform account, `metadata.rail=native_primary`); last deploy so no money path exists before every gate is proven |
| **S-16 Refusal-ladder probes, end to end** | `READ ONLY` (probes create no order) | on a throwaway buyer, BEFORE the flag: `reserve_primary_inventory` → expect `precondition_failed: feature_disabled`; on a SECOND throwaway org that is unbound: `create_primary_checkout` → `payout_not_ready`; as anon: 42501 | exact refusal strings per KI §2.2 (B1, C2); zero rows in `venue."order"` for the probes | proves the ladder is live in production with the same strings the rehearsal produced; last chance to stop with zero money |
| **S-17 Flip the flag** | `PRODUCTION CONFIG` (single admin by design) | ADMIN-1: `select catalog.set_platform_config('feature.native_issuance_enabled','true'::jsonb,'activation','<ck>')` → `{"status":"ok"}` | value `true`, version 2; `feature.%` is single-admin (kill switch must not need a quorum) | gate at both `reserve_primary_inventory` (081) and `kernel.issue_ticket_atoms` (093 §8); the first controlled quote is impossible before this (KI P1-2) |
| **S-18 First controlled quote** | `PRODUCTION DB MUTATION` | throwaway buyer JWT → `reserve_primary_inventory(<SESSION>, 1)` → `POST primary-checkout` for the smallest ticket | `select order_id,status,total_minor from venue."order" where buyer_id='<BUYER>'` = 1 row `pending`; `select stripe_payment_intent_id, mode from public.payments where mode='native_primary'` = 1 row | the PI is minted here (`STRIPE MUTATION` secondary) — stop here if anything is off; an unpaid PI expires |
| **S-19 First controlled payment** | `STRIPE MUTATION` | PaymentSheet with a real card → `payment_intent.succeeded` | `public.payments` row `succeeded`; `kernel.payment_native` 1 row for `<ORDER>`; order `status='paid'`; webhook event row `completed` | `venue.finalize_primary_order` via the native webhook branch (S-6) |
| **S-20 First mint** | `IRREVERSIBLE AFTER MINT` + `PRODUCTION DB MUTATION` | (automatic on finalize) | `select count(*), min(signing_key_id) from kernel.tickets where event_session_id='<SESSION>'` = qty, the bootstrap key; `kernel.ticket_ownership_log` `cause='issue'` = qty; Sentry 0 | point of no return for the signing key (KMS §11); everything after is forward-only |
| **S-21 First refund rehearsal — A9 proof on the first sale** | `STRIPE MUTATION` + `TWO-PERSON REQUIRED` (owner watching) | platform support JWT → `POST refund-execute {"action":"record","order_id":"<ORDER>"}` (→ `kernel.request_order_refund`); then WAIT for the `refund-execute-tick` (do not call `execute` by hand — the proof is the invoker) | `select status, stripe_refund_ref from kernel.refund` = `succeeded`, `re_…`; `kernel.tickets` `state='voided'` = qty; Stripe shows the refund; card credited; `cron.job_run_details` for the tick `succeeded` | A9 is outcome-shaped ("money actually returning"); this single run proves executor + invoker + webhook together |
| **S-22 Settlement observation** | `READ ONLY` | do NOT open/close a settlement in this section unless the owner authorizes P-1; watch 24 h: `select count(*) from kernel.refund where status in ('pending','submitted') and created_at < now()-interval '1 hour'` = 0; Sentry no `refund-execute` exceptions; monitor run green | end state: venue money for any further sale rests as `primary_sale` lines only when a settlement is closed; no payout exists; `payout-execute` not deployed; `payout.executor_enabled=false` | legal launch posture (G6 §4.1) with the disclosure obligation to the venue and Stripe's holding limit |

---

## 3. PAYOUT ACTIVATION — SEPARATE GATE, SEPARATELY OWNER-AUTHORIZED

```
╔══════════════════════════════════════════════════════════════════════════════════════════╗
║  §2 DOES NOT ENTER THIS SECTION. A second, written owner authorization is required.        ║
║  Default-off here is a CONJUNCTION: payout-execute undeployed ∧ payout.executor_enabled=false║
║  ∧ eligible set empty (no submitted payout with destination_ref) — not one boolean.        ║
╚══════════════════════════════════════════════════════════════════════════════════════════╝
```

| Step | PRIMARY marker (+ secondary) | Command / query | Verification — expected | Dependency reason (code) |
|---|---|---|---|---|
| **P-0 G5 signed; Gate-M attested; G4 HELD** | `OWNER APPROVAL REQUIRED` | signature block; G5's own approval text: the executor may not be deployed until signed | dated signatures | matrix hazard: H4 D-4 rated post-payout loss acceptable BECAUSE no executor existed; that ends at P-2 |
| **P-1 A matured settlement exists** | `READ ONLY` | `select kernel.settlement_payout_maturity('<S>')` on one `closed` settlement with `net_minor > 0` | reason codes reduce to `maturity_not_elapsed` only, then clear; NOT `unbounded_refund_exposure`, `refund_in_flight`, `dispute_open`, `dispute_unabsorbed` | proves S-13(4) is live and 10m's (now nine) predicates evaluate; `close_settlement` (097 text) may have booked a shortfall hold — `hold_reason_code='shortfall_pending'` is cleared only by `kernel.release_payout` |
| **P-2 Deploy `payout-execute`** | `EDGE DEPLOY` + `OWNER APPROVAL REQUIRED` | `supabase functions deploy payout-execute --no-verify-jwt` (env: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY`, optional `INTERNAL_CRON_SECRET`) | `POST {}` with service key → `{"status":"ok","attempted":0}` (NOT 501); wrong bearer → 401; the failed-reconcile pass runs with `claim_failed_payouts_for_reconcile` → 0 rows | needs `claim_payouts_for_execution` (10p), `get_payout_execution_context` (10n/095), `mark_payout_transfer_state` (085/098 guard), `hold_payout_transfer_reversed` (095), `reconcile_payout_transfer` + `claim_failed_payouts_for_reconcile` (096). `payout.executor_enabled` is still false ⇒ the 099 tick stays inert |
| **P-3 Human request** | `PRODUCTION DB MUTATION` (org money role, aal2, ≥72 h role maturity) | org_finance → `kernel.retry_held_payout('<ORG>','<S>','<ck>')` once matured → `kernel.request_org_payout('<ORG>','<S>','<ck>')` | `select status, hold_state, destination_ref, stripe_transfer_ref from kernel.payout where cause_ref='<S>'` = `submitted`, `none`, `acct_…`, `null`; above `payout.dual_control_min_minor` (null ⇒ every payout parks) a `payout.request` approval row for a platform role | `tg_payout_org_payable_guard` (095) fires on `→ submitted`; `destination_ref` pinned here (10j) is what the executor sends |
| **P-4 Manual single execution — NOT the cron** | `STRIPE MUTATION` + `TWO-PERSON REQUIRED` `OWNER APPROVAL REQUIRED` | `POST payout-execute {"limit":1}` with the service key, once, owner watching | `GET /v1/balance` preflight passed; one `tr_…` on the platform account to `destination_ref`; `kernel.payout` `paid`, `stripe_transfer_ref` set (unique index from 096); `venue.settlement.status='paid'` (`venue.on_payout_settled`); `kernel.payout_reversal` 0 rows | first money leaves the platform; §6 (platform Stripe payout schedule manual/floated) must already hold |
| **P-5 Arm the payout invoker** | `PRODUCTION CONFIG` + `TWO-PERSON REQUIRED` `OWNER APPROVAL REQUIRED` | ADMIN-1: `select catalog.set_platform_config('payout.executor_enabled','true'::jsonb,'payout_activation','<ck>')` → parked; ADMIN-2: `select kernel.approve_refund_request('<request_id>','approve','payout_activation','<ck>')` | key `true`; within 10 min `cron.job_run_details` for `payout-execute-tick` = `succeeded`; edge log `run complete`, `attempted:0` (nothing else is submitted) | ONLY after P-4 succeeded by hand; `payout.%` is dual-controlled, boolean ⇒ parks both ways |
| **P-6 Threshold keys** | `PRODUCTION CONFIG` + `TWO-PERSON REQUIRED` | `payout.dual_control_min_minor`, `payout.request_auto_max_minor`, `payout.destination_cooldown_hours`, `payout.destination_probation_days` — each parks (lower/higher-is-restrictive polarities apply); ADMIN-2 approves | approval rows approved; pending = 0 | `destination_ref` exists (093 10j) so the matrix ordering constraint 2 is discharged; set AFTER P-4 so the first payout was dual-controlled by construction |

---

## 3b. PROMOTER PAYOUT — NOT PART OF EITHER SECTION

```
╔══════════════════════════════════════════════════════════════════════════════════════════╗
║  kernel.release_payout on a promoter_commission payout is PROHIBITED until G4 is SIGNED.   ║
║  098 changes only AMOUNTS (pro-rata funding vs surviving face; FUNDED ≠ PAID); it releases  ║
║  nothing and pays nobody. 098's mark_payout_transfer_state refuses cause='promoter_commission'║
║  outright (`promoter_payout_dark`, ruling A4). Verification, standing:                      ║
║  select count(*) from kernel.payout where cause='promoter_commission' and status<>'pending'  ║
║  and hold_state<>'held'  → 0.                                                               ║
╚══════════════════════════════════════════════════════════════════════════════════════════╝
```

---

## 4. A9 CLOSURE — refund executability (KI §7)

**Option A is the path.** A9 disjunct 1 ("an automated executor") is satisfied by ALL of:
1. **Deployed** — S-7: `refund-execute` live with `--no-verify-jwt`; `sweep` → `{"status":"ok"}` on the service key, 401 on a wrong bearer.
2. **Invoked** — S-12: `refund.executor_enabled=true` (quorum), `refund-execute-tick` (*/2) `succeeded` in `cron.job_run_details`, edge log shows the sweep, the cron command carries `"action":"sweep"`.
3. **Tested** — S-21: one real refund on the first sale reaches `kernel.refund.status='succeeded'` with a `re_…`, atoms `voided`, card credited, WITHOUT a human calling `execute`.
4. **Healthy** — 24 h after S-21: Sentry shows no `refund-execute` exception class; `select count(*) from kernel.refund where status in ('pending','submitted') and created_at < now()-interval '1 hour'` = 0; every tick run `succeeded`; cadence (2 min) is far inside the 20 h `create`/`reconcile` window of `claim_refunds_for_execution` (10i) and Stripe's 24 h idempotency window.

**Option B (only if the owner chooses it in writing)** must contain, verbatim in a signed doc: the named accountable
human (name, role, backup); the trigger (daily `select refund_id, status, created_at from kernel.refund where status
in ('pending','submitted') order by created_at`); the exact act (`POST refund-execute {"action":"sweep"}` with the
secret, or per-refund `execute`); the write-back (a dated log; the executor itself calls `mark_refund_state`); an SLA
≤ 20 h (past the `create` window a row must be reconciled against Stripe); handling of `stripe_error` (retry) vs
`refused` (escalate). Calling B "automated" is dishonest; launching on B without the daily query actually running is dishonest.

---

## 5. KILL SWITCHES

| Switch | Act | Who | Quorum? | Effect / note |
|---|---|---|---|---|
| **Sale** | `select catalog.set_platform_config('feature.native_issuance_enabled','false'::jsonb,'kill','<ck>')` | one `platform_admin` (aal2) | **NO** — by design (`feature.%` single-admin; KMS §13 step 1) | stops holds (`reserve_primary_inventory`) and mints (`issue_ticket_atoms`) immediately; paid-but-unfinalized orders still finalize via the webhook |
| **Refund invoker (key)** | `set_platform_config('refund.executor_enabled','false'::jsonb,…)` | ADMIN-1 proposes → parks; ADMIN-2 approves | **YES** — `refund.%` is dual-controlled; boolean has no polarity ⇒ `false` parks too | a kill switch that needs a quorum is not a kill switch (H9 §7): use the no-quorum stop below when seconds matter |
| **Refund invoker (no-quorum stop)** | `select cron.unschedule('refund-execute-tick')` (as postgres, SQL editor) | one superuser holder | **NO** | `PRODUCTION DB MUTATION`; diverges live cron from 099 — record it; re-schedule only via a migration or a written act |
| **Payout invoker (key)** | `set_platform_config('payout.executor_enabled','false'::jsonb,…)` | ADMIN-1 → ADMIN-2 | **YES** (same reason) | tick becomes inert within one cadence |
| **Payout invoker (no-quorum stop)** | `select cron.unschedule('payout-execute-tick')` | one superuser holder | **NO** | same divergence note |
| **Payout executor** | `supabase functions delete payout-execute` (undeploy) | one CLI holder | **NO** | the cron `net.http_post` then 404s harmlessly; nothing else can create a transfer. Rollback tree class 4 |
| **KMS monitor** | `set_platform_config('signing.monitor_enabled','false'::jsonb,…)` | one `platform_admin` | **NO** — `signing.%` is not dual-controlled (KJ Q3 accepted gap) | disarming detection alone is the weakness; treat any disarm as an incident entry |
| **Signing key** | KMS runbook §10 (revoke before first mint) / §13 (compromise) | A + B | **YES** (ceremony) | after S-20 the key is never reversible (§11) |

---

## 6. NO AUTO-PAYOUT

```
╔══════════════════════════════════════════════════════════════════════════════════════════╗
║  SALE ACTIVATION (§2) DOES NOT ACTIVATE PAYOUT. After S-22:                                ║
║   • venue money rests as venue.settlement_line rows (primary_sale, refund_void, chargeback…)║
║     inside settlements a human opens and closes; a close mints a kernel.payout that is      ║
║     held (maturity_* / shortfall_pending) or pending — never submitted by a machine;        ║
║   • payout-execute is NOT deployed and payout.executor_enabled = false;                      ║
║   • the PLATFORM's own Stripe payout schedule must be MANUAL, or a float held above the     ║
║     largest open matured settlement (matrix row 10(c)) — otherwise P-4's GET /v1/balance    ║
║     preflight fails with balance_insufficient and no transfer is attempted;                 ║
║   • no cross-venue netting: 097 ring-fences the chargeback arm to the originating venue and ║
║     holds only that venue's unpaid payouts on a shortfall (G5 direction).                   ║
╚══════════════════════════════════════════════════════════════════════════════════════════╝
```

---

## 7. ROLLBACK / FORWARD-ONLY POSTURE PER MIGRATION

| Migration | Posture | Guard | Note |
|---|---|---|---|
| 093 | **FORWARD-ONLY from the moment it lands** (no `093_*` rollback file exists; PRE-8) | — | ~14 body replacements + payments CHECK/NOT NULL changes; the dark posture (flags false, `venue` unexposed, no signing key) makes a mid-apply failure recoverable by fix-forward |
| 094 | guarded rollback `094_organization_obligation_rollback.sql` | refuses while any `kernel.organization_obligation` row exists | restores `close_settlement` to 093 10d text — presumes 093 stays |
| 095 | guarded rollback | refuses while money state exists (held/rearmed payouts) | body-only restores over 093 |
| 096 | guarded rollback (`096_*_rollback.sql`) | refuses while `kernel.payout_reversal` / `organization_obligation_recovery` rows exist | drops the two tables + verbs; re-grants as 094/095 shipped |
| 097 | guarded rollback | `venue_id` column drop refused while any obligation row exists (DESIGN 2.7); function bodies restored to 093/094/095/088 text | forward-fix posture once a shortfall or unlined obligation exists |
| 098 | guarded rollback | refuses while any commission line produced under pro-rata exists | restores 10e / 090 / 085 bodies; PFA stays recorded |
| 099 | rollback unschedules the 3 jobs and drops `check_signing_key_invariants` | seeds cannot be removed (append-only `platform_config`; 085 orphan-key precedent) | after S-12/P-5 the keys must be set `false` (quorum) or the jobs unscheduled BEFORE the rollback |
| Any | after the FIRST native mint (S-20) or FIRST transfer (P-4) | — | the whole train is forward-only; corrections are new facts (`settlement_line` append-only, `payout_reversal`, `obligation_recovery`) |

Sequence for a rollback while still dark (before S-9): `scripts/release/local_rollback_battery_093_099.sh` proven identity-0 →
apply `099 → 094` rollbacks in reverse on production → verify ledger 108 (093 remains) → 093 stays, acknowledged.

---

**NOT EXECUTED. NOTHING IN THIS DOCUMENT IS AUTHORIZED.** No production mutation, no remote, no Stripe call, no secret,
no deploy, no git act was performed in authoring it. Numbers cited come from KI/KJ (executed on `snatchit_rehears_i`),
the design memos, and the 2026-09-02 deployment record; every value that is the owner's is an `<OWNER_VALUE:…>` placeholder.

## Package 105 addendum — the completed door plane (DO NOT EXECUTE)

The door plane is now MECHANISM-complete (packages 102-105). Insert these steps into the activation
sequence; every step keeps its label. Full derivation + owner-decision list is in
`FINAL_DOOR_PLANE_ACTIVATION_READINESS_REPORT.md`.

- **[OWNER APPROVAL]** Sign PFA-18B (single-admin revoke un-park), PFA-26-UNPARK (bcrypt PIN KDF),
  PFA-PT-9 items 1&3, PFA-PT-6, PFA-PT-8; decide KMS provider/algorithm (D1/D2).
- **[ENGINEERING, post-signature]** Land the four small un-park/conformance migrations: revoke
  (wire `kernel.force_close_key_manifests` + single-admin authz), PFA-26 PIN (create extension pgcrypto
  + re-create create_door_pin/mint_door_session), the record_scan/reconcile service_role door-session
  auth path, and cancel_event's §7.2.1 force-close wiring. Re-run the full test floor + CI.
- **[READ ONLY]** Confirm the production-observation closeout ARTIFACT (never "time elapsed").
- **[PRODUCTION MIGRATION]** Apply 093→(latest) forward-only, hashes pinned, AUTODEPLOY-VERIFIED-OFF.
- **[KMS][TWO-PERSON]** Ceremony: create the key, insert ONE `kernel.signing_key` (algorithm matching);
  dual-control the fingerprint; arm `signing.monitor_enabled`.
- **[EDGE DEPLOY]** credential-sign, primary-checkout, door-session, door-manifest with KMS+provider env.
- **[CONFIG]** Provision the door PIN(s) (now un-parked); onboard a real org (Connect + fee); expose the
  RPC surface to PostgREST.
- **[CONTROLLED SALE][IRREVERSIBLE at issue_ticket_atoms, G3]** first quote → PaymentIntent → atom →
  credential-sign → M1 → C37/M2 → **[CONTROLLED SCAN]** door admit → offline reconcile. Prove a refund.
- Venue payout is a SEPARATE later sequence; promoter payout stays DARK.

## Package 106–109 addendum — the four un-parks are now LANDED (DO NOT EXECUTE)

Supersedes the "Package 105 addendum" pending-work note: the four migrations it listed are now
authored, tested, and DARK/unapplied (093–105 byte-untouched). Backend construction is complete for
a controlled first sale + signed credential + controlled door scan. The remaining sequence:

1. **[OWNER APPROVAL]** Sign PFA-18B (106 revoke un-park), PFA-26-UNPARK (107 bcrypt PIN), PFA-PT-9
   items 1&3 (104/109), PFA-PT-6 and PFA-PT-8 (wire format + algorithm pin). D1/D2 are owner-decided
   (AWS KMS / ES256). See POST_FREEZE_AMENDMENTS "OWNER GATE RATIFICATION TRAIN, 2026-09-03".
2. **[OWNER/LEGAL]** Resolve tax (PFA-PT-7) or affirm compute-none; set `deletion.post_event_hold_hours`.
3. **[OBSERVATION]** Confirm the production-observation closeout artifact (ledger 107, 0 signing keys,
   native edges undeployed, no mutation).
4. **[MIGRATE]** Apply migrations 093→109 to production (forward-only, hashes pinned,
   `AUTODEPLOY-VERIFIED-OFF`, `git_branch` empty). 107 includes `create extension if not exists
   pgcrypto with schema extensions` (already present in prod — a no-op).
5. **[KMS CEREMONY]** Two-person: create the AWS KMS asymmetric ES256 key; insert ONE
   `kernel.signing_key` row (SPKI `public_key`, version-pinned `kms_handle_ref`, `algorithm='ES256'`).
6. **[DEPLOY]** Deploy the DARK edges (credential-sign, primary-checkout, door-session, door-manifest)
   with KMS + provider env.
7. **[CONFIG]** Provision the door PIN(s) via `create_door_pin` (now un-parked); onboard a real org
   (Connect + `fee.buyer_service_bps`); expose the RPC surface to PostgREST; publish an event on_sale.
8. **[CONTROLLED SALE + SCAN]** quote → PaymentIntent → issue_ticket_atoms (the irreversible point) →
   credential-sign (M1) → door M1 verify → C37/M2 → controlled scan (`record_scan_door`) → offline
   reconcile (`reconcile_offline_scans_door`). Prove a refund end-to-end before widening.
9. **[BREAK-GLASS — PFA-PT-9 item 5]** If an admin_action ownership transfer occurs during an OPEN
   door episode, force-close/refresh that session's manifest (revoke's `force_close_key_manifests` or
   a session-scoped close) so no offline device admits a stale credential until not_after.
10. **[SEPARATE — venue payout]** Only after the first sale is proven + settled (see the payout runbook).
