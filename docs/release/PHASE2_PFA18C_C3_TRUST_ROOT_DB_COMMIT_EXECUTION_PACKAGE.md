# PFA-18C — C3 TRUST-ROOT DB COMMIT EXECUTION PACKAGE — **FOR OWNER REVIEW** (NOT AUTHORIZED · NOTHING EXECUTED)

**Date:** 2026-09-10 (rev 2 — corrected per owner review items 1–5) · **Coordinator:** Claude B · **Prepared against:** production after **C2 COMPLETE** (`PHASE2_PFA18C_C2_EXECUTION_RECORD.md`) and C4 (110–114 live; guard 110 enforcing).
**Nothing here was executed.** No `kernel.signing_key` row exists; no edge, secret, flag, credential, or AWS change. **C3 requires the separate exact owner phrase `AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT`** (§1). This document is not that authorization.
**C18:** the owner runs the one `psql` invocation on the primary; the coordinator reads back only (read-only MCP); Device 2 reads back independently (§6). **C3 does not approach T3** (it signs nothing and enables nothing); Model A is required before T3, not before C3.
**Dated corrections (rev 1 → rev 2, 2026-09-10):** (i) the artifact pin cited "commit `66f5de60…`" — that is the file's **blob** id; the last commit touching the file is **`1f3fc19d295e101fb680393e4bd99db8b2f2cc5f`** (2026-09-05); both resolve to the same §6.1 block, hash below. (ii) "Anything else means nothing was written" is **withdrawn**; §5 defines the uncertain-outcome procedure. (iii) §7 now separates read-only checks from write-attempt probes and drops the live `revoke_signing_key` call. (iv) Coordinator label = Claude B. (v) The C2 proof was **one** successful KMS `Sign`; the other two `Sign` events are denied probes.

Evidence classes: **CLAUDE-OBSERVED**, **OWNER-RETURNED**, **OFFICIAL-DOC**.

---

## 1. Scope

The owner authorizes C3 by writing exactly **`AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT`**, scoped to:
- **Artifact:** the fenced `sql` block under "§6.1 The artifact" of `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` at commit **`1f3fc19d295e101fb680393e4bd99db8b2f2cc5f`** (blob `66f5de60f5a3f5ed3e12665822b8719f65ca31c7`), extracted by the exact command in §4 → `signing_key_bootstrap.sql`, **118 lines, SHA-256 `380f434d07d85c1f5a7a92ad376da3843becc9019f01c4f20580d67a66eba7f6`** (CLAUDE-OBSERVED from the commit, the blob and the working tree — identical). Run **verbatim**; the SQL is not modified by this package (invocation flags only, §4).
- **Inputs (exact):** `KMS_HANDLE_REF` = **D4** `arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e` · `PUBLIC_KEY_PEM` = **Device 2's own `pub.pem`** (SPKI PEM; SHA-256(DER) = D5) · `EXPECTED_FINGERPRINT` = **D5** `562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415` · `ALGORITHM` = **`ES256`** (explicit; the column default is `EdDSA`).
- **One** invocation, one transaction (§4), producing the four NOTICEs + `COMMIT`; then §7.

Not authorized: C5 monitor arming, C6 secrets/deploy, any edge, any flag, a second row, issuance/scanning, M5/T3, Model A, any AWS change, any re-run (§5), rollback (§8 — own phrase `AUTHORIZE PFA-18C C3 ROLLBACK`).

## 2. Prerequisites (all must hold; G1–G5 re-read by the coordinator seconds before the invocation)

