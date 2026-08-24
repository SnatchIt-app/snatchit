-- Migration 069: vendor the webhook_retries table (Gate-2 reproducibility)
--
-- webhook_retries exists in PRODUCTION but was created out-of-band (SQL editor) during the
-- "webhook retries no longer silently dropped" fix and was never captured in a migration —
-- so a fresh bootstrap (Supabase branch / CI / db reset) could not reproduce it. Definition
-- captured verbatim from production public.webhook_retries on 2026-08-24.
--
-- The table is written by the stripe-webhook Edge Function (service_role) to record webhook
-- handler RPC failures for retry. It is NOT referenced by any other migration, so creating it
-- here (after the chain) is order-safe. No client access (RLS on, zero policies, REVOKE ALL) —
-- matches production exactly. CREATE TABLE IF NOT EXISTS makes this a no-op on production.
create table if not exists public.webhook_retries (
  id            uuid        primary key default gen_random_uuid(),
  payment_id    uuid        references public.payments(id),
  listing_id    uuid        references public.listings(id),
  rpc_name      text        not null,
  error_message text,
  resolved      boolean     default false,
  created_at    timestamptz default now()
);
alter table public.webhook_retries enable row level security;
revoke all on public.webhook_retries from public, anon, authenticated;
