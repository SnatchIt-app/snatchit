# 131 — session-bound push bindings: lifecycle design (A, 2026-09-15, for D's independent review)

**Why:** owner decision O-3 = option (b). The persistent notification-capture residual (session compromise ⇒
redirect/forwarding/dormant plant, surviving credential revocation — `O3_128_RESIDUAL_DECISION_BRIEF.md`) is **not
accepted for production**. This is a **production security gate**; sandbox acceptance and the candidate build do
not waive it. Local implementation, tests and review are authorized; nothing hosted.

**Number:** `131` (moved from 129 on 2026-09-15: 129 became the `public.revoke_push_token` wrapper, which must sort below this in the same candidate for the merge guard). pgTAP `198`. Branch `fix/131-session-bound-push`.

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
needed in the edge — which keeps 131 migration-only, no edge deploy.

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

## 4c. D's first-pass findings X1–X6 (2026-09-15) and the revised design
| | Finding | Disposition |
|---|---|---|
| **X1 — NOT CLOSED by §2e alone** | a redirect **completed** during the compromise (delete-then-register, or a claimed plant) lives in a row now owned by the **attacker**; the victim's epoch never touches it; the victim's genuine device on a new session gets 42501 forever. D probed it | **Adopt D's (i), proof-carrying reclaim:** when a token leaves an account (owner DELETE, rule 3/5 rebind), write a tombstone `(token, previous_user, previous_hash, at)`; a device presenting a secret whose hash matches the tombstoned hash for that token **reclaims** it — the attacker's row is revoked and the token rebinds to the previous owner. Closes delete-then-register and any seizure of a device that had **already proven itself**. **What it cannot close, stated for the owner:** seizure of a device whose only hash was planted by the attacker, or of a hash-less legacy row — no genuine proof exists to reclaim with. That slice is closed only by provider-side proof (option c, client v3, next candidate) and, until then, by support unbind + a client error that tells the user. +0.5–1 day, uncertain |
| **X2 — HIGH** | DELETE was unguarded: an old JWT can delete the victim's revoked rows, then rule 1 from the attacker's account binds the token after the credential change | guard `BEFORE DELETE` with the same session/epoch check; the owner's post-epoch session still deletes (recovery kept) |
| **X3 — MEDIUM** | lock-order deadlock: a client UPDATE holds the row lock then its trigger wants the advisory lock; the invalidator holds the advisory lock then wants row locks — GoTrue's password change could abort | invalidator takes **row locks first** (the UPDATE), **then** bumps the epoch under the advisory lock; racing UPDATE waits on the row and re-evaluates; racing INSERT waits on the advisory lock and reads the committed epoch. No cycle |
| **X4 — MEDIUM** | epoch = `now()` is transaction-start time on Postgres's clock; `auth.sessions.created_at` is GoTrue's clock; a session minted in flight or skew can read as "after" | epoch = `greatest(new.updated_at, clock_timestamp()) + 2 s`; legitimate re-login retries on 42501 (client). Hosted verification is part of S12 |
| **X5 — MEDIUM** | S2 relied on an updated client calling the verb; old clients, a failed call, and dashboard revocation leave forwarding rows and plants **active** (writes refused, rows not) | add an `AFTER DELETE` trigger on `auth.sessions` that invalidates **only when the deleted session was live** (`not_after` null or future) **and the user has no live session left** — distinguishable from expiry cleanup, which deletes expired rows. The verb stays as the fast path |
| **X6 — LOW, release note** | old-client users lose push silently after a password change until they sign out/in | documented; the old code swallows the error; C's new client re-auths |

Revised object list for 131: `kernel.identity_ext.push_binding_epoch`; `kernel.invalidate_push_bindings_for(uuid, text)`;
trigger on `auth.users` (password) and on `auth.sessions` (live-session delete, none left); `public.revoke_all_push_bindings()`;
`public.push_token_tombstone` (no-client-access) + tombstone writes in the verb's rebind paths and a `BEFORE DELETE`
tombstone trigger; the write-time guard on `push_tokens` (`BEFORE INSERT OR UPDATE OR DELETE`); reclaim logic in
`register_push_token` (rule 3′: tombstoned-hash match → revoke current holder, rebind to previous owner). Census:
+1 table, +2–3 functions, +2 triggers in `public`; manifest rows; expected_grants row; rollback stated as non-restoring.

## 5. Tests (pgTAP 198; all valid states, every assertion with a negative control against 128-only)
Added for X1–X5: completed-redirect reclaim (attacker row revoked, victim rebinds with the genuine secret; a
planted-only device does NOT reclaim — the unclosed slice, asserted as such); old-JWT DELETE refused; two-connection
lock-order race (D's probe; pgTAP cannot open two sessions — recorded as D's evidence, not a pgTAP assertion);
session minted in flight refused by the margin; live-session-delete trigger fires, expiry cleanup does not.
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
Candidate (Fri): **none** — 131 is not in the candidate. Production: gated on 131 reviewed + tested + integrated
(a second candidate or a delta build, because the client delta is required for P7 to be usable). Estimate: SQL +
196 Tue–Wed (A, 5–8 h), D review Wed–Thu, C delta Wed–Thu, then a build carrying it. **Realistic production
readiness: the week of 21 Sept**, not Friday.

