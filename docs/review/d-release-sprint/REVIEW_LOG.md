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
| D-1 | admin/analytics-redesign @ 64f26f9 on its own track; AN-1/2/3 deferred to backlog | A review (D-AR1) | **APPROVED by A** (independent gates: tsc 0, lint 0, vitest 136/136, build 0; merge-tree clean; reads ops.money_overview/today/whoami only). Deployment owner-gated. AN-2 backlog note: `types.ts` toCertainty maps only exact/uncertain; 126 emits known/uncertain/mixed + known_cents → safe degradation, exact part of mixed hidden until AN-2 |
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

## D-INT1 — candidate snapshot `release/candidate-20260918 @ cd1f03c` (2026-09-15)
Byte identity vs reviewed heads (migration + rollback): 121/030a922, 123-124/26b8e2e, 125/fc4f113, 126/db2f95f,
127-128/f22c1a3 — all SAME. Harness PASS 20 · FAIL 0 · WARN 2 (declared: 20260906120000 archive 102, 128 epoch + notify
grant 10) · replay 147 · census 31|93|37|35 · grants = fixture (68) · manifest PASS · pgTAP 4918/4918 (189 19, 190 30,
191 15, 192 11, 193 63, 194 30, 195 58) · production order 135 → PAY → TIX → 121 → 123 → 124 → 125 → 126 → 127 → 128 ·
rollback identity exact for 121/123/124/125/126/127 · S1/S2/S3 identical. Not yet in the tree: B's #64 edge, 130, C's client.

## 129 design §4c — reclaim (X1 option i) is not safe as written
| # | Path | Why |
|---|---|---|
| R1 | attacker self-deletes its own seized row (tombstone with its own hash) before the victim's credential change, then reclaims after the victim re-registers | reclaim keys only on "secret matches a tombstoned hash"; attacker's own password change satisfies any epoch condition |
| R2 | ping-pong: eviction by reclaim writes a tombstone for the evicted holder | §4c writes tombstones on rebinds |
| R3 | pre-registration squat + self-delete → capture after the genuine device registers | converts V3's DoS-only squat into a session-less capture |
Constraints a) evicted/cross-user-taken holders never get reclaimable tombstones, b) earliest proof wins, c) take-away tombstones carry the acting session, invalidated by the previous owner's epoch — close R1/R2, **not R3**.
Disposition: no DB-only reclaim closes X1 without opening R3; options for the owner: provider proof (c) before production;
129 without reclaim with completed redirects stated UNCLOSED (support unbind + client error); or reclaim with a–c and R3 stated.

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

