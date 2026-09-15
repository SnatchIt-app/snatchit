-- =============================================================================
-- 133_functions_base_url_from_config.sql
-- The edge-functions base URL becomes CONFIGURATION (Vault secret `project_url`),
-- never a literal. Owner item 6 (2026-09-15): four function bodies and five cron
-- commands hardcoded the PRODUCTION project URL in net.http_post calls, so any
-- fresh replay with a live pg_net (GitHub CI, a new environment, a restored
-- sandbox) POSTed production — proven on CI run 34933664373 (one 401 per job).
--
-- After this migration:
--   * public.notify_bid_placed / notify_transfer_event / notify_moderation_event
--     (033/034/035) read `project_url` next to `service_role_key` and post only
--     when BOTH are present;
--   * kernel.check_signing_key_invariants (099) posts only when `project_url`
--     exists;
--   * the five http crons — enforce-transfer-expiry (032), crm-export-build-tick
--     and crm-export-purge-tick (087), refund-execute-tick and payout-execute-
--     tick (099) — are re-registered (unschedule + schedule, the 032 pattern) with
--     the URL read from Vault and a `where exists (project_url)` guard: no
--     configuration ⇒ no request, no error, no cron failure row.
-- No new objects: census, grant decisions and expected_grants are unchanged.
-- Trust boundary: whoever can write Vault can already read `service_role_key`
-- from it, so a configurable URL adds no new capability (the bearer these posts
-- carry is that key). It is NOT in catalog.platform_config on purpose — a single
-- platform_admin must not be able to redirect service-role-bearer posts.
--
-- PRECONDITION for a live environment (production, sandbox): insert the Vault
-- secret `project_url` = 'https://<ref>.supabase.co' (no trailing slash)
-- BEFORE applying. ENFORCED in §0: where Vault carries service_role_key (a
-- live environment) and no project_url, the migration refuses. CI leaves both
-- unset — that is the point. The production preflight read must also count
-- function bodies / cron commands naming the production host (expected 4 / 5):
-- §4's proof aborts on any unrecorded object carrying that literal.
-- Rollback: supabase/rollbacks/133_functions_base_url_from_config_rollback.sql
-- restores the four bodies and five commands byte-for-byte (md5-proven).
-- =============================================================================
begin;

-- ── 0. precondition (D's F-133-1): an environment that carries the service-role
--       key in Vault is LIVE and must carry project_url too — otherwise every
--       http cron and notification trigger below goes silent with no error and
--       no failed cron row. CI and the local harness carry neither and apply.
do $pre$
declare v_key boolean; v_url text;
begin
  select exists (select 1 from vault.decrypted_secrets where name = 'service_role_key') into v_key;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url' order by created_at desc limit 1;
  if v_key and v_url is null then
    raise exception '133 REFUSED: Vault carries service_role_key but no project_url — insert project_url (https://<ref>.supabase.co, no trailing slash) BEFORE applying, or transfer expiry, Phase 0 refunds, the executor ticks, the notify triggers, the signing-monitor alert and CRM export all go silent';
  end if;
  if v_url is not null and v_url !~ '^https://[a-z0-9]{20}\.supabase\.co$' then
    raise exception '133 REFUSED: Vault project_url has an unexpected shape (%) — expected https://<20-char ref>.supabase.co with no trailing slash', v_url;
  end if;
end $pre$;

-- ── 1. the four function bodies (from pg_get_functiondef at the 130 tip; only the
--       URL read and its guard change — diff the rollback against this file)

CREATE OR REPLACE FUNCTION public.notify_bid_placed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_key text;
  v_url text;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_key
      FROM vault.decrypted_secrets
     WHERE name = 'service_role_key'
     ORDER BY created_at DESC
     LIMIT 1;
    -- 133: the functions base URL is configuration (Vault 'project_url'), never a literal.
    SELECT decrypted_secret INTO v_url
      FROM vault.decrypted_secrets
     WHERE name = 'project_url'
     ORDER BY created_at DESC
     LIMIT 1;

    IF v_key IS NOT NULL AND v_url IS NOT NULL THEN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/notify-transfer',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_key,
          'Content-Type',  'application/json'
        ),
        body    := jsonb_build_object(
          'event',      'bid_placed',
          'bid_id',     NEW.id,
          'listing_id', NEW.listing_id,
          'bidder_id',  NEW.bidder_id,
          'amount',     NEW.amount
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Never block a bid because a notification failed.
    RAISE WARNING 'notify_bid_placed: notification failed: %', SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_transfer_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_key     text;
  v_url     text;
  v_event   text;
  v_payload jsonb;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_event := 'transfer_created';
  ELSE
    v_event := 'tickets_marked_sent';
  END IF;

  v_payload := jsonb_build_object(
    'event',       v_event,
    'transfer_id', NEW.id,
    'listing_id',  NEW.listing_id,
    'buyer_id',    NEW.buyer_id,
    'seller_id',   NEW.seller_id
  );

  BEGIN
    SELECT decrypted_secret INTO v_key
      FROM vault.decrypted_secrets
     WHERE name = 'service_role_key'
     ORDER BY created_at DESC
     LIMIT 1;
    -- 133: the functions base URL is configuration (Vault 'project_url'), never a literal.
    SELECT decrypted_secret INTO v_url
      FROM vault.decrypted_secrets
     WHERE name = 'project_url'
     ORDER BY created_at DESC
     LIMIT 1;

    IF v_key IS NOT NULL AND v_url IS NOT NULL THEN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/notify-transfer',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_key,
          'Content-Type',  'application/json'
        ),
        body    := v_payload
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Never block the buyer/seller action because a notification failed.
    RAISE WARNING 'notify_transfer_event: % notification failed: %', v_event, SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_moderation_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_key     text;
  v_url     text;
  v_event   text;
  v_payload jsonb;
