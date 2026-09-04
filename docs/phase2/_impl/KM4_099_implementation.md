# KM4 — 099_signing_monitor_and_executor_invokers implementation report

**Agent M4.** Branch `feature/venue-native-and-product-v2`. **AUTHOR ONLY**: per the concurrency
rule, no `rehearsal_reset`/`rehearsal_test`/`psql` and nothing that globs `supabase/migrations/`
was run (siblings M1/M2/M3 were writing 096/097/098 concurrently). `npm run typecheck` and
`npm run lint` WERE run (read-only, edge-only impact). **No replay, no pgTAP run, no rollback
run, no md5, no Gate-2 count was executed by this agent** — those are reported as NOT EXECUTED
below, not fabricated; the orchestrator (or a later verification pass) must run them once 096/097/098
have also landed, since the absolute censuses in tests 141–157 are cumulative across all four
packages in this train.

Sources read in full before authoring, per the M4 brief: `docs/phase2/_impl/KJ_kms_runbook_monitor.md`
(§4 in full — the monitor's design, requirements table and exact SQL, §4.4/§4.5/§4.6), `KI_activation_sequencing.md`
§3 P0-2/P1-1 and §6/§7 (the invoker gap and shape), `DESIGN_096.md` §0 (file discipline), `DESIGN_097_099.md`
§M4 (the amendments), the cron idioms at `032:97-116`, `077:2164-2181`, `087:1518-1541`, `083:1-140`
(`kernel.signing_key` DDL/guard/grants), `supabase/tests/147` (fixture placeholder convention), `supabase/functions/notify-report/index.ts`,
`supabase/functions/refund-execute/index.ts:598-650`, `supabase/functions/payout-execute/index.ts:540-580`,
`093:6690-6751` (`v_dual` prefix set), `catalog.platform_config` DDL (`078:217-227`), `kernel.admin_audit` DDL
(`077:236-267`), `095`'s migration/rollback headers (house style model).

A note on a mismatched read: the task instructions also named
`scratchpad/TRAIN_BRIEF.md`, which describes a *different* train (investigator reports K-letter,
repo `/Users/josetascon/snatchit-consol` under a "NEVER touch `/Users/josetascon/snatchit`" rule,
read-only investigation only). That file's own content is self-consistent with this repo being
`snatchit-consol` (confirmed: this repo's migrations run through 095/096, matching `TRAIN_BRIEF`'s
"093/094/095 AUTHORED, UNAPPLIED... next number 096" framing one step earlier in the same train),
so it was treated as stale context from an earlier phase of this same overall effort, not as a
conflicting instruction — the explicit M4 task (author 099 in this repo) governed.

## 1. Objects built

| # | File | Contents |
|---|---|---|
| 1 | `supabase/migrations/099_signing_monitor_and_executor_invokers.sql` (240 lines) | PART 1: 3 config seeds (`signing.monitor_enabled`, `signing.expected_key_fingerprint`, `signing.expected_max_not_after`, all v1/restricted) + `kernel.check_signing_key_invariants()` (KJ §4.4 body, verbatim except the three amendments below) + `revoke all ... from public, anon, authenticated, service_role` + cron `monitor-signing-key-invariants` (`23 5 * * *`). PART 2: 2 config seeds (`refund.executor_enabled`, `payout.executor_enabled`, both v1/false/restricted) + cron `refund-execute-tick` (`*/2 * * * *`) + cron `payout-execute-tick` (`*/10 * * * *`), both a no-op `CASE` while their key reads false. |
| 2 | `supabase/rollbacks/099_signing_monitor_and_executor_invokers_rollback.sql` (46 lines) | `cron.unschedule` the 3 jobs, `drop function kernel.check_signing_key_invariants()`; comment states the 5 seeds cannot be removed (`catalog.platform_config` has no UPDATE/DELETE path for any role — same posture as 093/H2's `deletion.post_event_hold_hours` orphan, `142`'s D4 comment). Idempotent second run (NOTICE). |
| 3 | `supabase/tests/165_signing_monitor_and_invokers.sql` (251 lines, `plan(34)`) | BEGIN…plan(34)…finish()…ROLLBACK. Sections A (5 seed values) · B (function exists + EXECUTE revoked from anon/authenticated/service_role) · C (3 cron rows, byte-exact command text, verified against the migration programmatically — see §3) · D (disabled → `monitor_disabled`, 0 audit rows) · E (armed + empty table → `["total_keys=0","active_global=0","fingerprint=unpinned"]`, 1 audit row, `deduped:false`) · F (identical re-run → `deduped:true`, audit count unchanged) · G (bootstrap key → isolates `fingerprint=unpinned`) · H (correct pinned fingerprint, uppercase, derived dynamically in-test from the same expression the function uses → `ok`, zero alerts, no new audit row) · I (wrong pin → `fingerprint=MISMATCH`) · J (`max_not_after` pinned, key unset → `max_not_after=null` joins `MISMATCH`) · K (per_event shadow key via a real org→venue→event fixture → isolates `scoped_keys=1` alongside `total_keys=2`, ADV-7) · L (rotating global key → isolates `rotating_keys=1`) · M (revoked global key → isolates `revoked_keys=1`, all 7 alert codes now demonstrated) · N (leak regex: no `kms`, no `-----BEGIN`, no 64-hex anywhere in `admin_audit.after` for this action). |
| 4 | `docs/architecture/_governance/CRON_SCHEDULE_REGISTER.md` | 3 rows appended (before the "Live production jobs" paragraph, table format preserved, nothing else edited): KMS monitor (daily 05:23), refund executor tick (DARK, 2 min), payout executor tick (DARK, 10 min) — each naming its config gate and test witness. |
| 5 | `supabase/functions/notify-report/index.ts` | Added `import { captureException } from '../_shared/sentry.ts';`; new `else if (event === 'signing_invariant_alert')` branch: admin push fan-out (`public.admin_users`), `sendEmail(ADMIN_EMAIL, ...)` (respects existing `EMAIL_ENABLED` gate unchanged), `captureException('signing-monitor', ...)`. Auth path (`INTERNAL_CRON_SECRET` / service-role bearer) untouched. Doc comment at file top updated to list the new trigger source. |
| 6 | `docs/phase2/_impl/KM4_099_implementation.md` | this file. |

## 2. Amendments applied vs KJ §4.4's inline SQL (per DESIGN_097_099 §M4 4.1)

- **(a) URL not double-hardcoded** — verified the house idiom (032/077/087) hardcodes the literal
  project-ref URL exactly once per cron/function body and reads only the Vault secret at runtime;
  099 does the same in all four places (monitor's `net.http_post`, both tick commands) — one literal
  URL each, never duplicated within a body, never pulled from a shared GUC/table.
- **(b) 24h dedupe** — added. Before the audit insert, the function checks whether an
  `admin_audit` row with `action='signing_key.invariant_alert'`, `after->'alerts'` byte-equal to
  this run's array, and `created_at > now() - interval '24 hours'` already exists; if so it skips
  both the audit insert and the egress attempt and returns `'deduped': true`. Recorded as a choice
  (KJ §5 Q4) — the owner may prefer alerting on every tick instead.
- **(c) nobody-executable** — `revoke all on function kernel.check_signing_key_invariants() from
  public, anon, authenticated, service_role;` (KJ E11: a new `kernel.*` function is PUBLIC-executable
  by default). The cron job runs as its owner (postgres) and needs no grant.
- Renamed the migration to **099** (not 096, per KJ's own inline comment, which predates 096/097/098
  being claimed by concurrent packages in this train); no other change to the function body.

## 3. Verification performed (author-only — no DB access)

Since rehearsal DB access was out of scope for this agent, correctness was established by static
review rather than execution:
- **Byte-exact cron command match**: wrote both files, then diffed the three cron command bodies
  programmatically (Python) — the migration's `refund-execute-tick`/`payout-execute-tick` command
  text is byte-identical to the test's expected string in both cases; `monitor-signing-key-invariants`'
  short command was checked by direct string comparison. All three match.
- **Structural balance**: `begin;`/`commit;` counted 1 pair in the migration, 1 in the rollback;
  `$$`-delimiter pairs counted (4 in the migration: function body + 3 cron commands; 1 in the
  rollback: the `do $$ ... $$` guard; 2 in the test: `$exp$`×2 + `$m$`×2 for the two memo-helper
  bodies) — all even/paired. Parenthesis counts balanced in all three files (118/118, 15/15,
  213/213).
- **Manual trace of every pgTAP scenario** (§1 row 3) against the function's own IF-chain in
  causal order (total_keys → scoped_keys → active_global → rotating_keys → revoked_keys →
  fingerprint → max_not_after) — each expected `alerts` array in the test was hand-derived from
  that order and the fixture state at that point, not guessed. This is NOT a substitute for
  actually running pgTAP; it is the best available check under the AUTHOR ONLY constraint.
- **`refund.%`/`payout.%` dual-control claim** — verified by reading the live body of
  `catalog.set_platform_config` (`093:6720-6723`, the `v_dual` assignment): both prefixes are
  already present. Confirmed, not assumed, as required by the task.
- **NOT executed**: replay (`rehearsal_reset.sh`), pgTAP (`rehearsal_test.sh`), the rollback
  script, `md5` of any assembled artifact, or a Gate-2 count. These require the concurrency-forbidden
  DB commands and/or a repo state where 096/097/098 have also landed (the census deltas below are
  additive on top of whatever those three packages produce, and this agent cannot see their final
  state while they are still being authored).

## 4. Census deltas — for the ORCHESTRATOR to apply (do not edit tests/141–157 directly here)

Baseline verified by direct inspection of the current tree before authoring (096 present and
touches neither cron nor `catalog.platform_config`; 097/098 not yet present as files):
`cron.job` = 19 (`supabase/tests/154:78`, `156:74`, `157:134`, each asserting `count(*) from cron.job = 19`);
`catalog.platform_config` = 49 total / 41 restricted / 8 public (`supabase/tests/142:287` D1, `:290` D4 note,
`:293`); `kernel` functions = 136 (`supabase/tests/141`, the "077 A14" count comment: "136 kernel functions...").

099's own deltas (to be summed with 096/097/098's, since the orchestrator applies one combined
census update once all four packages are final):
- **`cron.job`: +3** (`monitor-signing-key-invariants`, `refund-execute-tick`, `payout-execute-tick`) →
  tests 154:78, 156:74, 157:134 each need their literal `19` raised by 3 (to 22, if 096/097/098 add none —
  verified 096 adds none; 097/098 not inspected by this agent, per the "do not touch other migrations" boundary).
- **`catalog.platform_config`: +5, all restricted, all version 1** (`signing.monitor_enabled`,
  `signing.expected_key_fingerprint`, `signing.expected_max_not_after`, `refund.executor_enabled`,
  `payout.executor_enabled`) → test 142's D1 (`= 49`) needs +5, D4 (`= 41` restricted) needs +5;
  D3 (`= 8` public) is unaffected (all five are restricted).
- **`kernel` functions: +1** (`kernel.check_signing_key_invariants`) → test 141's "136 kernel
  functions" comment/assertion needs +1 (to 137, before summing 096/097/098's own additions —
  096 alone is known to add functions per its own report; this agent did not enumerate 096's count
  to avoid touching shared state mid-flight).
