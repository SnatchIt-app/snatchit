-- Investor expression-of-interest leads from the marketing website (/investors).
-- Fully isolated from all app tables. Anonymous INSERT only: no select/update/delete
-- policies exist, so submissions are write-only for the public and readable only via
-- service role / dashboard. Length CHECKs bound abuse from the public endpoint.
--
-- NOTE: applied to production remotely on 2026-07-14 (Supabase migration
-- 20260714190445) from the website workstream; vendored here verbatim so the
-- local migration history matches the remote before pushing 039.

create table public.investor_leads (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  full_name text not null check (char_length(full_name) between 1 and 200),
  email text not null check (char_length(email) between 3 and 320),
  phone text check (phone is null or char_length(phone) <= 50),
  company text check (company is null or char_length(company) <= 300),
  linkedin text check (linkedin is null or char_length(linkedin) <= 500),
  location text check (location is null or char_length(location) <= 300),
  investor_type text check (investor_type is null or char_length(investor_type) <= 100),
  check_size text check (check_size is null or char_length(check_size) <= 100),
  previous_investments text check (previous_investments is null or char_length(previous_investments) <= 3000),
  areas_of_interest text check (areas_of_interest is null or char_length(areas_of_interest) <= 3000),
  relevant_experience text check (relevant_experience is null or char_length(relevant_experience) <= 3000),
  strategic_value text check (strategic_value is null or char_length(strategic_value) <= 3000),
  referral_source text check (referral_source is null or char_length(referral_source) <= 1000),
  accredited text check (accredited is null or char_length(accredited) <= 50),
  preferred_next_step text check (preferred_next_step is null or char_length(preferred_next_step) <= 100),
  message text check (message is null or char_length(message) <= 5000),
  source text not null default 'website' check (char_length(source) <= 50)
);

alter table public.investor_leads enable row level security;

-- Public (anon) may INSERT only. No select/update/delete policies → reads are
-- impossible with the publishable key; only service role / dashboard can read.
create policy "investor_leads: anon insert only"
  on public.investor_leads
  for insert
  to anon
  with check (true);
