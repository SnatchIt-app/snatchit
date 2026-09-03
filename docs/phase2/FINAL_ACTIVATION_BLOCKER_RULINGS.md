# Final activation blocker rulings

**Status: DRAFT. NOT APPROVED. NOT SIGNED.** **Five** decisions now stand between the current
implementation and a first venue-direct ticket sale. Each carries approval text written so the owner
can adopt it verbatim. **None of the five is approved.** Nothing in this document has been acted on
beyond the fail-closed defaults already in migration 093.

G1–G3 were raised by the activation-blocker train (2026-09-02). **G4 and G5 were added 2026-09-03 by
the refund/payout backend train**, and neither is an implementation detail: G4 is what a promoter is
owed when the sale they drove is reversed, and G5 is whether the platform accepts an uncollectable
post-payout loss or builds a receivable first. G1's and G2's recommendations are unchanged, but both
carry corrected evidence from that train — including two corrections to this document's own earlier
claims.

**Production is untouched.** Ledger verified at 107 rows ending at `092_notify_reduced`; no `093`.

**Evidence.** `docs/phase2/_impl/G1_expiry_semantics.md`, `G2_settlement_maturity.md`,
`G3_signing_rehearsal.md`, `G7_adversarial_review.md`, and the runbook
`docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md`. Every claim below was executed against a local
replay of the migration chain: **110 files** at entry (000–095, the state this document's G1–G3
evidence was gathered against) and **114** once 096–099 (this train's obligation-recovery,
cross-venue ring-fence, promoter pro-rata funding, and signing-monitor migrations) land — not
reasoned from documents.

---

# RULING G1 — TICKET EXPIRY

## CURRENT STATE

`ticket.expiry_grace` ships in migration 093 seeded `'null'::jsonb`. The sweep
`kernel.sweep_expired_ticket_atoms` (`079:456`) reads it, and with no value returns
`{swept_count: 0}` — no atom is ever expired.

## EVIDENCE

**What `expired` actually means, measured across fifteen dimensions.** It enforces exactly **one**
thing that is live today: **the door refuses the credential** (`kernel.mark_ticket_scanned`
`079:433-437` → `venue.record_scan` writes `result='invalid'`, `086:1088-1097`). It additionally
*enables* the BP-1 deletion blocker to clear (`079:706-717`), *breaks* cancellation refunds
(`catalog.cancel_event` excludes expired atoms — `088:1682/1735/1783`), and *degrades* chargeback
overlay handling (`088:823-833` mislabels an expired atom `overlay_occupied`).

It does **not** affect: app visibility (RLS is `current_owner_id = auth.uid()`, state-independent),
attendee history (expiry writes no ownership-log row), settlement, or promoter commission (both key
on `state <> 'voided'`). Transfer and resale are technically affected but moot — `is_transfer_frozen`
is already true from doors, before `ends_at`.

**A CORRECTION, AND THEN A CORRECTION TO THE CORRECTION — both are load-bearing, so both are
recorded.**

The previous implementation report said that leaving this key unset makes a paying no-show buyer
permanently undeletable. Research initially judged that wrong, on the ground that
`kernel.deletion_blockers_money` BP-12 arm 2 (`085:262-283`) is a second, order-anchored, fail-closed
gate keyed on `deletion.refund_possible_window_hours`. That much is true and verified: setting
`ticket.expiry_grace` alone unblocks nobody who paid, so the population *this* key frees is comp,
guest-list and imported holders.

**But adversarial review then overturned the conclusion drawn from it, and the previous report was
right on substance.** BP-12 arm 2 measures its window from `venue."order".created_at` — the *payment*
clock, which ruling G2 below spends its entire analysis proving is the wrong anchor for anything
event-shaped. Executed: a buyer who paid 60 days ago for an event 10 days away is blocked while the
key is unset, and becomes fully erasable the moment the key is set to a payment-anchored window — all
five deletion arms clear and the sweep tombstones them **before the event happens**, while G2's gate is
simultaneously holding the venue's money for precisely that risk.

Two consequences, and they pull apart:

1. `ticket.expiry_grace` genuinely does not have to carry money safety, so it does not have to be
   long. It can be set on admissibility grounds alone. **That part stands.**
2. `deletion.refund_possible_window_hours` is **not** a safe companion value and no duration is
   recommended for it in this document. Its clock is anchored to payment, not to the event, which is
   the same defect G2 exists to fix. Setting it without re-anchoring buys irreversible erasure of a
   buyer whose event has not occurred.

**The derivation is forced.** `ends_at + grace` is the only expressible candidate. `catalog.event`
carries no time column at all (`078:134-158`); there is no per-atom TTL column; no `admission_until`
exists; door-close is per-manifest and nullable, and no manifest has ever existed. Every column is
`timestamptz`, so the arithmetic is timezone-free.

