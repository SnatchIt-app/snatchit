-- ============================================================================
-- 099_signing_monitor_and_executor_invokers.sql — dark operational monitors.
--
-- WHAT THIS MIGRATION IS. Two independent DARK closures, both additive and
-- both inert on apply:
--   (1) the KMS signing-key invariant monitor (KJ §4.4): one read-only
--       SECURITY DEFINER checker, three owner-unset config keys, one daily
--       cron row. While signing.monitor_enabled=false it writes nothing.
--   (2) two DARK executor invokers (KI §3 P0-2 / P1-1): refund-execute and
--       payout-execute each get a cron tick whose command is a NO-OP while
--       its own config key is false. Arming either is a PRODUCTION CONFIG
--       act — a `refund.%`/`payout.%` write through
--       catalog.set_platform_config, already dual-controlled (verified
--       below, PART 2) — not a deploy, and not this migration.
--
-- WHAT IT IS NOT. It does not deploy any edge function, does not flip any
-- existing flag, does not widen any grant on an existing object, does not
-- touch kernel.payout, kernel.refund, kernel.signing_key or any function
-- 096/097/098 own (this package creates no object any of the three touch).
-- The cron rows exist from apply and post to functions that may not be
-- deployed yet — that is safe: while the gating key is false the edge is
-- never reached (the CASE short-circuits before net.http_post is
-- evaluated); after arming, a not-yet-deployed function is a 404 at the
-- Supabase edge gateway, not a Postgres error — pg_net has no synchronous
-- caller to propagate one to.
--
-- SOURCES READ, NOT ASSUMED: docs/phase2/_impl/KJ_kms_runbook_monitor.md §4
-- (the monitor's design, requirements table, exact SQL — reproduced here
-- verbatim except the amendments below); KI_activation_sequencing.md §3
-- P0-2 (refund-execute has no invoker) / P1-1 (payout-execute has no flag
-- at all) and §6 P-5 / §7 (the invoker shape, the enforce-transfer-expiry
-- idiom); 083:49-105 (kernel.signing_key DDL + immutability guard — never
-- widened here); 032:97-116 / 077:2170-2181 / 087:1518-1541 (the
-- net.http_post + vault.decrypted_secrets idiom, copied verbatim per job —
-- one literal project-ref URL per cron command, never a shared GUC/table);
-- 093:6690-6751 (the v_dual prefix set inside catalog.set_platform_config —
-- `refund.%` and `payout.%` are ALREADY dual-controlled; read, not assumed
-- — see PART 2's note); supabase/functions/notify-report/index.ts (the
-- branch this migration's monitor posts to, added in the same PR);
-- supabase/functions/refund-execute/index.ts:598-650 (the sweep arm:
-- action='sweep', body {action,limit,lease_seconds}, auth =
-- INTERNAL_CRON_SECRET or the service-role bearer); supabase/functions/
-- payout-execute/index.ts:540-580 (the batch arm: no action field needed,
-- body {limit,lease_seconds}, same auth).
--
-- DEVIATIONS FROM KJ §4.4's inline SQL, per the orchestrator design (M4
-- §4.1):
--   (a) the migration NUMBER is 099, not 096 as KJ's inline comment says —
--       096/097/098 were claimed by three concurrent packages during this
--       train; renamed here, nothing else changed from KJ §4.4's function
--       body.
--   (b) dedupe added — a run whose `alerts` array is byte-identical to one
--       already written to kernel.admin_audit in the last 24h writes
--       NOTHING further (no new audit row, no egress attempt); the return
--       value carries `'deduped': true` so a caller can distinguish a
--       suppressed repeat from a fresh 'ok'. Recorded as a choice (KJ §5
--       Q4): the alternative — alerting on every tick while unresolved — is
--       what KJ shipped un-amended; the owner may prefer that back.
--   (c) the function is granted to nobody, INCLUDING service_role (KJ E11:
--       a new kernel.* function is PUBLIC-executable by default; the cron
--       job runs as its owner, postgres, which needs no grant at all).
-- ============================================================================
begin;

set local lock_timeout = '3s';

-- ============================================================================
-- PART 1 — the KMS signing-key invariant monitor (KJ §4.4).
-- ============================================================================

