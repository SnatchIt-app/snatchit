-- Rollback for migration 067. Restores broad EXECUTE (anon + authenticated + public) on
-- every function 067 locked down, returning to the pre-067 grant posture. Behaviorally inert
-- beyond re-opening the linter 0028/0029 findings.
grant execute on function public.disputes_set_updated_at()        to anon, authenticated, public;
grant execute on function public.guard_listing_identity_columns() to anon, authenticated, public;
grant execute on function public.guard_listing_state_columns()    to anon, authenticated, public;
grant execute on function public.guard_proof_status()             to anon, authenticated, public;
grant execute on function public.handle_new_user()                to anon, authenticated, public;
grant execute on function public.handle_new_user_notification_prefs() to anon, authenticated, public;
grant execute on function public.notify_auction_won_inbox()       to anon, authenticated, public;
grant execute on function public.notify_bid_inbox()               to anon, authenticated, public;
grant execute on function public.notify_bid_placed()              to anon, authenticated, public;
grant execute on function public.notify_moderation_event()        to anon, authenticated, public;
grant execute on function public.notify_outbid()                  to anon, authenticated, public;
grant execute on function public.notify_transfer_created_inbox()  to anon, authenticated, public;
grant execute on function public.notify_transfer_event()          to anon, authenticated, public;
grant execute on function public.notify_transfer_state_inbox()    to anon, authenticated, public;
grant execute on function public.set_updated_at()                 to anon, authenticated, public;
grant execute on function public.sync_listing_current_bid()       to anon, authenticated, public;
grant execute on function public.validate_and_apply_bid()         to anon, authenticated, public;
grant execute on function public.is_admin()                       to anon, authenticated, public;
grant execute on function public.request_is_service_role()        to anon, authenticated, public;
grant execute on function public.check_rate_limit(uuid, text, integer, integer) to anon, authenticated, public;
grant execute on function public.refresh_seller_risk_score(uuid)  to anon, authenticated, public;
grant execute on function public.refresh_all_seller_risk_scores() to anon, authenticated, public;
grant execute on function public.cleanup_expired_reservations()   to anon, authenticated, public;
grant execute on function public.auto_finalize_expired_auctions() to anon, authenticated, public;
grant execute on function public.finalize_auction(uuid)           to anon, authenticated, public;
grant execute on function public.can_create_listing(uuid)         to anon, authenticated, public;
grant execute on function public.get_profile_trust_stats(uuid)    to anon, authenticated, public;
grant execute on function public.phone_verified()                 to anon, authenticated, public;
