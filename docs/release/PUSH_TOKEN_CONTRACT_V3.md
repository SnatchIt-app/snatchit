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
Same signature as v2. Reply `{token_id, outcome, platform, contract_version, challenge?}` where **`contract_version` is `2` on
`registered` / `refreshed` replies and `3` only on replies that carry `challenge`** (and on every reply of the confirm verb).
Reason (D, V3-1): the shipped v2 client (`src/lib/push/registerToken.ts:97`) rejects ANY reply whose `contract_version` is not 2
as `contract_mismatch`, terminal until a new build; stamping 3 everywhere would silently stop push registration for every build
that has not updated. With this rule an old build behaves exactly as today on the cases v3 does not change and only loses the
cross-account case it could never complete (it sees a `3` there and goes terminal, as it did on the v2 42501). **The v3 client
accepts `contract_version ∈ {2, 3}` on `registered` / `refreshed`, and requires `3` wherever `challenge` is present and on the
confirm verb.** Production rollout sentence: a v3 server with the installed base on v2 is NOT a push outage under this rule;
without it, it would be one for everyone who has not updated.

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
One open challenge per (token, requesting_user). A new request while one is open **re-issues the nonce on the same row** (only
the hash is stored, so the same nonce cannot be re-sent; attempts are kept, expiry refreshed, mode as requested). **An open
challenge whose attempts are exhausted or which has expired is consumed and a fresh one issued on the next request** (D, P3-1) —
no dead-end while a stale row lives. Expired and consumed rows are swept by the notify drain (`> 24 h`).

## 4. `public.confirm_push_token_challenge(p_challenge_id uuid, p_nonce text) → jsonb`
Reply `{outcome, token_id, contract_version: 3}`. The bind happens **here**, atomically, only when all hold:
- caller = `requesting_user` **and** the caller's JWT `session_id` = `requesting_session` (C3);
- the challenge is unexpired, unconsumed, `attempts < 5`; `sha256(p_nonce) = nonce_hash`;
- the caller's session does not predate a credential change (131).
On success: the row's `user_id` := caller, `is_active` := true, `revoked_*` := null, `device_secret_hash` := `secret_hash` (C5 —
the stored proof is superseded by the proving device's), `session_id` := caller's session, `last_used` := now(); the previous
owner's binding on this token ends (they receive the notice `security_device_rebound` **in the notification centre** — an
`in_app` template, no push and no email row (N1: email is owner-gated); never push, since their push is exactly what moved —
deduped per token per day); challenge consumed.
**Reply shape, explicit (D, H): among 200 replies only `outcome: 'rebound'` is a bind.** The other 200 replies are refusals:
`{outcome: 'nonce_mismatch', attempts_left, token_id, contract_version: 3}` (a raise would roll back the attempt count),
`{outcome: 'challenge_consumed', …}` (the fifth mismatch; terminal for that challenge — request a new one), and
`{outcome: 'stale_nonce', …}` (the echoed nonce is the one superseded by a re-issue: free, no attempt counted, no bind — the
client waits for the current push). The client branches on `outcome` before treating any reply as success; errors are refusals:

| error | code |
|---|---|
| `not_authenticated` | 42501 |
| `insufficient_privilege: challenge belongs to another session` | 42501 |
| `precondition_failed: challenge expired` / `challenge consumed` / `challenge attempts exhausted` | P0001 |
| `insufficient_privilege: session predates a credential change` | 42501 |

