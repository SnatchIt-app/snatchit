-- Registry 208. Installation leaves this policy inactive. Arm or clear it only
-- while issuance is off and primary checkout writers are drained.
begin;
set local lock_timeout = '3s';

create table venue.primary_checkout_pilot (
  singleton boolean primary key default true check (singleton),
  batch_id uuid not null references venue.inventory_batch(batch_id) on delete restrict,
  event_session_id uuid not null references catalog.event_session(session_id) on delete restrict,
  buyer_id uuid not null references auth.users(id) on delete restrict,
  expires_at timestamptz not null
);
alter table venue.primary_checkout_pilot enable row level security;
revoke all on table venue.primary_checkout_pilot from public, anon, authenticated, service_role;

create function venue.guard_primary_checkout_pilot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $pilot$
declare
  pilot venue.primary_checkout_pilot%rowtype;
begin
  select * into pilot from venue.primary_checkout_pilot where singleton;
  if not found then
    return new;
  end if;

  -- Keep rejecting inserts after expiry until the operator closes the pilot.
  if clock_timestamp() >= pilot.expires_at or not exists (
    select 1 from venue.inventory_batch
    where batch_id = pilot.batch_id and event_session_id = pilot.event_session_id
  ) then
    raise exception 'precondition_failed: primary_checkout_pilot_restricted' using errcode = 'P0001';
  end if;

  if tg_table_name = 'inventory_hold' then
    if new.batch_id is not distinct from pilot.batch_id
       and new.identity_id is not distinct from pilot.buyer_id
       and new.quantity = 1 then
      return new;
    end if;
  elsif new.event_session_id is not distinct from pilot.event_session_id
        and new.buyer_id is not distinct from pilot.buyer_id then
    return new;
  end if;

  raise exception 'precondition_failed: primary_checkout_pilot_restricted' using errcode = 'P0001';
end;
$pilot$;
revoke all on function venue.guard_primary_checkout_pilot() from public, anon, authenticated, service_role;

create trigger tg_primary_checkout_pilot_hold
before insert on venue.inventory_hold
for each row execute function venue.guard_primary_checkout_pilot();

create trigger tg_primary_checkout_pilot_order
before insert on venue."order"
for each row execute function venue.guard_primary_checkout_pilot();

commit;
