# RT-B — ADVERSARIAL RED TEAM, MONEY SLICE (093 / settlement / refund / webhook)

Date: 2026-09-02 · Scope: `supabase/migrations/093_primary_ticketing.sql` (assembled),
`docs/phase2/_impl/093_parts/10_money_settlement.sql`, `supabase/functions/refund-execute/`,
`supabase/functions/stripe-webhook/index.ts` + `native.ts`.

Method: full 093 replay on a private local rehearsal DB (`snatchit_rehearsal_redteam_b`,
`scripts/rehearsal_reset.sh` — the script's own guard rejects a name without `rehears`, so the
mandated `snatchit_redteam_b` was widened to `snatchit_rehearsal_redteam_b`; no other agent's DB
was touched). GATE-2 matched the CI baseline exactly (tables=27 functions=70 policies=37
triggers=24). Every finding below is an **executed** reproduction, not an argument. No repo file
other than this report was modified; nothing ran against a remote; Stripe was never called.

Fixture: `rt.seed()` builds org1(seller=owner, other_user=org_finance)/venue1/event1/session1 and
org2(other_user=owner)/venue2/event2/session2 through the real RPCs. `rt.paid_order()` writes the
exact triple `venue.finalize_primary_order` leaves behind (`venue."order".status='paid'` +
`public.payments` + `kernel.payment_native`).

---

## THE INVARIANT, SCORED

    BUYER PAYMENT  ≠  VENUE OBLIGATION  ≠  PAYOUT EXECUTION

* **"A successful payment must produce enough durable accounting state"** — HOLDS. Proven at
  §H1/§H7.
* **"Payout failure must NOT erase the venue obligation"** — HOLDS for payout execution
  (§H7), FAILS for *refund* execution (§P1-3).
* **"Stripe history must NOT be the sole source of truth for what a venue is owed"** —
  **VIOLATED.** §P0-1 case (b): after a full refund the settlement ledger says the venue is owed
  the full face value, forever, and the only record that the money came back lives in
  `kernel.refund` + Stripe. The venue ledger is never corrected.

---

# P0 FINDINGS

## P0-1 — A refund that succeeds after its settlement closed is never collected. The venue is overpaid and the ledger is wrong either way.

**PROVED.** Reproduction (`/tmp/rt_p0.sql`, one order, face $100.00):

```sql
select rt.paid_order(rt.g('sess1'), rt.g('org1'), 10000, 1000, 'p0');   -- face 10000, buyer fee 1000
select rt.put('S1', rt.open1('p0-s1', rt.g('event1'))::text);
select rt.close1(rt.g('S1'),'p0-c1');
--> {"status":"ok","net_minor":10000,"payout_ids":["2fcfab28-…"]}       -- venue PAID 10000

-- buyer refunds in full AFTER the close; money leaves Stripe
insert into kernel.refund (payment_id,reason_code,amount_minor,idempotency_key,status,stripe_refund_ref)
 values (rt.g('pay'),'buyer_request',10000,'p0-r','succeeded','re_p0');
update venue."order" set status='refunded' where command_idempotency_key='p0';
```

**Case (b) — nobody opens another settlement for that event (the normal case once an event is over):**

```
venue.settlement_line refund_void rows          : 0
org1 owed per the DATABASE (Σ closed net_minor) : 10000
org1 PAID per kernel.payout                     : 10000
TRUE economics (10000 face − 10000 refund)      : 0
```

The `refund_void` debit exists **nowhere in the venue ledger**. The database's own answer to
"what is this venue owed" is off by the full refund, permanently.

**Case (a) — an operator does open a second settlement for the same event:**

```
CLOSE 2 -> {"status":"ok","net_minor":-10000,"payout_ids":[]}
S2 lines: refund_void -10000
org1 owed per the DATABASE (Σ closed net) = 0
org1 PAID per kernel.payout               = 10000
payouts minted for the NEGATIVE settlement: 0
```

The debit lands, but a negative net mints **no payout, no receivable, no clawback object, and no
carry-forward** — `kernel.close_settlement` derives net from the lines of *this* settlement only.
The 10000 already left. Longer sequence (`/tmp/…/c_a4.sql` §C2), five closes of nets
`10000, −4000, 0, −6600, 9000`:

```
org lifetime net across all closed settlements = 8400
TOTAL PAID OUT to org1 (kernel.payout)         = 19000
```

