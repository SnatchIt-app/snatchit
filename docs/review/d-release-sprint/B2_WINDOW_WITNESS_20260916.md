# B2 sandbox window — D's independent witness record (2026-09-16)

**Role:** read-only witness. D applies nothing, writes nothing, and holds no secret value. Every reading below is
taken by D against the sandbox `ofaidukbieeekqaboscm` with a hard refusal on the production ref in the connection
string. Probe: `probes/sandbox/v0_witness.sql` (read-only; no DDL, no writes).

**Authorization in force:** the owner's ruling of 2026-09-16 — apply order `131 → 132 → 133 → 135 →
20260916000000`, option **(b)** (no sandbox service key; b2 push-delivery verification deferred, not attempted),
the `project_url` ceremony required before 133, and "No production reads, migrations, edge deployments, flags, AWS
changes or build submission are authorized by this message". A reconfirms immediately before each write; D reads
before each. Execution commit `9bef640`; ceremony script final review **`685340f`** — verified by D to refuse
`key` at entry with `exit 3` **before** any pre-check, so the owner's deferral is enforced ahead of every other
guard.

**D's four stop invariants:** (1) `vault.secrets` holds exactly one name, `project_url`, from the ceremony to the
close — names only, never values; (2) V0 immediately before each apply, every difference attributed through
`cron.job_run_details` before acceptance, an unattributable difference is a stop, and A applies nothing while a
read is unexplained; (3) `project_url` names the sandbox host, checked between `url` and `verify-url` and again
after 133; (4) zero production-host references in routines and cron at the close.

---

## V0 — baseline, 2026-09-16 04:35:37Z (before any write)

| Reading | Value |
|---|---|
| identity guard (ledger 130..141, no `ops`, `public.sandbox_gucs` present) | **true** |
| ledger rows | 136 |
| versions > 109 | 123, 124, 125, 127, 128, 129, 130 (+ the six timestamped) |
| Gate-2 census (public tables\|functions\|policies\|triggers) | **31\|97\|37\|34** |
| **INV1** `vault.secrets` | **0 rows, names `(none)`** |
| **INV4** production-host refs in routines / cron | **0 / 0** |
| cron jobs | 21; **no `enforce-transfer-expiry`** |
| `net.http_request_queue` | 0 |
| `net._http_response` | **2 rows — see the correction below** |
| `auth.sessions` non-internal triggers | **(none)** |
| `push_tokens` rows / `session_id` column | 1 / **absent** |
| 131/132/135 objects (`revoke_all_push_bindings`, `checkout_group_claim`, `notify.push_token_challenges`, `confirm_push_token_challenge`) | all **absent** |
| kernel tickets / signing_key | 0 / 0 |
| native flags (resale, issuance, scanning) | all **false** |
| L-1 (`refunded` with NULL `refunded_at`) | 0 |
| business counts | listings 49 · payments 51 (3 pending) · transfers 33 · bids 0 · listings_reserved 0 |

### Correction to the package's §10 table — `net._http_response` is 2, not 0
Both rows are **401s from 2026-09-07**, at 16:04:00.128Z and 16:06:00.258Z — two minutes apart, the signature of
the `*/2` `enforce-transfer-expiry` cron firing twice before that cron was removed from this sandbox. Nothing in
flight; the queue is genuinely 0. A's earlier reading, "0 rows **in the last 24 h**", was correct; the table
dropped the window and recorded a plain zero.

This matters in both directions at the close. If the baseline is recorded as 0, then 2 reads as two posts that
never happened; and if two *real* posts appear, 4 gets shrugged off as the old pair plus noise. **So the close
condition is a timestamp, not a count: any row created after 2026-09-16T04:35:37Z is new and must be attributed.
The newest pre-existing row is 2026-09-07 16:06:00.257881Z.** Sent to A to correct in §10.

### Two readings the package's table does not carry
- **`auth.sessions` has no non-internal triggers at all.** This is independent confirmation of the row-17 /
  DV-607a limit recorded earlier: 131's `trg_push_bindings_on_sessions_gone` is not present, so a server-side
  session delete on this sandbox cannot exercise the A-131-K2 behaviour. Evidence now, not inference.
- **Business counts at V0**, above — the baseline drift is attributed against under invariant 2.

---

## Window progress

| Step | A announced | D read | Result |
|---|---|---|---|
| V0 baseline | — | **04:35:37Z** | taken; one §10 correction raised; **"proceed" given for `url`** |
| ceremony `url` (write 1) | 04:37:06Z | **04:38Z** | **OK** — `vault.secrets` = exactly one name `project_url`, value equals `https://ofaidukbieeekqaboscm.supabase.co`, no secret names production; census `31\|97\|37\|34` and ledger 136 **unchanged** (a Vault write should touch neither); prod-host refs 0/0; queue 0, **0 responses after V0**. "Proceed" given for 131 |
| **131 apply** (write 2) | announced | **04:41Z** | **OK** — ledger **137**, version `131`, 1 statement, ledger `stmt_md5 e07ac078f151fc68589286d0acfb16f5`. Census **31\|100\|37\|36** = V0 +3 functions, +2 public triggers, and the +2 are named: `trg_guard_push_token_session_row`, `trg_guard_push_token_session_stmt`. `auth.sessions` now carries **exactly one** non-internal trigger, `trg_push_bindings_on_sessions_gone`, `tgtype=8` (after-delete, statement-level) — the A-131-K2 shape I reviewed. `revoke_all_push_bindings`, `kernel.invalidate_push_bindings_for`, `kernel.push_session_predates_epoch` present; `push_tokens.session_id` present. **INV1** `project_url` only · **INV4** 0/0 · queue 0, **0 responses after V0**. **Zero business drift** (49/49, 51/51, 3/3 pending, 33/33, 1/1) with 16 cron jobs run since V0, all attributed through `cron.job_run_details`, none moving a row. "Proceed" given for 132 |

