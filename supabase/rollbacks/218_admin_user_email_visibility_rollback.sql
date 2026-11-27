begin;
DO $guard$ begin
 if to_regprocedure('ops.admin_user_emails(uuid[])') is not null and (select md5(prosrc) from pg_proc where oid='ops.admin_user_emails(uuid[])'::regprocedure) is distinct from '17418111c6d9500434c991e248ccbdaa' then raise exception 'rollback_refused: contact reader drift';end if;
end $guard$;
drop function if exists ops.admin_user_emails(uuid[]);
commit;
