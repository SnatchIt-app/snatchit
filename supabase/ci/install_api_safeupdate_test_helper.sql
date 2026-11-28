-- CI disposable stack only; run as its existing supabase_admin before pgTAP.
create schema if not exists ci_test_private;
revoke all on schema ci_test_private from public,anon,authenticated,service_role;
grant usage on schema ci_test_private to postgres;
create function ci_test_private.enable_api_safeupdate() returns void
language plpgsql security definer set search_path='' as $loader$
begin
 execute 'LOAD ''safeupdate''';
 perform set_config('safeupdate.enabled','1',true);
end $loader$;
revoke all on function ci_test_private.enable_api_safeupdate() from public,anon,authenticated,service_role;
grant execute on function ci_test_private.enable_api_safeupdate() to postgres;
