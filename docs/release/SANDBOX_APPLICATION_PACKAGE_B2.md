# Sandbox application package — production-gate candidate with b2 (A, 2026-09-16; owner APPROVED IN PRINCIPLE 2026-09-16, see §9)

**Scope requested:** apply the reviewed production-gate content to the shared sandbox `ofaidukbieeekqaboscm` only, so the
combined build can be verified on a handset. **Nothing here touches production.** Execution is serialized through A with
`scripts/release/apply_sandbox_migration.sh` (asserts the sandbox ref twice, refuses production, records each ledger row from
the pinned file's exact bytes, md5-verified); D witnesses.

**Pinned commit: `candidate/2026-09-18-pin-b2` = `release/production-gate-20260918 @ 9bef640`** (annotated tag, pushed
2026-09-16; the earlier `candidate/2026-09-18-pin` = `aabe029` is kept, untouched, and stays identifiable as the source of the
SBX-2 window and Build 17). Every migration, rollback, test and edge in §3–§4 is taken from this tree.

**Evidence at the pin.** GitHub CI run 35053607616 at `9bef640`: 5/5 jobs green; pgTAP files=85, tests_ran=5186, result PASS,
masking gate 0/0/0. D Gate 3 PASS at `9bef640` (D's log `26d69d9`): the merge chain checked byte-for-byte against the heads D
passed (`cd996df` = 135 + rollback + 202 + send-push identical, nothing else under `supabase/migrations`; `0e8de77` = C's four
client files identical to `e8114df`, SQL unchanged; `9bef640` = one new 74-line test file only); full-chain rehearsal at
`0e8de77` PASS 27 / FAIL 0 / WARN 3 (the two pre-existing rollback WARNs on 20260906120000 and 128), census 32|105|37|38, both
orders converge; reverse-order rollback 20260916000000 → 135 → 133 → 132 → 131 leaves 0 lines differing from the candidate,
census back to 31|96|37|35; C1–C6 matrix 0 errors with all four negative controls flipping; push/auth suites 97/97; every string
the client keys on verified against the migrations' `raise exception` sites with comments stripped (twelve raised; `nonce
mismatch` is a dead v2 branch); C's classifier guard fails by name on each of three mutations of 135.

**pgTAP count note (D, confirmed by A at the pin):** CI reports `files=85 tests_ran=5186`; the local harnesses (A's and D's) report
`plan=5180`. The six are `000_helpers.sql`'s own `plan(6)`: the local harness runs it as the bootstrap that commits the `tap`
schema and excludes it from the totals (84 files, 5180); CI runs it as an ordinary test file (85, 5186). A summed the declared
plans at `9bef640`: all 85 files 5186, the 84 excluding the helper 5180, no file without a literal plan. Both runs are
complete; nothing is unrun.

**Docs-only commits above the pin (applied bytes unchanged, tag stays at `9bef640`):** `5e8b0f4` integrates B's runbook
correction `5225557` (D-135-5, D PASS). B's follow-up `84ddd9a` (D-135-6: an interim route for the challenge-history
precondition until D's console read exists; "challenge history unavailable" recorded literally, never blank) is with D and is
integrated on D's PASS. A verifies each as one file, no SQL, direct descendant of the pin.

## 1. Pre-flight (read-only, immediately before)
Ledger 136 and versions >109 = 123,124,125,127,128,129,130; native flags all false; `kernel.tickets` 0, `signing_key` 0;
counts as manifest §10; L-1 = 0; push_tokens: exactly one row (`140fcb44…`, the buyer's after Path B). **Drift counts,
corrected after the pre-flight of 2026-09-16 04:10Z:** the production-host counts 4 / 5 are production's; on the sandbox they
are **0 / 0**, because SBX-1/2 rewrote the notify bodies and three crons out of band with the *sandbox* host literal (functions
naming the sandbox host: `notify_bid_placed`, `notify_moderation_event`, `notify_transfer_event`, `kernel.check_signing_key_invariants`;
crons: `crm-export-build-tick`, `payout-execute-tick`, `refund-execute-tick`; `notify_outbid` reads a GUC). 133 replaces all of
them with the Vault form, so after 133 no routine or cron names any Supabase host literally (proof: 0). **Sandbox Vault is
empty** (no `service_role_key`, no `project_url`), see §2. Stop on any difference from these corrected values. D recaptures
its V0 values at the start of the window with its read-back script (the sandbox ledger moved during SBX-2, so D's manifest V0
is not reused).

## 2. Vault ceremony (sandbox, before 133) — A runs, D witnesses
Insert Vault secret `project_url` = `https://ofaidukbieeekqaboscm.supabase.co` (no trailing slash) — the one new secret the
owner's ruling names. Verify `select count(*) from vault.decrypted_secrets where name='project_url'` = 1 (names only, never
values). **Corrected after the pre-flight:** the sandbox Vault carries **no** `service_role_key`, so 133's §0 refusal would not
have fired here either way; the ceremony is still performed because it is what makes the sandbox exercise 133's real
URL-from-Vault path and its `where exists (project_url)` cron guard. **No `service_role_key` is inserted** (excluded: new
secrets). **Consequences on this sandbox (recorded):** (a) the four rewritten functions post only when key AND URL exist, so
they stay inert exactly as today; (b) 133 creates the `enforce-transfer-expiry` cron the sandbox lacks, and because
`project_url` exists it fires every 2 min at the sandbox edge with an empty bearer (the sandbox edges are deployed
`--no-verify-jwt`; the edge's own handling of a missing bearer is recorded in §5 from the pin's source, and the first two runs'
statuses in `net._http_response` are read back by A and D before moving on); `crm-export-*` stay inert (no worker secret),
`refund/payout-execute-tick` stay inert (flags false); (c) the out-of-band notify bodies and the three sandbox-host crons are
replaced by the Vault form; (d) 133's purge of production-host queue rows is a no-op here (queue 0, none naming production).

**§2a. OWNER DECISION REQUIRED before the window — the empty Vault also kills every b2 challenge push (D, verified by A from
the source at the pin and from the sandbox).** 135's `notify.issue_push_token_challenge` posts to `send-push` only when
`project_url` exists, with `'Bearer ' || coalesce(service_role_key, '')`; `send-push`'s `isAuthorized` returns false on a
length mismatch before comparing, so an empty bearer is refused with 401. After the ceremony, `register_push_token` answers
`challenge_required`, the challenge row is written, the post is queued, `send-push` refuses it and no push arrives; the
client's 60-second fallback (`request_push_token_challenge`) dispatches through the same path, so the visible code never
arrives either. **The refusal is invisible in the database:** the verb's handler catches only a failure to queue; pg_net is
asynchronous, so the 401 lands in `net._http_response` and the challenge row stays a healthy-looking pending challenge with
`delivery_outcome` null (`record_push_token_challenge_delivery` is never reached). Today the sandbox has no working pg_net
post at all: the only routine posting to `send-push` (`notify_outbid`) is guarded on the key, and `net._http_response` holds
0 rows for the last 24 h — so Build 17's push-*delivery* rows (DV-611/611S) cannot pass on this sandbox either; only
registration rows can. Options, one line each:
- **(a) Add `service_role_key` to the sandbox Vault as a second named exception to "new secrets"** (the `project_url`
  reasoning applies: it is what makes the window able to reach its purpose). Performed either by A from the sandbox
  environment's existing `TEST_SERVICE_ROLE_KEY` value through a script that never prints it (the value never transits chat
  or a record), or by the owner in the sandbox dashboard; D verifies names only (`project_url` and `service_role_key` rows
  exist) and reads the first challenge dispatch's status in `net._http_response`. **Consequence:** the sandbox's outbound
  function posts go live in general — 133's `enforce-transfer-expiry` cron then really runs every 2 min against sandbox
  data (Phase 0 refunds of sandbox test rows), the four notify functions post for real, and notification pushes reach any
  handset registered on the sandbox (today: the owner's). `crm-export-*` stay inert (no worker secret), `refund/payout-execute-tick`
  stay inert (flags false).
- **(b) Keep the exclusion.** The window then proves schema, verbs, grants, rollbacks and the migration chain — real value —
  but **b2 device verification is deferred**: the challenge → push → echo → rebind path stays unproven, the device matrix's core
  rows stay open, and the one build cannot be validated against the sandbox for the feature it was cut for. If (b) is chosen
  this file and the manifest say so in those words, so "sandbox application passed" is never read as "b2 works on a handset".
**A's and D's recommendation: (a), performed by A from the environment value with D witnessing names only.** Mechanics if A
performs it: `scripts/release/sandbox_vault_ceremony.sh` (converge branch; D read it in full), modes `check → url → verify-url →
key → verify-key`; the server asserts its own sandbox identity before any write (ledger 130..141, no `ops` schema, sandbox-only
`public.sandbox_gucs` present — CS-1, D); the insert is `vault.create_secret($1,$2,$3)` via psql `\bind` so the value is a
protocol parameter, never statement text; the sandbox logs only DDL, no duration logging, no parameters on error (re-read by
the script, STOP otherwise); `\getenv` (no argv, no subprocess), `PSQL_HISTORY=/dev/null`, no `set -x`; known property: the
key sits in the script process's environment for its lifetime (same-user `ps eww`), accepted. The owner's dashboard paste
avoids all of this on our side and is equally acceptable. Three conditions travel with (a), agreed by A and D:
1. **Ceremony order is fixed: `project_url` first, verified, then `service_role_key`.** D verifies between the two steps that
   the URL row exists and its value has the sandbox host's shape (`https://ofaidukbieeekqaboscm.supabase.co`; shape only,
   never the secret), and again after the key lands. Reason: with the key present and a wrong URL the sandbox would send
   authenticated-looking traffic at whatever host the URL names; with the URL first and no key, a wrong URL produces an
   empty-bearer request that is refused. A sandbox posting at the production host, even to collect a 401, would be an
   unauthorized production contact, and the ordering makes it impossible.
