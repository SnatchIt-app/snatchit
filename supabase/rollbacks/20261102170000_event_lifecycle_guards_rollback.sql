-- ============================================================================
-- 20261102170000_event_lifecycle_guards_rollback.sql — registry 203 / pgTAP 272.
-- Restores the applied predecessor bodies byte for byte:
--   catalog.cancel_event(uuid, text, text)           088 PART 7         md5 dfb5b3eb3dfeca2d96f54e30a097f0e6
--   catalog.update_event_session(uuid, jsonb, text)  20261027020000     md5 27945260de23bb1889eef5091d48bbad
-- INVERSE GUARD: each body must be 203's (b23e3dc88e9bb1a3e9c1b84c8626e0f4 / 8b84fb6007d3ee1bb0fb9e488e6d4e41) — restored — or
-- already its predecessor's — no change (a second rollback is a no-op). Anything else is refused:
--   ROLLBACK_203_REFUSED: <sig> md5 <seen> is neither 203's nor its predecessor's; nothing changed
-- No CASCADE, no grant, no drop. create or replace keeps owner, ACL, SECURITY DEFINER, proconfig and
-- comment; the post-check compares each with the capture taken before the restore.
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── CAPTURE: owner / ACL / SECURITY DEFINER / proconfig / comment before the restore
create temp table r203_snap on commit drop as
  select s.sig, p.proowner, p.proacl::text as acl, p.prosecdef, p.proconfig::text as cfg,
         obj_description(p.oid, 'pg_proc') as cmt
    from (values ('catalog.cancel_event(uuid,text,text)'),
                 ('catalog.update_event_session(uuid,jsonb,text)')) as s(sig)
    left join pg_proc p on p.oid = to_regprocedure(s.sig);

-- ── INVERSE GUARD
do $pre$
declare r record; v_md5 text;
begin
  for r in select * from (values
    ('catalog.cancel_event(uuid,text,text)',           'b23e3dc88e9bb1a3e9c1b84c8626e0f4', 'dfb5b3eb3dfeca2d96f54e30a097f0e6'),
    ('catalog.update_event_session(uuid,jsonb,text)',  '8b84fb6007d3ee1bb0fb9e488e6d4e41', '27945260de23bb1889eef5091d48bbad')
  ) as t(sig, own, pred) loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if v_md5 is null or v_md5 not in (r.own, r.pred) then
      raise exception 'ROLLBACK_203_REFUSED: % md5 % is neither 203''s (%) nor its predecessor''s (%); nothing changed',
        r.sig, coalesce(v_md5, '<absent>'), r.own, r.pred;
    end if;
    if v_md5 = r.pred then
      raise notice '203 rollback: % already carries its predecessor (no change)', r.sig;
    end if;
  end loop;
end $pre$;

