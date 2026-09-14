# PFA-18C — MIGRATION 125 (086↔112/113 SCANNING-CONTRACT CORRECTION) — REVIEW PACKAGE rev 1 (NOT APPLIED · LOCAL REHEARSAL ONLY)

**Date:** 2026-09-14 · **Author:** Claude B · **Owner instruction:** prepare the 086↔112/113 scanning-contract correction (formerly "migration 122", reassigned to **125** with pgTAP **190**), confirm the registry with Claude A first, inspect the current implementation, rehearse locally on a fresh replay (never the shared sandbox or production), reconcile documents still naming 122 with dated corrections, coordinate integration with A. **No signing, Model A, flag, AWS, secret, deployment or production write** — none performed.
**Registry confirmation:** `docs/release/MIGRATION_NUMBER_REGISTRY.md` (A, branch `fix/122-transfers-profiles-fk` @ `26b8e2e`) assigns `~~122~~ → 125`, pgTAP 190, owner Claude B, reassigned 2026-09-12 on the owner's sequencing approval; Claude A acknowledged by session message 2026-09-14 (numbers, branch, merge order 121 → 123 → 124 → 125; A holds 126/193, 127/194, 128/195). Migration 121 / test 189 (PR #58) are **not** renumbered.
**Production state (read-only, 2026-09-14):** `venue.sync_scan_device_manifest` definition md5 `666422e5fe0c7e96c267ad259d7ef50a` = the 086 text verbatim, no comment, grants authenticated EXECUTE only; ledger 135, numeric tip 120; scanning flag false; native data 0.

