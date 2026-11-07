-- OC-PAYMENT-ATOMIC-COORDINATION-1 — LOCAL DRAFT ROLLBACK ONLY. DO NOT APPLY.
-- One transaction. Any failed preflight raises before DDL and restores all.
-- Refuses on unresolved attempts, pending orders, active holds, mixed/partial
-- active/retired pairs, archive collisions, or missing active RPCs. No CASCADE,
-- no DROP TABLE, no data erase. The archive append-only trigger/function is
-- retained intentionally; only the active RPCs and cancel trigger are removed.
begin;

-- Keep concurrent writers out between the drain check and trigger removal.
set local lock_timeout = '3s';
lock table venue."order", venue.inventory_hold in share row exclusive mode;

do $rollback$
declare
  v_active_attempt boolean := to_regclass('venue.payment_attempt') is not null;
  v_active_event   boolean := to_regclass('venue.payment_attempt_event') is not null;
  v_ret_attempt    boolean := to_regclass('venue.payment_attempt_retired_20261103') is not null;
  v_ret_event      boolean := to_regclass('venue.payment_attempt_event_retired_20261103') is not null;
  v_any_rpc        boolean;
  v_all_rpc        boolean;
  v_guard_fn       boolean;
  v_guard_trigger  boolean;
  v_active_fn_count integer;
  v_n              integer;
