-- ============================================================================
-- 080_venue_staff_roles_and_predicates.sql
-- Phase-2 package 080 (PHASE E — venue roles + the remaining role predicates).
--
-- Frozen sources: plan §8/080 + PHASE E body (MN-2 corrected six-label set);
-- schema §3.9; ROLE_MODEL §3.4/§6.2 (HELPER-DERIVED); RLS §2.2 (R-8/R-9 helper
-- definitions), §9.9, §11.1 (AUTHZ-M7), §16.10, §16.10a (AUTHZ-PKG1 — the four
-- deferred venue-plane read policies, USING clauses verbatim, incl. the R3-3a
-- corrected `status <> 'draft'` form and the OPEN-1 scanner omission);
-- RPC §1.1a, §20.4.1/§20.4.2 (G-13); ODR-16 INV #23/#24 (the OR-17 rider:
-- kernel.on_identity_erased_staff's real body); registry depends_on
-- {076,077,078,079}.
--
-- ACTIVATION BOUNDARY: creating kernel.has_venue_role makes the PFA-10
-- deferred arms in 078 (create_venue, approve_venue is org/platform-only,
-- create_event, create_event_session, update_event, update_venue) and 079
-- (update_event_session) LIVE — their late-bound calls now resolve. Every
-- label array in those arms is confirmed ∈ the canonical six.
--
-- NOT here (deferred by name): venue.ticket_type/inventory (081) ·
-- door_pin/scan_device/door RPCs (086) · is_promoter_for_event (090) ·
-- assert_door_session (086). No F-clause host lives in 080 (dsm §3.2's F-1..F-7
-- name checkout/market/org verbs only).
-- ============================================================================

-- ============================================================================
-- PART 1 — venue.staff_role (schema §3.9; C36 disjoint venue scope)
-- ============================================================================

create table if not exists venue.staff_role (
  venue_id    uuid not null references catalog.venue(venue_id) on delete restrict,
  identity_id uuid not null references auth.users(id) on delete restrict,
  -- text + CHECK, never a native enum (§0.6.1/OD-6). The canonical SIX (MN-2:
  -- venue_door was RENAMED venue_scanner; venue_promoter was REMOVED — a
  -- promoter is a relationship, venue.promoter, not a staff grant).
  role        text not null check (role in
                ('venue_manager','venue_finance','venue_box_office',
                 'venue_marketing','venue_promoter_manager','venue_scanner')),
  -- nullable: INV #24 — the erased-identity hook SET NULLs it (grantor erasure
  -- must not orphan the grant row itself).
  granted_by  uuid references auth.users(id) on delete restrict,
  created_at  timestamptz not null default now(),
  constraint staff_role_pk primary key (venue_id, identity_id, role)
);

-- "my venues" — a navigation projection, NEVER an authorization input (§2.2c).
create index if not exists staff_role_identity_idx on venue.staff_role (identity_id);
create index if not exists staff_role_venue_role_idx on venue.staff_role (venue_id, role);

-- ============================================================================
-- PART 2 — the four predicates (RLS §2.2; RPC §1.1a; SEAM-1 binds them HERE:
-- has_venue_role reads venue.staff_role, created in this package)
-- ============================================================================

-- Reads venue.staff_role ONLY (R-8: the door-PIN branch is REMOVED — door
-- principals never satisfy this predicate). Live-table point probe (C9/I-5):
-- a revoke takes effect on the very next call, on the same JWT. Fail-closed on
-- every degenerate input: NULL caller, NULL venue, NULL/empty role array and an
-- unknown venue all yield no matching row => false.
create or replace function kernel.has_venue_role(p_venue_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from venue.staff_role s
     where s.venue_id = p_venue_id
       and s.identity_id = auth.uid()
       and s.role = any (p_roles)
  )
$$;

