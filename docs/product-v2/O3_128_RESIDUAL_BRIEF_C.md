# O-3 — migration 128 residual risk: C's brief (client side), 2026-09-15

Owner ask: exact attack, required access, affected users, persistence after session revocation, remaining
exposure after cold-launch registration, safest alternative with its cost. A's brief
(`docs/release/O3_128_RESIDUAL_DECISION_BRIEF.md`) covers all six; this verifies it against
`supabase/migrations/128_register_push_token_secure_rebind.sql` @ `cf73d7b`, pgTAP 195 (B5/B6, E2, H1) and the
client at `d90db6b`, and states where the client changes the picture and where C differs. **For the production
release decision only. Sandbox and build authorisations (O-1/O-2) test 128 and accept nothing.**

## 1. Exact attack — as A §1, confirmed in the SQL
Rule 2 (`v_row_user = v_uid`) runs `device_secret_hash = coalesce(device_secret_hash, v_hash)`: the first secret
presented for a NULL-hash row sticks, whoever presents it. Rule 3 rebinds to any account whose presented secret
hashes to the stored value, with no time bound. So: session-as-victim → plant → later, from the attacker's own
account, claim. Client fact: after a plant the genuine device is answered `refreshed` (195 H1: "the reply cannot
reveal the mismatch"); the client asserts only what the reply says, and its recovery path does not fire (it needs a
freshly generated secret, and the device still holds its own). The device has no signal and does nothing.

## 2. Required attacker access
An authenticated session as the victim. Token knowledge alone is closed by 128 (rule 4 refuses; rule 5 is gated
four ways and sunsets). Rows: owner insert/select/update/delete policies exist (`000_baseline_schema.sql:902-917`),
so a session holder can also delete the victim's row and rebind under rule 1 — A §3's point stands.

## 3. Affected users
Every `push_tokens` row with a NULL hash: all rows at apply time, plus every row written afterwards by a build that
does not call the verb (Build 16 and the App Store 1.0 build: `registerLegacy` is insert-only and `legacyTouch`
writes `last_used`/`is_active` only). Production count unmeasured; not queried (owner-authorised reads only).

## 4. Persistence after session revocation
Persists. A planted hash and a completed claim are row facts. Sign-out, password reset and global session
revocation do not touch `push_tokens`. What does: the owner deleting their own row (before the claim only —
and they have no signal to act on), `unbind_push_token` (service_role, support), or the 128 rollback (drops the
column, clearing every hash, genuine ones included).

## 5. Remaining exposure after cold-launch registration
- The every-cold-launch clause (`d90db6b`) sets the genuine hash only on rows that are still NULL when the device
  first launches the new build. It does not undo a plant made earlier and cannot detect one (coalesce keeps the
  planted hash; the reply is `refreshed`). "Bounded by the cold-launch clause" is true of the plant *window* for
  devices that upgrade, not of a plant that already happened.
- Rows from devices that never upgrade stay plantable with **no sunset**: rule 2 has no epoch or sunset predicate;
  the 90-day sunset bounds rule 5 only.
- NULL-hash monitoring counts the legacy tail; a planted row is indistinguishable from a healed one. It detects
  exposure. It prevents nothing.

## 6. Where C differs from A §3 ("adds no capability")
The end state equals delete-and-rebind, but the plant adds a **deferred, signal-less trigger**: the capture can be
fired weeks after the compromise, timed to an auction close or a transfer deadline, with nothing for the victim to
notice until it fires. Delete-and-rebind must be executed during the compromise, and the victim's next cold launch
reveals it (rule 4 → the terminal remedy copy). That deferral is a capability; the incremental risk is not zero.
Likelihood low (needs a session); impact: silenced outbid/receipt notices at a chosen moment plus attacker-
generated pushes on the victim's phone; recovery support-only.

## 7. Safest alternative and its cost
None prevents capture by a session holder during the compromise. What can be closed is the deferred, silent part:
- **(a) C proposes — `mismatch` outcome on rule 2 (server, A; client, C).** When the caller's own row already
  carries a hash that is not the presented one, reply a distinct outcome (owner-only; discloses nothing about
  other accounts) instead of `refreshed`. The client then deletes its own row and re-registers (rule 1) — the
  existing recovery path, with the server's signal replacing the client's three-way guess gate. Combined with
  every-cold-launch registration a plant now lives only until the victim's next cold launch, and a claim that beats
  it is visible as rule 4. Trade-off: an owner-only match oracle, rate-limited 20/600 s against a 32-byte CSPRNG
  secret; a session holder can plant anyway, so it gains them nothing. Cost: A ~1 h (branch, flip 195 H1, negative
  control) · D ~1 h delta review · C ~1 h (route `mismatch` → `deleteOwn` → register; tests). It changes the v2
  reply vocabulary, so it must be in the freeze text or it is v3.
- **(b) A §7 — rebind audit + previous-owner in-app notice** (~2–3 h A, ~1 h D; no client change).
- **(c) A §7 — sunset the plant path** (~30 min A) closes §5's "no sunset".
All three: about half a day of A, ~2 h of D, ~1 h of C. They fit this candidate only if A starts Tue and D's delta
review lands before the Wed AM freeze; otherwise next candidate, with the residual disclosed in the packet.

## 8. C's recommendation
Do not accept on the "adds no capability" argument. Accept for production only as an explicit written risk
acceptance that names §6, and take (a)+(b)+(c) in this candidate if they fit before the freeze — else next
candidate with disclosure. D's independent disposition governs if it differs; requested 2026-09-15.