-- catalog.cancel_event(uuid, text, text) — 088 PART 7, verbatim
create or replace function catalog.cancel_event(p_event_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid(); v_e catalog.event%rowtype; v_s record; v_a record; v_r record; v_ms record; v_atom uuid;
  v_voided integer := 0; v_refunds integer := 0; v_skipped integer := 0; v_refund_id uuid; v_prior bigint; v_total bigint; v_amt bigint; v_res jsonb;
begin
  if v_uid is null then raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501'; end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: command_key must be 1-64 chars of [A-Za-z0-9._:-] (it lands in the immutable audit)';
  end if;
  if p_reason_code is not null and p_reason_code !~ '^[A-Za-z0-9._:-]{1,64}$' then
    raise exception 'invalid_input: reason_code must be 1-64 chars of [A-Za-z0-9._:-]';
  end if;
  select * into v_e from catalog.event e where e.event_id = p_event_id;
  if not found then raise exception 'not_found: event %', p_event_id using errcode = 'P0002'; end if;
  -- E-76: a venue-role arm also requires the venue's CURRENT operator to be the event's org.
  if not (kernel.has_org_role(v_e.org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_e.venue_id, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_e.venue_id and v.org_id = v_e.org_id))
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only' using errcode = '42501';
  end if;
  select * into v_e from catalog.event e where e.event_id = p_event_id for update;              -- rank 1
  for v_s in select es.session_id from catalog.event_session es where es.event_id = p_event_id order by es.session_id for update loop
    perform 1 from venue.inventory_batch b where b.event_session_id = v_s.session_id for update;   -- rank 2 (Inventory before Atom — §14.2)
    -- market drain (reason event_cancelled) — every open native machine on the session (rank 4 → 5).
    for v_r in select p.transfer_id, p.ticket_atom_id from market.p2p_transfer p join kernel.tickets t on t.ticket_atom_id = p.ticket_atom_id
                where t.event_session_id = v_s.session_id and p.status = 'initiated' order by p.ticket_atom_id for update of p loop
      update market.p2p_transfer set status = 'cancelled', reason_code = 'event_cancelled', updated_at = now() where transfer_id = v_r.transfer_id;
      perform kernel.unlock_ticket(v_r.ticket_atom_id, p_command_key || ':t:' || v_r.transfer_id::text);
    end loop;
    for v_r in select l.listing_id, l.ticket_atom_id from market.listing_native l join kernel.tickets t on t.ticket_atom_id = l.ticket_atom_id
                where t.event_session_id = v_s.session_id and l.status in ('active','reserved') order by l.ticket_atom_id for update of l loop
      update market.listing_native set status = 'cancelled', reason_code = 'event_cancelled', updated_at = now() where listing_id = v_r.listing_id;
      update market.offer set status = 'withdrawn', updated_at = now() where listing_id = v_r.listing_id and status = 'pending';
      update market.auction set status = 'cancelled', updated_at = now() where listing_id = v_r.listing_id and status = 'active';
      perform kernel.unlock_ticket(v_r.ticket_atom_id, p_command_key || ':l:' || v_r.listing_id::text);
    end loop;
    -- RESALE BUYERS FIRST: every PAID, untransferred native sale on the session gets its refund
    -- intent under the payment lock (rank 6) BEFORE the void, so the C26 hook can compensate
    -- (compensated ⇔ the buyer's money carries a refund — never a stranded 'compensated').
    for v_ms in select ms.sale_id, ms.payment_id, ms.price_minor from market.market_sale ms join kernel.tickets t on t.ticket_atom_id = ms.ticket_atom_id
                 where t.event_session_id = v_s.session_id and ms.sale_state = 'paid_pending_transfer' and ms.terminal_state = 'pending' and ms.payment_id is not null
                 order by ms.sale_id for update of ms loop
      perform 1 from public.payments p where p.id = v_ms.payment_id for update;
      select p.total into v_total from public.payments p where p.id = v_ms.payment_id;
      select coalesce(sum(r.amount_minor), 0) + coalesce((select sum(d.amount_minor) from kernel.dispute_native d
                                                            where d.payment_id = v_ms.payment_id and d.status in ('lost','charge_refunded')), 0)
        into v_prior from kernel.refund r where r.payment_id = v_ms.payment_id and r.status <> 'failed';
      v_amt := least(v_ms.price_minor::bigint, greatest(v_total - v_prior, 0));
      if v_amt > 0 then
        insert into kernel.refund (payment_id, reason_code, amount_minor, currency, idempotency_key)
        values (v_ms.payment_id, 'event_cancelled', v_amt, 'USD', p_command_key || ':sale:' || v_ms.sale_id::text)
        on conflict (idempotency_key) do nothing
        returning refund_id into v_refund_id;
        if v_refund_id is not null then
          v_refunds := v_refunds + 1;
          perform notify.emit_event_required('refund_requested', 'refund', v_refund_id, 'refund_requested:' || v_refund_id::text,
                    jsonb_build_object('event_id', p_event_id, 'sale_id', v_ms.sale_id, 'amount_minor', v_amt, 'reason', 'event_cancelled'));
        end if;
      end if;
    end loop;
    -- RESOLD ATOMS: an atom acquired through a COMPLETED native sale refunds the LATEST such sale's
    -- PAYER (the last money-in for this atom — the reseller already received proceeds; the
    -- royalty/proceeds clawback is NATIVE_RESALE_SPLIT_POLICY (10)), never the originating order.
    -- Void first (rank 5), refund row after under the payment lock (rank 6), id fixed up front.
    for v_ms in
      select ms.sale_id, ms.payment_id, ms.price_minor, ms.ticket_atom_id
        from market.market_sale ms join kernel.tickets t on t.ticket_atom_id = ms.ticket_atom_id
       where t.event_session_id = v_s.session_id and t.state in ('issued','active')
         and ms.terminal_state = 'completed' and ms.payment_id is not null
         and ms.created_at = (select max(x.created_at) from market.market_sale x where x.ticket_atom_id = ms.ticket_atom_id and x.terminal_state = 'completed')
       order by ms.ticket_atom_id loop
      select r.refund_id into v_refund_id from kernel.refund r
       where r.idempotency_key = p_command_key || ':sale:' || v_ms.sale_id::text and r.payment_id = v_ms.payment_id;
      if v_refund_id is null then
        select p.total into v_total from public.payments p where p.id = v_ms.payment_id;
        select coalesce(sum(r.amount_minor), 0) + coalesce((select sum(d.amount_minor) from kernel.dispute_native d
                                                              where d.payment_id = v_ms.payment_id and d.status in ('lost','charge_refunded')), 0)
          into v_prior from kernel.refund r where r.payment_id = v_ms.payment_id and r.status <> 'failed';
        v_amt := least(v_ms.price_minor::bigint, greatest(v_total - v_prior, 0));
        if v_amt <= 0 then
          v_skipped := v_skipped + 1;
          insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
          values (v_uid, 'event.cancel_skip', 'market_sale', v_ms.sale_id, 'money_already_returned',
                  jsonb_build_object('event_id', p_event_id, 'atom_id', v_ms.ticket_atom_id, 'prior_minor', v_prior, 'total_minor', v_total));
          continue;
        end if;
        v_refund_id := gen_random_uuid();
      else
        v_amt := 0;
      end if;
      v_res := kernel.void_ticket_atom(v_ms.ticket_atom_id, v_refund_id, p_command_key);            -- rank 5
      if coalesce(v_res ->> 'status', '') = 'ok' then v_voided := v_voided + 1; end if;
      if v_amt > 0 then
        perform 1 from public.payments p where p.id = v_ms.payment_id for update;                 -- rank 6
        select p.total into v_total from public.payments p where p.id = v_ms.payment_id;
        select coalesce(sum(r.amount_minor), 0) + coalesce((select sum(d.amount_minor) from kernel.dispute_native d
                                                              where d.payment_id = v_ms.payment_id and d.status in ('lost','charge_refunded')), 0)
          into v_prior from kernel.refund r where r.payment_id = v_ms.payment_id and r.status <> 'failed';
        if v_amt > greatest(v_total - v_prior, 0) then
          raise exception 'precondition_failed: refund_sum_guard — payment % headroom changed concurrently (retry)', v_ms.payment_id;
        end if;
        insert into kernel.refund (refund_id, payment_id, reason_code, amount_minor, currency, idempotency_key)
        values (v_refund_id, v_ms.payment_id, 'event_cancelled', v_amt, 'USD', p_command_key || ':sale:' || v_ms.sale_id::text);
        v_refunds := v_refunds + 1;
        perform notify.emit_event_required('refund_requested', 'refund', v_refund_id, 'refund_requested:' || v_refund_id::text,
                  jsonb_build_object('event_id', p_event_id, 'sale_id', v_ms.sale_id, 'amount_minor', v_amt, 'reason', 'event_cancelled'));
      end if;
    end loop;
    -- PRIMARY ORDERS: one refund per originating order (amount = Σ voided item prices, §11.4-guarded
    -- against prior refunds AND lost/charge_refunded disputes, operand = the payment's total).
    -- Atoms that were RESOLD (a completed native sale) are the arm above's, never this one's.
    -- The refund id is fixed BEFORE the voids and the row is inserted AFTER them (Atom 5 → Refund 6).
    for v_r in
      select o.order_id, pn.payment_id, pn.currency,
             array_agg(t.ticket_atom_id order by t.ticket_atom_id) as atoms, sum(oi.unit_price_minor)::bigint as amount
        from kernel.tickets t
        join kernel.ticket_ownership_log l1 on l1.ticket_atom_id = t.ticket_atom_id and l1.sequence = 1 and l1.cause = 'issue'
        join venue.order_item oi on oi.id = l1.cause_ref
        join venue."order" o on o.order_id = oi.order_id
        join kernel.payment_native pn on pn.order_id = o.order_id
       where t.event_session_id = v_s.session_id and t.state in ('issued','active')
         and not exists (select 1 from market.market_sale x where x.ticket_atom_id = t.ticket_atom_id and x.terminal_state = 'completed' and x.payment_id is not null)
       group by o.order_id, pn.payment_id, pn.currency
       order by o.order_id loop
      select r.refund_id into v_refund_id from kernel.refund r
       where r.idempotency_key = p_command_key || ':order:' || v_r.order_id::text and r.payment_id = v_r.payment_id;
      if v_refund_id is null then
        -- pre-void read of the guard (the re-check under the payment lock follows the voids)
        select p.total into v_total from public.payments p where p.id = v_r.payment_id;
        select coalesce(sum(r.amount_minor), 0) + coalesce((select sum(d.amount_minor) from kernel.dispute_native d
                                                              where d.payment_id = v_r.payment_id and d.status in ('lost','charge_refunded')), 0)
          into v_prior from kernel.refund r where r.payment_id = v_r.payment_id and r.status <> 'failed';
        v_amt := least(v_r.amount, greatest(v_total - v_prior, 0));
        if v_amt <= 0 then
          -- the money already went back (refunds and/or a chargeback): nothing to refund, so no void
          -- rides a refund that does not exist — skipped + audited (the held/disputed atom stays as it is).
          v_skipped := v_skipped + coalesce(array_length(v_r.atoms, 1), 0);
          insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
          values (v_uid, 'event.cancel_skip', 'order', v_r.order_id, 'money_already_returned',
                  jsonb_build_object('event_id', p_event_id, 'atoms', to_jsonb(v_r.atoms), 'prior_minor', v_prior, 'total_minor', v_total));
          continue;
        end if;
        v_refund_id := gen_random_uuid();
      else
        v_amt := 0;   -- replay: the refund row already exists; only re-void what is still live
      end if;
      foreach v_atom in array v_r.atoms loop
        v_res := kernel.void_ticket_atom(v_atom, v_refund_id, p_command_key);                  -- rank 5 → hook → ledger → head
        if coalesce(v_res ->> 'status', '') = 'ok' then v_voided := v_voided + 1; end if;
      end loop;
      if v_amt > 0 then
        perform 1 from public.payments p where p.id = v_r.payment_id for update;                 -- rank 6: the guard re-checked under the lock
        select p.total into v_total from public.payments p where p.id = v_r.payment_id;
        select coalesce(sum(r.amount_minor), 0) + coalesce((select sum(d.amount_minor) from kernel.dispute_native d
                                                              where d.payment_id = v_r.payment_id and d.status in ('lost','charge_refunded')), 0)
          into v_prior from kernel.refund r where r.payment_id = v_r.payment_id and r.status <> 'failed';
        if v_amt > greatest(v_total - v_prior, 0) then
          raise exception 'precondition_failed: refund_sum_guard — payment % headroom changed concurrently (retry)', v_r.payment_id;
        end if;
        insert into kernel.refund (refund_id, payment_id, reason_code, amount_minor, currency, idempotency_key)
        values (v_refund_id, v_r.payment_id, 'event_cancelled', v_amt, coalesce(v_r.currency,'USD'), p_command_key || ':order:' || v_r.order_id::text);
        v_refunds := v_refunds + 1;
        perform notify.emit_event_required('refund_requested', 'refund', v_refund_id, 'refund_requested:' || v_refund_id::text,
                  jsonb_build_object('event_id', p_event_id, 'order_id', v_r.order_id, 'amount_minor', v_amt, 'reason', 'event_cancelled'));
      end if;
    end loop;
    -- atoms with no refund lineage (comp / import): not voided, alerted (E-102).
    for v_a in select t.ticket_atom_id from kernel.tickets t
                where t.event_session_id = v_s.session_id and t.state in ('issued','active')
                  and not exists (select 1 from kernel.ticket_ownership_log l1 join venue.order_item oi on oi.id = l1.cause_ref
                                   where l1.ticket_atom_id = t.ticket_atom_id and l1.sequence = 1 and l1.cause = 'issue')
                order by t.ticket_atom_id loop
      v_skipped := v_skipped + 1;
      if not exists (select 1 from kernel.admin_audit a where a.subject_id = v_a.ticket_atom_id and a.action = 'event.cancel_skip' and a.reason_code = 'no_refund_lineage') then
        insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, after)
        values (v_uid, 'event.cancel_skip', 'ticket_atom', v_a.ticket_atom_id, 'no_refund_lineage', jsonb_build_object('event_id', p_event_id));
      end if;
    end loop;
    update catalog.event_session set status = 'cancelled', updated_at = now() where session_id = v_s.session_id and status <> 'cancelled';
  end loop;
  if v_e.status = 'cancelled' and v_voided = 0 and v_refunds = 0 then
    return jsonb_build_object('status','noop_replay','event_id', p_event_id,'atoms_voided', 0,'refunds_created', 0);
  end if;
  update catalog.event set status = 'cancelled', updated_at = now() where event_id = p_event_id and status <> 'cancelled';
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.cancel', 'event', p_event_id, coalesce(p_reason_code,'event_cancelled'),
          jsonb_build_object('status', v_e.status),
          jsonb_build_object('status','cancelled','atoms_voided', v_voided,'refunds_created', v_refunds,'atoms_skipped', v_skipped));
  if v_e.status <> 'cancelled' then
    perform notify.emit_event_required('event_cancelled', 'event', p_event_id, 'event_cancelled:' || p_event_id::text,
              jsonb_build_object('reason_code', coalesce(p_reason_code,'event_cancelled'), 'atoms_voided', v_voided));
  end if;
  return jsonb_build_object('status','ok','event_id', p_event_id,'atoms_voided', v_voided,'refunds_created', v_refunds,'atoms_skipped', v_skipped);
end;
$$;

-- catalog.update_event_session(uuid, jsonb, text) — 20261027020000 (registry 165), verbatim
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
           else array['venue_manager'] end)
      -- E-76 (165): a venue-role arm also requires the venue's CURRENT operator
      -- to be the event's org (088 cancel_event's conjunct, inlined; B's 187 shape).
      and exists (select 1 from catalog.venue v
                   where v.venue_id = v_venue_id and v.org_id = v_org_id);
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