-- Resolves event -> venue via catalog, then delegates. The single place
-- event-grain authorization becomes venue-grain authority (§2.2) — no table
-- stores an "event role", so there is no second source of venue authority.
create or replace function kernel.has_event_role(p_event_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select kernel.has_venue_role(
    (select e.venue_id from catalog.event e where e.event_id = p_event_id),
    p_roles)
$$;

-- The ONLY sanctioned expression of org->venue inheritance on the read path
-- (RM-3): resolve catalog.venue.org_id, delegate to has_org_role. RM-4: no
-- venue->org path exists in any helper.
create or replace function kernel.has_org_role_over_venue(p_venue_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select kernel.has_org_role(
    (select v.org_id from catalog.venue v where v.venue_id = p_venue_id),
    p_roles)
$$;

create or replace function kernel.has_org_role_over_event(p_event_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select kernel.has_org_role(
    (select e.org_id from catalog.event e where e.event_id = p_event_id),
    p_roles)
$$;

-- ============================================================================
-- PART 3 — venue.grant_staff_role / venue.revoke_staff_role (RPC §20.4.1/.2)
-- ============================================================================

create or replace function venue.grant_staff_role(
  p_venue_id uuid, p_identity_id uuid, p_role text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_status   text;
  v_allowed  boolean := false;
  v_inserted integer := 0;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  -- p_role re-validated in-body against the 080 CHECK set: venue_door and
  -- venue_promoter are the superseded labels and raise; the label sets are
  -- disjoint by scope, so an org_* or platform_* label raises too (C36).
  if p_role not in ('venue_manager','venue_finance','venue_box_office',
                    'venue_marketing','venue_promoter_manager','venue_scanner') then
    raise exception 'precondition_failed: bad_role %', p_role;
  end if;

  -- No self-grant (I-11/H-2).
  if p_identity_id = v_uid then
    raise exception 'precondition_failed: self_grant';
  end if;

  select v.approval_status into v_status
    from catalog.venue v where v.venue_id = p_venue_id;
  if v_status is null then
    raise exception 'not_found: venue %', p_venue_id using errcode = 'P0002';
  end if;
  if v_status = 'archived' then
    raise exception 'precondition_failed: venue_archived';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_identity_id) then
    raise exception 'not_found: identity %', p_identity_id using errcode = 'P0002';
  end if;
  -- dsm §1.3: ERASED is terminal, and INV #23's CLEANED disposition ("a
  -- tombstone holds no authority") is stable only if no writer can recreate
  -- the row post-tombstone — without this, any manager resurrects authority
  -- for an erased account the sweep just cleaned (erratum E-26; the E-23
  -- principle applied to the one 080 verb that confers authority on a
  -- counterparty). DELETION_PENDING is deliberately NOT refused: roles are not
  -- blockers, and the freeze surface (dsm §3.2) names no staff-grant refusal.
  -- The check takes FOR SHARE on the target's identity_ext row — the F-11
  -- construction: the deletion sweep's terminal entry holds FOR UPDATE on the
  -- same row across its BP evaluation AND the INV #23 cleanup, so either this
  -- grant commits first (and the tombstone's cleanup removes the fresh row) or
  -- the tombstone commits first (and this check reads ERASED and refuses).
  -- Without the lock, a grant that observed DELETION_PENDING could commit
  -- after the tombstone: ERASED ∧ holds-authority — proven with a real
  -- interleave before this lock was added (erratum E-26).
  -- A target with NO identity_ext row has never requested deletion; there is
  -- nothing to race, and a later request finds the row and cleans it.
  declare
    v_del text;
  begin
    select e.deletion_state into v_del
      from kernel.identity_ext e
     where e.identity_id = p_identity_id
     for share;
    if v_del = 'ERASED' then
      raise exception 'precondition_failed: identity_erased — a tombstone holds no authority';
    end if;
  end;
  -- The target need NOT already be org-affiliated: is_org_affiliate is a
  -- scoping input, never an authorizing one (RM-6).

  -- AUTHZ-M7 — the venue-plane tier guard. venue_manager is one of only three
  -- principals that may open_door_manifest (O-4): a venue_manager minting
  -- another venue_manager is minting a custody-boundary principal. The org
  -- tier above the venue is the correct minter (MD-15), and it already reaches
  -- every venue through the §1.1a helper — never a re-inlined org_id join.
  if p_role = 'venue_manager' then
    v_allowed := kernel.has_org_role_over_venue(p_venue_id, array['org_owner','org_admin'])
              or kernel.is_platform(array['platform_admin']);
    if not v_allowed
       and kernel.has_venue_role(p_venue_id, array['venue_manager']) then
      raise exception 'precondition_failed: tier_guard — venue_manager is granted from the org plane';
    end if;
  else
    v_allowed := kernel.has_venue_role(p_venue_id, array['venue_manager'])
              or kernel.has_org_role_over_venue(p_venue_id, array['org_owner','org_admin'])
              or kernel.is_platform(array['platform_admin']);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager (non-manager labels) or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- Admin-plane lock, outside the six ranks; PK makes a re-grant noop_replay.
  perform 1 from venue.staff_role s
    where s.venue_id = p_venue_id and s.identity_id = p_identity_id
    for update;
  insert into venue.staff_role (venue_id, identity_id, role, granted_by)
  values (p_venue_id, p_identity_id, p_role, v_uid)
  on conflict on constraint staff_role_pk do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return jsonb_build_object('status','noop_replay','venue_id',p_venue_id,
                              'identity_id',p_identity_id,'role',p_role);
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'venue.staff_role.grant', 'identity', p_identity_id, 'staff_grant',
          (select coalesce(jsonb_agg(s.role order by s.role), '[]'::jsonb)
             from venue.staff_role s
            where s.venue_id = p_venue_id and s.identity_id = p_identity_id
              and s.role <> p_role),
          (select jsonb_agg(s.role order by s.role)
             from venue.staff_role s
            where s.venue_id = p_venue_id and s.identity_id = p_identity_id));

  return jsonb_build_object('status','ok','venue_id',p_venue_id,
                            'identity_id',p_identity_id,'role',p_role);
end;
$$;

create or replace function venue.revoke_staff_role(
  p_venue_id uuid, p_identity_id uuid, p_role text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid;
  v_allowed boolean := false;
  v_removed integer := 0;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;

  -- §20.4.2: the guard is ASYMMETRIC on purpose — venue_manager may revoke any
  -- label INCLUDING venue_manager (dropping authority is not escalation), and
  -- SELF-REVOKE is permitted (a departing manager can stand down). There is no
  -- last-venue_manager floor: a venue with zero managers is recoverable from
  -- the org tier — which is exactly why that floor does not exist here while
  -- §2.4's last-org_owner floor does.
  v_allowed := (p_identity_id = v_uid)
            or kernel.has_venue_role(p_venue_id, array['venue_manager'])
            or kernel.has_org_role_over_venue(p_venue_id, array['org_owner','org_admin'])
            or kernel.is_platform(array['platform_admin']);
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  perform 1 from venue.staff_role s
    where s.venue_id = p_venue_id and s.identity_id = p_identity_id
    for update;
  delete from venue.staff_role s
   where s.venue_id = p_venue_id and s.identity_id = p_identity_id
     and s.role = p_role;
  get diagnostics v_removed = row_count;
  if v_removed = 0 then
    return jsonb_build_object('status','noop_replay');
  end if;

  -- GP-2 on a PK-only role table: the audit row carries the removed grant.
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'venue.staff_role.revoke', 'identity', p_identity_id, 'staff_revoke',
          jsonb_build_object('venue_id', p_venue_id, 'role', p_role), null);

  -- Revocation takes effect immediately, everywhere, with no TTL: every
  -- has_venue_role call is a live table read (I-5) — no JWT survives it.
  return jsonb_build_object('status','ok');
end;
$$;

-- ============================================================================
-- PART 4 — OR-17 rider: kernel.on_identity_erased_staff's REAL body
-- (SEAM-2a body-only; INV #23/#24, dsm §4.5 — terminal cleanup, executed by
-- the 077 sweep at tombstone entry, never at DELETION_PENDING entry)
-- ============================================================================

create or replace function kernel.on_identity_erased_staff(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$
  -- INV #23: the erased identity's venue capability rows are removed — a
  -- tombstoned account holds no staff authority anywhere.
  delete from venue.staff_role s where s.identity_id = p_identity;
  -- INV #24 (CLEANED — SET NULL): grants MADE BY the erased identity survive
  -- (the grantee's authority is a fact of the venue, not of the grantor), but
  -- the grantor link is cut rather than left pointing at a tombstone.
  update venue.staff_role s set granted_by = null where s.granted_by = p_identity;
$$;

-- ============================================================================
-- PART 5 — RLS on venue.staff_role (§9.9; §16.10 register: three names)
-- ============================================================================

alter table venue.staff_role enable row level security;
-- INV-NOFORCE (I-12): this table's own read policy calls has_venue_role, which
-- SELECTs this same table. The model does not recurse ONLY because the helper
-- is SECURITY DEFINER owned by postgres and the table owner bypasses RLS.
-- FORCE would remove that bypass. relforcerowsecurity MUST stay false
-- (T-RLS-FORCE-02 asserts it positively).

revoke all on venue.staff_role from anon, authenticated;
grant select on venue.staff_role to authenticated;

-- every staff label reads its own venue's roster (§9.9: A(own-venue roster) —
-- the self-read rows are a subset).
drop policy if exists venue_staff_role_sel_venue on venue.staff_role;
create policy venue_staff_role_sel_venue
  on venue.staff_role for select to authenticated
  using (kernel.has_venue_role(
           venue_id,
           array['venue_manager','venue_finance','venue_box_office',
                 'venue_marketing','venue_promoter_manager','venue_scanner']));

drop policy if exists venue_staff_role_sel_org on venue.staff_role;
create policy venue_staff_role_sel_org
  on venue.staff_role for select to authenticated
  using (kernel.has_org_role_over_venue(venue_id, array['org_owner','org_admin']));

drop policy if exists venue_staff_role_sel_platform on venue.staff_role;
create policy venue_staff_role_sel_platform
  on venue.staff_role for select to authenticated
  using (kernel.is_platform(array['platform_admin','platform_support','platform_risk']));

-- ============================================================================
-- PART 6 — AUTHZ-PKG1: the FOUR deferred venue-plane read policies, created
-- HERE, after their helpers (RLS §16.10a — USING clauses verbatim)
-- ============================================================================

-- §8.1: venue_manager A(own venue incl. draft); every other venue label A(own venue).
drop policy if exists catalog_venue_sel_venue on catalog.venue;
create policy catalog_venue_sel_venue
  on catalog.venue for select to authenticated
  using (
    kernel.has_venue_role(
      venue_id,
      array['venue_manager','venue_finance','venue_box_office',
            'venue_marketing','venue_promoter_manager','venue_scanner'])
  );

-- §8.2, two tiers, and the difference is load-bearing: only venue_manager sees
-- a DRAFT event. R3-3a: the test is `status <> 'draft'` — NEVER
-- `status >= 'announced'`, which is lexicographic over a text column and true
-- for every label including 'draft'.
drop policy if exists catalog_event_sel_venue on catalog.event;
create policy catalog_event_sel_venue
  on catalog.event for select to authenticated
  using (
        kernel.has_venue_role(venue_id, array['venue_manager'])
     or (     status <> 'draft'
          and kernel.has_venue_role(
                venue_id,
                array['venue_finance','venue_box_office','venue_marketing',
                      'venue_promoter_manager','venue_scanner']) )
  );

-- The table carries event_id, so the EVENT-grain helper applies directly.
-- OPEN-1: the venue_scanner "tonight" narrowing has NO specification anywhere —
-- the scanner arm is deliberately ABSENT (fail-closed; a scanner reads its
-- manifest through venue.get_door_manifest, 086), filed to the RLS owner.
drop policy if exists catalog_event_session_sel_venue on catalog.event_session;
create policy catalog_event_session_sel_venue
  on catalog.event_session for select to authenticated
  using (
    kernel.has_event_role(
      event_id,
      array['venue_manager','venue_finance','venue_box_office',
            'venue_marketing','venue_promoter_manager'])
  );

-- Carries BOTH arms of the §7.5 grant (GP-3 NOTE: the org arm is not split into
-- its own policy — T-RLS-POL-01 pins the exact per-table list). kernel.tickets
-- is at SESSION grain and no session-grain helper exists (OPEN-2): the
-- correlated sub-select is a grain resolution, not an authority join.
drop policy if exists kernel_tickets_sel_venue on kernel.tickets;
create policy kernel_tickets_sel_venue
  on kernel.tickets for select to authenticated
  using (
        kernel.has_org_role(org_id, array['org_owner','org_admin','org_finance'])
     or kernel.has_event_role(
          ( select s.event_id from catalog.event_session s
             where s.session_id = kernel.tickets.event_session_id ),
          array['venue_manager','venue_finance','venue_scanner'])
  );

-- I-4 (§16.10a): the issuing-venue/org read is col-scoped — current_owner_id
-- (owner PII, §7.5 footnote 8) is NOT among the granted columns. A row-level
-- clause cannot express a per-policy column set (one role, one grant — the
-- platform impossibility recorded as E-24), so the discipline is carried by
-- the GRANT: re-issue kernel.tickets' authenticated grant with every column
-- EXCEPT current_owner_id. The owner's row visibility is unaffected
-- (sel_owner's predicate is a policy expression, outside column ACLs), and an
-- owner client never needs to SELECT the column — it is by definition their
-- own auth.uid().
revoke select on kernel.tickets from authenticated;
grant select (ticket_atom_id, event_session_id, org_id, ticket_type_id, serial_no,
              state, resale_state, credential_version, signing_key_id, home_region,
              seat_ref, unit_row_id, external_seat_ref, issued_at, created_at, updated_at)
  on kernel.tickets to authenticated;

-- ============================================================================
-- PART 7 — function ACLs (I-7: strip PUBLIC, then grant exactly)
-- ============================================================================

do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'kernel.has_venue_role(uuid, text[])',
    'kernel.has_event_role(uuid, text[])',
    'kernel.has_org_role_over_venue(uuid, text[])',
    'kernel.has_org_role_over_event(uuid, text[])',
    'venue.grant_staff_role(uuid, uuid, text, text)',
    'venue.revoke_staff_role(uuid, uuid, text, text)'
  ];
  -- plan §8/080 Grants row: EXECUTE on the four predicates to authenticated.
  -- grant/revoke_staff_role are caller-authorized RPCs (RLS §11.1) — also
  -- authenticated; their bodies carry the AUTHZ-M7 authority.
  v_auth constant text[] := array[
    'kernel.has_venue_role(uuid, text[])',
    'kernel.has_event_role(uuid, text[])',
    'kernel.has_org_role_over_venue(uuid, text[])',
    'kernel.has_org_role_over_event(uuid, text[])',
    'venue.grant_staff_role(uuid, uuid, text, text)',
    'venue.revoke_staff_role(uuid, uuid, text, text)'
  ];
begin
  foreach v_fn in array v_all loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
  end loop;
  foreach v_fn in array v_auth loop
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
  -- kernel.on_identity_erased_staff: ACL untouched by CREATE OR REPLACE — it
  -- keeps 077's DEF class (service_role EXECUTE; sweep-internal).
end $$;
