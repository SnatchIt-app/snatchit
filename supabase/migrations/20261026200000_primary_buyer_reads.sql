-- ============================================================================
-- 20261026200000_primary_buyer_reads.sql — registry 182 (pgTAP 252): the four
-- `public` buyer reads of the primary-ticketing launch — session discovery (A's
-- contract C1) and the owner-scoped ticket-atom / order reads (A's C5) that C's
-- Tickets + QR screen consumes.
--
-- Registry 182 / pgTAP 252 — CONFIRMED by Claude A 2026-10-26 (CONTRACTS.md §4;
-- CONTRACTS-D §3a). D writes, A reviews before this leaves draft, C consumes.
-- DARK: applied nowhere but local rehearsal clones. It exposes no schema, flips
-- no flag, seeds no config key and touches no table, policy or trigger. It DOES
-- create four functions in `public`, which PostgREST serves at /rest/v1/rpc/ the
-- moment it is applied — so the FOUR-FILE RULE is real here (below).
--
-- ORDER: after 162 (20261026100000 — catalog.venue.timezone, catalog.event.
-- age_policy, venue.ticket_type.sale_starts_at/sale_ends_at and
-- venue.ticket_type_on_sale are read here), which itself sits after 159 / 176 /
-- 160 / 161; before 183+ (20261026210000 and later). The pre-flight DO block
-- refuses to run otherwise. Independent of 163 (20261026110000) by object.
-- The definer bodies below read catalog.*, venue.* and kernel.* directly and do
-- NOT depend on 176's public RLS arms (a SECURITY DEFINER body bypasses RLS):
-- every visibility rule is restated in the WHERE clauses, so the functions
-- behave the same whether or not 176 is present.
--
-- WHAT THIS MIGRATION IS (A's shapes, verbatim; CONTRACTS.md §C1/§C5):
--  1. public.list_primary_sessions_on_sale() → rows (event_id uuid, session_id
--     uuid, title text, venue_name text, neighborhood text, starts_at timestamptz,
--     doors_at timestamptz, age_restriction text, status text). One row per
--     session a buyer may buy into RIGHT NOW:
--       · catalog.event.status IN ('on_sale','live') — draft, announced,
--         completed and cancelled events are NEVER listed;
--       · catalog.event_session.status NOT IN ('cancelled','completed');
--       · catalog.venue.approval_status = 'approved' — D's addition for RLS
--         parity: catalog_venue_sel_anon (078:309) hides a non-approved room
--         from anon, and a definer must not widen what anon can read (176's
--         whole reason). publish_event (081:899) does not gate on approval, so
--         an on_sale event at a 'draft'/'pending' room is invisible here until
--         the room is approved — FLAGGED for A / the owner (252 L16 pins it);
--       · at least one tier of the event with visibility = 'public' for which
--         venue.ticket_type_on_sale(tt, now()) is true (162: window contains
--         now(), event on_sale/live) — an event whose public tiers are all
--         outside their windows, or which has only hidden/door_only tiers, is
--         not "on sale" to a buyer and is not listed.
--     age_restriction = catalog.event.age_policy (162; NULL = not specified).
--     status = the EVENT status ('on_sale' | 'live'). Order: starts_at ASC,
--     session_id ASC (tie-break, deterministic). EXECUTE anon + authenticated.
--  2. public.get_primary_session(p_session_id uuid) → ONE row (session jsonb,
--     event jsonb, venue jsonb, ticket_types jsonb) or ZERO rows — never an
--     error and never a {status:'not_found'} row, so an unknown id, a draft or
--     announced event, a cancelled event, a cancelled session or a non-approved
--     room are indistinguishable from "no such session" (no existence leak).
--     Visible iff catalog.event.status IN ('on_sale','live','completed') AND
--     catalog.event_session.status <> 'cancelled' AND venue approved. A
--     completed event stays readable (it is anon-visible in catalog today —
--     078 catalog_event_sel_anon — and its tiers answer on_sale_now = false);
--     'announced' is withheld because nothing is buyable yet (C1: discovery is
--     the on-sale surface) — FLAGGED for A if the detail of an announced event
--     should be readable before its on-sale date.
--       session      = {session_id, event_id, session_label, starts_at, ends_at,
--                       doors_at, status, timezone, starts_at_local,
--                       ends_at_local, doors_at_local}
--       event        = {event_id, title, description, hero_image_ref, category,
--                       genre_tags, status, age_restriction}
--       venue        = {venue_id, name, neighborhood, address, timezone}
--       ticket_types = [{ticket_type_id, name, price_minor, currency,
--                        visibility, display_rank, sale_starts_at, sale_ends_at,
--                        on_sale_now, remaining}, …]   ('[]' when none)
--     ticket_types holds ONLY tiers with visibility = 'public' (hidden and
--     door_only never appear — not even as a count). `remaining` =
--     SUM(capacity − held − sold) over venue.inventory_batch rows of (tier,
--     THIS session) with release_kind = 'public_sale', computed inside this
--     definer body (it equals the 081 generated column `remaining`, summed);
--     comp / door / presale / promoter_hold batches are NOT buyer inventory and
--     are excluded; a public tier with no public_sale batch on the session reads
--     remaining = 0. capacity, held and sold are NEVER serialised (081 E-29
--     column privacy; 252 P10/P16 pin the key set). on_sale_now =
--     venue.ticket_type_on_sale(tt, now()). *_local = to_char(x AT TIME ZONE
--     venue.timezone, 'YYYY-MM-DD HH24:MI') — 162's venue_api format, text,
--     NULL when the instant is NULL. ticket_types order: display_rank ASC NULLS
--     LAST, price_minor ASC, name ASC. EXECUTE anon + authenticated.
--  3. public.get_my_ticket_atoms(p_event_session_id uuid) → rows
--     (ticket_atom_id uuid, serial_no integer, ticket_type_id uuid,
--     ticket_type_name text, state text, resale_state text, credential_version
--     integer, issued_at timestamptz) from kernel.tickets WHERE
--     current_owner_id = auth.uid() AND event_session_id = p_event_session_id,
--     ordered by serial_no. The body binds to auth.uid(): a forged or another
--     buyer's session id yields 0 rows (not an error); auth.uid() NULL raises
--     'tickets_unauthenticated' (SQLSTATE 28000 — the get_my_tickets pattern,
--     20260909000000:117-121). state / resale_state are the RAW kernel
--     vocabularies (issued|active|scanned|voided|expired; none|listed|locked|
--     refund_hold|dispute_hold) — C5 asks for them raw so a credential_version
--     change observed here invalidates C's cached token (A's client rule).
--     EXECUTE authenticated ONLY (anon revoked: denied at the ACL, never served
--     empty). NEVER returned: signing_key_id, current_owner_id (it IS the
--     caller), org_id, seat_ref, unit_row_id, external_seat_ref, home_region,
--     anything from kernel.ticket_ownership_log, any KMS or Stripe reference.
--  4. public.get_my_primary_orders(p_event_session_id uuid) → rows (order_id
--     uuid, status text, total_minor integer, currency text, created_at
--     timestamptz, atoms_issued integer, payment_state text) from venue."order"
--     WHERE buyer_id = auth.uid() AND event_session_id = p_event_session_id,
--     newest first. NULL uid → 'orders_unauthenticated' (28000). status is the
--     raw venue.order status (pending|paid|partially_refunded|refunded|
--     cancelled). EXECUTE authenticated ONLY.
--     atoms_issued — THE REAL ATOM→ORDER LINK (read from 085/093, not invented):
--       venue.finalize_primary_order mints each order item through
--       kernel.issue_ticket_atoms with ctx cause = 'issue' and cause_ref =
--       venue.order_item.id (085:2045-2050); the mint writes one
--       kernel.ticket_ownership_log row per atom with sequence = 1, cause =
--       'issue', cause_ref = that order_item.id (093:5009-5013). finalize
--       itself counts an order's atoms with exactly this predicate for its
--       idempotency replay (085:1966-1970, 2071-2076). So:
--         atoms_issued = count(kernel.tickets t
--                              JOIN kernel.ticket_ownership_log l
--                                ON l.ticket_atom_id = t.ticket_atom_id
--                               AND l.sequence = 1 AND l.cause = 'issue'
--                              JOIN venue.order_item oi ON oi.id = l.cause_ref
--                             WHERE oi.order_id = o.order_id)
--       — every atom ever minted for the order, whoever holds it now (a later
--       transfer does not un-issue it). No approximation.
--     payment_state ∈ none | processing | succeeded | failed, from
--       public.payments.status through kernel.payment_native (payment_native.
--       order_id → payment_id → payments.status; newest link if several):
--         no payment_native row        → 'none'
--         'pending' | 'processing'     → 'processing'
--         'succeeded'                  → 'succeeded'
--         'refunded'                   → 'succeeded'  (the ORDER status tells
--                                        the refund story: refunded /
--                                        partially_refunded)
--         'failed'                     → 'failed'
--     STRUCTURAL LIMITATION — SAID PLAINLY FOR A AND C (brief §4 asked for it):
--       kernel.payment_native is INSERTED BY finalize_primary_order ITSELF
--       (085:2058-2060), i.e. only once the order is 'paid'. Before that
--       instant the database holds NO link from an order to its payment: there
--       is no public.payments.order_id (C4: "never"), and the primary-checkout
--       edge records the order only in the Stripe PaymentIntent's
--       metadata.order_id (supabase/functions/primary-checkout/index.ts:217,
--       280). Consequently EVERY 'pending' order reads payment_state = 'none'
--       here — "no payment is linked in the database", NOT "the buyer did not
--       pay". The C5 wish ("pending = unpaid vs paid-awaiting-webhook, so C can
--       render Issuance pending truthfully") CANNOT be delivered by the schema
--       as it stands; this function delivers the contracted vocabulary over the
--       link that exists and nothing more. 'processing' / 'failed' are reachable
--       only through a payment_native row whose payment later moves to that
--       status (finalize links a 'succeeded' payment; 20260906120000's
--       transition guard governs later moves). C: render (pending, none) as
--       "awaiting payment confirmation", never "unpaid"; A: a pre-finalize link
--       (the edge persisting order_id ↔ payment id, or the webhook writing it
--       before finalize) is the fix, not a wider read here.
--
-- EVERY FUNCTION: SECURITY DEFINER, SET search_path = '' (all references
-- schema-qualified; auth.uid() included), STABLE, LANGUAGE sql for the two
-- anonymous reads (inlinable, no branching) and plpgsql for the two owner reads
-- (the 28000 raise). None takes a user id, owner id or org id. None writes.
--
-- GRANT DECISIONS (I-7: strip, then grant exactly; 20260909000000:193-197):
--   list_primary_sessions_on_sale(), get_primary_session(uuid)
--       REVOKE ALL FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO anon,
--       authenticated. anon is a DELIBERATE grant (discovery is the logged-out
--       surface; the manifest row is 'anon-execute', whose B5 check requires an
--       explicit anon grant, a non-NULL proacl and no PUBLIC entry — all true
--       here).
--   get_my_ticket_atoms(uuid), get_my_primary_orders(uuid)
--       REVOKE ALL FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO
--       authenticated (manifest 'authenticated-execute'). anon is denied at the
--       ACL (42501), never served an empty set.
--   service_role (all four): KEEPS the public-schema DEFAULT EXECUTE. This chain
--       carries pg_default_acl `public / functions / postgres -> anon=X,
--       authenticated=X, service_role=X` (Supabase's ALTER DEFAULT PRIVILEGES),
--       so every function created in public is born with the three; the I-7
--       sequence strips and re-grants anon/authenticated and — exactly as
--       20260909000000's get_my_tickets (proacl {postgres,authenticated,
--       service_role}) and 112 of the 126 public functions today — leaves
--       service_role's default standing. Not revoked here on purpose: deviating
--       from the house posture is A's call, not a side effect of this package
--       (FLAGGED in EVIDENCE-182 §9); there is no server-side caller, a
--       service_role call of the two owner reads raises 28000 (auth.uid() is
--       NULL) and of the two discovery reads returns the same public rows. The
--       post-flight and 252 A8-A11 PIN this posture so it is read, not assumed.
--
-- FOUR-FILE RULE (CLAUDE.md) — REAL for this package, all four touched/read:
--   1. supabase/ci/assert_public_table_grant_decisions.sql — four Part-B rows:
--      two 'anon-execute', two 'authenticated-execute' (this commit series).
--   2. supabase/ci/expected_grants.txt — public TABLE grants only: UNCHANGED
--      (no table grant moves; read, not edited).
--   3. .github/workflows/ci.yml Gate-2 census — EXPECT_FUNCS 126 → 130 (+4
--      public functions; tables 35 / policies 37 / triggers 49 unchanged), dated
--      comment. The same pin lives in pgTAP tests/162 P2 (126 → 130, dated
--      comment, in-repo per the task instruction).
--   4. this rollback: supabase/rollbacks/20261026200000_primary_buyer_reads_
--      rollback.sql — md5-asserts the four live bodies are 182's before
--      dropping them (a later body-replace would otherwise be silently undone),
--      verifies the census returns to 126.
--   venue / catalog / kernel object counts: unchanged (nothing created there).
--
-- NEGATIVE CONTROLS (pgTAP 252 on mutant clones; EVIDENCE-182 §4): drop the
-- current_owner_id = auth.uid() predicate → the cross-buyer test fails; include
-- hidden tiers → the exclusion test fails; serialise capacity → the key-absence
-- test fails; list drafts → the draft test fails; drop buyer_id = auth.uid() →
-- the cross-buyer order test fails; sum remaining over every release_kind →
-- the public_sale-only test fails.
--
-- VERIFICATION (after apply):
--   select proname, prosecdef, provolatile, proconfig, proacl from pg_proc
--    where pronamespace = 'public'::regnamespace
--      and proname in ('list_primary_sessions_on_sale','get_primary_session',
--                      'get_my_ticket_atoms','get_my_primary_orders');
--   -- 4 rows; prosecdef t; provolatile s; proconfig {search_path=""};
--   -- proacl = {postgres, service_role, anon, authenticated}=X for the first two,
--   -- {postgres, service_role, authenticated}=X for the last two (service_role = the kept default).
--   select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
--      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');  -- 130 (was 126)
--   -- md5(prosrc) of the four bodies as applied (the rollback's G1 targets):
--   --   list_primary_sessions_on_sale  93debdf3ad599a263a7e6a208ec7e7c9
--   --   get_primary_session            9bfb318898954b958c07982cc7723835
--   --   get_my_ticket_atoms            8f142e0d4f47d197d633d13c33e70312
--   --   get_my_primary_orders          f0ec61fcf60b8125bcb1a43dc4332de6
-- LOCKS / RUNTIME: four CREATE FUNCTION + grants — catalog rows only,
-- milliseconds; no table is read or written. lock_timeout 3s so it fails
-- cleanly rather than queue behind a long reader.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ============================================================================
-- PRE-FLIGHT — 160 and 162 present; census captured for the post-flight check
-- ============================================================================
CREATE TEMP TABLE _pre182 ON COMMIT DROP AS
  SELECT count(*)::integer AS n_public_fns
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e');

DO $pre$
BEGIN
  IF to_regprocedure('venue.ticket_type_on_sale(uuid, timestamptz)') IS NULL THEN
    RAISE EXCEPTION '182_REFUSED: venue.ticket_type_on_sale (162) is absent; apply 162 first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'catalog.venue'::regclass AND attname = 'timezone' AND NOT attisdropped)
  OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'catalog.event'::regclass AND attname = 'age_policy' AND NOT attisdropped)
  OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'venue.ticket_type'::regclass AND attname = 'sale_starts_at' AND NOT attisdropped) THEN
    RAISE EXCEPTION '182_REFUSED: a 162 column (catalog.venue.timezone / catalog.event.age_policy / venue.ticket_type.sale_starts_at) is absent; apply 162 first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'venue.ticket_type'::regclass AND attname = 'display_rank' AND NOT attisdropped) THEN
    RAISE EXCEPTION '182_REFUSED: venue.ticket_type.display_rank (160) is absent; apply 160 first.';
  END IF;
  IF to_regprocedure('public.list_primary_sessions_on_sale()') IS NOT NULL
  OR to_regprocedure('public.get_primary_session(uuid)') IS NOT NULL
  OR to_regprocedure('public.get_my_ticket_atoms(uuid)') IS NOT NULL
  OR to_regprocedure('public.get_my_primary_orders(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '182_REFUSED: a 182 function already exists in public; this migration creates, it does not replace. Nothing changed.';
  END IF;
END $pre$;

-- ============================================================================
-- PART 1 — public.list_primary_sessions_on_sale()  (C1 discovery; anon + auth)
-- ============================================================================
create function public.list_primary_sessions_on_sale()
returns table (
  event_id        uuid,
  session_id      uuid,
  title           text,
  venue_name      text,
  neighborhood    text,
  starts_at       timestamptz,
  doors_at        timestamptz,
  age_restriction text,
  status          text
)
language sql
stable
security definer
set search_path = ''
as $$
  select e.event_id,
         s.session_id,
         e.title,
         v.name          as venue_name,
         v.neighborhood,
         s.starts_at,
         s.doors_at,
         e.age_policy    as age_restriction,
         e.status
    from catalog.event_session s
    join catalog.event e on e.event_id = s.event_id
    join catalog.venue v on v.venue_id = e.venue_id
   where e.status in ('on_sale', 'live')
     and s.status not in ('cancelled', 'completed')
     and v.approval_status = 'approved'
     and exists (select 1
                   from venue.ticket_type tt
                  where tt.event_id = e.event_id
                    and tt.visibility = 'public'
                    and venue.ticket_type_on_sale(tt.ticket_type_id, now()))
   order by s.starts_at asc, s.session_id asc
$$;

comment on function public.list_primary_sessions_on_sale() is
  '182 (C1): buyer discovery — one row per session of an on_sale/live event at an approved venue with at least one public tier on sale now (venue.ticket_type_on_sale). '
  'Drafts, announced, completed and cancelled events and cancelled/completed sessions are never listed. age_restriction = catalog.event.age_policy (NULL = not specified); status = the event status. '
  'Frontend-safe fields only; no capacity, owner, credential or payment data. EXECUTE anon + authenticated. Order: starts_at asc.';

-- ============================================================================
-- PART 2 — public.get_primary_session(uuid)  (C1 detail; anon + auth; 0 rows =
--          unknown / not buyable — no existence leak)
-- ============================================================================
create function public.get_primary_session(p_session_id uuid)
returns table (
  session      jsonb,
  event        jsonb,
  venue        jsonb,
  ticket_types jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    jsonb_build_object(
      'session_id',      s.session_id,
      'event_id',        s.event_id,
      'session_label',   s.session_label,
      'starts_at',       s.starts_at,
      'ends_at',         s.ends_at,
      'doors_at',        s.doors_at,
      'status',          s.status,
      'timezone',        v.timezone,
      'starts_at_local', to_char(s.starts_at at time zone v.timezone, 'YYYY-MM-DD HH24:MI'),
      'ends_at_local',   to_char(s.ends_at   at time zone v.timezone, 'YYYY-MM-DD HH24:MI'),
      'doors_at_local',  to_char(s.doors_at  at time zone v.timezone, 'YYYY-MM-DD HH24:MI')
    ) as session,
    jsonb_build_object(
      'event_id',        e.event_id,
      'title',           e.title,
      'description',     e.description,
      'hero_image_ref',  e.hero_image_ref,
      'category',        e.category,
      'genre_tags',      to_jsonb(e.genre_tags),
      'status',          e.status,
      'age_restriction', e.age_policy
    ) as event,
    jsonb_build_object(
      'venue_id',        v.venue_id,
      'name',            v.name,
      'neighborhood',    v.neighborhood,
      'address',         v.address,
      'timezone',        v.timezone
    ) as venue,
    coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'ticket_type_id', tt.ticket_type_id,
                 'name',           tt.name,
                 'price_minor',    tt.price_minor,
                 'currency',       tt.currency,
                 'visibility',     tt.visibility,
                 'display_rank',   tt.display_rank,
                 'sale_starts_at', tt.sale_starts_at,
                 'sale_ends_at',   tt.sale_ends_at,
                 'on_sale_now',    venue.ticket_type_on_sale(tt.ticket_type_id, now()),
                 -- buyer inventory of THIS session only: public_sale batches; the
                 -- 081 generated column `remaining` = capacity - held - sold, summed.
                 -- capacity / held / sold themselves are never serialised (E-29).
                 'remaining',      coalesce((select sum(b.capacity - b.held - b.sold)
                                              from venue.inventory_batch b
                                             where b.ticket_type_id   = tt.ticket_type_id
                                               and b.event_session_id = s.session_id
                                               and b.release_kind     = 'public_sale'), 0)::integer
               )
               order by tt.display_rank asc nulls last, tt.price_minor asc, tt.name asc)
        from venue.ticket_type tt
       where tt.event_id = e.event_id
         and tt.visibility = 'public'
    ), '[]'::jsonb) as ticket_types
  from catalog.event_session s
  join catalog.event e on e.event_id = s.event_id
  join catalog.venue v on v.venue_id = e.venue_id
 where s.session_id = p_session_id
   and e.status in ('on_sale', 'live', 'completed')
   and s.status <> 'cancelled'
   and v.approval_status = 'approved'
