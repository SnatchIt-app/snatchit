# 129 — session-bound push bindings: lifecycle design (A, 2026-09-15, for D's independent review)

**Why:** owner decision O-3 = option (b). The persistent notification-capture residual (session compromise ⇒
redirect/forwarding/dormant plant, surviving credential revocation — `O3_128_RESIDUAL_DECISION_BRIEF.md`) is **not
accepted for production**. This is a **production security gate**; sandbox acceptance and the candidate build do
not waive it. Local implementation, tests and review are authorized; nothing hosted.

**Number:** `129` (free; the 126→129 renumber was withdrawn). pgTAP `196`. Branch `fix/129-session-bound-push`.

## 1. Required properties (owner's words, made testable)
| # | Property | Test shape |
|---|---|---|
| P1 | **Password change invalidates** every push binding and device proof of that user | trigger fires on `auth.users.encrypted_password` change → all rows `is_active=false, revoked_at=now(), revoked_reason='password_changed', device_secret_hash=NULL`; epoch bumped |
| P2 | **Sign-out-everywhere invalidates** the same | verb `public.revoke_all_push_bindings()` (own user) does the same with reason `signed_out_everywhere`; client calls it immediately before `signOut({scope:'global'})` |
| P3 | **A compromised old session cannot silently recreate** a binding after P1/P2 | the verb refuses any registration whose **session was created before the user's binding epoch**, or whose session no longer exists (`42501 insufficient_privilege: session predates a credential change`) |
| P4 | **Dormant planted hashes die** at P1/P2 | hash cleared; a later claim from the attacker's account → rule 4 (no hash) or rule 5 (fails: reason ≠ `signed_out`) |
| P5 | **Forwarding dies** at P1/P2 and cannot be re-established from the old session | attacker's phone row revoked; re-bind needs a post-epoch session, i.e. the new password |
| P6 | **Ordinary sign-out** is unchanged | the client revokes its own token via `notify.revoke_push_token`; hash kept; other devices untouched; epoch untouched |
| P7 | **Legitimate re-registration** after P1/P2 works from a new session | new sign-in → new `auth.sessions` row (created ≥ epoch) → verb: rule 2 with hash NULL adopts the device's real hash → `refreshed`; or rule 1 if the row was deleted |
| P8 | **Older clients** (pre-128 insert path) after P1/P2 | their direct INSERT/UPDATE still work under RLS; they carry no proof; they are subject to P3 only through the verb (they don't call it) — so an old client on an OLD session can still re-INSERT a hash-less row. **This is a gap the design must state, not hide:** it is closed by (i) the P1/P2 revoke also **deleting** rows instead of revoking? No — see §4 decision |

## 2. Mechanism
### 2a. Per-user binding epoch
`kernel.identity_ext.push_binding_epoch timestamptz` (kernel, not public: no census/manifest movement; the verb
is SECURITY DEFINER). NULL = never bumped.

### 2b. Password change — server-authoritative (DB trigger, not a hosted auth hook)
```
create trigger trg_push_bindings_on_password_change
  after update of encrypted_password on auth.users
  for each row when (old.encrypted_password is distinct from new.encrypted_password)
  execute function kernel.invalidate_push_bindings_for(new.id, 'password_changed');
```
A DB trigger on `auth.users` is the same class as the existing `handle_new_user` pattern; it is **not** a hosted
Auth Hook and needs no dashboard change. It is auth-schema-adjacent and is called out for the owner. Ownership:
`auth.users` is owned by `supabase_auth_admin`; the migration must create the trigger as a role permitted to —
**verify on the local harness whether `postgres` may create a trigger on `auth.users`; if not, this is the one
piece that needs a hosted step and the owner must be told before, not after.**

### 2c. Sign-out-everywhere — client-initiated verb, server-enforced consequences
`public.revoke_all_push_bindings() → jsonb {revoked, contract_version: 2}` — `authenticated` only, acts on
`auth.uid()` only. The client calls it, then `signOut({scope:'global'})`. Why not a trigger on `auth.sessions`
DELETE-when-none-remain: Supabase's expired-session cleanup also deletes rows, and a user whose only session
expired would lose bindings and, worse, the epoch would move — a silent, unattributable effect. D may disagree;
argue it.

### 2d. The verb's session-age check (the P3 guarantee)
In `register_push_token`, after auth:
```
v_sid := (auth.jwt() ->> 'session_id')::uuid;           -- present in every Supabase access token
select created_at into v_sess_made from auth.sessions where id = v_sid;
if v_sess_made is null or v_sess_made < v_epoch then      -- v_epoch = identity_ext.push_binding_epoch
  raise exception 'insufficient_privilege: session predates a credential change' using errcode='42501';
end if;
```
Consequences stated plainly: **after a password change every device must re-establish its session before it can
register** — including the device that changed the password (its session predates the change). The client
handles it: after `updateUser({password})`, global sign-out + sign-in with the new password → register. C owns
that delta. An attacker holding an old access token (≤ 1 h) is refused; holding an old refresh token, they are
refused at refresh once sessions are deleted, and refused by P3 even if not.

### 2e. What `invalidate_push_bindings_for(uid, reason)` does (one definer function, both callers)
```
set epoch = now()  (identity_ext, upsert)
update push_tokens set is_active=false, revoked_at=now(), revoked_reason=<reason>, device_secret_hash=NULL
 where user_id = uid            -- under app.push_token_verb='on' for the guard, reset after
update notify.identity_channel_state set state='unreachable', reason=<reason> where identity_id=uid and channel='push'
```
Clearing the hash matters: a revoked row **with** the attacker's hash would still be claimable by rule 3.

## 3. Rule 5 interaction
`revoked_reason` for P1/P2 is `password_changed` / `signed_out_everywhere`, **never** `signed_out`, so rule 5
cannot hand those rows to a token-knower. Confirmed by the existing (b) predicate; add a negative test.

## 4. Older clients and the JWT window (P8; D's S3/S4/S5) — REVISED after D's criteria
A pre-128 client never calls the verb; it INSERTs/UPDATEs `push_tokens` directly under RLS. And any client — old
or new — holds a valid access JWT for up to an hour after P1/P2. Both must be refused at **write time, on the
table, for every role except the definer paths**, not by cleanup and not only in the verb:

**Write-time guard on `push_tokens` (replaces the RLS option):** `BEFORE INSERT OR UPDATE` trigger; when the row
would become `is_active = true` and the caller is a client role (`app.push_token_verb` not set), it
1. takes `pg_advisory_xact_lock(hashtext('push_bindings:' || user_id::text))` — the same key
   `invalidate_push_bindings_for()` takes first — so a write racing the password-change transaction **waits**
   and then re-reads the epoch under READ COMMITTED, seeing the committed bump (closes S4 without a
   delivery-time check);
2. reads `auth.jwt()->>'session_id'` → `auth.sessions.created_at`; missing row or `created_at < epoch` →
   `42501 insufficient_privilege: session predates a credential change` (closes S3 and S5 for the direct path).
The verb calls the same check explicitly (§2d) so its message is the contract's, not the trigger's. Old clients
on a **new** session still work (unproven row, as today). Old clients on an **old** JWT are refused — what they
see is an insert error their code already swallows (`usePushToken.ts:89-90` warns and continues); push resumes
on their next real sign-in. **Trigger count +1 in `public` (census 36).**

**Delivery paths (S9):** revocation sets `is_active = false`, which is the only filter the legacy
`supabase/functions/send-push/index.ts:66-71` reader applies (called by five senders); `notify.claim_deliveries`
D checks. Because writes are serialized above, `is_active` is truthful and no delivery-time epoch check is
needed in the edge — which keeps 129 migration-only, no edge deploy.

## 4b. D's criteria S1–S12 → where each is met
| S | Met by | Note |
|---|---|---|
| S1 | §2b trigger on `encrypted_password`; §2e | Whether Supabase ends other sessions on password change is a **hosted config fact, unverified**; the design does not rely on it (S3 covers surviving sessions) |
| S2 | §2c verb + §2e | |
| S3 | §2d + §4 write-time guard | session_id → live `auth.sessions` row ≥ epoch; missing row refused |
| S4 | advisory xact lock on the per-user key in both the invalidator and the guard | D probes with two connections; test in 196 with `dblink`/two sessions if the harness allows, else documented as D's probe |
| S5 | §4 | re-login works; old JWT refused; direct INSERT stays granted |
| S6 | §2e clears hashes; §2d/§4 refuse old JWT; P7 re-proof | |
| S7 | §2e revokes attacker-device rows; recreation needs a post-epoch session | **Out of scope, stated:** an attacker who knows the new password or holds a fresh session |
| S8 | P6 — `revoke_push_token` unchanged; epoch untouched | |
| S9 | `is_active=false` on revocation; write serialization | D's addendum confirmed the filter |
| S10 | `push_tokens.user_id → auth.users ON DELETE CASCADE` (baseline); kernel deletion sweep untouched | D verifies the sweep path |
| S11 | rollback drops the column, triggers, verb and reverts `register_push_token` to 128's body; **cleared hashes and revoked rows are not restorable** — stated in the rollback header | |
| S12 | **No hosted auth hook.** One DB trigger on `auth.users` (same class as `handle_new_user`) and reads of `auth.sessions` from a postgres-owned definer. Supabase-compatibility: creating triggers on `auth.users` as `postgres` is the documented pattern; `auth.sessions` SELECT by `postgres` is the dashboard's own access. **Hosted privilege not provable locally** (the harness's auth stand-ins are postgres-owned) — flagged for the owner; first hosted apply is the sandbox under an authorization that names it | |

