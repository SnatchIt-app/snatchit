-- ============================================================================
-- 146_ops_alert_delivery_and_ack.sql — an ops alert can be SENT, have its delivery CONFIRMED, and be ACKNOWLEDGED.
-- Today none of the three is possible.
--
-- WHY (mapped by D, 2026-09-19; docs/operations/OPS_ALERT_DELIVERY_DESIGN.md). ops.alert_fire() writes a row and that
-- is the whole story: no trigger on ops.alert, no pg_net in the ops files, no edge function reads it, no notify.*
-- enqueue, and the daily summary is written 'portal_only'. The admin console renders firing alerts only when an
-- operator loads the page, and it does not poll. The table has no acknowledgement, assignee or escalation concept —
-- `state` is 'firing' or 'recovered' and only detectors change it. So "a p1 case fired an alert" has never meant a
-- person was told, and nothing recorded that they had not been. The repo says as much:
-- docs/admin-console/DESIGN_AND_EXECUTION_PLAN.md — "Not built (honest labels): … email/SMS alerts (no adapter)".
--
-- QUEUED IS NOT DELIVERED (A, 2026-09-19). net.http_post returns a request id at once; the response lands later in
-- net._http_response. A 401 — the failure this project has actually seen — is a perfectly successful QUEUE. So the
-- columns and the wording here keep the two apart, and only a 2xx recorded against the request id counts as delivered:
--   queued_at + notify_request_id  = the post was accepted by pg_net, and NOTHING more;
--   delivered_at + delivery_status = notify-report answered 2xx AND reported delivered >= 1 for that request. A status
--     alone is not enough: notify-report answers 200 for an event it does not know and for its own internal errors,
--     so before the ops_alert branch is deployed every post would otherwise look delivered;
--   an unconfirmed or non-2xx delivery makes the alert eligible again (up to the attempt cap), it is never "sent".
--
-- WHAT.
--   * ops.alert gains queued_at, notify_request_id, delivered_at, delivery_status, last_notify_error,
--     notify_attempts, acknowledged_at, acknowledged_by, incident_seq. An alert nobody was told about is now
--     visibly undelivered, and a recurrence is visibly a new incident rather than more of the old one.
--   * ops.alert_fire (117) is replaced so that the recovered→firing transition opens a NEW incident: see the
--     section below. Nothing else about firing changes, and a repeat fire of a still-firing alert is untouched.
--   * ops.alert_post(body) and ops.alert_response(request_id) (new): the ONLY two places that touch pg_net and Vault.
--     One auditable egress point — and the seam a test substitutes, because CI's postgres is not superuser and may
--     not create or write anything in the net or vault schemas (the local harness can, which would have hidden this).
--   * ops.dispatch_alerts(p_limit) (new). Each call first RECONCILES what it queued before (through
--     ops.alert_response), then posts eligible alerts to the one working database→human path: net.http_post to
--     /functions/v1/notify-report, 133's pattern byte for byte (Vault project_url + service_role_key), with a NEW
--     event 'ops_alert'. It is:
--       - OFF: ops.setting 'alert_delivery_enabled' is seeded false and checked for EVERY caller;
--       - MINIMAL: the body carries an ALLOW-LIST — alert key, kind, counts, timestamps, and case_id / case_type /
--         jobname when the payload has them. ops.alert.payload is free-form and is NEVER passed through, so a
--         buyer's or seller's details cannot leave the database this way (pgTAP 213 pins it with a payload that
--         contains an email and a phone);
--       - non-fatal: it never raises, so a delivery problem cannot fail a detector tick;
--       - bounded: an alert that has failed 5 times is skipped and counted, so a broken endpoint cannot loop;
--       - unscheduled: see below.
--   * ops.alert_ack(p_alert_key, p_note) (new): an operator records that a person has seen the alert. It writes
--     acknowledged_at/by and an ops.audit row. It does NOT recover the alert: acknowledging is not fixing.
--   No new table, no index, no schedule, no public object (Gate-2 census and the grant manifests are unchanged).
--
-- TURNING THE SETTING ON STILL DELIVERS NOTHING BY ITSELF (A, 2026-09-19). 146 schedules nothing: no cron entry calls
-- ops.dispatch_alerts, and no detector calls it either. Flipping alert_delivery_enabled only makes a CALL able to
-- send. Scheduling it is a separate, owner decision, and until that decision "enabled" would be one more silent
-- non-delivery. Whoever flips the setting must be told that.
--
-- WHAT THIS DOES NOT CLAIM. Delivery becomes ATTEMPTABLE, CONFIRMABLE and RECORDED — never proven to have reached a
-- person. A 2xx from notify-report means the edge function accepted the event, not that a human read a push or an
-- email. Only ops.alert_ack records that someone saw it. The deployed notify-report is not byte-read.
--
-- EDGE FUNCTION. supabase/functions/notify-report/index.ts gains an 'ops_alert' branch in the repository only. No
-- existing branch or payload changes (B owns the signing monitor's use of that function; B has no live session, so
-- this file and the design note are the record). Deploying it is a separate owner act; until then an 'ops_alert' post
-- is answered 200 with no delivery count, which this migration records as "answered 200 but reported no delivery" —
-- NOT delivered, and eligible again up to the attempt cap.
--
-- TWO DEFECTS FOUND IN REVIEW AND FIXED HERE (independent review, 2026-09-20; pgTAP 213 sections S and R, both of
-- which fail against the first version of this file):
--   1. QUEUE STARVATION. dispatch_alerts selected its batch and only then skipped alerts that had used up their
--      attempts, so p_limit dead alerts older than a live one filled every slot and the live one was never posted.
--      The cap is now part of the batch predicate and the dead ones are counted separately: still visible to an
--      operator, no longer occupying a delivery slot.
--   2. INCIDENT RECURRENCE. alert_fire reused the row without clearing the closed incident's delivery and
--      acknowledgement, so a recurrence was ineligible for notification, inherited an acknowledgement given for a
--      different incident, and could be marked delivered by a late response to the previous incident's request.
-- ROLLBACK: supabase/rollbacks/146_ops_alert_delivery_and_ack_rollback.sql restores 117's ops.alert_fire, drops the
-- three new functions, deletes the setting row and drops the nine columns. Alert rows themselves are untouched; what
-- is discarded is the delivery bookkeeping and the incident counter, which the rollback says out loud.
-- VERIFY (read-only): select value from ops.setting where key = 'alert_delivery_enabled';  -- false
--   md5(pg_get_functiondef('ops.dispatch_alerts(integer)'::regprocedure)), md5 of ops.alert_ack(text,text).
-- FAILURE BEHAVIOUR: one transaction; the column adds take a brief ACCESS EXCLUSIVE on ops.alert (a small table) with
-- lock_timeout 3s. At runtime dispatch_alerts swallows its own errors by design and records them on the row; with
-- net._http_response absent (no pg_net) it queues nothing and reports why.
-- OWNER APPROVAL POINT: local build only. No PR, apply, schedule, setting flip or deploy without the owner. Flipping
-- the setting AND scheduling a caller is the act that would first send anything to a person.
-- ============================================================================