**A type trap worse than previously documented — now closed in code.**
`('24'::jsonb #>> '{}')::interval` evaluates to **`00:00:24` — twenty-four seconds.** A bare number
does *not* fail the cast; it silently becomes a near-instant sweep that would terminal-ize every atom
on every ended session within two minutes. Verified.

The root cause is that the type witness at `078:1111-1114` is **skipped when the current value is JSON
null**, and every owner-STOP key in 093 is null-seeded — so each accepts any JSON type on its first
write, which is exactly the write the owner is about to make.

Migration 093 now refuses a bare number for interval-typed keys at the setter, so this is no longer
guarded only by the approval text below. Verified: `24` is refused with a message naming the correct
form, `"not an interval"` is refused as unparseable, `"24 hours"` is accepted, and a number on a
non-interval key is unaffected. One honest limitation carried in the code comment: the guard uses an
explicit key list and must gain future interval keys — the root cause is the missing witness on a null
seed, not the list.

## OPTIONS

| | Option | Consequence |
|---|---|---|
| 1 | Leave unset | No ticket ever expires. The door still refuses on other grounds only after a manifest exists. Comp/guest holders stay undeletable. Safe but permanently incomplete. |
| 2 | `"24 hours"` | Matches the ratified `door.session_absolute_max_interval` floor exactly. Leaves no margin for late door operation or offline reconciliation. |
| 3 | **`"72 hours"`** | Above the 24h door floor; equals the corpus's own ratified human-reaction constant `authn.money_role_maturity_hours = 72` (`078:1560`); crosses a full business day for any weekday. |
| 4 | Longer (7d+) | Extends erasure exposure for no admissibility benefit, since the door bound is 24h. |

## RECOMMENDATION

**Option 3 — `'"72 hours"'::jsonb`.**

## EXACT VALUE / DERIVATION

```sql
select catalog.set_platform_config(
  'ticket.expiry_grace',
  '"72 hours"'::jsonb,          -- a jsonb STRING. A NUMBER means SECONDS.
  '<reason code>', '<command key>');
```

Floor of 24h forced by `door.session_absolute_max_interval` (`078:1540`) — the architecture's own
outer bound on post-show door activity. 72h chosen above it because it is the corpus's existing
ratified constant for "a human needs to react", and because 24h and 48h do not cross a full business
day for a Friday or Saturday event, which is when nightlife volume actually is.

## FAILURE BEHAVIOR

- **Unset:** sweep inert. No expiry. Fail-safe for credentials, incomplete for deletion of
  non-purchasing holders.
- **Set as a number:** **refused at the setter since 093** (`093_parts/40:1248`), with a message naming
  the correct form. It was previously silent and became seconds. The approval text below still pins
  the type, but that is now belt to the code's braces rather than the only defence. As of 2026-09-03
  `ticket.%` is also dual-controlled, so a well-typed wrong value needs a second administrator — and
  the two guards compose in the right order: a bare number is rejected outright and never reaches the
  approval queue, so no one can be asked to rubber-stamp `'24'`.
- **Set too short:** live tickets terminal-ized, and `cancel_event` then excludes them from refunds —
  the holder loses ticket *and* money. Irreversible in practice: no shipped function writes `state`
  back.
- **Event postponed after expiry:** verified — moving `ends_at` +5 days returns `swept_count: 0` and
  atoms stay expired.
- **`ends_at` moved earlier:** verified — expires live atoms on the next tick with no guard and no
  reason code.
- **`ends_at IS NULL` or `state='issued'`:** never expire; configuration cannot reach either.

## OWNER APPROVAL TEXT

> **G1 — TICKET EXPIRY**
>
> `ticket.expiry_grace` is set to the jsonb string `"72 hours"`. It must be a JSON string spelled in
> hours; a JSON number is interpreted as seconds and is forbidden.
>
> Terminal ticket expiry derives from `catalog.event_session.ends_at` plus that grace. No other
> derivation is adopted, and no per-atom TTL is introduced.
>
> It is recorded that this key governs **door admissibility only**. It is not the money-safety clock:
> `deletion.post_event_hold_hours` (BP-12) independently blocks deletion for any identity with
> paid orders, and that key remains a separate owner decision.
>
> Two defects are acknowledged as accepted risk at launch rather than closed by this ruling: an
> `ends_at` moved earlier expires live atoms with no guard, and a postponement after expiry does not
> reinstate them. Both require a code change, not a configuration value.

## OWNER DIRECTION RECEIVED 2026-09-03 (unsigned)

