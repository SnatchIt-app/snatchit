-- D 131 finding probe: deleting an auth user who has a live session (GoTrue admin deleteUser / account deletion sweep).
\set ON_ERROR_STOP 0
BEGIN;
CREATE TEMP TABLE o (n serial, k text, v text) ON COMMIT DROP;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
 ('d1310000-0000-4000-8000-0000000000e1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','e1@test.local','{}','{}',now(),now()),
 ('d1310000-0000-4000-8000-0000000000e2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','e2@test.local','{}','{}',now(),now()),
 ('d1310000-0000-4000-8000-0000000000e3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','e3@test.local','{}','{}',now(),now());
INSERT INTO auth.sessions (id, user_id, created_at, updated_at, aal) VALUES
 (gen_random_uuid(),'d1310000-0000-4000-8000-0000000000e1',now(),now(),'aal1'),
 (gen_random_uuid(),'d1310000-0000-4000-8000-0000000000e2',now(),now(),'aal1');
INSERT INTO kernel.identity_ext (identity_id) VALUES ('d1310000-0000-4000-8000-0000000000e2') ON CONFLICT DO NOTHING;
INSERT INTO o(k,v) SELECT 'fk', pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='identity_ext_identity_id_fkey';
INSERT INTO o(k,v) SELECT 'e2_has_identity_ext', count(*)::text FROM kernel.identity_ext WHERE identity_id='d1310000-0000-4000-8000-0000000000e2';
SAVEPOINT s1; DELETE FROM auth.users WHERE id='d1310000-0000-4000-8000-0000000000e1'; INSERT INTO o(k,v) VALUES ('delete_user_live_session_no_identity_ext','ok'); RELEASE SAVEPOINT s1;
ROLLBACK TO SAVEPOINT s1;
SAVEPOINT s2; DELETE FROM auth.users WHERE id='d1310000-0000-4000-8000-0000000000e2'; INSERT INTO o(k,v) VALUES ('delete_user_live_session_with_identity_ext','ok'); RELEASE SAVEPOINT s2;
ROLLBACK TO SAVEPOINT s2;
SAVEPOINT s3; DELETE FROM auth.users WHERE id='d1310000-0000-4000-8000-0000000000e3'; INSERT INTO o(k,v) VALUES ('delete_user_no_session','ok'); RELEASE SAVEPOINT s3;
SELECT n, k, v FROM o ORDER BY n;
ROLLBACK;
