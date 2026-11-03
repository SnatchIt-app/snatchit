-- ============================================================================
-- ROLLBACK for 20261102130000_refund_ledger_post_success_failure_and_executor_exclusions.sql (registry 199).
-- Restores the applied state before 199: kernel.mark_refund_state (085:1737-1788), kernel.get_refund_execution_context
-- (093:1038-1068, language sql), kernel.claim_refunds_for_execution (093:1311-1384) and ops.executor_claim
-- (118:614-688) verbatim with their grants, then drops the four 199 functions (none existed before 199).
--
-- GUARDS (any one refuses the whole file):
--   * an executor is enabled — catalog.platform_config refund.executor_enabled (latest version) or ops.setting
--     refund_execute_enabled is true. The pre-199 bodies hand manual and parked rows back to the sweep and restore the
--     unconfirmed already_refunded_locally acknowledgement, so this runs only with both executors off;
--   * inverse md5: each replaced body must be 199's or its predecessor; each new function 199's or absent. A foreign
--     body is refused, never overwritten or dropped. record_refund_stripe_failure is accepted at this revision's body
--     (8a443bd8…) or at the reviewed head 45708aec's (ba2de45d…, which carried the ref shape check), matching the
--     migration's pre-flight, so a database that applied either revision rolls back with this file;
--   * callers: any function body or view outside the eight 199 signatures that names a 199 function.
-- ORDER: roll back A's edges first (a webhook calling the dropped verb gets PGRST202, which A maps to ack + page).
-- Roll 199 back BEFORE any 150 rollback.
-- DATA STAYS: refunds moved to `failed` remain failed (Stripe truth; failed is terminal), and the refund.execute_parked /
-- refund.execute_rearmed / refund.failed_after_success audit rows remain (append-only). The 093 claim ignores them, so
-- pre-199 re-claiming resumes — which is why this file is flag-gated.
-- Re-running this file after a successful rollback is a no-op (every body already at its predecessor, every new
-- function absent).
-- ============================================================================
begin;
set local lock_timeout = '3s';

do $rb$
declare
  r      record;
  v_md5  text;
  v_on   boolean;
  v_hit  text;
  v_pre  jsonb;
