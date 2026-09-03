# PHASE-2 DARK SUBSTRATE — PRODUCTION DEPLOYMENT RECORD (2026-09-02)

OWNER AUTHORIZATION: given in-session 2026-09-02 (Option A+C dark DB apply; retry
authorization for the apply command after the local permission layer surfaced the
human approval gate). Executor: Claude (Fable 5.1), this session.

- WINDOW: 2026-09-02 ~19:40Z (gates) → 20:41:58Z apply start → 20:43:31Z apply end
  → 20:47Z API cutover + edges → 20:5xZ smoke complete.
- SOURCE: phase2/consolidation @ d0b155da2c3264aa4fb5a9acccf1f410ae18d446 (verified
  local=remote at window open; CI green on that head; 076–092 hashes byte-identical
  to the package closing records; freeze held for the window).
- BACKUP: Pro plan; PITR disabled; 8 daily physical backups retained; newest
  COMPLETED 2026-09-02T13:50:19Z (<24 h). Local belt-and-suspenders row snapshot of
  all core public/auth tables in backups/ (gitignored). Docker absent → no local
  CLI dump; gate satisfied on the confirm branch.
- PREFLIGHT: 21/21 PASS three times (T-24H-class 19:4xZ, T-1H-class, T-15M-class
  20:00:27Z). Rollback battery 17/17 identity-0 and production-order rehearsal
  (zero live-row mutation; verify 18/18; suites 2622/2622) re-run at the tip.
- APPLY: `supabase db push --linked --include-all` after a dry-run plan check that
  gated on exactly 076..092. 17 migrations applied in 93 s. Ledger 90 → 107.
- POST-APPLY (+5M): V1–V18 ALL PASS on production. Cron 19 jobs; first ticks all
  succeeded. Legacy row counts identical to the pre-apply snapshot.
- API CUTOVER: PostgREST db_schema `public,graphql_public` → `public,graphql_public,kernel`.
  Probes: kernel reachable + anon walled (42501); venue rejected (PGRST106 listing
  only the three exposed schemas); public serves 200.
- EDGES: delete-account v18 (OR-17 cutover; one post-deploy fix — the rate-limit
  call's parameter is `p_max`, corrected and redeployed within the window),
  create-payment-intent v45 (F-5 guard), confirm-and-release v34 (F-5 guard).
  No other function touched.
- SMOKE (throwaway accounts only): request → DELETION_PENDING ✓ · exactly one
  account_deletion_pending envelope ✓ · pending buyer → 403 account_deletion_pending ✓ ·
  withdraw → ACTIVE ✓ (second throwaway, inside the sweep window) · payment flow
  normal after withdrawal (400 validation, no guard trip; no Stripe object minted) ✓.
- EXPECTED-BEHAVIOR FINDING: an account with ZERO obligations reaches the ERASED
  tombstone on the next */2 sweep tick — the ratified "tombstone (no waiting
  window)" design (RATREC :584). Smoke user 1 is ERASED; its completed-notice
  envelope drained; the E-only delivery sits suppressed (email N1-gated).
- OBSERVATION STATE (+30M class): outbox done:3 dead:0 · notifications 3 ·
  deliveries pending:2 (push; claim fail-closed on the NULL lease) suppressed:3 ·
  cron 80/0 succeeded/failed · flags 5/5 false · owner-unset keys 3/3 NULL ·
  native money rows 0 · legacy counts 56|98|111|36 unchanged.
- ROLLBACK STATE: FORWARD ONLY (real Phase-2 facts exist as of the smoke).
- PR #28: OPEN and untouched through the window; owner disposition CLOSE/SUPERSEDE
  now that the cutover is live (close action to be taken per owner instruction).
- INCIDENTAL: the management API's postgrest GET returned the project JWT secret
  into the session transcript (not used, not stored elsewhere); flagged to owner.
  GitHub reports 8 pre-existing Dependabot advisories on the default branch.
