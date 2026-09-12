-- @generated-by: scripts/assemble_093.sh
-- =============================================================================
-- !!  GENERATED FILE — DO NOT EDIT BY HAND  !!
--
-- Assembled from the reviewed slices in docs/phase2/_impl/093_parts/.
-- THE SLICES ARE CANONICAL. This file is a build artifact.
--
-- To change anything below:
--   1. edit the slice under docs/phase2/_impl/093_parts/
--   2. run ./scripts/assemble_093.sh
--   3. commit the slice AND this regenerated file together
--
-- A hand-edit here is reverted by the next assembler run and is REJECTED BY CI:
-- the "Migrations guard / Immutability + ordering" job regenerates this file
-- from the committed slices and compares it byte-for-byte
-- (scripts/ci/assembled_migration_integrity.sh).
-- =============================================================================
-- =============================================================================
-- 093_primary_ticketing.sql
--
-- Venue-direct primary ticketing: the database half.
--
-- AUTHORITY. Every object below implements a ruling ratified by the owner on
-- 2026-09-02 and recorded in docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md.
-- The evidence behind those rulings is in docs/phase2/_rulings/ and the scope
-- derivation is docs/phase2/093_FINAL_PROPOSED_SCOPE.md. Nothing here was
-- invented at the keyboard.
--
-- WHAT THIS MIGRATION IS NOT. It does not activate anything. Every Phase-2 rail
-- stays dark, every feature flag stays off, and no money can move when it lands:
-- there is still no payout executor, and the buyer-side fee key and the ticket
-- expiry grace both ship with NULL values that the owner must set before
-- issuance is switched on. Applying this file changes what the system CAN be
-- configured to do, not what it does.
--
-- SHAPE. 0 new tables. 0 new enum members. 0 new policies beyond two policy
-- REPLACEMENTS that add a missing authority conjunct.
--
-- COLUMNS: 4 added, all additive. Three on kernel.organization
-- (connect_transfers_active, connect_state_synced_at, connect_pending_ref) and
-- ONE ON A MONEY-LEDGER TABLE: kernel.payout.destination_ref.
--
-- That last one is a deliberate exception to this migration's original "0 DDL on
-- any money-ledger table" rule, and it is called out here rather than buried
-- because that rule was load-bearing. It exists because a proved replacement
-- race showed kernel.payout had NO destination column at all: an organization's
-- payout destination could be re-pointed while a payout sat in `submitted`, and
-- the transfer would follow the new account with no predicate anywhere refusing
-- it. Recording the authorized destination on the payout row at pending->submitted
-- is what makes the money's destination a property of the approval rather than of
-- whatever the organization happens to point at when the worker runs.
--
-- ORDERING CONSTRAINT that travels with it: destination_ref must exist before
-- payout.dual_control_min_minor is ever given a value. That key is seeded NULL,
-- so X-12 currently parks every payout and the approval row is the only thing
-- pinning a destination. Setting the threshold is what creates the exposure.
--
-- MIGRATIONS 076-092 ARE IMMUTABLE and are not touched. Every behaviour change
-- to an existing function is a CREATE OR REPLACE of its body at its exact
-- existing signature.
--
-- ONE LOCK MATTERS: the ALTERs on public.payments. That table holds ~56
-- production rows and the change is catalogue-only, but the statement takes an
-- ACCESS EXCLUSIVE lock and therefore runs under an explicit lock_timeout.
--
-- ASSEMBLED by scripts/assemble_093.sh from docs/phase2/_impl/093_parts/.
-- Edit the parts, not this file, then re-run the assembler.
-- =============================================================================



-- ###########################################################################
-- ## SLICE: 10_money_settlement.sql
-- ###########################################################################

-- ============================================================================
-- 093 PART 10 — MONEY AND SETTLEMENT.
--   FRAGMENT, not a migration: no `begin;` / `commit;` here — 093 wraps the
--   assembled parts in ONE transaction, exactly as 087/090 do. Assemble AFTER any
--   part that touches public.payments (scope item 1) and BEFORE the test part.
--
--   Frozen sources: R2 (docs/phase2/_impl/R2_settlement_economic_owner.md) ·
--     PRIMARY_TICKETING_OWNER_RATIFICATION A3/A4/A5 · 093_FINAL_PROPOSED_SCOPE
--     items 11-14 · schema §3.13/§3.14/§3.14.1 · RPC §10.1/§10.2/§20.11.1 ·
--     RLS §9.13/§9.14 · E-73 (sign convention) · E-76 (current operator) ·
--     E-104 (per-org seam lock) · E-128/E-138 (commission hold) · AUTHZ-C1C.
--
--   WHAT THIS PART CONTAINS, AND WHICH RULING PUTS IT HERE
--   ------------------------------------------------------------------------
--   10a  venue.open_settlement           body-only  — A3 (the booked-event fix;
--                                                      R2 §5.1 Edit 1 + Edit 2)
--   10b  kernel.settlement_primary_lines NEW fn     — A5 (face-value entitlement)
--                                                      + A3 (payee = settlement org)
--   10c  two partial unique indexes      new index  — A5 / scope item 13
--   10d  kernel.close_settlement         body-only  — A5 / scope item 12
--                                                      (three-seam union + the
--                                                       NAMED on-conflict target)
--   10e  kernel.settlement_commission_lines body-only — A4 (no commission on
--                                                      revenue that was refunded;
--                                                      releases NOTHING)
--   10f  two settlement RLS policies     replaced   — A3 / R2 §6 (E-76 conjunct)
--   10g  kernel.get_refund_execution_context NEW fn — A2 / E4 §3 (the executor's
--                                                      missing refund → Stripe
--                                                      binding; service_role only)
--   10i  kernel.claim_refunds_for_execution NEW fn — D3 / E4 §3 (the executor's
--                                                      missing WORK LIST — a
--                                                      LEASED CLAIM, not a list;
--                                                      service_role only)
--   10h  kernel.settlement_royalty_lines  body-only  — A5 (the chargeback arm
--                                                      double-debited refunded
--                                                      money and charged the
--                                                      platform's own fee to the
--                                                      venue); royalty arm verbatim
--
--   OWNER STOP RAISED BY THIS PART. 10d refuses to release organization money
--   unless EVERY maturity predicate is proven (G2 —
--   docs/phase2/_impl/G2_settlement_maturity.md): the policy value is set, the
--   covered set resolves, no covered event is cancelled, the last covered
--   session's ends_at is known and has elapsed by the interval, no refund on a
--   covered payment is in flight, and no dispute on one is open. The DURATION is
--   still owner policy and 093 invents none — but the ANCHOR INSTANT is no longer
--   an open question: it is max(event_session.ends_at) over the settlement's own
--   lines, and it is derived, not configured. The key row is NOT created here —
--   it belongs with the other config rows in slice 40, seeded 'null'::jsonb /
--   'restricted' in the retention.backup_window_days pattern, and it is now
--   spelled 'payout.settlement_maturity_interval' (see 10d for why the old
--   'settlement.refund_window_interval' spelling was a lie AND a dual-control
--   bypass).
--
--   TEST DELTAS THIS PART CREATES (for the author of 093's test section — every
--   one of these was checked against the shipped pgTAP suite, not assumed):
--     * 151 C2b (151:215-216) and C2c (151:219-220) stay GREEN unchanged — see 10a.
--     * 151 C40b (151:541-542) FLIPS P0002 → 42501 and MUST be amended. After the
--       operatorship transfer the caller holds only a stale venue_finance grant, so
--       10a's E-76 conjunct now refuses at the AUTHORITY gate before the scope gate
--       is reached. The refusal is stronger and discloses nothing new (the caller
--       already holds a role on that venue), but the expected errcode changes.
--     * 151 A5/A6 (151:48-55) and B7 (151:127-129) enumerate the seams BY NAME and
--       therefore still pass, but they should be extended to cover the third seam.
--     * 155 A13 (155:184-191) counts the frozen SEAM register at 19 by name;
--       settlement_primary_lines is deliberately NOT a SEAM-2a hook, so it stays 19.
--     * 151's money assertions are unaffected: 151 creates NO kernel.payment_native
--       row, so the primary seam emits nothing there. 153 and 155 DO finalize paid
--       orders, so their closes now carry primary_sale gross where they previously
--       carried none — that is the activation this migration exists for, and those
--       expectations must be recomputed rather than suppressed.
--
--   NOT IN THIS PART, DELIBERATELY: no new table, no new enum member, no new
--   column, no DDL on venue.settlement / venue.settlement_line / kernel.payout /
--   kernel.refund, no change to venue.finalize_primary_order, and no release of
--   any held payout (A4: "nothing in 093 may accidentally release promoter
--   money"). Every REPLACED function below is a CREATE OR REPLACE at its EXACT
--   frozen signature, keeping security definer, `set search_path = ''`, language
--   and volatility. There are exactly TWO new objects, and both revoke the default
--   PUBLIC EXECUTE first (076 discipline): 10b is definer-internal and granted to
--   nobody (087 PART 8's seam treatment), 10g is granted to service_role ONLY.
--
--   ONE CLASS OF CHANGE RUNS THROUGH BOTH MONEY ITEMS AND IS WORTH STATING ONCE:
--   venue.settlement_line has no UPDATE and no DELETE (087:110-112), so a wrong
--   line is wrong forever. Every rule in 10b therefore books a line only for a
--   fact that can no longer change — see the terminal-state discussion there.
-- ============================================================================


-- ============================================================================
-- 10a — venue.open_settlement (087:227-269) — BODY ONLY. Ruling A3.
--
--   THE BUG (R2 §3.2, §5.1): 087:254 and 087:257-259 are a CONJUNCTION. The
--   header required BOTH venue ∈ p_org_id AND event ∈ p_org_id. Those two facts
--   are the same fact only while catalog.venue.org_id = catalog.event.org_id, and
--   catalog.update_venue (078:688-702) repoints the venue's org with NO cascade to
--   events already stamped. After such a transfer NEITHER org can open an
--   event-scoped settlement — the old org fails 254, the new org fails 258 — and
--   the state is terminal because catalog.event.org_id is unwritable by every RPC
--   (078:943-950). The affected events become permanently unsettleable.
--
--   WHY THE EVENT WINS (R2 §4): the deterministic venue-side economic counterparty
--   is catalog.event.org_id. It is NOT NULL (078:137), server-derived exactly once
--   (078:877-881), never updated, and it is the root of the seller chain that
--   venue."order".org_id (082:369-372) and kernel.tickets.org_id (085:2047) are
--   copied from. Every live settlement seam already joins on it — 088:341,
--   088:357, 090:1527 — and the payout is minted to settlement.org_id and never
--   re-resolved (087:341-343). catalog.venue.org_id is the operator of the ROOM,
--   it is mutable, and NO seam joins on it: a header carrying it matches zero
--   lines and closes at net = 0.
--
--   THE FIX IS A REMOVAL, NOT A REWRITE. The event conjunct was already exactly
--   right; 087:257-259 is reproduced below byte-identical. What goes is the
--   venue ∈ org requirement at the EVENT grain — the venue check degrades to
--   EXISTENCE. The PERIOD grain keeps 087:254-255 verbatim and FAILS CLOSED: a
--   venue+period window can span events sold by several orgs, so it has no unique
--   economic counterparty, and the ruling says any ambiguity fails closed.
--   Widening the period grain is a separate owner decision and is NOT taken here.
--
--   E-76 ON THE AUTHORITY ARM (R2 §5.1 Edit 1). Once the scope stops requiring
--   venue ∈ org, a ROOM's venue_finance could otherwise open a header PAYABLE TO
--   A DIFFERENT ORG. The venue arm is therefore conjoined with the current-operator
--   clause in the identical shape kernel.close_settlement already uses at
--   087:299-300. The promoter travels the org arm, which is correct: the selling
--   org's own finance opens the selling org's own settlement.
--
--   ORDERING NOTE (authority BEFORE scope, unchanged from 087). Because the E-76
--   conjunct joins the AUTHORITY gate, a stale venue_finance holder over a
--   transferred room is now refused with 42501 where 087 refused with P0002 after
--   falling through to the scope gate — 151 C40b's expected code changes. The
--   order is NOT inverted to preserve the old code: raising not_found before
--   proving authority would hand an unauthorized caller the venue/event binding,
--   which is the exact disclosure AUTHZ-C1C exists to prevent.
--
--   Every raise keeps errcode P0002 / 'not_found' — never insufficient_privilege
--   (AUTHZ-C1C, 087:222-224: the caller must not learn the venue exists).
--   Everything else in this body — the command-key regex, the C16 advisory lock,
--   the audit-row replay, the idempotency-conflict arm, the INSERT and the audit
--   write — is reproduced unchanged.
-- ============================================================================
create or replace function venue.open_settlement(
  p_org_id uuid, p_venue_id uuid, p_event_id uuid, p_period jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-] (it lands in the immutable audit)';
  end if;
  -- E-76: the venue arm is the ROOM's authority, so it may only open a header
  -- payable to the room's CURRENT operator. Same shape as 087:299-300.
  if not ((kernel.has_venue_role(p_venue_id, array['venue_finance'])
           and (select v.org_id from catalog.venue v where v.venue_id = p_venue_id) = p_org_id)
          or kernel.has_org_role(p_org_id, array['org_finance','org_owner'])) then
    raise exception 'insufficient_privilege: venue_finance or org_finance/org_owner required' using errcode = '42501';
  end if;
  -- C16 replay: the same actor + key returns the header it already opened.
  perform pg_advisory_xact_lock(hashtext('settlement.open:' || v_uid::text || ':' || p_command_key));
  select a.subject_id into v_id from kernel.admin_audit a
   where a.action = 'settlement.open' and a.actor_identity = v_uid and a.reason_code = p_command_key
   order by a.occurred_at limit 1;
  if v_id is not null then
    if not exists (select 1 from venue.settlement s where s.settlement_id = v_id and s.org_id = p_org_id
                     and s.venue_id = p_venue_id and s.event_id is not distinct from p_event_id) then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    return jsonb_build_object('status','idempotency_replay','settlement_id', v_id);
  end if;
  -- SCOPE BINDING BY GRAIN (AUTHZ-C1C, ruling A3). The venue check is EXISTENCE
  -- only: the room is where the event happened, not who is owed for it.
  if not exists (select 1 from catalog.venue v where v.venue_id = p_venue_id) then
    raise exception 'not_found: venue %', p_venue_id using errcode = 'P0002';
  end if;
  if p_event_id is not null then
    -- EVENT GRAIN — deterministic. The event is the economic counterparty, so the
    -- header binds to catalog.event.org_id and to nothing else (087:257-259 verbatim).
    if not exists (select 1 from catalog.event e
         where e.event_id = p_event_id and e.venue_id = p_venue_id and e.org_id = p_org_id) then
      raise exception 'not_found: event % for venue % / org %', p_event_id, p_venue_id, p_org_id using errcode = 'P0002';
    end if;
  elsif not exists (select 1 from catalog.venue v where v.venue_id = p_venue_id and v.org_id = p_org_id) then
    -- PERIOD GRAIN — FAIL CLOSED (087:254-255 verbatim). A venue+period window has
    -- no unique economic counterparty, so only the room's current operator may
    -- open one. Otherwise the payee would be caller-chosen (test C2c, 151:219-220).
    raise exception 'not_found: venue % for org %', p_venue_id, p_org_id using errcode = 'P0002';
  end if;
  insert into venue.settlement (org_id, venue_id, event_id, period_start, period_end, status)
  values (p_org_id, p_venue_id, p_event_id,
          (p_period ->> 'period_start')::timestamptz, (p_period ->> 'period_end')::timestamptz, 'open')
  returning settlement_id into v_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (v_uid, 'settlement.open', 'settlement', v_id, p_command_key);
  return jsonb_build_object('status','ok','settlement_id', v_id);
end;
$$;


-- ============================================================================
-- 10b — kernel.settlement_primary_lines (NEW; SEAM-3). Rulings A5 + A3.
--
--   WHY IT EXISTS: until now the ONLY insert into venue.settlement_line (087:318)
--   is fed by two seams — 088:319 (market royalty / chargeback) and 090:1511
--   (promoter commission). NEITHER emits primary revenue, and
--   venue.finalize_primary_order writes no settlement, no line and no payout
--   (085:1881-2078). Gross is therefore structurally zero: no org payout is ever
--   minted and every promoter commission is a debit against nothing. This seam is
--   the credit side of the venue ledger.
--
--   AMOUNT = FACE VALUE (ruling A5). Venue entitlement BEGINS at the configured
--   ticket face value. venue."order".total_minor IS that face value and nothing
--   else: 082:424-426 states the identity in its own words — "order.total_minor =
--   Σ(order_item.unit_price × qty)" — written from ONE server-side price snapshot
--   per item (082:399-427), never from a client figure and never re-read. NO
--   platform fee is subtracted (A5: Snatch It revenue is buyer-funded, and no
--   percentage is invented anywhere in 093) and NO Stripe processing cost is
--   subtracted (A5: "processing cost is not silently subtracted from venue
--   face-value entitlement"; its allocation is the OPEN OWNER ITEM and is not
--   encoded here). public.payments.total may EXCEED order.total_minor — 085:1930
--   only requires the charge to COVER the order — and that excess is deliberately
--   not the venue's.
--
--   PAYEE = s.org_id, joined through the EVENT chain via o.org_id = s.org_id,
--   which is 088:357's idiom byte for byte. venue."order".org_id is stamped from
--   catalog.event.org_id (082:369-372) and no UPDATE anywhere writes it, so the
--   join is the seller chain, not a caller-chosen org (R2 §1.4, §4.1).
--
--   PAID-STATE FILTER. The eligible statuses are the MONEY-RECEIVED ones —
--   'paid', 'partially_refunded', 'refunded' — proven structurally by the
--   kernel.payment_native join, whose row is written by finalize_primary_order in
--   the same statement that sets status='paid' (085:2059-2061). 'pending' and
--   'cancelled' carry no money and are excluded. A fully 'refunded' order MUST
--   still emit its positive line: it was paid, its face value WAS credited, and the
--   refund arm below books the offsetting debit. Dropping the credit instead would
--   leave a naked negative line and drive the venue's net below zero.
--
--   REFUNDS ARE THEIR OWN NEGATIVE LINES (cause 'refund_void', cause_ref =
--   refund_id). venue.settlement_line is append-only (087:110-112 trigger), so the
--   original credit is NEVER amended — one line per kernel.refund row, forever.
--
--   ── THE APPEND-ONLY RULE: BOOK ONLY TERMINAL FACTS ──────────────────────────
--   kernel.refund runs pending → submitted → succeeded|failed (085:82-85), and
--   'failed' means Stripe ACCEPTED the refund and then could not settle it
--   (085:86-88) — THE BUYER GOT NOTHING BACK. Only 'succeeded' and 'failed' are
--   terminal.
--
--   An earlier draft of this seam booked the debit at `status <> 'failed'`,
--   copying 085:538-539's over-refund accounting. That was safe only while
--   'failed' was UNREACHABLE — nothing called kernel.mark_refund_state. The
--   refund executor built in this same train makes it reachable, so
--   pending → submitted → failed would book a NEGATIVE line for money that never
--   left, in a ledger with no UPDATE and no DELETE. The venue is debited, the
--   buyer is not paid, and neither can ever be made whole. That is the one class
--   of error an append-only ledger cannot survive, so the rule here is: A LINE IS
--   WRITTEN ONLY FOR A FACT THAT CAN NO LONGER CHANGE.
--
--   A compensating positive line is NOT the escape: 10c's
--   settlement_one_refund_void_line_ever is unique (cause_ref) where
--   cause = 'refund_void', so a second line for that refund is unstorable, and
--   reversing under a different cause ('admin_action') would fabricate an
--   administrative act that never happened. The fix must be to not write the line
--   in the first place.
--
--   TWO CHANGES, AND BOTH ARE LOAD-BEARING — one without the other just moves the
--   loss:
--     (i)  THE DEBIT ARM TAKES 'succeeded' ONLY. A refund that has not settled is
--          not yet an economic fact about the venue.
--     (ii) AN ORDER WITH A NON-TERMINAL REFUND IS DEFERRED ENTIRELY — no credit
--          and no debit, in scoped_order below.
--
--   WHY (ii) IS REQUIRED, CHECKED RATHER THAN ASSUMED. Booking 'succeeded' only
--   would otherwise let a settlement close and PAY the venue face value while a
--   refund for one of its orders is still in flight, and the platform would eat
--   the refund. Nothing in the corpus prevents that: kernel.close_settlement
--   (087:289-355) reads no refund state at all, and kernel.request_org_payout's
--   six preconditions (087:423-465 — settlement closed · pending payout · SoD-1
--   setter · money-grant maturity · AAL2 step-up · destination cool-down and
--   probation) touch kernel.refund NOWHERE. The R-40 gate that would have covered
--   this was explicitly deferred to 088 (087:406-407, E-67), and 088 never
--   replaced either function — verified: no `create or replace function` for
--   close_settlement or request_org_payout exists anywhere in 088-092. So the
--   gate does not exist and 093 must not assume it.
--     (ii) supplies it at the only grain that is safe: THE ORDER, not the
--   settlement. Blocking the whole close on one stuck refund would freeze a
--   venue's entire unrelated revenue behind a single in-flight refund; deferring
--   one order costs that order's face value until the refund resolves, and then
--   credit and debit are booked together in the same close, netting correctly.
--   Every intermediate state stays honest: in flight ⇒ NOTHING is asserted about
--   the order; succeeded ⇒ +face −settled_share; failed ⇒ +face and no debit,
--   which is exactly right because the buyer was not paid.
--
--   THE POST-CLOSE REFUND IS **NOT** A TOLERABLE RESIDUAL — CORRECTED. An earlier
--   revision of this comment excused it as "the same shape as the shipped
--   chargeback arm (088:311-316)". That comparison was wrong the moment 093
--   landed. Pre-093 gross was structurally ZERO, so the shape was INERT: no
--   organization payout was ever minted, so nothing could be overpaid. 093
--   activates the credit side AND mints the payout inside the close, which makes
--   "the refund succeeds after the settlement closed" the ORDINARY refund
--   timeline, not an edge case — and the debit then lands either in a settlement
--   nobody ever opens, or in one that nets negative and mints no payout, while the
--   money has already left. A negative net is NOT a receivable: this schema has no
--   carry-forward object. The deferral above covers only refunds that exist BEFORE
--   the close; nothing in a seam can cover one that begins after it. The gate for
--   that case is in 10d and it fails closed against a config key, because the
--   policy that would bound the exposure does not exist to be implemented.
--
--   DEBIT SENIORITY, so the two debit causes cannot double-count. An order's face
--   value is a single pool of headroom drawn down by BOTH debit causes —
--   'refund_void' here and 'chargeback' in 10h. Refunds are SENIOR: this arm
--   allocates first, and 10h's chargeback arm subtracts this order's settled
--   refund exposure before allocating its own. Both are the same money leaving for
--   the same buyer; the seniority only decides which cause label carries it, and
--   the pool caps the total either way.
--
--   THE FACE-VALUE CAP is a LEDGER IDENTITY, not an invented allocation: an order
--   was credited exactly total_minor, so the sum of its refund debits can never
--   exceed total_minor. The residual — a refund of the buyer-side service fee — is
--   platform money, and A5 forbids subtracting platform economics from the venue's
--   face-value entitlement. The system already defines a "full refund" against the
--   ORDER total, not the payment total (085:573), so this cap is the corpus's own
--   notion of exhaustion. The baseline schema states the same fact from the other
--   side: public.payments.total is "amount + buyer_fee (= what Stripe charges the
--   card)" (000_baseline_schema.sql:978-985), so a refund measured against the
--   PAYMENT can exceed the face value the venue was ever credited. The cap is
--   applied against refunds ALREADY LINED in any settlement (refund_prior), so it
--   holds across closes; the running window then allocates the remaining headroom
--   in a deterministic order (created_at, refund_id) that no later row can
--   disturb — and because only terminal 'succeeded' refunds are ever lined, no
--   allocation can be invalidated by a later state change.
--
--   MUST NOT RAISE (087:204-207): a raise inside a seam rolls back the entire
--   close. Hence NOT ONE `raise` in this body, and a currency filter
--   (o.currency = s.currency, r.currency = o.currency) that DROPS a mismatched row
--   instead of letting 087:314-316 raise on it — 088:346's idiom. A missing input
--   (unknown settlement, no payment link, no order in scope) RETURNS early and
--   empty. pg_advisory_xact_lock introduces no raise path either: it BLOCKS until
--   the key is free rather than failing, and it is re-entrant within the
--   transaction, so the two sibling seams taking the SAME key later in the same
--   union are no-ops rather than a self-deadlock.
--
--   VOLATILE + THE E-104 PER-ORG XACT ADVISORY LOCK — the same discipline as the
--   two shipped seams (088:321/333-336 royalty, 090:1513/1518 commission), and for
--   the same reason. A STABLE body would hold the caller's statement snapshot and
--   could not see a line committed by a sibling close of the same org that started
--   later; its NOT EXISTS dedupes would be best-effort and the loser of that race
--   would abort on 23505 — a safe failure, but an avoidable one, which is precisely
--   what E-104 exists to avoid. VOLATILE takes a FRESH snapshot after the wait, so
--   a sibling's committed line IS seen and the row simply drops out of the
--   candidate set. A third seam behaving differently under concurrency from the
--   other two is also exactly the asymmetry a later reader would assume away.
--
--   THE DEDUPES ARE AN OPTIMISATION; 10c's GLOBAL UNIQUE INDEXES ARE THE
--   GUARANTEE. The lock orders concurrent closes and nothing more — it does not
--   survive a crash, a second cluster, or a hand-written INSERT. The index is what
--   makes "one primary_sale line per order, platform-wide, for all time" a storage
--   fact, and 10d's NAMED on-conflict deliberately does not swallow a violation of
--   it: such a close aborts having written nothing, which is safe and retryable.
--   A silently dropped revenue line in an append-only ledger is not.
-- ============================================================================
create or replace function kernel.settlement_primary_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language plpgsql volatile security definer set search_path = ''
as $$
declare v_org uuid;
begin
  select st.org_id into v_org from venue.settlement st where st.settlement_id = p_settlement_id;
  if v_org is null then return; end if;   -- fail inert: unknown settlement ⇒ no rows, no raise
  -- E-104: serialize this org's candidate emission for the calling transaction
  -- (released at commit). After the wait every query below takes a fresh snapshot
  -- (VOLATILE), so a line committed by a sibling close is SEEN by the dedupes.
  perform pg_advisory_xact_lock(hashtext('settlement.seam.org:' || v_org::text));
  return query
  with s as (
    select st.settlement_id, st.org_id, st.venue_id, st.event_id,
           st.period_start, st.period_end, st.currency
      from venue.settlement st where st.settlement_id = p_settlement_id
  ),
  -- the settlement's orders: this org (the seller chain), this scope (event, or
  -- venue + period), money actually received, AND economically settled — an order
  -- carrying a refund that has not reached a terminal state is deferred WHOLE
  -- (neither arm sees it) until that refund succeeds or fails. Scope predicate is
  -- 088:347-351 / 090:1529-1533 verbatim in shape.
  scoped_order as (
    select o.order_id, o.total_minor::bigint as face_minor, o.currency, s.org_id
      from s
      join venue."order" o on o.org_id = s.org_id
      join kernel.payment_native pn on pn.order_id = o.order_id          -- money-received proof (085:2059)
      join catalog.event_session es on es.session_id = o.event_session_id
      join catalog.event e on e.event_id = es.event_id
     where o.status in ('paid','partially_refunded','refunded')
       and o.currency = s.currency
       and ((s.event_id is not null and e.event_id = s.event_id)
            or (s.event_id is null and e.venue_id = s.venue_id
                and (s.period_start is null or es.starts_at >= s.period_start)
                and (s.period_end is null or es.starts_at < s.period_end)))
       -- IN-FLIGHT REFUND ⇒ DEFER THE ORDER. Nothing gates the close or the payout
       -- on refund state (087:289-355 and 087:423-465 read kernel.refund nowhere;
       -- the R-40 gate was deferred to 088 at 087:406-407 and never authored), so
       -- without this the venue would be paid face value for an order that is
       -- about to be refunded. Deferring is per-ORDER, never per-settlement: one
       -- stuck refund must not freeze a venue's unrelated revenue.
       and not exists (select 1 from kernel.refund r0
                        where r0.payment_id = pn.payment_id
                          and r0.status in ('pending','submitted'))
  ),
  -- CREDIT ARM: +face value, one line per order, platform-wide once (10c).
  primary_sale as (
    select 'primary_sale'::text as cause, so.order_id as cause_ref,
           so.face_minor as amount_minor, so.currency,
           'organization'::text as payee_kind, so.org_id as payee_id
      from scoped_order so
     where not exists (select 1 from venue.settlement_line l
                        where l.cause = 'primary_sale' and l.cause_ref = so.order_id)
  ),
  -- EVERY debit already lined against this order, in ANY settlement, ever, under
  -- EITHER debit cause — the cap below is cumulative across closes AND across
  -- causes. 'refund_void'.cause_ref is a refund_id and 'chargeback'.cause_ref is a
  -- dispute_id; both resolve to the order through kernel.payment_native. Counting
  -- chargebacks here is what stops a dispute lined earlier from being charged to
  -- the venue a second time as a refund (the mirror of 10h's refund awareness).
  order_prior_debit as (
    select pn2.order_id, (-l.amount_minor)::bigint as debit_minor
      from venue.settlement_line l
      join kernel.refund r2 on r2.refund_id = l.cause_ref
      join kernel.payment_native pn2 on pn2.payment_id = r2.payment_id
     where l.cause = 'refund_void'
    union all
    select pn3.order_id, (-l.amount_minor)::bigint
      from venue.settlement_line l
      join kernel.dispute_native d3 on d3.dispute_id = l.cause_ref
      join kernel.payment_native pn3 on pn3.payment_id = d3.payment_id
     where l.cause = 'chargeback'
  ),
  refund_prior as (
    select opd.order_id, coalesce(sum(opd.debit_minor), 0)::bigint as prior_debit_minor
      from order_prior_debit opd
     where opd.order_id in (select so2.order_id from scoped_order so2)
     group by opd.order_id
  ),
  refund_candidate as (
    select so.order_id, so.face_minor, so.currency, so.org_id,
           r.refund_id, r.amount_minor::bigint as refund_minor, r.created_at,
           coalesce(rp.prior_debit_minor, 0) as prior_debit_minor
      from scoped_order so
      join kernel.payment_native pn on pn.order_id = so.order_id
      -- 'succeeded' ONLY — the sole state in which the buyer actually has the
      -- money back. 'failed' (085:86-88) means Stripe accepted and could not
      -- settle: booking it would debit the venue for a payment that never left,
      -- permanently, in an append-only ledger. 'pending'/'submitted' cannot appear
      -- here at all — scoped_order defers such orders whole.
      join kernel.refund r on r.payment_id = pn.payment_id and r.status = 'succeeded'
      left join refund_prior rp on rp.order_id = so.order_id
     where r.currency = so.currency
       and not exists (select 1 from venue.settlement_line l
                        where l.cause = 'refund_void' and l.cause_ref = r.refund_id)
  ),
  -- DEBIT ARM: the face-value share of each refund, capped so that Σ debits per
  -- order never exceeds the credit that order produced.
  refund_alloc as (
    select rc.refund_id, rc.currency, rc.org_id,
           greatest(
             0,
               least(rc.prior_debit_minor + sum(rc.refund_minor) over w, rc.face_minor)
             - least(rc.prior_debit_minor + sum(rc.refund_minor) over w - rc.refund_minor, rc.face_minor)
           )::bigint as debit_minor
      from refund_candidate rc
    window w as (partition by rc.order_id order by rc.created_at, rc.refund_id
                 rows between unbounded preceding and current row)
  ),
  refund_void as (
    select 'refund_void'::text as cause, ra.refund_id as cause_ref,
           (-ra.debit_minor)::bigint as amount_minor, ra.currency,
           'organization'::text as payee_kind, ra.org_id as payee_id
      from refund_alloc ra
     where ra.debit_minor > 0        -- a zero-value line carries no fact; emit nothing
  )
  select * from primary_sale
  union all
  select * from refund_void
  order by 1, 2;
end;
$$;

-- Grants (087 PART 8 discipline): the seams are DEFINER-INTERNAL — close_settlement
-- reaches this as owner. Revoke the default PUBLIC EXECUTE; grant to nobody.
revoke all on function kernel.settlement_primary_lines(uuid) from public, anon, authenticated, service_role;


-- ============================================================================
-- 10c — TWO PARTIAL UNIQUE INDEXES (scope item 13). Ruling A5.
--
--   087:105's uniqueness is PER SETTLEMENT — unique (settlement_id, cause,
--   cause_ref) — so the same order can be lined in two different settlements and
--   paid twice, and settlement_line is append-only (087:110-112): the bad line can
--   never be deleted. These are the cross-settlement money constraints, in the
--   exact shape of the promoter one at 090:214-215 (schema §3.14.1).
--
--   They are the STRUCTURAL guarantee behind every seam's NOT EXISTS dedupe. The
--   E-104 advisory lock orders concurrent closes; only the index survives a crash,
--   a second cluster or a hand-written INSERT. That is also why 10d must NAME its
--   on-conflict target: a bare DO NOTHING would tolerate a violation of THESE
--   indexes and silently drop an already-lined order out of gross, underpaying the
--   venue in a ledger that has no delete.
--
--   CREATE INDEX (not CONCURRENTLY): 093 is one transaction, and these tables are
--   empty in production — the only writer is 087:318 and no seam has ever emitted
--   either cause.
-- ============================================================================
create unique index if not exists settlement_one_primary_sale_line_ever
  on venue.settlement_line (cause_ref) where cause = 'primary_sale';
create unique index if not exists settlement_one_refund_void_line_ever
  on venue.settlement_line (cause_ref) where cause = 'refund_void';


-- ============================================================================
-- 10d — kernel.close_settlement (087:289-355) — BODY ONLY. Ruling A5 / scope 12.
--
--   FOUR CHANGES, NOTHING ELSE. (1) and (4) were the original scope; (2) and (3)
--   close two P0s the red team executed on a real replay.
--
--   (1) THREE SEAMS, NOT TWO. kernel.settlement_primary_lines is unioned first so
--       the ledger's credit side exists before the debits that net against it. The
--       union is one statement, exactly as 087:311-312. All THREE seams are now
--       VOLATILE and take the SAME E-104 per-org key, so concurrent same-org closes
--       serialize around this statement and each seam reads a post-wait snapshot;
--       the key is re-entrant, so the second and third acquisitions are no-ops.
--
--   (2) THE ON-CONFLICT TARGET IS NAMED (087:320). The old inferred arbiter
--       `on conflict (settlement_id, cause, cause_ref)` resolves to
--       settlement_line_cause_uq today, but it is INFERENCE: once 10c's global
--       indexes exist, a cross-settlement duplicate raises 23505 and aborts the
--       close. Naming the constraint keeps EXACTLY the old tolerance — a re-close
--       replaying its own lines — and refuses to swallow anything else. A bare
--       `do nothing` is FORBIDDEN: it would absorb a 10c violation and drop a
--       revenue line out of gross with no error and no way to repair the ledger.
--       An aborted close writes nothing and can be retried; a lost credit cannot.
--
--   (2) THE PAYOUT IS MINTED HELD UNLESS EVERY MATURITY PREDICATE HOLDS — the
--       fix for the post-close refund, and for the far worse defect that the
--       first cut of that fix introduced. That cut released on
--       `config IS NOT NULL` alone, which made an owner config value a hidden
--       feature flag for payout logic nobody had written. The release condition
--       is now a CONJUNCTION over seven predicates with distinct
--       hold_reason_codes. The full argument is at the call site below.
--
--   (3) THE INT4 CEILING RAISES A NAMED REFUSAL instead of a bare 22003 that
--       wedged the header open with zero lines forever. Also at the call site.
--
--   PRESERVED VERBATIM: the FOR UPDATE header read, the E-76 authority arm
--   (087:299-302), the noop_replay arm, the per-candidate currency raise, the
--   whole-settlement currency check, the E-73 waterfall derivation (087:329-333,
--   byte for byte), the write-once money UPDATE, the net > 0 mint condition and
--   its idempotency_key, and the net_minor READ-BACK (§10.2 R1-2). The audit row
--   keeps its actor / action / subject / reason_code and GAINS `after` (additive).
--   RULING A4 IS UNTOUCHED, AND THE GATE ONLY STRENGTHENS IT: the ONLY payout row
--   this function touches is the one it INSERTs itself — cause='settlement',
--   payee_kind='organization', a single INSERT with no UPDATE and no DELETE
--   anywhere in the body. It reads no promoter row, writes no promoter_commission
--   payout, calls no release verb, and every change in this revision can only move
--   a payout from unheld to HELD. A promoter commission is minted
--   'held'/'unfunded_settlement' by kernel.pay_promoter_commission (090:1487-1491)
--   and is released ONLY by kernel.release_payout (085:807, platform_risk /
--   platform_admin, Control-5); neither verb is named here.
-- ============================================================================
create or replace function kernel.close_settlement(p_settlement_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_s venue.settlement%rowtype; v_c kernel.settlement_line_candidate;
  v_gross bigint; v_fees bigint; v_refunds bigint; v_net bigint;
  v_payout_id uuid; v_ids uuid[] := '{}';
  -- G2 payout-maturity operands. THE CONJUNCTION ITSELF NOW LIVES IN
  -- kernel.settlement_payout_maturity (10m) and is called from THREE sites: here
  -- at the mint, in kernel.request_org_payout immediately before the
  -- pending→submitted advance (10k), and in kernel.get_payout_execution_context
  -- immediately before the transfer (10n). It was extracted (D-1) for exactly
  -- one reason: inline, it was a CLOSE-TIME SNAPSHOT that four later state
  -- changes defeat — a refund reaching 'succeeded' after the close;
  -- catalog.cancel_event, which touches kernel.payout NOWHERE; a dispute first
  -- observed already 'lost' (record_dispute_native freezes only on an OPEN
  -- dispute, 088:804, so the freeze is inverted relative to risk); and Connect
  -- capability loss. request_org_payout re-derived NONE of the eight predicates.
  -- One definition, three call sites, so the evaluations cannot drift. The
  -- operands themselves, and their fail-toward-the-hold initialisation, moved
  -- wholesale into 10m — nothing about the gate's meaning changed here.
  v_held boolean := false; v_hold_reason text; v_hold_detail jsonb;
  v_maturity_verdict jsonb;
begin
  select * into v_s from venue.settlement where settlement_id = p_settlement_id for update;   -- SSCAS #4 rank-6
  if not found then raise exception 'not_found: settlement %', p_settlement_id using errcode = 'P0002'; end if;
  if not ((kernel.has_venue_role(v_s.venue_id, array['venue_finance'])
           and (select v.org_id from catalog.venue v where v.venue_id = v_s.venue_id) = v_s.org_id)   -- E-76: current operator
          or kernel.has_org_role(v_s.org_id, array['org_finance'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege: venue_finance / org_finance / platform only' using errcode = '42501';
  end if;
  if v_s.status <> 'open' then   -- forward-only: a re-close is an idempotent replay
    return jsonb_build_object('status','noop_replay','net_minor', v_s.net_minor,
      'payout_ids', (select coalesce(array_agg(payout_id),'{}') from kernel.payout
                      where cause='settlement' and cause_ref=p_settlement_id));
  end if;
  -- generate the money lines from the THREE seams: primary revenue (093/10b),
  -- royalty + chargeback (088:319), promoter commission (090:1511).
  for v_c in select * from kernel.settlement_primary_lines(p_settlement_id)
             union all select * from kernel.settlement_royalty_lines(p_settlement_id)
             union all select * from kernel.settlement_commission_lines(p_settlement_id) loop
    if v_c.cause is not null then
      if v_c.currency is not null and v_c.currency <> v_s.currency then
        raise exception 'precondition_failed: candidate currency % differs from the settlement currency %', v_c.currency, v_s.currency
          using errcode = 'P0001';
      end if;
      insert into venue.settlement_line (settlement_id, cause, cause_ref, amount_minor, currency)
      values (p_settlement_id, v_c.cause, v_c.cause_ref, v_c.amount_minor::integer, v_s.currency)
      -- NAMED, never bare: this tolerates ONLY a replay of this settlement's own
      -- line. A cross-settlement duplicate (10c) raises and aborts the close.
      on conflict on constraint settlement_line_cause_uq do nothing;
    end if;
  end loop;
  if exists (select 1 from venue.settlement_line l where l.settlement_id = p_settlement_id and l.currency <> v_s.currency) then
    raise exception 'precondition_failed: settlement lines carry a currency other than the header''s' using errcode = 'P0001';
  end if;
  -- one derivation from the lines this settlement holds, by the frozen SIGN
  -- convention (E-73): credits + / debits −; refund causes are the refund bucket.
  -- net = gross − fees − refunds = Σ all lines, exactly.
  select coalesce(sum(amount_minor)  filter (where amount_minor > 0 and cause not in ('refund_void','chargeback')), 0),
         coalesce(sum(-amount_minor) filter (where amount_minor < 0 and cause not in ('refund_void','chargeback')), 0),
         coalesce(sum(-amount_minor) filter (where cause in ('refund_void','chargeback')), 0)
    into v_gross, v_fees, v_refunds from venue.settlement_line where settlement_id = p_settlement_id;
  v_net := v_gross - v_fees - v_refunds;
  -- (3) INT4 CEILING, NAMED INSTEAD OF OPAQUE. The four money columns are integer
  -- (087:52-55, frozen) while these locals are bigint, so a settlement whose gross
  -- exceeds 2^31-1 minor units (~$21.47M) raised a bare 22003 out of the UPDATE
  -- below. That rolled the whole close back, leaving the header `open` with zero
  -- lines and EVERY retry failing identically — a permanently wedged settlement
  -- whose error names nothing. Refuse first, with the remedy in the message. This
  -- is 090:1471-1473's rule ("never an opaque 22003 out of the close") applied to
  -- the header. The ceiling itself is structural — widening the columns is DDL on
  -- a frozen money table and an owner item, NOT 093.
  if v_gross > 2147483647 or v_fees > 2147483647 or v_refunds > 2147483647
     or v_net > 2147483647 or v_net < -2147483648 then
    raise exception 'precondition_failed: settlement_amount_overflow — gross %, fees %, refunds %, net % exceed the int4 money columns (schema §3.13); settle this scope as narrower periods, or widen the columns (owner item)',
      v_gross, v_fees, v_refunds, v_net using errcode = 'P0001';
  end if;
  update venue.settlement
     set status='closed', gross_minor=v_gross::integer, fees_minor=v_fees::integer,
         refunds_minor=v_refunds::integer, net_minor=v_net::integer, updated_at=now()
   where settlement_id = p_settlement_id;
  -- generate the pending payout only when there is positive net (kernel.payout
  -- amount_minor > 0). Deterministic idempotency on (cause, cause_ref, payee).
  if v_net > 0 then
    -- (2) THE PAYOUT-MATURITY GATE (G2 — docs/phase2/_impl/G2_settlement_maturity.md).
    -- A refund that succeeds AFTER this close cannot be collected: its debit lands
    -- in a settlement nobody opens, or in one that nets negative — and a negative
    -- net mints no payout and creates no receivable, because this schema has no
    -- carry-forward object. The payout is therefore MINTED (so the obligation is a
    -- durable ledger fact — ruling A3: the debt must be knowable without
    -- reconstructing it from Stripe) but minted HELD unless EVERY predicate below
    -- is satisfied, so no money can move on a partial proof.
    --
    -- ── WHAT THIS REPLACES, AND WHY ──────────────────────────────────────────
    -- The first cut of this gate was `v_held := v_refund_window is null` — the
    -- ONLY predicate was "is the config key set". Setting the key to any value
    -- released every payout immediately, with no maturity semantics implemented
    -- anywhere: an owner config value was a hidden feature flag for logic that did
    -- not exist, and the slice's own comment had to warn that SETTING the key was
    -- the dangerous act. That is inverted here. The key is now ONE CONJUNCT of a
    -- gate that also has to prove the event happened, that it happened long enough
    -- ago, and that no money is still in motion against the orders being paid for.
    --
    -- ── THE PREDICATES, ALL OF WHICH MUST HOLD TO RELEASE ────────────────────
    --   1. the maturity policy VALUE is set and non-negative;
    --   2. every money line in this settlement resolves to its payment AND its
    --      session — we must know what this money is about before we can time it;
    --   3. no covered session and no covered event is cancelled;
    --   4. the maturity INSTANT is known: at least one covered session, and every
    --      covered session carries ends_at;
    --   5. that instant plus the policy interval has ELAPSED;
    --   6. no refund against any covered payment is in a non-terminal state;
    --   7. no dispute against any covered payment is open.
    -- Any single failure holds, with its own hold_reason_code. An operand that
    -- cannot be computed is NOT assumed satisfied: all seven locals are declared
    -- pre-set to the value that holds.
    --
    -- ── WHY ends_at OF THE LAST COVERED SESSION IS THE ANCHOR ────────────────
    -- The buyer's own chargeback clock starts THERE, not at payment: Stripe states
    -- it in terms of this exact industry — "when a customer pays for a future
    -- event or service (like a vacation reservation, professional services
    -- appointment, or event ticket), the dispute window starts on the event date,
    -- not the payment date" (https://docs.stripe.com/disputes/how-disputes-work).
    -- Anchoring on payment would make a ticket bought three months early payable
    -- three months before anyone could attend. catalog.event carries NO time
    -- column at all (078:134-154) — the only instants in the schema are on
    -- catalog.event_session — and venue."order".event_session_id is NOT NULL
    -- (082:369-372), so every covered order resolves to exactly one session. That
    -- makes the anchor computable for BOTH settlement grains: event-scoped and
    -- period-scoped headers alike derive it from their OWN LINES rather than from
    -- the header's scope, so a period settlement is timed by the last session it
    -- actually paid for and not by period_end (which is nullable, bounds
    -- starts_at rather than ends_at, and can be open-ended).
    --
    -- ends_at IS NULLABLE (078:170) and catalog.create_event_session requires only
    -- starts_at (078:805-807). The corpus's ticket-expiry sweep meets the same
    -- fact and FAILS OPEN — it skips such sessions (079:490-492), which slice 40
    -- already records as an unfixed schema hole. This gate fails CLOSED on it: a
    -- session with no end has not verifiably ended, so its money does not mature.
    -- Session STATUS is deliberately not used: nothing in 076-092 ever writes
    -- event_session.status = 'completed' (the only writer of that column is
    -- 088:1793, which writes 'cancelled'), so requiring it would hold every payout
    -- forever.
    --
    -- WHY HELD RATHER THAN REFUSING THE CLOSE OR MINTING NOTHING. Refusing the
    -- close would also refuse the LINES, so the ledger would never record what the
    -- venue is owed — the opposite of A3. Minting nothing would strand the payout
    -- permanently, because close_settlement is the only minter of a
    -- cause='settlement' payout and it is forward-only (a re-close returns
    -- noop_replay above), so no later run could ever create it. The hold overlay
    -- is the corpus's own answer to exactly this shape: 090:1487-1491 mints an
    -- unfunded promoter commission 'held'/'unfunded_settlement' for the same
    -- reason. A held payout cannot be requested (087:463-465 refuses
    -- hold_state <> 'none') and cannot be advanced by
    -- kernel.mark_payout_transfer_state; kernel.release_payout (085:807,
    -- platform_risk/platform_admin, Control-5) is the contracted release path once
    -- the owner rules. The hold is therefore recoverable; an overpayment is not.
    --
    -- ── THE KEY WAS RENAMED, BECAUSE THE OLD NAME WAS A LIE ──────────────────
    -- 'settlement.refund_window_interval' named a REFUND ELIGIBILITY window — how
    -- long a buyer may still ask for money back. That policy exists, it is owned
    -- by an entirely different set of keys (refund.buyer_self_service_window_hours
    -- / refund.request_ttl_hours / refund.scanned_atom_policy, 078:1544-1551), and
    -- this value is not it. What this value actually is: HOW LONG AFTER THE EVENT
    -- THE VENUE'S MONEY MUST SIT STILL. It is a payout property, so it is spelled
    -- 'payout.settlement_maturity_interval' — and that prefix is load-bearing, not
    -- cosmetic: 078:1145-1147 puts every 'payout.%' key under DUAL CONTROL, and
    -- the key carries no declared polarity, so EVERY set of it parks for a second
    -- platform_admin (078:1268-1285). Slice 40's own caveat on the old name was
    -- that "there is no second human in the way"; under the new name there is.
    --
    -- READ AS THE HOUSE PATTERN: absent row, JSON null and unparseable value all
    -- collapse to NULL and therefore to the hold (the 081:630-639 idiom).
    -- ONE CALL, AND THE OPERANDS ARE NO LONGER RE-DERIVED HERE. Everything the
    -- commentary above describes — the config read with its absent / JSON-null /
    -- unparseable collapse to NULL, the covered set derived from THIS
    -- settlement's own lines, the causal predicate order, the
    -- first-failing-predicate-wins rule and the full detail vector — is now
    -- kernel.settlement_payout_maturity (10m), verbatim. It never raises (a
    -- raise here would roll back the whole close and the ledger would never
    -- record what the venue is owed) and it fails toward the hold on every
    -- missing operand, exactly as this block did.
    v_maturity_verdict := kernel.settlement_payout_maturity(p_settlement_id);
    v_hold_reason := v_maturity_verdict ->> 'hold_reason';
    v_held        := v_hold_reason is not null;
    v_hold_detail := coalesce(v_maturity_verdict -> 'detail', '{}'::jsonb);
    insert into kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, currency, status, idempotency_key,
                               hold_state, hold_reason_code, held_by, held_at)
    values ('organization', v_s.org_id, 'settlement', p_settlement_id, v_net::integer, v_s.currency, 'pending',
            'settlement:' || p_settlement_id::text,
            case when v_held then 'held' else 'none' end,
            v_hold_reason,
            null,
            case when v_held then now() else null end)
    on conflict (idempotency_key) do nothing
    returning payout_id into v_payout_id;
    if v_payout_id is not null then v_ids := array[v_payout_id]; end if;
  end if;
  -- the audit row gains `after` — ADDITIVE, and the only durable place an operator
  -- can read the WHOLE predicate vector rather than the one code that won.
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
  values (auth.uid(), 'settlement.close', 'settlement', p_settlement_id, coalesce(p_command_key,'close'),
          jsonb_build_object('payout_hold', v_hold_reason, 'hold_predicates', v_hold_detail));
  -- net_minor is a READ-BACK of the column this function wrote (§10.2 R1-2), never a local.
  -- 'payout_hold' is ADDITIVE — every contracted key (status, payout_ids,
  -- net_minor) keeps its meaning; callers that do not read it are unaffected.
  -- 'payout_hold_detail' is additive in the same way and is NULL when nothing held.
  return jsonb_build_object('status','ok','payout_ids', v_ids,
           'net_minor', (select net_minor from venue.settlement where settlement_id = p_settlement_id),
           'payout_hold', v_hold_reason,
           'payout_hold_detail', case when v_held then v_hold_detail else null end);
end;
$$;


-- ============================================================================
-- 10e — kernel.settlement_commission_lines (090:1511-1548) — BODY ONLY.
--   Ruling A4 / scope item 14.
--
--   THE DEFECT: the eligible set excludes o.status in ('refunded','cancelled')
--   (090:1535) but NOT 'partially_refunded'. A DIRECT partial refund voids NO
--   atoms — 085:571-573 makes the void scope conditional on v_full, and a
--   direct-partial refund is "money only (voids nothing)" — so the commission
--   basis at 090:1461-1466, which counts SURVIVING atoms, is completely unreduced.
--   Result: FULL commission is paid on revenue that was partly refunded, and the
--   payout is minted before anyone notices. 093 is what activates this seam by
--   giving it revenue to deduct from, so the defect goes live with this migration.
--
--   THE FIX IS ONE LITERAL: 'partially_refunded' is added to the terminal-class
--   exclusion. It is an OVER-correction — the promoter earns nothing rather than a
--   reduced amount, and because an order never returns to 'paid' the exclusion is
--   permanent — and that is the deliberate direction: over-paying a promoter in an
--   append-only ledger is unrecoverable, over-correcting is reversible by an
--   owner-approved adjustment. A pro-rated basis would require an owner ruling on
--   how a partial refund maps onto ticket atoms; none exists, and 093 invents none.
--
--   RULING A4 IS NOT DISTURBED. This function still routes through
--   kernel.pay_promoter_commission, which mints every commission payout with
--   hold_state='held' and hold_reason_code='unfunded_settlement' (090:1487-1491).
--   Nothing here releases a hold, changes a hold reason, or adds an advance path.
--   The change can only ever REMOVE rows from the eligible set.
--
--   PRESERVED VERBATIM: signature, VOLATILE, the E-104 per-org advisory lock, the
--   scope predicate, the never-lined-before dedupe, the currency filter, the
--   payee-resolvable filter, the deny-decision filter, the pay_promoter_commission
--   call with its 'seam:' command key, and the negated return projection.
-- ============================================================================
create or replace function kernel.settlement_commission_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language plpgsql volatile security definer set search_path = ''
as $$
declare v_s venue.settlement%rowtype; v_ids uuid[]; v_res jsonb;
begin
  select * into v_s from venue.settlement st where st.settlement_id = p_settlement_id;
  if v_s.settlement_id is null then return; end if;
  perform pg_advisory_xact_lock(hashtext('settlement.seam.org:' || v_s.org_id::text));
  -- the eligible set: this org, this settlement's scope (event, or venue + period),
  -- never lined before (fresh snapshot after the lock — VOLATILE)
  select coalesce(array_agg(a.id order by a.order_paid_at, a.id), '{}') into v_ids
    from venue.attribution a
    join venue."order" o on o.order_id = a.order_id
    join catalog.event_session es on es.session_id = o.event_session_id
    join catalog.event e on e.event_id = a.event_id
   where a.org_id = v_s.org_id
     and ((v_s.event_id is not null and a.event_id = v_s.event_id)
          or (v_s.event_id is null and e.venue_id = v_s.venue_id
              and (v_s.period_start is null or es.starts_at >= v_s.period_start)
              and (v_s.period_end is null or es.starts_at < v_s.period_end)))
     and not exists (select 1 from venue.settlement_line l where l.cause = 'promoter_commission' and l.cause_ref = a.id)
     -- terminal classes are excluded HERE so a permanently-held attribution is not re-walked at every
     -- close under the settlement lock (red-team B5); pay_promoter_commission keeps its own defensive arms.
     -- 093/A4: 'partially_refunded' joins the exclusion — a direct partial refund voids no atoms
     -- (085:571-573), so the surviving-atom basis (090:1461-1466) is unreduced and FULL commission
     -- would be paid on partly refunded revenue. Excluding is the reversible error.
     and o.status not in ('refunded','partially_refunded','cancelled')
     and a.currency = v_s.currency
     and exists (select 1 from venue.promoter p where p.promoter_id = a.promoter_id and p.identity_id is not null)
     and coalesce((select r.decision from venue.attribution_review r where r.attribution_id = a.id order by r.seq desc limit 1), 'held') <> 'deny';
  if cardinality(v_ids) = 0 then return; end if;
  v_res := kernel.pay_promoter_commission(p_settlement_id, v_ids, 'seam:' || p_settlement_id::text);
  return query
    select 'promoter_commission'::text, (x ->> 'attribution_id')::uuid, -((x ->> 'amount_minor')::bigint), v_s.currency,
           'identity'::text, (x ->> 'payee_identity_id')::uuid
      from jsonb_array_elements(coalesce(v_res -> 'lines', '[]'::jsonb)) x
     order by 2;
end;
$$;


-- ============================================================================
-- 10f — THE TWO SETTLEMENT VENUE-ARM RLS POLICIES (087:82-84, 087:122-125).
--   Ruling A3 / R2 §6.
--
--   THE LEAK: both venue arms call kernel.has_venue_role bare. That predicate
--   probes venue.staff_role on (venue_id, auth.uid(), role) and NOTHING else
--   (080:60-73) — it knows neither who operates the room nor whose settlement this
--   is. These are the ONLY settlement surfaces in 087 without the E-76
--   current-operator conjunct their sibling verbs carry (087:299-300, 087:657,
--   087:1299, 087:1370, 087:1425-1428). With 10a in place, a promoter-owned
--   settlement at a foreign room becomes routine, and a ROOM's venue_manager or
--   venue_finance would read the PROMOTER's complete money picture: the header's
--   gross/fees/refunds/net (the grant at 087:75 is whole-table, so there is no
--   column-level backstop) and every signed line with its cause_ref — the
--   promoter's individual order_ids, sale_ids and dispute_ids, with amounts.
--
--   THE FIX: conjoin E-76 in the shape proven at 087:299-300 — the settlement's
--   venue's CURRENT operator org must equal the settlement's own org_id.
--
--   EFFECTS. A venue operator keeps full venue-arm visibility of its own
--   settlements at its own room: zero behaviour change on every state the shipped
--   write paths can create (R2 §3.1). A promoter's settlement at a foreign room
--   becomes invisible to that room's staff. A departing operator's stale staff
--   lose the venue arm over legacy settlements after a transfer — the intended
--   E-76 semantics. The true owner is unaffected: it reads through
--   venue_settlement_sel_org (087:78-81), which already keys on org_id.
--
--   NOT DONE HERE, deliberately: promoting E-76 into kernel.has_venue_role itself
--   (080:60-73) would close this class everywhere at once, but that predicate is
--   called from 15+ frozen sites across 078-090 and is a far larger blast radius
--   than 093 carries. Column-scoping the money columns is defence in depth and is
--   likewise out of scope. Both are recorded, not taken.
-- ============================================================================
drop policy if exists venue_settlement_sel_venue on venue.settlement;
create policy venue_settlement_sel_venue on venue.settlement for select to authenticated
  using (kernel.has_venue_role(venue_id, array['venue_manager','venue_finance'])
         and (select v.org_id from catalog.venue v where v.venue_id = venue.settlement.venue_id)
             = venue.settlement.org_id);   -- E-76: current operator

drop policy if exists venue_settlement_line_sel_venue on venue.settlement_line;
create policy venue_settlement_line_sel_venue on venue.settlement_line for select to authenticated
  using (exists (select 1 from venue.settlement s where s.settlement_id = venue.settlement_line.settlement_id
                  and kernel.has_venue_role(s.venue_id, array['venue_manager','venue_finance'])
                  and (select v.org_id from catalog.venue v where v.venue_id = s.venue_id) = s.org_id));   -- E-76


-- ============================================================================
-- 10g — kernel.get_refund_execution_context(p_refund_id uuid) — NEW.
--   Ruling A2 (payment collection and payout execution are separate concepts) ·
--   E4_refund_executor.md §3 · PFA-21 · X-6 / ruling F (no identity, no PII).
--
--   THE GAP IT CLOSES. service_role holds USAGE on kernel and NO table or DML
--   grants (085:2091-2096, PFA-21 verbatim: "No table/DML grants"), plus EXECUTE
--   on a named handful of functions. It therefore cannot SELECT kernel.refund or
--   kernel.payment_native. The only refund reader that exists,
--   kernel.list_org_refunds (085:1487), is authenticated-only, org-scoped, and
--   deliberately projects has_stripe_ref as a BOOLEAN (085:1512) rather than the
--   reference. So there is NO path from refund_id → payment_id →
--   stripe_payment_intent_id, and the refund executor cannot bind a refund to the
--   PaymentIntent it must call Stripe with. PFA-23 named the caller and never gave
--   it its read. The executor does not guess: it names this function and fails
--   closed with HTTP 501 when it is absent (supabase/functions/refund-execute/
--   index.ts:108, :211-222).
--
--   READ-ONLY, AND THAT IS STRUCTURAL. `language sql stable` — no state machine in
--   a reader. The refund's forward-only transitions stay where they are, in
--   kernel.mark_refund_state (085:1737); this function decides nothing.
--
--   IT RETURNS THE EXECUTOR'S OPERANDS AND NOTHING ELSE. Every key below is
--   consumed by planRefund (refund-execute/executor.ts:200-290): the binding
--   (payment_id, and the order_id/sale_id XOR the executor re-proves at :212-219),
--   the state (status, stripe_refund_ref), the money (amount_minor, currency,
--   payment_total_minor, payment_status), the Stripe handle (PaymentIntent +
--   livemode, which must be TRUE — a live key cannot see a test-era intent, and
--   NULL from migration 045 fails closed), and the two Σ-guard operands. NO buyer
--   identity: public.payments carries buyer_id and seller_id (000:973-975) and
--   NEITHER is projected. No ticket atom, no demographic field, no listing.
--
--   NON-ENUMERABLE. An unknown refund id yields zero rows, so the function returns
--   SQL NULL and the executor maps that to 404 refund_not_found (index.ts:223-226)
--   — never a partial object, never a distinguishable shape. The join to
--   public.payments cannot itself drop a row (kernel.refund.payment_id is NOT NULL
--   with an ON DELETE RESTRICT FK, 085:76), so NULL means exactly one thing: no
--   such refund.
--
--   ONE DELIBERATE DEVIATION FROM E4 §3, and it makes the failure louder. §3 joins
--   kernel.payment_native with an INNER join; that collapses "this refund does not
--   exist" and "this refund exists but its payment has no native link" into the
--   same NULL, and the second is a data-integrity fault, not a missing row. LEFT
--   JOIN keeps NULL meaning "no such refund" and hands the unbound case to the
--   executor's own binding_subject_ambiguous refusal (executor.ts:212-219), which
--   is the specific alarm that exists for it. No other field or filter differs.
--
--   THE Σ-GUARD OPERAND USES `status <> 'failed'` ON PURPOSE, and it is NOT the
--   rule 10b uses. Here the question is Stripe headroom — how much of this payment
--   is already spoken for — so a refund in flight MUST reserve its amount, exactly
--   as kernel.refund does under the payment lock (085:538-539). In 10b the question
--   is what the venue is owed, where only a settled fact may be written to an
--   append-only ledger. Same table, two different questions; do not reconcile them.
--
--   NOT AUTHORED HERE: kernel.list_pending_refunds(integer). The executor's sweep
--   mode also names it (index.ts:496, E4 §3 trailing note) and will keep returning
--   501 until it exists. It is deliberately left out of this slice — it was not
--   asked for, and unlike this function it IS an enumeration verb over pending
--   money, so it deserves its own ratification rather than arriving as a silent
--   passenger in the money slice. The single-refund execution path works without it.
-- ============================================================================
create or replace function kernel.get_refund_execution_context(p_refund_id uuid)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'refund_id',                r.refund_id,
    'payment_id',               r.payment_id,
    'order_id',                 pn.order_id,      -- XOR with sale_id (085:57-59)
    'sale_id',                  pn.sale_id,
    'amount_minor',             r.amount_minor,
    'currency',                 r.currency,
    'reason_code',              r.reason_code,
    'status',                   r.status,
    'stripe_refund_ref',        r.stripe_refund_ref,
    'payment_total_minor',      p.total,          -- amount + buyer_fee (000:978-985)
    'payment_status',           p.status,
    'stripe_payment_intent_id', p.stripe_payment_intent_id,
    'stripe_livemode',          p.stripe_livemode,   -- migration 045; NULL ⇒ executor fails closed
    -- Σ-guard operands: everything already claimed against this payment. Both
    -- reserve for in-flight claims by design — see the header note.
    'prior_non_failed_minor',   coalesce((select sum(r2.amount_minor) from kernel.refund r2
                                           where r2.payment_id = r.payment_id
                                             and r2.status <> 'failed'
                                             and r2.refund_id <> r.refund_id), 0),
    'disputed_minor',           coalesce((select sum(d.amount_minor) from kernel.dispute_native d
                                           where d.payment_id = r.payment_id
                                             and d.status in ('lost','charge_refunded')), 0))
    from kernel.refund r
    join public.payments p on p.id = r.payment_id                      -- total: NOT NULL FK (085:76)
    left join kernel.payment_native pn on pn.payment_id = r.payment_id -- see the deviation note
   where r.refund_id = p_refund_id;
$$;

-- EXEC DEF (§0.1a): a MACHINE verb on the money execution path — service_role
-- only, never a client. Revoke the default PUBLIC EXECUTE first (076 discipline).
revoke all on function kernel.get_refund_execution_context(uuid) from public, anon, authenticated;
grant execute on function kernel.get_refund_execution_context(uuid) to service_role;


-- ============================================================================
-- 10h — kernel.settlement_royalty_lines (088:319-366) — BODY ONLY.
--   Ruling A5 (face-value entitlement, on the DEBIT side too) · E-90 · E-94 ·
--   E-104 · PFA-29.
--
--   TWO DEFECTS IN THE CHARGEBACK ARM, BOTH EXECUTED ON A REPLAY. Order A 10000
--   clean, order B 6000 face fully refunded, its dispute closed at 6600 (face +
--   the 600 buyer-side service fee):
--
--     lines : chargeback -6600 | primary_sale 10000 | primary_sale 6000 | refund_void -6000
--     PAYOUT: 3400                                                       TRUTH: 10000
--
--   The venue is underpaid 6600, permanently, in a ledger with no UPDATE and no
--   DELETE. The two defects are independent:
--
--   (i)  DOUBLE DEBIT. The same money leaving for the same buyer is booked TWICE —
--        once as 'refund_void' (10b) and once as 'chargeback'. 088:351-359 has no
--        awareness of refunds at all. dispute_native.status='charge_refunded' is
--        Stripe's canonical "the merchant refunded the disputed charge", written
--        by the live charge.dispute.* branches, so the overlap is the NORMAL
--        outcome of a disputed-then-refunded order, not a contrived one.
--   (ii) THE PLATFORM'S FEE IS CHARGED TO THE VENUE. d.amount_minor is measured
--        against public.payments.total, which is "amount + buyer_fee" (baseline
--        000:978-985). Subtracting it whole takes the 600 buyer-side service fee —
--        Snatch It's own revenue under A5 — out of the venue's face-value
--        entitlement. A5 forbids exactly this, and 10b already caps 'refund_void'
--        for the identical reason; the chargeback arm simply never got the cap.
--
--   THE FIX MIRRORS 10b: ONE POOL OF HEADROOM PER ORDER, capped at the face value
--   that order was credited, drawn down by BOTH debit causes. Refunds are SENIOR
--   (10b allocates first and knows nothing of disputes), so this arm subtracts,
--   before allocating anything:
--     · the order's SETTLED refund exposure — least(Σ succeeded refunds, face) —
--       read from kernel.refund directly rather than from lines, so it is correct
--       whether or not 10b has lined those refunds yet, including in this very
--       close where neither cause can see the other's uncommitted rows; and
--     · every chargeback ALREADY LINED against this order in any settlement.
--   The remaining headroom is then allocated across this order's unlined disputes
--   by the same cumulative-cap window 10b uses, ordered (created_at, dispute_id),
--   so an earlier dispute's allocation is never disturbed by a later one. A
--   dispute with no headroom left emits NOTHING rather than a zero line.
--   10b's own cap counts 'chargeback' lines symmetrically, so the protection holds
--   whichever cause is lined first.
--
--   ON THE RED TEAM'S CASE the chargeback arm now emits nothing (refund exposure
--   6000 already consumes order B's whole 6000 face), lines are
--   primary_sale 10000 · primary_sale 6000 · refund_void -6000, and the payout is
--   10000 — the truth. With no refund present it emits -6000, not -6600: order B
--   nets to zero and the 600 fee stays with the platform, which is A5.
--
--   THE ROYALTY ARM IS UNTOUCHED — reproduced byte-identical from 088:336-350,
--   including E-90's positive-credit posture and the PFA-30 note that no royalty
--   is guessed. So are the signature, VOLATILE, the E-104 per-org lock, the `s`
--   CTE, the currency filters, the never-lined-before dedupes, the E-94 boundary
--   (`pn.order_id is not null` — a native-resale dispute is still NOT booked
--   against the org), the deliberate absence of a scope predicate on the
--   chargeback arm (088:311-316: a chargeback lands in the org's NEXT settlement
--   to close, which is 088's design and not 093's to change), and the trailing
--   `order by 1, 2`. This function still MUST NOT raise (087:204-207) and does not.
-- ============================================================================
create or replace function kernel.settlement_royalty_lines(p_settlement_id uuid)
returns setof kernel.settlement_line_candidate
language plpgsql volatile security definer set search_path = ''
as $$
declare v_org uuid;
begin
  select st.org_id into v_org from venue.settlement st where st.settlement_id = p_settlement_id;
  if v_org is null then return; end if;
  -- E-104: serialize this org's candidate emission for the calling transaction
  -- (released at commit). After the wait, every query below takes a fresh
  -- snapshot (VOLATILE), so a line committed by the sibling close is SEEN.
  perform pg_advisory_xact_lock(hashtext('settlement.seam.org:' || v_org::text));
  return query
  with s as (
    select st.settlement_id, st.org_id, st.venue_id, st.event_id, st.period_start, st.period_end, st.currency
      from venue.settlement st where st.settlement_id = p_settlement_id
  ),
  royalty as (
    select 'market_sale'::text as cause, ms.sale_id as cause_ref,
           ms.venue_royalty_minor::bigint as amount_minor, ms.currency, 'organization'::text as payee_kind, s.org_id as payee_id
      from s
      join market.market_sale ms on ms.terminal_state = 'completed' and ms.venue_royalty_minor is not null and ms.venue_royalty_minor > 0
      join kernel.tickets t on t.ticket_atom_id = ms.ticket_atom_id and t.org_id = s.org_id
      join catalog.event_session es on es.session_id = t.event_session_id
      join catalog.event e on e.event_id = es.event_id
     where ms.currency = s.currency
       and ((s.event_id is not null and e.event_id = s.event_id)
            or (s.event_id is null and e.venue_id = s.venue_id
                and (s.period_start is null or es.starts_at >= s.period_start)
                and (s.period_end is null or es.starts_at < s.period_end)))
       and not exists (select 1 from venue.settlement_line l where l.cause = 'market_sale' and l.cause_ref = ms.sale_id)
  ),
  -- 093/A5: the operands the cap needs, one row per UNLINED eligible dispute.
  cb_candidate as (
    select d.dispute_id, d.created_at, d.currency, s.org_id,
           d.amount_minor::bigint as disputed_minor,
           o.order_id, o.total_minor::bigint as face_minor,
           -- refunds are SENIOR: what 10b has taken, or will take, of this face.
           -- Read from kernel.refund (not from lines) so it is right even when
           -- both causes are unlined in this same close.
           least(coalesce((select sum(r.amount_minor) from kernel.refund r
                            where r.payment_id = pn.payment_id and r.status = 'succeeded'), 0),
                 o.total_minor)::bigint as refund_exposure_minor,
           -- chargebacks already lined against THIS ORDER in any settlement, ever.
           coalesce((select sum(-l2.amount_minor) from venue.settlement_line l2
                       join kernel.dispute_native d2 on d2.dispute_id = l2.cause_ref
                       join kernel.payment_native pn2 on pn2.payment_id = d2.payment_id
                      where l2.cause = 'chargeback' and pn2.order_id = o.order_id), 0)::bigint as prior_cb_minor
      from s
      join kernel.dispute_native d on d.status in ('lost','charge_refunded') and d.amount_minor > 0
      join kernel.payment_native pn on pn.payment_id = d.payment_id and pn.order_id is not null   -- E-94
      join venue."order" o on o.order_id = pn.order_id and o.org_id = s.org_id
     where d.currency = s.currency
       and not exists (select 1 from venue.settlement_line l where l.cause = 'chargeback' and l.cause_ref = d.dispute_id)
  ),
  cb_alloc as (
    select cb.dispute_id, cb.currency, cb.org_id,
           greatest(
             0,
               least(sum(cb.disputed_minor) over w,
                     greatest(0, cb.face_minor - cb.refund_exposure_minor - cb.prior_cb_minor))
             - least(sum(cb.disputed_minor) over w - cb.disputed_minor,
                     greatest(0, cb.face_minor - cb.refund_exposure_minor - cb.prior_cb_minor))
           )::bigint as debit_minor
      from cb_candidate cb
    window w as (partition by cb.order_id order by cb.created_at, cb.dispute_id
                 rows between unbounded preceding and current row)
  ),
  chargeback as (
    select 'chargeback'::text as cause, ca.dispute_id as cause_ref,
           (-ca.debit_minor)::bigint as amount_minor, ca.currency, 'organization'::text as payee_kind, ca.org_id as payee_id
      from cb_alloc ca
     where ca.debit_minor > 0        -- no headroom left ⇒ no line, not a zero line
  )
  select * from royalty
  union all
  select * from chargeback
  order by 1, 2;
end;
$$;


-- ============================================================================
-- 10i — kernel.claim_refunds_for_execution(p_limit int, p_lease_seconds int) — NEW.
--   Ruling D3 (build the refund executor) · E4_refund_executor.md §3 trailing
--   note + §5 · PFA-21 (service_role: USAGE only, no table/DML grants) ·
--   PFA-23 · H1_refund_architecture.md.
--
--   THE GAP IT CLOSES. 10g gave the executor its READ. It still has no WORK
--   LIST. refund-execute's `action: sweep` — the leg that drains every refund
--   row a crash, a Stripe timeout or catalog.cancel_event left behind — calls a
--   function that does not exist (index.ts:496) and therefore answers 501. A
--   full local replay of 000-093 confirms it: kernel.list_pending_refunds is
--   absent. Single refunds would work on deploy day; INTERRUPTED ones would be
--   unfindable, which is precisely the class this executor exists to recover.
--
--   WHY THIS IS A CLAIM AND NOT A LIST. E4 §3's trailing note names
--   `kernel.list_pending_refunds(integer)`. A bare list is refused here, and the
--   refusal is the whole point: a list hands N workers the SAME N refunds and
--   relies on Stripe's idempotency key alone to keep the money right. That key
--   IS the last line of defence and it must never also be the first. This verb
--   hands each refund to ONE worker for a bounded lease, exactly as
--   064_webhook_event_claim_lease.sql does for Stripe deliveries, so a healthy
--   race never becomes a herd against Stripe's API.
--
--   THE LEASE IS AN AUDIT ROW, NOT A COLUMN. 064 stamps claimed_at on
--   public.stripe_webhook_events. kernel.refund is a money-ledger table under an
--   owner-signed freeze and 093 does no DDL on one, so the lease is carried by
--   an append-only kernel.admin_audit row (`action = 'refund.execute_claim'`,
--   subject_kind 'refund'). That is strictly BETTER than a column for this
--   problem, and not merely a workaround:
--     * every attempt on money is durably recorded rather than overwritten —
--       admin_audit is UPDATE/DELETE-revoked even for service_role (077:259)
--       and trigger-guarded (077:261-264);
--     * `min(occurred_at)` over those rows is the FIRST-ATTEMPT INSTANT, which
--       is the operand the Stripe idempotency window below needs and which a
--       single mutable claimed_at column cannot express;
--     * `count(*)` is the attempt counter 064 keeps in a column, for free.
--
--   THE STRIPE IDEMPOTENCY WINDOW — the defect this verb refuses to enable.
--   E4 §5 cases 2/3/13 all recover by REPLAYING `refund_<refund_id>` and relying
--   on Stripe returning the ORIGINAL Refund object. Stripe retains an
--   idempotency key's result for 24 HOURS. After that the key is forgotten and
--   the identical request creates a SECOND, REAL refund. A work list that hands
--   a worker a `pending` row whose key was first used 25 hours ago is therefore
--   a double-payment generator, and the schedule (a crashed worker, a paused
--   cron, a paused project) makes that ordinary rather than exotic. So the
--   DATABASE decides, per row, which of two modes the worker is authorized to
--   run, and the worker cannot pick:
--     'create'    — safe to POST /v1/refunds under refund_<refund_id>: either
--                   the key has NEVER been used (no claim row) or its first use
--                   is inside the window. A replay inside the window is
--                   deduped by Stripe and returns the original object.
--     'reconcile' — the key is unusable as a dedup token, so the worker must
--                   first ESTABLISH what exists at Stripe (the row's own
--                   stripe_refund_ref when it has one, else a search of the
--                   PaymentIntent's refunds for metadata.refund_id, which the
--                   executor always writes) and only create if nothing is
--                   there. Never a blind create.
--   The window is 20 hours, not 24: a 4-hour margin against clock skew and
--   against a claim stamped before a long Stripe call. It is a CONSTANT, not a
--   parameter and not a config key — a caller-tunable dedup window is the
--   tampering vector this verb exists to remove.
--
--   'submitted' IS IN SCOPE, AND THAT IS A BUG FIX. E4 §5 case 4 leaves a row
--   stranded at 'submitted' when a worker dies between the two mark_refund_state
--   calls, and E4's own sweep filters `status = 'pending'` (executor.ts:497), so
--   nothing would ever pick it up again. A stranded 'submitted' row keeps the
--   buyer's account deletion blocked forever (BP-12 arm 1, 085:249-262) — the
--   SAME defect ruling D3 was issued to close, one state later. A 'submitted'
--   row always carries a ref (refund_ref_pairing_ck, 085:93), so it is always
--   'reconcile' and can never mint a second refund.
--
--   WHAT THIS VERB CANNOT DO, BY CONSTRUCTION. It takes no payment, no order,
--   no venue, no organization, no identity, no amount, no destination and no
--   refund id: there is NO parameter by which a caller can name a subject at
--   all. It returns refund ids and a mode. It moves no money, transitions no
--   refund (mark_refund_state, 085:1737, remains the only writer of status) and
--   projects no PaymentIntent, no buyer and no amount — the executor still has
--   to go through 10g for those, under 10g's own X-6 / ruling-F projection. The
--   name is the whole capability: it claims refunds, for execution.
--
--   THE COMMAND KEY IS DB-DERIVED. `refund.execute:<refund_id>` is returned
--   rather than minted by the worker (index.ts built `sweep:<uuid>` itself), so
--   the audit identity of an execution attempt comes from the durable refund
--   fact and two workers on one refund cannot land under two audit identities.
--   42 chars: inside admin_audit's budget with no truncation.
--
--   ATOMICITY. `for update ... skip locked` on kernel.refund is what makes the
--   claim exclusive: a concurrent claimer never even evaluates a row another
--   transaction holds, and by the time the lock is released the claim's audit
--   row is committed and the `not exists` predicate excludes it for the lease.
--   Same guarantee 064 gets from its single INSERT … ON CONFLICT statement.
--   The row lock ends with this transaction; the LEASE is the audit row.
-- ============================================================================
create or replace function kernel.claim_refunds_for_execution(
  p_limit integer default 25, p_lease_seconds integer default 900)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Both operands are CLAMPED, not trusted. p_lease_seconds = 0 from a
  -- misconfigured worker would make the lease vacuous and re-create the herd
  -- this function exists to prevent; p_limit is bounded so one tick cannot
  -- claim the entire backlog and sit on it.
  v_limit   integer  := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_lease   integer  := least(greatest(coalesce(p_lease_seconds, 900), 60), 3600);
  -- Stripe retains an idempotency key's result for 24h; 4h of margin.
  v_window  constant interval := interval '20 hours';
  v_sys     constant uuid := '00000000-0000-0000-0000-0000000000f1';
  v_rows    jsonb := '[]'::jsonb;
  v_r       record;
  v_first   timestamptz;
  v_tries   integer;
  v_mode    text;
begin
  for v_r in
    select r.refund_id, r.created_at, r.status, r.stripe_refund_ref
      from kernel.refund r
     where r.status in ('pending','submitted')      -- the two UNFINISHED states
       and not exists (
             select 1 from kernel.admin_audit a
              where a.subject_kind = 'refund'
                and a.subject_id   = r.refund_id
                and a.action       = 'refund.execute_claim'
                and a.occurred_at  > now() - make_interval(secs => v_lease))
     order by r.created_at, r.refund_id                     -- oldest money first
     limit v_limit
     for update skip locked
  loop
    select min(a.occurred_at), count(*)::integer into v_first, v_tries
      from kernel.admin_audit a
     where a.subject_kind = 'refund' and a.subject_id = v_r.refund_id
       and a.action = 'refund.execute_claim';

    if v_r.status = 'submitted' then
      v_mode := 'reconcile';                       -- always carries a ref (085:93)
    elsif v_first is null or v_first > now() - v_window then
      v_mode := 'create';                          -- key unused, or still deduped
    else
      v_mode := 'reconcile';                       -- key expired: establish, then act
    end if;

    insert into kernel.admin_audit
           (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_sys, 'refund.execute_claim', 'refund', v_r.refund_id, v_mode,
            jsonb_build_object('status', v_r.status,
                               'stripe_refund_ref', v_r.stripe_refund_ref),
            jsonb_build_object('execution_mode', v_mode,
                               'attempt', v_tries + 1,
                               'lease_seconds', v_lease,
                               'first_attempt_at', coalesce(v_first, now())));

    v_rows := v_rows || jsonb_build_object(
      'refund_id',      v_r.refund_id,
      'created_at',     v_r.created_at,
      'status',         v_r.status,
      'execution_mode', v_mode,
      'attempt',        v_tries + 1,
      'command_key',    'refund.execute:' || v_r.refund_id::text);
  end loop;

  return jsonb_build_object('refunds', v_rows,
                            'lease_seconds', v_lease,
                            'claimed_at', now());
end;
$$;

-- EXEC DEF (§0.1a): a MACHINE verb on the money execution path — service_role
-- only, never a client. Revoke the default PUBLIC EXECUTE first (076 discipline).
revoke all on function kernel.claim_refunds_for_execution(integer, integer)
  from public, anon, authenticated;
grant execute on function kernel.claim_refunds_for_execution(integer, integer) to service_role;

-- ============================================================================
-- 10j — kernel.deletion_blockers_money (085:229-285) — BODY ONLY.
--       H2: BP-12 arm 2's CLOCK is re-anchored, and its operand is renamed.
--       Full argument and executed matrix: docs/phase2/_impl/H2_deletion_clock.md
-- ============================================================================
--
-- THE DEFECT. BP-12 arm 2 measured its window from `venue."order".created_at`
-- — the PAYMENT clock:
--
--     and o.created_at > now() - make_interval(hours => v_window::int)   -- 085:281
--
-- so ORDER AGE was taken as proof that an event-related obligation was finished.
-- Executed against snatchit_rehears_del with the key set to 720 (30 days), the
-- following identities were ALL fully erasable — every deletion arm clear, and
-- kernel.sweep_deletion_pending tombstoned them — BEFORE their event happened:
--
--   * bought 90 days out, event in 10 days                        (the G7 P0-3 case)
--   * bought 90 days out, PARTIALLY REFUNDED already, event in 10 days
--   * bought 90 days out, session already CANCELLED, event in 10 days
--   * bought 90 days out, multi-session and multi-day events still ahead
--   * bought 90 days out, event POSTPONED further into the future
--
-- The only buyer the old clock protected was the one who had bought RECENTLY —
-- and it protected them for the wrong reason (when they paid), not because
-- their event had not happened. Meanwhile kernel.close_settlement's G2 maturity
-- gate was simultaneously holding the VENUE's money on `refund_in_flight` /
-- `dispute_open` predicates that, after the tombstone, can no longer identify
-- the counterparty. The two halves of this train contradicted each other on the
-- same question.
--
-- ENGAGING WITH 085's OWN STATED REASONING. The 085 comment defends created_at
-- as "the only stable timestamp on the immutable 082 table", and PFA-22 defends
-- it as expiring "no later than a paid-time window would". Both statements are
-- TRUE and both are IRRELEVANT: they compare two PAYMENT-clock instants to each
-- other and never consider the event clock at all. The anchor does not have to
-- live on 082. `venue."order".event_session_id` is `not null references
-- catalog.event_session(session_id) on delete restrict` (082:77), so the join is
-- TOTAL (every order resolves to exactly one session) and STABLE (the referent
-- cannot be deleted out from under it). This is the identical derivation G2
-- built for the settlement maturity gate, restricted to one identity's orders.
--
-- THE ANCHOR:
--
--     anchor(identity) = max( coalesce(session.ends_at, session.starts_at) )
--                        over the sessions of the identity's CANDIDATE orders
--
-- and the arm blocks while `now() < anchor + deletion.post_event_hold_hours`.
--
--   * `max` because erasure is per-IDENTITY: one unmatured order must hold the
--     whole account. Multi-session and multi-day events fall out of this for
--     free (verified: a two-session buyer anchors on day 2; a single session
--     running days 10-13 anchors on day 13).
--   * `coalesce(ends_at, starts_at)` because `ends_at` is NULLABLE (078:170) and
--     `catalog.create_event_session` requires only `starts_at` (078:805-807).
--     G2 fails CLOSED here — a payout with an unknown end simply never matures,
--     and `kernel.release_payout` is a human exit. THIS GATE HAS NO SUCH EXIT:
--     nothing in the corpus can force-tombstone an identity, so blocking on an
--     unknown end would be an UNBOUNDED erasure block with no release verb —
--     an erasure-law failure, not a safety property. `starts_at` is NOT NULL,
--     is event-anchored, and is at most one session-duration early; the hold
--     interval swamps that gap. Bounded and honest beats unbounded and unusable.
--   * the ORDER'S OWN session, not every session of its event: a day-1 buyer's
--     obligation is day 1. An event-grain cancellation that reaches them opens a
--     `kernel.refund` row, which arm 1 blocks on independently.
--
-- CANDIDATE SET UNCHANGED, verbatim from PFA-22: paid / partially_refunded. A
-- `refunded` order carries no further refund exposure, and a post-tombstone
-- chargeback is OR-13/16c's ruled path (it lands against the tombstone) with
-- BP-10 (kernel.identity_obligation) as its blocker. Widening here would add
-- population without a named risk the corpus does not already carry.
--
-- THE CONFIG READ IS NO LONGER POISONABLE — a SECOND defect, found by execution
-- while testing the first, and it is worse than the one above.
-- 085:273-276 reads the operand as
--
--     select (c.value #>> '{}')::numeric into v_window
--       from catalog.platform_config c where c.key = '…'
--      order by c.version desc limit 1;
--
-- Postgres may evaluate the target list BEFORE the LIMIT, so the ::numeric cast
-- is applied to EVERY historical version of the key, not just the newest.
-- `catalog.platform_config` is APPEND-ONLY (tg_platform_config_append_only), so
-- one bad version is permanent. Executed: with versions [null, 720,
-- "720 hours", 720] the whole function raises `invalid input syntax for type
-- numeric` — for EVERY identity, not only the one who typed it. That exception
-- is swallowed by sweep_deletion_pending's per-identity `exception when others`
-- (077:2038-2041), so THE DELETION MACHINE SILENTLY STOPS TOMBSTONING ANYONE,
-- FOREVER, leaving only a `raise warning` in the log. And `"720 hours"` is the
-- single most likely typo on this key, because the sibling key
-- `ticket.expiry_grace` REQUIRES exactly that string form. One platform_admin,
-- one plausible statement, no dual control on `deletion.%` before this change.
-- CLOSED here by reading the raw jsonb out of an ordered SUBQUERY and branching
-- on jsonb_typeof, so no cast is ever applied to a row the LIMIT discards, and
-- a bad version is named, survivable, and superseded by the next good one.
--
-- FAIL-CLOSED IN EVERY DIRECTION (G2's "never assume satisfied" discipline), and
-- every block names a BOUNDED, actionable instant or a nameable policy fault:
--   value absent / JSON null        -> block, 'hold unset'          (PFA-22 verbatim)
--   value not a JSON number         -> block, 'policy invalid — type'
--   value < 0 or > 87600 (10 years) -> block, 'policy invalid — range'
--   anchor unresolvable             -> block, 'anchor unknown'      (unreachable by schema; kept as the guard)
--   now() < anchor + hold           -> block, and the message CARRIES the maturity instant
-- With NO candidate order the arm is skipped entirely — the owner's PFA-22
-- scoping ruling, unchanged: a NULL value must not block an identity that has
-- no qualifying order.
--
-- WHAT IS NOT TOUCHED: BP-5, BP-6 and BP-12 arm 1 are transcribed BYTE-FOR-BYTE
-- from 085:235-261. The signature, return type, volatility, security mode and
-- search_path are the 077 stub's, unchanged, so SEAM-2a holds and CREATE OR
-- REPLACE preserves the ACLs 077 authored (085:2124-2125 states this contract).
--
-- THE OPERAND IS RENAMED — and the prefix is load-bearing, exactly as it was for
-- G2's `payout.settlement_maturity_interval`:
--   `deletion.refund_possible_window_hours` -> `deletion.post_event_hold_hours`
--   (a) The old NAME says "refund possible window", i.e. refund ELIGIBILITY —
--       which 085:2186-2187 and PFA-22 both go out of their way to say this key
--       is NOT ("the key controls DELETION SAFETY only"). The name has been
--       wrong since PFA-22; the anchor bug and the name bug are one bug.
--   (b) A changed anchor is a CHANGED CONTRACT. Re-pointing the same key would
--       silently re-interpret any value an operator had already stored.
--   (c) The family stays `deletion.` deliberately — this IS a deletion-safety
--       key, and filing it under `refund.` or `payout.` to buy dual control
--       would re-collapse the very concepts this change separates. Dual control
--       is bought instead by adding `deletion.%` to set_platform_config's prefix
--       list, in slice 40, which is where the row and the setter both live.
-- The 085 row survives as an unread orphan (platform_config is append-only and
-- 085 is immutable) — the same residue G2's rename left behind, recorded rather
-- than hidden. Nothing reads it after this migration, which also retires its
-- poisonable read.
--
-- SEPARATION OF CONCEPTS, restated because collapsing them is what produced the
-- defect:  TICKET EXPIRY (admissibility at a door; ticket.expiry_grace; BP-1)
--       != REFUND ELIGIBILITY (may the buyer still ask; refund.% keys)
--       != DELETION SAFETY (may this identity be irreversibly tombstoned; THIS)
--       != PAYOUT MATURITY (may the venue's money leave; payout.settlement_maturity_interval).
-- Four clocks, four keys, four subjects. This function owns exactly one of them.

create or replace function kernel.deletion_blockers_money(p_identity uuid)
returns text language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_raw        jsonb;
  v_hold_hours numeric;
  v_anchor     timestamptz;
  v_matures_at timestamptz;
begin
  -- BP-5: an IN-FLIGHT identity payout (pending/submitted). Terminal failed/
  -- reversed do NOT block forever (R1 P3 — no transition exits them).
  if exists (select 1 from kernel.payout p
              where p.payee_identity_id = p_identity and p.status in ('pending','submitted')) then
    return 'BP-5: identity payout in flight';
  end if;
  -- BP-6: a payout under hold/probation for this identity.
  if exists (select 1 from kernel.payout p
              where p.payee_identity_id = p_identity and p.hold_state <> 'none') then
    return 'BP-6: identity payout under hold';
  end if;
  -- BP-12 arm 1: an in-flight refund on the identity's orders (non-terminal
  -- refund row, or a pending refund approval request on one of their orders).
  if exists (
       select 1
         from kernel.refund r
         join kernel.payment_native pn on pn.payment_id = r.payment_id
         join venue."order" o on o.order_id = pn.order_id
        where o.buyer_id = p_identity and r.status in ('pending','submitted'))
     or exists (
       select 1
         from kernel.approval_request ar
         join venue."order" o on o.order_id = ar.subject_id
        where ar.action = 'refund.issue' and ar.subject_kind = 'order'
          and ar.state = 'pending' and o.buyer_id = p_identity) then
    return 'BP-12: refund in flight';
  end if;
  -- BP-12 arm 2 (PFA-22, re-anchored by H2): the POST-EVENT deletion hold over
  -- candidate orders. Candidates = the identity's paid/partially_refunded
  -- orders (PFA-22 verbatim). With NO candidate the arm is skipped entirely, so
  -- an unset value never blocks an identity that has no qualifying order —
  -- the owner's scoping ruling, preserved exactly.
  if exists (select 1 from venue."order" o
              where o.buyer_id = p_identity
                and o.status in ('paid','partially_refunded')) then
    -- The read is a SUBQUERY so the LIMIT is applied BEFORE any cast: casting in
    -- an ordered target list would touch every historical version of the key and
    -- one bad append would permanently break this function for EVERY identity.
    select v.value into v_raw
      from (select c.value
              from catalog.platform_config c
             where c.key = 'deletion.post_event_hold_hours'
             order by c.version desc
             limit 1) v;
    if v_raw is null or jsonb_typeof(v_raw) = 'null' then
      return 'BP-12: post-event deletion hold unset (deletion.post_event_hold_hours) with candidate orders present';
    end if;
    if jsonb_typeof(v_raw) <> 'number' then
      return 'BP-12: post-event deletion hold policy invalid — deletion.post_event_hold_hours must be a JSON NUMBER of hours, got ' || jsonb_typeof(v_raw);
    end if;
    v_hold_hours := (v_raw #>> '{}')::numeric;
    if v_hold_hours < 0 or v_hold_hours > 87600 then
      return 'BP-12: post-event deletion hold policy invalid — deletion.post_event_hold_hours must be 0..87600 hours';
    end if;
    -- THE ANCHOR (H2). max() because erasure is per-identity; coalesce because
    -- ends_at is nullable and an unbounded erasure block has no release verb.
    select max(coalesce(es.ends_at, es.starts_at))
      into v_anchor
      from venue."order" o
      join catalog.event_session es on es.session_id = o.event_session_id
     where o.buyer_id = p_identity
       and o.status in ('paid','partially_refunded');
    if v_anchor is null then
      -- Unreachable while event_session_id is NOT NULL with an ON DELETE RESTRICT
      -- FK and starts_at is NOT NULL. Kept as the fail-closed guard: an operand
      -- this function could not compute must never read as "satisfied".
      return 'BP-12: post-event deletion anchor unknown for a candidate order';
    end if;
    v_matures_at := v_anchor + make_interval(hours => floor(v_hold_hours)::int);
    if now() < v_matures_at then
      -- The instant goes IN THE MESSAGE: sweep_deletion_pending writes this to
      -- kernel.identity_ext.deletion_block_reason, so an operator (and the
      -- erasure-request audit trail) can see exactly when the account clears.
      return 'BP-12: inside the post-event deletion hold — erasable after '
             || to_char(v_matures_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
    end if;
  end if;
  return null;
end;
$$;

-- GRANTS: NONE, deliberately. kernel.deletion_blockers_money is a DEFINER-
-- INTERNAL hook called only by kernel.sweep_deletion_pending; 085:2124-2125
-- records that it "keeps its 077 grants (CREATE OR REPLACE preserves ACLs)".
-- Re-granting here would restate a frozen ACL and risk widening it.


-- ============================================================================
-- 10j — kernel.payout.destination_ref: PIN THE PAYEE AT AUTHORIZATION.
--   H6 (docs/phase2/_impl/H6_payout_destination.md, agent F) ·
--   H8 (docs/phase2/_impl/H8_payout_executor.md) · H3 §5.
--
--   *** THIS IS A NEW COLUMN ON A MONEY-LEDGER TABLE. It is a deliberate    ***
--   *** SCOPE ADDITION to 093 and it overrides H3 §4's "kernel.payout       ***
--   *** columns: NONE" and the migration header's "0 DDL on any             ***
--   *** money-ledger table". Both were written before F executed the race   ***
--   *** below. It belongs in 093 rather than a 094 because 093 has never    ***
--   *** been deployed: adding it now is a column on an empty rail, whereas  ***
--   *** adding it later is a column on live money.                          ***
--
--   THE RACE, PROVED — NOT THEORETICAL. kernel.payout has no destination column
--   at all, so nothing in the row records WHO the authorized payee was:
--     · destination at authorization: acct_ORGAMINTED
--     · kernel.set_org_payout_destination re-points the org to acct_RACEDEST
--       while the payout is still status='submitted'
--     · the payout row is UNCHANGED — there is nothing in it to change
--     · kernel.mark_payout_transfer_state(...,'paid',...) accepts the result
--       with NO destination predicate whatsoever (085:1668-1735 tests status,
--       hold_state and the ref, and nothing else)
--     · no approval row pins it either, once the request has been consumed
--   and the paid-after-change payout.state_sync row then DISARMS destination
--   probation for the NEXT payout (087:479-481 reads exactly that audit row).
--   One re-point therefore both diverts the money in flight and lowers the
--   guard behind it.
--
--   WHY PINNING, AND NOT "RE-READ AT EXECUTION". The payee was decided when
--   kernel.request_org_payout authorized the payout behind SoD-1 destination-
--   setter exclusion, money-role maturity, an aal2 step-up and — above the
--   dual-control threshold — a second approver. A later re-point passed NONE of
--   those. An execution-time re-read would let a destination that was never
--   approved inherit an approval it never received. That is the same staleness
--   087:506 already refuses at request time (an approval naming a different
--   destination is marked 'stale' and never honoured); this column extends the
--   same rule past the moment the approval is consumed.
--
--   AND WHY PINNING ALONE IS ALSO WRONG. A pinned destination can be disabled,
--   disconnected or rejected by Stripe between authorization and execution, and
--   paying it would be paying a dead account. So the contract is BOTH:
--     BIND at pending→submitted (here, and in 10k's request_org_payout),
--     RE-VERIFY at execution as a fail-closed cross-check (10n), and on
--     divergence do NOT pay and do NOT fail — de-authorize (10o).
--
--   LAUNCH-SEQUENCE REQUIREMENT, NOT A NICETY. 'payout.dual_control_min_minor'
--   is seeded NULL, and X-12 makes NULL restrictive, so TODAY every payout is
--   parked and the kernel.approval_request row's payload.destination_ref is
--   what pins the destination. The exposure above is created by SETTING that
--   config key — the direct-advance arm (087:566-572) has no approval row and
--   therefore no pin at all. THIS COLUMN MUST LAND BEFORE
--   'payout.dual_control_min_minor' IS EVER SET.
--
--   SHAPE. Nullable (every historical row predates the pin and every payout
--   born 'pending' has not been authorized yet), text, constrained to Stripe's
--   account-id shape so a malformed value is unstorable rather than merely
--   refused at the edge. Re-writable, and only by request_org_payout: a payout
--   de-authorized by 10o must be able to re-pin a NEW destination when a human
--   releases the hold and the org re-requests behind the full control set.
-- ============================================================================
alter table kernel.payout
  add column if not exists destination_ref text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'payout_destination_ref_shape_ck'
                   and conrelid = 'kernel.payout'::regclass) then
    alter table kernel.payout
      add constraint payout_destination_ref_shape_ck
      check (destination_ref is null or destination_ref ~ '^acct_[A-Za-z0-9]+$');
  end if;
end $$;

comment on column kernel.payout.destination_ref is
  'The Stripe Connect destination this payout was AUTHORIZED against, pinned by kernel.request_org_payout at pending->submitted. The executor sends THIS value and never a fresh read; a divergence from the organization''s current ref de-authorizes the payout (kernel.hold_payout_destination_changed). NULL = not yet authorized.';


-- ============================================================================
-- 10k — kernel.request_org_payout (087:408-575) — BODY ONLY, TWO CHANGES.
--   H6 (the destination pin) · D-1 (the maturity gate is not inherited).
--
--   CHANGE 1 — THE PIN. The two arms that advance pending→submitted now also
--   write destination_ref = v_org.stripe_connect_account_ref.
--
--   CHANGE 2 — THE MATURITY RE-DERIVATION. One guard is inserted immediately
--   after the probation arm and before everything that can advance or park,
--   calling kernel.settlement_payout_maturity (10m) — the SAME definition the
--   mint uses — and holding the payout with the returned reason instead of
--   advancing. 087 re-derived NONE of the eight predicates; it only honoured a
--   hold somebody else had already set, and that hold was a close-time
--   snapshot. Adds one result-set member, 'maturity_held'; changes none.
--
--   Nothing else differs — not the signature, not SECURITY DEFINER, not
--   search_path, not one existing precondition, not one existing audit row, not
--   one existing return shape, not one comment. Diff it against 087:408-575:
--   two UPDATE statements gain a column, one declare and one guard block are
--   inserted, and nothing else moves.
--
--   WHY BOTH ARMS AND ONLY THESE ARMS. These are the ONLY writers of
--   status='submitted' on kernel.payout, verified against the live catalogue:
--   the five functions whose bodies UPDATE kernel.payout are hold_payout,
--   release_payout and record_dispute_native (hold_state only),
--   mark_payout_transfer_state (which REFUSES 'submitted' outright, 085:1681)
--   and this one. So pinning here pins every authorized payout, with no second
--   door.
--
--   THE VALUE PINNED IS THE ONE THE CONTROLS PASSED. In the approved-request
--   arm, 087:506 has already refused any approval whose payload destination_ref
--   differs from v_org.stripe_connect_account_ref, so the org's current ref IS
--   the approved destination at that instant. In the direct arm the same row
--   was read under the organization's FOR UPDATE lock (087:428) after the
--   cool-down and probation gates, so it is the destination those gates were
--   evaluated against. In neither arm is a fresh read introduced.
--
--   087 IS NOT MODIFIED. This is a CREATE OR REPLACE at the exact existing
--   signature, which is the discipline 093 uses everywhere for a behaviour
--   change to a shipped function (migrations 076-092 are immutable).
-- ============================================================================
create or replace function kernel.request_org_payout(p_org_id uuid, p_settlement_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_s venue.settlement%rowtype; v_po kernel.payout%rowtype; v_org kernel.organization%rowtype;
  v_threshold bigint; v_threshold_ver integer; v_req uuid; v_aal text;
  v_prob_days integer; v_changed_at timestamptz; v_ar kernel.approval_request%rowtype;
  v_maturity_now jsonb;   -- D-1: the G2 verdict, re-derived immediately before the advance
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if not kernel.has_org_role(p_org_id, array['org_owner','org_finance']) then
    raise exception 'insufficient_privilege: org_owner or org_finance required' using errcode = '42501';
  end if;
  select * into v_s from venue.settlement where settlement_id = p_settlement_id for update;   -- SSCAS #4 rank-6
  if not found or v_s.org_id <> p_org_id then   -- AUTHZ-C1C: the scope binds to the subject, under the lock
    raise exception 'not_found: settlement % for org %', p_settlement_id, p_org_id using errcode = 'P0002';
  end if;
  if v_s.status = 'open' then
    raise exception 'precondition_failed: settlement not closed' using errcode = 'P0001';
  end if;
  -- the org row under lock: SoD-1 setter, cool-down, the probation operand.
  select * into v_org from kernel.organization o where o.org_id = p_org_id for update;
  if v_org.payout_destination_set_by is not null and v_org.payout_destination_set_by = v_uid then
    raise exception 'sod_violation: the payout-destination setter cannot request a payout';
  end if;
  if not kernel.money_role_grant_matured(p_org_id) then
    raise exception 'sod_violation: org money grant not yet matured';
  end if;
  -- AUTHZ-M4 step-up: an absent claim is never a pass or a fail.
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to request a payout';
  end if;
  if v_org.payout_destination_locked_until is not null and v_org.payout_destination_locked_until > now() then
    raise exception 'precondition_failed: destination cool-down until %', v_org.payout_destination_locked_until using errcode = 'P0001';
  end if;
  if v_org.stripe_connect_account_ref is null then   -- a disbursement needs a destination; a NULL one strands the money at the edge   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
    raise exception 'precondition_failed: no_payout_destination — the org has no Stripe Connect destination bound' using errcode = 'P0001';
  end if;
  select * into v_po from kernel.payout
   where cause = 'settlement' and cause_ref = p_settlement_id and status in ('pending','submitted')
   order by (status = 'pending') desc, created_at limit 1 for update;   -- a pending sibling is never shadowed by a submitted one
  if not found then
    raise exception 'precondition_failed: no pending payout for this settlement' using errcode = 'P0001';
  end if;
  if v_po.status = 'submitted' then
    return jsonb_build_object('status','noop_replay','payout_id', v_po.payout_id);
  end if;
  if v_po.hold_state = 'probation_hold' then   -- still held: the request is recorded and declined again
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'payout.request', 'payout', v_po.payout_id, 'probation_held', jsonb_build_object('settlement_id', p_settlement_id));
    return jsonb_build_object('status','probation_held','payout_id', v_po.payout_id);
  elsif v_po.hold_state <> 'none' then   -- a platform RISK hold is not a request outcome (§10.3 result set): fail closed
    raise exception 'precondition_failed: payout_held — a platform risk hold must be released before a request' using errcode = 'P0001';
  end if;
  -- DESTINATION PROBATION (§10.3 third arm). Operand: the last destination change
  -- (the org.payout_destination.change audit row 085 writes) inside the window;
  -- "first payout" = no payout of this org reached `paid` since that change.
  select (c.value #>> '{}')::integer into v_prob_days from catalog.platform_config c
   where c.key = 'payout.destination_probation_days' order by c.version desc limit 1;
  -- the change instant: the 085 destination-change audit OR the 077 first bind (a fresh destination
  -- is the archetypal fresh destination — the restrictive reading, E-86).
  select max(a.occurred_at) into v_changed_at from kernel.admin_audit a
   where a.action in ('org.payout_destination.change','org.connect_ref.bind')
     and a.subject_kind = 'organization' and a.subject_id = p_org_id;
  if v_changed_at is not null
     and (v_prob_days is null or v_changed_at > now() - make_interval(days => v_prob_days))   -- NULL ⇒ X-12 restrictive
     -- "the FIRST payout": no payout of this org was SYNCED to paid since the change (the 085
     -- payout.state_sync audit row — never updated_at, which a later overlay may bump).
     and not exists (select 1 from kernel.admin_audit a2 join kernel.payout p on p.payout_id = a2.subject_id
                      where p.payee_org_id = p_org_id and a2.subject_kind = 'payout' and a2.action = 'payout.state_sync'
                        and a2.after ->> 'status' = 'paid' and a2.occurred_at > v_changed_at)
     -- a platform_risk/platform_admin RELEASE OF THIS PROBATION (kernel.release_payout, the sole release
     -- path, reason = the probation hold's own reason) is the human decision the arm exists to obtain:
     -- it is not re-imposed (T-RPC-MONEY-32). A risk-hold release does not count.
     and not exists (select 1 from kernel.admin_audit a where a.subject_kind = 'payout' and a.subject_id = v_po.payout_id
                       and a.action = 'payout.release' and a.reason_code = 'destination_probation'
                       and a.occurred_at >= v_changed_at) then   -- >=: same-transaction instants
    update kernel.payout
       set hold_state = 'probation_hold', hold_reason_code = 'destination_probation', held_at = now(), held_by = null, updated_at = now()
     where payout_id = v_po.payout_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'payout.probation_hold', 'payout', v_po.payout_id, 'destination_probation',
            jsonb_build_object('settlement_id', p_settlement_id, 'destination_changed_at', v_changed_at));
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)   -- §10.3 Writes: payout.request on every arm
    values (v_uid, 'payout.request', 'payout', v_po.payout_id, 'probation_held', jsonb_build_object('settlement_id', p_settlement_id));
    return jsonb_build_object('status','probation_held','payout_id', v_po.payout_id);
  end if;
  -- ── D-1: THE MATURITY GATE IS RE-EVALUATED HERE, NOT INHERITED ─────────────
  -- 087 re-derived NONE of the eight G2 predicates: it honoured a hold somebody
  -- else had already set, and 10d's hold was a CLOSE-TIME SNAPSHOT. Four later
  -- state changes defeat that snapshot and NONE of them writes kernel.payout —
  -- a refund reaching 'succeeded' after the close; catalog.cancel_event, which
  -- touches kernel.payout nowhere, so a cancelled event leaves the payout at
  -- none/pending/full amount; a dispute first observed already 'lost', because
  -- kernel.record_dispute_native freezes only on an OPEN dispute (088:804), so
  -- the freeze is INVERTED relative to the risk; and Connect capability loss.
  -- The conjunction is therefore re-run HERE, from the SAME definition the mint
  -- used (10m) — a move plus a call site, not a second implementation.
  --
  -- IT GUARDS BOTH ADVANCE ARMS *AND* THE PARK, on purpose. Everything below
  -- this point either advances to 'submitted' or parks an approval that will
  -- later be consumed to advance; an approval parked against an immature
  -- settlement is precisely the drift this closes.
  --
  -- IT HOLDS RATHER THAN RAISING, for 10d's reason: a raise leaves the payout
  -- advanceable on the next attempt with no durable record, while the hold
  -- overlay is the corpus's own recoverable answer and has a contracted release
  -- path (kernel.release_payout, 085:807, platform_risk/platform_admin).
  --
  -- CONTRACT NOTE: 'maturity_held' is a NEW member of this function's result
  -- set, alongside 'submitted' / 'pending_approval' / 'probation_held' /
  -- 'noop_replay'. It is additive; no existing status changes meaning.
  v_maturity_now := kernel.settlement_payout_maturity(p_settlement_id);
  if (v_maturity_now ->> 'hold_reason') is not null then
    update kernel.payout
       set hold_state = 'held', hold_reason_code = v_maturity_now ->> 'hold_reason',
           held_at = now(), held_by = null, updated_at = now()
     where payout_id = v_po.payout_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'payout.maturity_hold', 'payout', v_po.payout_id, v_maturity_now ->> 'hold_reason',
            jsonb_build_object('settlement_id', p_settlement_id, 'hold_predicates', v_maturity_now -> 'detail'));
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)   -- §10.3 Writes: payout.request on every arm
    values (v_uid, 'payout.request', 'payout', v_po.payout_id, 'maturity_held', jsonb_build_object('settlement_id', p_settlement_id));
    return jsonb_build_object('status','maturity_held','payout_id', v_po.payout_id,
                              'hold_reason_code', v_maturity_now ->> 'hold_reason',
                              'payout_hold_detail', v_maturity_now -> 'detail');
  end if;
  -- an APPROVED, unexpired dual-control request for THIS payout advances it (E-74) — but ONLY the
  -- destination it was approved against (E-85): an approval that predates the last destination
  -- change, or names another destination, is STALE and is never honoured.
  select * into v_ar from kernel.approval_request a
   where a.action = 'payout.request' and a.subject_kind = 'settlement' and a.subject_id = p_settlement_id
     and a.state = 'approved' and a.expires_at > now() and (a.payload ->> 'payout_id')::uuid = v_po.payout_id
   order by a.updated_at desc limit 1;
  if found then
    if (v_ar.payload ->> 'destination_ref') is distinct from v_org.stripe_connect_account_ref   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
       or (v_changed_at is not null and v_ar.updated_at <= v_changed_at) then
      update kernel.approval_request set state = 'stale', updated_at = now() where request_id = v_ar.request_id;
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_uid, 'payout.request_stale', 'approval_request', v_ar.request_id, 'destination_changed',
              jsonb_build_object('payout_id', v_po.payout_id, 'settlement_id', p_settlement_id));
      -- fall through: a fresh park against the CURRENT destination
    else
      update kernel.payout set status = 'submitted',
           destination_ref = v_org.stripe_connect_account_ref,   -- H6/F: PIN THE PAYEE AT AUTHORIZATION   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
           updated_at = now() where payout_id = v_po.payout_id;
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_uid, 'payout.request', 'payout', v_po.payout_id, 'approved_request',
              jsonb_build_object('settlement_id', p_settlement_id, 'request_id', v_ar.request_id, 'approved_by', v_ar.approved_by));
      return jsonb_build_object('status','submitted','payout_id', v_po.payout_id, 'request_id', v_ar.request_id);
    end if;
  end if;
  -- dual-control threshold: absent (NULL) ⇒ X-12 restrictive ⇒ always park.
  select (c.value #>> '{}')::bigint, c.version into v_threshold, v_threshold_ver from catalog.platform_config c
   where c.key = 'payout.dual_control_min_minor' order by c.version desc limit 1;
  if v_threshold is null or v_po.amount_minor >= v_threshold then
    -- a request already parked for this payout is returned, never duplicated.
    select * into v_ar from kernel.approval_request a
     where a.action = 'payout.request' and a.subject_kind = 'settlement' and a.subject_id = p_settlement_id
       and a.state = 'pending' and a.expires_at > now() and (a.payload ->> 'payout_id')::uuid = v_po.payout_id
     order by a.created_at limit 1;
    if found and (v_ar.payload ->> 'destination_ref') is not distinct from v_org.stripe_connect_account_ref then   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
      return jsonb_build_object('status','pending_approval','request_id', v_ar.request_id, 'payout_id', v_po.payout_id,
                                'required_approver_class', v_ar.required_approver_class);
    elsif found then   -- parked against a destination that has since changed: stale, park anew
      update kernel.approval_request set state = 'stale', updated_at = now() where request_id = v_ar.request_id;
      insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
      values (v_uid, 'payout.request_stale', 'approval_request', v_ar.request_id, 'destination_changed',
              jsonb_build_object('payout_id', v_po.payout_id, 'settlement_id', p_settlement_id));
    end if;
    -- PARK: a second org money role must approve (kernel.approve verb, 085).
    insert into kernel.approval_request (action, required_approver_class, subject_kind, subject_id, org_id,
             payload, amount_minor, config_versions, requested_by, expires_at, command_idempotency_key)
    values ('payout.request', 'org', 'settlement', p_settlement_id, p_org_id,
            jsonb_build_object('payout_id', v_po.payout_id, 'tier', 'parked',
                               'destination_ref', v_org.stripe_connect_account_ref),   -- E-85: the approval binds to THIS destination   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
            v_po.amount_minor,
            jsonb_build_object('payout.dual_control_min_minor', v_threshold_ver),   -- pinned, never a parameter
            v_uid, now() + interval '72 hours',
            coalesce(p_command_key, 'req:' || p_settlement_id::text))
    on conflict do nothing
    returning request_id into v_req;
    if v_req is null then   -- same (actor, command key): the original request
      select a.request_id into v_req from kernel.approval_request a
       where a.requested_by = v_uid and a.command_idempotency_key = coalesce(p_command_key, 'req:' || p_settlement_id::text);
    end if;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'payout.request', 'payout', v_po.payout_id, 'pending_approval',
            jsonb_build_object('settlement_id', p_settlement_id, 'request_id', v_req, 'required_approver_class', 'org'));
    -- best-effort notice (BE; dual control is enforced by the Approval row, not the notice).
    begin
      perform notify.emit_event('payout_request_pending_approval', 'settlement', p_settlement_id,   -- R2 row 20 (snake_case IN type)
              'payout_request:' || p_settlement_id::text,
              jsonb_build_object('org_id', p_org_id, 'amount_minor', v_po.amount_minor));
    exception when others then null; end;
    return jsonb_build_object('status','pending_approval','request_id', v_req, 'payout_id', v_po.payout_id,
                              'required_approver_class', 'org');
  else
    -- below an owner-set threshold: advance directly to submitted (the edge executes Stripe).
    update kernel.payout set status = 'submitted',
           destination_ref = v_org.stripe_connect_account_ref,   -- H6/F: PIN THE PAYEE AT AUTHORIZATION   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
           updated_at = now() where payout_id = v_po.payout_id;
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
    values (v_uid, 'payout.request', 'payout', v_po.payout_id, 'submitted',
            jsonb_build_object('settlement_id', p_settlement_id));
    return jsonb_build_object('status','submitted','payout_id', v_po.payout_id);
  end if;
end;
$$;


-- ============================================================================
-- 10l — kernel.settlement_covered_payments: the covered set, ONCE.
--   H3 §5 step 4 / H3 §7.1 · G2 (docs/phase2/_impl/G2_settlement_maturity.md).
--
--   WHAT IT IS. The set of (payment_id, session_id) pairs a settlement's lines
--   actually cover, derived from venue.settlement_line by the same five causes
--   the three line seams emit. It is the operand of every maturity predicate
--   and of the executor's staleness re-check, and until now it existed only as
--   an inline CTE inside 10d's close-time gate.
--
--   WHY IT IS A FUNCTION NOW. The maturity conjunction must be evaluated at
--   THREE moments, not one — the mint (10d), the pending→submitted advance
--   (10k) and immediately before the transfer (10n) — because as a close-time
--   snapshot it is defeated by at least four later state changes: a refund
--   succeeding post-close, catalog.cancel_event (which touches kernel.payout
--   NOWHERE), a dispute first observed already 'lost' (record_dispute_native
--   freezes only on an OPEN dispute, 088:804, so the freeze is inverted
--   relative to risk), and Connect capability loss. Three evaluations of one
--   inline CTE is three chances to drift; one function called three times is
--   none. 10d now calls it (via 10m) instead of carrying its own copy.
--
--   NEVER RAISES. Every lookup is a scalar subquery that yields NULL rather
--   than failing, and a NULL on either column is what the callers COUNT as
--   unresolved. A settlement whose lines are all of some other cause yields
--   zero rows, which every caller reads as "no anchor" and holds on.
--
--   NOT A DISCLOSURE VERB. It returns internal ids only, is service_role-only,
--   and is called by definer functions in this slice. No buyer, no amount, no
--   destination, no Stripe identifier.
-- ============================================================================
create or replace function kernel.settlement_covered_payments(p_settlement_id uuid)
returns table (payment_id uuid, session_id uuid, cause text)
language sql stable security definer set search_path = ''
as $$
  select
    case l.cause
      when 'primary_sale'        then (select pn.payment_id from kernel.payment_native pn where pn.order_id = l.cause_ref)
      when 'refund_void'         then (select r.payment_id from kernel.refund r where r.refund_id = l.cause_ref)
      when 'chargeback'          then (select d.payment_id from kernel.dispute_native d where d.dispute_id = l.cause_ref)
      when 'market_sale'         then (select ms.payment_id from market.market_sale ms where ms.sale_id = l.cause_ref)
      when 'promoter_commission' then (select pn.payment_id from venue.attribution a
                                         join kernel.payment_native pn on pn.order_id = a.order_id where a.id = l.cause_ref)
    end,
    case l.cause
      when 'primary_sale'        then (select o.event_session_id from venue."order" o where o.order_id = l.cause_ref)
      when 'refund_void'         then (select o.event_session_id from kernel.refund r
                                         join kernel.payment_native pn on pn.payment_id = r.payment_id
                                         join venue."order" o on o.order_id = pn.order_id where r.refund_id = l.cause_ref)
      when 'chargeback'          then (select o.event_session_id from kernel.dispute_native d
                                         join kernel.payment_native pn on pn.payment_id = d.payment_id
                                         join venue."order" o on o.order_id = pn.order_id where d.dispute_id = l.cause_ref)
      when 'market_sale'         then (select t.event_session_id from market.market_sale ms
                                         join kernel.tickets t on t.ticket_atom_id = ms.ticket_atom_id where ms.sale_id = l.cause_ref)
      when 'promoter_commission' then (select o.event_session_id from venue.attribution a
                                         join venue."order" o on o.order_id = a.order_id where a.id = l.cause_ref)
    end,
    l.cause
  from venue.settlement_line l
 where l.settlement_id = p_settlement_id
   and l.cause in ('primary_sale','refund_void','chargeback','market_sale','promoter_commission');
$$;

revoke all on function kernel.settlement_covered_payments(uuid) from public, anon, authenticated;
grant execute on function kernel.settlement_covered_payments(uuid) to service_role;


-- ============================================================================
-- 10m — kernel.settlement_payout_maturity: THE payout-maturity conjunction,
--   defined ONCE and called from THREE sites.
--   G2 (docs/phase2/_impl/G2_settlement_maturity.md) · D-1 · H3 §5 · H8.
--
--   THE DEFECT THIS CLOSES. The conjunction used to live inline inside 10d, so
--   it was a CLOSE-TIME SNAPSHOT of eight predicates and nothing re-evaluated
--   it afterwards. Four later state changes defeat that snapshot, three of them
--   demonstrated by execution:
--     · a refund reaching 'succeeded' after the close leaves the payout
--       untouched at full face value;
--     · catalog.cancel_event NEVER touches kernel.payout — a cancelled event
--       leaves the payout at none/pending/full amount;
--     · kernel.record_dispute_native freezes a payout only when the dispute is
--       observed OPEN (088:804), so a dispute first seen as 'lost' holds
--       nothing — the freeze is INVERTED relative to the risk;
--     · Connect capability loss, which no payout path consulted at all.
--   And kernel.request_org_payout re-derived NONE of the eight predicates: it
--   only honoured a hold somebody else had already set.
--
--   THE FIX IS A MOVE PLUS TWO CALL SITES, not four new checks. The body below
--   is 10d's block verbatim — the same config read with its
--   absent/JSON-null/unparseable collapse to NULL, the same covered set (now
--   10l), the same causal predicate order, the same
--   first-failing-predicate-wins rule, the same full detail vector. Calling it
--   at the mint, at the advance and at the transfer turns a snapshot into an
--   invariant, and because there is exactly one definition the three
--   evaluations cannot disagree.
--
--   WHAT IS DELIBERATELY *NOT* HERE. The payee predicates — destination pinned
--   and unchanged, Connect transfers active, organization status — belong to
--   the EXECUTION-time gate (10n) and to the de-authorization verb (10o),
--   because they are about who may be paid rather than when the money has
--   settled, and because holding a payout at MINT for a capability the org has
--   not finished onboarding yet would be a different (and wrong) policy. The
--   staleness re-check is likewise not here: it is meaningless at the mint,
--   where the lines were just written, and lives in 10n.
--
--   ALSO NOT HERE, ON PURPOSE — the predicates D confirmed are already enforced
--   correctly elsewhere, which must NOT be duplicated: settlement-closed and
--   destination-non-null (request_org_payout, 087:425/447); the obligation
--   being positive (10d's `if v_net > 0` plus CHECK (amount_minor > 0)); no
--   prior payout for the settlement (noop_replay plus the unique
--   idempotency_key). The promoter deduction is correctly not a predicate at
--   all: commission is a NEGATIVE line, so the net is already reduced by it.
--
--   MUST NOT RAISE. It is called from inside close_settlement, where a raise
--   would roll back the entire close and the ledger would never record what the
--   venue is owed. Every operand therefore fails toward the HOLD: the config
--   read is wrapped, every count coalesces to its holding value, and an unknown
--   settlement yields the same shape as an immature one.
-- ============================================================================
create or replace function kernel.settlement_payout_maturity(p_settlement_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  -- EVERY OPERAND IS INITIALISED TO THE VALUE THAT HOLDS, so a path that fails
  -- to compute one can only fail toward the hold, never past it.
  v_maturity     interval;
  v_unresolved   bigint  := 1;
  v_sess_n       bigint  := 0;
  v_sess_no_end  bigint  := 1;
  v_anchor       timestamptz;
  v_cancelled    boolean := true;
  v_refund_open  boolean := true;
  v_dispute_open boolean := true;
  v_reason       text;
begin
  -- READ AS THE HOUSE PATTERN: absent row, JSON null and unparseable value all
  -- collapse to NULL and therefore to the hold (the 081:630-639 idiom).
  begin
    v_maturity := (select (c.value #>> '{}')::interval
                     from catalog.platform_config c
                    where c.key = 'payout.settlement_maturity_interval'
                    order by c.version desc limit 1);
  exception when others then v_maturity := null;
  end;

  -- THE COVERED SET IS DERIVED FROM THIS SETTLEMENT'S OWN LINES (10l), not from
  -- the header's scope predicate: the lines are the money actually being paid,
  -- and 088's chargeback arm deliberately carries NO scope predicate
  -- (088:311-316), so a scope-based derivation would miss exactly the rows most
  -- likely to be in dispute.
  with cov as (select * from kernel.settlement_covered_payments(p_settlement_id)),
       cov_session as (select distinct c.session_id from cov c where c.session_id is not null)
  select
    (select count(*) from cov c where c.payment_id is null or c.session_id is null),
    (select count(*) from cov_session),
    (select count(*) from cov_session cs join catalog.event_session es on es.session_id = cs.session_id where es.ends_at is null),
    (select max(es.ends_at) from cov_session cs join catalog.event_session es on es.session_id = cs.session_id),
    (select exists (select 1 from cov_session cs
                      join catalog.event_session es on es.session_id = cs.session_id
                      join catalog.event e on e.event_id = es.event_id
                     where es.status = 'cancelled' or e.status = 'cancelled')),
    -- NON-TERMINAL refund: kernel.refund runs pending → submitted →
    -- succeeded|failed (085:82-85). Money is still in motion in the first two.
    (select exists (select 1 from cov c join kernel.refund r on r.payment_id = c.payment_id
                     where r.status in ('pending','submitted'))),
    -- OPEN dispute: the four non-terminal members of dispute_native.status.
    -- 'won'/'warning_closed' are closed favourably; 'lost'/'charge_refunded'
    -- are closed adversely AND already lined by 10h.
    (select exists (select 1 from cov c join kernel.dispute_native d on d.payment_id = c.payment_id
                     where d.status in ('warning_needs_response','warning_under_review','needs_response','under_review')))
    into v_unresolved, v_sess_n, v_sess_no_end, v_anchor, v_cancelled, v_refund_open, v_dispute_open;

  -- FIRST FAILING PREDICATE WINS THE CODE, in causal order: you cannot ask
  -- whether money has matured until you know the policy, what the money is
  -- about, and when the event ended. The FULL vector rides in 'detail', so
  -- precedence hides nothing.
  v_reason := case
    when v_maturity is null                                    then 'unbounded_refund_exposure'
    when v_maturity < interval '0'                             then 'maturity_policy_invalid'
    when coalesce(v_unresolved, 1) > 0                         then 'covered_set_unresolvable'
    when coalesce(v_cancelled, true)                           then 'event_cancelled'
    when coalesce(v_sess_n, 0) = 0
      or coalesce(v_sess_no_end, 1) > 0
      or v_anchor is null                                      then 'maturity_instant_unknown'
    when now() < v_anchor + v_maturity                         then 'maturity_not_elapsed'
    when coalesce(v_refund_open, true)                         then 'refund_in_flight'
    when coalesce(v_dispute_open, true)                        then 'dispute_open'
    else null
  end;

  return jsonb_build_object(
    'hold_reason', v_reason,
    'detail', jsonb_build_object(
      'maturity_interval',  case when v_maturity is null then null else v_maturity::text end,
      'maturity_anchor',    v_anchor,
      'matures_at',         case when v_anchor is null or v_maturity is null then null else (v_anchor + v_maturity) end,
      'covered_sessions',   v_sess_n, 'sessions_without_end', v_sess_no_end,
      'unresolvable_lines', v_unresolved, 'event_cancelled', v_cancelled,
      'refund_in_flight',   v_refund_open, 'dispute_open', v_dispute_open));
end;
$$;

-- Called by kernel.close_settlement (10d, SECURITY DEFINER) and
-- kernel.request_org_payout (10k, SECURITY DEFINER, `authenticated`) as well as
-- by the service_role executor read (10n). A DEFINER caller executes it under
-- the definer's privileges, so no client grant is needed or wanted: it is a
-- money gate, not a read model.
revoke all on function kernel.settlement_payout_maturity(uuid) from public, anon, authenticated;
grant execute on function kernel.settlement_payout_maturity(uuid) to service_role;


-- ============================================================================
-- 10n — kernel.get_payout_execution_context: the payout executor's ONLY read,
--   and the place the payout decision is actually MADE.
--   H3 §5 · H6 (the destination cross-check) · H8 · the 10g/10i house pattern.
--
--   THE INVARIANT. PAYOUT-ROW-DRIVEN, and more than that: THE DATABASE DECIDES
--   whether this payout may be executed, in SQL, here. The worker receives
--   `execution_eligible` and a `refusal_code`; it does not receive the
--   ingredients of a decision it could reach differently. There is no parameter
--   for an organization, a destination, an amount or a settlement — the ONLY
--   parameter is a payout id, and every other fact is resolved from it. A
--   worker cannot select a destination, cannot choose an amount, cannot name an
--   org, and cannot pay a settlement whose ledger disagrees with the payout row.
--
--   THE AMOUNT IS NOT RECOMPUTED HERE AND MUST NEVER BE. kernel.close_settlement
--   (10d) already ran the waterfall — gross − fees − refunds, with the promoter
--   commission already deducted as a negative line — and wrote it to
--   venue.settlement.net_minor and kernel.payout.amount_minor in ONE
--   transaction. This function only proves the two still AGREE
--   ('amount_ledger_mismatch'). That equality is the whole anti-tamper control:
--   a payout row cannot be edited into a larger number without the closed,
--   waterfall-constrained header (settlement_waterfall_ck, 087) agreeing, and a
--   closed header cannot move because its lines are append-only.
--
--   THE DESTINATION IS THE PINNED ONE (payout.destination_ref, 10j), NOT A
--   FRESH READ — and the organization's CURRENT ref is returned beside it so
--   the divergence is a fact the executor can see rather than a race it cannot.
--   Four destination predicates, all fail-closed, all here rather than in the
--   worker:
--     'destination_not_bound'        the payout was authorized before 10j, or
--                                    by something that is not request_org_payout
--     'destination_changed'          pinned <> current: the payee moved after
--                                    the approval. NEVER pay either one — 10o
--                                    de-authorizes instead
--     'connect_transfers_inactive'   the org's own transfers mirror is false.
--                                    F: this column is read by three functions
--                                    and NONE of them was on the payout path
--     'org_not_active'               organization.status not in
--                                    (approved, active). A SUSPENDED org could
--                                    be paid out today; 093 gates both binders
--                                    on status but nothing gated the payout.
--                                    The individual seller rail already does
--                                    this at attempt time
--                                    (_shared/payouts.ts:83-96); the org rail
--                                    had no equivalent until now.
--   plus the two that were already implicit:
--     'destination_individual_plane' the identifier belongs to the PERSONAL
--                                    seller plane (public.profiles.stripe_connect_id,
--                                    002:25, or the 044 archive). An
--                                    organization settlement must never land in
--                                    a personal seller's Connect account
--     'destination_cooldown'         payout_destination_locked_until is in the
--                                    future — the same operand
--                                    request_org_payout blocks on (087:443),
--                                    re-asserted because the request may be
--                                    days old.
--   The remaining destination fact — Stripe's own `capabilities.transfers` —
--   is not ours to hold, and is preflighted by the executor BEFORE an
--   idempotency key is spent (H3 §5 step 3).
--
--   WHY MATURITY IS RE-EVALUATED RATHER THAN READ OFF hold_state. 10d's gate
--   ran at CLOSE. A settlement payout is executed at least one maturity
--   interval later — by construction, weeks. In that window a covered refund
--   can reach 'succeeded', a dispute can open, and an event can be cancelled;
--   none of those rewrite hold_state, because nothing sweeps closed
--   settlements. Trusting the close-time verdict is trusting a stale fact about
--   money. So 10m — the SAME conjunction the mint used, not a second copy of it
--   — is re-evaluated here against now(), and its verdict is adopted whole in a
--   single `when`. hold_state is ALSO checked, and FIRST among the money gates:
--   a human hold and a platform risk hold refuse before anything else is
--   considered.
--
--   THE STALENESS RE-CHECK (H3 §5 step 4 / §7.1) IS THE ONE PREDICATE 10d DOES
--   NOT HAVE. venue.settlement_line is append-only under a unique
--   (settlement_id, cause, cause_ref), so a refund that reaches 'succeeded'
--   AFTER close cannot reduce the header it was never lined into. Its money
--   carries forward to the NEXT settlement (H3 §7.2), but the payout in hand is
--   then an obligation computed before that fact existed. So: Σ succeeded
--   refunds over the covered payments is compared with the closed header's own
--   refunds_minor, and an exposure that EXCEEDS what the header booked refuses
--   with 'refund_exposure_stale'. The executor never pays a stale obligation —
--   and it does not decide that, this does.
--
--   NON-ENUMERABLE, like 10g. An unknown payout id yields SQL NULL, which the
--   executor maps to 404 — never a partial object, never a distinguishable
--   shape.
--
--   WHAT IT DOES NOT PROJECT. No buyer, no order, no ticket atom, no
--   PaymentIntent, no charge, no line detail, no identity of any kind. The
--   destination IS projected — it is the one field the executor cannot do
--   without — which is precisely why this verb carries the same service_role-
--   only grant as kernel.get_org_connect_ref (slice 30 §7), and must never be
--   widened.
-- ============================================================================
create or replace function kernel.get_payout_execution_context(p_payout_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_po           kernel.payout%rowtype;
  v_st           venue.settlement%rowtype;
  v_org          kernel.organization%rowtype;
  v_pinned       text;
  v_current      text;
  v_dest_indiv   boolean := false;
  -- The G2 conjunction is NOT re-implemented here; it is 10m's verdict, verbatim.
  v_maturity     jsonb;
  -- The one predicate 10m cannot carry, because it is meaningless at the mint.
  v_stale_minor  bigint := 0;
  v_code         text;
begin
  select * into v_po from kernel.payout where payout_id = p_payout_id;
  if not found then
    return null;                      -- non-enumerable: 404 at the edge
  end if;

  select * into v_st from venue.settlement where settlement_id = v_po.cause_ref;
  if v_po.payee_org_id is not null then
    select * into v_org from kernel.organization o where o.org_id = v_po.payee_org_id;
  end if;
  v_pinned  := v_po.destination_ref;
  v_current := v_org.stripe_connect_account_ref;   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)

  -- CROSS-PLANE: the personal seller Connect plane is not a payout destination
  -- for an organization settlement. Both the live column (002:25) and the 044
  -- archive are consulted, against the PINNED value — the one that would be
  -- sent. A NULL pin trivially matches neither.
  if v_pinned is not null then
    v_dest_indiv := exists (select 1 from public.profiles pr where pr.stripe_connect_id = v_pinned)
                 or exists (select 1 from public.stripe_connect_archive ar where ar.stripe_connect_id = v_pinned);
  end if;

  -- THE G2 CONJUNCTION IS NOT RE-IMPLEMENTED HERE. One definition (10m), three
  -- call sites: the mint (10d), the pending→submitted advance (10k), and this,
  -- the transfer. Re-evaluated against now(), so a refund that succeeded, a
  -- dispute that opened or an event that was cancelled AFTER the close is seen.
  v_maturity := kernel.settlement_payout_maturity(v_po.cause_ref);

  -- THE STALENESS OPERAND (H3 §5 step 4 / §7.1) — the one predicate 10m does
  -- not carry, because at the mint the lines were just written and it can only
  -- read zero. Per covered order: the settled refund exposure the ledger is
  -- ENTITLED to book, capped at the order's face value exactly as 10b caps
  -- 'refund_void', minus what has actually been lined for that order in ANY
  -- settlement. A positive remainder means money has left for the buyer that no
  -- settlement has debited, so the payout in hand is an obligation computed
  -- before that fact existed.
  --
  -- THE FACE CAP IS LOAD-BEARING, NOT DECORATION. kernel.refund.amount_minor is
  -- measured against public.payments.total = amount + buyer_fee (000:978-985),
  -- while a 'refund_void' line is capped at the order's face value because the
  -- buyer-side service fee is platform money under ruling A5. Comparing raw
  -- refund sums against refunds_minor would therefore fire on every ordinary
  -- fee-bearing refund and STRAND the venue's money — a false positive here is
  -- not conservative, it is the same permanent loss by another route.
  select coalesce(sum(x.entitled - x.lined), 0)::bigint into v_stale_minor
    from (
      select least(
               coalesce((select sum(r.amount_minor) from kernel.refund r
                          where r.payment_id = c.payment_id and r.status = 'succeeded'), 0),
               coalesce((select o.total_minor from venue."order" o
                          join kernel.payment_native pn on pn.order_id = o.order_id
                         where pn.payment_id = c.payment_id), 0))::bigint as entitled,
             coalesce((select sum(-l.amount_minor) from venue.settlement_line l
                        join kernel.refund r2 on r2.refund_id = l.cause_ref
                       where l.cause = 'refund_void' and r2.payment_id = c.payment_id), 0)::bigint as lined
        from (select distinct cp.payment_id
                from kernel.settlement_covered_payments(v_po.cause_ref) cp
               where cp.payment_id is not null) c
    ) x
   where x.entitled > x.lined;

  -- FIRST FAILING PREDICATE WINS, in causal order: identity and binding before
  -- money, money before the payee, the payee before maturity, maturity before
  -- staleness. Everything below REFUSES; nothing here is advisory.
  v_code := case
    -- ── binding: is this even a settlement payout to an organization? ──────
    when v_po.cause <> 'settlement'                        then 'cause_not_settlement'
    when v_po.payee_kind <> 'organization'
      or v_po.payee_org_id is null                         then 'payee_not_organization'
    -- ── the row's own state ───────────────────────────────────────────────
    when v_po.hold_state <> 'none'                         then 'payout_held'
    when v_po.status <> 'submitted'                        then 'payout_not_submitted'
    when v_po.stripe_transfer_ref is not null              then 'transfer_already_recorded'
    when v_po.amount_minor is null
      or v_po.amount_minor <= 0                            then 'amount_not_positive'
    when upper(coalesce(v_po.currency,'')) <> 'USD'        then 'currency_unsupported'
    -- ── the obligation ────────────────────────────────────────────────────
    when v_st.settlement_id is null                        then 'settlement_not_found'
    when v_st.org_id is distinct from v_po.payee_org_id    then 'org_mismatch'
    when v_st.status <> 'closed'                           then 'settlement_not_closed'
    when upper(coalesce(v_st.currency,'')) <> upper(coalesce(v_po.currency,''))
                                                           then 'currency_mismatch'
    when v_st.net_minor is distinct from v_po.amount_minor then 'amount_ledger_mismatch'
    -- ── the payee (H6) ────────────────────────────────────────────────────
    when v_org.org_id is null                              then 'organization_not_found'
    when v_org.status not in ('approved','active')         then 'org_not_active'
    when v_pinned is null                                  then 'destination_not_bound'
    when v_pinned !~ '^acct_[A-Za-z0-9]+$'                 then 'destination_malformed'
    when v_dest_indiv                                      then 'destination_individual_plane'
    when v_current is null                                 then 'no_payout_destination'
    when v_pinned is distinct from v_current               then 'destination_changed'
    when not coalesce(v_org.connect_transfers_active, false) then 'connect_transfers_inactive'
    when v_org.payout_destination_locked_until is not null
     and v_org.payout_destination_locked_until > now()     then 'destination_cooldown'
    -- ── maturity: 10m's verdict, adopted whole. ONE line, so this gate and
    --    the mint gate cannot disagree about what "matured" means. ──────────
    when (v_maturity ->> 'hold_reason') is not null        then v_maturity ->> 'hold_reason'
    -- ── staleness (H3 §5 step 4) ──────────────────────────────────────────
    when v_stale_minor > 0                                 then 'refund_exposure_stale'
    else null
  end;

  return jsonb_build_object(
    'payout_id',              v_po.payout_id,
    'cause',                  v_po.cause,
    'settlement_id',          v_po.cause_ref,
    'payee_kind',             v_po.payee_kind,
    'payee_org_id',           v_po.payee_org_id,
    'amount_minor',           v_po.amount_minor,
    'currency',               v_po.currency,
    'status',                 v_po.status,
    'hold_state',             v_po.hold_state,
    'hold_reason_code',       v_po.hold_reason_code,
    'stripe_transfer_ref',    v_po.stripe_transfer_ref,
    'source_transaction_ref', v_po.source_transaction_ref,   -- H3 §3: NULL on this rail, always
    'created_at',             v_po.created_at,
    -- the obligation, for the executor's own equality assertion and the audit
    'settlement_org_id',        v_st.org_id,
    'settlement_status',        v_st.status,
    'settlement_net_minor',     v_st.net_minor,
    'settlement_refunds_minor', v_st.refunds_minor,
    'settlement_currency',      v_st.currency,
    -- the payee: PINNED is what gets sent; CURRENT is what it is checked against
    'destination',              v_pinned,
    'destination_ref',          v_pinned,
    'org_connect_ref_current',  v_current,
    'org_status',               v_org.status,
    'connect_transfers_active', coalesce(v_org.connect_transfers_active, false),
    'destination_locked_until', v_org.payout_destination_locked_until,
    'destination_individual_plane', v_dest_indiv,
    -- transfer_group: the ONLY durable handle back to a transfer whose response
    -- was lost after the 24h idempotency window (H3 §6).
    'transfer_group',         'payout_' || v_po.payout_id::text,
    -- THE VERDICT. The worker consumes this; it does not re-derive it.
    'execution_eligible',     (v_code is null),
    'refusal_code',           v_code,
    'maturity_detail',        coalesce(v_maturity -> 'detail', '{}'::jsonb)
                                || jsonb_build_object('unbooked_refund_exposure_minor', v_stale_minor));
end;
$$;

-- EXEC DEF (§0.1a): a MACHINE verb on the money execution path, and the ONE
-- verb in this slice that discloses a payout destination. service_role only,
-- never a client — the same posture kernel.get_org_connect_ref carries, and for
-- the same reason. Revoke the default PUBLIC EXECUTE first (076 discipline).
revoke all on function kernel.get_payout_execution_context(uuid) from public, anon, authenticated;
grant execute on function kernel.get_payout_execution_context(uuid) to service_role;


-- ============================================================================
-- 10o — kernel.hold_payout_destination_changed: DE-AUTHORIZE, never pay, never
--   fail. H6 · H3 §6 (the absorbing-'failed' constraint).
--
--   THE PROBLEM. A payout whose pinned destination no longer matches the
--   organization's — or whose org has been suspended, or whose transfers
--   capability has gone false — must not be paid to EITHER address. But the
--   executor cannot write 'failed' (085's state machine has no edge out of it;
--   see 10o), and it cannot call kernel.hold_payout: that verb is gated on
--   kernel.is_platform, which tests auth.uid() and is NULL on a machine
--   session, AND it is not granted to service_role at all (verified on the
--   rehearsal database: has_function_privilege('service_role',
--   'kernel.hold_payout(uuid,text,text)','EXECUTE') = false). Leaving the row
--   'submitted' would let the next tick try again forever against a payee that
--   is no longer authorized.
--
--   WHAT IT DOES. submitted → pending, hold_state='held',
--   hold_reason_code='destination_changed'. That is a DE-AUTHORIZATION, not a
--   money state: it returns the payout to the state it was in before
--   request_org_payout advanced it, and holds it so the advance cannot happen
--   again without a human. The recovery path is the correct one and already
--   exists: a platform_risk/platform_admin releases the hold
--   (kernel.release_payout — the sole release path), the org re-requests, and
--   request_org_payout re-runs SoD-1, money-role maturity, the aal2 step-up,
--   the cool-down, destination probation and dual control against the NEW
--   destination, then re-pins it (10k). The new payee earns its own approval
--   instead of inheriting one.
--
--   IT IS THE ONLY BACKWARD STATUS EDGE IN THE SYSTEM, AND IT IS DELIBERATE.
--   Every other transition is forward-only. This one is safe precisely because
--   it moves AWAY from executability: 'pending' + held is strictly less
--   capable than 'submitted', mark_payout_transfer_state refuses a held row
--   outright (085:1690) with BOTH columns untouched, and request_org_payout
--   refuses a risk-held row (087:462-464). It is guarded by
--   stripe_transfer_ref is null, so a payout that has already reached Stripe
--   can never be walked back by this verb.
--
--   THE WORKER CANNOT CHOOSE TO USE IT. It takes no destination and no reason:
--   the function RE-DERIVES the fault itself from kernel.payout.destination_ref
--   and kernel.organization, and RAISES precondition_failed when there is no
--   fault. A worker cannot demote a healthy payout, and cannot pick which
--   fault it is reporting. p_observed_ref is recorded in the audit as the
--   worker's OBSERVATION and is never used in a predicate.
-- ============================================================================
create or replace function kernel.hold_payout_destination_changed(
  p_payout_id uuid, p_observed_ref text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_po   kernel.payout%rowtype;
  v_org  kernel.organization%rowtype;
  v_code text;
begin
  select * into v_po from kernel.payout where payout_id = p_payout_id for update;
  if not found then
    raise exception 'not_found: payout %', p_payout_id using errcode = 'P0002';
  end if;
  if v_po.cause <> 'settlement' or v_po.payee_kind <> 'organization' then
    raise exception 'precondition_failed: not an organization settlement payout' using errcode = 'P0001';
  end if;
  if v_po.stripe_transfer_ref is not null then
    raise exception 'precondition_failed: transfer_already_recorded' using errcode = 'P0001';
  end if;
  if v_po.status <> 'submitted' then
    raise exception 'precondition_failed: payout is %, not submitted', v_po.status using errcode = 'P0001';
  end if;
  if v_po.hold_state <> 'none' then
    return jsonb_build_object('status','noop_replay','payout_id', p_payout_id,
                              'hold_reason_code', v_po.hold_reason_code);
  end if;

  select * into v_org from kernel.organization o where o.org_id = v_po.payee_org_id for update;

  -- THE FAULT IS RE-DERIVED HERE. The caller's observation is evidence, never a
  -- predicate. Same order as 10n so the two never disagree about which fault it
  -- is.
  v_code := case
    when v_org.org_id is null                                 then 'organization_not_found'
    when v_org.status not in ('approved','active')            then 'org_not_active'
    when v_po.destination_ref is null                         then 'destination_not_bound'
    when v_org.stripe_connect_account_ref is null             then 'no_payout_destination'   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
    when v_po.destination_ref is distinct from v_org.stripe_connect_account_ref then 'destination_changed'   -- x6-allow: naming-only (money-engine operand, kernel.organization; outside the export closure — 152 C4)
    when not coalesce(v_org.connect_transfers_active, false)  then 'connect_transfers_inactive'
    else null
  end;
  if v_code is null then
    raise exception 'precondition_failed: no_destination_fault — the pinned destination still matches and the payee is still payable'
      using errcode = 'P0001';
  end if;

  update kernel.payout
     set status           = 'pending',
         hold_state       = 'held',
         hold_reason_code = 'destination_changed',
         held_by          = null,
         held_at          = now(),
         updated_at       = now()
   where payout_id = p_payout_id;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values ('00000000-0000-0000-0000-0000000000f1', 'payout.destination_hold', 'payout', p_payout_id, v_code,
          jsonb_build_object('status', v_po.status, 'hold_state', v_po.hold_state,
                             'destination_ref', v_po.destination_ref),
          jsonb_build_object('status', 'pending', 'hold_state', 'held',
                             'fault', v_code,
                             'org_status', v_org.status,
                             'connect_transfers_active', coalesce(v_org.connect_transfers_active, false),
                             'observed_ref', left(coalesce(p_observed_ref,''), 64),
                             'command_key', left(coalesce(p_command_key,''), 64)));

  -- best-effort notice: a human must release this, so a human must hear about it.
  begin
    perform notify.emit_event('payout_on_hold', 'payout', p_payout_id,
            'payout_destination_hold:' || p_payout_id::text,
            jsonb_build_object('reason', v_code, 'amount_minor', v_po.amount_minor));
  exception when others then null; end;

  return jsonb_build_object('status','held','payout_id', p_payout_id, 'fault', v_code);
end;
$$;

revoke all on function kernel.hold_payout_destination_changed(uuid, text, text)
  from public, anon, authenticated;
grant execute on function kernel.hold_payout_destination_changed(uuid, text, text) to service_role;


-- ============================================================================
-- 10p — kernel.claim_payouts_for_execution: the payout worker's work list.
--   The same primitive kernel.claim_refunds_for_execution (10i) is, for the
--   payout rail, and deliberately its mirror image line for line.
--
--   WHY A CLAIM AND NOT A LIST. Two workers on one payout that both reach
--   Stripe inside the 24h idempotency window are harmless (one key, one
--   transfer). Two workers a day apart are NOT: Stripe forgets a key after 24h
--   (<https://docs.stripe.com/api/idempotent_requests>), so the second attempt
--   would create a SECOND transfer of the same money. The lease is what stops a
--   crashed worker's row being re-attempted immediately by the herd, and the
--   `execution_mode` below is what stops a stale retry creating money.
--
--   THE 20-HOUR WINDOW IS THE WHOLE POINT OF `execution_mode`. Inside it,
--   Stripe still holds the key, so a replay is a replay: mode 'create'. Outside
--   it the key is gone and a bare POST would MINT A SECOND TRANSFER: mode
--   'reconcile', which obliges the executor to read
--   GET /v1/transfers?transfer_group=payout_<id> and adopt what it finds before
--   it is allowed to create anything. Four hours of margin on Stripe's 24.
--
--   WHAT THIS VERB CANNOT DO, BY CONSTRUCTION. It takes no payout id, no
--   organization, no settlement, no destination and no amount: there is NO
--   parameter by which a caller can name a subject at all. It returns payout
--   ids and a mode. It moves no money, transitions no payout
--   (mark_payout_transfer_state, 085:1668, remains the only writer of status to
--   a terminal and of stripe_transfer_ref), and projects NO DESTINATION AND NO
--   AMOUNT — the executor must still go through 10n for those, under 10n's own
--   gate. The destination is deliberately absent here even though it is pinned
--   on the row: the claim's job is to hand out work, and 10n's job is to prove
--   the work is still authorized. Two verbs, two questions.
--
--   THE ELIGIBLE SET IS NARROWER THAN THE REFUND ONE, AND ONLY ON PURPOSE:
--     cause='settlement'          — the promoter-commission payout
--                                   (090:1483-1491) is minted held/unfunded and
--                                   is NEVER this executor's business (H3 §9).
--     payee_kind='organization'   — the identity plane has no settlement rail.
--     status='submitted'          — 'pending' has not passed request_org_payout's
--                                   controls (SoD-1, money-role maturity, aal2
--                                   step-up, cool-down, probation, dual
--                                   control) and must not be short-circuited by
--                                   a machine.
--     hold_state='none'           — a held payout is refused by
--                                   mark_payout_transfer_state anyway
--                                   (085:1690); refusing it here means no key
--                                   is ever spent on one.
--     stripe_transfer_ref is null — the DB-side idempotency stop (H3 §6). A row
--                                   that already carries a ref is finished with
--                                   Stripe whatever its status says.
--     destination_ref is not null — un-pinned means un-authorized under 10j.
--
--   'failed' IS ABSENT FROM THE ELIGIBLE SET AND CANNOT BE ADDED. Verified
--   EMPIRICALLY against the live state machine on a rehearsal database:
--   submitted→failed is accepted; failed→paid raises
--   'payout_state_backwards (failed → paid)'; failed→reversed raises the same;
--   failed→submitted raises 'invalid_input' because
--   mark_payout_transfer_state accepts only paid|failed|reversed. There is NO
--   edge out of 'failed'. request_org_payout only ever selects status in
--   ('pending','submitted'), and close_settlement's mint is
--   `on conflict (idempotency_key) do nothing` on 'settlement:'||settlement_id,
--   so it can never re-mint. A failed settlement payout is UNRECOVERABLE money.
--   THAT is why the executor this feeds NEVER writes 'failed' — every
--   non-success leaves the row 'submitted', which this function hands out again.
--
--   THE COMMAND KEY IS DB-DERIVED. `payout.execute:<payout_id>` is returned
--   rather than minted by the worker, so the audit identity of an execution
--   attempt comes from the durable payout fact and two workers on one payout
--   cannot land under two audit identities. 51 chars: inside admin_audit's
--   budget with no truncation.
--
--   ATOMICITY. `for update ... skip locked` on kernel.payout is what makes the
--   claim exclusive: a concurrent claimer never even evaluates a row another
--   transaction holds, and by the time the lock is released the claim's audit
--   row is committed and the `not exists` predicate excludes it for the lease.
--   The row lock ends with this transaction; the LEASE is the audit row.
-- ============================================================================
create or replace function kernel.claim_payouts_for_execution(
  p_limit integer default 25, p_lease_seconds integer default 900)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Both operands are CLAMPED, not trusted — 10i's reasoning applies verbatim:
  -- a vacuous lease re-creates the herd this function exists to prevent, and an
  -- unbounded limit lets one tick claim the entire backlog and sit on it.
  v_limit   integer  := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_lease   integer  := least(greatest(coalesce(p_lease_seconds, 900), 60), 3600);
  -- Stripe retains an idempotency key's result for 24h; 4h of margin.
  v_window  constant interval := interval '20 hours';
  v_sys     constant uuid := '00000000-0000-0000-0000-0000000000f1';
  v_rows    jsonb := '[]'::jsonb;
  v_r       record;
  v_first   timestamptz;
  v_tries   integer;
  v_mode    text;
begin
  for v_r in
    select p.payout_id, p.created_at, p.status, p.stripe_transfer_ref
      from kernel.payout p
     where p.cause = 'settlement'
       and p.payee_kind = 'organization'
       and p.status = 'submitted'          -- the ONE unfinished, human-authorized state
       and p.hold_state = 'none'
       and p.stripe_transfer_ref is null   -- the DB-side idempotency stop
       and p.destination_ref is not null   -- un-pinned is un-authorized (10j)
       and not exists (
             select 1 from kernel.admin_audit a
              where a.subject_kind = 'payout'
                and a.subject_id   = p.payout_id
                and a.action       = 'payout.execute_claim'
                and a.occurred_at  > now() - make_interval(secs => v_lease))
     order by p.created_at, p.payout_id                     -- oldest money first
     limit v_limit
     for update skip locked
  loop
    select min(a.occurred_at), count(*)::integer into v_first, v_tries
      from kernel.admin_audit a
     where a.subject_kind = 'payout' and a.subject_id = v_r.payout_id
       and a.action = 'payout.execute_claim';

    if v_first is null or v_first > now() - v_window then
      v_mode := 'create';                          -- key unused, or still deduped
    else
      v_mode := 'reconcile';                       -- key expired: establish, then act
    end if;

    insert into kernel.admin_audit
           (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_sys, 'payout.execute_claim', 'payout', v_r.payout_id, v_mode,
            jsonb_build_object('status', v_r.status,
                               'stripe_transfer_ref', v_r.stripe_transfer_ref),
            jsonb_build_object('execution_mode', v_mode,
                               'attempt', v_tries + 1,
                               'lease_seconds', v_lease,
                               'first_attempt_at', coalesce(v_first, now())));

    v_rows := v_rows || jsonb_build_object(
      'payout_id',      v_r.payout_id,
      'created_at',     v_r.created_at,
      'status',         v_r.status,
      'execution_mode', v_mode,
      'attempt',        v_tries + 1,
      'command_key',    'payout.execute:' || v_r.payout_id::text);
  end loop;

  return jsonb_build_object('payouts', v_rows,
                            'lease_seconds', v_lease,
                            'claimed_at', now());
end;
$$;

-- EXEC DEF (§0.1a): a MACHINE verb on the money execution path — service_role
-- only, never a client. Revoke the default PUBLIC EXECUTE first (076 discipline).
revoke all on function kernel.claim_payouts_for_execution(integer, integer)
  from public, anon, authenticated;
grant execute on function kernel.claim_payouts_for_execution(integer, integer) to service_role;


-- ============================================================================
-- 10q — kernel.record_payout_execution_note: the executor's ONLY write on an
--   ordinary non-success path, and the reason it never needs 'failed'.
--
--   THE PROBLEM IT SOLVES. Every non-success in the payout executor leaves the
--   row 'submitted' (H3 §6), because 'failed' is absorbing and would strand the
--   venue's money forever. That is the right call, but on its own it makes a
--   repeatedly-refused payout INVISIBLE: it looks exactly like one that has not
--   been attempted yet. This verb is the difference between a recoverable hang
--   and a silent one. It writes an immutable audit row and NOTHING else.
--
--   IT CANNOT CHANGE STATE, AND THAT IS THE POINT. It does not touch
--   kernel.payout — not status, not hold_state, not stripe_transfer_ref, not
--   destination_ref. The one non-success path that DOES change state is 10o,
--   which is a de-authorization and re-derives its own fault. Everything else
--   is an audit row plus a notification, and a HUMAN decides what to do.
--
--   The reason code is clamped to 120 characters, matching the money-denial
--   convention, and the detail is a jsonb the executor fills with the evidence
--   it had at the moment it refused — 10n's refusal code, the Stripe error
--   class, the destination state it probed, the balance shortfall.
-- ============================================================================
create or replace function kernel.record_payout_execution_note(
  p_payout_id uuid, p_reason_code text, p_detail jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_exists boolean;
begin
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'invalid_input: reason_code is mandatory';
  end if;
  select exists (select 1 from kernel.payout where payout_id = p_payout_id) into v_exists;
  if not v_exists then
    raise exception 'not_found: payout %', p_payout_id using errcode = 'P0002';
  end if;
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values ('00000000-0000-0000-0000-0000000000f1', 'payout.execute_note', 'payout', p_payout_id,
          left(trim(p_reason_code), 120),
          jsonb_build_object('command_key', left(coalesce(p_command_key,''), 64)),
          coalesce(p_detail, '{}'::jsonb));
  return jsonb_build_object('status','ok','payout_id', p_payout_id);
end;
$$;

revoke all on function kernel.record_payout_execution_note(uuid, text, jsonb, text)
  from public, anon, authenticated;
grant execute on function kernel.record_payout_execution_note(uuid, text, jsonb, text) to service_role;


-- ###########################################################################
-- ## SLICE: 20_payments_contract.sql
-- ###########################################################################

-- ============================================================================
-- 093 · PART 20 — THE PAYMENTS CONTRACT AMENDMENT
-- POST-FREEZE AMENDMENT **PFA-PT-3** — `public.payments` obligation re-scoped
-- from resale-only to BOTH RAILS (owner ratification 2026-09-02, ruling E:
-- "constrained relaxation plus an explicit rail-pairing constraint").
-- ----------------------------------------------------------------------------
-- Authorities (read, not assumed):
--   · docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md §E  — RATIFIED,
--     recorded as PFA-PT-3, classification POST-FREEZE AMENDMENT → 093.
--   · docs/phase2/_decisions/E_payments_reshape.md §6 (design), §6.2 (why the
--     resale rail is EXACTLY as strict after this as before), §6.3 (the RLS
--     disposition), §6.4 (the one named residual), §8 (statement order).
--   · docs/phase2/_rulings/H_migration_design.md §5.3 (the one lock that
--     matters; `set local lock_timeout`; `NOT VALID` explicitly rejected).
--   · docs/phase2/093_FINAL_PROPOSED_SCOPE.md §1 + manifest ("0 new policies,
--     0 DDL on any money-ledger table, venue.finalize_primary_order untouched").
--   · docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md:2392
--     (PUBLIC_PAYMENTS_NATIVE_SHAPE — the obligation this discharges).
-- ----------------------------------------------------------------------------
-- THE PROBLEM, IN BYTES. `public.payments` requires a listing, a seller and a
-- resale mode:
--   000_baseline_schema.sql:973  listing_id uuid NOT NULL references public.listings(id)
--   000_baseline_schema.sql:975  seller_id  uuid NOT NULL references auth.users(id)
--   000_baseline_schema.sql:995  mode       text NOT NULL check (mode in ('buy_now','auction'))
-- A venue-direct sale has NO listing and NO seller — its counterparty is an
-- organization. And the requirement is bolted in TWICE inside frozen 085:
--   085:42        kernel.payment_native.payment_id NOT NULL → public.payments(id)
--   085:1919-1937 venue.finalize_primary_order: `select p.buyer_id, p.total,
--                 p.status ... if not found then raise 'payment_unverified'`.
-- So the direct rail cannot record money until this table admits its shape.
-- ----------------------------------------------------------------------------
-- THE SHAPE OF THE FIX. Three DDL facts, ONE transaction:
--   1. widen the `mode` CHECK to admit the direct rail's label;
--   2. drop NOT NULL on `listing_id` and `seller_id` (catalogue-only);
--   3. re-impose BOTH requirements CONDITIONALLY via a rail-pairing CHECK.
-- Net loosening of the resale rail: **ZERO**. The enforcement moves from a
-- column constraint to a table constraint with identical effect — a resale row
-- carrying a null is still unstorable, it just fails 23514 instead of 23502.
-- Every one of the 12 live-rail breaks enumerated in E §2 (headed by the
-- create-payment-intent double-charge at :417-422 and the swallowed 23502 in
-- confirm-payment:243-273) REQUIRES a resale row carrying a null, and step 3
-- makes that row unstorable. The 87-site blast radius is not touched by this
-- part: no consumer is rewritten here — the constraint is simply made precise
-- enough that no consumer can ever meet a row it was not written for.
-- ----------------------------------------------------------------------------
-- WHAT THIS PART DELIBERATELY DOES NOT DO (each forbidden by name):
--   · NO column is added to public.payments — EDGE_FUNCTION_SPEC:1811-1817,
--     "No column is added to the frozen public.payments table — ever."
--     In particular NO `order_id`; the forward link lives only in
--     kernel.payment_native.order_id (085:43).
--   · NO sentinel listing and NO synthesized listing row —
--     POST_FREEZE_AMENDMENTS.md:2392 ("No fake listing row"), and E §5.2 which
--     forbids it a second time. A single sentinel would also cap the platform
--     at ONE succeeded direct sale forever via idx_payments_one_success_per_listing.
--   · NO use of the 019 anonymization sentinel user for seller_id. It buys the
--     identical RLS invisibility as NULL while making deleted-user rows and
--     venue-direct rows indistinguishable in the ledger (E §5.2).
--   · NO RLS policy is added, dropped or altered — see §4 below.
--   · NO rescope of idx_payments_one_success_per_listing — see §5 below.
--   · NO `create or replace` of venue.finalize_primary_order or any other 085
--     function. Its body needs only buyer_id, total and status (E §4), all of
--     which a direct row supplies. This is the decisive saving over option A:
--     no owner-signed authored-money-verb amendment is required.
--   · NO `NOT VALID`. H §5.3 rejects it explicitly: on 56 rows it buys nothing
--     and it opens exactly the window the ratification forbids — a period in
--     which a null is insertable with the pairing constraint not yet in force.
-- ----------------------------------------------------------------------------
-- TRANSACTION OWNERSHIP. This is a PART, not a migration. It emits no `begin;`
-- and no `commit;` — 093 is ONE apply and the three DDL facts above MUST land
-- in the same transaction as each other (ratification §E), so the assembled
-- migration owns the transaction boundary.
--
-- LOCK NOTE — THIS IS THE ONE ITEM IN 093 THAT TAKES A LOCK THAT MATTERS.
-- `public.payments` is the only LIVE table in the whole of 093 (56 production
-- rows) and the resale rail writes to it constantly (create-payment-intent,
-- stripe-webhook, enforce-transfer-expiry). Every statement below takes
-- ACCESS EXCLUSIVE: `drop not null` is catalogue-only and instant; the two
-- `add constraint` full-scan 56 rows, i.e. microseconds. The exclusive WINDOW
-- is trivial — the exclusive WAIT is not. Without a timeout this queues every
-- in-flight resale payment write behind a single slow reader. `set local
-- lock_timeout` therefore makes the migration FAIL FAST and be retried rather
-- than stall live payment writes. Per H §5.3 the setting is for the whole
-- transaction; it is emitted here, in the part that needs it, and is
-- deliberately NOT reset — if the 093 assembler hoists an identical
-- `set local lock_timeout` into its header, this line is a harmless no-op and
-- may be dropped.
-- ============================================================================

set local lock_timeout = '3s';


-- ============================================================================
-- 0. PRE-FLIGHT — assert the shape this amendment was written against
-- ----------------------------------------------------------------------------
-- The amendment was authored against 000:973/975/995 plus four purely additive
-- alterations (007 stripe_refund_id, 022 service_fee→buyer_fee + seller_fee,
-- 045 stripe_livemode). If the live catalogue is not that shape, the reasoning
-- above does not apply and we refuse rather than guess. Re-run tolerant: a
-- second application finds the columns already nullable and says so.
-- ============================================================================
do $$
declare
  v_listing_notnull boolean;
  v_seller_notnull  boolean;
  v_mode_notnull    boolean;
  v_bad             bigint;
begin
  select a.attnotnull into v_listing_notnull from pg_attribute a
   where a.attrelid = 'public.payments'::regclass and a.attname = 'listing_id'
     and not a.attisdropped;
  select a.attnotnull into v_seller_notnull  from pg_attribute a
   where a.attrelid = 'public.payments'::regclass and a.attname = 'seller_id'
     and not a.attisdropped;
  select a.attnotnull into v_mode_notnull    from pg_attribute a
   where a.attrelid = 'public.payments'::regclass and a.attname = 'mode'
     and not a.attisdropped;

  -- the exact column names are load-bearing: the pairing CHECK below names
  -- them, and 022 renamed a *different* column (service_fee→buyer_fee), so
  -- "the names are what 000 says" is a claim worth executing, not assuming.
  if v_listing_notnull is null or v_seller_notnull is null or v_mode_notnull is null then
    raise exception
      'PFA-PT-3 preflight: public.payments is missing one of listing_id/seller_id/mode — refusing to amend an unrecognised table';
  end if;

  -- mode NOT NULL is what makes the pairing CHECK below EXHAUSTIVE. A CHECK
  -- evaluates to NULL (and therefore PASSES) on a NULL input, so a nullable
  -- `mode` would silently open a third, unpaired rail. Assert it.
  if not v_mode_notnull then
    raise exception
      'PFA-PT-3 preflight: public.payments.mode is nullable — the rail-pairing CHECK would not be exhaustive';
  end if;

  if not v_listing_notnull and not v_seller_notnull then
    raise notice 'PFA-PT-3: listing_id/seller_id already nullable — re-run, proceeding idempotently';
  end if;

  -- the relaxation must start from a base that the pairing CHECK will accept.
  -- Deliberately phrased as the POST-amendment predicate, not the legacy one:
  -- on a first run every row is a resale row carrying both columns and
  -- satisfies the resale arm, and on a re-run existing direct rows satisfy the
  -- direct arm — so this stays true in both worlds. Phrasing it as "every row
  -- is legacy" would make the part fail on its own second application. It also
  -- catches an unrecognised `mode` before §1 widens the vocabulary. Without it,
  -- §3's immediate validation would fail with a bare 23514 and no reason.
  select count(*) into v_bad from public.payments
   where not (
     (mode in ('buy_now', 'auction') and listing_id is not null and seller_id is not null)
     or
     (mode = 'native_primary' and listing_id is null and seller_id is null)
   );
  if v_bad > 0 then
    raise exception
      'PFA-PT-3 preflight: % existing public.payments row(s) would fail payments_rail_pairing_ck — investigate before relaxing', v_bad;
  end if;
end $$;


-- ============================================================================
-- 1. WIDEN `mode` — admit the direct rail's label
-- ----------------------------------------------------------------------------
-- BEFORE: mode text NOT NULL check (mode in ('buy_now','auction'))   [000:995]
-- AFTER : mode text NOT NULL check (mode in ('buy_now','auction','native_primary'))
--
-- WHY 'native_primary' and not a new invented word: it is the frozen
-- PaymentIntent-metadata vocabulary. EDGE_FUNCTION_SPEC:373 specifies the
-- direct-rail PI metadata as `{ rail:'native_primary', order_id, buyer_id,
-- org_id, session_id }`, and :1206/:1211 key the webhook's new branches off
-- `metadata.rail` with `external` = existing behaviour. The column and the
-- metadata now say the same word.
--
-- WHY THIS IS SAFE TO WIDEN AT ALL — VERIFIED, not assumed: `payments.mode`
-- has **zero SQL consumers**. A grep of every migration for a `payments`-scoped
-- `mode` reference returns nothing; the only `.mode` hits in 085/088/092 are
-- `market.resale_policy.mode` (088:978-989, :1409-1415), an unrelated column.
-- Dispatch on mode happens in TypeScript over STRIPE METADATA, not over this
-- column, and 074:172-177 pins that fact in the tree: both dynamic RPC call
-- sites (stripe-webhook/index.ts:405, web/src/lib/checkout.ts:163) are "a
-- CLOSED two-branch selection on metadata.mode over exactly
-- { 'mark_listing_sold', 'complete_auction_payment' }". Nothing in the database
-- reads public.payments.mode. Adding a value to the CHECK is therefore purely
-- additive: all 56 production rows satisfy the widened form unchanged.
--
-- The constraint is located BY CATALOGUE, not by name. 000:995 authored it as
-- an inline column CHECK, so PostgreSQL named it `payments_mode_check`; we do
-- not depend on that, we find the sole check constraint whose key is exactly
-- {mode} and refuse if there is more than one.
-- ============================================================================
do $$
declare
  v_attnum smallint;
  v_conname text;
  v_n int;
begin
  select a.attnum into v_attnum from pg_attribute a
   where a.attrelid = 'public.payments'::regclass and a.attname = 'mode'
     and not a.attisdropped;

  -- conkey is int2vector; cast to smallint[] so the array equality operator is
  -- the one we mean (there is no cast the other way).
  select count(*) into v_n from pg_constraint c
   where c.conrelid = 'public.payments'::regclass
     and c.contype = 'c'
     and c.conkey::smallint[] = array[v_attnum]::smallint[];

  if v_n > 1 then
    raise exception
      'PFA-PT-3: % check constraints key ONLY public.payments.mode; 000 authored exactly one — refusing to guess which to widen', v_n;
  elsif v_n = 1 then
    select c.conname into v_conname from pg_constraint c
     where c.conrelid = 'public.payments'::regclass
       and c.contype = 'c'
       and c.conkey::smallint[] = array[v_attnum]::smallint[];
    execute format('alter table public.payments drop constraint %I', v_conname);
  end if;
  -- v_n = 0: already dropped by an interrupted run; the add below is guarded.
end $$;

do $$ begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.payments'::regclass
       and conname  = 'payments_mode_check'
  ) then
    alter table public.payments
      add constraint payments_mode_check
      check (mode in ('buy_now', 'auction', 'native_primary'));
  end if;
end $$;


-- ============================================================================
-- 2. RELAX — drop the two NOT NULLs
-- ----------------------------------------------------------------------------
-- Catalogue-only: `drop not null` clears pg_attribute.attnotnull and rewrites
-- no heap. The FOREIGN KEYS are RETAINED UNCHANGED — listing_id still
-- references public.listings(id) and seller_id still references
-- auth.users(id); a foreign key simply does not apply to a NULL, so a
-- non-null value is still forced to name a real listing / a real user.
-- Idempotent by definition — `drop not null` on an already-nullable column is
-- a no-op, not an error.
--
-- This statement, on its own, would be the dangerous change the adversarial
-- review describes. It is never on its own: §3 lands in the same transaction,
-- so there is no instant at which a null is insertable on the resale rail.
-- ============================================================================
alter table public.payments alter column listing_id drop not null;
alter table public.payments alter column seller_id  drop not null;


-- ============================================================================
-- 3. RE-IMPOSE — the rail-pairing CHECK  ← THE LOAD-BEARING STATEMENT
-- ----------------------------------------------------------------------------
-- This is the constraint that makes §2 safe. It re-imposes BOTH dropped NOT
-- NULLs conditionally, and it pins the mode to the rail in the same breath, so
-- no row can sit half-way between the two rails:
--
--   RESALE / LEGACY arm : mode in ('buy_now','auction')
--                         → listing_id NOT NULL **and** seller_id NOT NULL
--   DIRECT / PRIMARY arm: mode = 'native_primary'
--                         → listing_id IS NULL   **and** seller_id IS NULL
--
-- Exhaustive because `mode` is NOT NULL (asserted in §0) and constrained by
-- §1 to exactly those three values. Every other combination — a 'buy_now' row
-- missing a seller, a 'native_primary' row carrying a listing, a 'native_primary'
-- row carrying a seller, a resale row with a listing but no seller — is
-- rejected 23514 at INSERT. The eight-way truth table has exactly two
-- satisfying rows and they are the two rails.
--
-- NO CONTRADICTION WITH ANY EXISTING CHECK. The complete set on this table is:
--   amount > 0 · buyer_fee >= 0 · total > 0        [000:981-984]
--   seller_fee >= 0                                 [000:983 / re-added 022:42-44]
--   status in ('pending','processing','succeeded','failed','refunded') [000:991-992]
--   mode in (...)                                   [000:995, widened in §1]
-- Every one of those keys a DIFFERENT column. This constraint keys listing_id,
-- seller_id and mode, and it only ever RESTRICTS combinations that were
-- previously unreachable anyway. It cannot conflict with the money CHECKs and
-- it cannot conflict with the widened mode CHECK, of which it is a refinement.
--
-- NO `NOT VALID` — H §5.3, explicitly rejected. `add constraint` validates
-- immediately against all 56 rows (microseconds), so the constraint is in
-- force for existing rows and new rows from the instant the transaction
-- commits. §0 has already proved the validation will pass.
-- ============================================================================
do $$ begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.payments'::regclass
       and conname  = 'payments_rail_pairing_ck'
  ) then
    alter table public.payments
      add constraint payments_rail_pairing_ck
      check (
        (
          mode in ('buy_now', 'auction')
          and listing_id is not null
          and seller_id  is not null
        )
        or
        (
          mode = 'native_primary'
          and listing_id is null
          and seller_id  is null
        )
      );
  end if;
end $$;


-- ============================================================================
-- 4. THE SELLER-SIDE DISPOSITION — **NO POLICY DDL**, ASSERTED INSTEAD
-- ----------------------------------------------------------------------------
-- ADVERSARIAL_REVIEW J-2 is CORRECT that a null seller_id makes a direct row
-- invisible through `"payments: seller select" USING (seller_id = auth.uid())`
-- (000:1027-1029) — `NULL = auth.uid()` is NULL, which is not TRUE, so the row
-- never matches. It is WRONG that this needs a replacement policy. Three
-- reasons, all ratified (E §6.3, ratification §E "No organization policy is
-- added ... The existing seller policy is not destabilized"):
--
--   (a) THE INVISIBILITY IS THE CORRECT BEHAVIOUR. A venue-direct order has no
--       seller. `buyer_id` stays NOT NULL, so `"payments: buyer select"`
--       (000:1021-1023) still shows the buyer their own order payment — the
--       only client-side read that should exist on this table.
--   (b) NOTHING LOSES ACCESS IT HAS. There are zero direct client reads of
--       public.payments in /app, /src, /components, /hooks, /packages, and no
--       venue read in src/lib/venue/. Every org money read goes through
--       venue.settlement_line, kernel.payout and scoped DEFINER RPCs.
--   (c) AN ORG-SCOPED POLICY IS NOT IMPLEMENTABLE AND WOULD BREAK CI. The org
--       linkage lives in kernel.payment_native → venue."order".org_id, and
--       085:69 revokes all on kernel.payment_native from anon/authenticated, so
--       a policy could only reach it through a NEW security-definer helper.
--       And supabase/tests/010_rls_smoke.sql:42 PINS the policy count at
--       exactly 2 — a third policy fails the suite. 093's own manifest says
--       "0 new policies".
--
-- So this part ships no `create policy`, no `drop policy`, no `alter policy`.
-- What it ships instead is the ASSERTION that the invisibility holds and that
-- the frozen visibility model is intact — the guarantee made executable at
-- migration time rather than asserted only in a test file. Broadening
-- visibility is not merely avoided here; it is proved not to have happened.
--
-- NOTE — this is the one place where the drafting brief and the 093 scope memo
-- (093_FINAL_PROPOSED_SCOPE.md:58-59, "ship the seller-side policy replacement
-- in the same migration") read as asking for policy DDL, while the OWNER
-- RATIFICATION and E §6.3 forbid it. The ratification controls, and a
-- null-guard added to the existing predicate would in any case be a provable
-- no-op: `seller_id is not null and seller_id = auth.uid()` selects exactly the
-- rows `seller_id = auth.uid()` already selects, at the cost of a gratuitous
-- drop/create of a policy on a live table.
-- ============================================================================
do $$
declare
  v_policies int;
  v_nonselect int;
  v_seller_qual text;
begin
  -- 4a. the frozen count is unchanged — mirrors 010_rls_smoke.sql:42 in-migration
  select count(*) into v_policies
    from pg_policies where schemaname = 'public' and tablename = 'payments';
  if v_policies <> 2 then
    raise exception
      'PFA-PT-3: public.payments carries % RLS policies, expected exactly 2 (000 buyer+seller select) — visibility model altered', v_policies;
  end if;

  -- 4b. still SELECT-only — mirrors 010_rls_smoke.sql:48-50
  select count(*) into v_nonselect
    from pg_policies
   where schemaname = 'public' and tablename = 'payments' and cmd <> 'SELECT';
  if v_nonselect <> 0 then
    raise exception
      'PFA-PT-3: public.payments carries % non-SELECT RLS policies — client writes must remain impossible', v_nonselect;
  end if;

  -- 4c. the seller policy is byte-intact: a bare equality on seller_id, with no
  --     null-guard bolted on and no org linkage smuggled in. This is the
  --     regression guard — if a later change rewrites the predicate, 093's
  --     assertion is where it surfaces.
  select pg_get_expr(p.polqual, p.polrelid) into v_seller_qual
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'payments'
     and p.polname = 'payments: seller select';

  if v_seller_qual is null then
    raise exception 'PFA-PT-3: policy "payments: seller select" is missing from public.payments';
  end if;
  if v_seller_qual !~ 'seller_id' or v_seller_qual !~ 'auth\.uid\(\)' then
    raise exception 'PFA-PT-3: "payments: seller select" no longer reads (seller_id = auth.uid()): %', v_seller_qual;
  end if;
  if v_seller_qual ~* 'org|payment_native|is not null|is null' then
    raise exception 'PFA-PT-3: "payments: seller select" has been widened or null-guarded — forbidden by ruling E §6.3: %', v_seller_qual;
  end if;

  -- 4d. ASSERT THE INVISIBILITY ITSELF. Under SQL three-valued logic the
  --     policy predicate on a direct row is `NULL = <uuid>` → NULL, and RLS
  --     admits a row only when the qual is TRUE. A direct-rail payment is
  --     therefore invisible to every seller, by construction, with no policy
  --     change required. Executed, not merely claimed.
  if ((null::uuid = gen_random_uuid()) is true) then
    raise exception 'PFA-PT-3: NULL seller_id compares TRUE — the direct-rail invisibility guarantee does not hold';
  end if;
end $$;


-- ============================================================================
-- 5. idx_payments_one_success_per_listing — VERIFIED, NEEDS NO RESCOPING
-- ----------------------------------------------------------------------------
-- The gap matrix reported this partial unique index as a fourth blocker
-- requiring a rescope. **That report is FALSE**, and this section records the
-- verification rather than the assumption.
--
-- Read at 003_payment_integrity.sql:52-54, in full:
--
--     create unique index if not exists idx_payments_one_success_per_listing
--       on public.payments (listing_id)
--       where status = 'succeeded';
--
-- There is NO `nulls not distinct` clause. Under the default (NULLS DISTINCT)
-- a unique index treats every NULL as distinct from every other NULL, so an
-- unlimited number of succeeded rows with `listing_id IS NULL` coexist without
-- collision: the index becomes an AUTOMATIC NO-OP for direct sales, and is
-- preserved byte-for-byte for resale rows, where listing_id is still forced
-- NOT NULL by §3. Its absence here is meaningful rather than accidental — this
-- codebase uses `nulls not distinct` deliberately where it wants it (078:269,
-- 083:309), so the plain form at 003:52 is a choice.
--
-- Consequences, both correct:
--   · supabase/tests/060_payments_money.sql:38-41 ("second succeeded payment
--     for the same listing rejected, 23505") keeps passing unchanged — its
--     fixture rows are 'buy_now' rows with a real listing.
--   · Two succeeded 'native_primary' rows coexist, as they must: two different
--     direct orders are two different charges.
--
-- Therefore this part issues NO DDL against that index — dropping and
-- recreating it would take a second ACCESS EXCLUSIVE lock on the live table
-- for a change with no effect.
--
-- THE ONE NAMED RESIDUAL (E §6.4): with listing_id NULL, the equivalent
-- direct-rail invariant — one succeeded charge per ORDER — is not carried by
-- this index. It is partially covered already: payment_native_payment_uq
-- (085:56) stops one payment linking twice, and finalize_primary_order's
-- order.status='paid' short-circuit (085:1971-1980) stops a double mint. NOT
-- covered: two DISTINCT succeeded PaymentIntents for the same order, where the
-- second finalize returns idempotency_replay and leaves a stranded succeeded
-- charge with no payment_native row. Primary mitigation is the frozen
-- deterministic PI idempotency key `pi_native_${order_id}_${total}_c${customerId}`
-- (EDGE_FUNCTION_SPEC:379-381), which prevents it at the edge. The database
-- backstop E §6.4 suggests — a partial unique index on
-- kernel.payment_native (order_id) where order_id is not null — is
-- **deliberately OUT of this part and out of 093**: the 093 manifest commits to
-- "0 DDL on any money-ledger table" and kernel.payment_native is one. It is
-- carried forward as a named residual, not silently dropped.
-- ============================================================================


-- ============================================================================
-- 6. CATALOGUE COMMENTS — the amendment, recorded where the reader will be
-- ============================================================================
comment on column public.payments.listing_id is
  'Resale listing this charge is against. NULL ONLY on the venue-direct rail '
  '(mode = ''native_primary''), where the sale has no resale listing and the '
  'counterparty is an organization — the order is linked via '
  'kernel.payment_native.order_id (085:43), never by a column on this table. '
  'The NOT NULL from 000:973 is re-imposed conditionally by '
  'payments_rail_pairing_ck. POST-FREEZE AMENDMENT PFA-PT-3 (ruling E).';

comment on column public.payments.seller_id is
  'Individual seller of a resale listing. NULL ONLY on the venue-direct rail '
  '(mode = ''native_primary''): a direct order has no individual seller. NULL '
  'says that truthfully; the 019 anonymization sentinel would say it falsely '
  'and make deleted-user rows indistinguishable from venue-direct rows. A NULL '
  'here is deliberately invisible to "payments: seller select" (000:1027-1029) '
  '— see ruling E §6.3; no replacement policy exists or is wanted. The NOT NULL '
  'from 000:975 is re-imposed conditionally by payments_rail_pairing_ck. '
  'POST-FREEZE AMENDMENT PFA-PT-3 (ruling E).';

comment on column public.payments.mode is
  'Rail label. ''buy_now''/''auction'' = resale rail (000:995). '
  '''native_primary'' = venue-direct rail, matching the frozen PaymentIntent '
  'metadata vocabulary (EDGE_FUNCTION_SPEC:373, metadata.rail). This column has '
  'ZERO SQL consumers — dispatch is a closed selection on Stripe metadata in '
  'TypeScript (074:172-177), not on this column. Paired to listing_id/seller_id '
  'by payments_rail_pairing_ck. POST-FREEZE AMENDMENT PFA-PT-3 (ruling E).';

comment on constraint payments_rail_pairing_ck on public.payments is
  'PFA-PT-3 (ruling E, ratified 2026-09-02). The load-bearing half of the '
  'constrained relaxation: it re-imposes, conditionally, the two NOT NULLs that '
  '000:973/975 imposed unconditionally. Resale rail (mode in buy_now/auction) '
  'MUST carry both listing_id and seller_id; direct rail (mode = native_primary) '
  'MUST carry neither. No row can be half-way between the rails. Net loosening '
  'of the resale rail: ZERO — a resale row carrying a NULL remains unstorable, '
  'failing 23514 where it used to fail 23502. Do not drop this without also '
  'restoring the two NOT NULLs in the same transaction.';

comment on constraint payments_mode_check on public.payments is
  'PFA-PT-3: widened from 000:995''s (buy_now, auction) to admit '
  'native_primary. Purely additive — all pre-amendment rows satisfy it '
  'unchanged. Kept as a separate constraint from payments_rail_pairing_ck so '
  'the rail vocabulary and the rail pairing can be reasoned about separately.';

-- ============================================================================
-- END 093 · PART 20 — PFA-PT-3
-- Follow-ups this part creates, none of which are a runtime break and none of
-- which belong in the migration (E §6.2, §8 "Accompanying, not in the migration"):
--   · scripts/release/phase2_preflight.sql:92-94 — the M3 orphan assertion
--     ("every payment's listing exists") must be rail-scoped to
--     mode in ('buy_now','auction') or every direct row reports as an orphan.
--   · src/types/index.ts:190-213 and packages/types/src/index.ts:179-202 —
--     listing_id/seller_id become nullable, PaymentMode gains native_primary.
--     No generated database.types.ts exists in the repo, so nothing breaks at
--     compile time; the declarations are simply now incorrect.
--   · New pgTAP in a 093_* file (existing suites untouched): a native_primary
--     row with both columns NULL inserts; a buy_now row with either column NULL
--     is rejected 23514; a native_primary row carrying a listing_id or a
--     seller_id is rejected 23514; two succeeded native_primary rows coexist;
--     two succeeded buy_now rows for one listing still collide 23505; a
--     native_primary row is visible to its buyer and to NO other authenticated
--     user.
--   · Rollback (supabase/rollbacks/093_*): drop payments_rail_pairing_ck,
--     restore both NOT NULLs, restore the narrow mode CHECK — VALID ONLY WHILE
--     ZERO native_primary ROWS EXIST, with a fail-loud guard. Once real money
--     lands on the direct rail the posture is FORWARD-FIX ONLY, matching 085.
--   · Errata for the amendment record: 019_anonymized_sentinel_user.sql:6's
--     rationale ("preserves NOT NULL constraints on payments") is no longer
--     strictly true for seller_id; and the E §6.4 one-charge-per-order residual
--     above, with its edge-side mitigation.
--   · Edge-side, already scoped separately as gap-matrix F5: stripe-webhook must
--     branch on metadata.rail BEFORE :267, because its downstream reads
--     metadata.listing_id (:327/:333/:379/:385), which a direct PI does not
--     carry. This part neither creates nor mitigates that; it is required by
--     the frozen spec regardless.
-- ============================================================================


-- ###########################################################################
-- ## SLICE: 30_connect_org.sql
-- ###########################################################################

-- ============================================================================
-- 093 PART 30 — STRIPE CONNECT / ORGANIZATION slice.
--
-- FRAGMENT, not a migration. No `begin;`/`commit;` here — the assembled 093
-- owns the transaction. 076-092 are IMMUTABLE: this part only ADDs columns and
-- CREATE-OR-REPLACEs function bodies. No new table, no new enum member, no
-- policy, no grant change to an existing verb (create-or-replace preserves the
-- ACL — the two replaced verbs keep their frozen `authenticated` grants, which
-- is precisely why every control below has to live in SQL).
--
-- OWNER RULINGS IMPLEMENTED (PRIMARY_TICKETING_OWNER_RATIFICATION.md):
--   §1  two mirror columns on kernel.organization ......... A6  (scope item 5)
--   §2  kernel.sync_org_connect_state, service_role only .. A6  (scope item 6)
--   §2b kernel.stage_org_connect_ref, service_role only ... A7/A9 (RT-A-3)
--   §3  checkout readiness gates, UNCONDITIONAL ........... A8  (scope item 7)
--         G2a organization status — is this org allowed to trade at all?
--         G2  connect readiness — can the VENUE be paid?
--         G2b signing-key readiness — can the BUYER be delivered to?
--       + the buyer-side service fee, fail-closed ......... A5  (part 40's
--         `fee.buyer_service_bps`, whose only possible reader this is)
--   §4  kernel.set_org_connect_ref — hardened ............. A7/A9 (item 8)
--   §5  kernel.set_org_payout_destination — hardened ...... A7/A9 (item 9)
--   §6  kernel.get_org_connect_state — read, HUMANS ........ A7  (F §3.5 G5)
--   §7  kernel.get_org_connect_ref — read, MACHINES ........ A7  (F §3.4)
--   §8  kernel.issue_ticket_atoms — resolve, not accept .... T1  (binds G2b)
--   §10 kernel.guard_connect_id_not_org_bound + 2 triggers  A7/G-1/G-12
--         (H6/F-4: the cross-plane refusal was ONE-WAY. An org-bound acct_
--          could be written onto public.profiles, mis-routing seller payouts
--          AND bricking that org's re-point forever. Now bidirectional.)
--   §9  kernel.authorize_org_payout_dashboard ............. A7/A9 extension
--         (H6/F-3: the acct_ was provenance-locked; the BANK ACCOUNT INSIDE IT
--          was not. The Express Dashboard login link the onboarding edge issues
--          reached org_finance with no aal2, no audit row and no notification.)
--
-- §6, §7 and §9 are the three objects here that are NOT in the 093 scope list.
-- §9's justification is in its own header; §6/§7's follows. Both §6 and §7
-- were added because the onboarding edge cannot function without them: the
-- column they read is unreachable by BOTH candidate roles (`authenticated` is
-- revoked at 077:133-138; service_role holds kernel USAGE only, 085:2092-2095).
-- They are a DELIBERATE PAIR SPLIT ON THE TRUST BOUNDARY — §6 is granted to
-- `authenticated` and returns last4; §7 is granted to service_role and returns
-- the full identifier. Rulings F §3.5 (G5) and F §3.4 prescribe both; neither
-- was ever authored. DO NOT MERGE THEM.
--
-- Supporting rulings: docs/phase2/_rulings/F_org_onboarding.md §3.3/§3.5/§3.6
-- (what may be mirrored, and where the gates go) and
-- docs/phase2/_rulings/G_onboarding_security.md §2 (threats G-1/G-2/G-4/G-6),
-- §5.1 (attach vs replace) and §6.1/§6.2 (audit + notification wiring).
--
-- ORDERING: §1, §2 and §3 are ONE UNIT. §3 reads a column created by §1 and
-- written only by §2. Applied apart, the buyer-facing checkout raises an
-- undefined-column error instead of cleanly refusing the sale.
-- ============================================================================


-- ============================================================================
-- §1 — kernel.organization: the Connect state mirror. EXACTLY TWO COLUMNS.
--   Ruling A6 · F §3.3 · 093 scope item 5.
--
-- OWNER CONSTRAINT, VERBATIM: "Do NOT copy Stripe's entire account object into
-- Postgres." Stripe stays authoritative for verification state. Postgres holds
-- only what a SQL gate must evaluate with no network call — which is one
-- boolean — plus the freshness stamp that says whether that boolean can still
-- be believed.
--
-- WHY ONLY TWO. Four further candidates were CUT because no reader exists in
-- the ruled design, and a column with no reader sits at its default forever:
--   · payouts_enabled          — F §3.5 rules it explicitly NOT a sale gate
--                                (transfers active + payouts disabled still
--                                sells and still receives transfers), so no
--                                SQL predicate reads it. Dashboard-only.
--   · requirements.disabled_reason  — support triage copy. No predicate.
--   · requirements.current_deadline — warning copy. No predicate.
--   · requirements-due flag         — banner copy. No predicate; F §3.6(2)
--                                     rules that requirements due must warn
--                                     and gate NOTHING.
-- Two of them would also duplicate columns already carried on the individual
-- plane (public.profiles.stripe_payouts_enabled / stripe_connect_status).
-- They become justified when an operator console exists to render them; until
-- then they are exactly the `stripe_charges_enabled` failure — a column
-- written by nothing, read by nothing, believed by everyone.
--
-- CLIENT VISIBILITY: kernel.organization carries a COLUMN-SCOPED grant
-- (077:120-123 — authenticated may SELECT only org_id/display_name/status).
-- A column added to a table with column-level grants inherits NO grant, so
-- both columns below are unreadable by `authenticated` by construction. That
-- is intended: the gate reads them inside SECURITY DEFINER functions, and the
-- dashboard reads them through a scoped RPC, never through PostgREST.
-- ============================================================================

-- The product gate operand. `capabilities.transfers = 'active'` is the ONLY
-- readiness predicate this money model needs, and the shipped payout probe
-- already uses exactly it (supabase/functions/_shared/payouts.ts:96-98) — this
-- mirrors that predicate rather than inventing a second one.
--
-- NON-MONOTONIC, DELIBERATELY — DO NOT "FIX" THIS INTO A RATCHET.
-- public.profiles.stripe_onboarding_complete is monotonic on purpose
-- (supabase/functions/create-connect-account/index.ts:281 only ever sets it
-- true), because flipping an individual seller's flag false on one transient
-- read would bar an onboarded seller from listing. The organization flag is
-- the OPPOSITE by requirement: when Stripe disables an account, `transfers`
-- leaves 'active' and the organization MUST stop selling. A monotonic mirror
-- here means an account Stripe has disabled stays sellable forever, with the
-- platform as merchant of record and no destination to settle to. §2 is the
-- only writer and it writes both directions.
alter table kernel.organization
  add column if not exists connect_transfers_active boolean not null default false;

-- Freshness, not truth. A row whose stamp is old renders "checking…" and
-- triggers a re-read rather than asserting a stale green. It is also the
-- out-of-order guard in §2: a webhook redelivery carrying an OLDER observation
-- cannot overwrite a newer one.
alter table kernel.organization
  add column if not exists connect_state_synced_at timestamptz;

-- THE THIRD COLUMN — added under protest against the two-column target, and
-- the reason is worth stating plainly because it overrides §1's own rule.
--
-- RT-A-3: the red team bound `acct_ORPHANATTACKER` as `authenticated`, on both
-- the first bind AND a re-point of a LIVE destination. It is present in neither
-- public.profiles.stripe_connect_id nor public.stripe_connect_archive, so the
-- cross-plane refusal below never fired. That refusal is a BLOCKLIST of known
-- individual-plane accounts, and a blocklist cannot satisfy ruling A7's
-- absolute form: "A caller must never be permitted to supply or bind an
-- arbitrary acct_ identifier." An attacker's own freshly created Stripe
-- account is in no list anyone can enumerate.
--
-- The "server mints, caller never names" property was real but ADVISORY: it
-- lived in the onboarding edge, and both binders are granted to `authenticated`
-- and reachable through PostgREST in one call. An attacker simply does not use
-- the edge.
--
-- This column converts that property from advisory to STRUCTURAL. It is the
-- platform's own record of the account IT minted for THIS organization, written
-- only by kernel.stage_org_connect_ref (§2b, service_role only). §4 and §5 then
-- require the caller-supplied identifier to EQUAL it. The caller still passes a
-- value — CREATE OR REPLACE cannot drop a parameter — but can no longer pass a
-- value the platform did not mint for that org. Provenance, not enumeration.
--
-- It is deliberately NOT part of the §1 Stripe mirror: it mirrors nothing from
-- Stripe. It is a Snatch It fact, like payout_destination_set_by. It carries no
-- client grant (a column added to a table with column-scoped grants inherits
-- none), and no read verb in this slice returns it.
alter table kernel.organization
  add column if not exists connect_pending_ref text;


-- ============================================================================
-- §2 — kernel.sync_org_connect_state: the service_role-only sync writer.
--   Ruling A6 · F §3.3 ("Writer") · 093 scope item 6.
--
-- WHY IT EXISTS AT ALL: service_role holds USAGE ONLY on the kernel schema
-- (085:2092-2095, PFA-21) — no table DML grant — so the account.updated
-- webhook physically CANNOT `update kernel.organization`. A definer function
-- is the only door, and this is it.
--
-- WHY NOT set_org_connect_ref: that verb RAISES when auth.uid() is NULL
-- (077:962-966, T-RPC-CONNECT-04) because it must stamp the SoD-1 operand with
-- a real human. A webhook has no human. The two are different acts.
--
-- SHAPE: modelled on kernel.mark_payout_transfer_state (085:1668) — DEF,
-- service_role EXEC only, NO HUMAN PATH AND NONE MAY EVER BE ADDED. Same
-- five-argument shape: subject, the fact(s), and the command/idempotency key.
--
-- SIGNATURE, derived from how the webhook actually calls it (F §3.6(1)): the
-- handler matches kernel.organization.stripe_connect_account_ref = account.id
-- and FALLS BACK to metadata.org_id, so both selectors are accepted and at
-- least one is required. The ref wins when both are supplied.
-- ============================================================================
create or replace function kernel.sync_org_connect_state(
  p_org_id uuid, p_connect_account_ref text, p_transfers_active boolean,
  p_observed_at timestamptz, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org      kernel.organization%rowtype;
  v_observed timestamptz;
begin
  if p_transfers_active is null then
    raise exception 'invalid_input: transfers_active is the fact being synced and may not be null';
  end if;
  -- RT-A-5: A NULL REF IS NOT A WILDCARD. The first draft made the cross-org
  -- guard below conditional on `p_connect_account_ref is not null`, so a caller
  -- holding only service_role could omit the ref entirely and write capability
  -- state onto ANY organization by id — the red team set
  -- connect_transfers_active = true on an unbound org that way. That widened a
  -- leaked-key blast radius onto the org plane, which ruling G (threat G-12)
  -- asserts is closed precisely because no kernel table DML grant exists. The
  -- ref is now MANDATORY and is always compared.
  if p_connect_account_ref is null then
    raise exception 'invalid_input: connect_account_ref is required — a null ref must never be read as "match any organization" (RT-A-5)';
  end if;
  if p_connect_account_ref !~ '^acct_[A-Za-z0-9]+$' then
    raise exception 'precondition_failed: malformed_account_ref';
  end if;
  -- The observation instant is the webhook's RETRIEVE time, not now(): Stripe
  -- redelivers, and a redelivery must not be able to present itself as fresher
  -- than a later observation already recorded. A caller that has no instant
  -- passes null and gets now().
  v_observed := coalesce(p_observed_at, now());

  -- Resolve by the bound ref first (the webhook's primary join), then by the
  -- metadata org id (its documented fallback). The fallback survives only to
  -- produce the precise refusal below instead of a bare not_found.
  select * into v_org from kernel.organization o
    where o.stripe_connect_account_ref = p_connect_account_ref for update;
  if v_org.org_id is null and p_org_id is not null then
    select * into v_org from kernel.organization o
      where o.org_id = p_org_id for update;
  end if;
  if v_org.org_id is null then
    raise exception 'not_found: organization for %', coalesce(p_connect_account_ref, p_org_id::text)
      using errcode = 'P0002';
  end if;

  -- RT-A-5: AN UNBOUND ORGANIZATION MAY NOT RECEIVE CAPABILITY STATE AT ALL.
  -- Until §4 binds a destination the org is not the payee of anything, so a
  -- `transfers active` fact about it has nowhere legitimate to live — and
  -- writing one would arm the §3 checkout gate for an organization with no
  -- destination to settle to. An account.updated that arrives for a minted-but-
  -- never-bound account is refused here and lands again after the bind.
  if v_org.stripe_connect_account_ref is null then
    raise exception 'precondition_failed: org_not_bound — capability state may not be written for an organization with no bound payout destination';
  end if;

  -- G-4 / A9 (stale onboarding callback binding): an account.updated for an
  -- account that is NOT this organization's currently bound destination must
  -- never write its state. A rebind that raced the event, or an event for a
  -- superseded account, is refused — never silently applied to the live row.
  -- UNCONDITIONAL NOW: see the RT-A-5 note on the mandatory ref above.
  if v_org.stripe_connect_account_ref is distinct from p_connect_account_ref then
    raise exception 'conflict_locked: % is not the bound destination of org %',
      p_connect_account_ref, v_org.org_id;
  end if;

  -- Out-of-order redelivery: an observation no newer than the one already
  -- recorded changes nothing. Never a raise — a raising webhook is retried
  -- forever (the 082 cancel_pending_order lesson).
  if v_org.connect_state_synced_at is not null
     and v_observed <= v_org.connect_state_synced_at then
    return jsonb_build_object('status','noop_replay','org_id', v_org.org_id,
                              'connect_transfers_active', v_org.connect_transfers_active,
                              'connect_state_synced_at', v_org.connect_state_synced_at);
  end if;

  -- HEARTBEAT vs TRANSITION. Both writes stamp freshness; only a transition is
  -- an auditable fact. F §3.3's refresh discipline gives this verb two callers
  -- — the webhook AND every dashboard status read — so auditing an unchanged
  -- poll would bury the capability losses that matter under heartbeat noise.
  if v_org.connect_transfers_active = p_transfers_active then
    update kernel.organization
       set connect_state_synced_at = v_observed
     where org_id = v_org.org_id;
    return jsonb_build_object('status','noop_replay','org_id', v_org.org_id,
                              'connect_transfers_active', p_transfers_active,
                              'connect_state_synced_at', v_observed);
  end if;

  update kernel.organization
     set connect_transfers_active = p_transfers_active,
         connect_state_synced_at  = v_observed
   where org_id = v_org.org_id;

  -- G §6.1: `org.connect_ref.capability_lost` is the named audit action for the
  -- org account.updated branch; its twin records the recovery. Actor is the
  -- SN-SYSTEM sentinel (078 §1.16, uuid ...f1) — the same coalesce idiom
  -- mark_payout_transfer_state uses (085:1724) — because a webhook has no human
  -- and admin_audit.actor_identity is NOT NULL.
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'),
          case when p_transfers_active then 'org.connect_ref.capability_gained'
                                       else 'org.connect_ref.capability_lost' end,
          'organization', v_org.org_id,
          case when p_transfers_active then 'transfers_active' else 'transfers_inactive' end,
          jsonb_build_object('connect_transfers_active', v_org.connect_transfers_active,
                             'connect_state_synced_at', v_org.connect_state_synced_at),
          jsonb_build_object('connect_transfers_active', p_transfers_active,
                             'connect_state_synced_at', v_observed));

  return jsonb_build_object('status','ok','org_id', v_org.org_id,
                            'connect_transfers_active', p_transfers_active,
                            'connect_state_synced_at', v_observed);
end;
$$;

-- 076 grant discipline: the default PUBLIC EXECUTE is revoked explicitly, then
-- ONE targeted grant. service_role ONLY — never `authenticated`, never anon.
-- This verb asserts Stripe's own state; a human principal that could call it
-- could declare itself ready to sell and walk straight through §3. There is no
-- human path here and none may ever be added (R-31, the mark_* pair's rule).
revoke all on function kernel.sync_org_connect_state(uuid, text, boolean, timestamptz, text)
  from public, anon, authenticated;
grant execute on function kernel.sync_org_connect_state(uuid, text, boolean, timestamptz, text)
  to service_role;


-- ============================================================================
-- §2b — kernel.stage_org_connect_ref: the PROVENANCE WRITER.
--   Ruling A7 ("The server creates/resolves the connected account. A caller
--   must never be permitted to supply or bind an arbitrary acct_ identifier")
--   and A9 (personal-account injection; caller-supplied acct_ replacement).
--   Closes RT-A-3.
--
-- WHAT IT IS: the platform's record that IT minted this account for THIS
-- organization. The onboarding edge calls it immediately after Stripe returns
-- the account, BEFORE sending the human to §4. §4 and §5 then refuse any
-- identifier that does not equal what is staged here.
--
-- WHY A VERB AND NOT A DIRECT WRITE: service_role holds USAGE ONLY on the
-- kernel schema (085:2092-2095, PFA-21), so the edge cannot UPDATE
-- kernel.organization. Same reason §2 exists, same treatment.
--
-- WHY `authenticated` CAN NEVER REACH IT: if a browser session could stage a
-- ref, it could stage its own account and then bind it, and the provenance
-- requirement would be theatre — the attacker would simply write the answer
-- before taking the test. THE ENTIRE VALUE OF RT-A-3's FIX IS THIS GRANT.
--
-- THE TWO-KEY PROPERTY THIS CREATES, stated so it is not weakened by accident:
-- staging needs service_role (a machine credential); binding needs a human
-- org_owner with an aal2 session and REFUSES a service_role connection
-- outright (077:962-966). Neither credential alone can bind an account. A
-- leaked service_role key can stage a ref it likes and get no further; a
-- compromised org_owner can bind only what the platform already minted for
-- that org. That separation is the control — do not merge these two verbs, and
-- do not add a human path here.
--
-- NO ORG-STATUS GATE, DELIBERATELY. §4 already refuses to bind for an org that
-- is not approved/active, so a status gate here would add nothing except a way
-- to strand a freshly minted live Stripe account: the edge would have already
-- created it at Stripe and would then be unable to record it. The edge reads
-- org_status from §6 and refuses BEFORE minting; this verb is downstream of
-- that decision, and the authoritative refusal stays at the bind.
--
-- Staging is idempotent and overwrite-safe: re-staging the same ref is a
-- noop_replay, and staging a different one replaces the pending value. It
-- never touches stripe_connect_account_ref — only §4 and §5 write that.
-- ============================================================================
create or replace function kernel.stage_org_connect_ref(
  p_org_id uuid, p_connect_account_ref text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org kernel.organization%rowtype;
begin
  if p_org_id is null then
    raise exception 'invalid_input: org_id is required';
  end if;
  if p_connect_account_ref is null or p_connect_account_ref !~ '^acct_[A-Za-z0-9]+$' then
    raise exception 'precondition_failed: malformed_account_ref';
  end if;

  -- Cross-plane refusal applies HERE TOO, and earliest of all: an individual
  -- seller's account must never even become stageable, so the refusal lands
  -- before a human is sent to Stripe rather than after (G-1).
  if exists (select 1 from public.profiles pf
              where pf.stripe_connect_id = p_connect_account_ref)
     or exists (select 1 from public.stripe_connect_archive ar
                 where ar.stripe_connect_id = p_connect_account_ref) then
    raise exception 'precondition_failed: account_not_platform_minted_for_org — this account belongs to the individual seller plane';
  end if;

  select * into v_org from kernel.organization where org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: organization %', p_org_id using errcode = 'P0002';
  end if;

  -- One account per org across the whole platform (077:124-126 says so for the
  -- bound column; this says it for the pending one, so the collision surfaces
  -- at staging rather than as a unique_violation after Stripe has minted).
  if exists (select 1 from kernel.organization o
              where o.stripe_connect_account_ref = p_connect_account_ref
                and o.org_id <> p_org_id) then
    raise exception 'conflict_locked: connect account already bound to another org';
  end if;

  -- Already the org's LIVE destination: nothing to stage, and staging it would
  -- arm a pointless re-point. The §4 replay path already handles this caller.
  if v_org.stripe_connect_account_ref = p_connect_account_ref then
    return jsonb_build_object('status','noop_replay','org_id', p_org_id,
                              'already_bound', true);
  end if;
  if v_org.connect_pending_ref = p_connect_account_ref then
    return jsonb_build_object('status','noop_replay','org_id', p_org_id,
                              'already_bound', false);
  end if;

  update kernel.organization
     set connect_pending_ref = p_connect_account_ref
   where org_id = p_org_id;

  -- Auditable per A7 ("Initial onboarding and account replacement must be
  -- auditable") — and this is the row that proves WHEN the platform minted the
  -- account, which is the fact the bind's provenance check rests on. Actor is
  -- the SN-SYSTEM sentinel (078 §1.16): the mint has no human principal, and
  -- the human is recorded separately by §4/§5's own audit row.
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'),
          'org.connect_ref.stage', 'organization', p_org_id, 'onboarding_mint',
          jsonb_build_object('pending_ref_last4',
                             case when v_org.connect_pending_ref is null then null
                                  else right(v_org.connect_pending_ref, 4) end),
          jsonb_build_object('pending_ref_last4', right(p_connect_account_ref, 4)));

  return jsonb_build_object('status','ok','org_id', p_org_id, 'staged', true);
end;
$$;

-- service_role ONLY, and this grant IS the control (see the header). The
-- `revoke ... from public` is load-bearing: CREATE FUNCTION grants EXECUTE to
-- PUBLIC by default and `authenticated` inherits PUBLIC, which would hand a
-- browser session the ability to stage its own account and defeat RT-A-3's fix
-- entirely.
revoke all on function kernel.stage_org_connect_ref(uuid, text, text)
  from public, anon, authenticated;
grant execute on function kernel.stage_org_connect_ref(uuid, text, text) to service_role;


-- ============================================================================
-- §3 — venue.create_primary_checkout: the checkout readiness gate.
--   Ruling A8 ("Checkout must fail closed if the venue organization is not
--   eligible for primary-sale collection") · F §3.5 gate G2 · scope item 7.
--
-- REPLACEMENT SCOPE: the ONLY change to this body is the payout-readiness
-- precondition marked A8/G2 below, placed beside the existing `not_on_sale`
-- check where v_org_id is already server-derived from the session's event.
-- Every other check, the hold/inventory coverage logic, the C16 idempotency
-- short-circuit and race handler, the single-price-snapshot rule, the insert
-- pair and the return shape are reproduced unchanged.
--
-- UNCONDITIONAL — THERE IS NO CONFIGURATION KEY FOR THIS GATE, DELIBERATELY.
-- F §3.5 proposed `venue.require_connect_for_on_sale`; the owner declined it
-- outright (093 scope, OUT). A configuration key whose only function is
-- switching off the gate that protects money is not minimality, it is a second
-- way to be wrong: a fail-open flip with no migration, no review and no audit
-- row. If this gate is ever wrong, the fix is code.
--
-- THERE IS NO EDGE-SIDE RE-CHECK, AND ONE MUST NOT BE RESTORED. F §3.5 gate G3
-- specified the primary-checkout edge re-asserting this predicate before
-- minting the PaymentIntent. THAT RE-CHECK HAS BEEN REMOVED, NOT RELOCATED,
-- and its removal is correct on two independent grounds:
--
--   1. IT WAS STRICTLY WEAKER THAN THIS ONE. The read below happens in the SAME
--      TRANSACTION as the price snapshot and the hold-coverage proof, under the
--      same row-visibility, so the readiness fact and the price the buyer is
--      quoted are decided against one consistent state. An edge re-read happens
--      moments later against a state that may have moved — it can only ever
--      disagree with a decision already taken, never improve on it. The
--      IN-TRANSACTION READ IS THE CONTROL.
--   2. IT WAS UNREACHABLE IN BOTH DIRECTIONS ANYWAY. kernel.get_org_connect_state
--      (§6) is granted to `authenticated` and deliberately never to
--      service_role, and its body demands org_owner/org_finance — which a BUYER
--      is not. There is no credential the checkout edge could present that
--      would let it ask, and the direct table reads it was attempting were
--      illegal for the same reason (076:76 grants `catalog` USAGE to anon and
--      authenticated only; 085:2088 gives service_role `venue` USAGE ONLY and
--      085:2092 gives it `kernel` USAGE ONLY, both saying so verbatim; no
--      migration grants service_role any table privilege in
--      venue/kernel/catalog/market).
--
-- SO DO NOT "FIX" A MISSING EDGE CHECK BY WIDENING A GRANT. Widening §6 to
-- service_role, or granting the edge SELECT on kernel.organization, buys a
-- strictly worse duplicate of the check below and hands the machine plane the
-- payout state of every organization. This function is granted to
-- `authenticated` and reachable through PostgREST in one call, so an edge-side
-- check would be bypassed by not using the edge in any case. The authoritative
-- gate is here and only here.
--
-- SELF-HEALING BY CONSTRUCTION: no sweep, no scheduled job, no backward event
-- transition. The moment Stripe disables the account, §2 writes false and the
-- next checkout attempt refuses; the moment it recovers, sales resume with no
-- operator action. F §3.6(4) forbids consuming the operator's forward-only
-- publish state machine on a transient Stripe state, and this gate is correct
-- precisely because it is reversible for free.
--
-- ---------------------------------------------------------------------------
-- SECOND CHANGE IN THIS BODY — THE BUYER-SIDE SERVICE FEE (ruling A5).
--
-- Part 40 of this migration mints `fee.buyer_service_bps` (restricted, seeded
-- null) and names its reader in advance: "The real reader is the buyer-side
-- pricing path — venue.create_primary_checkout and the primary-checkout edge",
-- which "must fail closed (refuse to price) rather than default to zero while
-- the value is null." THIS BODY IS THAT READER. Part 40 created the key ahead
-- of its reader deliberately; this closes the gap inside the same migration.
--
-- THE DEFECT THIS FIXES — MEASURED ON THE REHEARSAL DB, NOT ASSUMED. The
-- checkout edge can read the rate under NEITHER credential it could present:
--   · service_role — 076:76 grants `catalog` USAGE to `anon, authenticated`
--     ONLY. has_schema_privilege('service_role','catalog','USAGE') is FALSE.
--     The edge key cannot reach the schema at all, let alone the table.
--   · authenticated — 078:234 revokes the table and grants back a
--     column-scoped SELECT, then RLS splits it in two (AUTHZ-CFG1,
--     078:353-361): catalog_platform_config_sel_public exposes
--     visibility='public' rows, while a `restricted` row rides
--     catalog_platform_config_sel_restricted, which demands
--     is_platform(['platform_admin','platform_risk']). A BUYER IS NEITHER.
-- So setting the rate would NOT have been enough to activate primary selling:
-- the feature would have stayed dead with no obvious cause — the
-- `stripe_charges_enabled` failure mode in a new place.
--
-- WHY HERE AND NOWHERE ELSE — both alternatives are worse:
--   · Granting service_role USAGE on `catalog` widens a boundary 076 drew
--     deliberately, and hands the machine plane EVERY configuration row —
--     including every money threshold — in order to read one rate.
--   · A separate kernel reader function puts pricing authority in a SECOND
--     place when this RPC is already the price authority: it is what snapshots
--     ticket_type.price_minor and computes total_minor, and §6.1's whole point
--     is that price is decided ONCE, server-side. Two pricing readers is two
--     prices.
-- This function is SECURITY DEFINER, so it reaches the row past both the
-- schema grant and the visibility restriction, and THE RATE NEVER LEAVES THE
-- DATABASE — only the derived amount does.
--
-- ORDERING, AND IT IS DELIBERATE: the A8 readiness gate runs BEFORE any fee
-- work. An organization that cannot be paid is refused without the rate ever
-- being read, so an unset rate can never mask an ineligible org (or the
-- reverse) in the error the buyer sees. The rate is then resolved and
-- validated BEFORE the item/hold loop, so an unset rate fails closed without
-- doing inventory work; only the arithmetic waits for v_total.
-- ---------------------------------------------------------------------------
-- ============================================================================
create or replace function venue.create_primary_checkout(
  p_session_id uuid, p_items jsonb, p_hold_ids uuid[], p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_sess_status text;
  v_evt_status  text;
  v_org_id    uuid;
  v_order_id  uuid;
  v_total     integer := 0;
  v_ex_id     uuid;
  v_ex_total  integer;
  v_ex_curr   text;
  v_item      jsonb;
  v_tt_id     uuid;
  v_qty       integer;
  v_price     integer;
  v_held      integer;
  v_snapshot  jsonb := '[]'::jsonb;
  -- A8/G2: the readiness operands, read once from the selling organization.
  v_org_ref    text;
  v_org_ready  boolean;
  v_org_status text;
  -- A8/G2b: the deliverability operands — the event's scope keys for the
  -- signing-key resolution, and the key that resolution finds.
  v_event_id    uuid;
  v_venue_id    uuid;
  v_signing_key uuid;
  -- A5: the buyer-side service fee. v_fee_bps is NUMERIC on purpose — the cast
  -- happens once, and an owner typo is caught by an explicit range check with a
  -- greppable message instead of a raw 22P02 out of an ::integer cast.
  v_fee_bps      numeric;
  v_fee_minor    integer;
  v_charge_total integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  -- OR-17 F-1 + E-23 gate FIRST — an acquisition refusal fires before ANY work
  -- (as 081's reserve does), so a non-ACTIVE buyer is turned away regardless of
  -- what else is in the request. F-1 (dsm §3.2, tests the caller; buyer_id =
  -- auth.uid()): refuse DELETION_PENDING. E-23: is_deletion_pending returns FALSE
  -- for ERASED, so the checkout buyer must be proven ACTIVE, not merely
  -- not-pending — the 077 F-6 / E-8 defensive-twin idiom. (Defensive: an ERASED
  -- identity cannot authenticate, but E-23 mandates the refusal be present and
  -- NOT dischargeable by is_deletion_pending alone.)
  if kernel.is_deletion_pending(v_uid) then
    raise exception 'precondition_failed: deletion_pending';
  end if;
  if exists (select 1 from kernel.identity_ext e
              where e.identity_id = v_uid and e.deletion_state = 'ERASED') then
    raise exception 'precondition_failed: identity_erased';
  end if;

  -- Idempotency short-circuit (C16): a replay of a succeeded checkout returns the
  -- original order, not a second one. DELIBERATELY AHEAD OF THE A8/G2 GATE: an
  -- order that already exists is a settled fact, and re-refusing it would turn a
  -- harmless client retry into a phantom failure after the money decision was
  -- already taken.
  -- IT ALSO CARRIES NO FEE FIELDS, DELIBERATELY. A replay is not a fresh quote:
  -- the buyer-side charge for this order was quoted on the ORIGINAL call and
  -- the edge already minted a PaymentIntent from it. Re-deriving the fee here
  -- from the CURRENT rate would silently move the price under an already-minted
  -- PI if the owner had changed fee.buyer_service_bps in between. The fee is
  -- not stored on venue."order" (see the A5 block below — total_minor is face
  -- value and nothing else on the row may carry it), so this function cannot
  -- reproduce the original quote and must not guess at one. `idempotency_replay`
  -- means "you already have this order — reuse the quote you already made."
  -- Recorded as R30-4 in the footer.
  select order_id, total_minor, currency into v_ex_id, v_ex_total, v_ex_curr
    from venue."order"
   where buyer_id = v_uid and command_idempotency_key = p_command_key;
  if v_ex_id is not null then
    return jsonb_build_object('status','idempotency_replay','order_id',v_ex_id,
                              'total_minor',v_ex_total,'currency',v_ex_curr);
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'precondition_failed: no items';
  end if;

  -- Session must be sellable (event on_sale/live) and not terminal (§6.1). org_id
  -- is server-derived from the session's event; never client-trusted.
  select e.status, s.status, e.org_id, e.event_id, e.venue_id
    into v_evt_status, v_sess_status, v_org_id, v_event_id, v_venue_id
    from catalog.event_session s
    join catalog.event e on e.event_id = s.event_id
   where s.session_id = p_session_id;
  if v_sess_status is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;
  if v_evt_status not in ('on_sale','live') then
    raise exception 'precondition_failed: not_on_sale';
  end if;
  if v_sess_status in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;

  -- ---- A8 / F §3.5 gate G2 — PAYOUT READINESS, FAIL CLOSED -----------------
  -- The organization whose event this is must have a BOUND destination AND a
  -- live `transfers` capability. Under Ruling A1/A2 the platform is merchant of
  -- record and the organization is paid later by POST /v1/transfers, so
  -- `transfers` active is what makes that transfer legal — F §3.5 rules that
  -- payouts_enabled is explicitly NOT part of this predicate (an organization
  -- that can be transferred to but cannot yet reach its bank keeps selling; the
  -- money rests in their Stripe balance and no ticket is harmed).
  -- Both operands are required: a bound ref with a dead capability is not
  -- ready, and a live-looking flag with no ref has nowhere to send money. The
  -- org row is read WITHOUT a lock on purpose — checkout moves no money, and
  -- 085's finalize is the authoritative money moment; taking a row lock on the
  -- organization here would serialize every buyer in the venue behind one row.
  --
  -- THIS READ IS LEGAL AND NEEDS NO GRANT — DO NOT "FIX" IT BY WIDENING ONE.
  -- kernel.organization revokes everything from `authenticated` and grants back
  -- only (org_id, display_name, status) (077:133-138), so a BUYER cannot read
  -- stripe_connect_account_ref or the §1 columns. This function is SECURITY
  -- DEFINER: it executes as the function owner, not as the caller, so the
  -- client-side revoke does not apply to it and the select below succeeds for
  -- every buyer without any column ever becoming client-readable. That is the
  -- whole design — the gate reads privileged state, the caller cannot. Anyone
  -- who "fixes" a permission error here by granting `authenticated` SELECT on
  -- these columns has published the payout destination of every organization
  -- on the platform to every signed-in user. The read path for humans is
  -- kernel.get_org_connect_state (§6), which masks the account id.
  select o.stripe_connect_account_ref, o.connect_transfers_active, o.status
    into v_org_ref, v_org_ready, v_org_status
    from kernel.organization o
   where o.org_id = v_org_id;

  -- G2a — ORGANIZATION STATUS, AND IT IS CHECKED FIRST.
  -- A suspended organization could sell: this function read kernel.organization
  -- for two columns and never consulted `status`, so a suspended org with a
  -- bound acct_, transfers active and a live signing key refused only on the
  -- fee key. That is inconsistent with 093's own posture — this same migration
  -- added status ∈ ('approved','active') to BOTH Connect binders (§4, §5) and to
  -- the dashboard read verb (§6), on the reasoning that an organization the
  -- platform has suspended must not move money or name a payee. SELLING is the
  -- money-path entry that was left out, and it is the exact twin of the gap the
  -- rest of this slice closed.
  --
  -- ORDERED BEFORE THE CONNECT GATE, DELIBERATELY — this is the one place my
  -- ladder diverges from the one specified, and it is the divergence that was
  -- asked for: the more FUNDAMENTAL fact should win the error. "This
  -- organization is suspended" explains the refusal completely and is actionable
  -- by exactly one party (the platform, via kernel.set_org_status). Leading with
  -- `payout_not_ready` would send an operator to re-check Stripe — where they
  -- would find nothing wrong, because nothing is — for a condition Stripe has no
  -- part in. A suspended org that is ALSO not connect-ready should still report
  -- the suspension, because resolving the Connect side would not make it
  -- sellable.
  --
  -- FAILS CLOSED ON NULL. A null status covers the org row having vanished
  -- (SELECT INTO leaves every target null when no row matches), which is
  -- stricter than the previous behaviour: that case used to fall through to
  -- `payout_not_ready`, which was accidentally correct rather than deliberately.
  -- Any status outside the pair — 'applied', 'suspended', 'closed', or anything
  -- a later migration adds — refuses. X-12 restrictive: unknown authorizes
  -- NOTHING.
  --
  -- SCOPE, FOR THE RECORD, since this lands late in 093's life: 093 has never
  -- reached production; this is the same primary-ticketing atomic contract; it
  -- adds NO object and NO column, being a body-only CREATE OR REPLACE of a
  -- function 093 already replaces for G2/G2b/A5. THE OBJECT CENSUS DOES NOT
  -- MOVE: this change creates nothing, so whatever the slice's object count is
  -- at assembly time, this clause does not alter it.
  if v_org_status is null or v_org_status not in ('approved','active') then
    raise exception 'precondition_failed: org_not_active — a % organization may not sell', coalesce(v_org_status,'missing');
  end if;

  if v_org_ref is null or coalesce(v_org_ready, false) is not true then
    -- X-12 restrictive reading: absent or unknown state authorizes NOTHING.
    raise exception 'precondition_failed: payout_not_ready';
  end if;
  -- ---- end A8 / G2 ---------------------------------------------------------

  -- ---- A8 / G2b — SIGNING-KEY DELIVERABILITY, FAIL CLOSED -----------------
  -- THE DEFECT THIS CLOSES: with ZERO signing keys in the database an order was
  -- created, the buyer paid, the webhook called venue.finalize_primary_order,
  -- and the mint raised `no_active_signing_key` (083:513-530) — AFTER the
  -- PaymentIntent was confirmed. The buyer is charged and holds no ticket, and
  -- with the refund executor undeployed and kernel.mark_refund_state without a
  -- caller, nothing gives the money back automatically. G2 asks whether the
  -- VENUE can be paid; this asks whether the BUYER can be delivered to. The
  -- owner's SALEABLE rule covers both: do not sell what Snatch It cannot
  -- honour, and a sale that provably cannot mint a ticket is the clearest case.
  --
  -- THE PREDICATE IS COPIED FROM THE MINT, NOT APPROXIMATED. A gate looser than
  -- the mint's would pass here and fail there, which is the bug being closed —
  -- so this is venue.finalize_primary_order's own resolution (085:1948-1960)
  -- character for character: active status, inside [not_before, not_after), and
  -- a scope that GOVERNS this event, ordered MOST SPECIFIC FIRST — per_event
  -- outranks per_venue outranks global. 083:517-527 then re-validates the
  -- pinned key with the identical conditions, so a key this finds is a key the
  -- mint accepts.
  --
  -- The `order by … limit 1` is retained even though a bare EXISTS would be
  -- logically equivalent for a yes/no gate: the ordering is what makes this
  -- visibly the SAME query as finalize's, so a future change to the precedence
  -- there is an obvious mismatch here rather than a silent divergence.
  --
  -- FAILS CLOSED ON EVERY AMBIGUITY: no key at all, a key that is inactive, one
  -- not yet in force, one already expired, or one whose scope does not govern
  -- this event all resolve to NULL and refuse. This gate is ON from the moment
  -- 093 applies and stays on until the ruling-B bootstrap key row exists — the
  -- owner ceremony (093 scope item 2) — which is the correct resting state:
  -- until that row exists, no ticket can be minted by anything.
  --
  -- NOTHING HERE PROVISIONS A KEY. Ruling B parks kernel.provision_signing_key
  -- and rotate_signing_key as unconditional raises, and this slice neither
  -- un-parks them nor inserts a signing_key row. A gate that could mint its own
  -- key would defeat the two-person KMS ceremony it exists to wait for.
  select k.key_id into v_signing_key
    from kernel.signing_key k
   where k.status = 'active'
     and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
     and (   (k.scope = 'per_event' and k.event_id = v_event_id)
          or (k.scope = 'per_venue' and k.venue_id = v_venue_id)
          or (k.scope = 'global'))
   order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
   limit 1;
  if v_signing_key is null then
    raise exception 'precondition_failed: no_active_signing_key — an active signing key must resolve for the event scope before a ticket can be sold';
  end if;
  -- The key is NOT pinned onto the order. Resolution happens again at finalize
  -- under the rank-1 session lock (085:1943-1960), which is the correct place
  -- for it: a key legitimately rotated between checkout and payment must not be
  -- frozen by a value captured here, and venue."order" has no column for one.
  -- This gate proves DELIVERABILITY AT QUOTE TIME; finalize decides WHICH key.
  -- ---- end A8 / G2b --------------------------------------------------------

  -- ---- A5 — BUYER SERVICE FEE RATE, FAIL CLOSED ---------------------------
  -- STRICTLY AFTER the gate above: an organization that cannot be paid is
  -- refused before the rate is read at all. STRICTLY BEFORE the item loop: an
  -- unset rate refuses without doing hold/inventory work.
  -- Same platform_config idiom as the money code (085:1646-1647) — highest
  -- version wins, and `#>> '{}'` turns the seeded jsonb `null` into a SQL NULL.
  select (c.value #>> '{}')::numeric into v_fee_bps
    from catalog.platform_config c
   where c.key = 'fee.buyer_service_bps'
   order by c.version desc limit 1;
  -- THE OWNER STOP (A5): "No service-fee percentage is hardcoded in migration
  -- 093. No percentage is invented anywhere." An unset rate must REFUSE TO
  -- QUOTE. It must never fall back to zero: that would sell the ticket at face
  -- value with no platform revenue, and settlement lines are append-only with a
  -- write-once header, so revenue not recognised at the sale can never be
  -- restated afterwards. A missing KEY reads the same as a null VALUE and is
  -- refused identically — X-12 restrictive: absent state authorizes NOTHING.
  -- Distinct and greppable on purpose; this is the error that will be seen at
  -- activation if the rate was never set, and it must name its own cause.
  if v_fee_bps is null then
    raise exception 'precondition_failed: service_fee_unset — fee.buyer_service_bps has no value; selling cannot be activated until the owner sets it';
  end if;
  -- Bare integer basis points, 0..10000 — the shape of catalog.resale_policy
  -- .price_cap_bps / .royalty_bps (078:258-261). A fractional or out-of-band
  -- value is an owner typo, and a typo in a money rate fails closed.
  if v_fee_bps < 0 or v_fee_bps > 10000 or v_fee_bps <> trunc(v_fee_bps) then
    raise exception 'precondition_failed: service_fee_out_of_range — fee.buyer_service_bps must be an integer 0..10000, got %', v_fee_bps;
  end if;
  -- ---- end A5 rate resolution ----------------------------------------------

  -- Validate items and snapshot the server-authoritative price ONCE per item
  -- (§6.1: a SINGLE server snapshot — the same value backs total_minor AND the
  -- line item, so a concurrent set_ticket_type_price cannot make them diverge),
  -- then prove the buyer's ACTIVE holds cover each item's quantity for THIS
  -- session (holds belong to the buyer, are active, not expired — §6.1). Money
  -- never moves; the authoritative held→sold conversion + oversell backstop
  -- (C27) is 085/finalize, which MUST re-read hold status + re-derive capacity
  -- under the batch FOR UPDATE (forward obligation — see governance E-40).
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_tt_id := (v_item->>'ticket_type_id')::uuid;
    v_qty   := (v_item->>'quantity')::integer;
    if v_tt_id is null or v_qty is null or v_qty <= 0 then
      raise exception 'precondition_failed: bad_item';
    end if;

    select tt.price_minor into v_price
      from venue.ticket_type tt
     where tt.ticket_type_id = v_tt_id;
    if v_price is null then
      raise exception 'not_found: ticket type %', v_tt_id using errcode = 'P0002';
    end if;

    -- coverage: sum of the buyer's active, unexpired holds for batches of this
    -- ticket_type in this session must be >= the requested quantity.
    select coalesce(sum(h.quantity), 0) into v_held
      from venue.inventory_hold h
      join venue.inventory_batch b on b.batch_id = h.batch_id
     where h.hold_id = any(p_hold_ids)
       and h.identity_id = v_uid
       and h.status = 'active'
       and h.expires_at > now()
       and b.ticket_type_id = v_tt_id
       and b.event_session_id = p_session_id;
    if v_held < v_qty then
      raise exception 'precondition_failed: holds do not cover item (type %, need %, held %)', v_tt_id, v_qty, v_held;
    end if;

    v_total := v_total + (v_price * v_qty);
    -- carry the ONE snapshotted price forward; the line item is written from
    -- this, never re-read, so order.total_minor = Σ(order_item.unit_price × qty).
    v_snapshot := v_snapshot || jsonb_build_array(
      jsonb_build_object('tt', v_tt_id, 'qty', v_qty, 'price', v_price));
  end loop;

  -- ---- A5 — THE FEE AMOUNT, AND WHAT IT IS *NOT* --------------------------
  -- Derived "from the base in integer cents, half-up"
  -- (docs/phase2/_decisions/A_venue_money.md:115). round() on numeric is
  -- half-away-from-zero and v_total is non-negative, so that IS half-up here.
  v_fee_minor    := round(v_total::numeric * v_fee_bps / 10000)::integer;
  v_charge_total := v_total + v_fee_minor;
  --
  -- *** READ THIS BEFORE CHANGING ANYTHING BELOW — THE SINGLE MOST
  -- *** MISREADABLE LINE IN THIS MIGRATION:
  -- venue."order".total_minor STAYS FACE VALUE. THE FEE IS NEVER ADDED TO IT.
  -- Ruling A5 fixes the venue's entitlement at the configured ticket face
  -- value and subtracts no platform fee from it, because Snatch It's revenue
  -- is BUYER-FUNDED and collected at checkout, not deducted at settlement. The
  -- settlement revenue seam (093 scope item 11) reads total_minor as the
  -- venue's gross, so folding the buyer fee into that column would pay the
  -- venue the platform's own revenue — silently, in an append-only ledger with
  -- no delete and a write-once header. The fee exists ONLY on the buyer's
  -- charge: it rides out in the return below, the edge mints a PaymentIntent
  -- for charge_total_minor, and no column on venue."order" ever carries it.
  -- The insert below is therefore UNCHANGED and must stay unchanged.
  -- ---- end A5 fee amount ---------------------------------------------------

  -- Create the pending order + items in one inner block. source is server-tagged;
  -- the frozen §6.1 signature carries no source hint and the rail is dark, so 'web'
  -- is the inert placeholder (owner-owed-forward, E-39). Candidate columns stay
  -- NULL (R2B/C112 — no promoter tables until 090). A concurrent C16 replay (both
  -- submits pass the short-circuit above, the loser trips order_buyer_command_uq)
  -- returns idempotency_replay, not a raw 23505 — the 081 reserve idiom. Scoped to
  -- the INSERTs so the gate's FOR SHARE lock on identity_ext (taken above via
  -- is_deletion_pending, F-11) is held to commit, outside this savepoint.
  begin
    insert into venue."order" (buyer_id, event_session_id, org_id, status, source,
                               total_minor, currency, command_idempotency_key)
    values (v_uid, p_session_id, v_org_id, 'pending', 'web', v_total, 'USD', p_command_key)
    returning order_id into v_order_id;

    for v_item in select * from jsonb_array_elements(v_snapshot) loop
      insert into venue.order_item (order_id, ticket_type_id, quantity, unit_price_minor, currency)
      values (v_order_id, (v_item->>'tt')::uuid, (v_item->>'qty')::integer,
              (v_item->>'price')::integer, 'USD');
    end loop;
  exception when unique_violation then
    -- the C16 (buyer, command_key) race: the other txn committed the order first.
    select order_id, total_minor, currency into v_ex_id, v_ex_total, v_ex_curr
      from venue."order"
     where buyer_id = v_uid and command_idempotency_key = p_command_key;
    if not found then raise; end if;   -- a different unique violation (e.g. a dup item)
    -- No fee fields here either, for the same reason as the C16 short-circuit
    -- above: the winning transaction produced the quote, and this loser must
    -- not mint a second, possibly different one (R30-4).
    return jsonb_build_object('status','idempotency_replay','order_id',v_ex_id,
                              'total_minor',v_ex_total,'currency',v_ex_curr);
  end;

  -- total_minor is FACE VALUE (the venue's entitlement and the settlement
  -- seam's gross); buyer_fee_minor is the platform's buyer-funded revenue; and
  -- charge_total_minor is the ONLY figure the PaymentIntent may be minted for.
  -- `buyer_fee` is the corpus noun for exactly this money (public.payments,
  -- 000:982-985; and the config namespace already carries
  -- refund.buyer_fee_refundable, 078:1550) — not an invented name.
  -- org_id rides out on the SUCCESS return ONLY. Its single consumer is
  -- metadata[org_id] on the PaymentIntent, which the webhook's organization arm
  -- joins on (F §3.6(1)) — and the edge cannot derive it any other way: reading
  -- venue."order" or kernel.organization with the service_role client is 42501
  -- (no table privilege exists in either schema for that role). It is
  -- DELIBERATELY ABSENT from both idempotency_replay returns: that path reuses
  -- an existing PaymentIntent and mints no new metadata, so it has no use for
  -- the value, and supplying one would invite exactly the re-derivation the fee
  -- fields were kept off those returns to prevent (R30-4).
  return jsonb_build_object('status','ok','order_id',v_order_id,
                            'org_id',v_org_id,
                            'total_minor',v_total,'currency','USD',
                            'buyer_fee_minor', v_fee_minor,
                            'charge_total_minor', v_charge_total);
end;
$$;


-- ============================================================================
-- §4 — kernel.set_org_connect_ref: the FIRST BIND, hardened.
--   Rulings A7 ("A caller must never be permitted to supply or bind an
--   arbitrary acct_ identifier"; "cross-plane reuse of an ordinary seller's
--   existing connected account must be prevented") and A9 (attachment is a
--   privileged, audited operation) · G §2 threats G-1/G-6, §5.1 · scope item 8.
--
-- SIGNATURE IS UNCHANGED AND MUST STAY UNCHANGED. `create or replace function`
-- CANNOT drop a parameter — dropping p_connect_account_id would be a DROP and
-- CREATE, which is a new object with a new ACL and is out of scope for an
-- additive migration. THE CALLER-SUPPLIED IDENTIFIER THEREFORE STAYS IN THE
-- SIGNATURE ON PURPOSE. What eliminates the attack is the REFUSAL IN THE BODY,
-- not the shape of the argument list. Do not "tidy" this parameter away, and
-- do not read its presence as permission for a caller to choose an account:
-- the edge function mints the account server-side with metadata[org_id] and
-- passes back only the id IT minted (F §3.2), and everything below exists to
-- make any other value unusable.
--
-- WHAT CHANGED vs 077:948-1013 — four additions and one narrowing:
--   (a) CROSS-PLANE REFUSAL (G-1, the highest-value line in this migration).
--   (b) org_owner ONLY — org_finance dropped from the role set.
--   (c) status narrowed to ('approved','active') — 'applied' no longer binds.
--   (d) aal2 step-up required, in the 085:1624-1631 shape.
--   (e) best-effort security notification (G-2).
-- Everything else — the caller-JWT requirement, the regex, the row lock, the
-- noop_replay path, BIND-ONCE, the SoD-1 stamp, the unique_violation mapping,
-- the audit row and the return shape — is preserved verbatim.
--
-- WHAT DELIBERATELY DID NOT CHANGE: no money-role maturity requirement on the
-- FIRST bind. G §5.1 recommends one; the owner declined it for this verb and
-- the reasoning is decisive — maturity here forces a waiting period before
-- onboarding can even BEGIN, at a moment when the organization holds no money
-- and none is at risk. Maturity stays where it belongs, on the re-point (§5),
-- where a live destination is being taken away.
-- ============================================================================
create or replace function kernel.set_org_connect_ref(
  p_org_id uuid, p_connect_account_id text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_ref       text;
  v_status    text;
  v_pending   text;
  v_aal       text;
  v_audit_id  uuid;
  v_recipient uuid;
begin
  -- §20.1.1 / §0.1a: EDGE-CALLER-JWT bound — a service-role invocation has
  -- auth.uid() NULL and must RAISE rather than bind (T-RPC-CONNECT-04).
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: caller JWT required — connect-onboarding must use the caller''s Authorization header'
      using errcode = '42501';
  end if;
  -- A9 / G §5.1 — NARROWED from ('org_owner','org_finance'). Attaching the
  -- payee IS replacing it when the prior value was nothing, and SoD-1 already
  -- reserves the destination to org_owner on the re-point (085:1618-1620).
  -- org_finance retains initiate-the-Stripe-flow and view; it no longer binds.
  -- Roles are single-valued with NO inheritance (077:150) — an org_owner row
  -- can never satisfy has_org_role(['org_finance']) and vice versa, so this is
  -- a real narrowing, not a notational one.
  if not kernel.has_org_role(p_org_id, array['org_owner']) then
    raise exception 'insufficient_privilege: org_owner required (SoD-1; org_finance may initiate onboarding but may not bind the payee)'
      using errcode = '42501';
  end if;
  -- AUTHZ-M4: step-up demanded, fail closed — an absent claim can never be
  -- evaluated as satisfied. Same shape as 085:1624-1631. Binding the payee is
  -- a money-destination act and carries the money-destination step-up.
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to bind a payout destination';
  end if;
  if p_connect_account_id is null or p_connect_account_id !~ '^acct_[A-Za-z0-9]+$' then
    raise exception 'precondition_failed: malformed_account_ref';
  end if;

  -- ---- A7 / A9 / G-1 — THE CROSS-PLANE REFUSAL ----------------------------
  -- THIS IS THE LINE THAT CLOSES THE PERSONAL-SELLER-ACCOUNT ATTACK.
  -- 077:124-126 is UNIQUE(stripe_connect_account_ref) WHERE NOT NULL on
  -- kernel.organization — it is PER-PLANE and cannot see the individual plane
  -- at all. A staff member who has onboarded as an ordinary Snatch It seller
  -- already HOLDS a valid acct_ id (create-connect-account/index.ts:212); with
  -- nothing but a regex in the way, binding it here points every settlement
  -- payout for that organization at a personal account, indefinitely and
  -- silently. Total impact, most likely attack, one `exists` clause.
  -- The archive is included as well (044): an id that was archived off a
  -- profile is still an account the platform minted for an INDIVIDUAL, and
  -- re-minting on the individual plane must never hand the org plane a
  -- laundering route.
  -- Placed BEFORE the row read, so a replay carrying a poisoned id is refused
  -- rather than short-circuiting through the noop path below. Fail closed.
  if exists (select 1 from public.profiles pf
              where pf.stripe_connect_id = p_connect_account_id)
     or exists (select 1 from public.stripe_connect_archive ar
                 where ar.stripe_connect_id = p_connect_account_id) then
    -- errcode: this is a refusal of the SUPPLIED VALUE, not of the caller, so it
    -- is a precondition (P0001), matching every other precondition_failed here.
    raise exception 'precondition_failed: account_not_platform_minted_for_org — this account belongs to the individual seller plane';
  end if;
  -- ---- end cross-plane refusal --------------------------------------------

  select o.stripe_connect_account_ref, o.status, o.connect_pending_ref
    into v_ref, v_status, v_pending
    from kernel.organization o where o.org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: organization %', p_org_id;
  end if;
  -- G-6 — NARROWED from ('applied','approved','active'). A payee is bound
  -- AFTER platform review, never before. This also SUBSUMES the probation-clock
  -- defect: the probation operand is max(occurred_at) over the bind/change
  -- audit actions (087:472-476), so a bind that could precede approval let a
  -- fraudster age the probation window out before the org was ever reviewed.
  -- A bind can no longer precede approval, so the clock can no longer be
  -- started early — no change to 087 is required.
  if v_status not in ('approved','active') then
    raise exception 'precondition_failed: org_not_bindable — a % org may not bind a payee (approval precedes the payee)', v_status;
  end if;

  if v_ref is not null and v_ref = p_connect_account_id then
    -- the "reuse existing connect ids" re-onboarding retry path
    return jsonb_build_object('status', 'noop_replay', 'org_id', p_org_id,
                              'connect_account_id', v_ref, 'newly_bound', false);
  end if;
  if v_ref is not null then
    -- BIND-ONCE: a re-point is never an onboarding event; the only path is
    -- kernel.set_org_payout_destination (§17.7, a later package).
    raise exception 'precondition_failed: destination_already_set — re-pointing rides kernel.set_org_payout_destination only';
  end if;

  -- ---- A7 / RT-A-3 — THE PROVENANCE REQUIREMENT ---------------------------
  -- THIS IS THE CHECK THAT MAKES "the caller may not supply an arbitrary acct_"
  -- TRUE RATHER THAN ADVISORY. The identifier must equal the one the platform
  -- itself minted for THIS organization and recorded via §2b, which only
  -- service_role can call. The cross-plane refusal above is a blocklist and
  -- cannot catch an attacker's own fresh Stripe account — the red team bound
  -- `acct_ORPHANATTACKER` straight through it. This is an allowlist of exactly
  -- one value, and it is written by a credential a browser session never holds.
  --
  -- PLACED AFTER THE REPLAY AND BIND-ONCE ARMS ON PURPOSE. A successful bind
  -- CLEARS connect_pending_ref (below), so a replay of the same call arrives
  -- with nothing staged; checking provenance first would turn the idempotent
  -- retry that G-8 depends on — and that tests/141:638-641 asserts — into a
  -- hard failure. Order: replay → bind-once → provenance → write.
  if v_pending is null then
    raise exception 'precondition_failed: no_pending_connect_ref — no account has been minted for this organization; onboarding must run through the connect-onboarding edge function';
  end if;
  if v_pending <> p_connect_account_id then
    raise exception 'precondition_failed: connect_ref_not_platform_minted — this identifier was not minted by the platform for this organization';
  end if;
  -- ---- end provenance ------------------------------------------------------

  begin
    update kernel.organization
       set stripe_connect_account_ref = p_connect_account_id,
           -- SoD-1 applies from the very first destination
           payout_destination_set_by  = v_uid,
           -- SINGLE USE: consumed at the bind so it cannot be replayed into a
           -- later re-point. A new destination requires a new mint and a new
           -- staging call, which is exactly the property A9 wants — "a live
           -- payout destination is never silently replaced".
           connect_pending_ref        = null
     where org_id = p_org_id;
  exception when unique_violation then
    raise exception 'conflict_locked: connect account already bound to another org';
  end;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.connect_ref.bind', 'organization', p_org_id, 'onboarding',
          null, jsonb_build_object('connect_account_id', p_connect_account_id))
  returning id into v_audit_id;

  -- ---- A9 / G-2 — the human tripwire, BEST-EFFORT --------------------------
  -- security_payout_destination_changed has existed in the deployed catalogue
  -- since 092:269 with templates at 092:336-337 and has had ZERO producers
  -- anywhere in the repo. The destination could change and nobody was told.
  -- Pattern is change_org_role's verbatim (077:1263-1279): wrapped in
  -- begin…exception when others then raise warning, keyed on the admin_audit
  -- row id (the PFA-2 per-occurrence collision rule), so a failed emit warns
  -- and the bind still commits — N-A30. The bind does not read the envelope.
  -- Recipients: every org_owner AND org_finance. The brief names owners; G §6.2
  -- names "every org_owner and org_finance of the org, plus the actor", and the
  -- superset is used because under-notifying the finance role is precisely the
  -- G-2 defect. The actor is included when they hold either role, which after
  -- the (b) narrowing above they always do.
  -- Payload carries the LAST 4 ONLY, never the acct_ id: the templates ask only
  -- for {{destination_last4}} (092:336), and Connect ids may not leave the
  -- trust boundary (G §6.1).
  begin
    for v_recipient in
      select m.identity_id from kernel.org_member m
       where m.org_id = p_org_id and m.role in ('org_owner','org_finance')
    loop
      perform notify.emit_event(
        'security_payout_destination_changed', 'identity', v_recipient,
        'security_payout_destination:' || v_audit_id::text || ':' || v_recipient::text,
        jsonb_build_object('org_id', p_org_id,
                           'destination_last4', right(p_connect_account_id, 4),
                           'origin', 'connect_ref_bind',
                           'actor_identity', v_uid));
    end loop;
  exception when others then
    raise warning 'set_org_connect_ref: best-effort security notice emit failed: %', sqlerrm;
  end;

  return jsonb_build_object('status', 'ok', 'org_id', p_org_id,
                            'connect_account_id', p_connect_account_id, 'newly_bound', true);
end;
$$;


-- ============================================================================
-- §5 — kernel.set_org_payout_destination: the RE-POINT, hardened.
--   Rulings A7 (both binding surfaces must reject caller-selected account ids)
--   and A9 ("Replacement of an existing organization Stripe account is treated
--   as higher risk than first-time onboarding") · G §2 threats G-1/G-3/G-6,
--   §5.1 · scope item 9.
--
-- WHY THIS VERB IS NOT OPTIONAL WORK. It is granted to `authenticated`
-- (085:2137) and reachable through PostgREST in one call. Hardening only the
-- first bind would leave settlement money re-pointable to a personal seller
-- account, invisible to 077:124-126 because that index is per-plane. A first
-- bind risks no money; a re-point risks all of it.
--
-- WHAT CHANGED vs 085:1601-1662 — three additions, nothing removed:
--   (a) the SAME cross-plane refusal as §4 (G-1).
--   (b) an ORGANIZATION-STATUS gate — today a SUSPENDED org can re-point
--       (G-6 / G §5.1: "suspension must freeze the payee").
--   (c) the same best-effort security notification (G-2).
-- Every existing control is kept exactly: org_owner only (SoD-1), money-role
-- grant maturity, aal2 step-up with the fail-closed absent-claim arm, the row
-- lock, the cool-down refusal, the cool-down write from platform_config, the
-- SoD-1 setter stamp and the audit row.
--
-- DELIBERATELY NOT CHANGED HERE: the cool-down key still fails OPEN when its
-- value is null (085:1650, seeded null at 078:1553) — the owner ruled that
-- setting `payout.destination_cooldown_hours` is CONFIGURATION, not migration
-- work (093 scope, OUT), and it must be set before activation. And the missing
-- unique_violation → conflict_locked mapping (G-4a) stays missing: the owner
-- ruled it cosmetic and out of 093. Neither is fixed here; both are recorded.
-- ============================================================================
create or replace function kernel.set_org_payout_destination(
  p_org_id uuid, p_connect_account_ref text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org       kernel.organization%rowtype;
  v_aal       text;
  v_cool      numeric;
  v_audit_id  uuid;
  v_recipient uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: no principal' using errcode = '42501';
  end if;
  if not kernel.has_org_role(p_org_id, array['org_owner']) then
    raise exception 'insufficient_privilege: org_owner only (SoD-1)' using errcode = '42501';
  end if;
  if not kernel.money_role_grant_matured(p_org_id) then
    raise exception 'sod_violation: org money grant not yet matured';
  end if;
  -- AUTHZ-M4: step-up demanded (the key's NULL seed DEMANDS it — fail closed);
  -- an absent claim can never be evaluated as satisfied.
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required for money-destination changes';
  end if;
  if p_connect_account_ref is null or p_connect_account_ref !~ '^acct_[A-Za-z0-9]+$' then
    raise exception 'precondition_failed: bad connect account ref';
  end if;

  -- ---- A7 / A9 / G-1 — THE CROSS-PLANE REFUSAL, TWIN OF §4 ----------------
  -- Same rule, same reason, and MORE consequential here: this verb re-points a
  -- LIVE destination. As in §4 the caller-supplied parameter cannot be dropped
  -- by create-or-replace, so the refusal in the body is the control. The
  -- account must be one the platform minted FOR AN ORGANIZATION; anything that
  -- has ever sat on the individual plane (live in profiles, or archived by the
  -- 044 self-heal) is refused outright.
  if exists (select 1 from public.profiles pf
              where pf.stripe_connect_id = p_connect_account_ref)
     or exists (select 1 from public.stripe_connect_archive ar
                 where ar.stripe_connect_id = p_connect_account_ref) then
    -- errcode: this is a refusal of the SUPPLIED VALUE, not of the caller, so it
    -- is a precondition (P0001), matching every other precondition_failed here.
    raise exception 'precondition_failed: account_not_platform_minted_for_org — this account belongs to the individual seller plane';
  end if;
  -- ---- end cross-plane refusal --------------------------------------------

  select * into v_org from kernel.organization where org_id = p_org_id for update;
  if not found then
    raise exception 'not_found: org %', p_org_id using errcode = 'P0002';
  end if;
  -- G-6 / G §5.1 — NEW. This verb performed NO org-status check at all, so a
  -- SUSPENDED organization's owner could re-point the payee while the platform
  -- believed the org was frozen. Suspension must freeze the payee: the same
  -- ('approved','active') set §4 now requires, so the two surfaces agree.
  if v_org.status not in ('approved','active') then
    raise exception 'precondition_failed: org_not_bindable — a % org may not re-point its payout destination', v_org.status;
  end if;
  -- ---- A7 / A9 / RT-A-3 — PROVENANCE, AND IT MATTERS MORE HERE ------------
  -- The red team re-pointed a LIVE destination to `acct_ORPHANATTACKER`. A9 is
  -- explicit that replacement is HIGHER RISK than first-time onboarding, so the
  -- verb that moves settlement money away from an existing payee cannot have a
  -- weaker provenance rule than the one that sets the first. Identical check,
  -- identical errors: the new destination must be an account the platform
  -- minted for THIS organization and staged through §2b (service_role only).
  -- There is no replay arm on this verb, so this sits with the other
  -- preconditions rather than after them.
  if v_org.connect_pending_ref is null then
    raise exception 'precondition_failed: no_pending_connect_ref — no replacement account has been minted for this organization; a re-point must run through the connect-onboarding edge function';
  end if;
  if v_org.connect_pending_ref <> p_connect_account_ref then
    raise exception 'precondition_failed: connect_ref_not_platform_minted — this identifier was not minted by the platform for this organization';
  end if;
  -- ---- end provenance ------------------------------------------------------
  if v_org.payout_destination_locked_until is not null and v_org.payout_destination_locked_until > now() then
    raise exception 'precondition_failed: destination cool-down until %', v_org.payout_destination_locked_until;
  end if;
  select (c.value #>> '{}')::numeric into v_cool from catalog.platform_config c
   where c.key = 'payout.destination_cooldown_hours' order by c.version desc limit 1;

  update kernel.organization
     set stripe_connect_account_ref = p_connect_account_ref,
         payout_destination_set_by = v_uid,
         payout_destination_locked_until = case when v_cool is null then null
                                                else now() + make_interval(hours => v_cool::int) end,
         -- consumed, exactly as at the first bind: one mint, one re-point
         connect_pending_ref = null,
         updated_at = now()
   where org_id = p_org_id;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.payout_destination.change', 'organization', p_org_id,
          coalesce(p_reason_code,'destination_change'),
          jsonb_build_object('connect_ref', v_org.stripe_connect_account_ref),
          jsonb_build_object('connect_ref', p_connect_account_ref))
  returning id into v_audit_id;

  -- ---- A9 / G-2 — the human tripwire, BEST-EFFORT (twin of §4) -------------
  -- "A live payout destination is never silently replaced" (A9). Recipients are
  -- every org_owner and org_finance INCLUDING any who did not act — that is the
  -- whole point: the org's other owners learn of a re-point they did not make.
  -- G §5.2 downgraded in-database dual control (unbuildable: kernel.
  -- approval_request closes its action/subject_kind vocabularies at frozen
  -- CHECKs, 077:269-276/299-302, and a destination change has no amount_minor).
  -- THIS NOTIFICATION IS ONE OF THE THREE SUBSTITUTES, alongside the SoD-1
  -- payout exclusion (087:428-431) and destination probation (087:465-495).
  -- Best-effort: a failed emit must never roll back the change.
  begin
    for v_recipient in
      select m.identity_id from kernel.org_member m
       where m.org_id = p_org_id and m.role in ('org_owner','org_finance')
    loop
      perform notify.emit_event(
        'security_payout_destination_changed', 'identity', v_recipient,
        'security_payout_destination:' || v_audit_id::text || ':' || v_recipient::text,
        jsonb_build_object('org_id', p_org_id,
                           'destination_last4', right(p_connect_account_ref, 4),
                           'origin', 'payout_destination_change',
                           'actor_identity', v_uid));
    end loop;
  exception when others then
    raise warning 'set_org_payout_destination: best-effort security notice emit failed: %', sqlerrm;
  end;

  return jsonb_build_object('status','ok','org_id', p_org_id);
end;
$$;

-- ============================================================================
-- §6 — kernel.get_org_connect_state: the READ path.
--   Ruling F §3.5 gate G5 ("Venue dashboard — client display only, never the
--   enforcement point — reads the same state via a read RPC") and F §3.7(6)
--   (the Payments status section). Prescribed there, never authored.
--
-- BELONGS WITH §1 — it reads the two columns §1 adds, and is placed last only
-- to avoid renumbering the sections above.
--
-- WHY IT IS NOT OPTIONAL: without it the resolve-before-create property of the
-- onboarding edge has no way to read the fact it depends on.
-- kernel.organization.stripe_connect_account_ref is readable by NEITHER role
-- that could ask: `authenticated` is revoked down to (org_id, display_name,
-- status) (077:133-138), and service_role holds USAGE ONLY on the kernel
-- schema with no table grant (085:2092-2095, PFA-21). So an edge function that
-- cannot call this verb cannot tell whether an organization already has a
-- Stripe account, and its only safe-looking option — mint one — is exactly the
-- failure this closes: a SECOND connected account for an org that already had
-- one, which 077:124-126 then refuses at bind time, leaving an orphaned live
-- Stripe account with no row pointing at it and no way to reach it.
--
-- CALLER-AUTHORIZED, NOT A MACHINE VERB. Granted to `authenticated` only —
-- never service_role. The onboarding edge already forwards the caller's
-- Authorization header because §4 RAISES without a caller JWT (077:962-966);
-- this read rides the same session, so authority is evaluated against a real
-- human on every call. A service_role grant would also be inert by
-- construction: has_org_role tests auth.uid() (077:453-466), which is NULL on
-- a machine session, so a service_role caller would earn 42501 anyway — but
-- the grant is withheld deliberately rather than left to that accident.
--
-- AUTHORITY: org_owner or org_finance — the same set F §3.4 gives the INITIATE
-- and RECONNECT actions, which are the two things this read serves. NOT
-- widened to venue roles: F §3.4 gives venue_manager/venue_finance a one-
-- sentence gate REASON and explicitly no account reference, and that carve-out
-- is a separate, narrower verb if the dashboard ever needs it. Not widened to
-- platform roles either (list_org_payouts admits them at 085:1452-1454; this
-- verb has no support use case yet, and minimality governs 093).
--
-- NEVER RETURNS THE FULL acct_ ID. Last 4 and a boolean, nothing more —
-- G §6.1 and PHASE_2_CRM_EXPORT_SPEC.md:285 bar Connect ids from leaving the
-- trust boundary, and F §3.7(6) specifies the account is shown MASKED. The
-- edge does not need the id: it re-reads live truth from Stripe by retrieving
-- the account it minted, and Postgres is only telling it whether a binding
-- already exists and what the last observed capability state was.
--
-- SAFE BEFORE ANY BINDING EXISTS — this is the NORMAL FIRST CALL. An unbound
-- org returns connect_bound=false, never not_found. There is no not_found arm
-- at all: has_org_role is a live join on kernel.org_member, so a caller
-- holding a role on a non-existent org is not representable, and a missing org
-- is refused as 42501 before the row is ever read.
-- ============================================================================
create or replace function kernel.get_org_connect_state(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org kernel.organization%rowtype;
begin
  if p_org_id is null then
    raise exception 'invalid_input: an org scope is required (no scope-free form)';
  end if;
  if not kernel.has_org_role(p_org_id, array['org_owner','org_finance']) then
    raise exception 'insufficient_privilege: org_owner or org_finance required'
      using errcode = '42501';
  end if;

  select * into v_org from kernel.organization where org_id = p_org_id;

  return jsonb_build_object(
    'status', 'ok',
    'org_id', p_org_id,
    -- org_status is ALREADY client-readable (077:120-123 grants it), so it
    -- discloses nothing new — and it has a named reader: §4 now refuses to bind
    -- a payee for an org that is not approved/active, so an edge that minted
    -- first and bound second would strand a live Stripe account on an 'applied'
    -- org. This field is what lets the edge refuse honestly BEFORE it mints.
    'org_status', v_org.status,
    -- The resolve-before-create operand. A boolean, never the id.
    'connect_bound', (v_org.stripe_connect_account_ref is not null),
    -- ANTI-FOOTGUN, added after the red team found the edge reading a key that
    -- did not exist. An edge that does `if (!state.connect_account_ref) mint()`
    -- got `undefined` for a BOUND org, treated it as unbound, and — past
    -- Stripe's 24h idempotency window — would mint an ORPHAN LIVE ACCOUNT on
    -- every attempt. This key therefore EXISTS and is deliberately non-null
    -- whenever the org is bound, so that mistake short-circuits correctly:
    --   unbound -> null   => the edge mints, which is right
    --   bound   -> sentinel (truthy, non-empty) => the edge does NOT mint
    -- and if it then hands the sentinel to Stripe it gets an immediate 400 for
    -- an unknown account. A loud, harmless failure replaces a silent orphan.
    -- THE REAL ANSWER IS §7, kernel.get_org_connect_ref (service_role only) —
    -- the sentinel names it so a reader debugging this lands on the right verb.
    -- Do NOT "fix" this by returning the identifier: §6 is granted to
    -- `authenticated` and is one PostgREST call from any browser session.
    'connect_account_ref', case when v_org.stripe_connect_account_ref is null
                                then null
                                else 'masked:call_kernel.get_org_connect_ref' end,
    -- Masked, per F §3.7(6). NULL when unbound — not an empty string, so the
    -- client cannot render "ending in ____" for an org with no account.
    'connect_account_last4', case when v_org.stripe_connect_account_ref is null
                                  then null
                                  else right(v_org.stripe_connect_account_ref, 4) end,
    -- The §1 mirror. LAST OBSERVED, NOT LIVE TRUTH — pair it with the stamp
    -- below and re-read Stripe rather than asserting a stale green (F §3.3).
    'connect_transfers_active', v_org.connect_transfers_active,
    'connect_state_synced_at', v_org.connect_state_synced_at);
end;
$$;

-- 076 grant discipline: revoke the default PUBLIC EXECUTE, then one targeted
-- grant. `authenticated` ONLY — anon never, service_role never (see the header:
-- this verb is caller-authorized by design, and the machine plane has no
-- business enumerating payout state).
revoke all on function kernel.get_org_connect_state(uuid)
  from public, anon, authenticated;
grant execute on function kernel.get_org_connect_state(uuid) to authenticated;


-- ============================================================================
-- §7 — kernel.get_org_connect_ref: the MACHINE reader. FULL IDENTIFIER.
--   Ruling F §3.4 (the RECONNECT path) and F §3.7(3)/(6) (minting the Account
--   Link, and the Express Dashboard login link).
--
-- ***  THIS IS THE ONE VERB IN THIS SLICE THAT DISCLOSES THE FULL PAYOUT   ***
-- ***  DESTINATION. IT IS service_role ONLY AND MUST STAY THAT WAY.       ***
--
-- WHY §6 CANNOT SERVE THIS, AND WHY THE SPLIT IS THE POINT. §6 deliberately
-- returns connect_account_last4 and never the id, because §6 is granted to
-- `authenticated` and is therefore reachable from a browser session in one
-- PostgREST call. But Stripe's account_links and login_links endpoints BOTH
-- require `account=acct_…`: a connected account cannot be resolved by metadata
-- (the Search API does not cover accounts) and the create-call idempotency key
-- expires after 24h, so there is no way to recover the id from Stripe once the
-- minting call has aged out. Without this verb, an ALREADY-BOUND organization
-- can have its status reported from the §1 mirror but CANNOT be sent to Stripe
-- at all — F §3.4's RECONNECT is unservable, and the onboarding edge is
-- reduced to refusing with 409 reconnect_unavailable.
--
-- THE TRUST BOUNDARY IS WHAT MAKES THIS A SECOND VERB RATHER THAN A WIDENED
-- ONE. The edge function runs inside the boundary; a browser session does not.
-- One verb cannot serve both without handing the id to the weaker caller.
-- STATE-FOR-HUMANS RETURNS last4 (§6); REF-FOR-MACHINES RETURNS THE IDENTIFIER
-- (here). THE TWO MUST NEVER BE MERGED, and §6 must never be "simplified" by
-- having it call this one.
--
-- NO ORG-ROLE CHECK HERE, AND ADDING ONE WOULD BREAK EVERY CALLER. Do not
-- "harden" this by adding has_org_role: that predicate tests auth.uid()
-- (077:453-466), which is NULL on a machine session, so the check could only
-- ever REFUSE — it would not tighten this verb, it would disable it. THE
-- AUTHORITY GATE FOR THIS VERB LIVES IN THE EDGE FUNCTION THAT CALLS IT, which
-- authenticates the human, checks the org role, and only then asks for the id.
-- That is the same division 085's state-sync pair already uses: the machine
-- verb carries no principal, and the principal is proven upstream. The verb's
-- protection is its GRANT, not a predicate — which is why the revoke below is
-- the load-bearing line of this section.
--
-- Returns NULL for an unbound organization rather than raising — the same
-- treatment §6 gives the normal pre-onboarding case, and the answer the edge
-- needs to decide "mint a new account" vs "reconnect the bound one". A
-- non-existent org likewise returns NULL rather than not_found: to a machine
-- caller "no id for this org" and "no such org" are the same instruction.
-- ============================================================================
create or replace function kernel.get_org_connect_ref(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select o.stripe_connect_account_ref
    from kernel.organization o
   where o.org_id = p_org_id;
$$;

-- 076 grant discipline. The `revoke ... from public` is LOAD-BEARING, not
-- ceremonial: CREATE FUNCTION grants EXECUTE to PUBLIC by default and
-- `authenticated` inherits PUBLIC, so without this line every signed-in user
-- could read every organization's payout destination in one PostgREST call.
-- service_role ONLY. This slice contains NO grant loop and NO blanket
-- `grant execute on all functions` — every grant in this file is an explicit
-- single-function statement, so nothing can catch this verb by accident.
revoke all on function kernel.get_org_connect_ref(uuid)
  from public, anon, authenticated;
grant execute on function kernel.get_org_connect_ref(uuid) to service_role;


-- ============================================================================
-- §8 — kernel.issue_ticket_atoms: RESOLVE the signing key, never accept it.
--   Signing review threat T1 · ruling B (activation boundary) · the binding
--   half of §3's G2b gate.
--
-- WHY THIS IS IN THE CONNECT SLICE: it is not connect work. It is here because
-- §3's G2b gate is UNENFORCEABLE WITHOUT IT, and shipping the gate without this
-- would be shipping a control that reads as binding and is not.
--
-- THE DEFECT. The mint took the key from the CALLER: `v_key := (p_ctx->>
-- 'signing_key_id')::uuid` (083:479), then validated it only for scope
-- COHERENCE (083:512-529) — active, in-window, and governing this session. That
-- predicate's `global` arm is UNCONDITIONAL, so a `global` key satisfies it even
-- when a `per_event` key exists for the event. Coherence is not resolution: it
-- asks "may this key govern here?", never "is this the key that governs here?".
-- Consequences, both real:
--   · T1 (a key silently outranking the intended one) is NOT superuser-only. Any
--     service_role caller could pin a global key over a per_event key and mint
--     atoms under it.
--   · MY OWN G2b GATE WAS ADVISORY. I copied finalize's resolution character for
--     character so a precedence change would surface as a visible mismatch — but
--     a mint that accepts whatever it is handed can disagree with the gate with
--     NO MISMATCH TO SEE: the gate resolves the per_event key, the caller pins
--     the global one, and both "succeed".
--
-- THE FIX, AND WHICH OPTION I TOOK. Two were available: ignore the supplied
-- value silently, or resolve internally and REFUSE a disagreement. I took the
-- REFUSAL. Silently ignoring would make a caller that believes it is choosing a
-- key be quietly overruled — the same class of invisible divergence as the bug,
-- just in the other direction — and it would erase the evidence that anyone
-- ever tried. The refusal converts an override into a loud, greppable error and
-- leaves every correct caller untouched: venue.finalize_primary_order supplies
-- the key it resolved at 085:1948-1960 with this exact rule (085:2050), so its
-- supplied value EQUALS the resolved one and it never trips the refusal.
--
-- NOTE ON THE SIGNATURE: unlike §4/§5 there is no parameter to defend here.
-- `signing_key_id` is a KEY INSIDE p_ctx jsonb, not an argument, so the frozen
-- signature (p_ctx jsonb, p_command_key text) is untouched and CREATE OR REPLACE
-- imposes no constraint at all. The value stays readable purely so the refusal
-- can compare against it.
--
-- THE RESOLUTION IS THE SAME QUERY IN ALL THREE PLACES BY CONSTRUCTION:
-- finalize (085:1948-1960), §3's G2b gate, and here. Same predicate, same
-- most-specific-first ordering (per_event → per_venue → global). It keeps 083's
-- original JOIN through event_session/event rather than finalize's two-step
-- derivation, for one reason: with a nonexistent session the join yields no row
-- and this raises `no_active_signing_key` BEFORE the rank-1 session lock,
-- exactly as the old coherence check did. On every reachable input the three
-- agree; the join form only preserves 083's pre-lock refusal ordering.
--
-- I CHECKED WHETHER THEY ALREADY DIFFERED, AS ASKED. They did, and this is the
-- finding: finalize RESOLVES (order by scope, limit 1) while the mint only
-- CHECKED COHERENCE (exists, unordered). Those are different operations, not
-- different spellings of one — which is precisely how the two could disagree.
-- After this replacement they are the same operation in all three sites.
--
-- EVERYTHING ELSE IS BYTE-FOR-BYTE: the ctx unpack, every refusal code, the
-- feature-flag gate, the idempotency anchor, the rank-1 session lock, the batch
-- lock and coherence check, the serial draw, the atom/ownership-log loop, the
-- sold conversion, the movement row, the door-manifest hook, the return shape,
-- and the unique_violation handler that returns the original atom set. NO
-- signing key is provisioned or inserted, and the parked signing RPCs stay
-- parked — a mint that could create its own key would defeat the ceremony this
-- boundary exists to wait for, exactly as §3's comment says of the gate.
-- ============================================================================
create or replace function kernel.issue_ticket_atoms(p_ctx jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor    uuid;
  v_session  uuid;
  v_org      uuid;
  v_tt       uuid;
  v_batch    uuid;
  v_owner    uuid;
  v_qty      integer;
  v_cause    text;
  v_cause_ref uuid;
  v_key      uuid;
  v_key_req  uuid;   -- T1: what the CALLER asked for. Compared, never trusted.
  v_flag     boolean;
  v_serial   integer;
  v_atom     uuid;
  v_atoms    uuid[] := '{}';
  v_ex       uuid[];
  v_b_session uuid;
  v_b_tt     uuid;
  i          integer;
begin
  v_actor := coalesce(auth.uid(), '00000000-0000-0000-0000-0000000000f1');  -- SN-SYSTEM for import/sweep
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  v_session   := (p_ctx->>'session_id')::uuid;
  v_org       := (p_ctx->>'org_id')::uuid;
  v_tt        := (p_ctx->>'ticket_type_id')::uuid;
  v_batch     := (p_ctx->>'batch_id')::uuid;
  v_owner     := (p_ctx->>'owner_id')::uuid;
  v_qty       := (p_ctx->>'quantity')::integer;
  v_cause     := (p_ctx->>'cause');
  v_cause_ref := (p_ctx->>'cause_ref')::uuid;
  -- T1: read as a REQUEST, not as the answer. Resolution happens below.
  v_key_req   := (p_ctx->>'signing_key_id')::uuid;

  if v_cause not in ('issue','comp','door_sale','import') then
    raise exception 'precondition_failed: bad_cause %', v_cause;
  end if;
  if v_qty is null or v_qty <= 0 then
    raise exception 'precondition_failed: bad_quantity';
  end if;
  if v_owner is null or v_batch is null or v_session is null
     or v_tt is null or v_cause_ref is null then
    -- cause_ref is the idempotency anchor and tt is the coherence key: a NULL in
    -- either would silently defeat the replay guard / batch check downstream (E-46).
    raise exception 'precondition_failed: incomplete context';
  end if;

  -- NATIVE ISSUANCE GATE — the mint is inert while the flag is false (dark).
  select (c.value #>> '{}')::boolean into v_flag
    from catalog.platform_config c
   where c.key = 'feature.native_issuance_enabled'
   order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled';
  end if;

  -- IDEMPOTENCY: a replay of a succeeded mint returns the original atoms. The mint's
  -- ownership-log entry is ALWAYS cause='issue' (the ownership_log_from_identity_check
  -- requires cause='issue' for the from-NULL sequence-1 row); the business cause lives
  -- in the movement + the state_transition jsonb.
  select array_agg(l.ticket_atom_id order by l.ticket_atom_id) into v_ex
    from kernel.ticket_ownership_log l
   where l.cause = 'issue' and l.cause_ref = v_cause_ref;
  if v_ex is not null and array_length(v_ex, 1) > 0 then
    return jsonb_build_object('status','idempotency_replay','atom_ids', to_jsonb(v_ex));
  end if;

  -- ACTIVATION BOUNDARY (§7.1): an ACTIVE signing_key must RESOLVE for the scope.
  -- Fail closed if none resolves — NEVER auto-create one. Most-specific-first:
  -- per_event outranks per_venue outranks global (085:1948-1960), so the key the
  -- door will expect is the key the atom is minted under.
  select k.key_id into v_key
    from kernel.signing_key k
    join catalog.event_session s on s.session_id = v_session
    join catalog.event e on e.event_id = s.event_id
   where k.status = 'active'
     and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
     -- scope coherence (E-46): the key must GOVERN this session's scope — an
     -- active-but-wrong-scope key would mint atoms the door cannot verify.
     and (   (k.scope = 'per_event' and k.event_id = s.event_id)
          or (k.scope = 'per_venue' and k.venue_id = e.venue_id)
          or (k.scope = 'global'))
   order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
   limit 1;
  if v_key is null then
    raise exception 'precondition_failed: no_active_signing_key — an active signing key must resolve for the event scope before any atom is minted';
  end if;
  -- T1: a caller MAY state which key it expects, and a correct caller does
  -- (085:2050 passes the key finalize resolved with this same rule). What it may
  -- not do is CHOOSE one. A disagreement is refused loudly rather than silently
  -- honoured (the old bug) or silently discarded (the other wrong fix).
  if v_key_req is not null and v_key_req <> v_key then
    raise exception 'precondition_failed: signing_key_override_refused — caller supplied % but % resolves for this scope; the mint resolves its own key', v_key_req, v_key;
  end if;

  -- rank-1 Event/Session lock (SPEC_FOUNDATION §5 order; DOOR §818; E-46): the
  -- serial_no counter below is SESSION-scoped while the batch lock is batch-scoped —
  -- without this, same-session/different-batch mints race to the same serial and the
  -- loser aborts on tickets_session_serial_uq. Also mutually excludes
  -- catalog.update_event_session's atoms-issued schedule guard.
  perform 1 from catalog.event_session s where s.session_id = v_session for update;
  if not found then
    raise exception 'not_found: session %', v_session using errcode = 'P0002';
  end if;

  -- lock the batch (C27 choke-point) and verify ctx coherence (E-46): the sold
  -- counter and the atoms must move on the SAME session/ticket_type.
  select b.event_session_id, b.ticket_type_id into v_b_session, v_b_tt
    from venue.inventory_batch b where b.batch_id = v_batch for update;
  if not found then
    raise exception 'not_found: batch %', v_batch using errcode = 'P0002';
  end if;
  if v_b_session <> v_session or v_b_tt <> v_tt then
    raise exception 'precondition_failed: batch_mismatch — batch % does not belong to the ctx session/ticket_type', v_batch;
  end if;

  select coalesce(max(t.serial_no), 0) into v_serial
    from kernel.tickets t where t.event_session_id = v_session;

  for i in 1..v_qty loop
    insert into kernel.tickets (event_session_id, org_id, ticket_type_id, serial_no,
                                current_owner_id, state, credential_version, signing_key_id)
    values (v_session, v_org, v_tt, v_serial + i, v_owner, 'active', 0, v_key)
    returning ticket_atom_id into v_atom;
    v_atoms := v_atoms || v_atom;

    insert into kernel.ticket_ownership_log (ticket_atom_id, sequence, from_identity, to_identity,
                                             cause, cause_ref, actor_identity, command_idempotency_key,
                                             credential_version_after, state_transition)
    values (v_atom, 1, null, v_owner, 'issue', v_cause_ref, v_actor, p_command_key || ':' || v_atom::text,
            0, jsonb_build_object('from', null, 'to', 'active', 'mint_cause', v_cause));
  end loop;

  -- convert to sold. The C27 CHECK (held+sold<=capacity) is the oversell backstop;
  -- 085/finalize releases the matching hold (held -= N) — forward obligation E-40.
  update venue.inventory_batch set sold = sold + v_qty, updated_at = now()
   where batch_id = v_batch;

  insert into venue.inventory_movement (batch_id, movement_kind, delta_held, delta_sold,
                                        cause, cause_ref, actor_identity)
  values (v_batch, 'issue', 0, v_qty, v_cause, v_cause_ref, v_actor);

  -- where an open door episode exists, feed the manifest delta (no-op stub until 086).
  perform venue.append_door_manifest_delta(v_session, v_atoms, 'add', v_cause_ref);

  return jsonb_build_object('status','ok','atom_ids', to_jsonb(v_atoms));
exception when unique_violation then
  -- concurrent identical retry (E-46): the loser's partial work rolled back to the
  -- block savepoint; under a fresh snapshot the winner's committed rows are visible.
  -- Honor the replay contract (the 081 reserve idiom) — any unique_violation NOT
  -- explained by the idempotency anchor re-raises raw.
  select array_agg(l.ticket_atom_id order by l.ticket_atom_id) into v_ex
    from kernel.ticket_ownership_log l
   where l.cause = 'issue' and l.cause_ref = v_cause_ref;
  if v_ex is not null and array_length(v_ex, 1) > 0 then
    return jsonb_build_object('status','idempotency_replay','atom_ids', to_jsonb(v_ex));
  end if;
  raise;
end;
$$;
-- No grant statement: CREATE OR REPLACE preserves the frozen 083 ACL for this
-- function, and this slice must not widen or narrow it.


-- ============================================================================
-- §9 — kernel.authorize_org_payout_dashboard: THE BANK-ACCOUNT DOOR.
--   Rulings A7/A9 extended to the surface they did not cover · G §2 (G-2),
--   §5.1, §6.1/§6.2 · finding H6/F-3.
--
-- THE DEFECT THIS CLOSES, STATED PLAINLY. Everything §2b/§4/§5 build protects
-- WHICH STRIPE ACCOUNT is the payee. NOTHING protected WHAT IS INSIDE IT. The
-- onboarding edge issues an Express Dashboard LOGIN LINK for a bound, verified
-- account (connect-onboarding/index.ts:1470), and from that dashboard the
-- holder changes the EXTERNAL BANK ACCOUNT the money actually lands in. That
-- link rode the endpoint gate — `['org_owner','org_finance']`
-- (connect-onboarding/index.ts:316) — with:
--   · NO org_owner narrowing. org_finance is precisely the role SoD-1 excludes
--     from naming the payee (§5 above, 085:1618-1620), and it could reach the
--     one surface that re-points the money for real.
--   · NO aal2 step-up. Both binders demand one; the surface that supersedes
--     them demanded none.
--   · NO kernel.admin_audit row. A destination change through this door is
--     invisible to the probation operand (087:472-476), which reads
--     `org.payout_destination.change` / `org.connect_ref.bind` and cannot see
--     a bank swap that wrote no row at all.
--   · NO security_payout_destination_changed emit. A9's "a live payout
--     destination is never silently replaced" was true of the acct_ and false
--     of the bank behind it.
--
-- WHY THIS IS A SQL VERB AND NOT AN `if` IN THE EDGE. The RT-A-3 lesson,
-- restated: a control that lives only in an edge function is ADVISORY, because
-- the verb it protects is reachable without the edge. Here the protected
-- object is Stripe's, not Postgres's, so SQL cannot make the login link
-- unreachable — but it CAN make the AUDIT ROW AND THE NOTIFICATION structural
-- rather than optional, and it can put the authority test in the same place,
-- in the same shape, as the two binders it is being brought level with. The
-- edge calls this FIRST and mints the link only on success; a future caller
-- that forgets is a caller that produces no authorization row, which is a
-- detectable absence rather than a silent bypass.
--
-- IT WRITES NO ORGANIZATION COLUMN, DELIBERATELY. This verb does not change the
-- destination — it records that a human was handed the ability to. So there is
-- no `for update` on kernel.organization (a plain read; taking the binders'
-- lock here would serialise dashboard opens against real destination changes
-- for no benefit), no cool-down write, and no `payout_destination_set_by`
-- stamp. THE SETTER STAMP IS NOT TOUCHED ON PURPOSE: SoD-1 must keep naming
-- whoever bound the acct_, and overwriting it here would let an owner clear
-- their own payout-request exclusion (087:428-431) by opening a dashboard.
--
-- WHY org_owner ONLY, WHEN F §3.4 GIVES VIEW+RECONNECT TO org_finance. Because
-- this is not view and it is not reconnect. Ruling F's carve-out is about
-- resuming an INCOMPLETE onboarding, where no money has a destination yet;
-- this verb only fires for an account that is bound AND transfers-active, i.e.
-- exactly when there IS money to redirect. org_finance keeps the status read
-- (§6) and the onboarding-continuation link; it loses the one surface that
-- edits a live payee. Same set as §4/§5, so all three destination authorities
-- now agree.
--
-- AUDIT ACTION NAME. `org.payout_destination.dashboard_grant` — deliberately
-- NOT `org.payout_destination.change`, which 087:472-476 reads as the
-- probation operand. A dashboard grant is not itself a change and must not
-- start the probation clock; conflating them would hold a payout every time an
-- owner looked at their Stripe dashboard. Whether a bank swap that follows
-- SHOULD arm probation is a real question and it is left open: the answer
-- needs Stripe's `account.external_account.updated` webhook, which this repo
-- does not handle. Recorded as R30-9.
-- ============================================================================
create or replace function kernel.authorize_org_payout_dashboard(
  p_org_id uuid, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org       kernel.organization%rowtype;
  v_aal       text;
  v_audit_id  uuid;
  v_recipient uuid;
begin
  -- Caller-JWT bound, exactly as §4: this verb stamps a human into
  -- admin_audit, and admin_audit.actor_identity is NOT NULL. A service_role
  -- connection has no auth.uid() and must raise rather than record a sentinel
  -- — a machine never opens a dashboard.
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: caller JWT required — the payout dashboard is authorized for a human, never a machine session'
      using errcode = '42501';
  end if;
  if p_org_id is null then
    raise exception 'invalid_input: an org scope is required';
  end if;
  -- SoD-1, the same narrowing §4 applied to the bind.
  if not kernel.has_org_role(p_org_id, array['org_owner']) then
    raise exception 'insufficient_privilege: org_owner required (SoD-1; org_finance may view payment status but may not open the payout dashboard)'
      using errcode = '42501';
  end if;
  -- AUTHZ-M4, the 085:1624-1631 shape: an absent claim is never a pass.
  v_aal := coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to open the payout dashboard';
  end if;

  select * into v_org from kernel.organization where org_id = p_org_id;
  if not found then
    raise exception 'not_found: organization %', p_org_id using errcode = 'P0002';
  end if;
  -- G-6, the same set §4/§5 require: a suspended org's payee is frozen, and
  -- that must include the bank account behind it.
  if v_org.status not in ('approved','active') then
    raise exception 'precondition_failed: org_not_bindable — a % org may not open its payout dashboard', v_org.status;
  end if;
  -- Nothing to authorize for an org with no destination: the edge sends an
  -- unbound org down the account_links arm, never here. Refusing is what keeps
  -- this verb from becoming a generic, contentless audit writer.
  if v_org.stripe_connect_account_ref is null then
    raise exception 'precondition_failed: no_payout_destination — this organization has no bound payout destination to administer';
  end if;

  -- THE ROW THAT MAKES THE GRANT VISIBLE. Last 4 only — G §6.1 bars Connect
  -- ids from leaving the trust boundary, and admin_audit is read by support.
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'org.payout_destination.dashboard_grant', 'organization', p_org_id,
          'express_dashboard_login', null,
          jsonb_build_object('destination_last4', right(v_org.stripe_connect_account_ref, 4),
                             'command_key', p_command_key))
  returning id into v_audit_id;

  -- A9 / G-2 — the human tripwire, BEST-EFFORT, verbatim §4/§5 pattern:
  -- keyed on the audit row id (PFA-2 per-occurrence collision rule), wrapped so
  -- a failed emit warns and the authorization still commits. Recipients are
  -- every org_owner AND org_finance including any who did not act — an owner
  -- opening the dashboard is exactly the event the other officers should see,
  -- because what happens next is invisible to us.
  begin
    for v_recipient in
      select m.identity_id from kernel.org_member m
       where m.org_id = p_org_id and m.role in ('org_owner','org_finance')
    loop
      perform notify.emit_event(
        'security_payout_destination_changed', 'identity', v_recipient,
        'security_payout_destination:' || v_audit_id::text || ':' || v_recipient::text,
        jsonb_build_object('org_id', p_org_id,
                           'destination_last4', right(v_org.stripe_connect_account_ref, 4),
                           'origin', 'express_dashboard_login',
                           'actor_identity', v_uid));
    end loop;
  exception when others then
    raise warning 'authorize_org_payout_dashboard: best-effort security notice emit failed: %', sqlerrm;
  end;

  return jsonb_build_object('status','ok','org_id', p_org_id,
                            'authorization_id', v_audit_id);
end;
$$;

-- 076 grant discipline: revoke the default PUBLIC EXECUTE, then ONE targeted
-- grant. `authenticated` only — this is a caller-authorized verb whose whole
-- content is a test against auth.uid(), so a service_role grant would be inert
-- (has_org_role tests auth.uid(), NULL on a machine session) AND misleading.
-- anon never.
revoke all on function kernel.authorize_org_payout_dashboard(uuid, text)
  from public, anon, authenticated;
grant execute on function kernel.authorize_org_payout_dashboard(uuid, text) to authenticated;


-- ============================================================================
-- §10 — THE CROSS-PLANE REFUSAL, MADE BIDIRECTIONAL.
--   Ruling A7/G-1 · G §2 threat G-12 · finding H6/F-4.
--
-- THE DEFECT. §2b, §4 and §5 all refuse an acct_ that lives on the INDIVIDUAL
-- seller plane. Nothing refused the reverse: an acct_ already bound to an
-- ORGANIZATION could be written onto public.profiles.stripe_connect_id, and
-- the red-team reproduction is one UPDATE. Two consequences, and the second is
-- worse than the first:
--   (a) MIS-ROUTED SELLER MONEY. supabase/functions/_shared/payouts.ts is the
--       individual rail's transfer path and it pays `profiles.stripe_connect_id`
--       verbatim. An org's Connect account sitting in that column receives
--       marketplace seller proceeds.
--   (b) THE ORG IS BRICKED, PERMANENTLY. §2b/§4/§5's refusal is `exists (select
--       1 from public.profiles where stripe_connect_id = <ref>)`. Once the org's
--       OWN account appears there, that clause matches the org's own identifier
--       forever: re-staging and re-pointing both raise
--       account_not_platform_minted_for_org, and §2.3's already-narrow re-point
--       path closes completely. A one-row write makes a venue's payout
--       destination unchangeable.
--
-- WHY A TRIGGER AND NOT A CHECK IN AN EDGE. There is NO verb on this side to
-- put a check in. profiles.stripe_connect_id is written by a direct table
-- UPDATE from a service-role client with no RLS in the way
-- (create-connect-account/index.ts:217 and :258) — that is ruling G's own G-12
-- finding, and it means an edge-level check protects only the edge. The
-- inbound edge path cannot actually inject an org id anyway (it writes
-- `created.id`, minted by Stripe seconds earlier), so an edge check would guard
-- the one caller that was never the threat and miss the two that are: a leaked
-- SUPABASE_SERVICE_ROLE_KEY, and any future writer. A BEFORE trigger holds
-- against every writer including service_role, which is exactly the asymmetry
-- G-12 asks to close.
--
-- GUARDED SO IT COSTS NOTHING. The body runs only when the column is non-null
-- AND actually changed; the lookup then rides organization_connect_ref_key
-- (077:124-126), a partial unique index on the very column being probed. An
-- ordinary profile update touches neither.
--
-- SECURITY DEFINER IS REQUIRED, NOT DECORATIVE: a trigger function executes as
-- the invoking role, and NEITHER `authenticated` NOR `service_role` holds any
-- grant on kernel.organization (077:133-138; 085:2092-2095 gives service_role
-- kernel USAGE only). An invoker-rights trigger here would raise `permission
-- denied for table organization` on every seller onboarding.
--
-- THE ARCHIVE IS GUARDED TOO, and not only for symmetry: §2b/§4/§5 consult
-- public.stripe_connect_archive with the identical `exists` clause, so an org
-- id landing there bricks the org exactly as (b) above. Covering profiles alone
-- would leave the same trap one table over.
-- ============================================================================
create or replace function kernel.guard_connect_id_not_org_bound()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ref text := new.stripe_connect_id;
begin
  -- Fire only on a real, changed value. TG_OP is checked rather than assumed so
  -- the same function can serve both triggers below.
  if v_ref is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.stripe_connect_id is not distinct from v_ref then
    return new;
  end if;

  if exists (select 1 from kernel.organization o
              where o.stripe_connect_account_ref = v_ref) then
    raise exception 'precondition_failed: account_bound_to_organization — % is an organization payout destination and may not be recorded on the individual seller plane', v_ref
      using errcode = 'P0001';
  end if;
  -- A STAGED-BUT-UNBOUND ref is refused as well. It is the account the platform
  -- minted FOR an org and is one org_owner bind away from being live; letting it
  -- land here would poison the provenance check before the bind could ever run,
  -- turning a pending onboarding into a permanent no_pending/​not_minted loop.
  if exists (select 1 from kernel.organization o
              where o.connect_pending_ref = v_ref) then
    raise exception 'precondition_failed: account_bound_to_organization — % has been minted for an organization and may not be recorded on the individual seller plane', v_ref
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function kernel.guard_connect_id_not_org_bound()
  from public, anon, authenticated, service_role;
-- NO grant, deliberately: PostgreSQL does not check EXECUTE on a trigger
-- function, and nothing may ever call this directly. Same treatment as
-- kernel.settlement_primary_lines (no grant at all).

drop trigger if exists tg_profiles_connect_id_not_org_bound on public.profiles;
create trigger tg_profiles_connect_id_not_org_bound
  before insert or update of stripe_connect_id on public.profiles
  for each row execute function kernel.guard_connect_id_not_org_bound();

drop trigger if exists tg_connect_archive_not_org_bound on public.stripe_connect_archive;
create trigger tg_connect_archive_not_org_bound
  before insert or update of stripe_connect_id on public.stripe_connect_archive
  for each row execute function kernel.guard_connect_id_not_org_bound();

-- EXISTING ROWS ARE NOT VALIDATED, AND THE MIGRATION MUST NOT FAIL ON THEM.
-- A BEFORE trigger only sees new writes. Refusing to apply 093 because a
-- pre-existing row already carries an org id would make a data problem into an
-- outage; reporting it loudly is the right trade. In practice this is expected
-- to be zero — no org has ever been bound in production — and a non-zero count
-- is a genuine incident to chase, not a migration blocker.
do $$
declare v_n integer;
begin
  select count(*) into v_n
    from public.profiles pf
    join kernel.organization o
      on o.stripe_connect_account_ref = pf.stripe_connect_id
     or o.connect_pending_ref         = pf.stripe_connect_id;
  if v_n > 0 then
    raise warning 'CROSS-PLANE COLLISION: % profile row(s) already carry an organization Connect account. The §10 trigger blocks NEW writes only; these rows must be reconciled by hand (H6/F-4).', v_n;
  end if;
end $$;


-- ============================================================================
-- END PART 30. Residuals this part creates, recorded so they are not mistaken
-- for oversights (all outside the authored scope of this fragment):
--   R30-1  OPEN — CARRIED AS A NAMED FOLLOW-UP, NOT CLOSED HERE.
--          notify.drain_outbox (092:730) has NO arm for
--          security_payout_destination_changed — its `else` branch counts the
--          envelope `unmapped` and marks it done. §4/§5 close G-2's PRODUCER
--          half; the routing half needs a drainer arm before an owner is
--          actually told, so TODAY A DESTINATION CHANGE STILL REACHES NOBODY.
--          092 is immutable, so the fix is a create-or-replace of
--          notify.drain_outbox in a later part or a follow-up migration.
--          Do not read the emit calls in §4/§5 as evidence that G-2 is closed.
--   R30-2  Nothing calls kernel.sync_org_connect_state yet. Until the
--          account.updated org arm exists (F §3.6(1)), connect_transfers_active
--          is false for every organization and §3 refuses every primary
--          checkout — correct, fail-closed, and total. The webhook arm is a
--          PREREQUISITE OF ACTIVATION, not a follow-up.
--   R30-3  The G-11 out-of-band write trigger (a superuser UPDATE of
--          stripe_connect_account_ref writes no audit row) is not built here.
--   R30-4  The buyer fee is DERIVED, never STORED: no column on venue."order"
--          carries it (A5 forbids folding it into total_minor, and adding a
--          fee column was not in scope). Consequence: the two
--          `idempotency_replay` returns carry no fee fields, because this
--          function cannot reproduce the quote the ORIGINAL call made if
--          fee.buyer_service_bps changed in between. The edge must treat its
--          own PaymentIntent as the record of what it quoted. If a replay ever
--          needs to re-quote, the durable fix is a fee column on venue."order"
--          written at checkout — a schema decision, not a body change.
--   R30-6  RT-A-3's fix requires the onboarding edge to call §2b
--          (kernel.stage_org_connect_ref) between minting the Stripe account
--          and calling §4/§5. AN EDGE THAT SKIPS IT CANNOT BIND AT ALL — it
--          will get `no_pending_connect_ref`. That is the intended failure
--          (fail closed, loudly), but it is a REQUIRED CHANGE to the edge
--          contract, not an optional one, and it must reach the agent building
--          supabase/functions/connect-onboarding/index.ts.
--   R30-7  connect_pending_ref is consumed at the bind and never expires on
--          its own. A staged ref for an org whose onboarding was abandoned sits
--          until the next stage call overwrites it. Harmless — it can only ever
--          authorize binding the account the platform itself minted for that
--          org — but a TTL sweep would be the tidier long-term shape, and it is
--          not in 093.
--   R30-8  G2b refuses EVERY primary checkout until the ruling-B bootstrap
--          signing-key row exists (093 scope item 2, an owner KMS ceremony).
--          That is the intended resting state, not a defect — but it means the
--          ceremony is now a hard blocker on the first sale, visible as
--          `no_active_signing_key` rather than as a post-payment mint failure.
--   R30-9  §9 records that a human was GRANTED the ability to change the bank
--          account behind the bound acct_; it cannot observe whether they then
--          did. Stripe reports that as `account.external_account.updated` /
--          `account.updated`'s external_accounts payload, and this repo's
--          webhook handles neither — supabase/functions/stripe-webhook only
--          reads capabilities on the org arm. CONSEQUENCE: a bank swap still
--          does not arm destination probation (087:465-495), because the
--          probation operand is an admin_audit action and no row is written
--          when the swap actually happens. §9 converts a silent change into a
--          visible GRANT, which is strictly better and is not the same thing as
--          closing it. Closing it needs the external-account webhook arm and a
--          decision on whether a bank swap re-arms probation.
--   R30-10 §9's emit inherits R30-1 exactly: notify.drain_outbox still has no
--          arm for security_payout_destination_changed, so the envelope is
--          counted `unmapped` and nobody is told. The admin_audit row is the
--          only channel that works today. Do not read §9 as closing G-2.
--   R30-5  Nothing in the database stops selling being activated while
--          fee.buyer_service_bps is null; the §3 refusal is per-checkout, so
--          the symptom is "every sale fails closed", not "no sale is
--          mispriced". Part 40 already names setting the rate as a launch
--          precondition on feature.native_issuance_enabled. §3 now makes that
--          precondition self-announcing (`service_fee_unset`) instead of
--          silent, but it does not enforce it at the flag.
-- ============================================================================


-- ###########################################################################
-- ## SLICE: 40_config_privacy_freeze.sql
-- ###########################################################################

-- ============================================================================
-- 093 PART 40 — CONFIG · PRIVACY · OPERATORSHIP FREEZE
--
-- A FRAGMENT of migration 093, not a migration. It carries NO `begin;`/`commit;`
-- — the 093 assembler owns the transaction, so this file must remain safe to
-- concatenate in place. It creates NO table, NO enum member, NO column, and no
-- object outside the four items below.
--
-- RULINGS IMPLEMENTED (docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md,
-- ratified by the owner 2026-09-02; the owner's A-numbering is canonical):
--
--   ITEM 1  ruling D2 (ticket expiry) + inventory readiness + ruling A5
--           (buyer-funded economics) + the settlement refund-window gate —
--           FIVE catalog.platform_config key rows. 093 scope items 3 and 10.
--           The fifth is routed here from the money slice so only one slice
--           writes it; its READER lives in 10_money_settlement.sql.
--   ITEM 2  ruling B (credential signing / dual control) — the signing bootstrap
--           trust row. 093 scope item 2. **BLOCKED — see the banner; this file
--           inserts NOTHING and invents no key material.**
--   ITEM 3  ruling C (venue operatorship transfer) — body-only CREATE OR REPLACE
--           of catalog.update_venue. 093 scope item 15.
--   ITEM 4  ruling F (attendee privacy) — column-scope venue."order" to omit
--           buyer identity. 093 scope item 4.
--
-- WHAT THIS FRAGMENT DOES NOT DO, deliberately:
--   * it activates nothing. Every rail stays dark; no flag is flipped.
--   * it un-parks NO signing-key RPC. kernel.provision_signing_key and
--     kernel.rotate_signing_key stay fail-closed (083:375-393) — both are
--     reachable by every signed-in user's role once granted, and ruling B
--     forbids the un-park explicitly.
--   * it revokes no EXECUTE grant. Ruling C's freeze is surgical to one patch
--     key precisely so benign venue profile edits keep working.
--
-- ACL NOTE (applies to ITEM 3): CREATE OR REPLACE FUNCTION preserves the
-- existing function ACL. catalog.update_venue keeps the grant 078 issued it;
-- this fragment must not re-grant it, and must not revoke it.
-- ============================================================================


-- ============================================================================
-- ITEM 1 — CONFIG KEY ROWS  (rulings D2 and A5; 093 scope items 3 and 10)
--
-- WHY A MIGRATION AND NOT set_platform_config: the setter resolves the key's
-- latest version under its own lock and then
--     if v_cur_ver is null then
--       raise exception 'precondition_failed: unknown_key %', p_key;
-- at 078:1102-1104, under the standing rule at 078:1093-1094 — "THIS FUNCTION
-- CREATES NO NEW KEY — a key that no code reads is a config row that lies".
-- A key that does not exist therefore cannot be created by configuration at
-- all. Only a migration can create one. There is no exception.
--
-- SHAPE: exactly 078:1520 — (key, version, value, visibility), version 1
-- (platform_config_version_check requires >= 1, 078:226), terminated with
-- `on conflict (key, version) do nothing` (the 078 seed idiom, 078:1580).
-- The table is append-only PER VERSION: tg_platform_config_append_only
-- (078:241-244) makes UPDATE and DELETE raise, even as superuser. A later
-- change is a NEW version row, never an edit of one of these.
--
-- VISIBILITY: all five are 'restricted'. None is a client-honoured span (the
-- 'public' set is the three feature flags, the two kill switches and the three
-- credential client spans, 078:1522-1530). These five are operational
-- thresholds, platform economics and a money-safety gate — PFA-8 posture.
--
-- DUAL CONTROL: FOUR of these five are not dual-controlled; the fifth now is.
-- The setter's prefix test is
--     v_dual := p_key like 'refund.%' or p_key like 'payout.%' or p_key like
--               'authn.%' or p_key like 'comp.%' or p_key like 'wallet.%' or
--               p_key like 'credential.%' or p_key like 'door.session\_%';
-- at 078:1145-1147. `ticket.%`, `inventory.%` and `fee.%` match none of them, so
-- each later set_platform_config call for those is a SINGLE platform_admin write
-- with no approval round — which is the property that makes seeding them absent
-- safe, because the owner can fill them in without a migration.
--
-- THE MONEY-SAFETY KEY IS THE EXCEPTION AND IT IS DELIBERATELY IN A DIFFERENT
-- NAMESPACE. It was 'settlement.refund_window_interval', which matched no
-- dual-control prefix — so the single most dangerous value in the train could be
-- set by one person with no countersignature. It is now
-- 'payout.settlement_maturity_interval' (G2), which matches 'payout.%' AND has no
-- polarity entry, so every set of it parks for a second platform_admin. See that
-- row's block.
--
-- TYPE WITNESS: 078:1111-1114 — "a key seeded absent-by-design (JSON null) has
-- no witness yet and accepts the first typed value, after which the witness
-- exists". So a null seed does NOT pin the type; a seeded value does.
-- ============================================================================

insert into catalog.platform_config (key, version, value, visibility) values

  -- ---- inventory: the two reservation keys (093 scope item 3) -------------
  --
  -- BOTH ARE SEEDED ABSENT (JSON null), which is the frozen
  -- retention.backup_window_days pattern (PFA-9, 078:1512-1517): the ROW exists
  -- so the setter's registry precondition holds; the VALUE is absent so every
  -- consumer takes the restrictive reading.
  --
  -- FAIL-CLOSED CLAIM — VERIFIED IN THE CONSUMER, NOT ASSUMED.
  --
  -- inventory.per_user_active_hold_max, read by venue.reserve_primary_inventory
  -- (081:527) at 081:615-621:
  --     select (c.value #>> '{}')::integer into v_cap_max
  --       from catalog.platform_config c
  --      where c.key = 'inventory.per_user_active_hold_max'
  --      order by c.version desc limit 1;
  --   exception when others then v_cap_max := null;
  --   end;
  --   v_cap_max := coalesce(v_cap_max, 0);          -- 081:621
  -- and then 081:624-626:
  --   if v_active + 1 > v_cap_max then
  --     raise exception 'precondition_failed: hold_cap_exceeded';
  -- With the value absent the cast raises, the handler sets null, the coalesce
  -- collapses the cap to ZERO, and `0 + 1 > 0` is true for the FIRST hold of
  -- every user. Every reservation is refused, loudly. FAIL-CLOSED — confirmed.
  -- 081:608-612 states the intent verbatim: "unseeded => fail-to-ZERO (AUTHZ-M8
  -- precedent), so a missing seed refuses every reserve loudly rather than
  -- admitting unbounded holds silently."
  ('inventory.per_user_active_hold_max',      1, 'null'::jsonb,       'restricted'),
  --
  -- inventory.hold_ttl_interval, read at 081:630-639 (inside
  -- venue.reserve_primary_inventory, 081:527) and again at 081:727-734 (inside
  -- venue.create_inventory_hold, 081:672):
  --     exception when others then v_ttl := null;
  --     end;
  --     if v_ttl is null then
  --       raise exception 'precondition_failed: hold_ttl_unset';     -- 081:638
  -- An absent value raises `hold_ttl_unset` outright — there is no default and
  -- no coalesce. Both call sites are identical. FAIL-CLOSED — confirmed.
  -- 081:628-629: "unseeded => REFUSE rather than invent a business policy (a
  -- TTL is policy, not a default)."
  --
  -- A null seed is therefore SAFE for both: while unset, nothing can be held,
  -- so nothing can be checked out and nothing can be minted. The owner sets
  -- both with set_platform_config before activation. NO VALUE IS INVENTED HERE.
  ('inventory.hold_ttl_interval',             1, 'null'::jsonb,       'restricted'),

  -- ---- ticket.expiry_grace — SEEDED NULL, AND IT IS THE DANGEROUS ONE ------
  --
  -- THIS KEY IS NOT LIKE THE OTHER THREE, AND THE DIFFERENCE RUNS THE OPPOSITE
  -- WAY TO WHAT YOU WOULD EXPECT. The other three are seeded absent because
  -- their consumers fail CLOSED — while unset, nothing can be held and nothing
  -- can be quoted, so an absent value is self-announcing. This consumer fails
  -- INERT: an absent value sweeps nothing, silently, forever. The row exists so
  -- the key is settable without a migration; the VALUE is absent because the
  -- number is an owner decision that is irreversible in the wrong direction.
  -- Both halves of that sentence are load-bearing; the full argument is below.
  --
  -- The consumer is kernel.sweep_expired_ticket_atoms (079:456), cron-scheduled
  -- every two minutes (079:799-803). At 079:475-479 it reads:
  --     v_grace := (select (c.value #>> '{}')::interval
  --                   from catalog.platform_config c
  --                  where c.key = 'ticket.expiry_grace'
  --                  order by c.version desc limit 1);
  -- and at 079:480-485:
  --   exception when others then
  --     v_grace := null;
  --   end;
  --   if v_grace is null then
  --     return jsonb_build_object('swept_count', 0);
  -- ABSENT, JSON-NULL and UNPARSEABLE all collapse to the same silent no-op.
  -- Nothing is swept, ever, and nothing says so.
  --
  -- WHY THAT IS FAIL-OPEN, NOT FAIL-INERT. 079:467-474 argues the inertness is
  -- safe FOR THE ATOM, and it is. It is fail-OPEN for the IDENTITY. The
  -- deletion blocker kernel.deletion_blockers_custody (079:707-717) is
  --     where exists (select 1 from kernel.tickets t
  --                    where t.current_owner_id = p_identity
  --                      and t.state in ('issued','active'))
  -- and BP-1's only three drains are scan, void and expiry. Scan is gated by
  -- feature.native_scanning_enabled, seeded false (078:1523); void is a
  -- platform break-glass (085:739-751), not a user path. So expiry is the ONLY
  -- drain a no-show buyer has. With this key unset, a buyer who simply does not
  -- attend becomes PERMANENTLY UNDELETABLE — an erasure-law failure that needs
  -- no money at all to trigger.
  --
  -- TYPE — THE SINGLE HIGHEST-RISK DETAIL IN THIS FILE. The value MUST be a
  -- jsonb STRING holding a Postgres interval literal, because 079:475 casts
  -- (c.value #>> '{}')::interval. A jsonb NUMBER (e.g. 24) fails that cast,
  -- lands in the `exception when others` arm at 079:480, and SILENTLY RE-ARMS
  -- the exact bug this row exists to close. Precedent for the string form is
  -- every door.* interval key at 078:1535-1541.
  --
  -- THE VALUE IS A JSON NULL, AND THAT IS DELIBERATE. An earlier draft of this
  -- row carried a derived '"24 hours"'. It was WITHDRAWN. The full reason, so
  -- the next reader does not re-derive it and put it back:
  --
  --   E-18 (POST_FREEZE_AMENDMENTS.md:1506-1515) is a RATIFIED erratum holding
  --   that this key is NOT seeded, and its ground is not caution for its own
  --   sake: the sweep's only effect is to write the TERMINAL label `expired`. A
  --   grace that is too short does not degrade, it irreversibly voids live
  --   tickets — and cancel_event then EXCLUDES expired atoms from its refund
  --   cascade (088:1682/1735/1783), so the buyer loses ticket AND refund.
  --   E-18's own words: "the inert direction is the only one the corpus
  --   declares harmless."
  --
  --   Ruling D2 says BOTH "do not leave the key absent/fail-open" AND "if a
  --   numeric owner value is genuinely unavoidable and not already ratified,
  --   STOP only that config value and report it." No grace duration exists
  --   anywhere in the corpus (POST_FREEZE_AMENDMENTS.md:648-649 — "in NO
  --   authoritative seed table, NO value anywhere"). The number is therefore
  --   unavoidable AND unratified, which is precisely the STOP case.
  --
  --   A ROW WITH A NULL VALUE honours both halves. The key is no longer ABSENT,
  --   so it is settable through the single sanctioned path with no migration —
  --   which is exactly PFA-9's CHOSEN option (c), "seed the ROW with a JSON null
  --   value and record the absence", already precedented by
  --   retention.backup_window_days. Deriving a number from
  --   door.session_absolute_max_interval (078:1540) remains the recommended
  --   STARTING POINT for the owner, and that derivation is preserved in the
  --   report — but it is the owner's call, not the implementer's, because it is
  --   irreversible in the wrong direction.
  --
  -- CONSEQUENCE, STATED PLAINLY RATHER THAN BURIED: until the owner sets a
  -- value, the sweep stays inert, tickets never expire, and any buyer holding an
  -- unscanned ticket stays permanently undeletable. That is a HARD ACTIVATION
  -- BLOCKER for issuance, not a nicety.
  --
  -- IT IS CHANGEABLE WITHOUT A MIGRATION. `ticket.%` matches no dual-control
  -- prefix (078:1145-1147), so
  --     select catalog.set_platform_config('ticket.expiry_grace',
  --              '"48 hours"'::jsonb, <reason>, <command key>);
  -- is one platform_admin write that inserts version 2. The owner's decision
  -- here is reversible and cheap; it is reported separately rather than
  -- presented as settled.
  --
  -- A SECOND FAIL-OPEN PATH CONFIG CANNOT REACH, surfaced not fixed: the sweep
  -- skips sessions with ends_at is null by design (079:492-493), and
  -- catalog.create_event_session requires only starts_at (078:806). A venue
  -- that omits ends_at reproduces the permanent-undeletable bug in full with
  -- this key correctly set. Carried as a separate schema decision — NOT closed
  -- by this row and NOT silently closed elsewhere in 093.
  ('ticket.expiry_grace',                     1, 'null'::jsonb,       'restricted'),  -- VALUE IS AN OWNER STOP (D2) — activation blocker until set

  -- ---- fee.buyer_service_bps — the platform's buyer-side service fee ------
  --
  -- Ruling A5, verbatim on the constraint this row must honour:
  --     "No service-fee percentage is hardcoded in migration 093."
  --     "No percentage is invented anywhere."
  --     "Fee economics remain owner/config controlled."
  -- The VALUE IS THEREFORE NULL, DELIBERATELY. This row creates the KEY and
  -- nothing else, so that the owner can set the rate later with a single
  -- set_platform_config call and no migration. That is the entire point of
  -- creating it now.
  --
  -- WHY THE KEY MUST EXIST BEFORE ANY SALE. Ruling A5 also fixes venue
  -- entitlement at "the configured ticket face value", and settlement lines are
  -- append-only while the settlement header is write-once. Revenue recognised
  -- before this key exists cannot be restated afterwards. This is the one place
  -- in 093 where "later" is unrecoverable.
  --
  -- HARD ACTIVATION CONSTRAINT, stated as ruling A5 requires: SELLING MUST NOT
  -- BE ACTIVATED WHILE THIS VALUE IS UNSET. Nothing in the database enforces
  -- that today — this fragment adds no reader — so it is a named launch
  -- precondition on feature.native_issuance_enabled, alongside the inventory
  -- keys above and payout.destination_cooldown_hours (078:1553, also null).
  --
  -- NAMING — house style, and why not one of the existing families. The corpus
  -- calls exactly this money `buyer_fee` (public.payments, 000:982-985; and the
  -- config namespace already carries refund.buyer_fee_refundable, 078:1550), so
  -- the noun is not invented. `fee.` is a new family in the same shape as every
  -- existing one (a bare lowercase domain noun: refund / payout / door / comp /
  -- resale / retention). It is deliberately NOT filed under `payout.` or
  -- `refund.`: those prefixes are dual-controlled (078:1145-1147) and this key
  -- has no declared polarity (078:1148-1196 falls through to `else null`), so
  -- filing it there would make it PARK on every write with no restrictive fast
  -- path — a rate the owner could never actually set.
  --
  -- UNITS — basis points, integer, following catalog.resale_policy.price_cap_bps
  -- and .royalty_bps (078:258-261, range 0..10000). A rate, not an amount,
  -- because the corpus already derives the buyer fee "from the base in integer
  -- cents, half-up" (docs/phase2/_decisions/A_venue_money.md:115). A single
  -- rate key is the MINIMAL shape; a rate-plus-fixed-component shape would be
  -- inventing fee economics, which A5 forbids.
  --
  -- THIS KEY HAS NO READER IN 093, AND THAT IS CORRECT — VERIFIED, NOT ASSUMED.
  -- The obvious candidate reader would be the settlement revenue seam (093 scope
  -- item 11, kernel.settlement_primary_lines), and it deliberately is NOT one:
  -- under A5 the venue's entitlement IS face value and "no platform fee is
  -- subtracted" from it, because Snatch It's revenue is buyer-funded and is
  -- collected at checkout, not deducted at settlement. The real reader is the
  -- buyer-side pricing path — venue.create_primary_checkout and the
  -- primary-checkout edge — which is outside this migration entirely.
  --
  -- So this row knowingly takes the ONE exception to 078:1093-1094 ("a key that
  -- no code reads is a config row that lies"): the key is created AHEAD of its
  -- reader. The justification is the irreversibility above — settlement lines
  -- are append-only and the header is write-once, so a rate that does not exist
  -- when the first sale settles can never be applied retroactively. Creating it
  -- early is recoverable; creating it late is not. The pricing path must adopt
  -- this exact spelling when it is built, and must fail closed (refuse to
  -- price) rather than default to zero while the value is null.
  ('fee.buyer_service_bps',                   1, 'null'::jsonb,       'restricted'),  -- A5: value is OWNER POLICY; never hardcoded here

  -- ---- payout.settlement_maturity_interval — THE PAYOUT HOLD AFTER THE -------
  -- ---- EVENT. RENAMED FROM settlement.refund_window_interval (G2). ----------
  --
  -- Routed here so slice 40 and the money slice do not both write the row. The
  -- READER is kernel.close_settlement in
  -- docs/phase2/_impl/093_parts/10_money_settlement.sql (the G2 maturity gate at
  -- the payout mint). Spelling verified against that reader.
  --
  -- THE OLD NAME WAS A LIE AND IS NOT PRESERVED. 'refund_window' names REFUND
  -- ELIGIBILITY — how long a buyer may still ask for money back. That is real
  -- policy and it is owned by an entirely different family of keys
  -- (refund.buyer_self_service_window_hours, refund.request_ttl_hours,
  -- refund.scanned_atom_policy — 078:1544-1551). This value is not that. It is:
  -- HOW LONG AFTER THE LAST COVERED SESSION ENDS THE VENUE'S MONEY MUST SIT
  -- STILL. Three separate concepts were collapsed into one name — refund
  -- ELIGIBILITY, payout MATURITY, and refund EXECUTION (kernel.mark_refund_state
  -- / the refund-execute edge) — and only the middle one is this row.
  --
  -- THE PREFIX IS LOAD-BEARING, NOT COSMETIC. This is the sentence the OLD
  -- version of this comment had to write, and the rename is what answers it:
  -- 'settlement.%' matched NONE of the dual-control prefixes at 078:1145-1147
  -- (refund. / payout. / authn. / comp. / wallet. / credential. / door.session_),
  -- so setting the most dangerous money key in the train was ONE platform_admin
  -- write with no second pair of eyes. 'payout.%' MATCHES. And because the key
  -- carries no entry in the polarity map (078:1152-1198), it has no declared
  -- restrictive direction, so EVERY set of it parks for a second platform_admin
  -- through kernel.approval_request / 'config.set_money_key' (078:1268-1285,
  -- consumed at 085:1224/1328). The rename converts a single-writer bypass into
  -- a two-person control at zero implementation cost.
  --
  -- WHAT IT GATES. A refund that succeeds AFTER its settlement has closed is
  -- never collected: the venue is paid face value, the buyer is refunded, and the
  -- debit exists NOWHERE in the ledger, permanently. Measured by the red team
  -- over five closes: lifetime net 8400 against 19000 actually paid out.
  -- **093 CREATED this exposure** by activating the credit side — pre-093 gross
  -- was structurally zero, so there was no payout to overpay.
  --
  -- HOW IT IS CLOSED: while this key is unset, close_settlement mints the
  -- settlement payout HELD — hold_state='held',
  -- hold_reason_code='unbounded_refund_exposure' (that code is retained verbatim
  -- for this arm). The ledger still records the full truth and the obligation
  -- still exists; only the MONEY is immobilised.
  --
  -- ####################################################################
  -- ##  SETTING THIS KEY IS NO LONGER SUFFICIENT TO RELEASE A PAYOUT.
  -- ##
  -- ##  That was the defect this rename ships with the fix for. The old gate
  -- ##  was `v_held := v_refund_window is null` — the ONLY predicate was
  -- ##  "is the key set", so setting it to ANY value released every payout
  -- ##  immediately with no maturity semantics implemented anywhere. The key
  -- ##  was a hidden feature flag for logic that did not exist.
  -- ##
  -- ##  The gate is now a CONJUNCTION (G2). This value is one conjunct; the
  -- ##  others are derived from the ledger and cannot be configured away:
  -- ##  the covered set must resolve, no covered event may be cancelled, the
  -- ##  last covered session's ends_at must be known and must have elapsed by
  -- ##  this interval, no refund on a covered payment may be in flight, and
  -- ##  no dispute on one may be open. Each failure has its own
  -- ##  hold_reason_code.
  -- ##
  -- ##  The DURATION remains owner policy and 093 invents none. The ANCHOR is
  -- ##  no longer policy: it is max(catalog.event_session.ends_at) over the
  -- ##  settlement's own lines. See docs/phase2/_impl/G2_settlement_maturity.md
  -- ##  for the recommended value and the evidence behind it.
  -- ####################################################################
  ('payout.settlement_maturity_interval',     1, 'null'::jsonb,       'restricted'),  -- G2: one conjunct of the maturity gate; dual-controlled by its 'payout.' prefix

  -- ---- deletion.post_event_hold_hours — HOW LONG AFTER THE EVENT AN --------
  -- ---- IDENTITY MAY NOT BE TOMBSTONED. RENAMED + RE-ANCHORED (H2). ---------
  --
  -- Routed here for the same reason the maturity key is: the READER is a kernel
  -- money verb — kernel.deletion_blockers_money, BP-12 arm 2, in
  -- docs/phase2/_impl/093_parts/10_money_settlement.sql section 10j — and slice
  -- 40 owns every platform_config row so the two slices never write the same
  -- table. Spelling verified against that reader.
  --
  -- IT REPLACES `deletion.refund_possible_window_hours` (085:2189, PFA-22).
  -- That key is NOT preserved as a fallback and is NOT read by anything after
  -- this migration. Two independent reasons, and the second is the decisive one:
  --
  --   (1) THE NAME WAS WRONG. "refund possible window" names refund
  --       ELIGIBILITY. 085:2186-2187 and PFA-22 both state in terms that this
  --       key is NOT that — "the key controls DELETION SAFETY only — never
  --       refund eligibility". Refund eligibility is owned by the `refund.%`
  --       family (078:1544-1551). This is the identical class of lie G2 removed
  --       from `settlement.refund_window_interval`.
  --
  --   (2) THE CLOCK CHANGED, SO THE CONTRACT CHANGED. The 085 arm measured its
  --       window from `venue."order".created_at` — the PAYMENT date — so ORDER
  --       AGE stood in for "the obligation is finished". Executed with the old
  --       key set to 720 (30 days), a buyer who paid 90 days before a session
  --       TEN DAYS AWAY was fully erasable and kernel.sweep_deletion_pending
  --       tombstoned them BEFORE the event, while kernel.close_settlement's G2
  --       gate was holding the venue's money for exactly that risk. The arm is
  --       re-anchored to `max(coalesce(session.ends_at, session.starts_at))`
  --       over the identity's own candidate orders — reached by the join
  --       `venue."order".event_session_id` (`not null … on delete restrict`,
  --       082:77), which is TOTAL and STABLE. Re-pointing the OLD key at the new
  --       anchor would silently re-interpret any value already stored under it.
  --
  -- THE FAMILY STAYS `deletion.`, AND THAT IS A DECISION, NOT INERTIA. Filing it
  -- under `refund.%` or `payout.%` would buy dual control for free — and would
  -- re-collapse the exact concepts this change exists to separate. TICKET EXPIRY
  -- != REFUND ELIGIBILITY != DELETION SAFETY != PAYOUT MATURITY. This is
  -- deletion safety; it is named for what it is, and the dual control is bought
  -- honestly instead, by adding `deletion.%` to the prefix list in this file's
  -- own set_platform_config body (see the `v_dual` block below). G7 P1-4 named
  -- this key as one of the two whose single-admin reachability made its attack a
  -- one-statement act; that half is closed here.
  --
  -- UNITS AND TYPE — a JSON NUMBER of hours, and the reader now ENFORCES it.
  -- Precedent: authn.money_role_maturity_hours, refund.buyer_self_service_window_hours,
  -- payout.destination_cooldown_hours (078). Hours-as-a-number is deliberately
  -- NOT an interval string: an interval-typed key carries the "'24' parses as
  -- TWENTY-FOUR SECONDS" trap that G1 §7.3 documents, whereas
  -- make_interval(hours => …) cannot be misread. A guard for this key is added
  -- alongside the interval guard in set_platform_config below, so a string can
  -- no longer be stored at all.
  --
  -- WHY THE VALUE IS NULL. Same PFA-9 shape as every other owner-STOP key here:
  -- the ROW exists so the key is settable with no migration; the NUMBER is owner
  -- policy and 093 invents none. FAIL-CLOSED, VERIFIED IN THE CONSUMER: with the
  -- value absent and a paid/partially_refunded order present, 10j returns
  -- 'BP-12: post-event deletion hold unset …' and the identity is not
  -- tombstoned. With NO candidate order the arm is skipped entirely and an
  -- absent value blocks nobody — PFA-22's owner scoping ruling, unchanged.
  --
  -- WHICH DIRECTION IS DANGEROUS, because it decides the polarity below. SHORT
  -- is the irreversible direction: a tombstone cannot be undone, and there is no
  -- force-tombstone verb to compensate a hold that is too long. LONG costs
  -- erasure LATENCY, which is recoverable. So a LONGER hold is the RESTRICTIVE
  -- direction (`higher_is_restrictive`, below): raising it executes in one
  -- statement for an operator responding to an incident, and SHORTENING it —
  -- making buyers erasable sooner — parks for a second platform_admin.
  --
  -- THE STARTING POINT FOR THE OWNER, and it is a trade, not a derivation:
  -- Stripe documents that for event ticketing "the dispute window starts on the
  -- event date, not the payment date" and runs ~120 days from it
  -- (https://docs.stripe.com/disputes/how-disputes-work), which is the same
  -- evidence G2 relied on. A 120-day post-event erasure block is not defensible
  -- against erasure law; a 30-day one (720) covers post-event refund requests,
  -- early-fraud-warning arrivals, the refund executor's own latency and a
  -- realistic postponement announcement, and it is what the H2 matrix was
  -- executed against. It is offered on those stated grounds and it is the
  -- owner's call. What it does NOT cover, plainly: a chargeback filed 60 or 110
  -- days after the event against an identity already tombstoned — which is
  -- OR-13/16c's ruled path (the chargeback lands against the TOMBSTONE) with
  -- BP-10 / kernel.identity_obligation as the blocker, not this key.
  ('deletion.post_event_hold_hours',          1, 'null'::jsonb,       'restricted')   -- H2: BP-12 arm 2's operand; EVENT-anchored; dual-controlled by the `deletion.` prefix added below

on conflict (key, version) do nothing;


-- ============================================================================
-- ITEM 2 — SIGNING BOOTSTRAP TRUST ROW  (ruling B; 093 scope item 2)
--
--                    *** STOP — NOTHING IS INSERTED BELOW. ***
--
-- This item CANNOT be completed without real key material, so it is reported
-- rather than faked. No row is written by this fragment.
--
-- THE FORCING COLUMNS, exactly. kernel.signing_key (083:49-70):
--     public_key      text not null,     -- 083:55  verify key, distributable
--     kms_handle_ref  text not null,     -- 083:56  opaque KMS handle/ARN
-- Both are NOT NULL with NO default. An INSERT must supply both, and neither
-- value exists until the two-person KMS ceremony has actually generated the
-- keypair. `public_key` is the one that forces the stop: it is not a trust
-- FACT the database can assert on its own, it is the ceremony's OUTPUT.
--
-- WHY A PLACEHOLDER IS NOT AN OPTION — three independent one-way doors:
--   1. kernel.guard_signing_key_immutable (083:84-102) raises
--      'append_only: signing_key identity/target/public_key/kms_handle is
--      immutable after creation' on any UPDATE of public_key or kms_handle_ref.
--      A placeholder can NEVER be corrected in place.
--   2. kernel.tickets.signing_key_id is
--      `not null references kernel.signing_key(key_id) on delete restrict`
--      (083:191). Once one atom pins the row, the row can never be deleted.
--   3. The mint does not validate the key material — only the trust envelope.
--      kernel.issue_ticket_atoms (083:514-530) checks status='active',
--      not_before <= now(), (not_after is null or > now()) and scope coherence,
--      then mints. A row with a garbage public_key passes every one of those
--      checks. The mint would happily issue atoms pinned to a key no door can
--      ever verify, and neither the deletion restriction nor the immutability
--      guard would let anyone undo it.
-- Inventing a public key is therefore not a harmless stub. It is a permanent,
-- unrepairable corruption of the trust root, and it is exactly the outcome
-- ruling B exists to prevent ("A single application administrator must not be
-- able to silently replace the trusted signing identity").
--
-- WHAT IS ALREADY DETERMINED, so the ceremony has nothing left to decide:
--   * scope must be 'global'. signing_key_scope_target_ck (083:64-68) requires
--     event_id and venue_id both null for 'global', and both a per_event and a
--     per_venue row would have to reference a catalog row that does not exist
--     yet at 093 time. 'global' is the only scope a bootstrap row can take.
--     signing_key_active_global_uq (083:77-78) then permits exactly ONE active
--     global key, which is the intended trust posture.
--   * key_id must be deterministic — proposed '00000000-0000-0000-0000-0000000000b0',
--     following the 078 sentinel style (…f0 / …f1 at 078:1607-1611); 'b0' for
--     ruling B. Deterministic so the ops runbook, the pgTAP fixtures and the
--     credential-sign edge all name the same row without a lookup.
--   * status 'active', not_before <= now(), not_after null — the exact envelope
--     083:514-530 requires for the mint to resolve a key.
--
-- THE TEMPLATE THE CEREMONY OPERATOR FILLS IN. Left COMMENTED OUT on purpose:
-- it must not execute with placeholder values, and it must not execute at all
-- until the KMS ceremony has produced both strings.
--
--   insert into kernel.signing_key
--          (key_id, scope, event_id, venue_id,
--           public_key, kms_handle_ref, status, not_before, not_after)
--   values ('00000000-0000-0000-0000-0000000000b0', 'global', null, null,
--           '<<< CEREMONY OUTPUT: the PUBLIC verify key, PEM/base64 >>>',
--           '<<< CEREMONY OUTPUT: the opaque KMS handle/ARN >>>',
--           'active', now(), null)
--   on conflict (key_id) do nothing;
--
-- The private key is created and stays inside KMS under two-person control and
-- is NEVER written to any column of any table (083:36-39 — "NO private key
-- material on any row"; signed tokens are produced only by the credential-sign
-- edge function calling KMS). The row above is the DATABASE'S REPRESENTATION OF
-- THAT TRUST STATE ONLY — a pointer and a verify key, never a secret.
--
-- NOT DONE HERE, AND NOT TO BE DONE: kernel.provision_signing_key and
-- kernel.rotate_signing_key stay parked and fail-closed exactly as 083:375-393
-- left them. Un-parking either one would expose a credential-lifecycle verb to
-- every signed-in user, which ruling B and the 093 scope both forbid by name.
-- ============================================================================


-- ============================================================================
-- ITEM 3 — OPERATORSHIP TRANSFER FREEZE  (ruling C; 093 scope item 15)
--
-- Body-only CREATE OR REPLACE of catalog.update_venue (born 078:623-742). The
-- signature, the language, `security definer` and `set search_path = ''` are
-- reproduced EXACTLY; every arm other than the org_id arm at 078:688-704 is
-- byte-identical to 078, including the declare block, the two authority arms,
-- the unwritable-key loop, the four profile-edit arms, the noop_replay return
-- and the kernel.admin_audit row.
--
-- WHAT CHANGES, and only this: the org_id arm no longer performs the UPDATE at
-- 078:701. It refuses.
--
-- WHY NOT A REVOKED GRANT: revoking EXECUTE on catalog.update_venue would also
-- kill the benign profile edits (name / neighborhood / address / capacity_hint)
-- that the venue arm legitimately serves at 078:706-724 and that pgTAP G22
-- asserts. The refusal must be surgical to the one patch key.
--
-- WHY NOT A CONFIG FLAG: catalog.set_platform_config cannot create the key a
-- flag would need (078:1093-1095, 078:1102-1104), so a flag-based freeze would
-- itself require a migration and would buy nothing over a direct refusal while
-- adding a runtime-mutable surface. Do not build one.
--
-- PLACEMENT: the refusal sits AFTER the unwritable-key loop, exactly as
-- docs/phase2/_decisions/C_operatorship_transfer.md:428-440 prescribes, and
-- BEFORE the is_platform([platform_admin]) check that 078:689-692 held. That
-- ordering is the point: the error is stable for every caller and carries NO
-- AUTHORITY ORACLE — a non-admin learns the transfer is frozen, not whether
-- they would otherwise have been allowed to perform it.
--
-- v_new_org is now unreferenced. Its declaration is retained so the declare
-- block stays byte-identical to 078; an unused local is inert in plpgsql.
-- v_reason is likewise no longer assigned, so the audit row's
-- coalesce(nullif(trim(coalesce(v_reason,'')),''), 'profile_edit') resolves to
-- 'profile_edit' for every remaining (benign) edit — which is precisely what
-- 078 already did for a patch with no org_id key.
--
-- PFA-10 (078:620-622) still holds: the org arm is still evaluated in its own
-- statement first, so an org_owner/org_admin caller still never parses
-- kernel.has_venue_role (080).
-- ============================================================================

create or replace function catalog.update_venue(
  p_venue_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_before    jsonb;
  v_key       text;
  v_new_org   uuid;
  v_reason    text;
  v_allowed   boolean := false;
  v_changed   boolean := false;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'invalid_input: patch must be a json object';
  end if;

  select v.org_id,
         jsonb_build_object('name', v.name, 'neighborhood', v.neighborhood,
                            'address', v.address, 'capacity_hint', v.capacity_hint,
                            'org_id', v.org_id)
    into v_org_id, v_before
    from catalog.venue v where v.venue_id = p_venue_id for update;
  if v_org_id is null then
    raise exception 'not_found: venue %', p_venue_id using errcode = 'P0002';
  end if;

  -- Arm 1 (078-resolvable): org_owner / org_admin over the operating org.
  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  end if;
  -- Arm 2 (DEFERRED to 080 — PFA-10 / SEAM-3): venue_manager on this venue.
  if not v_allowed then
    v_allowed := kernel.has_venue_role(p_venue_id, array['venue_manager']);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  for v_key in select jsonb_object_keys(p_patch) loop
    -- reason_code is a patch-CARRIED field, not a column: the operatorship arm
    -- below REQUIRES it, so omitting it here made that arm unreachable in both
    -- directions (no reason => reason_required; reason => unwritable_key).
    -- 093/ruling C keeps 'reason_code' admissible even though the operatorship
    -- arm now refuses: dropping it would change the error a frozen transfer
    -- attempt returns from operatorship_transfer_frozen to unwritable_key,
    -- which is a worse and less honest message.
    if v_key not in ('name','neighborhood','address','capacity_hint','org_id',
                     'reason_code') then
      raise exception 'invalid_input: unwritable_key %', v_key;
    end if;
  end loop;

  -- Operatorship (org_id) is a TENANCY MOVE, not a benign profile edit. In 078
  -- it was is_platform([platform_admin]) only, and audited (RLS §11.1a).
  -- 093 / RULING C: venue operatorship transfers are FROZEN for initial launch.
  -- The transfer is not merely an authority change — it is an atomic re-scoping
  -- of venue.staff_role, door credentials and open settlements that no verb in
  -- the frozen corpus performs, so permitting the bare org_id UPDATE at 078:701
  -- leaves the departing operator holding staff grants and live credentials
  -- over a venue they no longer operate. Refuse instead of half-transferring.
  if p_patch ? 'org_id' then
    raise exception 'precondition_failed: operatorship_transfer_frozen — venue operatorship transfer is suspended pending the 093+ atomic re-scoping verb (Decision C). Contact the platform owner.'
      using errcode = 'P0001';

    -- ------------------------------------------------------------------
    -- FORWARD GUARD (ruling C, third bullet: "any future transfer attempt is
    -- refused while the departing organization holds PENDING or SUBMITTED
    -- payout facts"). kernel.payout.status is the closed set
    -- ('pending','submitted','paid','failed','reversed') at 085:125-126, and
    -- the org payee is payee_org_id under payout_payee_xor_ck (085:139-142).
    --
    -- DELIBERATELY UNREACHABLE while the raise above stands, and deliberately
    -- present. Lifting the freeze is then the deletion of exactly one raise,
    -- and ruling C's payout condition cannot be lost in that edit — which is
    -- the failure mode a "remember to add it back" note would invite.
    --
    -- IT IS ORDERED SECOND, NOT FIRST, ON PURPOSE. kernel.payout is granted to
    -- nobody: `revoke all on kernel.payout from anon, authenticated` (085:160)
    -- with no compensating grant. Probing it inside a definer function BEFORE
    -- the freeze raise would hand every caller who clears the v_allowed check
    -- above — including a venue_manager, who is not an org money principal — a
    -- working oracle on the organization's payout state. The freeze error must
    -- stay the first and only thing an org_id patch can learn.
    --
    -- if exists (select 1 from kernel.payout p
    --             where p.payee_org_id = v_org_id
    --               and p.status in ('pending','submitted')) then
    --   raise exception 'precondition_failed: operatorship_transfer_blocked_pending_payout — the departing organization holds unsettled payout facts'
    --     using errcode = 'P0001';
    -- end if;
    -- ------------------------------------------------------------------
  end if;

  if p_patch ? 'name' then
    update catalog.venue set name = p_patch ->> 'name', updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;
  if p_patch ? 'neighborhood' then
    update catalog.venue set neighborhood = p_patch ->> 'neighborhood', updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;
  if p_patch ? 'address' then
    update catalog.venue set address = p_patch ->> 'address', updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;
  if p_patch ? 'capacity_hint' then
    update catalog.venue set capacity_hint = (p_patch ->> 'capacity_hint')::integer,
                             updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;

  if not v_changed then
    return jsonb_build_object('status','noop_replay');
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'venue.update', 'venue', p_venue_id,
          coalesce(nullif(trim(coalesce(v_reason,'')),''), 'profile_edit'),
          v_before,
          (select jsonb_build_object('name', v.name, 'neighborhood', v.neighborhood,
                                     'address', v.address,
                                     'capacity_hint', v.capacity_hint,
                                     'org_id', v.org_id)
             from catalog.venue v where v.venue_id = p_venue_id));

  return jsonb_build_object('status','ok');
end;
$$;

-- Layer 1 of ruling C only. Layer 2 (the no-direct-SQL owner policy) and Layer
-- 3 (the CI invariant that catalog.event.org_id never diverges from its venue's
-- org_id) are OPERATIONAL and live in the runbook and CI, not here: no SQL can
-- bind a superuser, so the direct-UPDATE path is covered detectively.


-- ============================================================================
-- ITEM 4 — COLUMN-SCOPE venue."order" TO OMIT BUYER IDENTITY
--          (ruling F; 093 scope item 4)
--
-- THE DEFECT. 082:129 grants the ORDER table at TABLE grain:
--     grant select on venue."order" to authenticated;
-- while venue_order_sel_venue (082:151-159) admits venue_manager and
-- venue_finance to every order row of their venue's sessions, and
-- venue_order_sel_org (082:144-148) admits org_owner/org_admin/org_finance to
-- every order row of their org. buyer_id (082:76) is therefore readable by all
-- of them, and ONE join to a display-name surface produces a complete attendee
-- roster with money attached — no audit row, no rate limit, no consent gate.
-- Ruling F: "The verified table-grain buyer-identity/display-name join that
-- allows an unaudited attendee roster is fixed."
--
-- THE PATTERN. This borrows the mechanism 080 applied to kernel.tickets at
-- 080:421-434. 079:735 had granted that table at table grain too; 080 revoked
-- it and re-granted every column EXCEPT current_owner_id, under I-4 / §16.10a:
--     "A row-level clause cannot express a per-policy column set (one role, one
--      grant — the platform impossibility recorded as E-24), so the discipline
--      is carried by the GRANT."  — 080:422-425
-- venue."order".buyer_id is that table's current_owner_id.
--
-- *** BUT THE ANALOGY DOES NOT TRANSFER WHOLE, AND ASSUMING IT DID WAS A BUG.
-- *** An earlier draft of this item said "the reasoning transfers verbatim" and
-- *** shipped the grant change alone. It broke venue.order_item for EVERY
-- *** client, including a buyer reading their own order lines. Recorded here in
-- *** full because the failure is subtle and the next person to column-scope a
-- *** table will walk into it.
--
--   THE TRUE RULE. A USING clause escapes the column ACL only for the table the
--   policy is ATTACHED TO. A subquery inside that clause against a DIFFERENT
--   relation is an ordinary reference, and its columns are permission-checked
--   against the INVOKING role like any other query.
--
--   SO: venue_order_sel_owner (082:140-141, `using (buyer_id = auth.uid())`) is
--   attached to venue."order" itself and keeps working — that half of the
--   original reasoning was right, and is verified below. But
--   venue_order_item_sel_owner (082:210-213) is attached to venue.order_item
--   and reaches ACROSS:
--       exists (select 1 from venue."order" o
--                where o.order_id = venue.order_item.order_id
--                  and o.buyer_id = auth.uid())
--   That `o.buyer_id` is checked against `authenticated`, which no longer holds
--   it. Reproduced on an empty table, no fixture needed:
--       select set_config('role','authenticated',true);
--       select count(*) from venue.order_item;
--       ERROR:  permission denied for table order
--
--   BLAST RADIUS IS TOTAL, not conditional. `authenticated` is the only role
--   with SELECT on venue.order_item (082:205 revokes anon; service_role holds
--   no venue-schema grant), and PostgreSQL evaluates ALL of a table's permissive
--   policies and ORs the results — so the failing one aborts the statement
--   regardless of row count, buyer identity, org role or venue role.
--
--   WHY 080 NEVER MET THIS: a census of pg_depend for objects depending on
--   kernel.tickets.current_owner_id returns no policy outside kernel.tickets
--   itself. 080's analogy held because its withheld column happened to have no
--   cross-table reader. Ours does. The fix is ITEM 4b.
--
-- THE COLUMN SET, enumerated from the CREATE TABLE at 082:74-94. Thirteen
-- columns exist; TWELVE are granted and exactly ONE is withheld:
--     order_id                       082:75   pk / the order reference itself
--     buyer_id                       082:76   ** WITHHELD — the identity **
--     event_session_id               082:77   which session (operational)
--     org_id                         082:78   which org (the RLS grain itself)
--     status                         082:79   refund/paid state (ruling F allows)
--     source                         082:81   app/web/door/promoter_link
--     total_minor                    082:83   authorized amount (ruling F allows)
--     currency                       082:84   pairs with total_minor
--     command_idempotency_key        082:85   see the note below
--     attribution_candidate_code_id  082:89   promoter attribution (ruling F allows)
--     attribution_candidate_link_id  082:90   promoter attribution (ruling F allows)
--     created_at                     082:91   purchase time (ruling F allows)
--     updated_at                     082:92   last movement
-- That is ruling F's permitted default set — "ticket status, ticket type,
-- check-in state, masked order reference, purchase time, refund state,
-- authorized financial amount, and promoter attribution where applicable" —
-- minus the one thing it forbids: "no attendee name, no attendee email, no
-- attendee phone, no individual demographic field".
--
-- command_idempotency_key IS RETAINED, and the call is deliberate. It is a
-- client-minted command key, not an identity attribute, and it is the replay
-- handle venue.create_primary_checkout resolves at 082:357 and 082:451. It
-- participates in order_buyer_command_uq (buyer_id, command_idempotency_key)
-- at 082:93, but a unique constraint discloses nothing through one of its
-- columns. RESIDUAL, RECORDED: if a client ever mints the key by deriving it
-- from the user id, the identity would leak through this column in plaintext.
-- The mitigation is a client-side invariant (command keys are opaque random
-- values), not a further grant reduction, because withholding it would break
-- the checkout replay surface for the org back office.
--
-- WHY THIS BELONGS IN 093 AND NOT AN EDGE FUNCTION: venue."order" is read
-- DIRECTLY through PostgREST by any role holding the grant. An edge function
-- cannot stand in front of a door it is not in front of. A column-level GRANT
-- is DDL and is the only control that binds the direct read.
--
-- ORDERING NOTE: this is a pure ACL change on an existing table. It takes no
-- lock beyond the catalog and is safe in any position within 093.
-- ============================================================================

revoke select on venue."order" from authenticated;
grant select (order_id, event_session_id, org_id, status, source,
              total_minor, currency, command_idempotency_key,
              attribution_candidate_code_id, attribution_candidate_link_id,
              created_at, updated_at)
  on venue."order" to authenticated;

-- anon is untouched: 082:128 already revoked everything from anon and never
-- re-granted, so anon holds no privilege on this table in either shape.
-- Writes are unaffected: 082 granted no INSERT/UPDATE/DELETE on venue."order"
-- to authenticated at all (money writes are RPC/definer-only, 082:129), so
-- there is nothing to re-issue on the write side.


-- ============================================================================
-- ITEM 4b — RE-SEAT venue.order_item's OWNER POLICY ON A DEFINER PREDICATE
--           (ruling F; mandatory companion to ITEM 4 — see the *** block above)
--
-- ITEM 4 is not shippable without this. The withheld column has exactly one
-- cross-table reader, and it must stop reading the column directly.
--
-- WHY A SECURITY DEFINER PREDICATE, AND NOT A RE-GRANT. Re-granting
-- SELECT (buyer_id) to authenticated would make order_item work again and would
-- also undo ruling F completely: the whole point is that a manager/finance role
-- must not be able to join buyer identity to money, and that join is exactly
-- what the column grant restores. The definer predicate answers the ONE
-- question the policy actually needs — "is the caller the buyer of this order?"
-- — without handing out the column that answers a thousand others.
--
-- THIS IS THE HOUSE IDIOM, NOT A NEW SHAPE. It is the same construction as
-- kernel.has_venue_role (080:60-73), which reads venue.staff_role from the
-- kernel schema so a policy never has to hold a grant on the underlying table:
--   language sql · stable · security definer · set search_path = '' ·
--   body is a bare `select exists (...)` · ACL stripped then granted to
--   authenticated (the 080:440-468 PART 7 idiom).
-- It lives in `kernel` for the same reason has_venue_role does: authority
-- predicates live in kernel regardless of which schema they read.
--
-- WHY IT IS SAFE — it grants no ability that does not already exist:
--   * auth.uid() is NOT a parameter. The predicate can only ever answer about
--     the CALLER. There is no argument that steers it at another identity.
--   * It returns true only for an order the caller already owns and can already
--     read (venue_order_sel_owner, 082:140-141). For any other order_id it
--     returns false — the identical answer the pre-093 policy gave.
--   * It is not an enumeration surface: it takes an order_id and returns a
--     boolean about the caller's own ownership. It reveals nothing about who
--     any OTHER order belongs to.
--   * No org or venue role gains anything. venue_order_item_sel_org (082:216)
--     and venue_order_item_sel_venue (082:223) are DELIBERATELY NOT TOUCHED:
--     they subquery o.order_id / o.org_id / o.event_session_id only, all of
--     which remain in the ITEM 4 grant, so they still work unchanged.
--   * The definer bypasses RLS on venue."order" exactly as has_venue_role
--     bypasses it on venue.staff_role; neither table sets FORCE ROW LEVEL
--     SECURITY (relforcerowsecurity = false, verified), so this is the same
--     trust boundary the corpus already relies on.
--
-- CENSUS — RE-CONFIRMED FROM THE LIVE CATALOG, NOT INHERITED. Every other
-- consumer of venue."order".buyer_id outside the table was enumerated three
-- ways against a rehearsal database with 093 applied:
--   (a) pg_depend on the buyer_id attnum returns exactly two policies —
--       venue_order_sel_owner (on venue."order" itself; escapes the ACL, fine)
--       and venue_order_item_sel_owner (the one fixed here) — plus an index and
--       two constraints, none of which are privilege-checked.
--   (b) every policy on every table whose expression names venue."order": four
--       total; only venue_order_item_sel_owner touches buyer_id.
--   (c) VIEWS: zero views anywhere reference venue."order" (and a view would
--       run with owner rights by default in any case).
--   (d) FUNCTIONS: 21 functions name venue."order"; exactly one is SECURITY
--       INVOKER (venue.assert_promoter_engine_consistency), it does not mention
--       buyer_id, and authenticated cannot execute it. Every function that DOES
--       read buyer_id — kernel.deletion_blockers_orders (082:656),
--       kernel.deletion_blockers_money (085:229), venue.resolve_order_attribution
--       (090:1051), and the refund/checkout RPCs — is SECURITY DEFINER, so the
--       invoker's column ACL never applies to it.
-- Conclusion: venue_order_item_sel_owner was the only break, and this is the
-- complete fix.
-- ============================================================================

create or replace function kernel.is_order_buyer(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from venue."order" o
     where o.order_id = p_order_id
       and o.buyer_id = auth.uid()
  )
$$;

-- I-7: strip PUBLIC, then grant exactly (the 080:440-468 idiom). authenticated
-- needs EXECUTE because a policy expression's function call is permission-checked
-- against the INVOKING role — the same reason has_venue_role is granted.
revoke all on function kernel.is_order_buyer(uuid) from public, anon, authenticated;
grant execute on function kernel.is_order_buyer(uuid) to authenticated;

-- The policy replacement. Identical row semantics to 082:210-213 — a buyer sees
-- the order_items of orders they bought, and nothing else — with the buyer_id
-- comparison moved inside the definer so no column grant is required.
drop policy if exists venue_order_item_sel_owner on venue.order_item;
create policy venue_order_item_sel_owner on venue.order_item for select to authenticated
  using (kernel.is_order_buyer(venue.order_item.order_id));

-- venue_order_item_sel_org and venue_order_item_sel_venue are intentionally
-- left exactly as 082 wrote them. Replacing policies that are not broken would
-- widen this migration's blast radius for no benefit.


-- ============================================================================
-- ITEM 5 — COLUMN-SCOPE venue.inventory_hold TO OMIT HOLDER IDENTITY
--          (ruling F; P0 — the attendee roster moved here after ITEM 4)
--
-- THE DEFECT, executed by the red team as venue_manager and reproduced here
-- verbatim against a fresh rehearsal database with 093 applied:
--
--   select p.display_name, o.total_minor, o.status
--     from venue.inventory_hold h
--     join public.profiles p            on p.id = h.identity_id
--     join venue.inventory_batch b      on b.batch_id = h.batch_id
--     join venue.ticket_type tt         on tt.ticket_type_id = b.ticket_type_id
--     join venue."order" o              on o.event_session_id = b.event_session_id
--                                      and o.total_minor = h.quantity * tt.price_minor;
--   -->  ATTENDEE ALICE | 10000 | paid
--        ATTENDEE BOB   | 15000 | paid
--
-- ITEM 4 closed venue."order".buyer_id and the join simply MOVED one table over:
--   1. venue.inventory_hold.identity_id is granted at TABLE grain (081:1043).
--   2. venue_inventory_hold_sel_venue (081:1049-1065) admits the SAME role set
--      ITEM 4 was closing against — org_owner/org_admin/org_finance via
--      has_org_role_over_event, plus venue_manager AND venue_scanner via
--      has_event_role.
--   3. public.profiles' policy profiles_select_all is `USING (true)`
--      (070:59), so ANY exposed identity id is a display name for free.
--   4. The order re-attaches to the hold by arithmetic:
--      order.total_minor = hold.quantity x ticket_type.price_minor.
--
-- THE LESSON, recorded because it is the second instance: closing ONE column is
-- not closing a capability. `profiles_select_all USING (true)` means the NAME is
-- never the control — the identity id is the whole vulnerability, wherever it is
-- exposed. The unit of defence is "can a venue-plane role reach any identity id
-- belonging to an attendee", not "is buyer_id readable".
--
-- NOT FIXED BY NARROWING profiles_select_all: that is a live marketplace surface
-- and out of this train, per the owner. The fix is on the venue plane.
--
-- THE COLUMN SET, enumerated from 081:141-155. Ten columns exist; NINE are
-- granted and exactly ONE is withheld:
--     hold_id                  081:142   pk
--     batch_id                 081:143   which batch (operational)
--     shard_no                 081:144   shard routing (operational)
--     identity_id              081:145   ** WITHHELD — the holder identity **
--     quantity                 081:146   how many (operational, and the arithmetic
--                                        link is harmless once identity is gone)
--     status                   081:147   active/converted/released/expired
--     expires_at               081:149   TTL, drives the sweep display
--     command_idempotency_key  081:150   replay handle (see the ITEM 4 note; it is
--                                        a client-minted key, not an identity)
--     created_at               081:151
--     updated_at               081:152
--
-- THE CROSS-TABLE TRAP — CHECKED THIS TIME, AND IT DOES NOT RECUR. The failure
-- that broke venue.order_item (see ITEM 4b) is a policy on a DIFFERENT table
-- subquerying the withheld column. Swept four ways against the live catalog:
--   (a) pg_depend on the identity_id attnum returns ONE policy,
--       venue_inventory_hold_sel_owner, which is attached to venue.inventory_hold
--       ITSELF — so it escapes the column ACL and keeps working — plus one index
--       and two constraints, none privilege-checked.
--   (b) the only other policy naming inventory_hold anywhere is
--       venue_inventory_hold_sel_venue, on the same table, and it does NOT
--       reference identity_id (it keys on batch_id).
--   (c) zero views reference inventory_hold.
--   (d) zero SECURITY INVOKER functions name inventory_hold.
-- So no definer predicate is needed here. A pure column-scope is the whole fix,
-- and the holder's own read survives on the same-table policy — proven by test.
--
-- venue_scanner — MADE DELIBERATE, NOT ACCIDENTAL. The scanner is inside
-- venue_inventory_hold_sel_venue's has_event_role arm (081:1064) and so reads
-- every hold row of its event. After this change it reads them WITHOUT the
-- holder identity, which is exactly what door admission needs: a scanner
-- validates a credential presented at the door (venue.scan / the door manifest,
-- 086), it never needs to know who reserved inventory. The role is left in the
-- policy on purpose — removing it is a door-path change this migration must not
-- make — and the column grant is what bounds it.
-- ============================================================================

revoke select on venue.inventory_hold from authenticated;
grant select (hold_id, batch_id, shard_no, quantity, status, expires_at,
              command_idempotency_key, created_at, updated_at)
  on venue.inventory_hold to authenticated;

-- anon is untouched (081:981 revoked it and never re-granted). Writes are
-- unaffected: 081 granted no INSERT/UPDATE/DELETE here — holds are RPC-only.


-- ============================================================================
-- ITEM 6 — E-76 CURRENT-OPERATOR CONJUNCT ON THE TWO ORDER VENUE ARMS
--          (ruling C adjacency / A3; red team B)
--
-- THE LEAK. venue_order_sel_venue (082:151-159) and venue_order_item_sel_venue
-- (082:223-229) call kernel.has_venue_role bare. That predicate probes
-- venue.staff_role on (venue_id, auth.uid(), role) and NOTHING else (080:60-73):
-- it knows neither who currently operates the room nor whose order this is.
-- After an operatorship divergence (event org <> venue org) the red team
-- measured, on the same fixture:
--     settlement      rows visible = 0   (10f's E-76 fix holds)
--     settlement_line rows visible = 0   (10f's E-76 fix holds)
--     venue."order"   rows visible = 1   <-- LEAK
-- so a stale or foreign venue-role holder reads another organization's order:
-- total_minor, status, org_id — and, before ITEM 4, buyer_id, which is PII the
-- settlement tables do not even carry.
--
-- WHY IT MATTERS MORE NOW: 093's open_settlement grain split makes the divergent
-- state routine rather than exotic, and this arm partially defeats ITEM 5 —
-- closing the inventory_hold roster path is worth less while a foreign venue
-- role can still read order rows directly.
--
-- THE FIX — the SAME shape the money slice used at
-- docs/phase2/_impl/093_parts/10_money_settlement.sql section 10f, so the two
-- read alike: conjoin "the venue's CURRENT operator org equals the row's own
-- org_id", proven at 087:299-300.
--
-- EFFECTS. A venue operator keeps full venue-arm visibility of its own orders at
-- its own room: zero behaviour change on every state the shipped write paths can
-- create. A promoter's order at a foreign room becomes invisible to that room's
-- staff. A departing operator's stale staff lose the venue arm over legacy
-- orders after a transfer — the intended E-76 semantics. The true owner is
-- unaffected: it reads through venue_order_sel_org (082:144-148), which already
-- keys on org_id. The buyer is unaffected: venue_order_sel_owner (082:140-141)
-- is a separate permissive policy on buyer_id = auth.uid().
--
-- CENSUS OF THE SAME OMISSION ELSEWHERE — reported, not silently fixed. Of the
-- 24 policies calling has_venue_role/has_event_role, four already carry the
-- conjunct (promoter, promoter_code, settlement, settlement_line). Of the
-- remaining twenty, only FOUR sit on a row that carries its own org_id and can
-- therefore express E-76 directly: catalog.event, catalog.venue, kernel.tickets
-- and venue."order". catalog.venue's conjunct is vacuous (v.org_id = its own
-- org_id is a tautology). venue."order" and venue.order_item are fixed here
-- because they are this slice's tables. catalog.event and kernel.tickets carry
-- the identical omission and are NOT touched here: they are 078/079 surfaces
-- owned by other slices, and kernel.tickets is additionally the door read path.
-- **Both are handed to the coordinator as open items.** The sixteen policies on
-- rows with no org_id (door_manifest*, scan*, guest_*, comp_allocation,
-- inventory_*, ticket_type, staff_role, promoter_link, event_session) cannot
-- express the conjunct without resolving event->org, which is a wider change than
-- 093 carries; recorded, not taken. Promoting E-76 into kernel.has_venue_role
-- itself would close the whole class at once but that predicate has 15+ frozen
-- call sites — the same judgement 10f recorded and declined.
-- ============================================================================

drop policy if exists venue_order_sel_venue on venue."order";
create policy venue_order_sel_venue on venue."order" for select to authenticated
  using (
    exists (
      select 1 from catalog.event_session s
        join catalog.event e on e.event_id = s.event_id
       where s.session_id = venue."order".event_session_id
         and kernel.has_venue_role(e.venue_id, array['venue_manager','venue_finance'])
         and (select v.org_id from catalog.venue v where v.venue_id = e.venue_id)
             = venue."order".org_id   -- E-76: current operator
    )
  );

drop policy if exists venue_order_item_sel_venue on venue.order_item;
create policy venue_order_item_sel_venue on venue.order_item for select to authenticated
  using (exists (
    select 1 from venue."order" o
      join catalog.event_session s on s.session_id = o.event_session_id
      join catalog.event e on e.event_id = s.event_id
     where o.order_id = venue.order_item.order_id
       and kernel.has_venue_role(e.venue_id, array['venue_manager','venue_finance'])
       and (select v.org_id from catalog.venue v where v.venue_id = e.venue_id)
           = o.org_id));   -- E-76: current operator



-- ============================================================================
-- ITEM 7 — DUAL-CONTROL THE `fee.%` NAMESPACE
--          (ruling A5; body-only CREATE OR REPLACE of catalog.set_platform_config)
--
-- THE FINDING, executed against the live setter as a single platform_admin:
-- set_platform_config('fee.buyer_service_bps', '750'::jsonb, ...) executed
-- IMMEDIATELY — status 'ok', a new version row inserted, no parking, no second
-- approver. fee.buyer_service_bps is the last surviving instance of the pattern
-- the owner banned: one person, one statement, and the platform goes from
-- "cannot sell" to "selling", with three preconditions a gate audit proved are
-- unenforced behind it (no active signing key required at checkout — the buyer
-- can be charged for a ticket that can never mint, being closed separately in
-- slice 30; refund executability checked nowhere; no tax model at all).
--
-- THE FIX IS A ONE-LINE WIDENING of the prefix test at 078:1145-1147, delivered
-- as a body-only replacement because 078 is immutable. The function body below
-- is reproduced from 078:1048-1310 MECHANICALLY (extracted, not retyped) and is
-- byte-identical except for the v_dual assignment and its adjacent comment. The
-- signature, `security definer`, `set search_path = ''`, every precondition,
-- every RANGE check, the whole polarity map, the cross-config wallet invariant,
-- the parked path, the direct path and both audit rows are untouched.
--
-- POLARITY — CHECKED, NOT ASSUMED. fee.buyer_service_bps appears NOWHERE in the
-- declared polarity map (078:1148-1196); it falls through to `else null`. With
-- v_polarity null, v_restrictive can never be set true (every arm that assigns
-- it requires a non-null polarity), so `v_dual and not v_restrictive` is
-- unconditionally true and the key PARKS ON EVERY WRITE, in both directions.
-- That is the intended behaviour: there is no "restrictive direction" for a
-- platform fee rate, so no write of it should ever bypass the second approver.
-- Verified by execution, not by reading.
--
-- NO NEW VOCABULARY: the parked path reuses action 'config.set_money_key' and
-- subject_kind 'config_key', both already in kernel.approval_request's frozen
-- closed sets and already exercised by the other seven dual-controlled
-- namespaces. Nothing is widened but the prefix list.
--
-- BLAST RADIUS: `fee.` is a namespace this train created (ITEM 1). It contains
-- exactly one key. No pre-093 key anywhere in the 41-key seed block starts with
-- `fee.`, so no existing configuration path changes behaviour — verified
-- against the seeded key list.
-- ============================================================================

create or replace function catalog.set_platform_config(
  p_key text, p_value jsonb, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_cur_ver    integer;
  v_cur_val    jsonb;
  v_visibility text;
  v_dual       boolean;
  v_polarity   text;
  v_restrictive boolean;
  v_old_num    numeric;
  v_new_num    numeric;
  v_span       interval;
  v_skew       interval;
  v_ttl        interval;
  v_probe      interval;                 -- 093: interval type guard scratch
  v_request_id uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  -- reason_code is mandatory for EVERY key, not only the money namespaces.
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  -- platform_support and platform_risk hold NO authority here: risk holds
  -- hold_payout, not the thresholds that decide when a payout needs approval.
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin required'
      using errcode = '42501';
  end if;
  if p_value is null then
    raise exception 'precondition_failed: bad_value — use the JSON null literal';
  end if;

  -- APPR-SUBJ-1: resolve the subject under its own lock, in the same transaction
  -- that writes the row. THIS FUNCTION CREATES NO NEW KEY — a key that no code
  -- reads is a config row that lies (078 seeds every key).
  select c.version, c.value, c.visibility
    into v_cur_ver, v_cur_val, v_visibility
    from catalog.platform_config c
   where c.key = p_key
   order by c.version desc
   limit 1
     for update;
  if v_cur_ver is null then
    raise exception 'precondition_failed: unknown_key %', p_key;
  end if;

  if v_cur_val = p_value then
    return jsonb_build_object('status','noop_replay','key',p_key,
                              'version',v_cur_ver,'request_id',null);
  end if;

  -- RPC §20.2.1 precondition: "p_value passes the key's declared TYPE/RANGE".
  -- TYPE: a key never changes shape. The seeded row is the type witness; a key
  -- seeded absent-by-design (JSON null) has no witness yet and accepts the first
  -- typed value, after which the witness exists.
  if jsonb_typeof(v_cur_val) <> 'null'
     and jsonb_typeof(p_value) <> jsonb_typeof(v_cur_val) then
    raise exception 'precondition_failed: bad_value — % is %, not %',
      p_key, jsonb_typeof(v_cur_val), jsonb_typeof(p_value);
  end if;
  -- RANGE: enforced for every key whose admissible range the frozen corpus
  -- actually states. A key with no stated range is not invented one here.
  if p_key = 'authn.money_role_maturity_hours'
     and jsonb_typeof(p_value) = 'number'
     and ((p_value #>> '{}')::numeric < 24 or (p_value #>> '{}')::numeric > 72) then
    -- RLS MD-14 / RPC §1.1e: "the admissible range as 24-72 hours".
    raise exception 'precondition_failed: bad_value — authn.money_role_maturity_hours is outside MD-14''s admissible 24-72 hours';
  end if;
  if p_key = 'notify.announcement_hold_seconds'
     and jsonb_typeof(p_value) = 'number'
     and (p_value #>> '{}')::numeric < 120 then
    -- NOTIF §7.5: "seed 300 s, FLOOR 120 s".
    raise exception 'precondition_failed: bad_value — notify.announcement_hold_seconds is below NOTIF §7.5''s 120 s floor';
  end if;
  if p_key = 'authn.money_action_required_aal'
     and jsonb_typeof(p_value) = 'string'
     and (p_value #>> '{}') not in ('aal1','aal2') then
    raise exception 'precondition_failed: bad_value — authn.money_action_required_aal must be aal1|aal2';
  end if;
  if p_key = 'refund.scanned_atom_policy'
     and jsonb_typeof(p_value) = 'string'
     and (p_value #>> '{}') not in ('refuse','platform_review') then
    raise exception 'precondition_failed: bad_value — refund.scanned_atom_policy must be refuse|platform_review';
  end if;

  -- 093 — INTERVAL TYPE GUARD (the second of this item's two changes).
  -- THE HOLE IT CLOSES: the TYPE witness above is skipped when the current value
  -- is JSON null (078:1111-1114 — "a key seeded absent-by-design has no witness
  -- yet and accepts the first typed value"). Every owner-STOP key in 093 is
  -- seeded null, so each one accepts ANY json type on its first write. For an
  -- interval-consumed key that is silent and severe: set_platform_config(
  -- 'ticket.expiry_grace','24') is accepted, and '24'::interval is TWENTY-FOUR
  -- SECONDS, not 24 hours (verified: select '24'::interval => 00:00:24). The
  -- sweep at 079:475 then terminal-izes every atom on every ended session within
  -- one cron tick, and `expired` is terminal and excluded from cancel_event's
  -- refund cascade. The typo reads as correct to a human, which is what makes it
  -- the dangerous shape.
  -- THE GUARD: for keys the corpus consumes with ::interval, require a jsonb
  -- STRING that actually parses. A bare number can no longer be stored.
  -- MAINTENANCE NOTE: this is a list, in the same explicit per-key style as the
  -- four RANGE checks above, and it must gain any future interval-typed key. The
  -- root cause is the missing type witness on a null seed, not the list.
  if p_key in ('ticket.expiry_grace','inventory.hold_ttl_interval',
               'payout.settlement_maturity_interval','door.schedule_move_grace_interval',
               'notify.delivery_lease_interval',
               'credential.wallet_exp_skew','credential.wallet_default_span',
               'credential.app_ttl_interval','wallet.apple.cert_expiry_warn_interval',
               'door.implicit_freeze_offset_interval','door.manifest_ttl_interval',
               'door.manifest_early_open_window','door.max_override_interval',
               'door.session_ttl_interval','door.session_absolute_max_interval',
               'door.session_post_session_grace')
     and jsonb_typeof(p_value) <> 'null' then
    if jsonb_typeof(p_value) <> 'string' then
      raise exception 'precondition_failed: bad_value — % is interval-typed and needs a JSON STRING such as "24 hours"; a bare number is read as SECONDS', p_key;
    end if;
    begin
      v_probe := (p_value #>> '{}')::interval;
    exception when others then
      v_probe := null;
    end;
    if v_probe is null then
      raise exception 'precondition_failed: bad_value — % must be a parseable interval literal', p_key;
    end if;
  end if;

  -- H2 — THE MIRROR GUARD: a key consumed as a NUMBER OF HOURS must be a JSON
  -- NUMBER. The guard above stops a number reaching an interval-typed key; this
  -- one stops a STRING reaching an hours-typed key, and it exists because the
  -- two failure modes are neighbours on the keyboard. `ticket.expiry_grace`
  -- REQUIRES the string form '"72 hours"', so '"720 hours"' is the natural typo
  -- on its sibling deletion key — and before H2's rewrite of
  -- kernel.deletion_blockers_money that one append would have raised inside the
  -- deletion blocker for EVERY identity, forever (platform_config is append-only,
  -- and 085's read cast the value in an ordered target list, so the LIMIT could
  -- not protect it). 10j is now immune by construction; this refuses the value at
  -- the door as well, so the bad version is never written in the first place.
  if p_key in ('deletion.post_event_hold_hours')
     and jsonb_typeof(p_value) <> 'null'
     and jsonb_typeof(p_value) <> 'number' then
    raise exception 'precondition_failed: bad_value — % is a NUMBER OF HOURS and needs a JSON number such as 720; "720 hours" is the interval spelling and belongs to ticket.expiry_grace', p_key;
  end if;

  -- 093 / ruling A5 — `fee.%` ADDED. This is the ONLY change to this function.
  -- WHY: fee.buyer_service_bps is the final clause of the SALEABLE chain — the
  -- statement that sets it moves the platform from "cannot sell" to "selling",
  -- and a gate audit proved three preconditions behind it are unenforced (no
  -- active signing key is required at checkout, refund executability is checked
  -- nowhere, and no tax model exists at all). A single administrator crossing
  -- that line in one un-parked statement is exactly the shape the owner banned:
  -- a config value acting as a hidden feature flag for incomplete logic.
  -- WHY THE PREFIX AND NOT A RENAME: the settlement maturity key was fixed by
  -- renaming it into `payout.%`; that is REJECTED here because this is not a
  -- payout key and the rename would reintroduce the misleading semantics the
  -- maturity rename removed. The prefix list is a policy statement about which
  -- NAMESPACES are money-critical, and buyer-facing pricing plainly is.
  -- 093 / H2 — `deletion.%` ADDED, for the same reason and by the same test.
  -- deletion.post_event_hold_hours decides when an identity becomes
  -- IRREVERSIBLY tombstoned while money obligations on their orders can still
  -- arise. G7 P1-4 executed the gap: as one platform_admin with an aal2 claim,
  -- `set_platform_config('deletion.refund_possible_window_hours', …)` returned
  -- `{"status":"ok"}` with no second human, and that single statement is what
  -- turned P0-3 from a design flaw into a one-statement act. `deletion.%`
  -- matched none of the prefixes below. It does now.
  -- WHY THE PREFIX AND NOT A RENAME INTO `refund.%`/`payout.%`: the same
  -- argument the `fee.%` note above makes. This is not a refund key and not a
  -- payout key; filing it under either would restore exactly the collapsed
  -- semantics — refund ELIGIBILITY vs payout MATURITY vs DELETION SAFETY — that
  -- G2's rename and H2's re-anchor both exist to take apart.
  -- 093 / H2 — `ticket.%` ADDED. The LAST destructive key family outside this list.
  -- The evidence is G1 §7 and the seed comment at the top of this file, and it is
  -- stronger than the case for several keys already here: setting
  -- `ticket.expiry_grace` wrongly does not DEGRADE, it writes the TERMINAL label
  -- `expired` across every atom on every ended session within one cron tick
  -- (079:456, cron */2 at 079:799-803) — and 088:1682/1735/1783 then EXCLUDE
  -- expired atoms from catalog.cancel_event's refund cascade, so the holder loses
  -- the ticket AND the money. There is no exit: no shipped function writes
  -- kernel.tickets.state back out of `expired`. A single administrator must not be
  -- able to cross that boundary alone, for the same reason `fee.%` (ruling A5) and
  -- `deletion.%` (H2) were added — an irreversible money or identity boundary takes
  -- two humans.
  -- NOTE the two controls are INDEPENDENT and both still apply. The interval TYPE
  -- guard above already refuses a bare number on this key (it is first in that
  -- list), which is what stops the '24' => TWENTY-FOUR SECONDS cast; dual control
  -- is the separate question of who may set a WELL-TYPED but wrong value. Neither
  -- shadows the other: a mistyped value is refused outright and never parks, and a
  -- well-typed one parks.
  -- `ticket.%` has NO entry in the polarity map below, so it takes §20.2.1's third
  -- arm — not comparable => PARK — in BOTH directions. That is intended and is the
  -- correct default here: the corpus declares no restrictive direction for a grace
  -- that is destructive when short and merely slow when long, so failing toward the
  -- approver is the honest reading.
  v_dual := p_key like 'refund.%' or p_key like 'payout.%' or p_key like 'authn.%'
         or p_key like 'comp.%'   or p_key like 'wallet.%' or p_key like 'credential.%'
         or p_key like 'door.session\_%' or p_key like 'fee.%'
         or p_key like 'deletion.%' or p_key like 'ticket.%';

  -- The declared polarity map. A key absent from it has NO declared polarity and
  -- therefore parks (when dual-controlled). Booleans, enums and every non-scalar
  -- are incomparable by construction and park for the same reason.
  v_polarity := case
    -- LOWER IS RESTRICTIVE: every one of these is a CEILING or a span whose
    -- reduction narrows what may happen without a second human.
    when p_key in ('refund.org_auto_execute_max_minor',
                   'refund.org_dual_control_max_minor',
                   'refund.buyer_self_service_max_minor',
                   'refund.buyer_self_service_window_hours',
                   'refund.platform_support_max_minor',
                   'payout.request_auto_max_minor',
                   -- payout.dual_control_min_minor is the amount ABOVE WHICH a
                   -- payout parks (MONEY §7.2), so RAISING it REMOVES payouts
                   -- from dual control. T-RPC-CFG-01 names this exact key:
                   -- "raising ... parks and inserts no version; lowering it
                   -- executes". It is a ceiling in disguise, not a floor.
                   'payout.dual_control_min_minor',
                   'comp.per_staff_step_up_max_units',
                   'authn.money_action_max_age_seconds',
                   'door.session_ttl_interval',
                   'door.session_absolute_max_interval',
                   'door.session_post_session_grace',
                   'credential.wallet_exp_skew',
                   'credential.wallet_default_span',
                   'credential.app_ttl_interval')          then 'lower_is_restrictive'
    -- HIGHER IS RESTRICTIVE: a longer cooldown, a longer probation and a longer
    -- maturity floor each narrow what may happen (RPC §20.2.1: "a longer
    -- probation"). comp.per_staff_step_up_window_hours is DELIBERATELY ABSENT:
    -- the window is the COUNTING period of the C39 insider-fraud gate, so
    -- shortening it counts fewer units and fires step-up LESS often — the
    -- corpus declares a direction only for its _max_units half (RLS §11.1
    -- AUTHZ-M8), so this key has NO declared polarity and takes §20.2.1's third
    -- arm: not comparable => PARK. Failing toward the approver is the whole
    -- point of that arm.
    -- H2: deletion.post_event_hold_hours joins this arm, and the direction is
    -- forced by irreversibility, not by taste. A LONGER hold blocks more
    -- tombstones, and a tombstone is TERMINAL — DSM has no exit from ERASED and
    -- the corpus carries no force-tombstone verb to compensate an over-long
    -- hold. Too long costs erasure LATENCY (recoverable, and visible in
    -- deletion_block_reason, which now carries the maturity instant). Too short
    -- destroys a live counterparty. So RAISING it executes in one statement — an
    -- operator must be able to tighten during an incident — and SHORTENING it,
    -- which is what makes advance-purchase buyers erasable sooner, parks for a
    -- second platform_admin. Note the seeded value is JSON null, so the FIRST
    -- set is not number-to-number and parks regardless: arming this key at all
    -- is the dangerous act and it takes two humans.
    when p_key in ('payout.destination_cooldown_hours',
                   'payout.destination_probation_days',
                   'authn.money_role_maturity_hours',
                   'deletion.post_event_hold_hours')       then 'higher_is_restrictive'
    -- FALSE IS RESTRICTIVE: a kill switch. WALLET §11.5b — "Setting
    -- wallet.apple.enabled := false ... needs ONE admin and no approval round.
    -- A kill switch that needs a quorum is not a kill switch."
    when p_key = 'wallet.apple.enabled'                    then 'false_is_restrictive'
    -- HIGHER AAL IS RESTRICTIVE: RPC §20.2.1 enumerates "a higher required AAL"
    -- among the restrictive directions by name, so raising it during a
    -- session-theft incident must execute in one transaction.
    when p_key = 'authn.money_action_required_aal'         then 'aal_higher_is_restrictive'
    else null
  end;

  v_restrictive := false;
  if v_polarity is not null
     and jsonb_typeof(v_cur_val) = 'number' and jsonb_typeof(p_value) = 'number' then
    v_old_num := (v_cur_val #>> '{}')::numeric;
    v_new_num := (p_value  #>> '{}')::numeric;
    v_restrictive := case v_polarity
                       when 'lower_is_restrictive'  then v_new_num < v_old_num
                       when 'higher_is_restrictive' then v_new_num > v_old_num
                     end;
  elsif v_polarity = 'false_is_restrictive'
     and jsonb_typeof(p_value) = 'boolean' then
    -- Pulling the switch is a tightening; flipping it on is the mandatory-
    -- dual-control write WALLET §11.5 describes.
    v_restrictive := (p_value = 'false'::jsonb);
  elsif v_polarity = 'aal_higher_is_restrictive'
     and jsonb_typeof(v_cur_val) in ('string','null') and jsonb_typeof(p_value) = 'string' then
    -- aal1 < aal2. An absent current value is the weakest state, so ANY named
    -- level is a tightening against it.
    v_restrictive := case
      when p_value #>> '{}' not in ('aal1','aal2') then false      -- unknown => park
      when jsonb_typeof(v_cur_val) = 'null'        then true
      else (p_value #>> '{}') > (v_cur_val #>> '{}')
    end;
  elsif v_polarity in ('lower_is_restrictive','higher_is_restrictive')
     and jsonb_typeof(v_cur_val) = 'string' and jsonb_typeof(p_value) = 'string' then
    begin
      v_restrictive := case v_polarity
        when 'lower_is_restrictive'
          then (p_value #>> '{}')::interval < (v_cur_val #>> '{}')::interval
        when 'higher_is_restrictive'
          then (p_value #>> '{}')::interval > (v_cur_val #>> '{}')::interval
      end;
    exception when others then
      v_restrictive := false;                       -- not comparable => park
    end;
  end if;

  -- The cross-config invariant (door §10.6): a Wallet token may never outlive the
  -- offline window any manifest could authorise. Validated whenever EITHER side
  -- changes, and the write is rejected otherwise. Evaluated INLINE rather than in
  -- a helper: a helper would be a catalog object the frozen closed world does not
  -- carry, and package parity is EXTRA = 0.
  if p_key in ('credential.wallet_default_span','credential.wallet_exp_skew',
               'door.manifest_ttl_interval') then
    begin
      select coalesce(
               case when p_key = 'credential.wallet_default_span' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'credential.wallet_default_span'
                 order by c.version desc limit 1)),
             coalesce(
               case when p_key = 'credential.wallet_exp_skew' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'credential.wallet_exp_skew'
                 order by c.version desc limit 1)),
             coalesce(
               case when p_key = 'door.manifest_ttl_interval' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'door.manifest_ttl_interval'
                 order by c.version desc limit 1))
        into v_span, v_skew, v_ttl;
    exception when others then
      v_span := null; v_skew := null; v_ttl := null;    -- unparseable => reject
    end;
    -- An absent operand cannot be shown to satisfy the invariant, so it does not.
    if v_span is null or v_skew is null or v_ttl is null or v_span + v_skew > v_ttl then
      raise exception 'precondition_failed: bad_value — wallet_default_span + wallet_exp_skew must not exceed door.manifest_ttl_interval';
    end if;
  end if;

  if v_dual and not v_restrictive then
    insert into kernel.approval_request
           (action, required_approver_class, subject_kind, subject_id, org_id,
            payload, config_versions, requested_by, state, reason_code,
            expires_at, command_idempotency_key)
    values ('config.set_money_key', 'platform_admin', 'config_key',
            md5(p_key)::uuid, null,
            jsonb_build_object('key', p_key, 'proposed_value', p_value,
                               'current_value', v_cur_val),
            jsonb_build_object(p_key, v_cur_ver),
            v_uid, 'pending', trim(p_reason_code),
            now() + interval '72 hours', p_command_key)
    returning request_id into v_request_id;

    insert into kernel.admin_audit
           (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'config.money_key_proposed', 'config_key', md5(p_key)::uuid,
            trim(p_reason_code),
            jsonb_build_object('key', p_key, 'version', v_cur_ver, 'value', v_cur_val),
            jsonb_build_object('key', p_key, 'value', p_value));

    -- version UNCHANGED: the UI must say "waiting for a second approver",
    -- never "saved".
    return jsonb_build_object('status','parked','key',p_key,
                              'version',v_cur_ver,'request_id',v_request_id);
  end if;

  -- Direct path. visibility is COPIED FORWARD: set_platform_config may not change
  -- it — a function that can flip a key to public is a function that can publish
  -- the ceilings.
  insert into catalog.platform_config (key, version, value, visibility)
  values (p_key, v_cur_ver + 1, p_value, v_visibility);

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'config.change', 'config_key', md5(p_key)::uuid, trim(p_reason_code),
          jsonb_build_object('key', p_key, 'version', v_cur_ver, 'value', v_cur_val),
          jsonb_build_object('key', p_key, 'version', v_cur_ver + 1, 'value', p_value));

  return jsonb_build_object('status','ok','key',p_key,
                            'version',v_cur_ver + 1,'request_id',null);
end;
$$;



-- ============================================================================
-- ITEM 8 — GUARD BACKWARD SCHEDULE MOVEMENT (P0 — seller-controlled backdating)
--          body-only CREATE OR REPLACE of catalog.update_event_session (079:518-699)
--
-- Reproduced as executed: a seller org moves starts_at AND ends_at back 400 days
-- with a reason_code; the settlement that had closed held/maturity_not_elapsed
-- re-closes with hold_state='none' and payout_hold null, and request_org_payout
-- returns pending_approval to an org-class approver. Second repro: three active
-- atoms on a session 30 days out are all swept to 'expired' — terminal — after
-- the same backdate.
--
-- The function below is reproduced from 079:518-699 MECHANICALLY (extracted, not
-- retyped). Two changes only: one added local (v_econ) and one added guard block,
-- both marked in place. The forward guard, door.schedule_move_grace_interval, the
-- boundary_engaged / move_exceeds_grace / reason_required / session_terminal /
-- unwritable_key refusals, the authority arms, the marketing-only arm, the
-- session_version bump, the audit row and both return shapes are untouched.
-- ============================================================================

create or replace function catalog.update_event_session(
  p_session_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_org_id     uuid;
  v_venue_id   uuid;
  v_event_id   uuid;
  v_status     text;
  v_starts     timestamptz;
  v_ends       timestamptz;
  v_doors      timestamptz;
  v_door_open  timestamptz;
  v_before     jsonb;
  v_key        text;
  v_reason     text;
  v_allowed    boolean := false;
  v_marketing  boolean := false;
  v_has_atoms  boolean := false;
  v_grace      interval;
  v_new_starts timestamptz;
  v_new_doors  timestamptz;
  v_new_ends   timestamptz;
  v_econ       boolean;                 -- 093: economic-weight probe (backward arm)
  v_time_chg   boolean := false;
  v_changed    boolean := false;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'invalid_input: patch must be a json object';
  end if;

  select s.event_id, s.status, s.starts_at, s.ends_at, s.doors_at, s.door_open_at,
         jsonb_build_object('session_label', s.session_label, 'starts_at', s.starts_at,
                            'ends_at', s.ends_at, 'doors_at', s.doors_at)
    into v_event_id, v_status, v_starts, v_ends, v_doors, v_door_open, v_before
    from catalog.event_session s
   where s.session_id = p_session_id
   for update;                                          -- rank 1
  if v_event_id is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;

  select e.org_id, e.venue_id into v_org_id, v_venue_id
    from catalog.event e where e.event_id = v_event_id;

  -- The unwritable set FIRST, for every caller (T-RPC-CAT-02): door_open_at has
  -- a sole writer (catalog.engage_door_freeze, 086, ruling O-5); session_version
  -- is bumped by THIS BODY, never named by a client; event_id re-parents atoms.
  for v_key in select jsonb_object_keys(p_patch) loop
    if v_key not in ('session_label','starts_at','ends_at','doors_at','reason_code') then
      raise exception 'invalid_input: unwritable_key %', v_key;
    end if;
  end loop;

  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;

  -- Marketing-only patch (RLS §11.1's D3 extension for this verb): the label is
  -- display; the time columns are freeze INPUTS and never marketing.
  v_marketing := not (p_patch ? 'starts_at' or p_patch ? 'ends_at' or p_patch ? 'doors_at');

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  elsif v_marketing
        and kernel.has_org_role(v_org_id, array['org_marketing']) then
    v_allowed := true;
  end if;
  if not v_allowed then             -- PFA-10 deferred arm (has_venue_role, 080)
    v_allowed := kernel.has_venue_role(
      v_venue_id,
      case when v_marketing then array['venue_manager','venue_marketing']
           else array['venue_manager'] end);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  v_new_starts := coalesce((p_patch ->> 'starts_at')::timestamptz, v_starts);
  v_new_doors  := case when p_patch ? 'doors_at'
                       then (p_patch ->> 'doors_at')::timestamptz else v_doors end;
  v_new_ends   := case when p_patch ? 'ends_at'
                       then (p_patch ->> 'ends_at')::timestamptz else v_ends end;
  if v_new_starts is null then
    raise exception 'invalid_input: starts_at cannot be null';
  end if;
  if v_new_ends is not null and v_new_ends <= v_new_starts then
    raise exception 'precondition_failed: ends_at must be after starts_at';
  end if;
  v_time_chg := (v_new_starts is distinct from v_starts)
             or (v_new_doors  is distinct from v_doors)
             or (v_new_ends   is distinct from v_ends);

  -- THE TIME GUARD — a custody property (§20.2.4). starts_at/doors_at are the
  -- inputs to catalog.effective_freeze_at, which decides when transfers stop.
  if (v_new_starts is distinct from v_starts) or (v_new_doors is distinct from v_doors) then
    -- once the boundary is taken, the schedule that produced it is evidence.
    if v_door_open is not null then
      raise exception 'precondition_failed: boundary_engaged';
    end if;
    select exists (select 1 from kernel.tickets t
                    where t.event_session_id = p_session_id)
      into v_has_atoms;
    if v_has_atoms then
      -- config('door.schedule_move_grace_interval') is a PFA-9 CLASS A key:
      -- NOT seeded, and 079 is directed to implement it FAIL-TO-SAFE — absent
      -- means NO later move is permitted (the X-12 shape, ruled in PFA-9).
      begin
        v_grace := (select (c.value #>> '{}')::interval
                      from catalog.platform_config c
                     where c.key = 'door.schedule_move_grace_interval'
                     order by c.version desc
                     limit 1);
      exception when others then
        v_grace := null;
      end;
      if (v_new_starts > v_starts
          and (v_grace is null or v_new_starts - v_starts >= v_grace))
         or (v_doors is not null and v_new_doors is not null and v_new_doors > v_doors
             and (v_grace is null or v_new_doors - v_doors >= v_grace))
         or (v_doors is null and v_new_doors is not null and v_new_doors > v_new_starts
             and (v_grace is null or v_new_doors - v_new_starts >= v_grace)) then
        raise exception 'precondition_failed: move_exceeds_grace';
      end if;
      -- any move with atoms issued is audited with a MANDATORY reason code.
      v_reason := p_patch ->> 'reason_code';
      if v_reason is null or length(trim(v_reason)) = 0 then
        raise exception 'precondition_failed: reason_required';
      end if;
    end if;
  end if;

  -- ==== 093 P0 — THE BACKWARD ends_at ARM. THIS IS THE ONLY LOGIC ADDED. ====
  -- The guard above tests FORWARD movement only: every arm at 079:646-651 is
  -- `v_new_* > v_*`, and it never inspects ends_at at all. So a seller org with
  -- org_owner/org_admin could move starts_at AND ends_at back 400 days with a
  -- reason_code and have it accepted. That single primitive:
  --   * defeats the whole eight-predicate G2 maturity gate, because every other
  --     predicate is anchored on the session's own ends_at — the settlement that
  --     closed held/maturity_not_elapsed re-closes with hold_state='none' and
  --     request_org_payout returns pending_approval to an ORG-class approver,
  --     with no platform human anywhere in the path; and
  --   * destroys live credentials — with ticket.expiry_grace set, backdating a
  --     session 30 days out makes sweep_expired_ticket_atoms terminal-ize every
  --     active atom on it within one cron tick.
  -- The bound the maturity report claimed ("the most a seller can shave is the
  -- session's own duration — hours, not months") does not hold: it is unbounded.
  --
  -- SCOPE — NARROWED TO ends_at, AND THE REASON MATTERS.
  -- The corpus's standing claim is that "an earlier move only tightens the
  -- freeze" (asserted by pgTAP 143 G10 and 144 E2). Per column, that claim is
  -- HALF right, and the half that is right is kept:
  --   * starts_at / doors_at earlier — GENUINELY SAFE, still permitted. They
  --     feed only catalog.effective_freeze_at (078:405-446); moving them earlier
  --     makes transfers freeze SOONER, which is strictly more conservative, and
  --     it touches no money anchor. 143 G10 moves starts_at alone and still
  --     passes.
  --   * ends_at earlier — NOT SAFE, and this is what the claim missed. ends_at
  --     is not a freeze input at all; it is the anchor of the two consumers that
  --     did not exist when that reasoning was written: the G2 payout-maturity
  --     gate and kernel.sweep_expired_ticket_atoms (079:494). Moving it earlier
  --     does not tighten anything — it MATURES money and EXPIRES live atoms.
  -- So this arm tests ends_at only. That is the whole exploitable surface: the
  -- red team's paired 400-day move is refused because its ends_at half is.
  --
  -- THE NULL CASE IS COVERED TOO. A session with ends_at NULL has no maturity
  -- anchor, so a two-step attack — move starts_at back (now permitted), then SET
  -- ends_at to a past value that still satisfies the 079:616-617 ends>starts
  -- check — would reach the same place. Newly setting an ends_at that has
  -- ALREADY ELAPSED is therefore refused as well. Setting a FUTURE ends_at on a
  -- session that lacked one stays permitted: it is benign, and it is the only
  -- way to close R1's separate null-ends_at fail-open.
  --
  -- WHY NOT FORBID EVERY BACKWARD MOVE: a pre-sale draft legitimately reschedules
  -- in both directions. The line is ECONOMIC WEIGHT, read from the schema:
  --   * an atom was minted for the session          (kernel.tickets)
  --   * money was actually taken                    (venue."order", paid /
  --     partially_refunded / refunded — 'pending' and 'cancelled' are not money)
  --   * the door ran                                (venue.scan)
  --   * settlement accounting began for the event   (venue.settlement.event_id)
  -- Any one of those and the schedule is evidence, not a plan.
  --
  -- THE PLATFORM CONJUNCT, AND ITS REAL REACHABILITY — MEASURED, NOT ASSUMED.
  -- The `not kernel.is_platform(...)` test below is NOT a usable escape hatch on
  -- its own, and must not be described as one. This verb's authority arms
  -- (079:591-606) admit only org_owner / org_admin / org_marketing and
  -- venue_manager / venue_marketing; kernel.is_platform is not among them. A
  -- platform_admin holding no org or venue role is therefore refused EARLIER, at
  -- 079:603-606, and never reaches this block. Verified by execution:
  --   pure platform_admin           -> insufficient_privilege (the 079 arm)
  --   platform_admin + org_owner    -> ok
  -- So in practice, for an economically-weighted session, a backward move is
  -- REFUSED OUTRIGHT for every principal who can reach this verb — the
  -- fail-closed end of "refused, or restricted to platform authority".
  -- The conjunct is kept because it is correct, costs nothing, and becomes a
  -- real hatch the moment platform authority is added to this verb's arms.
  -- WIDENING THOSE ARMS IS DELIBERATELY NOT DONE HERE: it would change who may
  -- call a frozen 079 verb, which is a bigger decision than this fix, and a
  -- genuine data-entry correction still has the service_role / superuser path
  -- that every other break-glass repair uses. Flagged, not taken.
  --
  -- FAIL CLOSED: if the probe itself raises, v_econ is forced true and the move
  -- is refused. A move we cannot prove is safe is not safe.
  if v_new_ends is not null
     and ( (v_ends is not null and v_new_ends < v_ends)      -- moved EARLIER
        or (v_ends is null     and v_new_ends <= now()) )    -- newly set, ALREADY elapsed
  then
    if not kernel.is_platform(array['platform_admin']) then
      begin
        select exists (select 1 from kernel.tickets t
                        where t.event_session_id = p_session_id)
            or exists (select 1 from venue."order" o
                        where o.event_session_id = p_session_id
                          and o.status in ('paid','partially_refunded','refunded'))
            or exists (select 1 from venue.scan sc
                        where sc.event_session_id = p_session_id)
            or exists (select 1 from venue.settlement st
                        where st.event_id = v_event_id)
          into v_econ;
      exception when others then
        v_econ := true;                                  -- fail closed
      end;
      if v_econ is null or v_econ then
        raise exception 'precondition_failed: backward_schedule_move_frozen — this session carries economic weight (an issued atom, a paid order, a door scan or a settlement), so its schedule may not be moved earlier; contact the platform owner'
          using errcode = 'P0001';
      end if;
    end if;
    -- a backward move is audited with a MANDATORY reason code, exactly as the
    -- forward arm demands one once atoms exist (079:654-658).
    v_reason := p_patch ->> 'reason_code';
    if v_reason is null or length(trim(v_reason)) = 0 then
      raise exception 'precondition_failed: reason_required';
    end if;
  end if;
  -- ==== end 093 backward arm ===============================================

  if p_patch ? 'session_label' then
    update catalog.event_session
       set session_label = p_patch ->> 'session_label', updated_at = now()
     where session_id = p_session_id;
    v_changed := true;
  end if;
  if v_time_chg then
    update catalog.event_session
       set starts_at = v_new_starts, doors_at = v_new_doors, ends_at = v_new_ends,
           -- Δ-N1 (NOTIF Group E): bumped IN THIS TRANSACTION, under the row's
           -- FOR UPDATE, whenever starts/doors/ends change — never a patch key.
           session_version = session_version + 1,
           updated_at = now()
     where session_id = p_session_id;
    v_changed := true;
  end if;

  if not v_changed then
    return jsonb_build_object('status','noop_replay','session_id',p_session_id,
                              'effective_freeze_at', catalog.effective_freeze_at(p_session_id));
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'session.update', 'event_session', p_session_id,
          coalesce(nullif(trim(coalesce(p_patch ->> 'reason_code','')),''), 'self_service'),
          v_before,
          (select jsonb_build_object('session_label', s.session_label, 'starts_at', s.starts_at,
                                     'ends_at', s.ends_at, 'doors_at', s.doors_at,
                                     'session_version', s.session_version)
             from catalog.event_session s where s.session_id = p_session_id));

  -- the recomputed boundary is returned, so the operator sees the consequence
  -- of the edit in the same round trip rather than discovering it at the door.
  return jsonb_build_object('status','ok','session_id',p_session_id,
                            'effective_freeze_at', catalog.effective_freeze_at(p_session_id));
end;
$$;


-- ============================================================================
-- END PART 40
-- ============================================================================
