-- ============================================================================
-- 091_kernel_reserve_stub.sql — Phase-2 package 091 (registry §2 row 091 "K —
-- money-ledger extensions"; plan §8/091; schema §1.11 EXT (Gate-M stub only);
-- RLS §7.11 money-custody-RPC-only DENY-ALL; writer registry row kernel.reserve
-- = NONE-wired-in-MVP; parity 091|kernel.reserve|table; E-149/E-150 (this pkg)).
-- ----------------------------------------------------------------------------
-- THE CLOSED WORLD: ONE table, kernel.reserve, created EMPTY-SHAPED so the
-- Gate-M extension point exists in the chain with its RLS/grants correct from
-- day one. NOTHING ELSE: no function, no RPC, no policy, no writer, no reserve
-- math, no clawback, no double-entry ledger, no cron row, no config key, no
-- seed, no edge, no SEAM hook (C29/C30/C31 = Gate-M; schema §11 extension
-- points). Its defining property is that it is ALWAYS EMPTY and ALWAYS
-- DROPPABLE; nothing may be added to it (plan §8/091). This is the C29 money
-- reserve — NOT an inventory reservation object (inventory holds live in venue,
-- 081) — so no inventory lock class, TTL or oversell rule exists here.
--
-- Shape (plan §8/091 · schema §1.11): reserve_id PK · org_id FK→kernel.
-- organization (NOT NULL — an ownerless reserve row has no meaning; the frozen
-- text states the FK, not its nullability: E-149) · balance_minor integer
-- default 0 (NO CHECK — none is stated; a Gate-M receivable posture is not
-- pre-empted: E-149) · currency default 'USD' · created_at/updated_at with the
-- 076 set_updated_at trigger (plan Triggers row). PK only.
-- Grants: REVOKE ALL from anon/authenticated (plan Grants row). RLS §7.11's
-- service_role `A(machine)` cell is NOT delivered (E-118 class — no dormant
-- machine grant on a money table; every 085 money ledger carries none): E-150.
-- ============================================================================
begin;

create table if not exists kernel.reserve (
  reserve_id    uuid primary key default gen_random_uuid(),
  org_id        uuid not null references kernel.organization(org_id) on delete restrict,
  balance_minor integer not null default 0,
  currency      text not null default 'USD',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

drop trigger if exists tg_reserve_set_updated_at on kernel.reserve;
create trigger tg_reserve_set_updated_at before update on kernel.reserve
  for each row execute function kernel.set_updated_at();

-- money-custody-RPC-only, DENY-ALL: RLS on, ZERO policies, no client grant
alter table kernel.reserve enable row level security;
revoke all on kernel.reserve from public, anon, authenticated, service_role;

commit;
