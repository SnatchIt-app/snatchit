begin;
DO $$begin if (select md5(prosrc)from pg_proc where oid=to_regprocedure('ops.prelaunch_listing_diagnose()')) is distinct from '75bbea6f89fef612d771c4cf799777aa' then raise exception 'rollback_refused: diagnostic source drift';end if;end$$;
drop function ops.prelaunch_listing_diagnose();
commit;
