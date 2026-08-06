-- Rollback 063 — restore TRUNCATE/REFERENCES/TRIGGER and anon EXECUTE on the
-- maintenance RPCs.
--
-- This puts anon back in a position to call finalize_auction(uuid) and end any
-- live auction at its current bid, and puts TRUNCATE on payments/bids/listings
-- back in the client roles' hands. Only apply if 063 is implicated in a
-- regression, and prefer re-granting the single function involved over running
-- this whole file.

GRANT TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public
  TO anon, authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT TRUNCATE, REFERENCES, TRIGGER ON TABLES TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.finalize_auction(uuid)                         TO anon;
GRANT EXECUTE ON FUNCTION public.auto_finalize_expired_auctions()               TO anon;
GRANT EXECUTE ON FUNCTION public.cleanup_expired_reservations()                 TO anon;
GRANT EXECUTE ON FUNCTION public.refresh_all_seller_risk_scores()               TO anon;
GRANT EXECUTE ON FUNCTION public.refresh_seller_risk_score(uuid)                TO anon;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(uuid, text, integer, integer)  TO anon;
