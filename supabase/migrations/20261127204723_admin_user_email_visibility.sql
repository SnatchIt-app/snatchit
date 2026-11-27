--218: owner-requested full-email read for platform admins only; other readers stay masked.
begin;
create function ops.admin_user_emails(p_user_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path=''
as $contact$
begin
 perform ops.assert_role(array['platform_admin']);
 if cardinality(p_user_ids)>200 then raise exception 'invalid_input: at most 200 user ids';end if;
 if exists(select from unnest(p_user_ids) x where x is null) then raise exception 'invalid_input: null user id';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'email',u.email) order by u.id)
 from auth.users u join public.profiles p on p.id=u.id where u.id=any(p_user_ids)),'[]'::jsonb);
end $contact$;
revoke all on function ops.admin_user_emails(uuid[]) from public,anon,authenticated,service_role;
grant execute on function ops.admin_user_emails(uuid[]) to authenticated;
comment on function ops.admin_user_emails(uuid[]) is 'Platform admin plus aal2 only. Bounded page-ID lookup of email, never phone/auth secrets. Existing masked APIs unchanged.';
commit;
