# KJ — PRODUCTION SIGNING / KMS OPERATIONS: runbook staleness diff + invariant monitor design

**Branch** `feature/venue-native-and-product-v2` @ `609e0f4` · **Date** 2026-09-03 · **Investigator J**
**Mutations: NONE.** No KMS, no secret, no production, no Supabase MCP/CLI, no Stripe, no commit. The only
repo file written is this one. Rehearsal DB `snatchit_rehears_j` was built from the full 110-file chain
(`GATE-2 tables=27 functions=70 policies=37 triggers=26` = CI baseline) and every prototype statement ran
inside `begin … rollback` — post-rollback census confirmed `cron.job=19`, `signing_key=0`,
`to_regproc('kernel.check_signing_key_invariants') = null`.

The runbook (`docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md`, 980 lines) was **not edited**. Corrections are
listed in §3 as a diff.

---

## 1. WHAT WAS INSPECTED (file:line)

| Area | Bytes read |
|---|---|
| Runbook | `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md:1-980` in full |
| Prior evidence | `_impl/G3_signing_rehearsal.md` (417), `_impl/H7_kms_gap_classification.md` (276, esp. `:28-45`, `:170-276`), `_impl/R1_ticket_expiry_derivation.md:180,347-350,560`, `_impl/R3_rehearsal_harness.md:1-30,162,238-242`, `FINAL_ACTIVATION_BLOCKERS_IMPLEMENTATION_REPORT.md:232-290,376-392`, `G4_G5_RECEIVABLE_094_IMPLEMENTATION_REPORT.md:33,208,283-291,360,390`, `REFUND_PAYOUT_BACKEND_COMPLETION_REPORT.md:298-326` |
| Signing substrate | `083:1-140` (table, guard, grants, policy), `083:370-430` (five parked RPCs), `083:500-570` (old mint), `083:840-875` (grant lists); `084:45-60` (FK); `079:40-55`; `086:700-725` (revoke parked), `086:855-870`, `086:1190-1205`; `085:1940-1965`, `085:2045-2055` |
| 093 | `093:3846` (`venue.create_primary_checkout`), `093:4025-4085` (G2b quote-time gate), `093:4805-5010` (mint header + body), `093:5370-5390`, `093:5425-5445`, `093:5857-5932` (ITEM 2), `093:6505-6520`, `093:6544` (`set_platform_config` replacement), `093:6695-6751`, `093:2838`; `093_parts/40_config_privacy_freeze.sql:17,446-521` |
| 094/095 | grepped for `signing`, `finalize_primary_order`, `create_primary_checkout`, `issue_ticket_atoms`, `set_platform_config`, `cron.` — **zero hits**; neither touches any signing object |
| Config / audit | `078:1048-1310` (`catalog.set_platform_config`: `unknown_key` at `:1103`, polarity map `:1152-1200`, direct path `:1297-1307`), platform_config DDL (`078`, append-only trigger), `077:236-262` (`kernel.admin_audit`), `078:1603-1615` (sentinels …f0/…f1), `083:742-745` (sentinel-actor audit pattern) |
| Cron / alert plumbing | `014:1-40`, `032:90-115`, `075:355-392`, `077:2164-2180`, `079:796-803`, `081:1119-1123`, `086:1501-1505`, `087:1518-1535`, `092:1195`; `docs/architecture/_governance/CRON_SCHEDULE_REGISTER.md:1-40`; `076:238-300` (`notify.emit_event`); `092:1-60,240-277` (closed 31-type catalogue) |
| Edges | `supabase/functions/*` grep for `Deno.env.get|kms|signing|KMS_SIGNER`; `stripe-webhook/native.ts:395-430`; `stripe-webhook/index.ts:346-360`; `_shared/sentry.ts:1-60`; `notify-report/index.ts:1-110`; `payout-execute/index.ts:60-110` |
| CI / tests | `.github/workflows/migrations-guard.yml:245-300`, `ci.yml:536-584` (Gate-2 counts `public` schema only), `supabase/tests/147:122,187-217`, `132:218-270`, `142:287-293`, `154:78`, `156:74`, `157:134`; `.gitignore:16,18,31` |
| Architecture | `PHASE_2_EDGE_FUNCTION_SPEC.md:1263-1298,1519-1527`; `_decisions/B_signing_dual_control.md:259-262,338-357`; `POST_FREEZE_AMENDMENTS.md:1124-1167` (PFA-16) |

---

## 2. WHAT WAS EXECUTED, AND RESULTS

All on `snatchit_rehears_j` (loopback PG 17, pg_cron/pg_net stand-ins from `scripts/rehearsal_bootstrap.sql`).

