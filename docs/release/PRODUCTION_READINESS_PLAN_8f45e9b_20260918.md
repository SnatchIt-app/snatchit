# Production-readiness plan — candidate `8f45e9b` (A, 2026-09-18). PLANNING ONLY

**Scope, owner's words:** *"prepare a production-readiness plan identifying exactly which database changes this candidate requires, their dependencies, verification and rollback approach, and the build/deployment sequence. Separate required changes from optional or deferred work; don't assume every migration applied to the sandbox belongs in production. Use existing records and source first. Identify any missing live facts and the specific read needed to establish them."*

**Not authorized, not done:**
- no migration;
- no merge into `main`;
- no production deployment or read;
- no build;
- no phone testing.

**Status marks used throughout:**
- **[S]** from source at `8f45e9b`.
- **[R]** from the release records.
- **[L]** needs a live read (§7). Nothing here was read from production.

## 0. Phase closed

The fix-and-consolidation phase is **closed at `release/production-gate-20260918` = `8f45e9bb4c48eeede270fff3c71bd4348c18cc4`**.
- It equals Build 21's tree except for one documented test-title rename. D confirmed that independently.
- CI was green on all five merges, and nothing was deployed or migrated.
- **The candidate** is that commit: the mobile client, the edge functions under `supabase/functions/`, and the migrations under `supabase/migrations/`.
- `web/` and `admin/` deploy on their own Vercel tracks and are **out of this plan** (§6.4).

## 1. Production versus the candidate

- **Production [R]** (`PHASE2_PRODUCTION_STATE_20260912.md`, read-only reads 2026-09-12):
  - ledger **135 rows**: numeric 000–120 with gaps (114 rows) plus 21 other rows;
  - **121 not applied**; nothing applied since 2026-09-12, per every later record;
  - 14 edge functions: 11 legacy plus `credential-sign`, `door-manifest` and `door-session`, dark;
  - 24 cron jobs; trust root live; native flags off.
- **The candidate [S]:** 157 migration files.
- **The 135 recorded rows match the candidate's oldest 135 exactly [S + R arithmetic]:**
  - the 114 three-digit files up to 120;
  - the 16 four-digit files (`0230`…`0661`);
  - the 5 earliest timestamped files (`20260714190445` … `20260902003623`).
- So **22 migrations are pending: [L1] must confirm this exact set.**

