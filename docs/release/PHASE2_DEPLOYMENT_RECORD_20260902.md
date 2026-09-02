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