| # | Check | Expected | Who |
|---|---|---|---|
| G1 | `select count(*) from kernel.signing_key` | **0** | coordinator (read-only MCP) + owner (`psql -tAc`) |
| G2 | triggers on `kernel.signing_key` | `tg_signing_key_insert_guard` **O**, `tg_signing_key_immutable` **O**, `tg_signing_key_updated_at` O (observed 2026-09-10) | coordinator |
| G3 | flags | `feature.native_issuance_enabled`/`native_scanning_enabled`/`signing.monitor_enabled` **false**; `signing.expected_key_fingerprint` null | coordinator |
| G4 | references | `kernel.tickets` 0 · `kernel.wallet_pass` 0 · `venue.door_manifest_entry` 0 (rollback stays available) | coordinator |
| G5 | ledger / tip / `get_manifest_signing_context()` | 135 / 120 / `unavailable: no_active_global_key` | coordinator |
| G6 | KMS key D4 | `Enabled`, `ECC_NIST_P256`, `SIGN_VERIFY`, `MultiRegion false`, policy = v2, tags 3, no alias | coordinator + Device 2 (`--profile verifier`) |
| G7 | runtime role | inline `pfa18c-runtime-sign` = D4-filled artifact; access keys 0/0/0 | coordinator |
| G8 | `pub.pem` on the primary = Device 2's export | 91-byte DER, prefix `3059301306072a8648ce3d020106082a8648ce3d03010703420004`, 0 `PRIVATE KEY`, one block; `openssl dgst -sha256 -hex pub.der` = D5 | owner |
| G9 | artifact hash reproduced on the primary | `380f434d…` (§4 step 1) | owner |
| G10 | **connection mode** | `$PROD_DB_URL` is a **session-mode** connection — direct `db.<ref>.supabase.co:5432` or the session pooler `…pooler.supabase.com:5432` (the local marker reads `aws-0-us-west-2.pooler.supabase.com:5432` = session mode). **Never the transaction pooler (port 6543):** the artifact uses a temp table, `pg_advisory_xact_lock` (guard rule 7) and a multi-statement transaction that require one server session | owner |
| G11 | psql | `psql (PostgreSQL) 17.11` on the primary; shell zsh; `$PROD_DB_URL` from the OS keychain — **never on Device 2, never in chat/Git** | owner |
| G12 | Device-2 DB read-back path decided (§6) | option A or C chosen by the owner | owner |
| G13 | C2 COMPLETE recorded | `PHASE2_PFA18C_C2_EXECUTION_RECORD.md` | coordinator |

## 3. The row passes migration 110's guard (rules 1–11) and the artifact's own gates

| Rule | Requirement | The §6.1 row |
|---|---|---|
| 1 | `scope='global'` | `'global'` |
| 2 | `status='active'` | `'active'` |
| 3 | `algorithm='ES256'` explicit | `-v ALGORITHM=ES256` (PRE-FLIGHT 2b also aborts on anything else) |
| 4 | full AWS KMS key ARN | D4 (regex-verified 2026-09-10) |
| 5 | no `PRIVATE KEY` | pub.pem public only (PRE-FLIGHT 2 also aborts) |
| 6 | SPKI PEM → 91-byte uncompressed P-256 | verified (G8) |
| 7 | advisory xact lock | taken by the trigger (needs session mode — G10) |
| 8 | no duplicate `key_id` | table empty (PRE-FLIGHT 1 also aborts if not) |
| 9 / 10 | no active/rotating, no revoked global | 0 rows |
| 11 | first global `key_id` = `…b0` | the artifact writes `00000000-0000-0000-0000-0000000000b0` |

Both layers evaluate inside the same transaction: a refusal from either aborts the whole transaction; there is no partial state.

## 4. Invocation (§6.2 — OWNER, primary machine; SQL unmodified; proposed invocation flags explained)

**Transaction boundaries of the artifact (verified from the pinned block):** line 13 `\set ON_ERROR_STOP on` → line 14 `begin;` → line 16 `create temp table ceremony_input on commit drop` → five `do $$` gate blocks (lines 23, 33, 59, 76 = PRE-FLIGHT 1, 2, 2b, 3) → line 90 `insert into kernel.signing_key` → line 101 `do $$` POST-CHECK → line 118 `commit;`. Any `raise exception` aborts the transaction; with `ON_ERROR_STOP` psql stops at that statement and, being non-interactive, exits (code 3), the session closes, and the server rolls back. No statement after `commit;` exists, so no idle-in-transaction state is left by a *completed* run.

