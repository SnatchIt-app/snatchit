-- ============================================================================
-- 136_public_security_notices_read.sql — the mobile client's owner-scoped read
-- and acknowledgement of MANDATORY SECURITY NOTICES, reachable through `public`.
--
-- WHY. 135 enqueues `security_device_rebound` for the PREVIOUS owner of a device
-- token as an in_app-only notification (allowed_channels '{}' — N1: no email;
-- owner ruling 2026-09-16/17: in-app only, no new outbound channel). The Expo app
-- has no notification centre and `notify` is not PostgREST-exposed (sandbox reads
-- 2026-09-16: `public, graphql_public, kernel`; production additionally exposes
-- `ops` for the console per its record — `notify` is in neither), so the previous owner was told
-- on no channel they could see on the phone: b2 stopped the silent redirect but
-- did not yet tell the victim. Notification batch 1, item 2 (owner-approved
-- 2026-09-17). The 129 pattern: `public` SECURITY DEFINER wrappers over notify's
-- own reads — no new channel, no new producer, no schema exposure.
--
-- WHAT.
--   public.get_my_security_notices()
--     The SECURITY TYPE SET is derived from the registry, never hard-coded
--     (D, Q2): notify.notification_type rows with target_kind = 'account_security'
--     and delivery_class = 'mandatory' (135's security_device_rebound today; a
--     later type joins this surface only by being classified so). The surface
--     is the ACTIONABLE one: it returns UNREAD, undismissed notices only (D's
--     lifecycle finding: nothing ever sets dismissed_at on a security notice, so a
--     count of undismissed rows would only ever grow and the read would page
--     back to the oldest notice on every foreground for the life of the
--     account; acknowledging must make the cost fall to zero). The read first
--     COUNTS the caller's unread rows of those types straight from
--     notify.notification — the partial index notification_recipient_unread_idx
--     (recipient_id, created_at desc) where read_at is null and dismissed_at is
--     null was built for exactly this predicate; usually 0 → return empty, no
--     rendering at all — then pages notify.get_inbox — the single renderer
--     (templates, locale, params) — until every counted row has been returned or
--     the inbox is exhausted. NO CAP: truncation is impossible by construction
--     (D, Q1: a mandatory notice must never be silently absent). A history of
--     read notices is not this surface (a mobile notification centre is a
--     separate backlog item).
--     Newest first: {id, type_key, title, body, created_at, read_at}. The copy is
--     the server template (highest version), so the mobile notice and the web
--     centre say the same thing.
--     Pagination dependency (E-160, 092): the cursor is get_inbox's single
--     created_at keyset; notify.notification.created_at defaults to
--     clock_timestamp(), not now(), so rows written in one transaction never tie
--     and a page boundary never skips a row. 203 G1 exercises a second page.
--     Dismissed semantics, deliberate: rows with dismissed_at set are excluded,
--     as get_inbox does; no dismiss wrapper exists for mobile and none may be
--     added for security types without review (D, F1) — the client's "Dismiss"
--     calls mark_security_notices_read, never notify.dismiss.
--   public.mark_security_notices_read(uuid[]) → integer
--     Acknowledges the CALLER's OWN security-type notices only (the same derived
--     set), via notify.mark_read (the single writer of read_at), which is itself
--     recipient-scoped: two independent scopes. Returns the count NEWLY marked:
--     already-read, foreign, non-security or unknown ids contribute 0 (D, Q3a) —
--     0 is not an error. p_ids is bounded to its first 100 elements (D, Q3b).
--     Never raises for an unknown id.
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
  v_uid      uuid := auth.uid();
  v_types    text[];
  v_expected integer;
  v_found    integer := 0;
  v_cursor   timestamptz := null;
  v_page     constant integer := 50;
  v_rows     integer;
  v_min      timestamptz;
  r          record;
begin
  if v_uid is null then return; end if;
  -- the security type set, from the registry (never a literal list)
  select coalesce(array_agg(t.type_key), '{}'::text[]) into v_types
    from notify.notification_type t
   where t.target_kind = 'account_security' and t.delivery_class = 'mandatory';
  if coalesce(array_length(v_types, 1), 0) = 0 then return; end if;
  -- how many UNREAD, undismissed security rows the caller has (partial index; usually 0)
  select count(*) into v_expected
    from notify.notification n
   where n.recipient_id = v_uid and n.type_key = any (v_types)
     and n.read_at is null and n.dismissed_at is null;
  if v_expected = 0 then return; end if;
  -- page the single renderer until every counted row has been returned (no cap)
  loop
    v_rows := 0; v_min := null;
    for r in select * from notify.get_inbox(v_cursor, v_page) loop
      v_rows := v_rows + 1;
      v_min := least(coalesce(v_min, r.created_at), r.created_at);
      if r.type_key = any (v_types) and r.read_at is null then
        id := r.notification_id; type_key := r.type_key; title := r.rendered_title; body := r.rendered_body;
        created_at := r.created_at; read_at := r.read_at;
        return next;
        v_found := v_found + 1;
      end if;
    end loop;
    exit when v_found >= v_expected or v_rows < v_page or v_min is null;
    v_cursor := v_min;
  end loop;
  return;
end $$;

comment on function public.get_my_security_notices() is
  '136: PostgREST-reachable, owner-scoped read of the caller''s mandatory account_security notices (type set derived from notify.notification_type: target_kind=account_security AND delivery_class=mandatory), UNREAD and undismissed only (acknowledged notices leave the surface and its cost), rendered by notify.get_inbox (server templates, highest version); newest first; pages until every counted unread row is returned — no cap, no silent truncation. No new channel. authenticated only.';

create or replace function public.mark_security_notices_read(p_ids uuid[])
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_types text[];
  v_in    uuid[] := coalesce(p_ids, '{}'::uuid[]);
  v_ids   uuid[];
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if coalesce(array_length(v_in, 1), 0) > 100 then v_in := v_in[1:100]; end if;   -- bounded input (D, Q3b)
  select coalesce(array_agg(t.type_key), '{}'::text[]) into v_types
    from notify.notification_type t
   where t.target_kind = 'account_security' and t.delivery_class = 'mandatory';
  select coalesce(array_agg(n.notification_id), '{}'::uuid[]) into v_ids
    from notify.notification n
   where n.recipient_id = v_uid
     and n.type_key = any (v_types)
     and n.notification_id = any (v_in);
  if coalesce(array_length(v_ids, 1), 0) = 0 then return 0; end if;
  return coalesce((notify.mark_read(v_ids) ->> 'updated')::integer, 0);   -- newly marked only (read_at was null)
end $$;

comment on function public.mark_security_notices_read(uuid[]) is
  '136: acknowledges the caller''s OWN mandatory account_security notices only, via notify.mark_read (recipient-scoped itself: two independent scopes); returns the count NEWLY marked — already-read, foreign, non-security or unknown ids contribute 0, which is not an error; p_ids bounded to its first 100 elements. authenticated only.';

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