| **132 apply** (write 3) | announced | **04:45Z** | **OK** — ledger **138**, 1 statement, `md5 ecdd91761e3849ea73190f174cf2681c`. Census **32\|103\|37\|36** = +1 table, +3 functions. `checkout_group_claim` present and **empty**; `claim_checkout_group`, `record_checkout_attempt`, `release_checkout_group` present; table grants **service_role only** (no anon, no authenticated). INV1 `project_url` only · INV4 0/0 · queue 0 · **0 responses after V0** · zero business drift. "Proceed" given for 133 |
| 133 rollback capture | 04:44:23Z | **04:47Z** | **list confirmed complete** — see below |

| **133 apply** (write 4) | 04:47:05Z | **04:48Z** | **OK** — ledger **139**, `md5 c08f8295…` (reproduced from the pin). Census unchanged **32\|103\|37\|36** (bodies only). INV4 **strengthened beyond production**: zero `https://<anything>.supabase.co` literals in any cron command or routine body across public/kernel/notify/venue/catalog — the out-of-band sandbox-host literals SBX-1/2 left are gone, which only a sandbox read can confirm. 22 crons, all active, all reading the URL from Vault. **Destination attested:** cron command → Vault `project_url` (verified = sandbox) → sandbox edge → 401. **Prediction held:** one tick, `enforce-transfer-expiry`, id 3, status **401**, 04:48:00.249691Z, `error_msg` null; no other job posted |
| **135 apply** (write 5) | 04:49:56Z | **04:51Z** | **OK** — ledger **140**, `md5 28e01d25…` (reproduced). Census **32\|106\|37\|37**, reconciliation verified by naming objects not arithmetic: `sandbox_gucs` present, `sandbox_pre_request` present, 119's `guard_listing_seller_not_blocked` and its trigger **absent** ⇒ +1 function, −1 trigger against the pin's declared 32\|105\|37\|38. All six 135 surfaces present, challenges table empty. **`notify.push_token_challenges` carries no grants at all** to anon/authenticated/service_role — the 157 B9 premise B's send-push rests on, until now verified only on my local harness. `confirm` executable by `authenticated` not `anon`; `issue` not executable by `authenticated`; `get` executable by `service_role`. All four `push_tokens` triggers present incl. `trg_guard_push_token_client_delete`. `security_device_rebound` = `{}`/`{}`/mandatory, `in_app` template only. 3 ticks after V0, **all 401, non-401 count 0**; zero drift. Expected md5 for `20260916000000` given to A **in advance**: `b1fda89070efa7a9ba24f5aee4492064` |

