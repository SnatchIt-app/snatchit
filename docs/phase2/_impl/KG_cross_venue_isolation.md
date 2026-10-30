# KG — Cross-venue isolation of post-payout recovery (investigation, no implementation)

Investigator G · 2026-09-03 · repo `snatchit-consol` @ `609e0f4` (feature/venue-native-and-product-v2) ·
rehearsal DB `snatchit_rehears_g` (000–095 + 5 timestamped, LC_ALL=C order, GATE-2 tables=27 functions=70 policies=37 triggers=26).

Owner direction under test: **NO default cross-venue netting.** Org O; Venue A owes 500; Venue B earns 1,000 → B must not
silently lose 500. Legal debtor may remain the org; recovery source = originating venue only.

**Headline (executed, not reasoned):** today Venue B loses the 500. The `chargeback` arm of
`kernel.settlement_royalty_lines` is the ONLY settlement/payout path that scopes by org without a venue predicate, and it
is enough on its own to (a) net A's loss into B's payout at full magnitude, (b) leave **zero** rows in
`kernel.organization_obligation` (the recovery is invisible to the "durable record"), (c) mis-attribute any residual
shortfall to B's settlement, (d) drag A's lifecycle holds (event cancelled / open dispute / later refund) onto B's payout,
and (e) show A's dispute id inside B's finance view. Every other seam is already venue-scoped. A 4-line body change,
prototyped in the rehearsal DB and reverted, removes (a)–(e) with 817/817 pgTAP still green — but it creates a new
stranding case that must be paired with an obligation producer or it merely converts B's loss into a platform loss.

---

## 1. What I inspected (file:line)

### 1.1 Enumeration of every settlement / chargeback / refund / commission / payout / obligation path and its scope

