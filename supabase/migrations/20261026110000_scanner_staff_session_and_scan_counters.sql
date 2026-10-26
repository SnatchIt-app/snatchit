-- ============================================================================
-- 20261026110000_scanner_staff_session_and_scan_counters.sql — the pop-up
-- scanner's identity-free SESSION SCAN COUNTERS (C9) and its STAFF-SESSION
-- admission path (C7 amendment 2026-10-26).
--
-- Registry 163 / pgTAP 230 — assigned by Claude A 2026-10-26 (CONTRACTS.md §4;
-- C7 amendment 2026-10-26). A reviews before this leaves draft. DARK: applied
-- nowhere (local rehearsal clones only); exposes no schema, flips no flag, seeds
-- no config key. venue_api / venue_cmd stay unexposed (owner setting); `venue`
-- is never exposed to a client (D's 10-22 ruling; A §1 keeps it for the edges).
-- ORDER: applies only AFTER 159 (20261021120000, venue_api), 160 (20261022100000)
-- and 161 (20261022110000, venue_cmd) — the guard below fails fast otherwise.
-- Roll back 163 BEFORE 161/160/159: 161's rollback refuses while venue_cmd holds
-- a function it did not create, 159's while venue_api holds a ninth view.
--
-- TWO PARTS, TWO COMMITS (A's instruction: strictly separate):
--   PART A (always ships) — the counters.
--     venue.get_session_scan_counters(p_session_id uuid)
--       returns table(session_id uuid, admitted integer, duplicate integer,
--                     invalid integer, last_admitted_at timestamptz)
--       STABLE SECURITY DEFINER search_path=''. Exactly one row for an authorized
--       caller (zeros + NULL when the session has no scan; last_admitted_at is
--       the server receipt time of the latest admitted+in row); unknown session and
--       unauthorized caller raise the SAME 'not_found: session <id>' (P0002) —
--       no existence oracle, never zeros for a stranger. No name, no
--       customer_ref, no per-atom row, no actor, no device: four counters and
--       one timestamp. The dashboard renders "Couldn't load" on P0002.
--     venue.list_session_scan_counters()
--       returns table(same five columns) STABLE SECURITY DEFINER search_path=''.
--       One row per catalog.event_session the CALLER may read under the same
--       authority rule, evaluated per session; sessions the caller may not read
--       are OMITTED — it never raises for an unauthorized session, and an
--       unauthenticated caller (auth.uid() NULL) gets zero rows. Ordered by
--       starts_at, session_id.
--     venue_api.session_admissions — the name A's CONTRACTS.md §4 / C9 uses —
--       a security_invoker + security_barrier VIEW over
--       venue.list_session_scan_counters(), explicit column list, SELECT to
--       authenticated only, owner = the migration runner (postgres) like 159's
--       eight. venue_api stays views-only (226 A3: no function there).
--     venue_cmd.get_session_scan_counters(p_session_id uuid) — the 161-form
--       LANGUAGE sql SECURITY INVOKER wrapper, identical result type, so the
--       dashboard reaches the single-session read through its command transport.
--   PART B (DROPPABLE — B accepted the staff-session path 2026-10-26 with the
--   conditions below; A may still drop this part within the sprint; nothing in
--   PART A depends on it; its rollback lines are IF EXISTS).
--     venue.record_scan_staff(p_atom_id uuid, p_session_id uuid,
--                             p_scan_meta jsonb, p_command_key text) returns jsonb
--       SECURITY DEFINER plpgsql search_path=''. Validates the input and calls
--       venue.record_scan(p_atom_id, p_session_id, NULL::uuid, <filtered meta>,
--       p_command_key) — the device is NEVER settable from this path; the actor
--       is auth.uid() (set inside venue.record_scan); the role gate
--       (venue_scanner/venue_manager, 086/108) and the feature.native_scanning_enabled
--       gate stay INSIDE venue.record_scan / venue._record_scan_core (ONE
--       authority, C7). NO exception handler: 'precondition_failed:
--       feature_disabled — native scanning is dark' (P0001) and
--       insufficient_privilege (42501) pass through unchanged.
--       scan_meta ALLOW-LIST — venue.filter_staff_scan_meta(p_scan_meta jsonb)
--       returns jsonb, IMMUTABLE, ZERO grants (reachable only through the definer
--       record_scan_staff; 230 Section H tests it directly as the owner, without
--       the flag). B's condition 2 as ruled by A+E 2026-10-26: NULL or '{}' -> '{}';
--         device_label        text, 1..64 chars, else
--                             'invalid_input: scan_meta.device_label must be 1-64 chars'
--         credential_version  passed through as given
--         key_id              passed through as given (B's 183 classifies malformed claims)
--         device_id           REFUSED 'invalid_input: scan_meta.device_id is not accepted'
--                             (B's X-5 parity with record_scan_door, 108:214)
--         occurred_at         STRIPPED silently (A+E ruling, supersedes the earlier
--                             "refuse"): the ledger gets the server's now();
--                             scan_meta.occurred_at stays reserved for offline
--                             reconcile batches (086/108 _reconcile_core). A client
--                             clock can never reach venue.scan.occurred_at on this
--                             path — 230 F19/F20 (flag ON), H7/H8 and G5 pin it.
--         anything else       REFUSED 'invalid_input: scan_meta key not accepted: <key>'
--         a non-object meta   REFUSED 'invalid_input: scan_meta must be a JSON object'
--                             (jsonb_object_keys would otherwise raise its own text)
--       p_command_key required non-empty ('precondition_failed: command key
--       required'), forwarded verbatim. NOTE: device_label is validated and
--       forwarded but venue.scan has no column for it on this chain; B's 183 adds
--       the nullable venue.scan.device_label and stores it from scan_meta. Until
--       then the scan row is actor-attributed only (actor_identity_id = caller,
--       device_id NULL — scan_attribution_ck holds).
--     venue_cmd.record_scan(p_atom_id uuid, p_session_id uuid, p_scan_meta jsonb,
--                           p_command_key text) returns jsonb
--       ONE-LINE LANGUAGE sql SECURITY INVOKER wrapper over venue.record_scan_staff
--       (so 228's "every venue_cmd function is LANGUAGE sql, prosecdef=false"
--       invariant survives — the logic lives in the definer above). No
--       p_actor_device_id parameter exists on this surface.
--     venue_cmd.validate_ticket_online(p_atom_id uuid, p_session_id uuid) returns jsonb
--       LANGUAGE sql STABLE SECURITY INVOKER over venue.validate_ticket_online
--       (086:1111; a READ, F renders scan results only). Same grants.
--   The door-session edge path (venue.record_scan_door, venue.mint_door_session,
--   kernel.assert_door_session, 108) is NOT touched: it stays the device-bound
--   authority for later doors. PFA-26 (107, bcrypt door PIN) is IN production.
--   Limits B recorded for the staff path: a venue-level role (any venue_scanner
--   of the venue may scan any session of that venue), no rate limiter on the RPC
--   path, client-side token verification under an honest-staff model (where
--   token->atom verification runs on the staff path is B's open item, P3/P8).
--
-- COUNTING RULE (E + A, 2026-10-26, so the dashboard count equals the ground truth):
--   admitted         = count of venue.scan rows with result='admitted' AND
--                      direction='in' — the SAME predicate as the race index
--                      scan_admitted_in_uq (086:146-148), so the number shown is
--                      the number the first-in-wins rule bounds; an 'out'
--                      admitted row never counts.
--   duplicate        = count of rows with result='duplicate' (any direction).
--   invalid          = count of rows with result IN ('invalid','frozen','fraud_review').
--                      FOLDED on purpose: the scanner renders one "not admitted"
--                      outcome (P8: admitted / duplicate+prior / invalid / cannot
--                      verify) and the three results share it; frozen and
--                      fraud_review are allowed by scan_result_check (086:131)
--                      but are not produced by venue._record_scan_core today (183
--                      keeps the result set unchanged). Whoever reads 'invalid'
--                      reads the fold; the per-result split is a later read.
--   last_admitted_at = max(SERVER_RECEIPT_AT) over the admitted+in rows (NULL when
--                      none) — NOT occurred_at (E, 2026-10-26): venue._record_scan_core
--                      coalesces a client-supplied scan_meta.occurred_at into
--                      venue.scan.occurred_at on the other paths (108:76), so a
--                      phone clock set to 2031 would otherwise become the
--                      dashboard's "last admitted" time; server_receipt_at is
--                      stamped by the database (086:137 default now()) and
--                      nothing a client sends can move it. (The staff path also
--                      refuses scan_meta.occurred_at outright — PART B.)
--   Every read names its venue.scan columns explicitly (B's condition: no
--   `select *`, no `scan.*`; 183 adds a column) — 230 pins the absence of '*'.
--
-- AUTHORITY (one expression, both counters functions; per session in the list):
--   kernel.has_org_role(event.org_id, ['org_owner','org_admin'])          -- the EVENT's org,
--                                                                        -- the helper cancel_event 088:1627 uses
--   OR (kernel.has_venue_role(event.venue_id, ['venue_scanner','venue_manager'])
--       AND venue.org_id = event.org_id)                                   -- E-76: the venue arm needs
--                                                                        -- the room's CURRENT operator to be the event's org
--   venue_finance / venue_box_office / venue_marketing / venue_promoter_manager,
--   org_finance / org_marketing, a cross-venue scanner, the former-operator
--   manager of a re-operated room, the new operator's org_owner on the former
--   operator's event, a fan: all refused as not_found. Unauthenticated: 42501
--   'authentication required' on the single-session read (160's form), zero
--   rows on the list (set-returning: it omits).
--
-- WHY A SECURITY DEFINER FUNCTION AND NOT A security_invoker VIEW OVER venue.scan
-- (F asked for a view; F accepted the function form; the view in venue_api is
-- the function's projection). venue.scan (086 PART 4) DOES grant SELECT to
-- authenticated under RLS policy venue_scan_sel_venue — venue_scanner /
-- venue_manager of the event's venue only — the brief's "zero table grants" is
-- not what the catalog holds (the a154c_green/production-template relacl is
-- {postgres=arwdDxtm/postgres,authenticated=r/postgres}, relrowsecurity=t).
-- A security_invoker view over it still cannot deliver the contract:
--   (a) the policy has no org arm (org_owner/org_admin would read NOTHING) and
--       no E-76 conjunct (the former-operator manager would read rows);
--   (b) a view returns NO row for a session with zero scans and NO row for an
--       unauthorized caller — the contract wants one row of zeros for the first
--       and a refusal for the second, which a view cannot raise;
--   (c) widening the 086 policy to add the org arm would hand org roles the raw
--       per-atom, per-actor venue.scan rows — the opposite of identity-free.
-- So the authority lives in the definer bodies, the rows never leave them, and
-- venue_api.session_admissions is security_invoker over the SET-RETURNING
-- function (the caller must hold EXECUTE on it and USAGE on venue, both true for
-- authenticated: 076:78, PART A grants).
--
-- GRANT DECISIONS (every one, because the CI grant gates read `public` only;
-- pgTAP 230 is the gate for these objects, 228 for the venue_cmd schema sweep,
-- 226 (+ the 163 hunk) for venue_api):
--   venue.filter_staff_scan_meta(jsonb)      EXECUTE : NOBODY (REVOKE ALL FROM PUBLIC, anon,
--                                                      authenticated, service_role — the
--                                                      _record_scan_core pattern, 108:84): a
--                                                      pure IMMUTABLE helper the definer
--                                                      record_scan_staff calls as its owner;
--                                                      no client needs it, so no client gets
--                                                      it (and 140 #27's sweep stays untouched).
--   venue.get_session_scan_counters(uuid)   EXECUTE : authenticated ONLY. REVOKE ALL
--   venue.list_session_scan_counters()                 FROM PUBLIC, anon, authenticated
--   venue.record_scan_staff(uuid,uuid,jsonb,text)      first (067: a bare REVOKE FROM
--                                                      PUBLIC is not enough once role
--                                                      grants exist), then GRANT EXECUTE
--                                                      TO authenticated. anon: NONE (076/
--                                                      E-30 walls anon from venue anyway).
--                                                      service_role: NONE — no server-side
--                                                      caller; the edges never read counters,
--                                                      and the machine scan path is
--                                                      record_scan_door (108), untouched.
--                                                      PUBLIC: NONE. No proacl DEFAULTED.
--   venue_cmd.get_session_scan_counters(uuid) EXECUTE : authenticated ONLY (161 PART 7
--   venue_cmd.record_scan(uuid,uuid,jsonb,text)         pattern). anon/PUBLIC/service_role:
--   venue_cmd.validate_ticket_online(uuid,uuid)         NONE. Schema USAGE unchanged (161).
--   venue_api.session_admissions              SELECT  : authenticated ONLY (159 pattern:
--                                                      REVOKE ALL FROM PUBLIC, anon,
--                                                      authenticated, then GRANT SELECT TO
--                                                      authenticated). No INSERT/UPDATE/
--                                                      DELETE, no column grant, anon NONE,
--                                                      service_role NONE. Owner = the
--                                                      migration runner (postgres), as 159.
--   default privileges                               : none stored (161's reasoning).
--   venue.record_scan / record_scan_door / _record_scan_core / validate_ticket_online
--                                                    : grants UNCHANGED (086/108) — 230 D12 pins.
--
-- FOUR-FILE RULE (CLAUDE.md): the grant-decision manifest and expected_grants.txt
-- read `public` only (the manifest's B2 fails closed on a row for a function
-- outside public), so no row is added; a dated scope note names every object
-- here with its posture and the pgTAP that asserts it. Gate-2 census (ci.yml)
-- reads `public` only: unchanged 35|126|37|49 (dated comment line). Rollback:
-- supabase/rollbacks/20261026110000_scanner_staff_session_and_scan_counters_rollback.sql
-- — drops the view, the three venue_cmd wrappers and the four venue functions
-- (nothing else), IF EXISTS, idempotent, rc 0.
-- PINS THIS MIGRATION MOVES: venue function count 90 -> 94 (144 A15, 145 A4,
-- 148 B5, 180 A5 — A/B patches in D's evidence dir; 227 A12 and 230 A19 — D's,
-- edited here); five-schema routine census 308 -> 312 (148 B2, 157 A46, 180 A6 —
-- patches); venue_api views 8 -> 9 and the F1/F5/F6 matrices (226 — F's, one
-- hunk delivered as a patch); venue_cmd functions 6 -> 9 (228 A2/A3/A5-A7/
-- A14-A20/A23 — D's, edited here; 7 if PART B is dropped); 140 #27's named
-- caller-authorized venue list + the three authenticated-execute venue names
-- (patch; the zero-grant filter is outside that sweep). If PART B is dropped the
-- venue count is 92 and the routine census 310.
--
-- VERIFICATION (after apply):
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='venue';      -- 94 (was 90)
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='venue_cmd';  -- 9 (was 6)
--   select count(*) from pg_views where schemaname='venue_api';                                               -- 9 (was 8)
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname in ('venue','venue_cmd') and p.proname in ('get_session_scan_counters','list_session_scan_counters','record_scan_staff','filter_staff_scan_meta','record_scan','validate_ticket_online')
--      and position('*' in p.prosrc) > 0;                                                                     -- 0
-- LOCKS / RUNTIME: CREATE FUNCTION / CREATE VIEW / GRANT only; no table is
-- touched, no row is read or written.
-- ============================================================================
BEGIN;

-- order guard: 159 (venue_api) and 161 (venue_cmd) must already be applied.
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'venue_api') then
    raise exception 'ORDER_163_REFUSED: schema venue_api (159, 20261021120000) is absent; apply 159 first';
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'venue_cmd') then
    raise exception 'ORDER_163_REFUSED: schema venue_cmd (161, 20261022110000) is absent; apply 160 then 161 first';
  end if;
end $$;

-- ============================================================================
-- PART A — the counters (always ships)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- A.1 venue.get_session_scan_counters — one session, one row, or P0002
-- ---------------------------------------------------------------------------
create or replace function venue.get_session_scan_counters(p_session_id uuid)
returns table (
  session_id       uuid,
  admitted         integer,
  duplicate        integer,
  invalid          integer,
  last_admitted_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_org_id uuid;
  v_venue  uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;

  select e.org_id, e.venue_id into v_org_id, v_venue
    from catalog.event_session es
    join catalog.event e on e.event_id = es.event_id
   where es.session_id = p_session_id;

  -- unknown and unauthorized raise the SAME error: no existence oracle, never zeros for a stranger.
  if v_org_id is null
     or not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
             or (kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager'])
                 and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;

  -- an aggregate without GROUP BY: exactly one row, zeros and NULL when there is no scan.
  return query
    select p_session_id,
           (count(s.scan_id) filter (where s.result = 'admitted' and s.direction = 'in'))::integer,
           (count(s.scan_id) filter (where s.result = 'duplicate'))::integer,
           (count(s.scan_id) filter (where s.result in ('invalid','frozen','fraud_review')))::integer,
           max(s.server_receipt_at) filter (where s.result = 'admitted' and s.direction = 'in')
      from venue.scan s
     where s.event_session_id = p_session_id;
end;
$$;
comment on function venue.get_session_scan_counters(uuid) is
  '163: identity-free scan counters of one session (admitted = result admitted AND direction in; duplicate; invalid folds invalid/frozen/fraud_review; last_admitted_at = max server_receipt_at of the admitted+in rows, never the client-supplied occurred_at). org_owner/org_admin of the EVENT''s org, or venue_scanner/venue_manager of the venue while it operates the event''s org (E-76). Unknown and unauthorized sessions raise the same P0002.';

-- ---------------------------------------------------------------------------
-- A.2 venue.list_session_scan_counters — every session the caller may read
-- ---------------------------------------------------------------------------
create or replace function venue.list_session_scan_counters()
returns table (
  session_id       uuid,
  admitted         integer,
  duplicate        integer,
  invalid          integer,
  last_admitted_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select es.session_id,
         coalesce(sc.admitted, 0)::integer,
         coalesce(sc.duplicate, 0)::integer,
         coalesce(sc.invalid, 0)::integer,
         sc.last_admitted_at
    from catalog.event_session es
    join catalog.event e on e.event_id = es.event_id
    left join lateral (
      select count(s.scan_id) filter (where s.result = 'admitted' and s.direction = 'in') as admitted,
             count(s.scan_id) filter (where s.result = 'duplicate')                          as duplicate,
             count(s.scan_id) filter (where s.result in ('invalid','frozen','fraud_review')) as invalid,
             max(s.server_receipt_at) filter (where s.result = 'admitted' and s.direction = 'in')  as last_admitted_at
        from venue.scan s
       where s.event_session_id = es.session_id) sc on true
   where auth.uid() is not null
     and (kernel.has_org_role(e.org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(e.venue_id, array['venue_scanner','venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = e.venue_id and v.org_id = e.org_id)))
   order by es.starts_at, es.session_id
$$;
comment on function venue.list_session_scan_counters() is
  '163: the same counters for every event_session the caller may read (same authority as get_session_scan_counters, evaluated per session; unauthorized sessions are omitted, never raised; unauthenticated = zero rows). The base of venue_api.session_admissions.';

-- ---------------------------------------------------------------------------
-- A.3 venue_api.session_admissions — F's read surface (C9 name), views-only schema
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW venue_api.session_admissions
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at
    FROM venue.list_session_scan_counters() c;
COMMENT ON VIEW venue_api.session_admissions IS
  '163: identity-free scan counters per session the caller may read (venue.list_session_scan_counters). admitted = result admitted AND direction in; invalid folds invalid/frozen/fraud_review; last_admitted_at = server receipt time. No name, no atom, no actor, no device.';
REVOKE ALL ON venue_api.session_admissions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON venue_api.session_admissions TO authenticated;

-- ---------------------------------------------------------------------------
-- A.4 venue_cmd.get_session_scan_counters — the 161-form invoker wrapper
-- ---------------------------------------------------------------------------
create or replace function venue_cmd.get_session_scan_counters(p_session_id uuid)
returns table (
  session_id       uuid,
  admitted         integer,
  duplicate        integer,
  invalid          integer,
  last_admitted_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at
    from venue.get_session_scan_counters(p_session_id) c
$$;
comment on function venue_cmd.get_session_scan_counters(uuid) is
  '163: invoker wrapper -> venue.get_session_scan_counters. Same P0002 for unknown and unauthorized sessions.';

-- ---------------------------------------------------------------------------
-- A.5 ACLs of PART A: strip PUBLIC/anon/authenticated, grant exactly authenticated
-- ---------------------------------------------------------------------------
do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'venue.get_session_scan_counters(uuid)',
    'venue.list_session_scan_counters()',
    'venue_cmd.get_session_scan_counters(uuid)'
  ];
begin
  foreach v_fn in array v_all loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end $$;

-- ============================================================================
-- PART B — the staff-session admission path (DROPPABLE; B's conditions 2026-10-26)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- B.0 venue.filter_staff_scan_meta — the allow-list, as a pure function (A+E
--     ruling 2026-10-26). ZERO grants; the definer below calls it as its owner.
-- ---------------------------------------------------------------------------
create or replace function venue.filter_staff_scan_meta(p_scan_meta jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key   text;
  v_label text;
  v_meta  jsonb := '{}'::jsonb;
begin
  if p_scan_meta is null then
    return v_meta;
  end if;
  if jsonb_typeof(p_scan_meta) <> 'object' then
    raise exception 'invalid_input: scan_meta must be a JSON object';
  end if;
  -- the named refusal first, whatever else the object carries (X-5 parity with record_scan_door)
  if p_scan_meta ? 'device_id' then
    raise exception 'invalid_input: scan_meta.device_id is not accepted';
  end if;
  for v_key in select k from jsonb_object_keys(p_scan_meta) k order by k loop
    if v_key = 'device_label' then
      if jsonb_typeof(p_scan_meta -> 'device_label') <> 'string' then
        raise exception 'invalid_input: scan_meta.device_label must be 1-64 chars';
      end if;
      v_label := p_scan_meta ->> 'device_label';
      if length(v_label) < 1 or length(v_label) > 64 then
        raise exception 'invalid_input: scan_meta.device_label must be 1-64 chars';
      end if;
      v_meta := v_meta || jsonb_build_object('device_label', v_label);
    elsif v_key = 'credential_version' then
      v_meta := v_meta || jsonb_build_object('credential_version', p_scan_meta -> 'credential_version');
    elsif v_key = 'key_id' then
      v_meta := v_meta || jsonb_build_object('key_id', p_scan_meta -> 'key_id');
    elsif v_key = 'occurred_at' then
      null;  -- STRIPPED: the ledger is stamped by the server; reserved for offline reconcile batches
    else
      raise exception 'invalid_input: scan_meta key not accepted: %', v_key;
    end if;
  end loop;
  return v_meta;
end;
$$;
comment on function venue.filter_staff_scan_meta(jsonb) is
  '163 (zero grant): the staff-path scan_meta allow-list. Keeps device_label (1-64 chars), credential_version and key_id as given; STRIPS occurred_at (server stamps time); REFUSES device_id by name, any other key by name, and a non-object. NULL -> {}. Called by venue.record_scan_staff.';
revoke all on function venue.filter_staff_scan_meta(jsonb) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- B.1 venue.record_scan_staff — command key, the allow-list, then venue.record_scan
--     with a NULL device. No authority of its own; no exception handler.
-- ---------------------------------------------------------------------------
create or replace function venue.record_scan_staff(
  p_atom_id uuid, p_session_id uuid, p_scan_meta jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meta jsonb;
begin
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  v_meta := venue.filter_staff_scan_meta(p_scan_meta);
  -- ONE authority: the flag gate, the venue_scanner/venue_manager gate and the core
  -- are venue.record_scan's (086/108). The device is never settable from this path.
  return venue.record_scan(p_atom_id, p_session_id, null::uuid, v_meta, p_command_key);
end;
$$;
comment on function venue.record_scan_staff(uuid, uuid, jsonb, text) is
  '163: the staff-session admission entrypoint (C7 amendment). Requires a command key, filters scan_meta through venue.filter_staff_scan_meta (device_label 1-64 chars, credential_version, key_id kept; occurred_at stripped; device_id and other keys refused), then calls venue.record_scan with a NULL device — role gate and native_scanning flag stay inside. No exception handler.';

-- ---------------------------------------------------------------------------
-- B.2 venue_cmd.record_scan — one line, LANGUAGE sql, SECURITY INVOKER
-- ---------------------------------------------------------------------------
create or replace function venue_cmd.record_scan(
  p_atom_id uuid, p_session_id uuid, p_scan_meta jsonb, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select venue.record_scan_staff(p_atom_id, p_session_id, p_scan_meta, p_command_key)
$$;
comment on function venue_cmd.record_scan(uuid, uuid, jsonb, text) is
  '163: invoker wrapper -> venue.record_scan_staff (no device parameter on this surface; actor = auth.uid()).';

-- ---------------------------------------------------------------------------
-- B.3 venue_cmd.validate_ticket_online — a READ, one line, STABLE
-- ---------------------------------------------------------------------------
create or replace function venue_cmd.validate_ticket_online(p_atom_id uuid, p_session_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select venue.validate_ticket_online(p_atom_id, p_session_id)
$$;
comment on function venue_cmd.validate_ticket_online(uuid, uuid) is
  '163: invoker wrapper -> venue.validate_ticket_online (086). venue_scanner/venue_manager gate inside.';

-- ---------------------------------------------------------------------------
-- B.4 ACLs of PART B
-- ---------------------------------------------------------------------------
do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'venue.record_scan_staff(uuid, uuid, jsonb, text)',
    'venue_cmd.record_scan(uuid, uuid, jsonb, text)',
    'venue_cmd.validate_ticket_online(uuid, uuid)'
  ];
begin
  foreach v_fn in array v_all loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end $$;

COMMIT;
