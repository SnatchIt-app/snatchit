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
--     doors_at timestamptz, age_restriction text, status text, timezone text,
--     starts_at_local text, doors_at_local text). The last three were appended
--     2026-10-26 at A's request (US all-in display fold-in, before 182 was ever
--     applied): timezone = 162's catalog.venue.timezone; *_local =
--     to_char(x AT TIME ZONE venue.timezone, 'YYYY-MM-DD HH24:MI') — the SAME
--     expression get_primary_session's session object uses, so a list row and
--     its detail never disagree; NULL when the instant is NULL (doors_at is
--     optional). AT TIME ZONE on a timestamptz yields a zone-local timestamp, so
--     the strings do not depend on the caller's session TimeZone (252 L19 pins
--     it under Asia/Tokyo). One row per session a buyer may buy into RIGHT NOW:
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
--                        on_sale_now, remaining, buyer_fee_minor,
--                        all_in_price_minor}, …]   ('[]' when none)
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
--     buyer_fee_minor / all_in_price_minor — US all-in display (A, 2026-10-26).
--     NOT a second fee model: the rate is read and gated, and the amount
--     rounded, with venue.create_primary_checkout's OWN expressions
--     (093_primary_ticketing.sql), copied character for character because a
--     money body is out of scope here and cannot be refactored onto a helper:
--       rate read    093:4091-4094  select (c.value #>> '{}')::numeric
--                                     from catalog.platform_config c
--                                    where c.key = 'fee.buyer_service_bps'
--                                    order by c.version desc limit 1
--       gates        093:4104-4112  NULL -> service_fee_unset;
--                                   < 0 or > 10000 or <> trunc(..) ->
--                                   service_fee_out_of_range
--       amount       093:4163-4164  round(v_total::numeric * v_fee_bps / 10000)::integer
--                                   (numeric round = half away from zero =
--                                   half-up for a non-negative total, 093:4159-4162)
--                                   charge_total = v_total + fee
--     Here v_total = tt.price_minor × 1, so per tier:
--       buyer_fee_minor    = round(price_minor::numeric * bps / 10000)::integer
--       all_in_price_minor = price_minor + buyer_fee_minor
--     = exactly the buyer_fee_minor / charge_total_minor create_primary_checkout
--     returns for a ONE-UNIT order of that tier (252 F5-F11 call checkout for
--     real on the same clone and compare, including a .5-cent boundary).
--     BOTH NULL whenever checkout would refuse to quote on the rate: unset
--     (JSON null or no row — 093 seeds it null), out of range, fractional, or a
--     value that is not numeric text at all. That last case is the one place
--     the read is gentler than checkout: checkout's cast raises 22P02 there (it
--     refuses either way), a discovery read must not take the whole detail
--     down with it, so the text is pre-checked with pg_input_is_valid(...,
--     'numeric') (PG 16+; CI/production are 17) and an unparseable value reads
--     NULL. For every value the cast accepts, the expression is identical.
--     And the read casts ONLY the top version's text. Checkout's own read
--     casts in the select list of an ORDER BY ... LIMIT 1 query, which on a
--     seq-scan plan is evaluated for EVERY historical row of the key: once a
--     non-numeric value has ever been written (the table is append-only),
--     checkout raises 22P02 under a valid top version or not, depending on
--     the plan (EVIDENCE-182b, checkout_cast_plan_dependence.txt). FLAGGED for
--     A (money path, not touched here); in that state this read shows the top
--     version's fee while checkout may refuse.
--     Never a default, never zero for "unknown" (A5: no percentage is invented).
--     QUANTITY 1 ONLY — SAID PLAINLY: checkout rounds the fee ONCE PER ORDER on
--     Σ(price × qty) across all items (093:4152, 4163), not per unit. So
--     n × all_in_price_minor is NOT the charge for n units whenever the unit
--     fee has a fractional cent ≥ .5 (1005 at 1000 bps: unit all-in 1106, but
--     two units charge round(201.0) + 2010 = 2211, not 2212 — 252 F12 pins it
--     against checkout), and the per-tier figures of a mixed-tier cart do not
--     sum to its charge either. A client must quote a multi-unit or multi-tier
--     total from checkout's own charge_total_minor, never by multiplying.
--     DISCLOSURE: the config row stays visibility 'restricted', but anyone who
--     can read a price and its fee can now derive the rate (fee/price). That is
--     inherent to all-in display (checkout already shows it to every buyer);
--     flagged for A, not hidden.
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
--     timestamptz, atoms_issued integer, payment_state text, charge_total_minor
--     integer) from venue."order"
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
--     charge_total_minor — THE ALL-IN AMOUNT ACTUALLY CHARGED (A, 2026-10-26;
--       appended LAST, before 182 was ever applied). total_minor stays FACE
--       value (093:4168-4178: "no column on venue."order" ever carries" the
--       buyer fee); the only place the database stores the charged all-in
--       amount is public.payments.total, which the primary-checkout edge writes
--       from create_primary_checkout's charge_total_minor (amount = face,
--       buyer_fee = fee, total = the charge — supabase/functions/primary-
--       checkout/index.ts:1196-1210; finalize re-checks total >= face at
--       085:1919-1934). So charge_total_minor = public.payments.total of the
--       SAME link payment_state reads (kernel.payment_native, newest link) —
--       one lateral row feeds both columns, so they can never describe two
--       different payments. No link → NULL. Every pending order therefore
--       reads NULL (the link is written at finalize, 085:2058-2060; the
--       payments row exists from checkout on but carries no order_id — the
--       structural limitation above). It is NEVER recomputed from the current
--       fee.buyer_service_bps: the rate may have changed since the quote, and a
--       recomputed figure would be an invented charge (A's ruling, 2026-10-26).
--       Persisting the charge total (and the PaymentIntent) on the order at
--       checkout is A's C5-1 follow-up, not this read. The value is the
--       PaymentIntent amount the buyer was quoted and charged; WHETHER money
--       moved is payment_state (a refunded payment keeps its total; the
--       synthetic failed/processing links of 252's matrix show the amount that
--       was attempted). It is the only amount a buyer screen may render.
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
--   service_role (all four): EXECUTE by an EXPLICIT GRANT (A's house-posture
--       ruling, 2026-10-26). The posture is the same as 20260909000000's
--       get_my_tickets (proacl {postgres,authenticated,service_role}), but it is
--       no longer INHERITED from pg_default_acl: CI's fresh Supabase stack carries
--       no `public / functions -> service_role=X` default entry, while the local
--       replay template does (scripts/local/replay_shim.sql:489), so the
--       inherited grant existed locally and was ABSENT on CI — 182's post-flight
--       raised there (service_role=f). An explicit `GRANT EXECUTE ... TO
--       service_role` makes the posture independent of whatever default ACL an
--       environment carries (production's is not asserted here): CI = local =
--       production by construction, and where a default entry exists the grant
--       is a no-op. There is no server-side caller: a service_role
--       call of the two owner reads raises 28000 (auth.uid() is NULL) and of the
--       two discovery reads returns the same public rows. The manifest classes
--       ('anon-execute' / 'authenticated-execute') are service_role-agnostic
--       (Part B checks anon, authenticated, PUBLIC and a non-NULL proacl only),
--       so the rows stand unchanged; their comments say the grant is explicit.
--       The post-flight and 252 A8-A11 PIN this posture so it is read, not assumed.
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
-- the public_sale-only test fails. Fee fold-in (EVIDENCE-182b): half-even
-- rounding → F9 fails; truncation → F9 fails; ceil → F11 fails; drop the
-- range gate → F3 fails; default an unset rate to 0 → F1 fails; list
-- *_local under the session TimeZone (::timestamp) → L19 fails.
--
-- VERIFICATION (after apply):
--   select proname, prosecdef, provolatile, proconfig, proacl from pg_proc
--    where pronamespace = 'public'::regnamespace
--      and proname in ('list_primary_sessions_on_sale','get_primary_session',
--                      'get_my_ticket_atoms','get_my_primary_orders');
--   -- 4 rows; prosecdef t; provolatile s; proconfig {search_path=""};
--   -- proacl = {postgres, anon, authenticated, service_role}=X for the first two,
--   -- {postgres, authenticated, service_role}=X for the last two (service_role = the explicit
--   -- grant; entry order may differ where the default ACL already supplied it).
--   select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
--      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');  -- 130 (was 126)
--   -- md5(prosrc) of the four bodies as applied (the rollback's G1 targets):
--   --   list_primary_sessions_on_sale  7a3fcb91976cdd31b32be4e192d09437
--   --   get_primary_session            5c2f3321170798edd277ef0d639c45e3
--   --   get_my_ticket_atoms            8f142e0d4f47d197d633d13c33e70312
--   --   get_my_primary_orders          3a098366bfa9b58a22214718d2f21c30
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
  status          text,
  timezone        text,
  starts_at_local text,
  doors_at_local  text
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
         e.status,
         v.timezone,
         -- the get_primary_session session-object expression, verbatim
         to_char(s.starts_at at time zone v.timezone, 'YYYY-MM-DD HH24:MI') as starts_at_local,
         to_char(s.doors_at  at time zone v.timezone, 'YYYY-MM-DD HH24:MI') as doors_at_local
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
  'Drafts, announced, completed and cancelled events and cancelled/completed sessions are never listed. age_restriction = catalog.event.age_policy (NULL = not specified); status = the event status; '
  'timezone = catalog.venue.timezone, starts_at_local / doors_at_local = the instants in that zone (YYYY-MM-DD HH24:MI, NULL when the instant is NULL). '
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
                                               and b.release_kind     = 'public_sale'), 0)::integer,
                 -- US all-in display: venue.create_primary_checkout's fee for a
                 -- ONE-UNIT order of this tier (093:4163-4164 with v_total =
                 -- price_minor); NULL while the rate is unset / refused (fee.bps NULL).
                 'buyer_fee_minor',    round(tt.price_minor::numeric * fee.bps / 10000)::integer,
                 'all_in_price_minor', tt.price_minor + round(tt.price_minor::numeric * fee.bps / 10000)::integer
               )
               order by tt.display_rank asc nulls last, tt.price_minor asc, tt.name asc)
        from venue.ticket_type tt
       where tt.event_id = e.event_id
         and tt.visibility = 'public'
    ), '[]'::jsonb) as ticket_types
  from catalog.event_session s
  join catalog.event e on e.event_id = s.event_id
  join catalog.venue v on v.venue_id = e.venue_id
  -- the buyer service fee rate, read as venue.create_primary_checkout reads it
  -- (093:4091-4094: highest version wins, `#>> '{}'` maps the seeded JSON null
  -- to SQL NULL) and gated as it gates (093:4104-4112): any value checkout would
  -- refuse to quote on reads NULL here. pg_input_is_valid only turns checkout's
  -- 22P02 (non-numeric text) into NULL instead of an error (see the header).
  cross join lateral (
    select case when r.bps is null
                  or r.bps < 0 or r.bps > 10000 or r.bps <> trunc(r.bps) then null
                else r.bps
           end as bps
      from (select case when pg_input_is_valid(cfg.txt, 'numeric') then cfg.txt::numeric end as bps
              from (select (select c.value #>> '{}'
                              from catalog.platform_config c
                             where c.key = 'fee.buyer_service_bps'
                             order by c.version desc limit 1) as txt) cfg) r
  ) fee
 where s.session_id = p_session_id
   and e.status in ('on_sale', 'live', 'completed')
   and s.status <> 'cancelled'
   and v.approval_status = 'approved'
