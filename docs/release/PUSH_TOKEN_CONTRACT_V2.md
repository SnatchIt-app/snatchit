# Push-token registration contract — version 2 (FROZEN 2026-09-15)

Server: migration `128_register_push_token_secure_rebind.sql` at **`f22c1a3`** (branch
`fix/127-release-reservation-guards`). Independent review: D pass 3 on `f22c1a3`, **no blocking findings**;
certified harness 4806/4806. Applied nowhere yet. **This document is the client's authority; the SQL is the
server's. If they disagree, the SQL wins and this file is wrong — report it, do not adapt silently.**
Owner: A. Consumer: C. Changes after this date require a version bump (`contract_version` 3), never an edit here.

## 1. The verb
`public.register_push_token(p_token text, p_platform text, p_device_secret text, p_device_name text default null) → jsonb`
- EXECUTE: `authenticated` only. `anon` and `service_role` are refused (`42501 not_authenticated` when `auth.uid()` is null).
- Called through PostgREST RPC as the signed-in user. Never through `notify.register_push_token`, which is
  **revoked from `authenticated`** by 128 and refuses with `42501`.

### Reply (success)
```json
{ "token_id": "<uuid>", "outcome": "registered|refreshed|rebound|rebound_legacy",
  "platform": "ios|android", "contract_version": 2 }
```
| `outcome` | Meaning |
|---|---|
| `registered` | the token was unbound; now bound to the caller with the caller's secret |
| `refreshed` | already the caller's row; `last_used`/`platform`/`device_name` updated, `is_active` true, revocation cleared. **The stored proof is never replaced** — a different secret from the owner still returns `refreshed` (no disclosure); recovery from a lost secret is delete-your-own-row + register |
| `rebound` | another account's row, but the caller presented the matching secret (same physical device, new account) |
| `rebound_legacy` | a pre-128, hash-less row the previous owner **signed out of** within 30 days; transitional, closes at the 90-day sunset |
Every success also **heals delivery**: `last_provider_error` is cleared and the caller's push channel state is reset to
`ok` if it was `unreachable`. A client need do nothing extra after a `DeviceNotRegistered` — re-registering is the repair.

### Errors (exact)
| SQLSTATE | Message | When | Client behaviour |
|---|---|---|---|
| `42501` | `not_authenticated` | no session | do not retry until signed in |
| `P0001` | `precondition_failed: token length` | `p_token` null, < 8 or > 4096 chars | client bug; terminal |
| `P0001` | `precondition_failed: platform must be ios or android` | anything else, incl. null | client bug; terminal |
| `P0001` | `precondition_failed: device secret length` | `p_device_secret` null, < 16 or > 512 chars | client bug; terminal |
| `P0001` | `precondition_failed: too many registration attempts` | > 20 calls per 600 s per user | back off; retry next launch |
| `42501` | `insufficient_privilege: token is bound to another account` | rule 4, **and every failed rule-5 condition including the 90-day sunset** — by design indistinguishable | terminal for this token on this account: show "contact support"; do not loop |
There is **no distinct sunset error and no other message text**. Any other error is a server defect: log the SQLSTATE and message, treat as transient.

## 2. What the client must do
1. **Generate the device secret once per install**: ≥ 16 characters from a CSPRNG (the server enforces the length floor
   only; it cannot measure entropy of a client-chosen value). Store it in SecureStore. Never log it, never send it
   anywhere but this verb. Losing it is recoverable (delete own row, register again); leaking it is not detectable.
2. **Call the verb on every cold launch** while signed in, not only on first install — regardless of any daily TTL.
   This is what converts a pre-128 row into a proven one on the first launch after upgrade. Backoff after
   `too many registration attempts` and terminal failures still win.
3. **Pin `contract_version`**: treat a reply without `contract_version: 2` as `contract_mismatch` — terminal until a
   new build. (A v1-shaped reply without the field cannot come from this verb; if seen, the client is talking to
   the wrong function.)
4. **Sign-out** revokes through **`public.revoke_push_token(p_token)`** (`supabase.rpc('revoke_push_token', { p_token })`)
   → `{ "revoked": 0|1 }`. Never by writing `revoked_at`/`revoked_reason` directly — those columns are not
   client-writable (below), and a direct write is refused. A failure (PGRST202, 42501, network) never blocks sign-out.
   > **ERRATUM 2026-09-15 (A's defect, found by C):** this clause originally named `notify.revoke_push_token`. The
   > `notify` schema is not PostgREST-exposed (sandbox: `public, graphql_public, kernel`) and Build 16 never calls it,
   > so the frozen text was unreachable. Migration **129** adds the public wrapper with the identical reply shape; the
   > contract version stays 2. Server: `129_public_revoke_push_token.sql`; test 196.
5. **Rate limit:** `precondition_failed: too many registration attempts` is **not terminal** — back off, retry on
   the next cold launch or after 600 s (C's reading, adopted).
6. **On `insufficient_privilege`** at registration: stop, surface the terminal "contact support" state, keep the
   secret. Do not delete the row (it is not yours) and do not regenerate the secret (it would not help).
7. **Recovery from a lost secret** (still your row): `DELETE FROM push_tokens WHERE token = <token>` under RLS
   (owner-delete), then register → `registered`. This is the only recovery path; rotation does not exist.

## 3. Table access the client may rely on (`public.push_tokens`, RLS owner-scoped)
| Privilege | Scope |
|---|---|
| SELECT | column-scoped: `id, user_id, token, platform, device_name, created_at, last_used, is_active, revoked_at, revoked_reason, provider_receipt_checked_at, last_provider_error` — **never `device_secret_hash`** (`select *` will fail; select columns by name) |
| UPDATE | column-scoped: `platform, device_name, last_used, is_active` only. Writing `revoked_*`, `user_id`, `token` or the hash is refused `42501` |
| INSERT | table-level (the pre-128 client path keeps working; such rows carry no proof until the verb runs). A non-null `device_secret_hash` on INSERT is refused by trigger |
| DELETE | table-level, own rows (the recovery path) |
The shipped Build 16 client (`select('id')`, `update({last_used, is_active})`, `insert({user_id, token, platform, is_active})`) is compatible unchanged.

## 4. Support path (not a client verb)
`public.unbind_push_token(p_token text)` → `{ "unbound": n, "contract_version": 2 }`, `service_role` only. Releases a
binding so the genuine device can register again; the remedy for a squatted or captured token.

## 5. Residual risk — for the owner's release decision, not the client's
`O3_128_RESIDUAL_DECISION_BRIEF.md` (with D's independent disposition). Summary: with the victim's **session**, an
attacker can redirect or forward the victim's notifications, persistent after credential revocation until support
unbinds; 128 closes capture by **token knowledge alone**. Nothing in this contract mitigates the session case;
the every-cold-launch clause bounds only how long a pre-128 row stays unproven.

## 6. Provisional → final
C's provisional implementation (`d90db6b`: `coldLaunch` in `decideRegistration`, `EXPECTED_128_CONTRACT_VERSION = 2`,
`contract_mismatch` terminal) matches this document. Final delta for C: (a) the sunset/rule-5 branch **is** the
rule-4 branch — one terminal path, one message; (b) confirm no direct write of `revoked_*`/`user_id`/`token`
anywhere on the candidate stack; (c) DV-611 L/S/R and DV-611C on the Thursday build with 128 applied to the
sandbox (SBX-2).
