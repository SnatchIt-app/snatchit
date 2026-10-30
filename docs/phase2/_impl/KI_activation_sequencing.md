# KI — Activation sequencing: the production runbook, derived from the actual system

**Scope.** Investigator I. Read-only against the repo at `feature/venue-native-and-product-v2` @ `609e0f4`;
executed only against a fresh local rehearsal DB `snatchit_rehears_i` (`./scripts/rehearsal_reset.sh
snatchit_rehears_i` → **[X] 110/110 migrations, GATE-2 tables=27 functions=70 policies=37 triggers=26**, equal
to `ci.yml:581-584`). No production, Supabase MCP, Stripe, secret or deploy was touched. Nothing here is
authorized; this is the shape of the path.

Markers used below: `READ ONLY` · `PRODUCTION MIGRATION` · `PRODUCTION CONFIG` · `EDGE DEPLOY` ·
`SUPABASE DASHBOARD` · `STRIPE MUTATION` · `KMS MUTATION` · `PRODUCTION DB MUTATION` ·
`OWNER APPROVAL REQUIRED` · `TWO-PERSON REQUIRED` · `IRREVERSIBLE AFTER MINT`.

---

## 1. What I inspected (file:line)

| Source | What it settled |
|---|---|
| `docs/phase2/PRIMARY_TICKETING_ACTIVATION_MATRIX.md` (398 lines; rows 1–12, critical path :261-331, hazards :335-391) | the prior ordering, its config census (49 keys), its `093:NNNN` citations |
| `docs/phase2/_impl/H9_activation_readiness.md:51-84, :153-186, :331-368` | the executed SALEABLE ladder, A9 verdict, the prior ordered path |
| `docs/phase2/_impl/G6_activation_gates.md:280-420` | A9 text, the "minimum honourable set", option (a)/(b) for `on_sale` |
| `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` (980 lines) | ceremony steps §3–§7, artifact §6.1, monitor §9.3, rollback §10, sequence §16 |
| `docs/phase2/FINAL_ACTIVATION_BLOCKER_RULINGS.md:1-16, :140-160, :280-306, :366-390, :503-530` | **all five rulings DRAFT / NOT SIGNED**; G1 value `"72 hours"`; G2 value 7 days; G3 approved-in-principle text |
| `docs/phase2/G4_PROMOTER_REVERSAL_RULING.md:1-3`, `G5_POST_PAYOUT_EXPOSURE_RULING.md:1-3` | both **DRAFT. NOT APPROVED. NOT SIGNED.** |
| `docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md` (88 lines) | dark apply 076–092, ledger 107, exposure `public,graphql_public,kernel`, edges deployed, **checkpoint 1 only** (:59-88) |
| `docs/release/PHASE2_PRODUCTION_RUNBOOK.md`, `PHASE2_ROLLBACK_DECISION_TREE.md`, `PHASE2_RELEASE_READINESS_REPORT.md:170-200` | the 076–092 runbook shape; `stripe-webhook` **v39** is the deployed (pre-native) build (:181) |
| `scripts/release/phase2_preflight.sql`, `phase2_postapply_verify.sql`, `local_prod_order_rehearsal.sh`, `local_rollback_battery.sh` | all four are **scoped to 076..092 by literal** (V1 `=107`, V3 `=75`, V4 `=243`, V7 `=43`, L1 regex `^0(7[6-9]|8[0-9]|9[0-2])$`, rollback loop `076..092`) |
| `.github/workflows/ci.yml:520-584`, `.github/workflows/migrations-guard.yml:237-246` | Gate-2 `EXPECT_*` = 27/70/37/26; the `AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD` PR-body gate lives in **migrations-guard.yml**, not ci.yml |
| `docs/operations/DEPLOYMENT_PATHS.md` (canonical) | Path B (Supabase GitHub integration) applies migrations on merge to `main`; owner must confirm OFF in the dashboard per migration-bearing PR; approved apply paths |
| `supabase/config.toml` | **does not exist in this repo** (`find . -name config.toml` → none). Exposed schemas are a dashboard field only; today = `public,graphql_public,kernel` (deployment record :23-25) |
| `supabase/migrations/093_primary_ticketing.sql` (7241 lines): header :1-72, slices :73/:2776/:3315/:5409, seeds :5498-5851, bootstrap template :5857-5920, checkout gates :4021/:4026/:4076/:4105/:4111, mint gate :4936/:4968, `set_platform_config` :6544-6935 (prefix set :6720-6723, interval guard :6633-6650) | every config key the rail reads, every seed value, the exact refusal ladder |
| `supabase/migrations/094_organization_obligation.sql:1-90`, `095_payout_state_machine_recovery.sql:1-48` | 094/095 read **no** new config key (`[X]` key-literal census: only audit action names + `payout.settlement_maturity_interval`) |
| `supabase/rollbacks/` | **`094_*` and `095_*` exist; there is NO `093_*` rollback file** although `093:3298`, `B_signing_dual_control.md:468` and `E_payments_reshape.md:496` all promise one |
| `supabase/migrations/083_kernel_credential_infrastructure.sql:49-110` | `kernel.signing_key` DDL: `public_key text not null`, `kms_handle_ref text not null`, one active global key (`signing_key_active_global_uq`), immutability guard |
| `supabase/functions/{connect-onboarding,primary-checkout,refund-execute,payout-execute,stripe-webhook}` | `Deno.env.get` census, RPC census, auth model, `verify_jwt` posture (E1 B4 / E2 :12: `verify_jwt: true`; executors and webhook do their own auth) |
| `supabase/functions/_shared/stripe.ts:32` | `STRIPE_SECRET_KEY` is read by the shared client → every function importing it needs it |
| `docs/operations/DAY2_DEPLOYMENT_GUIDE.md:131-138` | house pattern for a self-authenticating edge: `supabase functions deploy <fn> --no-verify-jwt` |
| `supabase/migrations/088_market_native_rail.sql:1862-1875` | the house ruling that an edge tick with `INTERNAL_CRON_SECRET` is **not scheduled from a migration** (no Vault name/header exists in bytes) |
| `supabase/tests/146_phase2_venue_orders.sql:112-330`, `158_refund_execution_claim.sql`, `161_payout_state_machine.sql:1-140` | fixture patterns reused for §2 |

---

## 2. What I executed, and the results

All in `snatchit_rehears_i`, inside `BEGIN … ROLLBACK` unless stated.

