-- ============================================================================
-- venue_command_key_replay.sql — registry 204 (DB-6) / pgTAP 273.
-- D writes and owns; A allocated the number and accepted the design with every recommended default
-- (D/s18-204/DESIGN-204-FINAL.md, audit-row-as-receipt); E reviews. REPO-ONLY and DARK: applied nowhere by this
-- branch, no production change.
-- ORDER: after 162 (event_policy_shared_capacity_and_tier_windows), 187 (e76_door_operator_binding), e76
-- (e76_venue_org_conjunct_catalog_event_verbs) and 202 (primary_fee_read_alignment). It refuses e76's
-- publish_event body: apply 202 first.
--
-- WHAT THIS GUARANTEES — command-key replay for five venue/catalog verbs (RPC contracts section 0.2: a replay
-- returns the original outcome). For the same actor, verb and command key:
--   same request       -> {status 'noop_replay', the ok receipt's keys with the original values}; nothing is
--                         written and no later gate runs;
--   different request  -> P0001 'precondition_failed: idempotency_conflict — command key reused with different
--                         parameters' (093's literal, venue.open_settlement); nothing is written;
--   no receipt         -> the call runs exactly as before (first-call equivalence), except where listed below.
-- The receipt is the verb's OWN kernel.admin_audit row, written in the same transaction as the effect, so a refused
-- call records nothing and the same key can be retried after a refusal. Its `after` gains two keys:
--   command_key_sha256   sha256 hex of the command key — never the raw key (the audit is append-only);
--   request_sha256       sha256 hex of a canonical request jsonb; timestamptz arguments enter as
--                        extract(epoch ...), so the digest does not depend on the session TimeZone.
-- Scope = (actor_identity = auth.uid(), the audit action [+ reason_code 'publish'], the key digest): never across
-- actors or verbs. The lookup runs AFTER every existing gate up to and including authority (no receipt and no
-- conflict signal before authority; the existing pre-authority gates and their order are unchanged), under
-- pg_advisory_xact_lock(hashtextextended('db6:<action>:<uid>:<key digest>', 0)), taken after the verb's parent-row
-- lock. Under READ COMMITTED two concurrent same-scope calls therefore produce one effect, and the second answers
-- from the first's committed row (REPEATABLE READ / SERIALIZABLE callers are residual R1; PostgREST runs RC).
--   catalog.create_event(uuid,text,jsonb,text)      request {venue_id, title: trim(title), first_session};
--       replay {noop_replay, event_id, session_id}: the implicit session is found by its own derived-key receipt
--       (create_event_session still receives p_command_key || ':implicit-session').
--   catalog.create_event_session(uuid,jsonb,text)   request {event_id, session}; replay {noop_replay, session_id}.
--       A same-key labelled resend replays instead of raising 23505; a new key behaves as before.
--   catalog.publish_event(uuid,text,text)           202's body plus three hunks (declare, receipt, audit after);
--       request {event_id, target_status}; replay {noop_replay, event_status: the ORIGINAL target}, also after the
--       event moved on or was cancelled. reason_code stays 'publish'.
--   venue.set_ticket_type_sale_window(...)          request {ticket_type_id, both bounds as epoch, reason_code};
--       replay {noop_replay, ticket_type_id, sale_starts_at, sale_ends_at}, with no re-apply. The value-equal
--       `noop` arm is unchanged and writes no audit row, so it leaves no receipt (residual R6; the COMMENT stays
--       true).
--   venue.allocate_comp(...)                        refuses a blank key ('precondition_failed: command key
--       required') AFTER authority, the 187 block and bad_quantity (input tightened; every caller in the repo sends
--       a non-blank key); writes one 'comp.allocate' audit row (reason_code = p_reason_code, 'unspecified' when
--       blank); request {session_id, batch_id, quantity, reason_code}; replay {noop_replay, comp_allocation_id}.
-- Audit rows written before this file carry no key digest and never match: a command that straddles the deploy
-- runs once more (residual R3).
--
-- WHAT CHANGES — body-only CREATE OR REPLACE of the five functions, each executed from a guarded DO block. Same
-- signatures, owner, ACL, SECURITY DEFINER, search_path '', volatility and COMMENT (the post-flight proves each
-- equal to the pre-flight's own capture). No table, column, index, grant, schema or function is created or dropped
-- (the post-flight compares a census of catalog, venue, venue_cmd, kernel and public). No row is read or written.
-- Every other byte of each body equals the applied predecessor (per-line diff: D/s18-204/pred_vs_new.diff). The
-- rationale lives here, not in the bodies: each body carries one marker comment per receipt block.
--
-- MD5 — measured on a local PG17 clone of origin/main c093bada's chain + 202 (prosrc / pg_get_functiondef):
--   catalog.create_event(uuid,text,jsonb,text)
--       predecessor (078)  e48b7093e3a92f3b396450565d9f3261 / 02314a386f05a3dd459482caf07375b8
--       204                d0cc74b90d40fa57f092ef59a8791d49 / d4412bd702a938a18d4de28da68fbb70
--   catalog.create_event_session(uuid,jsonb,text)
--       predecessor (e76)  ee243b12a8b51c7692a8f6ed22506a34 / 560bd7d37e9f6de01e1d8db2c60b1fcf
--       204                33b0d32e2a3b4269ad2fc9ae173066e1 / 8ce6b96c396f577adbf6be707b1433b3
--   catalog.publish_event(uuid,text,text)
--       predecessor (202)  0f7d65e79fc24cc5feed1048575d3e27 / f30eaca23ae71a33243e39a6c8c5a8fd
--       204                fe9bc5f0f91611a064b1cdef5143efec / 3243d8a053e81181d6c54fe1f05d5288
--   venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text)
--       predecessor (162)  9fd9b5f50b0c66afe7a0842e1e8104b9 / dc5cf9c96e8cfb97074f6b5e8e502ea9
--       204                a417a4acb7523b8a1d35c8fc3a025432 / a9e9d11d0619b03d22bb1f920901d2a8
--   venue.allocate_comp(uuid,uuid,integer,text,text)
--       predecessor (187)  269206489452fd2e8ea62afd4d1913f9 / 73ad103d04ce30dbf7d7238ade284a26
--       204                d35f9a24869a91b70755dcd75613f410 / fd475aaf290c34405b0037f35547d358
-- The pre-flight accepts exactly {predecessor, 204} per function (both md5s) and refuses anything else, naming the
-- function and both md5s seen; e76's publish_event body (prosrc b31abddf9aad2cb7b119d517424bb494) gets its own
-- message. A 204 body means already applied, and that install block is a no-op (idempotent re-apply).
--
-- DOWNSTREAM. (1) Roll back 204 FIRST: 202's rollback asserts publish_event = f30eaca2, 187's asserts
-- allocate_comp = 73ad103d, e76's asserts create_event_session's 165 body, and 162's rollback drops the setter.
-- (2) The open registries 198-203 and 205 replace none of these five except 202 (publish_event, this file's base);
-- 203 replaces cancel_event and update_event_session, which this file does not touch (its pre-flight relies on none
-- of the five, so 203 and 204 apply in either order), but it pins two of these bodies in tests: (a) it edits pgTAP
-- 232 A8's shared pin string (textual conflict: whoever lands second rebases that string); (b) its new pgTAP 272 A7
-- pins md5(prosrc) of create_event_session (ee243b12, e76) and publish_event (b31abddf, e76). That is a SEMANTIC
-- conflict git merges without a marker (272 is not in this tree), so the second lander would go red in CI. With
-- 202 + 204 applied A7 reads create_event_session=33b0d32e2a3b4269ad2fc9ae173066e1 and
-- publish_event=fe9bc5f0f91611a064b1cdef5143efec (update_event unchanged). Whichever of 203 / 204 lands second moves
-- 272 A7 to those two values in its own commit, with a comment naming registry 204 (203 sorts first, so 204 is the
-- likely second lander; D/s18-204/conflict-with-203.txt has the combined-chain run). (3) B's 191 must not re-create
-- these five; the guest-list delta is handed to it (design section 5.6). (4) Pins moved in this commit (values
-- only, plan counts unchanged): pgTAP 232 A2, A4 and A8's create_event part, 271 A6, 229 W49, and 271 S3 (an exact
-- event.status `after` comparison the design did not list; it now compares the status without the two digests).
--
-- GRANTS / FOUR-FILE RULE: CREATE OR REPLACE keeps every grant; none is re-stated. Nothing lands in `public`: the
-- grant-decision manifest and expected_grants are untouched; Gate-2 +0 (dated note in ci.yml).
-- LOCKS / RUNTIME: CREATE OR REPLACE FUNCTION only; no table or row is read or written; lock_timeout 3s.
-- ROLLBACK: the file of the same name under supabase/rollbacks/ restores the five predecessors byte for byte
-- (publish_event to 202's body, never e76's) under an inverse md5 guard; no drop, no CASCADE. Receipt digests
-- already written stay in the append-only audit and are inert under the predecessor bodies.
-- TESTS: supabase/tests/273_venue_command_key_replay.sql.
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── PRE-FLIGHT: classify each live body, check the premises, capture posture and a census for the post-flight.
-- to_regprocedure / to_regclass, never a '...'::regprocedure literal (a literal resolves at plan time).
do $pf$
declare
  r      record;
  v_src  text;
  v_def  text;
  v_st   text;
  v_n    integer;
  v_cap  jsonb := '[]'::jsonb;
  v_cen  jsonb;
