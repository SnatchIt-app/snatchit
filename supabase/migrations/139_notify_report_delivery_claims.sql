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
--   TRIGGER, not condition (D): moving 099's schedule to within ~an hour of
--   00:00 UTC makes this LIVE. Today it is `23 5 * * *` = 05:23 UTC.
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
-- Census: notify tables 8 → 9, notify routines 20 → 22 (claim + release); five-schema relations
-- 80 → 81, routines 303 → 305. Public census UNCHANGED (nothing here is public,
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
  -- NO SILENT TRUNCATION (D). Truncating and then deduping on the truncated value
  -- would let two different deliveries collapse into one claim — the exact failure
  -- direction this table exists to prevent. Refuse instead; no caller is near these.
  if length(p_kind) > 64 or length(p_key) > 200 then
    raise exception 'precondition_failed: kind (max 64) or key (max 200) too long' using errcode = 'P0001';
  end if;

  insert into notify.report_delivery_claim (kind, claim_key)
  values (p_kind, p_key)
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

-- ── the release (D's review of bcece84) ─────────────────────────────────────
-- A claim taken before the send, never released, turns "at most once" into
-- "sometimes zero": notify-report swallows every delivery error and answers 200,
-- so a claimed event whose sends ALL failed would stay claimed and every later
-- delivery of it would be suppressed for good. signing_invariant_alert self-heals
-- because its key is the run — tomorrow delivers. report_created and
-- dispute_opened have no next run, so the notice is lost permanently.
--
-- The caller releases when EVERY delivery attempt failed, which makes the pair
-- "at least once" without allowing duplicates on the normal path: a partial
-- success keeps the claim.
create or replace function notify.release_report_delivery(p_kind text, p_key text)
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

  delete from notify.report_delivery_claim where kind = p_kind and claim_key = p_key;
  get diagnostics v_n = row_count;
  return v_n = 1;
end;
$$;

comment on function notify.release_report_delivery(text, text) is
  '139 (G22, D review): give back the claim for (kind, key) so the delivery can be retried. The caller releases only when EVERY delivery attempt failed — a partial success keeps the claim, so the normal path still cannot duplicate. Returns true when a claim was actually given back. service_role only.';

revoke execute on function notify.release_report_delivery(text, text) from public, anon, authenticated;
grant  execute on function notify.release_report_delivery(text, text) to service_role;

commit;
