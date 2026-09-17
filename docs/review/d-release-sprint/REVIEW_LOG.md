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
| D-6 | owner 2026-09-15 direction: SBX-2 path (b) verification · 132 independent review · O-3 b1/b2/b3 disposition · K-2 server contract · CI item 6 | A applies / B writes 132 / A's CI branch | SBX-2 witnessed + row 10 PASS; O-3 + K-2 sent (A accepted; K2-S1 fix on 131 branch → D re-review); 132 @ 74a4371 **PASSES**; stack `6b058d2` (131+132+133) **PASSES** incremental review; item 6 CI VERIFIED at 10194d3 (negative control run by A); 131 @ f72e2d3 K2-S1/S2 closed, **F-131-K2a open**; 133 @ 235c839 **PASSES**; 131 @ f3963a3 **PASSES** (F-131-K2a closed); 132 battery pending B's revised head |

## Owner direction 2026-09-15 (resumed sprint) — D's part
Sandbox path (b): 126 deferred on this sandbox; O-1 extended to reviewed 129/130; venue acceptance a separate later step. 132
required before production (B implements; D reviews concurrency, retries, uncertain Stripe outcomes, duplicate prevention;
development and review authorized, production application not). O-3: session-bound protection required; A and D define b1/b2/b3
and which closes the persistent-redirection path. K-2 approved: ordinary sign-out = this device; separate "Sign out of all
devices"; A and D verify the server contract. Item 6: D verifies a fresh replay sends no production request before 133 takes
effect. No production read is authorized. Existing one-build authorization unchanged.

### SBX-2 path (b) — dependency and source verification before apply (local, read-only)
**This sandbox validates neither 126 nor its admin surfaces** (126 deferred by owner ruling); the full-chain rehearsal (D-5 at
4b012fd/74e51cf, CI) stays the separate evidence for 126.
- Source: tag `candidate/2026-09-18-pin` = `aabe029`; migrations/rollbacks/functions/tests trees identical at 74e51cf, aabe029,
  candidate tip 9de26e9 (02c56c9 / 6b0beaa / 3c41798 / 958dbdb). 127–130 + rollbacks + stripe-webhook, create-payment-intent,
  _shared byte-identical to reviewed `4b012fd` (127–128 also to `f22c1a3`).
- Shape: `probes/sandbox/build_sbx_shape.sh` replays the sandbox's exact 132-version ledger (`sandbox_ledger_132_versions.txt`;
  numbered >109 only 123/124/125) from the frozen pin; then 127→128→129→130 with ON_ERROR_STOP: all applied, no warnings.
- pgTAP on that shape: 194 30/30 · 195 58/58 · 196 9/9 · 197 45/45. Full suite 4249 ok / 73 not ok; rolled back 130→127 and
  re-ran the failing files: identical set except 157 (+18 pre-127, all 128-verb assertions) → every failure is the 110–121/126
  absence (census counts naming 111/117 objects; 176–186/189/190/193), none caused by 127–130.
- Rollback identity on the shape: 130, 129 exact; 128/127 differ only by the declared 128 exception (epoch table, 10 lines).
- Edges: every RPC called by stripe-webhook / create-payment-intent (+ _shared) exists after 130 with matching parameter
  names and service_role EXECUTE; tables disputes/listings/payments/profiles/transfers/webhook_retries present; no ops/126 use.
- 127–130 replace none of the five out-of-band sandbox-rewritten functions (production-URL triggers).

### SBX-2 witness read-back (sandbox, read-only, after A's apply) — MATCHES
`probes/sandbox/readback_sbx2.sql`, unlinked `snatchit-venue-accept`, `--project-ref ofaidukbieeekqaboscm`: ledger 136 (max
20260909000000); numbered 110–139 = 123,124,125,127,128,129,130; ledger md5 (statements) 127 b7b76ba8 · 128 a1b4c094 · 129
11b27f36 · 130 91f7720d = pinned files minus trailing newline (my computation); schemas catalog/kernel/notify/venue; the 127–130
objects present, epoch 1 row; absent as expected ops.refund_facts, guard_listing_seller_not_blocked (119), revoke_all_push_bindings
(131); payments.supersede_claim_token uuid / supersede_claimed_at timestamptz; push_tokens table privs anon/authenticated
DELETE,INSERT; column-scoped authenticated SELECT (all but device_secret_hash) and UPDATE (device_name,is_active,last_used,platform);
ACL/definer/search_path of nine push/checkout functions and push_tokens grants identical to the local shape; native flags false;
counts 49/51/33/0, reserved 0, pending 3, push_tokens 1, supersede claims 0; tickets 0, signing_key 0; L-1 0; authenticator config
unchanged. Census 31/97/37/34 explained: pin CI 31/96/37/35 − 119 function and trigger + sandbox-only `sandbox_gucs()`,
`sandbox_pre_request()` (local shape 31/95/37/34). Production ref in 0 function bodies and 0 cron commands; 21 cron jobs — the
sandbox lacks `enforce-transfer-expiry` (pre-existing drift). Evidence limits: no 110–121/126 (blocked-seller listing path
non-representative; door/scan per B's addendum).
### Row 10 edge parity — PASS
`supabase functions download --use-api` (unlinked scratch) vs `git archive aabe029`, cmp: stripe-webhook/index.ts 813b23f7,
create-payment-intent/index.ts 591b2213, _shared/stripe.ts 3ffcfbcc, sentry.ts 14d03f9d, money.ts a990098f identical;
native.ts/native-dispute.ts not in the bundle (not imported by index.ts — vitest-only). `functions list`: stripe-webhook v4 ezbr
897283ef, create-payment-intent v4 ezbr 4f0e9142, ACTIVE, verify_jwt false; enforce-transfer-expiry v3 unchanged.

### Item 6 — CI egress block `ci/egress-block-20260915 @ 30956ed`, run 34978570107: **NOT YET EVIDENCE**
Placement correct (after `supabase stop`, before `supabase start`); DOCKER-USER chain as intended; rest of the job unchanged vs
candidate run 34934718293 (steps identical + the two new steps; Gate-2 31/96/37/35; pgTAP Files=80 Tests=4980 PASS; masking 0).
**Vacuous:** cron runs `crm-export-build-tick` only, pg_net responses 0, queue 0 → gate "answered 0 / refused 0"; the */2
enforce-transfer-expiry tick never fell in the window (032 at 14:00:25, last query 14:01:04); baseline run had 0 too; the 401 in
34933664373 was a timing hit (~1 run in 3). Proposed: CI-only positive control `net.http_get('https://example.com/')` (never
production) polled to a NULL-status refused/reset error; gate also fails on a non-empty `net.http_request_queue`; optional
one-off negative control without the rules. Limits: CI only (other fresh replays unprotected until 133); 133 cannot close the
in-replay window between 032 and 133 (~108 files) — it should purge queued production-host requests at apply, and only
environment egress control makes "zero" hold during a replay; production-side confirmation needs an authorized production log read.
**Re-run with positive control — run 34979345542 @ 10194d3: VERIFIED for CI (negative control pending, A).** All jobs success;
migrations-job steps identical to the 30956ed run (so = baseline + the two steps); Gate-2 31/96/37/35; pgTAP Files=80 Tests=4980
PASS; masking 0. Probe `net.http_get('https://example.com/')` #8 → `(none)|Couldn't connect to server` (curl connect failure =
TCP reset from the REJECT rule; a DNS failure would read "Couldn't resolve host name") → refused at the runner; answered 0,
refused 1 (the probe), queue 0. No cron ran during this job, so the enforce-transfer-expiry attempt itself was again not
observed — the probe proves the path it would take (db container → outside 443) is refused for the whole job. Hardening (LOW):
the probe's case accepts any error text; require a connect/reset error and fail on resolve/timeout. Pending: A's one-off
negative control (rules removed → probe answered). Limits (a)(b)(c) above stand.

### O-3 — D's independent b1/b2/b3 disposition (sent to A for §12, verbatim there)
Path = completed redirect by either route: delete-then-register (rule 1, works on proven rows) or plant-then-claim (hash-less).
b1 (131 + disclosure + detection): does NOT close; detection needs a deletion tombstone for route 1 and an in-app (never push)
notice. b2 (131 + provider proof of possession): closes ONLY with C1 proof on every ownership-changing bind incl. rule 1 on any
token with history, no time window · C2 direct INSERT/DELETE paths cannot bypass (tombstone/revoke or grants removed) · C3
confirmation bound to initiating user AND session, single-use hashed nonce, short TTL · C4 pending claim never modifies the
live row · C5 a successful proof takes the binding back from any account (recovery of pre-existing redirects) · C6 rate limits
and "never share" copy on a visible-code fallback. Not closed by b2: attacker holding the unlocked phone at bind time (C5
recovers), new-password holder. Needs a contract version, one more pin and build beyond any 131/K-2 build — outside the current
one-build authorization. b3 (DB-only reclaim): partial and opens a session-less path (R1–R3); A's variant (reclaim at credential
change) needs its own R3 reproduction. Only b2 closes, under C1–C6. Gaps in A's §11 b2 wording vs C1/C3/C4/C5 raised with A.
§10 correction from K-2: the "signed-out devices still receiving push — closed" row is not true for this-device sign-out (K2-S1).

### K-2 — server sign-out contract on 131 @ f102ce2 (`probes/probe_131_k2_signout.sql`)
131 migration/rollback/198 byte-identical to a8ea025 (198 45/45 there). Holds: K1 this-device sign-out with revoke (phone
inactive, proof kept, signed_out; tablet active; epoch NULL) · K3 sign out of all devices (revoke_all {revoked:2} + one-statement
global delete: all inactive, proofs cleared, epoch set; other accounts untouched) · K3a post-epoch re-login refreshed · K3b inside
2 s margin 42501 · K4 password change revokes all · K5 old session refused on verb/INSERT/UPDATE-activate/DELETE, revoke allowed ·
K7 only-session this-device sign-out = everywhere semantics · K3o scope=others revokes nothing (not offered by the client).
| # | Severity | Finding |
|---|---|---|
| K2-S1 | MEDIUM | this-device sign-out whose best-effort revoke fails/times out (3 s) or comes from a pre-129 build, with another session live: the device's binding stays active and deliverable (probe K2). Server fix: stamp session id on each binding; sessions trigger revokes bindings of deleted sessions (~3–4 h + tests) |
| K2-S2 | LOW | `push_session_predates_epoch` returns false before checking session existence when the epoch is NULL: a still-valid JWT of a DELETED session can revoke/register (K2b refreshed). Fix: fail closed when the session_id claim's session is absent |
| S-13 | by design (LOW product) | after sign out of all devices, another account on the same install → 42501 (proof cleared; allowing a proof-less claim = R3). Recovery verified: r1 original account re-login + this-device sign-out → rebound; r2 support unbind → registered; r3 reinstall (device row). Copy should name the recovery, not only "contact support" |
| client | for C | `performSignOut` ignores `supabase.auth.signOut`'s `{error}`; auth-js 2.98.0 keeps the local session on network errors → offline sign-out silently no-ops; for all-devices the epoch is already bumped |
198 does not cover: K2-S1, one-statement global delete, scope=others, margin boundary, cross-account hand-off and S-13 recovery,
deleted-session JWT, only-session sign-out, races (race_131.sh), hosted GoTrue facts (statements, password change session
deletion, clock, NULL not_after cleanup — need an authorized sandbox apply of 131).

