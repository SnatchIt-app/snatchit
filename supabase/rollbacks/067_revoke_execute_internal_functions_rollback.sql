-- Rollback for migration 067. Restores the Postgres default (EXECUTE to PUBLIC) on
-- every function 067 locked down. The explicit service_role/authenticated grants that
-- 067 added are harmless once PUBLIC is restored (they are subsumed) and are left in place.
grant execute on function public.disputes_set_updated_at()        to public;
grant execute on function public.guard_listing_identity_columns() to public;
grant execute on function public.guard_listing_state_columns()    to public;
grant execute on function public.guard_proof_status()             to public;
grant execute on function public.handle_new_user()                to public;
grant execute on function public.handle_new_user_notification_prefs() to public;
grant execute on function public.notify_auction_won_inbox()       to public;
grant execute on function public.notify_bid_inbox()               to public;
grant execute on function public.notify_bid_placed()              to public;
grant execute on function public.notify_moderation_event()        to public;
grant execute on function public.notify_outbid()                  to public;
grant execute on function public.notify_transfer_created_inbox()  to public;
grant execute on function public.notify_transfer_event()          to public;
grant execute on function public.notify_transfer_state_inbox()    to public;
grant execute on function public.set_updated_at()                 to public;
grant execute on function public.sync_listing_current_bid()       to public;
grant execute on function public.validate_and_apply_bid()         to public;
grant execute on function public.is_admin()                       to public;
grant execute on function public.request_is_service_role()        to public;
grant execute on function public.check_rate_limit(uuid, text, integer, integer) to public;
grant execute on function public.refresh_seller_risk_score(uuid)  to public;
grant execute on function public.refresh_all_seller_risk_scores() to public;
grant execute on function public.cleanup_expired_reservations()   to public;
grant execute on function public.auto_finalize_expired_auctions() to public;
grant execute on function public.finalize_auction(uuid)           to public;
grant execute on function public.can_create_listing(uuid)         to public;
grant execute on function public.get_profile_trust_stats(uuid)    to public;
grant execute on function public.phone_verified()                 to public;
