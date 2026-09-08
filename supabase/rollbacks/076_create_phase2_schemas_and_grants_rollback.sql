-- 076_create_phase2_schemas_and_grants_rollback.sql
-- =============================================================================
-- Rollback for Phase-2 package 076.
--
-- FROZEN POSTURE (registry 076 / plan §8, amended OR-12/F-P1-7):
--   REVERSIBLE — but ONLY while notify.outbox is EMPTY. Once envelopes exist
--   the posture is CLEAN-WHILE-EMPTY: a cascade drop would destroy undrained
--   mandatory-notice carriers (the deletion-lifecycle and credential notices
--   ride this table from 077 onward). The guard below enforces that.
--
-- Drops (frozen: "DROP SCHEMA … CASCADE ×4 (incl. notify) + drop helpers"):
--   the four walled schemas cascade (kernel's cascade removes the two helper
--   functions; notify's removes the outbox + emit pair), then catalog (born
--   empty in 076 — plain DROP). ALTER DEFAULT PRIVILEGES entries die with
--   their schemas. Result is 075-equivalent.
-- =============================================================================

-- SELF-TRANSACTIONAL: the guard below must be INSEPARABLE from the drops.
-- Without this BEGIN, a caller running plain `psql -f` (no -1, no
-- ON_ERROR_STOP) would see the guard raise and then EXECUTE THE DROPS ANYWAY
-- — proven in the local battery (R1) and fixed here: inside one explicit
-- transaction a raised guard aborts the transaction, every later statement
-- fails as aborted, and the final COMMIT rolls back.
begin;

do $$
declare
  v_envelopes bigint;
begin
  -- A-F3: a partial plain-psql apply can leave schemas without the outbox;
  -- let the rollback clean that state instead of aborting on 42P01.
  if to_regclass('notify.outbox') is null then
    raise notice '076 rollback: notify.outbox absent (partial apply) — proceeding with schema drops.';
    return;
  end if;
  -- ROLLBACK_GUARD_ROW_SECURITY (obligation opened by 091's E-151, CLOSED at the 2026-09-02
  -- release-readiness pass): the guard counts RLS-enabled zero-policy tables; run by a
  -- non-owner, non-BYPASSRLS role it would read 0 rows and FAIL OPEN. Count with row
  -- security off — same house pattern as the 091/092 rollbacks.
  set local row_security = off;
  -- A-F2: close the TOCTOU between the count and the drops — no emit can
  -- commit between this lock and the end of this transaction.
  lock table notify.outbox in access exclusive mode;
  -- A-F1: only UNDRAINED carriers block (pending/claimed); drained rows
  -- (done/dead) are history whose destruction the drain already survived.
  select count(*) into v_envelopes
    from notify.outbox where state in ('pending','claimed');
  if v_envelopes > 0 then
    raise exception
      'REFUSED: notify.outbox holds % UNDRAINED envelope(s) (pending/claimed). The frozen rollback posture is CLEAN-WHILE-EMPTY once envelopes exist — a cascade drop would destroy undrained mandatory-notice carriers. Drain them (092) first; drained (done/dead) rows do not block.',
      v_envelopes;
  end if;
end;
$$;

drop schema notify cascade;
drop schema market cascade;
drop schema venue  cascade;
drop schema kernel cascade;
drop schema catalog;

commit;
