-- ============================================================================
-- 20260909000000_kernel_my_tickets_read.sql
-- Tickets frontend contract — the owner-scoped ticket ownership READ.
--
-- WHAT THIS ADDS
--   public.get_my_tickets() — a single SECURITY DEFINER, owner-scoped,
--   NO-ARGUMENT RPC that returns the caller's owned tickets as an EVENT-FIRST,
--   grouped projection with a STABLE frontend-facing vocabulary. It is the one
--   read the mobile client calls for the "Your Tickets" surface (Upcoming /
--   Past). It joins catalog.event_session / catalog.event / catalog.venue /
--   venue.ticket_type server-side so the client never reconstructs the event
--   from privileged joins, and it exposes ONLY frontend-safe fields.
--
-- WHY AN RPC (not a client view / raw table SELECT)
--   kernel.tickets already carries owner RLS (079 kernel_tickets_sel_owner) and
--   a column-narrowed authenticated grant (080). A raw client SELECT would
--   therefore work but would (a) force the client to join catalog/venue itself,
--   (b) leak the raw internal state vocabulary ('issued'/'scanned'/…,
--   'refund_hold'/…), and (c) expose a per-row filter surface. This RPC removes
--   all three: it takes NO user/ticket/event argument, so cross-user reads are
--   STRUCTURALLY impossible (the body binds to auth.uid()); it projects the
--   internal state machine to a small stable vocabulary; and it returns a
--   grouped, event-first shape.
--
-- OWNERSHIP / STATUS VOCABULARY (projected from kernel.tickets.state)
--   'valid'   <- state in ('issued','active')   -- owned and usable
--   'used'    <- state = 'scanned'              -- already admitted
--   'void'    <- state = 'voided'
--   'expired' <- state = 'expired'
--
-- FULFILLMENT / DELIVERY VOCABULARY (projected from kernel.tickets.resale_state)
--   'held'         <- 'none'         -- owned outright, no resale/transfer motion
--   'listed'       <- 'listed'       -- owner has it listed for resale
--   'in_transfer'  <- 'locked'       -- a sale/transfer is locked / in progress
--   'payment_hold' <- 'refund_hold'  -- money-side hold
--   'disputed'     <- 'dispute_hold'
--
-- TIME CLASS (upcoming vs past)
--   'past'     when coalesce(session.ends_at, session.starts_at) < now()
--   'upcoming' otherwise
--   All timestamps are timestamptz (absolute instants); classification is in
--   UTC via now(). starts_at is NOT NULL on catalog.event_session, so the
--   coalesce only falls back when ends_at is absent. A ticket keeps its time
--   class regardless of ownership_status (a 'void'/'expired' ticket still sorts
--   by its event time); the two axes are independent and both returned.
--
-- EMPTY STATE
--   An authenticated caller with no owned tickets gets ZERO rows (HTTP 200 []).
--   That success-empty is distinct from an auth failure (see below) and from a
--   transport/5xx failure — the frontend must not treat empty as an error.
--
-- ERROR VOCABULARY
--   anon / no JWT            -> EXECUTE is not granted to anon; PostgREST returns
--                              a permission error (SQLSTATE 42501). Treat as an
--                              auth failure, never as empty.
--   authenticated, null uid  -> raise 'tickets_unauthenticated' (SQLSTATE 28000)
--                              — defense in depth; should not occur on a real JWT.
--   Everything else is success (rows or empty). There is no not-found: this is a
--   list. Transient/internal failures surface as PostgREST 5xx (retryable).
--
-- DATA MINIMIZATION — fields deliberately NOT returned
--   current_owner_id (it IS the caller), serial_no, org_id, signing_key_id,
--   credential_version, unit_row_id, external_seat_ref, seat_ref, price/currency,
--   and anything from kernel.ticket_ownership_log. No payment/Stripe identifiers,
--   no credential/signing/redemption material, no fraud/risk fields, no
--   seller/buyer private data — none of it is on the projection.
--
-- QR / BARCODE / APPLE WALLET are a SEPARATE future contract and are NOT part of
--   this read. No credential surface is added or referenced here.
--
-- FORWARD BEHAVIOR / PRODUCTION IMPACT
--   Additive and read-only: creates one function + its grant. No table, RLS,
--   trigger, or data is touched. Native issuance is seeded OFF
--   (feature.native_issuance_enabled = false, 078) and no custody writer is
--   active, so in production TODAY this returns the defined empty set for every
--   caller until issuance is enabled and tickets are minted. FORWARD-ONLY.
--
-- ROLLBACK   supabase/rollbacks/20260909000000_kernel_my_tickets_read_rollback.sql
-- VERIFY (after apply)
--   select proname, prosecdef, proconfig
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and proname = 'get_my_tickets';
--   -- prosecdef = t ; proconfig contains search_path=public, pg_temp
--   select has_function_privilege('authenticated','public.get_my_tickets()','execute'); -- t
--   select has_function_privilege('anon','public.get_my_tickets()','execute');          -- f
-- EXPECTED LOCKS/RUNTIME  catalog row creation only; milliseconds.
-- ============================================================================