begin
  for r in
    select * from (values
      ('catalog.create_event(uuid,text,jsonb,text)', 'catalog', 'create_event',
       'e48b7093e3a92f3b396450565d9f3261', '02314a386f05a3dd459482caf07375b8', 'd0cc74b90d40fa57f092ef59a8791d49', 'd4412bd702a938a18d4de28da68fbb70'),
      ('catalog.create_event_session(uuid,jsonb,text)', 'catalog', 'create_event_session',
       'ee243b12a8b51c7692a8f6ed22506a34', '560bd7d37e9f6de01e1d8db2c60b1fcf', '33b0d32e2a3b4269ad2fc9ae173066e1', '8ce6b96c396f577adbf6be707b1433b3'),
      ('catalog.publish_event(uuid,text,text)', 'catalog', 'publish_event',
       '0f7d65e79fc24cc5feed1048575d3e27', 'f30eaca23ae71a33243e39a6c8c5a8fd', 'fe9bc5f0f91611a064b1cdef5143efec', '3243d8a053e81181d6c54fe1f05d5288'),
      ('venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text)', 'venue', 'set_ticket_type_sale_window',
       '9fd9b5f50b0c66afe7a0842e1e8104b9', 'dc5cf9c96e8cfb97074f6b5e8e502ea9', 'a417a4acb7523b8a1d35c8fc3a025432', 'a9e9d11d0619b03d22bb1f920901d2a8'),
      ('venue.allocate_comp(uuid,uuid,integer,text,text)', 'venue', 'allocate_comp',
       '269206489452fd2e8ea62afd4d1913f9', '73ad103d04ce30dbf7d7238ade284a26', 'd35f9a24869a91b70755dcd75613f410', 'fd475aaf290c34405b0037f35547d358')
    ) as t(sig, nsp, name, pred_src, pred_def, own_src, own_def)
  loop
    select count(*) into v_n
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = r.nsp and p.proname = r.name;
    if to_regprocedure(r.sig) is null or v_n <> 1 then
      raise exception 'MIGRATION_204_REFUSED: % — expected exactly one %.% overload with this signature (overloads %, signature %); nothing changed',
        r.sig, r.nsp, r.name, v_n, case when to_regprocedure(r.sig) is null then 'absent' else 'present' end;
    end if;
    select md5(p.prosrc), md5(pg_get_functiondef(p.oid)) into v_src, v_def
      from pg_proc p where p.oid = to_regprocedure(r.sig);
    v_st := case when v_src = r.pred_src and v_def = r.pred_def then 'pred'
                 when v_src = r.own_src and v_def = r.own_def then 'own' end;
    if v_st is null then
      if r.name = 'publish_event' and v_src = 'b31abddf9aad2cb7b119d517424bb494' then
        raise exception 'MIGRATION_204_REFUSED: catalog.publish_event carries e76''s body (prosrc %, functiondef %) — apply registry 202 first; nothing changed',
          v_src, v_def;
      end if;
      raise exception 'MIGRATION_204_REFUSED: % has prosrc % / functiondef %, neither the predecessor (% / %) nor 204''s own (% / %); nothing changed',
        r.sig, v_src, v_def, r.pred_src, r.pred_def, r.own_src, r.own_def;
    end if;
    v_cap := v_cap || jsonb_build_array((
      select jsonb_build_object('sig', r.sig, 'state', v_st, 'src', v_src, 'def', v_def,
               'want_src', r.own_src, 'want_def', r.own_def,
               'acl', coalesce(p.proacl::text, '<null>'), 'secdef', p.prosecdef,
               'cfg', coalesce(p.proconfig::text, '<null>'), 'owner', p.proowner::regrole::text,
               'vol', p.provolatile::text, 'cmt', coalesce(md5(obj_description(p.oid, 'pg_proc')), '<none>'))
        from pg_proc p where p.oid = to_regprocedure(r.sig)));
  end loop;

  -- premises the new bodies rely on (relied on, not replaced)
  if to_regprocedure('venue.assert_session_operator(uuid)') is null
     or to_regprocedure('pg_catalog.sha256(bytea)') is null
     or to_regprocedure('pg_catalog.hashtextextended(text,bigint)') is null
     or to_regprocedure('pg_catalog.pg_advisory_xact_lock(bigint)') is null
     or to_regclass('kernel.admin_audit_actor_idx') is null then
    raise exception 'MIGRATION_204_REFUSED: a premise is missing (venue.assert_session_operator %, sha256 %, hashtextextended %, pg_advisory_xact_lock %, kernel.admin_audit_actor_idx %); nothing changed',
      to_regprocedure('venue.assert_session_operator(uuid)') is not null, to_regprocedure('pg_catalog.sha256(bytea)') is not null,
      to_regprocedure('pg_catalog.hashtextextended(text,bigint)') is not null, to_regprocedure('pg_catalog.pg_advisory_xact_lock(bigint)') is not null,
      to_regclass('kernel.admin_audit_actor_idx') is not null;
  end if;
  select count(*) into v_n
    from pg_attribute a
   where a.attrelid = to_regclass('kernel.admin_audit') and a.attnum > 0 and not a.attisdropped
     and (a.attname::text, format_type(a.atttypid, a.atttypmod)) in
         (('id', 'uuid'), ('actor_identity', 'uuid'), ('action', 'text'), ('subject_id', 'uuid'),
          ('reason_code', 'text'), ('after', 'jsonb'), ('occurred_at', 'timestamp with time zone'));
  if v_n <> 7 then
    raise exception 'MIGRATION_204_REFUSED: kernel.admin_audit does not carry the seven columns the receipt reads (found % of 7); nothing changed', v_n;
  end if;

  -- census: the post-flight proves this file created and dropped nothing
  select jsonb_build_object(
           'procs', (select jsonb_object_agg(n.nspname, (select count(*) from pg_proc p where p.pronamespace = n.oid))
                       from pg_namespace n where n.nspname in ('catalog', 'venue', 'venue_cmd', 'kernel', 'public')),
           'rels',  (select jsonb_object_agg(n.nspname, (select count(*) from pg_class c where c.relnamespace = n.oid))
                       from pg_namespace n where n.nspname in ('catalog', 'venue', 'venue_cmd', 'kernel', 'public')),
           'audit_indexes', (select count(*) from pg_index i where i.indrelid = to_regclass('kernel.admin_audit')))
    into v_cen;

  perform set_config('migration_204.preflight', v_cap::text, true);
  perform set_config('migration_204.census', v_cen::text, true);
  raise notice '204 pre-flight: %',
    (select string_agg((e ->> 'sig') || '=' || left(e ->> 'def', 8) || case when e ->> 'state' = 'own' then ' (204 already)' else ' (predecessor)' end, ', ')
       from jsonb_array_elements(v_cap) e);
