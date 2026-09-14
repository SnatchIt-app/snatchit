# Venue slice 1 — acceptance kit

Automated acceptance for the `venue_api` read slice. Usage, phases, guards and the window procedure:
[`docs/venue-dashboard/HOSTED_ACCEPTANCE_RUNBOOK.md`](../../../docs/venue-dashboard/HOSTED_ACCEPTANCE_RUNBOOK.md).

- `accept.mjs` — phase runner (`--target local|sandbox`, `--phase …`); production ref refused; sandbox writes need `--window` + `VENUE_ACCEPT_WINDOW`.
- `lib/target.mjs` — SQL/Auth adapters (psql + harness locally; `supabase db query` + Auth admin API on the sandbox).
- `lib/cdp.mjs` — dependency-free headless Chrome client (isolated contexts per user).
- `sql/` — read-only preflight and verify queries; fixture template and cleanup (fixed `5a4d0b0e-` ids).
- `ledger-row.py` — ledger row with the real statement array for a migration file.
- `.runs/` — per-target baseline, synthetic-user state (0600) and evidence; gitignored.
