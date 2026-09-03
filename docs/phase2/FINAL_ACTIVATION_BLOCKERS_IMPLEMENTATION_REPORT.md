# Final activation blockers — implementation report

**Train:** final activation blockers + safety hardening.
**Date:** 2026-09-02/03.
**Outcome:** all four goals met. Three owner decisions remain, none approved.

---

## REPOSITORY

| | |
|---|---|
| **BRANCH** | `feature/venue-native-and-product-v2` |
| **HEAD** | `fc88320` (entered at `ca0ac0a`; 1 commit added) |
| **PR** | [#52](https://github.com/SnatchIt-app/snatchit/pull/52), open, base `phase2/consolidation` |
| **CI** | **GREEN** — 7/7, including *Immutability + ordering* (now carrying the new assembler gate) and *Migrations apply cleanly (fresh DB)* |
| **093** | `supabase/migrations/093_primary_ticketing.sql`, 5226 lines, md5 `e139aeb5bb48df63393dd93cb116bbb2` |

**Entry state verified mechanically before any change**, and it matched the prompt exactly: head
`ca0ac0a`, clean tree, 093 at the reported md5 `6ab87362…`, CI green, production ledger at 107 rows
ending at `092_notify_reduced` with no `093`.

---

## ASSEMBLER SAFETY

### Problem

`scripts/assemble_093.sh` concatenates four reviewed slices into the migration. Nothing in CI proved
`SLICES == ASSEMBLED`. The previous train recorded an incident where the artifact silently drifted
from its slices and nothing caught it.

### Fix

A gate in `.github/workflows/migrations-guard.yml`, job `guard` (*Migrations guard / Immutability +
ordering*), as its **first two steps** — deliberately **before** the job's change-detection early
exit, because the commonest drift is a PR that edits only slices and touches nothing under
`supabase/migrations/`. Placed later it would be silent exactly when needed. **No new required status
check** was added; the job name is unchanged, avoiding the disappearing-required-check deadlock this
repo has already been bitten by.

**The first design was defeated four ways by adversarial review, and the root cause was that the gate
asked the assembler what to check.** A lying `--manifest` dropped a whole 58 KB slice while printing
"byte-for-byte from 4 slices"; `cp -R scripts/.` smuggled arbitrary SQL; slices could be symlinks; a
decoy `parts_dir` redirected the build. All four exited 0.

Rebuilt so that every fact is derived rather than declared:

| Fact | Before (trusted) | After (derived) |
|---|---|---|
| Which files are slices | `part=` in the manifest | `git ls-files` |
| File kind | *unchecked* | git mode + on-disk `-f` / `! -L` |
| Where slices live | `parts_dir=` | filename convention `assemble_<TAG>.sh` → `<TAG>_parts/` |
| Artifact location | `out=` | the one tracked `<TAG>_*.sql` |
| Build inputs | whatever the script read | hermetic sandbox + stowaway check |
| SQL survived | assumed | each slice's committed bytes appear in the artifact exactly once |

`--manifest` survives only as a cross-check; disagreement with the derived facts is itself a failure.

### Tests

`scripts/ci/assembled_migration_integrity_selftest.sh` — **24/24**, identical locally and under
`CI=true`. The original six drift scenarios (missing, duplicated, reordered, stale, hand-edited,
whitespace) plus anti-vacuity cases (slices deleted, assembler deleted, banner stripped, artifact
deleted), determinism under perturbed locale/TZ/umask/cwd, and — the class the first self-test
structurally could not see — cases that mutate the **assembler or manifest** while leaving the
artifact perfectly consistent with the subverted build.

**The gate proved itself twice in live conditions:** once while being built, catching real drift from
a concurrent agent, and once at the end of this train, when `144` went red because the slices had
moved ahead of the artifact.

### Canonical-source rule

**(A) The slices are canonical. The assembled migration is a build artifact.** Verified rather than
assumed, from four independent signals: the assembler header already said so; every slice declares
itself a fragment carrying no `begin;/commit;` because the assembler owns the transaction, so a slice
is not independently applicable while the artifact is; the assembler is a pure ordered concatenation
with no inverse; and the recorded drift incident only parses as a build-ordering failure under (A).

Enforced, not merely documented: the artifact opens with a `-- @generated-by:` banner, and the banner
cannot drift because it *is* assembler output. A documented interaction the repo had not written down:
once 093 merges, the immutability invariant freezes the artifact — which **freezes the slices too**,
since any slice edit forces an artifact change that immutability rejects.

---

## ALL-IN PRICING

### Old bug

`src/lib/pricing/allIn.ts` asserted that on the direct rail `venue."order".total_minor` **is** the
entire buyer charge — true before ruling A5, false after it. A5 fixes the venue's entitlement at face
value and funds Snatch It through a configurable buyer-side fee, so feeding `total_minor` to the
primitive under-showed the real price by exactly the fee. That is the dishonesty the module exists to
prevent.

### New contract

The direct-rail input **no longer has a single "total" field** a caller can fill with face value, so
the bug is unrepresentable rather than documented against:

```ts
type DirectPriceInput = {
  rail: 'direct';
  faceValueMinor: Cents | null | undefined;   // order.total_minor — face, NOT the price
  buyerServiceFee: BuyerServiceFeeInput;      // REQUIRED — no default, no zero
  chargeTotalMinor?: Cents | null;            // authoritative, cross-checked
  currency?: string; tax?: TaxInput;
};
```

Results carry the full breakdown (`totalMinor`, `faceValueMinor`, `buyerServiceFeeMinor`, `taxMinor`),
and `allInFromPrimaryCheckout()` is the one supported reader of the edge's 200 body, so no screen ever
picks between `amount` and `total`. Three refusal reasons added: `service-fee-unset` (the A5 owner
STOP, never a zero fallback), `service-fee-out-of-range`, `quote-incoherent`. Direct-rail arithmetic
is integer-only, half-up, matching the RPC's `round(numeric)` exactly.

**Adversarial review then found the 100× collision still reachable** — `formatMinor(50)` returned
`"$0.50"`, and `asCents()` (which the guidance itself recommended) is an unchecked cast, so
`asCents(50)` on the resale rail produced `"$0.55"`, both tsc-clean. Closed at the type level:
`formatMinor` accepts only `Cents`; `centsFromDollars` returns a distinct subtype that `asCents`
cannot produce, so the resale rail rejects the escape hatch at compile time. **Zero false positives —
no threshold, no heuristic.**

A magnitude guard on `asCents` was **declined, deliberately**: a 10% `buyer_fee_minor` on a $5 face
*is* 50, and a tax line can be 25, so the false positives land squarely on the fields A5 introduced. A
guess that rejects real money is not safer than a type that cannot be wrong.

### Tests

**314/314** (299 baseline → +15). Proof the guard bites: reverting only the three type narrowings makes
the `@ts-expect-error` directives *unused*, which fails the typecheck gate. Runtime pin of the
divergence: `formatMinor(asCents(50)) === '$0.50'` beside `formatMinor(centsFromDollars(50)) === '$50'`.
Resale unchanged across a 200,000-case differential; no float arithmetic on the direct rail across a
0/126 differential.

---

## EXPIRY

### Findings

Measured across fifteen dimensions, `expired` enforces **exactly one live thing: the door refuses the
credential**. It additionally enables the BP-1 deletion blocker to clear, **breaks** cancellation
refunds (`catalog.cancel_event` excludes expired atoms), and degrades chargeback overlay handling. It
does not affect app visibility, attendee history, settlement, or promoter commission.

`ends_at + grace` is the **only expressible** derivation: `catalog.event` carries no time column at
all, there is no per-atom TTL, no `admission_until`, and door-close is per-manifest and nullable.

**A premise was corrected, then the correction was itself overturned — both are recorded.** Research
first judged the previous report wrong about paying buyers being undeletable, because
`deletion.refund_possible_window_hours` (BP-12 arm 2) independently blocks them. Adversarial review
then showed BP-12 measures from `order.created_at` — the *payment* clock that ruling G2 spends its
entire analysis rejecting — so setting it lets a buyer who paid early be tombstoned **before their
event**, while G2's gate holds the venue's money for exactly that risk. The previous report was right
on substance.

**The interval type trap was worse than documented and is now closed in code.** `('24'::jsonb)::interval`
is `00:00:24` — twenty-four *seconds*, not a failed cast. Root cause: the type witness is skipped when
the current value is JSON null, and **every** owner-STOP key in 093 is null-seeded, so each accepts any
JSON type on precisely the first write the owner is about to make. `set_platform_config` now refuses a
bare number for interval-typed keys.

### Recommendation

`ticket.expiry_grace` = `'"72 hours"'::jsonb`. Floor of 24h forced by the ratified
`door.session_absolute_max_interval`; 72h is the corpus's own ratified human-reaction constant and
crosses a full business day for a Friday or Saturday event.

### Remaining owner value

The 72-hour figure (ruling G1). Separately, **no duration is recommended for
`deletion.refund_possible_window_hours`** — its clock must be re-anchored to the event first, which is
a code change and a separate decision.

---

## REFUND / SETTLEMENT MATURITY

### Findings

**The §17 hazard was real and present.** The hold was `v_held := v_refund_window is null` — a single
"is the config set" test. Setting any value released the venue's money with **no event-based maturity
semantics implemented at all**. That is precisely a config value acting as a hidden feature flag for
logic that did not exist.

**The key was a lie and has been renamed.** `settlement.refund_window_interval` named refund
*eligibility*, which genuinely exists and already owns `refund.buyer_self_service_window_hours`,
`refund.request_ttl_hours` and `refund.scanned_atom_policy`. The value is a payout hold measured from
the event's end. It is now **`payout.settlement_maturity_interval`**, and the prefix is load-bearing:
`payout.%` matches the dual-control test, so setting it now parks for a second `platform_admin`.
Verified empirically — the set returns `parked`, writes no new version, and leaves the value null.
Under the old prefix it matched nothing and was a single unilateral write, on the one key in the
migration where *setting* the value is the dangerous act.

### Recommended start

**`max(catalog.event_session.ends_at)` over the settlement's own money lines** — not payment, not
close, not `period_end`. The schema forces it: `catalog.event` has no time column;
`venue."order".event_session_id` is NOT NULL so every covered order resolves to one session; and
deriving from lines rather than the header makes the anchor computable for event- and period-scoped
settlements alike. Decisive test passes: an order bought 90 days before an event 60 days out is HELD.
Stripe's dispute clock agrees on the anchor ("the dispute window starts on the event date, not the
payment date"), cited as corroboration only — **Stripe's payout schedule is not Snatch It's settlement
policy.**

### Recommended interval

**7 days**, with the trade stated rather than hidden. Full dispute coverage would need ~120 days after
the event, which is commercially impossible and exceeds the 90-day non-US manual-payout limit. Stripe
publishes no post-event hold figure. 7 days is more conservative than Stripe's own ticketing guidance,
sits inside both ceilings, and covers post-event refunds and executor latency. **The tail beyond it
needs a receivable object or fixed reserves — both separate owner items.**

### Failure behavior

Held unless **all** hold: policy set → non-negative → covered set resolvable → no covered
event/session cancelled → anchor known → interval elapsed → no non-terminal refund on a covered
payment → no open dispute. Every operand is pre-set to the holding value and every branch is
`coalesce(…, holding)`, so an uncomputable predicate can only fail toward the hold. Eight distinct
`hold_reason_code` values. Adversarial review broke **each of the eight in isolation** and all eight
held, with an all-satisfied control releasing — which is what makes each hold attributable.

### Remaining owner decision

The 7-day interval (ruling G2), plus acceptance of the post-release chargeback tail.

---

## SIGNING

### Local rehearsal

**12/12 PASS** with non-production material on a 108/108 replay: bootstrap row, active-key resolution,
mint, signature, verification against the PEM read back out of the database, inactive key rejected,
wrong key rejected, **rotation preserving verification of previously issued tickets**, a second key
serving new mints, uniqueness, immutability (the guard fires on `public_key`, `kms_handle_ref`,
`scope`), and deletion blocked once referenced. Ceremony gates also rehearsed: stale fingerprint,
private key pasted, placeholder handle and replay all abort.

Not reachable without a real KMS, stated rather than faked: a real `KMS.sign`, provider handle syntax,
the unbuilt door rail, and KMS IAM two-person enforcement.

### KMS ceremony readiness

`docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` is executable by a technically cautious owner without
improvising database commands. Every operation is marked `READ ONLY` / `LOCAL` / `KMS MUTATION` /
`PRODUCTION DB MUTATION` / `IRREVERSIBLE AFTER MINT` / `OWNER APPROVAL REQUIRED`, real values are
unmistakable placeholders, and no example secret appears anywhere.

**The implementation is provider-agnostic** — nothing in code names a KMS, `kms_handle_ref` is bare
`text` with no CHECK, and there is **no insert-time validation at all**, so Postgres cannot distinguish
a real key from a placeholder. The runbook therefore pins seven decisions, including a
**version-pinned handle** (an unversioned GCP handle would silently change the signer under an
immutable `public_key`).

### Dual-control proof

Prevented: application admin swapping the public key; stale fingerprint; the same key registered twice
as a second global; unauthorized activation by any client role; malicious rotation; `service_role`
bypass. Honestly **not** prevented, with compensating controls named: Person A or B completing alone
(IAM separation and the provider audit trail are the controls, not the database); a handle pointing at
different material (the binding proof is the sole detector); a superuser disabling a key.

**One P1 found and fixed here:** `issue_ticket_atoms` trusted a caller-supplied `signing_key_id`, so a
`service_role` caller could override the resolver — making the per-event-shadow threat not
superuser-only. Investigating it revealed the gate and the mint were doing **different operations**:
`finalize` *resolved* the key, the mint only *checked coherence* with an unconditional `global` arm.
That is exactly how the two could disagree while both "succeeding". All three sites now perform the
same operation, and a supplied value that disagrees is refused rather than silently ignored.

### Production action still required

The ceremony itself. **Nothing else in this document is on the critical path in the same way:** every
other blocker can be resolved by configuration, and this one cannot. As of this train the dependency
is also *visible* — checkout now refuses with `no_active_signing_key` at quote time rather than failing
after the buyer has paid.

---

## ACTIVATION GATES

| Gate | Predicate | Enforced? |
|---|---|---|
| **DRAFT** | approved org + venue + event + session + ticket type + inventory batch. Nothing else. | SQL |
| **PUBLISHABLE** | `publish_event(…,'announced')` + role authority. No money prerequisite. | SQL |
| **SALEABLE** | issuance flag → both inventory keys → event `on_sale`/`live` → bound Connect account **and** transfers active → **active signing key** → buyer service fee set | SQL |
| **PAYABLE** | the eight-predicate maturity hold, then `request_org_payout`, then `release_payout` | SQL |

**A8's SALEABLE was previously enforced only on the purchase half** — `publish_event(…,'on_sale')`
succeeded with nothing configured. Recorded as a finding.

**Ruling A9 resolved:** PAYABLE is correctly *not* required for SALEABLE — collection is separate from
payout and the ledger records the obligation. But **refund executability is** required by A9 and is
**not satisfied**: the executor is undeployed, `kernel.list_pending_refunds` does not exist so the
sweep returns 501, and PFA-23's direct arm is unreachable in both directions.

Full matrix: `docs/phase2/PRIMARY_TICKETING_ACTIVATION_MATRIX.md`. **Two of twelve rows ready** — event
drafting and event publish, exactly the two A8 rules require nothing.

---

## MONEY DARKNESS

Verified on a live replay, not inherited:

| Rail | State |
|---|---|
| **Payment** | Cannot activate. Three feature flags false; five 093 config keys null; checkout refuses without a signing key, a bound Connect account, transfers active, and a fee rate. |
| **Refund** | Cannot activate. Executor undeployed; `mark_refund_state` has no caller; sweep returns 501. |
| **Venue payout** | Cannot activate. No payout edge function exists; `set_org_payout_destination` has no non-comment caller; the maturity conjunction holds by default. |
| **Promoter payout** | Cannot activate, and correctly so per ruling A4 — commission payouts mint `held`/`unfunded_settlement` and nothing releases them. Re-verified after every change. |

**Single-config-flip hazards remaining: none on the money path.** `fee.buyer_service_bps` was the last
instance of the banned pattern — it crossed the SALEABLE gate unilaterally — and `fee.%` is now in the
dual-control prefix test. Two non-config hazards remain and are recorded: a direct
`UPDATE kernel.organization SET connect_transfers_active = true` (a permanent unaudited per-org grant),
and the PostgREST exposed-schema setting, which is a dashboard field and not in git.

---

## TIER-1 UI READINESS

**YES — the next train can begin the Product V2 Tier-1 redesign.**

This is a statement about contract stability, not backend activation. The blocker named in the previous
report was that `allIn.ts` was stale under A5; that is fixed, and fixed in a way that makes the old
mistake a compile error. A screen cannot now be built against a contract that silently under-shows the
price.

| Surface | Ready | Note |
|---|---|---|
| Home | Yes | Media + provenance + price ladder stable |
| Explore | Yes | Same |
| Unified Event Page | Yes | Provenance ordering ruled; direct/marketplace distinction fixed |
| Ticket Selection | Yes | Inventory contract stable; holds are server-authoritative |
| Checkout | Yes, against mocks | Edge contract fixed (`charge_total_minor`); `service-fee-unset` is an explicit state to design for, not an error to hide |
| Purchase Confirmation | Yes | Order shape stable |
| Tickets | Partly | Credential display is stable; anything depending on scan or Wallet is still dark |

The honest caveat: UI built now must treat `service-fee-unset` and `no_active_signing_key` as
first-class states, because both are the resting state until the owner acts.

---

## TESTS

| Suite | Result |
|---|---|
| pgTAP | **2981 planned, 2977 pass** — the 4 failures are the documented local-only deltas (060's two TODOs, 132's two cron DB-name artifacts) |
| vitest | **314/314**, 9 files |
| typecheck | clean (exit 0) |
| lint | 0 errors, 12 pre-existing warnings |
| web build | passes |
| assembler self-test | **24/24** |
| migration replay | 108/108, Gate-2 exactly matching the CI baseline |
| CI | 7/7 green |

Coverage was **added** for every property this train established, not merely repaired: the maturity
conjunction (with a control case that makes each hold attributable), the backward-schedule guard and
its two-step bypass, the signing gate's zero-key refusal with no order created and the hold untouched,
dual-control parking, and the pricing type traps.

---

## ADVERSARIAL REVIEW

**P0 — 3 found, 3 fixed.**

1. **The maturity anchor was seller-mutable.** `catalog.update_event_session` guarded only *forward*
   moves, so a seller organization could backdate a session 400 days and release its own payout for an
   event that had not happened, reaching only an org-class approver with no platform human involved.
   This overturned the maturity analysis's claim that exposure was bounded to "hours, not months", and
   it defeated all eight predicates at once by attacking the anchor they share.
2. **The same primitive terminal-ized live tickets** — three active atoms swept to `expired`.
3. **A buyer could be charged for a ticket that could never exist.** The signing-key requirement lived
   in `finalize_primary_order`, after the PaymentIntent. Now a checkout precondition, verified to
   create no order and leave the hold untouched.

**P1 — 6 found, 6 addressed.** `fee.%` outside dual control; the interval type trap; four assembler
gate bypasses; `formatMinor(50)` → `"$0.50"` and the unchecked `asCents`; caller-supplied
`signing_key_id`; a KMS handle logged verbatim on parked provisioning calls (bounded, procedurally
closed in the runbook).

**Claims overturned — including three of this train's own and one of mine.**

- The maturity report's "hours, not months" bound. **Wrong** — unbounded.
- The expiry report's conclusion that the previous train was wrong about undeletable buyers.
  **Wrong** — BP-12 uses the payment clock, so the previous report was right on substance.
- The expiry report's "an `ends_at`-only move is unguarded". **Too strong** — that form is refused by
  `event_session_time_check`; only the paired backward move works. The fix targets the paired move
  precisely because of this correction.
- The first assembler gate's claim that it could not be satisfied by deletion. **Four bypasses.**

**What held under attack:** the eight predicates individually; the `payout.%` rename genuinely parking;
ruling A4 throughout; `release_payout` as the sole hold exit; refund/chargeback shared headroom; the
exact-once webhook uniques; the Connect two-key property (disjoint grants *and* runtime refusal);
money darkness; the signing review's four prevented claims; and the no-float and resale-unchanged
differentials.

---

## PRODUCTION CHANGES

**NONE.**

Verified at entry and exit: the production ledger holds the same 107 rows, ending at
`092_notify_reduced` plus the five timestamped website migrations, with **no `093`**. No migration
applied, no edge deployed, no flag flipped, no schema exposed, no config value set, no KMS material
created, no Stripe object touched, no secret rotated, no mobile build published.

---

## OWNER ACTIONS REQUIRED NEXT

1. **Schedule and run the two-person KMS signing ceremony** (ruling G3,
   `PRODUCTION_SIGNING_KMS_CEREMONY.md`). It is the critical path: every other blocker is resolvable by
   configuration and this one is not. Nothing can mint a ticket in any environment until it is done,
   and checkout now refuses at quote time because of it. Requires two named people and a window.
2. **Rule G2 — payout maturity.** Adopt the anchor and the eight-predicate conjunction, and set
   `payout.settlement_maturity_interval` to 7 days. Note this now requires **two** platform
   administrators, and that setting it is the act that releases money.
3. **Rule G1 — ticket expiry.** Set `ticket.expiry_grace` to the jsonb string `"72 hours"`. Do **not**
   set `deletion.refund_possible_window_hours` — its clock is anchored to payment, not the event, and
   needs re-anchoring first.

---

## RECOMMENDED NEXT TRAIN

**Two candidates, and they are not equally urgent.**

The higher-value one is **the refund executor completion + payout executor derivation train**: deploy
the built refund executor, author `kernel.list_pending_refunds`, resolve PFA-23's unimplementable
direct arm, and settle the `source_transaction` cardinality question on paper before any payout
executor is written. That is what stands between "the ledger is honest" and "money can actually move
correctly in both directions", and ruling A9 makes refund executability a hard precondition of selling.

The parallel-safe one is **Product V2 Tier-1**, which this train unblocked. It needs no backend
activation and can proceed against the now-stable contracts, provided it treats `service-fee-unset`
and `no_active_signing_key` as first-class states.

If only one train runs, run the refunds one. A UI in front of a rail that cannot refund is the same
mistake in a nicer typeface.
