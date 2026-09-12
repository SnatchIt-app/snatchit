# PFA-18C — C3 TRUST-ROOT DB COMMIT — **FINAL HANDOFF (rev 3)** — FOR OWNER DECISION · **NOT AUTHORIZED · NOTHING EXECUTED**

**Date:** 2026-09-10 · **Coordinator:** Claude B · **State:** C2 COMPLETE (`PHASE2_PFA18C_C2_EXECUTION_RECORD.md`); C4 live (guard 110 enforcing); `kernel.signing_key` **0 rows**; flags false.
**C3 requires the separate exact owner phrase `AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT`.** This document is not that authorization. C18: the owner runs the one `psql` invocation on the primary (Mac 1); the coordinator reads back only (read-only MCP); Device 2 (Mac 2) reads back independently (§5). C3 does not approach T3.
**Revision history:** rev 1 (2026-09-10, draft) → rev 2 (owner review items 1–5: uncertain outcome, Device-2 path, probe separation, invocation, records) → **rev 3 (this): connection verification, named ceremony backend, definition review of `revoke_signing_key`, pinned Mac-2 SQL, final invocation, probe scripts with explicit rollback/exit handling.** Rev-1 error preserved as a dated correction: "commit `66f5de60…`" was the blob id; the commit is `1f3fc19d…`.

Evidence classes: **CLAUDE-OBSERVED**, **OWNER-RETURNED**, **OFFICIAL-DOC**, **DEFINITION-REVIEW** (read-only reading of live function source; not a live refusal test).

---

## 1. Exact C3 mutation scope

| Item | Value |
|---|---|
| Artifact | fenced `sql` block "§6.1 The artifact" of `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` at commit **`1f3fc19d295e101fb680393e4bd99db8b2f2cc5f`** (blob `66f5de60…`) → `signing_key_bootstrap.sql`, **118 lines, SHA-256 `380f434d07d85c1f5a7a92ad376da3843becc9019f01c4f20580d67a66eba7f6`**; run verbatim (flags only, §6) |
| The write | **one `INSERT` of one row into `kernel.signing_key`** inside the artifact's single transaction: `key_id 00000000-0000-0000-0000-0000000000b0`, `scope global`, `event_id null`, `venue_id null`, `public_key` = Device 2's `pub.pem`, `kms_handle_ref` = D4 `arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e`, `algorithm ES256`, `status active`, `not_before now()`, `not_after null` (D6) |
| Gates in the same transaction | artifact PRE-FLIGHT 1/2/2b/3 + POST-CHECK; guard 110 rules 1–11 (mapping unchanged from rev 2 §3); any refusal aborts everything |
| Also attempted (§8B) | three classes of **write-attempt probes** expected to be refused, each inside `begin…rollback`: the immutability UPDATE (7.5) and the five parked lifecycle calls (7.3). **No live `revoke_signing_key` call** (deviation for acknowledgement, §4) |
| Expected D5 | `562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415` |
| Not authorized | C5, C6, any edge/secret/flag/credential, a second row, any AWS change, any re-run (§7), rollback (§9, own phrase) |

## 2. Connection verification (owner item 1) — project match, mode, pass/fail only

CLAUDE-OBSERVED (local inspection, sanitized; no URL/password printed):

| Source | Linked project ref | URL user contains ref | Host is pooler | Port | Mode | Password embedded | Result |
|---|---|---|---|---|---|---|---|
| `snatchit-admin-console/supabase/.temp` | `hqycwntpfoztoinemqns` | true | true | 5432 | **session** | no | **PASS** |
| `snatchit-consol/supabase/.temp` | `hqycwntpfoztoinemqns` | true | true | 5432 | **session** | no | **PASS** |

Project identity (read-only Management API): **"Snatch It"**, ref `hqycwntpfoztoinemqns`, org `zcxpqolueooqkslolfrt`, region **us-west-2** (matches the session-pooler host `aws-0-us-west-2.pooler.supabase.com`), Postgres **17.6**, `ACTIVE_HEALTHY`, direct host `db.hqycwntpfoztoinemqns.supabase.co`.

