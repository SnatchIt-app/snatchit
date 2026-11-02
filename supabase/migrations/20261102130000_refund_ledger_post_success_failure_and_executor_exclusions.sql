-- ============================================================================
-- 20261102130000_refund_ledger_post_success_failure_and_executor_exclusions.sql
-- Registry 199 / pgTAP 268. D writes and owns the SQL, pgTAP, census and Gate-2 note; A owns the edges.
-- DARK: applied nowhere until merged. Spec: planning/2026-10-26-launch/D/s15-199/DESIGN-199-FINAL.md.
--
-- WHAT THIS MIGRATION GUARANTEES
--   refunds-4  A kernel.refund that Stripe fails or cancels AFTER it was recorded succeeded converges to `failed`
--              through exactly one verb, kernel.record_refund_stripe_failure(re_…, command_key). The verb resolves
--              the row by its own write-once stripe_refund_ref, takes the failure code from the recorded Stripe
--              state (public.payment_refund_state) and never from a caller argument, checks that the recorded
--              payment and amount match the row before any verdict, holds the org settlement seam lock, and
--              writes the settlement / obligation / atom / resale residue into one kernel.admin_audit row
--              (refund.failed_after_success). kernel.mark_refund_state refuses `succeeded` for a ref whose
--              recorded Stripe state is failed or canceled (refund_failed_at_stripe); nothing else in it changes.
--   refunds-2  A refund written by kernel.refund_primary_order's DIRECT arm (marked by its same-transaction
--              refund.issue audit with delegated=false) is never claimed by kernel.claim_refunds_for_execution,
--              and kernel.get_refund_execution_context raises executor_hold for it.
--   refunds-7  kernel.park_refund_execution parks an unfinished refund for the executor, fenced by the latest
--              claim attempt and scoped to the status that claim saw; a parked row is not claimed and its
--              context raises, until kernel.rearm_refund_execution (platform_risk / platform_admin at aal2,
--              never service_role, refused while Stripe money on a pending row's payment is bound to no kernel
--              refund) re-arms it. Every exclusion has its cause in append-only kernel.admin_audit.
--   refunds-5  ops.executor_claim acknowledges already_refunded_locally only when Stripe-confirmed succeeded
--              refunds cover the payment total (payments.refund_succeeded_cents >= total). A payment marked
--              refunded otherwise is admitted only for a previously-sent action (the handler lists before it
--              POSTs) or refused with charged_back / refund_state_unobserved / refund_state_unresolved + detail.
--              An action whose `result` is NULL (only a direct insert leaves one; ops.action_run always stores the
--              handoff object) makes the previously-sent flag NULL; it counts as NOT previously sent (fail closed).
--   claim mode (refunds-1 residual, assigned by A): a pending row is claimed in `create` mode only when it was
--              created inside the 20 h window (v_r.created_at > now() - 20 h); otherwise `reconcile`. created_at
--              precedes any POST with the row's key, so a row created inside the window can only have POSTs that
--              Stripe still dedupes; a row older than 20 h is reconciled first even if it has no claim row (a
--              POST may have come through action:execute, which writes no claim row). submitted rows always
--              reconcile, as before.
--
-- NOT CHANGED. No table, column, constraint, index, trigger, policy or table-grant DDL (the money-ledger freeze,
-- 093:148-150 / 093:1242-1243, holds). Not touched: 189's bodies (ops.record_primary_refund md5 337a8f19…),
-- kernel.refund_primary_order, public.record_refund_state, every settlement body. Nothing lands in `public`.
-- No body written here contains record_primary_refund or primary_reconciliation, so 189's rollback guard stays
-- satisfiable. Rationale lives in COMMENT ON FUNCTION, never in a pinned body.
--
-- FUNCTIONS. NEW (kernel): refund_executor_hold(uuid) — no grant; record_refund_stripe_failure(text,text) and
-- park_refund_execution(uuid,integer,text,text,text) — service_role; rearm_refund_execution(uuid,text,text) —
-- authenticated, service_role revoked. REPLACED (same signatures, CREATE OR REPLACE, OIDs and ACLs kept, ACLs
-- re-issued): kernel.mark_refund_state (085:1737-1788 + two insertions), kernel.claim_refunds_for_execution
-- (093:1311-1384 + two insertions + the mode line above), kernel.get_refund_execution_context (093:1038-1068,
-- now plpgsql STABLE, same fifteen keys, raises for a held unfinished row), ops.executor_claim (118:614-688,
-- the refunded-payment span replaced).
--
-- MD5 — md5(pg_get_functiondef(...)). Written here (O): the pre-flight accepts each of these as "already 199".
--   kernel.refund_executor_hold(uuid)                                   31d6705d651d04ef82191faec528ad27
--   kernel.mark_refund_state(uuid,text,text,text,text)                  a14aafa2040db639a18f64aa30e5b6f1
--   kernel.claim_refunds_for_execution(integer,integer)                 3664f28dc744d274ff8813309edf9fd0
--   kernel.get_refund_execution_context(uuid)                           8aede0fc7dbdb0bc37a53d53c0eda51e
--   kernel.record_refund_stripe_failure(text,text)                      ba2de45d6283db5afcc954b7d401596d
--   kernel.park_refund_execution(uuid,integer,text,text,text)           822d2d2fd0cfd3e39f8fe6f1f0baec74
--   kernel.rearm_refund_execution(uuid,text,text)                       977edd52c3d535a36f7431ea008a2bb9
--   ops.executor_claim(uuid,integer)                                    2d658f3406ea6e774fd8f6dcb163a27f
-- Predecessors (P), the applied bodies at main 7496fee3:
--   kernel.mark_refund_state (085)                                      4ed2a017cb2596f5c96b341c7856948c
--   kernel.claim_refunds_for_execution (093)                            e11686e3fc2da23aab169dbc668ae4d6
--   kernel.get_refund_execution_context (093)                           15e5576c89f55aedb9ea1be2c050d4dd
--   ops.executor_claim (118)                                            1cfa0290546ff36fe07389a9d13b7f9e
-- Dependencies pinned (D), unchanged by 199:
--   kernel.refund_primary_order(uuid,integer,text,text) (085, the manual-rail marker producer)  e0a37574a02131e4cedec43a2ef427f7
--   public.record_refund_state(text,text,text,integer,text,text,text) (150, failed/canceled final) 5e9f66129a4bb82b6b3e7a1b41e04365
--   kernel.settlement_primary_lines(uuid) (100, succeeded-only debit, whole-order deferral)      ebc5d6c16334e55e39ceea63d9eab7f6
-- Measured on a local PG17 replay of main 7496fee3 (template d197_base: a154c_green + main's 2026102x/3x
-- migrations, service_role function default revoked), under the server zone and under PGTZ=UTC (identical).
-- Five of the seven P/D values also equal lane D's earlier record of 7496fee3 (predecessor-md5-7496fee3.txt).
-- Every argument and return type is in pg_catalog, so pg_get_functiondef does not depend on search_path.
-- A production-equal clone has NOT been measured from lane D: confirm the P and D values there before apply. A
-- mismatch makes the pre-flight refuse (safe; it blocks apply).
--
-- ROLLBACK: supabase/rollbacks/20261102130000_refund_ledger_post_success_failure_and_executor_exclusions_rollback.sql
-- (refuses while refund.executor_enabled or ops refund_execute_enabled is on; restores the four predecessor bodies
-- verbatim; drops the four new functions; no CASCADE). Roll back A's edges first. Roll 199 back BEFORE any 150
-- rollback: mark_refund_state now reads public.payment_refund_state. Data written while 199 was applied stays by
-- design: refunds moved to `failed` remain failed (Stripe truth, terminal) and the park / re-arm /
-- failed-after-success audit rows remain (append-only; the 093 claim ignores them).
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── PRE-FLIGHT. to_regprocedure(sig) everywhere, never a '...'::regprocedure literal (it resolves at plan time).
do $pf$
declare
  r          record;
  v_md5      text;
  v_name     text;
  v_n        integer;
  v_first    boolean := true;   -- every replaced body at its predecessor, every new function absent
  v_again    boolean := true;   -- every body already 199's (idempotent re-apply)
  v_states   text    := '';
  v_pre      jsonb;
