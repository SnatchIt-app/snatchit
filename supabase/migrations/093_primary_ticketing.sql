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
-- REPLACEMENTS that add a missing authority conjunct. 0 DDL on any money-ledger
-- table. 2 new columns, both on kernel.organization, both additive.
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
--   10h  kernel.settlement_royalty_lines  body-only  — A5 (the chargeback arm
--                                                      double-debited refunded
--                                                      money and charged the
--                                                      platform's own fee to the
--                                                      venue); royalty arm verbatim
--
--   OWNER STOP RAISED BY THIS PART. 10d refuses to release organization money
--   while 'settlement.refund_window_interval' is unset, because NO settle-after-
--   refund-window policy exists anywhere in the corpus and this schema has no
--   receivable object to carry a post-close refund forward. The key row is NOT
--   created here — it belongs with the other config rows in slice 40, seeded
--   'null'::jsonb / 'restricted' in the retention.backup_window_days pattern.
--   093 invents no duration and no anchor instant.
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
--   (2) THE PAYOUT IS MINTED HELD WHILE THE REFUND WINDOW IS UNSET — the fix for
--       the post-close refund. The full argument is at the call site below.
--
--   (3) THE INT4 CEILING RAISES A NAMED REFUSAL instead of a bare 22003 that
--       wedged the header open with zero lines forever. Also at the call site.
--
--   PRESERVED VERBATIM: the FOR UPDATE header read, the E-76 authority arm
--   (087:299-302), the noop_replay arm, the per-candidate currency raise, the
--   whole-settlement currency check, the E-73 waterfall derivation (087:329-333,
--   byte for byte), the write-once money UPDATE, the net > 0 mint condition and
--   its idempotency_key, the audit row, and the net_minor READ-BACK (§10.2 R1-2).
--   RULING A4 IS UNTOUCHED: the ONLY hold this function writes is on the payout it
--   mints itself, cause='settlement', payee_kind='organization'. It reads no
--   promoter row, writes no promoter_commission payout, and releases nothing.
-- ============================================================================
create or replace function kernel.close_settlement(p_settlement_id uuid, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_s venue.settlement%rowtype; v_c kernel.settlement_line_candidate;
  v_gross bigint; v_fees bigint; v_refunds bigint; v_net bigint;
  v_payout_id uuid; v_ids uuid[] := '{}';
  v_refund_window interval; v_held boolean := false;
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
    -- (2) THE UNBOUNDED-REFUND-EXPOSURE GATE. A refund that succeeds AFTER this
    -- close cannot be collected: its debit lands in a settlement nobody opens, or
    -- in one that nets negative — and a negative net mints no payout and creates
    -- no receivable, because this schema has no carry-forward object. Bounding
    -- that exposure needs a settle-after-refund-window policy, and NO SUCH POLICY
    -- EXISTS anywhere in the corpus. 093 therefore does not pay: while
    -- 'settlement.refund_window_interval' is unset, the payout is MINTED (so the
    -- obligation is a durable ledger fact — ruling A3: the debt must be knowable
    -- without reconstructing it from Stripe) but MINTED HELD, so no money can move.
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
    -- READ AS THE HOUSE PATTERN: absent row, JSON null and unparseable value all
    -- collapse to NULL and therefore to the hold (the 081:630-639 idiom). NOTE
    -- WELL — the key's PRESENCE is not an implementation of the window. This gate
    -- is binary by design because the duration and the instant it runs from are
    -- owner policy and 093 invents neither. The verb that actually enforces a
    -- window must land WITH that ruling; setting this key before it exists would
    -- switch the protection off without replacing it.
    begin
      v_refund_window := (select (c.value #>> '{}')::interval
                            from catalog.platform_config c
                           where c.key = 'settlement.refund_window_interval'
                           order by c.version desc limit 1);
    exception when others then v_refund_window := null;
    end;
    v_held := v_refund_window is null;
    insert into kernel.payout (payee_kind, payee_org_id, cause, cause_ref, amount_minor, currency, status, idempotency_key,
                               hold_state, hold_reason_code, held_by, held_at)
    values ('organization', v_s.org_id, 'settlement', p_settlement_id, v_net::integer, v_s.currency, 'pending',
            'settlement:' || p_settlement_id::text,
            case when v_held then 'held' else 'none' end,
            case when v_held then 'unbounded_refund_exposure' else null end,
            null,
            case when v_held then now() else null end)
    on conflict (idempotency_key) do nothing
    returning payout_id into v_payout_id;
    if v_payout_id is not null then v_ids := array[v_payout_id]; end if;
  end if;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code)
  values (auth.uid(), 'settlement.close', 'settlement', p_settlement_id, coalesce(p_command_key,'close'));
  -- net_minor is a READ-BACK of the column this function wrote (§10.2 R1-2), never a local.
  -- 'payout_hold' is ADDITIVE — every contracted key (status, payout_ids,
  -- net_minor) keeps its meaning; callers that do not read it are unaffected.
  return jsonb_build_object('status','ok','payout_ids', v_ids,
           'net_minor', (select net_minor from venue.settlement where settlement_id = p_settlement_id),
           'payout_hold', case when v_held then 'unbounded_refund_exposure' else null end);
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
--   §3  checkout readiness gate, UNCONDITIONAL ............ A8  (scope item 7)
--       + the buyer-side service fee, fail-closed ......... A5  (part 40's
--         `fee.buyer_service_bps`, whose only possible reader this is)
--   §4  kernel.set_org_connect_ref — hardened ............. A7/A9 (item 8)
--   §5  kernel.set_org_payout_destination — hardened ...... A7/A9 (item 9)
--   §6  kernel.get_org_connect_state — read, HUMANS ........ A7  (F §3.5 G5)
--   §7  kernel.get_org_connect_ref — read, MACHINES ........ A7  (F §3.4)
--
-- §6 and §7 are the two objects here that are NOT in the 093 scope list. Both
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
  v_org_ref   text;
  v_org_ready boolean;
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
  select e.status, s.status, e.org_id
    into v_evt_status, v_sess_status, v_org_id
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
  select o.stripe_connect_account_ref, o.connect_transfers_active
    into v_org_ref, v_org_ready
    from kernel.organization o
   where o.org_id = v_org_id;
  if v_org_ref is null or coalesce(v_org_ready, false) is not true then
    -- X-12 restrictive reading: absent or unknown state authorizes NOTHING.
    raise exception 'precondition_failed: payout_not_ready';
  end if;
  -- ---- end A8 / G2 ---------------------------------------------------------

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
-- DUAL CONTROL: none of these prefixes is dual-controlled. The setter's
-- prefix test is
--     v_dual := p_key like 'refund.%' or p_key like 'payout.%' or p_key like
--               'authn.%' or p_key like 'comp.%' or p_key like 'wallet.%' or
--               p_key like 'credential.%' or p_key like 'door.session\_%';
-- at 078:1145-1147. `ticket.%`, `inventory.%`, `fee.%` and `settlement.%` match
-- none of them, so each later set_platform_config call is a SINGLE
-- platform_admin write with no approval round. For three of these rows that is
-- the property that makes seeding them absent safe — the owner can fill them in
-- without a migration. For settlement.refund_window_interval it is the OPPOSITE:
-- it is what makes setting it dangerous, because nobody has to countersign.
-- See that row's caveat.
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

  -- ---- settlement.refund_window_interval — THE KEY WHOSE *SETTING* IS THE ----
  -- ---- DANGEROUS ACT. READ THE CAVEAT BEFORE YOU TOUCH THIS ONE. ------------
  --
  -- Routed here so slice 40 and the money slice do not both write the row. The
  -- READER is kernel.close_settlement in
  -- docs/phase2/_impl/093_parts/10_money_settlement.sql (the lookup at 10:647,
  -- the hold at 10:653-657). Spelling verified against that reader; the name
  -- follows inventory.hold_ttl_interval.
  --
  -- WHAT IT GATES, which is NOT the obvious thing. A refund that succeeds AFTER
  -- its settlement has closed is never collected: the venue is paid face value,
  -- the buyer is refunded, and the debit exists NOWHERE in the ledger,
  -- permanently. Measured by the red team over five closes: lifetime net 8400
  -- against 19000 actually paid out. **093 CREATED this exposure** by activating
  -- the credit side — pre-093 gross was structurally zero, so there was no payout
  -- to overpay.
  --
  -- HOW IT IS CLOSED TODAY: while this key is unset, close_settlement mints the
  -- settlement payout HELD — hold_state='held',
  -- hold_reason_code='unbounded_refund_exposure' (10:657). The ledger still
  -- records the full truth and the obligation still exists; only the MONEY is
  -- immobilised. That is a deliberate fail-closed posture, not a bug.
  --
  -- ####################################################################
  -- ##  THE CAVEAT — THE PRESENCE OF THIS KEY IS NOT AN IMPLEMENTATION
  -- ##  OF THE REFUND WINDOW. THE GATE IS BINARY.
  -- ##
  -- ##  Both the DURATION and the INSTANT IT RUNS FROM are policy that has
  -- ##  NEVER BEEN RULED. Nothing in the corpus states either.
  -- ##
  -- ##  Setting this key before a verb exists that actually ENFORCES a window
  -- ##  switches the protection OFF WITHOUT REPLACING IT — it converts a
  -- ##  fail-closed hold into an unguarded payout. Whoever sets it MUST FIRST
  -- ##  CONFIRM THAT ENFORCEMENT EXISTS.
  -- ##
  -- ##  This is the THIRD and MOST DANGEROUS of the train's owner STOPs.
  -- ##  Unlike the other two — ticket.expiry_grace (leaving it unset is the
  -- ##  harm) and fee.buyer_service_bps (leaving it unset merely blocks
  -- ##  selling) — here SETTING THE VALUE IS THE HARMFUL ACTION and leaving
  -- ##  it null is the safe one. Do not "finish the config" by filling it in.
  -- ####################################################################
  --
  -- AND THERE IS NO SECOND HUMAN IN THE WAY, which is exactly why the caveat
  -- matters: 'settlement.%' matches NONE of the dual-control prefixes at
  -- 078:1145-1147 (refund. / payout. / authn. / comp. / wallet. / credential. /
  -- door.session_) — verified by evaluating that predicate against this key
  -- name. So a later set_platform_config call is a SINGLE platform_admin write
  -- with no approval round and no second pair of eyes. One person, one
  -- statement, and the hold is gone.
  ('settlement.refund_window_interval',       1, 'null'::jsonb,       'restricted')   -- SETTING THIS IS THE DANGEROUS ACT — read the caveat above

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
-- END PART 40
-- ============================================================================