**Why this is 093's problem, not 087's.** The 10b header names this residual ("an order already
lined in a CLOSED settlement whose refund succeeds afterwards … for an event-scoped settlement
there may be no next one") and dismisses it as "the identical shape as the shipped chargeback
arm." It is not identical any more. Before 093 there was **no credit seam**, so gross was
structurally zero and no org payout was ever minted — the shape was inert. 093 mints the payout
at close. The residual becomes real money out the door on the first refund that arrives after a
close, which for an event-scoped settlement is the *expected* arrival order (events settle, then
buyers complain).

**Rank P0** — money lost, and the durable accounting state that ruling A2 exists to protect is
wrong by the refund amount.

## P0-2 — `refund_void` and `chargeback` both debit the same money; the chargeback debit also carries the buyer-side service fee (ruling A5 violation on the debit side). A venue is underpaid in a single close.

**PROVED.** `kernel.dispute_native.status = 'charge_refunded'` is Stripe's canonical outcome for
"the merchant refunded the disputed charge" — it is in the CHECK set (088:201), it is written by
`kernel.record_dispute_native` / `kernel.mark_dispute_state` from the live
`charge.dispute.created` / `charge.dispute.closed` webhook branches
(`stripe-webhook/index.ts:951,:1048`). Nothing reconciles it against `kernel.refund`.

Reproduction (`/tmp/rt_cb.sql`) — order A clean at face 10000, order B face 6000 fully refunded,
one dispute row closed as `charge_refunded` at 6600 (= face + buyer fee, which is what Stripe
disputes):

```
lines : chargeback -6600, primary_sale 10000, primary_sale 6000, refund_void -6000
header: gross=16000 refunds=12600 net=3400
PAYOUT: 3400          TRUTH: 10000
```

The venue is short **6600** on one settlement: the 6000 refund is debited twice, and the extra
600 is the platform's own buyer-funded service fee being subtracted from the venue's face-value
entitlement — the exact thing ruling A5 forbids ("processing cost / platform economics is not
silently subtracted from venue face-value entitlement"). 10b caps `refund_void` at face for
precisely this reason; the shipped `chargeback` arm (088:352-359) has no cap and no
refund awareness, and 093 is what gives it a credit to eat.

`venue.settlement_line` is append-only, so both lines are wrong forever.

**Rank P0** — money misdirected (venue underpaid), and unrepairable in an append-only ledger.

---

# P1 FINDINGS

## P1-1 — `gross_minor::integer` overflow makes a large settlement permanently unclosable.

**PROVED.** `venue.settlement.{gross,fees,refunds,net}_minor` are `integer`; `close_settlement`
accumulates into `bigint` locals and then casts (`gross_minor=v_gross::integer`, 093:580-581).
Two orders of 2,000,000,000 minor in one event-scoped settlement:

```
F1 close  -> ERR 22003 integer out of range
F1 header -> status=open  lines=0
F1 RETRY  -> ERR 22003 integer out of range
```

The close aborts atomically (correct), writes nothing, and **every retry fails identically**.
$21,474,836 of gross in one settlement window is reachable for a festival or a month-long
period-scoped header. There is no split path and no partial close: the header is terminally
stuck, and 10c's global index means the orders cannot be moved to a smaller settlement without a
settlement that will also overflow. Fix is a column widening (`bigint`), which is DDL 093
deliberately excludes — so it must be a separate, ratified migration before activation.

**Rank P1** — settlement denial, not theft, but it is a hard stop at a size the platform is
building for.

## P1-2 — 10f closed the E-76 leak on `venue.settlement` / `venue.settlement_line` and left it open one table over, on `venue."order"`.

**PROVED.** After a room's operatorship diverges from an event's org (the exact state 10a is
built to survive), the room's stale `venue_finance`:

```
AFTER transfer: venue.settlement rows visible      = 0   (10f works)
AFTER transfer: venue.settlement_line rows visible = 0   (10f works)
AFTER transfer: venue."order" rows visible         = 1   (LEAK)
```

`venue_order_sel_venue` (082) calls `kernel.has_venue_role` bare, with no current-operator
conjunct. 093 states at :3012 that it ships no policy change for `venue."order"`. But 10f's own
threat model — "a ROOM's venue_manager or venue_finance would read the PROMOTER's complete money
picture" — is satisfied *better* through `venue."order"`, which exposes per-order `total_minor`,
`status`, `org_id` **and `buyer_id`** (PII the settlement tables do not carry). 10a is what makes
the divergent state routine, so 093 is what makes this leak reachable.

**Rank P1** — cross-org money + buyer-identity disclosure, created by this migration's own
widening.

## P1-3 — A non-terminal refund defers the venue's whole obligation with no bound, no alarm, and no executor in production.

**PROVED.**

```
B6: order face 7000 + one 'pending' refund  -> close net=0, ledger "(no lines)"
B7: second close, refund still pending      -> net=0, ledger "(no lines)"
B8: refund flips to 'failed'                -> net=7000, primary_sale 7000 appears
```

10b's rule (ii) is right in isolation. Its operational exposure is not:

* `refund-execute` is the **only** caller of `kernel.mark_refund_state` (executor.ts header;
  `kernel.refund` rows are born `pending` at 085:599/706 and 088:1664/1721/1779).
* `kernel.list_pending_refunds` **does not exist** — confirmed on the replayed DB
  (`count = 0`) — so the executor's sweep mode returns 501 (`index.ts:496`). 10g's own header
  says so. There is therefore **no deployed mechanism that moves a refund out of `pending`.**
* `catalog.cancel_event` inserts a pending refund for *every* order of the event, so one
  cancellation zeroes that event's entire venue ledger until each refund is individually resolved.

Net effect: today, on activation, any refunded order's face value is invisible to the venue
ledger indefinitely. The design's required property ("accumulate correct venue payable facts
while payout execution is entirely unavailable") holds; the symmetric property for **refund**
execution does not.

**Rank P1** — must be fixed (or `list_pending_refunds` ratified and deployed) before activation.

---

# P2 FINDINGS

## P2-1 — `chargeback` and `market_sale` have no global uniqueness; only `primary_sale`, `refund_void` and `promoter_commission` do.

10c's own rationale ("the E-104 advisory lock orders concurrent closes; only the index survives a
crash, a second cluster or a hand-written INSERT") applies verbatim to the two 088 causes, which
are protected by nothing but the lock and a `NOT EXISTS`. Verified on the replayed DB — the only
partial unique indexes on `venue.settlement_line` are
`settlement_one_primary_sale_line_ever`, `settlement_one_refund_void_line_ever`,
`attribution_one_commission_line_ever`. Given P0-2, the chargeback cause is the one that most
needs it.

## P2-2 — After a legacy operatorship divergence, the new room operator can open a period-scoped header for a room whose events belong to another org.

```
A2.3 org2 (new operator) PERIOD-scoped over the room -> {"status":"ok","settlement_id":"…"}
close  -> net=0, zero lines, zero payouts
```

Harmless economically (`scoped_order` binds `o.org_id = s.org_id`, so it sweeps nothing), but it
mints a permanent `settlement.open` audit row and a zero header attributable to a party with no
economic interest in that room's events. Record only.

---

# WHAT HELD (attacks attempted and defeated)

**1 · Settlement theft — NOT PROVED.** Every route refused, with the correct AUTHZ-C1C `P0002`:

| attempt | result |
|---|---|
| org2 creates an event at org1's venue1 (to reach the widened venue-existence check) | `ERR 42501 venue_manager or org_owner/org_admin required` |
| org2 opens event-scoped `(org2, venue1, event1)` | `ERR P0002 not_found: event … for venue … / org …` |
| org1 opens event-scoped `(org1, venue2, event1)` — venue/event mismatch | `ERR P0002` |
| org2 opens period-scoped `(org2, venue1, NULL)` | `ERR P0002 not_found: venue … for org …` |
| org2's period header closed over org1's paid order | 0 lines, net 0, 0 payouts |

The widened venue check is genuinely inert: the payee is `s.org_id` and `scoped_order` joins
`o.org_id = s.org_id`, so a header can never sweep another org's orders. **A settlement whose org
differs from the orders it sweeps is not constructible.**

**2 · Promoter-org ambiguity — NOT PROVED; fails closed as designed.** The `platform_admin`
repoint is frozen by 093 item 3 (`catalog.update_venue` refuses the `org_id` patch key). Forcing
a *pre-existing* divergence by direct UPDATE: org1 (the event owner, holding **no** venue role)
still opens its event-scoped settlement (`{"status":"ok"}` — ruling A3's fix works, the previously
terminal state is gone); org2 (the new room operator) is refused the event grain; the period grain
correctly refuses org1 and admits only the current operator. No case picks a wrong owner.

**3 · Double-lining / double payment — NOT PROVED.**
Sequential: second event-scoped settlement over the same event closes at 0 lines; period-scoped
over the same order closes at 0 lines; exactly **1** global `primary_sale` row survives.
Re-close: `noop_replay`, returning the *original* payout id — no second payout.
Concurrent (two live psql sessions, T1 holding the E-104 lock 1.5 s across an event-scoped close
while T2 runs a period-scoped close of the same order):

```
T1 {"status":"ok","net_minor":10000,"payout_ids":["f807a783-…"]}
T2 {"status":"ok","net_minor":0,"payout_ids":[]}
LINES: 1 × primary_sale 10000     PAYOUTS: 10000 minted, nets 10000,0
```

`VOLATILE` + the per-org xact lock behave exactly as documented: the loser takes a post-wait
snapshot, sees the committed line and drops the candidate.

**4 · Swallowed conflict — DISPROVED (the defence works).** Direct storage test of the claim:

```sql
insert into venue.settlement_line (settlement_id,cause,cause_ref,amount_minor)
values (<other settlement>,'primary_sale',<same order>,5000)
on conflict on constraint settlement_line_cause_uq do nothing;
--> ERR 23505 duplicate key value violates unique constraint "settlement_one_primary_sale_line_ever"
```

The named arbiter does **not** absorb a global-index violation; the close aborts having written
nothing. No revenue line can be silently dropped out of gross by this mechanism.

**5 · RULING A4 — NOT PROVED, exhaustively.** `grep -n "update kernel.payout" 093` → **zero
hits**; `hold_state` appears in 093 only inside a comment. The five routines that write
`kernel.payout` (`hold_payout`, `release_payout`, `mark_payout_transfer_state`,
`request_org_payout`, `record_dispute_native`) are all pre-093 and **none** is replaced by 093.
Empirically, a `promoter_commission` payout minted `held / unfunded_settlement / pending` was
driven through close → re-close → succeeded refund → second event-scoped close → period-scoped
close:

```
A4 RESULT: hold_state=held reason=unfunded_settlement status=pending
A4: payouts with hold_state='none' and cause='promoter_commission' = 0
```

No release, no unhold, no advance, no hold-reason rewrite. 10e can only ever *remove* rows from
the eligible set. **Clean.**

**6 · Refund attacks — largely NOT PROVED** (the two that did land are P0-1 / P0-2 above):
* *failed refund must not debit* — `status='failed'` refund of 4000 against a 10000 order:
  close net 0, ledger `(no lines)`, **no `refund_void`**. The deferred-non-terminal fix works.
* *refund more than was paid* — refund of 3900 against a 3000-face / 3900-charge payment:
  `primary_sale 3000 | refund_void -3000`. Capped at face; the 900 fee residual correctly stays
  platform money (A5).
* *double refund of the same refund row* — blocked by
  `settlement_one_refund_void_line_ever` plus the seam's `NOT EXISTS`.
* *refund the wrong payment/order* — structurally impossible in `refund-execute`: the payment is
  read out of `kernel.refund.payment_id` inside the DB, `assertNoClientPaymentReference` refuses
  9 smuggled request keys, `planRefund` refuses on the `payment_native` XOR
  (`binding_subject_ambiguous`) and on `expected.order_id` disagreement
  (`binding_order_mismatch`), and the Stripe idempotency key is `refund_<refund_id>`.
* *race two refunds* — `kernel.refund_primary_order` takes `for update` on `public.payments`
  before the Σ-guard (085:534-539), so both serialize; the guard caps cumulative non-failed
  refunds at `payments.total`.

**7 · Obligation loss — the payout-side property HOLDS** (see §H7); the refund-side losses are
P0-1 and P1-3.

**8 · Price/fee tampering — NOT PROVED.** `venue."order"` carries **no** grant to
`authenticated`, `anon` or `service_role` (verified on the replayed DB), so there is no direct
write path. `total_minor` is written once by `create_primary_checkout` from
`venue.ticket_type.price_minor` × qty (one server snapshot per item, never re-read) and by
nothing else — `grep` finds no `update … set total_minor` anywhere in the chain. The A5 identity
holds end to end in the executed ledger: a 10000-face / 1000-fee order produces

```
ledger: primary_sale 10000  ||  gross=10000 fees=0 refunds=0 net=10000
```

**10000, never 11000.** The buyer fee never enters venue gross on the credit side. (It *does*
enter on the debit side through the chargeback arm — that is P0-2.)

**9 · Webhook replay / PI substitution / double issuance — NOT PROVED.** The branch is complete,
not mid-edit (`git diff --stat` = +490/−5 on `index.ts`, plus a new untracked `native.ts`).
* *Replay / concurrent double delivery* — the claim is an idempotent conditional UPDATE
  (`.neq('status','succeeded').neq('status','refunded')`), and the finalize command key is
  `wh_native_primary:<order>:<pi>`, an invariant of the economic fact rather than of the
  delivery, so a second `event.id` for the same PI converges on the mint's replay short-circuit
  (`ownership_log_command_uq`).
* *Out of order vs a refund* — the `.neq('status','refunded')` guard plus
  `finalize_primary_order`'s "payment already carries a refund" refusal (085:1935-1937) block
  minting for money that went back.
* *PI substitution* — `payments.stripe_payment_intent_id` is UNIQUE;
  `verifyNativePaymentRow` requires `mode='native_primary'`, `listing_id IS NULL`,
  `seller_id IS NULL` and `buyer_id = metadata.buyer_id`; `finalize_primary_order` then re-proves
  buyer equality against the **order**, `payments.status='succeeded'`, and
  `payments.total >= order.total_minor`; and `payment_native_payment_uq` makes a second link to a
  different order a `unique_violation` that the handler re-raises (the replay arm only returns
  when *that* order is already `paid`).
* *Forged `rail` / `mode`* — `resolveRail` is rail-first and asserts `mode === rail`;
  `rail_mode_mismatch` and `unknown_rail` both fail closed. Forging metadata at all requires
  forging the Stripe webhook signature.

---

# THE DESIGN'S OWN CLAIMS

## H7 — "a settlement can accumulate correct venue payable facts while payout execution is entirely unavailable" — **HOLDS.**

Seven simulated days, one order per day (face 1000·i), open + close each day, with no executor
ever run:

```
Σ face of the 7 daily orders                  = 28000
Σ primary_sale lines for those orders         = 28000
payout statuses                               = pending   (only)
payouts carrying a stripe_transfer_ref        = 0
```

The owed amount is exact and complete with zero payout execution. **Required property confirmed.**

## H1 — "no test or code path reconstructs venue debt from Stripe rather than from the database" — **HOLDS.**

`grep -rniE "stripe.*(balance|charges|payout)|reconcile.*stripe|from stripe"` across
`refund-execute/`, `stripe-webhook/`, `tests/` and `supabase/tests/`, filtered to money nouns,
returns exactly one hit: `151:396 'C28: the Stripe state-sync marks the payout paid'` — that is
Stripe → `kernel.payout.status`, i.e. execution *outcome* flowing in, never venue debt flowing
out. `kernel.settlement_primary_lines` reads `venue."order"`, `kernel.payment_native`,
`kernel.refund` and `venue.settlement_line` only. No Stripe object is an operand of any settlement
figure.

The caveat is P0-1: nothing reconstructs debt from Stripe, but after a post-close refund **Stripe
is the only place the truth exists**, because the database's answer is stale and never revisited.

---

# RANKED SUMMARY

| # | Finding | Rank |
|---|---|---|
| P0-1 | Post-close refund is never collected; negative settlements mint no payout and never carry forward (paid 19000 vs owed 8400) | **P0** |
| P0-2 | `refund_void` + `chargeback` double-debit the same money; chargeback also debits the buyer-side fee (A5) — venue underpaid 6600 in one close | **P0** |
| P1-1 | `gross_minor::integer` overflow permanently bricks a settlement > $21.47M | P1 |
| P1-2 | `venue_order_sel_venue` lacks the E-76 conjunct 10f added — stale room staff read a foreign org's orders and `buyer_id` | P1 |
| P1-3 | Non-terminal refunds defer the obligation with no bound; `kernel.list_pending_refunds` does not exist, so nothing moves a refund out of `pending` | P1 |
| P2-1 | `chargeback` / `market_sale` have no global uniqueness, unlike the three causes that do | P2 |
| P2-2 | Post-divergence period header openable by a party with no economic interest (inert, but audited) | P2 |

**Clean:** ruling A4 (no promoter money released, by grep and by execution), settlement theft,
promoter-org ambiguity, double-lining incl. the concurrent race, the swallowed-conflict question
(the named arbiter provably does not swallow a global violation), the A5 credit-side fee rule,
`total_minor` tampering, and every webhook replay / substitution / forgery route tried.

The two P0s share one root: **093 activated the credit side of the ledger without a
settle-after-refund-window policy or a receivable object.** Once gross is real, every debit that
arrives after its credit's settlement closed is either invisible (case b) or unrecoverable
(case a). The 10b header names this as a residual and defers it to an owner decision; the
measurement above is that it is not a residual any more — it is the default outcome for the
ordinary refund timeline, and it is money.
