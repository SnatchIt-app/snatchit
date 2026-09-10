# Venue dashboard slice 1 — hosted acceptance procedure (copy-ready)

Scope: prove on a **hosted Supabase project** what the local auth stub cannot — real login, token
and cookie refresh, JWT verification, `venue_api` exposure, cross-tenant denial, logout — for the
code frozen at `ae2e2ea8528db37b3b416d5192cb18e3e6192bad` (branch `venue/read-adapters-slice-1`).

**Do not run this against production.** Target: the shared sandbox `ofaidukbieeekqaboscm`, only
after Claude C's D5 work is finished and Claude A has reviewed the migration. Every step below
is either read-only, or explicitly marked **MUTATION** with its reversal in §8. Nothing here
enables a feature flag, deploys an edge function, or touches AWS.

Notation: `<REF>` = project ref (`ofaidukbieeekqaboscm`), `<URL>` = `https://<REF>.supabase.co`,
`<ANON>` = the project's anon/publishable key (public; never the service-role key).

---

## 0. Preconditions (read-only, SQL editor)

```sql
-- 0.1 ledger: 076–092 present, our migration absent, no duplicate versions
select version, name from supabase_migrations.schema_migrations
 where version between '076' and '092' or version like '2026091%' order by version;
select version, count(*) from supabase_migrations.schema_migrations group by 1 having count(*) > 1;
-- 0.2 substrate shape
select count(*) as views from pg_views where schemaname = 'venue_api';          -- expect 0 before §1
select (select count(*) from catalog.venue)  venues,
       (select count(*) from venue.staff_role) staff,
       (select count(*) from kernel.org_member) members;                          -- note the numbers
-- 0.3 flags stay dark (informational; nothing here changes them)
select key, value from catalog.platform_config where key like 'feature.%' order by key;
```

```bash
# 0.4 API exposure today (expect 406 PGRST106 for venue_api; 404 for public)
curl -s -o /dev/null -w '%{http_code}\n' -H "apikey: <ANON>" -H "Accept-Profile: venue_api" "<URL>/rest/v1/nonexistent"
# 0.5 JWT signing: record the algorithm the project uses (see §5.2)
curl -s "<URL>/auth/v1/.well-known/jwks.json"
```

Stop if 0.1 shows 076–092 missing or duplicated, or 0.2 shows `views > 0`.

---

## 1. Apply the migration — **MUTATION** (owner/Claude A, SQL editor)

Paste `supabase/migrations/20260910120000_venue_api_read_views.sql` verbatim (one transaction),
then record the ledger row exactly as the repo names it:

```sql
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260910120000', 'venue_api_read_views', '{}') on conflict do nothing;
-- verify
select count(*) from pg_views where schemaname = 'venue_api';                                   -- 8
select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'venue_api' and c.relkind = 'v'
   and not exists (select 1 from unnest(c.reloptions) o where o = 'security_invoker=true');      -- 0 rows
select has_schema_privilege('anon', 'venue_api', 'USAGE');                                        -- f
```

Reversal: `supabase/rollbacks/20260910120000_venue_api_read_views_rollback.sql` + delete the ledger row.

---

## 2. Expose `venue_api` — **MUTATION** (Dashboard → Integrations → Data API → Settings → Exposed schemas)

Add **`venue_api`** only. Do not add `catalog` or `venue`. Verify:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H "apikey: <ANON>" -H "Accept-Profile: venue_api" "<URL>/rest/v1/nonexistent"   # 404 (was 406)
curl -s -w ' %{http_code}\n' -H "apikey: <ANON>" -H "Accept-Profile: venue_api" "<URL>/rest/v1/events?select=event_id"       # 42501 … 401 (anon has no USAGE)
curl -s -o /dev/null -w '%{http_code}\n' -H "apikey: <ANON>" -H "Accept-Profile: catalog" "<URL>/rest/v1/event"              # still 406
```

Reversal: remove `venue_api` from the list.

---

## 3. Synthetic fixtures — **MUTATION**, exact requirements (do not create yet)

Four auth users, two organizations, two approved venues, three events, two ticket types, two
batches, three grants. All ids are fixed so §8 can remove exactly them. Emails use a domain the
team controls (`+` addresses are fine); passwords are chosen by the person running this and typed
into the Dashboard — **never pasted into chat or a file**.

### 3.1 Auth users — Dashboard → Authentication → Users → Add user → Create new user, **Auto Confirm User** ticked

| Email | Purpose |
|---|---|
| `venue.manager.a+hosted@<team-domain>` | venue_manager at Venue A |
| `org.owner.a+hosted@<team-domain>` | org_owner of Org A (sees drafts) |
| `venue.finance.b+hosted@<team-domain>` | venue_finance at Venue B (cross-tenant probe) |
| `outsider+hosted@<team-domain>` | authenticated, **no grant** (entry-denial probe) |

After creation, copy each user's UUID from the Users list into the SQL below.

### 3.2 Rows — SQL editor (as the editor's postgres role; direct inserts are the sanctioned path for
synthetic data only — see the note after the block)

```sql
begin;
insert into kernel.organization (org_id, legal_name, display_name, status) values
  ('5a4d0b0e-0000-4000-8000-00000000000a', 'Hosted Acceptance Org A (synthetic)', 'Hosted Acceptance Org A', 'active'),
  ('5a4d0b0e-0000-4000-8000-00000000000b', 'Hosted Acceptance Org B (synthetic)', 'Hosted Acceptance Org B', 'active');