- NOT DONE (per authorization): no flag flips, no Stripe changes, no email, no
  push lease, no Vault secrets, no other schema exposure, no PR #28 merge, no
  post-092 migration, no rail activation.


## OBSERVATION CYCLE — checkpoint 1 (2026-09-02 ~21:35Z, elapsed ~0.9 h of 24)
- Deployed-state verification: 12/12 PASS (tip 74479b81; 076-092 immutable; ledger 107;
  flags 5/5 false; owner-unset 3/3 NULL; exposure exactly public,graphql_public,kernel;
  cron 19 by exact name - no parked tick armed; PFA-1 sweep 0; anon walls 0).
- PR #28: CLOSED as SUPERSEDED (unmerged, branch retained) after mechanical confirmation -
  deployed delete-account source contains zero auth.admin.deleteUser calls; cutover
  request/withdraw smoke-proven; owner ruling recorded in-session.
- Cron: 19/19 jobs, every run succeeded since apply (0 failures; holder-mix dailies not
  yet due; CRM ticks succeed as fail-closed no-ops on the absent secret - by design).
- Deletion: ERASED:1 (smoke1 - the ratified no-waiting-window tombstone), ACTIVE:3
  (smoke2 + the two 078 sentinels); both smoke auth rows present (no physical delete);
  0 orphaned requests; no real-user deletion activity.
- Money: legacy invariants 0 anomalies; native money rows 0 across payout/refund/
  market_sale/reserve/custody ledger; 0 promoter payouts.
- Notifications: outbox done:3 dead:0; deliveries pending:2 (push; claim fail-closed on
  the NULL lease) suppressed:3 (channel_unavailable - email N1); payload scan 0 hits.
- Logs: 0 error-severity postgres lines in the window; edge invocations = the cron tick
  plus the smoke calls only.
- Credential follow-up (read-only inventory; NO rotation this cycle): the value that
  reached one AI session transcript via the management API postgrest GET is the
  project's legacy signing secret for API tokens - it can mint any role's token, so
  treat it as compromised-by-policy. Consumers of that category: the deployed mobile
  build (baked legacy anon key), web (Vercel env), edge functions (platform-injected
  env - auto-tracks rotation), the Vault service_role_key row (read by
  enforce-transfer-expiry and the two CRM ticks), and user sessions. Recommended
  owner-gated sequence: (1) ship mobile + web on the new publishable key
  (rotation-independent), (2) stage the new secret key into the Vault row, (3) rotate
  in a low-traffic window (all sessions sign out - 14 users), (4) verify edges, web,
  cron. Timing: after the publishable-key mobile build clears review; NOT during this
  observation cycle.
- Mobile follow-up (owner-approved separate client work, authored on the post-cutover
  line): app/settings/index.tsx now reads own deletion state (kernel.identity_ext,
  owner-scoped), shows a DELETION_PENDING banner with a working withdraw action, and
  the request-flow copy no longer claims immediate physical deletion. No App Store
  build published.
- 24-hour close: NOT DUE (target ~2026-09-03T20:45Z). Next checkpoint: the close-out.

---

## Checkpoint 2 — 24-HOUR DARK-SUBSTRATE CLOSEOUT (2026-09-03T20:45Z)

**OBSERVATION START** 2026-09-02T20:43:31Z (DB apply end) ·
**OBSERVATION END** 2026-09-03T20:45:14Z ·
**ELAPSED** 24 h 01 m 43 s — the full window elapsed before anything below was
evaluated. Time gate checked first, against the host clock, as the protocol requires.

**VERDICT: 24-HOUR DARK-SUBSTRATE OBSERVATION — CLOSED — PASS.**
Production status remains **PHASE-2 DARK SUBSTRATE DEPLOYED**. No feature is live.
No rail was activated, no flag moved, no config value was set, no migration was
applied, no edge was deployed, no secret was rotated during this observation.