```bash
# 1 — stage the artifact from the pinned commit and verify its hash (do not edit it)
mkdir -p "$CEREMONY_DIR" && cd "$CEREMONY_DIR"
git -C /Users/josetascon/snatchit-consol show 1f3fc19d295e101fb680393e4bd99db8b2f2cc5f:docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md \
  | awk '/^### 6.1 The artifact/{f=1} /^### 6.2 Running it/{f=0} f' | awk '/^```sql/{f=1;next} /^```/{f=0} f' > signing_key_bootstrap.sql
shasum -a 256 signing_key_bootstrap.sql        # MUST print 380f434d07d85c1f5a7a92ad376da3843becc9019f01c4f20580d67a66eba7f6
wc -l < signing_key_bootstrap.sql              # 118
# 2 — stage the inputs as files (never in shell history); pub.pem / pub.der = Device 2's export, copied to the primary
printf '%s' 'arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e' > handle.txt
openssl dgst -sha256 -hex pub.der | awk '{print $2}' > fingerprint.txt
cat fingerprint.txt                            # MUST print 562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415
# 3 — the one mutation (single transaction inside the file)
psql -X -v ON_ERROR_STOP=1 "$PROD_DB_URL" \
  -v PUBLIC_KEY_PEM="$(cat pub.pem)" \
  -v KMS_HANDLE_REF="$(cat handle.txt)" \
  -v EXPECTED_FINGERPRINT="$(cat fingerprint.txt)" \
  -v ALGORITHM="ES256" \
  -f signing_key_bootstrap.sql 2>&1 | tee c3_output.txt; echo "psql_exit=${pipestatus[1]}"
```
**Proposed invocation corrections (flags only; the reviewed SQL is untouched):** `-X` (`--no-psqlrc`) isolates the run from any `~/.psqlrc` (`AUTOCOMMIT off`, `ON_ERROR_ROLLBACK`, variable overrides) — the file's own `\set ON_ERROR_STOP on` on line 13 still applies; `-v ON_ERROR_STOP=1` makes the setting effective from the first line (belt and braces); **do not add `-1/--single-transaction`** (the file already has `begin;`/`commit;` — `-1` would nest and change the boundaries); `2>&1 | tee` captures the NOTICEs (psql prints them on stderr) into an evidence file; `${pipestatus[1]}` (zsh; bash: `${PIPESTATUS[0]}`) records psql's exit code: **0** = script completed, **3** = a statement failed under ON_ERROR_STOP (rolled back), **2** = connection failure → §5.

**Required output — all four lines, then `COMMIT`, exit 0:**
```
NOTICE:  PRE-FLIGHT 2 PASSED — fingerprint 562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415
NOTICE:  PRE-FLIGHT 2b PASSED — algorithm ES256
NOTICE:  PRE-FLIGHT 3 PASSED — handle accepted (value not echoed)
NOTICE:  POST-CHECK PASSED — exactly one active global key, key_id …b0, algorithm ES256
COMMIT
```
**Do not use the Supabase SQL editor for this step** (no `-v` variables; values would be retained in query history). Then §5.4 of the ceremony doc: `rm -f handle.txt fingerprint.txt` is optional (public values); keep `c3_output.txt`, `pub.pem`, `pub.der` as evidence.

## 5. Outcome determination — including the uncertain case (replaces "anything else means nothing was written")

| Observed | Class | Action |
|---|---|---|
| four NOTICEs + `COMMIT` + `psql_exit=0` | **committed** | proceed to §7 |
| an `ERROR:` line, no `COMMIT`, `psql_exit=3` | **rolled back** (server aborted the open transaction when psql exited) | read §5.1 to confirm `count = 0`; report the error text; no re-run without owner review |
| no `COMMIT` line and exit ≠ 0/3, connection reset, terminal/laptop died, hang, or output lost | **UNCERTAIN** | **never re-run automatically.** Run §5.1 + §5.2 first |

**5.1 Read-only determination (owner via `psql -X -tAc`, coordinator via read-only MCP — identical query):**
```sql
select count(*) as n,
       bool_and(key_id = '00000000-0000-0000-0000-0000000000b0' and scope = 'global' and status = 'active'
                and algorithm = 'ES256' and not_after is null and not_before <= now()
                and kms_handle_ref = 'arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e'
                and encode(sha256(decode(regexp_replace(public_key,'-----(BEGIN|END) PUBLIC KEY-----|[[:space:]]','','g'),'base64')),'hex')
                    = '562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415') as exact_row
  from kernel.signing_key;
```
- `n=1, exact_row=true` → the COMMIT happened (only the acknowledgement was lost). **Treat as committed; go to §7; no re-run.**
- `n=0` → nothing is committed. Before any decision run §5.2. A re-run is a **new owner decision** (fresh explicit go), never automatic; it is safe by construction because PRE-FLIGHT 1 aborts if a row appeared meanwhile.
- `n=1, exact_row=false`, or `n>1` → **STOP.** Do not delete, do not re-run; report the row(s) (§7.1 query) for owner review.

