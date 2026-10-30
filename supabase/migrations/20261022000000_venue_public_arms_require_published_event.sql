-- ============================================================================
-- 20261022000000_venue_public_arms_require_published_event.sql — registry 176 (pgTAP 246).
-- The public read arms of venue.ticket_type and venue.inventory_batch now also require a published
-- (non-draft) parent event. Every other arm, name, role, command and grant is unchanged.
--
-- Registry 176 / pgTAP 246, allocated by A (origin/a/registry-20261021: 912c81aa allocates it, tip 14f3e8ec
-- records "written by F, reviewed by A").
-- A reviews before this leaves draft. Owner decision 2026-10-21 (V-13): fix draft-event ticket
-- visibility before venue_api is exposed.
--
-- WHY (A's review of 159, owner decision V-13). 081 created the two public arms as
--     venue_ticket_type_sel_public      FOR SELECT TO authenticated USING (visibility = 'public')
--     venue_inventory_batch_sel_public  FOR SELECT TO authenticated USING (EXISTS (public ticket type))
-- Neither looks at the parent event, so ANY signed-in user (no org or venue role) reads a public ticket
-- type's name and price_minor, and its batch's `remaining`, while the event is still a DRAFT that the same
-- user cannot read in catalog.event (078 catalog_event_sel_anon: status <> 'draft'). venue_api (159) does
-- not widen this (security_invoker, view = base under RLS), but exposing venue_api in the Data API would
-- make it readable over REST. anon is not affected today and is not affected after: 076 gives schema
-- venue USAGE to authenticated only (081 E-30), and both policies stay TO authenticated.
--
-- WHAT. Each public arm keeps its predicate and gains a published parent:
--   venue_ticket_type_sel_public:
--     visibility = 'public' AND EXISTS (catalog.event e: e.event_id = the type's event_id
--                                       AND e.status <> 'draft')
--   venue_inventory_batch_sel_public:
--     EXISTS (venue.ticket_type tt JOIN catalog.event e ON e.event_id = tt.event_id:
--             tt.ticket_type_id = the batch's ticket_type_id AND tt.visibility = 'public'
--             AND e.status <> 'draft')
--   The rule is catalog_event_sel_anon's, verbatim: status <> 'draft', never status >= 'announced'
--   (R3-3a, 078: status is TEXT with a CHECK, so >= is lexicographic and 'announced' sorts first —
--   ">= 'announced'" is true for 'draft' too). announced, on_sale, live, completed and cancelled events
--   keep their public types and batches readable, exactly as catalog.event keeps those events readable.
--   The batch resolves its event through its ticket type, as 081's own public and venue arms do. Its
--   event_session belongs to the same event: create_inventory_batch (081) refuses
--   type_session_event_mismatch, it is the only INSERT path for batches, and no writer updates
--   ticket_type_id or event_session_id.
--
-- WHAT STAYS. Policy names, FOR SELECT, TO authenticated, PERMISSIVE. venue_ticket_type_sel_venue and
--   venue_inventory_batch_sel_venue (081) are not touched, so venue_manager, org_owner and org_admin
--   still read a draft's types (hidden included) and batches; org_finance, venue_finance and
--   venue_scanner still read a draft's batches; every lower staff tier still reads a draft's non-hidden
--   types. Column grants (081 E-29: capacity/held/sold withheld), table grants, RLS enablement and every
--   function are untouched. Every SECURITY DEFINER reader (create_primary_checkout, publish_event,
--   get_my_tickets, the market and promoter readers, ...) runs as the table owner and bypasses RLS, so it
--   is unaffected (docs/venue-dashboard/176_READERS.md lists all twenty).
--
-- CONSEQUENCE (deliberate, listed in 176_READERS.md for A and D). A role whose ONLY path to a draft's
--   public batch was the public arm loses it until the event is published. org_member, venue_box_office,
--   venue_marketing and venue_promoter_manager still read the draft's non-hidden TYPES through the
--   unchanged venue arm, but none of them is in 081's batch venue arm, so the draft's batches disappear
--   for them. org_marketing, org_promoter_manager and the platform labels hold no arm on either table
--   (the console reads through ops.* definers, none of which reads these tables), so they now see what
--   any signed-in user sees. Of all these, only org_member can open a draft event at all (078
--   catalog_event_sel_org); the lower venue labels cannot read a draft in catalog.event (080
--   catalog_event_sel_venue, T-RLS-CAT-01). Every role's view of a non-draft event is unchanged.
--
-- RECURSION (42P17) — none, by the 078 pattern. Parent visibility is an inline EXISTS through the parent,
--   the shape 078 uses for catalog_event_session_sel_anon and catalog_resale_policy_sel_public and 081
--   uses for the batch arm itself; no new SECURITY DEFINER helper (078's resale_policy note: a new helper
--   is an object the closed world does not carry). The subqueries run under the caller's RLS:
--     ticket_type -> catalog.event      catalog.event's policies call only kernel.has_org_role,
--                                       kernel.is_platform and kernel.has_venue_role (definers over
--                                       kernel.org_member / kernel.platform_role / venue.staff_role);
--                                       none reads venue.ticket_type or venue.inventory_batch.
--     inventory_batch -> ticket_type, catalog.event    ticket_type's policies read catalog.event and the
--                                       080 definer helpers; nothing reads venue.inventory_batch back.
--   No cycle. The explicit e.status <> 'draft' makes each arm independent of WHICH catalog.event arm
--   admitted the row: every non-draft event is visible to every authenticated caller through
--   catalog_event_sel_anon, and a draft fails the conjunct whoever reads it. authenticated already holds
--   USAGE on catalog and SELECT (event_id, status) on catalog.event (076, 078). No function is created,
--   so no search_path question arises.
--
-- ORDER. After 159 (20261021120000, venue_api) and after A's 173-175 (20261021133000, 20261021134000,
--   20261021135000); before 177 (20261022001000) and 178 (20261022002000). Before the owner adds
--   venue_api to the Data API exposed schemas. Independent of 157/158/170-175 by object: none of them
--   touches the venue or catalog schemas (157, 158 and 170-172 checked by reading their files; 173-175
--   by their registry descriptions only, because they were not pushed when this was written).
--
-- GATE-2 (public census): unchanged. Nothing is created in public; the counters (incl. EXPECT_POLICIES)
--   read schemaname = 'public' only. Four-file rule: the grant-decision manifest, expected_grants.txt and
--   parity_grants.sql are public-only and carry no venue policy row; no table or function is added.
--   pgTAP 246 pins both new definitions and both unchanged _venue definitions.
-- ROLLBACK: supabase/rollbacks/20261022000000_venue_public_arms_require_published_event_rollback.sql —
--   restores 081's two public arms verbatim (and so REOPENS the draft read). Touches nothing else.
-- VERIFY (read-only): select tablename, policyname, roles, cmd, permissive, qual from pg_policies
--   where schemaname = 'venue' and policyname in ('venue_ticket_type_sel_public',
--   'venue_inventory_batch_sel_public');  -- {authenticated} | SELECT | PERMISSIVE | qual has <> 'draft'
-- FAILURE BEHAVIOUR: one transaction; lock_timeout 3s. DROP/CREATE POLICY take a brief ACCESS EXCLUSIVE
--   lock on venue.ticket_type and venue.inventory_batch (ACCESS SHARE on catalog.event while the
--   expressions are parsed); it fails cleanly rather than queue. The closing DO block refuses to COMMIT
--   unless each table ends with exactly its two policies, both public arms SELECT / PERMISSIVE / TO
--   authenticated with no WITH CHECK, and both public quals carry the draft conjunct.
-- OWNER APPROVAL POINT: prepared locally only; applying it to any project is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ticket_type: `public`-visibility read to any authenticated principal, for a published event only.
drop policy if exists venue_ticket_type_sel_public on venue.ticket_type;
create policy venue_ticket_type_sel_public
  on venue.ticket_type for select to authenticated
  using (visibility = 'public'
         and exists (select 1 from catalog.event e
                      where e.event_id = venue.ticket_type.event_id
                        and e.status <> 'draft'));

