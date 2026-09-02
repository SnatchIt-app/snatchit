# PHASE 2 — FINAL STATE CENSUS (post-092; docs/reporting only)

**Status:** REPORTING ARTIFACT. Records the end state of the 076–092 implementation train on
`phase2/consolidation` at the 092 merge. It changes no byte, activates nothing, and asserts nothing
about production (which has NONE of 076–092 applied). Authority order and every ruling it cites live
in `PHASE_2_ARCHITECTURE_FREEZE.md` and `POST_FREEZE_AMENDMENTS.md` (E-1…E-162, PFA-1…PFA-31).
Counts are the suite-asserted values (`supabase/tests/140…157`) on a fresh 001→092 replay.

## 1. The train (17 packages, no gaps, no duplicates — ODR-1 as re-ratified for the 076–092 band)

| Package | Merge commit on `phase2/consolidation` | Subject |
|---|---|---|
| 076 | `ee15b883f4c5513fe5d1940a21bca08d7b21b019` | Phase-2 package 076 — schemas, GRANT boundary, transactional outbox + OR-14 emit pair (#29 |
| 077 | `b060923ea99ec9fd76f5780e26f2146d51393557` | Phase-2 package 077 — kernel identity/orgs/roles + the OR-17 deletion state machine (#30) |
| 078 | `c730240bd16c75aa7c890bf823c94046b8416175` | Phase-2 package 078 — catalog reference data, config plane + PFA-7 owner signature (#32) |
| 079 | `bb4eb26c363984a0e06e5dccf474c1decb2ceddf` | Phase-2 package 079 — ticket atom, custody ledger + the BP-1 deletion blocker body (#33) |
| 080 | `c6cc53eddbee5413a6a05f89a1471a95164374b1` | Phase-2 package 080 — venue staff roles, the authority predicates + the AUTHZ-PKG1 policie |
| 081 | `262a716f73d0fbde85290097ed9039638414b069` | Phase-2 package 081 — venue ticket-type / inventory substrate (C27 oversell-safe) (#35) |
| 082 | `456aaa711b411c27b5823544902f2867aee56808` | Phase 2 · Package 082 — venue orders (primary-purchase container + CRM consent) (#36) |
| 083 | `53fe02fe85cf75686211126853e7fa450763b1d4` | feat(083): kernel credential infrastructure — mint engine + wallet substrate + signing key |
| 084 | `cb2b23002a99221debb753d4b0e0c9b6d6318fc3` | feat(084): kernel.tickets late-binding FKs — the ADOPT step, and nothing else (#38) |
| 085 | `f22fad6d8024c031e0c7552c7f23c450950f2c44` | feat(085): kernel money native — refunds, payouts, obligations, finalize (#39) |
| 086 | `9768308f2a2444d420af72715b2576cff33c1b2a` | feat(086): venue door & scan — manifest episode ledger, tokenized sessions (parked), holde |
| 087 | `35ddbae90f14a543dce1ace491e3173efe7c2c17` | feat(phase2): package 087 — venue settlement + CRM export (PFA-28 fail-closed parks) (#42) |
| 088 | `3ef477fa6b26cf8a44c2f2c1ddc2d849029ae85c` | feat(phase2): package 088 — market native rail, transfer engine, R-40 disputes, PFA-29 set |
| 089 | `aa7ec36140390ea00a22b2f8a01d140c8607a4ee` | feat(phase2): package 089 — market.listing_unified bridge VIEW + adopt payment_native.sale |
| 090 | `d3d50ce367eefad3fcfdcc1d4b32b01f76457dd9` | feat(phase2): package 090 — venue promoter engine (attribution · promoter codes · commissi |
| 091 | `ea6dc818b205ac4bdc1d67b1ee3dc9b7eac241cd` | feat(phase2): package 091 — kernel.reserve stub (the only Gate-K object built in MVP) (#49 |
| 092 | *(this PR's squash — recorded in the closing report)* | notify reduced plane + outbox drainer |

Every migration 076–091 is byte-identical to its merge blob (one commit each, verified at the 092
pre-flight); 092 is the chain tip and the train ENDS here. 093+ does not exist.

## 2. ODR-16 — end-state deletion-body census (all REAL, zero stubs)

| Routine | State | Package |
|---|---|---|
| `kernel.request_account_deletion(text)` | REAL | 077 |
| `kernel.withdraw_account_deletion(text)` | REAL | 077 |
| `kernel.sweep_deletion_pending(integer)` | REAL (HARDENING-1 body) | 077 → 078 |
| `kernel.deletion_blockers_custody` (BP-1) | REAL | 079 |
| `kernel.deletion_blockers_orders` | REAL | 082 |
| `kernel.deletion_blockers_wallet` (BP-2) | REAL | 083 |
| `kernel.deletion_blockers_money` | REAL | 085 |
| `kernel.deletion_blockers_market` (BP-3/4/7/8 twins) | REAL | 088 |
| `kernel.on_identity_erased_staff` | REAL | 080 |
| `kernel.on_identity_erased_door` | REAL | 086 |
| `kernel.on_identity_erased_market` | REAL | 088 |
| `kernel.on_identity_erased_promoter` (INV #36) | REAL | 090 |
| `kernel.on_deletion_q5_release` | REAL | 085/088 |

Lifecycle notices (092): `account_deletion_pending` (self, I+P; E suppressed) on entry; `account_deletion_completed`
(self, E-only → suppressed until N1) once, by the terminal sweep, after the committed ERASED state; replay-safe at
hop 2 (`UNIQUE(event_type,event_key)`) and hop 3 (`dedupe_key`); post-erasure push suppressed `identity_erased`;
the notification plane never mutates deletion state (157 section J).

## 3. SEAM final census — TOTAL 19 · REAL 19 · NEUTRAL 0 · OVERLOAD 0

kernel: `deletion_blockers_custody` · `deletion_blockers_orders` · `deletion_blockers_wallet` · `deletion_blockers_money` ·
`deletion_blockers_market` · `on_identity_erased_staff` · `on_identity_erased_door` · `on_identity_erased_market` ·
`on_identity_erased_promoter` · `has_outstanding_obligations` · `on_deletion_q5_release` · `settlement_royalty_lines` ·
`settlement_commission_lines` — venue: `resolve_order_attribution` · `on_payout_settled` · `append_door_manifest_delta` —
market: `on_atom_voided` · `on_door_freeze_engaged` · `door_freeze_drain_preview`.
Every hook has exactly ONE overload (SEAM-2a: signatures, parameter names, return types and ACLs frozen; bodies replaced
by `CREATE OR REPLACE` only). 091 and 092 replaced no body (156 C2; 157 A48/A49).

## 4. Writer final census

`scripts/precedence_gate.py` — 175 distinct writers, checks A–H hold. 092's rows of `WRITER_REGISTRY_PARITY_SPEC.md`
(229–239) are delivered as written: `notify.notification` ← enqueue · drain_outbox · mark_read · mark_all_read · dismiss;
`preference` ← set_preference; `notification_type` / `template` SEED-ONLY; `delivery` ← drain_outbox (via enqueue) ·
claim_deliveries · record_delivery_result; `outbox` ← emit_event · emit_event_required · drain_outbox (state / cursor);
`identity_channel_state` ← record_delivery_result · register_push_token; `public.push_tokens` ← register_push_token ·
revoke_push_token · record_delivery_result. No client role can INSERT or DELETE a notification (GP-2).

## 5. Cron final census — 19 rows (absolute)

`auto-finalize-auctions` · `enforce-transfer-expiry` (pg_net, legacy) · `sweep-auth-password-changes` · `sweep-deletion-pending` ·
`sweep-expired-org-invites` · `sweep-expired-ticket-atoms` · `sweep-expired-inventory-holds` · `sweep-expired-refund-requests` ·
`sweep-expired-door-sessions` · `sweep-expired-door-overrides` · `sweep-implicit-door-freezes` · `refresh-holder-mix` ·
`reconcile-holder-mix` · `sweep-expired-exports` · `crm-export-build-tick` (pg_net, fail-closed on Vault) ·
`crm-export-purge-tick` (pg_net, fail-closed on Vault) · `market-sweep-expired-p2p-transfers` · `market-sweep-paid-pending-sales` ·
**`notify-drain-outbox`** (`*/2 * * * *`, `notify.drain_outbox(200)`).
NOT scheduled (parked, E-158 / E-79 class): `notify-dispatch`, `notify-receipts`, `resale-checkout-sweep`.

## 6. Edge final census

Repository (`supabase/functions/`, pre-Phase-2 era, production): `auto-finalize-auctions` · `confirm-and-release` ·
`confirm-payment` · `create-connect-account` · `create-payment-intent` · `delete-account` · `enforce-transfer-expiry` ·
`notify-report` · `notify-transfer` · `send-push` · `stripe-webhook` (+ `_shared`).
Phase-2 edge functions specified by `PHASE_2_EDGE_FUNCTION_SPEC.md` and NOT authored / NOT deployed (deploy artifacts,
every one behind an owner gate): `notify-dispatch` · `notify-receipts` · `credential-sign` · `primary-checkout` (+ code/link
params) · `promoter-code-preview` · `crm-export-worker` · `refund-execute` · `payout-execute` · the Stripe-webhook
native branches. **No Phase-2 edge function exists in production.**

## 7. Notification idempotency + failure-isolation proofs (157)

Three keys, three layers: hop 2 `UNIQUE(event_type, event_key)` (E9); hop 3 partial `UNIQUE(dedupe_key)` + `ON CONFLICT DO
NOTHING` with the existing id returned (D10–D13, E10–E11); hop 4 `UNIQUE(notification_id, channel)` (D17). Wire semantics
are AT-LEAST-ONCE with a lease (`claimed_until`): an expired lease is re-claimable (F32–F33), a lease that expires five
times is dead-lettered (F34–F35); exactly-once on the wire is NOT claimed. Failure isolation: one poison envelope goes
`dead` with `last_error` while the rest of the batch completes (E12–E15); two drainers cannot interleave (xact advisory
lock; race harness R1); two claimers never claim the same row (`SKIP LOCKED`; R2, overlap 0); two results on one delivery
serialise on the row lock and the second is a terminal no-op (R3). A notification failure never reaches money or custody
state (`notify.enqueue` is non-raising; producers emit BEST-EFFORT or REQUIRED per OR-14 — the REQUIRED class raises only
when the ENVELOPE cannot be written, never for a downstream fan-out fault).

## 8. Final dark-rail composition

| Rail | State | Gate to leave the state |
|---|---|---|
| Native primary issuance (081–083) | DARK — `feature.native_issuance_enabled=false` | owner flag + `credential-sign` edge + signing keys in KMS |
| Native door / scanning (086) | DARK — `feature.native_scanning_enabled=false`; door PIN KDF PARKED (PFA-26) | owner flag + PFA-26 ruling + PFA-25 config surface |
| Apple Wallet (083) | DARK — `wallet.apple.enabled=false`; bearer-token crypto PARKED (PFA-20) | owner flag + PFA-20 mechanism + pass-type cert |
| Native money (085) | DARK — refund/payout EXECUTION are edge artifacts (PFA-23 delegation shape in DB); `refund-execute`/`payout-execute` not deployed | edge deploy + Stripe Connect activation + owner release gate |
| Venue settlement (087) | ACTIVE-ON-APPLY (DB-only); payouts flow only through the dark money rail | money rail |
| CRM export (087) | PARKED FAIL-CLOSED — PFA-28 `customer_ref` crypto; worker secret unnamed | PFA-28 ruling + Vault secrets + worker edge |
| Native resale / P2P / disputes (088–089) | DARK — `feature.native_resale_enabled=false`; 3-way split PARKED (PFA-30); dispute dual control PARKED (PFA-31); public projection `NATIVE_DISCOVERY_PUBLIC_PROJECTION` open | owner flag + PFA-30/31 rulings + `RESALE_CHECKOUT_SWEEP_TICK` |
| Promoter engine (090–091) | INERT / PARTIAL-HELD — accrues attributions; every `promoter_commission` payout HELD `unfunded_settlement`; `COMMISSION_FUNDING_SOURCE` policy RESOLVED (Option B) / IMPLEMENTATION OPEN; `kernel.reserve` empty | the Option-B implementation (13-item proof list) + `COMMISSION_PAYOUT_LIFECYCLE` |
| Notifications (076 + 092) | FAIL-CLOSED — drainer scheduled; `claim_deliveries` refuses (lease unset); edge ticks parked; email N1-gated (every E row suppressed); announcements OFF (OR-5 [C]) | `NOTIFY_DELIVERY_LEASE_VALUE` + `NOTIFY_DISPATCH_TICK` + Expo credentials; email separately `EMAIL_GO_LIVE` |
| Identity / orgs / deletion (077–080) | ACTIVE-ON-APPLY (DB-only; the sweep is scheduled) | none for the DB half; `delete-account` edge alignment is a release-gate item |

"ACTIVE-ON-APPLY" means: would run once the migrations are applied — they are NOT applied anywhere.

## 9. Forward-obligation ledger (complete, classified)

Classes: **BP** BLOCKS PRODUCTION · **BFA** BLOCKS FEATURE ACTIVATION (of the named rail) · **OPR** OWNER POLICY REQUIRED ·
**IMPL** IMPLEMENTATION REQUIRED · **EXT** EXTERNAL OPERATIONAL REQUIREMENT · **OPT** OPTIONAL-FUTURE.
"Blocks production" is read narrowly: applying 076–092 to a database with every rail dark is blocked only by the
rows marked BP; every other row blocks the rail it names.

| Obligation | Class | Rail / owner of the fork |
|---|---|---|
| `ROLLBACK_GUARD_ROW_SECURITY` (091) | BP · IMPL | 088/089/090 rollbacks count deny-all tables without `row_security=off` — fix before any production rollback is possible |
| PFA-1 compensating control (per-schema function default belt impossible) | BP · EXT | release gate must run the PFA-1 sweep against production after apply |
| Production migration ledger reconciliation 076–092 vs the 89-row ledger; `db push --include-all`; `AUTODEPLOY-VERIFIED-OFF` | BP · EXT | release gate |
| Vault secrets: `service_role_key`, `INTERNAL_CRON_SECRET`, `crm_export_worker_secret`, `RESEND_API_KEY`; pg_net + pg_cron on production | BP for the ticks that exist (`crm-export-*` fail closed without them) · EXT | release gate |
| `NOTIFY_PRODUCER_PARITY` (E-161) | BFA (money/custody/viability types) · IMPL | body-only amendments 079/080/083/085 + edge producers |
| `NOTIFY_DISPATCH_TICK` (E-158) | BFA (notifications) · IMPL + EXT | header + Vault names (owner), two edge functions, two cron rows |
| `NOTIFY_DELIVERY_LEASE_VALUE` (E-154) | BFA (notifications) · OPR | owner sets the interval |
| `EMAIL_GO_LIVE` (N1 / O-N3) | BFA (email channel) · OPR + EXT | domain/DMARC, provider, templates |
| `NOTIFY_DEVICE_LOCALE_COLUMN` (E-157) | OPT · OPR | localisation beyond en-US |
| `NOTIFY_INBOX_COMPOSITE_CURSOR` (E-160) | OPT · IMPL | signature amendment |
| `NOTIFY_DRAIN_THROUGHPUT` (E-162) | OPT · IMPL | body-only constants |
| `COMMISSION_FUNDING_SOURCE` (E-138; Option B countersigned 2026-09-02) | BFA (promoter payouts) · IMPL (policy resolved) | the 13-item proof list |
| `COMMISSION_PAYOUT_LIFECYCLE` (E-138) | BFA (promoter payouts) · OPR + IMPL | §17.7 controls on `cause='promoter_commission'` |
| `PROMOTER_COMMISSION_PAYOUT_HOLD` (E-132) | BFA (promoter payouts) · IMPL | dispute leg for commission payouts |
| `AFFILIATE_PAYOUT_DESTINATION` | BFA (affiliates) · OPR | payee shape for identity-less affiliates |
| `PROMOTER_MANAGER_CODE_READ` (E-124) | BFA (dashboard codes tab) · OPR | RLS matrix cell |
| `PROMOTER_CODE_PREVIEW_EDGE` · `PRIMARY_CHECKOUT_CODE_PARAMS` | BFA (promoter codes at checkout) · IMPL | deploy artifacts |
| `NATIVE_RESALE_SPLIT_POLICY` (PFA-30) | BFA (native resale) · OPR | platform/venue/seller split |
| `DISPUTE_DUAL_CONTROL` (PFA-31) | BFA (disputes) · OPR | approver class + threshold |
| `NATIVE_DISCOVERY_PUBLIC_PROJECTION` | BFA (public discovery of native listings) · OPR + IMPL | a separate anon projection (PFA-14/E-106 class) |
| `RESALE_CHECKOUT_SWEEP_TICK` (E-79) | BFA (native resale) · IMPL + EXT | header/Vault names + cron row |
| `REQUEST_ORG_PAYOUT_OPEN_DISPUTE_GATE` · `REFUND_HOLD_RELEASE_REARM` · `VOID_PATH_LOCK_LADDER` · `CHARGEBACK_CROSS_SETTLEMENT_UNIQUE` | BFA (money/resale) · IMPL | 088 red-team residuals, Gate M |
| `NEGATIVE_SETTLEMENT_CARRY` · `PUBLIC_PAYMENTS_NATIVE_SHAPE` · `P2P_TRANSFER_TTL` · `PAID_PENDING_DWELL_SLO` · `RESALE_CHECKOUT_LATE_PAYMENT_DWELL` · `LISTING_EXPIRY_SWEEP` · `OFFER_COUNTER_DECISION` | BFA (native resale / settlement) · OPR | 088 owner forks recorded as undecided |
| `CRM_CUSTOMER_REF_CRYPTO` (PFA-28) · `crm-export-worker` | BFA (CRM export) · OPR + IMPL + EXT | HMAC mechanism ruling, worker edge, Vault secret |
| Door PIN KDF (PFA-26) · per-event door config surface (PFA-25) · holder-mix audit/alarm (PFA-27) | BFA (native scanning / demographics) · OPR + IMPL | owner rulings |
| Wallet bearer-token crypto (PFA-20) · pass-type cert · `credential-sign` edge | BFA (Wallet / native issuance) · OPR + IMPL + EXT | owner ruling + Apple artefacts |
| `refund-execute` · `payout-execute` · native `stripe-webhook` branches (PFA-23 delegation consumers) | BFA (native money) · IMPL + EXT | deploy artifacts + Stripe Connect |
| PFA-9 CLASS-A config gaps (`door.session_touch_interval`, `door.schedule_move_grace_interval`) | BFA (native scanning) · OPR | values never invented |
| Announcements (OR-5 [C] OUT) · SMS · quiet hours (§3.6) · template CMS · `es-US` copy | OPT | a later gate; nothing built |

## 10. Readiness matrix (four different questions — each answered separately)

| Question | Answer | Basis |
|---|---|---|
| ARCHITECTURE COMPLETE? | **YES** | frozen corpus at tag `phase2-architecture-v2` + amendments PFA-1…PFA-31, E-1…E-162; every owner fork is either countersigned or filed as an obligation above |
| IMPLEMENTATION COMPLETE (the 076–092 train)? | **YES for the frozen package scope; NO for its deploy artifacts** | 17 migrations, 17 rollbacks, suites 140–157 (35 files / 2 927 planned assertions), every CI gate green; edge functions, secrets and producer parity are obligations, not bytes |
| FEATURE ACTIVATION READY (any rail)? | **NO — every rail** | §8: each rail sits behind an owner flag that is `false` and at least one PARKED / OPEN row in §9 |
| PRODUCTION DEPLOYMENT READY? | **NO** | nothing of 076–092 is applied anywhere; the BP rows in §9 are open; a separate PHASE-2 PRODUCTION READINESS / RELEASE GATE (owner-authorised) has not begun |

*(reporting artifact; maintained beside `POST_FREEZE_AMENDMENTS.md`; never an authority)*