| # | Statement | Result |
|---|---|---|
| E1 | `kernel.signing_key` columns/constraints/indexes/triggers/grants | 11 columns exactly as `083:49-70`; 7 constraints incl. `signing_key_scope_target_ck`, `signing_key_window_ck`; 3 partial unique indexes incl. `signing_key_active_global_uq ON ((true))`; triggers `tg_signing_key_immutable`, `tg_signing_key_updated_at`; **`authenticated` has column SELECT on 8 columns — `kms_handle_ref` excluded; `service_role` and `anon` have nothing** (matches ADV-3/ADV-12) |
| E2 | `select count(*) from kernel.signing_key` | `0` |
| E3 | Runbook §9.3 fingerprint expression on a synthetic PEM (`base64('hello')`, NOT a key) | builtin `sha256()` works on PG17 without pgcrypto; returned the SHA-256 of `hello` — the expression is executable as written |
| E4 | Sentinel identities | `…f0 void@snatchit.internal`, `…f1 system@snatchit.internal` present in `auth.users` (SN-SYSTEM usable as `admin_audit.actor_identity`, whose FK is `auth.users(id)`) |
| E5 | Six parked RPC signatures + mint | All present with the arities the runbook's §3/§7.3 calls use; `kernel.issue_ticket_atoms(jsonb,text)` body contains `signing_key_override_refused`; `venue.create_primary_checkout` body contains `no_active_signing_key` |
| E6 | `catalog.set_platform_config('signing.expected_key_fingerprint', …)` as `postgres` | `insufficient_privilege: authentication required` (`078:1067-1071`) — the setter cannot be driven by pg_cron/superuser; a platform_admin JWT is required, and an **unseeded key is refused `unknown_key` (`078:1103`)** → the monitor's config keys must be SEEDED by a migration before the owner can set them |
| E7 | Cron census | 19 jobs, names kebab-case, all registered by owning package (`CRON_SCHEDULE_REGISTER.md` premise); `cron.schedule('monitor-signing-key-invariants', …)` inside a txn → census 20 → rolled back → 19 |
| E8 | Prototype `kernel.check_signing_key_invariants()` (SQL in §4.4), rolled back | disabled flag → `{"status":"monitor_disabled"}`; enabled + empty table → alerts `["total_keys=0","active_global=0","fingerprint=unpinned"]`; synthetic global row + pinned (uppercase hex accepted) → `status=ok`; wrong pin → `fingerprint=MISMATCH`; `not_after` set → `max_not_after=set`; **per_event shadow row (direct fixture org→venue→event) → `["total_keys=2","scoped_keys=1"]` and the `093:4066` resolver returned the shadow's `key_id`, reproducing ADV-7** |
| E9 | Alert body leak check | `kernel.admin_audit.after::text ~ 'NON-PRODUCTION\|BEGIN PUBLIC KEY\|<fpr hex>\|PUBKEY\|aGVsbG8'` → **false**; audit row = `actor …f1, action signing_key.invariant_alert, subject_kind signing_key, subject_id …b0, reason monitor, after.alerts=[…]` |
| E10 | Append-only on the audit row | `UPDATE kernel.admin_audit …` → `append_only: admin_audit is immutable` (`kernel.raise_append_only`) |
| E11 | Default EXECUTE on a new `kernel.*` function | `has_function_privilege('authenticated', …, 'execute') = true` by default → a 096 function MUST `revoke all … from public, anon, authenticated, service_role` (083's pattern at `:867-869`); after revoke `false`, `postgres` still `true` |
| E12 | `grep -rniE 'kms\|KMS_SIGNER' .github/workflows/` | empty (H7 §"Stale" item 3 confirmed) |
| E13 | `.gitignore` | `*.p8` (:16), `*.key` (:18), `*.pem` (:31); no `*.der`, `*.sig`, `*.bin` — runbook §9.4 still accurate |
| E14 | Edge functions reading a signing key or KMS handle | **None.** `primary-checkout/index.ts:150-152` and `refund-execute/index.ts:87-90` read only `SUPABASE_URL / ANON_KEY / SERVICE_ROLE_KEY (/ INTERNAL_CRON_SECRET)`. No `KMS_SIGNER_ROLE_ARN` anywhere. The only signing-aware edge code is `stripe-webhook/native.ts:420-421`: `no_active_signing_key` → `{ack:false, alert:true, reason:'finalize_no_signing_key'}` → Sentry `captureException` (`index.ts:358-359`) |

Not executed: anything against production or any KMS. Provider choice (D1) untouched.

---

## 3. RUNBOOK STALENESS DIFF (report, not edit)

Legend: **says** → **true now** (file:line) → **corrected text**. Severity: S1 = an operator following the text
would do or believe something wrong; S2 = dangling/moved reference, substance intact; S3 = cosmetic.

### 3.1 The quote-time signing gate — §1.3 is materially incomplete (S1)

- **Says** (§1.3 "What is NOT built"): the ceremony exists because `kernel.tickets.signing_key_id` is NOT NULL and *"the mint refuses without an active in-scope key — so a ticket cannot exist at all until one honest row does."* No mention of checkout.
- **True now:** `venue.create_primary_checkout` (`093:3846`) carries the A8/G2b deliverability gate at `093:4030-4081`: the same resolver (`093:4066-4074`) runs at **quote** time and raises `precondition_failed: no_active_signing_key — an active signing key must resolve for the event scope before a ticket can be sold` (`093:4076`) **before any order row or PaymentIntent exists**. Gate order inside the function: `payout_not_ready` (`093:4026`) → `no_active_signing_key` (`093:4076`) → `service_fee_unset`. The key is deliberately NOT pinned onto the order (`093:4077-4081`).
- **Corrected text** for §1.3, append: *"Since 093, the same resolver also runs inside `venue.create_primary_checkout` (`093:4066-4077`). With no active key, no primary checkout can be quoted at all — the ceremony gates the first production QUOTE, not the first webhook-time mint. The 'buyer charged, no ticket' hazard is therefore closed before the charge, and a webhook that still reaches finalize without a key is classified retryable+alert by `stripe-webhook/native.ts:420-421`."*
- Also §11 opening line *"The point of no return is the first successful `kernel.issue_ticket_atoms` call — in production, the first `venue.finalize_primary_order` on a paid order"* — still true (`085` untouched by 093/094/095: `093:2838`), but add: *"…which cannot be reached until a quote has passed the 093:4066 gate."*

### 3.2 The current mint source — every `083:514-530` / `083:557-559` citation (S2, one S1 nuance)

| Runbook site | Says | True now | Corrected |
|---|---|---|---|
| §1.1 table row "Validation of the pair" | `kernel.issue_ticket_atoms (083:514-530) validates only status/not_before/not_after/scope coherence` | Mint replaced by `093:4874` (`create or replace function kernel.issue_ticket_atoms(p_ctx jsonb, p_command_key text)`); envelope now **resolves** most-specific-first at `093:4954-4966`, refuses `no_active_signing_key` at `093:4968`, and additionally refuses a caller-supplied `p_ctx->>'signing_key_id'` that disagrees with the resolved key: `signing_key_override_refused` (`093:4974-4976`) | cite `093:4950-4976`; add: *"the mint no longer accepts a key — it resolves one and refuses disagreement"* |
| §6.1 POST-CHECK comment `(083:514-530) … (085:1948-1960)` | same | three identical resolvers: finalize `085:1948-1960`, checkout gate `093:4066-4074`, mint `093:4954-4966` | *"the row must satisfy the resolver used at all three sites (085:1948-1960 · 093:4066-4074 · 093:4954-4966)"* |
| §8 bullet 2 `pinned at mint (083:557-559)` | pin write | `093:5003-5005` (`insert into kernel.tickets (… signing_key_id) values (… v_key)`) | `093:5003-5005` |
| §11 door 3 `083:557-559 writes signing_key_id at insert` | same | `093:5003-5005` | same |
| §11 door 4 *"The mint validates only status/window/scope"* | still true in substance | + override refusal (`093:4974-4976`); it still cannot validate key material | keep, add *"(and refuses a caller override, 093:4974)"* |
| §15 ADV-7 *"the resolver immediately prefers it (`085:1955-1960`)"* | true | now true at three sites; reproduced today on the rehearsal DB (E8) | cite all three |
| §15 ADV-12 *"`service_role` can call `issue_ticket_atoms` … only against a key someone else created"* | true | strengthened: `service_role` can no longer pin a `global` key over a `per_event` one (override refusal). The FINAL report's P1 (caller-supplied `signing_key_id`) is closed | add the strengthening |
| §1.3 `083:519` / D6 `083:519 requires not_after > now()` | old mint line | `093:4959` (`(k.not_after is null or k.not_after > now())`) — and the same predicate at `093:4069` and `085:1953` | `093:4959` |
| §7.2 comment *"this is the 085:1948-1960 / 086:1196-1201 resolver, verbatim shape"* | claims verbatim | the §7.2 query filters `k.scope in ('global')` — it is NOT the verbatim shape; the real resolver's scope arm is `per_event/per_venue/global` ordered most-specific-first. As written §7.2 cannot see a shadow scoped key (that is §7.4's job). Also `086:1196-1201` is the comp-issue path, fine | reword: *"the global arm of the resolver; the full resolver is 085:1948-1960 = 093:4066-4074 = 093:4954-4966"* |