$$;

comment on function public.get_primary_session(uuid) is
  '182 (C1): buyer detail of one session — (session, event, venue, ticket_types) jsonb; ticket_types = public tiers only with price_minor, currency, visibility, display_rank, sale window, on_sale_now and remaining (= SUM(capacity-held-sold) over public_sale batches of this session; capacity/held/sold never returned). '
  'buyer_fee_minor / all_in_price_minor = what venue.create_primary_checkout charges for ONE unit of the tier (same rate read, gates and half-up rounding; the fee is rounded per order, so never multiply for n units); both NULL while fee.buyer_service_bps is unset or refused. '
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
  payment_state text,
  charge_total_minor integer
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
         coalesce(case lp.status
                    when 'pending'    then 'processing'
                    when 'processing' then 'processing'
                    when 'succeeded'  then 'succeeded'
                    when 'refunded'   then 'succeeded'
                    when 'failed'     then 'failed'
                    else 'none'
                  end, 'none')                                    as payment_state,
         -- the all-in amount charged = payments.total of the SAME link (the
         -- edge writes total = charge_total_minor, index.ts:1204); no link ->
         -- NULL, never recomputed from the current rate (see the header).
         lp.total                                                 as charge_total_minor
    from venue."order" o
    left join lateral (select p.status, p.total
                         from kernel.payment_native pn
                         join public.payments p on p.id = pn.payment_id
                        where pn.order_id = o.order_id
                        order by pn.linked_at desc, pn.id desc
                        limit 1) lp on true
   where o.buyer_id         = v_uid
     and o.event_session_id = p_event_session_id
   order by o.created_at desc, o.order_id asc;
