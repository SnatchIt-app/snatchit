-- ROLLBACK 180 · restores every predecessor body VERBATIM (production bodies; ops.order_detail = 157's applied body), drops the 6 predicates.
-- STACKING GUARD (first statement): every reader must carry 180's md5 (applied) or already the predecessor's (no-op re-verify);
-- any third body refuses with nothing changed. Verified md5 + ACL + definer + search_path at the end.
-- No data to restore (180 changed no row).
DO $rbguard180$
DECLARE v_sig text; v_md5 text;
  v_self jsonb := '{"ops.today(boolean)": "d31e8c1c578f15c94ac41deaf85ed74e", "ops.list_cases(jsonb,text,integer,boolean)": "8907693fe649c2ea40bed524236c4a19", "ops.case_detail(uuid)": "9108da306c0c2856246c46d7114272ec", "ops.list_orders(jsonb,text,integer,boolean)": "be2e7e330ab4e49017b7e4108170dde1", "ops.order_detail(uuid)": "7958264c4f259745954753385613bad5", "ops.order_timeline(uuid)": "d75e81db687a7b1a47b9cc072f0b5542", "ops.money_overview(date,date,boolean)": "708abcdfa504ca322d44ef454584ac0b", "ops.list_payouts(jsonb,text,integer,boolean)": "c50b34115582b4ddfc5e77432e2e4935", "ops.reconciliation_queue(text,integer,boolean)": "c612b57722fb38a876a3ef1851940373", "ops.list_listings(jsonb,text,integer,boolean)": "2b8d34b1b2cb9cf9b24c4f5c80b506c4", "ops.listing_detail(uuid)": "a7366de17ff5b017adaec0854db849d3", "ops.list_reports(jsonb,text,integer,boolean)": "58ae87ce90b3817ce40e91fa47c347c6", "ops.search(text,integer,boolean)": "96c9a0beeaf6a8d56bcd02e749a1b087", "ops.money_overview(date,date,boolean)@chain": "0b8ba90ab806af4f0620cbce2a852bf7"}'::jsonb;
  v_pred jsonb := '{"ops.today()": "da8289c36caf73d76b929eb14feaaaad", "ops.list_cases(jsonb,text,integer)": "96177f2e77b88b58a05f8527a568550a", "ops.case_detail(uuid)": "5f6645a0d52d0e58948ff9ae0defdd94", "ops.list_orders(jsonb,text,integer)": "0a66c02369840233f5ce485dcbb4e386", "ops.order_detail(uuid)": "4358f577291f84b25986b8904b38ab36", "ops.order_timeline(uuid)": "1ac47ec8cf7c04459b3307611f8d5c13", "ops.money_overview(date,date)": "2903d6deb3a9949cb317ba9d05b860ab", "ops.list_payouts(jsonb,text,integer)": "c1c81cc8c2f526f2a48bc5b3f060197e", "ops.reconciliation_queue(text,integer)": "b8cfac065c780f07e77e6abf7f8eb129", "ops.list_listings(jsonb,text,integer)": "a9d99c85727437888a526e6d994b45cb", "ops.listing_detail(uuid)": "5208dbb14d749db54c2fdd62e50ab800", "ops.list_reports(jsonb,text,integer)": "b41569ac86023709e7f93d039f06f84b", "ops.search(text,integer)": "8e99fcbe8f57472a54724f8a6be41eaf", "ops.money_overview(date,date)@chain": "895b0fa065d7fbdae1cd192d92219b0e"}'::jsonb;
  v_map  jsonb := '{"ops.today(boolean)": "ops.today()", "ops.list_cases(jsonb,text,integer,boolean)": "ops.list_cases(jsonb,text,integer)", "ops.case_detail(uuid)": "ops.case_detail(uuid)", "ops.list_orders(jsonb,text,integer,boolean)": "ops.list_orders(jsonb,text,integer)", "ops.order_detail(uuid)": "ops.order_detail(uuid)", "ops.order_timeline(uuid)": "ops.order_timeline(uuid)", "ops.money_overview(date,date,boolean)": "ops.money_overview(date,date)", "ops.list_payouts(jsonb,text,integer,boolean)": "ops.list_payouts(jsonb,text,integer)", "ops.reconciliation_queue(text,integer,boolean)": "ops.reconciliation_queue(text,integer)", "ops.list_listings(jsonb,text,integer,boolean)": "ops.list_listings(jsonb,text,integer)", "ops.listing_detail(uuid)": "ops.listing_detail(uuid)", "ops.list_reports(jsonb,text,integer,boolean)": "ops.list_reports(jsonb,text,integer)", "ops.search(text,integer,boolean)": "ops.search(text,integer)"}'::jsonb;   -- 180 signature -> predecessor signature
BEGIN
  FOR v_sig IN SELECT jsonb_object_keys(v_self) LOOP
    IF v_sig NOT LIKE '%@chain' AND to_regprocedure(v_sig) IS NOT NULL THEN
      v_md5 := md5(pg_get_functiondef(to_regprocedure(v_sig)));
      IF v_sig NOT LIKE '%@chain' AND v_md5 IS DISTINCT FROM (v_self ->> v_sig) AND v_md5 IS DISTINCT FROM (v_pred ->> (v_map ->> v_sig)) AND NOT (v_sig = 'ops.money_overview(date,date,boolean)' AND (v_md5 = (v_self ->> 'ops.money_overview(date,date,boolean)@chain') OR v_md5 = (v_pred ->> 'ops.money_overview(date,date)@chain'))) THEN
        RAISE EXCEPTION '180 rollback refused (nothing changed): % carries md5 % (expected 180''s % or the predecessor''s %)', v_sig, v_md5, v_self ->> v_sig, v_pred ->> (v_map ->> v_sig);
      END IF;
    END IF;
  END LOOP;
END
$rbguard180$;

-- ── ops.today: predecessor verbatim ──
DROP FUNCTION IF EXISTS ops.today(boolean);
CREATE OR REPLACE FUNCTION ops.today()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_grace   integer := coalesce((select (value #>> '{}')::integer from ops.setting where key = 'paid_unsettled_grace_minutes'), 10);
  v_soon    integer := coalesce((select (value #>> '{}')::integer from ops.setting where key = 'transfer_deadline_soon_hours'), 6);
  v_wh      integer := coalesce((select (value #>> '{}')::integer from ops.setting where key = 'webhook_stuck_minutes'), 15);
begin
  perform ops.assert_reader();
  return jsonb_build_object(
    'attention', coalesce((select jsonb_agg(ops.case_row(k) order by k.priority, k.due_at nulls last, k.detected_at) from (
                             select * from ops."case"
                              where status not in ('resolved','dismissed')
                              order by priority, due_at nulls last, detected_at
                              limit 200) k), '[]'::jsonb),
    'metrics', jsonb_build_object(
      'open_cases_by_type', coalesce((select jsonb_object_agg(x.case_type, x.n) from (
                               select case_type, count(*) n from ops."case" where status not in ('resolved','dismissed') group by case_type) x), '{}'::jsonb),
      'open_cases',        (select count(*) from ops."case" where status not in ('resolved','dismissed')),
      'paid_unsettled',    (select count(*) from public.payments p
                             where p.status = 'succeeded' and p.paid_at < now() - make_interval(mins => v_grace)
                               and p.mode in ('buy_now','auction')
                               and not exists (select 1 from public.transfers t where t.payment_id = p.id)),
      'transfers_due_6h',  (select count(*) from public.transfers t
                             where t.status = 'pending' and t.expires_at >= now() and t.expires_at < now() + make_interval(hours => v_soon)),
      'transfers_overdue', (select count(*) from public.transfers t where t.status = 'pending' and t.expires_at < now()),
      'refunds_pending',   (select count(*) from public.transfers t join public.payments p on p.id = t.payment_id
                             where p.status = 'succeeded'
                               and (t.status = 'expired' or t.dispute_resolution in ('resolved_buyer_refunded','resolved_partial_refund'))),
      'disputes_open',     (select count(*) from public.transfers t where t.status = 'disputed'),
      'stripe_disputes_open', (select count(*) from public.disputes d where d.status not in ('won','lost','warning_closed','charge_refunded')),
      'evidence_due_72h',  (select count(*) from public.disputes d
                             where d.status not in ('won','lost','warning_closed','charge_refunded')
                               and d.evidence_due_by is not null and d.evidence_due_by < now() + interval '72 hours'),
      'payout_review',     (select count(*) from public.transfers t where t.payout_review_status is not null and t.stripe_transfer_id is null),
      'reports_pending',   (select count(*) from public.reports r where r.status = 'pending'),
      'jobs_failing',      (select count(*) from ops.job_state js where js.enabled and js.consecutive_failures >= 2),
      'webhook_backlog',   (select count(*) from public.stripe_webhook_events w
                             where w.processed_at is null and w.received_at < now() - make_interval(mins => v_wh)),
      'approvals_pending', (select count(*) from ops.approval ap where ap.state = 'pending' and ap.expires_at > now()),
      'alerts_firing',     (select count(*) from ops.alert where state = 'firing')),
    'freshness', jsonb_build_object(
      'snapshot_computed_at',      (select max(computed_at) from ops.metric_snapshot),
      'last_detector_success_at',  (select max(last_success_at) from ops.job_state),
      'last_detector_run_at',      (select max(last_run_at) from ops.job_state),
      'detectors_enabled',         coalesce((select (value #>> '{}')::boolean from ops.setting where key = 'detectors_enabled'), false),
      'generated_at',              now()));
end;
$function$;
REVOKE ALL ON FUNCTION ops.today() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.today() TO authenticated;

-- ── ops.list_cases: predecessor verbatim ──
DROP FUNCTION IF EXISTS ops.list_cases(jsonb,text,integer,boolean);
CREATE OR REPLACE FUNCTION ops.list_cases(p_filters jsonb DEFAULT '{}'::jsonb, p_cursor text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  lim      integer := ops.clamp_limit(p_limit);
  c        record;
  v_status text[] := ops.jsonb_text_array(f -> 'status');
  v_type   text[] := ops.jsonb_text_array(f -> 'case_type');
  v_prio   text[] := ops.jsonb_text_array(f -> 'priority');
  v_assg   text   := nullif(f ->> 'assignee', '');
  v_assg_id uuid;
  v_unassigned boolean := false;
  v_skind  text := nullif(f ->> 'subject_kind', '');
  v_sid    uuid := nullif(f ->> 'subject_id', '')::uuid;
  v_items  jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);
  if v_assg = 'me' then v_assg_id := auth.uid();
  elsif v_assg = 'unassigned' then v_unassigned := true;
  elsif v_assg is not null then v_assg_id := v_assg::uuid; end if;

  with page as (
    select k.created_at as created_at, k.id as id, ops.case_row(k) as item
    from ops."case" k
   where (v_status is null or k.status = any(v_status))
     and (v_type   is null or k.case_type = any(v_type))
     and (v_prio   is null or k.priority = any(v_prio))
     and (v_assg_id is null or k.assignee = v_assg_id)
     and (not v_unassigned or k.assignee is null)
     and (v_skind is null or k.subject_kind = v_skind)
     and (v_sid   is null or k.subject_id = v_sid)
     and (c.ts is null or (k.created_at, k.id) < (c.ts, c.id))
   order by k.created_at desc, k.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null then
    select count(*) into v_count from ops."case" k
     where (v_status is null or k.status = any(v_status))
       and (v_type   is null or k.case_type = any(v_type))
       and (v_prio   is null or k.priority = any(v_prio))
       and (v_assg_id is null or k.assignee = v_assg_id)
       and (not v_unassigned or k.assignee is null)
       and (v_skind is null or k.subject_kind = v_skind)
       and (v_sid   is null or k.subject_id = v_sid);
  end if;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', v_count);
end;
$function$;
REVOKE ALL ON FUNCTION ops.list_cases(jsonb,text,integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.list_cases(jsonb,text,integer) TO authenticated;

-- ── ops.case_detail: predecessor verbatim ──
CREATE OR REPLACE FUNCTION ops.case_detail(p_case_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare k ops."case"%rowtype;
begin
  perform ops.assert_reader();
  select * into k from ops."case" where id = p_case_id;
  if not found then
    raise exception 'not_found: case % does not exist', p_case_id using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'case',    ops.case_row(k),
    'notes',   coalesce((select jsonb_agg(to_jsonb(n) || jsonb_build_object('author_label', ops.actor_label(n.author)) order by n.created_at)
                           from ops.case_note n where n.case_id = k.id), '[]'::jsonb),
    'events',  coalesce((select jsonb_agg(to_jsonb(e) || jsonb_build_object('actor_label', ops.actor_label(e.actor)) order by e.created_at)
                           from ops.case_event e where e.case_id = k.id), '[]'::jsonb),
    'subject', ops.subject_summary(k.subject_kind, k.subject_id, k.subject_ref),
    'actions', coalesce((select jsonb_agg(ops.action_row(a) order by a.requested_at desc) from (
                          select * from ops.action a
                           where (a.subject_kind = 'case' and a.subject_id = k.id)
                              or (k.subject_id is not null and a.subject_kind = k.subject_kind and a.subject_id = k.subject_id)
                              or (k.subject_id is null and k.subject_ref is not null and a.subject_kind = k.subject_kind and a.subject_ref = k.subject_ref)
                           order by a.requested_at desc limit 100) a), '[]'::jsonb),
    'operators', ops.operators());
end;
$function$;
REVOKE ALL ON FUNCTION ops.case_detail(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.case_detail(uuid) TO authenticated;

-- ── ops.list_orders: predecessor verbatim ──
DROP FUNCTION IF EXISTS ops.list_orders(jsonb,text,integer,boolean);
CREATE OR REPLACE FUNCTION ops.list_orders(p_filters jsonb DEFAULT '{}'::jsonb, p_cursor text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f          jsonb := coalesce(p_filters, '{}'::jsonb);
  lim        integer := ops.clamp_limit(p_limit);
  c          record;
  r          record;
  v_pstat    text[] := ops.jsonb_text_array(f -> 'payment_status');
  v_tstat    text[] := ops.jsonb_text_array(f -> 'transfer_status');
  v_pay      text   := nullif(f ->> 'payout_state', '');
  v_case     boolean := (f ->> 'has_open_case')::boolean;
  v_from     timestamptz := nullif(f ->> 'from', '')::timestamptz;
  v_to       timestamptz := nullif(f ->> 'to', '')::timestamptz;
  v_q        text := nullif(trim(coalesce(f ->> 'q', '')), '');
  v_items    jsonb;
  v_last_ts  timestamptz;
  v_last_id  uuid;
  v_n        integer;
  v_count    integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);
  select * into r from ops.uuid_prefix_range(v_q);
  if v_pay is not null and v_pay not in ('released','pending_release','held','manual_review','none') then
    raise exception 'invalid_input: payout_state must be released|pending_release|held|manual_review|none';
  end if;

  with page as (
    select p.created_at as created_at, p.id as id, ops.order_row(p, t) as item
    from public.payments p
    left join public.transfers t on t.payment_id = p.id
   where (v_pstat is null or p.status = any(v_pstat))
     and (v_tstat is null or t.status = any(v_tstat))
     and (v_from is null or p.created_at >= v_from)
     and (v_to   is null or p.created_at <  v_to)
     and (v_pay is null or case v_pay
            when 'released'        then t.stripe_transfer_id is not null
            when 'held'            then t.stripe_transfer_id is null and t.payout_review_status = 'held'
            when 'manual_review'   then t.stripe_transfer_id is null and t.payout_review_status = 'manual_review'
            when 'pending_release' then t.stripe_transfer_id is null and t.payout_review_status is null
                                        and t.status in ('seller_sent','buyer_confirmed','auto_released')
            else t.stripe_transfer_id is null and t.payout_review_status is null
                 and (t.id is null or t.status not in ('seller_sent','buyer_confirmed','auto_released')) end)
     and (v_case is null or v_case = exists (
            select 1 from ops."case" oc
             where oc.status not in ('resolved','dismissed')
               and ((oc.subject_kind = 'payment'  and oc.subject_id = p.id)
                 or (oc.subject_kind = 'transfer' and oc.subject_id = t.id)
                 or (oc.subject_kind = 'listing'  and oc.subject_id = p.listing_id))))
     and (v_q is null
          or (r.lo is not null and (p.id between r.lo and r.hi or t.id between r.lo and r.hi or p.listing_id between r.lo and r.hi))
          or (v_q like 'pi\_%' and p.stripe_payment_intent_id = v_q)
          or (v_q like 're\_%' and p.stripe_refund_id = v_q)
          or (v_q like 'tr\_%' and t.stripe_transfer_id = v_q)
          or (r.lo is null and v_q not like 'pi\_%' and v_q not like 're\_%' and v_q not like 'tr\_%'
              and exists (select 1 from public.listings l where l.id = p.listing_id and l.event_name ilike '%' || v_q || '%')))
     and (c.ts is null or (p.created_at, p.id) < (c.ts, c.id))
   order by p.created_at desc, p.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null then
    select count(*) into v_count
      from public.payments p
      left join public.transfers t on t.payment_id = p.id
     where (v_pstat is null or p.status = any(v_pstat))
       and (v_tstat is null or t.status = any(v_tstat))
       and (v_from is null or p.created_at >= v_from)
       and (v_to   is null or p.created_at <  v_to)
       and v_pay is null and v_case is null and v_q is null;
    -- count_hint is only cheap for status/date filters; null for the rest
    if v_pay is not null or v_case is not null or v_q is not null then v_count := null; end if;
  end if;

  return jsonb_build_object(
    'items', v_items,
    'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
    'count_hint', v_count);
end;
$function$;
REVOKE ALL ON FUNCTION ops.list_orders(jsonb,text,integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.list_orders(jsonb,text,integer) TO authenticated;

-- ── ops.order_detail: predecessor verbatim ──
CREATE OR REPLACE FUNCTION ops.order_detail(p_payment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  p public.payments%rowtype;
  t public.transfers%rowtype;
  v_listing_id uuid;
begin
  perform ops.assert_reader();
  select * into p from public.payments where id = p_payment_id;
  if not found then
    raise exception 'not_found: payment % does not exist', p_payment_id using errcode = 'P0002';
  end if;
  select * into t from public.transfers where payment_id = p.id;
  v_listing_id := p.listing_id;

  return jsonb_build_object(
    'payment',  ops.payment_json(p),
    'transfer', ops.transfer_json(t),
    'listing',  ops.listing_summary(v_listing_id),
    'buyer',    ops.user_summary(p.buyer_id),
    'seller',   ops.user_summary(p.seller_id),
    'disputes', coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at) from public.disputes d
                           where d.payment_id = p.id or (t.id is not null and d.transfer_id = t.id)), '[]'::jsonb),
    'dispute_resolutions', coalesce((select jsonb_agg(to_jsonb(dr) || jsonb_build_object('actor_label', ops.actor_label(dr.actor_id)) order by dr.created_at)
                                       from public.dispute_resolutions dr where dr.transfer_id = t.id), '[]'::jsonb),
    'payout_decisions', coalesce((select jsonb_agg(to_jsonb(pd) order by pd.decided_at) from public.payout_decisions pd
                                   where pd.payment_id = p.id or pd.transfer_id = t.id), '[]'::jsonb),
    'refund', jsonb_build_object(
                'payment_status',   p.status,
                'refunded_at',      p.refunded_at,
                'stripe_refund_id', p.stripe_refund_id,
                'refund_actions',   coalesce((select jsonb_agg(ops.action_row(a) order by a.requested_at desc) from ops.action a
                                               where a.action_type = 'refund_execute' and a.subject_kind = 'payment' and a.subject_id = p.id), '[]'::jsonb)),
    'seller_funds_state', ops.funds_state(t, p),
    'cases', coalesce((select jsonb_agg(ops.case_row(c) order by c.created_at desc) from ops."case" c
                        where (c.subject_kind = 'payment'  and c.subject_id = p.id)
                           or (c.subject_kind = 'transfer' and c.subject_id = t.id)
                           or (c.subject_kind = 'listing'  and c.subject_id = v_listing_id)), '[]'::jsonb),
    'actions', coalesce((select jsonb_agg(ops.action_row(a) order by a.requested_at desc) from (
                          select * from ops.action a
                           where (a.subject_kind = 'payment'  and a.subject_id = p.id)
                              or (a.subject_kind = 'transfer' and a.subject_id = t.id)
                              or (a.subject_kind = 'listing'  and a.subject_id = v_listing_id)
                           order by a.requested_at desc limit 50) a), '[]'::jsonb),
    -- 157: UNCAPPED: every unsettled refund_execute on the payment and payout_release on its transfer, with the
    -- approval that gates it (drives the console's pending-request guard; 'actions' above stays capped at 50).
    'unsettled_money_actions', coalesce((select jsonb_agg(ops.action_row(a) || jsonb_build_object(
                                     'approval_id',         ap.id,
                                     'approval_expires_at', ap.expires_at,
                                     'approval_expired',    coalesce(ap.state = 'pending' and ap.expires_at <= now(), false))
                                   order by a.requested_at desc, a.id)
                                   from ops.action a left join ops.approval ap on ap.id = a.approval_id
                                  where a.state in ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')
                                    and (   (a.action_type = 'refund_execute' and a.subject_kind = 'payment'  and a.subject_id = p.id)
                                         or (a.action_type = 'payout_release' and a.subject_kind = 'transfer' and a.subject_id = t.id))), '[]'::jsonb),
    'evidence', jsonb_build_object(
                  'transfer_evidence_path',   jsonb_build_object('bucket', 'proof-docs', 'path', t.transfer_evidence_path),
                  'transfer_screenshot_path', jsonb_build_object('bucket', 'proof-docs', 'path', to_jsonb(t) ->> 'transfer_screenshot_path'),
                  'dispute_evidence_path',    jsonb_build_object('bucket', 'proof-docs', 'path', t.dispute_evidence_path),
                  'proof_of_ownership_path',  jsonb_build_object('bucket', 'proof-docs',
                                                'path', (select l.proof_of_ownership_path from public.listings l where l.id = v_listing_id))),
    'bank_payout', jsonb_build_object('tracked', false, 'note', 'Bank payouts from the connected account are not tracked (payout.paid webhook only logged).'));
end;
$function$;
REVOKE ALL ON FUNCTION ops.order_detail(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.order_detail(uuid) TO authenticated;

-- ── ops.order_timeline: predecessor verbatim ──
CREATE OR REPLACE FUNCTION ops.order_timeline(p_payment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  p public.payments%rowtype;
  t public.transfers%rowtype;
  v_events jsonb;
begin
  perform ops.assert_reader();
  select * into p from public.payments where id = p_payment_id;
  if not found then
    raise exception 'not_found: payment % does not exist', p_payment_id using errcode = 'P0002';
  end if;
  select * into t from public.transfers where payment_id = p.id;

  with ev(at, source, kind, label, ref) as (
    select p.created_at,  'payment', 'created',  'Payment created (' || p.mode || ')', p.id::text
    union all select p.paid_at,     'payment', 'paid',     'Payment captured $' || (p.total / 100.0)::numeric(12,2)::text, p.stripe_payment_intent_id
    union all select p.failed_at,   'payment', 'failed',   'Payment failed', p.stripe_payment_intent_id
    union all select p.refunded_at, 'payment', 'refunded', 'Payment refunded', p.stripe_refund_id
    union all select t.created_at,          'transfer', 'created',          'Transfer obligation created', t.id::text
    union all select t.seller_sent_at,      'transfer', 'seller_sent',      'Seller marked tickets sent', t.transfer_evidence_path
    union all select t.buyer_viewed_at,     'transfer', 'buyer_viewed',     'Buyer viewed the transfer', null
    union all select t.buyer_confirmed_at,  'transfer', 'buyer_confirmed',  'Buyer confirmed receipt', null
    union all select t.disputed_at,         'transfer', 'disputed',         'Buyer opened a dispute (' || coalesce(t.dispute_reason, '?') || ')', t.dispute_evidence_path
    union all select t.dispute_resolved_at, 'transfer', 'dispute_resolved', 'Dispute resolved: ' || coalesce(t.dispute_resolution, '?'), t.dispute_resolved_by::text
    union all select t.expired_at,          'transfer', 'expired',          'Transfer expired (seller did not send)', null
    union all select t.payout_released_at,  'transfer', 'payout_released',  case when t.stripe_transfer_id is not null
                                                                                 then 'Seller funds released to connected account'
                                                                                 else 'Release recorded; connected-account transfer pending' end, t.stripe_transfer_id
    union all select pd.decided_at, 'payout_decision', pd.decision, 'Payout decision: ' || pd.decision || ' (' || pd.risk_tier || ')', pd.id::text
                from public.payout_decisions pd where pd.payment_id = p.id or (t.id is not null and pd.transfer_id = t.id)
    union all select d.created_at, 'dispute', 'created', 'Stripe dispute opened: ' || coalesce(d.reason, '?'), d.stripe_dispute_id
                from public.disputes d where d.payment_id = p.id or (t.id is not null and d.transfer_id = t.id)
    union all select d.evidence_due_by, 'dispute', 'evidence_due', 'Stripe dispute evidence due', d.stripe_dispute_id
                from public.disputes d where d.payment_id = p.id or (t.id is not null and d.transfer_id = t.id)
    union all select dr.created_at, 'dispute_resolution', dr.outcome, 'Resolution recorded: ' || dr.outcome
                                      || case when dr.refund_required then ' (refund required)' else '' end, dr.id::text
                from public.dispute_resolutions dr where t.id is not null and dr.transfer_id = t.id
    union all select n.created_at, 'notification', n.type, coalesce(n.title, n.type) || ' → ' || coalesce(ops.actor_label(n.user_id), ''), n.id::text
                from public.notifications n
               where n.user_id in (p.buyer_id, p.seller_id)
                 and (n.metadata ->> 'listing_id'  = p.listing_id::text
                   or n.metadata ->> 'payment_id'  = p.id::text
                   or (t.id is not null and n.metadata ->> 'transfer_id' = t.id::text)
                   or (p.listing_id is not null and n.link like '%' || p.listing_id::text || '%')
                   or (t.id is not null and n.link like '%' || t.id::text || '%'))
    union all select a.requested_at, 'ops_action', 'requested', a.action_type || ' requested by ' || coalesce(ops.actor_label(a.requested_by), '?'), a.id::text
                from ops.action a
               where (a.subject_kind = 'payment' and a.subject_id = p.id)
                  or (a.subject_kind = 'transfer' and a.subject_id = t.id)
                  or (a.subject_kind = 'listing' and a.subject_id = p.listing_id)
    union all select a.completed_at, 'ops_action', a.state, a.action_type || ' ' || a.state, a.id::text
                from ops.action a
               where a.completed_at is not null
                 and ((a.subject_kind = 'payment' and a.subject_id = p.id)
                   or (a.subject_kind = 'transfer' and a.subject_id = t.id)
                   or (a.subject_kind = 'listing' and a.subject_id = p.listing_id))
    union all select c.detected_at, 'ops_case', 'detected', 'Case opened: ' || c.title, c.id::text
                from ops."case" c
               where (c.subject_kind = 'payment' and c.subject_id = p.id)
                  or (c.subject_kind = 'transfer' and c.subject_id = t.id)
                  or (c.subject_kind = 'listing' and c.subject_id = p.listing_id)
    union all select c.resolved_at, 'ops_case', c.status, 'Case ' || c.status || ': ' || c.title, c.id::text
                from ops."case" c
               where c.resolved_at is not null
                 and ((c.subject_kind = 'payment' and c.subject_id = p.id)
                   or (c.subject_kind = 'transfer' and c.subject_id = t.id)
                   or (c.subject_kind = 'listing' and c.subject_id = p.listing_id))
  )
  select coalesce(jsonb_agg(jsonb_build_object('at', at, 'source', source, 'kind', kind, 'label', label, 'ref', ref)
                            order by at, source, kind), '[]'::jsonb)
    into v_events
    from ev where at is not null;

  return jsonb_build_object('payment_id', p.id, 'events', v_events,
           'note', 'Stripe webhook receipts are not linkable to an order (stripe_webhook_events has no payment reference).');
end;
$function$;
REVOKE ALL ON FUNCTION ops.order_timeline(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.order_timeline(uuid) TO authenticated;

-- ── ops.money_overview: predecessor verbatim ──
-- ENVIRONMENT-AWARE: restores the predecessor matching the live 180 variant (production 118 body, or the CI chain's parked 126 body).
DO $rbmo180$
DECLARE v_md5 text := md5(pg_get_functiondef(to_regprocedure('ops.money_overview(date,date,boolean)')));
BEGIN
  IF v_md5 = '708abcdfa504ca322d44ef454584ac0b' THEN
    DROP FUNCTION ops.money_overview(date,date,boolean);
    EXECUTE $p1$
CREATE OR REPLACE FUNCTION ops.money_overview(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_to    date := coalesce(p_to,   (now() at time zone 'UTC')::date);
  v_from  date := coalesce(p_from, v_to - 30);
  lo      timestamptz;
  hi      timestamptz;
  m       jsonb;
  v_val   bigint; v_cnt bigint;
begin
  perform ops.assert_reader();
  if v_from > v_to then
    raise exception 'invalid_input: from must not be after to';
  end if;
  if v_to - v_from > 400 then
    raise exception 'invalid_input: range must be 400 days or fewer';
  end if;
  lo := (v_from::timestamp) at time zone 'UTC';
  hi := ((v_to + 1)::timestamp) at time zone 'UTC';
  m := '{}'::jsonb;

  -- Gross captured volume
  select coalesce(sum(p.total), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status in ('succeeded','refunded') and p.paid_at >= lo and p.paid_at < hi;
  m := m || jsonb_build_object('gross_captured_volume', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of payments.total where status in (succeeded, refunded). Captured card volume including buyer fees; refunds are NOT netted out — see refunded_volume.',
         'source', 'public.payments', 'basis', 'paid_at, UTC calendar day'));

  -- Refunded volume
  select coalesce(sum(p.total), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status = 'refunded' and p.refunded_at >= lo and p.refunded_at < hi;
  -- The local model records refund STATUS only: charge.refunded (which Stripe
  -- also sends for partial refunds) flips payments.status to refunded and no
  -- refunded amount is stored. The amount is therefore an UPPER BOUND, never a
  -- headline figure.
  m := m || jsonb_build_object('refunded_volume', jsonb_build_object(
         'value_cents', null, 'upper_bound_cents', v_val, 'count', v_cnt, 'certainty', 'uncertain',
         'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Count of payments with status = refunded. The amount is not available locally: payments records refund status only, and Stripe sends charge.refunded for partial refunds too, so Σ payments.total is only an upper bound. Verify amounts in the Stripe Dashboard.',
         'note', 'upper_bound_cents = Σ payments.total over refunded rows; the true refunded amount may be lower.',
         'source', 'public.payments', 'basis', 'refunded_at, UTC calendar day'));

  -- Platform fees (gross, pre-refund)
  select coalesce(sum(p.buyer_fee + coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status = 'succeeded' and p.paid_at >= lo and p.paid_at < hi;
  m := m || jsonb_build_object('platform_fees_gross', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of buyer_fee + seller_fee on succeeded payments. Gross and pre-refund; not revenue.',
         'source', 'public.payments', 'basis', 'paid_at, UTC calendar day'));

  -- Seller funds released to connected account
  select coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.stripe_transfer_id is not null and t.payout_released_at >= lo and t.payout_released_at < hi;
  m := m || jsonb_build_object('seller_funds_released', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of payments.amount - seller_fee for transfers whose stripe_transfer_id is set (a Stripe Transfer to the seller''s connected account exists). Not a bank payout.',
         'source', 'public.transfers + public.payments', 'basis', 'payout_released_at, UTC calendar day'));

  -- Seller funds pending (point in time)
  select coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.status in ('seller_sent','buyer_confirmed','auto_released') and t.stripe_transfer_id is null
     and p.status = 'succeeded';
  m := m || jsonb_build_object('seller_funds_pending', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', null, 'to', null,
         'definition', 'Seller share (amount - seller_fee) of transfers in seller_sent / buyer_confirmed / auto_released with no Stripe Transfer yet. Point-in-time, not a date range.',
         'source', 'public.transfers + public.payments', 'basis', 'now()'));

  -- Bank payouts — not tracked
  m := m || jsonb_build_object('bank_payouts', jsonb_build_object(
         'value_cents', null, 'count', null, 'currency', 'USD', 'from', null, 'to', null,
         'definition', 'Not tracked. Payouts from connected accounts to sellers'' banks are Stripe-side; the payout.paid webhook is only logged.',
         'source', null, 'basis', 'not_tracked'));

  return jsonb_build_object(
    'from', v_from, 'to', v_to, 'currency', 'USD', 'computed_at', now(),
    'metrics', m,
    'snapshot', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'value', s.value, 'computed_at', s.computed_at) order by s.key)
                            from ops.metric_snapshot s), '[]'::jsonb),
    'snapshot_computed_at', (select max(computed_at) from ops.metric_snapshot));
end;
$function$
$p1$;
  ELSIF v_md5 = '0b8ba90ab806af4f0620cbce2a852bf7' THEN
    DROP FUNCTION ops.money_overview(date,date,boolean);
    EXECUTE $p2$
CREATE OR REPLACE FUNCTION ops.money_overview(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_to    date := coalesce(p_to,   (now() at time zone 'UTC')::date);
  v_from  date := coalesce(p_from, v_to - 30);
  lo      timestamptz;
  hi      timestamptz;
  m       jsonb;
  v_val   bigint; v_cnt bigint;
  v_rf    jsonb;
begin
  perform ops.assert_reader();
  if v_from > v_to then
    raise exception 'invalid_input: from must not be after to';
  end if;
  if v_to - v_from > 400 then
    raise exception 'invalid_input: range must be 400 days or fewer';
  end if;
  lo := (v_from::timestamp) at time zone 'UTC';
  hi := ((v_to + 1)::timestamp) at time zone 'UTC';
  m := '{}'::jsonb;

  -- Gross captured volume
  select coalesce(sum(p.total), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status in ('succeeded','refunded') and p.paid_at >= lo and p.paid_at < hi;
  m := m || jsonb_build_object('gross_captured_volume', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of payments.total where status in (succeeded, refunded). Captured card volume including buyer fees; refunds are NOT netted out — see refunded_volume.',
         'source', 'public.payments', 'basis', 'paid_at, UTC calendar day'));

  -- Refunded volume (126): the one definition, ops.refund_facts, over [lo, hi).
  -- value_cents is the page headline and the release client renders it without
  -- reading certainty, so it is set ONLY when certainty is 'known'; the exact
  -- ledger part always rides in known_cents, and upper_bound_cents is a true
  -- bound (exact + legacy) whenever an unrecorded refund exists.
  v_rf := ops.refund_facts(lo, hi);
  m := m || jsonb_build_object('refunded_volume', jsonb_build_object(
         'value_cents', case when v_rf ->> 'certainty' = 'known' then v_rf -> 'cents' else 'null'::jsonb end,
         'known_cents', v_rf -> 'cents',
         'upper_bound_cents', v_rf -> 'upper_bound_cents',
         'legacy_upper_bound_cents', v_rf -> 'legacy_upper_bound_cents',
         'legacy_count', v_rf -> 'legacy_count',
         'count', v_rf -> 'count', 'full_count', v_rf -> 'full_count', 'partial_count', v_rf -> 'partial_count',
         'certainty', v_rf ->> 'certainty',
         'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Money returned to buyers: refunds and lost chargebacks recorded in the append-only ledger, each payment capped at what it actually refunded. Exact (certainty known) only when every refund in the range is recorded; refunds that predate the ledger have no recorded amount (certainty mixed: known_cents is exact, upper_bound_cents adds those payments'' unrefunded totals).',
         'note', v_rf ->> 'note',
         'source', v_rf ->> 'source', 'basis', v_rf ->> 'basis'));

  -- Platform fees (gross, pre-refund)
  select coalesce(sum(p.buyer_fee + coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.payments p
   where p.status = 'succeeded' and p.paid_at >= lo and p.paid_at < hi;
  m := m || jsonb_build_object('platform_fees_gross', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of buyer_fee + seller_fee on succeeded payments. Gross and pre-refund; not revenue.',
         'source', 'public.payments', 'basis', 'paid_at, UTC calendar day'));

  -- Seller funds released to connected account
  select coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.stripe_transfer_id is not null and t.payout_released_at >= lo and t.payout_released_at < hi;
  m := m || jsonb_build_object('seller_funds_released', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', v_from, 'to', v_to,
         'definition', 'Sum of payments.amount - seller_fee for transfers whose stripe_transfer_id is set (a Stripe Transfer to the seller''s connected account exists). Not a bank payout.',
         'source', 'public.transfers + public.payments', 'basis', 'payout_released_at, UTC calendar day'));

  -- Seller funds pending (point in time)
  select coalesce(sum(p.amount - coalesce(p.seller_fee, 0)), 0), count(*) into v_val, v_cnt
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.status in ('seller_sent','buyer_confirmed','auto_released') and t.stripe_transfer_id is null
     and p.status = 'succeeded';
  m := m || jsonb_build_object('seller_funds_pending', jsonb_build_object(
         'value_cents', v_val, 'count', v_cnt, 'currency', 'USD', 'from', null, 'to', null,
         'definition', 'Seller share (amount - seller_fee) of transfers in seller_sent / buyer_confirmed / auto_released with no Stripe Transfer yet. Point-in-time, not a date range.',
         'source', 'public.transfers + public.payments', 'basis', 'now()'));

  -- Bank payouts — not tracked
  m := m || jsonb_build_object('bank_payouts', jsonb_build_object(
         'value_cents', null, 'count', null, 'currency', 'USD', 'from', null, 'to', null,
         'definition', 'Not tracked. Payouts from connected accounts to sellers'' banks are Stripe-side; the payout.paid webhook is only logged.',
         'source', null, 'basis', 'not_tracked'));

  return jsonb_build_object(
    'from', v_from, 'to', v_to, 'currency', 'USD', 'computed_at', now(),
    'metrics', m,
    'snapshot', coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'value', s.value, 'computed_at', s.computed_at) order by s.key)
                            from ops.metric_snapshot s), '[]'::jsonb),
    'snapshot_computed_at', (select max(computed_at) from ops.metric_snapshot));
end;
$function$
$p2$;
  ELSIF v_md5 IS NULL AND to_regprocedure('ops.money_overview(date,date)') IS NOT NULL THEN
    RAISE NOTICE '180 rollback: ops.money_overview already carries a predecessor body; re-verifying only';
  ELSE
    RAISE EXCEPTION '180 rollback refused (nothing changed): ops.money_overview carries an unexpected body (%)', v_md5;
  END IF;
END
$rbmo180$;
REVOKE ALL ON FUNCTION ops.money_overview(date,date) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.money_overview(date,date) TO authenticated;

-- ── ops.list_payouts: predecessor verbatim ──
DROP FUNCTION IF EXISTS ops.list_payouts(jsonb,text,integer,boolean);
CREATE OR REPLACE FUNCTION ops.list_payouts(p_filters jsonb DEFAULT '{}'::jsonb, p_cursor text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  lim      integer := ops.clamp_limit(p_limit);
  c        record;
  v_state  text := nullif(f ->> 'state', '');
  v_items  jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);
  if v_state is not null and v_state not in ('released','pending_release','held','manual_review','none') then
    raise exception 'invalid_input: state must be released|pending_release|held|manual_review|none';
  end if;

  with page as (
    select t.created_at as created_at, t.id as id,
         ops.transfer_json(t) || jsonb_build_object(
           'seller_funds_state', ops.funds_state(t, p),
           'seller',             ops.user_summary(t.seller_id),
           'event_name',         (select l.event_name from public.listings l where l.id = t.listing_id),
           'payment_status',     p.status,
           'amount',             p.amount,
           'seller_fee',         p.seller_fee,
           'seller_share_cents', p.amount - coalesce(p.seller_fee, 0),
           'payout_decision',    (select to_jsonb(pd) from public.payout_decisions pd where pd.transfer_id = t.id
                                    order by pd.decided_at desc limit 1)) as item
    from public.transfers t
    left join public.payments p on p.id = t.payment_id
   where (v_state is null or case v_state
            when 'released'        then t.stripe_transfer_id is not null
            when 'held'            then t.stripe_transfer_id is null and t.payout_review_status = 'held'
            when 'manual_review'   then t.stripe_transfer_id is null and t.payout_review_status = 'manual_review'
            when 'pending_release' then t.stripe_transfer_id is null and t.payout_review_status is null
                                        and t.status in ('seller_sent','buyer_confirmed','auto_released')
            else t.stripe_transfer_id is null and t.payout_review_status is null
                 and t.status not in ('seller_sent','buyer_confirmed','auto_released') end)
     and (c.ts is null or (t.created_at, t.id) < (c.ts, c.id))
   order by t.created_at desc, t.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null and v_state is null then
    select count(*) into v_count from public.transfers;
  end if;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', v_count);
end;
$function$;
REVOKE ALL ON FUNCTION ops.list_payouts(jsonb,text,integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.list_payouts(jsonb,text,integer) TO authenticated;

-- ── ops.reconciliation_queue: predecessor verbatim ──
DROP FUNCTION IF EXISTS ops.reconciliation_queue(text,integer,boolean);
CREATE OR REPLACE FUNCTION ops.reconciliation_queue(p_cursor text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  lim     integer := ops.clamp_limit(p_limit);
  c       record;
  v_items jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);

  with recon (kind, subject_kind, subject_id, detail, since) as (
  select 'refunded_but_released', 'transfer', t.id,
         jsonb_build_object('payment_id', p.id, 'stripe_transfer_id', t.stripe_transfer_id, 'transfer_status', t.status, 'refunded_at', p.refunded_at),
         coalesce(p.refunded_at, t.payout_released_at, now())
    from public.payments p join public.transfers t on t.payment_id = p.id
   where p.status = 'refunded' and t.stripe_transfer_id is not null and t.status <> 'reversed'
  union all
  select 'total_mismatch', 'payment', p.id,
         jsonb_build_object('amount', p.amount, 'buyer_fee', p.buyer_fee, 'total', p.total, 'expected_total', p.amount + p.buyer_fee, 'status', p.status),
         p.created_at
    from public.payments p
   where p.total <> p.amount + p.buyer_fee
  union all
  select 'release_unconfirmed', 'transfer', t.id,
         jsonb_build_object('payout_released_at', t.payout_released_at, 'transfer_status', t.status, 'payment_id', t.payment_id),
         t.payout_released_at
    from public.transfers t
   where t.payout_released_at is not null and t.stripe_transfer_id is null
     and t.payout_released_at < now() - interval '30 minutes'
     and t.status not in ('reversed','expired')
  union all
  select 'expired_without_refund', 'payment', p.id,
         jsonb_build_object('transfer_id', t.id, 'expired_at', t.expired_at, 'payment_status', p.status),
         coalesce(t.expired_at, t.expires_at, now())
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.status = 'expired' and p.status = 'succeeded'
  union all
  select 'buyer_win_without_refund', 'payment', p.id,
         jsonb_build_object('transfer_id', t.id, 'dispute_resolution', t.dispute_resolution, 'dispute_resolved_at', t.dispute_resolved_at, 'payment_status', p.status),
         coalesce(t.dispute_resolved_at, now())
    from public.transfers t join public.payments p on p.id = t.payment_id
   where t.dispute_resolution in ('resolved_buyer_refunded','resolved_partial_refund') and p.status = 'succeeded'
  union all
  select 'action_outcome_unknown', 'action', a.id,
         jsonb_build_object('action_type', a.action_type, 'state', a.state, 'subject_kind', a.subject_kind, 'subject_id', a.subject_id,
                            'provider_ref', a.provider_ref, 'error', a.error),
         coalesce(a.completed_at, a.updated_at)
    from ops.action a
   where a.state = 'unknown'
      or (a.state = 'succeeded_at_provider' and a.updated_at < now() - interval '1 hour')
  ),
  page as (
    select x.* from recon x
     where c.ts is null or (x.since, x.subject_id) < (c.ts, c.id)
     order by x.since desc, x.subject_id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by since desc, subject_id desc) as rn from page)
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'subject_kind', subject_kind, 'subject_id', subject_id,
                                               'detail', detail, 'since', since,
                                               'subject_label', ops.subject_label(subject_kind, subject_id, null))
                            order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(since) filter (where rn = lim),
         (max(subject_id::text) filter (where rn = lim))::uuid,
         count(*),
         (select count(*) from recon)
    into v_items, v_last_ts, v_last_id, v_n, v_count
    from numbered;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', case when p_cursor is null then v_count end,
           'generated_at', now());
end;
$function$;
REVOKE ALL ON FUNCTION ops.reconciliation_queue(text,integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.reconciliation_queue(text,integer) TO authenticated;

-- ── ops.list_listings: predecessor verbatim ──
DROP FUNCTION IF EXISTS ops.list_listings(jsonb,text,integer,boolean);
CREATE OR REPLACE FUNCTION ops.list_listings(p_filters jsonb DEFAULT '{}'::jsonb, p_cursor text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  lim      integer := ops.clamp_limit(p_limit);
  c        record;
  r        record;
  v_status text := nullif(f ->> 'status', '');
  v_astat  text := nullif(f ->> 'auction_status', '');
  v_seller uuid := nullif(f ->> 'seller_id', '')::uuid;
  v_q      text := nullif(trim(coalesce(f ->> 'q', '')), '');
  v_rep    boolean := (f ->> 'has_reports')::boolean;
  v_items  jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);
  select * into r from ops.uuid_prefix_range(v_q);

  with page as (
    select l.created_at as created_at, l.id as id,
         ops.listing_summary(l.id) || jsonb_build_object(
           'seller_display_name', (select pr.display_name from public.profiles pr where pr.id = l.seller_id),
           'report_count',  (select count(*) from public.reports rp where rp.target_type = 'listing' and rp.target_id = l.id),
           'payment_status',(select p.status from public.payments p where p.listing_id = l.id order by p.created_at desc limit 1),
           'open_cases',    (select count(*) from ops."case" oc where oc.subject_kind = 'listing' and oc.subject_id = l.id
                                                                  and oc.status not in ('resolved','dismissed'))) as item
    from public.listings l
   where (v_status is null or l.status = v_status)
     and (v_astat  is null or l.auction_status = v_astat)
     and (v_seller is null or l.seller_id = v_seller)
     and (v_q is null
          or (r.lo is not null and l.id between r.lo and r.hi)
          or (r.lo is null and l.event_name ilike '%' || v_q || '%'))
     and (v_rep is null or v_rep = exists (select 1 from public.reports rp where rp.target_type = 'listing' and rp.target_id = l.id))
     and (c.ts is null or (l.created_at, l.id) < (c.ts, c.id))
   order by l.created_at desc, l.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null and v_q is null and v_rep is null then
    select count(*) into v_count from public.listings l
     where (v_status is null or l.status = v_status)
       and (v_astat  is null or l.auction_status = v_astat)
       and (v_seller is null or l.seller_id = v_seller);
  end if;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', v_count);
end;
$function$;
REVOKE ALL ON FUNCTION ops.list_listings(jsonb,text,integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.list_listings(jsonb,text,integer) TO authenticated;

-- ── ops.listing_detail: predecessor verbatim ──
CREATE OR REPLACE FUNCTION ops.listing_detail(p_listing_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l public.listings%rowtype;
begin
  perform ops.assert_reader();
  select * into l from public.listings where id = p_listing_id;
  if not found then
    raise exception 'not_found: listing % does not exist', p_listing_id using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'listing',  to_jsonb(l),
    'seller',   ops.user_summary(l.seller_id),
    'payments', coalesce((select jsonb_agg(ops.order_row(p, t) order by p.created_at desc)
                            from public.payments p left join public.transfers t on t.payment_id = p.id
                           where p.listing_id = l.id), '[]'::jsonb),
    'transfer', (select ops.transfer_json(t) from public.transfers t where t.listing_id = l.id),
    'bids', jsonb_build_object(
              'count',   (select count(*) from public.bids b where b.listing_id = l.id),
              'highest', (select max(b.amount) from public.bids b where b.listing_id = l.id),
              'highest_bidder_id', l.highest_bidder_id,
              'recent',  coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'amount', b.amount, 'bidder_id', b.bidder_id,
                                                                        'bidder_display_name', ops.actor_label(b.bidder_id), 'created_at', b.created_at)
                                                    order by b.created_at desc)
                                     from (select * from public.bids where listing_id = l.id order by created_at desc limit 20) b), '[]'::jsonb)),
    'reports', coalesce((select jsonb_agg(to_jsonb(rp) || jsonb_build_object('reporter_label', ops.actor_label(rp.reporter_id)) order by rp.created_at desc)
                           from public.reports rp where rp.target_type = 'listing' and rp.target_id = l.id), '[]'::jsonb),
    'seller_flags', coalesce((select jsonb_agg(to_jsonb(sf) order by sf.created_at desc) from public.seller_flags sf where sf.listing_id = l.id), '[]'::jsonb),
    'cases', coalesce((select jsonb_agg(ops.case_row(k) order by k.created_at desc) from ops."case" k
                        where k.subject_kind = 'listing' and k.subject_id = l.id), '[]'::jsonb),
    'actions', coalesce((select jsonb_agg(ops.action_row(a) order by a.requested_at desc) from (
                          select * from ops.action a where a.subject_kind = 'listing' and a.subject_id = l.id
                           order by a.requested_at desc limit 50) a), '[]'::jsonb),
    'evidence', jsonb_build_object(
                  'proof_of_ownership_path', jsonb_build_object('bucket', 'proof-docs', 'path', l.proof_of_ownership_path),
                  'cover_image_path',        jsonb_build_object('bucket', 'auction-media', 'path', l.cover_image_path)));
end;
$function$;
REVOKE ALL ON FUNCTION ops.listing_detail(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.listing_detail(uuid) TO authenticated;

-- ── ops.list_reports: predecessor verbatim ──
DROP FUNCTION IF EXISTS ops.list_reports(jsonb,text,integer,boolean);
CREATE OR REPLACE FUNCTION ops.list_reports(p_filters jsonb DEFAULT '{}'::jsonb, p_cursor text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  lim      integer := ops.clamp_limit(p_limit);
  c        record;
  v_status text[] := ops.jsonb_text_array(f -> 'status');
  v_ttype  text := nullif(f ->> 'target_type', '');
  v_items  jsonb; v_last_ts timestamptz; v_last_id uuid; v_n integer; v_count integer;
begin
  perform ops.assert_reader();
  select * into c from ops.cursor_decode(p_cursor);

  with page as (
    select rp.created_at as created_at, rp.id as id,
         to_jsonb(rp) || jsonb_build_object(
           'reporter_label', ops.actor_label(rp.reporter_id),
           'target_label',   ops.subject_label(rp.target_type, rp.target_id, null),
           'open_cases',     (select count(*) from ops."case" oc where oc.subject_kind = 'report' and oc.subject_id = rp.id
                                                                   and oc.status not in ('resolved','dismissed'))) as item
    from public.reports rp
   where (v_status is null or rp.status = any(v_status))
     and (v_ttype  is null or rp.target_type = v_ttype)
     and (c.ts is null or (rp.created_at, rp.id) < (c.ts, c.id))
   order by rp.created_at desc, rp.id desc
     limit lim + 1),
  numbered as (select page.*, row_number() over (order by created_at desc, id desc) as rn from page)
  select coalesce(jsonb_agg(item order by rn) filter (where rn <= lim), '[]'::jsonb),
         max(created_at) filter (where rn = lim),
         (max(id::text) filter (where rn = lim))::uuid,
         count(*)
    into v_items, v_last_ts, v_last_id, v_n
    from numbered;

  if p_cursor is null then
    select count(*) into v_count from public.reports rp
     where (v_status is null or rp.status = any(v_status))
       and (v_ttype  is null or rp.target_type = v_ttype);
  end if;

  return jsonb_build_object('items', v_items,
           'next_cursor', case when v_n > lim then ops.cursor_encode(v_last_ts, v_last_id) end,
           'count_hint', v_count);
end;
$function$;
REVOKE ALL ON FUNCTION ops.list_reports(jsonb,text,integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.list_reports(jsonb,text,integer) TO authenticated;

-- ── ops.search: predecessor verbatim ──
DROP FUNCTION IF EXISTS ops.search(text,integer,boolean);
CREATE OR REPLACE FUNCTION ops.search(p_q text, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  q      text := trim(coalesce(p_q, ''));
  lim    integer := greatest(1, least(100, coalesce(p_limit, 20)));
  r      record;
  v_hits jsonb;
begin
  perform ops.assert_reader();
  if length(q) < 2 then
    return jsonb_build_object('q', q, 'hits', '[]'::jsonb);
  end if;
  select * into r from ops.uuid_prefix_range(q);

  with hits as (
    -- Stripe ids
    select 'payment' as kind, p.id, coalesce(l.event_name, 'payment') as label, p.stripe_payment_intent_id as sub, p.status, p.created_at
      from public.payments p left join public.listings l on l.id = p.listing_id
     where q like 'pi\_%' and p.stripe_payment_intent_id = q
    union all
    select 'payment', p.id, coalesce(l.event_name, 'payment'), 'refund ' || p.stripe_refund_id, p.status, p.created_at
      from public.payments p left join public.listings l on l.id = p.listing_id
     where q like 're\_%' and p.stripe_refund_id = q
    union all
    select 'transfer', t.id, coalesce(l.event_name, 'transfer'), 'stripe transfer ' || t.stripe_transfer_id, t.status, t.created_at
      from public.transfers t left join public.listings l on l.id = t.listing_id
     where q like 'tr\_%' and t.stripe_transfer_id = q
    union all
    select 'dispute', d.id, 'stripe dispute ' || d.stripe_dispute_id, coalesce(d.reason, ''), d.status, d.created_at
      from public.disputes d
     where q like 'dp\_%' and d.stripe_dispute_id = q
    -- uuid prefix ranges (btree pkey scans)
    union all
    select 'payment', p.id, coalesce(l.event_name, 'payment'), p.stripe_payment_intent_id, p.status, p.created_at
      from public.payments p left join public.listings l on l.id = p.listing_id
     where r.lo is not null and p.id between r.lo and r.hi
    union all
    select 'transfer', t.id, coalesce(l.event_name, 'transfer'), t.transfer_method, t.status, t.created_at
      from public.transfers t left join public.listings l on l.id = t.listing_id
     where r.lo is not null and t.id between r.lo and r.hi
    union all
    select 'listing', l.id, l.event_name, l.venue, coalesce(l.auction_status, l.status), l.created_at
      from public.listings l
     where r.lo is not null and l.id between r.lo and r.hi
    union all
    select 'user', pr.id, coalesce(pr.display_name, ''), ops.mask_email(u.email), null::text, pr.created_at
      from public.profiles pr left join auth.users u on u.id = pr.id
     where r.lo is not null and pr.id between r.lo and r.hi
    union all
    select 'dispute', d.id, 'stripe dispute ' || d.stripe_dispute_id, coalesce(d.reason, ''), d.status, d.created_at
      from public.disputes d
     where r.lo is not null and d.id between r.lo and r.hi
    -- exact email / phone
    union all
    select 'user', pr.id, coalesce(pr.display_name, ''), ops.mask_email(u.email), null::text, pr.created_at
      from auth.users u join public.profiles pr on pr.id = u.id
     where position('@' in q) > 1 and lower(u.email) = lower(q)
    union all
    select 'user', pr.id, coalesce(pr.display_name, ''), ops.mask_phone(coalesce(pr.phone_number, pr.phone)), null::text, pr.created_at
      from public.profiles pr
     where q ~ '^\+?[0-9][0-9 ()-]{6,}$' and (pr.phone_number = q or pr.phone = q)
    -- text
    union all
    select 'listing', l.id, l.event_name, l.venue, coalesce(l.auction_status, l.status), l.created_at
      from public.listings l
     where r.lo is null and position('@' in q) = 0 and l.event_name ilike '%' || q || '%'
    union all
    select 'user', pr.id, coalesce(pr.display_name, ''), null::text, null::text, pr.created_at
      from public.profiles pr
     where r.lo is null and position('@' in q) = 0 and pr.display_name ilike '%' || q || '%'
  ),
  ranked as (
    select distinct on (kind, id) kind, id, label, sub, status, created_at
      from hits order by kind, id, created_at desc
  )
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'id', id, 'label', label, 'sub', sub, 'status', status)
                            order by created_at desc), '[]'::jsonb)
    into v_hits
    from (select * from ranked order by created_at desc limit lim) s;

  return jsonb_build_object('q', q, 'hits', v_hits);
end;
$function$;
REVOKE ALL ON FUNCTION ops.search(text,integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION ops.search(text,integer) TO authenticated;
DROP FUNCTION IF EXISTS ops.is_test_payment(uuid);
DROP FUNCTION IF EXISTS ops.is_test_transfer(uuid);
DROP FUNCTION IF EXISTS ops.is_test_listing(uuid);
DROP FUNCTION IF EXISTS ops.is_test_report(uuid);
DROP FUNCTION IF EXISTS ops.is_test_case(uuid);
DROP FUNCTION IF EXISTS ops.is_test_subject(text,uuid);

DO $rbverify180$
DECLARE v_sig text; v_bad text := ''; v_acl text;
  v_pred jsonb := '{"ops.today()": "da8289c36caf73d76b929eb14feaaaad", "ops.list_cases(jsonb,text,integer)": "96177f2e77b88b58a05f8527a568550a", "ops.case_detail(uuid)": "5f6645a0d52d0e58948ff9ae0defdd94", "ops.list_orders(jsonb,text,integer)": "0a66c02369840233f5ce485dcbb4e386", "ops.order_detail(uuid)": "4358f577291f84b25986b8904b38ab36", "ops.order_timeline(uuid)": "1ac47ec8cf7c04459b3307611f8d5c13", "ops.money_overview(date,date)": "2903d6deb3a9949cb317ba9d05b860ab", "ops.list_payouts(jsonb,text,integer)": "c1c81cc8c2f526f2a48bc5b3f060197e", "ops.reconciliation_queue(text,integer)": "b8cfac065c780f07e77e6abf7f8eb129", "ops.list_listings(jsonb,text,integer)": "a9d99c85727437888a526e6d994b45cb", "ops.listing_detail(uuid)": "5208dbb14d749db54c2fdd62e50ab800", "ops.list_reports(jsonb,text,integer)": "b41569ac86023709e7f93d039f06f84b", "ops.search(text,integer)": "8e99fcbe8f57472a54724f8a6be41eaf", "ops.money_overview(date,date)@chain": "895b0fa065d7fbdae1cd192d92219b0e"}'::jsonb;
BEGIN
  FOR v_sig IN SELECT jsonb_object_keys(v_pred) LOOP
    IF v_sig LIKE '%@chain' THEN CONTINUE; END IF;
    IF to_regprocedure(v_sig) IS NULL THEN v_bad := v_bad || v_sig || ' missing; '; CONTINUE; END IF;
    IF md5(pg_get_functiondef(to_regprocedure(v_sig))) IS DISTINCT FROM (v_pred ->> v_sig) AND NOT (v_sig = 'ops.money_overview(date,date)' AND md5(pg_get_functiondef(to_regprocedure(v_sig))) = (v_pred ->> 'ops.money_overview(date,date)@chain')) THEN v_bad := v_bad || v_sig || ' md5 differs from the predecessor; '; END IF;
    v_acl := (SELECT coalesce(array_to_string(proacl, ','), '<default>') FROM pg_proc WHERE oid = to_regprocedure(v_sig));
    IF v_acl !~ 'authenticated=X' OR v_acl ~ 'anon=X' OR v_acl ~ 'service_role=X' OR v_acl ~ '^=X' THEN v_bad := v_bad || format('%s acl %s; ', v_sig, v_acl); END IF;
  END LOOP;
  IF to_regprocedure('ops.is_test_payment(uuid)') IS NOT NULL THEN v_bad := v_bad || 'predicates still present; '; END IF;
  IF v_bad <> '' THEN RAISE EXCEPTION '180 rollback verification failed (nothing changed): %', v_bad; END IF;
  RAISE NOTICE '180 rolled back: every predecessor body, ACL and definer verified';
END
$rbverify180$;