### Database
Ledger **107** rows; **[V]** max numeric version `092`; **[V]** `093+` rows in the
ledger: **0** — the twelve migrations authored since the deployment (093–104) are
confirmed **NOT applied**. Five-schema census **relations 75 / routines 243 /
policies 72**, matching the post-apply baseline exactly (kernel 28/109/12, venue
29/79/38, catalog 5/16/12, market 6/22/5, notify 7/17/5). All five feature flags
`false`; the three owner-unset keys still `'null'::jsonb`; **43** config keys, every
row still `version = 1` and no `effective_from` later than the apply itself — no
config changed in the window. PostgREST `db_schema` = `public,graphql_public,kernel`;
venue/catalog/market/notify remain unexposed.

### Cron
Exactly **19** jobs, names matching the register 1:1. The three parked ticks
(`notify-dispatch`, `notify-receipts`, `resale-checkout-sweep`) do **not** exist.
Across the full window from `2026-09-02 20:41:58+00`: **0 unexpected failures** —
every one of the ~9 800 runs returned `succeeded`, last status `succeeded` on all 19.
The two daily holder-mix jobs did run: `refresh-holder-mix` at 04:17:00Z and
`reconcile-holder-mix` at 04:47:00Z, both succeeded. The two CRM ticks
(`crm-export-build-tick` 1446 runs, `crm-export-purge-tick` 97 runs) succeeded as
**fail-closed no-ops**: `vault.secrets` holds exactly one row (`service_role_key`),
`crm_export_worker_secret` is absent by design, and — confirmed in the edge logs —
the ticks made **zero** HTTP calls to `crm-export-worker` in the window, so they
short-circuit before the network rather than 404ing.

### Deletion
Census **ACTIVE:4 / ERASED:1** against a deploy+1h baseline of ACTIVE:3 / ERASED:1.
The delta is **one new account creation, not a deletion**. Full accounting of the
five `kernel.identity_ext` rows: two 078 sentinels (`…f0`, `…f1`, ACTIVE), the smoke1
identity `b83e9195…` (ERASED at 2026-09-02T20:50:01Z — unchanged all window), the
smoke2 identity `32c91a84…` (ACTIVE), and one **REAL** identity `3b7b50af…`
(`contact@snatchitapp.com`, auth row created 2026-09-03T14:39:32Z, identity_ext
14:40:18Z, **ACTIVE**, `deletion_requested_at` NULL).

**REAL-USER DELETION EVENTS: 0.** Nothing to review individually.

Every invariant holds: `auth.users` = 19 rows, **0** soft-deleted, **0** physically
deleted — the ERASED identity's auth row is still present, which is the tombstone
behaving as ratified; **0** `identity_ext` rows without an auth row; **0** orphan
requests (DELETION_PENDING with NULL `deletion_requested_at`); **0** rehydrations
(no ERASED→ACTIVE); **0** duplicate or impossible terminal transitions; **0** rows in
`kernel.identity_obligation` (so no obligation bypass and no lost financial
obligation was possible); **0** rows in `kernel.identity_demographic_erasure`;
**0** deletion-related `kernel.admin_audit` entries. Of the 5 auth users created in
the window, 4 are the sentinels and smoke identities and 1 is the real signup above.

### Edges
`delete-account` is at **v19**, not v18: v18 was the cutover and **v19 is the
in-window fix** (`updated_at` 2026-09-02T20:49:26Z) for the `check_rate_limit`
`p_max_requests`→`p_max` defect. `create-payment-intent` **v45** and
`confirm-and-release` **v34** unchanged (both 2026-09-02T20:47:00Z). No edge has
been deployed since 20:49:26Z on the apply day — **no deploy drift**. Eleven
functions total; none of the five undeployed activation edges
(`connect-onboarding`, `primary-checkout`, `refund-execute`, `payout-execute`,
`credential-sign`) is present.

Every non-200 in the window, enumerated:

| When | Function | Status | Classification |
|---|---|---|---|
| 09-02 20:48:03 | delete-account | 503 | **FIXED-IN-WINDOW** — the known `check_rate_limit` arity defect. **One occurrence, no recurrence.** |
| 09-02 20:48:04 / 20:51:37 | create-payment-intent | 400 ×2 | SMOKE — negative input assertions |
| 09-02 20:49:37 | create-payment-intent | 403 | SMOKE — **F-5 deletion guard true positive**, fired 1 s after the 20:49:36 deletion request |
| 09-02 21:34 → 09-03 20:12 | enforce-transfer-expiry | 401 ×10 | **PRE-EXISTING**, see below |

**EDGES P0: 0 · EDGES P1: 0.** No unexplained 5xx, no false deletion-guard 403, no
physical-delete path, no legacy purchase or transfer regression. Real legacy traffic
in the window behaved: `create-connect-account` ×7 all 200, `create-payment-intent`
×2 all 200 (09-03 14:40:20 and 14:56:29 — the second is a client retry that correctly
reused the pending intent instead of minting a second one).

**The 10× 401 on `enforce-transfer-expiry` is PRE-EXISTING, not a Phase-2
regression** — and this was proven, not assumed: the same query over the 24 h
*before* the deployment (2026-09-01T20:00Z–2026-09-02T20:00Z) returns **9 × 401 against
720 × 200**, an identical ~1.2 % rate. The function was not on the Phase-2 train.
`pg_cron` reports these ticks `succeeded` because the SQL-side HTTP post succeeds
regardless of the response status, so the sweep silently skips ~1 in 75 ticks; the
job runs every 2 minutes and the sweep is time-based and idempotent, so the missed
work is picked up on the next tick. Recorded below as a fix-forward item, **P3, not
a blocker**.

### Notifications
`notify.outbox`: **done 3**, pending 0, claimed 0, **dead 0**. `notify.delivery`:
**pending 2** (both `push`), **suppressed 3** (all `channel_unavailable`), sent 0,
failed 0, **dead 0**. All five delivery rows date from the 09-02 20:50–20:52 smoke;
no notification activity at all in the following 24 h, which is correct for a dark
substrate. **Push remains FAIL-CLOSED**: `notify.delivery_lease_interval` is still
`'null'::jsonb` and **`claimed_until` is NULL on every row — 0 deliveries have ever
been claimed, 0 ever sent.** **Email remains OFF** (`channel_unavailable`).
Payload scan across `notify.notification.params`: **0** values matching an email
pattern, **0** matching a 7+-digit sequence. **NOTIFICATION DEFECTS: 0.**

### Money
**LEGACY:** payments 57, transfers 36, listings 111, bids 98, disputes 0,
payout_decisions 4, webhook_retries **0 open**. In-window change: **1 payment row**
(and nothing else — 0 new transfers, listings, bids or payout decisions). That row
is `965c65a0…`, created 09-03 14:40:20 by the new real user, `buy_now`, livemode,
status **pending** — an abandoned checkout, no money captured. Invariants tested for
impossible states rather than stable counts, per protocol: **0** duplicate succeeded
payment per (listing_id, buyer_id); **0** duplicate `stripe_payment_intent_id`;
**0** duplicate `stripe_refund_id`; **0** duplicate `stripe_transfer_id`;
**0** impossible payment status; **0** orphan payment→listing, transfer→listing or
transfer→payment; **0** double payout releases.

Two legacy hygiene rows were surfaced and both are **PRE-EXISTING, not Phase-2**:
3 payments with `refunded_at` set and no `stripe_refund_id` (2026-03-27, and two on
2026-08-04) and 1 transfer released against a non-succeeded payment (2026-04-01).
All four predate the deployment by four to five months. **LEGACY MONEY REGRESSION: 0.**

**NATIVE: economically inert, verified across seventeen tables** — `kernel.payout` 0,
`kernel.refund` 0, `market.market_sale` 0, `kernel.reserve` 0,
`kernel.ticket_ownership_log` 0, plus `kernel.tickets` 0, `kernel.payment_native` 0,
`venue.order` 0, `venue.attribution` 0, `market.listing_native` 0, `venue.settlement` 0,
`venue.scan` 0, `venue.inventory_batch` 0, `catalog.event` 0, `kernel.organization` 0,
`kernel.wallet_pass` 0, `kernel.dispute_native` 0. Payouts with
`cause = 'promoter_commission'`: **0**. **NATIVE MONEY MOVED: NONE.**

