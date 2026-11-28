--221: retain API safeupdate protection; completion targets only the verified singleton.
begin;
DO $patch$
declare d text;
begin
 if (select md5(prosrc)from pg_proc where oid='ops.prelaunch_listing_execute(text,text,text)'::regprocedure) is distinct from '9db951fbe99d54905787349aac6dbce9' then raise exception 'precondition_failed: archive executor predecessor drift';end if;
 select pg_get_functiondef('ops.prelaunch_listing_execute(text,text,text)'::regprocedure)into d;
 d:=replace(d,$old$update ops.prelaunch_listing_archive set archived_at=now(),archived_by=auth.uid(),reason=trim(p_reason),receipt=r;$old$,$new$update ops.prelaunch_listing_archive set archived_at=now(),archived_by=auth.uid(),reason=trim(p_reason),receipt=r where singleton=true and archived_at is null and snapshot_sha256=p_digest and backup_sha256=p_digest;
 get diagnostics n=row_count;if n<>1 then raise exception 'catalog_archive_refused: batch completion changed';end if;$new$);
 execute d;
end $patch$;
commit;
