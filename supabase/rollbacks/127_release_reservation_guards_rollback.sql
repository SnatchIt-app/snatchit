-- ============================================================================
-- 127_release_reservation_guards_rollback.sql — restores the pre-127 state:
-- `public.release_reservation` returns to its APPLIED (0590) body (sold +
-- hold-ownership checks only, no succeeded-payment guard, no comment), and
-- `public.release_reservation_for_payment` is dropped.
--
-- WHAT THIS RE-INTRODUCES, deliberately and on the record: L2 (a live release
-- can free a PAID order's hold between the payment succeeding and the listing
-- reading `sold`) and L1 (a stale cancellation can free a hold taken after the
-- payment it claims to belong to). Production is forward-only by policy; this
-- is an emergency measure needing its own authorization.
--
-- The pre-127 state is 0590's body, NOT 000_baseline's: 0590 removed the last
-- `coalesce(auth.uid(), p_user_id)` fallbacks, and a rollback that restored the
-- baseline would silently undo that applied hardening. Body-only, grants preserved. Census -1
-- (the new function goes away). Any caller of release_reservation_for_payment
-- MUST be redeployed to the pre-127 webhook first, or it will fail PGRST202 /
-- undefined_function.
-- ============================================================================
begin;

drop function if exists public.release_reservation_for_payment(uuid, uuid, uuid);

create or replace function public.release_reservation(
  p_listing_id uuid,
  p_user_id    uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id   uuid;        -- resolved identity: auth.uid() or p_user_id
  v_status      text;
  v_reserved_by uuid;
begin
  -- SECURITY (0590): auth.uid() is authoritative. p_user_id is honoured ONLY for a
  -- verified service-role caller. 0590 removed the last
  -- identity-fallback coalesces precisely so a future re-GRANT
  -- could not silently reopen that hole. Do not reintroduce one.
  v_caller_id := auth.uid();
  if v_caller_id is null and public.request_is_service_role() then
    v_caller_id := p_user_id;
  end if;

  -- 1) Lock the listing row.
  select status, reserved_by
    into v_status, v_reserved_by
    from public.listings
   where id = p_listing_id
     for update;

  if not found then
    return;  -- nothing to release
  end if;

  -- 2) Already sold — no-op (purchase went through on another device / tab).
  if v_status = 'sold' then
    return;
  end if;

  -- 3) Only release if still reserved by this same caller.
  if v_status = 'reserved' and v_reserved_by = v_caller_id then
    perform set_config('app.bypass_listing_guard', 'on', true);
    update public.listings
       set status         = 'active',
           reserved_by    = null,
           reserved_until = null
     where id = p_listing_id;
  end if;

  -- Any other state (active, reserved by someone else) — no-op.
end;
$$;

comment on function public.release_reservation(uuid, uuid) is null;

commit;