**5.2 In-flight transaction check (read-only; only in the UNCERTAIN case with `n=0`):**
```sql
select pid, state, xact_start, backend_start, wait_event_type, left(query, 60) as query
  from pg_stat_activity
 where datname = current_database() and pid <> pg_backend_pid() and state <> 'idle';
```
A backend in `idle in transaction` from the primary's psql means the INSERT may still be uncommitted and the guard's advisory lock held: wait for the dead client to time out (server keepalives), or the owner terminates that pid (`select pg_terminate_backend(<pid>)` — an owner action; it rolls that transaction back). Only when §5.1 reads `n=0` **and** no such backend exists is the state settled as "not written".

## 6. Device-2 independent database verification — access path

The AWS verifier identity (`snatchit-kms-verifier`) grants **nothing** in Supabase. **Device 2 must never receive** `$PROD_DB_URL`, the database password, a service-role or secret key, a PAT, or a copied primary session.

| Option | What exists today | Independence | Residual |
|---|---|---|---|
| **A — Supabase Dashboard on Device 2** (recommended for C3) | the owner signs in to the Supabase Dashboard in Device 2's browser with the owner's Supabase account and **its own MFA**; runs only the §7 read-only SELECTs in the SQL editor | separate device + separate authenticated session; nothing copied | the Dashboard executes as `postgres` — read-only by **procedure**, not by principal; mitigations: the queries are pinned verbatim (§7.1/7.2/7.4/D3C), print no handle/secret, and the Dashboard's SQL calls are logged by Supabase (the coordinator corroborates via read-only `query_logs`) |
| B — admin console (LIVE 2026-09-08) | exposes no `kernel.signing_key` read | — | not usable for C3 |
| **C — dedicated read-only DB role for Device 2** | **does not exist** (genuinely missing prerequisite) — would need a reviewed migration (`create role … login`, `grant usage on schema kernel`, `grant select on kernel.signing_key`) plus a password delivered to Device 2 | principal-enforced read-only | new production role + credential; own authorization; not required for C3 if A is accepted |

**Smallest owner action:** choose **A** (no new prerequisite; sign in on Device 2 with Supabase MFA) or **C** (needs its own migration authorization before C3). The ceremony doc's "do not use the Supabase SQL editor" applies to the **INSERT** (variables/history); the §7 SELECTs carry no secret.

## 7. Post-commit verification — read-only checks vs write-attempt probes (separated)

### 7A. Read-only (coordinator via read-only MCP; owner via `psql -X -tAc`; Device 2 via §6)
| # | Query | Expected |
|---|---|---|
| 7.1 | ceremony doc §7.1 (key_id, scope, status, not_before, not_after, fingerprint; **handle not printed**) | one line; `…b0 \| scope=global \| status=active \| not_after=null \| fingerprint=562b5e87…` |
| 7.2 | §7.2 resolver global arm | `…b0 \| global` |
| 7.4 | §7.4 counts | `1\|1\|0\|0` |
| D3C-1 | `select venue.get_manifest_signing_context()` (stable function; returns the ARN — public) | `status ok`, `key_id …b0`, `algorithm ES256`, `key_status active`, `not_after null` |
| D3C-2 | `select count(*) from kernel.signing_key` / flags / references (G3, G4) | 1 / false / 0-0-0 |
| D3C-3 | grants: `venue.get_signing_keys_door`, `get_door_manifest_door`, `get_manifest_signing_context` | `service_role` only |
| 7.3-def | **read-only replacement for the live revoke probe:** `select pg_get_functiondef('kernel.revoke_signing_key(uuid,text,integer,text)'::regprocedure) ~ 'platform_admin' and pg_get_functiondef(…) ~ 'aal2'` | `true` (observed 2026-09-10: "checks platform_admin+aal2") |
| CT | CloudTrail | **no AWS event** from C3; KMS `Sign` count unchanged (1 success + 2 denied); no lifecycle event |