## 5. Tests (pgTAP 196; all valid states, every assertion with a negative control against 128-only)
P1: update `auth.users.encrypted_password` → bindings revoked, hashes NULL, epoch set, channel unreachable ·
P2: verb → same · P3: register from a session with `created_at < epoch` → 42501; from a session ≥ epoch → ok;
missing session row → 42501 · P4: plant (attacker hash on victim row) → P1 → attacker claim from own account →
42501 · P5: attacker phone bound to victim → P1 → attacker's row revoked; re-register from old session → 42501 ·
P6: ordinary `revoke_push_token` leaves epoch NULL and other rows untouched · P7: new session → `refreshed`,
hash adopted · P8: old-client INSERT under old session → refused (option 2) · races: two registrations racing a
password change (the trigger's UPDATE and the verb's FOR UPDATE serialize on the row; assert the loser's
outcome) · rollback: epoch column and trigger drop; verb reverts to 128's body; hashes are not restorable (state
it). Fixture: `auth.sessions` rows inserted as postgres; `tap.login` extended to carry `session_id` in claims.

## 6. Client delta (C, provisional until 129 freezes)
- Password change flow: after success → `signOut({scope:'global'})` → sign in with the new password → cold-launch
  registration path.
- Sign-out-everywhere: call `revoke_all_push_bindings()` **before** `signOut({scope:'global'})`; ignore its
  failure (never block sign-out).
- New terminal error at registration: `session predates a credential change` → force re-auth, then register.
- Ordinary sign-out: unchanged.

## 7. Effect on dates
Candidate (Fri): **none** — 129 is not in the candidate. Production: gated on 129 reviewed + tested + integrated
(a second candidate or a delta build, because the client delta is required for P7 to be usable). Estimate: SQL +
196 Tue–Wed (A, 5–8 h), D review Wed–Thu, C delta Wed–Thu, then a build carrying it. **Realistic production
readiness: the week of 21 Sept**, not Friday.
