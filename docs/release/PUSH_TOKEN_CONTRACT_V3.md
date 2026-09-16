# Push token contract v3 — proof of possession (DRAFT for D's review, A, 2026-09-16)

Status: **DRAFT.** Supersedes `PUSH_TOKEN_CONTRACT_V2.md` for the production-gate candidate once D reviews it (b2, owner
decision 2026-09-16, brief §13). Development against this draft is authorized; nothing here is applied anywhere. Where v2
and v3 differ, v3 wins for the new build; a v2 client keeps working (see §7).

## 1. The property
A push binding becomes deliverable for an account only after the push provider proves the registering device holds the
token: the server sends a one-time nonce **to that token**; the device echoes it. Consequences the client must expect:
- a bind that changes the token's owner never activates immediately;
- the current binding (if any) stays deliverable until the proof lands (nothing is denied by a mere claim);
- a device that was redirected earlier can take its binding back by proof, without support;
- client rows are never deleted: a client DELETE becomes a revoke with history.

## 2. `public.register_push_token(p_token text, p_platform text, p_device_secret text, p_device_name text default null) → jsonb`
Same signature as v2. Reply `{token_id, outcome, platform, contract_version: 3, challenge?}`.

| outcome | when | effect | client next step |
|---|---|---|---|
| `registered` | no row has ever carried this token (no history) | row created, active, proof = hash(secret), session stamped | none |
| `refreshed` | the caller already owns the row (any state except a pending cross-account challenge by the caller — see below) | re-activated, `session_id` re-stamped, proof `coalesce(existing, hash)` (v2 rule 2) | none |
| **`challenge_required`** | the row is another account's (v2 rules 3/5, active or revoked, proof or not), **or** the token has history under another account (v2 rule 1 with a tombstone) | **nothing changes on the row**; a challenge row is created (§3); the nonce is dispatched to the token via `send-push`; reply carries `challenge: {id, mode: 'silent', expires_in_s: 300}` | wait for the push; echo via §4; fallback §5 |
| 42501 `insufficient_privilege: session predates a credential change` | v2/131 | unchanged | re-login |
| P0001 `precondition_failed: …` | v2 preconditions + `too many challenge requests` (§6) | unchanged | as v2 |

The v2 outcomes `rebound` and `rebound_legacy` no longer occur from this verb: every ownership change goes through a
confirmed challenge (§4) and reports `rebound` **from the confirm verb**. The v2 error `token is bound to another account`
is gone: that state now answers `challenge_required`.

## 3. Challenge row — `notify.push_token_challenges` (not PostgREST-exposed; no client grants)
`id uuid pk · token_id uuid → push_tokens · requesting_user uuid · requesting_session uuid (from the JWT session_id; required) ·
nonce_hash text (sha256 of a 32-byte CSPRNG nonce; the nonce itself is never stored) · mode text ('silent' | 'visible') ·
purpose text ('rebind') · secret_hash text (hash of the requester's device secret, applied on confirm) · platform, device_name ·
expires_at timestamptz (now() + 5 min) · attempts int (max 5) · confirmed_at · consumed_at · created_at · **delivery: dispatched_at,
delivery_outcome text, provider_message_id text, delivery_error text** (written by `notify.record_push_token_challenge_delivery(p_challenge_id uuid,
p_outcome text, p_provider_message_id text, p_error text)`, service_role — a challenge is a control message, not an outbox notification,
so it never touches `notify.delivery`/`record_delivery_result`)`.
One open challenge per (token, requesting_user); a new request while one is open re-dispatches the same challenge (no new nonce)
until it expires. Expired and consumed rows are swept by the notify drain (`> 24 h`).

## 4. `public.confirm_push_token_challenge(p_challenge_id uuid, p_nonce text) → jsonb`
Reply `{outcome, token_id, contract_version: 3}`. The bind happens **here**, atomically, only when all hold:
- caller = `requesting_user` **and** the caller's JWT `session_id` = `requesting_session` (C3);
- the challenge is unexpired, unconsumed, `attempts < 5`; `sha256(p_nonce) = nonce_hash`;
- the caller's session does not predate a credential change (131).
On success: the row's `user_id` := caller, `is_active` := true, `revoked_*` := null, `device_secret_hash` := `secret_hash` (C5 —
the stored proof is superseded by the proving device's), `session_id` := caller's session, `last_used` := now(); the previous
owner's binding on this token ends (they receive an in-app notice `security_device_rebound`, never a push); challenge consumed.
Outcome `rebound`. Every other path writes nothing except `attempts += 1`:

| error | code |
|---|---|
| `not_authenticated` | 42501 |
| `insufficient_privilege: challenge belongs to another session` | 42501 |
| `precondition_failed: challenge expired` / `challenge consumed` / `challenge attempts exhausted` | P0001 |
| `precondition_failed: nonce mismatch` | P0001 (attempts += 1) |
| `insufficient_privilege: session predates a credential change` | 42501 |