Owner direction for this train: `ticket.expiry_grace` = **`"72 hours"`** — confirming this ruling's
own Option 3 / recommendation above. This is direction, not a signature; the approval text above and
the signature block below still read PENDING OWNER SIGNATURE. Nothing in migrations 096–099 touches
this key or the sweep; what already exists at 093 (the setter-level interval-type guard that refuses a
bare number for interval keys, and `ticket.%` dual control) is what this direction would execute
against once signed. No new mechanism was built for G1 this train.

---

# RULING G2 — SETTLEMENT / REFUND MATURITY

## CURRENT STATE

**A defect found and fixed during this train.** The payout hold was decided by a single test:

```sql
v_held := v_refund_window is null;
```

So the only predicate was "has the owner set the config key". Setting any value released the venue's
money immediately, even though **no event-based maturity semantics existed**. That made an owner
configuration value a hidden feature flag for payout logic that had not been written. It is now an
eight-predicate conjunction, described below.

**The key was misnamed and has been renamed.** `settlement.refund_window_interval` described refund
*eligibility* — a genuinely different concept that already has its own keys
(`refund.buyer_self_service_window_hours`, `refund.request_ttl_hours`, `refund.scanned_atom_policy`).
The value actually controls a payout hold measured from the event's end. It is now
**`payout.settlement_maturity_interval`**. The prefix is load-bearing: `payout.%` matches the
dual-control test at `078:1145-1147`, so setting it parks for a second `platform_admin`. Under the
old `settlement.` prefix it matched nothing and was a single unilateral write — for the one key where
*setting* the value is the dangerous act.

## WINDOW START

**`max(catalog.event_session.ends_at)` over the settlement's own money lines.**

Not payment time, not settlement close, not `period_end`. The schema forces it: `catalog.event`
carries no time column, so "event ended" must reduce to sessions; `venue."order".event_session_id` is
`NOT NULL` (`082:369-372`), so every covered order resolves to exactly one session; and deriving from
the settlement's *lines* rather than its header makes the anchor computable for period-scoped and
event-scoped settlements alike. `period_end` is unusable — nullable, and the seams bound `starts_at`
against it rather than `ends_at`.

Decisive test, executed: an order bought 90 days before an event 60 days out is **HELD**, with
`matures_at` = event end + interval. A venue does not become payable because a fan bought early.