begin
  -- (a) replaced bodies: predecessor or 199's own; (b) new functions: absent or 199's own, and no other overload
  for r in
    select * from (values
      ('kernel.refund_executor_hold(uuid)',                         'new',      null,                               '31d6705d651d04ef82191faec528ad27'),
      ('kernel.mark_refund_state(uuid,text,text,text,text)',        'replaced', '4ed2a017cb2596f5c96b341c7856948c', 'a14aafa2040db639a18f64aa30e5b6f1'),
      ('kernel.claim_refunds_for_execution(integer,integer)',       'replaced', 'e11686e3fc2da23aab169dbc668ae4d6', '3664f28dc744d274ff8813309edf9fd0'),
      ('kernel.get_refund_execution_context(uuid)',                 'replaced', '15e5576c89f55aedb9ea1be2c050d4dd', '8aede0fc7dbdb0bc37a53d53c0eda51e'),
      ('kernel.record_refund_stripe_failure(text,text)',            'new',      null,                               'ba2de45d6283db5afcc954b7d401596d'),
      ('kernel.park_refund_execution(uuid,integer,text,text,text)', 'new',      null,                               '822d2d2fd0cfd3e39f8fe6f1f0baec74'),
      ('kernel.rearm_refund_execution(uuid,text,text)',             'new',      null,                               '977edd52c3d535a36f7431ea008a2bb9'),
      ('ops.executor_claim(uuid,integer)',                          'replaced', '1cfa0290546ff36fe07389a9d13b7f9e', '2d658f3406ea6e774fd8f6dcb163a27f')
    ) as t(sig, kind, pred_md5, own_md5)
  loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if r.kind = 'replaced' then
      if v_md5 is null then
        raise exception 'MIGRATION_199_REFUSED: % is absent (199 replaces it in place)', r.sig;
      elsif v_md5 = r.pred_md5 then
        v_again := false;
      elsif v_md5 = r.own_md5 then
        v_first := false;
      else
        raise exception 'MIGRATION_199_REFUSED: % body md5 % is neither its predecessor (%) nor 199''s (%)',
          r.sig, v_md5, r.pred_md5, r.own_md5;
      end if;
    else
      if v_md5 is null then
        v_again := false;
      elsif v_md5 = r.own_md5 then
        v_first := false;
      else
        raise exception 'MIGRATION_199_REFUSED: a foreign % exists (md5 %, 199''s is %)', r.sig, v_md5, r.own_md5;
      end if;
      v_name := split_part(split_part(r.sig, '(', 1), '.', 2);
      select count(*) into v_n from pg_proc p where p.pronamespace = 'kernel'::regnamespace and p.proname = v_name;
      if v_n > (case when v_md5 is null then 0 else 1 end) then
        raise exception 'MIGRATION_199_REFUSED: another kernel.% overload exists (% pg_proc rows)', v_name, v_n;
      end if;
    end if;
    v_states := v_states || r.sig || '=' || coalesce(v_md5, '<absent>') || '; ';
  end loop;
  if not (v_first or v_again) then
    raise exception 'MIGRATION_199_REFUSED: partial state — the eight bodies are neither all pre-199 nor all 199''s: %', v_states;
  end if;

  -- (c) dependency pins (exact md5, no substring fallback)
  for r in
    select * from (values
      ('kernel.refund_primary_order(uuid,integer,text,text)',              'e0a37574a02131e4cedec43a2ef427f7', 'the refund.issue delegated marker producer'),
      ('public.record_refund_state(text,text,text,integer,text,text,text)', '5e9f66129a4bb82b6b3e7a1b41e04365', 'failed/canceled finality of the recorded Stripe state'),
      ('kernel.settlement_primary_lines(uuid)',                             'ebc5d6c16334e55e39ceea63d9eab7f6', 'the succeeded-only refund_void debit and the whole-order deferral')
    ) as t(sig, want_md5, why)
  loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if v_md5 is distinct from r.want_md5 then
      raise exception 'MIGRATION_199_REFUSED: % has md5 % (expected %) — 199 relies on %; re-examine 199',
        r.sig, coalesce(v_md5, '<absent>'), r.want_md5, r.why;
    end if;
  end loop;

  -- (d) the columns the new bodies read exist (not dropped)
  for r in
    select * from (values
      ('public.payment_refund_state', 'stripe_refund_id'), ('public.payment_refund_state', 'payment_id'),
      ('public.payment_refund_state', 'amount_cents'),     ('public.payment_refund_state', 'status'),
      ('public.payment_refund_state', 'failure_reason'),
      ('public.payments', 'total'),                  ('public.payments', 'status'),
      ('public.payments', 'stripe_payment_intent_id'), ('public.payments', 'stripe_refund_id'),
      ('public.payments', 'refund_succeeded_cents'), ('public.payments', 'refund_requested_cents'),
      ('public.payments', 'refund_failed_cents'),    ('public.payments', 'amount_refunded_cents'),
      ('public.payment_refunds', 'payment_id'),      ('public.payment_refunds', 'stripe_refund_id'),
      ('public.payment_refunds', 'amount_cents'),    ('public.payment_refunds', 'source'),
      ('venue.settlement_line', 'cause'),            ('venue.settlement_line', 'cause_ref'),
      ('venue.settlement_line', 'settlement_id'),    ('venue.settlement_line', 'amount_minor'),
      ('venue.attribution', 'order_id'),
      ('market.market_sale', 'sale_id'),             ('market.market_sale', 'payment_id'),
      ('market.market_sale', 'terminal_state'),
      ('kernel.ticket_ownership_log', 'cause'),      ('kernel.ticket_ownership_log', 'cause_ref'),
      ('kernel.ticket_ownership_log', 'ticket_atom_id')
    ) as t(rel, col)
  loop
    if not exists (select 1 from pg_attribute a
                    where a.attrelid = to_regclass(r.rel) and a.attname = r.col and a.attnum > 0 and not a.attisdropped) then
      raise exception 'MIGRATION_199_REFUSED: column %.% is missing', r.rel, r.col;
    end if;
  end loop;

  -- (e) the audit markers are unforgeable: no client or machine role may INSERT into kernel.admin_audit
  if has_table_privilege('anon', 'kernel.admin_audit', 'INSERT')
     or has_table_privilege('authenticated', 'kernel.admin_audit', 'INSERT')
     or has_table_privilege('service_role', 'kernel.admin_audit', 'INSERT') then
    raise exception 'MIGRATION_199_REFUSED: a client or machine role holds INSERT on kernel.admin_audit — the executor-hold markers would be forgeable';
  end if;

  -- capture the replaced functions' posture; the post-flight requires it unchanged (ACL compared as a set)
  select jsonb_object_agg(t.sig, jsonb_build_object(
           'acl',    (select jsonb_agg(x order by x) from unnest(coalesce(p.proacl, acldefault('f', p.proowner))::text[]) x),
           'secdef', p.prosecdef,
           'config', to_jsonb(p.proconfig),
           'owner',  p.proowner::regrole::text))
    into v_pre
    from (values ('kernel.mark_refund_state(uuid,text,text,text,text)'),
                 ('kernel.claim_refunds_for_execution(integer,integer)'),
                 ('kernel.get_refund_execution_context(uuid)'),
                 ('ops.executor_claim(uuid,integer)')) as t(sig)
    join pg_proc p on p.oid = to_regprocedure(t.sig);
  perform set_config('migration_199.preflight', v_pre::text, true);
