# Claude D — release sprint review and verification log (target Fri 2026-09-18)

Owner directive 2026-09-14: D = release verification + independent review. Authorised: isolated local work,
review, release preparation. Not authorised here: hosted builds, shared-sandbox writes, production, credentials,
feature activation. D edits nothing in `supabase/migrations` or `docs/release` — findings go to the owner of the
file (A: 127/128, registry, release docs; B: 126, L1 edge coupling).

Probes live in `probes/`; each is `BEGIN … ROLLBACK` against a local rehearsal database built by
`scripts/rehearsal_reset.sh` (loopback only). States are produced through the real writers wherever one exists.

## Task board (D)

| Id | Task | Depends on | Status |
|---|---|---|---|
| D-1 | admin/analytics-redesign @ 64f26f9 on its own track; AN-1/2/3 deferred to backlog | A review (D-AR1) | waiting on A |
| D-2 | automated sandbox acceptance + cleanup, venue kit 62ec887; marketplace phase steps if cheap | owner window, serialized via A | local prep |
| D-3 | independent review of 126 money semantics + pgTAP 193 (A1–A8, CONVERGENCE_135_REPORT.md:541-548) | B review-ready | pre-review findings sent |
| D-4 | integrated-chain rehearsal on A's candidate snapshot (fresh + production-order replay, rollback battery, pgTAP, Gate-2, manifest, expected_grants) | A snapshot (Thu) | D-INT0 dry run done |
| D-5 | independent authorization-boundary review of 128 | A fold-in commit | F1–F3 found, fixes in progress |

## D-INT0 — dry run on A's head `e104c87` (2026-09-15)

| Check | Result |
|---|---|
| Fresh `LC_ALL=C` replay (`rehearsal_reset.sh`) | exit 0, 5.2 s |
| Full pgTAP (`rehearsal_test.sh`) | plan 4789 · ok 4769 · not_ok 20 · psql_err 0 · 12.8 s — **REGRESSION** (157: 17, 162: 3) |
| CI run 34926241630 (`f00c946`) | failed at privilege parity (`push_token_rebind_epoch` service_role grants) before pgTAP ran — the 20 failures were not visible in CI |

## D-5 — 128 `register_push_token_secure_rebind` (cold read of `e104c87`/`f00c946`)