Stripe's own model agrees on the clock: *"when a customer pays for a future event or service (like …
event ticket), the dispute window starts on the event date, not the payment date"*
(https://docs.stripe.com/disputes/how-disputes-work). **This is cited as corroboration of the
anchor only. Stripe's payout schedule is not Snatch It's settlement policy and the two must not be
conflated.**

## INTERVAL

**`'7 days'` — recommended, with the trade stated rather than hidden.**

No interval is fully safe, and the evidence does not support pretending otherwise. Full dispute
coverage would need roughly 120 days after the event, which is commercially impossible and exceeds
the 90-day non-US manual-payout limit. Stripe publishes no post-event hold figure; its only
ticketing-specific guidance is a reserve released the day after the event, which covers none of the
dispute tail. 7 days is strictly more conservative than Stripe's own guidance, sits inside both the
90-day and 180-day ceilings, and covers post-event refunds and executor latency. **The tail beyond it
requires a receivable object or Stripe fixed reserves — both separate owner items.**

## POSTPONEMENT

The anchor moves with `ends_at`, so a postponement automatically extends the hold.

**A P0 was found here by adversarial review and is fixed in this train.** The maturity analysis
originally judged this a bounded residual — "the most a seller can shave is the session's own
duration, hours not months." **That was wrong.** `catalog.update_event_session`'s time guard tests
only FORWARD movement (`079:624-659`), so a seller organization could move `starts_at` and `ends_at`
backward together and release its own payout for an event that had not happened. Executed: a control
settlement held with `maturity_not_elapsed` and `request_org_payout` refused with `payout_held`; after
a 400-day backdate the identical settlement closed `hold_state='none'` with `payout_hold: null` and
the payout request reached an **org-class approver** with no platform human involved anywhere.
Unbounded, one RPC, and it turns the whole eight-predicate gate into a no-op — every other predicate
held under attack, but they all depend on this anchor.

The same primitive terminal-izes live credentials: three active atoms on a session thirty days out
were swept to `expired` after a backdate. One correction to the expiry findings while recording this —
the claim that an `ends_at`-only move is unguarded is too strong; that form is refused by
`event_session_time_check`. **Only the paired backward move works**, and that is what the fix targets.

Migration 093 now guards backward movement once a session carries economic weight, while leaving a
pre-sale draft event freely reschedulable in both directions.

**Re-verified 2026-09-03 and the residual is struck.** Independent execution as `org_owner` against a
full replay: a backward move of −65 days is refused; an `ends_at`-only move of −4 hours is refused;
a postponement of +30 days succeeds, which is the safe direction. The anchor is no longer mutable by
the party being paid.

**The anchor and interval were attacked again and survive unchanged.** Every scenario in the brief was
executed — normal nightclub event, an event ending after midnight, one ending at 4–6 AM, a multi-day
festival, multiple sessions, postponement, cancellation, delayed close, a refund pending on day 7, a
dispute pending on day 7, the executor offline, a disconnected account, funded commission, and a
post-release chargeback. The 4–6 AM case, which looked like the most likely source of an off-by-one-day
error, **does not matter**: the gate is pure instant arithmetic on `timestamptz`, with no `date_trunc`,
no `AT TIME ZONE` and no `::date` anywhere. It would only matter if the policy were ever re-expressed
as a calendar day, and the recommendation is that it never is.

## CANCELLATION

A covered event or session in `cancelled` state holds the payout with `event_cancelled`. Cancellation
inserts pending refunds for every order (`088:1664/1716/1774`), which independently trips
`refund_in_flight`.

## REFUND

Any non-terminal refund (`pending`, `submitted`) on a covered payment holds the payout with
`refund_in_flight`. The settlement seam separately defers an order with a non-terminal refund out of
the ledger entirely, so the obligation is neither overstated nor understated while money is in doubt.

## DISPUTE

An open dispute on a covered payment holds the payout with `dispute_open`.

## CHARGEBACK

A chargeback filed **after** release lands in the organization's next settlement
(`088:311-316`). **This is not closed by this ruling and cannot be, without a receivable object.** It
is the known tail.

## RECOMMENDATION

Adopt the anchor and the conjunction. Set the interval to 7 days. Accept the chargeback tail as a
named residual with a follow-up for a receivable object.

## OWNER APPROVAL TEXT

> **G2 — SETTLEMENT / PAYOUT MATURITY**
>
> The key `settlement.refund_window_interval` is renamed `payout.settlement_maturity_interval`,
> because it governs payout maturity and not refund eligibility. It inherits `payout.%` dual control:
> setting it requires two platform administrators.
>
> Payout maturity is measured from `max(catalog.event_session.ends_at)` across the money lines the
> settlement actually covers, plus the configured interval, which is set to **7 days**.
>
> A settlement payout is minted HELD unless every one of these holds: the maturity policy is set and
> non-negative; the covered set resolves; no covered event or session is cancelled; the maturity
> anchor is known; the interval has elapsed; no non-terminal refund exists on a covered payment; and
> no dispute is open on a covered payment. Any predicate that cannot be computed holds the payout. No
> single predicate may release money on its own.
>
> `kernel.release_payout` remains the only contracted exit and stays restricted to platform roles.
>
> It is recorded that a chargeback filed after release is not covered by this ruling and lands in the
> organization's next settlement; closing that tail requires a receivable object, which is a separate
> decision. It is also recorded that `catalog.update_event_session` does not guard an `ends_at`-only
> change, which is a code defect and not closed by this ruling.

## OWNER DIRECTION RECEIVED 2026-09-03 (unsigned)

Owner direction for this train: payout maturity = **`max(session.ends_at) + 7 days`**, with the
fail-closed conjunction — confirming this ruling's own anchor and interval recommendation. **The
conjunction is now nine predicates, not eight.** Migration 097 (this train) adds a ninth,
`dispute_unabsorbed`, alongside the eight this ruling's approval text already lists (maturity policy
set and non-negative; covered set resolves; no covered event/session cancelled; maturity anchor known;
interval elapsed; no non-terminal refund on a covered payment; no open dispute on a covered payment;
any predicate that cannot be computed holds the payout). `dispute_unabsorbed` holds the payout while a
chargeback's ring-fenced recovery against the *originating venue* (G5 direction; migration 097) has not
yet been fully recovered — a mechanical extension of the same shape, not a new policy question: no
single predicate may release money on its own, which this ruling already establishes.

---

# RULING G3 — PRODUCTION SIGNING CEREMONY

## CURRENT STATE

No signing key exists in any environment. `kernel.signing_key.public_key` and `kms_handle_ref` are
`NOT NULL` with no defaults (`083:55-56`); `guard_signing_key_immutable` (`083:84-102`) blocks any
UPDATE of either, **including for a superuser**; `kernel.tickets.signing_key_id` is `NOT NULL` with
`ON DELETE RESTRICT` (`083:191`). `kernel.provision_signing_key` and `rotate_signing_key` remain
parked unconditional raises and are **not** un-parked.

