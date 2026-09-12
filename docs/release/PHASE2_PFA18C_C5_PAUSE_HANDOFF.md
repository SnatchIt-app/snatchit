# PFA-18C — C5 MONITOR ARMING — PAUSED AFTER C5-1 (HANDOFF FOR RESUMPTION) — READ-ONLY MATERIALS

**Date:** 2026-09-10 · **Coordinator:** Claude B · **Owner instruction:** pause after C5-1; founder B unavailable today; do not approve, arm, disarm or modify production. Nothing below was executed after the pause.
**Authorization in force:** "AUTHORIZE PFA-18C MONITOR ARMING" (2026-09-10) — still covers C5-2/C5-3/C5-4 when resumed; it does not expire, but the parked request does (§1).

## 1. Recorded pause state (CLAUDE-OBSERVED 2026-09-10T20:46:33Z)

| Item | Value |
|---|---|
| Approval request `05e0ff5d-1044-40c9-b32d-c5db1c171976` | **`pending`**; action `config.set_money_key`; `requested_by` founder A (`2b117757-…`); `approved_by` null; proposed value = D5; created 19:59:17Z |
| **Expiry (72 h)** | **2026-09-13T19:59:17Z** (71.2 h remaining at the read). If it lapses, C5-1 is simply re-run by founder A (a new request; nothing else changes). |
| `signing.expected_key_fingerprint` | **v1 = null** (no version written) |
| `signing.expected_max_not_after` | v1 = null (unchanged by design, D6) |
| `signing.monitor_enabled` | **v1 = false** |
| `kernel.check_signing_key_invariants()` | **`monitor_disabled`** (writes nothing while disabled) |
| `kernel.signing_key` | 1 row, active ES256 `…b0`, fingerprint D5 |
| Flags | issuance false · scanning false |
| Audit | one `config.money_key_proposed` row (founder A); no `config.change`, no `signing_key.invariant_alert` |

## 2. C5-2 — founder B approves (their own device; their own MFA-verified session; token never leaves the browser)

Prerequisite facts (verified): the admin console is `@supabase/ssr` `createBrowserClient` (0.12), so the session lives in browser-readable chunked cookies `sb-hqycwntpfoztoinemqns-auth-token.0/.1`; `kernel` is PostgREST-exposed; `kernel.approve_refund_request` requires a `sub` claim, platform_admin, `aal = aal2`, a `pending` request, and refuses `self_approval`. Founder B = `3b7b50af-e9a2-41b6-89a3-b82a43dcae00` (contact@snatchitapp.com).

Steps: sign in to the admin console as founder B → complete the MFA challenge → Safari **Develop → Show Web Inspector → Console** → paste the block → Return. It decodes the session from the cookies inside the page, refuses to proceed unless the session is founder B's and `aal2` and unexpired, then calls the approval RPC and prints only the HTTP status and response body.

