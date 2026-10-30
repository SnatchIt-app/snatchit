-- ============================================================================
-- supabase/rollbacks/20261027031000_primary_fee_read_hardening_rollback.sql
-- Rollback for registry 188 (20261027031000). Restores the APPLIED predecessor bodies VERBATIM (as
-- pg_get_functiondef printed them on the stacked clone): venue.create_primary_checkout = 093's (the rate
-- is again read with the cast before the LIMIT — plan-dependent pricing returns) and
-- catalog.set_platform_config = 102's (the first write of fee.buyer_service_bps /
-- inventory.per_user_active_hold_max again accepts any JSON type). Rolling 188 back re-opens exactly what
-- 188 closed and nothing older: no later hardening is reverted. Owner, ACLs, SECURITY DEFINER and
-- search_path are kept by CREATE OR REPLACE and asserted by the post-restore self-check; no data is touched
-- (a fee proposal parked while 188 was live stays parked; an accepted hold-max version stays in the history).
-- Guard: the pre-flight accepts, per function, only 188's body (rollback) or the predecessor (idempotent
-- re-run) and refuses anything else with nothing changed.
--   create_primary_checkout  188 77004331198b9dad2e51e1ed2ceaef35 -> predecessor a629b41216397da48f71a7c6cc4fd298
--   set_platform_config      188 2ece44b98c73af1e8c2b5d930b0a5895 -> predecessor d0aaada87856b8579f7e19fcd9934fbf
-- PINS: 252 F17 moves back to 22P02 (seq-scan plan) with the rollback.
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── PRE-FLIGHT (inverse of 188's guard): each body being restored over must be EXACTLY 188's (rollback) or
-- already the predecessor (idempotent re-run); anything else is a later change this rollback must not
-- destroy — refuse; nothing changes. ACLs captured for the post-restore self-check.
do $pf$
declare
  v_c text := md5(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)')));
  v_s text := md5(pg_get_functiondef(to_regprocedure('catalog.set_platform_config(text, jsonb, text, text)')));
begin
  if v_c is null or v_c not in ('77004331198b9dad2e51e1ed2ceaef35',   -- 188 body
                                'a629b41216397da48f71a7c6cc4fd298') then -- 093 body (already rolled back)
    raise exception 'precondition_failed: 188 rollback refuses to overwrite an unexpected venue.create_primary_checkout body (md5 %); nothing changed', coalesce(v_c, '<missing>');
  end if;
  if v_s is null or v_s not in ('2ece44b98c73af1e8c2b5d930b0a5895',   -- 188 body
                                'd0aaada87856b8579f7e19fcd9934fbf') then -- 102 body (already rolled back)
    raise exception 'precondition_failed: 188 rollback refuses to overwrite an unexpected catalog.set_platform_config body (md5 %); nothing changed', coalesce(v_s, '<missing>');
  end if;
  perform set_config('a188.acl_c', (select coalesce(proacl::text, '<default>') from pg_proc where oid = to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)')), true);
  perform set_config('a188.acl_s', (select coalesce(proacl::text, '<default>') from pg_proc where oid = to_regprocedure('catalog.set_platform_config(text, jsonb, text, text)')), true);
end $pf$;

-- ── venue.create_primary_checkout: the 093 body, verbatim
CREATE OR REPLACE FUNCTION venue.create_primary_checkout(p_session_id uuid, p_items jsonb, p_hold_ids uuid[], p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

-- ── catalog.set_platform_config: the 102 body, verbatim
CREATE OR REPLACE FUNCTION catalog.set_platform_config(p_key text, p_value jsonb, p_reason_code text, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- 102 / owner §21 — `signing.expected_key_fingerprint` and
  -- `signing.expected_max_not_after` ADDED (single-key, not a prefix — see the
  -- header note above for why signing.monitor_enabled is deliberately excluded).
  v_dual := p_key like 'refund.%' or p_key like 'payout.%' or p_key like 'authn.%'
         or p_key like 'comp.%'   or p_key like 'wallet.%' or p_key like 'credential.%'
         or p_key like 'door.session\_%' or p_key like 'fee.%'
         or p_key like 'deletion.%' or p_key like 'ticket.%'
         or p_key = 'signing.expected_key_fingerprint' or p_key = 'signing.expected_max_not_after';

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
    -- 102: signing.expected_key_fingerprint / signing.expected_max_not_after
    -- are DELIBERATELY ABSENT from this map. Neither has a corpus-declared
    -- restrictive direction (a fingerprint is not orderable at all; a
    -- ceiling timestamp has no stated policy for which direction is the
    -- tightening one), so both take §20.2.1's third arm and park in BOTH
    -- directions — arming or changing the trust root at all is the act that
    -- needs a second human, same posture as `ticket.%` above.
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
$function$;

-- ── POST-RESTORE SELF-CHECK: each body is EXACTLY its predecessor; definer, search_path and ACLs unchanged.
do $pc$
begin
  if md5(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'))) is distinct from 'a629b41216397da48f71a7c6cc4fd298' then
    raise exception 'precondition_failed: 188 rollback self-check — the restored venue.create_primary_checkout body is not the predecessor; this file was modified';
  end if;
  if md5(pg_get_functiondef(to_regprocedure('catalog.set_platform_config(text, jsonb, text, text)'))) is distinct from 'd0aaada87856b8579f7e19fcd9934fbf' then
    raise exception 'precondition_failed: 188 rollback self-check — the restored catalog.set_platform_config body is not the predecessor; this file was modified';
  end if;
  if exists (select 1 from pg_proc
              where oid in (to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)'), to_regprocedure('catalog.set_platform_config(text, jsonb, text, text)'))
                and (not prosecdef or proconfig is distinct from array['search_path=""']))
  or (select coalesce(proacl::text, '<default>') from pg_proc where oid = to_regprocedure('venue.create_primary_checkout(uuid, jsonb, uuid[], text)')) <> current_setting('a188.acl_c')
  or (select coalesce(proacl::text, '<default>') from pg_proc where oid = to_regprocedure('catalog.set_platform_config(text, jsonb, text, text)')) <> current_setting('a188.acl_s') then
    raise exception 'precondition_failed: 188 rollback self-check — SECURITY DEFINER, search_path or an EXECUTE ACL moved';
  end if;
end $pc$;

commit;