insert into catalog.venue (venue_id, org_id, name, neighborhood, address, capacity_hint, approval_status) values
  ('5a4d0b0e-0000-4000-8000-0000000000aa', '5a4d0b0e-0000-4000-8000-00000000000a', 'Hosted Acceptance Room A (synthetic)', 'wynwood',  '1 Synthetic St',  500, 'approved'),
  ('5a4d0b0e-0000-4000-8000-0000000000bb', '5a4d0b0e-0000-4000-8000-00000000000b', 'Hosted Acceptance Room B (synthetic)', 'brickell', '2 Synthetic Ave', 300, 'approved');
insert into kernel.org_member (org_id, identity_id, role) values
  ('5a4d0b0e-0000-4000-8000-00000000000a', '<UUID org.owner.a>', 'org_owner');
insert into venue.staff_role (venue_id, identity_id, role) values
  ('5a4d0b0e-0000-4000-8000-0000000000aa', '<UUID venue.manager.a>', 'venue_manager'),
  ('5a4d0b0e-0000-4000-8000-0000000000bb', '<UUID venue.finance.b>', 'venue_finance');
insert into catalog.event (event_id, venue_id, org_id, title, status) values
  ('5a4d0b0e-0000-4000-8000-0000000000e1', '5a4d0b0e-0000-4000-8000-0000000000aa', '5a4d0b0e-0000-4000-8000-00000000000a', 'Hosted Acceptance Night A (synthetic, on sale)', 'on_sale'),
  ('5a4d0b0e-0000-4000-8000-0000000000e2', '5a4d0b0e-0000-4000-8000-0000000000aa', '5a4d0b0e-0000-4000-8000-00000000000a', 'Hosted Acceptance Draft A (synthetic)',        'draft'),
  ('5a4d0b0e-0000-4000-8000-0000000000e3', '5a4d0b0e-0000-4000-8000-0000000000bb', '5a4d0b0e-0000-4000-8000-00000000000b', 'Hosted Acceptance Night B (synthetic, announced)', 'announced');
insert into catalog.event_session (session_id, event_id, starts_at, doors_at, status) values
  ('5a4d0b0e-0000-4000-8000-0000000000f1', '5a4d0b0e-0000-4000-8000-0000000000e1', now() + interval '3 days',  now() + interval '3 days' - interval '1 hour', 'scheduled'),
  ('5a4d0b0e-0000-4000-8000-0000000000f2', '5a4d0b0e-0000-4000-8000-0000000000e2', now() + interval '30 days', null, 'scheduled'),
  ('5a4d0b0e-0000-4000-8000-0000000000f3', '5a4d0b0e-0000-4000-8000-0000000000e3', now() + interval '10 days', null, 'scheduled');
insert into venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) values
  ('5a4d0b0e-0000-4000-8000-000000000011', '5a4d0b0e-0000-4000-8000-0000000000e1', 'admission', 'General admission (synthetic)', 2500, 'public'),
  ('5a4d0b0e-0000-4000-8000-000000000012', '5a4d0b0e-0000-4000-8000-0000000000e1', 'admission', 'Hidden early bird (synthetic)', 1800, 'hidden');
