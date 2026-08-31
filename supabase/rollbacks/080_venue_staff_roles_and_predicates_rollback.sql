-- ============================================================================
-- ROLLBACK for 080_venue_staff_roles_and_predicates.sql
-- POSTURE: CLEAN-WHILE-EMPTY (plan §8/080). Refuses once venue.staff_role
-- holds any grant row — a live authority surface is forward-fix territory.
--
-- Order is the frozen one: the four AUTHZ-PKG1 policies FIRST (fails closed —
-- the venue plane goes dark; a table is never left readable by a principal
-- whose predicate has just been dropped), then the RPCs and venue.staff_role's
-- own policies (both consumers of the predicates, either order), then the
-- predicates, then the table.
--
-- OR-17 rider F-5: kernel.on_identity_erased_staff is restored to its 077
-- stub body VERBATIM — a rolled-back replacer must never leave a body
-- referencing a dropped table live under the 2-minute sweep.
--
-- kernel.tickets' authenticated column grant is restored to the post-079
-- state (full-column SELECT) — the I-4 narrowing travels with the venue
-- policy it serves. HARDENING-1, the 079 BP-1 body and the PFA-13 posture
-- are untouched by this script.
-- ============================================================================

begin;

-- PART 0 — refusal guard
do $$
declare
  v_rows bigint := 0;
begin
  if to_regclass('venue.staff_role') is not null then
    execute 'select count(*) from venue.staff_role' into v_rows;
  end if;
  if v_rows > 0 then
    raise exception 'REFUSED: venue.staff_role holds % grant row(s). Staff authority is live — CLEAN-WHILE-EMPTY only (plan §8/080); revoke the grants through venue.revoke_staff_role first.', v_rows;
  end if;
end $$;

-- PART 1 — the four AUTHZ-PKG1 policies, first
drop policy if exists kernel_tickets_sel_venue on kernel.tickets;
drop policy if exists catalog_event_session_sel_venue on catalog.event_session;
drop policy if exists catalog_event_sel_venue on catalog.event;
drop policy if exists catalog_venue_sel_venue on catalog.venue;

-- PART 2 — restore kernel.tickets' post-079 grant (full-column SELECT)
revoke select on kernel.tickets from authenticated;
grant select on kernel.tickets to authenticated;

-- PART 3 — OR-17 rider F-5: the 077 stub body, verbatim
create or replace function kernel.on_identity_erased_staff(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;              -- INV #23/#24; real body 080

-- PART 4 — the staff RPCs, then the predicates (policy consumers are gone)
drop function if exists venue.revoke_staff_role(uuid, uuid, text, text);
drop function if exists venue.grant_staff_role(uuid, uuid, text, text);
drop policy if exists venue_staff_role_sel_platform on venue.staff_role;
drop policy if exists venue_staff_role_sel_org on venue.staff_role;
drop policy if exists venue_staff_role_sel_venue on venue.staff_role;
drop function if exists kernel.has_org_role_over_event(uuid, text[]);
drop function if exists kernel.has_org_role_over_venue(uuid, text[]);
drop function if exists kernel.has_event_role(uuid, text[]);
drop function if exists kernel.has_venue_role(uuid, text[]);

-- PART 5 — the table
drop table if exists venue.staff_role;

commit;