**Owner-side check of the actual `$PROD_DB_URL` the ceremony will use** (prints only three tokens; run on Mac 1 right before §6):
```bash
python3 - <<'EOF'
import os, urllib.parse as up
p = up.urlsplit(os.environ['PROD_DB_URL']); host, port, user = (p.hostname or ''), (p.port or 0), (p.username or '')
ref = 'hqycwntpfoztoinemqns'
mode = 'session' if port == 5432 and 'pooler' in host else ('transaction' if port == 6543 else ('direct' if host.startswith('db.') and port == 5432 else 'unknown'))
match = (ref in user) or host.startswith('db.' + ref + '.')
print(f"project_match={match} mode={mode} " + ("PASS" if match and mode in ('session', 'direct') else "FAIL"))
EOF
```
Accepted: `mode=session` (pooler :5432) or `mode=direct` (`db.<ref>…:5432`). `transaction` (:6543) is **FAIL** (temp table + advisory lock + multi-statement transaction need one server session).

## 3. Named ceremony connection and backend identity (owner item 2)

- The ceremony `psql` runs with **`PGAPPNAME=pfa18c-c3-bootstrap-<UTC stamp>`** (exported for that command only; the reviewed SQL is untouched).
- The invocation's first statement, in the **same connection** before the artifact, is `-c "select pg_backend_pid() … current_setting('application_name') …"`; its output is the first line of `c3_output.txt` and is the **recorded backend identity** (server backend pid + application_name + start time). `pg_backend_pid()` is evaluated on the server, so the pid is the real backend even through the session pooler.
- Outcome handling (§7) identifies **that pid and that application_name only**. No ownership is inferred from other `pg_stat_activity` rows; no unidentified backend is ever terminated.

## 4. `kernel.revoke_signing_key` — DEFINITION-REVIEW EVIDENCE (read-only; **not** a live refusal test)

Source read from production 2026-09-10 (`pg_get_functiondef`, `SECURITY DEFINER`, `search_path ''`). Control flow in order; **the first write is step 10** — every authorization gate precedes it:

