# The Canonical Scheduler Table — every required job, enumerated (2026-08-29, P0-1 closure)

**Premise corrected corpus-wide:** no shared 2-minute heartbeat exists (red-team `P0-1`). **Mechanism:
per-job `cron.schedule` entries created BY THE OWNING PACKAGE** — the written default; the alternative
(one dispatcher function) is filed engineering and adds no capability. **No owner bit: the mechanism is
derivable** — per-job entries are what production already does (`014`'s two jobs), need no new function,
and each package's rollback drops its own jobs. Nothing here is implementation — this is the obligations
register the packages build against.

| JOB | FUNCTION | PKG | CADENCE | MECHANISM | IDEMPOTENCY KEY | LOCKING / CONCURRENCY | TEST WITNESS |
|---|---|---|---|---|---|---|---|
| invite expiry | `kernel.sweep_expired_org_invites` | 077 | 2 min | `cron.schedule` in 077 | re-entrant (status predicate) | `FOR UPDATE SKIP LOCKED`, per-row txn | `T-RPC-ORG-06` |
| atom expiry | `kernel.sweep_expired_ticket_atoms` | 079 | 2 min | `cron.schedule` in 079 | re-entrant | terminal-states-untouched; batch `p_limit` | `T-SCHEMA-EXPIRY-01` |
| inventory-hold expiry | `venue.sweep_expired_inventory_holds` | 081 | 2 min | `cron.schedule` in 081 | re-entrant | `SKIP LOCKED`; poison-quarantine per row | §20.3.3's tests |
| wallet pass lifecycle | `kernel.sweep_wallet_pass_lifecycle` | 083 | 15 min | `cron.schedule` in 083 | re-entrant | per-pass; supersede idempotent | WALLET §12 set |
| refund-request expiry | `kernel.sweep_expired_refund_requests` | 085 | 2 min | `cron.schedule` in 085 *(row added 2026-08-29 — it had NONE)* | re-entrant | releases `refund_hold` overlays; `SKIP LOCKED` | plan 085 Tests ("asserted, because a hold with no sweep is a bricked ticket") |
| door-session expiry | `venue.sweep_expired_door_sessions` | 086 | 2 min | `cron.schedule` in 086 | re-entrant | one-way `active → expired` | `AUTHZ-H3` family |
| door-override expiry | `kernel.sweep_expired_door_overrides` | 086 | 2 min | `cron.schedule` in 086 | re-entrant | closes its own audit pair | §17.11's tests |
| implicit door freezes | `catalog.sweep_implicit_door_freezes` | 086 | 2 min | `cron.schedule` in 086 | re-entrant | ledger-head trigger guards | `G-21` tests |
| holder-mix refresh | `venue.refresh_holder_mix` | 086 | nightly | `cron.schedule` in 086 | snapshot-versioned | R2/R4 suppression rules | DEMOG §13 set |
| holder-mix reconcile | `venue.reconcile_holder_mix` | 086 | nightly | `cron.schedule` in 086 | read-only (asserts+alarms) | none | its §17.20 contract |
| export expiry | `venue.sweep_expired_exports` | 087 | hourly | `cron.schedule` in 087 (exists) | terminal-guarded | claim lease | CRM set |
| export build tick | `crm-export-worker POST /build` | 087 | 1 min | `cron.schedule`+`pg_net` (exists) | claim lease | `purge_lease_until` | CRM set |
| export purge tick | `crm-export-worker POST /purge` | 087 | 15 min | `cron.schedule`+`pg_net` (exists) | claim lease + attempts | lease | CRM set |
| p2p expiry + offer tick | `market.sweep_expired_p2p_transfers` (2nd stmt: `market.offer`) | 088 | 2 min | `cron.schedule` in 088 (row corrected) | re-entrant | per-row Transfer→Atom `FOR UPDATE` | `T-SCHEMA-OFFER-01` (tick DISABLED) |
| C25 compensation | `market.sweep_paid_pending_sales` | 088 | 2 min | `cron.schedule` in 088 | XOR terminal-state | compensate-XOR-complete | §12.3 tests |
| outbox drain | `notify.drain_outbox` | 092 | 2 min | `cron.schedule` in 092 | `UNIQUE(dedupe_key)` + envelope state | `pg_try_advisory_xact_lock` + `SKIP LOCKED`; bounded expansion | N-A7 family |
| notify dispatch | `notify-dispatch` edge | 092 | 1 min | `cron.schedule`+`pg_net` in 092 | delivery claim lease | `claim_deliveries` lease | §17.25 set |
| notify receipts | `notify-receipts` edge | 092 | 15 min | `cron.schedule`+`pg_net` in 092 | terminal-state guard | lease | §17.25 set |

**Live production jobs (unchanged, outside the band):** `auto_finalize_expired_auctions` (2 min — the
LEGACY auction engine, untouched by `OR-11`) · `enforce-transfer-expiry` http_post (2 min) · the `014`
schedule file is their home. **Every "rides the existing heartbeat" phrase in the corpus is corrected;
none remains load-bearing.**
