-- ============================================================================
-- 20261102160000_primary_fee_read_alignment_rollback.sql — rollback of registry 202 (pgTAP 271).
-- Restores the applied predecessors of the two bodies 202 replaces, and 182's COMMENT on get_primary_session:
--   public.get_primary_session(uuid)        202 ac639b649b510ef089ea55c3c70068fa -> 182 8915bf3df8acf0b00a0cfe7042c2f55e
--   catalog.publish_event(uuid,text,text)   202 f30eaca23ae71a33243e39a6c8c5a8fd -> e76 18e9624482acee10a68b0ae6a2af97c1
-- INVERSE MD5 GUARD: per function, a 202 md5 is restored, a predecessor md5 is left alone (rollback re-run = no-op),
-- anything else refuses naming the function and the md5 seen, with nothing changed. CREATE OR REPLACE only: no drop,
-- no CASCADE, no grant re-stated; the post-check proves the predecessor md5s, 182's comment and every captured
-- attribute (ACL, SECURITY DEFINER, search_path, owner, volatility) unchanged.
-- The bodies below are the predecessors' pg_get_functiondef text byte for byte (dumped from a clone of main 7496fee3).
-- ============================================================================
begin;
set local lock_timeout = '3s';

do $pf$
declare
  r      record;
  v_md5  text;
  v_n    integer;
  v_cap  jsonb := '[]'::jsonb;
begin
  for r in
    select * from (values
      ('public.get_primary_session(uuid)', 'public', 'get_primary_session', '8915bf3df8acf0b00a0cfe7042c2f55e', 'ac639b649b510ef089ea55c3c70068fa'),
      ('catalog.publish_event(uuid,text,text)', 'catalog', 'publish_event', '18e9624482acee10a68b0ae6a2af97c1', 'f30eaca23ae71a33243e39a6c8c5a8fd')
    ) as t(sig, nsp, name, pred, own)
  loop
    select count(*) into v_n
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = r.nsp and p.proname = r.name;
    if to_regprocedure(r.sig) is null or v_n <> 1 then
      raise exception 'ROLLBACK_202_REFUSED: % — expected exactly one %.% overload with this signature (overloads %); nothing changed',
        r.sig, r.nsp, r.name, v_n;
    end if;
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if v_md5 is distinct from r.own and v_md5 is distinct from r.pred then
      raise exception 'ROLLBACK_202_REFUSED: % has md5 %, which is neither 202''s body (%) nor the predecessor (%); nothing changed',
        r.sig, v_md5, r.own, r.pred;
    end if;
    v_cap := v_cap || jsonb_build_array((
      select jsonb_build_object('sig', r.sig, 'md5', v_md5, 'want', r.pred,
               'acl', coalesce(p.proacl::text, '<null>'), 'secdef', p.prosecdef,
               'cfg', coalesce(p.proconfig::text, '<null>'), 'owner', p.proowner::regrole::text,
               'vol', p.provolatile::text)
        from pg_proc p where p.oid = to_regprocedure(r.sig)));
  end loop;
  perform set_config('rollback_202.preflight', v_cap::text, true);
  raise notice '202 rollback pre-check: %',
    (select string_agg((e ->> 'sig') || '=' || left(e ->> 'md5', 8) || case when e ->> 'md5' = e ->> 'want' then ' (already the predecessor)' else ' (202 -> predecessor)' end, ', ')
       from jsonb_array_elements(v_cap) e);
end $pf$;

do $g$
begin
  if md5(pg_get_functiondef(to_regprocedure('public.get_primary_session(uuid)'))) = 'ac639b649b510ef089ea55c3c70068fa' then
    execute $body182$CREATE OR REPLACE FUNCTION public.get_primary_session(p_session_id uuid)
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
  -- the buyer service fee rate, read as venue.create_primary_checkout reads it
  -- (093:4091-4094: highest version wins, `#>> '{}'` maps the seeded JSON null
  -- to SQL NULL) and gated as it gates (093:4104-4112): any value checkout would
  -- refuse to quote on reads NULL here. pg_input_is_valid only turns checkout's
  -- 22P02 (non-numeric text) into NULL instead of an error (see the header).
  cross join lateral (
    select case when r.bps is null
                  or r.bps < 0 or r.bps > 10000 or r.bps <> trunc(r.bps) then null
                else r.bps
           end as bps
      from (select case when pg_input_is_valid(cfg.txt, 'numeric') then cfg.txt::numeric end as bps
              from (select (select c.value #>> '{}'
                              from catalog.platform_config c
                             where c.key = 'fee.buyer_service_bps'
                             order by c.version desc limit 1) as txt) cfg) r
  ) fee
 where s.session_id = p_session_id
   and e.status in ('on_sale', 'live', 'completed')
   and s.status <> 'cancelled'
   and v.approval_status = 'approved'