**Therefore no ticket can be minted in any environment until this ceremony runs.** Migration 093
ships the fully-determined row as a commented template and inserts nothing.

**The implementation is provider-agnostic.** Nothing in code names a KMS; `kms_handle_ref` is bare
`text` with no CHECK and no regex, and **there is no insert-time validation at all** — Postgres
cannot distinguish a real key from a placeholder. Intent comes only from
`PHASE_2_EDGE_FUNCTION_SPEC.md`: asymmetric signer, Ed25519 preferred and ECDSA-P256 acceptable
(`:1273-4`); custody in AWS KMS asymmetric, GCP KMS, or CloudHSM (`:1291-2`); `global` scope
sanctioned only for a controlled bootstrap (`:1286-8`).

## CEREMONY MODEL

Two-person, KMS-backed, with the private key never leaving the KMS and never existing in the
repository, logs, fixtures, documentation, CI output or the database. Full runbook:
`docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md`. Rehearsed locally with non-production material,
**12 of 12 items passing**, including rotation preserving verification of previously issued tickets.

## PERSON A

Holds KMS `CreateKey` authority. Creates the asymmetric key, pins the key **version** in the handle,
extracts the public key as SPKI PEM, and computes the fingerprint as SHA-256 over the DER SPKI.
Person A never touches the production database.

## PERSON B

Holds the production database path. Independently recomputes the fingerprint from the public key
before any insert, and aborts if it differs from Person A's. Person B holds no `CreateKey` authority.
The ceremony aborts loudly on a stale fingerprint, on a private key appearing in any buffer, on a
placeholder handle, and on replay.

## IRREVERSIBLE POINT

**The first `issue_ticket_atoms` call — not the ceremony, and not the feature-flag flip.** Four doors
close simultaneously: the foreign key blocks deletion; the immutability guard blocks correcting
`public_key` or `kms_handle_ref` even for a superuser; every minted atom is pinned to that key forever
and rotation never re-pins; and nothing can prove the key honest after the fact. Before that call,
§10 of the runbook is a clean rollback.

## RECOMMENDATION

Approve the ceremony and schedule it. It is the critical path: **every other blocker in this document
can be resolved by configuration, and this one cannot.**

Three residuals are irreducible and are stated rather than papered over: Postgres cannot verify that a
key is real; nothing constrains a superuser; and there is no in-band revocation while PFA-18A is open.
The compensating control for all three is the standing monitor in runbook §9.3. One threat is worth
the owner's attention specifically: a `per_event` key silently outranks the `global` bootstrap key in
scope resolution (`085:1948-60`), so a second key registered at event scope takes over immediately and
without collision.

## OWNER APPROVAL TEXT

> **G3 — PRODUCTION SIGNING CEREMONY**
>
> The two-person KMS ceremony in `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` is approved for
> execution. Person A holds KMS key-creation authority and never touches the production database;
> Person B holds the database path and holds no key-creation authority; the fingerprint is
> independently recomputed by Person B and the ceremony aborts on any mismatch.
>
> The provider, algorithm and handle format are pinned by the runbook before execution. The handle
> must pin a key version, because an unversioned handle would let the signer change under an immutable
> public key.
>
> It is recorded that the point of no return is the first ticket mint, not the ceremony itself, and
> that after it the trusted signing identity cannot be corrected by anyone, including a superuser.
>
> It is recorded that a per-event signing key outranks the global bootstrap key in scope resolution,
> and that monitoring for an unexpected scoped key is a standing operational control.
>
> The database signing-key RPCs remain parked and are not un-parked by this ruling.

## OWNER DIRECTION RECEIVED 2026-09-03 (unsigned)

Owner direction for this train: the ceremony is **approved in principle** but **NOT executed this
train**. No KMS call, no production database write, nothing against `PRODUCTION_SIGNING_KMS_CEREMONY.md`
was run. What the train built against it: the standing monitor this ruling's recommendation already
calls the compensating control for all three irreducible residuals is no longer aspirational —
migration **099** (`099_signing_monitor_and_executor_invokers.sql`) ships it dark: function
`kernel.check_signing_key_invariants()`, config keys `signing.monitor_enabled` /
`signing.expected_key_fingerprint` / `signing.expected_max_not_after` (all owner-unset), cron job
`monitor-signing-key-invariants`, and alert egress via the `notify-report` edge's
`signing_invariant_alert` event. Arming it (pinning the fingerprint, flipping `signing.monitor_enabled`
to `true`) remains a separate `PRODUCTION CONFIG` / `OWNER APPROVAL REQUIRED` act, itself **NOT
executed** — see `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` §9.3 and
`docs/phase2/_impl/KJ_kms_runbook_monitor.md`.

