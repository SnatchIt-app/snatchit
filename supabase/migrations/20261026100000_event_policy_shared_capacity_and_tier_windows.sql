-- ============================================================================
-- 20261026100000_event_policy_shared_capacity_and_tier_windows.sql — S2 event
-- policy (DB slice): venue timezone, event age policy, a per-session sales
-- capacity shared by every batch of the session, tier sale windows + the
-- on-sale predicate, local-time projections in venue_api, the venue_cmd
-- wrappers, and A's R3 ruling on the ORG arm of the six venue.* tier/inventory
-- writers (body-only replaces of 160's bodies).
--
-- Registry 162 / pgTAP 229 — assigned by Claude A 2026-10-26 (CONTRACTS.md §4).
-- A reviews before this leaves draft. DARK: applied nowhere (local rehearsal
-- clones only); exposes no schema, flips no flag, seeds no config key. venue_api
-- and venue_cmd stay unexposed (owner setting). No PFA control is bypassed; no
-- disabled reader is exposed; the purchase path (reserve_primary_inventory,
-- create_primary_checkout) is NOT touched — the purchase-time call of
-- venue.ticket_type_on_sale is A's (migration 185, CONTRACTS-D R2).
--
-- ORDER: applies only AFTER 159 (20261021120000, F's venue_api views — parts
-- 7-9 re-create three of them), 176 (20261022000000, F's published-event public
-- arms — 229 P1-P4 pin the interplay), 160 (20261022100000 — the six bodies
-- replaced here are 160's, md5-guarded below) and 161 (20261022110000 — part 10
-- adds wrappers to its schema); BEFORE 163+ (20261026110000 and later) and
-- before A's 185. The pre-flight DO block refuses to run otherwise.
--
-- WHAT THIS MIGRATION IS (CONTRACTS-D §3; PROMPT-D items 2-4; owner decisions
-- #5-#8 stay open — every choice is reversible and recorded here):
--  1. catalog.venue.timezone text NOT NULL DEFAULT 'America/New_York' (an IANA
--     name; the setter validates against pg_catalog.pg_timezone_names, exact
--     case) + catalog.set_venue_timezone(p_venue_id uuid, p_timezone text,
--     p_reason_code text, p_command_key text) returns jsonb. Authority =
--     catalog.update_venue's (093:5974, read and mirrored, NOT replaced):
--     kernel.has_org_role(venue.org_id, [org_owner, org_admin]) OR
--     kernel.has_venue_role(venue_id, [venue_manager]). There is no event, so
--     no E-76 conjunct can apply: the venue's CURRENT staff venue_manager is
--     accepted (as update_venue accepts them today) — 229 T23 pins that status
--     quo for A. Reason required; same value = noop without audit; otherwise
--     one kernel.admin_audit row 'venue.timezone_change' with before/after.
--  2. catalog.event.age_policy text NULL CHECK IN ('all_ages','18_plus',
--     '21_plus') (NULL = not specified; the value set is owner decision #8, the
--     column is reversible) + catalog.set_event_age_policy(p_event_id uuid,
--     p_age_policy text, p_reason_code text, p_command_key text). Authority =
--     catalog.update_event's org arm (078:901: kernel.has_org_role on the
--     EVENT's org_id) + the venue arm with E-76 (bound venue_manager). The
--     marketing arm of update_event (org_marketing/venue_marketing on
--     marketing-only patches) does NOT apply: an age policy is an admission
--     rule, not copy. completed/cancelled -> 'precondition_failed:
--     event_terminal'; NULL clears; same value = noop; audit
--     'event.age_policy_change'.
--  3. catalog.event_session.sales_capacity integer NULL CHECK (> 0) + catalog.
--     set_session_sales_capacity(p_session_id uuid, p_capacity integer,
--     p_reason_code text, p_command_key text). FOR UPDATE on the session (rank
--     1); same authority as 2 (update_event_session's org arm, 093:6950, + the
--     E-76 venue arm); event terminal -> event_terminal, session terminal ->
--     session_terminal (093's vocabulary); refused below the current
--     SUM(venue.inventory_batch.capacity) of the session
--     ('precondition_failed: below_allocated') and above catalog.venue.
--     capacity_hint when that is not NULL ('precondition_failed:
--     above_venue_capacity'); NULL clears (unlimited — the 160 behaviour, 229
--     S14/S15 pin it); audit 'event_session.sales_capacity_change'. It does NOT
--     bump session_version: that counter is bumped only by update_event_session
--     for the time columns the notification dedupe keys embed (078:188-191);
--     stale-version semantics for sessions remain whatever 093 does.
--  4. Body-only CREATE OR REPLACE of venue.create_inventory_batch and
--     venue.set_batch_capacity at their EXACT signatures (160's bodies, copied
--     mechanically by gen_162.py — D's evidence dir — with the substitutions
--     listed under R3 below plus ONE addition each): lock the session row
--     (`select … from catalog.event_session where session_id = … for update`,
--     rank 1 BEFORE the batch's rank 2 — the cancel_event lock order, so a
--     concurrent cancel/create/resize cannot deadlock) and refuse with
--     'precondition_failed: session_capacity_exceeded' when SUM(capacity) over
--     the session's batches (this one included) would exceed sales_capacity
--     when it is not NULL. Tiers and comp/door/presale batches therefore share
--     ONE room by construction; the reserve path is untouched (it locks the
--     batch only — no new lock interaction).
--  5. venue.ticket_type.sale_starts_at timestamptz NULL, sale_ends_at timestamptz
--     NULL, CHECK (sale_ends_at is null or sale_starts_at is null or
--     sale_ends_at > sale_starts_at) + venue.set_ticket_type_sale_window(
--     p_ticket_type_id uuid, p_sale_starts_at timestamptz, p_sale_ends_at
--     timestamptz, p_reason_code text, p_command_key text): authority/terminal/
--     audit exactly like 160's set_ticket_type_visibility with the R3 org arm
--     and the E-76 venue conjunct; ends <= starts -> invalid_input before the
--     CHECK; NULL/NULL clears; audit 'ticket_type.sale_window_change'.
--     + venue.ticket_type_on_sale(p_ticket_type_id uuid, p_at timestamptz
--     DEFAULT now()) returns boolean, STABLE SECURITY DEFINER, LANGUAGE sql:
--     true iff the tier exists AND visibility <> 'hidden' AND (sale_starts_at
--     is null or sale_starts_at <= p_at) AND (sale_ends_at is null or p_at <
--     sale_ends_at) AND the event's status in ('on_sale','live'). Starts
--     inclusive, ends exclusive, NULL = open on that side; unknown id -> false;
--     a NULL p_at -> false (fail closed: an unknown instant is in no window);
--     door_only counts as on sale (it is sold, at the door). The 081 table
--     grant (081:988, table grain) already covers the two new columns, so
--     every role that reads a tier row reads its window — as display_rank (160).
--  6. venue_cmd SECURITY INVOKER wrappers (LANGUAGE sql, identical argument
--     lists and result types) for the four setters and the predicate (part 10).
--  7. CREATE OR REPLACE VIEW venue_api.ticket_types (160's projection) with
--     sale_starts_at, sale_ends_at, on_sale_now (= venue.ticket_type_on_sale(
--     ticket_type_id)) appended LAST. venue_api.events (159) + age_policy,
--     timezone (LEFT JOIN catalog.venue — the row set is unchanged, 226 D1/D4
--     stay true; a venue row the caller cannot read yields NULLs, never a
--     missing event). venue_api.event_sessions (159) + timezone,
--     starts_at_local, ends_at_local, doors_at_local (text,
--     to_char(x at time zone v.timezone, 'YYYY-MM-DD HH24:MI'); LEFT JOIN
--     catalog.event, catalog.venue). security_invoker + security_barrier
--     re-stated; each view's ACL (SELECT to authenticated) and comment persist
--     across CREATE OR REPLACE. age_policy is projected because the column has
--     no other client read path (catalog is not exposed) — D's addition to §3,
--     flagged for F/A.
--  8. REVOKE ALL FROM PUBLIC, anon, authenticated and GRANT EXECUTE TO
--     authenticated on the five new functions (081 PART 16 pattern).
--
-- R3 — THE ORG ARM BINDS TO THE EVENT'S ORG (A's ruling 2026-10-26 on
-- CONTRACTS-D R3). 160 left the org arm of the four 081 writers and its two
-- setters as 081 wrote it: kernel.has_org_role_over_venue(v_venue, …), i.e. the
-- venue's CURRENT operator. On a re-operated room (venue.org_id = B,
-- event.org_id = A) that accepted the NEW operator B's owner on A's event and
-- refused the event's OWN owner A (227 B9/B10 pinned it for A to rule). Ruling:
-- the org arm must bind to catalog.event.org_id with the helper cancel_event
-- uses (088:1629: kernel.has_org_role(v_e.org_id, array['org_owner',
-- 'org_admin'])). This migration therefore replaces, body-only and at the exact
-- signatures, ALL SIX: venue.create_ticket_type, set_ticket_type_price,
-- create_inventory_batch, set_batch_capacity, set_ticket_type_visibility,
-- set_ticket_type_rank — each 160 body with
--   kernel.has_org_role_over_venue(v_venue, array['org_owner','org_admin'])
--     -> kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
-- (v_org_id is already the event's org in every body) and the E-76 venue arm
-- unchanged; set_ticket_type_sale_window is written in the same form. Result on
-- the re-operated room: B's owner REFUSED, A's owner ACCEPTED (even though the
-- venue now belongs to B), V2's former-operator manager still refused (E-76).
-- 227 B9/B10 FLIP and are updated in this package (A's instruction); 229 B1-B15
-- carry the positive and negative controls on all six plus the new setter.
-- CALLER ENUMERATION (A's PR-body requirement; the full table with the new
-- "org arm" column is E76_CALLER_ENUMERATION.md in D's evidence dir): no caller
-- on ce1c9737 or the read-only refs relies on the venue's CURRENT org differing
-- from the event's org — every event was stamped from its venue by
-- catalog.create_event (078:856-868) and no operatorship changed before a
-- writer call (153 re-operates only after its writer calls, for cancel_event's
-- own E-76 test, and reverts); every pgTAP caller is the org_owner of the org
-- that created the venue, so has_org_role(event.org_id) accepts exactly the
-- same callers as has_org_role_over_venue did for them. The ONLY state where
-- the two arms differ is the frozen tenancy move (093 ruling C refuses the
-- org_id patch today), i.e. unreachable in production. No existing caller is
-- newly refused; 227 (with B9/B10 flipped) and 229 pin both arms.
--
-- AUTHORITY SUMMARY (one line each):
--   set_venue_timezone         has_org_role(venue.org_id, owner/admin) OR has_venue_role(venue, manager)        [= update_venue]
--   set_event_age_policy       has_org_role(event.org_id, owner/admin) OR (has_venue_role(event.venue_id, manager) AND venue.org_id = event.org_id)
--   set_session_sales_capacity same as set_event_age_policy (event resolved through the session)
--   set_ticket_type_sale_window, and the six replaced venue.* bodies: the same two arms (event's org + E-76 venue arm)
--   ticket_type_on_sale        none (a boolean read; EXECUTE to authenticated — see GRANT DECISIONS)
--
-- GRANT DECISIONS (every one — the CI grant gates read `public` only, so 229 is
-- the gate for these objects, the 226/227/228 pattern):
--   catalog.set_venue_timezone / set_event_age_policy / set_session_sales_capacity,
--   venue.set_ticket_type_sale_window, venue.ticket_type_on_sale
--                      EXECUTE: authenticated ONLY (REVOKE ALL FROM PUBLIC, anon,
--                      authenticated first — 067 — then GRANT). anon: NONE —
--                      anon reads go through 176's public arms and F's views
--                      (venue_api grants anon nothing, 159); the predicate is
--                      called INSIDE venue_api.ticket_types as the caller
--                      (security_invoker), so authenticated needs it and anon
--                      cannot reach the view at all. service_role: NONE (no
--                      server-side caller; A's 185 calls the predicate from
--                      venue.* definer bodies, which run as the owner).
--                      ticket_type_on_sale leaks no row data: it answers a
--                      boolean about an id the caller already holds; hidden
--                      tiers and unpublished events answer false.
--   venue_cmd.* (five new wrappers)
--                      EXECUTE: authenticated ONLY; schema USAGE unchanged (161:
--                      authenticated only). The three catalog-targeting wrappers
--                      rely on authenticated's USAGE on catalog (076), which it
--                      holds.
--   catalog.venue.timezone      GRANT SELECT (timezone) TO anon, authenticated — the
--                      078:125 column-grant list extended by one column, same
--                      roles: a room's timezone is public information and the
--                      security_invoker views need the caller to read it.
--   catalog.event.age_policy    GRANT SELECT (age_policy) TO anon, authenticated — the
--                      078:160 list extended by one column, same roles: an
--                      admission policy is listing information ("21+").
--   catalog.event_session.sales_capacity   NO client grant (withheld, the E-29
--                      posture for capacity figures: 081:1011-1018). Staff see
--                      it in the setter's result; a staff read is 163's.
--   venue.ticket_type.sale_starts_at / sale_ends_at   covered by the 081:988
--                      TABLE-grain SELECT grant to authenticated (as display_rank
--                      in 160); anon is walled from venue (076/E-30).
--   the six replaced venue.* bodies keep their 081/160 grants (a body-only
--                      CREATE OR REPLACE does not touch proacl; 229 A-section
--                      and 227 B11 pin it).
--
-- FOUR-FILE RULE (CLAUDE.md): the grant-decision manifest and expected_grants.txt
-- read `public` only (the manifest's B2 fails closed on a row for a function
-- outside public; 159/160/161 added no row for the same reason), so no row is
-- added; 229 pins the exact EXECUTE ACL of the five functions and five wrappers,
-- the three views' ACLs and the two column grants. The Gate-2 census (ci.yml)
-- reads `public` only: unchanged (a dated comment line records it).
-- PINS THIS MIGRATION MOVES (existing pgTAP files; the one-hunk updates are
-- delivered as patch files in D's evidence dir, stacked on 160's patches, for
-- their owners — only 227 B9/B10 are edited in-repo, on A's instruction):
--   venue function count 90 -> 92: 144 A15, 145 A4, 148 B5, 179 A8, 180 A5, 227 A12;
--   catalog function count 17 -> 20: 154 A10 ('22/157/17' -> '22/157/20');
--   five-schema routine census 308 -> 313: 148 B2, 156 A20, 157 A46, 179 A9, 180 A6;
--   140 #27 (named caller-authorized venue functions): + set_ticket_type_sale_window, ticket_type_on_sale;
--   226 F5 (56 -> 65 columns) and F6 (exp_ticket_types, exp_events, exp_event_sessions);
--   228 (venue_cmd 6 -> 11; A2/A3/A5-A7/A14-A20/A23 — A18-A20 must also accept catalog targets);
--   227 B9/B10 (the org arm — flipped in this package).
-- Every other suite in the sweep (141, 146, 149, 150, 168, 246) is unchanged.
-- Rollback: supabase/rollbacks/20261026100000_event_policy_shared_capacity_and_tier_windows_rollback.sql
-- — restores the SIX 160 bodies verbatim (md5-asserted both ways), drops the five
-- wrappers, the five functions and the three re-created views, drops the five
-- columns ONLY when every value is NULL/default (refuses otherwise, rc 3), and
-- re-creates the three views in their 160 state (ticket_types) / 159 state
-- (events, event_sessions) with their comments and grants.
--
-- VERIFICATION (after apply):
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='venue';      -- 92 (was 90)
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='catalog';    -- 20 (was 17)
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='venue_cmd';  -- 11 (was 6)
--   select attname from pg_attribute where attrelid='venue_api.ticket_types'::regclass and attnum>0 and not attisdropped order by attnum;  -- …, display_rank, sale_starts_at, sale_ends_at, on_sale_now
--   select proname, md5(prosrc) from pg_proc where pronamespace='venue'::regnamespace and proname in ('create_ticket_type','set_ticket_type_price','create_inventory_batch','set_batch_capacity','set_ticket_type_visibility','set_ticket_type_rank');
--   -- expected post-162 md5s: create_ticket_type bfc2972e6aecb2dd5a0b4bd587dcc377 · set_ticket_type_price 7d1cc0c9d95b99b94f17ae9ab1f86932
--   --                        create_inventory_batch 30424f73432699526f4424bbcbf52c73 · set_batch_capacity 7aa6b6d303276f44125ab91829689542
--   --                        set_ticket_type_visibility 69ded39de3ca710d3f12c738784a2177 · set_ticket_type_rank fa9da73250e877b913bc178b4644f41d
--   -- pre-162 (160) md5s:   create_ticket_type bba1f015338953b1b84ab1a8ce6e1ff9 · set_ticket_type_price 0b349a564a50fdda0b721d097a3bb9eb
--   --                        create_inventory_batch abedde3ce19d1a49087ac4a5c6aaacd0 · set_batch_capacity 76c69e9d8625b056e67e53c1d4e34fd9
--   --                        set_ticket_type_visibility d3d7f28c126641188ee1e68f312624ed · set_ticket_type_rank e9aa82f8d38acf2e7fe4e050d596e4fe
-- LOCKS / RUNTIME: ADD COLUMN takes a brief ACCESS EXCLUSIVE on catalog.venue,
-- catalog.event, catalog.event_session and venue.ticket_type with no rewrite
-- (the NOT NULL DEFAULT constant on catalog.venue is metadata-only, PG11+; the
-- CHECKs validate existing rows, all NULL); CREATE OR REPLACE FUNCTION/VIEW take
-- brief locks; no data is read or written. lock_timeout 3s: it fails cleanly
-- rather than queue behind a long reader.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ============================================================================
-- PRE-FLIGHT — 159, 160, 161 present; each of the six bodies is 160's (first apply) or
-- 162's own (re-apply) by md5 — anything else is a later migration or a hotfix that landed
-- first and is refused (A's #166 review ask 2 mirrored from 160 PART 5.0; B's 183 N2 pattern)
-- ============================================================================
DO $pre$
BEGIN
  IF to_regclass('venue_api.ticket_types') IS NULL OR to_regclass('venue_api.events') IS NULL
     OR to_regclass('venue_api.event_sessions') IS NULL THEN
    RAISE EXCEPTION '162_REFUSED: venue_api views (159) are absent; apply 159 first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'venue.ticket_type'::regclass AND attname = 'display_rank' AND NOT attisdropped) THEN
    RAISE EXCEPTION '162_REFUSED: venue.ticket_type.display_rank (160) is absent; apply 160 first.';
  END IF;
  IF to_regnamespace('venue_cmd') IS NULL THEN
    RAISE EXCEPTION '162_REFUSED: schema venue_cmd (161) is absent; apply 161 first.';
  END IF;
  -- The six bodies PART 9 replaces: exactly 160's (first apply) or 162's own (re-apply); any other md5 means a
  -- later migration or a hotfix landed first and CREATE OR REPLACE would silently overwrite it — refuse; the single
  -- transaction then changes nothing. The rollback's G1 is the mirror guard on the way back. Values: header VERIFICATION.
  DECLARE
    v_tt text := (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('venue.create_ticket_type(uuid, text, text, integer, text, text)'));
    v_px text := (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('venue.set_ticket_type_price(uuid, integer, text, text)'));
    v_cb text := (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'));
    v_sc text := (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('venue.set_batch_capacity(uuid, integer, text, text)'));
    v_vs text := (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('venue.set_ticket_type_visibility(uuid, text, text, text)'));
    v_rk text := (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('venue.set_ticket_type_rank(uuid, smallint, text)'));
  BEGIN
    IF v_tt IS NULL OR v_tt NOT IN ('bba1f015338953b1b84ab1a8ce6e1ff9', 'bfc2972e6aecb2dd5a0b4bd587dcc377') THEN
      RAISE EXCEPTION 'MIGRATION_162_REFUSED (pre-flight): venue.create_ticket_type body is neither 160''s nor 162''s (md5 %); nothing changed', coalesce(v_tt, '<missing>');
    END IF;
    IF v_px IS NULL OR v_px NOT IN ('0b349a564a50fdda0b721d097a3bb9eb', '7d1cc0c9d95b99b94f17ae9ab1f86932') THEN
      RAISE EXCEPTION 'MIGRATION_162_REFUSED (pre-flight): venue.set_ticket_type_price body is neither 160''s nor 162''s (md5 %); nothing changed', coalesce(v_px, '<missing>');
    END IF;
    IF v_cb IS NULL OR v_cb NOT IN ('abedde3ce19d1a49087ac4a5c6aaacd0', '30424f73432699526f4424bbcbf52c73') THEN
      RAISE EXCEPTION 'MIGRATION_162_REFUSED (pre-flight): venue.create_inventory_batch body is neither 160''s nor 162''s (md5 %); nothing changed', coalesce(v_cb, '<missing>');
    END IF;
    IF v_sc IS NULL OR v_sc NOT IN ('76c69e9d8625b056e67e53c1d4e34fd9', '7aa6b6d303276f44125ab91829689542') THEN
      RAISE EXCEPTION 'MIGRATION_162_REFUSED (pre-flight): venue.set_batch_capacity body is neither 160''s nor 162''s (md5 %); nothing changed', coalesce(v_sc, '<missing>');
    END IF;
    IF v_vs IS NULL OR v_vs NOT IN ('d3d7f28c126641188ee1e68f312624ed', '69ded39de3ca710d3f12c738784a2177') THEN
      RAISE EXCEPTION 'MIGRATION_162_REFUSED (pre-flight): venue.set_ticket_type_visibility body is neither 160''s nor 162''s (md5 %); nothing changed', coalesce(v_vs, '<missing>');
    END IF;
    IF v_rk IS NULL OR v_rk NOT IN ('e9aa82f8d38acf2e7fe4e050d596e4fe', 'fa9da73250e877b913bc178b4644f41d') THEN
      RAISE EXCEPTION 'MIGRATION_162_REFUSED (pre-flight): venue.set_ticket_type_rank body is neither 160''s nor 162''s (md5 %); nothing changed', coalesce(v_rk, '<missing>');
    END IF;
  END;
END $pre$;

-- ============================================================================
-- PART 1 — catalog.venue.timezone (additive; NOT NULL DEFAULT, metadata-only)
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_attribute
                  where attrelid = 'catalog.venue'::regclass
                    and attname = 'timezone' and not attisdropped) then
    alter table catalog.venue
      add column timezone text not null default 'America/New_York';
  end if;
end $$;
comment on column catalog.venue.timezone is
  'IANA time zone of the room (pg_timezone_names; default America/New_York — owner decision open). Set only by catalog.set_venue_timezone (162). venue_api projects session times in it (*_local).';
grant select (timezone) on catalog.venue to anon, authenticated;   -- the 078:125 list + one column, same roles

-- ============================================================================
-- PART 2 — catalog.event.age_policy (additive; NULL = not specified)
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_attribute
                  where attrelid = 'catalog.event'::regclass
                    and attname = 'age_policy' and not attisdropped) then
    alter table catalog.event
      add column age_policy text
        constraint event_age_policy_check check (age_policy in ('all_ages','18_plus','21_plus'));
  end if;
end $$;
comment on column catalog.event.age_policy is
  'Admission age policy: all_ages | 18_plus | 21_plus; NULL = not specified (owner decision #8 open). Set only by catalog.set_event_age_policy (162); audited.';
grant select (age_policy) on catalog.event to anon, authenticated;  -- the 078:160 list + one column, same roles

-- ============================================================================
-- PART 3 — catalog.event_session.sales_capacity (additive; NULL = unlimited)
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_attribute
                  where attrelid = 'catalog.event_session'::regclass
                    and attname = 'sales_capacity' and not attisdropped) then
    alter table catalog.event_session
      add column sales_capacity integer
        constraint event_session_sales_capacity_check check (sales_capacity > 0);
  end if;
end $$;
comment on column catalog.event_session.sales_capacity is
  'The shared sales pool of the session: SUM(venue.inventory_batch.capacity) over its batches may never exceed it (162 guards in create_inventory_batch / set_batch_capacity). NULL = unlimited. Set only by catalog.set_session_sales_capacity. Not client-readable (E-29 posture).';
-- no client grant on sales_capacity (E-29 posture; see the header)

-- ============================================================================
-- PART 4 — venue.ticket_type.sale_starts_at / sale_ends_at (additive)
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_attribute
                  where attrelid = 'venue.ticket_type'::regclass
                    and attname = 'sale_starts_at' and not attisdropped) then
    alter table venue.ticket_type
      add column sale_starts_at timestamptz,
      add column sale_ends_at   timestamptz,
      add constraint ticket_type_sale_window_check
        check (sale_ends_at is null or sale_starts_at is null or sale_ends_at > sale_starts_at);
  end if;
end $$;
comment on column venue.ticket_type.sale_starts_at is
  'Sale window start (inclusive); NULL = open. Set only by venue.set_ticket_type_sale_window (162); read through venue.ticket_type_on_sale. Readable by every role that reads the row (081:988 table grant).';
comment on column venue.ticket_type.sale_ends_at is
  'Sale window end (exclusive); NULL = open. CHECK sale_ends_at > sale_starts_at when both are set. Set only by venue.set_ticket_type_sale_window (162).';

-- ============================================================================
-- PART 5 — catalog.set_venue_timezone (authority = update_venue 093:5974)
-- ============================================================================
create or replace function catalog.set_venue_timezone(
  p_venue_id uuid, p_timezone text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_org_id uuid;
  v_old    text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  -- an IANA name, exact case, as pg_timezone_names spells it ('America/New_York').
  if p_timezone is null or length(trim(p_timezone)) = 0 then
    raise exception 'invalid_input: timezone required';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names tz where tz.name = p_timezone) then
    raise exception 'invalid_input: unknown_timezone %', p_timezone;
  end if;

  select v.org_id, v.timezone into v_org_id, v_old
    from catalog.venue v where v.venue_id = p_venue_id for update;
  if v_org_id is null then
    raise exception 'not_found: venue %', p_venue_id using errcode = 'P0002';
  end if;

  -- update_venue's two arms (093:6013-6021), mirrored: the venue's org plane or
  -- its own venue_manager. No event is involved, so no E-76 conjunct applies.
  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or kernel.has_venue_role(p_venue_id, array['venue_manager'])) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  if v_old = p_timezone then
    return jsonb_build_object('status','noop','venue_id',p_venue_id,'timezone',v_old);
  end if;

  update catalog.venue set timezone = p_timezone, updated_at = now()
   where venue_id = p_venue_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'venue.timezone_change', 'venue', p_venue_id, p_reason_code,
          jsonb_build_object('timezone', v_old), jsonb_build_object('timezone', p_timezone));

  return jsonb_build_object('status','ok','venue_id',p_venue_id,'timezone',p_timezone);
end;
$$;
comment on function catalog.set_venue_timezone(uuid, text, text, text) is
  '162: venue timezone setter (IANA name validated against pg_timezone_names). org_owner/org_admin of the venue''s org or the venue''s venue_manager (update_venue''s authority). Reason required; same value = noop without audit.';

-- ============================================================================
-- PART 6 — catalog.set_event_age_policy (authority = update_event's org arm + E-76 venue arm)
-- ============================================================================
create or replace function catalog.set_event_age_policy(
  p_event_id uuid, p_age_policy text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_org_id uuid;
  v_venue  uuid;
  v_status text;
  v_old    text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  -- validated here so the caller gets invalid_input, not the table CHECK's 23514.
  if p_age_policy is not null and p_age_policy not in ('all_ages','18_plus','21_plus') then
    raise exception 'invalid_input: bad age_policy % (all_ages|18_plus|21_plus or NULL)', p_age_policy;
  end if;

  select e.org_id, e.venue_id, e.status, e.age_policy
    into v_org_id, v_venue, v_status, v_old
    from catalog.event e where e.event_id = p_event_id for update;   -- rank 1
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  -- update_event's org arm (078:901: the EVENT's org) + the venue arm with E-76.
  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager (current operator) or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  if v_old is not distinct from p_age_policy then
    return jsonb_build_object('status','noop','event_id',p_event_id,'age_policy',v_old);
  end if;

  update catalog.event set age_policy = p_age_policy, updated_at = now()
   where event_id = p_event_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event.age_policy_change', 'event', p_event_id, p_reason_code,
          jsonb_build_object('age_policy', v_old), jsonb_build_object('age_policy', p_age_policy));

  return jsonb_build_object('status','ok','event_id',p_event_id,'age_policy',p_age_policy);
end;
$$;
comment on function catalog.set_event_age_policy(uuid, text, text, text) is
  '162: event age policy setter (all_ages|18_plus|21_plus; NULL clears). org_owner/org_admin of the EVENT''s org or the bound venue_manager (E-76). Reason required; terminal events refused; same value = noop without audit.';

-- ============================================================================
-- PART 7 — catalog.set_session_sales_capacity (the shared room; FOR UPDATE rank 1)
-- ============================================================================
create or replace function catalog.set_session_sales_capacity(
  p_session_id uuid, p_capacity integer, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_event_id  uuid;
  v_sstatus   text;
  v_old       integer;
  v_org_id    uuid;
  v_venue     uuid;
  v_estatus   text;
  v_allocated integer;
  v_hint      integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  -- validated here so the caller gets invalid_input, not the table CHECK's 23514.
  if p_capacity is not null and p_capacity <= 0 then
    raise exception 'invalid_input: bad sales_capacity % (> 0 or NULL = unlimited)', p_capacity;
  end if;

  select s.event_id, s.status, s.sales_capacity
    into v_event_id, v_sstatus, v_old
    from catalog.event_session s
   where s.session_id = p_session_id
   for update;                                          -- rank 1 (serialises against the batch writers)
  if v_event_id is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;
  select e.org_id, e.venue_id, e.status into v_org_id, v_venue, v_estatus
    from catalog.event e where e.event_id = v_event_id;
  if v_estatus in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;
  if v_sstatus in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;

  -- update_event_session's org arm (093:6950: the EVENT's org) + the venue arm with E-76.
  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager (current operator) or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  select coalesce(sum(b.capacity), 0) into v_allocated
    from venue.inventory_batch b where b.event_session_id = p_session_id;

  if v_old is not distinct from p_capacity then
    return jsonb_build_object('status','noop','session_id',p_session_id,
                              'sales_capacity',v_old,'allocated',v_allocated);
  end if;

  if p_capacity is not null then
    -- the pool can never be set below what the batches already hold.
    if p_capacity < v_allocated then
      raise exception 'precondition_failed: below_allocated (new=% < allocated=%)', p_capacity, v_allocated;
    end if;
    -- …nor above the room's recorded capacity when the venue carries one
    -- (capacity_hint stays "informational; NOT the oversell guard" — 078:110 — the
    -- oversell guard is the per-batch CHECK; this is the planning ceiling).
    select v.capacity_hint into v_hint from catalog.venue v where v.venue_id = v_venue;
    if v_hint is not null and p_capacity > v_hint then
      raise exception 'precondition_failed: above_venue_capacity (new=% > capacity_hint=%)', p_capacity, v_hint;
    end if;
  end if;

  -- session_version is NOT bumped: it is the notification dedupe key for the
  -- TIME columns and is bumped only by catalog.update_event_session (078:188-191).
  update catalog.event_session set sales_capacity = p_capacity, updated_at = now()
   where session_id = p_session_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'event_session.sales_capacity_change', 'event_session', p_session_id, p_reason_code,
          jsonb_build_object('sales_capacity', v_old), jsonb_build_object('sales_capacity', p_capacity));

  return jsonb_build_object('status','ok','session_id',p_session_id,
                            'sales_capacity',p_capacity,'allocated',v_allocated);
end;
$$;
comment on function catalog.set_session_sales_capacity(uuid, integer, text, text) is
  '162: per-session sales pool setter (> 0 or NULL = unlimited). org_owner/org_admin of the EVENT''s org or the bound venue_manager (E-76). Refused below SUM(batch capacity) (below_allocated) and above catalog.venue.capacity_hint when set (above_venue_capacity). Session row FOR UPDATE; reason required; terminal refused; same value = noop without audit.';

-- ============================================================================
-- PART 8 — venue.set_ticket_type_sale_window + venue.ticket_type_on_sale
-- ============================================================================
create or replace function venue.set_ticket_type_sale_window(
  p_ticket_type_id uuid, p_sale_starts_at timestamptz, p_sale_ends_at timestamptz,
  p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_venue     uuid;
  v_status    text;
  v_old_start timestamptz;
  v_old_end   timestamptz;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  -- validated here so the caller gets invalid_input, not the table CHECK's 23514.
  if p_sale_starts_at is not null and p_sale_ends_at is not null and p_sale_ends_at <= p_sale_starts_at then
    raise exception 'invalid_input: sale_ends_at must be after sale_starts_at';
  end if;

  select tt.sale_starts_at, tt.sale_ends_at, e.org_id, e.venue_id, e.status
    into v_old_start, v_old_end, v_org_id, v_venue, v_status
    from venue.ticket_type tt
    join catalog.event e on e.event_id = tt.event_id
   where tt.ticket_type_id = p_ticket_type_id
   for update of tt;                                    -- rank 2, Inventory class (081:279)
  if v_org_id is null then
    raise exception 'not_found: ticket type %', p_ticket_type_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  -- 162 (A's R3 ruling): the ORG arm binds to the EVENT's org — kernel.has_org_role on
  -- event.org_id, the 088:1629 cancel_event helper. The venue arm carries E-76 (160).
  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager (current operator) or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  if v_old_start is not distinct from p_sale_starts_at and v_old_end is not distinct from p_sale_ends_at then
    return jsonb_build_object('status','noop','ticket_type_id',p_ticket_type_id,
                              'sale_starts_at',v_old_start,'sale_ends_at',v_old_end);
  end if;

  update venue.ticket_type
     set sale_starts_at = p_sale_starts_at, sale_ends_at = p_sale_ends_at, updated_at = now()
   where ticket_type_id = p_ticket_type_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.sale_window_change', 'ticket_type', p_ticket_type_id, p_reason_code,
          jsonb_build_object('sale_starts_at', v_old_start, 'sale_ends_at', v_old_end),
          jsonb_build_object('sale_starts_at', p_sale_starts_at, 'sale_ends_at', p_sale_ends_at));

  return jsonb_build_object('status','ok','ticket_type_id',p_ticket_type_id,
                            'sale_starts_at',p_sale_starts_at,'sale_ends_at',p_sale_ends_at);
end;
$$;
comment on function venue.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text) is
  '162: tier sale window setter (starts inclusive, ends exclusive, NULL = open; NULL/NULL clears). org_owner/org_admin of the EVENT''s org or the bound venue_manager (E-76). Reason required; terminal events refused; same values = noop without audit.';

create or replace function venue.ticket_type_on_sale(
  p_ticket_type_id uuid, p_at timestamptz default now())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- a NULL instant is never inside a window (fail closed; the default is now()).
  select p_at is not null
     and coalesce((select tt.visibility <> 'hidden'
                      and (tt.sale_starts_at is null or tt.sale_starts_at <= p_at)
                      and (tt.sale_ends_at   is null or p_at < tt.sale_ends_at)
                      and e.status in ('on_sale','live')
                     from venue.ticket_type tt
                     join catalog.event e on e.event_id = tt.event_id
                    where tt.ticket_type_id = p_ticket_type_id), false)
$$;
comment on function venue.ticket_type_on_sale(uuid, timestamptz) is
  '162: true iff the tier exists, is not hidden, its sale window contains p_at (starts inclusive, ends exclusive, NULL = open) and its event is on_sale or live. Unknown id or NULL p_at -> false. STABLE; the purchase-time call is A''s (185).';

-- ============================================================================
-- PART 9 — R3 on the six venue.* bodies (body-only replaces at the exact
-- signatures; 160's text with the substitutions listed in the header) and the
-- shared-room guard on the two batch writers. The rollback restores 160's text.
-- ============================================================================

-- 9.1 venue.create_ticket_type (081:175 / 160 5.1)
create or replace function venue.create_ticket_type(
  p_event_id uuid, p_kind text, p_name text, p_price_minor integer,
  p_visibility text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid;
  v_org_id  uuid;
  v_venue   uuid;
  v_status  text;
  v_tt_id   uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_kind not in ('admission','table') then
    raise exception 'invalid_input: bad kind %', p_kind;
  end if;
  if p_visibility not in ('hidden','public','door_only') then
    raise exception 'invalid_input: bad visibility %', p_visibility;
  end if;
  if p_price_minor is null or p_price_minor <= 0 then
    raise exception 'precondition_failed: bad_price';
  end if;

  select e.org_id, e.venue_id, e.status into v_org_id, v_venue, v_status
    from catalog.event e where e.event_id = p_event_id;
  if v_org_id is null then
    raise exception 'not_found: event %', p_event_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  -- RM-3: org->venue inheritance is expressed ONLY through the sanctioned
  -- helper, never a direct has_org_role on the denormalised event.org_id
  -- (which IS the venue's org). Reconciles §5.1's has_org_role spelling to the
  -- ratified helper-derived discipline; functionally identical (E-31 note).
  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          -- 162 (A's R3 ruling): the ORG arm binds to the EVENT's org — kernel.has_org_role on
          -- event.org_id, the 088:1629 cancel_event helper — no longer the venue's CURRENT org.
          -- E-76 (160): the venue-role arm also requires the venue's CURRENT operator to be
          -- the event's org (the 088:1628-1631 cancel_event pattern).
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  insert into venue.ticket_type (event_id, kind, name, price_minor, visibility)
  values (p_event_id, p_kind, p_name, p_price_minor, coalesce(p_visibility,'hidden'))
  returning ticket_type_id into v_tt_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.create', 'ticket_type', v_tt_id, 'self_service',
          null, jsonb_build_object('event_id', p_event_id, 'kind', p_kind,
                                   'price_minor', p_price_minor, 'visibility', p_visibility));

  return jsonb_build_object('status','ok','ticket_type_id',v_tt_id);
exception when unique_violation then
  raise exception 'precondition_failed: duplicate_name';
end;
$$;

-- 9.2 venue.set_ticket_type_price (081:246 / 160 5.2)
create or replace function venue.set_ticket_type_price(
  p_ticket_type_id uuid, p_price_minor integer, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_org_id uuid;
  v_venue  uuid;
  v_status text;
  v_old    integer;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_price_minor is null or p_price_minor <= 0 then
    raise exception 'precondition_failed: bad_price';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;

  select tt.price_minor, e.org_id, e.venue_id, e.status
    into v_old, v_org_id, v_venue, v_status
    from venue.ticket_type tt
    join catalog.event e on e.event_id = tt.event_id
   where tt.ticket_type_id = p_ticket_type_id
   for update of tt;                                    -- rank 2, Inventory class
  if v_org_id is null then
    raise exception 'not_found: ticket type %', p_ticket_type_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  -- C9 money-consequential live-table recheck (never a JWT claim); RM-3 helper.
  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          -- 162 (A's R3 ruling): the ORG arm binds to the EVENT's org — kernel.has_org_role on
          -- event.org_id, the 088:1629 cancel_event helper — no longer the venue's CURRENT org.
          -- E-76 (160): the venue-role arm also requires the venue's CURRENT operator to be
          -- the event's org (the 088:1628-1631 cancel_event pattern).
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  if v_old = p_price_minor then
    return jsonb_build_object('status','noop_replay','ticket_type_id',p_ticket_type_id,
                              'price_minor',v_old);
  end if;

  -- Binds only orders created AFTER it — orders snapshot unit_price_minor at
  -- checkout (§6.1), so this cannot re-price a pending/paid order, a refund or a
  -- settlement line. That property lives in venue.order_item (082), not here.
  update venue.ticket_type set price_minor = p_price_minor, updated_at = now()
   where ticket_type_id = p_ticket_type_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.price_change', 'ticket_type', p_ticket_type_id, p_reason_code,
          jsonb_build_object('price_minor', v_old),
          jsonb_build_object('price_minor', p_price_minor));

  return jsonb_build_object('status','ok','ticket_type_id',p_ticket_type_id,
                            'price_minor',p_price_minor);
end;
$$;

-- 9.3 venue.create_inventory_batch (081:320 / 160 5.3) + the session lock and pool guard
create or replace function venue.create_inventory_batch(
  p_ticket_type_id uuid, p_session_id uuid, p_release_kind text,
  p_capacity integer, p_shard_count integer, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_venue     uuid;
  v_tt_event  uuid;
  v_s_event   uuid;
  v_batch_id  uuid;
  v_evstatus  text;
  v_sharded   boolean;
  v_sales_cap integer;                 -- 162: the session's shared sales pool (NULL = unlimited)
  v_allocated integer;                 -- 162: SUM(capacity) over the session's existing batches
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_release_kind not in ('public_sale','promoter_hold','comp','door','presale') then
    raise exception 'invalid_input: bad release_kind %', p_release_kind;
  end if;
  if p_capacity is null or p_capacity <= 0 then
    raise exception 'precondition_failed: bad_capacity';
  end if;

  -- Sharding is deferred (E-32): the aggregate counter is oversell-safe and no
  -- contention exists while native issuance is dark. Refuse rather than create
  -- inert shard rows that would break the §3.3 Σshard==batch reconciliation.
  if coalesce(p_shard_count, 0) > 0 then
    raise exception 'precondition_failed: sharding_deferred (MVP ships the unsharded counter; schema §3.3 is MVP-optional)';
  end if;

  select tt.event_id, e.org_id, e.venue_id, e.status into v_tt_event, v_org_id, v_venue, v_evstatus
    from venue.ticket_type tt join catalog.event e on e.event_id = tt.event_id
   where tt.ticket_type_id = p_ticket_type_id;
  if v_tt_event is null then
    raise exception 'not_found: ticket type %', p_ticket_type_id using errcode = 'P0002';
  end if;
  -- refuse a batch on a terminal event (symmetry with create_ticket_type; a
  -- batch on a completed/cancelled event can never reach on_sale anyway).
  if v_evstatus in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;
  select s.event_id into v_s_event from catalog.event_session s where s.session_id = p_session_id;
  if v_s_event is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;
  -- type & session must belong to the SAME event.
  if v_tt_event <> v_s_event then
    raise exception 'precondition_failed: type_session_event_mismatch';
  end if;

  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          -- 162 (A's R3 ruling): the ORG arm binds to the EVENT's org — kernel.has_org_role on
          -- event.org_id, the 088:1629 cancel_event helper — no longer the venue's CURRENT org.
          -- E-76 (160): the venue-role arm also requires the venue's CURRENT operator to be
          -- the event's org (the 088:1628-1631 cancel_event pattern).
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- 162: THE SHARED ROOM. Lock the session row (rank 1 — the cancel_event order:
  -- session before batch), read its sales pool and refuse when this batch would
  -- push SUM(capacity) over it. NULL sales_capacity = unlimited (160 behaviour).
  select s.sales_capacity into v_sales_cap
    from catalog.event_session s where s.session_id = p_session_id for update;   -- rank 1
  if v_sales_cap is not null then
    select coalesce(sum(b.capacity), 0) into v_allocated
      from venue.inventory_batch b where b.event_session_id = p_session_id;
    if v_allocated + p_capacity > v_sales_cap then
      raise exception 'precondition_failed: session_capacity_exceeded (allocated=% + new=% > sales_capacity=%)',
        v_allocated, p_capacity, v_sales_cap;
    end if;
  end if;

  -- sharding deferred: is_sharded is always false, no shard rows (E-32).
  v_sharded := false;
  insert into venue.inventory_batch
         (ticket_type_id, event_session_id, release_kind, capacity, held, sold, is_sharded)
  values (p_ticket_type_id, p_session_id, p_release_kind, p_capacity, 0, 0, v_sharded)
  returning batch_id into v_batch_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'inventory.batch.create', 'inventory_batch', v_batch_id, 'self_service',
          null, jsonb_build_object('ticket_type_id', p_ticket_type_id, 'session_id', p_session_id,
                                   'release_kind', p_release_kind, 'capacity', p_capacity,
                                   'shards', coalesce(p_shard_count,0)));

  return jsonb_build_object('status','ok','batch_id',v_batch_id,
                            'capacity',p_capacity,'is_sharded',v_sharded);
end;
$$;

-- 9.4 venue.set_batch_capacity (081:408 / 160 5.4) + the session lock (first) and pool guard
create or replace function venue.set_batch_capacity(
  p_batch_id uuid, p_new_capacity integer, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid;
  v_org_id   uuid;
  v_venue    uuid;
  v_cap      integer;
  v_held     integer;
  v_sold     integer;
  v_sharded  boolean;
  v_delta    integer;
  v_room     integer;
  v_take     integer;
  r          record;
  v_session  uuid;                     -- 162: the batch's session (the shared room)
  v_sales_cap integer;                 -- 162: its sales pool (NULL = unlimited)
  v_allocated integer;                 -- 162: SUM(capacity) over the session's OTHER batches
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  if p_new_capacity is null or p_new_capacity <= 0 then
    raise exception 'precondition_failed: bad_capacity';
  end if;

  -- 162: lock the batch's SESSION row first (rank 1 before the batch's rank 2 —
  -- the cancel_event order, so a concurrent cancel/create cannot deadlock here)
  -- and read its shared sales pool. An unknown batch locks nothing and falls
  -- through to the P0002 below unchanged.
  select s.sales_capacity, s.session_id into v_sales_cap, v_session
    from catalog.event_session s
   where s.session_id = (select b.event_session_id from venue.inventory_batch b where b.batch_id = p_batch_id)
   for update;                                          -- rank 1

  select b.capacity, b.held, b.sold, b.is_sharded, e.org_id, e.venue_id
    into v_cap, v_held, v_sold, v_sharded, v_org_id, v_venue
    from venue.inventory_batch b
    join venue.ticket_type tt on tt.ticket_type_id = b.ticket_type_id
    join catalog.event e on e.event_id = tt.event_id
   where b.batch_id = p_batch_id
   for update of b;                                     -- rank 2
  if v_org_id is null then
    raise exception 'not_found: batch %', p_batch_id using errcode = 'P0002';
  end if;

  -- Authority: venue_manager OR org_owner/admin. NO platform arm — a platform
  -- capacity edit on a venue's room is not a support action (§20.3.2).
  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          -- 162 (A's R3 ruling): the ORG arm binds to the EVENT's org — kernel.has_org_role on
          -- event.org_id, the 088:1629 cancel_event helper — no longer the venue's CURRENT org.
          -- E-76 (160): the venue-role arm also requires the venue's CURRENT operator to be
          -- the event's org (the 088:1628-1631 cancel_event pattern).
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  -- THE REFUSAL FLOOR (C27, absolute): capacity may never drop below what is
  -- already committed. No force flag, no override role, no platform bypass.
  if p_new_capacity < v_held + v_sold then
    raise exception 'precondition_failed: below_committed (new=% < held+sold=%)',
      p_new_capacity, v_held + v_sold;
  end if;

  if v_cap = p_new_capacity then
    return jsonb_build_object('status','noop_replay','batch_id',p_batch_id,
                              'capacity',v_cap,'held',v_held,'sold',v_sold,
                              'remaining',v_cap - v_held - v_sold);
  end if;

  -- 162: THE SHARED ROOM — the new capacity plus every OTHER batch of the
  -- session must fit the pool (NULL = unlimited, 160 behaviour).
  if v_sales_cap is not null then
    select coalesce(sum(b.capacity), 0) into v_allocated
      from venue.inventory_batch b where b.event_session_id = v_session and b.batch_id <> p_batch_id;
    if v_allocated + p_new_capacity > v_sales_cap then
      raise exception 'precondition_failed: session_capacity_exceeded (others=% + new=% > sales_capacity=%)',
        v_allocated, p_new_capacity, v_sales_cap;
    end if;
  end if;

  v_delta := p_new_capacity - v_cap;
  if v_sharded then
    if v_delta > 0 then
      -- grow: put the whole delta on the lowest shard (Σ shard.capacity stays = batch).
      update venue.inventory_batch_shard
         set capacity = capacity + v_delta, updated_at = now()
       where batch_id = p_batch_id and shard_no = (
         select min(shard_no) from venue.inventory_batch_shard where batch_id = p_batch_id);
    else
      -- shrink: draw down ascending shard_no, only from each shard's own room
      -- (capacity - held - sold); raise if the distribution can't be satisfied.
      v_take := -v_delta;
      for r in select shard_no, capacity, held, sold from venue.inventory_batch_shard
                where batch_id = p_batch_id order by shard_no for update loop
        exit when v_take = 0;
        v_room := r.capacity - r.held - r.sold;
        if v_room > 0 then
          declare v_cut integer := least(v_room, v_take);
          begin
            update venue.inventory_batch_shard set capacity = capacity - v_cut, updated_at = now()
             where batch_id = p_batch_id and shard_no = r.shard_no;
            v_take := v_take - v_cut;
          end;
        end if;
      end loop;
      if v_take > 0 then
        raise exception 'precondition_failed: shard_distribution_unsatisfiable';
      end if;
    end if;
  end if;

  update venue.inventory_batch set capacity = p_new_capacity, updated_at = now()
   where batch_id = p_batch_id;

  -- C27: every capacity delta has a ledger row — an edit IS a delta.
  insert into venue.inventory_movement
         (batch_id, movement_kind, delta_held, delta_sold, cause, cause_ref, actor_identity)
  values (p_batch_id, 'capacity_change', 0, 0, 'admin_action', gen_random_uuid(), v_uid);

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'inventory.capacity.change', 'inventory_batch', p_batch_id, p_reason_code,
          jsonb_build_object('capacity', v_cap), jsonb_build_object('capacity', p_new_capacity));

  return jsonb_build_object('status','ok','batch_id',p_batch_id,'capacity',p_new_capacity,
                            'held',v_held,'sold',v_sold,'remaining',p_new_capacity - v_held - v_sold);
end;
$$;

-- 9.5 venue.set_ticket_type_visibility (160 PART 2)
create or replace function venue.set_ticket_type_visibility(
  p_ticket_type_id uuid, p_visibility text, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_org_id uuid;
  v_venue  uuid;
  v_status text;
  v_old    text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_visibility is null or p_visibility not in ('hidden','public','door_only') then
    raise exception 'invalid_input: bad visibility %', coalesce(p_visibility, '<null>');
  end if;
  -- the set_ticket_type_price rule (081:270-272): a visibility flip lands in the audit with a reason.
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;

  select tt.visibility, e.org_id, e.venue_id, e.status
    into v_old, v_org_id, v_venue, v_status
    from venue.ticket_type tt
    join catalog.event e on e.event_id = tt.event_id
   where tt.ticket_type_id = p_ticket_type_id
   for update of tt;                                    -- rank 2, Inventory class (081:279)
  if v_org_id is null then
    raise exception 'not_found: ticket type %', p_ticket_type_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  -- 162 (A's R3 ruling): the ORG arm binds to the EVENT's org — kernel.has_org_role on
  -- event.org_id, the 088:1629 cancel_event helper — no longer the venue's CURRENT org.
  -- The venue arm carries E-76 (160): the venue's CURRENT operator must be the event's org.
  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager (current operator) or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  if v_old = p_visibility then
    return jsonb_build_object('status','noop','ticket_type_id',p_ticket_type_id,'visibility',v_old);
  end if;

  update venue.ticket_type set visibility = p_visibility, updated_at = now()
   where ticket_type_id = p_ticket_type_id;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.visibility_change', 'ticket_type', p_ticket_type_id, p_reason_code,
          jsonb_build_object('visibility', v_old), jsonb_build_object('visibility', p_visibility));

  return jsonb_build_object('status','ok','ticket_type_id',p_ticket_type_id,'visibility',p_visibility);
end;
$$;

-- 9.6 venue.set_ticket_type_rank (160 PART 3)
create or replace function venue.set_ticket_type_rank(
  p_ticket_type_id uuid, p_display_rank smallint, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid;
  v_org_id uuid;
  v_venue  uuid;
  v_status text;
  v_old    smallint;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  -- validated here so the caller gets invalid_input, not the table CHECK's 23514.
  if p_display_rank is not null and (p_display_rank < 0 or p_display_rank > 999) then
    raise exception 'invalid_input: bad display_rank % (0..999 or NULL)', p_display_rank;
  end if;

  select tt.display_rank, e.org_id, e.venue_id, e.status
    into v_old, v_org_id, v_venue, v_status
    from venue.ticket_type tt
    join catalog.event e on e.event_id = tt.event_id
   where tt.ticket_type_id = p_ticket_type_id
   for update of tt;                                    -- rank 2, Inventory class (081:279)
  if v_org_id is null then
    raise exception 'not_found: ticket type %', p_ticket_type_id using errcode = 'P0002';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: event_terminal';
  end if;

  if not (kernel.has_org_role(v_org_id, array['org_owner','org_admin'])
          -- 162 (A's R3 ruling): the ORG arm binds to the EVENT's org — kernel.has_org_role on
          -- event.org_id, the 088:1629 cancel_event helper — no longer the venue's CURRENT org.
          or (kernel.has_venue_role(v_venue, array['venue_manager'])
              and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id))) then
    raise exception 'insufficient_privilege: venue_manager (current operator) or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  if v_old is not distinct from p_display_rank then
    return jsonb_build_object('status','noop','ticket_type_id',p_ticket_type_id,'display_rank',v_old);
  end if;

  update venue.ticket_type set display_rank = p_display_rank, updated_at = now()
   where ticket_type_id = p_ticket_type_id;

  -- no reason is required for a sort-order change (as create_ticket_type 081:232).
  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'ticket_type.rank_change', 'ticket_type', p_ticket_type_id, 'self_service',
          jsonb_build_object('display_rank', v_old), jsonb_build_object('display_rank', p_display_rank));

  return jsonb_build_object('status','ok','ticket_type_id',p_ticket_type_id,'display_rank',p_display_rank);
end;
$$;

-- ============================================================================
-- PART 10 — venue_api: three views re-created with the new columns appended LAST
-- (CREATE OR REPLACE keeps each view's ACL and comment; options re-stated)
-- ============================================================================
CREATE OR REPLACE VIEW venue_api.ticket_types
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT t.ticket_type_id, t.event_id, t.kind, t.name, t.price_minor, t.currency, t.visibility,
         t.created_at, t.updated_at, t.display_rank,
         t.sale_starts_at, t.sale_ends_at,
         venue.ticket_type_on_sale(t.ticket_type_id) AS on_sale_now
    FROM venue.ticket_type t;

CREATE OR REPLACE VIEW venue_api.events
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT e.event_id, e.venue_id, e.org_id, e.title, e.status, e.created_at, e.updated_at,
         e.age_policy, v.timezone
    FROM catalog.event e
    LEFT JOIN catalog.venue v ON v.venue_id = e.venue_id;

CREATE OR REPLACE VIEW venue_api.event_sessions
  WITH (security_invoker = true, security_barrier = true) AS
  SELECT s.session_id, s.event_id, s.session_label, s.starts_at, s.ends_at, s.doors_at,
         s.door_open_at, s.status, s.created_at, s.updated_at,
         v.timezone,
         to_char(s.starts_at AT TIME ZONE v.timezone, 'YYYY-MM-DD HH24:MI') AS starts_at_local,
         to_char(s.ends_at   AT TIME ZONE v.timezone, 'YYYY-MM-DD HH24:MI') AS ends_at_local,
         to_char(s.doors_at  AT TIME ZONE v.timezone, 'YYYY-MM-DD HH24:MI') AS doors_at_local
    FROM catalog.event_session s
    LEFT JOIN catalog.event e ON e.event_id = s.event_id
    LEFT JOIN catalog.venue v ON v.venue_id = e.venue_id;

-- ============================================================================
-- PART 11 — venue_cmd wrappers (161 pattern: SECURITY INVOKER, LANGUAGE sql,
-- one SELECT, the target's argument list and result type)
-- ============================================================================
create or replace function venue_cmd.set_venue_timezone(
  p_venue_id uuid, p_timezone text, p_reason_code text, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select catalog.set_venue_timezone(p_venue_id, p_timezone, p_reason_code, p_command_key)
$$;
comment on function venue_cmd.set_venue_timezone(uuid, text, text, text) is
  '162: invoker wrapper -> catalog.set_venue_timezone.';

create or replace function venue_cmd.set_event_age_policy(
  p_event_id uuid, p_age_policy text, p_reason_code text, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select catalog.set_event_age_policy(p_event_id, p_age_policy, p_reason_code, p_command_key)
$$;
comment on function venue_cmd.set_event_age_policy(uuid, text, text, text) is
  '162: invoker wrapper -> catalog.set_event_age_policy.';

create or replace function venue_cmd.set_session_sales_capacity(
  p_session_id uuid, p_capacity integer, p_reason_code text, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select catalog.set_session_sales_capacity(p_session_id, p_capacity, p_reason_code, p_command_key)
$$;
comment on function venue_cmd.set_session_sales_capacity(uuid, integer, text, text) is
  '162: invoker wrapper -> catalog.set_session_sales_capacity.';

create or replace function venue_cmd.set_ticket_type_sale_window(
  p_ticket_type_id uuid, p_sale_starts_at timestamptz, p_sale_ends_at timestamptz,
  p_reason_code text, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select venue.set_ticket_type_sale_window(p_ticket_type_id, p_sale_starts_at, p_sale_ends_at, p_reason_code, p_command_key)
$$;
comment on function venue_cmd.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text) is
  '162: invoker wrapper -> venue.set_ticket_type_sale_window.';

create or replace function venue_cmd.ticket_type_on_sale(
  p_ticket_type_id uuid, p_at timestamptz default now())
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select venue.ticket_type_on_sale(p_ticket_type_id, p_at)
$$;
comment on function venue_cmd.ticket_type_on_sale(uuid, timestamptz) is
  '162: invoker wrapper -> venue.ticket_type_on_sale (STABLE boolean read).';

-- ============================================================================
-- PART 12 — function ACLs (081 PART 16 pattern: strip PUBLIC/anon/authenticated,
-- grant exactly authenticated) — the five functions and the five wrappers
-- ============================================================================
do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'catalog.set_venue_timezone(uuid, text, text, text)',
    'catalog.set_event_age_policy(uuid, text, text, text)',
    'catalog.set_session_sales_capacity(uuid, integer, text, text)',
    'venue.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text)',
    'venue.ticket_type_on_sale(uuid, timestamptz)',
    'venue_cmd.set_venue_timezone(uuid, text, text, text)',
    'venue_cmd.set_event_age_policy(uuid, text, text, text)',
    'venue_cmd.set_session_sales_capacity(uuid, integer, text, text)',
    'venue_cmd.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text)',
    'venue_cmd.ticket_type_on_sale(uuid, timestamptz)'
  ];
begin
  foreach v_fn in array v_all loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end $$;

-- ============================================================================
-- POST — refuse to COMMIT unless the catalog ends in the state the header claims
-- ============================================================================
DO $post$
BEGIN
  IF (SELECT count(*) FROM pg_attribute WHERE attrelid = 'venue_api.ticket_types'::regclass AND attnum > 0 AND NOT attisdropped) <> 13
  OR (SELECT count(*) FROM pg_attribute WHERE attrelid = 'venue_api.events'::regclass AND attnum > 0 AND NOT attisdropped) <> 9
  OR (SELECT count(*) FROM pg_attribute WHERE attrelid = 'venue_api.event_sessions'::regclass AND attnum > 0 AND NOT attisdropped) <> 14 THEN
    RAISE EXCEPTION '162: a venue_api view does not carry the expected column count (13/9/14).';
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'venue_cmd' AND p.prosecdef) <> 0 THEN
    RAISE EXCEPTION '162: a venue_cmd wrapper is SECURITY DEFINER.';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'::regprocedure)
       IS DISTINCT FROM '30424f73432699526f4424bbcbf52c73'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'venue.set_batch_capacity(uuid, integer, text, text)'::regprocedure)
       IS DISTINCT FROM '7aa6b6d303276f44125ab91829689542' THEN
    RAISE EXCEPTION '162: a replaced batch writer body does not hash to this file''s text.';
  END IF;
END $post$;

COMMIT;
