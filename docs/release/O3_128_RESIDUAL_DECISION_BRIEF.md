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

## 11. The three production-gate options, defined exactly (A, 2026-09-15; D's independent text in §12)
Owner's instruction: "give me the exact b1/b2/b3 definitions together, identify which closes that path, and give the
incremental work and verification required." The path in question is the **completed redirect** of §10 — the attacker
(holding the victim's session) plants their secret on the victim's legacy row, then rebinds the victim's token to the
attacker's account before the victim changes credentials; from then on the victim's device carries the attacker's
binding and the victim's genuine client is refused (42501) until support unbinds. Everything else in §10 is closed by
131 (`fix/131-session-bound-push @ f102ce2`, 198 45/45, D's second pass). Nothing below is a risk-acceptance statement.

| | **b1 — 131 + disclosure + detection** | **b2 — 131 + provider-side proof of possession** | **b3 — 131 + constrained reclaim** |
|---|---|---|---|
| **Definition** | Ship 131 exactly as built. The completed-redirect path stays open and is **disclosed as such**; add §7's two server items so a redirect is *detected and recoverable* rather than silent: (i) a rebind audit row + an in-app (never push) notice to the previous owner on every cross-account bind (rules 3/5, and rule 1 on a token whose previous row was deleted within 30 days); (ii) the plant path sunsets with the legacy rule (rule 2 stops writing a hash onto a NULL-hash row after 128's 90-day sunset). Support recovers with `unbind_push_token`. | Ship 131, plus: **no cross-account bind activates until the push provider proves the registering device holds the token.** The verb returns `outcome: 'challenge_required'` for rules 3/5 (and rule 1 on a recently-owned token) and writes an inactive binding + a one-time nonce; `send-push` delivers the nonce to *that token* (silent push, 5-minute TTL); the client echoes it via a new verb `confirm_push_token_challenge(p_challenge_id, p_nonce)`, which activates the binding. Same-account refresh (rule 2) needs no challenge. | Ship 131, plus: at the victim's credential change, `invalidate_push_bindings_for` also **reclaims** rows for tokens the victim's account held within N days that are now bound to another account — under D's constraints (a) only tokens whose previous row was the victim's, (b) only if the rebind happened after the victim's last successful registration, (c) reclaim = revoke + hash cleared, never re-activation. |
| **Closes the completed-redirect path?** | **No.** The row is the attacker's; the victim learns (notice) and support acts. Silent capture becomes detected capture. | **Yes.** Step 3 of §1 fails: the attacker's device never receives a push sent to the *victim's* token, so the nonce cannot be echoed and the rebind never activates. It also closes the plant path (a planted hash buys nothing without the device). | **Closes R1/R2, opens R3:** an attacker who can make a token "previously held" by a victim account (a squat: register the victim's token under an account the attacker controls, wait for the victim's credential change) gets the victim's binding revoked from the outside — a session-less denial, and with (c) a session-less capture window on the next registration race. Neither A nor D recommends it (§10). |
| **Incremental work (after 131)** | Server ~2–3 h (A): audit table in `notify` (seam rule: a `notify` routine writes it), one `notify` template `security_device_rebound`, the two predicates in the verb; sunset predicate ~30 min. No client change (C's 42501 terminal state already says "contact support"). D review ~1 h. **No new build.** | DB ~1 day (A): `notify.push_token_challenges` (token_id, nonce_hash, purpose, expires_at, confirmed_at), verb branch + new verb, guard changes so an unconfirmed binding is never selected by a send path (S9 pattern), sunset of unconfirmed rows; four-file rule; rollback. Edge ~½ day (A): `send-push` challenge kind, 401/429 handling. **Client v3 ~1–1½ days (C):** silent-push handler, echo, `challenge_required` UI state, fallback when iOS throttles silent pushes (visible push with a 6-digit code). D review ~1 day. **One more pin and one more build.** ~3–4 working days end to end after 131. | DB ~½ day (A) inside 131's invalidator + tests; D review ~½ day; no client change. But it ships a new attack (R3) that the audit of b1 does not detect. |
| **Verification required** | pgTAP: audit row + notice enqueued on rules 3/5/1-recent, none on rule 2; sunset refuses the plant after 90 d; **negative controls** (predicates removed → 3 failures). 198 unchanged. Device row (production gate, C): cross-account rebind on two handsets → the previous owner sees the in-app notice on next launch. | pgTAP: state machine (challenge issued, expired, wrong nonce, replayed nonce, confirmed exactly once), unconfirmed binding never selected by `notify.drain`, same-account refresh unchallenged; negative control (activation-without-confirm → fails). vitest: `send-push` challenge kind. **Device rows on real APNs (sandbox APNs env — an evidence limit today, packet §7):** (1) legitimate rebind on the same handset confirms within the TTL; (2) plant-then-claim from a second handset **never activates** and the victim's client keeps its binding; (3) iOS silent-push throttling → fallback code path completes. | pgTAP: reclaim under (a)(b)(c); **and an R3 reproduction** to show the new exposure exists, which is the reason not to choose it. |
| **Effect on dates** | Production-gate candidate = pin after 131 + 132 + 133 + b1's ~½ day; **one** more pin/build (already needed for 131's client delta and K-2). Production readiness unchanged from the checkpoint estimate. | Adds ~3–4 working days **and a third build** after the 131 build; D's review and the APNs device rows are on the critical path. Production readiness moves by about one week. | Same as b1 for time; **not recommended** for the reason above. |

**A's position:** only **b2** closes the completed-redirect path. **b1** does not close it; it makes it detectable and
recoverable and discloses it. **b3** closes the specific redirect and opens R3. If the owner requires the path closed
before production, the option is b2 and the date moves by about a week; if the owner requires 131 plus detection with
the path disclosed, the option is b1 and the date holds. The choice between them is the owner's; A does not accept
either residual on the owner's behalf.

## 12. D's independent disposition on b1/b2/b3 (verbatim; Claude D, 2026-09-15)
Evidence: 131 @ f102ce2 (content = a8ea025), probes probe_129_design_completed_redirect.sql, probe_131_lifecycle.sql, probe_131_k2_signout.sql; reclaim analysis R1–R3.

THE PATH. During a compromise, someone holding the victim's authenticated session can move the victim's phone's push binding into an account they control. Two routes: (1) delete the victim's row (owner-delete), then register the token from the attacker's account (a fresh bind; works on rows WITH a genuine device proof); (2) on a hash-less row, plant a secret and later claim it. After either, the row belongs to the attacker's account. The victim's phone receives the attacker account's notifications and none of the victim's own, mandatory ones included (outbid, payment-due, transfer-expiry). The attacker can also make notifications from their own account appear on the victim's phone. The victim's genuine app is refused (42501) on every launch. None of this is undone by the victim changing the password or signing out everywhere, because 131 only touches the victim's own rows. A's §11 describes the path through route (2). Route (1) is the same path and needs no plant; any option must close both.

b1 — 131 as built, the path disclosed as open, plus detection (A's §7 audit row + in-app notice to the previous owner; the plant sunset).
- Closes the path? NO. It neither prevents nor undoes the redirect: detection tells the victim, and support's unbind_push_token recovers them. Two conditions for the detection to be real: route (1) is visible only if the server records deleted bindings (a tombstone, which is not in push_tokens today); and the notice must be in-app, never push, because the victim's push is exactly what was taken.
- Incremental work: A's estimate, about half a day server-side, plus a support runbook for unbind with identity checks. No build of its own.
- Verification: pgTAP for audit/notice on each cross-account route, including rule 1 after a delete; negative controls; 198 unchanged; a two-handset device row.

b2 — 131 plus provider-side proof of possession: a one-time nonce sent through the push provider to the token, echoed back by the app.
- Closes the path? YES, but only if all six conditions below hold. If any is missing, I would report the path as still open.
  C1. Proof is required on EVERY route that makes a token deliverable for an account other than its current proven owner: rule 3, rule 5, and rule 1 for any token with any prior binding, with no time window. A "recently owned, 30 days" window re-opens route (1) for an inactive victim whose app does not re-register inside the window. The simplest sound rule is a proof on every bind except a same-account refresh.
  C2. The direct-table paths cannot bypass it. authenticated and anon still hold INSERT and DELETE on push_tokens. Either a client DELETE writes a tombstone (or becomes a revoke), and a client INSERT of a token with history is refused, or those grants go.
  C3. A confirmation counts only from the same user AND session that asked for the challenge, with a single-use nonce stored hashed and a short TTL. Otherwise the victim's own app, which receives the nonce, would confirm the attacker's claim for them.
  C4. A pending claim never changes the existing row. The current binding stays active and deliverable until the proof succeeds; otherwise a challenge alone is a denial of the victim's push.
  C5. A successful proof is sufficient to take the binding back from ANY account, even when the device's stored secret no longer matches. Otherwise a victim redirected before b2 shipped, or through any route the proof does not cover, still needs support. This is also the reclaim that the database-only approach could not do safely (R3), made safe because only the physical device receives the nonce.
  C6. Challenges are rate-limited per user and per token (our send path must not become a push-spam relay). Any visible-code fallback for iOS says "never share this code", because a visible code is phishable.
- What b2 does not close: an attacker holding the victim's unlocked phone at bind time (C5 lets the victim take the binding back later from that phone); an attacker who knows the new password; the notification content itself.
- Incremental work: A's breakdown (DB about 1 day, edge about half a day, client v3 1–1.5 days, D review about 1 day), plus C1–C6. It needs a new contract version, one more pin and one more build beyond any build carrying 131/K-2. The owner's current one-build authorization does not cover it.
- Verification I would require: pgTAP per route with and without a valid proof (expired, replayed, wrong nonce, wrong user, wrong session, wrong token), each with a negative control that removes the check and reopens the path; the direct INSERT/DELETE refusal; the completed-redirect probe ending with the victim's device reclaiming and the attacker's binding revoked; an R3 squat probe showing that a squatter cannot bind without the device; race probes (two proofs at once, a proof racing 131's invalidator, lock order); 198 and my K-2 probe unchanged; edge tests (service role only, nonce never logged, rate limit). Device rows on iOS and Android through the real provider: foreground registration; background/killed during registration; notifications permission denied; silent-push throttling fallback; reinstall with a new token; two accounts on one install; a plant-then-claim attempt from a second handset that never activates. Hosted proof requires a sandbox apply and edge deploy. Evidence limit today: sandbox APNs environment only.

b3 — 131 plus a database-only reclaim.
- Closes the path? PARTIALLY, and it opens a new one. Without the device, the database cannot tell the genuine phone from anyone who knows the token string and holds some secret. So every database-only reclaim rule I tested (R1–R3) either leaves the path open for planted-first or hash-less rows, or lets a session-less squatter capture a binding (R3). A's b3 (reclaim at the victim's credential change) is a different mechanism from the one I tested; it needs its own R3 reproduction before its claims are relied on. I do not recommend b3 in either form.
- Incremental work: about half to one day DB, no client or build. Verification would include an R3 reproduction that is expected to show the exposure.

WHICH CLOSES IT: only b2, and only under C1–C6. b1 discloses and detects; it does not close. b3 trades the path for a session-less one.

CORRECTION TO §10 CAUSED BY K-2 (independent of b1/b2/b3). §10's row "signed-out devices still receiving push — closed by the live-session trigger" is no longer true once ordinary sign-out is this-device-only. The trigger fires only when the user's LAST live session goes. A this-device sign-out whose revoke call fails, times out (the client's 3 s budget, never blocking) or comes from a pre-129 build leaves that device's binding active and deliverable while any other session lives (probe K2). Server-only fix, no client or contract change: stamp the session id on each binding at registration (verb and direct-insert trigger), and have the sessions trigger revoke bindings whose own session was deleted. My estimate: 3–4 h plus tests, uncertain. Until then §10 should say "closed for sign-out-everywhere, password change and a device's last session; best-effort client revoke for single-device sign-out."

No option above is accepted on the owner's behalf.

### A's reconciliation with §12 (2026-09-15)
- **Agreed:** only b2 closes the path, and only under D's C1–C6. §11's "rule 1 on a recently-owned token" is replaced by
  C1 (proof on every bind except a same-account refresh); §11's b2 work estimate stands but now includes C2 (client
  INSERT of a token with history refused; client DELETE becomes a tombstoning revoke) and C5 (proof-based reclaim).
- **Route (1) is added to §11's definition of the path** (delete-then-fresh-bind needs no plant). b1's detection must
  therefore include a tombstone on client DELETE, or it cannot see route (1) — added to b1's incremental work (~1 h).
- **§10 correction accepted:** with K-2 (ordinary sign-out = this device), the live-session trigger closes the
  signed-out-device leak only for sign-out-everywhere, password change and a device's *last* session. A's 131 amendment
  (A-131-K2, on the 131 branch, D re-reviews): stamp `session_id` on every binding at registration (verb and direct-insert
  trigger) and revoke a binding whose own session was deleted, in the existing sessions trigger. Server-only; no contract
  or client change; census unchanged; 198 extended with a negative control.
