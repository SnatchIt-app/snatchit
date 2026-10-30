-- ============================================================================
-- 092_notify_reduced_rollback.sql — REVERSES 092_notify_reduced.sql
-- ----------------------------------------------------------------------------
-- POSTURE (registry row 092; 091 precedent): CLEAN-WHILE-EMPTY. A notification
-- that a person has already received is a delivered fact (§5.3: the wire copy
-- is what they were sent), so the guard refuses once any notify.notification
-- or notify.delivery row exists, once any public.push_tokens row carries a
-- 092 column value, once any notify.outbox row carries an expansion cursor,
-- and once any routine outside this package references a 092 table.
-- Registry/template SEED rows are this package's own bytes and are not facts.
-- ORDERING WITH LATER PACKAGES: none (092 is the chain tip; the train ends).
-- ORDER: 1 guard · 2 cron · 3 config key · 4 the 15 routines · 5 tables
-- children-first · 6 the additive columns · 7 the schema USAGE grant.
-- 076's notify.outbox and the emit pair are NOT touched.
-- ============================================================================
begin;

-- 1 — CLEAN-WHILE-EMPTY guard (RLS is on with zero policies on four of the six
-- tables — count with row_security off so the guard cannot fail open, 091 lesson)
do $$
declare v_notifs bigint; v_deliveries bigint; v_prefs bigint; v_tokens bigint; v_cursors bigint; v_refs bigint;
begin
  if to_regclass('notify.notification') is null and to_regclass('notify.notification_type') is null then
    raise notice '092 rollback: already rolled back (no 092 table present) — the remaining statements are no-ops';
    return;
  end if;
  set local row_security = off;
  lock table notify.notification in access exclusive mode;
  lock table notify.delivery in access exclusive mode;
  select count(*) into v_notifs from notify.notification;
  select count(*) into v_deliveries from notify.delivery;
  select count(*) into v_prefs from notify.preference;
  select count(*) into v_tokens from public.push_tokens
   where revoked_at is not null or revoked_reason is not null or provider_receipt_checked_at is not null or last_provider_error is not null;
  select count(*) into v_cursors from notify.outbox where expand_cursor is not null or expanded_count <> 0;
  -- any routine OUTSIDE this package that names a 092 table (the 091 guard shape)
  select count(*) into v_refs
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('kernel','catalog','venue','market','notify','public')
     and not (n.nspname = 'notify' and p.proname in ('drain_outbox','enqueue','channel_enabled','claim_deliveries','record_delivery_result',
              'resolve_web_link','get_inbox','get_unread_count','mark_read','mark_all_read','dismiss','get_preference_matrix',
              'set_preference','register_push_token','revoke_push_token'))
     and p.prosrc ~ '(notify|"notify")\s*\.\s*"?(notification_type|notification|delivery|preference|template|identity_channel_state)"?\M';
  if v_notifs > 0 or v_deliveries > 0 or v_prefs > 0 or v_tokens > 0 or v_cursors > 0 or v_refs > 0 then
    raise exception 'rollback_refused: 092 is not clean — % notification(s), % delivery row(s), % preference row(s), % push_tokens row(s) carrying 092 columns, % outbox expansion cursor(s), % external routine reference(s); forward-fix instead (CLEAN-WHILE-EMPTY)',
      v_notifs, v_deliveries, v_prefs, v_tokens, v_cursors, v_refs;
  end if;
end $$;

-- 2 — cron (guarded: a partially-applied 092 may carry no row)
select cron.unschedule(jobname) from cron.job where jobname = 'notify-drain-outbox';

-- 3 — the owner-unset config key (its own bytes; never set to a value by 092).
-- catalog.platform_config is APPEND-ONLY (078 tg_platform_config_append_only);
-- the 085 rollback precedent lifts the trigger for exactly this delete.
alter table catalog.platform_config disable trigger tg_platform_config_append_only;
delete from catalog.platform_config where key = 'notify.delivery_lease_interval';
alter table catalog.platform_config enable trigger tg_platform_config_append_only;

-- 4 — the 15 routines
drop function if exists notify.drain_outbox(integer);
drop function if exists notify.enqueue(uuid,text,text,uuid,jsonb,text);
drop function if exists notify.channel_enabled(uuid,text,text);
drop function if exists notify.claim_deliveries(text,integer);
drop function if exists notify.record_delivery_result(uuid,text,text,text,text,text,text);
drop function if exists notify.resolve_web_link(text,uuid);
drop function if exists notify.get_inbox(timestamptz,integer);
drop function if exists notify.get_unread_count();
drop function if exists notify.mark_read(uuid[]);
drop function if exists notify.mark_all_read();
drop function if exists notify.dismiss(uuid[]);
drop function if exists notify.get_preference_matrix();
drop function if exists notify.set_preference(text,text,boolean);
drop function if exists notify.register_push_token(text,text,text,text);
drop function if exists notify.revoke_push_token(text);

-- 5 — tables, children first (policies / grants / indexes ride along)
drop table if exists notify.delivery;
drop table if exists notify.preference;
drop table if exists notify.notification;
drop table if exists notify.identity_channel_state;
drop table if exists notify.template;
drop table if exists notify.notification_type;

-- 6 — the additive columns
alter table notify.outbox drop column if exists expand_cursor;
alter table notify.outbox drop column if exists expanded_count;
drop index if exists public.push_tokens_live_idx;
alter table public.push_tokens drop column if exists revoked_at;
alter table public.push_tokens drop column if exists revoked_reason;
alter table public.push_tokens drop column if exists provider_receipt_checked_at;
alter table public.push_tokens drop column if exists last_provider_error;

-- 7 — the client-side schema USAGE 092 opened (076's wall is restored)
revoke usage on schema notify from authenticated;

commit;