create or replace function public.get_my_tickets()
returns table (
  event_id           uuid,
  event_session_id   uuid,
  event_title        text,
  session_label      text,
  starts_at          timestamptz,
  ends_at            timestamptz,
  doors_at           timestamptz,
  venue_id           uuid,
  venue_name         text,
  artwork_ref        text,
  ticket_type_id     uuid,
  ticket_type_name   text,
  ticket_type_kind   text,
  quantity           integer,
  ownership_status   text,
  fulfillment_status text,
  time_class         text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  -- Fail closed. anon is already blocked by the EXECUTE grant; this covers an
  -- authenticated role that somehow presents no subject claim.
  if v_uid is null then
    raise exception 'tickets_unauthenticated' using errcode = '28000';
  end if;

  return query
  select
    e.event_id,
    s.session_id                                   as event_session_id,
    e.title                                        as event_title,
    s.session_label,
    s.starts_at,
    s.ends_at,
    s.doors_at,
    v.venue_id,
    v.name                                         as venue_name,
    e.hero_image_ref                               as artwork_ref,
    tt.ticket_type_id,
    tt.name                                        as ticket_type_name,
    tt.kind                                        as ticket_type_kind,
    count(*)::integer                              as quantity,
    -- ownership_status: internal lifecycle -> stable frontend vocabulary.
    (case t.state
       when 'issued'  then 'valid'
       when 'active'  then 'valid'
       when 'scanned' then 'used'
       when 'voided'  then 'void'
       when 'expired' then 'expired'
       else 'valid'
     end)                                          as ownership_status,
    -- fulfillment_status: internal resale overlay -> stable frontend vocabulary.
    (case t.resale_state
       when 'none'         then 'held'
       when 'listed'       then 'listed'
       when 'locked'       then 'in_transfer'
       when 'refund_hold'  then 'payment_hold'
       when 'dispute_hold' then 'disputed'
       else 'held'
     end)                                          as fulfillment_status,
    (case when coalesce(s.ends_at, s.starts_at) < now() then 'past' else 'upcoming' end)
                                                   as time_class
  from kernel.tickets t
  join catalog.event_session s on s.session_id     = t.event_session_id
  join catalog.event         e on e.event_id       = s.event_id
  join catalog.venue         v on v.venue_id       = e.venue_id
  join venue.ticket_type     tt on tt.ticket_type_id = t.ticket_type_id
  where t.current_owner_id = v_uid
  group by
    e.event_id, s.session_id, e.title, s.session_label, s.starts_at, s.ends_at,
    s.doors_at, v.venue_id, v.name, e.hero_image_ref, tt.ticket_type_id, tt.name,
    tt.kind,
    (case t.state
       when 'issued'  then 'valid'  when 'active'  then 'valid'
       when 'scanned' then 'used'   when 'voided'  then 'void'
       when 'expired' then 'expired' else 'valid' end),
    (case t.resale_state
       when 'none' then 'held' when 'listed' then 'listed'
       when 'locked' then 'in_transfer' when 'refund_hold' then 'payment_hold'
       when 'dispute_hold' then 'disputed' else 'held' end)
  order by
    -- Upcoming first (soonest first), then Past (most recent first).
    (case when coalesce(s.ends_at, s.starts_at) < now() then 1 else 0 end) asc,
    (case when coalesce(s.ends_at, s.starts_at) >= now() then s.starts_at end) asc nulls last,
    (case when coalesce(s.ends_at, s.starts_at) <  now() then s.starts_at end) desc nulls last,
    e.title asc;
end;
$$;

comment on function public.get_my_tickets() is
  'Owner-scoped, event-first ticket ownership read for the mobile Tickets surface. '
  'No arguments; binds to auth.uid(). Returns grouped rows with stable '
  'ownership_status / fulfillment_status / time_class vocabularies. Frontend-safe '
  'fields only; no payment, credential, or private data. Empty set = no tickets. '
  'See 20260909000000_kernel_my_tickets_read.sql and TICKETS_FRONTEND_CONTRACT_HANDOFF.md.';

-- Function ACLs (I-7: strip PUBLIC, then grant exactly). anon is intentionally
-- excluded so an unauthenticated caller is denied at the ACL, never served empty.
revoke all on function public.get_my_tickets() from public;
revoke all on function public.get_my_tickets() from anon;
grant execute on function public.get_my_tickets() to authenticated;
