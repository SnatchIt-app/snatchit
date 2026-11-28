--220: bounded admin/MFA diagnostic; successful inner execution is ALWAYS rolled back.
begin;
create function ops.prelaunch_listing_diagnose() returns jsonb
language plpgsql security definer set search_path='' as $diagnose$
declare d text;v_before jsonb;v_after jsonb;v_receipt jsonb;v_result jsonb;v_code text;v_message text;v_context text;
begin
 perform ops.assert_role(array['platform_admin']);
 perform pg_catalog.pg_advisory_xact_lock(21920261127);
 select snapshot_sha256 into d from ops.prelaunch_listing_archive where archived_at is null and backup_sha256=snapshot_sha256;
 if d is null then raise exception 'catalog_diagnostic_refused: verified unexecuted batch required';end if;
 v_before:=ops.prelaunch_listing_collect();
 begin
  v_receipt:=ops.prelaunch_listing_execute(d,'Rollback-only request safety check; never commit cleanup','ARCHIVE 113 OLD LISTINGS');
  if v_receipt->>'status' is distinct from 'archived' then raise exception 'catalog_diagnostic_refused: unexpected inner receipt';end if;
  raise exception using errcode='PZ220',message='ROLLBACK_CATALOG_DIAGNOSTIC';
 exception when sqlstate 'PZ220' then
  v_result:=jsonb_build_object('status','checked_no_changes');
 when others then
  get stacked diagnostics v_code=RETURNED_SQLSTATE,v_message=MESSAGE_TEXT,v_context=PG_EXCEPTION_CONTEXT;
  v_result:=jsonb_build_object('status','refused_no_changes','code',v_code,'message',v_message,'context',v_context);
 end;
 v_after:=ops.prelaunch_listing_collect();
 if v_before is distinct from v_after or exists(select from ops.prelaunch_listing_archive where archived_at is not null) then raise exception 'catalog_diagnostic_refused: rollback verification failed';end if;
 return v_result;
end $diagnose$;
revoke all on function ops.prelaunch_listing_diagnose() from public,anon,authenticated,service_role;
grant execute on function ops.prelaunch_listing_diagnose() to authenticated;
commit;
