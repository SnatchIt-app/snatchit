-- 20260730212326_ambassador_applications_website_form.sql
-- Creates public.ambassador_applications: an anon-insert-only intake table for the
-- marketing website's Ambassador Program form (/ambassadors/apply), with CHECK-based
-- server-side validation, honeypot rejection, an atomic pending-email unique index,
-- an updated_at trigger, and default-deny RLS (no read path for anon/authenticated).
-- Recovered from supabase_migrations.schema_migrations version 20260730212326; applied 20260730212326. Not re-applied.

-- Ambassador Program applications from the marketing website (/ambassadors/apply).
-- Public, anonymous intake table. Fully isolated from mobile-app tables.
--
-- Security model (matches the investor_leads precedent already in this project):
--   * RLS enabled, anon may INSERT only. No select/update/delete policy for anon
--     or authenticated -> default-deny, so submissions are write-only from the
--     public internet. Reviewable only via the Supabase dashboard / service role.
--   * All server-side validation is enforced by CHECK constraints (Postgres
--     rejects malformed/incomplete payloads regardless of what the client sends).
--   * Honeypot (hp_field) must stay empty; a bot that fills it is rejected by a
--     CHECK constraint before the row is ever written.
--   * A partial unique index on lower(email) WHERE status='pending' makes
--     duplicate-active-application prevention atomic and race-condition-safe
--     (handles rapid double-submits, retries, and back-button resubmits).

create table public.ambassador_applications (
  id uuid primary key default gen_random_uuid(),

  -- Optional link if the applicant happens to be a signed-in mobile-app user.
  -- The public website itself has no auth session, so this is null in practice
  -- for web-sourced applications; kept for schema completeness / future reuse.
  user_id uuid references auth.users(id) on delete set null,

  -- About you
  full_name text not null check (char_length(btrim(full_name)) between 1 and 200),
  preferred_name text check (preferred_name is null or char_length(preferred_name) <= 100),
  email text not null check (char_length(email) between 3 and 320 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone text not null check (char_length(btrim(phone)) between 5 and 30),
  city text not null check (char_length(btrim(city)) between 1 and 150),
  region text check (region is null or char_length(region) <= 150),
  country text not null check (char_length(btrim(country)) between 1 and 100),
  age_confirmed boolean not null default false,

  -- Socials (all optional individually; at least one is enforced client-side,
  -- not required server-side since ambassadors may legitimately use only one)
  instagram_handle text check (instagram_handle is null or char_length(instagram_handle) <= 100),
  tiktok_handle text check (tiktok_handle is null or char_length(tiktok_handle) <= 100),
  other_platform text check (other_platform is null or char_length(other_platform) <= 300),

  -- Your audience
  ambassador_category text not null check (
    ambassador_category in ('promoter','influencer','dj','nightlife_creator','college_ambassador','community_leader','other')
  ),
  audience_size_range text not null check (char_length(audience_size_range) <= 50),
  audience_location text not null check (char_length(btrim(audience_location)) between 1 and 200),
  content_focus text not null check (char_length(btrim(content_focus)) between 1 and 500),
  audience_channels text[] not null default '{}',

  -- Your experience / how you'd promote
  motivation text not null check (char_length(btrim(motivation)) between 1 and 1000),
  promotion_plan text not null check (char_length(btrim(promotion_plan)) between 1 and 1000),
  has_brand_experience boolean not null default false,
  partnership_details text check (partnership_details is null or char_length(partnership_details) <= 1000),

  -- Discovery
  discovery_source text check (discovery_source is null or char_length(discovery_source) <= 200),
  referral_contact text check (referral_contact is null or char_length(referral_contact) <= 200),

  -- Agreements (both required to submit)
  terms_accepted boolean not null default false check (terms_accepted = true),
  contact_consent boolean not null default false check (contact_consent = true),

  -- Spam trap: must always arrive empty. A filled honeypot fails this check,
  -- rejecting the insert outright with a generic Postgres error.
  hp_field text check (hp_field is null or char_length(hp_field) = 0),

  -- Review lifecycle (admin-only fields; never selectable by anon/authenticated)
  status text not null default 'pending' check (status in ('pending','approved','rejected','waitlisted')),
  review_notes text,
  reviewer_id uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,

  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.ambassador_applications is
  'Public Ambassador Program applications from the marketing website. Admin-only read via Supabase dashboard / service role until a dedicated admin system is built.';

-- Atomic duplicate-active-application prevention: only one PENDING application
-- per email at a time. A second insert attempt with the same email raises a
-- unique_violation (23505), which the client catches and shows a neutral
-- "already under review" message for.
create unique index ambassador_applications_pending_email_idx
  on public.ambassador_applications (lower(email))
  where status = 'pending';

-- Review-queue indexes.
create index ambassador_applications_status_submitted_idx
  on public.ambassador_applications (status, submitted_at desc);
create index ambassador_applications_email_idx
  on public.ambassador_applications (lower(email));

-- updated_at housekeeping, scoped to this table only.
create or replace function public.set_ambassador_application_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger ambassador_applications_set_updated_at
  before update on public.ambassador_applications
  for each row
  execute function public.set_ambassador_application_updated_at();

alter table public.ambassador_applications enable row level security;

-- Public (anon) may INSERT only. No select/update/delete policies exist for
-- anon or authenticated, so those actions are impossible with the publishable
-- key — only service role / dashboard access can read applications.
create policy "ambassador_applications: anon insert only"
  on public.ambassador_applications
  for insert
  to anon
  with check (true);
