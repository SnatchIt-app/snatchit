-- scripts/rehearsal_m2_evidence.sql — LOCAL REHEARSAL ONLY (run via
-- scripts/rehearsal_m2_evidence.sh). Captures the REAL `venue.get_door_manifest`
-- output for the SCANNER-CONTRACT-v1 evidence file
-- (tests/fixtures/m2-rehearsal-evidence.json), inside one transaction that is
-- ROLLED BACK — the rehearsal database is left exactly as it was.
-- Requires the tap helper schema (000_helpers.sql) — the runner applies it.
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\pset pager off
BEGIN;
CREATE TEMP TABLE ev (k text PRIMARY KEY, v jsonb) ON COMMIT DROP;
GRANT INSERT, SELECT ON ev TO authenticated, anon, service_role; -- the tap.login() role switches write into it too
DO $body$
DECLARE
  v_org uuid; v_venue uuid; v_e uuid; v_s uuid; v_tt uuid; v_b uuid; v_k uuid; v_m1 uuid; v_m2 uuid;
  v_atom uuid; v_err text;
BEGIN
  PERFORM tap.seed_core();
  PERFORM tap.login(tap.seller());
  v_org := (kernel.create_organization('EV Co','EV Co','ev-o') ->> 'org_id')::uuid;
  PERFORM tap.logout();
  UPDATE kernel.organization SET status='approved' WHERE org_id = v_org;
  PERFORM tap.login(tap.seller());
  v_venue := (catalog.create_venue(v_org,'EV Hall','wynwood',NULL,'ev-v') ->> 'venue_id')::uuid;
  PERFORM tap.logout();
  PERFORM tap.login(tap.admin_user());
  PERFORM catalog.approve_venue(v_venue,'approved','miami_gate','ev-a');
  PERFORM tap.logout();
  INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
  INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
  VALUES (v_venue, tap.seller(), 'venue_manager', tap.admin_user()), (v_venue, tap.other_user(), 'venue_scanner', tap.admin_user()) ON CONFLICT DO NOTHING;
  PERFORM tap.login(tap.seller());
  v_e := (catalog.create_event(v_venue,'EV Night', jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ev-e') ->> 'event_id')::uuid;
  SELECT session_id INTO v_s FROM catalog.event_session WHERE event_id = v_e;
  v_tt := (venue.create_ticket_type(v_e,'admission','GA',5000,'public','ev-tt') ->> 'ticket_type_id')::uuid;
  v_b := (venue.create_inventory_batch(v_tt, v_s, 'comp', 100, 0, 'ev-b') ->> 'batch_id')::uuid;
  PERFORM tap.logout();
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', v_e, 'PUBKEY-EV', 'kms-ev', 'active', now(), 'ES256') RETURNING key_id INTO v_k;
  PERFORM kernel.issue_ticket_atoms(jsonb_build_object('session_id',v_s,'org_id',v_org,'ticket_type_id',v_tt,'batch_id',v_b,
    'owner_id',tap.buyer(),'quantity',3,'cause','comp','cause_ref',gen_random_uuid(),'signing_key_id',v_k),'ev-m');
  PERFORM tap.login(tap.seller());
  v_m1 := (venue.open_door_manifest(v_s,'doors_open','ev-d1') ->> 'manifest_id')::uuid;
  PERFORM tap.logout();

  INSERT INTO ev VALUES ('ids', jsonb_build_object('session_id', v_s, 'venue_id', v_venue, 'event_id', v_e, 'signing_key_id', v_k, 'manifest_id', v_m1));
  INSERT INTO ev SELECT 'stored_header', jsonb_build_object('manifest_id', manifest_id, 'manifest_version', manifest_version, 'session_id', session_id,
     'opened_at', opened_at, 'not_after', not_after, 'manifest_digest', manifest_digest, 'status', status) FROM venue.door_manifest WHERE manifest_id = v_m1;

  PERFORM tap.login(tap.other_user());
  INSERT INTO ev VALUES ('open_full', venue.get_door_manifest(v_s, 0));
  PERFORM tap.logout();

  SELECT ticket_atom_id INTO v_atom FROM venue.door_manifest_entry WHERE manifest_id = v_m1 ORDER BY serial_no LIMIT 1;
  PERFORM venue.append_door_manifest_delta(v_s, ARRAY[v_atom], 'revoke', gen_random_uuid());
  PERFORM tap.login(tap.other_user());
  INSERT INTO ev VALUES ('open_incremental_since_0', venue.get_door_manifest(v_s, 0));
  INSERT INTO ev VALUES ('open_incremental_since_1', venue.get_door_manifest(v_s, 1));
  PERFORM tap.logout();

  -- unauthorized callers (error text captured, never a manifest)
  PERFORM tap.login(tap.buyer());
  BEGIN PERFORM venue.get_door_manifest(v_s, 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('unauthorized_buyer', to_jsonb(v_err));
  PERFORM tap.login_service();
  BEGIN PERFORM venue.get_door_manifest(v_s, 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('unauthorized_service_role_door_relay', to_jsonb(v_err));
  PERFORM tap.login(tap.other_user());
  BEGIN PERFORM venue.get_door_manifest(gen_random_uuid(), 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('wrong_session_unknown', to_jsonb(v_err));
  PERFORM tap.logout();

  -- closed
  PERFORM tap.login(tap.seller());
  PERFORM venue.close_door_manifest(v_s,'doors_closed','ev-c1');
  PERFORM tap.login(tap.other_user());
  INSERT INTO ev VALUES ('closed', venue.get_door_manifest(v_s, 0));
  PERFORM tap.logout();

  -- expired: now() is frozen for this single transaction, so the stored window
  -- is backdated (guard trigger disabled for the fixture only) — the RPC can
  -- only be reading the STORED not_after.
  PERFORM tap.login(tap.seller());
  v_m2 := (venue.open_door_manifest(v_s,'doors_open','ev-d2') ->> 'manifest_id')::uuid;
  PERFORM tap.login(tap.other_user());
  INSERT INTO ev VALUES ('reopened_v2_fresh', venue.get_door_manifest(v_s, 0));
  PERFORM tap.logout();
  ALTER TABLE venue.door_manifest DISABLE TRIGGER tg_door_manifest_transition;
  UPDATE venue.door_manifest SET opened_at = now() - interval '3 hours', not_after = now() - interval '1 second' WHERE manifest_id = v_m2;
  ALTER TABLE venue.door_manifest ENABLE TRIGGER tg_door_manifest_transition;
  PERFORM tap.login(tap.other_user());
  INSERT INTO ev VALUES ('expired', venue.get_door_manifest(v_s, 0));
  PERFORM tap.logout();
  INSERT INTO ev SELECT 'expired_stored_row', jsonb_build_object('status', status, 'not_after', not_after, 'now', now()) FROM venue.door_manifest WHERE manifest_id = v_m2;
  INSERT INTO ev VALUES ('rpc_source', jsonb_build_object('definition_md5', md5(pg_get_functiondef('venue.get_door_manifest(uuid,integer)'::regprocedure)),
     'captured_at', now(), 'database', current_database()));
END
$body$;
SELECT jsonb_pretty(jsonb_object_agg(k, v)) FROM ev;
ROLLBACK;