begin;
set local lock_timeout = '3s';

alter table ops.alert
  add column if not exists queued_at         timestamptz,   -- pg_net accepted the request. NOT delivery.
  add column if not exists notify_request_id bigint,        -- net.http_post's id, reconciled against net._http_response
  add column if not exists delivered_at      timestamptz,   -- a 2xx came back for that request
  add column if not exists delivery_status   integer,
  add column if not exists notify_attempts   integer not null default 0,
  add column if not exists last_notify_error text,
  add column if not exists acknowledged_at   timestamptz,
  add column if not exists acknowledged_by   uuid,
  add column if not exists incident_seq      integer not null default 1;  -- a recovery/re-fire opens a NEW incident

insert into ops.setting (key, value) values ('alert_delivery_enabled', 'false'::jsonb) on conflict (key) do nothing;

-- ── a recurrence is a NEW incident ──────────────────────────────────────────────────────────────────────────────
-- 117's ops.alert_fire reused the row and reset nothing, which was harmless while an alert row carried nothing but
-- "this is firing". Now that the row also carries delivery and acknowledgement, an alert that recovers and fires
-- again would INHERIT both (reported by the independent review, 2026-09-20): dispatch_alerts excludes a row whose
-- delivered_at or acknowledged_at is set, so the new incident would never be notified; the previous incident's
-- attempts would still count against the cap; and a response to the CLOSED incident's request, arriving late, would
-- be recorded against the new one. So the recovered→firing transition — and only that transition — opens a new
-- incident and clears the delivery bookkeeping. A repeat fire of an alert that is STILL firing changes nothing of
-- the kind: it is the same incident, and re-notifying every detector tick would be a storm.
-- What a new incident discards is the previous incident's delivery bookkeeping. What survives is the ops.audit row
-- that every ops.alert_ack writes — that, not the alert row, is the durable record that a person saw it.
create or replace function ops.alert_fire(p_key text, p_kind text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare v_state text;
begin
  select state into v_state from ops.alert where alert_key = p_key for update;
  if not found then
    insert into ops.alert (alert_key, kind, state, payload)
    values (p_key, p_kind, 'firing', coalesce(p_payload, '{}'::jsonb));
    return jsonb_build_object('alert_key', p_key, 'fired', true, 'was', null);
  end if;
  if v_state = 'recovered' then
    -- a NEW incident: a fresh first_fired_at, the next incident number, and nothing carried over from the closed one
    update ops.alert
       set state = 'firing', kind = p_kind, payload = coalesce(p_payload, payload),
           last_fired_at = now(), fire_count = fire_count + 1, first_fired_at = now(), recovered_at = null,
           incident_seq = incident_seq + 1,
           queued_at = null, notify_request_id = null, delivered_at = null, delivery_status = null,
           notify_attempts = 0, last_notify_error = null, acknowledged_at = null, acknowledged_by = null
     where alert_key = p_key;
  else
    -- the same incident, seen again: only the counters move
    update ops.alert
       set state = 'firing', kind = p_kind, payload = coalesce(p_payload, payload),
           last_fired_at = now(), fire_count = fire_count + 1, recovered_at = null
     where alert_key = p_key;
  end if;
  return jsonb_build_object('alert_key', p_key, 'fired', v_state = 'recovered', 'was', v_state);
end;
$ops$;
revoke all on function ops.alert_fire(text,text,jsonb) from public, anon, authenticated, service_role;

-- ── the only two places that touch the outside world ────────────────────────────────────────────────────────────
-- Everything ops knows about pg_net and Vault lives in these two functions. That keeps the egress in one auditable
-- place, and it is also what makes the behaviour testable without touching the `net` or `vault` schemas: CI's postgres
-- is NOT superuser and may not create or write objects there, so a test substitutes THESE instead.
create or replace function ops.alert_post(p_body jsonb)
returns bigint language plpgsql security definer set search_path = ''
as $ops$
declare v_url text; v_req bigint;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets
   where name = 'project_url' order by created_at desc limit 1;
  if v_url is null then
    return null;                       -- the functions base URL is not configured: nothing can be posted
  end if;
  select net.http_post(
    url     := v_url || '/functions/v1/notify-report',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets
                                               where name = 'service_role_key'
                                               order by created_at desc limit 1), ''),
      'Content-Type', 'application/json'),
    body    := p_body) into v_req;
  return v_req;
