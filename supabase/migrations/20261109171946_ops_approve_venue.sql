-- Registry 207: expose only the audited venue approval operation through ops.
-- This does not expose catalog, approve a venue, or change ticket issuance.
do $preflight$
begin
  if not has_schema_privilege('authenticated', 'catalog', 'USAGE')
     or not has_function_privilege('authenticated', 'catalog.approve_venue(uuid,text,text,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'ops.actor_role()', 'EXECUTE') then
    raise exception 'venue approval requires the existing authenticated grants';
  end if;
end $preflight$;

create function ops.approve_venue(p_venue_id uuid, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $approval$
begin
  if auth.uid() is null or ops.actor_role() is distinct from 'platform_admin' then
    raise exception 'insufficient_privilege: platform_admin required' using errcode = '42501';
  end if;
  if (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb ->> 'aal') is distinct from 'aal2' then
    raise exception 'step_up_required: confirm with your authenticator' using errcode = '42501';
  end if;
  return catalog.approve_venue(p_venue_id, 'approved', p_reason_code, p_command_key);
end;
$approval$;

revoke all on function ops.approve_venue(uuid,text,text) from public, anon, authenticated, service_role;
grant execute on function ops.approve_venue(uuid,text,text) to authenticated;