**2.1 Config census after 093/094/095** — `[X] 49 distinct keys`; every activation-path key at version 1 with the
value below (`feature.native_issuance_enabled=false`, `inventory.hold_ttl_interval=null`,
`inventory.per_user_active_hold_max=null`, `fee.buyer_service_bps=null`, `ticket.expiry_grace=null`,
`payout.settlement_maturity_interval=null`, `payout.dual_control_min_minor=null`, `payout.request_auto_max_minor=null`,
`payout.destination_cooldown_hours=null`, `payout.destination_probation_days=null`, `deletion.post_event_hold_hours=null`,
`deletion.refund_possible_window_hours=null` (orphan), `refund.*` all null except `refund.scanned_atom_policy="platform_review"`,
`authn.money_role_maturity_hours=72`). `[X] select count(*) from kernel.signing_key = 0`.

**2.2 The refusal ladder, executed end to end** (script: scratchpad `ki_quote_gate.sql`; fixture = 146 pattern:
org→venue(approved)→event→session→ticket_type→batch→`announced`→`on_sale`):

```
A  catalog.event.status after publish with NOTHING configured        -> on_sale        (A8 gap confirmed)
B1 reserve_primary_inventory, flag=false                             -> precondition_failed: feature_disabled
B2 flag=true, per_user_active_hold_max=null                          -> precondition_failed: hold_cap_exceeded
B3 cap=4, hold_ttl_interval=null                                     -> precondition_failed: hold_ttl_unset
B4 ttl="10 minutes"                                                  -> hold created
C1 create_primary_checkout, org status='suspended'                   -> precondition_failed: org_not_active — a suspended organization may not sell   (093:4021)
C2 org approved, acct_ unbound                                       -> precondition_failed: payout_not_ready                                          (093:4026)
   stage_org_connect_ref (service)  -> {"staged":true}
   set_org_connect_ref (org_owner aal2) -> {"newly_bound":true}
C3 bound, connect_transfers_active=false                             -> precondition_failed: payout_not_ready                                          (093:4026)
   sync_org_connect_state(..., true, now()) (service) -> {"connect_transfers_active":true}
C4 transfers active, zero signing keys                               -> precondition_failed: no_active_signing_key                                     (093:4076)
   insert kernel.signing_key (…b0, global, active)   [fixture non-key]
C5 key present, fee.buyer_service_bps=null                           -> precondition_failed: service_fee_unset                                         (093:4105)
   fee.buyer_service_bps=500
C6                                                                   -> order created: status=pending, total_minor=10000
```
Observations that shape the runbook: (i) `set_org_connect_ref` succeeds while `transfers` is still inactive — binding
and readiness are two different writes, and only `sync_org_connect_state` (service_role, callers: `connect-onboarding/
index.ts:1151`, `stripe-webhook/index.ts` account.updated org arm) flips readiness; (ii) the signing gate is the **4th**
refusal, after org status and both Connect predicates, so the KMS ceremony is provably not the head of the path;
(iii) no `refund` operand exists in the ladder (H9 §1 gate 3, re-confirmed by reading `093:3846-4270`).

**2.3 Config quorum behaviour, as a real `platform_admin` on aal2 through `catalog.set_platform_config`:**
`ticket.expiry_grace` `"72 hours"` → **parked** (approval row `config.set_money_key/pending`); bare `72` → refused
`bad_value … a bare number is read as SECONDS` (**before** any quorum); `payout.settlement_maturity_interval` `"7 days"` →
**parked**; `deletion.post_event_hold_hours` `720` → **parked**; `feature.native_issuance_enabled` `false` → **executed,
single admin, no approval row**. Approval path: `kernel.approve_refund_request(request_id,'approve',reason,command_key)`
(`085:1089`, `authenticated`; the `config.set_money_key` arm at `085:1224` requires a **second, distinct**
`platform_admin`, and applies the value at `085:1328-1345` as the next version).

**2.4 KMS runbook §3/§7.3 preflight, as written** — all three raise `precondition_failed: dual_control_unavailable`
(`provision_signing_key(text,uuid,text,text,timestamptz,text,text)`, `rotate_signing_key(uuid,text,text,text,text)`,
`revoke_signing_key(uuid,text,integer,text)`): the runbook's argument lists match the deployed signatures.

**2.5 Executor eligibility on a fresh 095 catalog** — `kernel.claim_payouts_for_execution(10,60)` → `{"payouts":[]}`;
`kernel.claim_refunds_for_execution(10,60)` → `{"refunds":[]}`; `kernel.payout`/`refund`/`tickets`/
`organization_obligation` all 0. **[X] None of the six execution verbs reads `catalog.platform_config`**
(`pg_get_functiondef ~ 'platform_config'` = false for `claim_payouts_for_execution`, `claim_refunds_for_execution`,
`get_payout_execution_context`, `get_refund_execution_context`, `mark_refund_state`, `mark_payout_transfer_state`).
Eligible set read from the live body: payouts = `cause='settlement' ∧ payee_kind='organization' ∧ status='submitted' ∧
hold_state='none' ∧ stripe_transfer_ref is null ∧ destination_ref is not null`; refunds = `status in
('pending','submitted')` with a 20 h `create`/`reconcile` window.

**2.6 `scripts/release/phase2_postapply_verify.sql` against the 093–095 catalog** — V3 relations **76** (script expects 75),
V4 routines **270** (expects 243), V7 keys **49** (expects 43), V5 policies 72 (ok), V6 cron 19 (ok). **The post-apply
verifier will FAIL on a correct 093–095 apply as it stands.** V1 expects ledger 107 (will be 110).

**2.7 `supabase/tests/158_refund_execution_claim.sql`** on this DB → suite matches the expected baseline (green).

**2.8 Cron census** — 19 jobs, all `select <fn>()` or `net.http_post` to `enforce-transfer-expiry` / the two CRM ticks using
`vault.decrypted_secrets where name='service_role_key'`. **No job invokes `refund-execute` or `payout-execute`.**

---

## 3. Findings, ranked

### P0

**P0-1 — There is no 24-hour close-out record for the 2026-09-02 dark apply.** `PHASE2_DEPLOYMENT_RECORD_20260902.md:88`
ends at *"24-hour close: NOT DUE (target ~2026-09-03T20:45Z). Next checkpoint: the close-out."* No later checkpoint,
no `prod/phase2-apply-*` tag (`git tag -l 'prod/*'` → none), no commit under `docs/release/` after `7e89f0e`
(checkpoint 1). The runbook's own +24H items (`PHASE2_PRODUCTION_RUNBOOK.md:127-131` — cron failure count = 0, outbox
growth, ledger 107 recorded, SHA tagged) are unrecorded. **Elapsed time is not a PASS.** Step 0 of the sequence below
is therefore *produce the close-out from live reads*, not *assume it*.