begin
  v_on := coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c
                     where c.key = 'refund.executor_enabled' order by c.version desc limit 1), false);
  if v_on then
    raise exception 'ROLLBACK_199_REFUSED: catalog.platform_config refund.executor_enabled is true — turn the refund executor off first';
  end if;
  v_on := coalesce((select (s.value #>> '{}')::boolean from ops.setting s where s.key = 'refund_execute_enabled'), false);
  if v_on then
    raise exception 'ROLLBACK_199_REFUSED: ops.setting refund_execute_enabled is true — turn ops-refund-execute off first';
  end if;

  for r in
    select * from (values
      ('kernel.refund_executor_hold(uuid)',                         'new',      null,                               '31d6705d651d04ef82191faec528ad27', null),
      ('kernel.mark_refund_state(uuid,text,text,text,text)',        'replaced', '4ed2a017cb2596f5c96b341c7856948c', 'a14aafa2040db639a18f64aa30e5b6f1', null),
      ('kernel.claim_refunds_for_execution(integer,integer)',       'replaced', 'e11686e3fc2da23aab169dbc668ae4d6', '3664f28dc744d274ff8813309edf9fd0', null),
      ('kernel.get_refund_execution_context(uuid)',                 'replaced', '15e5576c89f55aedb9ea1be2c050d4dd', '8aede0fc7dbdb0bc37a53d53c0eda51e', null),
      ('kernel.record_refund_stripe_failure(text,text)',            'new',      null,                               '8a443bd8ee3444ba11b6097eeda6fd9a', 'ba2de45d6283db5afcc954b7d401596d'),
      ('kernel.park_refund_execution(uuid,integer,text,text,text)', 'new',      null,                               '822d2d2fd0cfd3e39f8fe6f1f0baec74', null),
      ('kernel.rearm_refund_execution(uuid,text,text)',             'new',      null,                               '977edd52c3d535a36f7431ea008a2bb9', null),
      ('ops.executor_claim(uuid,integer)',                          'replaced', '1cfa0290546ff36fe07389a9d13b7f9e', '2d658f3406ea6e774fd8f6dcb163a27f', null)
    ) as t(sig, kind, pred_md5, own_md5, rev_md5)
  loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if r.kind = 'replaced' and v_md5 is distinct from r.own_md5 and v_md5 is distinct from r.pred_md5 then
      raise exception 'ROLLBACK_199_REFUSED: % has md5 %, neither 199''s (%) nor its predecessor (%) — not overwriting a foreign body',
        r.sig, coalesce(v_md5, '<absent>'), r.own_md5, r.pred_md5;
    end if;
    if r.kind = 'new' and v_md5 is not null and v_md5 <> r.own_md5 and v_md5 is distinct from r.rev_md5 then
      raise exception 'ROLLBACK_199_REFUSED: % has md5 %, not 199''s (%) — not dropping a foreign body', r.sig, v_md5,
        r.own_md5 || coalesce(' or ' || r.rev_md5, '');
    end if;
  end loop;

  select string_agg(x.obj, ', ' order by x.obj) into v_hit
    from (select n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as obj
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname !~ '^pg_'
             and p.prosrc ~ '(refund_executor_hold|record_refund_stripe_failure|park_refund_execution|rearm_refund_execution)'
             and p.oid not in (select o from unnest(array[
                   to_regprocedure('kernel.refund_executor_hold(uuid)'),
                   to_regprocedure('kernel.mark_refund_state(uuid,text,text,text,text)'),
                   to_regprocedure('kernel.claim_refunds_for_execution(integer,integer)'),
                   to_regprocedure('kernel.get_refund_execution_context(uuid)'),
                   to_regprocedure('kernel.record_refund_stripe_failure(text,text)'),
                   to_regprocedure('kernel.park_refund_execution(uuid,integer,text,text,text)'),
                   to_regprocedure('kernel.rearm_refund_execution(uuid,text,text)'),
                   to_regprocedure('ops.executor_claim(uuid,integer)')]::oid[]) o where o is not null)
          union all
          select n.nspname || '.' || c.relname
            from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema') and n.nspname !~ '^pg_'
             and pg_get_viewdef(c.oid) ~ '(refund_executor_hold|record_refund_stripe_failure|park_refund_execution|rearm_refund_execution)') x;
  if v_hit is not null then
    raise exception 'ROLLBACK_199_REFUSED: % still name a 199 function — remove those callers first', v_hit;
  end if;

  -- capture the replaced functions' ACLs; the post-check requires them unchanged
  select jsonb_object_agg(t.sig, (select jsonb_agg(x order by x) from unnest(coalesce(p.proacl, acldefault('f', p.proowner))::text[]) x))
    into v_pre
    from (values ('kernel.mark_refund_state(uuid,text,text,text,text)'),
                 ('kernel.claim_refunds_for_execution(integer,integer)'),
                 ('kernel.get_refund_execution_context(uuid)'),
                 ('ops.executor_claim(uuid,integer)')) as t(sig)
    join pg_proc p on p.oid = to_regprocedure(t.sig);
  perform set_config('rollback_199.acl', v_pre::text, true);
end $rb$;

-- ── restore the applied predecessor bodies verbatim (085 / 093 / 118), with their grants
create or replace function kernel.mark_refund_state(
  p_refund_id uuid, p_new_status text, p_stripe_refund_ref text, p_failure_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row kernel.refund%rowtype;
begin
  if p_new_status not in ('submitted','succeeded','failed') then
    raise exception 'invalid_input: mark_refund_state takes submitted|succeeded|failed';
  end if;
  select * into v_row from kernel.refund where refund_id = p_refund_id for update;
  if not found then
    raise exception 'not_found: refund %', p_refund_id using errcode = 'P0002';
  end if;
  if v_row.status = p_new_status
     and (p_stripe_refund_ref is null or v_row.stripe_refund_ref = p_stripe_refund_ref) then
    return jsonb_build_object('status','noop_replay','refund_id', p_refund_id);
  end if;
  -- forward-only pending→submitted→succeeded|failed. 'failed' = Stripe ACCEPTED
  -- then couldn't settle (carries re_…); a create-call error leaves 'pending'
  -- (the S-24 pairing CHECK makes the wrong reading unstorable).
  if not ( (v_row.status = 'pending'   and p_new_status = 'submitted')
        or (v_row.status = 'submitted' and p_new_status in ('succeeded','failed')) ) then
    raise exception 'precondition_failed: refund_state_backwards (% → %)', v_row.status, p_new_status;
  end if;
  if p_stripe_refund_ref is null then
    raise exception 'invalid_input: stripe_refund_ref is mandatory (non-pending rows carry it)';
  end if;
  if v_row.stripe_refund_ref is not null and v_row.stripe_refund_ref <> p_stripe_refund_ref then
    raise exception 'conflict_locked: stripe_refund_ref is write-once';
  end if;
  if p_new_status = 'failed' and (p_failure_code is null or length(trim(p_failure_code)) = 0) then
    raise exception 'invalid_input: failure_code is mandatory for failed';
  end if;

  update kernel.refund
     set status = p_new_status,
         stripe_refund_ref = coalesce(v_row.stripe_refund_ref, p_stripe_refund_ref),
         updated_at = now()
   where refund_id = p_refund_id;      -- touches NO atom, NO public.* table

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(),'00000000-0000-0000-0000-0000000000f1'), 'refund.state_sync', 'refund',
          p_refund_id, coalesce(p_failure_code, p_new_status),
          jsonb_build_object('status', v_row.status),
          jsonb_build_object('status', p_new_status));
  return jsonb_build_object('status','ok','refund_id', p_refund_id, 'new_status', p_new_status);
end;
$$;

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
revoke all on function kernel.get_refund_execution_context(uuid) from public, anon, authenticated;
grant execute on function kernel.get_refund_execution_context(uuid) to service_role;

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
revoke all on function kernel.claim_refunds_for_execution(integer, integer)
  from public, anon, authenticated;
grant execute on function kernel.claim_refunds_for_execution(integer, integer) to service_role;

create or replace function ops.executor_claim(p_action_id uuid, p_lease_seconds integer default 300)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  a    ops.action%rowtype;
  ap   ops.approval%rowtype;
  p    public.payments%rowtype;
  v_prev_sent boolean;
begin
  if not public.request_is_service_role() then
    raise exception 'insufficient_privilege: service_role only' using errcode = '42501';
  end if;
  select * into a from ops.action where id = p_action_id for update;
  if not found then
    return jsonb_build_object('status','refused','reason','not_found');
  end if;
  if a.action_type <> 'refund_execute' then
    return jsonb_build_object('status','refused','reason','wrong_type','state', a.state);
  end if;
  if a.state in ('succeeded','failed','rejected') then
    return jsonb_build_object('status','refused','reason','terminal','state', a.state);
  end if;
  if a.state = 'succeeded_at_provider' then
    return jsonb_build_object('status','refused','reason','succeeded_at_provider','state', a.state, 'provider_ref', a.provider_ref);
  end if;
  if a.state not in ('processing','unknown') then
    return jsonb_build_object('status','refused','reason','not_executable','state', a.state);
  end if;
  if not coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'actions_enabled'), true) then
    return jsonb_build_object('status','refused','reason','paused','state', a.state);
  end if;
  if not coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'refund_execute_enabled'), false) then
    return jsonb_build_object('status','refused','reason','disabled','state', a.state);
  end if;
  select * into ap from ops.approval where action_id = a.id and state = 'approved' order by decided_at desc limit 1;
  if not found then
    return jsonb_build_object('status','refused','reason','approval_missing','state', a.state);
  end if;
  if ap.action_hash <> ops.action_hash(a.action_type, a.subject_kind, a.subject_id, a.subject_ref, a.params) then
    return jsonb_build_object('status','refused','reason','approval_stale','state', a.state);
  end if;
  if a.claimed_until is not null and a.claimed_until > now() then
    return jsonb_build_object('status','refused','reason','claim_busy','state', a.state, 'claimed_until', a.claimed_until);
  end if;
  select * into p from public.payments where id = a.subject_id;
  if not found then
    return jsonb_build_object('status','refused','reason','payment_missing','state', a.state);
  end if;
  if p.status = 'refunded' then
    return jsonb_build_object('status','refused','reason','already_refunded_locally','state', a.state, 'stripe_refund_id', p.stripe_refund_id);
  end if;
  if p.status <> 'succeeded' or p.stripe_payment_intent_id is null then
    return jsonb_build_object('status','refused','reason','payment_not_refundable','state', a.state, 'payment_status', p.status);
  end if;

  v_prev_sent := a.attempt > 0 or a.provider_ref is not null or (a.result ? 'stripe_request_started_at');
  update ops.action
     set claimed_until = now() + make_interval(secs => greatest(coalesce(p_lease_seconds, 300), 30)),
         attempt = attempt + 1,
         state = 'processing',
         version = version + 1
   where id = a.id;
  perform ops.audit_write('action.claim.refund_execute', a.subject_kind, a.subject_id, a.subject_ref, null,
                          jsonb_build_object('state', a.state, 'attempt', a.attempt),
                          jsonb_build_object('attempt', a.attempt + 1, 'previously_sent', v_prev_sent),
                          'claimed', a.correlation_id, a.id);
  return jsonb_build_object(
    'status', 'claimed', 'action_id', a.id, 'payment_id', p.id,
    'stripe_payment_intent_id', p.stripe_payment_intent_id,
    'amount_cents', p.total, 'payment_total_cents', p.total, 'currency', 'usd',
    'reason_code', a.params ->> 'reason_code',
    'previously_sent', v_prev_sent, 'provider_ref', a.provider_ref, 'attempt', a.attempt + 1,
    'stripe_livemode', p.stripe_livemode);