-- config keys (PFA-22 owner-unset shape; catalog.set_platform_config
-- refuses unknown keys, 078:1103 — these rows exist so the setter's
-- registry precondition holds once the owner arms the ceremony).
insert into catalog.platform_config (key, version, value, visibility) values
  ('signing.monitor_enabled',          1, 'false'::jsonb, 'restricted'),
  ('signing.expected_key_fingerprint', 1, 'null'::jsonb,  'restricted'),  -- SHA-256 over DER SPKI, lowercase hex (runbook D5)
  ('signing.expected_max_not_after',   1, 'null'::jsonb,  'restricted')   -- runbook D6: NULL unless the owner overrides
on conflict (key, version) do nothing;

create or replace function kernel.check_signing_key_invariants()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enabled        boolean;
  v_total          integer;
  v_scoped         integer;
  v_active_global  integer;
  v_rotating       integer;
  v_revoked        integer;
  v_max_not_after  timestamptz;
  v_exp_not_after  timestamptz;
  v_pinned         text;
  v_actual         text;
  v_fpr_state      text;
  v_alerts         text[] := '{}';
  v_out            jsonb;
  v_dup            boolean := false;
begin
  select (c.value #>> '{}')::boolean into v_enabled
    from catalog.platform_config c where c.key = 'signing.monitor_enabled'
   order by c.version desc limit 1;
  if not coalesce(v_enabled, false) then
    return jsonb_build_object('status', 'monitor_disabled', 'checked_at', now());
  end if;

  -- counts only. kms_handle_ref is never read.
  select count(*),
         count(*) filter (where scope <> 'global'),
         count(*) filter (where scope = 'global' and status = 'active'),
         count(*) filter (where status = 'rotating'),
         count(*) filter (where status = 'revoked'),
         max(not_after)
    into v_total, v_scoped, v_active_global, v_rotating, v_revoked, v_max_not_after
    from kernel.signing_key;

  select nullif(lower(c.value #>> '{}'), '') into v_pinned
    from catalog.platform_config c where c.key = 'signing.expected_key_fingerprint'
   order by c.version desc limit 1;
  select (c.value #>> '{}')::timestamptz into v_exp_not_after
    from catalog.platform_config c where c.key = 'signing.expected_max_not_after'
   order by c.version desc limit 1;

  -- the D5 fingerprint, recomputed from the stored PEM; reduced to a comparison result.
  select encode(sha256(decode(regexp_replace(k.public_key,
           '-----(BEGIN|END) PUBLIC KEY-----|[[:space:]]', '', 'g'), 'base64')), 'hex')
    into v_actual
    from kernel.signing_key k
   where k.key_id = '00000000-0000-0000-0000-0000000000b0';
  v_fpr_state := case when v_pinned is null then 'unpinned'
                      when v_actual is null then 'bootstrap_row_missing'
                      when v_pinned = v_actual then 'match'
                      else 'MISMATCH' end;

  if v_total        <> 1 then v_alerts := array_append(v_alerts, 'total_keys='    || v_total);        end if;
  if v_scoped       <> 0 then v_alerts := array_append(v_alerts, 'scoped_keys='   || v_scoped);       end if;  -- ADV-7 shadow
  if v_active_global<> 1 then v_alerts := array_append(v_alerts, 'active_global=' || v_active_global);end if;  -- ADV-8
  if v_rotating     <> 0 then v_alerts := array_append(v_alerts, 'rotating_keys=' || v_rotating);     end if;  -- expected 0 until first rotation
  if v_revoked      <> 0 then v_alerts := array_append(v_alerts, 'revoked_keys='  || v_revoked);      end if;  -- ADV-9
  if v_fpr_state <> 'match' then v_alerts := array_append(v_alerts, 'fingerprint=' || v_fpr_state);   end if;  -- ADV-4/5/6/10
  if v_max_not_after is distinct from v_exp_not_after
     then v_alerts := array_append(v_alerts, 'max_not_after=' ||
            case when v_max_not_after is null then 'null' else 'set' end);                            end if;  -- ADV-9 / §7.6

  -- DEDUPE (deviation b): an identical alerts array already written within
  -- the last 24h suppresses this run's audit row AND its egress attempt.
  if cardinality(v_alerts) > 0 then
    select exists (
      select 1 from kernel.admin_audit a
       where a.action = 'signing_key.invariant_alert'
         and a.subject_id = '00000000-0000-0000-0000-0000000000b0'
         and a.after -> 'alerts' = to_jsonb(v_alerts)
         and a.created_at > now() - interval '24 hours'
    ) into v_dup;
  end if;

  v_out := jsonb_build_object(
    'status',            case when cardinality(v_alerts) = 0 then 'ok' else 'alert' end,
    'checked_at',        now(),
    'total_keys',        v_total,
    'scoped_keys',       v_scoped,
    'active_global',     v_active_global,
    'rotating_keys',     v_rotating,
    'revoked_keys',      v_revoked,
    'fingerprint',       v_fpr_state,            -- a WORD, never the hex
    'max_not_after_set', v_max_not_after is not null,
    'alerts',            to_jsonb(v_alerts),
    'deduped',           v_dup);

  if cardinality(v_alerts) > 0 and not v_dup then
    -- durable, append-only, actor = SN-SYSTEM sentinel (083:743 pattern)
    insert into kernel.admin_audit
           (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values ('00000000-0000-0000-0000-0000000000f1', 'signing_key.invariant_alert', 'signing_key',
            '00000000-0000-0000-0000-0000000000b0', 'monitor', null, v_out);

    -- push egress — BEST-EFFORT, fail-open for the audit row (033:162 pattern);
    -- Vault service_role_key header is the 032/077/087 pattern; no secret in
    -- this file; a missing Vault row sends an empty bearer (401 at the edge,
    -- never a Postgres exception) via the outer coalesce(...,'').
    begin
      perform net.http_post(
        url     := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/notify-report',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets
                                                   where name = 'service_role_key'
                                                   order by created_at desc limit 1), ''),
          'Content-Type', 'application/json'),
        body    := jsonb_build_object('event', 'signing_invariant_alert', 'alerts', to_jsonb(v_alerts),
                                      'checked_at', now()));
    exception when others then
      raise warning 'signing monitor: alert egress failed — % (%)', sqlerrm, sqlstate;
    end;
  end if;

  return v_out;
end;
$$;

-- grants: nobody, including service_role, may execute (deviation c; KJ E11:
-- default is PUBLIC-executable). The cron job runs as postgres (the owner),
-- which needs no grant.
revoke all on function kernel.check_signing_key_invariants() from public, anon, authenticated, service_role;

-- cron (owning-package registration, kebab name, idempotent by jobname — 077:2164-2167)
select cron.schedule('monitor-signing-key-invariants', '23 5 * * *', $$select kernel.check_signing_key_invariants();$$);

-- ============================================================================
-- PART 2 — dark executor invokers (KI §3 P0-2 / P1-1).
--
-- VERIFIED, NOT ASSUMED: `refund.%` and `payout.%` are ALREADY members of
-- catalog.set_platform_config's dual-control prefix set (093:6720-6723
-- `v_dual := ... or p_key like 'refund.%' or p_key like 'payout.%' ...`).
-- Arming either key below therefore PARKS for a second, distinct
-- platform_admin the instant an owner sets it true through the setter; this
-- migration only SEEDS both false and never calls the setter itself.
-- ============================================================================

insert into catalog.platform_config (key, version, value, visibility) values
  ('refund.executor_enabled', 1, 'false'::jsonb, 'restricted'),
  ('payout.executor_enabled', 1, 'false'::jsonb, 'restricted')
on conflict (key, version) do nothing;

-- refund-execute-tick — posts the sweep arm ONLY while refund.executor_enabled
-- reads true. The sweep arm is the machine path (refund-execute/index.ts:
-- 598-650): action='sweep', auth = INTERNAL_CRON_SECRET or the service-role
-- bearer this job supplies. The vault read is wrapped in coalesce(...,''), so
-- a missing Vault secret sends an empty bearer (the edge answers 401) instead
-- of raising inside Postgres — a raise every 2 minutes would otherwise fill
-- cron.job_run_details with an unrelated failure class.
select cron.schedule('refund-execute-tick', '*/2 * * * *', $$select case when coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c where c.key = 'refund.executor_enabled' order by c.version desc limit 1), false) then net.http_post(url := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/refund-execute', headers := jsonb_build_object('Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key' order by created_at desc limit 1), ''), 'Content-Type', 'application/json'), body := '{"action":"sweep","limit":25,"lease_seconds":900}'::jsonb) end;$$);

-- payout-execute-tick — posts the batch arm ONLY while payout.executor_enabled
-- reads true. payout-execute/index.ts:540-580 needs no action field (the
-- whole POST is the batch runner); same auth, same fail-harmless vault read.
select cron.schedule('payout-execute-tick', '*/10 * * * *', $$select case when coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c where c.key = 'payout.executor_enabled' order by c.version desc limit 1), false) then net.http_post(url := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/payout-execute', headers := jsonb_build_object('Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key' order by created_at desc limit 1), ''), 'Content-Type', 'application/json'), body := '{"limit":25,"lease_seconds":900}'::jsonb) end;$$);

commit;
