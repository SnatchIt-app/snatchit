BEGIN;
SELECT plan(9);

INSERT INTO auth.users(id,email) VALUES
  ('27600000-0000-4000-8000-000000000001','approver.276@test.local'),
  ('27600000-0000-4000-8000-000000000002','fan.276@test.local');
INSERT INTO public.admin_users(user_id,label) VALUES
  ('27600000-0000-4000-8000-000000000001','TEST VENUE APPROVER');
INSERT INTO kernel.organization(org_id,legal_name,display_name)
VALUES ('27600000-0000-4000-8000-000000000003','Venue approval test','Venue approval test');
INSERT INTO catalog.venue(venue_id,org_id,name,neighborhood)
VALUES ('27600000-0000-4000-8000-000000000004','27600000-0000-4000-8000-000000000003','Draft venue','wynwood');

SELECT ok(
  (SELECT NOT prosecdef AND proconfig = array['search_path=""'] FROM pg_proc
    WHERE oid=to_regprocedure('ops.approve_venue(uuid,text,text)')),
  'venue approval uses caller privileges and an empty search path');
SELECT ok(
  has_function_privilege('authenticated',to_regprocedure('ops.approve_venue(uuid,text,text)'),'EXECUTE')
  AND NOT has_function_privilege('anon',to_regprocedure('ops.approve_venue(uuid,text,text)'),'EXECUTE')
  AND NOT has_function_privilege('service_role',to_regprocedure('ops.approve_venue(uuid,text,text)'),'EXECUTE'),
  'only the authenticated client role may execute');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"27600000-0000-4000-8000-000000000002","aal":"aal2","role":"authenticated"}',true);
SELECT throws_ok($$SELECT ops.approve_venue('27600000-0000-4000-8000-000000000004','venue pilot','pilot-276')$$,
  '42501','insufficient_privilege: platform_admin required','non-admin denied even at aal2');
SELECT set_config('request.jwt.claims','{"sub":"27600000-0000-4000-8000-000000000001","aal":"aal1","role":"authenticated"}',true);
SELECT throws_ok($$SELECT ops.approve_venue('27600000-0000-4000-8000-000000000004','venue pilot','pilot-276')$$,
  '42501','step_up_required: confirm with your authenticator','admin at aal1 denied');
RESET ROLE;
SELECT is((SELECT approval_status FROM catalog.venue WHERE venue_id='27600000-0000-4000-8000-000000000004'),
  'draft','refused calls leave the venue in draft');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"27600000-0000-4000-8000-000000000001","aal":"aal2","role":"authenticated"}',true);
SELECT is(ops.approve_venue('27600000-0000-4000-8000-000000000004','venue pilot','pilot-276')->>'status','ok','verified admin may approve');
SELECT is(ops.approve_venue('27600000-0000-4000-8000-000000000004','venue pilot','pilot-276')->>'status','noop_replay','retry is a no-op');
RESET ROLE;
SELECT is((SELECT approval_status FROM catalog.venue WHERE venue_id='27600000-0000-4000-8000-000000000004'),'approved','venue is approved');
SELECT is((SELECT jsonb_agg(jsonb_build_object('actor',actor_identity,'reason',reason_code,'before',before,'after',after))
  FROM kernel.admin_audit WHERE action='venue.approve' AND subject_id='27600000-0000-4000-8000-000000000004'),
  '[{"actor":"27600000-0000-4000-8000-000000000001","reason":"venue pilot","before":{"approval_status":"draft"},"after":{"approval_status":"approved"}}]'::jsonb,
  'exactly one audit entry preserves the admin identity, reason, and transition');
SELECT * FROM finish();
ROLLBACK;