## 4d. X1 — D's second pass (2026-09-15): reclaim REJECTED; the owner's choice
D reasoned from §4c that any reclaim keyed on "presented secret matches a tombstoned hash" cannot distinguish a
genuine earlier proof from an attacker-chosen one: **R1** a previous holder self-deletes to manufacture a tombstone
and reclaims later with no victim session; **R2** ping-pong if evictions write tombstones; **R3** a squat (rule 1,
token knowledge only) followed by self-delete becomes a **session-less capture** once the genuine device registers —
worse than V3's accepted DoS-only squat. Constraints (evicted holders get non-reclaimable tombstones; earliest
proof wins; acting-session recorded) close R1/R2 but not R3. **Disposition adopted: 131 ships WITHOUT reclaim.**
X1 — a redirect *completed* during the compromise — stays **UNCLOSED by 131**, mitigated by support
`unbind_push_token` plus the client's terminal "contact support" state, and closed only by provider-side proof
(option c, client v3). **Owner choice, stated in `O3_128_RESIDUAL_DECISION_BRIEF.md` §10.**

## 4e. P6 corrected for the shipped clients (C and D, independently, 2026-09-15)
Every shipped build signs out with auth-js's default **global** scope: one device's sign-out ends every session.
So "ordinary sign-out leaves other devices untouched" has never been true, and today those other devices keep
**active, hash-bearing rows with no live session — push keeps arriving on signed-out devices** (a current
production leak, pre-128). Under 131's live-session trigger (X5) every such sign-out revokes all bindings, clears
hashes and bumps the epoch — consistent, and it closes that leak. P6 is therefore **per client version**:
- old and current builds: sign-out ≡ sign-out-everywhere for push; re-sign-in on each device re-registers;
- C's delta: ordinary sign-out becomes scope **`local`** (one device), and **"Sign out of all devices"** is the
  distinct action that calls `revoke_all_push_bindings()` first. **This is the one product change** in the client
  delta; it is the owner's to confirm.
New cases for 198: **S13** a device whose session was ended by another device's global sign-out has its row revoked
and hash cleared at that moment; **S14** it signs back in on a new session → rule 2 re-activates with its genuine
secret, never the old hash; an old JWT cannot; **S15** the device that changed the password signs out globally then
re-registers on a new session — the +2 s margin must not be a hard failure (client retry succeeds); **S16** a
registration racing the trigger loses with 42501 and leaves no half-written row.

## 4f. Scope of the session-age check (D, 2026-09-15)
The check in §2d/§4 applies **only to acts that create or activate a binding** (the verb's rules 1/2/3/5, and the
table guard on INSERT / UPDATE-to-active / DELETE). **`revoke_all_push_bindings()` and `notify.revoke_push_token`
must succeed from any authenticated session**, including one that predates the epoch: C's reset-password flow calls
`revoke_all` from the device's pre-change session immediately after `updateUser` bumps the epoch, and a refusal there
(logged, never blocking) would silently lose the verb's fast path in exactly the flow that matters. Revocation can
only reduce exposure, so it needs no session-age proof. Asserted in 198.

## 8. A-131-K2 amendment (2026-09-15, after the owner approved K-2; D's K2-S1 / K2-S2)
With ordinary sign-out = this device only, §2's live-session trigger covered a signed-out device only when it was the
user's LAST live session. Amendment on `fix/131-session-bound-push @ f72e2d3`: `public.push_tokens.session_id` (not
client-readable or -writable) is stamped by the verb on every success path and by the row guard on the client INSERT /
re-activation path; the sessions trigger takes the per-user advisory lock, keeps the last-live-session global
invalidation, then revokes the deleted sessions' own bindings (reason `signed_out`, proof kept, no epoch). K2-S2:
`kernel.push_session_predates_epoch` reads the session claim first — a claim naming a deleted session fails closed even
on a never-bumped account; no claim on a never-bumped account stays untouched (J2). P6 now reads: a device's sign-out
(client revoke OR its session's deletion) ends delivery to that device; sign-out-everywhere / password change / last
session end everything and bump the epoch. S-13 (shared install after global sign-out → 42501 for another account) is
deliberate (D): clearing the proof is what kills a plant; recovery = original account re-login + this-device sign-out,
support unbind, or reinstall. 198 → plan 56 with two negative controls; census unchanged; rollback drops the column.
**F-131-K2a (D, MEDIUM, found in the re-review of `f72e2d3`; fixed at the next head):** the session-end revoke wrote
`revoked_reason = 'signed_out'`, which is 128's rule-5 precondition — a hash-less pre-128 row re-activated by an old build and
then revoked by its session's end became claimable (`rebound_legacy`) by any account that knew the token string. Fix: that
path writes `'session_ended'` and `revoked_at = now()`; rule 3 hand-off ignores the reason (K1b/K1c unchanged); 129's client
revoke keeps `'signed_out'`. 198 P1–P4 with the negative control (`'signed_out'` on that path → claimable). **Product note
(D, by design, recorded):** expired-session cleanup revokes that device's binding with the proof kept; a dormant user whose
session is cleaned up loses push until the next launch refreshes it; the epoch does not move. **Cosmetic (LOW, open):** a
deleted session is refused with the contract's frozen text "session predates a credential change"; the client's neutral
copy covers it; changing the server text is a contract change and is not made here.
