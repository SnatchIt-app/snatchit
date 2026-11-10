-- Preserve private events until they have a replacement access boundary.
begin;
set local lock_timeout = '3s';
lock table catalog.event in access exclusive mode;
do $rollback$
begin
  if md5(pg_get_functiondef(to_regprocedure('public.get_primary_session(uuid)'))) is distinct from 'b424bab2534c5fba04271b55490fffc4'
     or md5(pg_get_functiondef(to_regprocedure('public.list_primary_sessions_on_sale()'))) is distinct from '839f047c85a28de5f0c659fd011780aa'
     or md5(pg_get_functiondef(to_regprocedure('public.reserve_primary_tier(uuid,uuid,integer,text)'))) is distinct from 'c56a6af75c79193cb2657a5cafb5ad53' then
    raise exception 'precondition_failed: private pilot RPCs changed; rebase rollback';
  end if;
  if exists (select from catalog.event where private_pilot) then
    raise exception 'precondition_failed: preserve private pilot event access before rollback';
  end if;
end;
$rollback$;

CREATE OR REPLACE FUNCTION public.list_primary_sessions_on_sale()
 RETURNS TABLE(event_id uuid, session_id uuid, title text, venue_name text, neighborhood text, starts_at timestamp with time zone, doors_at timestamp with time zone, age_restriction text, status text, timezone text, starts_at_local text, doors_at_local text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select e.event_id,
         s.session_id,
         e.title,
         v.name          as venue_name,
         v.neighborhood,
         s.starts_at,
         s.doors_at,
         e.age_policy    as age_restriction,
         e.status,
         v.timezone,
         -- the get_primary_session session-object expression, verbatim
         to_char(s.starts_at at time zone v.timezone, 'YYYY-MM-DD HH24:MI') as starts_at_local,
         to_char(s.doors_at  at time zone v.timezone, 'YYYY-MM-DD HH24:MI') as doors_at_local
    from catalog.event_session s
    join catalog.event e on e.event_id = s.event_id
    join catalog.venue v on v.venue_id = e.venue_id
   where e.status in ('on_sale', 'live')
     and s.status not in ('cancelled', 'completed')
     and v.approval_status = 'approved'
     and exists (select 1
                   from venue.ticket_type tt
                  where tt.event_id = e.event_id
                    and tt.visibility = 'public'
                    and venue.ticket_type_on_sale(tt.ticket_type_id, now()))
   order by s.starts_at asc, s.session_id asc
$function$;

CREATE OR REPLACE FUNCTION public.get_primary_session(p_session_id uuid)
 RETURNS TABLE(session jsonb, event jsonb, venue jsonb, ticket_types jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    jsonb_build_object(
      'session_id',      s.session_id,
      'event_id',        s.event_id,
      'session_label',   s.session_label,
      'starts_at',       s.starts_at,
      'ends_at',         s.ends_at,
      'doors_at',        s.doors_at,
      'status',          s.status,
      'timezone',        v.timezone,
      'starts_at_local', to_char(s.starts_at at time zone v.timezone, 'YYYY-MM-DD HH24:MI'),
      'ends_at_local',   to_char(s.ends_at   at time zone v.timezone, 'YYYY-MM-DD HH24:MI'),
      'doors_at_local',  to_char(s.doors_at  at time zone v.timezone, 'YYYY-MM-DD HH24:MI')
    ) as session,
    jsonb_build_object(
      'event_id',        e.event_id,
      'title',           e.title,
      'description',     e.description,
      'hero_image_ref',  e.hero_image_ref,
      'category',        e.category,
      'genre_tags',      to_jsonb(e.genre_tags),
      'status',          e.status,
      'age_restriction', e.age_policy
    ) as event,
    jsonb_build_object(
      'venue_id',        v.venue_id,
      'name',            v.name,
      'neighborhood',    v.neighborhood,
      'address',         v.address,
      'timezone',        v.timezone
    ) as venue,
    coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'ticket_type_id', tt.ticket_type_id,
                 'name',           tt.name,
                 'price_minor',    tt.price_minor,
                 'currency',       tt.currency,
                 'visibility',     tt.visibility,
                 'display_rank',   tt.display_rank,
                 'sale_starts_at', tt.sale_starts_at,
                 'sale_ends_at',   tt.sale_ends_at,
                 'on_sale_now',    venue.ticket_type_on_sale(tt.ticket_type_id, now()),
                 -- buyer inventory of THIS session only: public_sale batches; the
                 -- 081 generated column `remaining` = capacity - held - sold, summed.
                 -- capacity / held / sold themselves are never serialised (E-29).
                 'remaining',      coalesce((select sum(b.capacity - b.held - b.sold)
                                              from venue.inventory_batch b
                                             where b.ticket_type_id   = tt.ticket_type_id
                                               and b.event_session_id = s.session_id
                                               and b.release_kind     = 'public_sale'), 0)::integer,
                 -- US all-in display: venue.create_primary_checkout's fee for a
                 -- ONE-UNIT order of this tier (093:4163-4164 with v_total =
                 -- price_minor); NULL while the rate is unset / refused (fee.bps NULL).
                 'buyer_fee_minor',    round(tt.price_minor::numeric * fee.bps / 10000)::integer,
                 'all_in_price_minor', tt.price_minor + round(tt.price_minor::numeric * fee.bps / 10000)::integer
               )
               order by tt.display_rank asc nulls last, tt.price_minor asc, tt.name asc)
        from venue.ticket_type tt
       where tt.event_id = e.event_id
         and tt.visibility = 'public'
    ), '[]'::jsonb) as ticket_types
  from catalog.event_session s
  join catalog.event e on e.event_id = s.event_id
  join catalog.venue v on v.venue_id = e.venue_id
  -- the buyer service fee rate, read and gated exactly as
  -- venue.create_primary_checkout reads and gates it since 188
  -- (20261027031000:362-371 and :391-399; restated here by registry 202):
  -- only the NEWEST version is picked, before anything is cast, so no older
  -- version is ever inspected; it prices only when it is a JSON number (JSON
  -- null, a missing key, a string such as "1000", a boolean or an object read
  -- NULL, where checkout refuses service_fee_unset) that is an integer
  -- 0..10000 (out of range or fractional reads NULL, where checkout refuses
  -- service_fee_out_of_range). A NULL rate makes buyer_fee_minor and
  -- all_in_price_minor NULL. No value raises here.
  cross join lateral (
    select case when r.bps is null
                  or r.bps < 0 or r.bps > 10000 or r.bps <> trunc(r.bps) then null
                else r.bps
           end as bps
      from (select case when jsonb_typeof(cfg.raw) = 'number' then (cfg.raw #>> '{}')::numeric end as bps
              from (select (select c.value
                              from catalog.platform_config c
                             where c.key = 'fee.buyer_service_bps'
                             order by c.version desc limit 1) as raw) cfg) r
  ) fee
 where s.session_id = p_session_id
   and e.status in ('on_sale', 'live', 'completed')
   and s.status <> 'cancelled'
   and v.approval_status = 'approved'
$function$;

CREATE OR REPLACE FUNCTION public.reserve_primary_tier(p_session_id uuid, p_ticket_type_id uuid, p_quantity integer, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_batch   uuid;
  v_res     jsonb;
  v_hold_id uuid;
  v_qty     integer;
  v_expires timestamptz;
begin
  -- the engine refuses a NULL uid itself (081:548-551); refusing it here FIRST
  -- keeps the not_found below from answering an unauthenticated caller.
  if auth.uid() is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;

  -- the server picks the batch: a public_sale batch of a PUBLIC tier of this
  -- session's event; the oldest with room for the quantity, else the oldest
  -- (the engine's oversell_rejected then answers under its row lock).
  select b.batch_id into v_batch
    from venue.inventory_batch b
    join venue.ticket_type tt     on tt.ticket_type_id = b.ticket_type_id
    join catalog.event_session s  on s.session_id = b.event_session_id
   where b.event_session_id = p_session_id
     and b.ticket_type_id   = p_ticket_type_id
     and b.release_kind     = 'public_sale'
     and tt.visibility      = 'public'
     and tt.event_id        = s.event_id
   order by (b.capacity - b.held - b.sold >= coalesce(p_quantity, 0)) desc,
            b.created_at asc, b.batch_id asc
   limit 1;
  if v_batch is null then
    raise exception 'not_found: no public_sale inventory for ticket type % on session %', p_ticket_type_id, p_session_id
      using errcode = 'P0002';
  end if;

  -- every decision (idempotency, flag, sale state, cap, TTL, oversell) is the
  -- engine's; no exception handler here, so its refusals reach the client as-is.
  v_res := venue.reserve_primary_inventory(v_batch, p_quantity, p_command_key);

  v_hold_id := (v_res ->> 'hold_id')::uuid;
  select h.quantity, h.expires_at into v_qty, v_expires
    from venue.inventory_hold h
   where h.hold_id = v_hold_id
     and h.identity_id = auth.uid();

  return jsonb_build_object('status',     v_res ->> 'status',
                            'hold_id',    v_hold_id,
                            'expires_at', v_expires,
                            'quantity',   v_qty);
end;
$function$;

alter policy catalog_event_sel_anon on catalog.event using (status <> 'draft');
alter table catalog.event drop column private_pilot;
commit;
