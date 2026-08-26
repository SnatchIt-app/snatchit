-- Rollback 056c — reopen the transaction-wide guard-bypass window.
--
-- Drops the statement-level reset trigger, so a trusted RPC's
-- set_config('app.bypass_transfer_guard','on',true) again stays on for the rest
-- of its transaction. Apply only if the reset trigger is implicated in a
-- regression — e.g. a writer that issues more than one statement against
-- transfers under a single set_config and now fails with
-- 'Cannot directly modify transfer state columns.'
--
-- The correct forward fix in that case is to re-arm the GUC before the writer's
-- additional statement (as delete_account_cleanup does), not to leave this
-- rolled back.
--
-- delete_account_cleanup is intentionally NOT reverted: the extra set_config
-- calls are harmless with or without the trigger.

DROP TRIGGER IF EXISTS trg_reset_transfer_guard_bypass ON public.transfers;
DROP FUNCTION IF EXISTS public.reset_transfer_guard_bypass();
