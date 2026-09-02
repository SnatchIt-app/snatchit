-- ============================================================================
-- 089_market_bridge_view_and_late_fk.sql — Phase-2 package 089 (Phase J ADOPT)
-- ----------------------------------------------------------------------------
-- SOURCES (frozen; bytes win): plan §8/089 · registry row 089 (J2, "native
-- marketplace bridge (ADOPT)") · schema §4.6 (the bridge VIEW: PROJ, no write
-- authority) · RLS §10.6 / §12 / §14.1 (security_invoker, inherits base-table
-- policies, exposes ONLY the common discovery set, creates no authority) ·
-- SPEC_FOUNDATION §7 (integrate, never rewrite public.listings) · 085 §1.8
-- (payment_native.sale_id deferred FK) · CDM §1 C10 (rail ∈ native | external |
-- external_verified) · E-106 (owner-countersigned: no anon access to market).
-- DEPENDENCIES: 085 (kernel.payment_native), 088 (market.listing_native,
-- market.market_sale). CREATES: one VIEW + one FK. No table, no function, no
-- policy, no trigger, no cron, no seed, no seam. Additive; fully reversible.
-- ============================================================================
begin;

-- ============================================================================
-- PART 1 — market.listing_unified (schema §4.6; RLS §14.1). A read-only UNION
--   of the external rail (public.listings) and the native rail
--   (market.listing_native), projecting ONLY the common discovery set:
--   id · rail · event/session · price · seller · status · cover (+ currency,
--   created_at for ordering). security_invoker: every row is evaluated under
--   the CALLER's privileges and the base tables' own RLS — the bridge launders
--   no authority (RLS §14.1). No money/custody/PII column, no cross-rail join.
--   rail (E-114): the external rail is 'external_verified' exactly when
--   public.listings.proof_status = 'approved' (071's CHECK set: pending_review
--   | approved | rejected — 'approved' is the only verified-positive label; C10).
--   price_minor (E-115): public.listings prices are whole dollars (the live
--   feed renders allInFromDollars(listing.current_bid) → dollarsToCents); the
--   native rail is integer minor units. The bridge normalizes the external
--   price to minor units (× 100, integer); nothing is rounded or inferred.
--   Native arm (E-116): carries the DISCOVERY predicate explicitly —
--   status ∈ {active, reserved} (the 088 public-arm set, R-37) AND the
--   feature.native_resale_enabled flag (X-12: NULL ⇒ false) — so a seller's own
--   draft/cancelled rows (visible to them on the base table through the owner
--   arm) never surface through the bridge, and the native union is INERT while
--   the rail is dark (plan §8/089 "native rows filtered by the flag").
--   event_name for a native row resolves through catalog.event under the
--   caller's catalog policies (LEFT JOIN: a row is never lost, only unnamed).
-- ============================================================================
create or replace view market.listing_unified
with (security_invoker = true)
as
  select l.id                                                            as id,
         case when l.proof_status = 'approved' then 'external_verified'
              else 'external' end::text                                  as rail,
         null::uuid                                                      as event_session_id,
         l.event_name::text                                              as event_name,
         (l.current_bid::bigint * 100)::integer                          as price_minor,
         'USD'::text                                                     as currency,
         l.seller_id                                                     as seller_id,
         l.status::text                                                  as status,
         l.cover_image_path::text                                        as cover_image_path,
         l.created_at                                                    as created_at
    from public.listings l
  union all
  select n.listing_id                                                    as id,
         'native'::text                                                  as rail,
         n.event_session_id                                              as event_session_id,
         e.title::text                                                   as event_name,
         n.price_minor                                                   as price_minor,
         n.currency                                                      as currency,
         n.seller_id                                                     as seller_id,
         n.status::text                                                  as status,
         null::text                                                      as cover_image_path,
         n.created_at                                                    as created_at
    from market.listing_native n
    left join catalog.event_session es on es.session_id = n.event_session_id
    left join catalog.event e on e.event_id = es.event_id
   where n.status in ('active','reserved')
     and coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c
                    where c.key = 'feature.native_resale_enabled' order by c.version desc limit 1), false);

comment on view market.listing_unified is
  'Phase-2 bridge VIEW (schema §4.6; RLS §14.1): external ∪ native discovery projection. security_invoker; read-only; native rows only while feature.native_resale_enabled is ON. PROJ — owns no truth.';

-- Grants (RLS §10.6 rows; E-113): SELECT to authenticated and service_role. NO
-- anon grant: anon holds no USAGE on the market schema (076 wall) and the owner
-- countersigned E-106 (PFA-14 controlling — no anon direct market access, no
-- anon SELECT added "merely to support future discovery"); plan §8/089's
-- "anon/authenticated" Grants row is superseded by that later signed ruling.
revoke all on market.listing_unified from public, anon, authenticated, service_role;
grant select on market.listing_unified to authenticated, service_role;

-- ============================================================================
-- PART 2 — the late-binding FK (plan §8/089; 085 §1.8 deferred): payment_native
--   .sale_id → market.market_sale(sale_id) ON DELETE RESTRICT. NOT VALID then
--   VALIDATE (payment_native carries no sale-linked rows before 088's engine
--   ran — on an empty set the validation is instant; on any set it proves the
--   rows). RESTRICT: a consummated sale's payment link is never orphaned.
-- ============================================================================
alter table kernel.payment_native
  drop constraint if exists fk_payment_native_sale;
alter table kernel.payment_native
  add constraint fk_payment_native_sale
  foreign key (sale_id) references market.market_sale(sale_id) on delete restrict
  not valid;
alter table kernel.payment_native validate constraint fk_payment_native_sale;

commit;