### DV row 3 (device push registration) — sandbox read-back after the owner's relaunch, 2026-09-16 ~01:19–01:33Z: **server refused, cause identified; CLOSED by Path B**
Read-only: sandbox DB read from the unlinked kit worktree + `query_logs` on `ofaidukbieeekqaboscm` (no writes).
- The handset IS reaching the sandbox: `/auth/v1/token` 200 at 01:19:04 and a session (user `919d511e`) refreshed 13 min before the read.
- `POST /rest/v1/rpc/register_push_token` at **01:19:06 → 403**, i.e. the verb raised 42501 (PostgREST maps it so). Permission and relaunch
  are not the problem; the app asked and the server refused.
- `push_tokens` still holds exactly ONE row: token `ExponentPushToken[nMdl…]` (41 chars), owner `1fcd0c69`, created 2026-09-08, **active,
  no device proof** (a pre-128 legacy row), last_used 2026-09-10. The tester's account is `919d511e`.
- Since the table holds only that row, the verb's only reachable 42501 is rule 4, "token is bound to another account": this handset
  registered under a DIFFERENT sandbox account before 128, the row is still active and hash-less, so 128 refuses the cross-account rebind
  (rule 5 needs the row revoked by a sign-out; it is active).
- Client consequence (`src/lib/push/registration.ts` @ aabe029): `bound_to_other` is TERMINAL for (user, token, rpc) — further relaunches
  return `wait` and never call the verb again. A sign-out clears the record (one was seen: `revoke_push_token` 200 at 01:33:37), so the next
  launch retries and gets the same 403 until the server row is dealt with.
- Remedies, each a sandbox WRITE needing owner authorization: (1) support unbind — service_role `select public.unbind_push_token(<that
  token>)`, then the next launch registers fresh (rule 1) and stores the proof; (2) sign in on that handset as `1fcd0c69` and sign out, which
  revokes the row (`signed_out`) and lets the new account take it under rule 5 (legacy, within 30 days, before the 90-day sunset); (3) run
  DV-611 as `1fcd0c69`.
- **CLOSED by Path B (owner-executed on the device, no server mutation; A read after each step; my own independent read-back 2026-09-16
  01:4xZ):** the single row `140fcb44…` is now **user `919d511e` (the buyer), active, proof present (hash true), device_name iPhone,
  revoked_reason null, last_used 01:42:41Z** — the same token row, rebound to the tester's account under rule 3 with the install's proof.
  Registration works on that handset again. Sequence: buyer sign-out → staff sign-in (`refreshed`, proof planted) → staff sign-out
  (`signed_out`, proof kept) → buyer sign-in (`rebound`).
- Acceptance value: this is 128's documented lock-out (O-3 §1 step 4) hit benignly in test. It confirms the support-unbind path is required at
  launch, and it is the same slice b2 would close by proof of possession.

### b2 scope (owner asked for it 2026-09-15; D's half merged as §13 of the O-3 brief, A's converge ecb72af)
D's conditions C1–C6 become work items 1–10 with owners: A = DB items 1–4 (challenge table + verbs + `challenge_required` branch;
ownership history so a delete cannot erase it; pending claim never touches the live row and send paths exclude unconfirmed rows; a
successful proof supersedes the stored secret), edge 5, contract 7, runbook 8; C = client v3 (6) and running the device rows (10);
D = review 9 and reviewing 10. Timeline 4–5 working days after 131/132/133 integrate (1.5 + 0.5 ∥ 1.5 + 1 + 0.5). Numbering per A:
b2 = migration **135** / pgTAP 202 / contract v3 (134 is the `processing` sweep arm from the 132 review). Builds: one more beyond the
131/K-2 build — A frames it as (i) hold the pin and ship a single build carrying b2, or (ii) two builds; either needs owner
authorization. Stated beside the ask: b2 does not close an attacker holding the unlocked phone at bind time (the victim reclaims
afterwards under C5), an attacker who knows the new password, or lock-screen content. **No option is accepted on the owner's behalf;
b1 is not proposed.**

### 131 re-verify — `f3963a3` (CI 34982075970 green): **F-131-K2a CLOSED — 131 PASSES from D**
The session-end path now writes `revoked_reason = 'session_ended'` and `revoked_at = now()`; 129's client revoke keeps `signed_out`.
Probe B: the legacy row after its session ends reads `session_ended`, and another account's claim by token knowledge → 42501 "bound to
another account" (was `rebound_legacy`); the row stays the owner's. 195 58/58 · 196 9/9 · 157 294/294 · 198 60/60. Races KR1–KR5 PASS with
the new reason (delete waited 2495 ms; register waited 2538 ms → 42501; both old-client orders; no 40P01). Integrated harness at f3963a3:
PASS 23 · FAIL 0 · WARN 2 declared · pgTAP 5034/5034 · census 31|99|37|37 · 131 rollback exact. Product note unchanged: expired-session
cleanup revokes that device's binding (proof kept, epoch unmoved).

### 131 re-review — A-131-K2 at `f72e2d3` (CI 34980745488 green): K2-S1 / K2-S2 CLOSED; **F-131-K2a open**
Harness (`scripts/review/d_candidate_rehearsal.sh`, frozen copy): PASS 23 · FAIL 0 · WARN 2 declared · replay 150 · census
31|99|37|37 · grants = fixture (68) · manifest PASS · pgTAP 5030/5030 · 131 rollback exact · S1/S2/S3 identical. Local: 195 58/58,
196 9/9, 157 294/294, 198 56/56. K-2 probe: K2 now inactive/proof kept/signed_out, only the other device deliverable; K2b gone-session
register 42501; K3o scope=others now revokes the others; all other rows unchanged. `probes/race_131_k2.sh` KR1–KR5 PASS (register
holds lock → delete waits 2498 ms then revokes; delete holds lock → register waits 2555 ms then 42501; old-client INSERT both orders;
no 40P01). `probes/probe_131_k2_amend.sql`: forged client session_id overwritten with the caller's session; SELECT/UPDATE of
session_id 42501.
| # | Severity | Finding |
|---|---|---|
| F-131-K2a | MEDIUM (security) | per-session revoke writes `revoked_reason='signed_out'` (rule 5's precondition): a hash-less pre-128 row re-activated by an old client, whose own session ends while another lives, becomes claimable by any account knowing the token (probe B3 → `rebound_legacy`); at f102ce2 it stayed active, not claimable. `coalesce(revoked_at, now())` also keeps a stale revoked_at. Fix: distinct reason (e.g. `session_ended`) + `revoked_at = now()`; 198 case with negative control |
| note | by design | expired-session cleanup revokes that device's binding with the proof kept (probe C2); epoch unchanged |
| cosmetic | LOW | a gone session gets "session predates a credential change" |

### 133 re-review — `@ 235c839` (CI 34982307401 green), after the disk-full outage: **F-133-1 and F-133-2 CLOSED**
Local matrix on copies of a 130-tip replay (`probes/d133_refusal_matrix.sh`, `probes/d133_cron_behaviour.sh`; base carries 4 fn / 5 cron
production-host sites):
| case | result |
|---|---|
| no Vault secrets (CI shape) | APPLIED; 0 production-host sites; running all five cron commands posts **0** times; queued production-host request purged |
| service_role_key, no project_url | **REFUSED**, catalog untouched (4 fn / 5 cron) |
| key + trailing-slash URL | **REFUSED**, untouched |
| key + short ref | **REFUSED**, untouched |
| key + sandbox URL | APPLIED; cron posts to the sandbox host; production-host queue row purged, sandbox row kept |
| key + production URL | APPLIED; cron posts to production; **both queue rows kept** (F-133-2 fixed) |
| URL without key | APPLIED |
Rollback on a copy: catalog identity 0 differing lines, all five cron command md5s restored, production-host sites back to 4 fn / 5 cron;
133 itself changes 8 identity lines and 5 cron commands. pg_net was replaced by a recording stub plus a `net.http_request_queue` table
for the behaviour test (the shim has neither) — stated as the evidence limit.
Preflight items unchanged and accepted by A: production drift counts before scheduling (4 / 5), post-apply proof that one
enforce-transfer-expiry request is answered, the sandbox notes (133 creates the missing cron there; its notify bodies are replaced), and
117's job-health continuity (A: joins by jobid, evaluates only runs_7d > 0, so no false case).
Integrated harness at 235c839: PASS 23 · FAIL 0 · WARN 2 declared · replay 150 · census 31|96|37|35 · grants = fixture (68) · manifest PASS · pgTAP 4998/4998 · production order + release chain · **133 rollback restores the catalog exactly** · S1/S2/S3 identical. **133 PASSES from D** (owner recorded the PASS 2026-09-15). **The PASS is a review result, not an authorization to apply**: production and sandbox applies still need their own owner authorization, with the pre-apply conditions (Vault `project_url` inserted first; production drift counts 4 fn / 5 cron read first) and the post-apply proof (one answered enforce-transfer-expiry request within 2 min). Evidence limit preserved: the behaviour test ran against a recording pg_net stub and a stand-in `net.http_request_queue`; the CI stack with real pg_net (run 34982307401) is the authority for that part.

### 133 first review — `@ 5fa1fa0` (CI 34980799558 green): **NOT PASSED — 2 findings**
Correct for its purpose (four bodies + five crons read Vault `project_url`, no URL ⇒ no post; in-migration proof of no production
host; rollback declared md5-identical).
| # | Severity | Finding |
|---|---|---|
| F-133-1 | HIGH (operational/money) | `project_url` precondition is prose only: a live environment applied without it silently stops enforce-transfer-expiry (transfer expiry + Phase 0 unfulfillable refunds), refund/payout executor ticks, notify triggers, signing-monitor egress, CRM export — crons "succeed" matching nothing, invisible to job health. Fix: abort when Vault has `service_role_key` but not `project_url` (CI has neither); optional format check; post-apply read that a post happened |
| F-133-2 | MEDIUM | the queue purge also runs on production, dropping production's own queued posts at apply. Fix: purge only when `project_url` is absent or is not the production host. Purge narrows, cannot close, the in-replay window |
Preflight (not defects): (a) the in-migration proof aborts on any environment with unrecorded functions/crons naming the production host
— the authorized production preflight read must count both; (b) the sandbox lacks enforce-transfer-expiry and 133 creates it (starts
expiry/Phase 0 on sandbox data once its `project_url` exists) and replaces its out-of-band notify bodies — the sandbox authorization must
name this; (c) unschedule+schedule changes jobids — confirm job-health keys on jobname.

### Contract v3 draft review (A's 8818550) — 5 findings, all applied by A at 53c95db
| # | Severity | Finding |
|---|---|---|
| V3-1 | HIGH | §7's compatibility story contradicted the shipped client: `registerToken.ts:97` rejects any reply whose `contract_version` ≠ 2 as terminal `contract_mismatch`, so a v3 server stamping 3 on every reply stops push registration on EVERY older build, including unchanged `registered`/`refreshed` — a silent push outage for the installed base after the store release. Fix taken: 2 on registered/refreshed, 3 only with a challenge and on confirm; §7 rewritten; rollout sentence added |
| V3-2 | MEDIUM | the visible fallback could never verify: a 6-digit HMAC-derived code against `nonce_hash = sha256(32-byte nonce)`. Fix taken: the visible code is a re-issued CSPRNG 6-digit nonce, one 5-attempt counter and 5-min expiry shared across modes |
| V3-3 | MEDIUM | `request_push_token_challenge` carried no device secret, so a confirm could leave the row with no proof. Fix taken: the verb takes `p_device_secret` |
| V3-4 | LOW–MEDIUM | the per-token rate limit let anyone knowing a token block the genuine device's reclaim. Fix taken: limits per (token, requesting user) |
| V3-5 | LOW | §9 now names the pre-135 deleted-row residual (self-correcting at the next genuine registration) |
Also raised: the public census moves by functions +3 / triggers +1 / tables +0 (the challenge table is in `notify`), and B's challenge send must be token-addressed without revealing the other account's identity in payload or logs. Both accepted.

### C's three client branches — second read (split with A: A took `signOut.ts` line by line; D took the call sites, the copy, the 131 server-contract match and F-SELL-1's layout)
Branches: `frontend/logout-scope @ 7dbe940`, `frontend/session-bound-131-r2 @ b48f4e9`, `frontend/sell-form-keyboard @ 465dc32`. Local: 62/62
(logout-scope, session-bound-131, auth-sign-out, push-registration) and 34/34 (sell-form-keyboard, adaptive-nav).
Holds: K-2's two acts match the server contract I verified at f3963a3 (local revoke per device; revoke_all then global, and revoke_all is
allowed from a pre-epoch session); the registration record is cleared only after a successful sign-out and a failed sign-out un-marks the
session-end reason; K-1 deletion uses all-devices; K-3 naming; K-4's neutral copy; `handleSessionStale` is once per process and re-arms when
the sign-out fails; `session_stale` is classified apart from `bound_to_other`; F-SELL-1's helpers are pure and the badge height is derived
(`lineHeight = SANDBOX_BADGE_EXTRA - 6` + 6 pt) so header and badge cannot drift.
| # | Severity | Finding |
|---|---|---|
| K-5 | LOW–MEDIUM | the account-deletion path ignores `r.signedOut` and routes to login anyway: an offline failure leaves the session live and the user silently restorable into an account they asked to delete |
| S-1 | LOW–MEDIUM | the sandbox badge text has no `allowFontScaling={false}`, so at the owner's large-text setting the badge outgrows `SANDBOX_BADGE_EXTRA` and crowds the heading again — the same defect, reintroduced by an accessibility setting (sandbox builds only) |
| K-6 | LOW | `clearStaleSession` signs out with the default reason, overwriting the pending 'expired' mark, so the login screen says nothing after a stale refresh token (predates K-2; now fixable by passing a reason) |
Evidence limit: source + vitest only. StickyBar and the badge have no rendering test, so the keyboard geometry and the badge height are
unverified until the combined build runs on a handset (DV-S1/S2, plus a large-text pass on a sandbox build for S-1).