insert into venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) values
  ('5a4d0b0e-0000-4000-8000-000000000021', '5a4d0b0e-0000-4000-8000-000000000011', '5a4d0b0e-0000-4000-8000-0000000000f1', 'public_sale', 300, 6, 120),
  ('5a4d0b0e-0000-4000-8000-000000000022', '5a4d0b0e-0000-4000-8000-000000000012', '5a4d0b0e-0000-4000-8000-0000000000f1', 'presale',     100, 0, 100);
commit;
```

Why direct inserts: `venue.grant_staff_role` / `kernel.invite_org_member` exist but live in
schemas the Data API does not expose, so they cannot be called with a user token from outside
the SQL editor, and the first `org_owner` of an organization has no client path at all. This is
a real gap for production onboarding (flagged in the handoff), not something this procedure works
around by exposing `venue`.

---

## 4. App configuration (no deploy: run the frozen commit locally or on a preview)

```
NEXT_PUBLIC_VENUE_DATA_SOURCE=database
NEXT_PUBLIC_SUPABASE_URL=<URL>
NEXT_PUBLIC_SUPABASE_ANON_KEY=<ANON>
NEXT_PUBLIC_ENV_LABEL=sandbox
```

`cd venue && npm ci && npm run dev` → http://localhost:3300. Confirm the strip is **blue** and
reads `Database (sandbox) — <REF>.supabase.co`. A service-role key in the anon slot must make every
page show "Database mode is not configured … refusing" (negative check, optional).

Routes used below: `A = /o/5a4d0b0e-0000-4000-8000-00000000000a/v/5a4d0b0e-0000-4000-8000-0000000000aa`,
`B = /o/5a4d0b0e-0000-4000-8000-00000000000b/v/5a4d0b0e-0000-4000-8000-0000000000bb`.

---

## 5. Acceptance checks

Record each result as PASS/FAIL with the observed text or HTTP code. Passwords are typed by the
tester; never share tokens in chat.

### 5.1 Real login (H1)
1. Open `A/events` signed out → **"Sign in to continue"**.
2. Sign in as `venue.manager.a` → `A/events` shows "Hosted Acceptance Night A … 174 available" and
   "Hosted Acceptance Draft A … no releases yet"; strip says **Capabilities come from your grants:
   Venue manager**; header shows the email and **Sign out**; no **Create event** button.
3. `A/events/5a4d0b0e-0000-4000-8000-0000000000e1` → status On sale, "Status changes are not
   available in database mode", both ticket types (incl. hidden), no gross/sold tiles.
4. `…/inventory` → remaining-only note, "174 available" and "0 available", no Release form.
5. `…/attendees` and `…/door` → "not wired to the database yet".

### 5.2 JWT verification / JWKS (H2)
1. From §0.5: if `keys` is non-empty the project signs with an asymmetric key and `getClaims()`
   verifies locally against JWKS; if empty (HS256), supabase-js falls back to `GET /auth/v1/user`.
   Record which.
2. Decode the session cookie's access token header (`sb-<REF>-auth-token`, base64url JSON; read
   only the `alg`/`kid`, never share the token): record `alg`.
3. Negative: edit one character of the cookie value in DevTools → reload `A/events` → must render
   **"Sign in to continue"** (tampered token rejected), never data.

### 5.3 Token and cookie refresh (H3)
Option A (no settings change): note `exp` from the token payload; wait until after it; reload
`A/events` → data still renders **and** the cookie value changed (refresh happened server-side).
Option B (faster, sandbox only, **MUTATION**, reversible): Authentication → Sessions → JWT expiry
→ 120 s; sign in, wait 3 minutes, reload → same expectation; restore the previous value afterwards.
Also: Authentication → Users → the manager → **Sign out user everywhere** (revokes the refresh
token) → reload → **"Sign in to continue"**.

### 5.4 `venue_api` exposure and projection (H4) — curl with the manager's real token
Obtain a token by signing in through the app and reading it from the cookie, **or**
`POST <URL>/auth/v1/token?grant_type=password` from the tester's own machine. Then:

```bash
T=<manager access token>   # keep in a shell variable only
q() { curl -s -w ' [%{http_code}]' -H "apikey: <ANON>" -H "Authorization: Bearer $T" -H "Accept-Profile: venue_api" "<URL>/rest/v1/$1"; echo; }
q "events?venue_id=eq.5a4d0b0e-0000-4000-8000-0000000000aa&select=title,status"      # 2 rows incl. draft
q "ticket_types?event_id=eq.5a4d0b0e-0000-4000-8000-0000000000e1&select=name,visibility" # 2 rows incl. hidden
q "inventory_batches?select=batch_id,remaining"                                          # remaining only
q "inventory_batches?select=capacity"                                                   # 42703 [400]
q "my_staff_roles" ; q "my_org_roles"                                                    # own rows only
```

### 5.5 Cross-tenant denial (H5)
1. Sign out; sign in as `venue.finance.b` → `B/events` shows "Hosted Acceptance Night B … 185
   available"; `A/events` → **"You don't have access to this… holds no staff or organization role
   at this venue"**; `A/events/…e2` (draft) → same denial; `A/events/…e1/inventory` → same.
2. curl with finance B's token: `events?event_id=eq.…e2` → `[]`; `ticket_types?ticket_type_id=eq.…12`
   → `[]`; `inventory_batches?batch_id=eq.…22` → `[]`; `my_staff_roles` → only Venue B.
3. Sign in as `outsider` → `A/events` and `B/events` → the same denial with **Sign out**.
4. Sign in as `org.owner.a` → `A/events` shows both A events; `B/events` → denial (no grant at B).

### 5.6 Logout (H6)
Signed in as any user: click **Sign out** → lands on `/login`; back-navigate to `A/events` →
**"Sign in to continue"**; the `sb-<REF>-auth-token` cookie is gone; Authentication → Users shows
the session ended (last sign-in unchanged, no active session).

### 5.7 No cross-user caching (H7)
In one browser: manager A → `A/events` (two rows) → Sign out → outsider → `A/events` must show
the denial, never the two rows. In a second private window at the same time: finance B → `B/events`
must show B only. Server logs show every request as dynamic (no ISR/route cache hits).

---

## 6. Stop conditions

Any of: data rendered without a session; a draft, hidden type or batch readable by finance B or
the outsider; `capacity` selectable; a tampered token accepted; the denial page revealing an event
title or count; `catalog`/`venue` reachable through the Data API. On a stop: remove `venue_api`
from exposed schemas (§2 reversal) — that alone closes the surface — then run §8 and report.

---

## 7. Evidence to record

HTTP codes and bodies from §5.4/§5.5 (tokens redacted), the JWKS answer and `alg` from §5.2, the
before/after cookie change from §5.3, page text (or screenshots) for §5.1/§5.5/§5.6, and the SQL
verification outputs from §1. Add them to `docs/venue-dashboard/SLICE1_HANDOFF.md` under
"Operationally verified".

---

## 8. Cleanup — **MUTATION** (reverse order; only the fixed ids above)

```sql
begin;
delete from venue.inventory_batch  where batch_id in ('5a4d0b0e-0000-4000-8000-000000000021','5a4d0b0e-0000-4000-8000-000000000022');
delete from venue.ticket_type      where ticket_type_id in ('5a4d0b0e-0000-4000-8000-000000000011','5a4d0b0e-0000-4000-8000-000000000012');
delete from catalog.event_session  where session_id like '5a4d0b0e-0000-4000-8000-0000000000f%';
delete from catalog.event          where event_id   like '5a4d0b0e-0000-4000-8000-0000000000e%';
delete from venue.staff_role       where venue_id   in ('5a4d0b0e-0000-4000-8000-0000000000aa','5a4d0b0e-0000-4000-8000-0000000000bb');
delete from kernel.org_member      where org_id     in ('5a4d0b0e-0000-4000-8000-00000000000a','5a4d0b0e-0000-4000-8000-00000000000b');
delete from catalog.venue          where venue_id   in ('5a4d0b0e-0000-4000-8000-0000000000aa','5a4d0b0e-0000-4000-8000-0000000000bb');
delete from kernel.organization    where org_id     in ('5a4d0b0e-0000-4000-8000-00000000000a','5a4d0b0e-0000-4000-8000-00000000000b');
commit;
-- verify: all four counts 0
select (select count(*) from catalog.event where event_id like '5a4d0b0e-%'),
       (select count(*) from catalog.venue where venue_id like '5a4d0b0e-%'),
       (select count(*) from kernel.organization where org_id like '5a4d0b0e-%'),
       (select count(*) from venue.staff_role where venue_id like '5a4d0b0e-%');
```

Then Dashboard → Authentication → Users → delete the four `+hosted` users. If any append-only
guard (`kernel.raise_append_only`) refuses a delete, stop and report the table — do not disable
the trigger. Leave the migration and the `venue_api` exposure in place unless the review says
otherwise; both have documented reversals (§1, §2).
