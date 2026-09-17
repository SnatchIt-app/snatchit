-- ============================================================================
-- 136_public_security_notices_read.sql — the mobile client's owner-scoped read
-- and acknowledgement of MANDATORY SECURITY NOTICES, reachable through `public`.
--
-- WHY. 135 enqueues `security_device_rebound` for the PREVIOUS owner of a device
-- token as an in_app-only notification (allowed_channels '{}' — N1: no email;
-- owner ruling 2026-09-16/17: in-app only, no new outbound channel). The Expo app
-- has no notification centre and `notify` is not PostgREST-exposed (sandbox and
-- production: `public, graphql_public, kernel`), so the previous owner was told
-- on no channel they could see on the phone: b2 stopped the silent redirect but
-- did not yet tell the victim. Notification batch 1, item 2 (owner-approved
-- 2026-09-17). The 129 pattern: `public` SECURITY DEFINER wrappers over notify's
-- own reads — no new channel, no new producer, no schema exposure.
--
-- WHAT.
--   public.get_my_security_notices()
--     Pages notify.get_inbox — the single renderer (templates, locale, params) —
--     for auth.uid() and returns only the mandatory security types, newest
--     first: {id, type_key, title, body, created_at, read_at}. Scans at most
--     200 inbox rows (4 pages of 50). The copy is the server template
--     (135: notify.template en-US in_app v1 for security_device_rebound), so the
--     mobile notice and the web notification centre say the same thing.
--   public.mark_security_notices_read(uuid[]) → integer
--     Acknowledges the CALLER's OWN security notices only, via notify.mark_read
--     (the single writer of read_at); ids of other users or other types are
--     ignored (0). Never raises for an unknown id.
--   notify.template v2 for security_device_rebound (en-US, in_app) — the copy the
--     owner corrected and D verified against 135 §5 (2026-09-17): the recipient is
--     the PREVIOUS owner (v_prev_owner read before the update), so the event means
--     "a device that was receiving THIS account's notifications now belongs to
--     ANOTHER account". v1's body told the victim to "sign in on that phone to
--     take it back, then change your password": unsafe advice when someone else
--     holds the phone, and the product has no in-app password change (the reset is
--     an emailed link). v1 also rendered {{device_name}}, which on the register
--     path is text the CLAIMING party supplies (up to 120 chars inside the
--     victim's security alert). v2 drops both and names the one action that
--     works and is non-collateral: sign out of all devices (K-2). Additive: the
--     PK is (template_key, locale, channel, version) and get_inbox reads
--     `order by version desc limit 1`; v1 stays in place; no UPDATE of 135's row.
--     Dedupe is one notice per token per UTC day, so the copy uses the present
--     tense and never "just". The client keys its two actions on type_key.
--   EXECUTE: authenticated only (anon, service_role, PUBLIC refused).
--   Census: +2 functions in public (production-gate stack 105 → 107); +1 template row.
--   Manifest: +2 authenticated-execute rows. pgTAP 203. Applied nowhere by this file.
-- ============================================================================
begin;

create or replace function public.get_my_security_notices()
returns table (id uuid, type_key text, title text, body text, created_at timestamptz, read_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_cursor  timestamptz := null;
  v_page    constant integer := 50;
  v_scanned integer := 0;
  v_rows    integer;
  v_min     timestamptz;
  r         record;
begin
  if v_uid is null then return; end if;
  loop
    v_rows := 0; v_min := null;
    for r in select * from notify.get_inbox(v_cursor, v_page) loop
      v_rows := v_rows + 1;
      v_min := least(coalesce(v_min, r.created_at), r.created_at);
      if r.type_key in ('security_device_rebound', 'security_password_changed') then
        id := r.notification_id; type_key := r.type_key; title := r.rendered_title; body := r.rendered_body;
        created_at := r.created_at; read_at := r.read_at;
        return next;
      end if;
    end loop;
    v_scanned := v_scanned + v_rows;
    exit when v_rows < v_page or v_scanned >= 200 or v_min is null;
    v_cursor := v_min;
  end loop;
  return;
end $$;

comment on function public.get_my_security_notices() is
  '136: PostgREST-reachable, owner-scoped read of the mandatory security notices (security_device_rebound, security_password_changed) for auth.uid(), rendered by notify.get_inbox (server templates); newest first; at most 200 inbox rows scanned. No new channel. authenticated only.';

create or replace function public.mark_security_notices_read(p_ids uuid[])
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_ids uuid[];
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select coalesce(array_agg(n.notification_id), '{}'::uuid[]) into v_ids
    from notify.notification n
   where n.recipient_id = v_uid
     and n.type_key in ('security_device_rebound', 'security_password_changed')
     and n.notification_id = any (coalesce(p_ids, '{}'::uuid[]));
  if coalesce(array_length(v_ids, 1), 0) = 0 then return 0; end if;
  return coalesce((notify.mark_read(v_ids) ->> 'updated')::integer, 0);
end $$;

comment on function public.mark_security_notices_read(uuid[]) is
  '136: acknowledges the caller''s OWN security notices only (ids of other users or other types are ignored → 0), via notify.mark_read, the single writer of read_at. authenticated only.';

revoke execute on function public.get_my_security_notices()            from public, anon, service_role;
grant  execute on function public.get_my_security_notices()            to authenticated;
revoke execute on function public.mark_security_notices_read(uuid[])   from public, anon, service_role;
grant  execute on function public.mark_security_notices_read(uuid[])   to authenticated;

-- the corrected, D-verified copy as a new template version (additive; v1 untouched)
insert into notify.template (template_key, locale, channel, version, subject, body) values
  ('security_device_rebound', 'en-US', 'in_app', 2,
   'A device stopped receiving your notifications',
   'A device that was getting notifications for this account is now registered to a different account. If that was you signing in to another account, there''s nothing to do. If not, sign out of all devices.')
on conflict (template_key, locale, channel, version) do nothing;

-- sanity inside the migration: both wrappers exist, are definer, pinned to an empty search_path, authenticated-only; template v2 present
do $chk$
declare v_bad text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v_bad
    from pg_proc p
   where p.oid in ('public.get_my_security_notices()'::regprocedure, 'public.mark_security_notices_read(uuid[])'::regprocedure)
     and not (p.prosecdef and coalesce(p.proconfig @> array['search_path=""'], false)
              and has_function_privilege('authenticated', p.oid, 'EXECUTE')
              and not has_function_privilege('anon', p.oid, 'EXECUTE')
              and not has_function_privilege('service_role', p.oid, 'EXECUTE'));
  if v_bad is not null then
    raise exception '136 sanity failed: %', v_bad;
  end if;
  if not exists (select 1 from notify.template where template_key = 'security_device_rebound' and locale = 'en-US' and channel = 'in_app' and version = 2) then
    raise exception '136 sanity failed: template v2 missing';
  end if;
end $chk$;

commit;