### b2 item 5 — send-push challenge delivery (B's PR #71 @ 8fcaa4f) — **PASSES**, 1 LOW; plus RB-1 from the runbook
C6's edge half verified independently: the send targets the challenge row's token (which may be another account's — the point), and nothing
in the payload or the logs identifies that row's owner; the requester's user id is used only for the rate-limit namespace; refusals send
nothing and are ordered unknown 404 / wrong requester 409 / confirmed 409 / expired 410 / attempts≥5 429 / rate-limited 429 / limiter error
503 fail-closed / provider 502; limits are per (token, requesting user) and per user with the DB verb still the authority; every log line
carries only challenge_id, mode or outcome. Tests 20/20 at the head; **my own RED control**: the same file against the stack edge (d61970b)
fails 16 of 20.
| # | Severity | Finding |
|---|---|---|
| SP-1 | LOW — **FIXED at d710772, verified** | `await req.json()` was inside the try whose catch logs `err.message`; V8 quotes an input snippet, so a malformed challenge body could put the nonce in a log. Now parsed in its own guard that logs a fixed string and answers 400. 21/21 at d710772; **my own mutant** (restore `err.message` in that catch) kills A18. B's own sharpening is worth keeping: the runtime truncates the quoted snippet, so an assertion on the whole nonce passed by luck — A18 now asserts no part of the body appears, and the leaking shape is a body that fails at the FIRST token (form-encoded instead of JSON), the realistic caller bug |
| **RB-1** | **MEDIUM (design) — ACCEPTED by A into 135** (unbind revokes + tombstones, consumes open challenges, keeps the row; rollback restores 128's delete; 202 G6–G9 with the delete as the negative control) | `unbind_push_token` DELETEs the row (128). Under v3 history is what forces a challenge, so every support unbind erases it and the next bind is `registered` with no proof — support becomes the documented bypass of b2. Fix: revoke + tombstone (`is_active=false`, proof cleared, `revoked_reason='support_unbound'`, row retained). A replacement handset has a different token and is unaffected; if the old device cannot receive push, nobody can prove possession, which is the safe answer |
Runbook (`docs/operations/SUPPORT_RUNBOOK_PUSH_TOKEN_UNBIND.md`) — D's answers to B's four open points: (1) two-person rule on EVERY unbind,
not just payout accounts — the harm is a redirect that survives a credential change, and volume is tiny by design; (2) no cool-down —
proof of possession already gates the next bind (true once RB-1 lands); (3) the durable audit record is `kernel.admin_audit` with action
`push_token.unbind` (the 083 append-only pattern) plus the existing in-app notice, read by the console rather than duplicated; (4) support
may see challenge OUTCOMES only (token id, created, expires, confirmed, attempts, delivery outcome) — never the nonce, its hash or the token
string — as an owner-gated admin-console read on D's surface, specced when 135 lands. Wording nit: §4's "the app has been signed out on the
lost device's behalf" claims more than the verb does.
Also: C fixed P3-2 and P3-3 at `push-proof-v3 @ ac88e3a` (constant renamed; the 60 s fallback counts cumulative foreground time and `inactive`
is no longer backgrounding). P3-1 waits on A's 135 ruling; P3-4 stands as the DV evidence limit.

### C's follow-ups — confirm-reply handling (H-135-1) CLOSED; `frontend/state-views-refresh @ 71eaef0` reviewed
`push-proof-v3 @ 969ff20`: `interpretConfirmReply` reads the outcome first — only `rebound` binds and carries the token id,
`nonce_mismatch` takes the attempts path with the server's `attempts_left` preferred, `challenge_consumed` is terminal, any other 200 is
`unknown` and never confirms or writes a record. push-proof-v3 16/16. **H-135-1 closed on the client side.** Consequence flagged to C and A:
on the PUSH path `prior` is null, so a mismatch is terminal with the code-flavoured copy — if A rotates the nonce on re-issue (M-135-2), a
stale silent echo tells a user who typed nothing that their code was wrong and ends the challenge.
`state-views-refresh @ 71eaef0` (owner's visual refresh of offline / error / empty / no-match): sound and on the right discipline — four
distinct states with one vocabulary, failure announced and exposed as an alert region, a real Button, nothing animated (Reduce Motion needs
no case), and screens show a state only with nothing cached, so a failed quiet refresh keeps the rows rather than showing a confident empty
screen. F-OFF-1 is closed by classifying Tickets' failure. Tests state-views 9/9.
| # | Severity | Finding |
|---|---|---|
| SV-1 | LOW–MEDIUM — **FIXED at bf8b9ba, verified** | `abort`/timeout dropped from `isNetworkError` (RED first); they fall to the server-error state and the OS offline signal still wins. The other callers of the helper (ListingDetail, my-listings, transfer send/receive) narrow the same way |
| SV-2 | LOW (device) — on DV-ST4 | both mechanisms kept for now (the handset is iOS, where the explicit call speaks); DV-ST4 says "announced exactly once" with my remedy if it doubles; Android TalkBack untested this session |
| SV-3 | LOW — **FIXED at bf8b9ba** | body is now "Something went wrong on our side. Try again in a moment."; preview mirrored and pinned away from timeout wording |
Auto-retry on reconnect is already a device check (DV-ST1 ends with airplane mode off → the screen retries by itself), so no new row. state-views 10/10 at bf8b9ba.

### 135 in progress — two consequences D raised before seeing the code (A accepted RB-1 and P3-1)
A's 135 returns refusals from the confirm verb with 200 instead of raising (`{outcome:'nonce_mismatch', attempts_left}`, `challenge_consumed`)
because a raise would roll back the attempt count — correct, but it changes the reply contract:
| # | Severity | Item |
|---|---|---|
| H-135-1 | HIGH (lands in C's client) | the shipped v3 client treats ANY non-error reply as success (`usePushToken.confirm` checks only `r.error`, then `onConfirmOk`), so a wrong code would show "This device is confirmed" and save a `rebound` record while nothing is bound. The contract must name the confirm verb's success shape (only `rebound` binds; the rest are 200 refusals) and C must branch on `outcome` before success, preferring the server's `attempts_left` |
| M-135-2 | MEDIUM (A's SQL) | re-issuing a LIVE challenge with a fresh nonce lets a push sent before the re-issue arrive after it; the client echoes any nonce whose challenge id matches, so a stale one costs a real attempt — and the client re-requests on every foreground. Either accept the previous nonce hash for one generation without counting an attempt, or do not rotate within the challenge's lifetime; say which in the contract |
Both sent to A, and H-135-1 also to C so the client is coded once against the final list.

### Client v3 `frontend/push-proof-v3 @ b098a46` — reviewed (client's share of C1–C6): holds, 4 findings
Local: push-proof-v3 13/13; the earlier client suites still green. C's four probes all clean:
- a push with a different challenge id or wrong type is ignored (`onPushReceived` gates on phase, type, id and a non-empty nonce);
- the code path refuses an expired challenge client-side before any call;
- backgrounding stops the 60 s clock, foreground restarts it and re-requests the same open challenge;
- no `console.*` in challenge.ts / usePushToken.ts / registerToken.ts / the Settings screen carries the nonce, code, payload or device
  secret, and the published status holds only phase, ids and counters — the nonce lives in one local variable between arrival and echo (C6's
  client half).
| # | Severity | Finding |
|---|---|---|
| P3-1 | MEDIUM (**A's 135**, not the client) | after five wrong codes the copy promises a new code, but §3 re-dispatches the SAME open challenge, which is exhausted → every confirm answers `attempts exhausted` until it expires (≤5 min). 135 should consume an exhausted challenge on re-request and issue a fresh one; pgTAP case + negative control requested |
| P3-2 | LOW | `EXPECTED_128_CONTRACT_VERSION` now holds 3 and means "the version a challenge must carry" — rename |
| P3-3 | LOW | iOS `inactive` (shade, system prompt, call) is treated as backgrounded and resets `startedAt`, so repeated transients can push the 60 s fallback past the 5-minute expiry |
| P3-4 | LOW (evidence) | 4 of 13 tests are `readFileSync` + `toContain` source assertions (hook wiring, deps, Settings screen, no UIBackgroundModes): guards, not behaviour. DV-V1..V3 must exercise a real silent push, the 60 s fallback, and a wrong-then-right code |
Device-row notes raised: the visible-code push shows the code in its alert, so the owner should accept the lock-screen preview; a silent push
arriving while the code screen is open is ignored by design.

## Post-window client reviews — auth deadlock PASS, run gate one change requested

**`frontend/auth-signout-deadlock @ a046568` → PASS; carries to `8dc4cec` (comment-only, verified: zero
non-comment lines).** C's root cause holds in the installed `@supabase/auth-js` 2.98.0: `signOut()` runs inside
`_acquireLock`, and `_notifyAllSubscribers` does `await x.callback(...)` then `await Promise.all(...)`, so the
sign-out cannot finish until every callback has. The decisive evidence is the reproduction, not the narrative, so
I mutated: **AM1** (handler back to `async`, diagnostic awaited inline) → **4 failed, suite 0.35 s → 4.88 s** with
three real ~1.5 s hangs. **AM2** (defer dropped) → 1 failed. **AM3** (hook wraps the callback in `void`) →
**6 passed, survives** — C claimed the source pin catches this; it does not, and with a synchronous handler it is
an *equivalent* mutant since there is no promise to swallow. So I tested the pair that matters: **AM4 = AM1+AM3**
→ 4 failed with the same hangs. **No blind spot** — the protection comes from the real-client tests, not the pin.
C corrected the claim and put the reasoning in the file header.

**`frontend/push-token-fetch-visibility @ ce310ef` → ONE CHANGE REQUESTED (F-611C-1, the defect I root-caused).**
The gate is correct: `beginRun`/`endRun`/`cancelRuns`/`isLive` have the right generation semantics (a stale run
cannot release a live gate, `rerun` is consumed once, cancel leaves nothing in flight); module-level is the right
choice and the header says why; and `withTimeout` clearing its timer in `finally` is what *fixes* the hang rather
than merely reporting it. 9/9 baseline in my own worktree.

**Finding D-611C-2.** `isLive` is checked after the token fetch and after `loadRegistrationState()`, then not
again. Six later awaits carry no check and three mutate persisted state — critically there is **no liveness check
between `tryRpc`/`tryLegacy` returning and `saveRegistrationState`**. Reachable through the same `userId` flap:
run 1 clears both early checks, tears down mid-RPC, run 2 completes and persists record A, run 1 returns and
persists record B over it. If run 1's outcome was a failure, `decideRegistration` reads that stale failure next
launch and for a terminal kind returns `wait` forever — **the original defect's shape exactly** (invisible
persisted state suppressing registration), through the RPC window instead of the token-fetch window. Fix: one
`if (!isLive(gate, run.gen)) return;` immediately after the register call, before anything is persisted, plus a
gate-level test in the same shape as C's others.

**D-611C-2 CLOSED at `a609cbc`.** The check sits at the last position before **all three**
`saveRegistrationState` sites with no await between, so one check at the widest window covers both the success and
failure branches — C's worry about needing a second was unfounded, and I verified the coverage rather than
reasoning about it. My two mutants both die: **GM1**, moving the check *above* the register call (wiring intact,
order wrong — precisely the seam C flagged as uncovered) → 1 failed; **GM2**, deleting it → 1 failed. 10/10.
**The placement pin now asserts ordering, not just presence** — a real step up on the `void`-wrapper pin from the
auth branch, which could not tell a correct wiring from a wrong one. The pattern (index-of-check > index-of-call,
< index-of-persist) is worth carrying into the other pins.

The session-stale `clearRegistration` stays unchecked deliberately: clearing on a confirmed `session_stale` is
idempotent and correct whichever run observed it, unlike overwriting a good record with a stale failure. The test
for gating a write on liveness is whether a dead run's version of it could be *wrong*; here it cannot be.

Exactly what C's own note predicted — "the pins prove the hook is wired, not that the order is right". The suite
is green with those awaits unchecked, so the pins do not require a check after every await. Had C claimed the pins
covered ordering, I would have looked elsewhere; the honesty about their reach is what made this quick to find.

## b2 Gate 1 — migration 135 (proof of possession) reviewed at `fix/135-push-proof-of-possession @ 1cfc85c`

Heads: `b49a012` (CI 35050777765 green, five jobs) → `fb2fd68` (CI 35051077164; `notify.get_push_token_challenge`
also returns `token_id` + `requesting_user` for B's CD-1/CD-2) → `1cfc85c` (comment only — I diffed it: zero
non-comment lines change). B's send-push delta re-checked at `fix/b2-send-push-challenge @ c92d7c7` (CI 35051330615).

**A's disclosure, recorded:** the two earlier pushes on this branch were not green and `94939b7`'s message claimed a
green suite while 157 aborted. A corrected it in `b49a012`'s message. I reviewed only from the CI-green heads; the
earlier commits are not evidence for anything here.

My own full-chain rehearsal of the tree, twice (`b49a012` and `1cfc85c`): **PASS 27 / FAIL 0 / WARN 3** each.
FRESH Gate-2 census `32|105|37|38` = the tree's ci.yml EXPECT_*; grant matrix 69 rows = `expected_grants.txt`;
grant-decision manifest asserts; **135's rollback restores the pre-migration catalog exactly** (0 identity lines) —
this is the check that matters for RB-1, since the rollback must put 128's deleting unbind back verbatim; both
orders converge (S1/S2/S3). WARNs are the three pre-existing ones (128 rollback's 10 classified lines, the
`20260916000000` release-position note, the shim note) — none new.

### C1–C6 matrix — `probes/probe_135_c1_c5.sql`, clean rebuilt DB, 0 psql errors
Real writers throughout; the nonce is read from a recording `net.http_post` stub because it exists nowhere else.

| Condition | Result |
|---|---|
| C1 proof on every ownership-changing bind | cross-account `challenge_required` cv3 (C1a); **legacy pre-epoch row with no stored proof** `challenge_required` (C1b — this is the 128 rule-5 hand-over, now closed); client-revoked row (C1c) and support-unbound tombstone (C1d) likewise; a token with no prior row is still `registered` (C1e) |
| C2 no bypass by writing directly | client DELETE deletes **0 rows** and the row survives as `deleted_by_client` (C2b); direct UPDATE of `user_id` / `device_secret_hash` 42501; `notify.push_token_challenges` SELECT+INSERT 42501 to clients **and to service_role** (B9 holds, X2); `issue` / `unbind` / `get_push_token_challenge` / `record_..._delivery` all 42501 to authenticated |
| C2 follow-ups | a client can still create a NEW row for an unknown token (unchanged 128 behaviour) but cannot overwrite an existing token (23505) and cannot plant a chosen proof (42501 from 128's guard) — so a planted row is inert under v3, because C1b makes it `challenge_required` anyway |
| C3 bound to initiating user AND session | third account 42501; **same account, other session** 42501; same account with no `session_id` claim 42501; correct user+session+nonce → `rebound` |
| C4 the claim never disturbs the live row | the row's identity string is byte-identical before the claim, after issue, after three foreign confirm attempts and after four mismatches; the nonce is in neither `nonce_hash` nor `delivery_error` |
| C5 proof superseded | after `rebound` the stored proof and `session_id` are the proving device's; the previous owner replaying the **old** secret gets `challenge_required`, not `refreshed` |
| C5 previous-owner notice | one `security_device_rebound` row for the previous owner, none for the new one; type is `mandatory` with `allowed_channels {}` / `default_channels {}` and an `in_app` template only — never push, no email (N1) |
| C6 rate limits | 3 challenges per (token, requester) then `precondition_failed`; the 5-per-user limit fired independently during an earlier fixture run; "no binding to challenge — register instead" for an absent row |
| C7 attempts / P3-1 / staleness | fifth mismatch returns `challenge_consumed` and consumes; the correct nonce afterwards is refused; a re-request on the exhausted challenge consumes it and issues a fresh row (P3-1); a re-issue rotates in place and the superseded echo answers `stale_nonce` at **attempts = 0**; expired refused |
| send-push's read | exactly `attempts, confirmed_at, consumed_at, dispatched_at, expires_at, id, mode, platform, requesting_user, token, token_id` — no owner identity, no secret hash, no nonce hash |

### Negative controls — `probes/mutants_135.sql` (all four flip their case)
| Mutant | Case that must catch it | Result |
|---|---|---|
| confirm checks the user but not the session | C3b | the other session confirms → `rebound` |
| `trg_guard_push_token_client_delete` dropped | C2b | DELETE removes the row, next binder gets `registered` |
| `unbind_push_token` deletes again (pre-RB-1) | C1d | row GONE, next binder gets `registered` — RB-1's closure is real |
| 128 rule 3 restored (hash match rebinds) | C1a | cross-account with the same secret → rebound, owner becomes the claimer |

### Findings
| # | Severity | Finding | Evidence | Fix |
|---|---|---|---|---|
| M-135-3 | LOW (correctness, security path) | The visible 6-digit code generator raises `22003 integer out of range` when the four random bytes are exactly `0x80000000`: `abs(int '-2147483648')` overflows. The raise aborts the whole verb, so the user gets a hard error and no challenge. p ≈ 2.3e-10 per visible challenge. | `V1.abs_int_min \| ERR 22003`; neighbour `0x80000001` returns `483647` | Drop `abs` and widen: `('x'\|\|encode(...,'hex'))::bit(32)::bigint % 1000000`. I verified it at all three boundaries: `0x80000000`→483648, `0xffffffff`→967295, `0x00000000`→000000 |
| D-135-4 | LOW (documentation, in-DB) | `comment on function public.confirm_push_token_challenge` says "the previous owner is **emailed**", and §8's banner reads "the previous owner's notice: **email**, never push". The implementation is in-app only, with no email row, per N1. The comment is what support reads out of the database. | the migration text vs `C5.rebound_type_channels {}\|{}\|mandatory`, `C5.rebound_templates in_app` | reword both to "notified in the notification centre (never push, no email — N1)" |

### Noted residual (owner-visible decision, not a 135 defect)
`security_device_rebound` is the **only** notification type in the system with no outbound channel at all. `in_app`
is not a channel here — 32 types carry an `in_app` template and none list `in_app` in `allowed_channels` — so the
notification row *is* the in-app item and `{}` is the correct shape for "never push, no email". The consequence is
that a previous owner who does not open the notification centre is never told their device was claimed. That
follows from the owner's N1 (email is owner-gated) plus the never-push rule, so I record it as a decision rather
than a finding. If the owner wants it to reach people, it needs an email row and N1 authorisation.

### B's send-push at `c92d7c7` — delta re-check
CD-1 and CD-2 are closed in the verb, and B took both values off the row. My own mutants: dropping the ownership
check (2 tests die), logging `requesting_user` on success (2), putting `token_id` in the push data (2), restoring a
direct table read (19) — all die. One **equivalent** mutant survives: keying the namespace on the body's `userId`
instead of the row's `requesting_user` passes 25/25, because the ownership check above makes the two provably
equal. Not a coverage gap — but the protection is the check's *position*, so the ordering deserves a comment; if it
is ever moved below the rate-limit block, CD-1 returns silently.

### Evidence limits
Local harness only: `net.http_post` and `vault.decrypted_secrets` are stand-ins, so nothing here proves real pg_net
delivery, real Vault reads, or APNs/FCM behaviour. No device evidence. Nothing applied anywhere. My rehearsal DB
was rebuilt clean (`scripts/rehearsal_reset.sh d_cand_tap_rehears` + `000_helpers.sql`) before the cited runs after
a malformed `\set` in my first mutant draft ran outside a transaction and committed two fixture users into it; I
checked and repaired the DB, and confirmed the trigger and `unbind_push_token` were untouched by that accident.

## b2 Gates 1–2 — both LOWs closed at `38b1e02`; C's client v3 reviewed at `0eea9c3`

**135 @ `38b1e02` (CI 35052114315).** A applied both findings and nothing else — I diffed it: two hunks, the
generator expression and the two documentation strings. Re-verified in a replayed database, not from the diff:
`issue_push_token_challenge` no longer contains `abs(` and now uses `::bit(32)::bigint`; the new expression returns
483648 / 967295 / 000000 / 483647 at `0x80000000` / `0xffffffff` / `0x00000000` / `0x7fffffff`; the confirm verb's
in-DB comment no longer says "emailed" and now says in-app notice. **M-135-3 and D-135-4 CLOSED.**
Full rehearsal at `38b1e02`: **PASS 27 / FAIL 0 / WARN 3** (same three pre-existing WARNs), census `32|105|37|38`,
135's rollback still restores the catalog exactly, both orders converge. My C1–C6 matrix re-ran with 0 errors and
all four negative controls still flip their case. Nothing is applied anywhere; this remains a review result.

**B's send-push @ `c92d7c7` (CI 35051330615)** — CD-1/CD-2 closed in A's verb; B reads both values off the row.
My own mutants: drop the ownership check (2 tests die), log `requesting_user` on success (2), `token_id` into the
push payload (2), restore the direct table read (19). One **equivalent** mutant survives — keying the namespace on
the body's `userId` passes 25/25, because the ownership refusal above makes the two provably equal. Not a coverage
gap; but the protection is that check's *position*, so moving it below the rate-limit block would reinstate CD-1
silently. Independently confirmed the premise: a service_role `select` on `notify.push_token_challenges` is 42501
in a real replayed database, so B9 is real and not merely modelled.

**C's client v3 @ `0eea9c3`** — 21/21 in my own worktree; the stale path is correct against the server, not just
against the ruling: the superseded echo answers `stale_nonce` with the row's `attempts` still 0 (C7). Two things I
checked that could have bitten and don't: `onStaleNonce`'s null-prior terminal is unreachable (`onPushReceived`
only yields a nonce from `awaiting_push`, and `submitCode` always passes the `awaiting_code` state), and
`armFallback` resumes the 60 s from `foregroundElapsedMs` rather than restarting it. Five of my six client mutants
die (stale→wrong-code, stale costs an attempt, unknown 200 treated as `rebound`, `retryPlan` visible branch
removed, dead challenge revived without a fresh id).

| # | Severity | Finding | Evidence | Fix |
|---|---|---|---|---|
| CV-1 | LOW | `classifyChallengeError`'s network branch still matches `timeout\|timed out\|abort`, and that copy is "Check your connection and try again" — the same wrong remedy C removed from `loadState.ts` for SV-1, in a second file. A timed-out request is not evidence the device is offline. | `challenge.ts` classifier + `CHALLENGE_COPY.failed.network` | drop those three from the regex so they fall to `unknown`; no new copy |
| CV-2 | LOW | `register_push_token`'s own limit raises `too many registration attempts` (20/10 min), which the rate-limit regex misses, so the user is told "try again later" instead of "in about 10 minutes" | verb body vs the classifier | `/too many (challenge requests\|registration attempts)/` |
| CV-3 | LOW (coverage, not a defect) | Nothing holds the fallback timer to *resuming*: replacing `CHALLENGE_FALLBACK_MS - foregroundElapsedMs(...)` with a flat `CHALLENGE_FALLBACK_MS` passes 21/21. The mutant costs the user a fresh 60 s after every re-arm — after a stale echo and after each background→foreground return — which is exactly what `foregroundElapsedMs` exists to prevent. | my mutant CM6 | one assertion: a re-arm with 45 s already elapsed schedules ~15 s, not 60 s |

I verified every server string the classifier keys on against the verb bodies at A's head; all match. `/nonce
mismatch/` is a dead branch now (the server returns rather than raises) and is harmless. The `challenge {id, mode,
expires_in_s}` shape `onVisibleIssued` expects is exactly what `request_push_token_challenge` returns.

Evidence limits unchanged: local harness and unit level only; `net.http_post` and `vault.decrypted_secrets` are
stand-ins; no device evidence; the push/foreground/background timing rows stay on DV-V4 and the device matrix.

## b2 — CV-1..CV-3 closed at `e8114df`; A22 verified at `77efd64`; B's flake not reproduced

**B @ `77efd64`** (CI 35052488716): source delta over the c92d7c7 I passed is comment-only (I checked: zero
non-comment source lines). A22 asserts no rate limit is counted on an ownership refusal. I verified it earns its
place with my own mutant — moving the ownership check below the rate-limit block fails **A22 and nothing else**
(1 failed / 25 passed), which is exactly the silent regression my equivalent mutant pointed at. 26/26 baseline.
Test-only on top of a passed head: **cleared for integration.**

**C @ `e8114df`**: 22/22; delta is three files. CV-1 — the challenge classifier's network branch is now
`network request failed|failed to fetch`, timeout/abort fall to `unknown`. CV-2 — the rate-limit regex covers
`registration attempts`. CV-3 — the re-arm is a pure `fallbackDelayMs(state, now)` and the hook no longer names
the constant. All four of my regression mutants die: timeout/abort back in the network branch (1 fails),
registration attempts dropped (1), `fallbackDelayMs` ignoring elapsed foreground time (1), and the hook bypassing
the helper with a flat literal (1 — stronger than the "no longer references the constant" pin C claimed, since my
mutant used a bare `60_000`). **CV-1, CV-2, CV-3 CLOSED.**

`src/lib/push/registration.ts:209` keeps the old timeout/abort → `network` regex. I checked C's reason rather than
accepting it: `REGISTRATION_REMEDY` has entries only for `bound_to_other`, `secret_unavailable`, `session_stale`
and `contract_mismatch`, so that kind carries no connection claim to the user and only schedules a retry. Leaving
it out of this branch is right; worth aligning later for consistency, not now.

**B's reported nondeterminism (one full run at 6 failed / 2004 passed, names not captured): not reproduced, and my
environment cannot speak to it.** Three consecutive full runs in my worktree of `77efd64` are identical —
2 failed / 1956 passed, 5 files failed — and every one of those failures is my own worktree, not the code:
`aes-js` unresolved through my symlinked `node_modules` (3 files fail to collect) and two `brand-fonts` assertions
on missing `@expo-google-fonts` `.ttf` payloads. So: deterministic here, with a different and explainable failure
set, and no sighting of B's six. I would not treat that as evidence either way about B's run; a full suite from a
worktree with real `node_modules` is the only thing that would be.

## b2 Gate 3 — the combined stack PASSES at `release/production-gate-20260918 @ 9bef640`

Chain of heads I checked rather than assumed: `cd996df` = 06d414f + 135 `38b1e02` + send-push `77efd64` — I
diffed all four artifacts (135, its rollback, 202, send-push/index.ts) against the heads I had passed: **identical**,
and the merge adds nothing else to `supabase/migrations`. `0e8de77` = cd996df + client v3 `e8114df` — all four
client files identical to the head I passed, SQL unchanged. `9bef640` = 0e8de77 + C's coupling guard, **+74 lines
in one new test file and nothing else**, so the SQL evidence below carries from 0e8de77 to the tip.

| Gate-3 check | Result |
|---|---|
| Full-chain rehearsal @ 0e8de77 | **PASS 27 / FAIL 0 / WARN 3**; census `32|105|37|38`; both orders converge (S1/S2/S3) |
| Per-migration rollbacks | every release migration restores its pre-migration catalog exactly, 135 included; the only two WARNs are the pre-existing `20260906120000` (102 lines) and `128` (10 lines) I classified earlier |
| **Reverse-order rollback 135 → 134 → 133 → 132 → 131** @ 9bef640 | stack adds 67 identity lines at census `32|105|37|38`; after rolling back in reverse, **0 lines differ from the candidate** and the census returns to `31|96|37|35` |
| C1–C6 possession matrix on the stack | 0 errors, every condition as at 38b1e02 |
| My four negative controls on the stack | all four still flip their case |
| Push/auth client suites at the stack commit | 97/97 across push-proof-v3, send-push-challenge, push-registration, session-bound-131, logout-scope |

**The coupling point, closed properly.** I extracted every string the client's classifier keys on and checked each
one against the stack's migrations — not by grep, but by parsing `raise exception` sites with `--` comments
stripped, so a phrase that only appears in prose does not count. All twelve are genuinely raised; the single
exception is `nonce mismatch`, which is a dead v2 branch (135 returns rather than raises) and is harmless.
C's guard at `d9eb102` then makes this permanent, and I proved it earns its place with three mutants on 135:
rewording `challenge attempts exhausted`, renaming the `stale_nonce` outcome, and changing the session refusal's
errcode from 42501 to P0001 each fail the guard **by name**, one test each. 17/17 clean.

### Finding
| # | Severity | Finding | Evidence | Fix |
|---|---|---|---|---|
| D-135-5 | LOW (operations documentation, ships on this commit) | `docs/operations/SUPPORT_RUNBOOK_PUSH_TOKEN_UNBIND.md` still presents RB-1 as unresolved on the very commit that resolves it: the header says "today `unbind_push_token` DELETEs the row … support would be the documented way around b2", §5 warns "under a delete-instead-of-tombstone build, that guarantee does not hold", and §8 lists RB-1 as "Still open — whether 135 tombstones instead of deleting. A owns it." On this stack 135 tombstones, and I verified it in a replayed database (`C2g`: `support_unbound`, proof cleared, row kept; next binder `challenge_required`). An agent reading this cannot tell whether their unbind erases the history. | the runbook text at `9bef640` vs `C2g` / MU3 | B: header and §8 become closed-at-135; §5 keeps the caveat but names the migration. Should land before the owner's application package, which will cite this runbook; it does not block the pin |

§7.4 of that runbook correctly records the support challenge-outcome read as mine, to be specced now that 135 has
landed — outcomes only, never a nonce, a nonce hash or a token string, owner-gated like the rest of my surface.

**Disposition: Gate 3 PASS at `9bef640`, conditional only on its CI (35053607616) landing green.** Nothing is
applied anywhere. The pin, the application package and the single combined build remain the owner's, and the
sandbox window authorisation still has to be reconfirmed through A before any execution.

Evidence limits unchanged: local harness and unit level; `net.http_post` and `vault.decrypted_secrets` are
stand-ins, so no real pg_net, Vault, APNs or FCM behaviour is proven here, and there is no device evidence yet —
the whole device matrix is still ahead. B root-caused the suite nondeterminism as two concurrent vitest processes
(timeouts on whichever test transpiles first); I now run one suite at a time.

## b2 — pin verified; D-135-5 fix reviewed; the 5180 vs 5186 pgTAP question answered

**Pin checked, not taken on trust:** `candidate/2026-09-18-pin-b2` resolves to `9bef640`, its tree is identical to
the commit I passed at Gate 3, and the earlier pin `candidate/2026-09-18-pin` still resolves to `aabe029`, untouched.

**The pgTAP totals differ for a benign reason, and I chased it before signing anything else.** CI reports
`files=85 tests_ran=5186`; my local harness (and A's) reports `TOTAL plan=5180 ok=5180` — a 6-assertion gap on a
pinned candidate, which would be serious if real. It is not: `000_helpers.sql` declares `plan(6)` of its own and
the local harness runs it as the bootstrap that commits the `tap` schema, excluding it from the totals (84 files,
5180), while CI runs it as an ordinary test file (85 files, 5186). I verified this per file — every one of the 84
the harness runs has executed plan == declared plan, and the only file where the two accountings differ is
`000_helpers.sql`. **No assertion goes unrun in either place; 5180 + 6 = 5186.** Worth stating because "every
file ran its whole plan" and a total 6 short of the declared sum cannot both be true without this explanation, and
the next person to compare the two numbers deserves the answer rather than the alarm.

**D-135-5 fix reviewed at `docs/b2-runbook-rb1-closed @ 5225557`** (branched off the pin; one file, docs-only —
I confirmed the scope). Every factual claim checks out against 135 §6b at the pin and against my own C2g/MU3
evidence: `is_active=false`, `device_secret_hash` cleared, `revoked_reason='support_unbound'`, `session_id`
cleared, row kept, open challenges consumed, reply `{unbound, contract_version: 3}`, next binder
`challenge_required`. §5 now names the migration the guarantee starts at and tells an agent on a pre-135 build to
escalate rather than unbind, which is the right instruction. **D-135-5 closed on that branch.** B's judgement call
— the second §8 bullet saying the support challenge-history read is specced but not built — should stay: §3 points
at it, and an agent who cannot see it will otherwise improvise.

### New finding, surfaced by that fix
| # | Severity | Finding | Evidence | Fix |
|---|---|---|---|---|
| D-135-6 | LOW (operations) | The runbook now requires two things an agent cannot do until my console read exists. §2.3 makes "check the challenge history first — if a challenge was issued and never confirmed, prefer reissuing it" a **precondition**, and §3 makes "the last challenge id and outcome" a **record-every-time** field; §8 now says plainly that read does not exist. A precondition nobody can satisfy is either skipped or improvised, and improvising here means guessing at whether the device already answered. | the runbook at `5225557`, §2.3 and §3 vs the new §8 bullet | mark both as "when the console read exists (§8)", and give §2.3 an interim route — an engineer-run, owner-gated read, or an explicit instruction to proceed without it and record that the history was unavailable |

That read is mine to spec now that 135 has landed: outcomes only — token id, created, expires, confirmed,
attempts, delivery outcome — never a nonce, a nonce hash or a token string, owner-gated like the rest of the
console surface.

## b2 — D-135-6 fix passed at `84ddd9a`; the interim gap measured, not argued

B's fix is right and I have nothing to add to the wording. The part that mattered is there in terms:
"*Until it exists:* **do not treat this step as passed**, and do not guess whether the device already answered."
The interim route is therefore framed as a mitigation, not a substitute — which is the distinction that keeps an
agent from believing a self-reported answer discharges a server-side control. §3 requiring the literal words
"challenge history unavailable" rather than a blank is better than what I suggested: a blank really is
indistinguishable from a skipped gate. B also ruled out an engineer-run read as the routine substitute on the
correct ground — it is a production read and needs the owner's authorization for that specific read.

**How bad is the interim gap? I measured it rather than reasoning about it** (`probes/probe_135_unbind_recovery.sql`):
the interim route's answers are self-reported, so a deliberate attacker simply says "nothing arrived" and the only
real controls left are §2.1 identity verification and §2.4's two-person rule. The question that decides the
severity is what a socially-engineered unbind actually buys, and the answer is: **almost nothing.**

| Step | Result |
|---|---|
| owner registers | `registered` |
| support unbinds | `{unbound: 1, contract_version: 3}`, row tombstoned |
| the owner's own device re-registers, same session | **`refreshed`** — active again, proof re-stored, no challenge |
| the owner's own device re-registers, a new session | **`refreshed`** |

So a social-engineered unbind is a **nuisance-level denial** — the victim stops receiving push only until their app
next registers, which happens on the next open, with no support contact and no challenge. It is **not** a
redirection: any *other* account still gets `challenge_required` (C1d), because the tombstone survives. That is
worth stating plainly in the owner's package, because "support can be talked into an unbind" sounds like the
persistent-redirection path the owner required closed, and it is not the same thing.

Suggested to B, small: §4 tells the user what the verb does but not that the **original** device recovers by
itself. An agent who unbinds by mistake, or a user who changes their mind, currently has no documented way back;
"open the app on the original phone" is the whole remedy and is worth one line.

## B2 window — owner rulings received; my final sign-off conditions and witness invariants

Owner, in their own words (relayed by A, who has them in session): apply order approved **as corrected** —
131 → 132 → 133 → 135 → 20260916000000, "the timestamped processing cleanup must run after 135"; **option (b)** —
no sandbox service key now, b2 push-delivery verification **deferred, not passed or attempted**, no outbound
sandbox notifications to the personal handset; the `project_url` ceremony still required before 133, "verify the
sandbox identity and URL before any authenticated secret is introduced"; and "No production reads, migrations,
edge deployments, flags, AWS changes or build submission are authorized by this message" — which A and I both read
as resolving the earlier window authorization's conditions and granting nothing new.

**Final script review: `5bd47da` plus one line.** I checked the whole file, not the diff: exactly two write
statements, both `vault.create_secret`, both mode- and `CEREMONY_EXECUTE`-gated, `require_server_is_sandbox`
before both, everything else read-only, `\bind :'srk'` taken. The one change I require before signing: **`key` must
refuse outright while the deferral stands** (`exit 3` on entry to that branch). The only distance between an
accidental key write and breaking the owner's most recent decision is typing one word with the same
`CEREMONY_EXECUTE=1` already in the shell history from the `url` step, while `TEST_SERVICE_ROLE_KEY` sits in
`sandbox.env`. Every other constraint here is enforced in code rather than prose; this one should be too.

**Witness invariants — any one of them stops the window:**
1. `vault.secrets` holds **exactly one name, `project_url`**, at the ceremony, after 133, after 135 and at the
   close. Under (b) this is what turns "nothing outbound can succeed" from a construction argument into a verified
   property: with no credential in the Vault, no pg_net post from this database can authenticate to any edge.
   Names only, never values.
2. **V0 immediately before each apply**, every difference attributed through `cron.job_run_details` before I accept
   it; an unattributable difference is a stop, and A applies nothing while a read of mine is unexplained.
3. `project_url` **names the sandbox host** at my shape check between `url` and `verify-url`, and again after 133
   has consumed it.
4. **No production host anywhere** — my `pg_proc` / `cron.job` production-reference probe re-run at the close,
   expecting 0/0, since 133 rewrites the bodies SBX-1/2 left naming the sandbox host out of band.

Recorded for the package so neither is discovered live: after 133 the re-registered crons post with an empty bearer
and are refused every tick, so `enforce-transfer-expiry` does not run for the life of this sandbox state — expected
under (b), and the refused ticks in `net._http_response` are the evidence it behaves as designed; and 133's §0
precondition is satisfied **only** because the ceremony precedes it, so if the ceremony is skipped or fails, 133
must not be applied.

## Row 15 root-caused; row 17's sandbox limit; ceremony script cleared

**Row 15 (04:12Z relaunch) is a deterministic re-entrancy defect in the shipped client, not a transient fetch
failure.** A's sandbox API-log read carried the positive control I asked for (the 04:16:34.448Z
`rpc/register_push_token` appears in the same query) and showed the 04:12 launch making six authenticated calls —
`auth/v1/user`, `user_blocks`, `get_my_profile` ×2, `listings` ×2 — and **never calling the verb**. A's
discriminator: the `auth/user` + `get_my_profile` pair appears **twice within five seconds** at 04:12 and **once**
at 04:16.

Reading `src/hooks/usePushToken.ts` at 9bef640 against that:
- `attempt()` line 116 is `if (runningRef.current || !userId) return;` — a bare early return: no record, no publish,
  nothing scheduled.
- `obtainToken()` awaits `Notifications.getExpoPushTokenAsync(...)` with **no timeout**.
- the effect cleanup (line 392) sets `alive = false` and clears timers but **never resets `runningRef`**.
- `attempt()` **never consults `alive`** — the only two uses are the `setState` guards at 96 and 109.

So a launch whose auth restores twice re-runs the `[userId]` effect while the first unbounded token fetch is still
in flight; the second, *live* `attempt()` returns at line 116 having done nothing, and if the first fetch never
resolves, `runningRef` stays true and **no registration can be attempted again for the rest of that launch**.
Silent to the user, to Settings and to any server read — exactly the log's shape, and it predicts A's
discriminator. **Not sandbox-specific and not new in 135:** it is in the shipped Build 17 client, so any user whose
auth restores twice on a cold launch loses push registration for that launch.

Sent to C, with the point that F-611C-1 as scoped would not close it — a bounded fetch, a persisted failure, a
published state and a backoff all live *inside* `attempt()`, and the failing launch never gets past line 116, so
the branch would improve instrumentation on the path that already worked. What closes it: the timeout (which is
what releases `runningRef` through `finally`), resetting `runningRef` on cleanup or scoping it to the effect run,
checking `alive` after each await, and making the line-116 early return schedule a re-check instead of ending the
launch. Deterministic test, which "transient" would never have given us: hang `getExpoPushTokenAsync`, change
`userId` mid-flight, assert the second attempt is not silently dropped. **It fails today** — that is the negative
control for the whole fix.

**Row 17 / DV-607a cannot test 131 on the sandbox.** 131 is not applied there (ledger 136 = 127–130; my SBX-2
read-back agrees), and 131 is what creates `trg_push_bindings_on_sessions_gone`, the
`after delete … for each statement` trigger on `auth.sessions` carrying the A-131-K2 behaviour. A server-side
session delete on the sandbox therefore leaves the push binding untouched. Two opposite failure modes: expecting
invalidation yields a false negative that costs a handset cycle and reads as a defect in what we just shipped; and
if the token *is* revoked, it came from 129 via the client's `signOutThisDevice`, so recording it as evidence for
the shipped behaviour is a false positive. Row 17 on the sandbox tests the client's reaction to a dead session and
nothing more — written into the manifest row before it runs, and an argument for sequencing it after the B2
application. As witness I capture, read-only: `auth.sessions` by id and count before/after; the handset's
`push_tokens` row before/after (`is_active`, `revoked_at`, `revoked_reason`, proof presence, `session_id`); and the
**absence** of the trigger at the moment of the delete, so the manifest carries proof of why the server did
nothing rather than an inference.

**Ceremony script cleared at `5bd47da`.** `require_server_is_sandbox` asserts identity on the server before any
write in both `url` and `key` — ledger 130..141, `ops` absent, `public.sandbox_gucs` present (absence *and*
presence) — and the output says what it checked instead of the vacuous `server_ref_ok=true`. `\bind :'srk'` taken;
the env-exposure property and the DRY-length rationale are recorded. Nothing further from me on it.

**Relayed rulings — the asymmetry I am applying.** C reports the owner deferred the sandbox push key and blocked
b2 real-delivery verification; A has not had it directly and is asking the owner to confirm. A relayed message that
*restricts* can be honoured at once, because stopping needs no authorisation; a relayed message that *permits*
cannot. So the key is deferred and **(b) is the operating assumption** from here, the b2 device rows are
**deferred, not failed**, and the apply-order confirmation remains outstanding.

## W-1 — the sandbox window cannot deliver a challenge as authorized (raised before execution)

**Finding W-1 (HIGH for the window's purpose; not a defect in 135).** A's pre-flight reports the sandbox Vault
empty — no `project_url`, no `service_role_key`. The ceremony adds `project_url` only, because the owner's ruling
excludes new secrets with `project_url` as the named exception. Consequence, traced in the source at the pin
rather than inferred:

- 135's dispatch builds `'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets where name =
  'service_role_key' …), '')` — with no row the header is `Bearer ` with an empty token.
- `send-push`'s `isAuthorized` compares the bearer to `SUPABASE_SERVICE_ROLE_KEY` and returns false on the length
  check before comparing anything.

So after the ceremony every challenge dispatch is refused: `register_push_token` answers `challenge_required`, the
row is written, no push arrives; the client's 60 s fallback calls `request_push_token_challenge`, which dispatches
through the same verb with the same empty bearer, so the visible code never arrives either. **Both routes are
dead, and the window as authorized therefore produces no device evidence for b2 at all.** A had found the same
empty bearer on the `enforce-transfer-expiry` cron; the challenge path is the same gap and matters far more.

**The refusal is invisible from the database.** The verb's handler catches only a failure to *queue*; pg_net is
asynchronous, so a 401 lands in `net._http_response` and never touches the challenge row, and
`record_push_token_challenge_delivery` is called by send-push, which never runs. `delivery_outcome` stays NULL and
the row looks healthy. This is the DV row-3 shape again — a missing credential presenting as a product defect — so
my witness steps now include reading `net._http_response` for the send-push posts after the first challenge.

Put to the owner through A as two options: (a) add `service_role_key` to the sandbox Vault as a second named
exception, performed by the owner, with D verifying only that a row exists and that a later dispatch is accepted,
never the value; or (b) accept the window as scoped — schema, verbs, grants, rollbacks and the chain are all
genuinely proven, but the challenge → push → echo → rebind path stays unproven and the device matrix's core rows
stay open. Under (b) the package must say plainly that b2 device verification is deferred, so "sandbox application
passed" is never read as "b2 works on a handset". I recommend (a): `project_url` was carved out for exactly this
pattern and the same reasoning applies, but it is a secret and so the owner's to authorize and to perform.

### W-1 follow-ups once option (a) is on the table
A verified the chain independently at the pin and on the sandbox, and adds that `net._http_response` has **0 rows
in 24 h** — nothing has ever posted from this sandbox through pg_net, so (a) switches outbound traffic **on**
rather than resuming it. Three conditions I attached, all sent to A for §2a:

1. **Ceremony order is a safety control, not a preference: `project_url` first, verify it names the sandbox host,
   then `service_role_key`.** With the key present and a wrong URL the sandbox posts authenticated-looking traffic
   at whatever host the URL names; with the URL first and no key, a wrong URL produces an empty-bearer request that
   is refused — fail-safe. A sandbox posting at the production host, even to collect a 401, is an unauthorized
   production contact. I verify the host between the two steps and again after, names and shape only.
2. **(a) means real pushes on the owner's real handset from the sandbox, indistinguishable on the device.**
   Pre-flight shows `push_tokens = 1` — their Build 17 phone. Once the key is in, notify functions post for real,
   so a sandbox event can put a payment-shaped notice on their lock screen; against their own product truth that a
   refund notice may only mean a confirmed refund, that is the false signal they care about. Not a reason to
   refuse (a), but they must know it before choosing.
3. **A live 2-minute sweep cron changes my witness method.** The ruling says stop on a count mismatch, but with a
   cron mutating rows every two minutes, drift between reads is expected, and a stop condition that fires on
   normal activity is one that gets waived — which is how a real mismatch gets talked away. So V0 is taken
   immediately before *each* apply, and every difference is attributed through `cron.job_run_details` first. A
   mismatch I cannot attribute to a recorded cron run is still a stop.

**Secret-insert mechanism, reviewed before it exists (raised to A).** Suppressing stdout does not address where
this value would actually leak, because it travels to the server inside the statement text. Three places:
(1) **the server log on error** — `log_min_error_statement` defaults to `error`, so a failed `vault.create_secret`
logs the whole failing statement, secret included, and the failure case is exactly when somebody reruns it; the fix
is to make the inserting statement unable to fail, by checking the function, the free name and the privilege as
separate statements first; (2) **`log_statement` / `log_min_duration_statement`** on the sandbox, which must be
read rather than assumed — at `all`, the insert is logged on success too and the ordering fix does not help;
(3) **shell and psql history** — no `set -x` on any path, `PSQL_HISTORY=/dev/null`. What I check when A sends the
script: no `set -x`; the value never in an `echo`, a `RAISE`, a comment or a displayed `\set`; history off; the
pre-checks present; and the insert the only statement carrying it. **The dashboard route avoids all three**, since
the value never becomes a logged SQL statement on our side — a reason to prefer it if the owner is indifferent.

**Handset, 04:12Z relaunch — recorded UNEXPLAINED, not closed.** Row 15 passed on the owner's second relaunch
(`last_used` 04:16:34Z); the 04:12Z relaunch left no stamp and C attributes it to a silent client token-fetch
failure. That is an attribution, not evidence, and it is a one-in-two failure on exactly the flow the b2 device
matrix exercises. Alternatives it displaces: the register call was made and **refused** (131/135 both raise 42501
on a session predating the epoch, and the client's terminal branches show the user nothing), the call was never
made (gate or early return), or it succeeded against a different row. Asked C what distinguishes the two
relaunches, and whether anything at all is recorded on a failed `getExpoPushTokenAsync` or a failed register — if
nothing distinguishes those three cases anywhere, **that** is the finding: the registration path fails invisibly,
which is what made DV row 3 expensive. Not blocking today; much cheaper to settle now than on the second sighting.

**04:12Z relaunch — C's analysis accepted in part; hypothesis 2 is the live one and carries a finding.** C showed a
refusal is not silent in Build 17 (`recordFailure` persists, `publishRegistrationStatus({state:'failed'})` surfaces
it in Settings, and terminal kinds make `decideRegistration` return `wait` on every later attempt), so the 04:16Z
cold launch registering normally is inconsistent with a persisted terminal refusal; and 131 is not on the sandbox
(ledger 136 = 127–130, which my own SBX-2 read-back agrees with), so the epoch 42501 cannot have been raised there.
A's 04:14:53Z read also rules out a stamp on another row. **Hypothesis 1 displaced; hypothesis 2 stands.**

Three things I added rather than accepting the read as pending-decisive:
- **The API-log read needs a positive control.** "No `register_push_token` calls 04:11–04:18Z" proves no call was
  made only if the same query, same window, same filters also returns the 04:16:34Z registration we know happened.
  Without it, "no rows" is indistinguishable from "this log does not cover what we think", and Supabase's ~10 min
  edge/API ingestion lag has produced confident false absences on this project before.
- **"Transient kinds would have stamped by ~04:13Z" assumes the app stayed foregrounded for the full 30 s backoff.**
  Quit inside half a minute and the in-process retry never fires. It does not rescue hypothesis 1 (a transient
  refusal still persists a record), but the dwell time is an unknown in the inference and the owner can remove it.
- **F-611C-1, broadened by C, should land before the single build is cut.** A token-fetch or storage failure
  produces a `console.warn` and nothing else — no persisted state, no published status, nothing in Settings,
  nothing a server read can see. Every core row of the b2 device matrix ends in "did the challenge arrive?", and
  this defect makes a failed token fetch, a hang and a never-attempted call indistinguishable. Running the
  sprint's most evidence-hungry session against a client that fails invisibly is how DV row 3 repeats three more
  times. The build is cut after the sandbox application, so there is room; I put it ahead of anything cosmetic
  still queued.

Secret handling unchanged: I never see, echo or reconstruct the value; my verification is that a row exists under
the expected name and the first dispatch's status in `net._http_response`. If a script would print the value I say
so rather than run alongside it. Under (b) the manifest should say the sandbox stays outbound-silent, so DV-611 /
611S and every b2 device row are **deferred, not failed**, and C records them as untried.

Also recorded: A corrected the apply order in package §3 to 131 → 132 → 133 → 135 → 20260916000000 and is putting
it to the owner to correct in their own words; the window does not open until they do. `84ddd9a` is integrated at
`e6d9f2e`; head vs pin is one docs file and the tag is unchanged at `9bef640`. A's Vault-empty and 0/0 drift
readings are taken as reported and I verify both myself at V0.

## b2 — D's staged review plan (owner chose b2 on 2026-09-16; build shape (i), one combined build)
Owner: "Begin the independent review preparation against your six proof-of-possession conditions. Coordinate staged reviews with A/B/C as
components become ready." Authorized: isolated implementation, local testing, review, integration; one build after the combined commit
passes reviews and CI. NOT authorized: sandbox migrations or edge deploys before an approved application package; any production change.
Numbering per A: contract v3, migration **135**, pgTAP **202**.

### Gate 0 — contract v3 text (before the three implementations build on it)
Read `PUSH_TOKEN_CONTRACT_V3.md` against C1–C6 and 128/131's frozen text: every outcome named, the refusal texts the client matches, what a
pre-v3 client receives on each route, and the statement that a proof supersedes a stored secret. Findings go to A as text; no code depends
on my reading being late.

### Gate 1 — migration 135 (A): C1–C5
| Condition | What I verify | Negative control that must fail |
|---|---|---|
| C1 proof on every ownership-changing bind, no time window | rule 3, rule 5, and rule 1 for a token with ANY prior row (active, revoked or tombstoned) return `challenge_required`; a same-account refresh does not | remove the rule-1-with-history branch → my completed-redirect probe hands the token over again |
| C2 no bypass on the direct paths | client INSERT of a token with history refused; client DELETE writes a tombstone (or the grants are gone); the tombstone is not client-writable | drop the tombstone trigger → delete-then-register works from another account |
| C3 confirmation bound to the initiating user AND session | confirm from another user, another session, no session claim, expired, replayed, wrong nonce, wrong token → refused; nonce stored hashed; single-use enforced by the write, not by a read | accept any authenticated confirm → the victim's own app confirms the attacker's claim |
| C4 pending claim never disturbs the live row | while a challenge is open the existing binding stays active and deliverable; send paths exclude unconfirmed rows | let the claim deactivate the row → a challenge alone becomes a denial-of-service |
| C5 proof supersedes the stored secret | a device that proves possession takes the binding from any account, including one redirected before b2 and one whose hash it cannot match | require the hash as well → the redirected victim still needs support |
| structure | census/grants/manifest/expected_grants four-file rule; rollback identity; 202 with each control; 131's 198 and my K-2 probe unchanged | — |
Races to run: two proofs for one token at once; a proof racing 131's invalidator; a proof racing a credential change; lock order vs 131's
per-user advisory lock; a reclaim racing a confirm.

### Gate 2 — send-push challenge delivery (B): C6
Nonce never logged (assert on the log shape, not by reading code alone); per-user and per-token rate limits with a negative control; the
challenge send is service_role only and cannot be triggered by a client; a visible-code fallback carries "never share"; no secret in Sentry.

### Gate 3 — client v3 (C), second read after A
Echo only a challenge this device requested; no auto-confirm of a challenge the app did not initiate; pending state; fallback path; the
refusal copy for a pre-v3 build; K-2/131 delta and F-SELL-1 reviewed in the same pass (coordinated split with A so we do not double-cover).

### Gate 4 — combined stack at one commit
Harness once on the combined tree (131–134 + 135 + client + F-SELL-1), reverse-order rollback including 135, then the device rows with C.
Device matrix I require before "closed": iOS and Android; foreground registration; app backgrounded or killed during registration;
notifications permission denied; silent-push throttling fallback; reinstall (new token); two accounts on one install; a plant-then-claim from
a second handset that never activates; and the completed-redirect recovery — the case DV row 3 hit, which must now recover without support.

### Stack `@ d61970b` (= cb68811 + 134) — **final stack review PASSES**
CI 35046570214 green. Harness: **PASS 26 · FAIL 0 · WARN 3** · replay **153** · Gate-2 **32|102|37|37** = the stack's ci.yml EXPECT_* ·
grants = fixture (**69**) · manifest PASS · pgTAP **5123/5123** · production's 135-row line then the release chain · every release rollback
exact (131, 132, 133 and 20260916000000 individually) · S1/S2/S3 identical. The third WARN is my harness noting the timestamped file is in
neither production's 135 nor the default release list — A confirms its production position as the window's last migration (121 → … → 133 →
20260916000000).
Reverse-order rollback of all four (`probes/gate_reverse_rollback.sh`): candidate chain → apply 131, 132, 133, 20260916000000 (adds 31
identity lines; census 32|102|37|37) → roll back **134 → 133 → 132 → 131** → **0 identity lines differ from the candidate**, census back to
31|96|37|35.
**Reviewed content of the production-gate stack is complete from D's side: 131 + 132 + 133 + 134, all PASS.** Not on the branch and not
reviewed here: C's K-2/131 client delta. Not decided: the owner's b1/b2/b3 choice, and b2 itself if chosen. Nothing is applied anywhere and
no pass of mine authorizes an apply.

### Stack `@ cb68811` (= 6b058d2 + 132's 74a4371) — re-run: **PASSES**
CI 35045923123 green. Harness on the stack tree: PASS 25 · FAIL 0 · WARN 2 declared · replay 152 · Gate-2 32|102|37|37 · grants 69 ·
manifest PASS · pgTAP 5114/5114 · production order + release chain · 131/132/133 rollbacks each exact · S1/S2/S3 identical. Unchanged from
6b058d2, as expected for an edge-only delta. Evidence now sits at one commit.

### 134 re-check — `@ 5146040` (CI 35046284427 green, all five jobs): **PASSES from D**
The fix is test-only and I verified that: `git diff cdf29e2..5146040 -- supabase` is empty, so every SQL, rollback and edge result from the
cdf29e2 run below still stands. `PayRow` gains optional `buyer_id`/`mode`; vitest settlement-sweep 18/18; pgTAP 201 **9/9**.
**My own negative control:** on a clone of the 134 pgTAP database I applied 134's rollback (the `processing_stale` arm disappears) and re-ran
201 → **5 ok / 4 not ok** (A1, A6, A7, A9), matching A's control exactly. So 201 is load-bearing.
Production position accepted as A states it: `20260916000000_…` is the last version string in the tree, after production's tip
(20260909000000) and after 131/132/133, so the window's order is 121 → … → 133 → 20260916000000, carried as the last migration of packet
step 3. Deploy coupling: migration first, then the `enforce-transfer-expiry` edge; the old edge settles the new kind through
settle_verified_payment, a no-op for a failed intent — degraded, never wrong. **Nothing is applied anywhere; this is not an authorization.**

### 134 first review — `@ cdf29e2` — NOT PASSED at the time: CI was RED
CI run 35045881634 **failed**: "Typecheck / Lint / Unit tests" → `tests/settlement-sweep.test.ts(362,39): error TS2353: 'mode' does not
exist in type 'PayRow'` (the canceled-intent auction case's `payments` fixture). A fixture-type fix, not a product defect — vitest does not
typecheck. Everything else I ran is good and independent of that line:
- Harness: PASS 26 · FAIL 0 · WARN 3 · replay 153 · census 32|102|37|37 · grants 69 · manifest PASS · pgTAP 5123/5123 · production order +
  release chain · **134's rollback restores the catalog exactly** · S1/S2/S3 identical. Third WARN: my harness reports the timestamped file is
  in neither production's 135 nor the default release list and appended it — A to confirm its production position.
- **Numbering, reproduced not assumed:** on a clone of the stack DB, applying the timestamped file adds the `processing_stale` arm; then
  applying `20260906110000_settle_verified_payment.sql` — exactly what a fresh replay does AFTER a `134_`-numbered file — removes it again.
  Under LC_ALL=C `134_…` sorts before `20260906110000…`, and `20260916000000…` sorts last. A's rename is correct.
- Edge: the Phase 0 branch matches stripe-webhook's payment_failed path (same guarded pending|processing transition; hold release only for
  buy_now, only after the row is failed, best-effort); other statuses fall through to the settle path.
- vitest settlement-sweep 18/18 at the head; **my RED control**: the same file on the stack (cb68811) fails 4 of the 5 new cases, the fifth
  being the by-design "untouched" assertion.
Sign-off waits for a green CI at the fixed head.

### 132 delta `9d82247..74a4371` (N-132-1 taken) — **incremental look PASSES**; N-132-2 accepted as a disclosed residual
The sweep and the claim re-check are now one gate (`handOutBlocked`) at all three hand-outs — reuse, race-recovered and final — so the claim
is the last word before a secret leaves. Edge vitest at 74a4371: **85/85** (CI 35045455695 green). **My own RED control:** the new test file
copied onto 9d82247 fails exactly one test, N1, so the re-check is load-bearing. Only the edge and its tests changed; no SQL, so the census,
grants and rollbacks from the 9d82247 battery still stand.
N-132-2 (withdraw reads then cancels): B keeps it and discloses it (design c5ff1a1). I accept: the worst case is availability, never money —
the other request's client gets a dead secret and retries, and the reuse path self-heals (a `canceled` intent retires its row and a fresh one
is minted). Never cancelling would trade a millisecond window for permanent orphan intents no sweep arm reaches, and a metadata-bound
withdrawal cannot help because a replayed intent carries the first request's token.

### Production-gate stack `release/production-gate-20260918 @ 6b058d2` (candidate tip + 131 + 133 + 132) — **incremental review PASSES**
CI run 35045310911 green (all five jobs). Integrated harness on the stack tree: **PASS 25 · FAIL 0 · WARN 2** (the two declared:
20260906120000 archive 102 lines, 128 epoch table 10 lines) · replay **152** · Gate-2 census **32|102|37|37** = the stack's own ci.yml
EXPECT_* · grants = `expected_grants.txt` (**69** rows) · grant-decision manifest PASS · pgTAP **5114/5114** · production's 135-row line
reproduced, then the release chain · every release rollback exact, including 131, 132 and 133 individually · S1/S2/S3 identical across
fresh and production order.
Reverse-order rollback of the stack (`probes/gate_reverse_rollback.sh`, my own): candidate chain (149 files, the three excluded) →
apply 131, 132, 133 (adds 30 identity lines; census 32|102|37|37) → roll back **133 → 132 → 131** → **0 identity lines differ from the
candidate**, census back to 31|96|37|35. The merge resolution A described (EXPECT_TABLES 32, EXPECT_FUNCS 102, 162 P1/P2) matches what the
tree actually produces.
Nothing here is applied anywhere, and this review is not an authorization to apply.

### 132 — full battery on PR #70 head `9d82247` (CI 35044535546 green): **PASSES from D, with 2 LOW notes**
Scope: concurrency, retries, uncertain Stripe outcomes, duplicate prevention (owner's assignment). Earlier findings F-132-1 (cross-mode),
F-132-2 (cross-buyer best-effort retire), the reuse-order stall and F-132-3 (leftover older attempt) are all closed.
- Integrated harness at 9d82247: PASS 23 · FAIL 0 · WARN 2 declared · replay 150 · census **32|99|37|35** · grants = fixture (**69**) ·
  manifest PASS · pgTAP 5030/5030 · production order + release chain · **132 rollback restores the catalog exactly** · S1/S2/S3 identical.
- `probes/probe_132_record_attempt.sql` (semantics): anon/authenticated denied on all three verbs and on the table · wrong token →
  `claim_lost`, 0 rows · right token → `recorded`, row shape pending|buy_now|10000|1000|1000|11000|livemode f|buyer ok · duplicate intent
  still raises 23505 (not swallowed) · after a real reclaim the old token records nothing (0 rows) and the claim's mode follows the new
  holder · release is token-bound and group-wide (`token_mismatch`, `released`, `not_claimed`) · no claim → `claim_lost` · null token →
  `missing_argument`.
- `probes/race_132_record.sh` (two live sessions, my own): R1 holder records first → the reclaim WAITS 2513 ms, then claims and sees the
  row to reuse · R2 reclaim first → the holder WAITS 2549 ms, gets `claim_lost`, writes 0 rows · C1 plain-insert control → the reclaim does
  not wait (100 ms) and sees 0 rows (the defect) · **C2 my own in-DB mutant, FOR KEY SHARE → the reclaim stops waiting**, so FOR SHARE is
  load-bearing.
- B's two-session script re-run independently: G1–G8 + C1–C4 all PASS (G7 2554 ms, G8 2548 ms).
- Cross-mode probe re-run: the second mode is now `claim_held` (group key is (listing, buyer)). Steps 6–7 of that probe bypass the edge and
  are kept only as the shape of F-132-1.
- Edge: vitest l1-edge-coupling + checkout-intent **84/84** at 9d82247. **Independent RED control**: the same two test files copied onto
  `ebbd1c0` fail **9** tests, including Q1 (my stalled-record case), Q2, Q3 and T1–T4 — so the new evidence is load-bearing, not tautological.
| # | Severity | Note (neither blocks 132) |
|---|---|---|
| N-132-1 | LOW | `otherLiveAttemptsCleared` runs AFTER the last `claimGuard.check()` and makes bounded Stripe calls, so the guard verdict is stale by the sweep's duration. The budget (90 s) still ends before the 120 s lapse, so no reclaim can intervene, but re-checking after the sweep would restore "the last word before a secret leaves" |
| N-132-2 | LOW | `withdrawUnrecordedIntent` reads `payments` then cancels; a concurrent request could record that intent in between. The window is milliseconds and it only reopens B's own Q1 defect in miniature. Alternative: never cancel on the claim-lost path and let the orphan expire |
Evidence limits: edge behaviour is proven by vitest against the real handler with injected Stripe/DB, not by a hosted run; the sandbox has
132 applied nowhere; Stripe's own idempotency replay is simulated.

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

## 2026-09-17 — build-source merge, the two-second window, and the owner's critical-path asks

**`aad5f75` merge verified (a diff, not a re-review, as the owner asked).** Its tree is exactly `e6d9f2e` + the two
heads I passed and nothing else: 10 files differ, every one **byte-identical** (`git hash-object`) to its source —
six to `a609cbc`, four to `8dc4cec`. The two branches touch **disjoint file sets**, which is what makes the
file-wise union lossless by construction: no merge resolution could have dropped one side. Union 10, merged 10.
`supabase/` diff empty, gated-surface diff empty. Base `e6d9f2e` differs from the sandbox pin `9bef640` by the one
docs-only runbook file. Sandbox pin stays clean; the build source is a strict superset of reviewed material.

**Two-second epoch window (owner ask, answered jointly with C).** Verdict: **understandable and recoverable, no
silent failure found in source, one LOW copy finding.** The reframing that matters: the margin is not the main
route — `push_session_predates_epoch` bars *every* pre-epoch session, so this is the ordinary post-password-change
experience and the two seconds only extend it. That removes the "too narrow to matter" argument.
- Register path verified by me in the tag's source: the hook persists the failure, **publishes
  `{state:'failed', kind:'session_stale'}` to Settings, and only then** forces the local sign-out — so the remedy
  is visible either way, and the login copy is true by the time it is shown.
- **F-2S-1 (LOW, copy), verified independently:** `session_stale` appears in the hook at exactly two places, a
  comment and the register branch — **the challenge path does not route into `handleSessionStale`**. A challenge
  refused across an invalidation shows `challenge.ts:255` "You were signed out on this device…" **while the user
  is still signed in and the app is working**. I differ from C's first remedy: prefer the **neutral copy**, not
  routing the challenge path into a forced sign-out — that is a materially bigger behaviour change out of a
  background push flow, and the register path forces re-auth at the next attempt anyway.
- No silent path found; C's one constructed edge (network drop between refusal and local sign-out) recorded rather
  than dismissed. **Device-untested** for the exact 2 s case — DV-131-1 and DV-131-2 are what turn "found none"
  into "proven none".

**Critical-path inputs and the environment resolution** are in
`docs/venue-dashboard/CRITICAL_PATH_INPUTS_D_20260917.md` (`a8cd818`). Headlines: trust root live / door edges dark
are **production-only** facts (sandbox has neither — `signing_key` 0 from my own reads, and A's `functions list`
shows nine functions with no door/credential one; local has neither and no edge runtime); **D-ONB-1 cuts the other
way from the report** — 107 *un-parks* `mint_door_session` and 107 is applied, so scanning is gated by the flag,
the dark edges and the absence of data, not by a parked function; the **operator surface is the real onboarding
blocker and has no owner**; and **scanning is downstream of primary sales**, since tickets come from
`issue_ticket_atoms` on a primary `payment_intent.succeeded` and `primary-checkout` is not deployed. Venue
acceptance needs the owner at **two** moments (B4 exposure 3 min; evidence review 5 min; ≈10 min owner, ≈8 min
automated, 25–30 min end to end), and `venue_api` is on **neither release branch**, so the evidence would age
against a branch nothing ships from unless A sequences that merge.