### 3.3 Line references that have moved (S2)

| Runbook | Says | True now |
|---|---|---|
| §3 checklist | `093_parts/40_config_privacy_freeze.sql:341-465` ships ITEM 2 | ITEM 2 is `40_config_privacy_freeze.sql:446-521` (ITEM 3 begins `:522`); assembled `093:5857-5932`. `:341-345` is the G2 settlement-maturity banner |
| §0 rule 1 | `083:36-39` states C33 | `083:36-41` (paragraph runs to `:41`) |
| §1.1 / §11 / §15 | guard `083:84-102`, `BEFORE UPDATE` only `083:104-105`, not_after excluded `083:88-93`, forward-only `083:96-99` | guard `083:84-101`; trigger `083:103-105`; immutable set `083:88-91` (**also `not_before`** — runbook never lists it); status rule `083:95-98`. Note the guard comment at `:95` permits `rotating → active` — the runbook's "forward-only" wording is looser than the code, which only makes `revoked` terminal |
| §1.1 | EDGE_SPEC §5.2 global-scope quote at `:1286-1288`; pinned-at-issue `:1289-1290` | `:1283-1284` and `:1287-1289` |
| §13 step 1 | `feature.%` not in the dual-control prefix set (`078:1145-1147`) | live body is `093:6748-6751` (`fee.%`, `deletion.%`, `ticket.%` added; `feature.%` still absent — the single-admin kill switch survives) |
| §7.3 / §0 rule 3 | `083:846-853`, `:869-871` | `v_auth` list `083:846-854`; grant loop `083:870-872` |
| §9.4 / §15 ADV-13 | CI grep returns "two prose comments" | returns **nothing** (E12) — stale in the safe direction |
| H7 (adjacent, not the runbook) | `093:3314`, `093:3390-3415`, `093:3444`, `093:2506-2516`, `093:2466`, `093:2545`, `093:4596`, `093:4747`, `093:1330`, `093:2517-2521` | 093 was re-assembled (7241 lines): `4874`, `4950-4976`, `5003-5005`, `4066-4077`, `4026`, `~4090`, `6544`, `6748`, `2838`, `4077-4081`. The REFUND report's `093:3983` / `093:4033` are now `4026` / `4076`. **Every 093 line reference written before the last `assemble_093.sh` run is stale; the runbook's are not the only ones.** |