| **`20260916000000` apply** (write 6) | 04:53:14Z | **04:53Z** | **OK** — ledger **141**, `md5 b1fda89070efa7a9ba24f5aee4492064` **matching the value I gave A before the apply**. Census unchanged 32\|106\|37\|37 (adds no object) |
| edge deploys (writes 7–9) | 04:54–04:55Z | **04:57Z** | **OK** — `create-payment-intent` v5, `send-push` v4, `enforce-transfer-expiry` v4; `stripe-webhook` untouched. Parity byte-identical to `/tmp/wt-pin` |
| **CLOSING READ** | — | **04:57:13Z** | **PASS** — see below |

## Closing state — 04:57:13Z, read by D

| Reading | Value |
|---|---|
| ledger | **141**, holding exactly `131, 132, 133, 135, 20260916000000` |
| census | **32\|106\|37\|37** (expected final) |
| **INV1** | `vault.secrets` = `project_url` **alone**, count 1 — held at every checkpoint |
| **INV3** | `project_url` names the sandbox host |
| **INV4** | production refs 0/0; **zero `*.supabase.co` literals** in any cron command or routine body |
| ticks after V0 | **5, all 401, zero 2xx**, at 04:48, 04:50, 04:52, 04:54, 04:56 — one job, on its two-minute schedule, no gaps, no extras. Queue 0 |
| business drift | **zero** — 49/49, 51/51, 3/3 pending, 33/33, 0/0 bids, 0/0 reserved, 1/1 push_tokens |
| new tables | `checkout_group_claim` 0 · `notify.push_token_challenges` 0 |
| unchanged | kernel tickets 0 · signing_key 0 · L-1 0 · all three native flags false |
| handset row | untouched from row 16 — inactive, `signed_out`, `session_id` null, **proof kept** |

The tick **cadence** is itself evidence: a second posting job would appear as an off-beat row, and none exists.

### Boundary statement (given to A verbatim, to carry unparaphrased)
This window establishes that the five migrations apply cleanly in production order, that the resulting catalog
matches the pin, that the grant matrix and the tombstone guard are live, that no production host is reachable from
this database, and that no outbound request can authenticate. **It establishes nothing about whether b2 works.**
Under option (b) the challenge path cannot be exercised: `send-push` refuses every dispatch by construction, no
notification can reach a device, and the whole device matrix — challenge delivery, echo, rebind, two accounts on
one install, plant-then-claim, recovery without support — is **deferred, not attempted and not passed**.
"Sandbox application passed" must never be read as "b2 works on a handset".

### Evidence limits recorded at the close
- **Pre-deploy `verify_jwt` for the three redeployed edges was inferred, not read** — from the SBX-2 record and
  from the five untouched functions' posture. The post-deploy read is real (all nine false). Security consequence
  nil: all three authenticate their own callers, which I verified in source (`create-payment-intent` throws on a
  missing `Authorization` header then validates via `supabase.auth.getUser(token)`; `enforce-transfer-expiry` and
  `send-push` compare the bearer themselves). Recorded as a near-miss rather than rounded up.
- **Deploy-time flags are undeclared state.** There is no `supabase/config.toml`; `verify_jwt` lives only in the
  last deploy. Source parity does not cover it, so the production preflight needs it as a separate read-and-match.
- **A's two parity false alarms** came from the harness, not the artefacts: a regex deriving an import set named a
  file the function does not import, and a clause that ignored transitive imports. Every byte comparison passed
  first time. Stopping at each until explained is what the abort rule is for.

### `net._http_response` is a 6-hour cache, not a log — the evidence self-deletes
At V0 the table held 2 rows from 2026-09-07; after the first new tick it held **only** id 3. Attributed and benign:
`pg_net.ttl = 6 hours`, and pg_net's worker purges only when it processes activity — there had been none since
2026-09-07, so two long-expired rows sat untouched until the 04:48 request woke the worker. 133 does not touch that
table (its only deletion is `http_request_queue` scoped to the production host; there were no such rows).

