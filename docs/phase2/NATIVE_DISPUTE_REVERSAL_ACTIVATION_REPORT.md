============================================================
SNATCH IT — NATIVE DISPUTE + REVERSAL + ACTIVATION REPORT
============================================================

**Train:** native dispute wiring · reversal lifecycle · activation sequencing.
**Session scope:** backend, database, money, security, production readiness, activation. **No UI work.**
**Date:** 2026-09-03. **Nothing was deployed, applied to production, exposed, configured, flipped, or committed to `main`.**

REPOSITORY

| | |
|---|---|
| **BRANCH** | `feature/venue-native-and-product-v2` |
| **HEAD** | `609e0f4` at entry; this train's commit is authored on top of it |
| **PR** | [#52](https://github.com/SnatchIt-app/snatchit/pull/52), open, base `phase2/consolidation` |
| **CI** | GREEN locally (full replay, full pgTAP, vitest, typecheck, lint, assembler); GitHub CI runs on push |
| **WORKTREE** | four new migrations + rollbacks + tests, three edge files, one new edge module, doc updates — all listed below |

PRODUCTION

| | |
|---|---|
| **LEDGER** | **107 rows**, through `092_notify_reduced` + five timestamped website migrations. Read-only verified at entry and exit; unchanged. |
| **093** | authored, **NOT APPLIED** (md5 `0e6729d72cf3f61b0a00c2683962d400`, byte-identical to entry — assembler G-4 PASS) |
| **094** | authored, **NOT APPLIED** |
| **095** | authored, **NOT APPLIED** |
| **NEW MIGRATIONS** | **096, 097, 098, 099** authored, **NOT APPLIED** |
| **MUTATIONS** | **NONE.** No apply, deploy, schema exposure, config, flag, Stripe call, KMS ceremony, or secret. |
| **ACTIVATION** | **NO** |

------------------------------------------------------------
NATIVE DISPUTE ROUTING
------------------------------------------------------------

STRIPE EVENTS: `charge.dispute.created`, `charge.dispute.updated` (NEW branch), `charge.dispute.closed`, `charge.dispute.funds_withdrawn|funds_reinstated` (status-sync as `updated`), `transfer.reversed` (native routing), plus the legacy events unchanged.

OLD ROUTE: every dispute/refund/transfer event wrote only `public.disputes` / `public.transfers` / `public.payments`; `charge.dispute.updated` and `funds_*` hit the default ACK; native disputes were invisible to the kernel (KA P0-1/P0-2, KH P0-1). `kernel.record_dispute_native` / `mark_dispute_state` had **zero callers**.

NEW ROUTE: `supabase/functions/stripe-webhook/native-dispute.ts` (new, import-free pure module) + native arms placed BEFORE each legacy arm in `index.ts` (legacy bytes byte-identical — `git diff` on `index.ts` is 404 insertions, 0 deletions). `created` → `kernel.record_dispute_native`; `updated`/`closed` → `kernel.mark_dispute_state`, falling back to `record` at the payload status on `not_found`. `transfer.reversed` → `kernel.record_payout_reversal` per reversal fact.

LEGACY PRESERVED: yes — the resale/legacy arms are unchanged and still own every legacy event; a `native_primary`-mode payment routes to the native arm, everything else to legacy.

NATIVE PAYMENT RESOLUTION: DB-derived, never metadata. `dispute.payment_intent` → `public.payments` (`id, mode, stripe_livemode, status`); `mode = 'native_primary'` ⇒ native, else legacy; null PI or absent row ⇒ legacy. Livemode gate (`event.livemode && payments.stripe_livemode`) else ack+alert with legacy still running.

IDEMPOTENCY: event-id lease (064) + business uniqueness (`dispute_native_stripe_ref_uq`, `payout_reversal_stripe_ref_uq` on the `trr_`) + forward-only state machines (`mark_dispute_state` terminal-absorbing; `record_*` replay to `noop_replay`).

OUT-OF-ORDER HANDLING: `closed`-before-`created` records at terminal (zero freeze legs) + alert; a stale `updated`/`created` after terminal raises `state_conflict` → ACK+alert (a redelivery can never fix it); `not_found` → ACK+alert; `created` always uses `record` (never `mark`, which would regress an open↔open status). Every native path ends via `finishDecision`, never a `markProcessed({error})`-then-200 fallthrough (KH P1-1 fixed).

------------------------------------------------------------
DISPUTE STATE MACHINE
------------------------------------------------------------

STRIPE → DB MAPPING: the eight-label `kernel.dispute_native.status` set is honoured; unknown labels (`prevented`) → ACK+alert `native_dispute_unknown_status`, never a retry loop (recorded owner item — the CHECK is in immutable 088).
OPEN: `record_dispute_native` freezes the disputed atoms (`dispute_hold`) and reachable pending/submitted payouts (`hold`, reason `dispute`).
WON: releases nothing (PFA-31; the parked resolver is unchanged) — logged, holds persist. Recorded owner item.
LOST / charge_refunded: alerted; the chargeback settlement-line arm books the venue debit at the next close (venue-scoped after 097).
TERMINAL-FIRST: a `created` or `closed` arriving already-terminal records at that status with zero freeze legs + alert.
REGRESSION DEFENSE: `mark_dispute_state` is forward-only + terminal-absorbing; `record` is replay-safe on the Stripe dispute ref; a native rail guard (097) refuses a payment that is neither `native_primary`-mode nor linked through `kernel.payment_native` (closing the KB P1-1 legacy leak).

------------------------------------------------------------
CHARGEBACK ACCOUNTING
------------------------------------------------------------

FACE CAP: preserved (ruling A5) — the chargeback line is capped at face minus prior refunds/chargebacks; the buyer-fee slice stays a platform loss.
BUYER FEE: unrepresented on the venue side, by A5 — recorded, not booked (owner item; no `dispute_fee` object exists).
REFUND OVERLAP: 097 adds a refund-deferral mirror to the chargeback arm — a dispute is not lined while a refund that could still succeed is in flight, closing KC P0-2 (the phantom debt against a venue paid 0).
CANCELLATION OVERLAP: `cancel_event`'s prior-return guard holds (KC 2.h); no double return.
SETTLEMENT LINE: the `chargeback` arm is now **venue-scoped** (097) — it joins the disputed order's event to the settlement's venue, closing the KG/KC P0-1 cross-venue leak (a venue's loss no longer nets into a sibling venue's payout).
ORGANIZATION OBLIGATION: a negative close books `settlement_shortfall`; the org-side debt now carries `venue_id` (097) so recovery can be venue-scoped (legal debtor = org, recovery source = originating venue).
DOUBLE-DEBIT DEFENSE: bidirectional — the `unlined_reversal` origin is refused when a line already exists (094), and 097 adds the reverse fence so the chargeback/refund arms skip an origin already carrying an obligation.

------------------------------------------------------------
UNLINED REVERSAL
------------------------------------------------------------

OLD STATUS: INERT — no producer, and the guard was one-directional (KC P1-2, KD F-8).
NOW REACHABLE: still operator-only (the webhook does NOT book it synchronously — KH P1-6, to avoid double-count) but now **fenced** (097): the origin must resolve to a real `lost`/`charge_refunded` dispute or `succeeded` refund whose primary order was actually **paid out** (post-payout proof), and the amount is **ledger-derived** (caller cannot name it).
ORIGIN: `dispute_id | refund_id`, order derived through `payment_native`, venue derived through the order's event.
COLLISION DEFENSE: bidirectional fence (above) — a loss booked as an obligation is never lined, a lined loss is never booked.
IDEMPOTENCY: `UNIQUE(origin_kind, origin_ref)` + `stripe_dispute_ref` partial unique.

------------------------------------------------------------
TRANSFER REVERSAL
------------------------------------------------------------

FULL: `kernel.record_payout_reversal` records the `trr_` fact; when Σ reversed = payout amount it drives `status → reversed` **through the existing `mark_payout_transfer_state` edge** (no second door onto status).
PARTIAL: representable at last — `kernel.payout_reversal` facts, `amount_minor > 0`, Σ-guard ≤ `payout.amount_minor`; the payout stays `paid`, `kernel.payout_reversed_minor(payout)` projects the returned amount. This closes KE F-2/F-3 (a partial was previously unrepresentable and a reversed transfer read as `paid` at full face).
STRIPE FACTS: `transfer.reversed` fires per reversal; `reversed` is full-only, `amount_reversed` carries the money; the webhook pages the reversal list when `has_more`.
DB MODEL: KE §4.1 model A — append-only facts table, `trr_` unique idempotency, nullable set-once `obligation_id` for the recovery link.
STATE: `paid` while Σ < amount; `reversed` when Σ = amount. `venue.settlement` stays `paid` (E-5 forbids rewinding a header).
AMOUNT: derived from the payout's own `amount_minor`; the caller's numbers are evidence only.
IDEMPOTENCY: `trr_` unique; replays → `noop_replay`.
REPLAY: safe — the webhook records each `trr_` once; a redelivery is a no-op.
OUTSTANDING DEBT EFFECT: a reversal that recovers an obligation is recorded via `kernel.record_obligation_recovery` (see below); a non-recovery reversal is a platform-liability owner item (KE §4.1 §2).

------------------------------------------------------------
FAILED PAYOUT WITH TRANSFER REF
------------------------------------------------------------

OLD DEFECT: a `failed` payout carrying a `tr_` was stranded across twelve verbs; the executor could not even claim it (KE F-5).
RECONCILIATION: `kernel.claim_failed_payouts_for_reconcile(limit, lease)` + `kernel.reconcile_payout_transfer(payout, ref, observed, key)` (096); the executor's new second phase (`payout-execute` reconcile pass, `planFailedReconcile` pure derivation) reads the Stripe transfer + its reversals + the transfer group and calls the verb.
AUTHORITY: service_role only; the caller may not name an amount; the stored `stripe_transfer_ref` must match (never adopts the caller's pair).
PAID: clean transfer (amount/currency/destination match, no reversal) ⇒ the single-writer `failed → paid` edge inside the verb, then `venue.on_payout_settled`.
FULLY REVERSED: `failed → paid` then reversal facts ⇒ `paid → reversed`.
PARTIAL: `failed → paid` + reversal facts, stays `paid`.
UNKNOWN: 404 / mismatch / ambiguous ⇒ stays `failed`, audited `transfer_unresolvable`, pages — never invents an outcome.
DOUBLE-PAY DEFENSE: never creates a transfer in this pass; idempotent; the amount is compared, never stored from the caller.

------------------------------------------------------------
ORGANIZATION OBLIGATION
------------------------------------------------------------

LEGAL DEBTOR: the organization (`org_id`), unchanged.
RECOVERY SOURCE: the originating venue — `organization_obligation.venue_id` is now stored (097), derived from the origin header/dispute.
VENUE SCOPE: the chargeback arm is venue-scoped (097); a venue's loss no longer consumes a sibling venue's payout.
CROSS-VENUE: not permitted by default (owner direction 2026-09-03) — enforced by the ring-fence.
CROSS-ORG: isolated (proved, KG V8).
RECOVERY FACTS: `kernel.organization_obligation_recovery` (096) — append-only, `amount_minor > 0`, `source_kind ∈ {transfer_reversal, manual}`, `UNIQUE(source_kind, source_ref)`, Σ-guard ≤ obligation amount, `transfer_reversal` must reference a real `payout_reversal` of the same org.
PARTIAL RECOVERY: representable — status becomes `recovered` (derived) only when Σ recoveries = amount; `kernel.obligation_outstanding_minor` projects the residual.
WRITEOFF: explicit platform act (authenticated + is_platform + aal2), records the remaining amount; refused once terminal.
OUTSTANDING: `kernel.org_outstanding_obligation_minor` nets recoveries (096 re-creation). The 094 defect — the resolve verb was unreachable by any real principal (KD P1-1) — is fixed: it is now granted to `authenticated` and requires is_platform + aal2, and refuses `recovered` without receipts.

------------------------------------------------------------
G4 PROMOTER
------------------------------------------------------------

LAUNCH HOLD: enforced — no promoter payout, no release. `mark_payout_transfer_state` now refuses `cause = 'promoter_commission'` (098), making the fourth containment lock an explicit refusal rather than an absence (KF P2-1).
PRE-CLOSE PARTIAL REFUND: fixed — 098 replaces the atom-survival basis with a real-fact basis (`face − least(face, Σ succeeded refunds + capped lost/charge_refunded disputes)`), so a partial refund yields a reduced pro-rata line instead of total forfeiture (KF P1-1) or full commission on a failed refund (KF P1-2).
PRO-RATA FUNDING: `floor(surviving × bps / 10000)`; flat-per-ticket = `floor(surviving_face / unit_price) × flat`. Recorded as **PFA-PT-4, PENDING OWNER SIGNATURE** (a basis change from the frozen atom reading — KF §5). A `settlement.commission` audit row is now written for every evaluated attribution, including the zero case.
POST-CLOSE REVERSAL: unchanged — commission stays HELD (G4); 098 does not release, pay, or post-close-reduce.
PROMOTER PAID: never (four independent locks; the fourth now explicit).
VENUE EFFECT / PLATFORM EFFECT: the org-side shortfall overstates venue debt by the retained held commission (KC 2.i / KF P1-3) — recorded as an addition to G4 question (iii); not auto-resolved.

------------------------------------------------------------
CONSERVATION
------------------------------------------------------------

FULL CHARGEBACK: venue debt = what the venue received; chargeback capped at face; obligation books the residual (KC 2.a). Conserves.
PARTIAL CHARGEBACK: `chargeback = face − refunds` (KC 2.f). Conserves.
REFUND + DISPUTE: the two arms now move together in one close (097 deferral mirror) — credit + debit, net 0, no phantom obligation (KC P0-2 fixed).
TRANSFER REVERSAL: recorded as facts; recovery links to the obligation; no double count (KE §4.4).
PARTIAL TRANSFER REVERSAL: representable; venue keeps `amount − Σ`; obligation reduced by Σ.
PROMOTER CASE: venue 9000 + held commission 1000 = 10000; the 1000 never left the platform; obligation overstatement recorded (owner item).
CROSS-VENUE CASE: closed — venue A's loss books to venue A / the org obligation, never to venue B's payout (KG/KC P0-1 fixed; test 163).

------------------------------------------------------------
A9
------------------------------------------------------------

REFUND EXECUTABILITY: the executor exists; its **automated invoker now exists** as a dark cron `refund-execute-tick` (099), config-gated by `refund.executor_enabled = false`. A9's automated-executor disjunct is buildable and armable (KI P0-2 addressed) — still NOT deployed or armed.
MACHINE: `claim_refunds_for_execution` + `refund-execute` sweep; the cron posts with the Vault service key while the gate is true.
RUNBOOK: `docs/phase2/PRIMARY_TICKETING_PRODUCTION_ACTIVATION_RUNBOOK.md` sequences deploy → arm → prove-the-tick → prove-a-real-refund before selling.
SALE ACTIVATION CONDITION: refund executability proven on the first sale (runbook S-15), or the named manual process — the runbook states both.

------------------------------------------------------------
KMS
------------------------------------------------------------

RUNBOOK UPDATED: yes — `PRODUCTION_SIGNING_KMS_CEREMONY.md` corrected for the quote-time gate, the mint source (by object name), the ITEM-2 path, §9.3 replaced by the migration-099 monitor + its arming step, and the "093–099 applied" wording (KJ §3). No secret/key/ARN/fingerprint added.
MONITOR AUTHORED: yes — `kernel.check_signing_key_invariants()` + daily cron `monitor-signing-key-invariants` + three `signing.*` config seeds + the `notify-report` `signing_invariant_alert` egress (099). Dark: returns `monitor_disabled` while `signing.monitor_enabled = false`; alert body carries no key material, no handle, no fingerprint (only a match/MISMATCH/unpinned word).
CEREMONY EXECUTED: **NO**
SIGNING KEY CREATED: **NO**
IRREVERSIBLE POINT: UNCHANGED (the first mint; unreachable until a quote passes the signing gate).

------------------------------------------------------------
MIGRATIONS
------------------------------------------------------------

| | md5 | notes |
|---|---|---|
| **093** | `0e6729d72cf3f61b0a00c2683962d400` | UNCHANGED (assembler G-4 PASS, byte-identical to entry) |
| **094** | `1beb85aa6973d3748fa181895e39f9c1` | UNCHANGED |
| **095** | `cb85cac5183d974c392b6422877b2aa4` | UNCHANGED |
| **096** `payout_reversal_and_obligation_recovery` | `466e0f605e20748e7ddd7e53889fbf5d` | NEW |
| **097** `settlement_scope_and_shortfall` | `6730beaf5a94d716938bae7f556d9055` | NEW (guard broadened by the orchestrator — see ADVERSARIAL) |
| **098** `promoter_prorata_funding` | `2684b3f67326cd9e166f164a9e9d74c0` | NEW |
| **099** `signing_monitor_and_executor_invokers` | `e83aca66b2dd76ebcd3e26de5246be43` | NEW |

TABLES: +2 kernel (`payout_reversal`, `organization_obligation_recovery`, both 096); 29 → 31.
FUNCTIONS: +10 kernel (096 +9, 099 +1; 097/098 body-only re-creates, no count change); 136 → 146; five-schema 270 → 280.
TRIGGERS: +3 kernel (096); Gate-2 public triggers unchanged (26).
POLICIES: 0 new (deny-all RLS on the new tables); Gate-2 public unchanged (37).
ENUMS: 0 new (all closed sets are CHECKs).
COLUMNS: +1 (`kernel.organization_obligation.venue_id`, 097).
CRON: +3 (099: `monitor-signing-key-invariants`, `refund-execute-tick`, `payout-execute-tick` — all dark); 19 → 22.
CONFIG: +5 restricted (099: `signing.monitor_enabled`, `signing.expected_key_fingerprint`, `signing.expected_max_not_after`, `refund.executor_enabled`, `payout.executor_enabled` — all seeded false/null); 49 → 54.
EXISTING ROW MUTATIONS: NONE.
GATE-2 DELTA: **NONE** — public schema census unchanged at tables=27 functions=70 policies=37 triggers=26.

------------------------------------------------------------
ACTIVATION RUNBOOK
------------------------------------------------------------

FILE: `docs/phase2/PRIMARY_TICKETING_PRODUCTION_ACTIVATION_RUNBOOK.md` (executable, **NOT EXECUTED**).
OWNER GATES: G1/G2/G3/G4/G5 signatures, Gate-M re-attestation, refund-claim-verb ratification, 093-forward-only acknowledgement — all recorded as preconditions.
MIGRATION ORDER: apply 093 → 094 → 095 → 096 → 097 → 098 → 099 in one `db push --include-all` (dry-run must list exactly those seven).
SCHEMA EXPOSURE: `catalog` + `venue` exposed LATE, immediately before `primary-checkout` deploy.
EDGE DEPLOY ORDER: connect-onboarding → stripe-webhook (native branches) → refund-execute → notify-report → (later) payout-execute.
KMS ORDER: ceremony parallelised, landed before config; monitor armed after.
CONFIG ORDER: inventory → ticket.expiry_grace → payout.settlement_maturity_interval → deletion.post_event_hold_hours (only after the refund tick is proven) → fee.buyer_service_bps.
SALE ACTIVATION: ends at one controlled quote/payment/mint + a real refund (A9 proof).
PAYOUT ACTIVATION: separate, G5-gated section; deploy → matured settlement → human request → one manual execution → then arm the invoker.
PROMOTER ACTIVATION: in neither section; `release_payout` on a `promoter_commission` payout prohibited until G4 is signed.

------------------------------------------------------------
ACTIVATION MATRIX
------------------------------------------------------------

DRAFT: YES · PUBLISHABLE: YES · SALEABLE: NO · PAYABLE: NO (updated in `PRIMARY_TICKETING_ACTIVATION_MATRIX.md`, third revision).
ROWS READY: 2 of 12 (event drafting, event publish) — unchanged, and correctly so.
REMAINING SALEABLE BLOCKERS: 093–099 unapplied; `catalog`/`venue` unexposed; connect-onboarding / stripe-webhook (native) / primary-checkout undeployed; no signing key; `fee.buyer_service_bps` unset; refund invoker unarmed.
REMAINING PAYABLE BLOCKERS: all of the above + G5 signature + Gate-M attestation + payout-execute undeployed + payout invoker unarmed + no bound payout destination.

------------------------------------------------------------
SECURITY
------------------------------------------------------------

P0: **0.**
P1: the pre-existing findings this train CLOSED — native disputes invisible to the kernel (KH P0-1), cross-venue netting leak (KG/KC P0-1), phantom obligation on in-flight refund (KC P0-2), obligation resolve verb unreachable (KD P1-1), partial transfer reversal unrepresentable (KE F-2/F-3), ref-bearing failed payout stranded (KE F-5), `transfer.reversed` dropped for native (KE F-1), pre-close promoter forfeiture (KF P1-1/P1-2), no `stripe_transfer_ref` uniqueness (KE F-6, closed by a unique index in 096).
P1 OPEN (recorded, owner follow-up): a native-resale sale disputed BEFORE its transfer writes `payment_native.sale_id` is refused (fail-closed, retried, alerted) rather than recorded — documented in `KT_pgtap_reconciliation.md`; the resale rail is dark, so it is not launch-blocking.
P2: `won` releases nothing (PFA-31); `prevented`/late-win unrepresentable in the immutable 088 CHECK (owner items); the buyer-fee slice of a lost dispute is an unrecorded platform loss (A5).

------------------------------------------------------------
ADVERSARIAL REVIEW
------------------------------------------------------------

CLAIMS OVERTURNED: the pre-train belief that the dispute writers merely "needed a caller" understated it — 097's rail guard, the venue ring-fence, and the unlined fence were all required for the wiring to be honest, not just wired.
DEFECTS FOUND: one during consolidated verification — 097's first rail guard exempted only `payment_native.sale_id`, wrongly refusing a primary-order dispute whose payment carries `payment_native.order_id` (surfaced by test 153's `finalize_primary_order` fixture). The orchestrator broadened the guard to accept any `payment_native` row OR `native_primary` mode, which still rejects only genuinely legacy payments — closing the leak without refusing a real primary dispute.
DEFECTS FIXED: that guard; plus every P1 listed above.
OPEN FINDINGS: the pre-transfer native-resale dispute gap (P1 OPEN above); `won`/`prevented`/late-win owner items; the obligation overstatement by held commission (G4 iii); recovery-by-automated-reversal-initiation not built (KE §4.1 §2).

------------------------------------------------------------
TESTING
------------------------------------------------------------

PGTAP: **plan=3486 ok=3482 not_ok=4** — only the four documented local-only deltas (060×2 TODO, 132×2 db-name). New files 162 (payout reversal + recovery), 163 (settlement scope + shortfall), 164 (promoter pro-rata), 165 (signing monitor + invokers); census + behavioural reconciliation across 141–161 (see `KT_pgtap_reconciliation.md`).
VITEST: **489 passed** (was 375; +114 — 89 dispute-decision-table cases, 25 failed-reconcile cases).
TYPECHECK: clean. LINT: clean (0 errors).
WEB / MOBILE: no shared contract changed; edge changes are Deno (outside tsc/vitest scope, verified by inspection).
FRESH DB: full 000–099 replay clean; Gate-2 27/70/37/26.
IMMUTABILITY: 000–095 byte-identical; 093 assembler G-4 PASS.
ASSEMBLER: PASS.
ROLLBACK BATTERY: 096–099 reverse cleanly on a fresh chain — kernel functions 146 → 136, tables 31 → 29, cron 22 → 19, the two 096 tables dropped (099's five config seeds remain as documented append-only orphans).
CI: green locally; GitHub CI on push.

------------------------------------------------------------
OWNER DECISIONS
------------------------------------------------------------

Recorded as DIRECTION (unsigned) in the ruling files; nothing self-signed:
G1: `ticket.expiry_grace = "72 hours"` — PENDING.
G2: payout maturity `max(session.ends_at) + 7 days`, now a **nine**-predicate conjunction (097 adds `dispute_unabsorbed`) — PENDING.
G3: ceremony approved in principle, NOT executed — PENDING.
G4: promoter commission HELD at launch; 098 implements pre-close pro-rata FUNDING only (PFA-PT-4 PENDING); question (iii) gains the overstatement finding — PENDING.
G5: organization obligation is THE durable record; recovery facts built (096); no default cross-venue netting (097); the approval text's cross-venue line pre-filled "not permitted" but UNSIGNED — PENDING.
GATE-M: re-attestation section + sixth signature line added; required before applying 094 and before venue payout activation — PENDING.
NEW OWNER ITEM: **PFA-PT-4** (promoter basis: atom-survival → real settled-refund-fact) PENDING SIGNATURE; the pre-transfer native-resale dispute gap; `won`/`prevented`/late-win representation.

------------------------------------------------------------
PRODUCTION
------------------------------------------------------------

PRODUCTION CHANGES: **NONE.**
PRODUCTION ACTIVATION AUTHORIZED: **NO.**

------------------------------------------------------------
FINAL STATUS
------------------------------------------------------------

NATIVE DISPUTE PATH READY: **YES** (wired, tested; deploy-gated).
CHARGEBACK ACCOUNTING READY: **YES** (venue-scoped, refund-deferred, obligation-recorded).
TRANSFER REVERSAL READY: **YES** (full + partial representable).
PARTIAL REVERSAL REPRESENTABLE: **YES.**
ORGANIZATION OBLIGATION RECOVERY READY: **YES** (facts + resolve verb reachable).
CROSS-VENUE ISOLATION READY: **YES** (ring-fenced; test 163).
G4 LAUNCH POSTURE READY: **YES** (HELD; pro-rata funding built, PFA pending).
REFUND BACKEND READY: **YES** (executor + dark invoker).
VENUE PAYOUT EXECUTOR CODE READY: **YES** (incl. failed-reconcile + reversal facts).
VENUE PAYOUT EXECUTOR SAFE TO DEPLOY: **NO** — G5 unsigned + Gate-M unattested.
PRIMARY SALEABLE BACKEND READY: **NO** — deploy/expose/config/signing-key pending.
PRIMARY PAYABLE BACKEND READY: **NO.**
093 PRODUCTION READY: **NO** (owner values + ratifications first).
094 PRODUCTION READY: **NO** (G5 signature + Gate-M attestation).
095 PRODUCTION READY: **NO.**
NEW MIGRATION PRODUCTION READY: **NO** — 096–099 authored, verified, dark; apply only under the runbook.
ACTIVATION RUNBOOK READY: **YES** (authored, not executed).
KMS CEREMONY SHOULD RUN NEXT: **NO** — schedule it (longest pole), land it before primary-checkout deploy, per the runbook.

RECOMMENDED NEXT CLAUDE A TRAIN: the **production activation train** — collect the owner signatures (G1–G5, Gate-M, PFA-PT-4, refund-claim ratification), author the 093-forward-only acknowledgement or a 093 rollback, write the `phase2b` preflight/postapply/rollback-battery scripts for the 093–099 apply, and execute the runbook's SALE-ACTIVATION section under two-person control up to the first controlled quote. Payout activation and the pre-transfer-dispute gap follow as their own gated steps.

============================================================
STOP. Nothing deployed, applied, exposed, configured, flipped, or moved. No KMS, no Stripe, no secret.
============================================================