**P0-2 — `refund-execute` has no invoker; A9 cannot be satisfied by deploying it alone.** The `sweep` arm is
authenticated by `INTERNAL_CRON_SECRET` or the service key (`refund-execute/index.ts:630-633`) and nothing schedules
it: no `cron.schedule` in 093/094/095 (`[X]`), no job in the 19 (`[X]`), and 088:1867-1874 records the house rule that
an edge tick is not armed from a migration until a Vault secret name and header exist in bytes. The `execute` arm needs
a platform JWT per refund (`index.ts:824`). So after deploy, a refund interrupted between `POST /v1/refunds` and
`mark_refund_state` stays `submitted` until a **human** POSTs `{"action":"sweep"}` with the secret. A9's first disjunct
("an automated executor") is not met by a deploy; it is met by deploy **plus** a scheduled invoker (a new migration —
096 — in the `enforce-transfer-expiry` pattern, `net.http_post` with the Vault `service_role_key`, which the sweep arm
already accepts via `svcOk`) **or** by the option-B written process. See §6.

**P0-3 — No `supabase/rollbacks/093_*.sql` exists.** Promised by `093:3298`, `B_signing_dual_control.md:468`,
`E_payments_reshape.md:496`; only `094_*` and `095_*` rollbacks exist. `094`'s own rollback restores
`kernel.close_settlement` to *"093:640-854 VERBATIM"* — so a 094 rollback presumes 093 stays. Consequence for the runbook:
**applying 093 is FORWARD-ONLY from the moment it lands**, and the rollback decision tree's class 1/2 procedure
(`PHASE2_ROLLBACK_DECISION_TREE.md:33-40`) has no analogue for 093. This must be stated as an owner-acknowledged
precondition of step 4 or a `093_*` rollback (payments CHECK/NOT NULL restore + 4-column drops + function body
restores, guarded on zero `native_primary` rows) must be authored and battery-proven first.

**P0-4 — Every release script is 076..092-scoped and will FAIL or mislead on 093–095.** `phase2_preflight.sql` L1/L2
(`=90`, regex to 092), `phase2_postapply_verify.sql` V1/V3/V4/V7 (§2.6: 107/75/243/43 vs 110/76/270/49), V9 names the
orphan key `deletion.refund_possible_window_hours` and not `deletion.post_event_hold_hours`, `local_prod_order_rehearsal.sh`
applies `0[789]*.sql … > "075"` (so it *does* include 093–095) but pins `PGPORT=5433 /tmp/pg150s` and a
`$RG_OUT/c089/catalog_identity.sql` that is not in the repo; `local_rollback_battery.sh` loops `076..092` and would not
find a 093 rollback anyway. New 093–095 preflight/verify/battery scripts are a **precondition** of the apply.

### P1

**P1-1 — `payout-execute` has no on/off flag at all; its only gates are (a) not being deployed and (b) the claim verb's
eligible set.** `[X]` no config read in the TS or in any execution verb (§2.5). The eligible set is empty until a human
org money role runs `kernel.request_org_payout` to `submitted` with `destination_ref` pinned — which itself needs
`payout.settlement_maturity_interval` set (else every payout is minted `held/unbounded_refund_exposure`) and an aal2 step-up.
**So "payout activation" = deploy + arm an invoker + set the maturity key + a venue requesting.** The kill switch is
*undeploy / unschedule*, not a key. This should be said in the runbook rather than implied by the word "dark".

**P1-2 — `feature.native_issuance_enabled` is not only the mint gate; it is the first inventory gate.** `[X]` B1:
`reserve_primary_inventory` refuses `feature_disabled` while false. The matrix step 10 says "flip last of all"; but a
buyer cannot even *hold* inventory before it is true, so the "first controlled quote" (§5.3) is impossible while it is
false. Correct ordering: flip it immediately **before** the first controlled quote and **after** every other clause is
green — which is what "last" already meant, but the runbook must say the controlled quote comes after the flip.

**P1-3 — The Stripe-side prerequisites are not in any runbook.** Required for a first sale, from code: (a) the platform
webhook endpoint must deliver `payment_intent.succeeded`, `payment_intent.payment_failed`, `payment_intent.canceled`,
`account.updated` (already live for v39, readiness report :181) — no new event subscription is needed for the sale path,
but `charge.dispute.*`, `charge.refunded`, `transfer.reversed`, `payout.paid/failed` are consumed by legacy arms only;
(b) `connect-onboarding` needs `VENUE_CONNECT_RETURN_URL` / `VENUE_CONNECT_REFRESH_URL` (E1 B3) pointing at dashboard
routes that **do not exist** (E1 B5: `/dashboard/payments/connect/return|refresh`) and Stripe Connect branding (E1 B10);
(c) `primary-checkout` mints PIs on the **platform** account with `metadata.rail=native_primary` (native.ts:36-45) —
`STRIPE_SECRET_KEY` already in env. Marked `STRIPE MUTATION` below where a Stripe object is created.

**P1-4 — The matrix's ordering "expose `catalog`+`venue` (step 2) before deploying `primary-checkout` (step 9)" opens
the RPC to any authenticated client for the whole interval.** `venue.create_primary_checkout` is granted to
`authenticated` (`[X]`), so once `venue` is exposed the SQL ladder is the only gate. That is *fail-closed by design*
(refuses `payout_not_ready`/`no_active_signing_key`/`service_fee_unset`) — but H9 §7 and the matrix both call the
exposure field "the outermost gate". Recommended re-ordering: expose `catalog`+`venue` as late as possible — after the
KMS ceremony and the config values, immediately before `primary-checkout` deploy — so the storefront is not reachable
while any single-admin write (`inventory.*`, the flag) could complete the ladder early.

**P1-5 — `deletion.post_event_hold_hours` ordering is enforced by nothing** (matrix :313-315): it must not be set until
`refund-execute` is deployed **and invoked** (P0-2), otherwise BP-12 arm 2 stops blocking while refunds can strand
`pending`. The runbook must sequence it after the invoker is proven (§5.2 step S-7 verification).

### P2

**P2-1 — Stale line citations across the corpus.** 093 is 7241 lines; everything in slice 30 moved by +43 after the
`org_not_active` gate was added. Matrix/H9 cite `093:3983/4033/4062` for the three checkout gates — actual **4026/4076/4105**;
`093:4229` set_org_connect_ref → **4272**; `093:4442` set_org_payout_destination → **4485**; `093:3486` sync → **3487**;
`093:4742` get_org_connect_ref → **4785**; `093:5067` authorize_org_payout_dashboard → **5110**; `093:5220` guard → **5263**;
`093:4831` issue_ticket_atoms → **4874**; `093:6907` update_event_session → **6950**; `093:6705` prefix set → **6720**;
`093:5808` deletion key seed → **5851**; `093:5867` bootstrap template → **5857-5920** (ok-ish). Slice 10/20 citations
(`:435 :640 :889 :1038 :1311 :1686 :1743 :1988 :2076 :2266 :2478 :2638 :2744`) are **correct**.

