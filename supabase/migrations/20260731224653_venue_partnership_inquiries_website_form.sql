-- 20260731224653_venue_partnership_inquiries_website_form.sql
-- Creates public.venue_partnership_inquiries: an anon-insert-only intake table for the
-- marketing website's /venues partnership form, with CHECK-based validation, honeypot
-- rejection, an atomic pending-email unique index, an updated_at trigger, and
-- default-deny RLS (no read path for anon/authenticated).
-- Recovered from supabase_migrations.schema_migrations version 20260731224653; applied 20260731224653. Not re-applied.

create table public.venue_partnership_inquiries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,

  full_name text not null check (char_length(full_name) between 1 and 200),
  work_email text not null check (
    work_email ~* '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(work_email) <= 320
  ),
  phone text not null check (char_length(phone) between 1 and 40),
  company_name text not null check (char_length(company_name) between 1 and 200),
  venue_or_event_name text not null check (char_length(venue_or_event_name) between 1 and 200),
  website_or_instagram text check (website_or_instagram is null or char_length(website_or_instagram) <= 300),
  city text not null check (char_length(city) between 1 and 120),

  venue_or_event_type text not null check (venue_or_event_type in (
    'nightclub', 'music_venue', 'festival', 'independent_promoter',
    'event_collective', 'campus_or_cultural', 'hospitality_group',
    'experiential_organizer', 'other'
  )),
  venue_capacity_range text check (venue_capacity_range is null or venue_capacity_range in (
    'under_300', '300_1000', '1000_5000', '5000_20000', '20000_plus'
  )),
  annual_ticketed_events_range text check (annual_ticketed_events_range is null or annual_ticketed_events_range in (
    '1_10', '11_50', '51_150', '150_plus'
  )),
  current_ticketing_provider text check (current_ticketing_provider is null or char_length(current_ticketing_provider) <= 200),

  partnership_interest text not null check (partnership_interest in (
    'official_resale', 'marketplace_waitlist', 'venue_growth_marketing',
    'primary_ticketing', 'festival_partnership', 'not_sure'
  )),
  message text check (message is null or char_length(message) <= 2000),

  -- Honeypot: must stay null/empty. A non-empty value is a bot signal the DB rejects outright.
  hp_field text check (hp_field is null or hp_field = ''),

  -- Attributes every row to the page/flow it came from (currently always 'venues_page').
  source text not null default 'venues_page' check (char_length(source) <= 60),

  status text not null default 'pending' check (status in ('pending', 'reviewed', 'contacted', 'qualified', 'closed')),
  review_notes text,
  reviewer_id uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,

  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.venue_partnership_inquiries is
  'Public venue/promoter partnership inquiries from the marketing website (/venues). Admin-only read via Supabase dashboard / service role until a dedicated admin system is built.';

-- Atomic duplicate-prevention: one pending inquiry per work email at a time,
-- enforced by Postgres itself (race-safe), same pattern as ambassador_applications.
create unique index venue_partnership_inquiries_pending_email_idx
  on public.venue_partnership_inquiries (lower(work_email))
  where status = 'pending';

-- Review-queue indexes
create index venue_partnership_inquiries_status_submitted_idx
  on public.venue_partnership_inquiries (status, submitted_at desc);
create index venue_partnership_inquiries_email_idx
  on public.venue_partnership_inquiries (lower(work_email));

create trigger venue_partnership_inquiries_set_updated_at
  before update on public.venue_partnership_inquiries
  for each row execute function public.set_updated_at();

alter table public.venue_partnership_inquiries enable row level security;

create policy "venue_partnership_inquiries: anon insert only"
  on public.venue_partnership_inquiries
  for insert
  to anon
  with check (true);
