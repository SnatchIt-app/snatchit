# PFA-18C — C5 MONITOR ARMING EXECUTION PACKAGE — **FOR OWNER REVIEW** (NOT AUTHORIZED · NOTHING EXECUTED · MONITOR NOT ARMED)

**Date:** 2026-09-10 · **Coordinator:** Claude B · **State:** C3 COMPLETE (trust root `…b0` registered, `PHASE2_PFA18C_C3_EXECUTION_RECORD.md`); monitor **disarmed** (`signing.monitor_enabled=false`, fingerprint pin `null`).
**C5 requires the separate exact owner phrase `AUTHORIZE PFA-18C MONITOR ARMING`.** This document is not that authorization. C5 is a **PRODUCTION CONFIG** mutation (three `catalog.platform_config` versions at most); it deploys nothing, writes no secret, flips no feature flag, signs nothing, and does not approach M5/T3.
**Key finding (CLAUDE-OBSERVED, live source 2026-09-10):** since migration **102**, `signing.expected_key_fingerprint` and `signing.expected_max_not_after` are **dual-controlled with no polarity** inside `catalog.set_platform_config` — a set **parks** a `kernel.approval_request` (`action = 'config.set_money_key'`, expires 72 h, version unchanged) and only a **second, distinct platform_admin on an aal2 session** can apply it via `kernel.approve_refund_request(request_id, 'approve', reason, command_key)` (the generic approver; branch `config.set_money_key`; SoD `self_approval` refusal; aal2 step-up required). `signing.monitor_enabled` is deliberately **single-admin** (kill switch). The ceremony doc §9.3 sentence "a single platform_admin can pin, arm" is **stale** (pre-102) — dated correction recorded.

Evidence classes: **CLAUDE-OBSERVED**, **OFFICIAL-DOC**, **DEFINITION-REVIEW**.

---

## 1. What C5 changes — exact config keys and values