$function$
$body182$;
    raise notice '202 rollback: public.get_primary_session(uuid) restored to 182';
  else
    raise notice '202 rollback: public.get_primary_session(uuid) already carries its predecessor (no-op)';
  end if;
end $g$;

comment on function public.get_primary_session(uuid) is
  '182 (C1): buyer detail of one session — (session, event, venue, ticket_types) jsonb; ticket_types = public tiers only with price_minor, currency, visibility, display_rank, sale window, on_sale_now and remaining (= SUM(capacity-held-sold) over public_sale batches of this session; capacity/held/sold never returned). '
  'buyer_fee_minor / all_in_price_minor = what venue.create_primary_checkout charges for ONE unit of the tier (same rate read, gates and half-up rounding; the fee is rounded per order, so never multiply for n units); both NULL while fee.buyer_service_bps is unset or refused. '
  'Local times via catalog.venue.timezone (*_local, YYYY-MM-DD HH24:MI). ZERO rows (no error) for an unknown id, a draft/announced/cancelled event, a cancelled session or a non-approved venue. EXECUTE anon + authenticated.';

do $p$
begin
  if md5(pg_get_functiondef(to_regprocedure('catalog.publish_event(uuid,text,text)'))) = 'f30eaca23ae71a33243e39a6c8c5a8fd' then
    execute $body165$CREATE OR REPLACE FUNCTION catalog.publish_event(p_event_id uuid, p_target_status text, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid          uuid;
  v_org_id       uuid;
  v_venue        uuid;
  v_status       text;
  v_ok           boolean;
  -- 102 / A8a' SALEABLE gate scratch — declared here, used only inside the
  -- on_sale branch below.
  v_org_status   text;
  v_org_ref      text;
  v_org_ready    boolean;
  v_signing_key  uuid;
  v_fee_bps      numeric;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_target_status not in ('announced','on_sale','live','completed') then
    raise exception 'invalid_input: bad target_status % (cancellation is catalog.cancel_event)', p_target_status;
  end if;

  select e.org_id, e.venue_id, e.status into v_org_id, v_venue, v_status
    from catalog.event e where e.event_id = p_event_id for update;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;

  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              -- E-76 (165): a venue-role arm also requires the venue's CURRENT operator
              -- to be the event's org (088 cancel_event's conjunct, inlined; B's 187 shape).
              and exists (select 1 from catalog.venue v
                           where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- legal FORWARD transition only (draft→announced→on_sale→live→completed).
  v_ok := (v_status = 'draft'     and p_target_status = 'announced')
       or (v_status = 'announced' and p_target_status = 'on_sale')
       or (v_status = 'on_sale'   and p_target_status = 'live')
       or (v_status = 'live'      and p_target_status = 'completed');
  if not v_ok then
    raise exception 'precondition_failed: illegal_transition (% -> %)', v_status, p_target_status;
  end if;

  -- on_sale requires >=1 ticket_type WITH a batch — no empty on-sale.
  if p_target_status = 'on_sale' then
    if not exists (
      select 1 from venue.ticket_type tt
       join venue.inventory_batch b on b.ticket_type_id = tt.ticket_type_id
      where tt.event_id = p_event_id) then
      raise exception 'precondition_failed: empty_inventory';
    end if;

    -- ---- 102 / A8a' — SALEABLE STATIC GATE LADDER, IN ORDER ---------------

    -- 1. ORG NOT SUSPENDED/UNAPPROVED. Mirrors create_primary_checkout's G2a
    -- (093:3982-4021) character-for-character: a suspended or not-yet-
    -- approved org must not be able to open sales, for the identical reason
    -- checkout refuses it at quote time. X-12 restrictive: unknown authorizes
    -- NOTHING (null status, from a vanished org row, refuses too).
    select o.status, o.stripe_connect_account_ref, o.connect_transfers_active
      into v_org_status, v_org_ref, v_org_ready
      from kernel.organization o
     where o.org_id = v_org_id;
    if v_org_status is null or v_org_status not in ('approved','active') then
      raise exception 'precondition_failed: org_not_saleable — a % organization may not go on sale', coalesce(v_org_status,'missing');
    end if;

    -- 2. CONNECT NOT READY. Mirrors G2 (093:4023-4026): a bound ref with dead
    -- transfer capability is not ready, and a live-looking flag with no ref
    -- has nowhere to send money. Both operands required.
    if v_org_ref is null or coalesce(v_org_ready, false) is not true then
      raise exception 'precondition_failed: connect_not_ready';
    end if;

    -- 3. SIGNING NOT READY. The same resolver query shape as
    -- kernel.issue_ticket_atoms (093:4952-4966) and create_primary_checkout's
    -- G2b (093:4066-4074): most-specific-first, per_event -> per_venue ->
    -- global, active and in-window. A signer trust root must exist for this
    -- event BEFORE sales open — this does not provision one (the KMS
    -- ceremony is a separate, un-parked act this migration does not touch).
    select k.key_id into v_signing_key
      from kernel.signing_key k
     where k.status = 'active'
       and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
       and (   (k.scope = 'per_event' and k.event_id = p_event_id)
            or (k.scope = 'per_venue' and k.venue_id = v_venue)
            or (k.scope = 'global'))
     order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
     limit 1;
    if v_signing_key is null then
      raise exception 'precondition_failed: signing_not_ready — an active signing key must resolve for the event scope before it can go on sale';
    end if;

    -- 4. FEE POLICY UNSET. Mirrors A5 (093:4093-4105): fee.buyer_service_bps
    -- must never fall back to zero — a missing key reads the same as a null
    -- value and both refuse.
    select (c.value #>> '{}')::numeric into v_fee_bps
      from catalog.platform_config c
     where c.key = 'fee.buyer_service_bps'
     order by c.version desc limit 1;
    if v_fee_bps is null then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps has no value; this event cannot go on sale until the owner sets it';
    end if;

    -- ---- end 102 / A8a' SALEABLE gate ladder ------------------------------
  end if;

  update catalog.event set status = p_target_status, updated_at = now()
   where event_id = p_event_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.status', 'event', p_event_id, 'publish',
          jsonb_build_object('status', v_status), jsonb_build_object('status', p_target_status));

  return jsonb_build_object('status','ok','event_status',p_target_status);
end;
$function$
$body165$;
    raise notice '202 rollback: catalog.publish_event(uuid,text,text) restored to e76 (165)';
  else
    raise notice '202 rollback: catalog.publish_event(uuid,text,text) already carries its predecessor (no-op)';
  end if;
end $p$;

do $pc$
declare
  v_cap jsonb := nullif(current_setting('rollback_202.preflight', true), '')::jsonb;
  e     jsonb;
  q     record;
begin
  if v_cap is null or jsonb_array_length(v_cap) <> 2 then
    raise exception 'ROLLBACK_202_POSTCHECK_FAILED: the pre-check capture is missing — run this file as one transaction';
  end if;
  for e in select * from jsonb_array_elements(v_cap) loop
    select md5(pg_get_functiondef(p.oid)) as md5, coalesce(p.proacl::text, '<null>') as acl, p.prosecdef,
           coalesce(p.proconfig::text, '<null>') as cfg, p.proowner::regrole::text as owner, p.provolatile::text as vol,
           (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) as n
      into q from pg_proc p where p.oid = to_regprocedure(e ->> 'sig');
    if q.md5 is distinct from e ->> 'want' then
      raise exception 'ROLLBACK_202_POSTCHECK_FAILED: % md5 % is not the predecessor %', e ->> 'sig', coalesce(q.md5, '<absent>'), e ->> 'want';
    end if;
    if (q.acl, q.prosecdef, q.cfg, q.owner, q.vol) is distinct from
       (e ->> 'acl', (e ->> 'secdef')::boolean, e ->> 'cfg', e ->> 'owner', e ->> 'vol') or q.n <> 1 then
      raise exception 'ROLLBACK_202_POSTCHECK_FAILED: % posture changed (acl % -> %, secdef % -> %, cfg % -> %, owner % -> %, vol % -> %, overloads %)',
        e ->> 'sig', e ->> 'acl', q.acl, e ->> 'secdef', q.prosecdef, e ->> 'cfg', q.cfg, e ->> 'owner', q.owner, e ->> 'vol', q.vol, q.n;
    end if;
  end loop;
  if md5(obj_description(to_regprocedure('public.get_primary_session(uuid)'), 'pg_proc')) is distinct from 'eca448d6e66ef40949681f4f4905f5f2' then
    raise exception 'ROLLBACK_202_POSTCHECK_FAILED: the COMMENT on public.get_primary_session(uuid) is not 182''s';
  end if;
  raise notice '202 rollback post-check: % ok; 182 comment restored',
    (select string_agg((x ->> 'sig') || '=' || left(x ->> 'want', 8), ' ') from jsonb_array_elements(v_cap) x);
end $pc$;

commit;
