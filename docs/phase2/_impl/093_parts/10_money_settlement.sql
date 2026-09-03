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