### 3.4 The standing monitor (§9.3, §7.6, §14, §15 ADV-1/8/9/10, §16 step 9) — S1

- **Says:** *"Alert on any of these, at least daily"* + a five-column SQL query; §16 step 9 *"monitor §9.3 armed"*; ADV-9 *"§9.3 alerts on `max_not_after` and on any status change"*.
- **True now:** no mechanism exists — no cron job, no function, no config key, no alert egress. H7 (`:37-41`) and the REFUND report (`:319-320`) already classify arming it as a **launch blocker**. Additionally:
  1. The §9.3 query **prints the fingerprint** (`bootstrap_fpr … expect <EXPECTED_PUBLIC_KEY_FINGERPRINT>`), which conflicts with the "no fingerprint in alert text" requirement; a monitor must compare against a pinned value and emit only the comparison result.
  2. It says "four standing invariants" but lists five columns.
  3. It does **not** watch status at all (ADV-9's claim); `active_global` catches `active→rotating|revoked` on the bootstrap key only by side effect, and a `rotating→revoked` flip on a retired key (which invalidates old credentials once verification exists) is invisible to it.
  4. Nothing pins the expected fingerprint anywhere in the database.
- **Corrected text:** replace §9.3 with a pointer to the 096 mechanism in §4 below (function name, config keys, cron job name, alert route) and the arming step; add a `status` census column (`count(*) filter (where status='revoked')`, `… 'rotating'`) with expected `0/0` until the first rotation; §16 step 9 becomes the two `set_platform_config` calls in §4.6.

### 3.5 The ceremony's DB insert step vs the 083 table shape — MATCHES (no change)

`§6.1` inserts `(key_id, scope, event_id, venue_id, public_key, kms_handle_ref, status, not_before, not_after)`; E1 confirms all nine exist with those types, `created_at/updated_at` default, no INSERT trigger, no format CHECK. The `where not exists` once-only guard, PRE-FLIGHT 2's fingerprint expression (E3), and the POST-CHECK's resolver shape all execute as written. §12's rotation artifact uses the same column list and `kernel.tickets.ticket_atom_id` (`079`) — matches. §10's three reference checks (`kernel.wallet_pass.signing_key_id` `083:191`, `venue.door_manifest_entry/delta.signing_key_id` `086`) exist. **Verdict: the executable SQL in §6, §10, §12 is current.** Only its comments are stale (§3.2).

### 3.6 Does the ceremony expect 093 applied first? — YES, and the runbook says so; here is exactly why (S2 clarification)

- The **INSERT itself depends only on 083/084**: `kernel.signing_key` (`083:49-70`), the FK `fk_tickets_signing_key … on delete restrict` (`084:52-55`), the guard (`083:84-105`). Both are in production already (ledger 107 = 000–092).
- **The runbook's semantics depend on 093**: (1) the quote-time gate `venue.create_primary_checkout` `093:4066-4077` — without it §1.3's hazard (charge, then no key) is live; (2) the resolving mint `kernel.issue_ticket_atoms` `093:4874-5010` — §11 door 4 and ADV-7/ADV-12 verdicts are stated against it; (3) `catalog.set_platform_config` `093:6544` — §13 step 1's single-admin `feature.%` flip is stated against the 093 body (`093:6748-6751`); (4) ITEM 2's commented template `093:5857-5932` is the ratified statement that 093 writes no row.
- **094 and 095 are not dependencies** (zero signing references; §1). But the G4_G5 report's activation order (`:289`) applies 093→094→095 as one block (ledger 107→110) before step 7 (ceremony), and that order is mandatory for other reasons — the runbook should say *"093, 094 and 095 applied (ledger 110)"* rather than "093 applied".
- **New:** if §4's monitor is adopted, **096 must be applied before the ceremony** so that §16 step 9 (arming) is a config act, not a deploy.

### 3.7 Minor (S3)

- §0 rule 3 says provisioning RPCs "carry `GRANT EXECUTE … TO authenticated`" — true (`083:846-854, 870-872`); E11 shows why this matters for 096: **any new `kernel.*` function is EXECUTE-able by `authenticated` by default** and must be revoked explicitly.
- §2 B4 "Holds the production database credential" — since no role but `postgres` holds INSERT on `kernel.signing_key` (E1, ADV-3), B4 means the **superuser** credential; say so.
- §9.4 suite 147 note: the literal non-keys are `'PUBKEY'` / `'kms-handle-opaque'` (`147:217`) and the zero assertion is `147:122` — both still true.

---

## 4. THE KMS INVARIANT MONITOR — design (dark, not armed)

### 4.1 Requirements (from the brief) and how each is met

| Requirement | Design |
|---|---|
| ≥ daily | pg_cron `'23 5 * * *'` (nightly band next to `refresh-holder-mix 17 4`, `reconcile-holder-mix 47 4`) |
| Structural alert destination | (i) durable: `kernel.admin_audit` row, action `signing_key.invariant_alert` (append-only, E10); (ii) push: `net.http_post` → `notify-report` edge (existing structural fan-out: every `public.admin_users` gets push; `ADMIN_EMAIL` env gets email when `EMAIL_ENABLED`) + `captureException('signing-monitor', …)` so Sentry alert rules (`SENTRY_SERVER_DSN`) route it. No named person anywhere |
| Checks | `total_keys==1`, `scoped_keys==0`, `active_global==1`, fingerprint COMPARISON vs pinned value, `max(not_after) is null` unless overridden, plus `revoked_keys`/`rotating_keys` census (closes §3.4 item 3) |
| No private material / no handle / no fingerprint in the alert | the function never selects `kms_handle_ref`; the fingerprint is reduced to `match / MISMATCH / unpinned / bootstrap_row_missing`; alert body = counts, booleans, state strings (E9 leak check false) |
| Expected fingerprint pinned | `catalog.platform_config` key `signing.expected_key_fingerprint`, seeded `version 1, 'null'::jsonb, 'restricted'` (PFA-22 owner-unset shape, same as 093's five keys `093:5498`) → monitor reports `fingerprint=unpinned` as an alert until set |
| Dark on apply | `signing.monitor_enabled` seeded `false`; function returns `{status:'monitor_disabled'}` and writes nothing while false (E8). The cron row exists from apply (owning-package pattern) but is inert |
| `not_after` override | `signing.expected_max_not_after` seeded `null`; alert when `max(not_after) is distinct from` the pinned value (D6 default NULL) |

### 4.2 Options

| | (a) pg_cron → SQL function → admin_audit + pg_net → notify-report/Sentry | (b) Edge on a schedule (pg_cron + pg_net → new `signing-monitor` edge) | (c) GitHub Action read-only query |
|---|---|---|---|
| House pattern | **Yes** — 13/19 jobs are pure-SQL cron registered by the owning package; DB→pg_net→edge fan-out is the 033/034/035 pattern; Vault `service_role_key` header is the 032/087 pattern | Half — cron→pg_net→edge exists (`enforce-transfer-expiry`, `crm-export-*`), but **`service_role` has zero privileges on `kernel.signing_key`** (E1, ADV-12), so the edge needs a `service_role`-granted RPC anyway → (b) = (a) + an extra hop and a new deploy artifact | **No** — needs a production DB credential in GitHub secrets, contradicting §9.4/ADV-13 ("no CI step touches KMS or prod"), and adds an availability dependency |
| Reads key material? | No (function selects counts + a hash of `public_key`) | Same, via RPC | Same, via a DB role with `kernel` USAGE — new grant surface |
| Alert egress | `notify-report` already fans out to `public.admin_users` + `ADMIN_EMAIL`; needs one new `event` branch + a Sentry capture (≈15 lines TS, redeploy) | new edge from scratch | GitHub notification / Slack webhook — outside the platform's alert plane |
| Silent-failure mode | if pg_net is down the audit row still lands (http_post wrapped in exception handler, `033:162` pattern); cron.job_run_details records the run | edge outage = no check at all | runner outage = no check |
| Test witness | pgTAP: function exists, EXECUTE revoked, cron row present, disabled→no-op, each alert code in isolation, leak regex on `after` | + Deno test | none in-repo |

**Recommendation: (a).** Smallest honest variant of (a): ship function + seeds + cron + audit row in 096; make the
pg_net egress **fail-open for the audit row** and route to `notify-report` (event `signing_invariant_alert`).
What would be dishonest: calling §9.3 "armed" with only the audit row and no egress (nobody reads
`kernel.admin_audit` unprompted), or raising an exception from the cron command so the failure shows in
`cron.job_run_details` — that rolls back the audit row and nothing pages.

### 4.3 Where it belongs — new migration `096` (093/094/095 are immutable)

- Next number verified free: `ls supabase/migrations | grep -E '^09[6-9]'` → none. Timestamped files (`2026…`) are website forms, not kernel packages.
- `migrations-guard.yml:251-275` fails any PR that modifies an existing migration; `ci.yml:536-584` Gate-2 counts the **`public`** schema only, so a `kernel.*` function does not move `EXPECT_FUNCS`.
- **Required companions in the same PR** (tests are absolute censuses and will fail otherwise):
  - `supabase/tests/154:78`, `156:74`, `157:134` assert `count(*) from cron.job = 19` → **20**.
  - `supabase/tests/142:287` asserts 49 config rows, `:293` asserts 41 restricted → **52 / 44** (three seeds).
  - New `supabase/tests/16x_phase2_signing_monitor.sql` (witnesses in §4.2 row "Test witness").
  - `supabase/rollbacks/096_*_rollback.sql` (house pattern: 090–095 all have one): `cron.unschedule('monitor-signing-key-invariants')`, `drop function kernel.check_signing_key_invariants()`. **The three config seeds cannot be rolled back** — `catalog.platform_config` has zero UPDATE/DELETE paths even for superuser (`tg_platform_config_append_only`, `078`); the rollback must say so, as 085's orphan key precedent does (`142:280-286`).
  - `docs/architecture/_governance/CRON_SCHEDULE_REGISTER.md`: add the row (`monitor-signing-key-invariants` · `kernel.check_signing_key_invariants` · 096 · daily · `cron.schedule` in 096 · read-only, idempotent · none · test 16x).
  - `notify-report/index.ts`: new `event === 'signing_invariant_alert'` branch → admin push + `ADMIN_EMAIL` + `captureException`. Deploy is a separate act (edges are not migrations).
- `AUTODEPLOY-VERIFIED-OFF` line required in the PR (migrations-guard).

### 4.4 Exact SQL for 096 (dark)

```sql
-- 096_signing_key_invariant_monitor.sql — DARK. Seeds three owner-unset config keys,
-- one SECURITY DEFINER read-only checker, one daily cron row. Arms NOTHING:
-- while signing.monitor_enabled is false the checker returns monitor_disabled and
-- writes nothing. Never selects kms_handle_ref; never emits public_key or a fingerprint.
begin;

-- 1. config keys (PFA-22 owner-unset shape; set_platform_config refuses unknown keys, 078:1103)
insert into catalog.platform_config (key, version, value, visibility) values
  ('signing.monitor_enabled',          1, 'false'::jsonb, 'restricted'),
  ('signing.expected_key_fingerprint', 1, 'null'::jsonb,  'restricted'),  -- SHA-256 over DER SPKI, lowercase hex (runbook D5)
  ('signing.expected_max_not_after',   1, 'null'::jsonb,  'restricted')   -- runbook D6: NULL unless the owner overrides
on conflict (key, version) do nothing;

-- 2. the checker
create or replace function kernel.check_signing_key_invariants()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enabled        boolean;
  v_total          integer;
  v_scoped         integer;
  v_active_global  integer;
  v_rotating       integer;
  v_revoked        integer;
  v_max_not_after  timestamptz;
  v_exp_not_after  timestamptz;
  v_pinned         text;
  v_actual         text;
  v_fpr_state      text;
  v_alerts         text[] := '{}';
  v_out            jsonb;
begin
  select (c.value #>> '{}')::boolean into v_enabled
    from catalog.platform_config c where c.key = 'signing.monitor_enabled'
   order by c.version desc limit 1;
  if not coalesce(v_enabled, false) then
    return jsonb_build_object('status', 'monitor_disabled', 'checked_at', now());
  end if;

  -- counts only. kms_handle_ref is never read.
  select count(*),
         count(*) filter (where scope <> 'global'),
         count(*) filter (where scope = 'global' and status = 'active'),
         count(*) filter (where status = 'rotating'),
         count(*) filter (where status = 'revoked'),
         max(not_after)
    into v_total, v_scoped, v_active_global, v_rotating, v_revoked, v_max_not_after
    from kernel.signing_key;

  select nullif(lower(c.value #>> '{}'), '') into v_pinned
    from catalog.platform_config c where c.key = 'signing.expected_key_fingerprint'
   order by c.version desc limit 1;
  select (c.value #>> '{}')::timestamptz into v_exp_not_after
    from catalog.platform_config c where c.key = 'signing.expected_max_not_after'
   order by c.version desc limit 1;

  -- the D5 fingerprint, recomputed from the stored PEM; reduced to a comparison result.
  select encode(sha256(decode(regexp_replace(k.public_key,
           '-----(BEGIN|END) PUBLIC KEY-----|[[:space:]]', '', 'g'), 'base64')), 'hex')
    into v_actual
    from kernel.signing_key k
   where k.key_id = '00000000-0000-0000-0000-0000000000b0';
  v_fpr_state := case when v_pinned is null then 'unpinned'
                      when v_actual is null then 'bootstrap_row_missing'
                      when v_pinned = v_actual then 'match'
                      else 'MISMATCH' end;

  if v_total        <> 1 then v_alerts := array_append(v_alerts, 'total_keys='    || v_total);        end if;
  if v_scoped       <> 0 then v_alerts := array_append(v_alerts, 'scoped_keys='   || v_scoped);       end if;  -- ADV-7 shadow
  if v_active_global<> 1 then v_alerts := array_append(v_alerts, 'active_global=' || v_active_global);end if;  -- ADV-8
  if v_rotating     <> 0 then v_alerts := array_append(v_alerts, 'rotating_keys=' || v_rotating);     end if;  -- expected 0 until first rotation
  if v_revoked      <> 0 then v_alerts := array_append(v_alerts, 'revoked_keys='  || v_revoked);      end if;  -- ADV-9
  if v_fpr_state <> 'match' then v_alerts := array_append(v_alerts, 'fingerprint=' || v_fpr_state);   end if;  -- ADV-4/5/6/10
  if v_max_not_after is distinct from v_exp_not_after
     then v_alerts := array_append(v_alerts, 'max_not_after=' ||
            case when v_max_not_after is null then 'null' else 'set' end);                            end if;  -- ADV-9 / §7.6

  v_out := jsonb_build_object(
    'status',            case when cardinality(v_alerts) = 0 then 'ok' else 'alert' end,
    'checked_at',        now(),
    'total_keys',        v_total,
    'scoped_keys',       v_scoped,
    'active_global',     v_active_global,
    'rotating_keys',     v_rotating,
    'revoked_keys',      v_revoked,
    'fingerprint',       v_fpr_state,            -- a WORD, never the hex
    'max_not_after_set', v_max_not_after is not null,
    'alerts',            to_jsonb(v_alerts));

  if cardinality(v_alerts) > 0 then
    -- durable, append-only, actor = SN-SYSTEM sentinel (083:743 pattern)
    insert into kernel.admin_audit
           (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values ('00000000-0000-0000-0000-0000000000f1', 'signing_key.invariant_alert', 'signing_key',
            '00000000-0000-0000-0000-0000000000b0', 'monitor', null, v_out);

    -- push egress — BEST-EFFORT, fail-open for the audit row (033:162 pattern);
    -- Vault service_role_key header is the 032/087 pattern; no secret in this file.
    begin
      perform net.http_post(
        url     := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/notify-report',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets
                                                   where name = 'service_role_key'
                                                   order by created_at desc limit 1), ''),
          'Content-Type', 'application/json'),
        body    := jsonb_build_object('event', 'signing_invariant_alert', 'alerts', to_jsonb(v_alerts),
                                      'checked_at', now()));
    exception when others then
      raise warning 'signing monitor: alert egress failed — % (%)', sqlerrm, sqlstate;
    end;
  end if;

  return v_out;
end;
$$;

-- 3. grants: nobody but the cron owner (postgres) may execute. E11: default is PUBLIC-executable.
revoke all on function kernel.check_signing_key_invariants() from public, anon, authenticated, service_role;

-- 4. cron (owning-package registration, kebab name, idempotent by jobname — 077:2164-2167)
select cron.schedule('monitor-signing-key-invariants', '23 5 * * *',
                     $$select kernel.check_signing_key_invariants();$$);

commit;
```

Executed on the rehearsal DB (rolled back) with the outcomes in §2 E7–E11. The `net.http_post` branch was not
exercised (stand-in only); its exception wrapper is the 033 pattern.

### 4.5 `notify-report` branch (edge, separate deploy — sketch, not implemented)

`event === 'signing_invariant_alert'` → title `"Signing-key invariant alert"`, body = `alerts.join(', ')`
(counts/words only) → existing `sendPush` to every `public.admin_users` row, `sendEmail(ADMIN_EMAIL, …)` under
`EMAIL_ENABLED`, and `captureException('signing-monitor', new Error('signing_invariant_alert: ' + alerts.join(',')))`
so a Sentry alert rule can route it. Auth is unchanged (`INTERNAL_CRON_SECRET` or service-role bearer,
`notify-report/index.ts:95-100`).

### 4.6 The arming step for the runbook — `PRODUCTION CONFIG` · `OWNER APPROVAL REQUIRED` · **NOT EXECUTED**

Replaces §16 step 9 ("monitor §9.3 armed"). Runs **after** §7 passes and **before** step 10 (flag flip). Requires
096 applied (§4.3) and the `notify-report` branch deployed. Executed by a **platform_admin JWT** (the setter
refuses `postgres` — E6) through PostgREST or an authenticated `psql` session — never the SQL editor.

```sql
-- PRODUCTION CONFIG — OWNER APPROVAL REQUIRED. Values from the evidence pack (§9.1), not from this file.
-- 1. pin the fingerprint B stated first and A confirmed (§5.2). Lowercase hex, 64 chars.
select catalog.set_platform_config('signing.expected_key_fingerprint',
         to_jsonb('<EXPECTED_PUBLIC_KEY_FINGERPRINT>'::text), 'ceremony_b_bootstrap', '<COMMAND_KEY_1>');
-- 2. (only if D6 chose a non-NULL not_after) pin it, else skip:
-- select catalog.set_platform_config('signing.expected_max_not_after',
--          to_jsonb('<PRODUCTION_KEY_NOT_AFTER>'::text), 'ceremony_b_bootstrap', '<COMMAND_KEY_2>');
-- 3. arm
select catalog.set_platform_config('signing.monitor_enabled', 'true'::jsonb, 'ceremony_b_bootstrap', '<COMMAND_KEY_3>');
-- 4. READ ONLY — prove the monitor is green NOW, not tomorrow at 05:23 (run as postgres, the cron owner):
--    select kernel.check_signing_key_invariants();   -- expected: {"status":"ok","alerts":[],"fingerprint":"match",...}
--    Anything else: STOP; the evidence pack is not signable.
```

Expected `set_platform_config` returns: `{"status":"ok","key":…,"version":2,…}` for each (direct path,
`078:1297-1307`) — because `signing.%` is **not** in the dual-control prefix set (`093:6748-6751`), a single
platform_admin can pin, arm, and — the weakness — **disarm or re-pin alone**. See §5 Q3.

---

## 5. OPEN QUESTIONS FOR THE ORCHESTRATOR / OWNER

1. **Q1 — Adopt (a) and author 096 now, or hold until the ceremony is scheduled?** 096 is dark either way; authoring it now lets the ceremony's step 9 be config, not deploy. Cost: three pgTAP censuses, a rollback file that cannot remove seeds, a register row, an edge branch.
2. **Q2 — Alert egress target:** reuse `notify-report` (legacy moderation pipeline, already fans out to `public.admin_users` + `ADMIN_EMAIL`) vs a new `ops-alert` edge. Reuse is smaller; a dedicated edge is cleaner. Either way Sentry is the pager; `ADMIN_EMAIL` is the mailbox; neither is a person.
3. **Q3 — Should `signing.%` be dual-controlled?** Adding `or p_key like 'signing.%'` to `v_dual` requires a **third body-only replacement of `catalog.set_platform_config`** in 096 (byte-identical to `093:6544-…` except that line — the same discipline 093 used against 078). Polarity: `signing.monitor_enabled` → `'false_is_restrictive'` is WRONG here (enabling detection is the tightening); it would need a new `'true_is_restrictive'` arm so `true` executes alone and `false` parks for a second admin. `signing.expected_key_fingerprint` (string, no polarity) would always park → two admins to (re)pin, which mirrors the two-person ceremony. Recommended if the owner wants the disarm path to need a quorum; otherwise record single-admin disarm as an accepted gap alongside H7 GAP 1.
4. **Q4 — Cadence and window:** daily at 05:23 UTC proposed; the owner may prefer hourly (cost is a 6-row scan). The alert repeats every run while unresolved (no dedupe) — is that the desired behaviour, or should the audit write dedupe on identical `alerts` within 24 h?
5. **Q5 — Runbook maintenance:** every `093:` line reference in the runbook, H7, and the REFUND/FINAL reports predates the last `assemble_093.sh` run and is wrong. Recommend the runbook cite 093 by **object name + anchor comment** (`-- ---- A8 / G2b`, `-- §8 — kernel.issue_ticket_atoms`) rather than line numbers, or pin a 093 sha.
6. **Q6 — 093 rollback file:** `supabase/rollbacks/` has 094/095 rollbacks but **no 093 rollback** (G3 §7 flagged it; still true). Out of J's scope, still open.
