-- Schema-only rollback. Never discard a prepared or completed archive or auto-replay money rows.
begin;
DO $guard$ begin
 if exists(select 1 from ops.prelaunch_archive_batch) then
  raise exception 'rollback_refused: retain the archive; reviewed row restoration is a separate operation';
 end if;
end $guard$;
drop function ops.prelaunch_archive_execute(uuid,text,text,text);
drop function ops.prelaunch_archive_read();
drop function ops.prelaunch_archive_prepare(uuid[]);
drop function ops.prelaunch_archive_assert_manifest(uuid[]);
drop function ops.prelaunch_archive_collect(uuid[]);
drop table ops.prelaunch_archive_batch;
commit;