**P2-2 — KMS runbook staleness.** §3 cites `093_parts/40_config_privacy_freeze.sql:341-465` for ITEM 2 — actual
**:446-521**. §13 step 1 cites `078:1145-1147` for the prefix set — superseded by `093:6720-6723` (conclusion unchanged:
`feature.%` is single-admin). §7.2 resolver citation `085:1948-1960` (finalize) is fine — 093 did not replace
`venue.finalize_primary_order` (`[X]` not in the 093 function index). §1.3 says "no `credential-sign`" — still true (`[X]`
`supabase/functions/` has none).

**P2-3 — FABR G1 approval text (:151-153) still names `deletion.refund_possible_window_hours` as the money-safety clock;
H2 renamed the live key to `deletion.post_event_hold_hours` (093:5851) and the old key is an unread orphan.** The owner
would be signing a sentence about a dead key.

**P2-4 — `README`-level: the deployment record's V7 baseline is 43 keys; the matrix says 49 after 093. Both are right for
their moment; the runbook must carry both numbers (pre-apply 43, post-apply 49).**

**P2-5 — `docs/architecture/_governance/CRON_SCHEDULE_REGISTER.md:28` describes a resale `sweep-lapsed` tick as
"`cron.schedule`+`pg_net` in 088" — 088:1867 says it is deliberately NOT scheduled.** Same class of stale claim that
would mislead a reader looking for the refund-sweep invoker pattern.

---

## 4. THE ORDERED SEQUENCE