## 5. Delivery and the fallback
- **Transport (B's component):** the issuing verb (`notify.issue_push_token_challenge`, §10) generates the nonce, stores only its
  hash, and calls `send-push` ONCE through pg_net with 133's Vault `project_url` and the Vault service-role bearer (the existing
  032/087 pattern): body `{kind: 'push_token_challenge', challenge_id, nonce, user_id}`. The plaintext nonce exists only in that one
  request (pg_net's queue row is service-internal and deleted on send; `net._http_response` never stores request bodies) and in the
  push itself. Where Vault `project_url` is absent (CI, the harness) the post is a guarded no-op and the challenge row still exists
  for the pgTAP tests. `send-push` re-reads the challenge row by id (token, mode, expires_at, confirmed_at, attempts), refuses a
  missing/expired/confirmed/exhausted challenge, sends via the **Expo push API** (silent = `_contentAvailable: true`, no title/body,
  data `{type: 'push_token_challenge', challenge_id, nonce}`; visible = title/body carrying the code + "Never share this code", data
  WITHOUT the nonce), records the result through `record_push_token_challenge_delivery`, and never logs the payload.
- **Nonce format by mode (pinned):** silent = 32 CSPRNG bytes, base64url (43 chars); visible = a 6-digit decimal code drawn from
  CSPRNG (the code IS the nonce; §4 compares `sha256(presented)` to `nonce_hash` in both modes). Switching an open challenge to
  visible re-issues the nonce (the silent one is invalidated).
- **Foreground-only delivery:** the client echoes from its foreground notification handler. No `UIBackgroundModes:
  remote-notification` (build-affecting config, out of scope). A backgrounded app re-requests on foreground; the same open challenge
  re-dispatches (silent: same nonce; visible: same code) until it expires. The 60 s fallback timer runs only while foregrounded.
- The nonce is never logged anywhere (edge, DB, Sentry): B's suite carries a mutant that logs it, which must fail.
- Fallback (iOS silent-push throttling): if no push arrives within 60 s the client calls
  `public.request_push_token_challenge(p_token text, p_mode text default 'visible') → jsonb` (same challenge row, `mode := 'visible'`,
  nonce re-issued as a 6-digit CSPRNG code — the code IS the nonce for §4): the push is an alert with the copy **"Snatch It
  verification code: 123456. Never share this code."** The user types it in Settings › Notifications; the client echoes via §4.
  A wrong code counts an attempt.
- Rate limits (C6): the verbs are the authority — **5 challenge requests per user per 10 min, 3 per token per 10 min** (`check_rate_limit`
  keys `push_challenge_user`, `push_challenge_token`); beyond that P0001 `too many challenge requests`. The edge re-checks with its own
  namespace (`push_challenge_edge_user:<uid>` 5/10 min, `push_challenge_edge_token:<token_id>` 3/10 min) so it never consumes the
  verbs' budget.

## 6. Table access (client roles) — C2
- SELECT column-scoped as v2 (no `device_secret_hash`, no `session_id`).
- UPDATE column-scoped as v2 (`platform, device_name, last_used, is_active`) — a client cannot re-activate a row it does not own
  (RLS), and re-activating its own row is a `refreshed`-equivalent (guard stamps the session).
- **DELETE by a client never removes a row:** a `BEFORE DELETE` trigger on the client path turns it into a revoke
  (`is_active=false, revoked_reason='deleted_by_client', revoked_at=now()`, proof kept) and suppresses the delete. History survives,
  so a later fresh bind of that token by another account is `challenge_required`, never `registered`.
- **INSERT by a client** is allowed only for a token with no history (the unique index refuses everything else); the row guard
  stamps the session (131). A v2/v1 client that inserts a token with history gets 23505 and stays unregistered until it upgrades.

## 7. Compatibility
- **v2 client (build 17) on a v3 server:** `registered`/`refreshed` unchanged; where v2 got 42501 "bound to another account" it now
  gets `challenge_required` — an unknown outcome to v2, which treats it as a non-terminal failure and retries on the next cold
  launch; the challenge is dispatched each time (bounded by §5 rates) and never confirmed. Old builds therefore stay unregistered
  on a token with foreign history, without error loops beyond the rate limit. Sign-out revoke (129) unchanged.
- **v3 client on a v2 server:** `contract_version: 2` in the reply → `contract_mismatch`, terminal until a new build (as v2 specified).
- `public.revoke_push_token`, `public.revoke_all_push_bindings`, 131's session rules: unchanged.

## 8. Support
`public.unbind_push_token(text)` (service_role) stays for the cases proof cannot reach (a lost or destroyed device, a user without
a working handset). Runbook: B drafts, D reviews. It is no longer the only route for the account-switch case (acceptance evidence,
brief end).

## 9. What v3 does not close (D §12, restated)
An attacker holding the victim's *unlocked* phone at bind time (the victim takes the binding back afterwards by proof); an attacker
who knows the new password; notification content on a lock screen.

## 10. Objects (migration `135_push_token_proof_of_possession.sql` — numbered: it owns its objects and redefines only 128/131 bodies)
Table `notify.push_token_challenges` (RLS on, no policies, no client grants) · functions `public.request_push_token_challenge(text, text)`,
`public.confirm_push_token_challenge(uuid, text)` (authenticated EXECUTE), `notify.issue_push_token_challenge(...)` (internal),
`notify.record_push_token_challenge_delivery(uuid, text, text, text)` (service_role EXECUTE, for `send-push`),
`public.guard_push_token_client_delete()` + trigger · `register_push_token` re-created (v3 body) · notify template
`security_device_rebound` (in-app) · pgTAP 202 · rollback restores the 131 verb and drops the new objects. **Send paths need no change:** a pending claim is a challenge row, never an unconfirmed `push_tokens` row, so `send-push`'s
`user_id + is_active` select stays as it is (C4 by construction). Census deltas at integration: tables +1 (notify), functions +5
(3 public + 2 notify), triggers +1 (public); manifest rows accordingly.
