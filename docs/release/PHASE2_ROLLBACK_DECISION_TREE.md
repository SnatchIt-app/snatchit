# PHASE-2 ROLLBACK DECISION TREE (production; companion to the runbook)

**Prime rule:** rollback is legal only while CLEAN-WHILE-EMPTY holds. Every rollback
file's guard enforces it (counts under `set local row_security = off`, tables locked,
refusal with the row count — battery-proven 2026-09-02, 17/17 identity-0). Once a live
Phase-2 fact exists, the guard REFUSES and the only path is FORWARD. Never bypass a
guard refusal; a refusal is the system telling you rollback would destroy a fact.

**Runner:** the `postgres` role (owner/BYPASSRLS), one operator, one terminal. Run
by any lesser role the guards now fail CLOSED (RLS error), never open.

## Failure classes → action

| # | Failure | Action |
|---|---|---|
| 1 | A migration file errors MID-APPLY (chain stops at file N) | The failed file rolled back atomically; files < N are applied. DO NOT immediately re-push. Diagnose from the psql error. If environmental (lock timeout, transient): re-run `db push --include-all` (idempotent — CLI resumes at N). If the file itself misbehaves against production state (should be impossible after the rehearsal): STOP, run rollbacks N-1 → 076 in reverse order, restore the 075 world, take the finding to the owner. |
| 2 | Post-apply verify FAILS (any V-row) on census/posture (V2–V9, V13–V16) | Do not proceed to edge deploy. Compare against the rehearsal DB. A census mismatch means production held something the preflight missed → run rollbacks 092 → 076 in reverse (all guards will pass — nothing live yet), restore, re-derive. |
| 3 | Post-apply verify V10 fails (a business row exists immediately after apply) | STOP EVERYTHING. That row's provenance is unexplained. Read it (read-only), identify the writer, owner call before any further step. Do not roll back (the guard will refuse anyway — correctly). |
| 4 | Cron job failing repeatedly (`cron.job_run_details.status='failed'`) | Do NOT roll back the DB. `select cron.unschedule('<jobname>')` for THAT job only; file the defect; re-schedule after the fix. The 16 new jobs are sweeps over empty tables — a failure is a defect, not data damage. |
| 5 | Edge deploy of the cutover misbehaves (delete-account 5xx) | Undeploy IS the wrong move (it would restore the physical-delete body — a compliance regression). Instead: fix forward on the edge. If unfixable same-day: re-deploy the PREVIOUS delete-account version explicitly as an owner-acknowledged temporary compliance regression, and record it. The DB stays applied either way. |
| 6 | F-5 guard misfires (false 403 on purchases) | The guards fail OPEN on probe errors by design, so a false 403 means `is_deletion_pending`/`identity_ext` returned true wrongly — read the row. If wrong data: owner call. If a guard bug: redeploy the affected edge with the guard short-circuited (one-line env toggle is NOT built — edit + deploy), never touch the DB. |
| 7 | Old mobile build broken by the apply | Should be impossible (grant parity + zero public contract changes — the only public delta is 4 nullable push_tokens columns + 1 admin function). If observed anyway: capture the failing call from Sentry, verify against the rehearsal DB, treat as class 2. |
| 8 | Deletion requests flowing but sweep misbehaving (wrong blocker, no terminal) | FORWARD ONLY (facts exist). The sweep is `kernel.sweep_deletion_pending` — body-only fixes ride a new migration; requests are safe while pending (nothing is deleted). |
| 9 | Anything money-anomalous on the LEGACY rail post-apply | The apply doesn't touch legacy money paths; treat as an ordinary production incident (065/064 tooling), not a Phase-2 rollback trigger. |
| 10 | Owner says stop | Freeze where you are; the dark substrate is inert (flags false, notify claim fail-closed, no client exposure beyond kernel). A half-deployed train can rest safely at any point AFTER the DB apply and BEFORE flag flips. |

## Reverse-order rollback procedure (classes 1/2 only, nothing live)
```bash
for n in 092 091 090 089 088 087 086 085 084 083 082 081 080 079 078 077 076; do
  psql "$PROD_DB_URL" -v ON_ERROR_STOP=1 -f supabase/rollbacks/${n}_*_rollback.sql || break
done
# then delete the 17 ledger rows the CLI wrote (the rollbacks do not touch the ledger):
psql "$PROD_DB_URL" -c "delete from supabase_migrations.schema_migrations where version ~ '^0(7[6-9]|8[0-9]|9[0-2])$'"
```
Any guard refusal mid-sequence = a live fact exists = STOP, forward-only from there.

## What rollback NEVER does
- Never drops a table holding a row (guards).
- Never touches `public.*` data (092's rollback drops only the 4 added columns —
  legal only while every row's `revoked_at` is NULL, which its guard checks).
- The 078 rollback DOES remove the two sentinel identities it seeded (f0/f1) — but
  only after its guard proves no custody row ever named them; 019's zero-uuid
  sentinel is never touched.
- Never un-deploys edges by itself (edges are versioned separately; see class 5).