| # | Object | Scope predicate actually in the body | Class | Venue-safe? |
|---|---|---|---|---|
| 1 | `venue.settlement` header — 087:44-66 | `org_id` NOT NULL, **`venue_id` NOT NULL**, `event_id` nullable, `period_start/end` nullable; waterfall CHECK 087:60-66 | accounting container | n/a — every settlement is bound to exactly one venue |
| 2 | `venue.open_settlement` — 093:216-268 | authority: venue_finance of the room whose CURRENT operator = `p_org_id`, or org_finance/org_owner (093:228-233); scope: event grain binds `event.venue_id = p_venue_id and event.org_id = p_org_id` (093:251-256); period grain requires `venue.org_id = p_org_id` (093:257-262) | authority + header | yes |
| 3 | `kernel.settlement_primary_lines` — 093:435-559 (`primary_sale` + `refund_void`) | `scoped_order`: `o.org_id = s.org_id` **and** `(event_id match) or (e.venue_id = s.venue_id and period window on es.starts_at)` — 093:461-470; `refund_candidate` joins `scoped_order` (093:520) so the refund arm inherits the venue scope | actual economic netting | **yes** (executed: variant 5) |
| 4 | `kernel.settlement_royalty_lines`, royalty arm — 093:1153-1167 | `t.org_id = s.org_id` + the same event-or-venue+period predicate (093:1158-1165) | economic credit | yes (code) |
| 5 | `kernel.settlement_royalty_lines`, **chargeback arm** — 093:1169-1196 | `join venue."order" o on o.order_id = pn.order_id and o.org_id = s.org_id` (093:1187), `d.status in ('lost','charge_refunded')` (093:1185), E-94 `pn.order_id is not null` (093:1186). **No join to session/event, no venue predicate, no period predicate.** Stated as deliberate: 093:1130-1133 "the deliberate absence of a scope predicate on the chargeback arm (088:311-316: a chargeback lands in the org's NEXT settlement to close, which is 088's design and not 093's to change)"; 088:310-316 original | **actual economic netting, ORG-scoped** | **NO — the leak** |
| 6 | `kernel.settlement_commission_lines` — 093:889-925 | `a.org_id = v_s.org_id` + event-or-venue+period (093:905-909) | economic debit (promoter, held) | yes (code) |
| 7 | `kernel.close_settlement` — 093:640-854, re-created 094:544-786 (only delta = `elsif v_net < 0` branch 094:753-775) | derives gross/fees/refunds/net from THIS settlement's lines only (093:700-704); mints one payout `payee_org_id = v_s.org_id, cause_ref = settlement_id, amount = net` (093:828-838) | payout netting per settlement | inherits #5's leak; the payout itself is settlement-bound, so no org-wide pooling |
| 8 | 094 shortfall branch — 094:771 → `kernel.record_organization_obligation` 094:320-425 | `origin_kind='settlement_shortfall', origin_ref = settlement_id`, amount re-derived from header (094:367-381) | obligation projection | attributes the shortfall to **whichever settlement netted negative** — after a leak that is the wrong venue (variant 4) |
| 9 | `kernel.organization_obligation` — 094:177-235 | `org_id` only; no venue column; J3 §7.1 explicitly declined to denormalise venue ("recoverable through origin_ref → … → event", J3:466-469) | obligation record | venue derivable only via origin settlement → wrong after a leak |
| 10 | `kernel.org_outstanding_obligation_minor` — 094:504-513 | `org_id`, `status='outstanding'` | reporting only (called by nothing: 094:488-489; pgTAP 160 F8/F9) | org-level by design ("legal debtor = org") — fine |
| 11 | `record_organization_obligation('unlined_reversal', …)` — 094:387-396 | guard: origin not already lined as chargeback/refund_void anywhere | obligation projection | **no producer**: `grep -rn organization_obligation supabase/functions` → 0 hits |
| 12 | `kernel.settlement_covered_payments` — 093:1988-2022 | covered set derived from THIS settlement's **lines** (093:2015-2017), by design because "088's chargeback arm deliberately carries NO scope predicate" (093:2106-2110) | operand for maturity/staleness | inherits #5: after a leak B's covered set contains A's payment + A's session |
| 13 | `kernel.settlement_payout_maturity` — 093:2076-2175 | predicates over covered sessions/payments (093:2111-2131) | hold gate (mint 093:824, advance 093:1859, transfer 095:1059, retry 095:551) | inherits #12 → **cross-venue hold leakage** (variants 6, 7) |
| 14 | `kernel.settlement_unbooked_refund_exposure` — 095:963-1001 + `get_payout_execution_context` 095:1014-1146 | Σ succeeded refunds over covered payments minus discharged `refund_void` lines | transfer-time refusal | inherits #12 → `refund_exposure_stale` on B for A's refund (variant 7b) |
| 15 | `kernel.request_org_payout` — 093:1743-1985 | `has_org_role(p_org_id)` + `v_s.org_id = p_org_id` (093:1756-1759); selects the payout by `cause_ref = p_settlement_id` (093:1786-1788) | authorization | settlement-bound; no org pooling |
| 16 | `kernel.payout` — 085:111-147 | `payee_org_id`, `cause_ref` (settlement), no venue column | accounting | venue derivable via settlement |
| 17 | `kernel.retry_held_payout` — 095:485-600 | org authority (095:506) + settlement-bound (095:517-519) + re-evaluates #13 (095:551) | authorization | inherits #13 |
| 18 | `kernel.rearm_failed_payout` 095:263, `hold_payout_transfer_reversed` 095:676-838, `guard_payout_org_payable` 095:100-160 | per-payout row; org status only | state machine | no netting |
| 19 | `kernel.record_dispute_native` payout leg — 088:836-850 | holds every pending/submitted payout whose `cause_ref` is a settlement carrying a line with `cause_ref = order_id` (088:842-844) | hold | venue-scoped in effect (variant 9: only SA1 held) |
| 20 | E-104 advisory lock `settlement.seam.org:<org>` — 093:441, 093:896, 093:1146 | per-org | concurrency only | serialises sibling-venue closes of one org; no money effect |
| 21 | RLS `venue_settlement_sel_venue` 093:965-969, `venue_settlement_line_sel_venue` 093:971-975 (+ org arms 087:78-81, 087:117-121) | venue role over `s.venue_id` + E-76 current operator | disclosure | the header is venue-bound, so a leaked line is readable by the **absorbing** venue's finance and invisible to the **originating** venue's finance (variant 1 RLS) |
| 22 | Identity / resale arm — 093:1186 (E-94), `kernel.identity_obligation` 085:165-198, `kernel.record_identity_obligation` | resale-rail disputes have `pn.sale_id`, never `pn.order_id` → never booked against the org; identity debt is per-identity | separate rail | not org/venue-netted (code-verified; not executed — needs market fixtures) |
| 23 | `supabase/functions/payout-execute/executor.ts:450-498` | asserts `settlement_org_id == payee_org_id`; payout-row-driven | executor | no aggregation |
| 24 | `kernel.list_org_payouts` 085:1439, notify `payout_request_pending_approval` 092:658 | org-scoped listings | reporting only | n/a |