### 7B. Write-attempt probes (expected refusal; each contained by an explicit transaction that is rolled back either way) — OWNER on the primary only
Caller context: the owner's `psql -X` session, role `postgres` (superuser; triggers still fire — the session must **not** set `session_replication_role = replica` or disable triggers). Coordinator does **not** run these (read-only MCP).

| # | Probe | Exact form | Expected | If it unexpectedly succeeds |
|---|---|---|---|---|
| 7.5 | immutability guard (`tg_signing_key_immutable`, present + enabled) | `begin; update kernel.signing_key set public_key = public_key \|\| 'X' where key_id = '00000000-0000-0000-0000-0000000000b0'; rollback;` | `ERROR: append_only: …` | the `rollback` discards the change; re-run 7.1 and confirm the fingerprint unchanged; record finding **F-C3-1 (guard not effective)**; **stop before C5** |
| 7.3-parked | the **five** parked lifecycle functions (each raises `dual_control_unavailable` before any write — definitions verified 2026-09-10) | for each: `begin; select kernel.provision_signing_key('global',null,'-','-',now(),'p','p'); rollback;` (and `rotate_signing_key`, `provision_pass_type_cert`, `rotate_pass_type_cert`, `revoke_pass_type_cert` with the §7.3 arguments) | `ERROR … dual_control_unavailable` | rollback discards any write; record **F-C3-2**; stop before C5 |
| `revoke_signing_key` | **not called in production** (proposed dated deviation from ceremony §7.3 / runbook §A line 67): it is un-parked (106) and its success path sets `status='revoked'` — terminal, and it would park recovery (guard rule 10). Its refusal today (`insufficient_privilege`, JWT-claims check) is verified read-only by 7.3-def instead. | — | — | if the owner still wants the live probe: only inside `begin; … rollback;` |

Each 7B probe is a **production DB mutation attempt**, recorded as such in the mutation ledger (attempted; refused; rolled back).

## 8. Rollback (own phrase `AUTHORIZE PFA-18C C3 ROLLBACK`) and its limits

`docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` §10 `signing_key_bootstrap_ROLLBACK.sql` — deletes the `…b0` row **only while** no `kernel.tickets` / `kernel.wallet_pass` / `venue.door_manifest_entry` / `venue.door_manifest_delta` row references it (FK `ON DELETE RESTRICT` + explicit guard); all four are 0 today, so rollback is available from the moment of commit until the first credential mint; after that: rotation/compromise response only. It is a DB mutation (owner runs; same `-X`/session-mode rules). It does **not** touch AWS (the key stays; C2 rollback is separate). If C5 has armed the monitor by then, disarm first (C5 rollback), otherwise the deletion is flagged. After a §10 rollback the table is empty and the `…b0` lineage may be re-bootstrapped (no revoked row → rules 10/11 admit it) — but only under a fresh authorization.

## 9. What C3 does NOT do / next

C3 writes one row. It does not arm the monitor, write secrets, deploy edges, flip flags, sign anything, or start issuance/scanning. **Next, each separately authorized:** **C5** (`AUTHORIZE PFA-18C MONITOR ARMING` — `signing.expected_key_fingerprint := 562b5e87…`, `signing.monitor_enabled := true`, one `kernel.check_signing_key_invariants()`), **C6** (`AUTHORIZE PFA-18C DARK DEPLOY`; the runtime access key is created only then), **C7/M5** pending §5d, **Model A** before T3.

## 10. Unresolved prerequisites (owner decisions)
1. **Device-2 DB read-back path:** option A (Dashboard on Device 2, Supabase MFA; no new prerequisite) or option C (read-only role via its own authorized migration). Recommendation: **A**.
2. **Acknowledge the §7.3 deviation** (no live `revoke_signing_key` call; definition check instead).
3. **Acknowledge C2 variance V-1** (Device 2 verified the final v2 policy, not the interim v1) — recorded in the C2 execution record.