BEGIN
  -- Build event payload
  IF TG_TABLE_NAME = 'reports' THEN
    v_event   := 'report_created';
    v_payload := jsonb_build_object(
      'event',        v_event,
      'report_id',    NEW.id,
      'reporter_id',  NEW.reporter_id,
      'target_type',  NEW.target_type,
      'target_id',    NEW.target_id,
      'reason',       NEW.reason
    );
  ELSIF TG_TABLE_NAME = 'transfers' THEN
    v_event   := 'dispute_opened';
    v_payload := jsonb_build_object(
      'event',        v_event,
      'transfer_id',  NEW.id,
      'listing_id',   NEW.listing_id,
      'buyer_id',     NEW.buyer_id,
      'seller_id',    NEW.seller_id,
      'reason',       COALESCE(NEW.dispute_reason, 'unspecified')
    );
  ELSE
    RETURN NEW;
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_key
      FROM vault.decrypted_secrets
     WHERE name = 'service_role_key'
     ORDER BY created_at DESC
     LIMIT 1;
    -- 133: the functions base URL is configuration (Vault 'project_url'), never a literal.
    SELECT decrypted_secret INTO v_url
      FROM vault.decrypted_secrets
     WHERE name = 'project_url'
     ORDER BY created_at DESC
     LIMIT 1;

    IF v_key IS NOT NULL AND v_url IS NOT NULL THEN
      PERFORM net.http_post(
        url     := v_url || '/functions/v1/notify-report',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_key,
          'Content-Type',  'application/json'
        ),
        body    := v_payload
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Never block the user action because a notification failed.
    RAISE WARNING 'notify_moderation_event: % notification failed: %', v_event, SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION kernel.check_signing_key_invariants()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      -- 133: post only when the functions base URL is configured (Vault 'project_url').
      if exists (select 1 from vault.decrypted_secrets where name = 'project_url') then
      perform net.http_post(
        url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url' order by created_at desc limit 1) || '/functions/v1/notify-report',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets
                                                   where name = 'service_role_key'
                                                   order by created_at desc limit 1), ''),
          'Content-Type', 'application/json'),
        body    := jsonb_build_object('event', 'signing_invariant_alert', 'alerts', to_jsonb(v_alerts),
                                      'checked_at', now()));
      end if;
    exception when others then
      raise warning 'signing monitor: alert egress failed — % (%)', sqlerrm, sqlstate;
    end;
  end if;

  return v_out;
end;
$function$;

-- ── 2. the five http crons: unschedule + schedule by jobname (032 pattern —
--       the local harness shim INSERTs on schedule, real pg_cron upserts; both
--       end with exactly one row per jobname). Schedules unchanged.

select cron.unschedule(jobname) from cron.job where jobname = 'enforce-transfer-expiry';
select cron.schedule(
  'enforce-transfer-expiry',
  '*/2 * * * *',
  $cron$
  SELECT net.http_post(
    url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url' ORDER BY created_at DESC LIMIT 1) || '/functions/v1/enforce-transfer-expiry',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (
        SELECT decrypted_secret
          FROM vault.decrypted_secrets
         WHERE name = 'service_role_key'
         ORDER BY created_at DESC
         LIMIT 1
      ),
      'Content-Type', 'application/json'
    ),
    body    := '{}'::jsonb
  )
  WHERE EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'project_url');   -- 133: no URL ⇒ no post
  $cron$
);

