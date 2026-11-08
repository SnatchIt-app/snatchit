-- Registry 206. Fresh-stack permissions and cancellation guard, complementing
-- the isolated lifecycle, concurrent-writer and rollback cases in CI.
begin;
select plan(7);

select is((
  select count(*)::int from pg_class
  where oid in (to_regclass('venue.payment_attempt'), to_regclass('venue.payment_attempt_event'))
    and relrowsecurity
), 2, 'both attempt tables enforce RLS');

select ok(not exists (
  select 1
  from unnest(array['anon','authenticated','service_role']) as roles(role_name)
  cross join unnest(array['venue.payment_attempt','venue.payment_attempt_event']) as tables(table_name)
  where has_table_privilege(role_name, table_name, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
), 'clients and service role have no direct access to either table');

with signatures(signature) as (values
  ('venue.begin_payment_attempt(uuid,text,uuid,uuid,integer,integer,integer,text)'),
  ('venue.store_payment_attempt_request(uuid,uuid,uuid,uuid,jsonb)'),
  ('venue.attach_payment_attempt(uuid,text,uuid,uuid,uuid,integer,integer,integer,text)'),
  ('venue.mark_payment_attempt(uuid,text,text)'),
  ('venue.mark_payment_attempt_by_pi(text,text,text)'),
  ('venue.read_payment_attempt_recovery(uuid,uuid,uuid)'),
  ('venue.read_payment_attempt_binding(uuid,text,uuid,uuid)'),
  ('venue.read_lapse_payment_attempts(uuid,uuid,uuid)'),
  ('venue.is_settled_native_payment_replay(uuid,uuid,uuid,text,uuid,integer,text,boolean)')
)
select is((
  select count(*)::int from signatures
  join pg_proc p on p.oid = to_regprocedure(signature)
  where p.prosecdef and p.proconfig @> array['search_path=""']
    and has_function_privilege('service_role', p.oid, 'EXECUTE')
    and not has_function_privilege('anon', p.oid, 'EXECUTE')
    and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
), 9, 'all nine RPCs have a pinned search path and service-only execution');

select is((
  select count(*)::int from pg_trigger
  where not tgisinternal and tgenabled = 'O'
    and ((tgrelid = to_regclass('venue."order"') and tgname = 'guard_order_cancel_attempts'
          and tgfoid = to_regprocedure('venue.guard_order_cancel_attempts()'))
      or (tgrelid = to_regclass('venue.payment_attempt_event') and tgname = 'payment_attempt_event_append_only'
          and tgfoid = to_regprocedure('venue.payment_attempt_event_append_only()')))
), 2, 'order cancellation and append-only event triggers are enabled');

select ok(not exists (
  select 1 from unnest(array['anon','authenticated','service_role']) as roles(role_name)
  where has_sequence_privilege(role_name, 'venue.payment_attempt_event_event_id_seq', 'USAGE,SELECT,UPDATE')
), 'the event identity sequence has no direct client or service access');

select is((
  select count(*)::int from pg_proc p
  where p.oid in (to_regprocedure('venue.guard_order_cancel_attempts()'),
                  to_regprocedure('venue.payment_attempt_event_append_only()'))
    and not has_function_privilege('anon', p.oid, 'EXECUTE')
    and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and not has_function_privilege('service_role', p.oid, 'EXECUTE')
), 2, 'only triggers use the internal helper functions');

select is(md5(pg_get_functiondef(to_regprocedure('venue.cancel_pending_order(uuid,text,text)'))),
  '3d7fef64c44483586f46b568cb92c610', 'existing cancellation RPC body is unchanged');

select * from finish();
rollback;