end;
$ops$;
revoke all on function ops.executor_claim(uuid,integer) from public, anon, authenticated;
grant execute on function ops.executor_claim(uuid,integer) to service_role;

-- 085 granted kernel.mark_refund_state through its EXEC DEF loop; the equivalent pair, re-issued.
revoke all on function kernel.mark_refund_state(uuid,text,text,text,text) from public, anon, authenticated;
grant execute on function kernel.mark_refund_state(uuid,text,text,text,text) to service_role;

comment on function kernel.mark_refund_state(uuid,text,text,text,text) is null;
comment on function kernel.claim_refunds_for_execution(integer,integer) is null;
comment on function kernel.get_refund_execution_context(uuid) is null;
comment on function ops.executor_claim(uuid,integer) is null;

-- ── drop the four 199 functions; the restored bodies no longer name them. No CASCADE: a dependent must fail this.
drop function if exists kernel.rearm_refund_execution(uuid, text, text);
drop function if exists kernel.park_refund_execution(uuid, integer, text, text, text);
drop function if exists kernel.record_refund_stripe_failure(text, text);
drop function if exists kernel.refund_executor_hold(uuid);

-- ── POST-CHECK: predecessor bodies, new functions absent, ACLs unchanged.
do $post$
declare
  r     record;
  v_md5 text;
  v_acl jsonb := current_setting('rollback_199.acl')::jsonb;
  v_now jsonb;