```javascript
(async () => {
  const ref = 'hqycwntpfoztoinemqns';
  const parts = document.cookie.split('; ').map(c => { const i = c.indexOf('='); return [c.slice(0, i), c.slice(i + 1)]; });
  const chunks = parts.filter(([k]) => k === `sb-${ref}-auth-token` || k.startsWith(`sb-${ref}-auth-token.`))
    .sort((a, b) => parseInt(a[0].split('.')[1] ?? '0') - parseInt(b[0].split('.')[1] ?? '0'));
  if (!chunks.length) return 'NO-AUTH-COOKIE: sign in again on this page, then re-run';
  const raw = chunks.map(([, v]) => decodeURIComponent(v)).join('');
  let session;
  if (raw.startsWith('base64-')) { const b = raw.slice(7).replace(/-/g, '+').replace(/_/g, '/'); session = JSON.parse(atob(b + '='.repeat((4 - b.length % 4) % 4))); }
  else session = JSON.parse(raw);
  const token = session.access_token; if (!token) return 'NO-ACCESS-TOKEN in the session cookie';
  const claims = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
  if (claims.sub !== '3b7b50af-e9a2-41b6-89a3-b82a43dcae00') return `WRONG-ACCOUNT: this session is ${claims.sub}, not founder B`;
  if (claims.aal !== 'aal2') return `NOT-AAL2 (aal=${claims.aal}): complete the MFA challenge in the console, reload, re-run`;
  if (claims.exp * 1000 < Date.now()) return 'TOKEN-EXPIRED: reload the page (refresh happens automatically), then re-run';
  const r = await fetch(`https://${ref}.supabase.co/rest/v1/rpc/approve_refund_request`, {
    method: 'POST',
    headers: { 'apikey': 'sb_publishable_dBAq-Yv22vguzP9QSC-Jew_4mmx64Yc', 'Authorization': `Bearer ${token}`, 'Content-Profile': 'kernel', 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_request_id: '05e0ff5d-1044-40c9-b32d-c5db1c171976', p_decision: 'approve', p_reason_code: 'pfa18c_c5_pin_fingerprint', p_command_key: 'pfa18c-c5-approve-1' })
  });
  return `${r.status} ${await r.text()}`;
})()
```
Expected: `200 {"status":"approved","request_id":"05e0ff5d-1044-40c9-b32d-c5db1c171976","applied_version":2}`. Guard messages (`WRONG-ACCOUNT`, `NOT-AAL2`, `TOKEN-EXPIRED`) and PostgREST errors (`step_up_required`, `self_approval`, `insufficient_privilege`, or `request … has expired`) write nothing. If the request expired, founder A re-runs C5-1 first and the new `request_id` replaces the one in the block. Founder B returns only the printed line.
**Coordinator read-back after C5-2:** `signing.expected_key_fingerprint` **v2** = D5; request `approved`, `approved_by` = founder B ≠ requester; audit `config.money_key_approved`; monitor still `false`.

## 3. C5-3 — arm (founder A, Mac 1; **gated: run only after the C5-2 read-back above shows v2 = D5**)
```bash
psql -X -v ON_ERROR_STOP=1 "$PROD_DB_URL" <<'SQL' 2>&1 | tee c5_3_output.txt
begin;
select set_config('request.jwt.claims', json_build_object('sub','2b117757-f4e3-41c1-b7df-68a4502d0fba','role','authenticated')::text, true);
select catalog.set_platform_config('signing.monitor_enabled', 'true'::jsonb, 'pfa18c_c5_arm', 'pfa18c-c5-arm-1');
commit;
SQL
```
Expected: `{"key": "signing.monitor_enabled", "status": "ok", "version": 2, "request_id": null}` then `COMMIT` (direct path; audit `config.change`). Running it before C5-2 would arm an **unpinned** monitor and cause an `fingerprint=unpinned` alert row plus egress at the first check — hence the gate.

## 4. C5-4 — first check (read-only; `postgres`; coordinator via MCP or owner via psql; immediately after C5-3)
```sql
select kernel.check_signing_key_invariants();
```
Expected: `{"status":"ok","alerts":[],"fingerprint":"match","total_keys":1,"scoped_keys":0,"active_global":1,"rotating_keys":0,"revoked_keys":0,"max_not_after_set":false,"deduped":false}` and **0** `signing_key.invariant_alert` rows. Anything else ⇒ disarm (§5) and report; never test a wrong fingerprint in production. Thereafter the cron job runs daily at 05:23 UTC.

## 5. Rollback / disarm (kill switch; single admin; own phrase `AUTHORIZE PFA-18C MONITOR DISARM`)
```bash
psql -X -v ON_ERROR_STOP=1 "$PROD_DB_URL" <<'SQL'
begin;
select set_config('request.jwt.claims', json_build_object('sub','2b117757-f4e3-41c1-b7df-68a4502d0fba','role','authenticated')::text, true);
select catalog.set_platform_config('signing.monitor_enabled', 'false'::jsonb, 'pfa18c_c5_disarm', 'pfa18c-c5-disarm-1');
commit;
SQL
```
Expected `{"status":"ok","version":3}`; the checker returns `monitor_disabled` and writes nothing. Un-pinning or re-pinning the fingerprint is dual-controlled (parks) by design; pausing before C5-2 needs no rollback (a pending request is inert and expires on its own).

## 6. Resumption checklist (read-only, minutes before C5-2)
G1 one active ES256 `…b0` row, fingerprint D5 · request `05e0ff5d…` still `pending` and unexpired · keys still v1/v1/v1 · checker `monitor_disabled` · founder B signed in with MFA (aal2) · flags false. Coordinator re-reads and records before C5-2 proceeds.

**If the request has expired (after 2026-09-13T19:59:17Z) — rehearsed 2026-09-10, no production change:** expiry is enforced by the approver (`precondition_failed: request … has expired`); the row stays `pending` and does not block a new proposal. Re-run C5-1 exactly as before but with a **new command key** (`pfa18c-c5-pin-2`): re-using `pfa18c-c5-pin-1` fails with `duplicate key value violates unique constraint "approval_request_command_key_key" (requested_by, command_idempotency_key)` and writes nothing. Then the coordinator reads back the new `request_id`, and founder B's C5-2 block is re-issued with that id substituted (and a new `p_command_key`, e.g. `pfa18c-c5-approve-2`).