end $pf$;

-- ── 1. NEW kernel.refund_executor_hold — the single executor-exclusion predicate (SQL; created first). No grant.
create or replace function kernel.refund_executor_hold(p_refund_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
           when exists (select 1
                          from kernel.payment_native pn
                          join kernel.admin_audit ai
                            on ai.subject_kind = 'order' and ai.subject_id = pn.order_id
                         where pn.payment_id = r.payment_id
                           and ai.action = 'refund.issue'
                           and ai.after ->> 'refund_id' = r.refund_id::text
                           and ai.after ->> 'delegated' = 'false')
             then 'manual_record'
           when r.status in ('pending','submitted')
            and (select count(*) from kernel.admin_audit ap
                  where ap.subject_kind = 'refund' and ap.subject_id = r.refund_id
                    and ap.action = 'refund.execute_parked'
                    and ap.before ->> 'status' = r.status)
              > (select count(*) from kernel.admin_audit aq
                  where aq.subject_kind = 'refund' and aq.subject_id = r.refund_id
                    and aq.action = 'refund.execute_rearmed'
                    and aq.before ->> 'status' = r.status)
             then 'parked'
         end
    from kernel.refund r
   where r.refund_id = p_refund_id;
$$;

-- ── 2. REPLACED kernel.mark_refund_state — 085:1737-1788 byte-for-byte + v_stripe + the Stripe-truth guard.
create or replace function kernel.mark_refund_state(
  p_refund_id uuid, p_new_status text, p_stripe_refund_ref text, p_failure_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row kernel.refund%rowtype;
  v_stripe text;
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
  if p_new_status = 'succeeded' then
    select s.status into v_stripe
      from public.payment_refund_state s
     where s.stripe_refund_id = p_stripe_refund_ref;
    if v_stripe in ('failed','canceled') then
      raise exception 'precondition_failed: refund_failed_at_stripe (% is %)', p_stripe_refund_ref, v_stripe;
    end if;
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

-- ── 3. REPLACED kernel.claim_refunds_for_execution — 093:1311-1384 byte-for-byte + the cursor hold filter, the
--    in-loop lease/hold recheck, and the create-mode line (created inside the window, not first claim).
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
       and kernel.refund_executor_hold(r.refund_id) is null
     order by r.created_at, r.refund_id                     -- oldest money first
     limit v_limit
     for update skip locked
  loop
    if exists (select 1 from kernel.admin_audit a
                where a.subject_kind = 'refund'
                  and a.subject_id   = v_r.refund_id
                  and a.action       = 'refund.execute_claim'
                  and a.occurred_at  > now() - make_interval(secs => v_lease))
       or kernel.refund_executor_hold(v_r.refund_id) is not null then
      continue;
    end if;
    select min(a.occurred_at), count(*)::integer into v_first, v_tries
      from kernel.admin_audit a
     where a.subject_kind = 'refund' and a.subject_id = v_r.refund_id
       and a.action = 'refund.execute_claim';

    if v_r.status = 'submitted' then
      v_mode := 'reconcile';                       -- always carries a ref (085:93)
    elsif v_r.created_at > now() - v_window then
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

-- ── 4. REPLACED kernel.get_refund_execution_context — plpgsql STABLE; 093:1042-1063 (the fifteen keys) verbatim.
create or replace function kernel.get_refund_execution_context(p_refund_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v      jsonb;
  v_hold text;
begin
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
    into v
    from kernel.refund r
    join public.payments p on p.id = r.payment_id                      -- total: NOT NULL FK (085:76)
    left join kernel.payment_native pn on pn.payment_id = r.payment_id -- see the deviation note
   where r.refund_id = p_refund_id;
  if v is null then
    return null;
  end if;
  if (v ->> 'status') in ('pending','submitted') then
    v_hold := kernel.refund_executor_hold(p_refund_id);
    if v_hold is not null then
      raise exception 'precondition_failed: executor_hold % (refund %)', v_hold, p_refund_id
        using errcode = 'P0001';
    end if;
  end if;
  return v;
end;
$$;

-- ── 5. NEW kernel.record_refund_stripe_failure — the single post-failure converger. service_role only.
create or replace function kernel.record_refund_stripe_failure(p_stripe_refund_ref text, p_command_key text)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_sys    constant uuid := '00000000-0000-0000-0000-0000000000f1';
  v_id     uuid;
  v_pay    uuid;
  v_order  uuid;
  v_org    uuid;
  v_row    kernel.refund%rowtype;
  v_obs    public.payment_refund_state%rowtype;
  v_code   text;
  v_line   jsonb;
  v_short  jsonb;
  v_unl    jsonb;
  v_claw   jsonb;
  v_comp   jsonb;
  v_atoms  jsonb;
  v_promo  boolean;
  v_review boolean;
  v_facts  jsonb;
begin
  if p_stripe_refund_ref is null or p_stripe_refund_ref !~ '^re_[A-Za-z0-9]{1,250}$' then
    raise exception 'invalid_input: stripe_refund_ref must be a Stripe refund id (re_…)' using errcode = 'P0001';
  end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{1,80}$' then
    raise exception 'invalid_input: command_key must match ^[A-Za-z0-9._:-]{1,80}$' using errcode = 'P0001';
  end if;

  select r.refund_id, r.payment_id into v_id, v_pay
    from kernel.refund r where r.stripe_refund_ref = p_stripe_refund_ref;
  if v_id is null then
    return jsonb_build_object('status','not_bound','stripe_refund_ref', p_stripe_refund_ref);
  end if;

  select pn.order_id, o.org_id into v_order, v_org
    from kernel.payment_native pn
    left join venue."order" o on o.order_id = pn.order_id
   where pn.payment_id = v_pay;
  if v_org is not null then
    perform pg_advisory_xact_lock(hashtext('settlement.seam.org:' || v_org::text));
  end if;

  select * into v_row from kernel.refund where refund_id = v_id for update;
  if v_row.stripe_refund_ref is distinct from p_stripe_refund_ref then
    raise exception 'conflict_locked: refund % is not bound to %', v_id, p_stripe_refund_ref;
  end if;
  if v_row.status = 'failed' then
    return jsonb_build_object('status','noop_replay','refund_id', v_id, 'stripe_refund_ref', p_stripe_refund_ref);
  end if;
  if v_row.status = 'pending' then
    raise exception 'precondition_failed: refund_not_submitted (refund % is pending)', v_id;
  end if;

  select * into v_obs from public.payment_refund_state s where s.stripe_refund_id = p_stripe_refund_ref;
  if not found then
    raise exception 'precondition_failed: stripe_state_unrecorded (% has no payment_refund_state row)', p_stripe_refund_ref;
  end if;
  if v_obs.payment_id <> v_row.payment_id then
    raise exception 'conflict_locked: refund_payment_mismatch (% is observed on payment %; refund % is on payment %)',
      p_stripe_refund_ref, v_obs.payment_id, v_id, v_row.payment_id;
  end if;
  if v_obs.amount_cents <> v_row.amount_minor then
    raise exception 'conflict_locked: refund_amount_mismatch (% observed, % recorded)', v_obs.amount_cents, v_row.amount_minor;
  end if;
  if v_obs.status in ('pending','requires_action') then
    return jsonb_build_object('status','in_flight','refund_id', v_id, 'stripe_status', v_obs.status, 'refund_status', v_row.status);
  end if;
  if v_obs.status = 'succeeded' then
    return jsonb_build_object('status','not_failed','refund_id', v_id, 'stripe_status', v_obs.status, 'refund_status', v_row.status);
  end if;

  v_code := case v_obs.status
              when 'canceled' then 'refund_canceled'
              else coalesce(nullif(btrim(v_obs.failure_reason), ''), 'stripe_refund_failed')
            end;

  if v_row.status = 'submitted' then
    perform kernel.mark_refund_state(v_id, 'failed', p_stripe_refund_ref, v_code, p_command_key);
    return jsonb_build_object('status','ok','transition','submitted_to_failed','refund_id', v_id,
                              'failure_code', v_code, 'stripe_status', v_obs.status,
                              'settlement_review_required', false);
  end if;

  select jsonb_build_object('line_id', l.id, 'settlement_id', l.settlement_id,
                            'amount_minor', l.amount_minor, 'settlement_status', st.status)
    into v_line
    from venue.settlement_line l
    join venue.settlement st on st.settlement_id = l.settlement_id
   where l.cause = 'refund_void' and l.cause_ref = v_id;
  if v_line is not null then
    select jsonb_build_object('obligation_id', oo.obligation_id, 'status', oo.status, 'amount_minor', oo.amount_minor)
      into v_short
      from kernel.organization_obligation oo
     where oo.origin_kind = 'settlement_shortfall' and oo.origin_ref = (v_line ->> 'settlement_id')::uuid;
  end if;
  select jsonb_build_object('obligation_id', oo.obligation_id, 'status', oo.status, 'amount_minor', oo.amount_minor)
    into v_unl
    from kernel.organization_obligation oo
   where oo.origin_kind = 'unlined_reversal' and oo.origin_ref = v_id;
  select jsonb_build_object('obligation_id', io.obligation_id, 'status', io.status, 'amount_minor', io.amount_minor)
    into v_claw
    from kernel.identity_obligation io
   where io.origin_kind = 'refund_clawback' and io.origin_ref = v_id;
  select coalesce(jsonb_agg(ms.sale_id order by ms.sale_id), '[]'::jsonb) into v_comp
    from market.market_sale ms
   where ms.payment_id = v_row.payment_id and ms.terminal_state = 'compensated';
  select coalesce(jsonb_agg(l.ticket_atom_id order by l.ticket_atom_id), '[]'::jsonb) into v_atoms
    from kernel.ticket_ownership_log l
   where l.cause = 'refund_void' and l.cause_ref = v_id;
  v_promo := v_order is not null and exists (
               select 1 from venue.settlement_line l
                 join venue.attribution a on a.id = l.cause_ref
                where l.cause = 'promoter_commission' and a.order_id = v_order);
  v_review := v_line is not null or v_short is not null or v_unl is not null or v_claw is not null
              or jsonb_array_length(v_comp) > 0 or v_promo;

  update kernel.refund set status = 'failed', updated_at = now() where refund_id = v_id;

  v_facts := jsonb_build_object(
    'failure_code', v_code, 'stripe_status', v_obs.status, 'command_key', p_command_key,
    'payment_id', v_row.payment_id, 'order_id', v_order, 'amount_minor', v_row.amount_minor,
    'refund_void_line', v_line, 'settlement_shortfall_obligation', v_short,
    'unlined_reversal_obligation', v_unl, 'refund_clawback_obligation', v_claw,
    'compensated_market_sale_ids', v_comp, 'atoms_voided', v_atoms,
    'promoter_commission_lined', v_promo, 'settlement_review_required', v_review);

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (coalesce(auth.uid(), v_sys), 'refund.failed_after_success', 'refund', v_id, v_code,
          jsonb_build_object('status', 'succeeded', 'stripe_refund_ref', p_stripe_refund_ref),
          jsonb_build_object('status', 'failed') || v_facts);

  return jsonb_build_object('status','ok','transition','succeeded_to_failed','refund_id', v_id) || v_facts;
end;
$$;

-- ── 6. NEW kernel.park_refund_execution — the sweep's fenced park. service_role only.
create or replace function kernel.park_refund_execution(
  p_refund_id uuid, p_attempt integer, p_outcome text, p_reason_code text, p_command_key text)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_sys    constant uuid := '00000000-0000-0000-0000-0000000000f1';
  v_row    kernel.refund%rowtype;
  v_latest integer;
  v_claim  kernel.admin_audit%rowtype;
  v_hold   text;
begin
  if p_refund_id is null or p_command_key is distinct from 'refund.execute:' || p_refund_id::text then
    raise exception 'invalid_input: command_key is not the DB-issued refund.execute:<refund_id>' using errcode = 'P0001';
  end if;
  if p_outcome is null or p_outcome not in ('refused','stripe_error','state_sync_deferred') then
    raise exception 'invalid_input: outcome must be refused|stripe_error|state_sync_deferred' using errcode = 'P0001';
  end if;
  if p_reason_code is null or p_reason_code !~ '^[a-z][a-z0-9_]{0,63}$' then
    raise exception 'invalid_input: reason_code must match ^[a-z][a-z0-9_]{0,63}$' using errcode = 'P0001';
  end if;
  if p_attempt is null or p_attempt < 1 then
    raise exception 'invalid_input: attempt must be a positive claim attempt' using errcode = 'P0001';
  end if;

  select * into v_row from kernel.refund where refund_id = p_refund_id for update;
  if not found then
    raise exception 'not_found: refund %', p_refund_id using errcode = 'P0002';
  end if;
  if v_row.status not in ('pending','submitted') then
    return jsonb_build_object('status','not_parked','reason','terminal','refund_id', p_refund_id,
                              'refund_status', v_row.status);
  end if;

  select max((a.after ->> 'attempt')::integer) into v_latest
    from kernel.admin_audit a
   where a.subject_kind = 'refund' and a.subject_id = p_refund_id
     and a.action = 'refund.execute_claim'
     and (a.after ->> 'attempt') ~ '^[0-9]+$';
  if v_latest is null then
    raise exception 'precondition_failed: never_claimed (refund % has no refund.execute_claim row)', p_refund_id;
  end if;
  if p_attempt > v_latest then
    raise exception 'invalid_input: no_such_claim_attempt (% > latest %)', p_attempt, v_latest using errcode = 'P0001';
  end if;
  if p_attempt < v_latest then
    return jsonb_build_object('status','not_parked','reason','stale_attempt','refund_id', p_refund_id,
                              'attempt', p_attempt, 'latest_attempt', v_latest);
  end if;

  select * into v_claim from kernel.admin_audit a
   where a.subject_kind = 'refund' and a.subject_id = p_refund_id
     and a.action = 'refund.execute_claim' and (a.after ->> 'attempt') = p_attempt::text
   order by a.occurred_at desc, a.created_at desc
   limit 1;
  if (v_claim.before ->> 'status') is distinct from v_row.status then
    return jsonb_build_object('status','not_parked','reason','status_moved','refund_id', p_refund_id,
                              'claimed_status', v_claim.before ->> 'status', 'refund_status', v_row.status);
  end if;

  v_hold := kernel.refund_executor_hold(p_refund_id);
  if v_hold is not null then
    return jsonb_build_object('status','noop_replay','refund_id', p_refund_id, 'hold', v_hold);
  end if;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_sys, 'refund.execute_parked', 'refund', p_refund_id, p_reason_code,
          jsonb_build_object('status', v_row.status, 'stripe_refund_ref', v_row.stripe_refund_ref),
          jsonb_build_object('outcome', p_outcome, 'attempt', p_attempt, 'command_key', p_command_key,
                             'claimed_at', v_claim.occurred_at,
                             'execution_mode', v_claim.after ->> 'execution_mode'));
  return jsonb_build_object('status','ok','refund_id', p_refund_id, 'hold','parked',
                            'parked_status', v_row.status, 'attempt', p_attempt);
end;
$$;

-- ── 7. NEW kernel.rearm_refund_execution — the only exit from a park. authenticated only (service_role revoked).
create or replace function kernel.rearm_refund_execution(p_refund_id uuid, p_reason_code text, p_command_key text)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_aal   text;
  v_row   kernel.refund%rowtype;
  v_hold  text;
  v_unatt bigint;
begin
  if v_uid is null then
    raise exception 'insufficient_privilege: authenticated actor required' using errcode = '42501';
  end if;
  if not kernel.is_platform(array['platform_risk','platform_admin']) then
    raise exception 'insufficient_privilege: platform_risk or platform_admin required' using errcode = '42501';
  end if;
  v_aal := coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: a step-up (aal2) session is required to re-arm a parked refund';
  end if;
  if p_reason_code is null or p_reason_code !~ '^[a-z][a-z0-9_]{0,63}$' then
    raise exception 'invalid_input: reason_code must match ^[a-z][a-z0-9_]{0,63}$' using errcode = 'P0001';
  end if;
  if p_command_key is null or p_command_key !~ '^[A-Za-z0-9._:-]{8,80}$' then
    raise exception 'invalid_input: command_key must match ^[A-Za-z0-9._:-]{8,80}$' using errcode = 'P0001';
  end if;

  select * into v_row from kernel.refund where refund_id = p_refund_id for update;
  if not found then
    raise exception 'not_found: refund %', p_refund_id using errcode = 'P0002';
  end if;
  if v_row.status not in ('pending','submitted') then
    return jsonb_build_object('status','not_rearmed','reason','terminal','refund_id', p_refund_id,
                              'refund_status', v_row.status);
  end if;
  v_hold := kernel.refund_executor_hold(p_refund_id);
  if v_hold is null then
    return jsonb_build_object('status','noop_replay','refund_id', p_refund_id);
  end if;
  if v_hold = 'manual_record' then
    raise exception 'precondition_failed: manual_record_not_rearmable (refund %)', p_refund_id;
  end if;

  if v_row.status = 'pending' then
    select coalesce(sum(s.amount_cents), 0) into v_unatt
      from public.payment_refund_state s
     where s.payment_id = v_row.payment_id
       and s.status in ('pending','requires_action','succeeded')
       and not exists (select 1 from kernel.refund k
                        where k.payment_id = v_row.payment_id and k.stripe_refund_ref = s.stripe_refund_id);
    v_unatt := v_unatt + coalesce((
      select sum(pr.amount_cents) from public.payment_refunds pr
       where pr.payment_id = v_row.payment_id and pr.source <> 'dispute_lost'
         and pr.stripe_refund_id is not null
         and not exists (select 1 from public.payment_refund_state s2 where s2.stripe_refund_id = pr.stripe_refund_id)
         and not exists (select 1 from kernel.refund k2
                          where k2.payment_id = v_row.payment_id and k2.stripe_refund_ref = pr.stripe_refund_id)), 0);
    if v_unatt > 0 then
      raise exception 'precondition_failed: unattributed_stripe_refunds (% minor units on payment % are bound to no kernel refund)',
        v_unatt, v_row.payment_id;
    end if;
  end if;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'refund.execute_rearmed', 'refund', p_refund_id, p_reason_code,
          jsonb_build_object('status', v_row.status, 'hold', 'parked'),
          jsonb_build_object('command_key', p_command_key, 'aal', v_aal));
  return jsonb_build_object('status','ok','refund_id', p_refund_id, 'rearmed_status', v_row.status);
end;
$$;

-- ── 8. REPLACED ops.executor_claim — 118:614-688 byte-for-byte, the refunded-payment span (662-669) replaced.
create or replace function ops.executor_claim(p_action_id uuid, p_lease_seconds integer default 300)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  a    ops.action%rowtype;
  ap   ops.approval%rowtype;
  p    public.payments%rowtype;
  v_prev_sent boolean;
  v_cb        bigint;
  v_unobs     bigint;
  v_detail    jsonb;
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
  v_prev_sent := a.attempt > 0 or a.provider_ref is not null or (a.result ? 'stripe_request_started_at');
  if p.refund_succeeded_cents >= p.total then
    return jsonb_build_object('status','refused','reason','already_refunded_locally','state', a.state, 'stripe_refund_id', p.stripe_refund_id);
  end if;
  if p.status = 'refunded' then
    v_cb := coalesce((select sum(pr.amount_cents) from public.payment_refunds pr
                       where pr.payment_id = p.id and pr.source = 'dispute_lost'), 0);
    v_detail := jsonb_build_object('payment_status', p.status, 'total_cents', p.total,
                                   'requested_cents', p.refund_requested_cents,
                                   'succeeded_cents', p.refund_succeeded_cents,
                                   'failed_cents', p.refund_failed_cents,
                                   'amount_refunded_cents', p.amount_refunded_cents,
                                   'chargeback_cents', v_cb,
                                   'previously_sent', v_prev_sent);
    if p.refund_succeeded_cents + v_cb >= p.total then
      return jsonb_build_object('status','refused','reason','charged_back','state', a.state, 'detail', v_detail);
    end if;
    if not coalesce(v_prev_sent, false) then
      v_unobs := coalesce((select sum(pr.amount_cents) from public.payment_refunds pr
                            where pr.payment_id = p.id and pr.source <> 'dispute_lost'
                              and pr.stripe_refund_id is not null
                              and not exists (select 1 from public.payment_refund_state s
                                               where s.stripe_refund_id = pr.stripe_refund_id)), 0);
      if v_unobs > 0 then
        return jsonb_build_object('status','refused','reason','refund_state_unobserved','state', a.state,
                                  'detail', v_detail || jsonb_build_object('unobserved_cents', v_unobs));
      end if;
      return jsonb_build_object('status','refused','reason','refund_state_unresolved','state', a.state, 'detail', v_detail);
    end if;
    if p.stripe_payment_intent_id is null then
      return jsonb_build_object('status','refused','reason','payment_not_refundable','state', a.state, 'payment_status', p.status);
    end if;
  elsif p.status <> 'succeeded' or p.stripe_payment_intent_id is null then
    return jsonb_build_object('status','refused','reason','payment_not_refundable','state', a.state, 'payment_status', p.status);
  end if;
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

-- ── ACLs. New functions as designed; replaced bodies: idempotent re-issue of their existing ACL.
revoke all on function kernel.refund_executor_hold(uuid) from public, anon, authenticated, service_role;
revoke all on function kernel.record_refund_stripe_failure(text,text) from public, anon, authenticated, service_role;
grant execute on function kernel.record_refund_stripe_failure(text,text) to service_role;
revoke all on function kernel.park_refund_execution(uuid,integer,text,text,text) from public, anon, authenticated, service_role;
grant execute on function kernel.park_refund_execution(uuid,integer,text,text,text) to service_role;
revoke all on function kernel.rearm_refund_execution(uuid,text,text) from public, anon, authenticated, service_role;
grant execute on function kernel.rearm_refund_execution(uuid,text,text) to authenticated;
revoke all on function kernel.mark_refund_state(uuid,text,text,text,text) from public, anon, authenticated;
grant execute on function kernel.mark_refund_state(uuid,text,text,text,text) to service_role;
revoke all on function kernel.claim_refunds_for_execution(integer,integer) from public, anon, authenticated;
grant execute on function kernel.claim_refunds_for_execution(integer,integer) to service_role;
revoke all on function kernel.get_refund_execution_context(uuid) from public, anon, authenticated;
grant execute on function kernel.get_refund_execution_context(uuid) to service_role;
revoke all on function ops.executor_claim(uuid,integer) from public, anon, authenticated;
grant execute on function ops.executor_claim(uuid,integer) to service_role;

-- ── Rationale (outside the pinned bodies: an object comment does not change pg_get_functiondef).
comment on function kernel.refund_executor_hold(uuid) is
  'Registry 199. The single executor-exclusion predicate: ''manual_record'' when the row was written by refund_primary_order''s DIRECT arm (its same-transaction refund.issue audit, subject the order, after.refund_id = the row, after.delegated = false), ''parked'' when an unfinished row has more refund.execute_parked than refund.execute_rearmed audit rows recorded at its CURRENT status (counts, not timestamps: now() is frozen per transaction; status-scoped, so a park at pending stops applying once the row is submitted), else NULL. Executable by nobody but its owner; reached definer-to-definer by the claim, the context, the park and the re-arm. cancel_event rows, admin_refund rows and delegated req: rows are never marked.';
comment on function kernel.mark_refund_state(uuid,text,text,text,text) is
  'Registry 199 (body 085 + one guard). Forward-only pending -> submitted -> succeeded | failed under FOR UPDATE, check order unchanged (input, lock, noop, direction, ref mandatory, write-once ref, failure code). New: `succeeded` is refused (precondition_failed: refund_failed_at_stripe) when public.payment_refund_state records the ref as failed or canceled, so the kernel never says succeeded for money Stripe did not return. The recorded state is a consistency input, not authentication (service_role holds DML on it). The row stays submitted and the next sweep reconciles it to failed.';
comment on function kernel.claim_refunds_for_execution(integer,integer) is
  'Registry 199 (body 093 + two insertions + one mode line). The executor''s leased work list. Excludes any row kernel.refund_executor_hold marks (manual_record or parked), in the cursor and again under the row lock: the cursor snapshot is fixed when it opens and a lock-only xmax triggers no EvalPlanQual, so a claim or park committed after that snapshot is re-checked with a fresh READ COMMITTED statement snapshot; rows dropped there were already counted by LIMIT, so a batch may come back under-filled (harmless). Mode: submitted always reconcile; a pending row is create only when created inside the 20 h window (created_at precedes any POST with the row''s key, so every earlier POST is still deduped by Stripe); older pending rows reconcile even with no claim row, because a POST may have come through action:execute, which writes none. A re-armed row therefore never creates blind after the window.';
comment on function kernel.get_refund_execution_context(uuid) is
  'Registry 199 (093''s fifteen keys, now plpgsql STABLE). The executor''s only binding read: unknown id -> SQL NULL; terminal rows -> the object (planReconcile''s noop_replay stays reachable); a pending or submitted row that kernel.refund_executor_hold marks -> raises precondition_failed: executor_hold <manual_record|parked> (refund <id>), which refund-execute''s loadContext maps to HTTP 409, so every Stripe POST path (sweep or action:execute, create or reconcile) fails closed for a held row without any edge change.';
comment on function kernel.record_refund_stripe_failure(text,text) is
  'Registry 199. The single post-failure converger, called by stripe-webhook for a failed or canceled Stripe refund. Resolves the row only by its own write-once stripe_refund_ref (never Stripe metadata); not_bound when none. Takes the org settlement seam lock, then the row lock. failed -> noop_replay; pending -> refund_not_submitted. Requires a recorded public.payment_refund_state row whose payment and amount equal the row''s (binding before verdict; a mismatch is conflict_locked, never a convergence). Stripe pending/requires_action -> in_flight, succeeded -> not_failed, both with no write. The failure code comes from the recorded state (canceled -> refund_canceled; else failure_reason, default stripe_refund_failed), never from the caller. submitted -> failed via mark_refund_state. succeeded -> failed (the one new transition) writes refund.failed_after_success with the residue: the refund_void line and its settlement, any settlement_shortfall / unlined_reversal / refund_clawback obligation, compensated market_sale ids, atoms voided, promoter commission lined, and settlement_review_required. It records exposure; it never writes lines, atoms, orders, obligations or public.* (O-1/O-2).';
comment on function kernel.park_refund_execution(uuid,integer,text,text,text) is
  'Registry 199. Parks an unfinished refund after a non-retryable executor outcome (refused | stripe_error | state_sync_deferred). Only the sweep holds the DB-issued key refund.execute:<refund_id>. Fenced by the latest claim attempt (attempt = count+1 minted under the row lock, so unique per refund): a stale attempt -> not_parked/stale_attempt, a future one -> no_such_claim_attempt, never claimed -> never_claimed. Scoped to the status that claim saw (status_moved otherwise). Terminal -> not_parked/terminal; already held -> noop_replay. Writes only refund.execute_parked (no free-form payload).';
comment on function kernel.rearm_refund_execution(uuid,text,text) is
  'Registry 199. The only exit from a park: a human platform_risk or platform_admin at aal2 (never service_role — a machine that executes money must not re-arm it; precedent rearm_failed_payout). A manual_record row is not re-armable. For a pending row it refuses while Stripe money on the payment (recorded refund state pending/requires_action/succeeded, or a payment_refunds row with no recorded state, dispute_lost excluded) is bound to no kernel refund, because a pending row''s reconcile searches only metadata.refund_id. Writes refund.execute_rearmed; the next claim''s mode follows the claim''s window rule. Limit: a Dashboard refund whose webhook has not been processed is invisible here; check the Dashboard first.';
comment on function ops.executor_claim(uuid,integer) is
  'Registry 199 (body 118, the refunded-payment span replaced). Gates 1-12 unchanged. already_refunded_locally only when payments.refund_succeeded_cents >= total (Stripe-confirmed), never on the one-way refunded flag. A payment marked refunded is refused charged_back when succeeded + lost-dispute money covers the total; for a fresh action refund_state_unobserved (a recorded refund with no Stripe state; detail.unobserved_cents) or refund_state_unresolved, each with detail {payment_status,total_cents,requested_cents,succeeded_cents,failed_cents,amount_refunded_cents,chargeback_cents,previously_sent}; a previously-sent action is admitted so the handler''s list-before-POST adopts its own refund. payments is read without a lock, as before.';

-- ── POST-FLIGHT: bodies, posture, ACLs, argnames, dependencies, writer census. Any failure rolls the file back.
do $pc$
declare
  r       record;
  v_md5   text;
  v_acl   text;
  v_pre   jsonb := current_setting('migration_199.preflight')::jsonb;
  v_now   jsonb;
  v_w     text;
begin
  for r in
    select * from (values
      ('kernel.refund_executor_hold(uuid)',                         '31d6705d651d04ef82191faec528ad27',  's', 'postgres:EXECUTE'),
      ('kernel.mark_refund_state(uuid,text,text,text,text)',        'a14aafa2040db639a18f64aa30e5b6f1',  'v', null),
      ('kernel.claim_refunds_for_execution(integer,integer)',       '3664f28dc744d274ff8813309edf9fd0', 'v', null),
      ('kernel.get_refund_execution_context(uuid)',                 '8aede0fc7dbdb0bc37a53d53c0eda51e',   's', null),
      ('kernel.record_refund_stripe_failure(text,text)',            'ba2de45d6283db5afcc954b7d401596d',  'v', 'postgres:EXECUTE,service_role:EXECUTE'),
      ('kernel.park_refund_execution(uuid,integer,text,text,text)', '822d2d2fd0cfd3e39f8fe6f1f0baec74',  'v', 'postgres:EXECUTE,service_role:EXECUTE'),
      ('kernel.rearm_refund_execution(uuid,text,text)',             '977edd52c3d535a36f7431ea008a2bb9', 'v', 'authenticated:EXECUTE,postgres:EXECUTE'),
      ('ops.executor_claim(uuid,integer)',                          '2d658f3406ea6e774fd8f6dcb163a27f',  'v', null)
    ) as t(sig, want_md5, want_vol, want_acl)
  loop
    if to_regprocedure(r.sig) is null then
      raise exception 'POSTFLIGHT_199_FAILED: % does not resolve', r.sig;
    end if;
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if v_md5 <> r.want_md5 then
      raise exception 'POSTFLIGHT_199_FAILED: % body md5 % is not 199''s (%) — this file was modified', r.sig, v_md5, r.want_md5;
    end if;
    if not exists (select 1 from pg_proc p
                    where p.oid = to_regprocedure(r.sig)
                      and p.prosecdef
                      and p.proconfig = array['search_path=""']
                      and p.proowner = 'postgres'::regrole
                      and p.provolatile::text = r.want_vol) then
      raise exception 'POSTFLIGHT_199_FAILED: % posture (SECURITY DEFINER, search_path '''', owner postgres, volatility %) not as decided',
        r.sig, r.want_vol;
    end if;
    if r.want_acl is not null then
      select string_agg(e.entry, ',' order by e.entry) into v_acl
        from pg_proc p,
             lateral (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                             || ':' || a.privilege_type as entry
                        from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) e
       where p.oid = to_regprocedure(r.sig);
      if v_acl is distinct from r.want_acl then
        raise exception 'POSTFLIGHT_199_FAILED: % ACL is %, not %', r.sig, v_acl, r.want_acl;
      end if;
    else
      select jsonb_build_object(
               'acl',    (select jsonb_agg(x order by x) from unnest(coalesce(p.proacl, acldefault('f', p.proowner))::text[]) x),
               'secdef', p.prosecdef,
               'config', to_jsonb(p.proconfig),
               'owner',  p.proowner::regrole::text)
        into v_now
        from pg_proc p where p.oid = to_regprocedure(r.sig);
      if v_now is distinct from (v_pre -> r.sig) then
        raise exception 'POSTFLIGHT_199_FAILED: % posture moved: pre-flight % / now %', r.sig, v_pre -> r.sig, v_now;
      end if;
    end if;
  end loop;

  if (select proargnames from pg_proc where oid = to_regprocedure('kernel.claim_refunds_for_execution(integer,integer)'))
       is distinct from array['p_limit','p_lease_seconds']
     or (select proargnames from pg_proc where oid = to_regprocedure('kernel.get_refund_execution_context(uuid)'))
       is distinct from array['p_refund_id']
     or (select proargnames from pg_proc where oid = to_regprocedure('ops.executor_claim(uuid,integer)'))
       is distinct from array['p_action_id','p_lease_seconds'] then
    raise exception 'POSTFLIGHT_199_FAILED: an argument name of the claim, the context or ops.executor_claim moved';
  end if;

  if md5(pg_get_functiondef(to_regprocedure('kernel.refund_primary_order(uuid,integer,text,text)'))) is distinct from 'e0a37574a02131e4cedec43a2ef427f7'
     or md5(pg_get_functiondef(to_regprocedure('public.record_refund_state(text,text,text,integer,text,text,text)'))) is distinct from '5e9f66129a4bb82b6b3e7a1b41e04365'
     or md5(pg_get_functiondef(to_regprocedure('kernel.settlement_primary_lines(uuid)'))) is distinct from 'ebc5d6c16334e55e39ceea63d9eab7f6' then
    raise exception 'POSTFLIGHT_199_FAILED: a dependency body moved (refund_primary_order, record_refund_state or settlement_primary_lines)';
  end if;

  if exists (select 1 from pg_proc p
              where p.oid in (to_regprocedure('kernel.refund_executor_hold(uuid)'),
                              to_regprocedure('kernel.mark_refund_state(uuid,text,text,text,text)'),
                              to_regprocedure('kernel.claim_refunds_for_execution(integer,integer)'),
                              to_regprocedure('kernel.get_refund_execution_context(uuid)'),
                              to_regprocedure('kernel.record_refund_stripe_failure(text,text)'),
                              to_regprocedure('kernel.park_refund_execution(uuid,integer,text,text,text)'),
                              to_regprocedure('kernel.rearm_refund_execution(uuid,text,text)'),
                              to_regprocedure('ops.executor_claim(uuid,integer)'))
                and p.prosrc ~ '(record_primary_refund|primary_reconciliation)') then
    raise exception 'POSTFLIGHT_199_FAILED: a 199 body names a 189 function (189''s rollback guard would be blocked)';
  end if;

  -- the writer census: exactly two functions UPDATE kernel.refund
  select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname || '.' || p.proname) into v_w
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog', 'information_schema', 'tap') and n.nspname !~ '^pg_'
     and p.prosrc ~* 'update\s+kernel\.refund\s';
  if v_w is distinct from 'kernel.mark_refund_state,kernel.record_refund_stripe_failure' then
    raise exception 'POSTFLIGHT_199_FAILED: the kernel.refund UPDATE writers are %, not mark_refund_state + record_refund_stripe_failure', v_w;
  end if;

  if has_table_privilege('anon', 'kernel.admin_audit', 'INSERT')
     or has_table_privilege('authenticated', 'kernel.admin_audit', 'INSERT')
     or has_table_privilege('service_role', 'kernel.admin_audit', 'INSERT') then
    raise exception 'POSTFLIGHT_199_FAILED: a client or machine role holds INSERT on kernel.admin_audit';
  end if;
end $pc$;

commit;