2. **(a) means real push notifications arriving on the owner's real handset, from the sandbox, with nothing on the device
   distinguishing them from production.** `push_tokens = 1` is the owner's Build 17 phone. Once the key is in, the notify
   functions post for real, so an ordinary sandbox event can put an auction-ended or payment-shaped notice on that lock
   screen. Under the product truth that a refund notice may only ever mean a confirmed refund, a sandbox-originated payment
   notification on a personal phone is exactly the false signal the owner cares about. Not a reason to refuse (a); a thing
   to know before choosing it.
3. **Witness method with a live 2-minute cron:** the ruling's "stop on count mismatch" would otherwise fire on normal cron
   activity and get waived, which is how a real mismatch gets talked away. So D takes V0 immediately before each apply rather
   than once at window start, and attributes every difference between reads using `cron.job_run_details` before calling it
   either way. **A mismatch that cannot be attributed to a recorded cron run is still a stop.** A applies nothing while a
   read is unexplained.
If (b): the sandbox stays outbound-silent, so DV-611/611S and every b2 device row are **deferred, not failed** — C does not
record them as attempted — and this file and the manifest say "b2 device verification deferred" in those words.

**Operating assumption from 2026-09-16 04:30Z: (b).** The owner told C that the sandbox push service key is DEFERRED and that
b2 real push-delivery verification is BLOCKED until deliberately approved. That reached A relayed by C, not in the owner's own
words in A's session; a relayed *restriction* is honoured immediately (stopping needs no authorization), so A and D operate
on (b) now: **b2 device verification deferred**, the push-dependent rows deferred-not-attempted, the `project_url` ceremony
still performed (§2), no `service_role_key` inserted. A relayed *permission* would not be honoured the same way: if the owner
later approves the key, it takes effect only in their own words. The apply-order confirmation (§3) remains outstanding.