begin
  for r in
    select * from (values
      ('kernel.mark_refund_state(uuid,text,text,text,text)',  '4ed2a017cb2596f5c96b341c7856948c'),
      ('kernel.claim_refunds_for_execution(integer,integer)', 'e11686e3fc2da23aab169dbc668ae4d6'),
      ('kernel.get_refund_execution_context(uuid)',           '15e5576c89f55aedb9ea1be2c050d4dd'),
      ('ops.executor_claim(uuid,integer)',                    '1cfa0290546ff36fe07389a9d13b7f9e')
    ) as t(sig, want_md5)
  loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if v_md5 is distinct from r.want_md5 then
      raise exception 'ROLLBACK_199_FAILED: % has md5 % after the restore, not its predecessor %', r.sig, coalesce(v_md5, '<absent>'), r.want_md5;
    end if;
    select (select jsonb_agg(x order by x) from unnest(coalesce(p.proacl, acldefault('f', p.proowner))::text[]) x)
      into v_now from pg_proc p where p.oid = to_regprocedure(r.sig);
    if v_now is distinct from (v_acl -> r.sig) then
      raise exception 'ROLLBACK_199_FAILED: % ACL moved: before % / after %', r.sig, v_acl -> r.sig, v_now;
    end if;
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.sig)
                     and p.prosecdef and p.proconfig = array['search_path=""'] and p.proowner = 'postgres'::regrole) then
      raise exception 'ROLLBACK_199_FAILED: % posture (SECURITY DEFINER, search_path '''', owner postgres) not restored', r.sig;
    end if;
  end loop;
  if to_regprocedure('kernel.refund_executor_hold(uuid)') is not null
     or to_regprocedure('kernel.record_refund_stripe_failure(text,text)') is not null
     or to_regprocedure('kernel.park_refund_execution(uuid,integer,text,text,text)') is not null
     or to_regprocedure('kernel.rearm_refund_execution(uuid,text,text)') is not null then
    raise exception 'ROLLBACK_199_FAILED: a 199 function still exists';
  end if;
end $post$;

commit;
