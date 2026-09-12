# KD — ORGANIZATION OBLIGATION: RESOLUTION AND RECOVERY (investigation, no implementation)

Investigator D · train brief §13/§17/§21 · repo `snatchit-consol` @ 609e0f4 · rehearsal DB `snatchit_rehears_d`
(fresh replay, 110/110 migrations, GATE-2 27/70/37/26 = CI baseline; pgTAP 000+160 → 96/96 before any probe).

Scripts (scratchpad, not in repo): `kd_scenarios.sql`, `kd_probe2.sql` — both BEGIN…ROLLBACK, run as `postgres`
(the `guard_listing_insert_columns` ALLOW-2 arm needs `current_user = postgres`; as any other role `tap.seed_core()` fails).

---

## 1. What was inspected

| Object | Where |
|---|---|
| `kernel.organization_obligation` DDL | 094:177-247 — `origin_kind` closed pair 094:201; `origin_ref uuid NOT NULL` soft ref 094:203; `amount_minor integer CHECK (>0)` 094:215; `status` triple 094:225-226; resolution triple 094:227-229; `organization_obligation_origin_uq (origin_kind, origin_ref)` 094:234; `resolution_ck` 094:236-238; partial UNIQUE `stripe_dispute_ref` 094:241-242; partial idx `(org_id) WHERE status='outstanding'` 094:245-246 |
| `kernel.organization_obligation_guard()` (BEFORE UPDATE/DELETE) | 094:260-293 — DELETE refused; identity/magnitude/currency write-once; terminals exclusive 094:281; no return to outstanding |
| RLS / grants on the table | 094:300-306 — RLS on, zero policies, `REVOKE ALL` from every role incl. service_role |
| `kernel.record_organization_obligation(uuid,text,uuid,text,integer,text,text,text)` | 094:320-413 — shortfall re-derivation 094:352-378 (`p_amount_minor <> -v_s.net_minor` 094:371); unlined_reversal anti-double-count `NOT EXISTS settlement_line cause in (chargeback,refund_void)` 094:387-392; `ON CONFLICT ON CONSTRAINT origin_uq DO NOTHING` 094:399; audit `org_obligation.record` 094:408-410 |
| `kernel.resolve_organization_obligation(uuid,text,text,text)` | 094:431-476 — `is_platform(platform_risk|platform_admin)` 094:441; `p_resolution in (recovered, written_off)` 094:444; same-terminal replay 094:452-454; `state_conflict` 094:455-457; UPDATE status+triple 094:459-463; audit `org_obligation.resolve` with `before/after = {status}` only 094:464-467 |
| `kernel.org_outstanding_obligation_minor(uuid)` | 094:504-514 (STABLE, `sum(amount_minor) where status='outstanding'`) |
| `kernel.close_settlement` shortfall branch | 094:753-775 (`elsif v_net < 0` → `perform record_organization_obligation(v_s.org_id,'settlement_shortfall',p_settlement_id,null,(-v_net),v_s.currency,…)`) |
| Grants | 094:808-831 — record/resolve/projection `service_role` only; `authenticated` revoked |
| Identity twin | 085:165-198 (DDL), 085:1795-1836 (`record_identity_obligation`), 085:1838-1878 (`resolve_identity_obligation`) — grant class differs: twin is `{authenticated, postgres}` (catalog probe below) |
| 095 E-6 `kernel.settlement_unbooked_refund_exposure(uuid)` | 095:963-997; discharge predicate 095:983-986; the "extend when the obligation lands" note 095:931-943; consumer `get_payout_execution_context` 095:1069 |
| 095 E-4 `kernel.hold_payout_transfer_reversed` | 095:676-771 (submitted→pending+held only; refuses on `paid`; names no obligation) |
| `kernel.mark_payout_transfer_state` | 085:1668-1735 — `paid→reversed` writes status + audit `{status}` only; touches neither the settlement header nor any obligation |
| Chargeback arm | 088:310-316 (design: "org's NEXT settlement to close", no scope predicate), 093:1136-1196 (re-created; `o.org_id = s.org_id`, `NOT EXISTS settlement_line cause='chargeback' and cause_ref=dispute_id`) |
| `venue.settlement` | 087:44-70 — `venue_id uuid NOT NULL` 087:47; `settlement_line_cause_uq = UNIQUE (settlement_id, cause, cause_ref)` (catalog) |
| `kernel.is_platform` | 077:468-486 — `auth.uid()` against `kernel.platform_role` or `public.admin_users` |
| `kernel.admin_audit` | 077:236-247 — `reason_code text NOT NULL`, `before/after jsonb`; no command_key column |
| Design docs | J3 §5.1-§5.3, §6, §7, §10 (Q1-Q5, Q9, Q10); J7 §3, §4, §7-§9; J5 §5 (partial reversal unrepresentable), §6 (exposure fix + the extension note) |
| Edge callers | `grep rpc(` over `supabase/functions`: **zero** callers of any `organization_obligation` verb; the house precedent for the same grant/authority shape is `refund-execute/index.ts:713-736` (H1 §5) |