## 1. The drift, from the sources
- **086:1040-1068** selects the device's episode with `status = 'open'` only, binds `venue.scan_device` (`manifest_id`, `manifest_version`, `last_sync_at`) to it, then returns `venue.get_door_manifest(p_session_id, 0)`.
- **112** (and 113's shared core `venue._get_door_manifest_core`) re-defined the M2 read on the door §7.5 precondition `status = 'open' AND not_after > now()`: an episode past its **stored** `not_after` is reported `open:false` with no header and no entries; the row is never written (086 immutability guard forbids changing `not_after`).
- Consequence: for an expired-but-still-'open' episode, one call wrote a device binding ("holds manifest vN, synced now") and returned a payload saying no open episode. Readers of the device binding (device-liveness projections, VD §12.3 / RN §10.2 counts) would count the device as synced to an episode the door plane refuses. A second, smaller window: the bind and the return were two reads inside a VOLATILE function, so an episode closed between them produced a bound row plus a no-episode payload.
- Reachability today: **no client or edge calls the function** (the door path is `venue.get_door_manifest_door` via `door-session /manifest/sync`; `venue` is not a PostgREST-exposed schema; `door-manifest` uses `get_door_manifest`); native scanning is dark. The correction is a contract-consistency fix required **before the scanning flip**, not a live incident.

## 2. The correction (branch `fix/125-scan-device-sync-expired-episode`, cut from `admin/operating-console @ 562fda9`)
| Item | Value |
|---|---|
| Migration | `supabase/migrations/125_sync_scan_device_manifest_open_unexpired.sql` — body-only `create or replace`; the function calls `venue.get_door_manifest(p_session_id, 0)` **first** and binds the device only when the payload reports `open:true`, to exactly the `manifest_id`/`manifest_version` returned; otherwise the device row is untouched and the payload (`open:false`) is returned. Signature `(uuid,uuid,integer)`, VOLATILE, SECURITY DEFINER, `search_path=''`, grants and authorization unchanged (device-venue `venue_scanner`/`venue_manager` gate, then the session-venue gate inside `get_door_manifest`, which 086 also evaluated). Adds a function comment. Census 0. Post-apply md5 **`6beca3168e76bb566e456b6abd467197`** |
| Rollback | `supabase/rollbacks/125_…_rollback.sql` — restores the 086 body verbatim and nulls the comment; md5 returns to `666422e5…` (verified) |
| Test | `supabase/tests/190_sync_scan_device_manifest_open_unexpired.sql` — **30 assertions**: A definition (one contract read; bind-from-payload; 086 select gone; comment), B shape/grants, C contract (fresh device unbound → open v1 bound to exactly the returned manifest → closed: untouched → **expired-but-open v2: `open:false`, device still m1/1, `last_sync_at` untouched, row untouched, no header** → fresh v3 re-bound → repeat idempotent), D authorization (buyer 42501, unknown device P0002, manager ok), E census |
| Commit / PR | `fc4f1130dbbb7b926d87daa8c585e12ab521f6ba` · draft PR **#62** into `admin/operating-console` (review-only, not for apply) |

**Behaviour corrected, exactly:** expired-but-still-open episode → device row untouched and `open:false` (086: bound m/N with `last_sync_at = now()` while returning `open:false`). Open-unexpired and closed/absent cases return the same results as 086, the open case now consistent by construction (single read). Nothing writes `door_manifest`; no audit row (RPC §20.4.4).

**Explicitly out of scope (recorded in the migration header):** RPC §20.4.4 conformance beyond what 086 implemented — `p_device_boot_id`, `device_wrong_venue` precondition, `up_to_date` cursor-only result, monotonic `manifest_version`, service_role door path. Signature/result-shape changes with edge and scanner consumers; separate migration if wanted.

## 3. Local rehearsal (REHEARSAL; fresh replay DBs on `127.0.0.1:5432`; shared sandbox and production untouched)
| Step | Result |
|---|---|
| Fresh replay of the branch chain (`scripts/rehearsal_reset.sh snatchit_rehears_125_base`) | 136/136 applied; Gate-2 27/71/37/27 = CI baseline |
| Rollback round-trip on that DB | 125 `6beca316…` → rollback `666422e5…` (comment null, venue fns 87) → 125 `6beca316…`; second apply idempotent |
| pgTAP 190 + door suites 150/174/178/179 | 196/196 ALL-PASS |
| Full pgTAP suite (base DB with 125) | 4346/4350 — the 4 failures are the four documented local-only deltas (060 ×2, 132 ×2); "matches the expected local baseline" |
| **Combined-order replay** (scratch detached checkout at 562fda9 with 121 from PR #58, 123/124 from A's branch and 125 overlaid, uncommitted) `snatchit_rehears_121_125` | 139/139 applied; `LC_ALL=C` order `120 → 121 → 123 → 124 → 125 → 20260714…` (no timestamped row reorders around them); Gate-2 unchanged; suites 150/174/178/179/180/189/190/191/192 = **283/283**; md5s 125 `6beca316…`, 121 `333372bb…` |
Limitation: the harness is the Docker-less replica (fidelity ledger in `scripts/rehearsal_bootstrap.sql`); CI's real-stack replay runs on the PR.

## 4. Application / recovery plan (NOT authorized by this document)
1. **Sequencing:** merge after 121 (#58), 123 and 124 per the owner-approved order; the migrations guard (§4, scheme-aware strictly-increasing on added migrations) is satisfied by 125 > 124 (and > 120 against the current base).
2. **Phrase:** the remaining-path §1.6 phrase reads "AUTHORIZE PFA-18C MIGRATION 122"; whether it is re-issued as **"AUTHORIZE PFA-18C MIGRATION 125"** is the owner's decision (A's note, 2026-09-14). Nothing applies until it is issued.
3. **Day-of discipline (C4 precedent):** `AUTODEPLOY-VERIFIED-OFF: <date>` added to the PR body; `git_branch` empty; `supabase db push --include-all --dry-run` must list **exactly** `125_…` (plus whatever the owner has sequenced ahead of it, each listed by name); owner runs the apply on Mac 1; coordinator reads back.
4. **Read-backs:** definition md5 `6beca3168e76bb566e456b6abd467197`; comment present (`125: the device is bound…`); grants authenticated true / service_role false / anon false; venue function count unchanged (87 at tip 120); ledger +1; `feature.native_scanning_enabled` still false; native counts still 0; monitor `ok/match`; suites 190 + 178/179 green in CI; Mac 2 Dashboard read-back of the md5 and grants.
5. **Recovery:** production is forward-only; `supabase/rollbacks/125_…_rollback.sql` restores the 086 body and needs its own authorization; it re-introduces the drift and must not be run once the scanning flag is true. Any later migration re-creating this function must be rolled back first (none exists).
6. **Dependencies:** not required before C6 (done), Model A, M5 or the issuance flip; **required before the scanning flip** (C8 second step) together with scanner SDK readiness. Does not touch KMS, secrets, flags, the trust root or the monitor.

## 5. Deliverable
- Branch `fix/125-scan-device-sync-expired-episode` (origin) @ `fc4f1130dbbb7b926d87daa8c585e12ab521f6ba`; draft PR **#62** into `admin/operating-console` (review-only, not for apply; the AUTODEPLOY attestation is a placeholder until the day of apply).
- Documents reconciled with dated corrections (history preserved): `PHASE2_PFA18C_FINAL_COORDINATOR_HANDOFF.md` (G6 and the open-items row), `PHASE2_PFA18C_REMAINING_PATH_AND_HANDOFF.md` and `PHASE2_PFA18C_C6_EXECUTION_RECORD.md` (A's dated numbering notes, fast-forwarded onto this branch), this package.
- The remaining launch gates (Model A, M5 ruling / M5-live, C8 flips, live commerce checks) stay documented in `PHASE2_PFA18C_FINAL_COORDINATOR_HANDOFF.md` §3 and are **not** part of this development deliverable.
