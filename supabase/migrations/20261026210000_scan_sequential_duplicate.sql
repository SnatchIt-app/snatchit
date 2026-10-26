-- ============================================================================
-- 20261026210000_scan_sequential_duplicate.sql — registry 183 / pgTAP 253 (B writes, A reviews).
--
-- WHAT THIS MIGRATION IS. DRAFT / unapplied / undeployed. Body-only re-create
-- of venue._record_scan_core (108 PART 1) plus ONE nullable ledger column.
-- No new function, no signature change, no grant change, no public-schema
-- object, Gate-2 function/policy/trigger census unchanged (+0). Replay-safe
-- (create or replace; add column if not exists). Both admission entrypoints
-- (venue.record_scan — staff path, auth.uid() + venue role; venue.record_scan_door
-- — door machine path, kernel.assert_door_session) reach this body, so both get
-- the change. Next migration after 20261013000000 on the gate tree.
--
-- ── THE DEFECT (S05, 2026-10-25 audit; CONTRACTS.md C7 "contract gap") ──────
-- The frozen contract says a SECOND scan of an atom records result='duplicate'
-- (RPC §7.5 L1408, DOOR spec L1797, RLS T-RLS-DOOR-03, 079:441 "record_scan
-- maps a repeat to 'duplicate'"). The 086/104/108 body never does: kernel.
-- mark_ticket_scanned takes the atom row FOR UPDATE and raises not_active
-- (state=scanned) BEFORE the C41 partial unique index can fire, so every
-- sequential rescan is recorded 'invalid' — indistinguishable at the door from
-- a forged or wrong-event ticket. 171 R1 / 174 D9 codified the observed
-- behaviour ("conflict, not duplicate"); this migration restores the contract.
--
-- ── WHAT CHANGES (each spot marked `183 BLOCK x`) ────────────────────────────
--   B  sequential "already used": when mark_ticket_scanned refused
--      not_active (state=scanned) AND an authoritative admitted inbound scan row
--      exists for (atom, session) → result='duplicate' and the response carries
--      prior:{scan_id, occurred_at, device_id, actor_identity_id, device_label}.
--      state=scanned WITHOUT an admitted row stays 'invalid' (fail closed).
--      The C41 race arm (unique_violation) also returns `prior` now, so a
--      duplicate always renders the same way at the door.
--   A  credential currency (staff path, CONTRACTS C7 amendment): when the caller
--      supplies the VERIFIED token claims in scan_meta (`credential_version`,
--      `key_id` — set by F's scanner after the reference verification, or by a
--      future edge), they must equal kernel.tickets.credential_version /
--      signing_key_id under the row lock; a mismatch is 'invalid' with
--      reason='credential_stale' and NO transition. Absent claims → unchanged
--      behaviour (the door machine path sends none today).
--   C  unknown atom: a well-formed uuid that is not a ticket used to raise a
--      foreign_key_violation out of the function (the ledger INSERT) — the
--      door-session edge turned that into HTTP 500 + Sentry. Now
--      {result:'invalid', reason:'unknown_atom', scan_id:null}, no ledger row
--      (the FK forbids one), nothing consumed.
--   D  `reason` on every 'invalid' response (response only, never stored):
--      voided | expired | not_active | wrong_session | listed_locked |
--      credential_stale | credential_claims_malformed | unknown_atom | other —
--      so the door distinguishes refunded/cancelled from wrong-event from stale
--      without a second read (S05/S08). The ledger `result` set is unchanged.
--   E  venue.scan.device_label text NULL (≤ 64 chars), captured from
--      scan_meta->>'device_label' on every row (A's attribution label for the
--      staff path, which has no scan_device). Table-level SELECT grant to
--      authenticated already covers it (venue_scan_sel_venue: venue staff only).
-- Everything else is the 108 body verbatim: flag gate first, terminal-session
-- gate, mark_ticket_scanned as the single-writer transition, first-in-wins.
-- NOT CHANGED (E-F1, recorded): p_command_key is accepted and still UNUSED —
-- it is not an idempotency anchor and this migration adds no key-based replay.
-- A same-key retry after a lost response is safe because the duplicate branch
-- (BLOCK B) answers it with the committed admission's facts (253 S8/S9); a
-- key-based replay store, if ever wanted, is a separate numbered item.
--
-- ── SOURCES READ, NOT ASSUMED ────────────────────────────────────────────────
-- 108:53-99 (the body re-created here), 079:408-447 (mark_ticket_scanned:
-- FOR UPDATE, the exact raise texts matched below), 086:119-153 (venue.scan
-- DDL, scan_admitted_in_uq, AO trigger, grants), 104 (terminal-session gate),
-- 083:46-48 (kernel.tickets.credential_version / signing_key_id), 174 D9 and
-- 171 R1 (the expectations this migration flips — updated in the same PR).
-- ============================================================================
begin;

-- ── 183 BLOCK E — the attribution label (nullable, bounded; AO trigger untouched)
alter table venue.scan add column if not exists device_label text;
alter table venue.scan drop constraint if exists scan_device_label_len_ck;
alter table venue.scan add constraint scan_device_label_len_ck
  check (device_label is null or length(device_label) <= 64);
comment on column venue.scan.device_label is
  '183: free-text attribution label supplied by the scanning client (scan_meta.device_label, ≤ 64 chars). Rendered as part of a duplicate response''s `prior`. Never identity, never PII by contract.';

-- ── PRE-FLIGHT (stacking guard, A review 2026-10-26): the body being replaced must be
-- EXACTLY the 108 body (first apply) or EXACTLY this migration's body (idempotent
-- re-apply). Any other body means a later _record_scan_core change landed first and
-- would be silently overwritten — refuse, so the registry order is re-examined.
do $pf$
declare v_md5 text := md5(pg_get_functiondef('venue._record_scan_core(uuid,uuid,uuid,uuid,jsonb,text)'::regprocedure));
begin
  if v_md5 not in ('9ae362e02023cd0d45df43daef326b11',   -- 108 body (= production, 2026-10-26)
                   '1b7e88e52a7a788081c7623fba62baf6') then                   -- this migration's body (re-apply)
    raise exception 'precondition_failed: 183 refuses to overwrite an unexpected venue._record_scan_core body (md5 %) — re-examine the migration order', v_md5;
  end if;
