INSERT INTO supabase_migrations.schema_migrations (version, name, statements, created_by)
VALUES ('20261015000100', 'listing_duration_72h', ARRAY[$pkg155$-- ============================================================================
-- 20261015000100_listing_duration_72h.sql — registry 155 (pgTAP 222).
-- Owner authorisation 2026-10-15 (A's chat): 72 h auction support, consistent everywhere.
--
-- WHAT. listings_duration_hours_check gains 72 and nothing else:
--   before (baseline 000:88; production pg_get_constraintdef 2026-10-15):
--     CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48])))
--   after:
--     CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48, 72])))
-- Expiry needs no change: auto_finalize_expired_auctions / finalize_auction act on ends_at, which the
-- client sets from the chosen duration; duration_hours is an allow-listed label only. Clients (C native,
-- F web) add the 72 h option and their own allow-list after this is applied.
--
-- GATE-2 census: unchanged (a constraint is not a table, function, policy or trigger).
-- ROLLBACK: supabase/rollbacks/20261015000100_listing_duration_72h_rollback.sql — refuses while any
--   listing has duration_hours = 72; otherwise restores {1,3,6,12,24,48}.
-- VERIFY (read-only): select pg_get_constraintdef(oid) from pg_constraint
--   where conrelid = 'public.listings'::regclass and conname = 'listings_duration_hours_check';
-- FAILURE BEHAVIOUR: one transaction; ACCESS EXCLUSIVE on listings while the new check validates every
--   row (113 in production: milliseconds); lock_timeout 3s, so it fails cleanly rather than queue.
-- OWNER APPROVAL POINT: prepared and tested locally only; applying it is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE public.listings DROP CONSTRAINT listings_duration_hours_check;
ALTER TABLE public.listings ADD CONSTRAINT listings_duration_hours_check
  CHECK (duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48, 72]));

COMMIT;
$pkg155$], 'claude-a/owner-authorised-155');
