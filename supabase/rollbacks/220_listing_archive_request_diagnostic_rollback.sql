begin;
DO $$begin if (select md5(prosrc)from pg_proc where oid=to_regprocedure('ops.prelaunch_listing_diagnose()')) is distinct from 'e1415d101e252da601d77e900a7a0ce7' then raise exception 'rollback_refused: diagnostic source drift';end if;end$$;
drop function ops.prelaunch_listing_diagnose();
commit;