end $pf$;

-- ── 1 catalog.create_event(uuid,text,jsonb,text): receipt after authority; audit after carries the digests
do $i1$
begin
  if md5(pg_get_functiondef(to_regprocedure('catalog.create_event(uuid,text,jsonb,text)'))) = '02314a386f05a3dd459482caf07375b8' then
    execute $body204$CREATE OR REPLACE FUNCTION catalog.create_event(p_venue_id uuid, p_title text, p_first_session jsonb, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid      uuid;
  v_org_id   uuid;
  v_approval text;
  v_allowed  boolean := false;
  v_event_id uuid;
  v_session  jsonb;
  v_kd       text;
  v_rd       text;
  v_rcpt_id  uuid;
  v_rcpt_aft jsonb;
  v_rcpt_ses uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_title is null or length(trim(p_title)) = 0 then
    raise exception 'precondition_failed: title required';
  end if;

  select v.org_id, v.approval_status
    into v_org_id, v_approval
    from catalog.venue v where v.venue_id = p_venue_id;
  if v_org_id is null then
    raise exception 'not_found: venue %', p_venue_id using errcode = 'P0002';
  end if;
  if v_approval <> 'approved' then
    raise exception 'precondition_failed: venue is not approved';
  end if;

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  end if;
  if not v_allowed then                                    -- PFA-10 deferred arm
    v_allowed := kernel.has_venue_role(p_venue_id, array['venue_manager']);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- 204 (DB-6): command-key receipt
  v_kd := encode(sha256(convert_to(p_command_key, 'UTF8')), 'hex');
  v_rd := encode(sha256(convert_to((jsonb_build_object('venue_id', p_venue_id, 'title', trim(p_title), 'first_session', coalesce(p_first_session, '{}'::jsonb)))::text, 'UTF8')), 'hex');
  perform pg_advisory_xact_lock(hashtextextended('db6:event.create:' || v_uid::text || ':' || v_kd, 0));
  select a.subject_id, a.after into v_rcpt_id, v_rcpt_aft
    from kernel.admin_audit a
   where a.actor_identity = v_uid and a.action = 'event.create'
     and a.after ->> 'command_key_sha256' = v_kd
   order by a.occurred_at, a.id
   limit 1;
  if v_rcpt_id is not null then
    if v_rcpt_aft ->> 'request_sha256' is distinct from v_rd then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    select a.subject_id into v_rcpt_ses
      from kernel.admin_audit a
     where a.actor_identity = v_uid and a.action = 'session.create'
       and a.after ->> 'command_key_sha256' = encode(sha256(convert_to(p_command_key || ':implicit-session', 'UTF8')), 'hex')
       and a.after ->> 'event_id' = v_rcpt_id::text
     order by a.occurred_at, a.id
     limit 1;
    return jsonb_build_object('status','noop_replay','event_id',v_rcpt_id,'session_id',v_rcpt_ses);
  end if;

  -- org_id is SERVER-DERIVED from catalog.venue.org_id (denormalised for the
  -- authz hot path and kept consistent by THIS function); status := 'draft'.
  insert into catalog.event (venue_id, org_id, title, status)
  values (p_venue_id, v_org_id, trim(p_title), 'draft')
  returning event_id into v_event_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.create', 'event', v_event_id, 'self_service',
          null, jsonb_build_object('venue_id', p_venue_id, 'status', 'draft', 'command_key_sha256', v_kd, 'request_sha256', v_rd));

  -- A1: an event has >= 1 session, enforced by the create flow rather than by a
  -- table constraint.
  v_session := coalesce(p_first_session, '{}'::jsonb);
  return jsonb_build_object(
    'status','ok',
    'event_id', v_event_id,
    'session_id',
    (catalog.create_event_session(v_event_id, v_session,
                                  p_command_key || ':implicit-session') ->> 'session_id')::uuid);