end;
$$;

comment on function public.get_my_primary_orders(uuid) is
  '182 (C5): the caller''s own primary orders for one session — binds to auth.uid() (0 rows for others; NULL uid raises 28000 orders_unauthenticated). status = raw venue.order status; atoms_issued = atoms minted for the order (kernel.ticket_ownership_log sequence-1 issue row -> venue.order_item.id); '
  'payment_state none|processing|succeeded|failed from public.payments via kernel.payment_native (refunded -> succeeded; no link -> none). payment_native is written at finalize, so a pending order reads none (no payment linked yet, not "unpaid"). '
  'charge_total_minor = public.payments.total of that same link (the all-in amount charged: face + buyer fee; total_minor stays face); NULL while no payment is linked (every pending order) — never recomputed from the current fee rate. EXECUTE authenticated only.';

-- ============================================================================
-- PART 5 — function ACLs (I-7: strip PUBLIC/anon/authenticated, then grant exactly;
-- service_role explicit on all four — A's house-posture ruling, never left to a default ACL)
-- ============================================================================
revoke all on function public.list_primary_sessions_on_sale() from public, anon, authenticated;
grant execute on function public.list_primary_sessions_on_sale() to anon, authenticated;
grant execute on function public.list_primary_sessions_on_sale() to service_role;

revoke all on function public.get_primary_session(uuid) from public, anon, authenticated;
grant execute on function public.get_primary_session(uuid) to anon, authenticated;
grant execute on function public.get_primary_session(uuid) to service_role;

revoke all on function public.get_my_ticket_atoms(uuid) from public, anon, authenticated;
grant execute on function public.get_my_ticket_atoms(uuid) to authenticated;
grant execute on function public.get_my_ticket_atoms(uuid) to service_role;

revoke all on function public.get_my_primary_orders(uuid) from public, anon, authenticated;
grant execute on function public.get_my_primary_orders(uuid) to authenticated;
grant execute on function public.get_my_primary_orders(uuid) to service_role;

-- ============================================================================
-- POST-FLIGHT — refuse to COMMIT unless the four functions carry exactly the
-- decided posture (anon as decided, authenticated, service_role's explicit grant,
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
    -- v_svc TRUE = PART 5's explicit service_role grant (the get_my_tickets posture; see GRANT DECISIONS)
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