---

# RULING G4 — FUNDED PROMOTER COMMISSION WHEN THE REVENUE IS REVERSED

## CURRENT STATE

Promoter commission is funded from primary-sale economics and reduces venue distributable before venue
money is released (ratified Option B). **Funded is not paid**, and nothing in the system has ever
released a commission hold — verified again this train across both economic chains, three refund
cycles, a chargeback, a cancellation, a re-close and an owner-level re-open: `count(*) from
kernel.payout where cause='promoter_commission' and hold_state <> 'held'` = **0**.

## THE PROBLEM

When the revenue that funded a commission is reversed **after the close that funded it**, there is no
mechanism to reduce the commission. Proved by execution, all four routes closed:

- the settlement line cannot be UPDATEd or DELETEd (append-only trigger),
- a compensating line is **unstorable** (the global partial unique index permits one line per cause
  reference, which is the protection against double-lining),
- the closed settlement header is write-once,
- `kernel.payout` has no reduce or void verb, and the schema has no carry-forward object.

Four ordinary shapes produce it: a post-close full refund, a post-close partial refund, a chargeback,
and an event cancellation. In the rehearsal, **3800 of 4800 minor units — 79% — across four of five
funded attributions stood against reversed revenue.**

## WHY IT IS CONTAINED, AND WHY THAT MATTERS

The exposure is bounded by a single fact: nobody has released a commission hold, which is exactly what
ruling A4 guarantees and what migration 093 was repeatedly verified not to break. So this is a decision
to be made deliberately, not an incident. **It becomes real the moment the first commission hold is
released**, which is why it belongs in the activation matrix rather than in a backlog.

## OPTIONS

| | Option | Consequence |
|---|---|---|
| A | Never release that attribution's hold | Simplest and already the de facto state. The promoter is not paid on reversed revenue, and also not paid on the surviving portion of a partly refunded order. |
| B | New `commission_reversal` cause plus a negative-obligation object | Correct accounting. Costs a new enum member on a frozen CHECK and DDL on a money ledger — a post-freeze amendment. |
| C | Promoter-level running balance | Option A applied at the promoter rather than the attribution; needs a new durable object. |
| D | Platform absorbs | Already rejected in the original Option B ratification; listed only so the record is complete. |

## RECOMMENDATION

**No recommendation is offered, deliberately.** This is a commercial relationship decision — what a
promoter is owed when the sale they drove is reversed — and the four options differ in what the
promoter is told, not merely in how the ledger is shaped. Migration 093 must not choose, and does not:
A4 holds everything in place while the question is open.

## OWNER APPROVAL TEXT

> **G4 — FUNDED COMMISSION ON REVERSED REVENUE**
>
> When primary revenue is reversed after the settlement close that funded a promoter commission, the
> policy is: ______________________________ (A / B / C).
>
> Until this is ruled, no promoter commission payout may be released, and `kernel.release_payout` must
> not be used on a `promoter_commission` payout for any reason. This constraint is recorded in the
> activation matrix as a precondition of promoter payout, not of venue payout or of selling.

## OWNER DIRECTION RECEIVED 2026-09-03 (unsigned)

Owner direction for this train: promoter commission stays **HELD at launch** — no release, no payout —
and reversed revenue does **not** automatically leave the full commission earned; the eventual
surviving-commission policy among options A/B/C above is to be decided **before the first release**,
not before this train. What the train built against it: migration **098** implements **pre-close
pro-rata FUNDING only** — disputes are included alongside refunds under the same face-value cap, using
the flat-per-ticket allocation rule, gated `PFA-PT-4 pending signature`. It does **not** release or pay
anything, and does **not** touch a post-close commission — the defect this ruling describes (funded
commission standing against reversed revenue after close) remains open. It also does not resolve the
finding that organization debt is overstated by the commission still held against reversed revenue
(`docs/phase2/_impl/KC_chargeback_accounting.md` §2.i; `docs/phase2/_impl/KF_promoter_prorata.md` P1-3)
— recorded as an addition to question (iii) in the G4 ruling itself. `kernel.release_payout` remains
unused on any `promoter_commission` payout.
See `docs/phase2/G4_PROMOTER_REVERSAL_RULING.md` for the fuller account of what 098 does and does not do.

---

# RULING G5 — POST-PAYOUT REFUND AND CHARGEBACK EXPOSURE

## CURRENT STATE

Once a venue has been paid, a later refund or lost dispute has no recovery mechanism. Executed this
train: an organization sold 23000, was paid 19000, was entitled to 13000 — **platform loss 6000.**

