-- Add preferred_neighborhoods column to profiles for "Your Scene" feature.
-- Stores the user's selected nightlife neighborhoods as a text array.
-- Safe to re-run: uses IF NOT EXISTS.

alter table public.profiles
  add column if not exists preferred_neighborhoods text[] not null default '{}';