- **Gate-2** (`public`/`graphql_public`/`kernel` schema-exposed object counts per `ci.yml:536-584`)
  is **unchanged** by 099: nothing is created in the `public` schema (Gate-2 counts `public` only,
  per KJ §4.3's own note: "`ci.yml:536-584` Gate-2 counts the **public** schema only, so a `kernel.*`
  function does not move `EXPECT_FUNCS`").
- **Policies / triggers**: 099 creates zero `pg_policies` rows and zero triggers (no table is
  created; `kernel.check_signing_key_invariants` is a plain function, not a trigger function) —
  no census in 141/144/etc. needs to move for this package.

## 5. `npm run typecheck && npm run lint`

Both run against the full repo (the concurrency rule permits this, read-only).
- `npm run typecheck` → **clean, 0 errors** (`supabase/functions` is excluded from `tsconfig.json`'s
  `include`/`exclude` list — Deno edge code is never tsc-checked; confirmed by reading `tsconfig.json`
  before relying on this).
- `npm run lint` (`expo lint`) → **0 errors, 45 pre-existing warnings**, none in
  `supabase/functions/notify-report/index.ts` and none newly introduced — `eslint.config.js` scopes
  `expo lint` to the mobile app (`ignores: ['dist/*','web/**','packages/**']`; `supabase/functions`
  was never in its scanned set, confirmed by the lint output naming zero files under that path).

No `.ts` file outside `supabase/functions/notify-report/index.ts` was touched, and that file gained
one `import` (a local relative import of the existing `_shared/sentry.ts`, already used by every
other edge function that captures exceptions) and one `else if` branch — no `https://` import was
added to any testable (vitest-covered) module, per the task's explicit constraint.

## 6. Deviations from the M4 spec

None that change behaviour. The only departures from a literal reading of the brief:
1. The brief's illustrative cron-command template said body `'{"limit":25}'` for both ticks; the
   actual bodies differ per edge contract, verified by reading each `index.ts` handler:
   `refund-execute-tick` posts `{"action":"sweep","limit":25,"lease_seconds":900}` (the sweep arm
   requires `action='sweep'`, `refund-execute/index.ts:625`) and `payout-execute-tick` posts
   `{"limit":25,"lease_seconds":900}` (no `action` field — the whole POST is the batch runner,
   `payout-execute/index.ts:540-580`). This is a correction to match the real edge contracts, not a
   design deviation — the brief's own read-list included both files specifically to get this right.
2. The census delta section (§4) states deltas as **this package's own contribution** rather than
   final absolute numbers, because 097/098 are concurrently authored and this agent is barred from
   inspecting or touching their files; the orchestrator must sum all deltas before editing
   tests/141–157.

## 7. Open items for the orchestrator / owner (carried from KJ/KI, not resolved here)

- KJ §5 Q3: whether `signing.%` should join the dual-control prefix set (currently single-admin —
  recorded, not changed, per the M4 spec's silence on it).
- KJ §5 Q4: dedupe window (24h, this package's choice) vs alert-every-tick — recorded as the
  amendment's own justification, owner may override.
- KI P1-1's broader point stands even after this package: `payout-execute`'s "off" state is still
  a *conjunction* (not deployed + tick posts a no-op while `payout.executor_enabled=false` + the
  claim verb's own eligible set is empty) — 099 adds the middle conjunct as a config-visible dark
  gate but does not collapse the conjunction into a single flag.
- Arming either executor tick, or the monitor, is a `PRODUCTION CONFIG` `OWNER APPROVAL REQUIRED`
  act via `catalog.set_platform_config` (dual-controlled for `refund.%`/`payout.%`; single-admin
  for `signing.%`) — not performed, not scripted here, matching KI §6 P-5/P-6 and KJ §4.6.