---

## 2. What was executed, and the results

### 2.1 Booking (producer) — works as J7 claims
| Step | Result |
|---|---|
| ev1: order 10000 → close sA1 | `net 10000`, payout minted `pending|held|unbounded_refund_exposure|10000` (maturity key unset on rehearsal) |
| refund 10000 succeeded after close → close sA2 | `net -10000`, `payout_ids []` → **O1 = settlement_shortfall|10000|outstanding** |
| ev2: order 7000 → close +7000; dispute `lost` 7000 → close sB2 | `net -7000` via the chargeback arm → **O2 = settlement_shortfall|7000|outstanding**; `org_outstanding = 17000` |

### 2.2 Who can resolve — executed matrix (`tap._resolve` sets claims; `p_switch_role=true` also switches the SQL role, i.e. the real PostgREST shape)
| Principal | Result |
|---|---|
| buyer (authenticated, claims only) | `42501 insufficient_privilege: platform_risk or platform_admin required` |
| seller = org_owner of the DEBTOR org | `42501` (org self-service is impossible — correct) |
| service_role JWT, no `sub` (claims only) | `42501 insufficient_privilege` (auth.uid() NULL ⇒ is_platform false) |
| **service_role ROLE + service JWT (real edge service client)** | **`42501 insufficient_privilege`** |
| **platform_admin user, `authenticated` ROLE (real edge caller client)** | **`42501 permission denied for function resolve_organization_obligation`** |
| platform_admin user, claims only, SQL role `postgres` (the pgTAP-160 shape) | `ok` → `recovered|off_platform_payment|resolved_by=4444…` |
| platform_risk (row in `kernel.platform_role`, NOT in admin_users), claims only | `ok` → O2 `written_off|uncollectable|resolved_by=3333…` |

Audit rows written (`kernel.admin_audit`, subject_kind `org_obligation`):
```
org_obligation.record  | 4444… | settlement_shortfall | before ∅ | after ∅
org_obligation.record  | 4444… | settlement_shortfall | before ∅ | after ∅
org_obligation.resolve | 4444… | off_platform_payment | {"status":"outstanding"} | {"status":"recovered"}
org_obligation.resolve | 3333… | uncollectable        | {"status":"outstanding"} | {"status":"written_off"}
```
`p_command_key` is accepted by both verbs and **persisted nowhere** (0 audit rows mention it). The `record` audit row carries no amount, no origin_ref, no currency in `after`.

Catalog census: 47 functions in kernel/venue/catalog/market gate on `kernel.is_platform(`; **45 hold an `authenticated` EXECUTE grant; exactly two do not: `kernel.refund_primary_order` and `kernel.resolve_organization_obligation`**. The former is the H1 §5 precedent the repo itself documents as "unreachable in both directions, and no caller shape fixes it" (`refund-execute/index.ts:721-727`), whose remedy was an `authenticated`-granted definer door (`kernel.request_order_refund`).

