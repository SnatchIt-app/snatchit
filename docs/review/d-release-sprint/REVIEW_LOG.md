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
