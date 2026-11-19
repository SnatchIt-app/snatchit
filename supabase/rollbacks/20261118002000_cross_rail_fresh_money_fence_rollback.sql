-- 214 recovery is forward-only. Never remove the financial fence or restore
-- the known cross-rail race. Disable new execution through the reviewed runbook,
-- retain reconciliation and this schema, then deploy a reviewed fix-forward.
-- This file only succeeds as a no-op on the exact unapplied 212 predecessor.
BEGIN;
DO $rollback214$ BEGIN
 IF to_regprocedure('kernel.authorize_fresh_refund(uuid)') IS NOT NULL THEN
  RAISE EXCEPTION 'ROLLBACK_214_FORWARD_ONLY: retain payment fencing; use reviewed fix-forward';
 END IF;
IF md5(pg_get_functiondef('public.claim_payout_attempt(uuid,text,interval)'::regprocedure)) <> '0ca6121d0306605cc8daab5415c450c0' THEN RAISE EXCEPTION 'PREFLIGHT_214_BODY_CHANGED: public.claim_payout_attempt(uuid,text,interval)'; END IF;
IF md5(pg_get_functiondef('ops.executor_claim(uuid,integer)'::regprocedure)) <> '23025535815c199354a75f31c768351c' THEN RAISE EXCEPTION 'PREFLIGHT_214_BODY_CHANGED: ops.executor_claim(uuid,integer)'; END IF;
IF md5(pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure)) <> 'd2579c0f72d09570d2463e8ce3046a12' THEN RAISE EXCEPTION 'PREFLIGHT_214_BODY_CHANGED: ops.action_dispatch(ops.action)'; END IF;
IF md5(pg_get_functiondef('ops.action_precheck(ops.action)'::regprocedure)) <> '092aa4d6ae428653cd9b9d4cf845b0c0' THEN RAISE EXCEPTION 'PREFLIGHT_214_BODY_CHANGED: ops.action_precheck(ops.action)'; END IF;
END $rollback214$;
COMMIT;
