-- ============================================================================
-- 20261102160000_primary_fee_read_alignment.sql — registry 202 / pgTAP 271.
-- D writes and owns; A allocated the number and decided the semantics (cluster DB-3 of
-- D/TRACE-CONTRACTS-20261102.md: no owner decision, align to the 188 ruling); E reviews. REPO-ONLY: applied
-- nowhere by this branch, no production change.
--
-- WHAT THIS GUARANTEES — every reader of catalog.platform_config 'fee.buyer_service_bps' uses the SAME read and
-- validity predicate as venue.create_primary_checkout after registry 188
-- (20261027031000_primary_fee_read_hardening.sql:362-371 and :391-399):
--   read      the NEWEST version only, picked in a LIMIT subquery before anything is cast, so no older version
--             is ever inspected and the result does not depend on the plan;
--   validity  it must be a JSON number (JSON null, a missing key, a string such as "1000", a boolean, an object
--             or an array are not), and an integer 0..10000 (0 is valid: checkout quotes a zero fee on it).
-- Readers at main 7496fee3 (git grep 'fee.buyer_service_bps' over supabase/migrations and supabase/functions;
-- the last definer of each function):
--   venue.create_primary_checkout (188)            the reference; NOT touched here.
--   public.get_primary_session(uuid) (182, primary_buyer_reads.sql:406-503) — the buyer all-in display. It
--             already took the newest version first, but read the value as TEXT and accepted any text pg_input_is_valid
--             passes as numeric, so a newest JSON string "1000" priced every tier while checkout refused it
--             (service_fee_unset). Now: a value that is not a JSON number reads NULL, so buyer_fee_minor and
--             all_in_price_minor are NULL — the response shape the function already uses for an unset rate
--             (same keys, same types; the consumer shows "Not on sale yet" and offers no purchase). The range and
--             integer gate and the half-up amount are unchanged. Its in-body comment, which still described 093's
--             read, and its COMMENT are restated.
--   catalog.publish_event(uuid,text,text) (e76, 20261027020000:726-735) — SALEABLE gate 4. It cast inside an
--             ordered LIMIT 1 target list (on a seq-scan plan every version is cast before the LIMIT, so one old
--             non-numeric version raised a raw 22P02) and refused only NULL, so 10001, 7.5 and "750" were accepted.
--             Now it refuses exactly when checkout refuses: newest null or missing, not a JSON number, fractional,
--             < 0 or > 10000. Every refusal keeps the prefix 'precondition_failed: fee_policy_unset' (the venue
--             dashboard's refusalToken maps it); the null text is unchanged, the two new cases append a reason:
--               'precondition_failed: fee_policy_unset — fee.buyer_service_bps is a JSON <type>, not a number; this
--                event cannot go on sale until the owner sets an integer'
--               'precondition_failed: fee_policy_unset — fee.buyer_service_bps must be an integer 0..10000, got <v>;
--                this event cannot go on sale until the owner corrects it'
--             The ladder order is unchanged (fee is still the last gate, after org, Connect and signing).
--   public.list_primary_sessions_on_sale(), the 167 buyer verbs (20261027015500) and the primary-checkout edge
--             read no fee value (the edge maps checkout's refusal codes only): nothing to align.
--
-- WHAT CHANGES — body-only CREATE OR REPLACE of the two functions above; same signatures, owner, ACL, SECURITY
-- DEFINER, search_path '' and volatility (the post-flight proves each unchanged against the pre-flight's own
-- capture), plus COMMENT ON FUNCTION public.get_primary_session. Every other byte of both bodies equals the applied
-- predecessor (per-line diff: D/s17-202/pred_vs_new.diff). No table, row, grant or config value is touched.
--
-- MD5 — md5(pg_get_functiondef(...)) measured on a local PG17 clone of the main 7496fee3 chain:
--   signature                                  applied predecessor                202
--   public.get_primary_session(uuid)           8915bf3df8acf0b00a0cfe7042c2f55e   ac639b649b510ef089ea55c3c70068fa
--   catalog.publish_event(uuid,text,text)      18e9624482acee10a68b0ae6a2af97c1   f30eaca23ae71a33243e39a6c8c5a8fd
-- The pre-flight accepts exactly {predecessor, 202} per function and refuses anything else, naming the function and
-- the md5 seen; a 202 md5 means already applied and that install block is a no-op (idempotent re-apply).
-- The alignment target is checked too: the pre-flight refuses unless venue.create_primary_checkout still carries
-- 188's newest-first read, its JSON-number test and its range gate (a text check, not an md5 pin, so the open
-- registry 198 — which replaces checkout and keeps that fee block byte for byte — does not order 202 behind it).
--
-- DOWNSTREAM. (1) 182's rollback md5-asserts get_primary_session's 182 body and e76's rollback asserts
-- publish_event's 165 body: roll back 202 first. (2) pgTAP 232 A4 pinned publish_event's prosrc md5 (165's body);
-- it moves with this file. (3) The open registries that replace these bodies (DB-1/DB-2 on 182, DB-2(c)/DB-5/DB-6 on
-- publish_event) must be regenerated over 202's bodies and pin 202's md5s.
-- OWNER NOTE (unchanged by this file): the money-config GO writes fee.buyer_service_bps as the JSON integer 1000,
-- never the string "1000"; set_platform_config (188 block V) already refuses the string.
--
-- GRANTS / FOUR-FILE RULE: CREATE OR REPLACE keeps every grant; none is re-stated. get_primary_session is in
-- `public` but no grant moves: its grant-decision manifest row ('anon-execute') and expected_grants (tables only)
-- are unchanged, Gate-2 +0 (dated note in ci.yml).
-- LOCKS / RUNTIME: CREATE OR REPLACE FUNCTION and COMMENT only; no table or row is read or written; lock_timeout 3s.
-- ROLLBACK: supabase/rollbacks/20261102160000_primary_fee_read_alignment_rollback.sql
-- restores both applied predecessors and 182's COMMENT under an inverse md5 guard (no CASCADE, no drop).
-- TESTS: supabase/tests/271_primary_fee_read_alignment.sql.
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── PRE-FLIGHT: classify each live body, refuse anything unknown, capture the posture the post-flight compares.
-- to_regprocedure, never a '...'::regprocedure literal (the literal is resolved at plan time, even when absent).
do $pf$
declare
  r      record;
  v_md5  text;
  v_n    integer;
  v_src  text;
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
      raise exception 'MIGRATION_202_REFUSED: % — expected exactly one %.% overload with this signature (overloads %, signature %); nothing changed',
        r.sig, r.nsp, r.name, v_n, case when to_regprocedure(r.sig) is null then 'absent' else 'present' end;
    end if;
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if v_md5 is distinct from r.pred and v_md5 is distinct from r.own then
      raise exception 'MIGRATION_202_REFUSED: % has md5 %, which is neither the applied predecessor (%) nor 202''s own body (%); nothing changed',
        r.sig, v_md5, r.pred, r.own;
    end if;
    v_cap := v_cap || jsonb_build_array((
      select jsonb_build_object('sig', r.sig, 'md5', v_md5, 'want', r.own,
               'acl', coalesce(p.proacl::text, '<null>'), 'secdef', p.prosecdef,
               'cfg', coalesce(p.proconfig::text, '<null>'), 'owner', p.proowner::regrole::text,
               'vol', p.provolatile::text)
        from pg_proc p where p.oid = to_regprocedure(r.sig)));
  end loop;
  -- the alignment target: checkout's fee read and gates as 188 wrote them (relied on, not replaced)
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'venue' and p.proname = 'create_primary_checkout';
  v_src := pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid,jsonb,uuid[],text)'));
  if v_n <> 1 or v_src is null
     or strpos(v_src, E'  select l.value into v_fee_raw\n    from (select c.value\n            from catalog.platform_config c\n           where c.key = ''fee.buyer_service_bps''\n           order by c.version desc\n           limit 1) l;\n  if jsonb_typeof(v_fee_raw) not in (''number'', ''null'') then\n') = 0
     or strpos(v_src, E'  v_fee_bps := case when jsonb_typeof(v_fee_raw) = ''number'' then (v_fee_raw #>> ''{}'')::numeric end;\n') = 0
     or strpos(v_src, E'  if v_fee_bps < 0 or v_fee_bps > 10000 or v_fee_bps <> trunc(v_fee_bps) then\n    raise exception ''precondition_failed: service_fee_out_of_range') = 0 then
    raise exception 'MIGRATION_202_REFUSED: venue.create_primary_checkout(uuid,jsonb,uuid[],text) (overloads %) no longer carries 188''s fee read and gates (md5 %); the alignment target moved — re-derive 202; nothing changed',
      v_n, coalesce(md5(v_src), '<absent>');
  end if;
  perform set_config('migration_202.preflight', v_cap::text, true);
  perform set_config('migration_202.checkout_md5', md5(v_src), true);
  raise notice '202 pre-flight: %; checkout fee block present (checkout md5 %)',
    (select string_agg((e ->> 'sig') || '=' || left(e ->> 'md5', 8) || case when e ->> 'md5' = e ->> 'want' then ' (202 already)' else ' (predecessor)' end, ', ')
       from jsonb_array_elements(v_cap) e), left(md5(v_src), 8);
end $pf$;

-- ── G public.get_primary_session(uuid): the fee lateral reads the newest jsonb value and prices only a JSON number
do $g$
begin
  if md5(pg_get_functiondef(to_regprocedure('public.get_primary_session(uuid)'))) = '8915bf3df8acf0b00a0cfe7042c2f55e' then
    execute $body202$CREATE OR REPLACE FUNCTION public.get_primary_session(p_session_id uuid)
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
$function$
$body202$;
    raise notice '202: public.get_primary_session(uuid) replaced';
  else
    raise notice '202: public.get_primary_session(uuid) already carries 202''s body (re-apply, unchanged)';
  end if;
end $g$;

comment on function public.get_primary_session(uuid) is
  '182 (C1): buyer detail of one session — (session, event, venue, ticket_types) jsonb; ticket_types = public tiers only with price_minor, currency, visibility, display_rank, sale window, on_sale_now and remaining (= SUM(capacity-held-sold) over public_sale batches of this session; capacity/held/sold never returned). '
  'buyer_fee_minor / all_in_price_minor = what venue.create_primary_checkout charges for ONE unit of the tier (the same rate read, gates and half-up rounding as checkout: the newest fee.buyer_service_bps version, used only when it is a JSON number and an integer 0..10000 — 188''s rule, restated here by 202; the fee is rounded per order, so never multiply for n units); both NULL whenever checkout would refuse to quote on the rate (unset, not a JSON number, out of range or fractional). '
  'Local times via catalog.venue.timezone (*_local, YYYY-MM-DD HH24:MI). ZERO rows (no error) for an unknown id, a draft/announced/cancelled event, a cancelled session or a non-approved venue. EXECUTE anon + authenticated.';

-- ── P catalog.publish_event(uuid,text,text): SALEABLE gate 4 = checkout's read and validity predicate
do $p$
begin
  if md5(pg_get_functiondef(to_regprocedure('catalog.publish_event(uuid,text,text)'))) = '18e9624482acee10a68b0ae6a2af97c1' then
    execute $body202$CREATE OR REPLACE FUNCTION catalog.publish_event(p_event_id uuid, p_target_status text, p_command_key text)
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
  v_fee_raw      jsonb;
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
    -- Registry 202: read and gated exactly as venue.create_primary_checkout
    -- reads and gates the rate since 188 (20261027031000:362-371 and :391-399),
    -- so an event goes on sale only with a rate checkout would quote on. The
    -- NEWEST version is picked first (a LIMIT subquery) and only that value is
    -- cast, so no older version can raise under any plan. A newest value that
    -- is not a JSON number refuses, and so does one outside the integer range
    -- 0..10000 (0 is accepted, as checkout accepts it). Every refusal keeps the
    -- fee_policy_unset token, which the venue dashboard maps.
    select l.value into v_fee_raw
      from (select c.value
              from catalog.platform_config c
             where c.key = 'fee.buyer_service_bps'
             order by c.version desc
             limit 1) l;
    if jsonb_typeof(v_fee_raw) not in ('number', 'null') then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps is a JSON %, not a number; this event cannot go on sale until the owner sets an integer', jsonb_typeof(v_fee_raw);
    end if;
    v_fee_bps := case when jsonb_typeof(v_fee_raw) = 'number' then (v_fee_raw #>> '{}')::numeric end;
    if v_fee_bps is null then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps has no value; this event cannot go on sale until the owner sets it';
    end if;
    if v_fee_bps < 0 or v_fee_bps > 10000 or v_fee_bps <> trunc(v_fee_bps) then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps must be an integer 0..10000, got %; this event cannot go on sale until the owner corrects it', v_fee_bps;
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
$body202$;
    raise notice '202: catalog.publish_event(uuid,text,text) replaced';
  else
    raise notice '202: catalog.publish_event(uuid,text,text) already carries 202''s body (re-apply, unchanged)';
  end if;
end $p$;

-- ── POST-FLIGHT: 202's md5s, every captured attribute unchanged, the comment, and checkout untouched.
do $pc$
declare
  v_cap jsonb := nullif(current_setting('migration_202.preflight', true), '')::jsonb;
  e     jsonb;
  q     record;
begin
  if v_cap is null or jsonb_array_length(v_cap) <> 2 then
    raise exception 'POSTFLIGHT_202_FAILED: the pre-flight capture is missing — run this file as one transaction';
  end if;
  for e in select * from jsonb_array_elements(v_cap) loop
    select md5(pg_get_functiondef(p.oid)) as md5, coalesce(p.proacl::text, '<null>') as acl, p.prosecdef,
           p.proconfig, coalesce(p.proconfig::text, '<null>') as cfg, p.proowner::regrole::text as owner,
           p.provolatile::text as vol,
           (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) as n
      into q from pg_proc p where p.oid = to_regprocedure(e ->> 'sig');
    if q.md5 is distinct from e ->> 'want' then
      raise exception 'POSTFLIGHT_202_FAILED: % body md5 % is not 202''s body % — this file was modified',
        e ->> 'sig', coalesce(q.md5, '<absent>'), e ->> 'want';
    end if;
    if q.acl is distinct from e ->> 'acl' then
      raise exception 'POSTFLIGHT_202_FAILED: % ACL changed from % to %', e ->> 'sig', e ->> 'acl', q.acl;
    end if;
    if q.prosecdef is distinct from (e ->> 'secdef')::boolean or not q.prosecdef then
      raise exception 'POSTFLIGHT_202_FAILED: % SECURITY DEFINER changed (was %, now %)', e ->> 'sig', e ->> 'secdef', q.prosecdef;
    end if;
    if q.cfg is distinct from e ->> 'cfg' or q.proconfig is distinct from array['search_path=""'] then
      raise exception 'POSTFLIGHT_202_FAILED: % proconfig changed (was %, now %)', e ->> 'sig', e ->> 'cfg', q.cfg;
    end if;
    if q.owner is distinct from e ->> 'owner' or q.vol is distinct from e ->> 'vol' or q.n <> 1 then
      raise exception 'POSTFLIGHT_202_FAILED: % owner/volatility/overloads changed (owner % -> %, volatility % -> %, overloads %)',
        e ->> 'sig', e ->> 'owner', q.owner, e ->> 'vol', q.vol, q.n;
    end if;
  end loop;
  if md5(obj_description(to_regprocedure('public.get_primary_session(uuid)'), 'pg_proc')) is distinct from '1af9f2294f0523662bad51d59f5dd00b' then
    raise exception 'POSTFLIGHT_202_FAILED: the COMMENT on public.get_primary_session(uuid) is not 202''s (md5 %)',
      coalesce(md5(obj_description(to_regprocedure('public.get_primary_session(uuid)'), 'pg_proc')), '<none>');
  end if;
  if md5(pg_get_functiondef(to_regprocedure('venue.create_primary_checkout(uuid,jsonb,uuid[],text)')))
       is distinct from current_setting('migration_202.checkout_md5', true) then
    raise exception 'POSTFLIGHT_202_FAILED: venue.create_primary_checkout changed during this file';
  end if;
  raise notice '202 post-flight: % ok; comment ok; checkout unchanged',
    (select string_agg((x ->> 'sig') || '=' || left(x ->> 'want', 8), ' ') from jsonb_array_elements(v_cap) x);
end $pc$;

commit;