Two gated sections: **§5 SALE ACTIVATION** and **§6 PAYOUT ACTIVATION**. Promoter payout is in neither (A4; G4 unsigned;
`[X]` a `promoter_commission` payout fails `claim_payouts_for_execution`'s first conjunct). Each step: marker · command
(placeholders for secrets) · verification · why-this-order (code that makes the dependency real).

### 4.0 Preconditions that gate everything (paper + observation)

| # | Precondition | Proving artifact / query | Marker |
|---|---|---|---|
| PRE-1 | 24 h observation of 076–092 **closed on evidence** | `select count(*) from cron.job_run_details where status='failed' and start_time > '2026-09-02T20:44Z'` = 0; `select count(*) from notify.outbox where state='dead'` = 0; ledger `select count(*) from supabase_migrations.schema_migrations` = 107; legacy counts unchanged vs record :50; write `## OBSERVATION CYCLE — close-out` into `PHASE2_DEPLOYMENT_RECORD_20260902.md`; `git tag prod/phase2-apply-20260902` | `READ ONLY` then a docs commit |
| PRE-2 | Owner signatures: **G1** (`"72 hours"`), **G2** (7 days), **G3** (ceremony), ratification of `kernel.claim_refunds_for_execution` (H1 §5.4) | signed `FINAL_ACTIVATION_BLOCKER_RULINGS.md` signature block :503-520 with values; a ratification row for the claim verb | `OWNER APPROVAL REQUIRED` |
| PRE-3 | Gate-M re-attestation (required to **apply 094**; MONEY §67 premise) — owner direction says re-attest as REQUIRED for venue payout | a dated attestation in `docs/phase2/` naming C29/C30/C31 | `OWNER APPROVAL REQUIRED` |
| PRE-4 | AUTODEPLOY-VERIFIED-OFF on the migration-bearing PR (#52) **and** `supabase branches list` shows `git_branch` empty | PR body line `AUTODEPLOY-VERIFIED-OFF: YYYY-MM-DD` (migrations-guard.yml:241); dashboard visual confirmation (DEPLOYMENT_PATHS.md:88-95) | `SUPABASE DASHBOARD` `OWNER APPROVAL REQUIRED` |
| PRE-5 | 093–095 release scripts exist and are green locally: `phase2b_preflight.sql` (L1 regex `^09[3-5]$` absent, L2 `=107`), `phase2b_postapply_verify.sql` (V1 `=110`, V3 `=76`, V4 `=270`, V5 `=72`, V6 `=19`, V7 `=49`, V8 flags 5/5 false, V9 owner-unset now **four** keys incl. `deletion.post_event_hold_hours`, V10 data plane empty, V13/V14 walls), a 093–095 rollback battery | script outputs in the PR | `READ ONLY` (local) |
| PRE-6 | A `093_*` rollback exists **or** the owner signs "093 is forward-only on apply" | file in `supabase/rollbacks/` with a zero-`native_primary`-rows guard, battery diff 0; or a signed line in the apply authorization | `OWNER APPROVAL REQUIRED` |
| PRE-7 | A9 executability path chosen (option A: invoker migration 096; option B: written process) — §6.1 | the 096 file + its pgTAP, or the signed process doc | `OWNER APPROVAL REQUIRED` |
| PRE-8 | Stripe: Connect branding set; `VENUE_CONNECT_RETURN_URL`/`REFRESH_URL` routes exist on `snatchitapp.com` (E1 B5/B10) | `curl -sI https://snatchitapp.com/dashboard/payments/connect/return` → not 404 | `STRIPE MUTATION` (dashboard) |
| PRE-9 | KMS ceremony people/provider booked (G3 D1–D7 filled) | KMS runbook §1.2 table countersigned | `OWNER APPROVAL REQUIRED` `TWO-PERSON REQUIRED` |
| PRE-10 | On-demand production backup < 24 h before the apply (runbook T-1H) | Dashboard → Backups id recorded | `SUPABASE DASHBOARD` |

---

## 5. SALE ACTIVATION (gated section A)

Nothing in this section moves venue money out. It ends with **one** controlled quote, **one** controlled payment and
**one** mint, on a throwaway buyer.

| Step | Marker | Command / query | Verification | Why this order |
|---|---|---|---|---|
| **S-1 Preflight** | `READ ONLY` | `psql "$PROD_DB_URL" -f scripts/release/phase2b_preflight.sql` (PRE-5) at T-24H, T-1H, T-15M | zero FAIL; ledger 107; `select count(*) from kernel.signing_key` = 0; exposure still `public,graphql_public,kernel` | apply must not start on a drifted ledger (`db push --include-all` resumes at the first unapplied file; a stray 043 or a re-linked Path B would change the plan) |
| **S-2 Dry-run plan** | `READ ONLY` | `supabase db push --db-url "$PROD_DB_URL" --include-all --dry-run` | plan lists **exactly** `093,094,095` | the runbook's own gate (:72-73) |
| **S-3 Apply 093 → 094 → 095** | `PRODUCTION MIGRATION` `OWNER APPROVAL REQUIRED` (**forward-only** per P0-3) | `supabase db push --db-url "$PROD_DB_URL" --include-all` | `phase2b_postapply_verify.sql` all PASS: ledger 110; 49 keys, version 1 each; flags 5/5 false; `kernel.signing_key` 0; `kernel.payout.destination_ref` exists; `select tgname from pg_trigger where tgname in ('tg_payout_org_payable_guard','tg_settlement_forward_only')` = 2; `select count(*) from cron.job` = 19 (093–095 add none) | 094 replaces `close_settlement` with a body that calls `kernel.record_organization_obligation` (094 rollback header: "restored text is 093:640-854 VERBATIM") → 093 first; 095 re-creates `get_payout_execution_context` body-only over 093's (`095:1014`) → after 093; 094/095 disjoint (matrix :287). `primary-checkout` calls `kernel.get_org_connect_state` (093:4672) and `venue.create_primary_checkout` as replaced (093:3846) — nothing downstream works before this |
| **S-4 Deploy `connect-onboarding`** | `EDGE DEPLOY` | `supabase secrets set VENUE_CONNECT_RETURN_URL=<https://snatchitapp.com/dashboard/payments/connect/return> VENUE_CONNECT_REFRESH_URL=<…/refresh>` then `supabase functions deploy connect-onboarding` (verify_jwt **on**, E1 B4) | `curl -X POST …/functions/v1/connect-onboarding` with no JWT → 401; with a staff JWT and `{status_only:true}` on a test org → 200 and `connect_state_unavailable` **not** returned | it is the only minter of an org `acct_` (A7) and the **first** writer of `connect_transfers_active` via `kernel.sync_org_connect_state` (093:3487, service_role; call at `index.ts:1151`). Needs 093's `get_org_connect_state`/`stage_org_connect_ref`/`set_org_connect_ref` (E1 B1) → after S-3 |
| **S-5 Deploy `stripe-webhook` (native branch)** | `EDGE DEPLOY` | `supabase functions deploy stripe-webhook` with the **same** verify-jwt posture as v39 (it verifies `STRIPE_WEBHOOK_SECRET` itself, `index.ts:38,139`); env unchanged (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`) | Stripe Dashboard → endpoint → send a test `account.updated` for a **legacy** individual account → 200 and legacy arm logged; `select event_type, processed_at from public.stripe_webhook_events order by claimed_at desc limit 1` (064) shows the event claimed/completed; Sentry no new class | it is the ongoing writer of `connect_transfers_active` (account.updated org arm, `metadata[snatchit_plane]=organization`) and the **only** caller of `venue.finalize_primary_order` (service_role, 085:1919). Safe to deploy before any native PI exists because dispatch is `metadata.rail==='native_primary'` (native.ts:36) — a legacy PI never enters the new branch. Must precede S-9 (a native PI on v39 → `unknown_mode` → 500 retried 3 days, buyer charged, no ticket) |
| **S-6 Deploy `refund-execute`** | `EDGE DEPLOY` | `supabase functions deploy refund-execute --no-verify-jwt` (self-authenticating; `sweep` = cron secret **or** service key, `execute` = platform JWT); confirm `INTERNAL_CRON_SECRET` exists in env (`supabase secrets list`), else set one | `POST {"action":"sweep"}` with `Bearer $SUPABASE_SERVICE_ROLE_KEY` → `{"status":"ok","attempted":0}` (**not** 501 `claim_rpc_missing`); `POST` with wrong bearer → 401 | `kernel.claim_refunds_for_execution` (093:1311) and `get_refund_execution_context` (093:1038) must exist → after S-3. A9 requires this **before** any sale (H9 §3) |
| **S-7 Arm the refund sweep invoker (A9 option A)** | `PRODUCTION MIGRATION` (096) `OWNER APPROVAL REQUIRED` | 096: `cron.schedule('refund-execute-sweep','*/5 * * * *', $$select net.http_post(url:='https://<ref>.supabase.co/functions/v1/refund-execute', headers:=jsonb_build_object('Authorization','Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='service_role_key' order by created_at desc limit 1),'Content-Type','application/json'), body:='{"action":"sweep","limit":25,"lease_seconds":900}'::jsonb)$$)` — the byte-for-byte `enforce-transfer-expiry` pattern (`[X]` cron row) | `select jobname from cron.job` = 20; after one tick `select status from cron.job_run_details where jobid=(select jobid from cron.job where jobname='refund-execute-sweep') order by start_time desc limit 1` = `succeeded`; edge logs show `sweep complete: {claimed:0}` | `svcOk` accepts the service key (`index.ts:632`), and Vault already holds `service_role_key` (preflight X4). Without this, A9's "automated executor" is a human with a curl. Must precede `deletion.post_event_hold_hours` (P1-5) and S-9 |
| **S-8 Onboard ONE organization** | `STRIPE MUTATION` `PRODUCTION DB MUTATION` (via the edge) | staff org_owner (aal2) → `POST connect-onboarding {org_id}` → hosted onboarding → return → `{status_only:true}` | `select stripe_connect_account_ref, connect_transfers_active, connect_state_synced_at from kernel.organization where org_id='<ORG>'` → `acct_…`, `true`, recent; `select count(*) from kernel.admin_audit where subject_id='<ORG>' and action like 'connect.%'` ≥ 2 | `payout_not_ready` (093:4026) requires **both** columns; `[X]` bind alone leaves `connect_transfers_active=false` (C3). This is the first venue-side fact and it is reversible (no money) |
| **S-9 KMS ceremony + bootstrap row** | `KMS MUTATION` `PRODUCTION DB MUTATION` `TWO-PERSON REQUIRED` `OWNER APPROVAL REQUIRED` `IRREVERSIBLE AFTER MINT` | KMS runbook §3→§7 verbatim; `psql "$PROD_DB_URL" -v PUBLIC_KEY_PEM="$(cat pub.pem)" -v KMS_HANDLE_REF="$(cat handle.txt)" -v EXPECTED_FINGERPRINT="$(cat fingerprint.txt)" -f signing_key_bootstrap.sql` | the three `NOTICE`s + `COMMIT`; §7.4 → `1\|1\|0\|0`; §7.5 update → `append_only:` error; **arm the §9.3 monitor as a real job** (cron job `signing-key-invariants` daily + alert) — H9 §7 calls arming it a launch blocker | `no_active_signing_key` is refusal #4 (093:4076) and the mint's gate (093:4968); `[X]` C4. Scheduled at PRE-9, landed here so the (reversible §10) row exists before any config makes a quote possible. Parallelisable with S-4..S-8 |
| **S-10 Owner config values, in this order** | `PRODUCTION CONFIG` (`TWO-PERSON REQUIRED` for parked keys: proposer + a **second** `platform_admin` via `kernel.approve_refund_request(<request_id>,'approve','<reason>','<ck>')`) | as `platform_admin` aal2 through PostgREST/SQL editor **never** as `postgres`: (1) `select catalog.set_platform_config('inventory.per_user_active_hold_max','<N>'::jsonb,'<reason>','<ck>')` → `ok`; (2) `('inventory.hold_ttl_interval','"<10 minutes>"'::jsonb,…)` → `ok`; (3) `('ticket.expiry_grace','"72 hours"'::jsonb,…)` → `parked` → second admin approves; (4) `('payout.settlement_maturity_interval','"7 days"'::jsonb,…)` → `parked` → approve; (5) **only after S-7 is proven** `('deletion.post_event_hold_hours','<hours>'::jsonb,…)` → `parked` → approve; (6) `('fee.buyer_service_bps','<bps>'::jsonb,…)` → `parked` → approve | `select key, value, version from catalog.platform_config c where version=(select max(version) from catalog.platform_config x where x.key=c.key) and key in (…)`; `select count(*) from kernel.approval_request where action='config.set_money_key' and state='pending'` = 0; `select count(*) from kernel.admin_audit where action in ('config.change','config.money_key_approved')` = 6 | (1)/(2) fail closed in `reserve_primary_inventory` (`[X]` B2/B3); (3) is a jsonb **string** or the setter refuses (`[X]`; a number would silently re-arm the inert sweep, 093:5585-5589); (4) is one conjunct of eight in `settlement_payout_maturity` (093:2076) and is harmless before any settlement exists; (6) is the **last** refusal in the ladder (093:4105) — set it last so nothing earlier can quote |
| **S-11 Expose `catalog` + `venue`** | `SUPABASE DASHBOARD` `TWO-PERSON REQUIRED` | Dashboard → Settings → API → Exposed schemas: `public,graphql_public,kernel,catalog,venue` | `curl "$SUPABASE_URL/rest/v1/rpc/create_primary_checkout" -H "apikey: $ANON"` with **no** auth → 401 (not `PGRST106`); with anon → 42501 | E2 AB-8: only after 093 (S-3). Deliberately **late** (P1-4): the RPC is `authenticated`-callable the instant the schema is exposed; by now every SQL gate is green *except* the flag |
| **S-12 Deploy `primary-checkout`** | `EDGE DEPLOY` | `supabase functions deploy primary-checkout` (verify_jwt **on**, E2 :12); env already present (`SUPABASE_*`, `STRIPE_SECRET_KEY`) | no-JWT → 401; staff JWT + empty items → 400 (`no items`) — no PI minted | it is the only thing that mints a PaymentIntent; last deploy so no money path exists before every gate is proven |
| **S-13 Flip the flag** | `PRODUCTION CONFIG` (single admin, by design) | `select catalog.set_platform_config('feature.native_issuance_enabled','true'::jsonb,'activation','<ck>')` → `ok` | value `true` version 2; `[X]` this is the gate at both `reserve_primary_inventory` (081:586) and `issue_ticket_atoms` (093:4936) | last: kill switch is the same call with `false` (KMS §13 step 1); nothing before it can hold, quote or mint |
| **S-14 First controlled quote / payment / mint** | `STRIPE MUTATION` `PRODUCTION DB MUTATION` `IRREVERSIBLE AFTER MINT` | throwaway buyer JWT → `reserve_primary_inventory` → `POST primary-checkout` → PaymentSheet with a real card for the smallest ticket → `payment_intent.succeeded` | **quote**: `select order_id,status,total_minor from venue."order" where buyer_id='<BUYER>'` = 1 row `pending`; `select stripe_payment_intent_id, mode, status from public.payments where mode='native_primary'` = 1 row; **payment**: same row `status='succeeded'`; `select * from kernel.payment_native where order_id='<ORDER>'` = 1; order `status='paid'`; **mint**: `select count(*), min(signing_key_id) from kernel.tickets where event_session_id='<SESSION>'` = `<qty>`, `…b0`; `select count(*) from kernel.ticket_ownership_log where cause='issue'` = qty; webhook event row `completed`; Sentry 0 alerts | this is the point of no return for the signing key (KMS §11). Everything after it is forward-only. Do **not** proceed to §6 until this has run and a refund of it (S-15) has *returned money* |
| **S-15 Prove A9 on the first sale** | `STRIPE MUTATION` | platform support JWT → `POST refund-execute {"action":"record", "order_id":…}` (routes to `kernel.request_order_refund`, `index.ts:750`) then the sweep tick (S-7) or `{"action":"execute"}` | `select status, stripe_refund_ref from kernel.refund` = `succeeded`, `re_…`; Stripe Dashboard shows the refund; `select count(*) from kernel.tickets where state='voided'` = qty; buyer's card credited | A9 is outcome-shaped ("money actually returning"). This is the only executed proof; it also proves the invoker |

**End state of §5:** venue money for that sale sits as a `primary_sale` line only when someone opens/closes a
settlement; no payout exists; `payout-execute` is not deployed. That is a legal launch posture (G6 §4.1) with a
disclosure obligation to the venue (contract) and Stripe's 2-year US holding limit.

---

## 6. PAYOUT ACTIVATION (gated section B — separately owner-authorized)

**The exact "on" mechanism, proven:** there is **no flag**. `[X]` §2.5. After 093/094/095 the payout executor is off
because (1) it is not deployed, (2) nothing invokes it, (3) `claim_payouts_for_execution`'s eligible set is empty until a
human org money role produces `status='submitted'` with `destination_ref` pinned, which `request_org_payout` (093:1743)
refuses unless the settlement payout is `hold_state='none'` — and every close mints `held/unbounded_refund_exposure`
while `payout.settlement_maturity_interval` is null (093:2100-2106). **Default-off is therefore a conjunction of an
undeployed function, an unarmed invoker and a null key** — not a boolean.

| Step | Marker | Command / query | Verification | Why |
|---|---|---|---|---|
| **P-0** | `OWNER APPROVAL REQUIRED` | **G5 signed** (its approval text: "the venue payout executor may not be deployed until this ruling is signed") + Gate-M re-attested (PRE-3, already required for 094) + G4 left **HELD** (owner direction) | signature block | H4 D-4's "acceptable because no executor exists" ends at P-2 |
| **P-1** | `READ ONLY` | at least one `venue.settlement` `closed` with `net_minor > 0`, its payout `pending/held(maturity_*)`; `select kernel.settlement_payout_maturity('<S>')` | reason code is `maturity_not_elapsed` only (not `unbounded_refund_exposure`, `refund_in_flight`, `dispute_open`) | proves S-10(4) is live and the eight predicates evaluate |
| **P-2 Deploy `payout-execute`** | `EDGE DEPLOY` `OWNER APPROVAL REQUIRED` | `supabase functions deploy payout-execute --no-verify-jwt`; env: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY`, `INTERNAL_CRON_SECRET` (optional; service key also accepted) | `POST {}` with service key → `{"status":"ok","attempted":0}` (**not** 501); wrong bearer → 401 | needs 093's four execution verbs + 095's `hold_payout_transfer_reversed` (`REVERSED_RPC`, `index.ts:79`) → after S-3 |
| **P-3 Human request** | `PRODUCTION DB MUTATION` (org money role, aal2, ≥72 h role maturity) | org_finance → `kernel.retry_held_payout(org, settlement, ck)` (095:485) once matured → `kernel.request_org_payout(org, settlement, ck)` | `select status, hold_state, destination_ref, stripe_transfer_ref from kernel.payout where cause_ref='<S>'` = `submitted`, `none`, `acct_…`, `null`; above `payout.dual_control_min_minor` (null ⇒ every payout parks, X-12) a `payout.request` approval row for platform_risk/admin | `guard_payout_org_payable` (095:100) fires on `→ submitted`; `destination_ref` pinned here is what the executor sends |
| **P-4 Manual single execution (NOT the cron)** | `STRIPE MUTATION` `TWO-PERSON REQUIRED` (owner watching) | `POST payout-execute {"limit":1}` with the service key, once | `GET /v1/balance` preflight passed (executor.ts), Stripe transfer `tr_…` created on the platform account to `destination_ref`; `select status, stripe_transfer_ref from kernel.payout` = `paid`, `tr_…` (via `mark_payout_transfer_state`); `venue.settlement.status='paid'` (`on_payout_settled`); `select amount_reversed` sync path not triggered | first money leaves the platform; matrix 10(c) requires the platform's own Stripe payout schedule be **manual** or a float above the largest matured settlement |
| **P-5 Arm the payout invoker** | `PRODUCTION MIGRATION` (097) `OWNER APPROVAL REQUIRED` | `cron.schedule('payout-execute-tick','*/15 * * * *', $$select net.http_post(url:='…/functions/v1/payout-execute', headers:=…service_role_key…, body:='{"limit":25,"lease_seconds":900}'::jsonb)$$)` | cron row `succeeded`; edge log `run complete` | only after P-4 succeeded by hand. Kill switch = `select cron.unschedule('payout-execute-tick')` (rollback tree class 4) |
| **P-6 Threshold keys** | `PRODUCTION CONFIG` `TWO-PERSON REQUIRED` | `payout.dual_control_min_minor`, `payout.request_auto_max_minor`, `payout.destination_cooldown_hours`, `payout.destination_probation_days` — all park | approval rows approved by a second admin | `destination_ref` exists (S-3) so the matrix's ordering constraint 2 is discharged; set **after** the first manual execution so the first payout was dual-controlled by construction |

**Never in either section:** `kernel.release_payout` on a `promoter_commission` payout (G4 unsigned; owner direction:
HELD at launch). `[X]` V17 stays 0.

---

## 7. A9 — refund executability: what "deployed, tested, healthy" concretely means

**What exists.** `refund-execute` (`index.ts` + `executor.ts`, 70 TS tests) with four actions (`index.ts:836`):
`record` (buyer/org/platform JWT → `request_order_refund` direct arm or `refund_primary_order` delegated arm),
`admin_refund` (platform JWT), `execute` (platform JWT, one refund), `sweep` (cron secret **or** service key →
`claim_refunds_for_execution` → `executeOne`/`reconcileOne` per row). DB side: `get_refund_execution_context` (093:1038),
`claim_refunds_for_execution` (093:1311; `[X]` 158 green), `mark_refund_state` (085:1737). Env: `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY` (shared client), `INTERNAL_CRON_SECRET` (optional).
Stripe: `POST /v1/refunds` with a `refund_<id>` idempotency key; the payment row must be `stripe_livemode=true`.

**What is missing for "automated" (A9 disjunct 1):** an invoker. `[X]` no cron, no `net.http_post`, no schedule
anywhere names it. Deploying the function makes single refunds executable **by a platform human per refund** and makes
the sweep executable **by a human with the secret**. That is disjunct 2 (a named human), not disjunct 1.

**Option A (recommended): deploy + 096 invoker migration + proof on the first sale.**
- 096 = one `cron.schedule` in the `enforce-transfer-expiry` shape (`[X]` cron row §2.8) posting
  `{"action":"sweep"}` with the Vault `service_role_key`; cadence `*/5` (lease 900 s, `p_limit` 25 — both clamped
  server-side 093:1311). Idempotent re-apply guard `where not exists (select 1 from cron.job where jobname=…)` (088:1877).
  Rollback = `cron.unschedule`. pgTAP: job exists, command names the function, no other job changed (CRON register row).
- Verification = S-6 (0-row sweep, not 501) → S-7 (cron `succeeded`) → S-15 (a real refund reaches `succeeded` with a
  `re_…` and the card is credited). "Healthy" = Sentry no `refund-execute:sweep` exceptions over 24 h and
  `select count(*) from kernel.refund where status in ('pending','submitted') and created_at < now()-interval '1 hour'` = 0.
- Honest cost: 096 is a new migration-bearing PR (AUTODEPLOY gate, immutability), and the 24-hour Stripe idempotency
  window vs the 20 h `create`/`reconcile` split (093:1311 `v_window`) is only as good as the cadence being < 4 h.

**Option B (fallback): a named written process.** To satisfy A9's own words it must contain: the named accountable
human (name, role, backup); the trigger (daily query `select refund_id, status, created_at from kernel.refund where
status in ('pending','submitted') order by created_at`); the exact act (`POST refund-execute {"action":"sweep"}` with
the secret, or per-refund `execute`); the write-back (the executor itself calls `mark_refund_state`; the process must
record the run in `kernel.admin_audit` via `record_money_denial`/notes or a dated log); an SLA (≤ 20 h, because past
the `create` window the row must be `reconcile`d against Stripe before a second refund could be minted); and what to do
on `stripe_error` (retry) vs `refused` (escalate). **It does not exist anywhere in the corpus** (H9 §3). It would be
dishonest to call B "automated" or to launch on B without the daily query actually being run.

---

## 8. STALE items for the orchestrator to fix (do not edit here)

| Where | Stale claim | Actual |
|---|---|---|
| `PRIMARY_TICKETING_ACTIVATION_MATRIX.md:127,130,140,153,156,71,78,188,294` + `H9:62-64,349` | `093:3983 / 4033 / 4062` checkout gates; `093:4229 / 4442 / 3486 / 4742 / 5067 / 5220 / 4831 / 6907 / 7143 / 6705 / 5808 / 5867` | **4026 / 4076 / 4105**; **4272 / 4485 / 3487 / 4785 / 5110 / 5263 / 4874 / 6950 / ~7186 / 6720 / 5851 / 5857-5920** (P2-1) |
| Matrix :288, H9 :344 (step 2) | "Expose `catalog` + `venue` — must come after step 1" placed **second** | move to immediately before `primary-checkout` deploy (P1-4) |
| Matrix :291, H9 :347 (step 5) | "Deploy `refund-execute` … A9's first disjunct" | deploy alone is not disjunct 1; add "arm the sweep invoker (096)" (P0-2) |
| Matrix :296, H9 :352 (step 10) | flag "last of all" with the first quote implicit | the first controlled quote **follows** the flip; the flag is also the `reserve_primary_inventory` gate (P1-2) |
| Matrix :298-300, H9 :354 | PAYABLE tail: "deploy `payout-execute` → only then may `dual_control_min_minor` be set" | add: P-1 matured settlement, P-4 manual single execution before P-5 invoker; state that there is **no** executor flag |
| Matrix :7-10, 287; H9 :343 | "ledger 107 → 110" fine; **no mention that no 093 rollback exists** | P0-3 |
| `PHASE2_ROLLBACK_DECISION_TREE.md:33-40` | reverse loop `092..076` | no 093 arm; must say 093 is forward-only or add the file |
| `scripts/release/phase2_preflight.sql` L1/L2, `phase2_postapply_verify.sql` V1/V3/V4/V7/V9, `local_rollback_battery.sh` loop | 076..092 literals; 43 keys; orphan deletion key | 093..095: 110 / 76 / 270 / 49; V9 should name `deletion.post_event_hold_hours` (P0-4, [X] §2.6) |
| `PRODUCTION_SIGNING_KMS_CEREMONY.md:177` | `093_parts/40_config_privacy_freeze.sql:341-465` | `:446-521` |
| `PRODUCTION_SIGNING_KMS_CEREMONY.md:872` | `078:1145-1147` prefix set | `093:6720-6723` (same conclusion) |
| `FINAL_ACTIVATION_BLOCKER_RULINGS.md:151-153` (G1 approval text) | names `deletion.refund_possible_window_hours` | live key is `deletion.post_event_hold_hours` (093:5851); old key is an unread orphan (P2-3) |
| `FINAL_ACTIVATION_BLOCKER_RULINGS.md:14-16` | "108-migration chain" | 110 |
| `PHASE2_DEPLOYMENT_RECORD_20260902.md:88` | "24-hour close: NOT DUE" | still true as a fact; the close-out was never written (P0-1) |
| `docs/architecture/_governance/CRON_SCHEDULE_REGISTER.md:28` | resale sweep "scheduled in 088" | 088:1867 deliberately did **not** schedule it (P2-5) |
| `H1_refund_architecture.md:36` | "`planSweep` filtered `status==='pending'`" (as overturned) | now moot: the DB claim covers `pending`+`submitted` (`[X]` §2.5); fine as history, but the matrix row 8(c) should cite the DB predicate |

---

## 9. Options and the smallest honest design

| Question | Options | Smallest honest choice |
|---|---|---|
| 093 rollback (P0-3) | (a) author `093_*_rollback.sql` (payments CHECK/NOT NULL restore, 4 column drops, ~14 body restores — large, and every body restore must be the 092 text byte-for-byte); (b) owner signs "093 forward-only on apply" and the runbook drops the class 1/2 arm for it | **(b)** — 093 replaces ~14 bodies; a restore file is a second 7k-line artifact with its own drift risk. The dark posture (flags false, `venue` unexposed, no signing key) already makes a mid-apply failure recoverable by fix-forward |
| A9 invoker (P0-2) | (A) 096 cron migration; (B) written human process; (C) both | **(A)**, with (B)'s daily query kept as the monitor. Dishonest: calling the deploy alone "automated" |
| Exposure timing (P1-4) | matrix step 2 vs late (S-11) | **late** — zero code, strictly fewer minutes of an `authenticated`-callable money RPC |
| Payout "flag" (P1-1) | (a) add a `payout.executor_enabled` key (new migration + edge read); (b) rely on deploy+invoker+null maturity key | **(b) at launch**, stated explicitly; (a) only if the owner wants a config-visible kill switch — note `payout.%` is dual-controlled, which is the wrong shape for a kill switch (H9 §7: "a kill switch that needs a quorum is not a kill switch") |
| Release scripts (P0-4) | edit the four 076–092 scripts in place vs new `phase2b_*` files | **new files** — the 092 scripts are the record of what was run on 2026-09-02 |

---

## 10. Open questions for the orchestrator / owner

1. **Is the 24 h observation of 076–092 closed?** No record exists. Who writes the close-out, from which live reads, and
   is the `prod/phase2-apply-20260902` tag to be cut?
2. **093 forward-only on apply — acknowledged in writing, or is a `093_*` rollback to be authored first?**
3. **A9: option A (096 invoker) or B (named process)?** If A: cadence, and whether `INTERNAL_CRON_SECRET` (already used by
   `enforce-transfer-expiry`, DAY2 guide :131) or the Vault `service_role_key` header is the sanctioned bearer — 088:1867
   ruled that no Vault name/header for `INTERNAL_CRON_SECRET` exists in bytes, so the service-key path is the only one
   already precedented in a migration.
4. **Exposure order:** may the runbook move `catalog`+`venue` exposure to just before `primary-checkout` (S-11)?
5. **Gate-M re-attestation** is required for **applying 094** (matrix 0a′), which is in the *sale* train (S-3), not the
   payout train — is the owner attesting now, or are 094/095 to be held back and only 093 applied (the three are disjoint
   `[X]`, and 095 does not depend on 094)? If held back, the S-3 plan check must list exactly `093`.
6. **Who is the second `platform_admin`** for the four parked keys in S-10? Two distinct aal2 admins are needed; today the
   corpus names one superuser holder (H7).
7. **Which `deletion.post_event_hold_hours` value** — FABR deliberately gives none (:522-530).
8. **Is `payout-execute`'s first execution to be manual (P-4) before any cron (P-5)?** The runbook above assumes yes.

---

**Nothing in this document has been authorized, applied, deployed or committed. No production mutation, no remote, no
Stripe call, no secret read. Executed evidence is from `snatchit_rehears_i` only.**
