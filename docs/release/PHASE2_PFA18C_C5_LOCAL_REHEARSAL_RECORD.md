# PFA-18C — C5 MONITOR ARMING — LOCAL REHEARSAL RECORD (REHEARSAL evidence · production untouched · C5 NOT AUTHORIZED)

**Date:** 2026-09-10T19:47Z · **Coordinator:** Claude B · **Target:** local database `snatchit_rehears_c5` on `127.0.0.1:5432` (harness `scripts/rehearsal_reset.sh`, all **135** migrations replayed in `LC_ALL=C` order, GATE-2 census = CI baseline: tables 27 / functions 71 / policies 37 / triggers 27). The harness scrubs every remote-pointing variable and refuses non-loopback hosts. **No production read or write occurred during the rehearsal.**
**Inputs identical to production:** the pinned §6.1 artifact (`380f434d…`, 118 lines) with the real (public) `pub.pem`, D4 handle and D5 fingerprint; two rehearsal platform_admins A and B via the `public.admin_users` bootstrap (matching production's model: 2 admins, 0 `kernel.platform_role` rows); a non-admin C.

## 1. Main path — PASS

| Step | Actor / claims | Result |
|---|---|---|
| R1 bootstrap row (artifact) | `postgres` | four NOTICEs (PRE-FLIGHT 2 fingerprint `562b5e87…`, 2b ES256, 3 handle accepted, POST-CHECK `…b0`) → 1 row, active ES256 |
| R2 checker before arming | `postgres`, no claims | `{"status":"monitor_disabled"}` — no write |
| R3 **C5-1 propose pin** | A (`sub`=A, `role` authenticated) | `{"status":"parked","key":"signing.expected_key_fingerprint","version":1,"request_id":"…"}`; version unchanged (1); `kernel.approval_request` pending, `config.set_money_key`, expires in 72 h; audit `config.money_key_proposed` |
| R8 **C5-2 approve** | B (`aal`=aal2) | `{"status":"approved","request_id":"…","applied_version":2}`; `signing.expected_key_fingerprint` **v2 = D5**; request `approved`, `requested_by ≠ approved_by`; audit `config.money_key_approved` |
| R9 **C5-3 arm** | A | `{"key":"signing.monitor_enabled","status":"ok","version":2,"request_id":null}` (direct path); audit `config.change` |
| R10 **C5-4 first check** | `postgres`, no claims | `{"status":"ok","alerts":[],"fingerprint":"match","total_keys":1,"scoped_keys":0,"active_global":1,"rotating_keys":0,"revoked_keys":0,"max_not_after_set":false,"deduped":false}`; **0** `signing_key.invariant_alert` rows |
| R11 local-only negative (wrong pin inserted directly — **never done in production**) | `postgres` | `{"status":"alert","alerts":["fingerprint=MISMATCH"],…}` → **1** `invariant_alert` audit row (egress attempted, harness stub); restoring the D5 pin → `ok`/`match` again |
| R12 **C5-R disarm** (kill switch) | A | `{"status":"ok","version":3}`; checker → `monitor_disabled` |

## 2. Negative cases — all refused as designed

| Case | Claims | Refusal (verbatim) |
|---|---|---|
| N1 requester approves own request | A + aal2 | `self_approval: the requester cannot decide their own request` |
| N2 approver without an aal claim | B, no aal | `step_up_unavailable: the session carries no aal claim` |
| N3 approver on aal1 | B + aal1 | `step_up_required: a step-up (aal2) session is required to approve money` |
| N4 non-admin approver | C + aal2 | `insufficient_privilege: platform_admin required` |
| N5 setter with no JWT (plain `postgres`) | none | `insufficient_privilege: authentication required` |
| N6 re-propose the already-current value | A | `{"status":"noop_replay","version":4,"request_id":null}` — no request created |
| N7 cleanup: deny a pending request | B + aal2 | `{"status":"denied"}`; version unchanged; audit `config.set_money_key.request_denied` |

## 3. Facts confirmed for the production procedure
- The propose → second-admin approve → arm → check sequence works end-to-end with the exact production values; the approver **applies the version itself** (`applied_version`), no further write is needed.
- Order matters: pin first, then arm — an armed checker with an unpinned/wrong pin writes an alert row and attempts egress (R11).
- Audit trail to expect in production: `config.money_key_proposed` → `config.money_key_approved` → `config.change` (arm). Disarm adds one `config.change`.
- The setter and approver are unreachable without a `sub` claim; the approver additionally needs `aal = aal2` and a different principal than the proposer.
- Coordinator scripting defects during the rehearsal (recorded): a cosmetic aggregate error in one summary query, and psql variables not interpolated inside `DO $$…$$` blocks — the negatives were re-run at top level (§2). The production package uses top-level statements only.

Logs (scratchpad, not committed): `c5_rehearsal.log`, `c5_negatives.log`. Rehearsal DB left in place for re-runs (`snatchit_rehears_c5`).
