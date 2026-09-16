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
