begin;
DO $rollback$
declare d text;
begin
 if exists(select from ops.prelaunch_listing_archive where archived_at is not null) then raise exception 'rollback_refused: completed archive history retained';end if;
 if (select md5(prosrc)from pg_proc where oid='ops.prelaunch_listing_execute(text,text,text)'::regprocedure) is distinct from '69a5871a35eedccf6c678cf4cabb0b1b' then raise exception 'rollback_refused: archive executor drift';end if;
 select pg_get_functiondef('ops.prelaunch_listing_execute(text,text,text)'::regprocedure)into d;
 execute replace(d,$new$update ops.prelaunch_listing_archive set archived_at=now(),archived_by=auth.uid(),reason=trim(p_reason),receipt=r where singleton=true and archived_at is null and snapshot_sha256=p_digest and backup_sha256=p_digest;
 get diagnostics n=row_count;if n<>1 then raise exception 'catalog_archive_refused: batch completion changed';end if;$new$,$old$update ops.prelaunch_listing_archive set archived_at=now(),archived_by=auth.uid(),reason=trim(p_reason),receipt=r;$old$);
end $rollback$;
commit;