select cron.unschedule(jobname) from cron.job where jobname = 'crm-export-build-tick';
select cron.schedule('crm-export-build-tick', '* * * * *', $cron$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url' order by created_at desc limit 1) || '/functions/v1/crm-export-worker/build',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets
                                               where name = 'service_role_key' order by created_at desc limit 1), ''),
      'X-Crm-Export-Worker', coalesce((select decrypted_secret from vault.decrypted_secrets
                                        where name = 'crm_export_worker_secret' order by created_at desc limit 1), ''),
      'Content-Type', 'application/json'),
    body    := '{}'::jsonb)
   where exists (select 1 from vault.decrypted_secrets where name = 'crm_export_worker_secret')   -- no secret ⇒ no post (fail closed, E-79)
     and exists (select 1 from vault.decrypted_secrets where name = 'project_url');               -- 133: no URL ⇒ no post
$cron$);

select cron.unschedule(jobname) from cron.job where jobname = 'crm-export-purge-tick';
select cron.schedule('crm-export-purge-tick', '*/15 * * * *', $cron$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url' order by created_at desc limit 1) || '/functions/v1/crm-export-worker/purge',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets
                                               where name = 'service_role_key' order by created_at desc limit 1), ''),
      'X-Crm-Export-Worker', coalesce((select decrypted_secret from vault.decrypted_secrets
                                        where name = 'crm_export_worker_secret' order by created_at desc limit 1), ''),
      'Content-Type', 'application/json'),
    body    := '{}'::jsonb)
   where exists (select 1 from vault.decrypted_secrets where name = 'crm_export_worker_secret')   -- no secret ⇒ no post (fail closed, E-79)
     and exists (select 1 from vault.decrypted_secrets where name = 'project_url');               -- 133: no URL ⇒ no post
$cron$);

select cron.unschedule(jobname) from cron.job where jobname = 'refund-execute-tick';
select cron.schedule('refund-execute-tick', '*/2 * * * *', $$select case when coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c where c.key = 'refund.executor_enabled' order by c.version desc limit 1), false) and exists (select 1 from vault.decrypted_secrets where name = 'project_url') then net.http_post(url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url' order by created_at desc limit 1) || '/functions/v1/refund-execute', headers := jsonb_build_object('Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key' order by created_at desc limit 1), ''), 'Content-Type', 'application/json'), body := '{"action":"sweep","limit":25,"lease_seconds":900}'::jsonb) end;$$);

select cron.unschedule(jobname) from cron.job where jobname = 'payout-execute-tick';
select cron.schedule('payout-execute-tick', '*/10 * * * *', $$select case when coalesce((select (c.value #>> '{}')::boolean from catalog.platform_config c where c.key = 'payout.executor_enabled' order by c.version desc limit 1), false) and exists (select 1 from vault.decrypted_secrets where name = 'project_url') then net.http_post(url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url' order by created_at desc limit 1) || '/functions/v1/payout-execute', headers := jsonb_build_object('Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key' order by created_at desc limit 1), ''), 'Content-Type', 'application/json'), body := '{"limit":25,"lease_seconds":900}'::jsonb) end;$$);

-- ── 3. the in-replay window (D, 2026-09-15): on a fresh replay 032's cron is live
--       from the moment 032 applies until this file rewrites it; a tick in that
--       window may already have QUEUED a request to the production host. Drop any
--       such queued request here so it can never leave after this point. (The
--       local harness has no pg_net queue table; guarded.)
--       Guarded (D's F-133-2): on PRODUCTION itself — Vault project_url IS the
--       production host — those queued requests are production's own (notify
--       posts, a cron tick) and must not be dropped. CI / the harness (no
--       project_url) and any other environment purge them.
do $purge$
declare v_url text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url' order by created_at desc limit 1;
  if to_regclass('net.http_request_queue') is not null
     and coalesce(v_url, '') <> 'https://hqycwntpfoztoinemqns.supabase.co' then
    execute $q$delete from net.http_request_queue where url like 'https://hqycwntpfoztoinemqns.supabase.co/%'$q$;
  end if;
end $purge$;

-- ── 4. proof inside the migration: nothing in this database names the production host any more
do $chk$
declare v_fn int; v_cron int;
begin
  select count(*) into v_fn   from pg_proc  where prosrc  like '%hqycwntpfoztoinemqns%';
  select count(*) into v_cron from cron.job where command like '%hqycwntpfoztoinemqns%';
  if v_fn <> 0 or v_cron <> 0 then
    raise exception '133: production host still referenced — functions=%, cron jobs=%', v_fn, v_cron;
  end if;
end $chk$;

commit;