| Key (`catalog.platform_config`, append-only versions) | Current (v1, seeded 2026-09-04 by 099) | Target | Path | Who |
|---|---|---|---|---|
| `signing.expected_key_fingerprint` | `null` | `"562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415"` (JSON string; lowercase hex; = D5 = the stored row's SHA-256(DER SPKI)) | **dual-controlled** → parked request → second platform_admin approves → **v2** written | proposer: platform_admin A · approver: platform_admin B |
| `signing.expected_max_not_after` | `null` | **unchanged** (D6 chose `not_after = NULL`; the checker compares `max(not_after) is distinct from pinned` → both null ⇒ agree) | no write | — |
| `signing.monitor_enabled` | `false` | `true` | **direct** single-admin write → **v2** | platform_admin A (or B) |

Nothing else is written. The cron job `monitor-signing-key-invariants` (`23 5 * * *`, command `select kernel.check_signing_key_invariants();`, owner `postgres`) already exists and becomes live the moment `monitor_enabled` is `true`.

## 2. The invariant check (DEFINITION-REVIEW of `kernel.check_signing_key_invariants()`, live)
Read-only, `SECURITY DEFINER`, EXECUTE granted to **`postgres` only**; never reads `kms_handle_ref`; fingerprint reduced to a word. While `monitor_enabled` is false it returns `{"status":"monitor_disabled"}` and writes nothing (observed 19:28Z). When armed it evaluates: `total_keys=1`, `scoped_keys=0`, `active_global=1`, `rotating_keys=0`, `revoked_keys=0`, `fingerprint=match` (recomputed from the `…b0` row's PEM vs the pinned hex), `max_not_after` vs `signing.expected_max_not_after` (both null ⇒ agree). **Expected after C5:** `{"status":"ok","alerts":[],"fingerprint":"match","total_keys":1,"scoped_keys":0,"active_global":1,"rotating_keys":0,"revoked_keys":0,"max_not_after_set":false,"deduped":false}`. On any alert: one append-only `kernel.admin_audit` row (`signing_key.invariant_alert`, actor sentinel `…f1`, deduped 24 h) + best-effort push to the deployed `notify-report` edge (event `signing_invariant_alert` → `public.admin_users` (2) push + `ADMIN_EMAIL` + Sentry). Egress readiness (CLAUDE-OBSERVED): `notify-report` ACTIVE and handles the event; `vault.secrets` `service_role_key` row present (1). **Order matters:** pin the fingerprint **before** arming, otherwise the first armed run alerts `fingerprint=unpinned` (audit row + egress).

## 3. Execution paths (the setter is reachable only two ways)

| Fact (CLAUDE-OBSERVED) | Consequence |
|---|---|
| PostgREST exposes only `public, graphql_public, kernel, ops` (probe 19:3xZ: `Invalid schema: catalog`) | `catalog.set_platform_config` **cannot** be called through PostgREST/the admin console; `kernel.approve_refund_request` and `kernel.list_approval_requests` **can** (kernel exposed; EXECUTE to `authenticated`) |
| Setter checks `auth.uid()` + `kernel.is_platform(['platform_admin'])`; no aal check. Approver checks `auth.uid()`, rate limit, `pending`, **SoD** (`self_approval` if approver = requester), platform_admin, **aal2 claim** | proposer and approver must be **two distinct** platform_admins; the approver's session must carry `aal = aal2` |
| platform_admins today: **2** (both via the `public.admin_users` bootstrap; `kernel.platform_role` has 0 rows) | the second founder is required for the pin; the owner cannot self-approve |
| Ceremony §9.3: "Executed by a platform_admin JWT … through PostgREST or an authenticated `psql` session — never the SQL editor" | with `catalog` unexposed, the proposer step can only run as an **authenticated psql session** = the DB owner's `psql` with the platform_admin's JWT claims set for the transaction (`set_config('request.jwt.claims', …, true)`) — a documented path, but it is claim injection by the DB owner, not a token-verified session (recorded as a limitation, §7) |
| Admin console has no platform-config screen; its `ops.approve_action` is the ops action queue, not `kernel.approval_request` | the approver step runs via **PostgREST `rpc/approve_refund_request`** with founder B's **real** session JWT (MFA, aal2), or via psql claims on founder B's behalf (weaker; not recommended) |

**Recommended procedure (for owner decision):** proposer = owner (founder A) via the authenticated-psql path; approver = the second founder (B) via PostgREST with B's own MFA/aal2 session token; arming = owner via the same psql path. The request id is obtained from the proposer's return value or `kernel.list_approval_requests`.

## 4. Preconditions (read-only, minutes before)
G1 exactly one active global ES256 row `…b0`, fingerprint = D5 · G2 monitor keys at v1 (`false`/`null`/`null`) · G3 `check_signing_key_invariants()` → `monitor_disabled` · G4 `kernel.approval_request` pending = 0 · G5 flags issuance/scanning false · G6 `notify-report` ACTIVE; vault `service_role_key` present · G7 second platform_admin available with an aal2-capable session (admin console MFA) · G8 `PROD_DB_URL` session-mode PASS (owner) · G9 no `signing_key.%` / `config.%` audit rows yet (baseline 0/0).

## 5. Steps (owner runs; coordinator reads back; nothing here is executed by this package)

**C5-1 — propose the pin (founder A, Mac 1, authenticated psql session; one transaction; values from the evidence pack):**
```sql
begin;
select set_config('request.jwt.claims', json_build_object('sub','<FOUNDER_A_AUTH_UID>','role','authenticated')::text, true);
select catalog.set_platform_config('signing.expected_key_fingerprint',
         to_jsonb('562b5e87bb1c70ba2791503dd3cfe7014332c4cf9278d7c72680806768f64415'::text),
         'pfa18c_c5_pin_fingerprint', 'pfa18c-c5-pin-1');
commit;
```
Expected: `{"status":"parked","key":"signing.expected_key_fingerprint","version":1,"request_id":"<uuid>"}` — version **unchanged**; one `kernel.approval_request` (`config.set_money_key`, pending, expires +72 h); one `kernel.admin_audit` row `config.money_key_proposed`. (`noop_replay` would mean the value is already set; `insufficient_privilege` means the claims/uid are wrong.)

**C5-2 — approve (founder B, own MFA session, aal2; via PostgREST):** `POST https://hqycwntpfoztoinemqns.supabase.co/rest/v1/rpc/approve_refund_request` with headers `apikey: <publishable key>`, `Authorization: Bearer <founder B session JWT>`, `Content-Profile: kernel`, body `{"p_request_id":"<request_id>","p_decision":"approve","p_reason_code":"pfa18c_c5_pin_fingerprint","p_command_key":"pfa18c-c5-approve-1"}`. Expected: `status ok`, request `approved`, **`signing.expected_key_fingerprint` v2 = the D5 string**, audit rows (`config.change` / request approved). Refusals to expect if misused: `self_approval` (same person), `step_up_required`/`step_up_unavailable` (no aal2), `insufficient_privilege`.

**C5-3 — arm (founder A, authenticated psql session):**
```sql
begin;
select set_config('request.jwt.claims', json_build_object('sub','<FOUNDER_A_AUTH_UID>','role','authenticated')::text, true);
select catalog.set_platform_config('signing.monitor_enabled', 'true'::jsonb, 'pfa18c_c5_arm', 'pfa18c-c5-arm-1');
commit;
```
Expected: `{"status":"ok","key":"signing.monitor_enabled","version":2,"request_id":null}` (direct path; audit `config.change`).

**C5-4 — first check now, not at 05:23 (read-only; `postgres`; owner via psql or coordinator via MCP):** `select kernel.check_signing_key_invariants();` → **`status ok`, `alerts []`, `fingerprint match`** (§2). Anything else ⇒ STOP: disarm (C5-R) and report; do **not** test a wrong fingerprint in production.

## 6. Read-backs (coordinator read-only MCP; Mac 2 Dashboard optional)
`catalog.platform_config` for `signing.%` ordered by version: fingerprint v2 = D5 string, `expected_max_not_after` v1 null (unchanged), `monitor_enabled` v2 true · `kernel.approval_request`: exactly one `config.set_money_key`, state `approved`, `requested_by ≠ approved_by` · `kernel.admin_audit`: `config.money_key_proposed`, `config.change` ×2 (fingerprint apply, arm), **no** `signing_key.invariant_alert` · `check_signing_key_invariants()` = ok/match · `cron.job` row unchanged · flags issuance/scanning false · `kernel.signing_key` unchanged (1 row, D5) · AWS: no event; KMS key unchanged.

## 7. Rollback / disarm, limits, and residuals
- **Disarm (single admin, kill switch):** `set_platform_config('signing.monitor_enabled','false'::jsonb, …)` → v3 false; the checker returns `monitor_disabled` and writes nothing. Own phrase `AUTHORIZE PFA-18C MONITOR DISARM`.
- **Un-pinning / re-pinning the fingerprint is itself dual-controlled** (parks; second admin) — by design (102).
- The proposer/arming path is DB-owner claim injection (§3) — a documented but weaker identity assurance than a verified token; the approver step keeps the genuine second-human control via PostgREST + aal2. Whether `catalog` should be exposed or an admin-console config screen built is an open item (KJ §5 Q3 lineage), not part of C5.
- `set_platform_config` has **never run in production** (0 `config.%` audit rows) — C5 is its first use; a local rehearsal of C5-1/C5-2 on the rehearsal harness is recommended before authorization (read-only relative to production).

## 8. Untouched by C5 (confirmation)
Issuance/scanning flags (`feature.*`) — not written · Supabase secrets — none · edge deployment — none (`notify-report` already deployed; the monitor only posts to it on an alert) · AWS/KMS — none · `kernel.signing_key` — not written · M5/T3 — no credential signed, issuance stays off · Model A — unchanged (still required before T3).

## 9. Owner decisions before authorization
1. Confirm the dual-control reality (102) and that the **second founder** will approve C5-2 with their own MFA/aal2 session.
2. Accept the proposer path (authenticated psql with claims) or choose to first build/expose a token-verified path (separate work).
3. Optional: rehearse C5-1/C5-2 locally first.
4. Then, if approved: **`AUTHORIZE PFA-18C MONITOR ARMING`** scoped to §1.