Of the six possible accounting outcomes, only **platform absorbs** is implemented. *Future payout
offset* exists accidentally: recovery works only if the organization's next settlement happens to
carry enough positive lines, and when it does it silently confiscates that later revenue while
destroying any excess. There is no receivable object, and `CHECK (amount_minor > 0)` on
`kernel.payout` makes one unrepresentable without DDL.

## WHY IT IS ACCEPTABLE TODAY, AND WHY THAT IS ABOUT TO CHANGE

It is tolerable right now for exactly one reason: **no payout executor exists**, so no venue can be
paid at all. No edge function calls `request_org_payout`, `mark_payout_transfer_state` or
`release_payout`, and no cron job does either.

**This train wrote the executor.** It is dark and undeployed, but the protection was the absence of the
thing that now exists. Two conditions were therefore identified as preconditions of ever *shipping* it,
distinct from writing it: the maturity re-evaluation fix (done this train — maturity is now an
invariant rather than a close-time snapshot) and a receivable or reserve object (**not done**).

## OPTIONS

| | Option | Consequence |
|---|---|---|
| 1 | Accept the exposure with explicit owner risk acceptance | Ships soonest. Bounded per settlement by the amount paid, unbounded in aggregate across settlements. |
| 2 | Build a receivable object before the executor ships | Correct, and needs DDL on a money ledger plus a policy for how a negative balance is collected. |
| 3 | Stripe fixed reserves on connected accounts | Moves the problem to Stripe; changes the venue relationship and needs its own onboarding decision. |
| 4 | Shorten the maturity interval | Reduces nothing meaningful — the dispute tail is ~120 days and no commercially viable hold covers it. |

## RECOMMENDATION

**Do not ship the payout executor on option 1 by default.** The honest framing is that option 1 is a
real business choice a launching marketplace may reasonably make, but it must be made explicitly and
with the number in front of the owner, because the loss lands entirely on the platform and is
discovered only after the money has gone.

## OWNER APPROVAL TEXT

> **G5 — POST-PAYOUT EXPOSURE**
>
> The venue payout executor may not be deployed until: ______________________________
> (1 accept with risk acceptance / 2 receivable object first / 3 Stripe reserves).
>
> It is recorded that only "platform absorbs" is implemented today, that "future payout offset" exists
> only accidentally and silently confiscates later venue revenue, and that no receivable object exists
> or is representable without DDL on a money ledger.

## OWNER DIRECTION RECEIVED 2026-09-03 (unsigned)

Owner direction for this train: the organization obligation is **the durable record of post-payout
debt** — recovery must eventually be deterministic and auditable, not accidental — and there is **no
default cross-venue netting**: Venue A's debt must not silently consume Venue B's payout inside the
same organization. The legal debtor may remain the organization; the recovery source may be
venue-scoped. What the train built against it: migration **096** adds immutable recovery facts
(`kernel.organization_obligation_recovery`: `source_kind` `transfer_reversal|manual`, Σ(recovered) ≤
`amount`, `status='recovered'` derived only when Σ=amount, `written_off` explicit, `resolve('recovered')`
refused without receipts). Migration **097** ring-fences the chargeback recovery arm to the
*originating venue* — no default cross-venue netting — and fences the unlined origin to post-payout
ledger-derived amounts. Neither migration builds the receivable object Option 2 above describes, and
neither releases or changes today's answer to this ruling's own question — the venue payout executor
still may not be deployed until this ruling is signed. Full account, including the remaining open
questions, appended to `docs/phase2/G5_POST_PAYOUT_EXPOSURE_RULING.md`.

---

# GATE-M RE-ATTESTATION

## CURRENT STATE

Gate-M is not a ruling raised by this train; it is a pre-existing architectural gate covering three
frozen constructs the Phase 2 corpus deliberately did not build: **C29** (a Reserve/Clawback object
plus a payout-timing policy — `docs/architecture/_governance/CTO_DECISION_MEMO.md:56`), **C30** (a
fan-side chargeback/clawback liability object — `:57`), and **C31** (an additive double-entry
money-ledger schema, the intended home for C29/C30 and the fix for the unbalanced royalty/rounding
residual — `:58`). All three were ratified **MODELED-ONLY at Gate-M**
(`docs/architecture/_governance/PHASE_2_RATIFICATION_RECORD.md`), not built, and
`docs/architecture/PHASE_2_MONEY_AUTHORITY_SPEC.md:67` states the premise under which that was
acceptable:

> "Gate M (C29 reserve / C31 double-entry) not required — CONFIRMED. Nothing here needs a reserve, a
> clawback, or instant payout. MVP payout stays settlement-cadenced."