end $pf$;

create or replace function venue._record_scan_core(
  p_atom_id uuid, p_session_id uuid, p_actor_device_id uuid, p_actor_identity_id uuid,
  p_scan_meta jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean; v_session_status text; v_res jsonb; v_result text; v_scan_id uuid;
        -- ── 183 BLOCK VARS — prior-admission facts, the caller's label, the credential claims, the refusal reason
        v_prior_scan_id uuid; v_prior_occurred_at timestamptz; v_prior_device_id uuid;
        v_prior_actor uuid; v_prior_label text;
        v_label text := nullif(left(coalesce(p_scan_meta->>'device_label',''), 64), '');
        v_claim_ver integer; v_claim_key uuid; v_cur_ver integer; v_cur_key uuid;
        v_reason text;
        -- ── 183 BLOCK VARS END
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'feature.native_scanning_enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled — native scanning is dark';
  end if;
  -- terminal-session gate (104): a cancelled/completed (or unknown) session must
  -- not admit. X-12 restrictive — a null status (vanished session) fails closed.
  select es.status into v_session_status
    from catalog.event_session es where es.session_id = p_session_id;
  if v_session_status is null or v_session_status in ('cancelled','completed') then
    raise exception 'precondition_failed: session_not_admitting (status=%)', coalesce(v_session_status,'missing');
  end if;
  -- lifecycle transition (single-writer choke point).
  begin
    -- ── 183 BLOCK A — credential currency, only when the caller supplies the claims
    if p_scan_meta ? 'credential_version' or p_scan_meta ? 'key_id' then
      begin
        v_claim_ver := nullif(p_scan_meta->>'credential_version','')::integer;
        v_claim_key := nullif(p_scan_meta->>'key_id','')::uuid;
      exception when others then
        raise exception 'precondition_failed: credential_claims_malformed';
      end;
      select t.credential_version, t.signing_key_id into v_cur_ver, v_cur_key
        from kernel.tickets t where t.ticket_atom_id = p_atom_id for update;
      if v_cur_ver is not null and ((v_claim_ver is not null and v_claim_ver <> v_cur_ver)
                                    or (v_claim_key is not null and v_claim_key is distinct from v_cur_key)) then
        raise exception 'precondition_failed: credential_stale';
      end if;
    end if;
    -- ── 183 BLOCK A END
    v_res := kernel.mark_ticket_scanned(p_atom_id, p_session_id, coalesce(p_scan_meta, '{}'::jsonb));
    v_result := 'admitted';
  exception when others then
    v_result := case when sqlerrm like '%not_active%' or sqlerrm like '%wrong_session%' then 'invalid'
                     when sqlerrm like '%listed_locked%' then 'invalid'
                     else 'invalid' end;
    -- ── 183 BLOCK D — the refusal reason (response only)
    v_reason := case when sqlerrm like '%not_active (state=voided)%'  then 'voided'
                     when sqlerrm like '%not_active (state=expired)%' then 'expired'
                     when sqlerrm like '%not_active%'                 then 'not_active'
                     when sqlerrm like '%wrong_session%'              then 'wrong_session'
                     when sqlerrm like '%listed_locked%'              then 'listed_locked'
                     when sqlerrm like '%credential_stale%'           then 'credential_stale'
                     when sqlerrm like '%credential_claims_malformed%' then 'credential_claims_malformed'
                     when sqlerrm like 'not_found%'                   then 'unknown_atom'
                     else 'other' end;
    -- ── 183 BLOCK B — sequential "already used": the atom is consumed AND the
    -- authoritative admitted inbound row exists → duplicate + prior facts.
    if sqlerrm like '%not_active (state=scanned)%' then
      select s.scan_id, s.occurred_at, s.device_id, s.actor_identity_id, s.device_label
        into v_prior_scan_id, v_prior_occurred_at, v_prior_device_id, v_prior_actor, v_prior_label
        from venue.scan s
       where s.ticket_atom_id = p_atom_id and s.event_session_id = p_session_id
         and s.result = 'admitted' and s.direction = 'in'
       limit 1;   -- scan_admitted_in_uq: at most one such row
      if v_prior_scan_id is not null then
        v_result := 'duplicate'; v_reason := null;
      end if;
    end if;
    -- ── 183 BLOCK B END
  end;
  -- ── 183 BLOCK C — an unknown atom cannot be written to the FK-bound ledger;
  -- answer invalid instead of raising foreign_key_violation out of the function.
  if v_result = 'invalid' and not exists (select 1 from kernel.tickets t where t.ticket_atom_id = p_atom_id) then
    return jsonb_build_object('status','ok','scan_id', null, 'result','invalid', 'reason','unknown_atom');
  end if;
  -- ── 183 BLOCK C END
  -- ── 183 BLOCK E — the 108 ledger INSERT with ONE added column (`device_label` ← `v_label`); the
  -- only 183 lines that cannot sit beside a literal 108 statement (the ledger is append-only, so the
  -- label must travel in the same INSERT). The two tagged lines are the whole difference.
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at, device_label)  -- 183 E: +device_label
  values (p_atom_id, p_session_id, p_actor_device_id, p_actor_identity_id, v_result,
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()), v_label)  -- 183 E: +v_label
  returning scan_id into v_scan_id;
  -- ── 183 BLOCK E END
  -- ── 183 BLOCK D/B — invalid → + `reason`; duplicate → + `prior`. 'admitted' falls through to the
  -- literal 108 RETURN below, so the response for an admission is byte-identical to production.
  if v_result = 'invalid' then
    return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', v_result, 'reason', coalesce(v_reason,'other'));
  elsif v_result = 'duplicate' and v_prior_scan_id is not null then
    return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', v_result, 'prior', jsonb_build_object(
             'scan_id', v_prior_scan_id, 'occurred_at', v_prior_occurred_at, 'device_id', v_prior_device_id,
             'actor_identity_id', v_prior_actor, 'device_label', v_prior_label));
  end if;
  -- ── 183 BLOCK D/B END
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', v_result);
exception when unique_violation then
  -- C41 first-in-wins: a second admitted inbound scan is a duplicate.
  -- ── 183 BLOCK E — the 108 race-arm INSERT with the same ONE added column
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at, device_label)  -- 183 E: +device_label
  values (p_atom_id, p_session_id, p_actor_device_id, p_actor_identity_id, 'duplicate',
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()), v_label)  -- 183 E: +v_label
  returning scan_id into v_scan_id;
  -- ── 183 BLOCK E END
  -- ── 183 BLOCK B — the race arm renders like the sequential arm: attach `prior` when the admitted
  -- row is visible; otherwise fall through to the literal 108 RETURN below.
  select s.scan_id, s.occurred_at, s.device_id, s.actor_identity_id, s.device_label
    into v_prior_scan_id, v_prior_occurred_at, v_prior_device_id, v_prior_actor, v_prior_label
    from venue.scan s
   where s.ticket_atom_id = p_atom_id and s.event_session_id = p_session_id
     and s.result = 'admitted' and s.direction = 'in'
   limit 1;
  if v_prior_scan_id is not null then
    return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', 'duplicate', 'prior', jsonb_build_object(
             'scan_id', v_prior_scan_id, 'occurred_at', v_prior_occurred_at, 'device_id', v_prior_device_id,
             'actor_identity_id', v_prior_actor, 'device_label', v_prior_label));
  end if;
  -- ── 183 BLOCK B END
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', 'duplicate');
end;
$$;
-- ── 183 BLOCK DOC — the 108 comment, extended
comment on function venue._record_scan_core(uuid,uuid,uuid,uuid,jsonb,text) is
  'INTERNAL (zero grant): the authorization-free admission body (104/108 + 183). Callers MUST pre-authorize (venue.record_scan role gate, or venue.record_scan_door via kernel.assert_door_session). Flag gate, terminal-session gate, optional credential-currency check (scan_meta.credential_version/key_id vs kernel.tickets), mark_ticket_scanned, first-in-wins. 183: a sequential rescan of a consumed atom is result=duplicate with prior:{scan_id, occurred_at, device_id, actor_identity_id, device_label}; invalid responses carry a reason; an unknown atom answers invalid/unknown_atom without a ledger row.';
-- ── 183 BLOCK DOC END

revoke all on function venue._record_scan_core(uuid,uuid,uuid,uuid,jsonb,text) from public, anon, authenticated, service_role;

commit;
