-- ============================================================================
-- 20261027033000_primary_refund_record_and_reconciliation.sql — registry 189 / pgTAP 259 (A).
--
-- WHAT THIS MIGRATION IS. DRAFT / unapplied / undeployed. Two NEW functions in schema `ops`; nothing
-- existing is replaced, no table, no column, no public-schema object. Stacks on 188 (20261027031000) only
-- by order — it calls neither 188 function. Replay-safe: CREATE OR REPLACE behind a pre-flight that accepts
-- only ABSENCE (the predecessor) or this file's own bodies.
--
-- ── WHY (planning A/PRIMARY-REFUND-MANUAL-PATH-DESIGN.md; owner decision 2026-10-21: refunds stay manual,
-- no executor is enabled) ─────────────────────────────────────────────────────────────────────
-- kernel.refund_primary_order (085) is EXECUTE service_role only, yet authorizes by auth.uid()
-- (platform_admin / platform_support, or a delegated 'req:' key): the console cannot call it, and nothing
-- reconciles the kernel's refund record with what Stripe actually refunded. The stripe-webhook
-- charge.refunded branch records EVERY Stripe refund (Dashboard refunds and ticket payments included) into
-- public.payment_refund_state / public.payment_refunds keyed by public.payments.id, never voids a ticket
-- and never writes kernel.refund; kernel.payment_native links a finalized order to its payment.
--
-- ── WHAT ────────────────────────────────────────────────────────────────────────────────────
-- (a) ops.record_primary_refund(p_order_id uuid, p_amount_minor integer, p_reason_code text,
--     p_command_key text) RETURNS jsonb — SECURITY DEFINER, search_path '', VOLATILE, EXECUTE authenticated
--     only. ops.assert_role(platform_admin | platform_support) — the 115 assert behind the console's money
--     actions: an operator role AND an aal2 session (aal1 -> step_up_required, no aal claim ->
--     step_up_unavailable) — then ops.assert_actions_enabled() (118's pause switch). The console key shape
--     (8-80 of [A-Za-z0-9._:-], ops.execute_action's); a 'req:' key is refused (that is the kernel's
--     dual-control DELEGATED arm; this records DIRECT refunds only). Then
--     kernel.refund_primary_order(...) is returned as is: auth.uid() is preserved inside a definer, so the
--     kernel's own platform / support-cap / pending-request / over-refund / custody / freeze / idempotency
--     rules apply unchanged; a FULL refund voids every voidable atom (the door then refuses them) and writes
--     kernel.refund with an empty stripe_refund_ref. This function writes nothing else. The owner then
--     refunds the PaymentIntent in the Stripe Dashboard by hand.
-- (b) ops.primary_reconciliation(p_from date default null, p_to date default null) RETURNS jsonb — STABLE
--     (read-only: a write raises), SECURITY DEFINER, search_path '', EXECUTE authenticated only, under
--     ops.assert_reader(). One row per finalized native payment (kernel.payment_native with an order;
--     window = linked_at, UTC days, NULL bound open): order status, tickets issued / voided / admitted /
--     live, kernel.refund sum (status <> failed), Stripe-recorded refunds (succeeded; open =
--     pending|requires_action) from public.payment_refund_state, payments.total, stripe_livemode, a state
--     (attention | refund_awaiting_stripe | refund_settled | ok) and attention items:
--       (i)   stripe_refunded_tickets_live  CRITICAL — Stripe refunded but tickets are still live (the door
--             would admit), unless the order is partially_refunded with a kernel sum >= Stripe's;
--       (ii)  kernel_refund_without_stripe — kernel refunds older than 24 h exceed every refund Stripe
--             recorded (succeeded or open);
--       (iii) refund_amount_mismatch — Stripe's succeeded sum <> the kernel sum (Stripe > 0);
--       (iv)  issuance_missing — linked more than 15 min ago with no atom ever issued; issuance_over — an
--             order item with more issued|active|scanned atoms than its quantity (the schema allows it:
--             ownership_log_cause_uq is (cause, cause_ref, ticket_atom_id); only the mint's replay check
--             prevents a second issuance).
--     ops.is_test_payment (DC-1, registry 180) is NOT on this tree: no dependency is added.
--
-- ── GRANTS / FOUR-FILE RULE ──────────────────────────────────────────────────────────────────
-- Both objects live in `ops`. The CI gates read `public` only (assert_public_table_grant_decisions.sql,
-- the Gate-2 census, expected_grants.txt): no manifest row, no census move, no expected_grants line
-- (measured before/after on the stacked clone). EXECUTE: REVOKE ALL FROM PUBLIC, anon, authenticated,
-- service_role; GRANT EXECUTE TO authenticated — asserted by the post-apply self-check.
--
-- ── MD5 — md5(pg_get_functiondef(...)) ──────────────────────────────────────────────────────
--   ops.record_primary_refund(uuid, integer, text, text)  predecessor ABSENT   189 337a8f19d11a482e47437eb968dab40b
--   ops.primary_reconciliation(date, date)                predecessor ABSENT   189 046dfce98f9e6714bb46a87e896e7763
-- No predecessor body exists, so there is no strip rule: the pre-flight proves absence instead.
--
-- ROLLBACK: supabase/rollbacks/20261027033000_primary_refund_record_and_reconciliation_rollback.sql drops
-- both (inverse guard: only 189's bodies; refuses while any function or view calls either).
-- VERIFICATION (after apply):
--   select md5(pg_get_functiondef(to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)')));  -- 337a8f19d11a482e47437eb968dab40b
--   select md5(pg_get_functiondef(to_regprocedure('ops.primary_reconciliation(date, date)')));                -- 046dfce98f9e6714bb46a87e896e7763
--   select ops.primary_reconciliation();   -- as an operator with aal2
-- LOCKS / RUNTIME: CREATE FUNCTION + GRANT/COMMENT only; no data read or written; lock_timeout 3s.
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── PRE-FLIGHT (stacking guard): each function must be ABSENT (first apply — its predecessor is absence) or
-- EXACTLY this migration's body (idempotent re-apply), and no other overload of either name may exist.
-- Anything else is someone else's object that CREATE OR REPLACE would silently overwrite — refuse; the
-- single transaction then changes nothing. The two callees are asserted present and SECURITY DEFINER.
do $pf$
declare
  v_r text := md5(pg_get_functiondef(to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)')));
  v_q text := md5(pg_get_functiondef(to_regprocedure('ops.primary_reconciliation(date, date)')));
begin
  if v_r is not null and v_r <> '337a8f19d11a482e47437eb968dab40b' then
    raise exception 'precondition_failed: 189 refuses to overwrite an unexpected ops.record_primary_refund body (md5 %); nothing changed', v_r;
  end if;
  if v_q is not null and v_q <> '046dfce98f9e6714bb46a87e896e7763' then
    raise exception 'precondition_failed: 189 refuses to overwrite an unexpected ops.primary_reconciliation body (md5 %); nothing changed', v_q;
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'ops' and p.proname in ('record_primary_refund', 'primary_reconciliation')
                and p.oid not in (coalesce(to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)')::oid, 0::oid), coalesce(to_regprocedure('ops.primary_reconciliation(date, date)')::oid, 0::oid))) then
    raise exception 'precondition_failed: 189 — another overload of ops.record_primary_refund / ops.primary_reconciliation exists; nothing changed';
  end if;
  if not coalesce((select prosecdef from pg_proc where oid = to_regprocedure('kernel.refund_primary_order(uuid, integer, text, text)')), false)
  or not coalesce((select prosecdef from pg_proc where oid = to_regprocedure('ops.assert_role(text[])')), false)
  or not coalesce((select prosecdef from pg_proc where oid = to_regprocedure('ops.assert_reader()')), false)
  or not coalesce((select prosecdef from pg_proc where oid = to_regprocedure('ops.assert_actions_enabled()')), false) then
    raise exception 'precondition_failed: 189 needs kernel.refund_primary_order (085), ops.assert_role / ops.assert_reader (115) and ops.assert_actions_enabled (118); nothing changed';
  end if;
end $pf$;

-- ── ops.record_primary_refund (new)
CREATE OR REPLACE FUNCTION ops.record_primary_refund(p_order_id uuid, p_amount_minor integer, p_reason_code text, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- 189 (A, 2026-10-27): the console's MANUAL refund record for a primary (ticket) order. Refunds stay
-- manual (owner decision 2026-10-21; no executor is enabled): this voids the order's tickets and writes
-- the kernel.refund row; the owner then refunds the PaymentIntent in the Stripe Dashboard by hand, and
-- the stripe-webhook charge.refunded branch records that refund in public.payment_refund_state, where
-- ops.primary_reconciliation pairs the two.
begin
  -- The console's step-up and role check — the same 115 asserts its money actions use:
  -- ops.assert_role -> ops.assert_reader (an operator role and an aal2 session; aal1 ->
  -- step_up_required, no aal claim -> step_up_unavailable), narrowed to the two platform roles
  -- kernel.refund_primary_order's DIRECT arm accepts. Then 118's console pause switch.
  perform ops.assert_role(array['platform_admin', 'platform_support']);
  perform ops.assert_actions_enabled();
  -- The console's idempotency-key shape (ops.execute_action). A 'req:<request id>' key is the
  -- kernel's DELEGATED dual-control arm (definer -> definer from an approved request, or the refund
  -- edge); this action records a DIRECT refund only and never consumes an approved request.
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{8,80}$' then
    raise exception 'invalid_input: command key must be 8-80 chars of [A-Za-z0-9._:-]';
  end if;
  if p_command_key like 'req:%' then
    raise exception 'invalid_input: a req: key is the dual-control delegated arm; this action records a direct refund only';
  end if;
  -- auth.uid() is the caller inside this definer, so the kernel's own rules apply unchanged:
  -- platform_admin / platform_support (support capped by refund.platform_support_max_minor on the
  -- cumulative operand, pending refund requests included), paid / partially_refunded orders only, the
  -- native payment link, the over-refund guard, a FULL refund voids every voidable atom (listed,
  -- transferred or frozen atoms refuse), a partial refunds money only, idempotent on the command key,
  -- kernel.admin_audit written as the caller. Its result is returned as is; nothing else is written.
  return kernel.refund_primary_order(p_order_id, p_amount_minor, p_reason_code, p_command_key);
end;
$function$;

-- ── ops.primary_reconciliation (new)
CREATE OR REPLACE FUNCTION ops.primary_reconciliation(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- 189 (A, 2026-10-27): primary (ticket) money vs tickets, one row per FINALIZED native payment
-- (kernel.payment_native with an order — written by venue.finalize_primary_order in the same
-- transaction that mints the atoms). Read-only (STABLE: a write raises). Window: linked_at, UTC
-- calendar days; a NULL bound is open on that side (the default reads every linked payment).
--   tickets   atoms whose sequence-1 ownership-log cause_ref is one of the order's items — the
--             linkage finalize / refund_primary_order / admin_refund use. live = issued|active (the
--             door can still admit), admitted = scanned, voided = voided.
--   kernel    kernel.refund rows of the payment, status <> 'failed' (refund_primary_order's own sum).
--   stripe    public.payment_refund_state of the payment (every Stripe refund the webhook saw,
--             Dashboard refunds included): succeeded, and open = pending|requires_action.
-- Attention items:
--   (i)   stripe_refunded_tickets_live  CRITICAL  Stripe refunded money but tickets are still live
--         (the door would still admit) — unless the kernel recorded a deliberate partial refund
--         (order partially_refunded) covering at least Stripe's amount.
--   (ii)  kernel_refund_without_stripe            kernel refunds older than 24 h exceed every refund
--         Stripe recorded (succeeded or open): the manual Stripe step was not done.
--   (iii) refund_amount_mismatch                  Stripe's succeeded sum <> the kernel sum (Stripe has
--         refunded something; a kernel refund with nothing in Stripe yet is (ii)'s, after 24 h).
--   (iv)  issuance_missing                        linked more than 15 min ago and no atom ever issued.
--         issuance_over                           an order item carries more issued|active|scanned
--                                                 atoms than its quantity (a second issuance).
-- ops.is_test_payment (DC-1) is not on this tree: no test-data filter; stripe_livemode is returned.
declare
  lo     timestamptz;
  hi     timestamptz;
  v_rows jsonb;
  v_att  jsonb;
begin
  -- the console's reader gate: an operator role and an aal2 session (115)
  perform ops.assert_reader();
  if p_from is not null and p_to is not null and p_from > p_to then
    raise exception 'invalid_input: from must not be after to';
  end if;
  lo := (p_from::timestamp) at time zone 'UTC';
  hi := ((p_to + 1)::timestamp) at time zone 'UTC';

  with pn as (
    select x.payment_id, x.order_id, x.linked_at
      from kernel.payment_native x
     where x.order_id is not null
       and (lo is null or x.linked_at >= lo)
       and (hi is null or x.linked_at <  hi)
  ),
  item as (
    select oi.order_id, oi.id as item_id, oi.quantity,
           count(t.ticket_atom_id)::integer                                                  as issued,
           count(t.ticket_atom_id) filter (where t.state = 'voided')::integer                  as voided,
           count(t.ticket_atom_id) filter (where t.state = 'scanned')::integer                 as admitted,
           count(t.ticket_atom_id) filter (where t.state in ('issued', 'active'))::integer     as live,
           count(t.ticket_atom_id) filter (where t.state in ('issued', 'active', 'scanned'))::integer as held_or_used
      from venue.order_item oi
      left join kernel.ticket_ownership_log l1 on l1.cause_ref = oi.id and l1.sequence = 1
      left join kernel.tickets t on t.ticket_atom_id = l1.ticket_atom_id
     where oi.order_id in (select pn.order_id from pn)
     group by oi.order_id, oi.id, oi.quantity
  ),
  ord as (
    select i.order_id,
           sum(i.issued)::integer as issued, sum(i.voided)::integer as voided,
           sum(i.admitted)::integer as admitted, sum(i.live)::integer as live,
           bool_or(i.held_or_used > i.quantity) as over
      from item i
     group by i.order_id
  ),
  kr as (
    select r.payment_id,
           sum(r.amount_minor)::bigint as minor,
           coalesce(sum(r.amount_minor) filter (where r.created_at <= now() - interval '24 hours'), 0)::bigint as aged,
           count(*)::integer as n
      from kernel.refund r
     where r.status <> 'failed'
       and r.payment_id in (select pn.payment_id from pn)
     group by r.payment_id
  ),
  sr as (
    select s.payment_id,
           coalesce(sum(s.amount_cents) filter (where s.status = 'succeeded'), 0)::bigint as ok,
           coalesce(sum(s.amount_cents) filter (where s.status in ('pending', 'requires_action')), 0)::bigint as open
      from public.payment_refund_state s
     where s.payment_id in (select pn.payment_id from pn)
     group by s.payment_id
  ),
  r as (
    select pn.payment_id, pn.order_id, pn.linked_at,
           p.status as payment_status, p.total as payment_total_minor, p.stripe_livemode,
           o.status as order_status, o.total_minor as order_total_minor,
           coalesce(ord.issued, 0) as issued, coalesce(ord.voided, 0) as voided,
           coalesce(ord.admitted, 0) as admitted, coalesce(ord.live, 0) as live,
           coalesce(ord.over, false) as over,
           coalesce(kr.minor, 0) as k_minor, coalesce(kr.aged, 0) as k_aged, coalesce(kr.n, 0) as k_n,
           coalesce(sr.ok, 0) as s_ok, coalesce(sr.open, 0) as s_open
      from pn
      join public.payments p on p.id = pn.payment_id
      join venue."order" o on o.order_id = pn.order_id
      left join ord on ord.order_id = pn.order_id
      left join kr on kr.payment_id = pn.payment_id
      left join sr on sr.payment_id = pn.payment_id
  ),
  a as (
    select r.*,
           array_remove(array[
             -- (i) CRITICAL: Stripe refunded, the door would still admit
             case when r.s_ok > 0 and r.live > 0
                   and not (r.order_status = 'partially_refunded' and r.s_ok <= r.k_minor)
                  then 'stripe_refunded_tickets_live' end,
             -- (ii) a kernel refund with no matching Stripe refund after 24 h
             case when r.k_aged > r.s_ok + r.s_open then 'kernel_refund_without_stripe' end,
             -- (iii) the kernel sum and Stripe's succeeded sum disagree
             case when r.s_ok > 0 and r.s_ok <> r.k_minor then 'refund_amount_mismatch' end,
             -- (iv) exactly-one issuance: none after 15 min, or more than the item's quantity
             case when r.issued = 0 and r.linked_at <= now() - interval '15 minutes' then 'issuance_missing' end,
             case when r.over then 'issuance_over' end
           ]::text[], null) as codes
      from r
  ),
  att as (
    select a.payment_id, a.order_id, a.linked_at, c.code, c.n
      from a, unnest(a.codes) with ordinality as c(code, n)
  )
  select (select coalesce(jsonb_agg(jsonb_build_object(
                   'payment_id', a.payment_id, 'order_id', a.order_id, 'linked_at', a.linked_at,
                   'payment_status', a.payment_status, 'payment_total_minor', a.payment_total_minor,
                   'stripe_livemode', a.stripe_livemode,
                   'order_status', a.order_status, 'order_total_minor', a.order_total_minor,
                   'tickets_issued', a.issued, 'tickets_voided', a.voided,
                   'tickets_admitted', a.admitted, 'tickets_live', a.live,
                   'kernel_refund_minor', a.k_minor, 'kernel_refund_count', a.k_n,
                   'stripe_refund_succeeded_minor', a.s_ok, 'stripe_refund_open_minor', a.s_open,
                   'state', case when cardinality(a.codes) > 0 then 'attention'
                                 when a.k_minor > a.s_ok then 'refund_awaiting_stripe'
                                 when a.s_ok > 0 then 'refund_settled'
                                 else 'ok' end,
                   'attention', to_jsonb(a.codes))
                 order by a.linked_at desc, a.payment_id), '[]'::jsonb)
            from a),
         (select coalesce(jsonb_agg(jsonb_build_object(
                   'code', att.code,
                   'severity', case when att.code = 'stripe_refunded_tickets_live' then 'critical' else 'warning' end,
                   'payment_id', att.payment_id, 'order_id', att.order_id,
                   'message', case att.code
                     when 'stripe_refunded_tickets_live' then 'Stripe shows a succeeded refund but tickets of this order are still live: the door would still admit them. Record the refund (it voids them) or confirm a deliberate partial.'
                     when 'kernel_refund_without_stripe' then 'A refund recorded here more than 24 h ago has no matching refund in Stripe: refund the PaymentIntent in the Stripe Dashboard.'
                     when 'refund_amount_mismatch'       then 'The refunds recorded here and the refunds Stripe shows as succeeded differ in amount.'
                     when 'issuance_missing'             then 'Paid and linked more than 15 minutes ago, but no ticket was ever issued for this order.'
                     when 'issuance_over'                then 'An order item carries more tickets than its quantity.'
                   end)
                 order by (att.code <> 'stripe_refunded_tickets_live'), att.linked_at desc, att.payment_id, att.n), '[]'::jsonb)
            from att)
    into v_rows, v_att;

  return jsonb_build_object(
    'from', p_from, 'to', p_to, 'computed_at', now(), 'currency', 'USD',
    'basis', 'kernel.payment_native.linked_at, UTC calendar day; a NULL bound is open',
    'count', jsonb_array_length(v_rows),
    'attention_count', jsonb_array_length(v_att),
    'critical_count', (select count(*) from jsonb_array_elements(v_att) e where e ->> 'severity' = 'critical'),
    'rows', v_rows,
    'attention', v_att);
end;
$function$;

-- EXECUTE: authenticated only (the console's session). Every other role is refused, PUBLIC included.
revoke all on function ops.record_primary_refund(uuid, integer, text, text) from public, anon, authenticated, service_role;
grant execute on function ops.record_primary_refund(uuid, integer, text, text) to authenticated;
revoke all on function ops.primary_reconciliation(date, date) from public, anon, authenticated, service_role;
grant execute on function ops.primary_reconciliation(date, date) to authenticated;

comment on function ops.record_primary_refund(uuid, integer, text, text) is
  '189: console MANUAL refund record for a primary order — ops.assert_role(platform_admin|platform_support) at aal2 + the console pause switch, then kernel.refund_primary_order as the caller (full refund voids the tickets; kernel.refund written with no Stripe ref). The owner refunds in the Stripe Dashboard by hand; ops.primary_reconciliation pairs the two.';
comment on function ops.primary_reconciliation(date, date) is
  '189: read-only primary reconciliation under ops.assert_reader — per finalized native payment: order status, tickets issued/voided/admitted/live, kernel.refund sum, Stripe-recorded refunds (succeeded/open), payments.total; attention items (i) stripe_refunded_tickets_live CRITICAL, (ii) kernel_refund_without_stripe (24 h), (iii) refund_amount_mismatch, (iv) issuance_missing (15 min) / issuance_over.';

-- ── POST-APPLY SELF-CHECK: each body just written must be EXACTLY this migration's (a modified copy of this
-- file would pass the pre-flight as a "re-apply"; this makes it fail its own transaction); SECURITY DEFINER,
-- search_path='', the volatility and the authenticated-only EXECUTE must be as written.
do $pc$
begin
  if md5(pg_get_functiondef(to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'))) is distinct from '337a8f19d11a482e47437eb968dab40b'
  or md5(pg_get_functiondef(to_regprocedure('ops.primary_reconciliation(date, date)'))) is distinct from '046dfce98f9e6714bb46a87e896e7763' then
    raise exception 'precondition_failed: 189 self-check — a written body is not this migration''s; this file was modified';
  end if;
  if exists (select 1 from pg_proc
              where oid in (to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'), to_regprocedure('ops.primary_reconciliation(date, date)'))
                and (not prosecdef or proconfig is distinct from array['search_path=""']))
  or (select provolatile from pg_proc where oid = to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)')) <> 'v'
  or (select provolatile from pg_proc where oid = to_regprocedure('ops.primary_reconciliation(date, date)')) <> 's' then
    raise exception 'precondition_failed: 189 self-check — SECURITY DEFINER, search_path or volatility is not as written';
  end if;
  if not has_function_privilege('authenticated', to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'), 'EXECUTE')
  or not has_function_privilege('authenticated', to_regprocedure('ops.primary_reconciliation(date, date)'), 'EXECUTE')
  or has_function_privilege('anon', to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'), 'EXECUTE')
  or has_function_privilege('anon', to_regprocedure('ops.primary_reconciliation(date, date)'), 'EXECUTE')
  or has_function_privilege('service_role', to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'), 'EXECUTE')
  or has_function_privilege('service_role', to_regprocedure('ops.primary_reconciliation(date, date)'), 'EXECUTE')
  or exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              where p.oid in (to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)'), to_regprocedure('ops.primary_reconciliation(date, date)')) and a.grantee = 0) then
    raise exception 'precondition_failed: 189 self-check — EXECUTE is not authenticated-only';
  end if;
end $pc$;

commit;