end;
$ops$;
revoke all on function ops.alert_post(jsonb) from public, anon, authenticated, service_role;

create or replace function ops.alert_response(p_request_id bigint)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare v_status integer; v_content text;
begin
  if to_regclass('net._http_response') is null then
    return null;                       -- no pg_net here: nothing can be confirmed, and that is not an error
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'net' and table_name = '_http_response' and column_name = 'content') then
    execute 'select status_code, content from net._http_response where id = $1' into v_status, v_content using p_request_id;
  else
    execute 'select status_code from net._http_response where id = $1' into v_status using p_request_id;
  end if;
  if v_status is null then
    return null;                       -- no answer recorded yet
  end if;
  return jsonb_build_object('status', v_status, 'content', v_content);
end;
$ops$;
revoke all on function ops.alert_response(bigint) from public, anon, authenticated, service_role;

-- ── send, then confirm ──────────────────────────────────────────────────────────────────────────────────────────
create or replace function ops.dispatch_alerts(p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  c_max_attempts constant integer := 5;            -- a broken endpoint must not loop for ever
  c_stale        constant interval := interval '15 minutes';   -- a queued request with no response by then is unconfirmed
  r          record;
  v_sent     integer := 0;                          -- posts accepted by pg_net this call (NOT deliveries)
  v_conf     integer := 0;                          -- 2xx confirmed this call
  v_failed   integer := 0;
  v_gave     integer := 0;
  v_req      bigint;
  v_resp     jsonb;
  v_status   integer;
  v_deliv    integer;
  v_posted   boolean;
begin
  if not ops.setting_bool('alert_delivery_enabled', false) then
    -- for EVERY caller, as 145's switch is: applying the migration sends nothing
    return jsonb_build_object('skipped', 'alert_delivery_disabled',
                              'queued', 0, 'confirmed', 0, 'failed', 0, 'given_up', 0);
  end if;

  -- (1) Reconcile what earlier calls queued. Only a 2xx recorded against the request id is a delivery.
  begin
    for r in
      select a.alert_key, a.notify_request_id, a.queued_at from ops.alert a
       where a.notify_request_id is not null and a.delivered_at is null
    loop
      v_resp   := ops.alert_response(r.notify_request_id);
      v_status := nullif(v_resp ->> 'status', '')::integer;
      -- notify-report answers 200 even for an event it does not know ("unknown event", and it answers 200 on its own
      -- errors too, so pg_net never retry-storms). A status alone would therefore call an UNDELIVERED alert delivered
      -- — including every post made before the ops_alert branch is deployed. Confirmation needs the edge's own
      -- accounting: delivered >= 1 for this event.
      begin
        v_deliv := nullif((v_resp ->> 'content')::jsonb ->> 'delivered', '')::integer;
      exception when others then
        v_deliv := null;
      end;
      if v_status between 200 and 299 and coalesce(v_deliv, 0) >= 1 then
        update ops.alert set delivered_at = now(), delivery_status = v_status, last_notify_error = null
         where alert_key = r.alert_key;
        v_conf := v_conf + 1;
      elsif v_status between 200 and 299 then
        -- accepted but nothing was delivered: the branch is not deployed, or every channel failed
        update ops.alert set delivery_status = v_status, notify_request_id = null, queued_at = null,
                             last_notify_error = 'notify-report answered 200 but reported no delivery'
         where alert_key = r.alert_key;
        v_failed := v_failed + 1;
      elsif v_status is not null then
        -- answered, and not a 2xx: a 401 lands here, which is exactly the case that used to look like success
        update ops.alert set delivery_status = v_status, notify_request_id = null, queued_at = null,
                             last_notify_error = format('HTTP %s from notify-report', v_status)
         where alert_key = r.alert_key;
        v_failed := v_failed + 1;
      elsif r.queued_at < now() - c_stale then
        -- no answer at all: unconfirmed, so it becomes eligible again (the attempt cap still applies)
        update ops.alert set notify_request_id = null, queued_at = null,
                             last_notify_error = 'no response recorded within 15 minutes'
         where alert_key = r.alert_key;
        v_failed := v_failed + 1;
      end if;
    end loop;
  exception when others then
    -- reconciliation must never fail a caller either; the next call tries again
    null;
  end;

  -- (2) Alerts that have used up their attempts are COUNTED here, never carried into the batch. Selecting them and
  -- then skipping them inside the loop (which is what this did) let a backlog of dead alerts fill every delivery
  -- slot: with p_limit exhausted alerts older than a new one, the new one was never posted at all — it sat behind a
  -- full batch for ever (reported by the independent review, 2026-09-20). They stay firing and keep their last
  -- error, so an operator still sees them; what they no longer occupy is a delivery slot.
  select count(*) into v_gave
    from ops.alert a
   where a.state = 'firing'
     and a.acknowledged_at is null
     and a.delivered_at is null
     and a.notify_request_id is null
     and a.notify_attempts >= c_max_attempts;

  -- (3) Post the eligible ones: firing, not acknowledged, not delivered, nothing in flight, attempts left.
  for r in
    select a.alert_key, a.kind, a.payload, a.first_fired_at, a.last_fired_at, a.fire_count, a.incident_seq
      from ops.alert a
     where a.state = 'firing'
       and a.acknowledged_at is null
       and a.delivered_at is null
       and a.notify_request_id is null
       and a.notify_attempts < c_max_attempts
     order by a.first_fired_at, a.alert_key
     limit greatest(coalesce(p_limit, 20), 1)
  loop
    begin
      -- ALLOW-LIST ONLY. ops.alert.payload is free-form and is never passed through: a person's details must not
      -- leave the database because an alert happened to carry them (A, 2026-09-19; pinned by pgTAP 213).
      v_req := ops.alert_post(jsonb_strip_nulls(jsonb_build_object(
                     'event',          'ops_alert',
                     'alert_key',      r.alert_key,
                     'kind',           r.kind,
                     'fire_count',     r.fire_count,
                     'incident_seq',   r.incident_seq,   -- so a recurrence is not read as a repeat of what was acked
                     'first_fired_at', r.first_fired_at,
                     'last_fired_at',  r.last_fired_at,
                     'case_id',        r.payload ->> 'case_id',
                     'case_type',      r.payload ->> 'case_type',
                     'jobname',        r.payload ->> 'jobname',
                     'sent_at',        now())));
      if v_req is null then
        -- the functions base URL is not configured: nothing was posted, and that is not an attempt
        v_posted := false;
        update ops.alert set last_notify_error = 'functions base URL (Vault project_url) is not configured'
         where alert_key = r.alert_key;
      else
        -- QUEUED, not delivered: the response is reconciled on a later call.
        v_posted := true;
        update ops.alert set queued_at = now(), notify_request_id = v_req,
                             notify_attempts = notify_attempts + 1, last_notify_error = null
         where alert_key = r.alert_key;
        v_sent := v_sent + 1;
      end if;
    exception when others then
      update ops.alert set notify_attempts = notify_attempts + 1,
                           last_notify_error = left(sqlstate || ': ' || sqlerrm, 500)
       where alert_key = r.alert_key;
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object('queued', v_sent, 'confirmed', v_conf, 'failed', v_failed, 'given_up', v_gave,
                            'max_attempts', c_max_attempts);
end;
$ops$;
revoke all on function ops.dispatch_alerts(integer) from public, anon, authenticated, service_role;

-- ── acknowledgement ─────────────────────────────────────────────────────────────────────────────────────────────
create or replace function ops.alert_ack(p_alert_key text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_uid uuid := auth.uid();
  v_row ops.alert%rowtype;
begin
  perform ops.assert_reader();          -- an operator at aal2: the gate the console's own reads use
  select * into v_row from ops.alert where alert_key = p_alert_key for update;
  if not found then
    raise exception 'not_found: no alert %', p_alert_key using errcode = 'P0002';
  end if;
  if v_row.state <> 'firing' then
    raise exception 'precondition_failed: alert % is %, so there is nothing to acknowledge', p_alert_key, v_row.state
      using errcode = 'P0001';
  end if;
  -- acknowledging is NOT recovering: the condition still clears the alert on its own
  update ops.alert set acknowledged_at = now(), acknowledged_by = v_uid
   where alert_key = p_alert_key returning * into v_row;
  perform ops.audit_write('alert.acknowledged', 'none', null, p_alert_key, nullif(trim(coalesce(p_note, '')), ''),
                          jsonb_build_object('state', v_row.state, 'acknowledged_at', null),
                          jsonb_build_object('state', v_row.state, 'acknowledged_at', v_row.acknowledged_at),
                          'succeeded', null, null);
  return jsonb_build_object('alert_key', v_row.alert_key, 'state', v_row.state, 'incident_seq', v_row.incident_seq,
                            'acknowledged_at', v_row.acknowledged_at, 'acknowledged_by', v_row.acknowledged_by,
                            'queued_at', v_row.queued_at, 'delivered_at', v_row.delivered_at,
                            'notify_attempts', v_row.notify_attempts);
end;
$ops$;
revoke all on function ops.alert_ack(text,text) from public, anon, authenticated, service_role;
grant execute on function ops.alert_ack(text,text) to authenticated;   -- the console; ops.assert_reader() gates it

commit;
