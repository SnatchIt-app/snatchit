-- ============================================================================
-- 20261027020000_e76_venue_org_conjunct_catalog_event_verbs.sql — registry 165
-- (pgTAP 232): the E-76 venue-org conjunct on the four catalog event verbs that
-- still lack it, so a venue_manager / venue_marketing role row that outlived an
-- out-of-band operator change no longer acts on the FORMER operator's events.
--
-- Registry 165 / pgTAP 232 — assigned by Claude A 2026-10-26. A reviews before
-- this leaves draft. DARK: applied nowhere but local rehearsal clones; exposes
-- no schema, flips no flag, seeds no config key, writes no row, creates no
-- object and changes no grant. REQUIRED before any production exposure of
-- venue_cmd (164's wrappers route to these bodies); not needed for the sandbox.
-- ORDER: last of D's venue stack (#143 → #166 → #168 → #169 → #170 → 183 → 185
-- → 187 → 164 → 166 → 167 → 165). It depends on no 159–167 object: it replaces
-- four bodies that 078 / 093 / 102 created; the pre-flight below is the guard.
--
-- WHAT CHANGES — four BODY-ONLY replaces (same signature, result type,
-- LANGUAGE plpgsql, SECURITY DEFINER, search_path = ''; CREATE OR REPLACE keeps
-- the owner, the ACL and the comment — the post-flight refuses any difference):
--   catalog.update_event(uuid, jsonb, text)           (078)
--   catalog.create_event_session(uuid, jsonb, text)   (078)
--   catalog.update_event_session(uuid, jsonb, text)   (093)
--   catalog.publish_event(uuid, text, text)           (102)
-- Each body is its predecessor copied byte for byte with ONE edit: the venue-role
-- arm (has_venue_role … venue_manager, plus venue_marketing on the marketing-only
-- patch of update_event / update_event_session) gains
--     and exists (select 1 from catalog.venue v
--                  where v.venue_id = <event's venue> and v.org_id = <event's org>)
-- — 088 catalog.cancel_event's E-76 conjunct (088:1628-1633), inlined, keyed on
-- the event already read by the body. B's shape (187, venue.assert_session_operator;
-- D/s7-e76-catalog/B-CONJUNCT-SHAPE-187.md) is matched:
--   (a) the comparison is catalog.venue.org_id = catalog.event.org_id — the
--       venue's CURRENT operator vs the event's org;
--   (b) a failed conjunct raises the body's OWN existing refusal, unchanged, so a
--       wrong-operator caller gets the byte-identical 42501 message a caller with
--       no role gets (232 F6–F9 compare the two SQLERRMs);
--   (c) a venue-less event fails closed: catalog.event.venue_id is NOT NULL with
--       an FK (078:136), and the exists() is false for any missing room row.
-- No second helper: the expression is inlined, as B asked.
--
-- WHO IS AFFECTED: only a caller who reaches the venue-role arm (no org_owner /
-- org_admin role on the event's org — nor org_marketing on a marketing-only
-- patch) for an event whose room is now operated by ANOTHER org. That state
-- exists only from history: update_venue's org_id path is frozen (093, Decision C,
-- 'operatorship_transfer_frozen'), so 232 models the move with a direct
-- UPDATE catalog.venue as postgres (B's 257 does the same). Unchanged on purpose:
--   * the ORG arm (the event's own org_owner / org_admin / org_marketing) — 088's
--     and 162's precedent; an org keeps authority over its own event at a room it
--     no longer operates (231 S17, 232 Section O);
--   * catalog.create_event — the event's org is DERIVED from the room's current
--     org, so the conjunct holds by construction (231 S2/S9 baseline);
--   * catalog.update_venue — no event to bind; 164's S8 baseline (the room's
--     staff grant edits the room); catalog.cancel_event — already has it (088);
--   * the existence order: every one of these bodies answers an unknown event /
--     session 'not_found' (P0002) BEFORE authority (078/093/102) — pre-existing,
--     pinned in 232 Section U, flagged for A/B, not changed here;
--   * a manager whose role row outlived the move still acts on the NEW
--     operator's events at that room (the conjunct holds there) — revoking such
--     rows belongs to the operator-transfer path, which is frozen (232 Section B).
--
-- PRE-FLIGHT (house pattern: 162 / 163): every one of the four must exist exactly
-- once by name in catalog and carry its predecessor's body or 165's own (re-apply);
-- anything else is a foreign body and is refused with
--   MIGRATION_165_REFUSED (pre-flight): <fn> body is neither the predecessor's nor 165's (md5 <x>); nothing changed
-- (one transaction; psql -v ON_ERROR_STOP=1 exits 3). md5(prosrc) on PG17 (CI and
-- production): a change to any body must re-hash it here and in the rollback:
--   catalog.update_event(uuid, jsonb, text)            078: ea572709f85bbab2d8b10dcd38073155   165: 1bf2a04bf1ffccfdbed04d8b067dd2df
--   catalog.create_event_session(uuid, jsonb, text)    078: 66eb523f94dca9679e64b2a6fef3a13b   165: ee243b12a8b51c7692a8f6ed22506a34
--   catalog.update_event_session(uuid, jsonb, text)    093: cc30a196b4e61acbd13f750b68ffcf3d   165: 9e834d57e7810f81d1f9ed11c79dcd24
--   catalog.publish_event(uuid, text, text)            102: b756ad2076bf856f8ce9d7bafa4655f4   165: b31abddf9aad2cb7b119d517424bb494
-- POST-FLIGHT: the four bodies are 165's; owner, ACL (proacl text), prosecdef,
-- proconfig and comment equal the pre-flight snapshot.
-- ROLLBACK: supabase/rollbacks/20261027020000_e76_venue_org_conjunct_catalog_event_verbs_rollback.sql
-- restores the four predecessor bodies byte for byte (G1 refuses a foreign body).
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TEMP TABLE e76_165_snap ON COMMIT DROP AS
  SELECT p.proname::text AS fn, p.proowner, p.proacl::text AS acl, p.prosecdef,
         p.proconfig::text AS cfg, obj_description(p.oid, 'pg_proc') AS cmt
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'catalog'
     AND p.proname IN ('update_event','create_event_session','update_event_session','publish_event');

DO $pre$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT e.fname, e.sig,
           (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'catalog' AND p.proname = e.fname) AS n_by_name,
           (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure(e.sig)) AS h,
           e.h_pred, e.h_165
      FROM (VALUES
              ('update_event', 'catalog.update_event(uuid, jsonb, text)', 'ea572709f85bbab2d8b10dcd38073155', '1bf2a04bf1ffccfdbed04d8b067dd2df'),
              ('create_event_session', 'catalog.create_event_session(uuid, jsonb, text)', '66eb523f94dca9679e64b2a6fef3a13b', 'ee243b12a8b51c7692a8f6ed22506a34'),
              ('update_event_session', 'catalog.update_event_session(uuid, jsonb, text)', 'cc30a196b4e61acbd13f750b68ffcf3d', '9e834d57e7810f81d1f9ed11c79dcd24'),
              ('publish_event', 'catalog.publish_event(uuid, text, text)', 'b756ad2076bf856f8ce9d7bafa4655f4', 'b31abddf9aad2cb7b119d517424bb494')
           ) AS e(fname, sig, h_pred, h_165)
  LOOP
    IF r.n_by_name <> 1 OR r.h IS NULL OR r.h NOT IN (r.h_pred, r.h_165) THEN
      RAISE EXCEPTION 'MIGRATION_165_REFUSED (pre-flight): % body is neither the predecessor''s nor 165''s (md5 %, % by name); nothing changed',
        r.sig, coalesce(r.h, '<absent>'), r.n_by_name;
    END IF;
  END LOOP;
END $pre$;

-- catalog.update_event(uuid, jsonb, text) — 078's body + the E-76 conjunct on the venue-role arm
create or replace function catalog.update_event(
  p_event_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_venue_id  uuid;
  v_status    text;
  v_before    jsonb;
  v_key       text;
  v_reason    text;
  v_allowed   boolean := false;
  v_marketing boolean := false;
  v_title_chg boolean := false;
  v_changed   boolean := false;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'invalid_input: patch must be a json object';
  end if;

  select e.org_id, e.venue_id, e.status,
         jsonb_build_object('title', e.title, 'description', e.description,
                            'hero_image_ref', e.hero_image_ref,
                            'category', e.category, 'genre_tags', e.genre_tags)
    into v_org_id, v_venue_id, v_status, v_before
    from catalog.event e where e.event_id = p_event_id for update;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;

  -- The unwritable set is checked BEFORE authority so that a patch naming
  -- venue_id / org_id / status raises invalid_input for every caller (T-RPC-CAT-01).
  for v_key in select jsonb_object_keys(p_patch) loop
    if v_key not in ('title','description','hero_image_ref','category',
                     'genre_tags','reason_code') then
      raise exception 'invalid_input: unwritable_key %', v_key;
    end if;
  end loop;

  -- Editability is bounded by LIFECYCLE, not by role, and the boundary is draft.
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  v_title_chg := p_patch ? 'title';
  v_marketing := not v_title_chg;   -- marketing-only patch (D3)

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  elsif v_marketing
        and kernel.has_org_role(v_org_id, array['org_marketing']) then
    v_allowed := true;              -- marketing-only columns additionally admit
  end if;                           -- org_marketing; no other column does
  if not v_allowed then             -- PFA-10 deferred arm (venue_manager, and
    v_allowed := kernel.has_venue_role(                -- venue_marketing on the
      v_venue_id,                                      -- marketing-only patch)
      case when v_marketing then array['venue_manager','venue_marketing']
           else array['venue_manager'] end)
      -- E-76 (165): a venue-role arm also requires the venue's CURRENT operator
      -- to be the event's org (088 cancel_event's conjunct, inlined; B's 187 shape).
      and exists (select 1 from catalog.venue v
                   where v.venue_id = v_venue_id and v.org_id = v_org_id);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager/org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- A title change after `announced` is what a buyer saw on the receipt for a
  -- ticket they already hold: it requires a reason code and is audited.
  v_reason := p_patch ->> 'reason_code';
  if v_title_chg and v_status <> 'draft'
     and (v_reason is null or length(trim(v_reason)) = 0) then
    raise exception 'precondition_failed: reason_required for a title change after draft';
  end if;

  if v_title_chg then
    update catalog.event set title = p_patch ->> 'title', updated_at = now()
     where event_id = p_event_id; v_changed := true;
  end if;
  if p_patch ? 'description' then
    update catalog.event set description = p_patch ->> 'description', updated_at = now()
     where event_id = p_event_id; v_changed := true;
  end if;
  if p_patch ? 'hero_image_ref' then
    update catalog.event set hero_image_ref = p_patch ->> 'hero_image_ref', updated_at = now()
     where event_id = p_event_id; v_changed := true;
  end if;
  if p_patch ? 'category' then
    update catalog.event set category = p_patch ->> 'category', updated_at = now()
     where event_id = p_event_id; v_changed := true;
  end if;
  if p_patch ? 'genre_tags' then
    update catalog.event
       set genre_tags = coalesce(
             (select array_agg(t) from jsonb_array_elements_text(p_patch -> 'genre_tags') t),
             '{}'),
           updated_at = now()
     where event_id = p_event_id; v_changed := true;
  end if;

  if not v_changed then
    return jsonb_build_object('status','noop_replay','event_id',p_event_id);
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.update', 'event', p_event_id,
          coalesce(nullif(trim(coalesce(v_reason,'')),''), 'marketing_edit'),
          v_before,
          (select jsonb_build_object('title', e.title, 'description', e.description,
                                     'hero_image_ref', e.hero_image_ref,
                                     'category', e.category, 'genre_tags', e.genre_tags)
             from catalog.event e where e.event_id = p_event_id));

  return jsonb_build_object('status','ok','event_id',p_event_id);
end;
$$;

-- catalog.create_event_session(uuid, jsonb, text) — 078's body + the E-76 conjunct on the venue-role arm
create or replace function catalog.create_event_session(
  p_event_id uuid, p_session jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_org_id     uuid;
  v_venue_id   uuid;
  v_status     text;
  v_allowed    boolean := false;
  v_session_id uuid;
  v_starts     timestamptz;
  v_ends       timestamptz;
  v_doors      timestamptz;
  v_label      text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_session is null or jsonb_typeof(p_session) <> 'object' then
    raise exception 'invalid_input: session must be a json object';
  end if;

  select e.org_id, e.venue_id, e.status
    into v_org_id, v_venue_id, v_status
    from catalog.event e where e.event_id = p_event_id for update;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  end if;
  if not v_allowed then                                    -- PFA-10 deferred arm
    v_allowed := kernel.has_venue_role(v_venue_id, array['venue_manager'])
      -- E-76 (165): a venue-role arm also requires the venue's CURRENT operator
      -- to be the event's org (088 cancel_event's conjunct, inlined; B's 187 shape).
      and exists (select 1 from catalog.venue v
                   where v.venue_id = v_venue_id and v.org_id = v_org_id);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  v_label  :=  p_session ->> 'session_label';
  v_starts := (p_session ->> 'starts_at')::timestamptz;
  v_ends   := (p_session ->> 'ends_at')::timestamptz;
  v_doors  := (p_session ->> 'doors_at')::timestamptz;
  if v_starts is null then
    raise exception 'invalid_input: starts_at required';
  end if;
  if v_ends is not null and v_ends <= v_starts then
    raise exception 'precondition_failed: ends_at must be after starts_at';
  end if;

  -- home_region and status are SERVER-DERIVED; session_version defaults to 1 and
  -- is never a parameter (its sole writer is catalog.update_event_session, 079).
  insert into catalog.event_session
         (event_id, session_label, starts_at, ends_at, doors_at, status, home_region)
  values (p_event_id, v_label, v_starts, v_ends, v_doors, 'scheduled', 'us-east')
  returning session_id into v_session_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'session.create', 'event_session', v_session_id, 'self_service',
          null, jsonb_build_object('event_id', p_event_id, 'starts_at', v_starts));

  return jsonb_build_object('status','ok','session_id',v_session_id);
end;
$$;

-- catalog.update_event_session(uuid, jsonb, text) — 093's body + the E-76 conjunct on the venue-role arm
create or replace function catalog.update_event_session(
  p_session_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_org_id     uuid;
  v_venue_id   uuid;
  v_event_id   uuid;
  v_status     text;
  v_starts     timestamptz;
  v_ends       timestamptz;
  v_doors      timestamptz;
  v_door_open  timestamptz;
  v_before     jsonb;
  v_key        text;
  v_reason     text;
  v_allowed    boolean := false;
  v_marketing  boolean := false;
  v_has_atoms  boolean := false;
  v_grace      interval;
  v_new_starts timestamptz;
  v_new_doors  timestamptz;
  v_new_ends   timestamptz;
  v_econ       boolean;                 -- 093: economic-weight probe (backward arm)
  v_time_chg   boolean := false;
  v_changed    boolean := false;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'invalid_input: patch must be a json object';
  end if;

  select s.event_id, s.status, s.starts_at, s.ends_at, s.doors_at, s.door_open_at,
         jsonb_build_object('session_label', s.session_label, 'starts_at', s.starts_at,
                            'ends_at', s.ends_at, 'doors_at', s.doors_at)
    into v_event_id, v_status, v_starts, v_ends, v_doors, v_door_open, v_before
    from catalog.event_session s
   where s.session_id = p_session_id
   for update;                                          -- rank 1
  if v_event_id is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;

  select e.org_id, e.venue_id into v_org_id, v_venue_id
    from catalog.event e where e.event_id = v_event_id;

  -- The unwritable set FIRST, for every caller (T-RPC-CAT-02): door_open_at has
  -- a sole writer (catalog.engage_door_freeze, 086, ruling O-5); session_version
  -- is bumped by THIS BODY, never named by a client; event_id re-parents atoms.
  for v_key in select jsonb_object_keys(p_patch) loop
    if v_key not in ('session_label','starts_at','ends_at','doors_at','reason_code') then
      raise exception 'invalid_input: unwritable_key %', v_key;
    end if;
  end loop;

  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;

  -- Marketing-only patch (RLS §11.1's D3 extension for this verb): the label is
  -- display; the time columns are freeze INPUTS and never marketing.
  v_marketing := not (p_patch ? 'starts_at' or p_patch ? 'ends_at' or p_patch ? 'doors_at');

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  elsif v_marketing
        and kernel.has_org_role(v_org_id, array['org_marketing']) then
    v_allowed := true;
  end if;
  if not v_allowed then             -- PFA-10 deferred arm (has_venue_role, 080)
    v_allowed := kernel.has_venue_role(
      v_venue_id,
      case when v_marketing then array['venue_manager','venue_marketing']
           else array['venue_manager'] end)
      -- E-76 (165): a venue-role arm also requires the venue's CURRENT operator
      -- to be the event's org (088 cancel_event's conjunct, inlined; B's 187 shape).
      and exists (select 1 from catalog.venue v
                   where v.venue_id = v_venue_id and v.org_id = v_org_id);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  v_new_starts := coalesce((p_patch ->> 'starts_at')::timestamptz, v_starts);
  v_new_doors  := case when p_patch ? 'doors_at'
                       then (p_patch ->> 'doors_at')::timestamptz else v_doors end;
  v_new_ends   := case when p_patch ? 'ends_at'
                       then (p_patch ->> 'ends_at')::timestamptz else v_ends end;
  if v_new_starts is null then
    raise exception 'invalid_input: starts_at cannot be null';
  end if;
  if v_new_ends is not null and v_new_ends <= v_new_starts then
    raise exception 'precondition_failed: ends_at must be after starts_at';
  end if;
  v_time_chg := (v_new_starts is distinct from v_starts)
             or (v_new_doors  is distinct from v_doors)
             or (v_new_ends   is distinct from v_ends);

  -- THE TIME GUARD — a custody property (§20.2.4). starts_at/doors_at are the
  -- inputs to catalog.effective_freeze_at, which decides when transfers stop.
  if (v_new_starts is distinct from v_starts) or (v_new_doors is distinct from v_doors) then
    -- once the boundary is taken, the schedule that produced it is evidence.
    if v_door_open is not null then
      raise exception 'precondition_failed: boundary_engaged';
    end if;
    select exists (select 1 from kernel.tickets t
                    where t.event_session_id = p_session_id)
      into v_has_atoms;
    if v_has_atoms then
      -- config('door.schedule_move_grace_interval') is a PFA-9 CLASS A key:
      -- NOT seeded, and 079 is directed to implement it FAIL-TO-SAFE — absent
      -- means NO later move is permitted (the X-12 shape, ruled in PFA-9).
      begin
        v_grace := (select (c.value #>> '{}')::interval
                      from catalog.platform_config c
                     where c.key = 'door.schedule_move_grace_interval'
                     order by c.version desc
                     limit 1);
      exception when others then
        v_grace := null;
      end;
      if (v_new_starts > v_starts
          and (v_grace is null or v_new_starts - v_starts >= v_grace))
         or (v_doors is not null and v_new_doors is not null and v_new_doors > v_doors
             and (v_grace is null or v_new_doors - v_doors >= v_grace))
         or (v_doors is null and v_new_doors is not null and v_new_doors > v_new_starts
             and (v_grace is null or v_new_doors - v_new_starts >= v_grace)) then
        raise exception 'precondition_failed: move_exceeds_grace';
      end if;
      -- any move with atoms issued is audited with a MANDATORY reason code.
      v_reason := p_patch ->> 'reason_code';
      if v_reason is null or length(trim(v_reason)) = 0 then
        raise exception 'precondition_failed: reason_required';
      end if;
    end if;
  end if;

  -- ==== 093 P0 — THE BACKWARD ends_at ARM. THIS IS THE ONLY LOGIC ADDED. ====
  -- The guard above tests FORWARD movement only: every arm at 079:646-651 is
  -- `v_new_* > v_*`, and it never inspects ends_at at all. So a seller org with
  -- org_owner/org_admin could move starts_at AND ends_at back 400 days with a
  -- reason_code and have it accepted. That single primitive:
  --   * defeats the whole eight-predicate G2 maturity gate, because every other
  --     predicate is anchored on the session's own ends_at — the settlement that
  --     closed held/maturity_not_elapsed re-closes with hold_state='none' and
  --     request_org_payout returns pending_approval to an ORG-class approver,
  --     with no platform human anywhere in the path; and
  --   * destroys live credentials — with ticket.expiry_grace set, backdating a
  --     session 30 days out makes sweep_expired_ticket_atoms terminal-ize every
  --     active atom on it within one cron tick.
  -- The bound the maturity report claimed ("the most a seller can shave is the
  -- session's own duration — hours, not months") does not hold: it is unbounded.
  --
  -- SCOPE — NARROWED TO ends_at, AND THE REASON MATTERS.
  -- The corpus's standing claim is that "an earlier move only tightens the
  -- freeze" (asserted by pgTAP 143 G10 and 144 E2). Per column, that claim is
  -- HALF right, and the half that is right is kept:
  --   * starts_at / doors_at earlier — GENUINELY SAFE, still permitted. They
  --     feed only catalog.effective_freeze_at (078:405-446); moving them earlier
  --     makes transfers freeze SOONER, which is strictly more conservative, and
  --     it touches no money anchor. 143 G10 moves starts_at alone and still
  --     passes.
  --   * ends_at earlier — NOT SAFE, and this is what the claim missed. ends_at
  --     is not a freeze input at all; it is the anchor of the two consumers that
  --     did not exist when that reasoning was written: the G2 payout-maturity
  --     gate and kernel.sweep_expired_ticket_atoms (079:494). Moving it earlier
  --     does not tighten anything — it MATURES money and EXPIRES live atoms.
  -- So this arm tests ends_at only. That is the whole exploitable surface: the
  -- red team's paired 400-day move is refused because its ends_at half is.
  --
  -- THE NULL CASE IS COVERED TOO. A session with ends_at NULL has no maturity
  -- anchor, so a two-step attack — move starts_at back (now permitted), then SET
  -- ends_at to a past value that still satisfies the 079:616-617 ends>starts
  -- check — would reach the same place. Newly setting an ends_at that has
  -- ALREADY ELAPSED is therefore refused as well. Setting a FUTURE ends_at on a
  -- session that lacked one stays permitted: it is benign, and it is the only
  -- way to close R1's separate null-ends_at fail-open.
  --
  -- WHY NOT FORBID EVERY BACKWARD MOVE: a pre-sale draft legitimately reschedules
  -- in both directions. The line is ECONOMIC WEIGHT, read from the schema:
  --   * an atom was minted for the session          (kernel.tickets)
  --   * money was actually taken                    (venue."order", paid /
  --     partially_refunded / refunded — 'pending' and 'cancelled' are not money)
  --   * the door ran                                (venue.scan)
  --   * settlement accounting began for the event   (venue.settlement.event_id)
  -- Any one of those and the schedule is evidence, not a plan.
  --
  -- THE PLATFORM CONJUNCT, AND ITS REAL REACHABILITY — MEASURED, NOT ASSUMED.
  -- The `not kernel.is_platform(...)` test below is NOT a usable escape hatch on
  -- its own, and must not be described as one. This verb's authority arms
  -- (079:591-606) admit only org_owner / org_admin / org_marketing and
  -- venue_manager / venue_marketing; kernel.is_platform is not among them. A
  -- platform_admin holding no org or venue role is therefore refused EARLIER, at
  -- 079:603-606, and never reaches this block. Verified by execution:
  --   pure platform_admin           -> insufficient_privilege (the 079 arm)
  --   platform_admin + org_owner    -> ok
  -- So in practice, for an economically-weighted session, a backward move is
  -- REFUSED OUTRIGHT for every principal who can reach this verb — the
  -- fail-closed end of "refused, or restricted to platform authority".
  -- The conjunct is kept because it is correct, costs nothing, and becomes a
  -- real hatch the moment platform authority is added to this verb's arms.
  -- WIDENING THOSE ARMS IS DELIBERATELY NOT DONE HERE: it would change who may
  -- call a frozen 079 verb, which is a bigger decision than this fix, and a
  -- genuine data-entry correction still has the service_role / superuser path
  -- that every other break-glass repair uses. Flagged, not taken.
  --
  -- FAIL CLOSED: if the probe itself raises, v_econ is forced true and the move
  -- is refused. A move we cannot prove is safe is not safe.
  if v_new_ends is not null
     and ( (v_ends is not null and v_new_ends < v_ends)      -- moved EARLIER
        or (v_ends is null     and v_new_ends <= now()) )    -- newly set, ALREADY elapsed
  then
    if not kernel.is_platform(array['platform_admin']) then
      begin
        select exists (select 1 from kernel.tickets t
                        where t.event_session_id = p_session_id)
            or exists (select 1 from venue."order" o
                        where o.event_session_id = p_session_id
                          and o.status in ('paid','partially_refunded','refunded'))
            or exists (select 1 from venue.scan sc
                        where sc.event_session_id = p_session_id)
            or exists (select 1 from venue.settlement st
                        where st.event_id = v_event_id)
          into v_econ;
      exception when others then
        v_econ := true;                                  -- fail closed
      end;
      if v_econ is null or v_econ then
        raise exception 'precondition_failed: backward_schedule_move_frozen — this session carries economic weight (an issued atom, a paid order, a door scan or a settlement), so its schedule may not be moved earlier; contact the platform owner'
          using errcode = 'P0001';
      end if;
    end if;
    -- a backward move is audited with a MANDATORY reason code, exactly as the
    -- forward arm demands one once atoms exist (079:654-658).
    v_reason := p_patch ->> 'reason_code';
    if v_reason is null or length(trim(v_reason)) = 0 then
      raise exception 'precondition_failed: reason_required';
    end if;
  end if;
  -- ==== end 093 backward arm ===============================================

  if p_patch ? 'session_label' then
    update catalog.event_session
       set session_label = p_patch ->> 'session_label', updated_at = now()
     where session_id = p_session_id;
    v_changed := true;
  end if;
  if v_time_chg then
    update catalog.event_session
       set starts_at = v_new_starts, doors_at = v_new_doors, ends_at = v_new_ends,
           -- Δ-N1 (NOTIF Group E): bumped IN THIS TRANSACTION, under the row's
           -- FOR UPDATE, whenever starts/doors/ends change — never a patch key.
           session_version = session_version + 1,
           updated_at = now()
     where session_id = p_session_id;
    v_changed := true;
  end if;

  if not v_changed then
    return jsonb_build_object('status','noop_replay','session_id',p_session_id,
                              'effective_freeze_at', catalog.effective_freeze_at(p_session_id));
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'session.update', 'event_session', p_session_id,
          coalesce(nullif(trim(coalesce(p_patch ->> 'reason_code','')),''), 'self_service'),
          v_before,
          (select jsonb_build_object('session_label', s.session_label, 'starts_at', s.starts_at,
                                     'ends_at', s.ends_at, 'doors_at', s.doors_at,
                                     'session_version', s.session_version)
             from catalog.event_session s where s.session_id = p_session_id));

  -- the recomputed boundary is returned, so the operator sees the consequence
  -- of the edit in the same round trip rather than discovering it at the door.
  return jsonb_build_object('status','ok','session_id',p_session_id,
                            'effective_freeze_at', catalog.effective_freeze_at(p_session_id));
end;
$$;

-- catalog.publish_event(uuid, text, text) — 102's body + the E-76 conjunct on the venue-role arm
create or replace function catalog.publish_event(
  p_event_id uuid, p_target_status text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid          uuid;
  v_org_id       uuid;
  v_venue        uuid;
  v_status       text;
  v_ok           boolean;
  -- 102 / A8a' SALEABLE gate scratch — declared here, used only inside the
  -- on_sale branch below.
  v_org_status   text;
  v_org_ref      text;
  v_org_ready    boolean;
  v_signing_key  uuid;
  v_fee_bps      numeric;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_target_status not in ('announced','on_sale','live','completed') then
    raise exception 'invalid_input: bad target_status % (cancellation is catalog.cancel_event)', p_target_status;
  end if;

  select e.org_id, e.venue_id, e.status into v_org_id, v_venue, v_status
    from catalog.event e where e.event_id = p_event_id for update;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;

  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              -- E-76 (165): a venue-role arm also requires the venue's CURRENT operator
              -- to be the event's org (088 cancel_event's conjunct, inlined; B's 187 shape).
              and exists (select 1 from catalog.venue v
                           where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- legal FORWARD transition only (draft→announced→on_sale→live→completed).
  v_ok := (v_status = 'draft'     and p_target_status = 'announced')
       or (v_status = 'announced' and p_target_status = 'on_sale')
       or (v_status = 'on_sale'   and p_target_status = 'live')
       or (v_status = 'live'      and p_target_status = 'completed');
  if not v_ok then
    raise exception 'precondition_failed: illegal_transition (% -> %)', v_status, p_target_status;
  end if;

  -- on_sale requires >=1 ticket_type WITH a batch — no empty on-sale.
  if p_target_status = 'on_sale' then
    if not exists (
      select 1 from venue.ticket_type tt
       join venue.inventory_batch b on b.ticket_type_id = tt.ticket_type_id
      where tt.event_id = p_event_id) then
      raise exception 'precondition_failed: empty_inventory';
    end if;

    -- ---- 102 / A8a' — SALEABLE STATIC GATE LADDER, IN ORDER ---------------

    -- 1. ORG NOT SUSPENDED/UNAPPROVED. Mirrors create_primary_checkout's G2a
    -- (093:3982-4021) character-for-character: a suspended or not-yet-
    -- approved org must not be able to open sales, for the identical reason
    -- checkout refuses it at quote time. X-12 restrictive: unknown authorizes
    -- NOTHING (null status, from a vanished org row, refuses too).
    select o.status, o.stripe_connect_account_ref, o.connect_transfers_active
      into v_org_status, v_org_ref, v_org_ready
      from kernel.organization o
     where o.org_id = v_org_id;
    if v_org_status is null or v_org_status not in ('approved','active') then
      raise exception 'precondition_failed: org_not_saleable — a % organization may not go on sale', coalesce(v_org_status,'missing');
    end if;

    -- 2. CONNECT NOT READY. Mirrors G2 (093:4023-4026): a bound ref with dead
    -- transfer capability is not ready, and a live-looking flag with no ref
    -- has nowhere to send money. Both operands required.
    if v_org_ref is null or coalesce(v_org_ready, false) is not true then
      raise exception 'precondition_failed: connect_not_ready';
    end if;

    -- 3. SIGNING NOT READY. The same resolver query shape as
    -- kernel.issue_ticket_atoms (093:4952-4966) and create_primary_checkout's
    -- G2b (093:4066-4074): most-specific-first, per_event -> per_venue ->
    -- global, active and in-window. A signer trust root must exist for this
    -- event BEFORE sales open — this does not provision one (the KMS
    -- ceremony is a separate, un-parked act this migration does not touch).
    select k.key_id into v_signing_key
      from kernel.signing_key k
     where k.status = 'active'
       and (k.not_after is null or k.not_after > now()) and k.not_before <= now()
       and (   (k.scope = 'per_event' and k.event_id = p_event_id)
            or (k.scope = 'per_venue' and k.venue_id = v_venue)
            or (k.scope = 'global'))
     order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end
     limit 1;
    if v_signing_key is null then
      raise exception 'precondition_failed: signing_not_ready — an active signing key must resolve for the event scope before it can go on sale';
    end if;

    -- 4. FEE POLICY UNSET. Mirrors A5 (093:4093-4105): fee.buyer_service_bps
    -- must never fall back to zero — a missing key reads the same as a null
    -- value and both refuse.
    select (c.value #>> '{}')::numeric into v_fee_bps
      from catalog.platform_config c
     where c.key = 'fee.buyer_service_bps'
     order by c.version desc limit 1;
    if v_fee_bps is null then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps has no value; this event cannot go on sale until the owner sets it';
    end if;

    -- ---- end 102 / A8a' SALEABLE gate ladder ------------------------------
  end if;

  update catalog.event set status = p_target_status, updated_at = now()
   where event_id = p_event_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.status', 'event', p_event_id, 'publish',
          jsonb_build_object('status', v_status), jsonb_build_object('status', p_target_status));

  return jsonb_build_object('status','ok','event_status',p_target_status);
end;
$$;

DO $post$
DECLARE
  r record;
  v_bad text;
BEGIN
  FOR r IN
    SELECT e.sig, md5(p.prosrc) AS h, e.h_165
      FROM (VALUES
              ('update_event', 'catalog.update_event(uuid, jsonb, text)', 'ea572709f85bbab2d8b10dcd38073155', '1bf2a04bf1ffccfdbed04d8b067dd2df'),
              ('create_event_session', 'catalog.create_event_session(uuid, jsonb, text)', '66eb523f94dca9679e64b2a6fef3a13b', 'ee243b12a8b51c7692a8f6ed22506a34'),
              ('update_event_session', 'catalog.update_event_session(uuid, jsonb, text)', 'cc30a196b4e61acbd13f750b68ffcf3d', '9e834d57e7810f81d1f9ed11c79dcd24'),
              ('publish_event', 'catalog.publish_event(uuid, text, text)', 'b756ad2076bf856f8ce9d7bafa4655f4', 'b31abddf9aad2cb7b119d517424bb494')
           ) AS e(fname, sig, h_pred, h_165)
      LEFT JOIN pg_proc p ON p.oid = to_regprocedure(e.sig)
  LOOP
    IF r.h IS DISTINCT FROM r.h_165 THEN
      RAISE EXCEPTION 'MIGRATION_165_POSTFLIGHT_FAILED: % md5 % expected %', r.sig, coalesce(r.h, '<absent>'), r.h_165;
    END IF;
  END LOOP;
  SELECT string_agg(s.fn, ', ' ORDER BY s.fn) INTO v_bad
    FROM e76_165_snap s
    LEFT JOIN (SELECT p.proname::text AS fn, p.proowner, p.proacl::text AS acl, p.prosecdef,
                      p.proconfig::text AS cfg, obj_description(p.oid, 'pg_proc') AS cmt
                 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'catalog') a ON a.fn = s.fn
   WHERE a.fn IS NULL OR (s.proowner, s.acl, s.prosecdef, s.cfg, s.cmt) IS DISTINCT FROM (a.proowner, a.acl, a.prosecdef, a.cfg, a.cmt);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'MIGRATION_165_POSTFLIGHT_FAILED: owner/ACL/definer/config/comment changed on %', v_bad;
  END IF;
END $post$;

COMMIT;