$$;

comment on function public.get_primary_session(uuid) is
  '182 (C1): buyer detail of one session — (session, event, venue, ticket_types) jsonb; ticket_types = public tiers only with price_minor, currency, visibility, display_rank, sale window, on_sale_now and remaining (= SUM(capacity-held-sold) over public_sale batches of this session; capacity/held/sold never returned). '
  'Local times via catalog.venue.timezone (*_local, YYYY-MM-DD HH24:MI). ZERO rows (no error) for an unknown id, a draft/announced/cancelled event, a cancelled session or a non-approved venue. EXECUTE anon + authenticated.';

-- ============================================================================
-- PART 3 — public.get_my_ticket_atoms(uuid)  (C5; authenticated only; auth.uid())
-- ============================================================================
create function public.get_my_ticket_atoms(p_event_session_id uuid)
returns table (
  ticket_atom_id     uuid,
  serial_no          integer,
  ticket_type_id     uuid,
  ticket_type_name   text,
  state              text,
  resale_state       text,
  credential_version integer,
  issued_at          timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  -- Fail closed (20260909000000 pattern): anon is already blocked at the ACL;
  -- this covers an authenticated role presenting no subject claim.
  if v_uid is null then
    raise exception 'tickets_unauthenticated' using errcode = '28000';
  end if;

  return query
  select t.ticket_atom_id,
         t.serial_no,
         t.ticket_type_id,
         tt.name,
         t.state,
         t.resale_state,
         t.credential_version,
         t.issued_at
    from kernel.tickets t
    join venue.ticket_type tt on tt.ticket_type_id = t.ticket_type_id
   where t.current_owner_id   = v_uid
     and t.event_session_id   = p_event_session_id
   order by t.serial_no asc;
end;
$$;

comment on function public.get_my_ticket_atoms(uuid) is
  '182 (C5): the caller''s own ticket atoms for one session — binds to auth.uid() (another buyer''s or a forged session id yields 0 rows; NULL uid raises 28000 tickets_unauthenticated). '
  'Raw kernel state / resale_state vocabularies and credential_version (a change invalidates the client''s cached credential token). Never returns signing_key_id, owner ids, org_id or seat references. EXECUTE authenticated only.';

-- ============================================================================
-- PART 4 — public.get_my_primary_orders(uuid)  (C5; authenticated only; auth.uid())
-- ============================================================================
create function public.get_my_primary_orders(p_event_session_id uuid)
returns table (
  order_id      uuid,
  status        text,
  total_minor   integer,
  currency      text,
  created_at    timestamptz,
  atoms_issued  integer,
  payment_state text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'orders_unauthenticated' using errcode = '28000';
  end if;

  return query
  select o.order_id,
         o.status,
         o.total_minor,
         o.currency,
         o.created_at,
         -- the real atom->order link: the mint's sequence-1 'issue' ledger row
         -- carries cause_ref = venue.order_item.id (085:2050, 093:5009-5013).
         (select count(*)::integer
            from kernel.tickets t
            join kernel.ticket_ownership_log l
              on l.ticket_atom_id = t.ticket_atom_id
             and l.sequence = 1
             and l.cause = 'issue'
            join venue.order_item oi on oi.id = l.cause_ref
           where oi.order_id = o.order_id)                       as atoms_issued,
         -- payment_native is written by finalize_primary_order (085:2060): a
         -- pre-finalize order has no link and reads 'none' (see the header).
         coalesce((select case p.status
                            when 'pending'    then 'processing'
                            when 'processing' then 'processing'
                            when 'succeeded'  then 'succeeded'
                            when 'refunded'   then 'succeeded'
                            when 'failed'     then 'failed'
                            else 'none'
                          end
                     from kernel.payment_native pn
                     join public.payments p on p.id = pn.payment_id
                    where pn.order_id = o.order_id
                    order by pn.linked_at desc, pn.id desc
                    limit 1), 'none')                             as payment_state
    from venue."order" o
   where o.buyer_id         = v_uid
     and o.event_session_id = p_event_session_id
   order by o.created_at desc, o.order_id asc;
end;
$$;

comment on function public.get_my_primary_orders(uuid) is
  '182 (C5): the caller''s own primary orders for one session — binds to auth.uid() (0 rows for others; NULL uid raises 28000 orders_unauthenticated). status = raw venue.order status; atoms_issued = atoms minted for the order (kernel.ticket_ownership_log sequence-1 issue row -> venue.order_item.id); '
  'payment_state none|processing|succeeded|failed from public.payments via kernel.payment_native (refunded -> succeeded; no link -> none). payment_native is written at finalize, so a pending order reads none (no payment linked yet, not "unpaid"). EXECUTE authenticated only.';

-- ============================================================================
-- PART 5 — function ACLs (I-7: strip PUBLIC/anon/authenticated, then grant exactly)
-- ============================================================================
revoke all on function public.list_primary_sessions_on_sale() from public, anon, authenticated;
grant execute on function public.list_primary_sessions_on_sale() to anon, authenticated;

revoke all on function public.get_primary_session(uuid) from public, anon, authenticated;
grant execute on function public.get_primary_session(uuid) to anon, authenticated;

revoke all on function public.get_my_ticket_atoms(uuid) from public, anon, authenticated;
grant execute on function public.get_my_ticket_atoms(uuid) to authenticated;

revoke all on function public.get_my_primary_orders(uuid) from public, anon, authenticated;
grant execute on function public.get_my_primary_orders(uuid) to authenticated;

-- ============================================================================
-- POST-FLIGHT — refuse to COMMIT unless the four functions carry exactly the
-- decided posture (anon as decided, authenticated, service_role's kept default,
-- no PUBLIC, non-NULL proacl) and the public census moved by exactly +4
-- ============================================================================
DO $post$
DECLARE
  v_pre  integer := (SELECT n_public_fns FROM _pre182);
  v_post integer;
  r      record;
  v_anon boolean; v_auth boolean; v_pub boolean; v_svc boolean;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('public.list_primary_sessions_on_sale()', true),
      ('public.get_primary_session(uuid)',       true),
      ('public.get_my_ticket_atoms(uuid)',       false),
      ('public.get_my_primary_orders(uuid)',     false)) AS x(sig, anon_ok)
  LOOP
    IF to_regprocedure(r.sig) IS NULL THEN
      RAISE EXCEPTION '182_POSTFLIGHT: % was not created', r.sig;
    END IF;
    IF NOT (SELECT p.prosecdef AND p.provolatile = 's' AND p.proconfig = ARRAY['search_path=""']
              FROM pg_proc p WHERE p.oid = to_regprocedure(r.sig)) THEN
      RAISE EXCEPTION '182_POSTFLIGHT: % is not SECURITY DEFINER / STABLE / search_path=''''', r.sig;
    END IF;
    SELECT has_function_privilege('anon',          to_regprocedure(r.sig), 'EXECUTE'),
           has_function_privilege('authenticated', to_regprocedure(r.sig), 'EXECUTE'),
           has_function_privilege('service_role',  to_regprocedure(r.sig), 'EXECUTE'),
           EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
                    WHERE p.oid = to_regprocedure(r.sig) AND a.grantee = 0 AND a.privilege_type = 'EXECUTE')
      INTO v_anon, v_auth, v_svc, v_pub;
    -- v_svc TRUE = the public-schema default ACL kept (the get_my_tickets posture; see GRANT DECISIONS)
    IF v_pub OR NOT v_svc OR NOT v_auth OR (v_anon <> r.anon_ok) THEN
      RAISE EXCEPTION '182_POSTFLIGHT: ACL of % is not the decided posture (anon=% expected %, authenticated=%, service_role=% expected t, PUBLIC=%)',
        r.sig, v_anon, r.anon_ok, v_auth, v_svc, v_pub;
    END IF;
    IF (SELECT proacl FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS NULL THEN
      RAISE EXCEPTION '182_POSTFLIGHT: proacl of % is DEFAULTED (PUBLIC EXECUTE)', r.sig;
    END IF;
  END LOOP;

  SELECT count(*)::integer INTO v_post
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e');
  IF v_post <> v_pre + 4 THEN
    RAISE EXCEPTION '182_POSTFLIGHT: public function census moved % -> % (expected +4)', v_pre, v_post;
  END IF;
  RAISE NOTICE '182 applied: public functions % -> % (Gate-2 EXPECT_FUNCS 126 -> 130 on the certified chain).', v_pre, v_post;
END $post$;

COMMIT;
