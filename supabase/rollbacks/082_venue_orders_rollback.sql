-- ============================================================================
-- ROLLBACK for 082_venue_orders.sql
-- POSTURE: CLEAN-WHILE-EMPTY (plan §8/082). Refuses once any order or consent row
-- exists — a live order/consent is forward-fix territory, never destroyed to make
-- rollback easy.
--
-- ORDER-OF-OPERATIONS NOTE (090): 090 ADOPTS two FK constraints onto
-- venue.order.attribution_candidate_code_id/_link_id. If 090 is ever applied,
-- ITS rollback must run first to drop those constraints; at this package no such
-- constraint exists (the columns are plain uuid here), so this script stands alone.
--
-- Restores post-081 state EXACTLY: kernel.deletion_blockers_orders is put back to
-- its 077 neutral stub VERBATIM (OR-17 F-5 rider — a rolled-back replacer must
-- never leave a body referencing a dropped table live under the deletion sweep).
-- HARDENING-1, the 079 BP-1 body, the 080 staff cleanup, the 081 inventory
-- substrate, PFA-14, PFA-13, E-22/E-23 (remaining arms), E-27, E-28/E-31/E-32/E-33
-- are all untouched — 082 replaced no other SEAM-2 stub and altered no earlier object.
-- ============================================================================

begin;

-- PART 0 — refusal guard. Count authoritatively regardless of the executing role
-- (row_security off): the two consent tables are deny-all zero-policy, so a
-- non-BYPASSRLS runner would count 0 and could false-negative — with row_security
-- off the owner/BYPASSRLS runner gets the true count and a non-privileged runner
-- ERRORS here and aborts. Fail-safe either way.
do $$
declare
  v_o bigint := 0; v_oi bigint := 0; v_cc bigint := 0; v_cce bigint := 0;
begin
  set local row_security = off;
  if to_regclass('venue.order')                     is not null then execute 'select count(*) from venue."order"'                    into v_o;   end if;
  if to_regclass('venue.order_item')                is not null then execute 'select count(*) from venue.order_item'                 into v_oi;  end if;
  if to_regclass('kernel.org_contact_consent')      is not null then execute 'select count(*) from kernel.org_contact_consent'       into v_cc;  end if;
  if to_regclass('kernel.org_contact_consent_event') is not null then execute 'select count(*) from kernel.org_contact_consent_event' into v_cce; end if;
  if v_o > 0 or v_oi > 0 or v_cc > 0 or v_cce > 0 then
    raise exception 'REFUSED: 082 holds rows (order=%, order_item=%, org_contact_consent=%, org_contact_consent_event=%). CLEAN-WHILE-EMPTY only (plan §8/082) — a live order/consent is forward-fix territory.',
      v_o, v_oi, v_cc, v_cce;
  end if;
end $$;

-- PART 1 — OR-17 F-5: restore the 077 neutral stub of kernel.deletion_blockers_orders, VERBATIM.
create or replace function kernel.deletion_blockers_orders(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$ select null::text $$;   -- BP-12 pending-order arm; real body 082

-- PART 2 — 082-authored RPCs (none is depended on by a surviving trigger).
drop function if exists venue.create_primary_checkout(uuid, jsonb, uuid[], text);
drop function if exists venue.cancel_pending_order(uuid, text, text);
drop function if exists kernel.grant_org_contact_consent(uuid, text, uuid);
drop function if exists kernel.withdraw_org_contact_consent(uuid);
drop function if exists kernel.list_my_org_contact_consents();

-- PART 3 — tables (children first; dropping each removes its triggers). The two
-- consent tables and order_item all FK into venue."order", so it drops last.
drop table if exists venue.order_item;
drop table if exists kernel.org_contact_consent_event;
drop table if exists kernel.org_contact_consent;
drop table if exists venue."order";

-- PART 4 — the two bespoke trigger functions (now no trigger depends on them).
drop function if exists venue.guard_order_item_immutable();
drop function if exists venue.guard_order_candidate_freeze();

commit;