| # | Severity | Finding | Evidence | Disposition |
|---|---|---|---|---|
| F1 | HIGH | The new verb never heals the push channel: after `device_not_registered`, re-registration leaves `identity_channel_state = 'unreachable'` and `last_provider_error` set, so `notify.enqueue` suppresses every later push (mandatory included). The revoked legacy verb healed (092:1119-1127, §17.24). | `probes/probe_128_unreachable.sql` — `verb=new`: state unreachable, next mandatory push `suppressed|undelivered_mandatory`; `verb=legacy` (negative control): state ok, push `pending` | accepted by A; fix on all success paths in progress |
| F2 | test | 157 still exercises the revoked verb (17 not_ok); F28–F31 are the §17.24 heal contract | rehearsal pgTAP output | accepted; port to the new verb (becomes F1's regression test) |
| F3 | test | 162 Gate-2 pins stale (30/88/33 vs 31/92/34) | rehearsal pgTAP output | accepted; bump with named delta |
| Q1 | open | `app.push_token_verb` stays `on` for the rest of the transaction (guard disarmed); reachable only by a multi-statement transaction such as a pg_graphql multi-field mutation | code reading; pg_graphql absent from harness | A resets the setting before every return and before the rule-4 raise; probe on the real stack optional |

### 128 fold-in pass — `cf73d7b`

Harness `scripts/review/d_candidate_rehearsal.sh` (copy of A's certified production-order script, extended).
**Correction:** its first dry run reported rollback PASSes that were vacuous (identity query errored, empty
snapshots). Fixed: an empty/errored snapshot is now a FAIL; snapshots ≈ 3.6 k lines. No claim was made from it.

cf73d7b: PASS 13 · FAIL 2 · WARN 4 — replay 144 · census 31|93|37|35 = ci.yml · manifest PASS · production order
135 PASS · S1 function hash / S2 census identical across orders · pgTAP 4801/4798 (195 A13/A14/A19) · S3 catalog
identity FAIL (push_tokens ACL) · rollback diffs: 20260906120000 102 (declared archive), 127 2, 128 34.

| # | Severity | Finding | Evidence | Disposition |
|---|---|---|---|---|
| F1 | closed | heal verified on the fix | `probe_128_unreachable.sql` verb=new @cf73d7b: state ok, push pending (= legacy control) | closed |
| G-1 | BLOCKING | `supabase/ci/parity_grants.sql:94,117` re-grant table-level SELECT on push_tokens after the chain (CI + certified harness), undoing 128's column scoping: 195 A13/A14/A19 fail, CI parity will diff, fresh vs production order diverge | harness output; fresh ACL `arwdm`, production order `awdm` | sent to A |
| G-2 | LOW | equality oracle: owner UPDATE with the true hash passes the guard (1 row), wrong raises | `probe_128_foldins.sql` G2 | sent to A (column-scoped UPDATE or record residual) |
| G-3 | MEDIUM | 128 rollback leaves per-column SELECT ACLs and does not restore `notify.register_push_token` EXECUTE for authenticated | `rb_128…diff` | sent to A (restore or declare) |
| G-4 | LOW | 127 rollback restores 0590's logic but not its text → post-rollback hash ≠ pre-127 | body diff vs `0590_strict_auth_on_listing_checkout_rpcs.sql` | sent to A |
| — | pass | GUC reset after return; epoch UPDATE/DELETE/TRUNCATE refused (service_role), second row 23505, client SELECT denied | `probe_128_foldins.sql` G1, G4–G6 | — |

## O-3 — independent disposition (128 residual, verified at `cf73d7b`)

Probes: `probe_128_o3_attacks.sql`, `probe_128_o3_delete_register.sql`. Attacker access in every case: the victim's
authenticated session (stolen token, unlocked signed-in phone, malware); no password, no victim device.

| Attack | Result | Survives revocation | Cold-launch effect |
|---|---|---|---|
| Plant-then-claim on a hash-less row | plant "refreshed"; victim's real cold launch also "refreshed", hash stays the attacker's; claim from attacker's account "rebound"; victim then 42501 on every launch, cannot delete the row | yes (nothing clears bindings/hashes) | none on a planted row |
| Delete-then-register (hashed row) | victim row deleted with the session; attacker registers "registered"; victim 42501 | yes | none |
| Forwarding | attacker's own phones bound to the victim (verb rule 3 with the attacker's secret, or direct INSERT) — victim's notifications route to them | yes | none |

Affected: plant — every hash-less row (all rows at 128 apply; old app versions indefinitely; rule-2 adoption has no
epoch/sunset bound). Delete-then-register and forwarding — every user, before and after 128. 128 closes the
token-knowledge-only claim (F7, 42501 verified). NULL-hash monitoring measures plantable rows; it cannot see a
completed plant, claim or forwarding.

**Disposition:** do not accept O-3 as worded. Ship 128 to sandbox/build and freeze v2 (testing is not acceptance).
Production: (a) accept the restated session-compromise residual, or (b) session-bound bindings before production
(revoke bindings + clear hashes on password change / sign-out-everywhere; server-only; D estimate 1–2 wd, uncertain),
or (c) + provider-side nonce proof for every bind/rebind/adoption (client v3; ~3–4 wd; next candidate).
Recommendation: (b) before production, (c) next candidate.

**Sandbox sequencing flag:** applying `20260910120000` (venue, Phase B of SBX-1) before 125–128 puts the sandbox
tip above 125 — the hazard A's registry forbids for 126–128. Run SBX-2 first or give venue its own window.

## D-1 — venue kit, local end to end (2026-09-15)
Kit `62ec887` · app `venue/read-slice1-fixes @ 2665a20` rebuilt · local stack with `venue_api` exposed:
**138 PASS / 0 FAIL**, exit 0. No marketplace steps added to the kit (A's hosted steps; would duplicate the manifest).

## 128 pass 3 — `f22c1a3` (freeze cleared from D)
Harness PASS 17 · FAIL 0 · WARN 2 — pgTAP 4806/4806 · grant matrix = expected_grants (68) · S1/S2/S3 identical ·
127 rollback identity exact (G-4 closed) · 128 rollback residue 10 lines, all declared (epoch table/trigger/function;
`notify.register_push_token` EXECUTE not restored, rollback:46-47) (G-3 closed) · hash UPDATE with true and wrong hash
both "permission denied for table" (G-2 closed by grant) · F1 heal still closed · O-3 attacks unchanged (residual).
Rule-2 sunset: A declined for this candidate; D agrees (bounds plant creation, not dormant activation).

## Owner O-3 decision (2026-09-15): option (b) — production security gate
Session-bound bindings required before production deployment; sandbox acceptance does not waive it. D reviews A's
lifecycle design and adversarial tests against S1–S12 (sent to A before the design): password change and
sign-out-everywhere revoke bindings + clear hashes (confirm the project actually ends other sessions on password
change); old JWT within exp cannot recreate via verb or direct table path; two-connection races (READ COMMITTED
revoke can miss a concurrent insert — prefer a delivery-time security-epoch check); older clients; dormant plants;
forwarding; ordinary single-device sign-out; every send path honours revocation (`send-push` filters `is_active`
only — revocation must set `is_active = false`); account deletion; rollback does not resurrect; hosted auth hook
needs its own authorisation.

## 129 design — first pass (A's `SESSION_BOUND_PUSH_BINDINGS_129_DESIGN.md`, working tree; no SQL yet)
| # | Severity | Finding | Evidence |
|---|---|---|---|
| X1 | **NOT CLOSED** | A redirect completed during the compromise (delete-then-register, or plant-then-claim after the claim) lives in a row owned by the attacker's account; §2e invalidates only the victim's rows, so it survives P1/P2 and the victim's new-session device gets 42501 until support unbinds. Options: (i) proof-carrying reclaim via token tombstones (previous user + hash) — closes seizures of already-proven devices, not planted-first or hash-less ones; (ii) provider proof (option c); (iii) support unbind + client error path | `probes/probe_129_design_completed_redirect.sql` on 128 @ f22c1a3 with §2e applied by hand: binding stays attacker|active|hashed; victim new-session register → 42501 |
| X2 | HIGH | Guard covers INSERT/UPDATE only; an old JWT can DELETE the victim's rows after the epoch, then rule 1 from the attacker's account → fresh redirect after the credential change (S3 open) | design §4 text; owner-delete RLS policy |
| X3 | MEDIUM | Lock-order deadlock: client UPDATE holds row lock → waits advisory; invalidator holds advisory → waits row lock; detection may abort GoTrue's password change. Fix: invalidator updates rows first, then bumps epoch under the advisory lock | design §4 |
| X4 | MEDIUM | epoch = now() (tx start, Postgres clock) vs `auth.sessions.created_at` (GoTrue clock); in-flight old-password sign-in or skew passes. Suggest greatest(NEW.updated_at, clock_timestamp()) + margin | design §2d/§2e |
| X5 | MEDIUM | S2 relies on an updated client calling `revoke_all_push_bindings` first; old clients / failed call / admin revocation leave forwarding and plants active. Live-session deletion leaving none is distinguishable from expiry cleanup | design §2c |
| X6 | LOW | After any password change, old-client users lose push silently until they re-login (release note) | design §4 |
Closed as designed: S1 (hosted trigger privilege flagged), S5 (with X6), S6 dormant plants, S7 forwarding, S8, S9, S10 (FK cascade verified, 000:881), S11, S12 flagged.

## D-4 — 126 review of B's `db2f95f` (PR #63): PASSED, no blocking findings
Harness PASS 15 · pgTAP 4755/4755 (193 63/63) · 126 rollback identity exact · orders converge · census 30|88|37|33.
Negative control: 193 against rolled-back (120) bodies → 18 ok / 45 not ok. `probes/probe_126_review_db2f95f.sql`:
C1 refund+chargeback 10000 known · C2 partial + amount-less full capped · C3 µs half-open boundaries · C4 legacy →
mixed with separate bound · C6 older payment's refund counted, TimeZone-invariant (UTC vs UTC+14) · C7 refund_facts
not executable by anon/authenticated/service_role. Deployed console (admin/operating-console) degrades mixed/null
safely. LOW: L-1 status refunded + NULL refunded_at invisible (data-drift only); L-2 cumulative full/partial
reclassifies history (documented); L-3 deployed-console copy "marked refunded" under mixed (D, admin track).

## D-3 — 126 refund exactness (pre-review of A's part 1 `048eeb1`, now B's)

| # | Severity | Finding | Evidence | Disposition |
|---|---|---|---|---|
| R126-1 | HIGH (money) | `ops.refund_facts` sums ledger rows with no per-payment cap: a full refund + lost chargeback on a $100 payment reports **$200 'known'**; a $60 partial + amount-less full reports $160. A8 violated — `payment_refunds_payment_dispute_uniq` only dedupes a repeated dispute. The payment fact itself is correctly capped. | `probes/probe_126_chargeback_after_refund.sql`, `probes/probe_126_refund_facts.sql` | sent to B and A |
| R126-2 | HIGH (money) | Pre-ledger refunds (`amount_refunded_cents` "never backfilled", 20260906120000:303-305) are invisible while certainty stays `'known'`; A5's known zero is false for any window holding a legacy refund | `probes/probe_126_refund_facts.sql` (case B) | sent to B and A; suggest `mixed` + separate upper bound |

Planned independent 193 cases (not from B's tests): refund at exactly `hi` and `hi − 1 µs`; non-UTC session
`TimeZone`; refund in window on a payment paid outside it; a later refund completing an earlier partial;
refund-then-chargeback; legacy + ledger in one window; rollback restores `120`'s bodies (definition diff);
grants (`refund_facts` service_role only); every assertion with a negative control failing against `120`.

## Restart instruction (if this session stops)
Rebuild: `scripts/rehearsal_reset.sh snatchit_d_int_rehears` in a detached worktree of the commit under test,
then `scripts/rehearsal_test.sh snatchit_d_int_rehears`; re-run each probe with `psql -f` (128 probe takes
`-v verb=new|legacy`). Task state is the board above; peer dispositions arrive by session message.