### Security
**PFA-1 sweep: 0** PUBLIC/anon EXECUTE grants across kernel/venue/market/notify (and
**0** in catalog as well). `anon` has **no USAGE** on kernel, venue, market or notify;
**0** anon/PUBLIC table grants in any walled schema. RLS is enabled on **every** table
in all five schemas (0 exceptions). **239** SECURITY DEFINER routines, **0** of them
without a pinned `search_path`. `authenticated` holds 25 read grants plus
INSERT/UPDATE on `notify.preference` alone — all RLS-guarded, and all but the two
`kernel` ones unreachable over the API since only `kernel` is exposed. PostgREST
exposure unchanged. Vault holds exactly one secret row, `service_role_key`,
`updated_at` **2026-06-11** — untouched, as instructed. **SECURITY P0: 0 ·
SECURITY P1: 0 · PRIVILEGE DRIFT: 0.**

### Logs
Postgres logs across the full window: **0 FATAL, 0 PANIC**, and **15 ERROR-severity
lines**, every one classified:

- **1 × `42501` "permission denied for schema kernel"** (09-02 20:46:36,
  `authenticator`) — **SMOKE**: the schema wall refusing a PostgREST reach into
  `kernel`, i.e. the control working. One occurrence, inside the smoke window,
  never again in 24 h.
- **12 × `23505` `push_tokens_token_key`** (09-03, spread 06:24–19:50) — **LEGACY,
  pre-existing client defect.** Root cause identified: `src/hooks/usePushToken.ts`
  does a read-then-insert whose `SELECT` is RLS-scoped to the caller's own rows, so a
  device token already held under a *different* `user_id` is invisible and the
  `INSERT` then hits the global unique constraint. The error is swallowed by the
  hook's `try/catch`, so push registration fails silently for that device.
  **Not Phase-2**: migration 092 was additive on `public.push_tokens` (four
  `add column if not exists` plus one partial index) and did not touch the
  constraint, and Phase-2's own `notify.register_push_token` already does this
  correctly (`on conflict (token) do update`) — it is simply unreachable, because
  `notify` is not exposed. Absent from the pre-deploy window only because that
  window carried 5 286 API requests but just 4 auth events — no signed-in mobile
  sessions. **P3 fix-forward.**
- **2 × `42703` "column listings.cover_image_url does not exist"** (09-03 14:40:17,
  14:56:26) — **LEGACY** client/schema mismatch from the same real user's session.
  Phase-2 changed no `public.listings` column. **P3 fix-forward.**

Statement-log lines containing the word "error" inside migration bodies were excluded
as the protocol directs. **NEW PHASE-2 ERRORS: 0. LEGACY REGRESSIONS: 0. UNKNOWN: 0.
UNRESOLVED PHASE-2 P0/P1: 0.**

**SENTRY: NOT AVAILABLE TO THIS SESSION** — no Sentry tool or credential is exposed
here, so "new unresolved P0/P1" could not be read from Sentry itself. It is reported
as **NOT VERIFIED** rather than as zero. The substitute evidence is complete over the
same window and is stated above: every edge invocation and its status, every postgres
error line, every cron run. An owner with Sentry access should confirm independently
before treating the P0/P1 count as attested.

### Mobile
Verified at source tip **`7e89f0e`**: `app/settings/index.tsx` still carries the
own-row deletion-state read (`.select('deletion_state')` against
`kernel.identity_ext`, owner-scoped — reachable because `kernel` is the exposed
schema and `authenticated` holds SELECT under RLS), the DELETION_PENDING banner, the
working withdraw action, and **no physical-delete language** (the copy says the
request "cannot be undone", not that data is erased immediately).
`src/screens/PlaceBidScreen.tsx` still carries the F-5 bid guard, refusing a bid when
`deletion_state = 'DELETION_PENDING'`. **CI is green on the tip** (run 33685688516,
`success`, 2026-09-02T21:32Z).