**The sandbox is not production-shaped [R]:**
- It never received 110–120 (production's trust-root and ops-console chain; ruling 5 kept 115–120 off it).
- It holds **20 of the 22**. It lacks 121 and 126.
- Sandbox device evidence therefore **never ran against a production-shaped database**, and **sandbox-applied does not mean production-required** (§2).

## 2. The 22 pending migrations, classified

"Caller" = the code in the candidate that calls an object the migration creates [S]. Every migration has a rollback file at `supabase/rollbacks/<version>_rollback.sql` [S], and a pgTAP file numbered per the registry.

### 2a. REQUIRED: the candidate's client or edge functions call what they create

| Migration | What it does | Caller in the candidate | On sandbox |
|---|---|---|---|
| **127** | release guards L1/L2: `release_reservation_for_payment`; redefines `public.release_reservation` | edges `enforce-transfer-expiry`, `stripe-webhook` | yes |
| **128** | `register_push_token` secure rebind; `push_token_rebind_epoch` | client `src/lib/push/registerToken.ts`, `challenge.ts` | yes |
| **129** | `public.revoke_push_token` (the sign-out revoke) | client `src/lib/auth/signOut.ts` (gated file) | yes |
| **130** | checkout supersede claim | edge `create-payment-intent` | yes |
| **131** | session-bound push bindings; `revoke_all_push_bindings`; auth triggers | client `signOut.ts`, push registration | yes |
| **132** | checkout group claim (D's OPEN MONEY DEFECT fix) | edge `create-payment-intent` | yes |
| **133** | edge base URL from Vault `project_url`; redefines 033/034/035 notify triggers and **099 `kernel.check_signing_key_invariants`**; re-registers 5 crons | no direct caller. **Prerequisite of 135**, which posts through `project_url` | yes |
| **135** | push token proof of possession (challenge tables and RPCs) | client `registerToken.ts`, `challenge.ts`, `registration.ts`; edge `send-push` | yes |
| **136** | `get_my_security_notices`, `mark_security_notices_read` | client `src/lib/security/notices.ts` (F-SEC-1/2 hook) | yes |
| **139** | `notify-report` delivery claims | edge `notify-report` | yes |
| **140** | `mark_transfer_sent` idempotent, **returns jsonb**; `attach_transfer_evidence` | client `app/transfer/send/[id].tsx`, which reads `transitioned`/`already_sent` | yes |
| **20260906100000** | checkout reservation authority; redefines `complete_auction_payment`, `mark_listing_sold`, `reserve_buy_now` | payments RC unit, used by the RC edges | yes |
| **20260906110000** | `settle_verified_payment`, `get_unsettled_payments`; redefines `cleanup_expired_reservations` | edges `confirm-payment`, `enforce-transfer-expiry`, `stripe-webhook` | yes |
| **20260906120000** | payout attempts, append-only refunds, `account_deletions` | client `src/lib/checkout/setupDecision.ts` (`record_payment_refund`, gated file); edges `_shared`, `stripe-webhook`, `enforce-transfer-expiry`, `delete-account` | yes |
| **20260906130000** | deletion sweep respects live-rail obligations; redefines `kernel.sweep_deletion_pending` | no direct caller. **Part of the reviewed payments RC unit**, shipped with it | yes |
| **20260909000000** | `public.get_my_tickets` | client `src/lib/tickets/api.ts`. **The Tickets tab ships unconditionally** (`app/(tabs)/_layout.tsx:36`) | yes |
| **20260916000000** | processing sweep arm (`get_unsettled_payments`) | edge `enforce-transfer-expiry` | yes |

### 2b. PARITY: production already has the end state; the version is applied only to align the ledger

| Migration | Evidence | Production requirement |
|---|---|---|
| **123** | transfers FK to `profiles`: production already carries it (read-only 2026-09-10) [R] | must be **proven a no-op** on production **[L2]** before it is applied |
| **124** | bids FK to `profiles` ON DELETE CASCADE: production already carries it; 0 orphans on 2026-09-12 [R] | the same, plus a fresh orphan count **[L10]** |

### 2c. OPTIONAL: a separate track, not needed by this candidate

| Migration | Why optional | Owner |
|---|---|---|
| **125** | the scanning-contract correction (`venue.sync_scan_device_manifest`). Native scanning is dark and the flags are false [R]. Recorded as "needed before the scanning flip" | B |
| **126** | ops refund exactness: redefines `ops.build_daily_summary`, `ops.money_overview`, `ops.refresh_metrics`, **the live admin console's figures**. No candidate caller. **Not applied on the sandbox either** | B/D (admin track) |

### 2d. DEFERRED by standing decision

| Migration | Decision |
|---|---|
| **121** | manifest signing context STRICT: *"applied only under `AUTHORIZE PFA-18C MIGRATION 121`"* [R] |

**Not in the candidate at all:** 137, 138 and 141 (never on the release branch), and the sandbox prerequisites 115–120, which production already has.

**Owner decision D-1:** whether 125 and 126 ride with this apply or wait. If they wait, they fall below the tip and need `--include-all` later. That is a tidiness cost only, as the record says, not a correctness one.

## 3. Dependencies and order

- **Order = file order within the pending set** [S]: 123, 124, (125, 126 if D-1 says yes), 127, 128, 129, 130, 131, 132, 133, 135, 136, 139, 140, 20260906100000, 20260906110000, 20260906120000, 20260906130000, 20260909000000, 20260916000000. **121 is excluded.**
- **Chains inside the set** [S]:
  - `register_push_token` is redefined in sequence by 128, then 131, then 135.
  - 133 must precede 135, which posts through `project_url`.
  - 130 precedes 132 (the checkout claims).
  - `get_unsettled_payments`: 20260906110000, then 20260916000000.
  - 127's `release_reservation_for_payment` is used by the RC edges.
- **What CI proves and what it does not.** CI's fresh replay applies all 157 in `LC_ALL=C` file order. Production has already applied the 21 older rows **in a different historical order**, and applies 110–114 after 115–120 [R]. **A production-order rehearsal is required** (§5, step 1). The existing `convergence_prod_order_rehearsal.sh` already models this [R].
- **Old code keeps running during the window.** Between migration and function deploy, the **deployed** legacy edge code and the **installed App Store client** run against the new schema. Functions whose bodies change underneath them:
  - `public.release_reservation`, `mark_transfer_sent` (void → jsonb);
  - `complete_auction_payment`, `mark_listing_sold`, `reserve_buy_now`, `cleanup_expired_reservations`;
  - the notify triggers, `kernel.check_signing_key_invariants`, `kernel.sweep_deletion_pending`.
- **Compatibility review required (A + B, from source), not yet done.** In particular:
  - **135** introduces a `challenge_required` path to `register_push_token`. **An installed client that predates b2 may stop registering push tokens** until it updates. This is a product decision for the owner (**D-2**) and depends on which client builds are live **[L9]**.
  - The RC redefinitions must keep the legacy `create-payment-intent`, `stripe-webhook` and `confirm-payment` working **for the minutes between the two steps**, or the window must be made atomic in practice (functions deployed immediately after).

## 4. Verification and rollback approach

**Before production:**
- CI green at the candidate (it is: run 35404338817).
- The production-order rehearsal of exactly the pending set, with each migration's pgTAP file and the Gate-2 census, run in CI's non-superuser role (the `pgtap-ci-not-superuser` lesson).
- Every rollback rehearsed **forward, back, forward** in that rehearsal.

**Per migration in production** (the method of the sandbox windows [R]):
- dry run: the planned version list checked **exactly**, with no default push;
- preflight (the migration's own §0 guards, e.g. 133 refuses if Vault has `service_role_key` but no `project_url`);
- apply one version;
- read back: the ledger row, the md5 of each new or redefined function, grants against `expected_grants.txt`, and the census;
- stop on any mismatch.

**Parity (123/124):** prove a no-op by comparing constraint definitions before and after, byte for byte **[L2]**.

**Rollback:**
- `supabase/rollbacks/<version>_rollback.sql` exists for all 22 [S].
- **Each must restore the body production actually runs**, not the repo baseline (CLAUDE.md). So the md5 of every function it would restore is compared to production's current body **[L2]** before approval.
- **Data-bearing rollbacks drop tables created after apply:** `checkout_group_claim`, `push_token_challenges`, `push_token_rebind_epoch`, `report_delivery_claim`, `payout_attempts`, `payment_refunds`, `account_deletions`. A rollback after real traffic loses those rows. So the rollback window is **before the edge deploy**; after that, fix forward, and the owner accepts this explicitly (**D-3**).

**After deploy:** read-only checks only.
- Function versions, cron list, ledger and census.
- **No test invocations**: the standing production restriction [R].
- Behaviour is observed only through normal traffic, or an owner-authorized smoke plan.

## 5. Build and deployment sequence (every step owner-gated; none authorized)

| Step | Action | Gate |
|---|---|---|
| 0 | Resolve **[L1]–[L11]**; B signs off 133's rewrite of the live signing monitor (099) and the 033–035 triggers; A and B finish the §3 compatibility review; owner decides D-1, D-2, D-3 | owner + B |
| 1 | Local production-order rehearsal, pgTAP (non-superuser), census, rollback cycle | A (+ D witness) |
| 2 | Confirm a production backup or PITR restore point exists **[L7]** | owner |
| 3 | **Vault: insert `project_url`** (production). A secret change, which the **standing PFA-18C restriction "no secret change" forbids today**, so it needs explicit lifting | owner (+ B) |
| 4 | Apply the pending migrations one at a time in §3 order, reading back after each | owner-authorized apply; `AUTODEPLOY-VERIFIED-OFF` confirmed visually |
| 5 | **Immediately** deploy the edge functions whose production version differs from the candidate. At least: `create-payment-intent`, `enforce-transfer-expiry`, `stripe-webhook`, `confirm-payment`, `confirm-and-release` (bundles `_shared`), `delete-account`, `send-push`, `notify-report`. The exact set comes from **[L4]**. The native arm, `ops-refund-execute` and the door functions are **not** deployed | owner |
| 6 | Post-deploy read-only verification (§4) | A + D |
| 7 | Production mobile build from a candidate tag (EAS `production` profile: `pk_live`, production project), then TestFlight and App Store | owner |
| 8 | Only after production carries every pending version (nothing left pending): align `main`. Never merge the release branch into `main` before that (B2 / AUTODEPLOY-1) | owner |

**Edge secrets [S]:** the deploy set reads `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `INTERNAL_CRON_SECRET`, `EXPO_PUSH_URL`, `ADMIN_EMAIL`, `EMAIL_ENABLED`, `EMAIL_FROM`, `RESEND_API_KEY`, `SENTRY_ENV`, `SENTRY_RELEASE`, `SENTRY_SERVER_DSN`. **[L5]** checks each name exists in production. No values are read.

## 6. Open items that are not migrations

1. **Deferred owner decisions:** F-SEC-3, F-SEC-1-B, and the unknown-outcome wording (**decide before step 7**, because the copy ships in the build).
2. **Server-side transfer-expiry / delivery-enforcement decision:** separate. The candidate does not depend on it.
3. **Unverified client facts:** App Store release status, and which builds are live **[L9]**. The owner's restriction stands: nothing is described as observed production behaviour.
4. **`web/` and `admin/`:**
   - `snatchit-web` production deploys from `feature/web-accounts-foundation`; `snatchit-admin` from `admin/operating-console` (`ab3e17f`).
   - Neither is part of this candidate.
   - 126 would change the live admin console's figures (§2c).

## 7. Missing live facts: the exact read for each (read-only; each needs the owner's authorization; none requested yet)

| # | Fact | Read |
|---|---|---|
| **L1** | The exact production ledger, confirming the 22 pending | `select version, name from supabase_migrations.schema_migrations order by version;` |
| **L2** | Production bodies and constraints that the pending set redefines or asserts: the rollback targets and the 123/124 no-op proof | `md5(pg_get_functiondef(oid))` for the **11** functions the required set redefines (§3 list), plus 5 more if 121, 125 or 126 are included; `pg_get_constraintdef` for `transfers_buyer_id_fkey`, `transfers_seller_id_fkey`, `bids_bidder_id_fkey`; existence checks that none of the new objects already exist |
| **L3** | Vault precondition for 133 | `select name from vault.secrets where name in ('service_role_key','project_url');` (**names only**) |
| **L4** | Deployed edge functions, to decide the step-5 set | the Supabase management API list (name, version, `updated_at`, `verify_jwt`, entrypoint) |
| **L5** | Edge secret names | `supabase secrets list --project-ref hqycwntpfoztoinemqns` (names and digests only) |
| **L6** | Cron state, which 133 re-registers 5 jobs in | `select jobname, schedule, active from cron.job order by jobname;` |
| **L7** | Backup / PITR availability | Supabase dashboard → Database → Backups (owner) |
| **L8** | AUTODEPLOY-1 | `git_branch ""` was read today via the connector and CLI [this session]. **CLAUDE.md still requires the owner's visual dashboard confirmation** |
| **L9** | Live client builds | App Store Connect / TestFlight (owner) |
| **L10** | Data preconditions | `count(*)` of orphan bids (124). State counts that 20260906120000's guards act on: payments and transfers by status, **counts only** |
| **L11** | PostgREST exposed schemas (why 129/136 are `public` wrappers) | API settings (owner or management API) |

**Nothing in this plan authorizes any of the reads above, any apply, any secret change, any deploy or any build.**
