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