**MOBILE DELETION BUILD READY FOR APP-STORE RELEASE AUTHORIZATION: YES** — the code is
correct against the deployed backend and CI passes. Not published; publication remains
an owner act. One sequencing note carried forward from the credential inventory: the
publishable-key migration should ride the same build, so that the later secret
rotation is client-independent.

### Secret
**NOT ROTATED.** The blast-radius inventory recorded at checkpoint 1 is **still
complete** — independently re-verified: `vault.secrets` contains exactly one row
(`service_role_key`), unchanged since 2026-06-11, and no new consumer category
appeared in the window. Consumers remain: the deployed mobile build (baked legacy
anon key), web (Vercel env), edge functions (platform-injected env, auto-tracks
rotation), the Vault `service_role_key` row (read by `enforce-transfer-expiry` and
the two CRM ticks), and live user sessions. **Recommended future sequence, unchanged:**
(1) ship mobile + web on the new publishable key, which is rotation-independent;
(2) stage the new secret key into the Vault `service_role_key` row; (3) rotate in a
low-traffic window — **all user sessions sign out**, now 15 real users (19 auth rows
less 2 sentinels and 2 smoke), up from the 14 recorded at checkpoint 1; (4) verify
edges, web and cron, with a rollback plan that restores the prior Vault value and a
failure plan that assumes the mobile build cannot be hot-fixed. **Rotation is its own
owner-authorized production operation and must not ride an activation train.**
**SECRET ROTATION READY FOR A SEPARATE PLANNED WINDOW: YES.**

### Material change since checkpoint 1 — recorded, not acted on
The observation window was not idle in the repository. Since `7e89f0e`, branch
**`feature/venue-native-and-product-v2`** has accumulated migrations **093–104**, five
new edge functions (`connect-onboarding`, `primary-checkout`, `refund-execute`,
`payout-execute`, `credential-sign`), a native branch and dispute wiring for
`stripe-webhook`, and an extensive ruling/decision corpus. **None of it is applied or
deployed** — independently confirmed against production: ledger max numeric version
`092`, zero `093+` ledger rows, the 093 connect-mirror columns absent from
`kernel.organization`, config at 43 keys (vs 49→54 in the local replay), cron at 19
jobs (vs 22), and none of the five new edges present in the function list. The
closeout verdict above is therefore unaffected. This is noted because the standing
task context described the post-deployment line as ending at `7e89f0e`, and it does
not.

### Fix-forward register opened by this closeout
None of these is a Phase-2 defect and none blocks the close.

| # | Item | Class | Sev |
|---|---|---|---|
| OBS-1 | `usePushToken.ts` read-then-insert is RLS-blind; 12 × `23505` in 24 h; push registration fails silently for a token held by another user | IMPLEMENTATION FOLLOW-UP | P3 |
| OBS-2 | A client requests `listings.cover_image_url`, which does not exist; 2 × `42703` | IMPLEMENTATION FOLLOW-UP | P3 |
| OBS-3 | `enforce-transfer-expiry` returns 401 on ~1.2 % of cron ticks (pre-dates the deployment); `pg_cron` records these as `succeeded`, so the skip is invisible in the job register | IMPLEMENTATION FOLLOW-UP | P3 |
| OBS-4 | 3 legacy payments refunded without a `stripe_refund_id`; 1 legacy transfer released against a non-succeeded payment — all Mar–Aug 2026 | IMPLEMENTATION FOLLOW-UP | P3 |
| OBS-5 | Sentry P0/P1 could not be read from this session | OPERATIONAL CONFIGURATION | P3 |

### Disposition
**PRODUCTION ACTIVATION: NOT AUTHORIZED.** The activation prioritization required by
the closeout protocol is written to
`docs/release/PHASE2_ACTIVATION_PRIORITIZATION.md`. **NEXT ACTION: owner
authorization to build the recommended activation train.** Nothing further is to be
applied, deployed, configured, armed or published without it.