| # | Statement | Effect |
|---|---|---|
| 1 | `v_uid := auth.uid(); if v_uid is null → raise 'insufficient_privilege: authenticated actor required' (42501)` | refuses any session without a JWT subject (the owner's `psql` as `postgres` has none) |
| 2 | `if not kernel.is_platform(array['platform_admin']) → raise 'insufficient_privilege: platform_admin only …'` | platform_admin enforced |
| 3 | `v_aal := request.jwt.claims ->> 'aal'; if null → raise 'step_up_unavailable …'` | absent claim is never treated as satisfied |
| 4 | `if v_aal <> 'aal2' → raise 'step_up_required …'` | aal2 enforced |
| 5 | reason_code / command_key charset validation | input gates |
| 6 | `select … for update` on the key; `not_found` if absent | row lock (no write) |
| 7 | if already `revoked` → return `noop_replay` | terminal-state idempotency, no write |
| 8 | lock in-scope `catalog.event_session` rows `for update` | locks (no write) |
| 9 | live-credential acknowledgement check (`precondition_failed` on mismatch) | gate |
| **10** | **`update kernel.signing_key set status='revoked', updated_at=now()`** | **first write — terminal** |
| 11–12 | `insert into kernel.admin_audit …`; `kernel.force_close_key_manifests(...)` cascade | further writes |

Conclusion (definition review): platform_admin (2) and aal2 (3–4) are enforced before any write; a `postgres` psql session with no JWT exits at (1). **Proposed deviation for acknowledgement:** the live call from ceremony §7.3 / runbook §A line 67 is **omitted** in production because a session that satisfied (1)–(4) would execute a terminal revoke (and guard rule 10 would then park recovery). The five parked functions (`provision_signing_key`, `rotate_signing_key`, `provision_pass_type_cert`, `rotate_pass_type_cert`, `revoke_pass_type_cert`) were read in full: each body is a single `raise exception 'precondition_failed: dual_control_unavailable …'` — no write is reachable; their live probes (§8B) cannot write and are still wrapped in `begin…rollback`.

## 5. Device 2 (Mac 2) — Option A: independent Supabase Dashboard login with MFA

**Limitation retained:** the Dashboard SQL editor executes as the **`postgres` role (privileged)**. Read-only is enforced **by procedure only**: Mac 2 runs exactly the pinned SELECTs below, nothing else — no DDL/DML, no saved queries, no other tabs' queries; sign out when done. **Never on Mac 2:** `$PROD_DB_URL`, the DB password, service-role/secret keys, a PAT, or a copied Mac-1 session. The ceremony's "do not use the SQL editor" rule applies to the INSERT (variables/history), not to these secret-free SELECTs.

**Access confirmation (do now, pre-C3):**
1. On Mac 2, open `https://supabase.com/dashboard` in the browser; sign in with the owner's Supabase account (owner of org `zcxpqolueooqkslolfrt`); complete the Supabase account MFA challenge.
2. Open project **"Snatch It"** (ref `hqycwntpfoztoinemqns`, us-west-2) → **SQL Editor** → new query.
3. Run **A0** and report its five values (no secrets in them):
```sql
-- A0 access confirmation (pre-C3 expected: postgres | postgres | <now> | 0 | 135)
select current_user, current_database(), now() as at,
       (select count(*) from kernel.signing_key) as signing_keys,
       (select count(*) from supabase_migrations.schema_migrations) as ledger;
```
Coordinator corroboration: the Dashboard's query passes through the platform API and is visible in Supabase logs; the coordinator checks (read-only `query_logs`) for the A0 execution around the reported time.

**Pinned post-C3 read-only SQL for Mac 2** (each expected value stated; the handle is never printed):
```sql
-- A1 = ceremony §7.1 — expect ONE line: …b0 | scope=global | status=active | not_before=<ts> | not_after=null | fingerprint=562b5e87…4415
select key_id || ' | scope=' || scope || ' | status=' || status || ' | not_before=' || not_before
    || ' | not_after=' || coalesce(not_after::text,'null')
    || ' | fingerprint=' || encode(sha256(decode(regexp_replace(public_key,'-----(BEGIN|END) PUBLIC KEY-----|[[:space:]]','','g'),'base64')),'hex')
  from kernel.signing_key;
-- A2 = §7.2 resolver global arm — expect: 00000000-0000-0000-0000-0000000000b0 | global
select k.key_id, k.scope from kernel.signing_key k
 where k.status='active' and (k.not_after is null or k.not_after > now()) and k.not_before <= now() and k.scope in ('global')
 order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end limit 1;
-- A3 = §7.4 — expect: 1|1|0|0
select count(*) || '|' || count(*) filter (where scope='global' and status='active') || '|' || count(*) filter (where scope='per_event') || '|' || count(*) filter (where scope='per_venue') from kernel.signing_key;
-- A4 exact-row check — expect: n=1, exact_row=true
select count(*) as n, bool_and(key_id='00000000-0000-0000-0000-0000000000b0' and scope='global' and status='active' and algorithm='ES256' and not_after is null and not_before <= now()
   and kms_handle_ref='arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e'
   and encode(sha256(decode(regexp_replace(public_key,'-----(BEGIN|END) PUBLIC KEY-----|[[:space:]]','','g'),'base64')),'hex')='562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415') as exact_row
  from kernel.signing_key;
-- A5 manifest signing context (stable function; returns the public ARN) — expect status ok, key_id …b0, algorithm ES256, key_status active, not_after null
select venue.get_manifest_signing_context();
-- A6 darkness + references — expect: false,false,false | 0 | 0 | 0
select (select jsonb_object_agg(key, value) from catalog.platform_config where key in ('feature.native_issuance_enabled','feature.native_scanning_enabled','signing.monitor_enabled')) as flags,
       (select count(*) from kernel.tickets) as tickets, (select count(*) from kernel.wallet_pass) as wallet_passes, (select count(*) from venue.door_manifest_entry) as manifest_entries;
-- A7 door RPC grants — expect service_role only for the three machine RPCs
select p.proname, array_agg(distinct a.grantee::text order by a.grantee::text) as grantees
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  left join information_schema.routine_privileges a on a.specific_schema=n.nspname and a.routine_name=p.proname and a.grantee in ('anon','authenticated','service_role')
 where n.nspname='venue' and p.proname in ('get_signing_keys_door','get_door_manifest_door','get_manifest_signing_context') group by 1 order by 1;
```

## 6. Final primary (Mac 1) invocation — OWNER; SQL unmodified; flags explained in rev 2

```bash
# 0 — connection check (prints only project_match / mode / PASS)  → must be PASS (§2)
# 1 — stage the artifact from the pinned commit; verify hash and length
mkdir -p "$CEREMONY_DIR" && cd "$CEREMONY_DIR"
git -C /Users/josetascon/snatchit-consol show 1f3fc19d295e101fb680393e4bd99db8b2f2cc5f:docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md \
  | awk '/^### 6.1 The artifact/{f=1} /^### 6.2 Running it/{f=0} f' | awk '/^```sql/{f=1;next} /^```/{f=0} f' > signing_key_bootstrap.sql
shasum -a 256 signing_key_bootstrap.sql   # 380f434d07d85c1f5a7a92ad376da3843becc9019f01c4f20580d67a66eba7f6
wc -l < signing_key_bootstrap.sql         # 118
# 2 — inputs as files (pub.pem / pub.der = Device 2's export copied to Mac 1)
printf '%s' 'arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e' > handle.txt
openssl dgst -sha256 -hex pub.der | awk '{print $2}' > fingerprint.txt; cat fingerprint.txt   # 562b5e87…4415
# 3 — named connection + the one mutation (single transaction inside the file); backend identity recorded first
export PGAPPNAME="pfa18c-c3-bootstrap-$(date -u +%Y%m%dT%H%M%SZ)"; echo "$PGAPPNAME"
psql -X -v ON_ERROR_STOP=1 "$PROD_DB_URL" \
  -c "select pg_backend_pid() as backend_pid, current_setting('application_name') as app, now() as started_at" \
  -v PUBLIC_KEY_PEM="$(cat pub.pem)" -v KMS_HANDLE_REF="$(cat handle.txt)" -v EXPECTED_FINGERPRINT="$(cat fingerprint.txt)" -v ALGORITHM="ES256" \
  -f signing_key_bootstrap.sql 2>&1 | tee c3_output.txt; echo "psql_exit=${pipestatus[1]}"
unset PGAPPNAME
```
`-c` then `-f` execute in order on one connection (no `-1`, so the artifact's own `begin;`/`commit;` are the only transaction boundaries). **Required output:** the backend-identity line, then the four NOTICEs, `COMMIT`, `psql_exit=0`.

## 7. Outcome determination (identified backend only)

| Observed | Class | Action |
|---|---|---|
| four NOTICEs + `COMMIT` + `psql_exit=0` | committed | §8 |
| `ERROR:` + no `COMMIT` + `psql_exit=3` | rolled back (psql exited; server aborted the open transaction) | confirm §7.1 `n=0`; report the error; no re-run without review |
| no `COMMIT`, exit ≠ 0/3, reset, hang, lost output | **UNCERTAIN** | §7.1 then §7.2; **never re-run automatically** |

**7.1 exact-row read** (coordinator via read-only MCP; owner via `psql -X -tAc`; Mac 2 via A4): `n=1, exact_row=true` → committed (only the acknowledgement was lost) → §8, no re-run. `n=0` → run 7.2 before any decision. `n=1, exact_row=false` or `n>1` → **STOP**, do not delete, report.
**7.2 the ceremony backend only** (use the pid and app recorded in `c3_output.txt` line 1):
```sql
select pid, application_name, state, xact_start, backend_start, backend_xid is not null as holds_xid
  from pg_stat_activity where pid = <recorded backend_pid> and application_name = '<recorded app>';
```
Absent → the backend is gone; with `n=0` its transaction never committed → state settled as "not written"; a re-run is a **new owner decision** (PRE-FLIGHT 1 makes a duplicate abort harmlessly). Present with `idle in transaction`/`active` → its transaction may be in flight: wait for the client to time out, or the owner decides to `select pg_terminate_backend(<recorded backend_pid>)` — **that pid only**; never any other row; nothing is inferred from other sessions.

## 8. Post-commit verification

**8A read-only** — coordinator (read-only MCP) runs A1–A7 (§5); owner may run the same via `psql -X -tAc`; Mac 2 runs A1–A7 in the Dashboard. Plus CloudTrail: no AWS event from C3; `Sign` count unchanged (1 success + 2 denied).
**8B write-attempt probes — OWNER on Mac 1 only** (`postgres` via `psql -X`; the session must not set `session_replication_role` or disable triggers). Each script turns `ON_ERROR_STOP` **off** so the expected `ERROR` does not abort the script, wraps the attempt in `begin … rollback`, re-reads the row afterwards, and the shell decides PASS/STOP from the captured output:
```bash
export PGAPPNAME=pfa18c-c3-probe
# P-7.5 immutability guard (tg_signing_key_immutable) — expected: ERROR append_only …, then fingerprint unchanged
psql -X "$PROD_DB_URL" 2>&1 <<'SQL' | tee probe_7_5.txt
\set ON_ERROR_STOP off
begin;
update kernel.signing_key set public_key = public_key || 'X' where key_id = '00000000-0000-0000-0000-0000000000b0';
rollback;
select encode(sha256(decode(regexp_replace(public_key,'-----(BEGIN|END) PUBLIC KEY-----|[[:space:]]','','g'),'base64')),'hex') as fingerprint_after from kernel.signing_key;
SQL
[ "$(grep -c 'append_only' probe_7_5.txt)" -ge 1 ] && grep -q '562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415' probe_7_5.txt && echo PROBE-7.5-PASS || echo PROBE-7.5-FAIL-STOP
# P-7.3 the five parked lifecycle functions — expected: five × dual_control_unavailable
psql -X "$PROD_DB_URL" 2>&1 <<'SQL' | tee probe_7_3.txt
\set ON_ERROR_STOP off
begin; select kernel.provision_signing_key('global',null,'-','-',now(),'p','p'); rollback;
begin; select kernel.rotate_signing_key('00000000-0000-0000-0000-0000000000b0','-','-','p','p'); rollback;
begin; select kernel.provision_pass_type_cert('-','-','-','-','-',now(),now()+interval '1 day','p','p'); rollback;
begin; select kernel.rotate_pass_type_cert('00000000-0000-0000-0000-000000000000','-','-','-',now(),now()+interval '1 day','p','p'); rollback;
begin; select kernel.revoke_pass_type_cert('00000000-0000-0000-0000-000000000000','p','p'); rollback;
select count(*) as rows_after, count(*) filter (where status='active') as active_after from kernel.signing_key;
SQL
[ "$(grep -c 'dual_control_unavailable' probe_7_3.txt)" -eq 5 ] && grep -Eq '^\s*1\s*\|\s*1\s*$|1 \| 1' probe_7_3.txt && echo PROBE-7.3-PASS || echo PROBE-7.3-FAIL-STOP
unset PGAPPNAME
```
Containment: the `rollback` runs whether or not the statement errored, so an unexpected success is discarded; a dropped connection mid-probe is rolled back by the server. `FAIL-STOP` = finding F-C3-1 (immutability guard not effective) or F-C3-2 (a parked function did not refuse): stop before C5, report; the row itself is unchanged by construction. Each probe is recorded in the ledger as a production write attempt (refused, rolled back).

## 9. Rollback (own phrase `AUTHORIZE PFA-18C C3 ROLLBACK`) — limits unchanged from rev 2
Ceremony §10 script; available only while `kernel.tickets` / `kernel.wallet_pass` / `venue.door_manifest_entry` / `venue.door_manifest_delta` hold no reference to `…b0` (all 0 today) — i.e. until the first credential mint; disarm C5 first if armed; does not touch AWS; after rollback the `…b0` lineage may be re-bootstrapped only under a fresh authorization.

## 10. Owner decisions before authorization
1. **Option A** for Mac 2 (Dashboard + Supabase MFA; privileged session, read-only by procedure) — confirm, and report A0.
2. **Acknowledge V-1** (historical verification gap: Device 2 verified the final v2 key policy, not the interim v1).
3. **Acknowledge the deviation:** no live `revoke_signing_key` probe in production; definition review (§4) instead.
4. Then, if approved: `AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT` scoped to §1.