end;
$function$
$body204$;
    raise notice '204: catalog.create_event(uuid,text,jsonb,text) replaced';
  else
    raise notice '204: catalog.create_event(uuid,text,jsonb,text) already carries 204''s body (re-apply, unchanged)';
  end if;
end $i1$;

-- ── 2 catalog.create_event_session(uuid,jsonb,text): receipt after authority, before the starts/ends validation
do $i2$
begin
  if md5(pg_get_functiondef(to_regprocedure('catalog.create_event_session(uuid,jsonb,text)'))) = '560bd7d37e9f6de01e1d8db2c60b1fcf' then
    execute $body204$CREATE OR REPLACE FUNCTION catalog.create_event_session(p_event_id uuid, p_session jsonb, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_kd         text;
  v_rd         text;
  v_rcpt_id    uuid;
  v_rcpt_aft   jsonb;
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

  -- 204 (DB-6): command-key receipt
  v_kd := encode(sha256(convert_to(p_command_key, 'UTF8')), 'hex');
  v_rd := encode(sha256(convert_to((jsonb_build_object('event_id', p_event_id, 'session', p_session))::text, 'UTF8')), 'hex');
  perform pg_advisory_xact_lock(hashtextextended('db6:session.create:' || v_uid::text || ':' || v_kd, 0));
  select a.subject_id, a.after into v_rcpt_id, v_rcpt_aft
    from kernel.admin_audit a
   where a.actor_identity = v_uid and a.action = 'session.create'
     and a.after ->> 'command_key_sha256' = v_kd
   order by a.occurred_at, a.id
   limit 1;
  if v_rcpt_id is not null then
    if v_rcpt_aft ->> 'request_sha256' is distinct from v_rd then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    return jsonb_build_object('status','noop_replay','session_id',v_rcpt_id);
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
          null, jsonb_build_object('event_id', p_event_id, 'starts_at', v_starts, 'command_key_sha256', v_kd, 'request_sha256', v_rd));

  return jsonb_build_object('status','ok','session_id',v_session_id);