### 2.3 Double / partial / amount / late-reversal attempts
| Attempt | Result |
|---|---|
| O1 recovered → recovered again | `noop_replay` (reason `again` silently dropped; no second audit row) |
| O1 recovered → written_off | `P0001 state_conflict … already recovered — terminals are exclusive` |
| O2 written_off → recovered ("money arrived after write-off") | `P0001 state_conflict … already written_off` — **the receipt cannot be recorded against the debt** |
| owner UPDATE `amount_minor 10000→8000` | `P0001 append_only: … write-once` |
| resolve with a 5th `amount` argument | `42883 function … does not exist` — there is no amount parameter |
| `p_resolution = 'partially_recovered'` | `P0001 invalid_input: resolution must be recovered|written_off` |
| owner UPDATE back to outstanding | `P0001 state_conflict` |
| second row for the same origin (2000) | `23505 organization_obligation_origin_uq` — one row per origin, so a partial cannot be modelled as a second row either |

### 2.4 Partial absorption + the 095 exposure guard (ev3)
| Step | `settlement_unbooked_refund_exposure(sC1)` | obligation |
|---|---|---|
| close sC1 (+10000, payout minted, never executed) | 0 | — |
| refund 10000 succeeded | **10000** (guard would refuse sC1's payout) | — |
| new order 4000; close sC2 → lines `primary_sale +4000`, `refund_void −10000`, net **−6000** | **10000** (E-6 discharges nothing from a negative header — by design) | **O3 = 6000 outstanding** |
| resolve O3 `recovered` (org repaid 6000) | **10000** — unchanged; 095 does not read the table | recovered |
| simulated J5 §6 extension ("…or the header's shortfall obligation is no longer outstanding") | **0** | — |

### 2.5 Cross-venue origin (ev4 at venue1, ev7 at venue1b, same org)
Order 10000 at **venue1** closed +10000 and paid; dispute lost 10000; venue1b's settlement for ev7 (3000 own revenue) closed next:
```
sE7 lines: chargeback −10000 (line's originating venue = venue1), primary_sale +3000 (venue1b)
net −7000 → obligation settlement_shortfall|7000, origin_ref = sE7
origin settlement.venue_id = venue1b   ← the ABSORBING venue
disputed order's event.venue_id = venue1 ← the ORIGINATING venue
```
`catalog.event.venue_id`, `venue.settlement.venue_id`, `venue."order".event_session_id` are all NOT NULL (information_schema probe), so per-line origin venues are always derivable.

### 2.6 Double-count between the two origins (ev5)
Order 5000 closed +5000 and paid; dispute lost 5000; org dormant → platform books `unlined_reversal` (guard passes: not lined yet) → `ok 5000`. Org later opens+closes a settlement for ev5: chargeback arm lines the dispute (it does not consult obligations — 160/F10 pins that), net −5000 → **`settlement_shortfall|5000` booked too**:
```
unlined_reversal      | ref=dispute    | 5000 | outstanding
settlement_shortfall  | ref=settlement | 5000 | outstanding
org_outstanding: 7000 → 17000 for ONE 5000 loss
```
Replay safety holds: re-close `noop_replay`, re-record `noop_replay`, rows for sF2 = 1; a second `stripe_dispute_ref` across origins raises `23505 organization_obligation_dispute_uq`.

### 2.7 "Post-payout" is actually "post-close" (probe2 P-1/P-2)
| Case | payout of the covered settlement | obligation booked |
|---|---|---|
| P-1: close, refund, close — payout **never executed** (`pending|held|unbounded_refund_exposure|10000` throughout) | still pending/held | `settlement_shortfall|10000` — `org_outstanding 10000` **and** `org_unpaid_payouts 10000` at the same instant |
| P-2: close, force `submitted→paid` (`mark_payout_transfer_state … 'paid'`, header → `paid`), refund, close | paid | `settlement_shortfall|10000` |
The two rows are byte-for-byte indistinguishable (13 columns; nothing records whether the money had left). P-1's debt is a debt for money the org never received, while the 095 guard is simultaneously holding that same money.

### 2.8 Recovery by transfer reversal — what the ledger can record (P-3)
`mark_payout_transfer_state(P, 'reversed', 'tr_kd2paid', …)` → payout `reversed|none|-|10000`, header stays `paid`, obligation **untouched** (`outstanding`), 0 audit rows link the reversal to the obligation. `hold_payout_transfer_reversed` refuses on a `paid` row (095:713-716). A partial reversal of a paid transfer is unrepresentable (J5 §5, owner item). So the only Stripe-side recovery instrument (J2 §4) has **no ledger path into the obligation**: a full reversal of a 10000 payout to cover a 6000 debt over-recovers by 4000 with nothing recording it, and a 6000 partial reversal cannot be stored on the payout at all.

---

## 3. Findings

### P0 — none that lose money today (094/095 are unapplied and dark). The items below are activation blockers for "recovery must be deterministic and auditable" (G5 direction).

### P1
**P1-1 `resolve_organization_obligation` is unreachable by any real principal.** Grant `{service_role}` only (094:808-831) + authority `is_platform(auth.uid())` (094:441). Executed: service client → `42501 insufficient_privilege`; platform_admin's own JWT → `42501 permission denied`. Only a direct `postgres` connection with forged claims (pgTAP) or a hand-minted JWT (`role=service_role` + `sub`) — no such minting exists in `supabase/functions` (grep for jose/djwt/SignJWT: none) — can call it. J7 §3's "reachable only through an edge forwarding a platform JWT" is false: a forwarded JWT yields role `authenticated`. The repo already diagnosed this exact shape for `refund_primary_order` (refund-execute/index.ts:721-727) and built an `authenticated`-granted door. As shipped, **no obligation can ever leave `outstanding` in production**, so `org_outstanding_obligation_minor` would only ever grow.

**P1-2 One loss can be booked twice (`unlined_reversal` then `settlement_shortfall`).** §2.6: the anti-double-count guard (094:387-392) runs only at booking time, one direction; the chargeback arm (093:1180-1196) and the shortfall branch (094:753-775) never consult existing obligations. The org's projected exposure doubles (5000 → 10000 for a 5000 loss). Under Q9 "sweep after N days" this is the *normal* path for any org that opens a settlement late. Also a TOCTOU: the guard's `NOT EXISTS` is not under the org seam lock that `settlement_royalty_lines` takes (093:1150) — unverified by execution, but the two writers take no common lock.

**P1-3 The shortfall is booked "post-close", not "post-payout"; the 095 exposure guard and the obligation then describe the same refund twice.** §2.7 P-1: payout of the covered settlement `pending|held`, exposure guard = 10000, obligation = 10000, at once. 094's boundary statement ("a refund BEFORE payout must create NO obligation", 094:112-117) is true only for refunds before the *close*; the G2 window between close and execution (≥ ends_at+7d) is exactly where refunds and lost disputes land. Consequences: (a) an org that repays a P-1 obligation off-platform has paid for money it never got unless the held payout is later released; (b) the J5 §6 extension, applied naively, releases the held payout on `recovered` — consistent by coincidence in the single-payment case, wrong in the multi-line case (P1-4); (c) nothing in the row lets an operator tell P-1 from P-2.

**P1-4 The all-or-nothing status cannot state any of the recovery facts the owner direction requires.** Executed §2.3/§2.8: no amount on resolve; no partial; no second row per origin; `written_off` is terminal so a late reversal/receipt cannot be recorded; `recovered` on a 10000 reversal against a 6000 debt records nothing about the 4000 over-recovery; a wrong-org reversal is undetectable because the verb takes only `obligation_id` and the reversal writers (`mark_payout_transfer_state`, `hold_payout_transfer_reversed`) never name an obligation. Where the model is dishonest, concretely:
| Scenario | What 094 can store | Truth it hides |
|---|---|---|
| Full Stripe transfer reversal | `recovered` (manual, unlinked) | reversal amount vs debt; over-recovery; which `tr_/trr_` |
| Manual off-platform | `recovered` + reason text | amount, receipt ref |
| Written off | `written_off` | remaining amount is implicit (= amount); any later receipt is unstorable |
| Partial 2000 of 6000 | nothing honest: `outstanding` overstates 6000; `recovered` erases 4000 | the 4000 residual |
| Recovery > debt | `recovered` | the excess owed back to the org |
| Wrong org's reversal | `recovered` on any row the operator picks | the mismatch |
| Several receipts summing to the debt | one `recovered` after the last | intermediate state; each receipt's ref |
| Reversal AFTER `recovered`/`written_off` | `noop_replay` / `state_conflict` | a real receipt with nowhere to live |

**P1-5 `origin_ref → settlement.venue_id` names the absorbing venue, not the originating one.** §2.5: venue1's chargeback landed in venue1b's settlement (shipped 088:310-316 arm), so a "recovery source = originating venue" predicate built on the header would target venue1b — the exact silent cross-venue consumption G5 forbids (3000 of venue1b's revenue was already consumed inside that close). For `unlined_reversal` the header does not exist at all; the venue is reachable only via `origin_ref → dispute/refund → payment_native → order → event_session → event.venue_id`.

### P2
**P2-1 `p_command_key` is a no-op on both verbs** (§2.2): not stored, not audited, not part of the replay decision (replay is by origin / by terminal). A replayed resolve with a *different* reason is a silent `noop_replay`.
**P2-2 The `record` audit row carries no amount/currency/origin_ref in `after`** (094:408-410); the obligation row is the only place the magnitude lives, and it is deny-all to every role — an operator reading admin_audit alone sees "a debt was recorded" with no number.
**P2-3 Resolution-by-projection risk.** J7 §3 pitches `org_outstanding_obligation_minor` as the operand a future hold/offset needs; with P1-2 it over-counts and with P1-3 it double-counts against held payouts, so any consumer (Q5 hold, venue-scoped offset) inherits both before it is written.
**P2-4 `stripe_dispute_ref` partial UNIQUE spans both origins** (094:241-242): a `settlement_shortfall` never carries it (094:772 passes `null`), so the second idempotency key protects only `unlined_reversal`; fine, but the header's "second idempotency key for the webhook" framing overstates it — no webhook calls the record verb.

---

## 4. Options

### 4.1 Recovery facts (brief §3)
**(C) Mutate status only — status quo.** Cannot express partial, >debt, late receipt, source ref, or amount; ordering of receipts lost; `written_off` swallows later money. Dishonest for every row of the table in §3/P1-4 except full-manual-recovery-at-exact-amount. Not viable for G5's "deterministic and auditable".

**(B) Reuse `kernel.admin_audit` as the recovery ledger.** Append `org_obligation.recovery` rows with `after = {amount_minor, source_kind, source_ref}`. Pros: zero DDL, append-only already (077:247-249). Cons: `admin_audit.before/after` are free jsonb — no CHECK on amount, no UNIQUE on `(source_kind, source_ref)` (a retried `transfer.reversed` webhook writes two rows), no FK to the obligation, Σ requires parsing jsonb in a money predicate, and the actor column is `NOT NULL → auth.uid()` (a webhook-driven reversal has no uid; 095 uses the `…f1` sentinel). An audit trail is not a ledger; the same reasoning 094:26-40 gives for not using a mutable balance applies to not using an unconstrained log.

**(A) `kernel.organization_obligation_recovery` — append-only, one row per receipt.** Smallest honest shape:
```sql
create table kernel.organization_obligation_recovery (
  recovery_id    uuid primary key default gen_random_uuid(),
  obligation_id  uuid not null references kernel.organization_obligation(obligation_id) on delete restrict,
  amount_minor   integer not null check (amount_minor > 0),
  currency       text not null,                       -- must equal the obligation's (trigger)
  source_kind    text not null check (source_kind in ('transfer_reversal','manual','offset_settlement')),
  source_ref     text not null,                        -- trr_… | receipt/ticket ref | settlement_line id
  recorded_by    uuid references auth.users(id) on delete restrict,   -- NULL for a machine source
  command_key    text not null,
  created_at     timestamptz not null default now(),
  constraint obligation_recovery_source_uq unique (source_kind, source_ref),   -- the at-least-once key
  constraint obligation_recovery_command_uq unique (command_key)
);
-- BEFORE INSERT trigger, obligation row locked FOR UPDATE:
--   refuse if obligation.status = 'written_off'  (or: allow, and let it be the "late receipt" fact — owner call, see §5)
--   refuse if currency <> obligation.currency
--   refuse if amount_minor + Σ existing recoveries > obligation.amount_minor   ("recovery > debt" is unstorable)
-- BEFORE UPDATE/DELETE trigger: refuse (append-only, as 094:260-293).
```
`outstanding_minor(obligation) = amount_minor − Σ recoveries`. **`writeoff` is NOT a `source_kind`**: a write-off recovers nothing; it is a status act with an explicit remaining amount, which is exactly what the existing `written_off` terminal + `resolved_at` triple already record (remaining = amount − Σ recoveries at that instant, derivable). `offset_settlement` exists only if the owner later permits recovery by netting (Q3); it should be `?`-gated in the CHECK until then — do not add a member without a producer (094:206-208's own rule).

**Status: derived projection vs stored column.** Recommendation: keep the stored column (every reader, 160's 90 assertions, and the identity twin's shape depend on it) but make its *forward* transition to `recovered` a consequence, not an act: the recovery trigger sets `status='recovered', resolution_reason_code='recovered:'||source_kind, resolved_by, resolved_at` when Σ reaches `amount_minor`; a consistency trigger refuses any UPDATE that sets `status='recovered'` while Σ < amount (so `resolve_organization_obligation(…, 'recovered', …)` becomes either (i) removed, or (ii) sugar that INSERTs a `manual` recovery for the whole remainder and therefore needs `source_ref`). `written_off` stays an explicit platform act with the same authority check, allowed only while Σ < amount. A fully derived status (view) would be cleaner but breaks the `resolution_ck` pairing, the partial index, and 160 — larger blast radius for no additional honesty.

**What would be dishonest:** a mutable `recovered_minor` column on the obligation (the 094:26-40 argument, verbatim); letting `resolve(..,'recovered')` stay callable with no amount once recoveries exist; treating `written_off` as "no longer outstanding" for any money predicate (§4.3).

### 4.2 Reachability (P1-1) — orthogonal to 4.1, needed first
(i) Add `authenticated` EXECUTE to `resolve_organization_obligation` in a new migration (096) — matches the identity twin (`{authenticated,postgres}`) and 45 of 47 is_platform verbs; the body's `is_platform` check is the real gate. Cheapest, one GRANT. (ii) An `authenticated`-granted definer door on the `request_order_refund` pattern (H1 §5) — more code, no benefit here since the verb has no delegated arm. (iii) Custom-JWT minting in an edge — new trust surface; reject. Smallest honest: (i). Note 094:808-831 comment claims the tighter grant is a feature; it is a defect.

### 4.3 The 095 E-6 extension (brief §5)
The J5 §6 wording — "…or the obligation whose origin_ref is this line is no longer outstanding" — is wrong on two counts once §4.1(A) exists, and on one count already:
1. `written_off` is "no longer outstanding" but recovers nothing; the extension as phrased would release the held payout on a write-off. Must read `Σ recoveries`, never `status <> 'outstanding'`.
2. With partial recoveries, the discharged amount for a negative header must be `absorbed + recovered`, allocated per line. Honest per-line rule: `discharged(line) = min(|line|, absorbed_share + recovered_share)` where `absorbed = gross_of_header` and `recovered = Σ recoveries of the header's shortfall obligation`, allocated across the header's debit lines pro rata (or in line order — needs a stated rule). The simulated single-line case (§2.4) gives 0 exposure after full recovery, correct; with 2000 of 6000 recovered it should give 4000, which neither the current predicate (10000) nor the naive extension (0 or 10000) can produce.
3. Double-count (P1-3): while the covered payout is still unpaid the guard's hold and the obligation are the same loss. Two honest resolutions, owner's choice: (a) the shortfall branch does not book (or books `status='offset_pending'`… no — new state, rejected) when the header's covered payouts are all unpaid; or (b) book always, and make the exposure guard's discharge consume recoveries (so repaying the obligation releases the held payout) — which is (2) above and is arithmetically consistent, but turns the obligation into a payout operand, contradicting 094's "gates no payout" attestation (094:60-70). (a) keeps the attestation but needs a new predicate in the close (SSCAS #4, Q10 class). Neither is free; the report does not pick.

Chargebacks are outside E-6 entirely (it reads `kernel.refund`/`refund_void` only, 095:967-986); a lost dispute after close is neither held by maturity predicate 7 (`dispute_open` = false once lost) nor by E-6. For chargebacks the obligation is the *only* record, so P1-3's double-count does not arise there — but neither does any hold.

### 4.4 Venue scope (brief §4)
No stored `venue_id` on the obligation; `origin_ref` is the settlement (shortfall) or dispute/refund (unlined). Derivations:
- `settlement_shortfall` → `venue.settlement.venue_id` (NOT NULL) = **absorbing** venue — wrong under the shipped chargeback arm (§2.5).
- per debit line → `chargeback: dispute_native.payment_id → payment_native.order_id → order.event_session_id → event.venue_id`; `refund_void: refund.payment_id → …same` — all NOT NULL, always single-valued per line, and for `refund_void` always equal to the header's venue (scoped arm 093:519).
- `unlined_reversal` → the same chain from the dispute/refund.

Smallest honest predicate: **a STABLE definer `kernel.obligation_origin_venues(obligation_id) returns table(venue_id uuid, debit_minor bigint)`** over the debit lines of the origin header (or the single origin fact), plus a convenience `kernel.obligation_origin_venue(obligation_id) returns uuid` that returns the venue **only when every debit line and the header agree, else NULL** (fail closed: an ambiguous shortfall is never offset against anyone). A stored `venue_id` written from the header at booking is dishonest today (P1-5); a stored value is honest only after Q1 is ruled "venue-ring-fenced" and the chargeback arm gains the scope predicate — at which point header venue = origin venue by construction and the column can be added with a backfill from the function. Any future `offset_settlement` recovery must then require `settlement.venue_id = obligation_origin_venue(obligation_id)` and `settlement.org_id = obligation.org_id`.

### 4.5 Double-booking surface (brief §6)
- `settlement_shortfall`: `origin_ref = settlement_id`; a header closes once (`status<>'open'` → `noop_replay`, 094:576-580; 095 E-5 forward-only guard) and `origin_uq` makes the branch idempotent — executed (§2.6, rows = 1). A dispute produces at most one `chargeback` line ever (`NOT EXISTS` at 093:1195 + `settlement_line_cause_uq (settlement_id, cause, cause_ref)`), so two negative headers from one dispute cannot both carry it; a second negative header from *other* debits is a genuinely different shortfall. No webhook calls `record_organization_obligation` (grep: 0 callers), so at-least-once delivery reaches the table only through `dispute_native`, whose `stripe_dispute_ref` UNIQUE absorbs the retry.
- The real double-booking is cross-origin (P1-2), not same-origin.

---

## 5. Open questions for the orchestrator / owner
1. **P1-1 fix vehicle**: is a 096 `GRANT EXECUTE … TO authenticated` acceptable against 094's stated intent (094:794-797), or must the door be a wrapper? Either way it precedes any recovery design.
2. **P1-2**: which writer yields — should the chargeback arm skip disputes carrying an outstanding `unlined_reversal` (touches the "not 093's to change" arm), or should the shortfall branch net them out, or should `unlined_reversal` simply not exist until Q9 is ruled (it is inert today; deleting the enum member is cheaper than fixing its interaction)?
3. **P1-3 boundary**: is a shortfall whose covered payouts are all unpaid a debt at all? (Owner: "do not auto-collect… unless required to close a lifecycle defect".) Options 4.3(a)/(b).
4. **Late receipt after `written_off`**: refuse (terminal is terminal) or allow as a recovery row that reopens nothing but records the money (`written_off` + Σ>0)? Accounting says record it; 094's forward-only guard says refuse.
5. **`offset_settlement` as a source_kind**: only if Q3 (recovery by netting) is ruled yes; if yes, venue-scoped per 4.4 and it must replace, not add to, the chargeback arm's cross-venue landing (Q1).
6. **Allocation rule for the E-6 extension** when a negative header has several `refund_void` lines and one shortfall obligation: pro rata vs line order — needs a stated rule before the predicate is written.
7. **Transfer-reversal linkage**: a `transfer.reversed` webhook on a paid settlement payout should produce a `transfer_reversal` recovery row against *which* obligation? The payout's settlement is the *credit* side (sB1), the obligation is on the *later* header (sB2); the link is `payout.payee_org_id = obligation.org_id` + operator choice, unless the executor is told the obligation_id when it initiates the reversal (the J2 §7.2 caller does not exist yet). Also: partial reversal of a paid transfer remains unrepresentable on `kernel.payout` (J5 §8) — the recovery row would be the only record of it.
8. Ratification row for 094 itself (J3 §5-bis.4 / J7 §9) is still absent; everything above is a further amendment on an unratified object.
