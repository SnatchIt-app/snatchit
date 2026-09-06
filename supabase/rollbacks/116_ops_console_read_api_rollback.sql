-- ============================================================================
-- 116_ops_console_read_api_rollback.sql — mechanical reversal of migration 116
-- (Operating Console read API). MECHANICAL-REVERSIBILITY REHEARSAL ONLY
-- (production is forward-only). Drops exactly the 38 functions 116 created in
-- schema `ops` (16 internal helpers + 22 reader entry points); nothing else was
-- touched (no table, no index, no policy, no public.* object). Schema `ops` and
-- every 115 object remain. Idempotent. ops function census returns to 22.
-- ============================================================================
begin;

-- readers (authenticated EXECUTE)
drop function if exists ops.search(text, integer);
drop function if exists ops.list_orders(jsonb, text, integer);
drop function if exists ops.order_detail(uuid);
drop function if exists ops.order_timeline(uuid);
drop function if exists ops.list_cases(jsonb, text, integer);
drop function if exists ops.case_detail(uuid);
drop function if exists ops.list_users(jsonb, text, integer);
drop function if exists ops.user_detail(uuid);
drop function if exists ops.list_listings(jsonb, text, integer);
drop function if exists ops.listing_detail(uuid);
drop function if exists ops.list_reports(jsonb, text, integer);
drop function if exists ops.money_overview(date, date);
drop function if exists ops.list_payouts(jsonb, text, integer);
drop function if exists ops.reconciliation_queue(text, integer);
drop function if exists ops.job_health();
drop function if exists ops.audit_log(text, integer);
drop function if exists ops.list_actions(jsonb, text, integer);
drop function if exists ops.action_detail(uuid);
drop function if exists ops.list_approvals(text);
drop function if exists ops.today();
drop function if exists ops.latest_summary();
drop function if exists ops.settings();

-- internal helpers
drop function if exists ops.action_row(ops.action);
drop function if exists ops.case_row(ops."case");
drop function if exists ops.subject_summary(text, uuid, text);
drop function if exists ops.subject_label(text, uuid, text);
drop function if exists ops.order_row(public.payments, public.transfers);
drop function if exists ops.funds_state(public.transfers, public.payments);
drop function if exists ops.transfer_json(public.transfers);
drop function if exists ops.payment_json(public.payments);
drop function if exists ops.listing_summary(uuid);
drop function if exists ops.user_summary(uuid);
drop function if exists ops.actor_label(uuid);
drop function if exists ops.jsonb_text_array(jsonb);
drop function if exists ops.uuid_prefix_range(text);
drop function if exists ops.cursor_decode(text);
drop function if exists ops.cursor_encode(timestamptz, uuid);
drop function if exists ops.clamp_limit(integer);

commit;
