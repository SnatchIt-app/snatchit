# Pre-migration snapshot — 040_web_accounts_foundation

Captured 2026-07-29, immediately before applying migration 040 to the
production project (`hqycwntpfoztoinemqns`). Schema/definition evidence
only — no row data. Purpose: prove post-migration that every existing
object referenced by 040 (`profiles`, `auth.users` trigger, `listings`)
was left byte-for-byte identical.

## Pre-flight: target tables do not already exist

```sql
select table_name from information_schema.tables
where table_schema='public' and table_name in ('saved_listings','notifications');
-- → [] (empty, confirmed clean)
```

## public.profiles — 21 columns (unchanged from prior audit)

id (uuid, NOT NULL) · created_at (timestamptz, default now()) · full_name
(text) · phone (text, legacy/unused) · display_name (text) · phone_number
(text) · avatar_url (text, legacy) · avatar_path (text) · is_verified_buyer
(bool, default false) · is_verified_seller (bool, default false) ·
wallet_balance (numeric, default 0) · bio (text) · stripe_connect_id (text)
· stripe_connect_status (text, default 'not_started') ·
stripe_payouts_enabled (bool, default false) · stripe_charges_enabled
(bool, default false) · is_admin (bool, default false) ·
trust_status_override (text) · preferred_neighborhoods (text[]) ·
stripe_onboarding_complete (bool, default false) · stripe_customer_id
(text)

## public.profiles — constraints (12)

```
profiles_bio_len_check          CHECK (bio IS NULL OR char_length(bio) <= 200)
profiles_bio_length             CHECK (bio IS NULL OR char_length(bio) <= 200)
profiles_display_name_len_check CHECK (display_name IS NULL OR char_length(display_name) <= 50)
profiles_display_name_length    CHECK (display_name IS NULL OR char_length(display_name) <= 50)
profiles_full_name_len_check    CHECK (full_name IS NULL OR char_length(full_name) <= 100)
profiles_full_name_length       CHECK (full_name IS NULL OR char_length(full_name) <= 100)
profiles_id_fkey                FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
profiles_phone_number_len_check CHECK (phone_number IS NULL OR char_length(phone_number) <= 20)
profiles_phone_number_length    CHECK (phone_number IS NULL OR char_length(phone_number) <= 20)
profiles_pkey                   PRIMARY KEY (id)
profiles_stripe_customer_id_key UNIQUE (stripe_customer_id)
profiles_trust_status_override_check CHECK (trust_status_override = ANY (ARRAY['verified','at_risk','restricted']))
```
(Duplicate-looking pairs like `*_len_check`/`*_length` are pre-existing
from migration history, not introduced here — noted for the record.)

## public.profiles — RLS policies (5)

```
"profiles: public read"  SELECT  USING (true)
profiles_insert_own      INSERT  WITH CHECK (id = auth.uid())
profiles_select_all      SELECT  USING (true)
profiles_select_own      SELECT  USING (id = auth.uid())
profiles_update_own      UPDATE  USING (id = auth.uid()) WITH CHECK (id = auth.uid())
```
(Pre-existing overlap between `profiles: public read`/`profiles_select_all`
and `profiles_select_own` — historical, not touched.)

## auth.users trigger — on_auth_user_created (enabled: 'O' = origin/normal)

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  insert into public.profiles (id, full_name, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'avatar_url', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$function$
```

## public.listings — FK target column

```
id  uuid  NOT NULL
```

## Post-migration diff plan

Re-run the exact same five queries after `apply_migration` and confirm
byte-identical output for all five, plus confirm `saved_listings` and
`notifications` now appear with the expected shape.
