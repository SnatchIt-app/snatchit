-- ============================================================================
-- 20261030030000_door_schedule_conformance.sql — registry 190 / pgTAP 260 (B writes, A reviews;
-- A's allocation 2026-10-27).
--
-- WHAT THIS MIGRATION IS. DRAFT / unapplied / undeployed. Body-only re-create of ONE function,
-- catalog.set_session_door_schedule (086 PART 9), to the frozen contract RPC §20.6.5. No new
-- object, no signature change, no grant change, no public-schema object; Gate-2 and the catalog
-- function census are untouched (+0). Replay-safe behind an md5 PRE-FLIGHT that accepts the 086
-- body or this body, with a POST-APPLY self-check (the 183/187 house pattern).
--
-- ── WHAT WAS MISSING (§20.6.5, "Guards … are custody properties, not validation") ───────────
-- The 086 body takes the row lock, refuses an unknown session and freezes once the boundary is
-- taken, and it writes doors_at. Everything else the contract requires was absent:
--   A  AUTHORITY — §20.6.5 inherits O4-3's allow-list, which includes
--      is_platform(['platform_admin']); 086 allowed only org_owner/org_admin or venue_manager.
--      The check also ran AFTER the boundary test, so an unauthorized caller learned whether the
--      boundary was engaged. Authority now runs first: an outsider gets one answer, always.
--   B  The frozen-boundary refusal used free text ("door already opened — schedule is frozen");
--      the contract (and 079/093's sibling guard) name it `precondition_failed: boundary_engaged`.
--   C  CUSTODY GUARDS were missing entirely. doors_at feeds catalog.effective_freeze_at, so a
--      later move pushes the implicit backstop later and re-opens the live-door/open-transfer
--      overlap C6 exists to close. Contract: free while the session has no atom; once atoms
--      exist, earlier freely and later only within config('door.schedule_move_grace_interval'),
--      with a MANDATORY reason code. The comparison shape, the fail-to-safe when the key is
--      absent (PFA-9 CLASS A: spelled, consumed, NOT seeded ⇒ no later move at all) and the
--      reason_required raise are the 079:630-658 / 093:7067-7095 idiom, kept identical so the
--      three siblings cannot drift.
--   D  AUDIT + RESULT. The contract requires a kernel.admin_audit row
--      ('session.door_schedule.change', before/after, reason_code) and returns
--      { status, session_id, doors_at, effective_freeze_at } — "the recomputed boundary is
--      returned, so the operator sees the consequence in the same round trip". 086 returned
--      { status, session_id } and wrote no audit row.
--
-- ── WHAT IS NOT CHANGED, DELIBERATELY ────────────────────────────────────────────────────────
-- * p_command_key stays accepted and UNUSED. catalog.event_session carries no
--   command_idempotency_key column, and inventing a replay store is not this migration's job
--   (same recorded position as 183 / E-F1). A same-key re-send is simply a second valid move,
--   which the guards above already bound; the audit row makes it visible.
-- * The function still READS door_open_at for guard B. **Contract ambiguity, flagged for A, not
--   silently resolved:** RLS §2208 and ROLE_MODEL §1494 say this function "never references
--   door_open_at (structural assertion T-RPC-DOOR-23)", while §20.6.5 itself requires it to be
--   "frozen entirely once door_open_at IS NOT NULL". Both cannot hold literally. The only
--   coherent reading is that T-RPC-DOOR-23 forbids WRITING the ledger head — catalog.
--   engage_door_freeze is its sole writer (O-5), which is the property the assertion protects —
--   while reading it is what guard B is. pgTAP 260 therefore pins the absence of any ASSIGNMENT
--   to door_open_at (and the trigger keeps the write side honest regardless). If A reads
--   T-RPC-DOOR-23 more strictly, the guard has to move behind a definer helper and §20.6.5's
--   freeze clause needs a ruling; say so and I will change it.
-- * auth.uid() is the audit actor and kernel.admin_audit.actor_identity is NOT NULL, so a caller
--   with no identity cannot write a schedule change: it fails closed at the insert. The function
--   is one of the thirteen caller-authorized catalog RPCs (142 F3), so an authenticated caller
--   always has one.
--
-- Not a pop-up blocker: for Nov 30 doors are set through create/update_event_session's doors_at
-- (which already carries this same guard set — that is where the idiom is copied from).
-- Order: after 183 (20261026210000) and 187 (20261027000000); independent of both.
-- ============================================================================
begin;

-- ── PRE-FLIGHT (stacking guard, 183/187 pattern): the body being replaced must be the 086 body
-- (first apply) or this migration's body (idempotent re-apply); anything else means a later
-- change landed first and would be silently overwritten — refuse.
do $pf$
declare v_md5 text := md5(pg_get_functiondef('catalog.set_session_door_schedule(uuid,timestamptz,text,text)'::regprocedure));
begin
  if v_md5 not in ('ff724eaf52e7713773c8e301a4b9d448', '68d48676a48bf3d1b440a2e6be40a83e') then
    raise exception 'precondition_failed: 190 refuses to overwrite an unexpected catalog.set_session_door_schedule body (md5 %) — re-examine the migration order', v_md5;
  end if;
end $pf$;

create or replace function catalog.set_session_door_schedule(
  p_session_id uuid, p_doors_at timestamptz, p_reason_code text, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row catalog.event_session%rowtype;
        -- ── 190 BLOCK VARS — the scope resolved once (086 re-read it inside each role test), plus
        -- the custody-guard, audit and result locals.
        v_org uuid; v_venue uuid;
        v_has_atoms boolean; v_grace interval; v_reason text; v_freeze timestamptz;
        -- ── 190 BLOCK VARS END
begin
  select * into v_row from catalog.event_session where session_id = p_session_id for update;
  if not found then raise exception 'not_found: session %', p_session_id using errcode = 'P0002'; end if;
  -- ── 190 BLOCK A — AUTHORITY FIRST, and §20.6.5's full allow-list (adds platform_admin). Running
  -- it before guard B means an unauthorized caller never learns the boundary state.
  select ev.org_id, ev.venue_id into v_org, v_venue
    from catalog.event ev where ev.event_id = v_row.event_id;
  if not (kernel.has_org_role(v_org, array['org_owner','org_admin'])
          or kernel.has_venue_role(v_venue, array['venue_manager'])
          or kernel.is_platform(array['platform_admin'])) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- ── 190 BLOCK A END
  -- ── 190 BLOCK B — once the boundary is taken, the schedule that produced it is evidence.
  -- Reads door_open_at; never writes it (T-RPC-DOOR-23 — see the header's flagged ambiguity).
  if v_row.door_open_at is not null then
    raise exception 'precondition_failed: boundary_engaged';
  end if;
  -- ── 190 BLOCK B END
  -- ── 190 BLOCK C — custody guards (§20.2.4 shape, 079:630-658 idiom kept identical). doors_at is
  -- an input to catalog.effective_freeze_at: free while no atom exists; once atoms exist, earlier
  -- freely and later only INSIDE the grace, with a mandatory reason code. A NULL p_doors_at clears
  -- the schedule, which moves the backstop EARLIER (to starts_at), so it is never grace-bound.
  select exists (select 1 from kernel.tickets t where t.event_session_id = p_session_id)
    into v_has_atoms;
  if v_has_atoms then
    -- config('door.schedule_move_grace_interval') is a PFA-9 CLASS A key: NOT seeded, implemented
    -- FAIL-TO-SAFE — absent means NO later move is permitted (the X-12 shape, ruled in PFA-9).
    begin
      v_grace := (select (c.value #>> '{}')::interval
                    from catalog.platform_config c
                   where c.key = 'door.schedule_move_grace_interval'
                   order by c.version desc
                   limit 1);
    exception when others then
      v_grace := null;
    end;
    if p_doors_at is not null
       and ((v_row.doors_at is not null and p_doors_at > v_row.doors_at
             and (v_grace is null or p_doors_at - v_row.doors_at >= v_grace))
         or (v_row.doors_at is null and p_doors_at > v_row.starts_at
             and (v_grace is null or p_doors_at - v_row.starts_at >= v_grace))) then
      raise exception 'precondition_failed: move_exceeds_grace';
    end if;
    -- any move with atoms issued is audited with a MANDATORY reason code.
    v_reason := p_reason_code;
    if v_reason is null or length(trim(v_reason)) = 0 then
      raise exception 'precondition_failed: reason_required';
    end if;
  end if;
  -- ── 190 BLOCK C END
  update catalog.event_session set doors_at = p_doors_at, updated_at = now() where session_id = p_session_id;
  -- ── 190 BLOCK D — the contracted audit row and result. actor_identity is NOT NULL, so a caller
  -- without an identity fails closed here rather than moving a schedule unattributably.
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (auth.uid(), 'session.door_schedule.change', 'event_session', p_session_id,
          coalesce(nullif(trim(coalesce(p_reason_code, '')), ''), 'schedule_set'),
          jsonb_build_object('doors_at', v_row.doors_at),
          jsonb_build_object('doors_at', p_doors_at));
  v_freeze := catalog.effective_freeze_at(p_session_id);
  return jsonb_build_object('status','ok','session_id', p_session_id,
                            'doors_at', p_doors_at, 'effective_freeze_at', v_freeze);
  -- ── 190 BLOCK D END
end;
$$;
comment on function catalog.set_session_door_schedule(uuid,timestamptz,text,text) is
  'RPC §20.6.5 (086 + 190): correct a session''s PUBLISHED door time (doors_at), never the ledger head door_open_at (catalog.engage_door_freeze is its sole writer, O-5). Authority first: org_owner/org_admin, venue_manager or platform_admin. Refuses boundary_engaged once door_open_at is set; once the session has atoms, moves earlier freely and later only within config(door.schedule_move_grace_interval) (absent ⇒ no later move, PFA-9 fail-to-safe) and requires a reason code. Writes kernel.admin_audit session.door_schedule.change with before/after. Returns {status, session_id, doors_at, effective_freeze_at}. p_command_key is accepted and unused (no replay store on event_session).';

-- ── POST-APPLY SELF-CHECK: the written body must be exactly this migration's body (a modified
-- copy would otherwise pass the pre-flight as an idempotent re-apply and overwrite).
do $pc$
declare v_md5 text := md5(pg_get_functiondef('catalog.set_session_door_schedule(uuid,timestamptz,text,text)'::regprocedure));
begin
  if v_md5 <> '68d48676a48bf3d1b440a2e6be40a83e' then
    raise exception 'precondition_failed: 190 post-apply self-check — the written body (md5 %) is not this migration''s body; this file was modified', v_md5;
  end if;
end $pc$;

commit;
