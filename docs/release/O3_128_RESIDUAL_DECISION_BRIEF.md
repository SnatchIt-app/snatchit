# O-3 — migration 128 residual risk: decision brief (A, 2026-09-15)

For the owner's **production-release** decision. Separate from the sandbox/build authorizations, which test 128
and accept nothing. D's independent disposition is attached below when received; A's reasoning must not be the
only reasoning on file.

## 1. The exact attack (plant-then-claim on a legacy row)
1. Victim V has a `push_tokens` row with `device_secret_hash IS NULL` — every row that exists at 128 apply, and
   every row written afterwards by a client that has not yet upgraded to the 128-aware build.
2. Attacker A, **holding an authenticated session as V**, calls
   `register_push_token(V_token, platform, A_SECRET)`. Rule 2 (own row) executes
   `device_secret_hash = coalesce(NULL, sha256(A_SECRET))` — A's hash is planted on V's still-V-owned row.
   (V's token string is readable from V's own session, so nothing beyond the session is needed.)
3. Later, from **A's own account**, A calls `register_push_token(V_token, platform, A_SECRET)`. Rule 3 (hash
   matches) rebinds the row to A. V's device now receives A's account's notifications; V's account has none.
4. V's genuine client next registers with V's real secret → rule 4 → **42501, refused**. V cannot delete the row
   either (RLS: it is A's now). V is locked out of push until support runs `unbind_push_token`.

## 2. Required attacker access
An **authenticated session as the victim** (stolen access/refresh token, or hands on an unlocked signed-in
device). Token knowledge alone is **not** sufficient — that was F7's original threat and 128 closes it.

## 3. What a session-holder can do anyway — the point that frames the decision
The victim's session is the victim, as far as the database can tell. With it, an attacker can capture the device
binding by paths that **no hash design closes** and that are **not** the residual under discussion:
- **delete + rebind:** `DELETE` V's own row (RLS owner-delete — the documented recovery path), then register the
  token from A's account: rule 1, fresh bind, A's secret. Works on rows **with** a genuine hash too.
- **revoke + rule 5:** sign V out (`revoke_push_token`, `signed_out`), then claim from A's account under rule 5
  within 30 days — legacy rows only.
Each ends in the same state as §1 step 4. So the residual **adds no capability** a session-holder lacks; closing
plant-then-claim in isolation would not reduce what a compromised session can do to the push binding.
What 128 does guarantee: an attacker **without** a session — one who merely knows or can enumerate a token —
cannot take a binding that carries a genuine hash, cannot take an active legacy binding, and cannot forge the
"revoked legacy" precondition (V4/V11 closed).

## 4. Affected users
All users with a legacy (NULL-hash) row: **every existing registration at apply time** plus late-upgrading
clients. Production `push_tokens` count is **unmeasured** (read-only count needs owner authorization; sandbox has
1). Under §3 the population that matters is "users whose session is compromised", for whom push capture is one
of several harms of that compromise (orders, tickets, transfers are readable with the same session).

## 5. Persistence after session revocation / password reset
**Persists.** A planted hash and a completed rebind are row facts; revoking V's sessions or resetting V's password
does not touch `push_tokens`. Recovery is support-only (`unbind_push_token`, service_role) once the row is A's.
Before A's claim (planted but not yet claimed), V can still recover by deleting the row and re-registering — but
V has no signal that anything was planted.

## 6. Remaining exposure after cold-launch registration (C has built it)
- A genuine client that registers **before** any planting stores V's real hash; from then on §1 is closed for
  that row (coalesce keeps the genuine hash; rule 3 needs V's secret).
- Registration **after** planting does **not** repair it: coalesce keeps the planted hash. So cold-launch
  registration bounds the *race* — the window between 128 apply and each device's first launch on the new build
  — and does nothing for a row already planted. For an inactive user that window can be weeks.
- Rows never touched by an upgraded client stay legacy until the 90-day sunset, after which rule 5 closes;
  §1 (rule 2 planting + rule 3 claim) has **no sunset** — a planted legacy row is claimable indefinitely.
- **Monitoring** (a service_role count of NULL-hash rows) shows the size of the legacy tail. It **detects
  exposure; it does not prevent capture**, and a planted hash is indistinguishable from a genuine one, so
  planting itself is invisible to it.

## 7. Safest alternative, and its cost
Prevention against a session-holder is not available (§3). What *is* available is turning silent capture into
detected, recoverable capture:
- **Rebind audit + previous-owner notice** (server, A): every cross-account bind (rules 3/5, and a rule-1 bind of
  a token whose previous row was deleted within N days) writes an audit row `(token, previous_user, new_user,
  rule, at)` and enqueues an **in-app** (not push) `security_device_rebound` notice to the previous owner —
  "This device was re-registered to another account. If this wasn't you, contact support." The victim learns;
  support has the row to act on. **~2–3 h A + ~1 h D review**; one new `notify` template; no client change
  (C's terminal 42501 branch already says "contact support").
- **Sunset the plant path too** (server, A): rule 2 stops planting on a NULL-hash row after the 90-day sunset,
  so a never-upgraded legacy row becomes unbindable by anyone except support — closes §6's "indefinitely".
  **~30 min**, one predicate + one assertion.
Together they cost about half a day and can ride in this candidate if D's pass 3 is clean; otherwise the next.

## 8. A's recommendation — REVISED after D's disposition (§9)
D's disposition arrived independently before my request and **rejects the brief as worded**: my §3 understated
the harm. Beyond redirect/lockout, a session-holder can bind **the attacker's own phone to the victim's account**
(rule 3 with the attacker's secret, or the still-granted direct INSERT), so the victim's notifications are
**forwarded** to the attacker — content exfiltration, not only denial — and every such path survives password
reset and sign-out-everywhere because nothing in the schema ties bindings to sessions. That is the residual the
owner is being asked about, restated accurately:

> **Session compromise ⇒ redirect and forwarding of the victim's push notifications to attacker-controlled
> devices, persistent after credential/session revocation until support intervenes.** 128 does not create it
> and does not close it; 128 closes the token-knowledge-only capture (F7).

A concurs with D's options and recommendation:
- **Freeze v2 and ship 128 to sandbox and the candidate build now** — a net improvement; testing is not acceptance.
- **Production acceptance is the owner's choice between (a) and (b)**: accept the residual as restated, or require
  **(b) session-bound bindings** — revoke the user's push bindings and clear hashes on password change /
  sign-out-everywhere (server-only, no v2 shape change; D estimates **1–2 working days, uncertain**, touching
  auth-hook design, which is itself an owner-approval surface per CLAUDE.md). (b) would not fit this sprint's
  notification chain without moving the candidate; it can be a production gate rather than a candidate gate.
- **(c) provider-side proof** (a data-only nonce push required for every bind) is the real prevention against an
  attacker without the victim's phone: client v3, **3–4 working days, next candidate.**
- The §7 audit + previous-owner notice remain worthwhile as **detection**; they do not change the acceptance
  question and A withdraws them from this candidate unless the owner wants detection before (b) exists.
Monitoring is not protective and is not offered as such.

### A's note on D's §7 judgement
D's correction that a plant adds **dormancy** (survives remediation; activates later with no session) rather than
capability is adopted into §8 above. D recommends taking the rule-2 adoption sunset (~30 min) in this candidate;
**A declines it for this candidate** and queues it: it re-opens the verb the day before the freeze for a marginal
gain (it bounds *when* a plant can be made, not when a dormant plant can be activated), and it leaves late-upgrading
devices permanently unproven so their legitimate handover needs support. The audit + notice is likewise queued.
Neither changes the acceptance question, which is (a) vs (b).

## 9. D's independent disposition (verbatim attachment, 2026-09-15; evidence `review/d-release-sprint @ 5cae354+`, probes `probe_128_o3_attacks.sql`, `probe_128_o3_delete_register.sql`, `probe_128_o3_sessionless.sql`, all run at `cf73d7b`)

> INDEPENDENT DISPOSITION — O-3 (Claude D, 2026-09-15)
>
> Recommendation: do not accept O-3 as currently worded. 128 should go to sandbox and the hosted build now, and contract v2 can freeze; testing it accepts nothing. For production, accept only a correctly stated residual, preferably after session-bound bindings land.
>
> §3, capability: I agree, with one correction. I found no session-less way to plant a hash or seize a binding.
> - anon INSERT of a row for the victim is rejected by RLS.
> - anon UPDATE and DELETE of the victim's row touch 0 rows.
> - anon EXECUTE on public.register_push_token is denied.
> - The provider signal writes revoked_reason 'device_not_registered', which rule 5 excludes, and never writes a hash.
> - graphql_public runs under the same roles, grants and RLS. That one is not probed; pg_graphql is absent locally.
> So every capture path requires the victim's authenticated session. A session holder can already redirect a fully hashed binding without planting: delete the victim's row, then register the token from their own account; the victim then gets 42501 on every launch.
> The correction: plant-then-claim adds DORMANCY, not capability.
> - A plant leaves the victim's service untouched.
> - It survives the victim's own cold launch (the real secret returns "refreshed" and the attacker's hash stays), password reset and sign-out-everywhere.
> - It can be activated later from the attacker's account with no session.
> - Delete-then-register takes effect immediately, so the victim's next launch reveals it.
> - After a compromise is "remediated" by revoking sessions, a dormant plant is still live.
>
> What the owner should know is accepted, if accepted:
> 1. Required access: the victim's authenticated session (stolen token, an unlocked signed-in phone, malware). No password or victim device needed.
> 2. Redirect: the victim's phone receives the attacker's notifications and none of the victim's own, mandatory included, until support runs unbind_push_token.
> 3. Forwarding: the victim's notifications delivered to the attacker's own phones, via the verb's rule 3 with the attacker's secret, or the still-granted direct INSERT.
> 4. Persistence: all of the above survive password reset and session revocation. Nothing clears bindings or hashes.
> 5. Scope: Redirect and forwarding affect every user, and predate 128. Plant affects every hash-less row: all rows at apply, and old app versions indefinitely, because rule-2 adoption has no epoch or sunset bound. The every-cold-launch clause protects only rows the real device reaches first.
> 6. Session-less and bounded: with token knowledge alone, rule 5 can claim a pre-128 row the owner signed out of within 30 days, until the 90-day sunset. If that owner signs back in on that device, they're locked out.
> 7. Monitoring: NULL-hash counts measure plantable rows. A 42501 on cold launch from a device that previously held the token is a redirect signal. Both detect; neither prevents.
> 8. What 128 closes: capture by token knowledge alone outside rule 5 (42501, verified), which production allows today.
>
> §7 judgement:
> - Sunset rule-2 adoption at 90 days (~30 min): take it. It bounds the dormancy window for hash-less rows at no interface cost. After sunset, a hash-less device still registers ("refreshed"), just unproven, and delete + rule 1 re-proves it.
> - Rebind audit + previous-owner in-app notice (~2–3 h): worth having, but narrow. It fires on rules 3 and 5 only, so it covers plant-then-claim. It does NOT cover delete-then-register, which isn't a rebind. On forwarding, the "previous owner" is the attacker. Take it this candidate only if it adds no client or contract change; otherwise next candidate.
> - The mitigation that addresses persistence for all three paths is session-bound bindings: revoke a user's push bindings and clear their hashes on password change or sign-out-everywhere. Server only. My estimate is 1–2 working days, uncertain; the auth-hook design needs checking. I recommend it before production.
> - Provider-side proof (a data-only nonce push required for every bind, rebind and adoption) prevents redirects by anyone without the victim's phone. It needs a client v3; ~3–4 working days; next candidate.

## 10. Owner decision (b) — what 131 closes, and the slice it cannot (2026-09-15, after D's second pass)
The owner chose **(b) session-bound bindings before production** and does not accept the persistent capture
residual. Design: `SESSION_BOUND_PUSH_BINDINGS_131_DESIGN.md` (renumbered from 129). D's second pass established
that **no DB-only reclaim can close a redirect completed during the compromise (X1) without opening a session-less
capture (R3)** — so 131 will ship without reclaim. Stated in the owner's terms:

| Path | After 131 |
|---|---|
| Dormant planted hash | **closed** — cleared at password change / sign-out-everywhere / any global sign-out; cannot be re-planted from an old session |
| Forwarding (attacker's phone bound to the victim) | **closed** — revoked at the same events; recreation needs a post-epoch session, i.e. the new password |
| Old-session re-registration or direct INSERT after the credential change | **closed** — write-time guard on every path incl. DELETE |
| **Redirect completed during the compromise** (victim's row deleted and re-bound to the attacker before the victim changes credentials) | **NOT closed.** The row is the attacker's; the victim's epoch cannot touch it. Recovery: support `unbind_push_token`; the victim's client shows the terminal "contact support" state on its next launch. Closed only by provider-side proof (option c) |
| Signed-out devices still receiving push (pre-existing leak, found while defining P6) | **closed** by the live-session trigger |

**The owner's choice for the production gate — one of:**
- **(b1)** 131 as designed, with the completed-redirect slice **disclosed as unclosed** and support-recoverable; provider-side proof (c) scheduled for the next candidate. *(A's and D's recommendation.)*
- **(b2)** 131 **plus** provider-side proof (c) before production — client v3, ~3–4 working days after 131, one more build.
- **(b3)** 131 with a constrained reclaim (D's a–c) — closes R1/R2 but **introduces R3**, a session-less capture via squat; neither A nor D recommends it.
No acceptance is implied by this section; it records the choice to be made.