## 5. Delivery and the fallback
- **Transport (B's component):** the issuing verb (`notify.issue_push_token_challenge`, §10) generates the nonce, stores only its
  hash, and calls `send-push` ONCE through pg_net with 133's Vault `project_url` and the Vault service-role bearer (the existing
  032/087 pattern): body `{kind: 'push_token_challenge', challenge_id, nonce, user_id}`. The plaintext nonce exists only in that one
  request (pg_net's queue row is service-internal and deleted on send; `net._http_response` never stores request bodies) and in the
  push itself. Where Vault `project_url` is absent (CI, the harness) the post is a guarded no-op and the challenge row still exists
  for the pgTAP tests. `send-push` reads the challenge **through `notify.get_push_token_challenge(p_challenge_id)`** (service_role EXECUTE; returns the
  token to address, `token_id`, `requesting_user`, platform, mode, expires_at, confirmed_at, consumed_at, attempts — no owner
  identity, secret or nonce hash; notify tables carry no service_role grants by design). The edge refuses when the request body's
  `user_id` is not `requesting_user` (409) and keys its own rate limit on (`token_id`, `requesting_user`); neither field ever reaches
  the push payload or a log line. It refuses a missing/expired/confirmed/consumed/exhausted challenge, sends via the **Expo push API** (silent = `_contentAvailable: true`, no title/body,
  data `{type: 'push_token_challenge', challenge_id, nonce}`; visible = title/body carrying the code + "Never share this code", data
  WITHOUT the nonce), records the result through `record_push_token_challenge_delivery`, and never logs the payload. **The challenge
  push is token-addressed** (the token may belong to ANOTHER account): `send-push` accepts a token-addressed send for this kind only
  and reveals nothing about the row's current owner in the payload or the logs (no user id, no email, no device name).
- **Nonce format by mode (pinned):** silent = 32 CSPRNG bytes, base64url (43 chars); visible = a 6-digit decimal code drawn from
  CSPRNG (the code IS the nonce; §4 compares `sha256(presented)` to `nonce_hash` in both modes). Every re-issue (re-request, or a
  switch to visible) rotates the nonce and keeps the previous hash for ONE generation (`prev_nonce_hash`): a late push carrying
  the superseded nonce answers `stale_nonce` at no cost (D, M).
- **Foreground-only delivery:** the client echoes from its foreground notification handler. No `UIBackgroundModes:
  remote-notification` (build-affecting config, out of scope). A backgrounded app re-requests on foreground; the same open challenge
  row is re-issued with a ROTATED nonce (silent) or code (visible) — the previous hash is kept one generation, so a late echo of
  the superseded value is `stale_nonce` — until it expires. The 60 s fallback timer runs only while foregrounded.
- The nonce is never logged anywhere (edge, DB, Sentry): B's suite carries a mutant that logs it, which must fail.
- Fallback (iOS silent-push throttling): if no push arrives within 60 s the client calls
  `public.request_push_token_challenge(p_token text, p_device_secret text, p_mode text default 'visible') → jsonb` — it carries the
  device secret like the register verb (D, V3-3), so a challenge it creates always has `secret_hash`; if an open challenge exists for
  (token, caller) it switches that row to visible (same `secret_hash`, nonce re-issued as the code), otherwise it creates one
  (same rules as `register_push_token`'s `challenge_required` branch, incl. the 131 session check). **Reply shape (pinned):**
  `{token_id, outcome: 'challenge_required', contract_version: 3, challenge: {id, mode, expires_in_s}}` — identical to the register
  verb's challenge reply; the client takes `challenge.id` from it (after P3-1 a fresh challenge has a NEW id). The row is switched
  to `mode := 'visible'` with the nonce re-issued as a 6-digit CSPRNG code (the code IS the nonce for §4): the push is an alert with the copy **"Snatch It
  verification code: 123456. Never share this code."** The user types it in Settings › Notifications; the client echoes via §4.
  Bounds of the visible code (D, V3-2): 10^6 space, the **same 5-attempt counter and 5-minute expiry as the silent path** (one
  counter per challenge row, shared across modes), and §5's rate limits on issuance — a wrong code counts an attempt; the fifth
  wrong attempt consumes the challenge and the client must request a new one (rate-limited).
- Rate limits (C6): the verbs are the authority — **5 challenge requests per user per 10 min, and 3 per (token, requesting user) per
  10 min** (`check_rate_limit` keys `push_challenge_user`, `push_challenge_token:<token_id>:<uid>`); counting per (token, user) means
  nobody who merely knows a token string can burn the rightful device's allowance (D, V3-4). Beyond that P0001 `too many challenge
  requests`. The edge re-checks with its own namespace (`push_challenge_edge_user:<uid>` 5/10 min,
  `push_challenge_edge_token:<token_id>:<uid>` 3/10 min) so it never consumes the verbs' budget.

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

**Device secret: generated once per install; rotation does not exist (carried forward from V2 §41/§62, 2026-09-17, D + A).**
V2's rule stands under v3 and is restated here so it does not survive only in a superseded file: the client generates the device
secret once per install and re-plants that same secret whenever it registers, including after a server-side proof clear
(`signed_out_everywhere`, password change, support unbind). Observed on the sandbox 2026-09-17: after row 17's global
invalidation cleared `device_secret_hash`, the first sign-in on Build 18 re-registered on the new session with the identical
hash — conformant, not a defect. The v3 reason the rule must stay: (a) the secret is no longer a takeover credential — under
135 a cross-account register is `challenge_required` regardless of hash (D's C1a with a hash, C1b without), and `confirm`
supersedes the stored proof with the proving device's, so a stale secret gains an attacker nothing without the nonce delivered
to the device; (b) rotating the secret would orphan an in-flight challenge, whose `secret_hash` was captured at issue time —
a successful confirm would then store a proof the device no longer holds, a silent mismatch of exactly the class v3 removes.

**The previous owner's notice on mobile (136, batch 1 item 2, 2026-09-17).** `security_device_rebound` is enqueued for the
previous owner (135 §5) as in-app only (no delivery row; N1). The mobile client reads it through
`public.get_my_security_notices()` → `{id, type_key, title, body, created_at, read_at}` (owner-scoped, security types only,
newest first, rendered server-side by `notify.get_inbox` from the highest `notify.template` version — 136's v2 carries the
owner-corrected, D-verified copy: "A device stopped receiving your notifications" / "A device that was getting notifications
for this account is now registered to a different account. If that was you signing in to another account, there's nothing to
do. If not, sign out of all devices.") and acknowledges it with `public.mark_security_notices_read(p_ids uuid[]) → integer`
(own security ids only; foreign or non-security ids → 0). The client carries **no title/body strings**; it keys its two
actions on `type_key = 'security_device_rebound'`: "Sign out of all devices" (K-2, `signOutAllDevices`; it does not undo the
rebind — the row now belongs to the new owner — and the copy must never imply it does) and "Dismiss" (`mark_…_read`).
Never on the shared login screen. `{{device_name}}` is not rendered: on the register path it is text the CLAIMING party
supplies. Dedupe is one notice per token per UTC day, so the copy is present-tense and never "just". Absent migration →
PGRST202 → the client treats it as "no notices", never an error.

## 8. Support
`public.unbind_push_token(text)` (service_role) stays for the cases proof cannot reach (a lost or destroyed device, a user without
a working handset). Runbook: B drafts, D reviews. It is no longer the only route for the account-switch case (acceptance evidence,
brief end).

## 9. What v3 does not close (D §12, restated)
An attacker holding the victim's *unlocked* phone at bind time (the victim takes the binding back afterwards by proof); an attacker
who knows the new password; notification content on a lock screen. **And (D, V3-5):** a token whose row was deleted before 135 ships
has no history, so the first bind after b2 is `registered` (with the registering device's proof, no challenge) — self-correcting: the
genuine device's next registration is `challenge_required`, it proves, and reclaims by C5; the window is one launch of the genuine
device.

## 10. Objects (migration `135_push_token_proof_of_possession.sql` — numbered: it owns its objects and redefines only 128/131 bodies)
Table `notify.push_token_challenges` (RLS on, no policies, no client grants) · functions `public.request_push_token_challenge(text, text)`,
`public.confirm_push_token_challenge(uuid, text)` (authenticated EXECUTE), `notify.issue_push_token_challenge(...)` (internal),
`notify.get_push_token_challenge(uuid)` and `notify.record_push_token_challenge_delivery(uuid, text, text, text)` (service_role EXECUTE, for
`send-push`; delivery outcomes `sent` | `rejected` | `error`),
`public.guard_push_token_client_delete()` + trigger · `register_push_token` re-created (v3 body) · notify template
`security_device_rebound` (in-app) · pgTAP 202 · rollback restores the 131 verb and drops the new objects. **Send paths need no change:** a pending claim is a challenge row, never an unconfirmed `push_tokens` row, so `send-push`'s
`user_id + is_active` select stays as it is (C4 by construction). Census deltas at integration, stated as CI asserts them: **public
Gate-2: tables +0, functions +3 (`request_push_token_challenge`, `confirm_push_token_challenge`, `guard_push_token_client_delete`),
policies +0, triggers +1** (the client-DELETE guard); five-schema routines +3 (`notify.issue_push_token_challenge`,
`notify.get_push_token_challenge`, `notify.record_push_token_challenge_delivery`) → 303; five-schema relations +1 (the notify
table, outside the public census); notify registry +1 type, +1 in_app template.
Manifest: 3 public function rows (2 authenticated-execute, 1 no-client-execute); `expected_grants.txt` unchanged (no client grant on
the notify table).