Two consequences given to A for the manifest: **(1)** the refused-tick evidence must be captured as *values* now,
because in six hours the query returns nothing and that reads as "no outbound activity", a different claim
entirely; **(2)** `cron.job_run_details` is not a substitute — it records that the *queuing SQL* succeeded, so a
job that posted successfully and one that was refused look identical there. Only the captured response rows
support "nothing succeeded". A is capturing and will re-capture at the close.

### Edge parity under option (b) is a source comparison, not a behavioural one
Raised to A for the manifest's wording: `send-push` cannot be exercised end to end here, so the four-edge parity
check proves the deployed bytes match the pin and **nothing** about whether a challenge can reach a device.
"send-push verified on the sandbox" would otherwise be read as the b2 delivery check the owner deferred.

### The md5 method, reproduced independently
A's apply script stores the ledger row's statements as one element holding the pinned file's bytes with trailing
newlines stripped, and compares `md5(array_to_string(statements,''))` to the md5 of the file minus its trailing
newline. I ran that myself from `/tmp/wt-pin` rather than accepting the description: `printf '%s' "$(cat file)"`
yields **e07ac078…** for 131 and **ecdd9176…** for 132, matching both ledger values, against raw file md5s of
`1c2fade4…` and `1d588749…`. The check is genuine. One wording caveat given to A for the manifest: `"$(cat …)"`
strips **all** trailing newlines, not one — harmless for these files, but the sentence should say so.

### 133's capture list — derived independently, then compared
From the pinned file, 133 replaces exactly four routines — `public.notify_bid_placed`,
`public.notify_transfer_event`, `public.notify_moderation_event`, `kernel.check_signing_key_invariants` — and
re-registers five crons: `enforce-transfer-expiry`, `crm-export-build-tick`, `crm-export-purge-tick`,
`refund-execute-tick`, `payout-execute-tick`. A's capture holds those four routines plus `notify_outbid` (a true
superset) and the four crons that exist here, with `enforce-transfer-expiry` rolled back by unschedule since 133
creates it on this sandbox. **Nothing 133 rewrites is missing.**

### Prediction recorded BEFORE the 133 apply
Exactly one cron may post afterwards, and it is guarded differently from the rest:
`enforce-transfer-expiry` (`*/2`) is guarded **only** on `project_url`, which now exists, so it attempts a post
every two minutes; `crm-export-build-tick` / `crm-export-purge-tick` additionally require
`crm_export_worker_secret` (absent) and `refund-execute-tick` / `payout-execute-tick` additionally require their
executor flags (both read **false**), so all four stay silent. **Any other job posting is a stop.** Also expected:
`enforce-transfer-expiry` alone builds `'Bearer ' || (select service_role_key …)` with **no `coalesce`**, so with
no key the header is NULL rather than empty — the tick may therefore record a 401 *or* a queue-time `error_msg`.
Both are consistent with option (b); which one occurs is recorded, not asserted in advance.

### Two notes raised during the window

**The ledger md5 is not the file md5.** A recorded "md5 e07ac078… == pinned file (verify OK)". The ledger value is
`md5(array_to_string(statements,''))` — the CLI's parsed statement array. The pinned file's own md5 is
`1c2fade42e2547cf617f70a7a970f523`. The two can never be equal, so the comparison made was not the one described.
Substance is fine — objects, triggers, counts and the `register_push_token` comment all match the file I reviewed,
and my full-chain rehearsal at this pin proved its effect — but the package should state which comparison was
actually performed. Raised to A.

**Row 17 / DV-607a: my earlier limitation is lifted, and C's expectation is now wrong.** At V0 `auth.sessions` had
no triggers at all, which is why I recorded that the sandbox could only test the client's reaction to a dead
session. After 131, `trg_push_bindings_on_sessions_gone` exists, so a server-side session delete now exercises the
real A-131-K2 path. C's agreed expectation — "token row UNCHANGED, any revocation is the client's 129 path" — was
right for the pre-131 sandbox and is **wrong** after it: the deleted session's own binding should now be revoked
with the proof kept. Restate before the run, and sequence row 17 after this window — now because it finally proves
the right thing, not because it proves nothing.