Client facts from C (`frontend/candidate-recovery @ 656b3ee`, C's report): shipped and old builds sign out with auth-js
default scope **global**, so 129's P6 ("other devices untouched") is false as shipped and today signed-out devices keep
active hashed rows (push continues after sign-out). A's live-session AFTER DELETE trigger would fire on every such
sign-out. Added cases S13 (row revoked when another device's global sign-out ends this session), S14 (re-login adopts
the genuine secret, never revives the old hash; old JWT refused), S15 (password-changing device through the +2 s margin
and client retry), S16 (in-flight registration racing the trigger; no half-written row).

## Sandbox marketplace phase STOPPED (A, SBX-2 under O-1) — D independent read-back and catalog gap
Read-only, `supabase db query --linked --project-ref ofaidukbieeekqaboscm` from the unlinked kit worktree (**hazard: the
main checkout `/Users/josetascon/snatchit` is linked to production `hqycwntpfoztoinemqns`**). Matches A on every field:
ledger 132 (max 20260909000000); numbered 110–132 only 123/124/125; schemas catalog/kernel/notify/venue (no ops, no
venue_api); no refund_facts / 127–130 objects; bids FK → profiles ON DELETE CASCADE, bids 0; sync_scan md5 6beca316;
listings 49 / payments 51 / transfers 33 / bids 0, reserved 0, pending 3, push_tokens 1; kernel.tickets 0, signing_key 0;
authenticator db_schemas public, graphql_public, kernel; db_pre_request public.sandbox_pre_request.
Venue phase unaffected: 20260910120000 references none of the 113 objects created in 110–120; 110–120 add no columns to
catalog/venue/kernel tables; kit preflight passed 8/8 on this sandbox 2026-09-14.
Catalog gap (probes/sandbox/): sandbox = repo for its own ledger (policy text deparse only; 5 function bodies identical after
normalising project URL and comments). Gap vs full 74e51cf chain: 379 identity lines (ops 323; 110–114 signing recovery;
121 door; **119 listing-block insert guard**; 127–130). Flags: sandbox lacks 119 (evidence limit for blocked-seller listing
paths); six migrations (032/033/034/035/087/099) hardcode the production functions URL in `net.http_post` triggers — the
sandbox was adapted out of band; fresh replays with live pg_net point at production.
CI exposure of the hardcoded production URL (source reasoning at 74e51cf, not executed on CI): triggers 033/034/035 post only
with a vault `service_role_key` (none in CI; pgTAP rolls back) → no; 087 ticks gated on `crm_export_worker_secret` → no; 099
monitor daily 05:23 + alerts + verify_jwt → very unlikely; **032 `enforce-transfer-expiry` cron `*/2` posts unconditionally**
with a NULL bearer → likely ~1 POST per 2 min of each CI migrations job to production, answered 401 by the function's own
bearer check (deployed --no-verify-jwt), no side effects; unknown whether pg_net accepts a null header. Definitive CI-only
check proposed: print `cron.job_run_details` and `net._http_response` status codes at the end of the migrations job.
**Confirmed** by A's CI run 34933664373 (3fa94d3): enforce-transfer-expiry cron ran once (enqueue succeeded), `net._http_response` one row status 401, queue 0 — live, benign, contingent on the function's bearer check. D advice: no CI-only unschedule/deactivate/DNS block (migrations apply inside `supabase start`, so any later step races the first tick and alters parity-tested cron state); add an edge unit test that null/empty/wrong bearer → 401 with zero Supabase/Stripe calls (none exists); real fix = config-driven URL migration, no-op when unset.

## Pin at `aabe029` (A, 2026-09-15/16); 131 rebased to `f102ce2` (content = a8ea025)

## 132 interim alerts — D costing (ops framework 115/117/118, deployed console)
| Item | Cost | Notes |
|---|---|---|
| (a) unfulfillable-refund detector | cheap, ~3–4 h incl. pgTAP | `ops.detect_unfulfillable()` in the detect_case/detect_sweep pattern over `public.webhook_retries` (`unfulfillable%`, unresolved, > 10 min) → p1 `refund_failed`/`payment`; manual_review also p1 (no p0: priority check p1–p4); needs a `run_job` CASE arm, schedule, census/manifest, negative control; no console change |
| (b) double-capture signature | +~1 h in the same migration | the second capture stays unsucceeded with `unfulfillable:one_success_per_listing`; join to a succeeded payment for the same listing **and buyer** → p2 `reconciliation_mismatch`, reported 7 days past refund so detect_sweep does not hide it |
| (c) job health for enforce-transfer-expiry | **not covered** | pg_cron runs `net.http_post` and records success on enqueue; the edge writes no `ops.job_state`; detect_jobs cannot see edge 500s; also job_health timed out on production volume (2026-09-08). (a) is the proxy; true cover needs an edge heartbeat or a `net._http_response` check |

## Re-pin — `aabe029` (code tree `74e51cf`: #68 193 fixtures without superuser GUCs): **PIN from D**
193 fixture reachability OK: every ledger row via `record_payment_refund`; time shifts only move the row just written and the
completing `refunded_at`, per-payment calls chronological (3, 4, 5, 11, 8), replay unshifted; U.3 legacy-then-chargeback
ordered correctly; ledger trigger re-enabled (F.7), bypass reset by `trg_reset_payment_guard_bypass` (statement-level, fires
on 0-row updates; F.8); guard validates only. No SET/set_config of superuser GUCs in any test. Negative control vs 120: 20 ok /
45 not ok. D-5 incremental 74e51cf: PASS 22 · FAIL 0 · WARN 2 · pgTAP 4974/4974 (193 65, 197 45) · S1/S2/S3 identical.
aabe029 vs 74e51cf: docs only. GitHub CI green at aabe029 (A: run 34932209458).

## 131 re-verify — `a8ea025`
Harness PASS 23 · pgTAP 5012/5012 · 131 rollback exact · F-131-1 closed (user with live session, no identity_ext row deletes) ·
F-131-2 order by user_id · lifecycle unchanged · races R1–R4 PASS · X1 UNCLOSED as stated. A: GitHub CI run 34931148396
applied triggers on auth.users/auth.sessions on Supabase's CI stack (S12 platform evidence; hosted project proof = sandbox).

## Fresh-mint residual — D disposition (B's three paths, 5c4cfa4)
**Open money defect with automated remediation**, not an orphaned-intent residual: each path yields two confirmable secrets
for one buyer; two captures are possible; the second collides with `idx_payments_one_success_per_listing` →
`unfulfillable` → enforce-transfer-expiry Phase 0 refunds once (manual review if a transfer exists). Buyer is charged twice
until the sweep; depends on sweep health, Stripe refund success, and the payments RC being applied. Structural fix: pending
row before minting (132 allocated to B, proposed; owner places it). A recommends 132 in the production gate beside 131.

## 131 session-bound push bindings — `fix/131-session-bound-push @ 38c4d8d` (production gate)
Harness (auth.sessions stand-in via `SHIM_EXTRA`, WARN): PASS 23 · FAIL 0 · WARN 3 · replay 150 · census 31|99|37|37 · pgTAP
5010/5010 (198 43/43) · 131 rollback identity exact · S1/S2/S3 identical. Probes `probe_131_lifecycle.sql`,
`probe_131_user_delete.sql`, `race_131.sh`.
Held: P1 revoke + hash clear + epoch · S3/X2 old session refused on verb/INSERT/UPDATE-activate/DELETE · revoke_all from the
old session ok · P4 planted claim 42501 · P5 forwarding re-bind 42501 · P7 new session refreshed · X5 expired-only no epoch,
one-of-two live keeps bindings, last live revokes · races R1 (2523 ms → 42501), R2 (2538 ms → 42501), R3 (password change
waits 2537 ms then revokes the committed new binding), R4 no 40P01 · S9 send paths honour is_active / revoked_at.
X1 **UNCLOSED** confirmed on real code (redirected tablet stays attacker's; victim's new session 42501).
| # | Severity | Finding |
|---|---|---|
| F-131-1 | MEDIUM | DELETE auth.users of a user with a live session and no identity_ext row aborts: sessions cascade → sessions-gone trigger → invalidator inserts identity_ext for the user being deleted → FK violation (dashboard / GoTrue admin deleteUser) |
| F-131-2 | LOW | sessions-gone trigger loops users without ORDER BY → per-user advisory locks in arbitrary order on multi-user deletes |
| hosted | verify | GoTrue clock for updated_at vs sessions.created_at (X4); session cleanup with NULL not_after counts as live → dormant users' bindings revoked on cleanup (product effect) |
Correction: D-4 passed 193 on the local superuser harness and missed a superuser-only `session_replication_role` fixture
that aborts on CI; A added a tripwire in `rehearsal_test.sh` (c8cf6ea). 193 fixture reachability re-review pending B's fix.

## D-5 incremental — pin candidate `4b012fd` (#66 E-1, #67 130 any-status): **PIN from D**
Harness (clean re-run from a frozen copy; a first run was invalidated because the script was edited while bash executed it —
every run now copies its harness first): PASS 22 · FAIL 0 · WARN 2 declared · replay 149 · census 31|96|37|35 · grants = fixture ·
manifest PASS · pgTAP 4972/4972 (197 45/45) · production order through 130 · amended 130 rollback identity exact · S1/S2/S3
identical. 130 probe Q3 now `claim_held`; concurrency S1–S5 + C1 PASS. E-1: vitest l1-edge-coupling + checkout-intent
51/51 at 4b012fd; the same tests against #65's edge (927b46d index.ts) fail E1–E6 (independent RED). LOW: per-call bound
is Promise.race without AbortSignal — a timed-out create may complete at Stripe as an unrecorded orphan intent (no secret).
131 harness gap: `scripts/local/replay_shim.sql` lacks the `auth.sessions` stand-in (also affects A's certified
production-order script); D's harness gained `SHIM_EXTRA`.

## D-5 — candidate `release/candidate-20260918 @ 927b46d` (121–130 + #64/#65 edges + C's stack)
Harness PASS 22 · FAIL 0 · WARN 2 (declared) · replay 149 · census 31|96|37|35 · grants = fixture (68) · manifest PASS ·
pgTAP 4967/4967 (130_storage 18, 190 30, 191 15, 192 11, 193 63, 194 30, 195 58, 196 9, 197 40) · production order
through 130 · rollback identity exact for 121/123/124/125/126/127/129/130 · S1/S2/S3 identical · 129 byte-identical to
the attacked version · B's `rehearsal_130_concurrency.sh` S1–S4 + C1 PASS.
130 probes (`probes/probe_130_claim.sql`, staleness by back-dating as postgres): stale other-row claim allows the
sibling, late release frees only its own row · same-row reclaim after 121 s, old token → token_mismatch · buyer/anon
UPDATE of claim columns 0 rows, authenticated EXECUTE denied.
| # | Severity | Finding |
|---|---|---|
| E-1 | MEDIUM (money) | `_shared/stripe.ts:22/51` fetch has no timeout; a claimed supersede stalled past 120 s resumes after its claim went stale and another request claimed the group → double-charge interleave reopens under latency. Fix: AbortSignal budget < 120 s or re-verify the token before inserting P2 / returning a secret |
| Q3 | LOW (question) | a fresh claim on a row that left `pending` no longer blocks the group; the edge's sold/succeeded checks precede the claim (TOCTOU) — confirm settlement neutralises a second success, else drop the status filter |
| Q4 | info | buyer and seller can read `supersede_claim_token` via SELECT policies (useless without service_role) |
Pin readiness from D: ready once E-1 is fixed or explicitly dispositioned by A and B.
A (2026-09-15): E-1 accepted as **pin-blocking**; B to add AbortSignal budgets (< 90 s section) + claim-token re-check before P2 insert and secret hand-out, with a stalled-Stripe test failing against #65. Pending: D incremental re-run on the fix; D independent check of B's three fresh-mint residual paths (replay-canceled `_u{uuid}` retry, re-price between reads, failedAttempts flip) before they reach the owner as disclosed.

## 129 `public.revoke_push_token` (A's staged working tree) — attacked, no findings
Clone of cd1f03c + 129: IDOR by token string → `{revoked:0}`, victim row untouched · own revoke → `{revoked:1}`,
is_active false, reason signed_out, hash kept · repeat → 0 · anon and service_role EXECUTE denied · ACL exactly
postgres=X, authenticated=X · definer, search_path "" · notify function ACLs identical before/after (0 lines) · revoked
post-128 row not rule-5 claimable (42501) · pgTAP 196 9/9 · rollback drops the function. Question (closed by A: contract v2 §2.4 specifies `{revoked}`; C pins contract_version only on register replies): reply lacks
`contract_version`. Numbering: session-bound work is now **131** (pgTAP 198); reclaim dropped per R1–R3 — completed
redirects go to the owner as UNCLOSED (A's brief §10).

## 129 client delta — C's `frontend/session-bound-129 @ 627ee62` (provisional, not in the candidate)
| # | Severity | Finding |
|---|---|---|
| K-1 | MEDIUM | account deletion (`app/settings/index.tsx:228`) calls `signOutEverywhere()` with defaults → now scope `local`; other devices keep sessions and active push after a deletion request → use `signOutAllDevices()` |
| K-2 | MEDIUM (decision) | ordinary "Sign out" (settings:127, profile:205) moves global → local: correct for P6, but a user reacting to suspected compromise no longer ends other sessions; gated file (`signOut.ts`) → A line review + recorded decision |
| K-3 | LOW | `signOutEverywhere` now defaults to local — name contradicts behaviour |
| K-4 | LOW–MEDIUM | "Your password was changed" copy is false when `session_stale` comes from another device's sign-out-everywhere (X5) or a missing session row |
Fixes verified at `frontend/session-bound-131 @ b538f1d`: K-1 (deletion → signOutAllDevices), K-3 (signOutThisDevice / signOutAllDevices; single `auth.signOut({scope})` site), K-4 (neutral copy) — targeted vitest 63/63, tsc 0; K-2 with the owner. Note for 131 SQL: `revoke_all_push_bindings` must not apply the session-age check (reset-password calls it from the pre-change session).
Correct: S15 (changing device registers only from the new session), S16 (no client write after 42501), reset-password global + server trigger, stale-refresh local, revoke_all failure non-blocking.

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
