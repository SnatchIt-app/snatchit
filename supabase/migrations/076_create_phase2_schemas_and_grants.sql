-- 076_create_phase2_schemas_and_grants.sql
-- =============================================================================
-- PHASE 2 · PACKAGE 076 — schema skeleton + GRANT boundary + shared helpers
--                        + the transactional outbox foundation (OR-12/OR-4/OR-14)
--
-- FROZEN ARCHITECTURE BASELINE: 06fd5ecccc405f416e8f27591ccbbf709771f8ef
--   (tag phase2-architecture-v2; governance seal fe57307). This file is an
--   IMPLEMENTATION of that frozen corpus:
--     plan      §8  `076_create_phase2_schemas_and_grants`
--     registry  package A / 076 (scope + REVERSIBLE rollback posture)
--     contracts §17.24 / §17.24a (emit pair, OR-14 two-behavior ruling)
--     contracts §20.16 (kernel.set_updated_at)
--     schema    §13.3 (the C12 envelope — column-for-column)
--     closed world: 076|{kernel.raise_append_only, kernel.set_updated_at,
--                        notify.outbox, notify.emit_event,
--                        notify.emit_event_required}
--   Nothing here is a design decision. Deviations require a POST-FREEZE
--   AMENDMENT (docs/architecture/_governance/PHASE_2_ARCHITECTURE_FREEZE.md §4).
--
-- DEPENDENCIES: precondition chain only (the applied pre-076 ledger). No
--   Phase-2 object from 077–092 is referenced — notify.outbox carries ZERO FK
--   dependencies by design (aggregate_kind/aggregate_id are polymorphic), and
--   the emit pair reads/writes notify.outbox only.
--
-- ROLLBACK POSTURE (frozen): REVERSIBLE while notify.outbox is EMPTY;
--   CLEAN-WHILE-EMPTY once envelopes exist (a cascade drop would destroy
--   undrained mandatory-notice carriers). supabase/rollbacks/076_*.sql guards
--   this with an explicit emptiness check.
--
-- OR-1 (O17/MD-2): the crm_export_builder role is NOT created here and must
--   not exist anywhere in the chain — asserted by the inverted D-1 test
--   (choice 9, OR-12) in supabase/tests/140_phase2_outbox_foundation.sql.
--
-- LOCKS / RUNTIME: new-object DDL only — no lock on any existing relation;
--   runtime well under a second on any size database.
-- VERIFICATION QUERY:
--   select (select count(*) from information_schema.schemata
--            where schema_name in ('kernel','catalog','venue','market','notify')) = 5
--      and to_regclass('notify.outbox') is not null
--      and (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--            where n.nspname='notify' and p.proname like 'emit_event%') = 2;
-- =============================================================================

-- =============================================================================
-- PART 1 — the five MVP schemas (kernel, catalog, venue, market + notify/OR-12)
-- =============================================================================