-- inventory_batch: `remaining` of a public type's batch, for a published event only.
drop policy if exists venue_inventory_batch_sel_public on venue.inventory_batch;
create policy venue_inventory_batch_sel_public
  on venue.inventory_batch for select to authenticated
  using (exists (select 1 from venue.ticket_type tt
                   join catalog.event e on e.event_id = tt.event_id
                  where tt.ticket_type_id = venue.inventory_batch.ticket_type_id
                    and tt.visibility = 'public'
                    and e.status <> 'draft'));

DO $post$
DECLARE
  v_auth oid := (SELECT oid FROM pg_roles WHERE rolname = 'authenticated');
  v_names text;
  v_bad int;
BEGIN
  SELECT string_agg(c.relname || '.' || p.polname, ',' ORDER BY c.relname, p.polname) INTO v_names
    FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'venue' AND c.relname IN ('ticket_type', 'inventory_batch');
  IF v_names IS DISTINCT FROM
     'inventory_batch.venue_inventory_batch_sel_public,inventory_batch.venue_inventory_batch_sel_venue,'
     || 'ticket_type.venue_ticket_type_sel_public,ticket_type.venue_ticket_type_sel_venue' THEN
    RAISE EXCEPTION '176: unexpected policy set on venue.ticket_type / venue.inventory_batch: %', v_names;
  END IF;

  SELECT count(*) INTO v_bad
    FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'venue'
     AND p.polname IN ('venue_ticket_type_sel_public', 'venue_inventory_batch_sel_public')
     AND NOT (p.polcmd = 'r'
              AND p.polpermissive
              AND p.polroles = ARRAY[v_auth]
              AND p.polwithcheck IS NULL
              AND position('<> ''draft''' IN pg_get_expr(p.polqual, p.polrelid)) > 0
              AND position('>=' IN pg_get_expr(p.polqual, p.polrelid)) = 0);
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '176: % public arm(s) are not SELECT / PERMISSIVE / TO authenticated with the draft conjunct', v_bad;
  END IF;
END
$post$;

COMMIT;