## 3. Migrations, in order, each `preflight → apply → verify` (ORDER_GUARD_SKIP=126 stays declared)
`131` (session-bound bindings) → `132` (pre-mint group record) → `133` (config-driven functions URL) → `135` (proof of
possession) → `20260916000000_processing_sweep_arm` (the migration the records call "134"). **Order corrected 2026-09-16
(D, at Gate 3):** under the chain's `LC_ALL=C` order `135_` sorts before `20260916000000_`; that is the order CI replays, the
order D's four rehearsals used and the order the reverse-rollback gate proved; 134 was timestamped precisely so it sorts last.
The owner's ruling wrote "131 → 132 → 133 → 134 → 135" and this file's earlier draft repeated it; applying the sweep migration
before 135 would put the sandbox in a state no replay, CI run or rollback test has produced. **The owner confirms the canonical
order before the window opens.** Expected ledger 136 → 141. After each: the object spot-check from the registry row; census
after the last apply: public 32 | 105 | 37 | 38 (the sandbox will differ by its known deltas — no 119 guard, +`sandbox_gucs`,
+`sandbox_pre_request` — D records the explained numbers).

## 4. Edges, from the pinned tree, `--project-ref ofaidukbieeekqaboscm --no-verify-jwt` (parity with today's sandbox)
`stripe-webhook` first (already v4 from the candidate pin; redeployed from the new pin for byte parity, no behaviour change).
After 132: `create-payment-intent` (132's edge; 503 fail-closed without 132). After 135: `send-push` (challenge kind). After
20260916000000, last: `enforce-transfer-expiry` (134's Phase 0 branch). Parity check after each: `supabase functions download`
into a scratch dir, `cmp` against the pin (A and D independently).

## 5. Verification and read-backs (documented; the DV rows of the combined build)
DV-V1..V4 (silent challenge, 60 s fallback with a visible code, wrong-then-right code, staged stale echo), DV-P1..P5 (K-2 and
131 rows), F-SELL-1 create/edit incl. large text, DV-ST1..ST4 (state views), Blocks 2/2b (checkout previews, 132 on the sandbox),
DV-134 (a processing row resolved by the sweep, staged). A stages fixtures and does the read-backs; D witnesses and reviews.

**`enforce-transfer-expiry` bearer check (read from the pin's source):** the edge accepts only a bearer equal to its
`INTERNAL_CRON_SECRET` or `SUPABASE_SERVICE_ROLE_KEY` function secret (constant-time compare) and refuses anything else. With
the sandbox Vault carrying no `service_role_key`, 133's cron posts with an empty bearer and is refused on every 2-minute tick:
**no sweep runs from cron on this sandbox**, and the refused ticks in `net._http_response` are read back as evidence of the guard
(first two ticks, A and D). DV-134 therefore invokes the edge directly with an existing sandbox bearer (`INTERNAL_CRON_SECRET`
exists as a sandbox function secret, set 2026-09-07; the service-role key likewise) — nothing new is created or inserted; if no
existing bearer value is available to A in the sandbox environment, DV-134 is deferred and recorded rather than improvised.

## 6. Cleanup and closing read-back
Fixture rows deleted by exact id; DV users' push rows left as the session ends them; counts back to baseline (+ledger rows, +the
new cron, +Vault `project_url`); closing census recorded in manifest §10.

## 7. What this package does NOT include
No production change of any kind; no native activation; no signing; no `ops` migrations (126 stays deferred here); no venue
phase (separate window, D's runbook); no build. The one authorized build (owner ruling 2026-09-16: "one additional build after
the combined commit passes required reviews and CI") has its conditions met at the pin; A recommends C cuts it from
`candidate/2026-09-18-pin-b2` only after §3–§4 complete on the sandbox, so the single build is not spent before the server side
it depends on is confirmed applied. Cutting it earlier is the owner's call.

## 8. Carried for the owner's decision or acknowledgement (from D's Gate 3)
1. **Notice channel (decision):** `security_device_rebound` is in-app only. A previous owner of a device who never opens the
   notification centre is never told that another account claimed their device. Accept as is, or authorize an email row (an N1
   exception). Either way the package applies unchanged; an email row would be a later migration.
2. **Evidence limit (acknowledgement):** every result above is local. `net.http_post` and `vault.decrypted_secrets` are stand-ins
   in the harness, so no real pg_net, Vault, APNs or FCM behaviour is proven, and there is no device evidence yet. The device
   matrix on the one build is the whole remaining risk of b2.
3. **D-135-5 and D-135-6 (LOW, B's runbook, closed):** `docs/operations/SUPPORT_RUNBOOK_PUSH_TOKEN_UNBIND.md` at the pin still
   said `unbind_push_token` DELETEs the row and listed RB-1 as open; on this stack it tombstones (`support_unbound`), which D
   verified in a replayed database. B's docs-only fixes `5225557` (D-135-5, D PASS) and `84ddd9a` (D-135-6: an interim route
   for the challenge-history precondition until D's owner-gated console read exists; "challenge history unavailable" is
   recorded literally, never blank; an engineer-run production read is an escalation, not a routine substitute; D PASS) are
   integrated on the stack at `5e8b0f4` and `e6d9f2e`. Both change one documentation file and no applied bytes; the pin stays
   at `9bef640`. **D measured the interim gap** (probe `probes/probe_135_unbind_recovery.sql`, D log `261eec3`): on the pin, a
   support unbind talked out of an agent is a nuisance-level denial that self-heals — the original device re-registers as
   `refreshed` from the same or a new session, proof re-stored, no challenge, no support contact — while any other account still
   gets `challenge_required`. It is not the redirection path the owner required closed.

## 9. Owner ruling 2026-09-16 (approval in principle; conditions and exclusions, in the owner's words)
"I approve the sandbox-only B2 application package in principle, subject to the final pin/package confirmation." **Before
executing, A must:** complete D's review of the support-runbook correction; publish the final immutable tag and commit hash;
update this file to name that exact hash; confirm CI and Gate 3 evidence correspond to the named commit. **Then the serialized
sandbox window is authorized:** migrations 131 → 132 → 133 → 134 → 135 in this order; the sandbox Vault `project_url`
ceremony before 133; only the four listed sandbox edges; all specified read-backs, device checks and cleanup; stop immediately
on any unexpected state, failed invariant, count mismatch, byte mismatch or rollback discrepancy. D witnesses the execution
and independently verifies the final state. **The one combined preview build is cut only after the sandbox application and
edge verification pass.** **Excluded:** production, venue exposure, native issuance, scanning, feature flags, AWS changes, new
secrets (the sandbox `project_url` ceremony is the named exception), and any other edge deployment. **§8.1 decided:** the
device-rebound notice stays in-app only; email remains unapproved. Before starting, A returns the final pin, package hash,
pre-flight results, exact owner actions and expected duration.

**Named commit:** tag `candidate/2026-09-18-pin-b2` = `9bef640` (annotated, pushed, not to be moved). CI run 35053607616 has
`headSha` `9bef640…`; D's Gate 3 log `26d69d9` names `9bef640`, and D re-resolved the tag to `9bef640` with a tree identical to
the commit it passed. The stack branch head carries only the docs-only runbook commits above the pin.

A stops on any unexpected state or uncertain mutation outcome, as before.