Conclusion of the enumeration: **exactly one** money path (#5) is org-scoped without a venue predicate; #7, #8, #12, #13,
#14, #17, #21 are venue-safe in themselves and become cross-venue only because they consume #5's line.

### 1.2 Prior corpus position (so the orchestrator knows this was already an open owner item)
- J3 §7.2 / §10 Q1-Q2 (`docs/phase2/_impl/J3_receivable_architecture.md:475-505, 560-571`): mechanism ratified at 088:310-316,
  economics NOT ratified; three engineering paths costed; disclosure question raised.
- G5 ruling §3 option 3, §5.1, §7 (`docs/phase2/G5_POST_PAYOUT_EXPOSURE_RULING.md:86, 113-118, 158-164`): cross-venue netting
  line left blank for the owner; "a 'not permitted' answer requires a change to shipped behaviour".
- `PRIMARY_TICKETING_ACTIVATION_MATRIX.md:156` / `H4_maturity_ledger.md:272` (cited by J3:481-484): "silently confiscates a
  venue's later revenue while destroying the excess — a dispute with the venue waiting to happen".
- Tests pinning the org-scoped behaviour by LABEL only: 153:786-815 (H45-H51 "chargeback lands in the org's NEXT
  settlement") — but st1/st2/st5 and the disputed orders are all at `venue1` (153:230-283, 675, 783, 823); 160:385-396
  (C14-C17, event ev2 at venue1 both sides); 160:523 F10 asserts only `!~ 'organization_obligation'`; 154:92 and 153:118
  grep `prosrc LIKE '%chargeback%'`. **No test exercises two venues of one org.**

---

## 2. What I executed and the results

Fixture (scratchpad `kg_scenario.sql`, BEGIN … ROLLBACK, one SAVEPOINT per variant; helper shape copied from
`supabase/tests/160_organization_obligation.sql:46-100`): `tap.seed_core()`; org O (seller) with venues A and B, org P
(other_user) with venue C, all approved; events evA, evA2 (venue A), evB (venue B), evC (venue C), sessions 15–30 days in
the past with `ends_at`; `payout.settlement_maturity_interval = "7 days"`; `venue.staff_role` rows: `vfinB` =
venue_finance on B only, `vfinA` = venue_finance on A only. Orders are the `venue."order"` + `public.payments` +
`kernel.payment_native` triple; disputes are direct `kernel.dispute_native` inserts at `status='lost'` (the producer gap is
KA's, not this file's). Opens run as `tap.seller()` (org_owner), closes as `tap.admin_user()` (platform_admin).

Step 1 — `oA1` face 50000 at venue A → `SA1` (event evA) closes:
```
 tag | status | gross | fees | refunds |  net  | venue_tag | event_tag
 SA1 | closed | 50000 |    0 |       0 | 50000 | venueA    | evA        payout_ids=[1]
```
Step 2 — `dA1` LOST 50000 on `oA1` (post-payout). Step 3 — `oB1` face 100000 at venue B. Org P: `oC1` 30000, `SC1` net
30000, `dC1` LOST 30000.

**Seam probe** (what each seam OFFERS an open venue-B period settlement `SBp`, no close):
```
 seam               | cause        | amount_minor | ref
 primary            | primary_sale |       100000 | oB1
 royalty/chargeback | chargeback   |       -50000 | dA1      ← venue A's dispute offered to venue B
```

### V1 — B period-scoped (`venue_id=B, event_id NULL, period {}`) closes  ← **the owner's scenario**
```
 SBp | closed | 100000 | 0 | 50000 | 50000 | venueB |          lines: chargeback -50000 dA1 · primary_sale 100000 oB1
 payout for SBp: 50000 pending none
 obligations org O: n=0 total=0        obligations org P: n=0 total=0
 dA1 lined in: SBp
 covered set of SBp: (pay:oA1, sA, chargeback) (pay:oB1, sB, primary_sale)
 SA2 (venue A, next period settlement): closed gross 0 refunds 0 net 0 — zero lines
```
Leakage = **50000 = 100% of A's debt**, taken from B; no obligation, no audit row names venue A; A's own next
settlement is empty.

RLS as `vfinB` (`tap.login` → role authenticated, claims sub=vfinB):
```
 visible_settlement | status | net_minor | venue_tag
 SBp                | closed |     50000 | venueB
 in_settlement | cause        | amount_minor | cause_ref_tag
 SBp           | chargeback   |       -50000 | dA1        ← another venue's dispute id, readable
 SBp           | primary_sale |       100000 | oB1
```
RLS as `vfinA`: sees SA1 (+50000) and SA2 (0) only; **no trace of the recovery** of its own loss.

### V2 — B EVENT-scoped (`event_id = evB`) closes: identical leak
```
 SBe | closed | 100000 | 0 | 50000 | 50000 | venueB | evB     lines: chargeback -50000 dA1 · primary_sale 100000 oB1
```

### V3 — A's own next settlement closes FIRST (permitted venue-scoped recovery)
```
 SA2 | closed | 0 | 0 | 50000 | -50000 | venueA |      line: chargeback -50000 dA1
 obligation: settlement_shortfall origin=SA2 amount=50000 outstanding
 then SBp: closed 100000 | 0 | 0 | 100000 — clean, payout 100000
```
Outcome is therefore **close-order dependent**: whichever venue of the org closes first absorbs the debit.

### V4 — B earns less than A owes (`oB1` cancelled, `oB2` face 30000)
```
 SBp | closed | 30000 | 0 | 50000 | -20000 | venueB |     lines: chargeback -50000 dA1 · primary_sale 30000 oB2
 payout for SBp: 0
 obligation: settlement_shortfall origin=SBp amount=20000 outstanding  origin_settlement_venue=venueB
```
30000 of B's revenue silently consumed; the residual 20000 is booked as **venue B's** shortfall; venue A appears nowhere.

### V5 — refund_void arm (post-payout SUCCEEDED refund `rA1` on `oA1`; dispute removed)
```
 primary seam offers SBp: primary_sale 100000 oB1   (no refund_void)
 SBp | closed | 100000 | 0 | 0 | 100000            SA2 | closed | 0 | 0 | 50000 | -50000  line: refund_void -50000 rA1
 obligation: settlement_shortfall origin=SA2 amount=50000
```
The refund arm is venue-scoped (093:461-470 + 093:520). Only the chargeback cause leaks.

### V6 — hold leakage: A's event cancelled after A's payout; B closes
```
 SBp payout: 50000 pending HELD event_cancelled
 maturity(SBp) = {hold_reason: event_cancelled, covered_sessions: 2, event_cancelled: true}
```
### V7 — a NEW open dispute (needs_response, 100) on A's payment after B closed with dA1 lined
```
 hold_at_close: null → maturity(SBp).hold_reason = dispute_open
 get_payout_execution_context(B payout, org bound to acct_gTestOrgO, transfers active, status active):
   execution_eligible=false refusal_code=dispute_open  maturity_detail.covered_sessions=2 dispute_open=true
```
### V7b — a SUCCEEDED 50000 refund on A's order after B closed with dA1 lined
```
 settlement_unbooked_refund_exposure(SBp) = 50000 → refusal_code = refund_exposure_stale
```
B's 50000 payout is refused at transfer time for a refund on a venue-A order.

### V8 — cross-org: org P's `dC1` never appears in org O's settlement
```
 SBp lines: chargeback -50000 dA1 · primary_sale 100000 oB1   (no dC1)
 dC1 lined where: (none)      chargeback seam for org P's next settlement: chargeback -30000
```
Isolation across orgs holds (093:1187 `o.org_id = s.org_id`; open_settlement binding 093:252-263).

### V9 — `record_dispute_native` payout leg, OPEN dispute on A's order
```
 payouts_held=1 → SA1 held/dispute · SBp none · SC1 none
```
The freeze leg is line-driven (088:842-844) and therefore venue-correct.

### V10 — SAME venue, DIFFERENT event: evA2-scoped settlement at venue A after evA's lost dispute
```
 baseline:  SA2e net -30000  lines: chargeback -50000 dA1 · primary_sale 20000 oA2
```

### Prototypes (rehearsal DB only; applied, measured, reverted — md5 of `pg_get_functiondef` identical after restore)
P1 = 093:1136-1220 body with ONE change in `cb_candidate` (093:1187 →):
```sql
      join venue."order" o on o.order_id = pn.order_id and o.org_id = s.org_id
+     join catalog.event_session es on es.session_id = o.event_session_id
+     join catalog.event e on e.event_id = es.event_id and e.venue_id = s.venue_id   -- originating venue only
     where d.currency = s.currency
```
P2 = P1 + `and (s.event_id is null or e.event_id = s.event_id)` (event grain binds to its own event; period grain absorbs
any chargeback at its venue with NO period window on debits).

| Variant | baseline (093) | P1 (venue) | P2 (venue+event grain) |
|---|---|---|---|
| seam probe for SBp | chargeback -50000 offered | not offered | not offered |
| V1 B period | net 50000, payout 50000, 0 obligations | net 100000, payout 100000 | same as P1 |
| V2 B event | net 50000 | net 100000 | net 100000 |
| V1 then SA2 (A period) | SA2 net 0 (debt gone) | SA2 net -50000 → obligation 50000 origin=SA2 (venue A) | same |
| V4 (B 30000) | B net -20000, obligation origin=SBp | B net 30000, payout 30000, 0 obligations (A's debt waits for A) | same |
| V6/V7/V7b holds on B | leaked | (covered set has no A rows → cannot leak; not re-run) | — |
| V8 cross-org | isolated | isolated | isolated |
| V10 evA2-scoped at venue A | absorbs (-30000) | absorbs (-30000) | does NOT absorb (net 20000) |
| pgTAP 151/153/160/161 | 274/367/90/86 ALL-PASS | **817/817 ALL-PASS** | **817/817 ALL-PASS** |

---

## 3. Findings, ranked

**P0-1 — Default cross-venue netting is live at full magnitude and unrecorded.** `kernel.settlement_royalty_lines`'s
chargeback arm (093:1169-1196, 093:1187) offers every terminal-lost dispute of the org to whichever venue's settlement
closes next. V1/V2: B's payout is 50000 instead of 100000 for both grains; `kernel.organization_obligation` has 0 rows;
the only durable trace is a `settlement_line` in B's settlement whose `cause_ref` is A's dispute id; no audit row names
venue A; outcome is close-order dependent (V3). This is exactly the "silent" outcome the owner ruled out, and it bypasses
the object G5 names as THE durable record — recovery is accidental, not deterministic or auditable.

**P0-2 — Shortfall mis-attribution.** When the absorbing venue's revenue is smaller than the foreign debt (V4), 094:771
books `settlement_shortfall` with `origin_ref` = the absorbing venue's settlement; the only venue derivable from the
obligation is the wrong one, and the consumed portion (30000) is invisible everywhere.

**P1-3 — Cross-venue hold and refusal leakage.** Because `settlement_covered_payments` derives the covered set from lines
(093:2015-2017, justified at 093:2106-2110 by the chargeback arm's lack of scope), a leaked line imports A's payment and
session into B's maturity/staleness operands: B held `event_cancelled` for A's event (V6), `dispute_open` for A's new
dispute at mint-time re-evaluation and at transfer (V7), `refund_exposure_stale` 50000 for A's later refund (V7b). B's
money is stuck behind A's lifecycle. Disappears with the ring-fence (covered set then contains only B rows).

**P1-4 — Disclosure asymmetry.** `venue_finance` of the absorbing venue reads a line naming another venue's dispute id and
amount (V1 RLS); `venue_finance` of the originating venue sees nothing about how its loss was recovered. J3 Q2 flagged
this; it is now executed. `cause_ref` is an opaque uuid (no buyer PII), so the disclosure is of existence/amount, not
identity.

**P1-5 — Ring-fencing creates a stranding case that today is masked by sibling venues.** After P1/P2, a chargeback at a
venue that never opens another settlement is never lined anywhere; the `unlined_reversal` origin (094:387-396) exists for
exactly this but has **no producer** (0 hits in `supabase/functions`), and its guard forbids booking once a line exists,
so producer ordering vs. a later venue close is a double-count trap. Shipping the ring-fence alone converts "B pays A's
debt" into "the platform eats A's debt silently" — dishonest unless paired (see §4).

**P2-6 — Cross-org isolation proven** (V8) — no change needed.
**P2-7 — refund_void (V5), promoter commission (093:905-909), royalty (093:1158-1165), dispute freeze leg (V9) are already
venue-scoped.** Only the chargeback cause needs the predicate.
**P2-8 — No test breaks under either prototype (817/817).** Stale prose only: 093:1130-1133 comment, 088:310-316 design
text, 153:802 H46 label ("org's NEXT settlement" — factually still true at one venue), 160:523 F10 label ("deliberate
absence of a scope predicate" — assertion is `!~ 'organization_obligation'`, unaffected), 093:2106-2110 comment in
`settlement_payout_maturity` (rationale becomes moot but the line-derived covered set stays correct). A new two-venue
pgTAP file is required; nothing existing asserts the behaviour.
**P2-9 — Event-grain semantics are an open choice** (V10): P1 lets an evA2-scoped settlement absorb evA's chargeback
(same venue); P2 does not. Both honour the owner's venue rule.

---

## 4. Options, trade-offs, the smallest honest design

Prerequisite for any option: 093/094/095 are immutable (CI gate); the change is a **new migration 096** with a
`create or replace function kernel.settlement_royalty_lines(uuid)` body-only re-creation (ACL preserved by CREATE OR
REPLACE — 087 revoke stays; 093:561 pattern). `kernel.close_settlement` (094's copy) is not touched.

| Option | Change | Recovers A's debt via | Stranding risk | Honesty notes |
|---|---|---|---|---|
| **A. Status quo + disclosure** (J3 "org-wide netting") | none / surface the line | any sibling venue | none | contradicts owner direction; keeps P0-1/P0-2/P1-3 |
| **B. P1 — venue ring-fence, grain-agnostic** (prototyped) | +2 joins in `cb_candidate` (`e.venue_id = s.venue_id`) | any later settlement at venue A (event- or period-scoped) | venue A never settles again → nothing recorded | smallest; V10 shows a different EVENT at the same venue absorbs — acceptable under "recovery source = originating venue" |
| **C. P2 — B + event-grain match** (prototyped) | B + 1 predicate | period settlement at A (any window) or event settlement of the SAME event | higher: an operator who only opens event settlements strands every post-close chargeback | cleaner accounting per event; more stranding |
| **D. Full scope mirror** (event, or venue+period **window** on the disputed session's `starts_at`) | B + the 093:467-470 predicate verbatim | only the matching period/event | highest: sequential monthly periods never revisit a January session disputed in March | dishonest to ship without a sweep/obligation producer; I did not prototype it |
| **E. Config/agreement-level org override** (later) | new `payout.%` dual-controlled key or agreement object | per owner ruling | — | not now (owner) |

**(ii) `venue_id` on `kernel.organization_obligation`** (all options): 096 `alter table kernel.organization_obligation add
column venue_id uuid references catalog.venue(venue_id) on delete restrict` + derive INSIDE `record_organization_obligation`
(no signature change): `settlement_shortfall` → `v_s.venue_id`; `unlined_reversal` → dispute/refund → `payment_native` →
`order.event_session_id` → `event.venue_id`. The write-once guard (094:260-291) must be re-created in 096 to add `venue_id`
to its immutable list (trigger count stays 2 — 160 A23 unaffected). NOT NULL is derivable for both origins; nullable only
if a future origin lacks a venue. Backfill: none (table is created by unapplied 094; `venue.settlement_line` is empty in
prod, 093:580-582). This gives future venue-scoped recovery a key without changing the debtor (`org_id`).

**Smallest honest design (my recommendation to the orchestrator, not a decision):** Option **B** + (ii) + a two-venue pgTAP
file + **one of** the two stranding answers below, chosen by the owner:
1. an `unlined_reversal` producer with an explicit rule such as "book the obligation when the originating venue has no
   open settlement after N days / at dispute-terminal + N" — but the 094:387-396 guard and the netting dedupe must be made
   mutually exclusive (obligation booked ⇒ the chargeback arm must skip that dispute, or the later close double-counts);
   this touches the seam a second time; or
2. accept stranding and make it visible: a platform read of "terminal-lost disputes of org O with no chargeback line and no
   obligation", i.e. a projection only (cheapest, honest as long as it is surfaced).

**What would be dishonest:** shipping B/C/D and describing the obligation table as the durable record while P1-5 is open;
adding an org-level netting switch now; applying the period window to debits (D) and calling it "mirrors the credit
side" when it strands money that today is recovered; touching `settlement_covered_payments`/maturity to "fix" P1-3
instead of the root cause; editing 093/094 in place.

---

## 5. Open questions for the orchestrator / owner
1. **Event-grain rule** (B vs C): may an event-scoped settlement at venue A absorb a chargeback from a DIFFERENT event at
   venue A? (V10.) Owner direction only says "originating venue".
2. **Period window on debits**: never (B/C) or mirrored (D)? Recommend never; needs a sentence in the ruling.
3. **Stranded debit policy** after ring-fencing (P1-5): which of §4's two answers, and the N.
4. **Disclosure**: after B, `vfinA` sees its own recovery line (V3 under P1) and `vfinB` sees nothing foreign — is that the
   intended posture (J3 Q2 answered by construction)?
5. **Obligation gating** (J3 Q5): does "legal debtor = org" imply `org_outstanding_obligation_minor` should hold ALL org
   payouts across venues? That is org-level netting by another name; I recommend the owner rule it explicitly and
   separately.
6. Should 096 also carry the KA dispute-producer wiring, given that without a writer of `dispute_native` at `lost` none of
   this arm executes in production today (brief §system facts; KA report)?
