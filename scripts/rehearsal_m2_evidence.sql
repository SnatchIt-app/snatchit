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
  v_atom uuid; v_err text; v_dev uuid; v_dsid uuid; v_secret text; v_mint jsonb; v_mint2 jsonb;
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
  INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_scanning_enabled', 2, 'true'::jsonb, 'public');
  INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
  VALUES (v_venue, tap.seller(), 'venue_manager', tap.admin_user()), (v_venue, tap.other_user(), 'venue_scanner', tap.admin_user()) ON CONFLICT DO NOTHING;
  PERFORM tap.login(tap.seller());
  v_e := (catalog.create_event(v_venue,'EV Night', jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ev-e') ->> 'event_id')::uuid;
  SELECT session_id INTO v_s FROM catalog.event_session WHERE event_id = v_e;
  v_tt := (venue.create_ticket_type(v_e,'admission','GA',5000,'public','ev-tt') ->> 'ticket_type_id')::uuid;
  v_b := (venue.create_inventory_batch(v_tt, v_s, 'comp', 100, 0, 'ev-b') ->> 'batch_id')::uuid;
  v_dev := (venue.register_scan_device(v_venue, 'scanner-ev', 'ev-dev') ->> 'device_id')::uuid;
  PERFORM venue.create_door_pin(v_venue, v_s, 'front', 'pin-ev', (now()+interval '1 day'), 'ev-pin');
  PERFORM tap.logout();
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', v_e, 'PUBKEY-EV', 'kms-ev', 'active', now(), 'ES256') RETURNING key_id INTO v_k;
  PERFORM kernel.issue_ticket_atoms(jsonb_build_object('session_id',v_s,'org_id',v_org,'ticket_type_id',v_tt,'batch_id',v_b,
    'owner_id',tap.buyer(),'quantity',3,'cause','comp','cause_ref',gen_random_uuid(),'signing_key_id',v_k),'ev-m');
  PERFORM tap.login(tap.seller());
  v_m1 := (venue.open_door_manifest(v_s,'doors_open','ev-d1') ->> 'manifest_id')::uuid;
  PERFORM tap.logout();

  -- door session (113 machine path). The SECRET is used in-flight only and is
  -- NEVER written into the evidence table (the fixture is committed to the repo).
  PERFORM tap.login_service();
  v_mint := venue.mint_door_session(v_venue, v_s, v_dev, 'pin-ev', 'ev-mint');
  PERFORM tap.logout();
  v_dsid := (v_mint ->> 'door_session_id')::uuid; v_secret := v_mint ->> 'secret';
  INSERT INTO ev VALUES ('ids', jsonb_build_object('session_id', v_s, 'venue_id', v_venue, 'event_id', v_e, 'signing_key_id', v_k, 'manifest_id', v_m1,
                                                   'device_id', v_dev, 'door_session_id', v_dsid));
  INSERT INTO ev SELECT 'stored_header', jsonb_build_object('manifest_id', manifest_id, 'manifest_version', manifest_version, 'session_id', session_id,
     'opened_at', opened_at, 'not_after', not_after, 'manifest_digest', manifest_digest, 'status', status) FROM venue.door_manifest WHERE manifest_id = v_m1;

  PERFORM tap.login(tap.other_user());
  INSERT INTO ev VALUES ('open_full', venue.get_door_manifest(v_s, 0));
  PERFORM tap.logout();
  PERFORM tap.login_service();
  INSERT INTO ev VALUES ('door_full', venue.get_door_manifest_door(v_s, v_dsid, v_secret, v_dev, 0));
  PERFORM tap.logout();

  SELECT ticket_atom_id INTO v_atom FROM venue.door_manifest_entry WHERE manifest_id = v_m1 ORDER BY serial_no LIMIT 1;
  PERFORM venue.append_door_manifest_delta(v_s, ARRAY[v_atom], 'revoke', gen_random_uuid());
  PERFORM tap.login(tap.other_user());
  INSERT INTO ev VALUES ('open_incremental_since_0', venue.get_door_manifest(v_s, 0));
  INSERT INTO ev VALUES ('open_incremental_since_1', venue.get_door_manifest(v_s, 1));
  PERFORM tap.logout();
  PERFORM tap.login_service();
  INSERT INTO ev VALUES ('door_incremental_since_0', venue.get_door_manifest_door(v_s, v_dsid, v_secret, v_dev, 0));
  INSERT INTO ev VALUES ('door_incremental_since_1', venue.get_door_manifest_door(v_s, v_dsid, v_secret, v_dev, 1));
  INSERT INTO ev VALUES ('door_incremental_since_null', venue.get_door_manifest_door(v_s, v_dsid, v_secret, v_dev, NULL));
  -- wrong token / device / session / unknown id; service_role without credentials; the core directly
  BEGIN PERFORM venue.get_door_manifest_door(v_s, v_dsid, 'not-the-secret', v_dev, 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('door_wrong_token', to_jsonb(v_err));
  BEGIN PERFORM venue.get_door_manifest_door(v_s, v_dsid, v_secret, gen_random_uuid(), 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('door_wrong_device', to_jsonb(v_err));
  BEGIN PERFORM venue.get_door_manifest_door(gen_random_uuid(), v_dsid, v_secret, v_dev, 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('door_wrong_session', to_jsonb(v_err));
  BEGIN PERFORM venue.get_door_manifest_door(v_s, gen_random_uuid(), v_secret, v_dev, 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('door_unknown_door_session_id', to_jsonb(v_err));
  BEGIN PERFORM venue.get_door_manifest_door(v_s, gen_random_uuid(), '', gen_random_uuid(), 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('door_service_role_no_credentials', to_jsonb(v_err));
  BEGIN PERFORM venue._get_door_manifest_core(v_s, 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('door_core_direct_service_role', to_jsonb(v_err));
  PERFORM tap.logout();
  PERFORM tap.login_anon();
  BEGIN PERFORM venue.get_door_manifest_door(v_s, v_dsid, v_secret, v_dev, 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('door_anon_direct_valid_credentials', to_jsonb(v_err));
  PERFORM tap.login(tap.other_user());
  BEGIN PERFORM venue.get_door_manifest_door(v_s, v_dsid, v_secret, v_dev, 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('door_authenticated_direct_valid_credentials', to_jsonb(v_err));
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
  PERFORM tap.login_service();
  INSERT INTO ev VALUES ('door_closed', venue.get_door_manifest_door(v_s, v_dsid, v_secret, v_dev, 0));
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
  PERFORM tap.login_service();
  INSERT INTO ev VALUES ('door_expired', venue.get_door_manifest_door(v_s, v_dsid, v_secret, v_dev, 0));
  -- credentials invalidated BETWEEN the edge's admit check and the machine RPC
  INSERT INTO ev SELECT 'door_admit_check_before_revoke', jsonb_build_object('device_id', device_id, 'event_session_id', event_session_id)
    FROM kernel.assert_door_session(v_dev, v_s, v_dsid, v_secret);
  PERFORM tap.login(tap.seller());   -- venue_manager revokes
  PERFORM venue.revoke_door_session(v_dsid, 'operator_revoked', 'ev-rv');
  PERFORM tap.login_service();
  BEGIN PERFORM venue.get_door_manifest_door(v_s, v_dsid, v_secret, v_dev, 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('door_revoked_between_checks', to_jsonb(v_err));
  -- expired door session (fresh mint, expiry backdated — door_session has no guard trigger)
  v_mint2 := venue.mint_door_session(v_venue, v_s, v_dev, 'pin-ev', 'ev-mint2');
  PERFORM tap.logout();
  UPDATE venue.door_session SET issued_at = now() - interval '3 hours', expires_at = now() - interval '1 second' WHERE door_session_id = (v_mint2 ->> 'door_session_id')::uuid;
  PERFORM tap.login_service();
  BEGIN PERFORM venue.get_door_manifest_door(v_s, (v_mint2 ->> 'door_session_id')::uuid, v_mint2 ->> 'secret', v_dev, 0); v_err := 'NO ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLSTATE || ' ' || SQLERRM; END;
  INSERT INTO ev VALUES ('door_expired_door_session', to_jsonb(v_err));
  PERFORM tap.logout();
  INSERT INTO ev SELECT 'expired_stored_row', jsonb_build_object('status', status, 'not_after', not_after, 'now', now()) FROM venue.door_manifest WHERE manifest_id = v_m2;
  INSERT INTO ev VALUES ('rpc_source', jsonb_build_object('definition_md5', md5(pg_get_functiondef('venue.get_door_manifest(uuid,integer)'::regprocedure)),
     'door_definition_md5', md5(pg_get_functiondef('venue.get_door_manifest_door(uuid,uuid,text,uuid,integer)'::regprocedure)),
     'core_definition_md5', md5(pg_get_functiondef('venue._get_door_manifest_core(uuid,integer)'::regprocedure)),
     'captured_at', now(), 'database', current_database()));
END
$body$;
SELECT jsonb_pretty(jsonb_object_agg(k, v)) FROM ev;
ROLLBACK;
