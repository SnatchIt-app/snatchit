-- 056c — stop the transfer-guard bypass leaking past the statement that used it.
--
-- Found while verifying 056b. Every trusted writer opens its bypass with:
--
--     PERFORM set_config('app.bypass_transfer_guard', 'on', true);
--
-- The third argument is is_local, so the setting survives until COMMIT rather
-- than until the end of the statement — and no writer ever sets it back.
-- Measured directly during the 056b regression run:
--
--     LEAK  bypass GUC after ensure_transfer_exists returns = 'on'
--
-- With it still on, direct UPDATEs of transfers.status, payout_released_at and
-- seller_id all succeeded from inside the same transaction. Clearing it by hand
-- made all three fail correctly, which is how the real 056b result was obtained.
--
-- Live blast radius today is small: PostgREST runs each request in its own
-- transaction, so an attacker cannot call an RPC and then issue a direct write
-- inside that same transaction over HTTP. The danger is latent — any future
-- plpgsql function, batch job, or trigger that calls one of these RPCs and then
-- touches transfers runs with the guard silently disabled, and the code would
-- look perfectly correct while doing it.
--
-- Preferred fix was a function-level `SET app.bypass_transfer_guard` clause,
-- which Postgres saves on entry and restores on exit. Not available here: this
-- role cannot set a custom parameter placeholder, so both
--   ALTER FUNCTION ... SET app.bypass_transfer_guard = 'on'
--   ALTER DATABASE postgres SET app.bypass_transfer_guard = 'off'
-- fail with 42501 permission denied.
--
-- So instead the bypass is made single-statement by construction: a statement
-- level trigger clears it after each INSERT/UPDATE on transfers. A writer's
-- set_config now authorises exactly the next statement and nothing after it.
-- Statement-level triggers fire even when zero rows match, so a blocked or
-- no-op write still closes the window.
--
-- Every trusted writer issues exactly one UPDATE on transfers, except
-- delete_account_cleanup, which issues two — it re-arms the GUC below.

CREATE OR REPLACE FUNCTION public.reset_transfer_guard_bypass()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  PERFORM set_config('app.bypass_transfer_guard', 'off', true);
  RETURN NULL;
END; $function$;

COMMENT ON FUNCTION public.reset_transfer_guard_bypass() IS
  'Closes the app.bypass_transfer_guard window after every statement that writes '
  'transfers, so a trusted RPC authorises one statement rather than the rest of '
  'the transaction (056c).';

DROP TRIGGER IF EXISTS trg_reset_transfer_guard_bypass ON public.transfers;
CREATE TRIGGER trg_reset_transfer_guard_bypass
  AFTER INSERT OR UPDATE ON public.transfers
  FOR EACH STATEMENT EXECUTE FUNCTION public.reset_transfer_guard_bypass();

-- delete_account_cleanup writes transfers twice (buyer_id then seller_id).
-- Body is unchanged except for re-arming the GUC before the second write.
CREATE OR REPLACE FUNCTION public.delete_account_cleanup(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare v_sentinel_id uuid := '00000000-0000-0000-0000-000000000000';
begin
  perform set_config('app.bypass_listing_guard', 'on', true);
  perform set_config('app.bypass_transfer_guard', 'on', true);

  update public.listings
     set auction_status='cancelled', status='active', reserved_by=null,
         reserved_until=null, ended_at=now()
   where seller_id = p_user_id and auction_status in ('active','ended');

  alter table public.listings disable trigger trg_guard_listing_identity;
  update public.listings set seller_id = v_sentinel_id where seller_id = p_user_id;
  alter table public.listings enable trigger trg_guard_listing_identity;

  update public.payments set buyer_id  = v_sentinel_id where buyer_id  = p_user_id;
  update public.payments set seller_id = v_sentinel_id where seller_id = p_user_id;

  perform set_config('app.bypass_transfer_guard', 'on', true);
  update public.transfers set buyer_id  = v_sentinel_id where buyer_id  = p_user_id;
  perform set_config('app.bypass_transfer_guard', 'on', true);
  update public.transfers set seller_id = v_sentinel_id where seller_id = p_user_id;
end; $function$;