begin
  if to_regclass('venue."order"') is null then
    raise exception 'precondition_failed: venue."order" is missing; rollback refused'
      using errcode = 'P0001';
  end if;
  if v_active_attempt <> v_active_event then
    raise exception 'precondition_failed: partial active attempt/event pair; rollback refused'
      using errcode = 'P0001';
  end if;
  if v_ret_attempt <> v_ret_event then
    raise exception 'precondition_failed: partial retired attempt/event pair; rollback refused'
      using errcode = 'P0001';
  end if;
  if v_active_attempt and v_ret_attempt then
    raise exception 'precondition_failed: active and retired pairs collide; rollback refused'
      using errcode = 'P0001';
  end if;

  v_any_rpc :=
       to_regprocedure('venue.begin_payment_attempt(uuid,text,uuid,uuid,integer,integer,integer,text)') is not null
    or to_regprocedure('venue.store_payment_attempt_request(uuid,uuid,uuid,uuid,jsonb)') is not null
    or to_regprocedure('venue.attach_payment_attempt(uuid,text,uuid,uuid,uuid,integer,integer,integer,text)') is not null
    or to_regprocedure('venue.mark_payment_attempt(uuid,text,text)') is not null
    or to_regprocedure('venue.mark_payment_attempt_by_pi(text,text,text)') is not null
    or to_regprocedure('venue.read_payment_attempt_recovery(uuid,uuid,uuid)') is not null
    or to_regprocedure('venue.read_payment_attempt_binding(uuid,text,uuid,uuid)') is not null
    or to_regprocedure('venue.read_lapse_payment_attempts(uuid,uuid,uuid)') is not null;
  v_all_rpc :=
       to_regprocedure('venue.begin_payment_attempt(uuid,text,uuid,uuid,integer,integer,integer,text)') is not null
   and to_regprocedure('venue.store_payment_attempt_request(uuid,uuid,uuid,uuid,jsonb)') is not null
   and to_regprocedure('venue.attach_payment_attempt(uuid,text,uuid,uuid,uuid,integer,integer,integer,text)') is not null
   and to_regprocedure('venue.mark_payment_attempt(uuid,text,text)') is not null
   and to_regprocedure('venue.mark_payment_attempt_by_pi(text,text,text)') is not null
   and to_regprocedure('venue.read_payment_attempt_recovery(uuid,uuid,uuid)') is not null
   and to_regprocedure('venue.read_payment_attempt_binding(uuid,text,uuid,uuid)') is not null
   and to_regprocedure('venue.read_lapse_payment_attempts(uuid,uuid,uuid)') is not null;
  v_guard_fn := to_regprocedure('venue.guard_order_cancel_attempts()') is not null;
  select count(*) into v_active_fn_count
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'venue'
     and p.proname in ('begin_payment_attempt','store_payment_attempt_request',
                       'attach_payment_attempt','mark_payment_attempt',
                       'mark_payment_attempt_by_pi','read_payment_attempt_recovery',
                       'read_payment_attempt_binding','read_lapse_payment_attempts','guard_order_cancel_attempts');
  select exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'venue."order"'::regclass
       and t.tgname = 'guard_order_cancel_attempts'
       and not t.tgisinternal
  ) into v_guard_trigger;

  if v_active_attempt then
    if v_active_fn_count <> 9 or not v_all_rpc or not v_guard_fn or not v_guard_trigger then
      raise exception 'precondition_failed: active pair has missing/extra function overloads or missing cancel trigger; rollback refused'
        using errcode = 'P0001';
    end if;
    if to_regprocedure('venue.payment_attempt_event_append_only()') is null
       or not exists (
         select 1 from pg_trigger t
          where t.tgrelid = 'venue.payment_attempt_event'::regclass
            and t.tgname = 'payment_attempt_event_append_only'
            and not t.tgisinternal
       ) then
      raise exception 'precondition_failed: active event append-only protection is missing; rollback refused'
        using errcode = 'P0001';
    end if;

    execute 'select count(*) from venue.payment_attempt where state <> ''canceled''' into v_n;
    if v_n <> 0 then
      raise exception 'precondition_failed: unresolved payment attempts exist; rollback refused'
        using errcode = 'P0001';
    end if;
    if not exists (select 1 from venue."order" where status = 'pending') then
      null;
    else
      raise exception 'precondition_failed: pending venue orders exist; rollback refused'
        using errcode = 'P0001';
    end if;
    if to_regclass('venue.inventory_hold') is null then
      raise exception 'precondition_failed: venue.inventory_hold is missing; rollback refused'
        using errcode = 'P0001';
    end if;
    execute 'select count(*) from venue.inventory_hold where status = ''active''' into v_n;
    if v_n <> 0 then
      raise exception 'precondition_failed: active inventory holds exist; rollback refused'
        using errcode = 'P0001';
    end if;

    -- Retire the pair exactly once. Indexes/constraints travel with the tables;
    -- the append-only trigger and its function are deliberately NOT dropped.
    execute 'alter table venue.payment_attempt_event rename to payment_attempt_event_retired_20261103';
    execute 'alter table venue.payment_attempt rename to payment_attempt_retired_20261103';

    execute 'drop trigger if exists guard_order_cancel_attempts on venue."order"';
    execute 'drop function if exists venue.guard_order_cancel_attempts()';
    execute 'drop function if exists venue.read_payment_attempt_recovery(uuid, uuid, uuid)';
    execute 'drop function if exists venue.store_payment_attempt_request(uuid, uuid, uuid, uuid, jsonb)';
    execute 'drop function if exists venue.read_lapse_payment_attempts(uuid, uuid, uuid)';
    execute 'drop function if exists venue.read_payment_attempt_binding(uuid, text, uuid, uuid)';
    execute 'drop function if exists venue.mark_payment_attempt_by_pi(text, text, text)';
    execute 'drop function if exists venue.mark_payment_attempt(uuid, text, text)';
    execute 'drop function if exists venue.attach_payment_attempt(uuid, text, uuid, uuid, uuid, integer, integer, integer, text)';
    execute 'drop function if exists venue.begin_payment_attempt(uuid, text, uuid, uuid, integer, integer, integer, text)';

    if to_regprocedure('venue.payment_attempt_event_append_only()') is null
       or not exists (
         select 1 from pg_trigger t
          where t.tgrelid = 'venue.payment_attempt_event_retired_20261103'::regclass
            and t.tgname = 'payment_attempt_event_append_only'
            and not t.tgisinternal
       ) then
      raise exception 'postcondition_failed: retired event archive lost append-only protection'
        using errcode = 'P0001';
    end if;
    return;
  end if;

  -- No active pair. Anything still active is a partial state.
  if v_active_fn_count <> 0 or v_any_rpc or v_guard_fn or v_guard_trigger then
    raise exception 'precondition_failed: active RPCs/overloads/trigger remain without active tables; rollback refused'
      using errcode = 'P0001';
  end if;
  if v_ret_attempt then
    if to_regprocedure('venue.payment_attempt_event_append_only()') is null
       or not exists (
         select 1 from pg_trigger t
          where t.tgrelid = 'venue.payment_attempt_event_retired_20261103'::regclass
            and t.tgname = 'payment_attempt_event_append_only'
            and not t.tgisinternal
       ) then
      raise exception 'precondition_failed: retired archive append-only protection is missing; rollback refused'
        using errcode = 'P0001';
    end if;
    return; -- complete retired pair + no active: safe repeat NOOP
  end if;

  -- Neither active nor retired pair. A lingering append-only helper is partial.
  if to_regprocedure('venue.payment_attempt_event_append_only()') is not null then
    raise exception 'precondition_failed: orphan append-only function without active/retired tables; rollback refused'
      using errcode = 'P0001';
  end if;
  return; -- not installed: safe NOOP
end;
$rollback$;

commit;