end;
$function$
$body204$;
    raise notice '204: catalog.create_event_session(uuid,jsonb,text) replaced';
  else
    raise notice '204: catalog.create_event_session(uuid,jsonb,text) already carries 204''s body (re-apply, unchanged)';
  end if;
end $i2$;

-- ── 3 catalog.publish_event(uuid,text,text): 202's body + H1 declare, H2 receipt (before the transition check,
-- under the event row lock), H3 audit after carries the digests; gate 4 and every other byte unchanged
do $i3$
begin
  if md5(pg_get_functiondef(to_regprocedure('catalog.publish_event(uuid,text,text)'))) = 'f30eaca23ae71a33243e39a6c8c5a8fd' then
    execute $body204$CREATE OR REPLACE FUNCTION catalog.publish_event(p_event_id uuid, p_target_status text, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_fee_raw      jsonb;
  v_kd           text;
  v_rd           text;
  v_rcpt_id      uuid;
  v_rcpt_aft     jsonb;
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

  -- 204 (DB-6): command-key receipt
  v_kd := encode(sha256(convert_to(p_command_key, 'UTF8')), 'hex');
  v_rd := encode(sha256(convert_to((jsonb_build_object('event_id', p_event_id, 'target_status', p_target_status))::text, 'UTF8')), 'hex');
  perform pg_advisory_xact_lock(hashtextextended('db6:event.status:' || v_uid::text || ':' || v_kd, 0));
  select a.subject_id, a.after into v_rcpt_id, v_rcpt_aft
    from kernel.admin_audit a
   where a.actor_identity = v_uid and a.action = 'event.status' and a.reason_code = 'publish'
     and a.after ->> 'command_key_sha256' = v_kd
   order by a.occurred_at, a.id
   limit 1;
  if v_rcpt_id is not null then
    if v_rcpt_aft ->> 'request_sha256' is distinct from v_rd then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    return jsonb_build_object('status','noop_replay','event_status',v_rcpt_aft ->> 'status');
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
    -- Registry 202: read and gated exactly as venue.create_primary_checkout
    -- reads and gates the rate since 188 (20261027031000:362-371 and :391-399),
    -- so an event goes on sale only with a rate checkout would quote on. The
    -- NEWEST version is picked first (a LIMIT subquery) and only that value is
    -- cast, so no older version can raise under any plan. A newest value that
    -- is not a JSON number refuses, and so does one outside the integer range
    -- 0..10000 (0 is accepted, as checkout accepts it). Every refusal keeps the
    -- fee_policy_unset token, which the venue dashboard maps.
    select l.value into v_fee_raw
      from (select c.value
              from catalog.platform_config c
             where c.key = 'fee.buyer_service_bps'
             order by c.version desc
             limit 1) l;
    if jsonb_typeof(v_fee_raw) not in ('number', 'null') then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps is a JSON %, not a number; this event cannot go on sale until the owner sets an integer', jsonb_typeof(v_fee_raw);
    end if;
    v_fee_bps := case when jsonb_typeof(v_fee_raw) = 'number' then (v_fee_raw #>> '{}')::numeric end;
    if v_fee_bps is null then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps has no value; this event cannot go on sale until the owner sets it';
    end if;
    if v_fee_bps < 0 or v_fee_bps > 10000 or v_fee_bps <> trunc(v_fee_bps) then
      raise exception 'precondition_failed: fee_policy_unset — fee.buyer_service_bps must be an integer 0..10000, got %; this event cannot go on sale until the owner corrects it', v_fee_bps;
    end if;

    -- ---- end 102 / A8a' SALEABLE gate ladder ------------------------------
  end if;

  update catalog.event set status = p_target_status, updated_at = now()
   where event_id = p_event_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.status', 'event', p_event_id, 'publish',
          jsonb_build_object('status', v_status), jsonb_build_object('status', p_target_status, 'command_key_sha256', v_kd, 'request_sha256', v_rd));

  return jsonb_build_object('status','ok','event_status',p_target_status);
end;
$function$
$body204$;
    raise notice '204: catalog.publish_event(uuid,text,text) replaced';
  else
    raise notice '204: catalog.publish_event(uuid,text,text) already carries 204''s body (re-apply, unchanged)';
  end if;
end $i3$;

-- ── 4 venue.set_ticket_type_sale_window(...): receipt after authority, before the value-equal noop arm
do $i4$
begin
  if md5(pg_get_functiondef(to_regprocedure('venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text)'))) = 'dc5cf9c96e8cfb97074f6b5e8e502ea9' then
    execute $body204$CREATE OR REPLACE FUNCTION venue.set_ticket_type_sale_window(p_ticket_type_id uuid, p_sale_starts_at timestamp with time zone, p_sale_ends_at timestamp with time zone, p_reason_code text, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_venue     uuid;
  v_status    text;
  v_old_start timestamptz;
  v_old_end   timestamptz;
  v_kd        text;
  v_rd        text;
  v_rcpt_id   uuid;
  v_rcpt_aft  jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  -- validated here so the caller gets invalid_input, not the table CHECK's 23514.
  if p_sale_starts_at is not null and p_sale_ends_at is not null and p_sale_ends_at <= p_sale_starts_at then
    raise exception 'invalid_input: sale_ends_at must be after sale_starts_at';
  end if;

  select tt.sale_starts_at, tt.sale_ends_at, e.org_id, e.venue_id, e.status
    into v_old_start, v_old_end, v_org_id, v_venue, v_status
    from venue.ticket_type tt
    join catalog.event e on e.event_id = tt.event_id
   where tt.ticket_type_id = p_ticket_type_id
   for update of tt;                                    -- rank 2, Inventory class (081:279)
  if v_org_id is null then
    raise exception 'not_found: ticket type %', p_ticket_type_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  -- 162 (A's R3 ruling): the ORG arm binds to the EVENT's org — kernel.has_org_role on
  -- event.org_id, the 088:1629 cancel_event helper. The venue arm carries E-76 (160).
  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager (current operator) or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- 204 (DB-6): command-key receipt
  v_kd := encode(sha256(convert_to(p_command_key, 'UTF8')), 'hex');
  v_rd := encode(sha256(convert_to((jsonb_build_object('ticket_type_id', p_ticket_type_id, 'sale_starts_at', extract(epoch from p_sale_starts_at), 'sale_ends_at', extract(epoch from p_sale_ends_at), 'reason_code', p_reason_code))::text, 'UTF8')), 'hex');
  perform pg_advisory_xact_lock(hashtextextended('db6:ticket_type.sale_window_change:' || v_uid::text || ':' || v_kd, 0));
  select a.subject_id, a.after into v_rcpt_id, v_rcpt_aft
    from kernel.admin_audit a
   where a.actor_identity = v_uid and a.action = 'ticket_type.sale_window_change'
     and a.after ->> 'command_key_sha256' = v_kd
   order by a.occurred_at, a.id
   limit 1;
  if v_rcpt_id is not null then
    if v_rcpt_aft ->> 'request_sha256' is distinct from v_rd then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    return jsonb_build_object('status','noop_replay','ticket_type_id',p_ticket_type_id,
                              'sale_starts_at',p_sale_starts_at,'sale_ends_at',p_sale_ends_at);
  end if;

  if v_old_start is not distinct from p_sale_starts_at and v_old_end is not distinct from p_sale_ends_at then
    return jsonb_build_object('status','noop','ticket_type_id',p_ticket_type_id,
                              'sale_starts_at',v_old_start,'sale_ends_at',v_old_end);
  end if;

  update venue.ticket_type
     set sale_starts_at = p_sale_starts_at, sale_ends_at = p_sale_ends_at, updated_at = now()
   where ticket_type_id = p_ticket_type_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.sale_window_change', 'ticket_type', p_ticket_type_id, p_reason_code,
          jsonb_build_object('sale_starts_at', v_old_start, 'sale_ends_at', v_old_end),
          jsonb_build_object('sale_starts_at', p_sale_starts_at, 'sale_ends_at', p_sale_ends_at, 'command_key_sha256', v_kd, 'request_sha256', v_rd));

  return jsonb_build_object('status','ok','ticket_type_id',p_ticket_type_id,
                            'sale_starts_at',p_sale_starts_at,'sale_ends_at',p_sale_ends_at);
end;
$function$
$body204$;
    raise notice '204: venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text) replaced';
  else
    raise notice '204: venue.set_ticket_type_sale_window(uuid,timestamptz,timestamptz,text,text) already carries 204''s body (re-apply, unchanged)';
  end if;
end $i4$;

-- ── 5 venue.allocate_comp(...): blank-key refusal after authority / 187 block / bad_quantity, receipt, audit row
do $i5$
begin
  if md5(pg_get_functiondef(to_regprocedure('venue.allocate_comp(uuid,uuid,integer,text,text)'))) = '73ad103d04ce30dbf7d7238ade284a26' then
    execute $body204$CREATE OR REPLACE FUNCTION venue.allocate_comp(p_session_id uuid, p_batch_id uuid, p_quantity integer, p_reason_code text, p_command_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_venue uuid; v_id uuid;
        v_uid uuid := auth.uid(); v_kd text; v_rd text; v_rcpt_id uuid; v_rcpt_aft jsonb;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_manager']) then
    raise exception 'insufficient_privilege: venue_manager required' using errcode = '42501';
  end if;
  -- ── 187 BLOCK — E-76 operator binding: the venue role reaches this session only while the
  -- venue's CURRENT operator is the event's org (087:1369 shape); identical refusal, no oracle.
  perform venue.assert_session_operator(p_session_id);
  -- ── 187 BLOCK END
  if p_quantity is null or p_quantity <= 0 then raise exception 'precondition_failed: bad_quantity'; end if;
  -- 204 (DB-6): command-key receipt
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  v_kd := encode(sha256(convert_to(p_command_key, 'UTF8')), 'hex');
  v_rd := encode(sha256(convert_to((jsonb_build_object('session_id', p_session_id, 'batch_id', p_batch_id, 'quantity', p_quantity, 'reason_code', p_reason_code))::text, 'UTF8')), 'hex');
  perform pg_advisory_xact_lock(hashtextextended('db6:comp.allocate:' || v_uid::text || ':' || v_kd, 0));
  select a.subject_id, a.after into v_rcpt_id, v_rcpt_aft
    from kernel.admin_audit a
   where a.actor_identity = v_uid and a.action = 'comp.allocate'
     and a.after ->> 'command_key_sha256' = v_kd
   order by a.occurred_at, a.id
   limit 1;
  if v_rcpt_id is not null then
    if v_rcpt_aft ->> 'request_sha256' is distinct from v_rd then
      raise exception 'precondition_failed: idempotency_conflict — command key reused with different parameters' using errcode = 'P0001';
    end if;
    return jsonb_build_object('status','noop_replay','comp_allocation_id',v_rcpt_id);
  end if;
  insert into venue.comp_allocation (event_session_id, batch_id, quantity, granted_by)
  values (p_session_id, p_batch_id, p_quantity, auth.uid()) returning id into v_id;
  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'comp.allocate', 'comp_allocation', v_id, coalesce(nullif(trim(p_reason_code), ''), 'unspecified'), null,
          jsonb_build_object('session_id', p_session_id, 'batch_id', p_batch_id, 'quantity', p_quantity,
                             'command_key_sha256', v_kd, 'request_sha256', v_rd));
  return jsonb_build_object('status','ok','comp_allocation_id', v_id);
end;
$function$
$body204$;
    raise notice '204: venue.allocate_comp(uuid,uuid,integer,text,text) replaced';
  else
    raise notice '204: venue.allocate_comp(uuid,uuid,integer,text,text) already carries 204''s body (re-apply, unchanged)';
  end if;
end $i5$;

-- ── POST-FLIGHT: 204's md5s, every captured attribute and comment unchanged, the census unchanged.
do $pc$
declare
  v_cap jsonb := nullif(current_setting('migration_204.preflight', true), '')::jsonb;
  v_cen jsonb := nullif(current_setting('migration_204.census', true), '')::jsonb;
  v_now jsonb;
  e     jsonb;
  q     record;
begin
  if v_cap is null or jsonb_array_length(v_cap) <> 5 or v_cen is null then
    raise exception 'POSTFLIGHT_204_FAILED: the pre-flight capture is missing — run this file as one transaction';
  end if;
  for e in select * from jsonb_array_elements(v_cap) loop
    select md5(p.prosrc) as src, md5(pg_get_functiondef(p.oid)) as def, coalesce(p.proacl::text, '<null>') as acl,
           p.prosecdef, p.proconfig, coalesce(p.proconfig::text, '<null>') as cfg, p.proowner::regrole::text as owner,
           p.provolatile::text as vol, coalesce(md5(obj_description(p.oid, 'pg_proc')), '<none>') as cmt,
           (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) as n
      into q from pg_proc p where p.oid = to_regprocedure(e ->> 'sig');
    if q.src is distinct from e ->> 'want_src' or q.def is distinct from e ->> 'want_def' then
      raise exception 'POSTFLIGHT_204_FAILED: % body md5 % / % is not 204''s body % / % — this file was modified',
        e ->> 'sig', coalesce(q.src, '<absent>'), coalesce(q.def, '<absent>'), e ->> 'want_src', e ->> 'want_def';
    end if;
    if q.acl is distinct from e ->> 'acl' then
      raise exception 'POSTFLIGHT_204_FAILED: % ACL changed from % to %', e ->> 'sig', e ->> 'acl', q.acl;
    end if;
    if q.prosecdef is distinct from (e ->> 'secdef')::boolean or not q.prosecdef then
      raise exception 'POSTFLIGHT_204_FAILED: % SECURITY DEFINER changed (was %, now %)', e ->> 'sig', e ->> 'secdef', q.prosecdef;
    end if;
    if q.cfg is distinct from e ->> 'cfg' or q.proconfig is distinct from array['search_path=""'] then
      raise exception 'POSTFLIGHT_204_FAILED: % proconfig changed (was %, now %)', e ->> 'sig', e ->> 'cfg', q.cfg;
    end if;
    if q.owner is distinct from e ->> 'owner' or q.vol is distinct from e ->> 'vol' or q.n <> 1 then
      raise exception 'POSTFLIGHT_204_FAILED: % owner/volatility/overloads changed (owner % -> %, volatility % -> %, overloads %)',
        e ->> 'sig', e ->> 'owner', q.owner, e ->> 'vol', q.vol, q.n;
    end if;
    if q.cmt is distinct from e ->> 'cmt' then
      raise exception 'POSTFLIGHT_204_FAILED: % COMMENT changed (md5 % -> %)', e ->> 'sig', e ->> 'cmt', q.cmt;
    end if;
  end loop;
  select jsonb_build_object(
           'procs', (select jsonb_object_agg(n.nspname, (select count(*) from pg_proc p where p.pronamespace = n.oid))
                       from pg_namespace n where n.nspname in ('catalog', 'venue', 'venue_cmd', 'kernel', 'public')),
           'rels',  (select jsonb_object_agg(n.nspname, (select count(*) from pg_class c where c.relnamespace = n.oid))
                       from pg_namespace n where n.nspname in ('catalog', 'venue', 'venue_cmd', 'kernel', 'public')),
           'audit_indexes', (select count(*) from pg_index i where i.indrelid = to_regclass('kernel.admin_audit')))
    into v_now;
  if v_now is distinct from v_cen then
    raise exception 'POSTFLIGHT_204_FAILED: the census changed during this file (before %, after %)', v_cen, v_now;
  end if;
  raise notice '204 post-flight: % ok; posture, comments and census unchanged',
    (select string_agg((x ->> 'sig') || '=' || left(x ->> 'want_def', 8), ' ') from jsonb_array_elements(v_cap) x);
end $pc$;

commit;