**That premise was written when no venue could be paid at all.** `docs/architecture/PHASE_2_PHYSICAL_POSTGRES_SCHEMA_SPEC.md:1186`
assigns org-side negative-settlement carry to exactly this gate ("C31, Gate-M"), and migration 094
(`kernel.organization_obligation`) is what records that carry. This train's 096/097 give it its first
recovery mechanism and its cross-venue ring-fence (see the G5 note above), on top of a payout executor
that is now code-complete, dark and undeployed. `docs/phase2/PRIMARY_TICKETING_ACTIVATION_MATRIX.md:279`
(row 0a′) and `:367,:369` both name **re-attestation — not obedience, not override** — as the
precondition of **applying migration 094** and of **any venue payout activation**, because the
premise's own condition ("no venue could be paid at all") is precisely what is about to stop being
true. Owner direction for this train re-affirms Gate-M as **REQUIRED** for venue payout activation and
records that it is **NOT** activated in production.

## WHY RE-ATTESTATION, NOT A NEW RULING

Gate-M was already ratified — MODELED-ONLY — by the frozen corpus; reopening it as a fresh ruling would
relitigate a frozen decision outside the post-freeze amendment procedure. What is missing is narrower: a
dated owner statement of whether the "not required" premise still holds now that a dark payout executor
and a dark organization-obligation object exist, or a statement that it does not — in which case C29/C30/C31
move from MODELED-ONLY to a scheduled build.

## OWNER ATTESTATION TEXT

> **GATE-M RE-ATTESTATION**
>
> I have read `PHASE_2_MONEY_AUTHORITY_SPEC.md:67`'s premise — *"Gate M (C29 reserve / C31 double-entry)
> not required … because payout is settlement-cadenced"* — and for each of C29, C30, and C31 I attest
> whether it still holds, given that a payout executor (dark) and `kernel.organization_obligation` (094,
> dark) now exist where neither did when §67 was written:
>
> **C29 (Reserve/Clawback object + payout-timing policy):** ______ still not required / now required,
> because: ______________________________
>
> **C30 (fan-side chargeback/clawback liability object):** ______ still not required / now required,
> because: ______________________________
>
> **C31 (double-entry money-ledger schema):** ______ still not required / now required, because:
> ______________________________
>
> This attestation is **required before applying migration 094** and **before any venue payout
> activation** (deploying `payout-execute` or arming its invoker) — it is not required for, and is not
> satisfied by, this train's dark migrations 096–099 landing in the repository.
>
> It is recorded that migrations 096 and 097 (this train) give the organization-obligation object a
> recovery mechanism and a cross-venue ring-fence **without building C29, C30, or C31** — they operate
> entirely within the existing "platform absorbs, then recovers deterministically from the originating
> venue" posture ruling G5 already describes, not the reserve, fan-liability, or double-entry shapes
> Gate-M gates. If that reading is incorrect, this attestation is where the owner says so.

---

# Signature block

**This document is NOT approved. No ruling below is in force.** G4 and G5 were added
2026-09-03 by the refund/payout backend train; G1 and G2 carry corrected evidence from the same
train and their recommendations are unchanged.

| Ruling | Subject | Status |
|---|---|---|
| G1 | Ticket expiry | PENDING OWNER SIGNATURE |
| G2 | Settlement / payout maturity | PENDING OWNER SIGNATURE |
| G3 | Production signing ceremony | PENDING OWNER SIGNATURE |
| G4 | Funded commission on reversed revenue | PENDING OWNER SIGNATURE |
| G5 | Post-payout refund / chargeback exposure | PENDING OWNER SIGNATURE |
| Gate-M | Re-attestation (C29/C30/C31) | PENDING OWNER ATTESTATION |

Owner signature: _______________________  Date: _______________

G1 and G2 additionally require the owner to supply a value, not only a signature. G3 requires two
named people and a scheduled window. Gate-M requires a per-construct attestation (C29/C30/C31), not a
single signature — see the GATE-M RE-ATTESTATION section above.

**A fourth value, surfaced this train and deliberately NOT given a recommendation.**
`deletion.post_event_hold_hours` (`093:5851`; the older name `deletion.refund_possible_window_hours`
at `085:2189` is now an unread orphan — see `docs/phase2/_impl/KI_activation_sequencing.md` P2-3) is
seeded null and fail-closed, and independently blocks account deletion for any identity holding paid
orders. It must be set before deletion works for purchasing buyers — but **it must not simply be set**,
because its window is measured from `venue."order".created_at`. That is the payment clock, and ruling
G2 establishes that the payment clock is the wrong anchor for anything event-shaped. Setting it as it
stands lets a buyer who paid early be tombstoned irreversibly before their event, while G2's gate holds
the venue's money for the same risk. Re-anchoring it to the event is a code change and a separate owner
decision; this document recommends no duration for it.
