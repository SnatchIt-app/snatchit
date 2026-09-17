-- =============================================================================
-- 139_notify_report_delivery_claims.sql — G22: notify-report claims before it sends
--
-- WHY. notify-report is invoked by database triggers through pg_net and is
-- fire-and-forget: it answers 200 even on failure so a caller never retry-storms.
-- Nothing recorded that a given event had already been announced, so a duplicate
-- trigger fire or a replayed post sent every push and every email again.
--
-- THE CLAIM IS A DEDUPE DEVICE, NOT AN AUTHORIZATION DEVICE. It answers one
-- question — "has this exact delivery already been claimed?" — and the caller
-- decides what to do about it.
--
-- KEYS, as ruled by A (2026-09-17):
--   report_created          → the report_id           (one-shot)
--   dispute_opened          → the transfer_id         (one-shot)
--   signing_invariant_alert → the monitor RUN         (NOT the alert text)
--
-- THE SIGNING ALERT IS THE REASON THE KEY MATTERS. That alert fires on a daily
-- cron, and if the trust root is wrong it fires again tomorrow with the SAME
-- codes. Keying it on (event, summary) would announce a compromise once and then
-- suppress every later warning while it stayed unresolved. Keyed on the run,
-- every day's alert is delivered and only a double delivery of one run collapses.
--
-- NO GRANTS ON THE TABLE (157 B9: anon and service_role hold zero notify table
-- grants — service_role is BYPASSRLS, so the grant wall IS its wall). The edge
-- reaches this only through notify.claim_report_delivery, service_role EXECUTE.
--
-- Census: notify tables 8 → 9, notify routines 20 → 21; five-schema relations
-- 80 → 81, routines 303 → 304. Public census UNCHANGED (nothing here is public,
-- so the grant-decision manifest and expected_grants.txt are untouched). Pins
-- updated in 157. pgTAP 204.
-- =============================================================================
begin;

create table if not exists notify.report_delivery_claim (
  kind        text        not null,
  claim_key   text        not null,
  claimed_at  timestamptz not null default now(),
  primary key (kind, claim_key)
);

comment on table notify.report_delivery_claim is
  '139 (G22): one row per delivery notify-report has already announced. kind is a caller-owned namespace (report_created | dispute_opened | signing_invariant_alert) and claim_key identifies the thing announced — a report id, a transfer id, or the monitor RUN for the signing alert, never the alert text. No grants: reached only through notify.claim_report_delivery.';

-- a future sweep of old claims has an index to work with; nothing schedules one
-- here (cron registration is A''s surface).
create index if not exists report_delivery_claim_claimed_at_idx
  on notify.report_delivery_claim (claimed_at);

alter table notify.report_delivery_claim enable row level security;
revoke all on notify.report_delivery_claim from public, anon, authenticated, service_role;

create or replace function notify.claim_report_delivery(p_kind text, p_key text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_n int;
begin
  if p_kind is null or p_kind = '' or p_key is null or p_key = '' then
    raise exception 'precondition_failed: kind and key are required' using errcode = 'P0001';
  end if;

  insert into notify.report_delivery_claim (kind, claim_key)
  values (left(p_kind, 64), left(p_key, 200))
  on conflict (kind, claim_key) do nothing;

  get diagnostics v_n = row_count;
  -- true  = this caller took the claim and OWNS the send
  -- false = someone already announced it; the caller skips
  return v_n = 1;
end;
$$;

comment on function notify.claim_report_delivery(text, text) is
  '139 (G22): take the delivery claim for (kind, key). Returns true exactly once per pair — the caller that gets true owns the send; every later caller gets false and skips. Never raises on a duplicate. service_role only.';

revoke execute on function notify.claim_report_delivery(text, text) from public, anon, authenticated;
grant  execute on function notify.claim_report_delivery(text, text) to service_role;

commit;
