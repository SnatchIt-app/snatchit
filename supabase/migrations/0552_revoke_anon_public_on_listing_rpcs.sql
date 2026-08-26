-- 055c_revoke_anon_public_on_listing_rpcs.sql
-- Revokes EXECUTE from PUBLIC and anon on the five listing/checkout RPCs that carry
-- the coalesce(auth.uid(), p_user_id) identity fallback, closing unauthenticated
-- identity spoofing via the shipped publishable key; regrants EXECUTE to
-- authenticated and service_role so real callers and Edge Functions are unaffected.
-- Recovered from supabase_migrations.schema_migrations version 20260805040935; applied 20260805040935. Not re-applied.

-- 055c: the coalesce(auth.uid(), p_user_id) identity fallback is NOT confined to
-- the transfer RPCs -- five listing/checkout RPCs carry it too, and all five were
-- EXECUTE-able by anon AND PUBLIC (bare '=X/postgres' ACL entry). With only the
-- shipped publishable key and no session, auth.uid() is NULL and p_user_id is
-- trusted verbatim, allowing: cancelling any seller's listing, reserving Buy Now
-- as any user, marking any listing sold, completing auction payment, and
-- releasing any reservation.
--
-- Revoking anon + PUBLIC makes the fallback unreachable by unauthenticated
-- callers. For `authenticated`, auth.uid() is non-NULL so coalesce always
-- resolves to the real caller and p_user_id cannot spoof. service_role keeps
-- EXECUTE, so the Edge Functions that legitimately pass p_user_id (auth.uid()
-- is structurally NULL there) continue to work unchanged.
--
-- This is the minimal change that closes the exploit without rewriting five
-- money-path function bodies. Rewriting them to strict auth.uid() remains
-- desirable follow-up hygiene, tracked for 056.

REVOKE EXECUTE ON FUNCTION public.cancel_listing(uuid, uuid)                     FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.complete_auction_payment(uuid, uuid)           FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.mark_listing_sold(uuid, uuid)                  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.release_reservation(uuid, uuid)                FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.reserve_buy_now(uuid, uuid, integer)           FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.cancel_listing(uuid, uuid)                      TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_auction_payment(uuid, uuid)            TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_listing_sold(uuid, uuid)                   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.release_reservation(uuid, uuid)                 TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_buy_now(uuid, uuid, integer)            TO authenticated, service_role;
