# RC-20261012: proposed deployment and rollback plan (A, 2026-10-12; D reviews)

Nothing here is authorised in this sprint. Every step is a separate owner approval, in this order. Each step names
its production effect and whether it can apply migrations automatically.

## Preconditions (all at `48d20ca1`, before step 1)
- CI is green, with every step confirmed to execute.
- The gate PR's required checks are green on the head: the five CI jobs (run 38203105234) and "Immutability + ordering" (run 38203637726, PR #100). The TruffleHog secret scan (`security.yml`) runs on PRs into `main`, weekly and on manual dispatch, so it is not part of step 1.
- C: a fresh-install native build log with exit 0, and the env-pairing checks.
- B: the consumer review verdict.
- D: the C4 and candidate-safety verdict.
- E: the acceptance matrix closed at `48d20ca1`.
- The owner's D2 decision on 152. A recommends "not in this release", and this plan assumes that answer.

## Step 1: gate update (source only)
- **What:** merge the PR from `integration/rc-20261012` into `release/production-gate-20260918`.
  - The gate ruleset requires a PR, allows only the "merge" method, enforces required checks, has 0 bypass actors and
    forbids non-fast-forward.
  - The resulting merge commit's tree must equal `7feadf07…`, the tree of `48d20ca1`, because the gate has not
    moved since `abef9506`. A verifies `git rev-parse <merge>^{tree}`.
- **Production effect: none.**
  - The gate is not a deploy trigger. Web deploys only from `feature/web-accounts-foundation`, and the console only
    from its pin.
  - The Supabase GitHub integration posts a `Supabase Preview` check on PRs (it reads `skipping` on PR #100). It
    applies migrations to production only on a push or merge to `main` (DEPLOYMENT_PATHS.md).
  - CI has `contents: read`.
- **Applies migrations automatically: no.**
- **Rollback:** a revert PR on the gate. Never a force push, which the ruleset forbids anyway.

## Step 2: G2 / X11, the app build and distribution
- **The build:** an EAS production build from exactly `48d20ca1`, or from the step-1 merge commit after tree
  equality is shown, in a clean detached worktree.
  - `appVersionSource: remote`, with autoIncrement.
  - The `production` profile pairs the production Supabase ref with the live publishable key. CI enforces the
    pairing with `assert-env-pairing.mjs`.
  - Verify the EAS build metadata names the commit.
- **Then:** TestFlight, then the owner's phone session (G1), then the owner's App Store submission with manual
  release.
- **Production effect:** only the new binary, once the owner releases it.
  - The backend is unchanged.
  - C4's 63 literal `.from()` chains and 25 `.rpc()` calls all resolve against the local ledger-164 stand-in
    `pkg151_rehears`, not against production. The 16 dynamic sites rest on the hand resolution at `9bbeaec6`, which
    still applies because `app/` and `src/` differ in 0 files.
  - Users on older builds are unaffected, because nothing on the server changes.
- **Applies migrations automatically: no.**
- **Rollback:**
  - Before release: do not release, or expire the TestFlight build.
  - After release: there is no server-side rollback, because nothing changed there. Ship a fixed build, or remove the
    version from sale in App Store Connect.

## Step 3 (independent, not a prerequisite for step 2): S7, gate → `main`
- **Migration-bearing.** `main` (`eadd456a`) lacks 78 of the gate's 167 migration files.
  - 75 are in the production ledger (164 rows).
  - **3 are NOT applied in production: 121, 125 and 126.** They are deferred under decision D1 (121 is B's PFA-18C
    track; 125 and 126 are not applied).
  - With auto-deploy on, a merge to `main` leaves exactly these 3 pending for the integration's `db push`. Because
    they sit below the numbered tip, the CLI may apply them or refuse (C7). The plan never relies on either.
  - FINAL_INTEGRATION_PLAN D1 requires the release record to list them as the only files on `main` that are not in
    the ledger: **121, 125, 126**.
- **The `main` ruleset allows only squash merges, with linear history.** A merge commit needs the owner's PR-3
  (MAIN_PROTECTION_PROPOSAL §2).
- **Applies migrations automatically: POSSIBLY.** The Supabase GitHub integration runs `db push` on a merge to `main`
  if its auto-deploy is on, and the current setting is unverified.
  - Precondition: a **fresh** owner visual confirmation that auto-deploy is off (`AUTODEPLOY-VERIFIED-OFF`), and D's
    pre-merge check.
  - Post-merge: the `Supabase Preview` check reads `skipped`, and an owner-authorised ledger read is unchanged at
    164 with no 121/125/126 rows.
  - If any of the three had been applied, it is handled as an incident: the matching `supabase/rollbacks/` file, under
    owner approval and with D's read-back.
- **Rollback:** source only. A revert PR on `main`. If anything was applied, the matching
  `supabase/rollbacks/` files are run under separate owner approval.

## Not deployed in this release
- Web and console: their production sources equal the candidate's `web/` and `admin/`.
- Edge functions and database: nothing new.
- Dashboards v2: preview only. Venue v2 needs the unapplied `venue_api` migration first.