-- ── POST-CHECK: predecessor md5s; posture equal to the capture
do $post$
declare r record; v_md5 text;
begin
  for r in select * from (values
    ('catalog.cancel_event(uuid,text,text)',           'dfb5b3eb3dfeca2d96f54e30a097f0e6'),
    ('catalog.update_event_session(uuid,jsonb,text)',  '27945260de23bb1889eef5091d48bbad')
  ) as t(sig, expected) loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if v_md5 is distinct from r.expected then
      raise exception 'ROLLBACK_203_FAILED: % md5 % is not the predecessor %', r.sig, coalesce(v_md5, '<absent>'), r.expected;
    end if;
  end loop;
  -- owner, ACL, SECURITY DEFINER, proconfig and comment equal the capture taken before the replace
  for r in
    select s.sig, s.proowner as o0, p.proowner as o1, s.acl as a0, p.proacl::text as a1,
           s.prosecdef as d0, p.prosecdef as d1, s.cfg as c0, p.proconfig::text as c1,
           s.cmt as m0, obj_description(p.oid, 'pg_proc') as m1
      from r203_snap s left join pg_proc p on p.oid = to_regprocedure(s.sig)
  loop
    if r.o0 is distinct from r.o1 or r.a0 is distinct from r.a1 or r.d0 is distinct from r.d1
       or r.c0 is distinct from r.c1 or r.m0 is distinct from r.m1 then
      raise exception 'ROLLBACK_203_FAILED: % posture changed (owner %->%, acl %->%, definer %->%, config %->%)',
        r.sig, r.o0, r.o1, r.a0, r.a1, r.d0, r.d1, r.c0, r.c1;
    end if;
    if r.d1 is distinct from true or r.c1 is distinct from '{"search_path=\"\""}' then
      raise exception 'ROLLBACK_203_FAILED: % is no longer SECURITY DEFINER with search_path = '''' (definer %, config %)',
        r.sig, r.d1, r.c1;
    end if;
  end loop;
end $post$;

commit;