-- Defensively idempotent per the frozen global property (plan §0.5: "every
-- migration is defensively idempotent — create schema/table/index if not
-- exists, create or replace function"; review D-F1).
create schema if not exists kernel;
create schema if not exists catalog;
create schema if not exists venue;
create schema if not exists market;
create schema if not exists notify;

-- =============================================================================
-- PART 2 — the modular-monolith GRANT boundary (frozen §8/076 Grants row)
--
--   REVOKE ALL ON SCHEMA kernel, venue, market, notify FROM PUBLIC, anon,
--     authenticated                          (deny-by-default wall from birth)
--   GRANT USAGE ON catalog TO anon, authenticated   (public read plane; its
--     tables' own RLS/grants land with 078)
--   GRANT USAGE ON kernel, venue, market TO authenticated — for function
--     EXECUTE only: every function in those schemas carries its own explicit
--     EXECUTE grant/revoke per its contract; USAGE alone confers nothing.
--   service_role is a machine identity, never a human grant target; it gets
--     USAGE on notify because the emit pair is service_role-only (NOTIF §4.3).
-- =============================================================================

revoke all on schema kernel  from public, anon, authenticated;
revoke all on schema venue   from public, anon, authenticated;
revoke all on schema market  from public, anon, authenticated;
revoke all on schema notify  from public, anon, authenticated;

grant usage on schema catalog to anon, authenticated;
grant usage on schema kernel  to authenticated;
grant usage on schema venue   to authenticated;
grant usage on schema market  to authenticated;

-- Derivation (review D-F6): the frozen Grants row omits this line, but
-- contracts §17.24 EXEC: DEF + NOTIF §4.3 "service_role-only" mandate the
-- emit-pair EXECUTE grant, and EXECUTE is inert without schema USAGE — the
-- grant is uniquely determined (freeze §2.5).
grant usage on schema notify  to service_role;

-- The ALTER DEFAULT PRIVILEGES belt (frozen: "revokes table rights from
-- anon/authenticated so future tables are deny-by-default BEFORE their own RLS
-- lands", extended to notify by OR-12/F-P1-7). Accuracy note (review A-F5):
-- for TABLES the built-in Postgres default already grants nothing, so these
-- REVOKEs store no pg_default_acl row — deny-by-default for future tables is
-- carried by the built-in default and this belt makes the intent explicit;
-- production's permissive default-ACL rows are all nspname='public' (074's
-- catalog quotes) and never reach these schemas.
alter default privileges in schema kernel revoke all on tables from public, anon, authenticated;
alter default privileges in schema venue  revoke all on tables from public, anon, authenticated;
alter default privileges in schema market revoke all on tables from public, anon, authenticated;
alter default privileges in schema notify revoke all on tables from public, anon, authenticated;

-- PFA-1 (2026-08-30 — RECORDED IMPOSSIBILITY, see
-- _governance/POST_FREEZE_AMENDMENTS.md): a per-schema functions-default belt
-- CANNOT exist in PostgreSQL — schema-scoped ALTER DEFAULT PRIVILEGES entries
-- are ADDITIVE to the built-in default and cannot subtract its implicit
-- PUBLIC EXECUTE (proven empirically on PG 17.11: the revoke stores no
-- pg_default_acl row and a subsequently created function remains
-- authenticated-executable). A GLOBAL default-privilege revoke would reach
-- every schema including public and change the live rail's expectations —
-- out of scope. The wall for FUNCTIONS therefore remains what the corpus
-- already mandates: an EXPLICIT per-function REVOKE in every function's own
-- contract (the §11.1a discipline), witnessed per-object by each package's
-- pgTAP suite (140's walled-function ACL sweep is the 076 witness).

-- =============================================================================
-- PART 3 — shared helper trigger functions (contracts §20.16; the AO guard)
--
-- Both are TRIGGER functions: never EXECUTEd by a principal directly.
-- SECURITY DEFINER, owned by postgres, search_path pinned — the frozen
-- posture verbatim (plan §8/076: "Shared helpers (SECURITY DEFINER, owner
-- postgres, search_path pinned per 066)").
-- kernel.set_updated_at writes NOTHING but NEW.updated_at, never raises,
-- never reads (§20.16 "What it never does"). kernel.raise_append_only always
-- raises — append-only tables attach it BEFORE UPDATE OR DELETE.
-- =============================================================================

create or replace function kernel.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function kernel.raise_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'append_only: % is immutable — % is not permitted',
    tg_table_name, tg_op
    using errcode = 'P0001';
end;
$$;

revoke all on function kernel.set_updated_at()    from public, anon, authenticated;
revoke all on function kernel.raise_append_only() from public, anon, authenticated;

-- =============================================================================
-- PART 4 — notify.outbox: the C12 envelope (schema §13.3, column-for-column)
--
-- Zero FK dependencies by design. sequence is allocated per
-- (aggregate_kind, aggregate_id) UNDER THE AGGREGATE'S EXISTING ROW LOCK,
-- which every SSCAS producer already holds (§17.24) — the emit pair computes
-- it; this table only constrains it. The envelope row is written LAST within
-- its producer transaction, strictly below the money plane in the lock order.
-- =============================================================================

create table if not exists notify.outbox (
  outbox_id      uuid primary key default gen_random_uuid(),
  event_type     text not null,
  aggregate_kind text not null,          -- polymorphic, deliberately no FK
  aggregate_id   uuid not null,
  sequence       bigint not null,
  causation_id   uuid,
  correlation_id uuid,
  event_key      text not null,
  payload        jsonb not null,         -- ids and scalars ONLY (producer contract §17.24):
                                         -- never a recipient list, never rendered copy
  occurred_at    timestamptz not null,
  state          text not null
                   constraint outbox_state_check
                   check (state in ('pending','claimed','done','dead')),
  claimed_until  timestamptz,
  attempt        int not null default 0,
  last_error     text,
  created_at     timestamptz not null default now(),  -- delta vs §13.3's bare
                   -- `created_at timestamptz`, recorded in the PFA register:
                   -- the emit pair never supplies it, so without the default
                   -- the audit column is always-NULL dead weight (D-F2).

  constraint outbox_event_type_event_key_key unique (event_type, event_key),
  constraint outbox_aggregate_sequence_key   unique (aggregate_kind, aggregate_id, sequence)
);

create index if not exists outbox_drain_order_idx
  on notify.outbox (state, occurred_at)
  where state in ('pending','claimed');

-- Deny-all posture: RLS enabled with ZERO policies; every client privilege
-- revoked. The only sanctioned writers are the emit pair below (092's drainer
-- claims rows later; it is NOT created here — SEAM-1 lands it with the last
-- consumer it must reach).
alter table notify.outbox enable row level security;
revoke all on table notify.outbox from public, anon, authenticated;

-- =============================================================================
-- PART 5 — the OR-14 emit pair (contracts §17.24 / §17.24a; NOTIF §4.3)
--
-- TWO emission behaviors, owner-ratified; every producer explicitly
-- classified (R2, 6 REQUIRED / 28 BEST-EFFORT / 0 unclassified); no implicit
-- default, no third behavior:
--
--   notify.emit_event          BEST-EFFORT, NON-RAISING. A producer that
--     cannot emit its envelope logs a WARNING and commits its money/custody
--     work regardless (the EXCEPTION WHEN OTHERS subtransaction shape of
--     public.enqueue_notification, 057:80-86).
--
--   notify.emit_event_required REQUIRED, RAISING. Identical envelope
--     semantics; a failed envelope write RAISES and the producer transaction
--     FAILS. Used ONLY where a required system invariant depends on the
--     envelope (the six R2 REQUIRED producers).
--
-- Shared envelope semantics (both classes):
--   * idempotent on UNIQUE(event_type, event_key): a replayed producer
--     transaction re-emitting the same event is a successful no-op — for
--     BOTH classes (replay must never raise);
--   * sequence := max(sequence)+1 for the aggregate, computed under the
--     aggregate's existing row lock (held by the producer, not taken here) —
--     no new lock, no new deadlock class; an unlocked concurrent emit on the
--     same aggregate collides on UNIQUE(aggregate_kind, aggregate_id,
--     sequence) — an outcome DERIVED from each class's own semantics (a
--     failed envelope write warns for BE, raises for REQUIRED; review C-F4:
--     stated as derivation, not as a cited ruling);
--   * the class governs the ENVELOPE WRITE only, never the drain — delivery
--     is best-effort for both (§17.24).
--
-- EXEC: DEF, service_role-only (NOTIF §4.3). SECURITY DEFINER with pinned
-- empty search_path; owner postgres. Producers (later-package SECURITY
-- DEFINER functions, owner postgres) reach them by ownership; the
-- service_role grant serves the edge emitters. No anon/authenticated path.
-- =============================================================================

create or replace function notify.emit_event(
  p_event_type     text,
  p_aggregate_kind text,
  p_aggregate_id   uuid,
  p_event_key      text,
  p_payload        jsonb default '{}'::jsonb,
  p_causation_id   uuid  default null,
  p_correlation_id uuid  default null
)
returns void
language plpgsql
security definer
set search_path = ''
set lock_timeout = '2s'
as $$
-- PFA-2 (2026-08-30, hostile review E-F2): the lock_timeout converts the one
-- error class that PIERCES `when others` in practice — the producer's own
-- statement_timeout (57014) firing while this insert waits on a concurrent
-- uncommitted duplicate's speculative-insertion lock — into 55P03, which the
-- handler DOES catch. Keeps BEST-EFFORT truthful: a blocked envelope becomes
-- a warning, never an aborted money transaction.
begin
  begin
    insert into notify.outbox
      (event_type, aggregate_kind, aggregate_id, sequence,
       causation_id, correlation_id, event_key, payload, occurred_at, state)
    values
      (p_event_type, p_aggregate_kind, p_aggregate_id,
       (select coalesce(max(o.sequence), 0) + 1
          from notify.outbox o
         where o.aggregate_kind = p_aggregate_kind
           and o.aggregate_id   = p_aggregate_id),
       p_causation_id, p_correlation_id, p_event_key,
       coalesce(p_payload, '{}'::jsonb), now(), 'pending')
    on conflict (event_type, event_key) do nothing;
  exception when others then
    -- BEST-EFFORT: the envelope is lost, the producer's work is not.
    raise warning 'notify.emit_event: envelope write failed for %/% — % (%)',
      p_event_type, p_event_key, sqlerrm, sqlstate;
  end;
end;
$$;

create or replace function notify.emit_event_required(
  p_event_type     text,
  p_aggregate_kind text,
  p_aggregate_id   uuid,
  p_event_key      text,
  p_payload        jsonb default '{}'::jsonb,
  p_causation_id   uuid  default null,
  p_correlation_id uuid  default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows int;
begin
  -- REQUIRED / RAISING: no exception handler by contract (§17.24a; the R2
  -- N-A30 re-scope forbids a swallow in REQUIRED bodies). Any failure other
  -- than the idempotent (event_type, event_key) replay raises and fails the
  -- producer transaction.
  insert into notify.outbox
    (event_type, aggregate_kind, aggregate_id, sequence,
     causation_id, correlation_id, event_key, payload, occurred_at, state)
  values
    (p_event_type, p_aggregate_kind, p_aggregate_id,
     (select coalesce(max(o.sequence), 0) + 1
        from notify.outbox o
       where o.aggregate_kind = p_aggregate_kind
         and o.aggregate_id   = p_aggregate_id),
     p_causation_id, p_correlation_id, p_event_key,
     coalesce(p_payload, '{}'::jsonb), now(), 'pending')
  on conflict (event_type, event_key) do nothing;

  -- PFA-2 (2026-08-30, hostile review E-F1): the idempotency contract is
  -- same-key ⇔ same-event. A zero-row outcome must therefore be a REPLAY of
  -- THIS event; if the standing row describes a DIFFERENT aggregate, the
  -- producer violated the key-derivation rule and a REQUIRED envelope would
  -- be silently lost — the one outcome §17.24a exists to forbid. Raise.
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    if not exists (
      select 1 from notify.outbox o
       where o.event_type = p_event_type
         and o.event_key  = p_event_key
         and o.aggregate_kind = p_aggregate_kind
         and o.aggregate_id   = p_aggregate_id
    ) then
      raise exception
        'notify.emit_event_required: event_key collision — (%, %) already exists for a DIFFERENT aggregate; a REQUIRED envelope would be silently lost. Producer key-derivation must embed a per-occurrence discriminator (PFA-2).',
        p_event_type, p_event_key
        using errcode = 'P0001';
    end if;
  end if;
end;
$$;

revoke all on function notify.emit_event(text, text, uuid, text, jsonb, uuid, uuid)
  from public, anon, authenticated;
revoke all on function notify.emit_event_required(text, text, uuid, text, jsonb, uuid, uuid)
  from public, anon, authenticated;

grant execute on function notify.emit_event(text, text, uuid, text, jsonb, uuid, uuid)
  to service_role;
grant execute on function notify.emit_event_required(text, text, uuid, text, jsonb, uuid, uuid)
  to service_role;
