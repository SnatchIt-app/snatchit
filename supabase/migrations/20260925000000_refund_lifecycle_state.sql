-- ============================================================================
-- 20260925000000_refund_lifecycle_state.sql  (registry 150, pgTAP 217)
--
-- Refund lifecycle accuracy. Design and trace:
-- docs/release/REFUND_LIFECYCLE_TRACE_AND_FIX_20260924.md (release/candidate-20260918).
--
-- A Stripe refund has its own status (pending, requires_action, succeeded,
-- failed, canceled) that can change in any direction for up to ~30 days; a card
-- refund can report succeeded and later fail (docs.stripe.com/testing,
-- /refunds). Until now the only writer, record_payment_refund (20260906120000),
-- took no status: every writer called it the moment a refund was created, so a
-- pending, failed or canceled refund was recorded as money returned, and the
-- one-way guard on payments made a later failure unrecordable.
--
-- This migration keeps that one-way record exactly as it is — it is what blocks
-- a payout once a refund is requested, which stays correct — and adds, beside
-- it, the refund's real state:
--   1. public.payment_refund_state      one row per Stripe refund (re_…), any
--                                       status may replace any other (Stripe's
--                                       own object is the input every time)
--   2. public.payment_refund_state_log  append-only audit of every change
--   3. payments.refund_requested_cents / refund_succeeded_cents /
--      refund_failed_cents              the three sums the app reads (the
--                                       existing own-row SELECT covers them);
--                                       only the writer may change them
--   4. public.record_refund_state()     the one writer: records the state,
--                                       COUNTS a refund through
--                                       record_payment_refund only while it is
--                                       pending / requires_action / succeeded
--                                       (a refund first seen failed or canceled
--                                       is never counted), recomputes the sums
--   5. ops.detect_refunds()             118's body verbatim plus two branches
--                                       behind refund_state_detection_enabled
--                                       (seeded false): refund_failed for a
--                                       failed/canceled Stripe refund not
--                                       covered by succeeded refunds, and
--                                       refund_pending for one still pending
--                                       after refund_state_pending_hours (120)
-- No backfill: rows recorded before this migration keep no state (the app shows
-- them as a legacy "Refund recorded"); reconciling them needs an authorised
-- Stripe read (design O-R4).
--
-- Census (public): tables +2 (34), functions +3 (111), policies +0 (37),
-- triggers +2 (40). Rollback: supabase/rollbacks/20260925000000_refund_lifecycle_state_rollback.sql.
-- ============================================================================

-- 1. per-refund state ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_refund_state (
  stripe_refund_id   text        PRIMARY KEY,
  payment_id         uuid        NOT NULL REFERENCES public.payments(id),
  amount_cents       integer     NOT NULL CHECK (amount_cents >= 0),
  status             text        NOT NULL CHECK (status IN ('pending','requires_action','succeeded','failed','canceled')),
  failure_reason     text,
  source             text        NOT NULL CHECK (source IN ('expiry','dashboard','admin','unfulfillable')),
  first_observed_at  timestamptz NOT NULL DEFAULT now(),
  last_observed_at   timestamptz NOT NULL DEFAULT now(),
  last_observed_via  text        NOT NULL CHECK (last_observed_via IN ('create_response','webhook','reconcile'))
);
CREATE INDEX IF NOT EXISTS payment_refund_state_payment_idx ON public.payment_refund_state (payment_id);
ALTER TABLE public.payment_refund_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_refund_state FROM PUBLIC, anon, authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.payment_refund_state TO service_role;

-- 2. append-only change log -------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_refund_state_log (
  id                 bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  stripe_refund_id   text        NOT NULL,
  payment_id         uuid        NOT NULL REFERENCES public.payments(id),
  status             text        NOT NULL,
  amount_cents       integer     NOT NULL,
  failure_reason     text,
  observed_via       text        NOT NULL,
  observed_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS payment_refund_state_log_refund_idx ON public.payment_refund_state_log (stripe_refund_id);
ALTER TABLE public.payment_refund_state_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_refund_state_log FROM PUBLIC, anon, authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.payment_refund_state_log TO service_role;
-- Supabase default privileges also reach the identity sequence; clients get nothing.
REVOKE ALL ON SEQUENCE public.payment_refund_state_log_id_seq FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.payment_refund_state_log_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION 'payment_refund_state_log is append-only (150).';
END; $function$;
REVOKE ALL ON FUNCTION public.payment_refund_state_log_append_only() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_payment_refund_state_log_append_only ON public.payment_refund_state_log;
CREATE TRIGGER trg_payment_refund_state_log_append_only
  BEFORE UPDATE OR DELETE ON public.payment_refund_state_log
  FOR EACH ROW EXECUTE FUNCTION public.payment_refund_state_log_append_only();

-- 3. the sums the app reads, writable only through the writer ----------------------
-- ADD COLUMN with a constant default is a catalog change (no table rewrite).
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS refund_requested_cents integer NOT NULL DEFAULT 0;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS refund_succeeded_cents integer NOT NULL DEFAULT 0;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS refund_failed_cents    integer NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.guard_payment_refund_state_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF coalesce(current_setting('app.refund_state_writer', true), 'off') <> 'on' THEN
    RAISE EXCEPTION 'payments refund-state columns are written only by record_refund_state (150).';
  END IF;
  RETURN NEW;
END; $function$;
REVOKE ALL ON FUNCTION public.guard_payment_refund_state_columns() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_guard_payment_refund_state_columns ON public.payments;
CREATE TRIGGER trg_guard_payment_refund_state_columns
  BEFORE UPDATE OF refund_requested_cents, refund_succeeded_cents, refund_failed_cents ON public.payments
  FOR EACH ROW
  WHEN (NEW.refund_requested_cents IS DISTINCT FROM OLD.refund_requested_cents
     OR NEW.refund_succeeded_cents IS DISTINCT FROM OLD.refund_succeeded_cents
     OR NEW.refund_failed_cents    IS DISTINCT FROM OLD.refund_failed_cents)
  EXECUTE FUNCTION public.guard_payment_refund_state_columns();

-- 4. the one writer --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_refund_state(
  p_payment_intent_id text,
  p_stripe_refund_id  text,
  p_status            text,
  p_amount_cents      integer,
  p_failure_reason    text,
  p_source            text,
  p_observed_via      text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_pay      public.payments%ROWTYPE;
  v_prev     public.payment_refund_state%ROWTYPE;
  v_had      boolean;
  v_changed  boolean;
  v_counted  boolean := false;
  v_req      integer;
  v_ok       integer;
  v_fail     integer;
BEGIN
  IF nullif(p_stripe_refund_id, '') IS NULL THEN
    RAISE EXCEPTION 'REFUND_REFERENCE_REQUIRED';
  END IF;
  IF p_status IS NULL OR p_status NOT IN ('pending','requires_action','succeeded','failed','canceled') THEN
    RAISE EXCEPTION 'INVALID_REFUND_STATUS' USING DETAIL = coalesce(p_status, '<null>');
  END IF;
  IF p_observed_via IS NULL OR p_observed_via NOT IN ('create_response','webhook','reconcile') THEN
    RAISE EXCEPTION 'INVALID_OBSERVATION_SOURCE' USING DETAIL = coalesce(p_observed_via, '<null>');
  END IF;
  IF p_source IS NULL OR p_source NOT IN ('expiry','dashboard','admin','unfulfillable') THEN
    RAISE EXCEPTION 'INVALID_REFUND_SOURCE' USING DETAIL = coalesce(p_source, '<null>');
  END IF;
  IF p_amount_cents IS NULL OR p_amount_cents < 0 THEN
    RAISE EXCEPTION 'INVALID_REFUND_AMOUNT' USING DETAIL = coalesce(p_amount_cents::text, '<null>');
  END IF;

  SELECT * INTO v_pay FROM public.payments
   WHERE stripe_payment_intent_id = p_payment_intent_id
   FOR UPDATE;
  IF NOT FOUND THEN
    -- Unknown to us (test-mode / foreign charge): acknowledged, never retried.
    RETURN jsonb_build_object('recorded', false, 'reason', 'unknown_payment', 'payment_id', NULL);
  END IF;

  SELECT * INTO v_prev FROM public.payment_refund_state
   WHERE stripe_refund_id = p_stripe_refund_id
   FOR UPDATE;
  v_had := FOUND;
  IF v_had AND v_prev.payment_id <> v_pay.id THEN
    RAISE EXCEPTION 'REFUND_PAYMENT_MISMATCH' USING DETAIL = p_stripe_refund_id;
  END IF;
  v_changed := NOT v_had
            OR v_prev.status         IS DISTINCT FROM p_status
            OR v_prev.failure_reason IS DISTINCT FROM p_failure_reason
            OR v_prev.amount_cents   IS DISTINCT FROM p_amount_cents;

  INSERT INTO public.payment_refund_state
    (stripe_refund_id, payment_id, amount_cents, status, failure_reason, source, last_observed_via)
  VALUES (p_stripe_refund_id, v_pay.id, p_amount_cents, p_status, p_failure_reason, p_source, p_observed_via)
  ON CONFLICT (stripe_refund_id) DO UPDATE
     SET amount_cents      = EXCLUDED.amount_cents,
         status            = EXCLUDED.status,
         failure_reason    = EXCLUDED.failure_reason,
         last_observed_at  = now(),
         last_observed_via = EXCLUDED.last_observed_via;

  IF v_changed THEN
    INSERT INTO public.payment_refund_state_log
      (stripe_refund_id, payment_id, status, amount_cents, failure_reason, observed_via)
    VALUES (p_stripe_refund_id, v_pay.id, p_status, p_amount_cents, p_failure_reason, p_observed_via);
  END IF;

  -- Only a refund that is (or was, when first seen) on its way back to the buyer
  -- enters the one-way record. It stays there if it later fails: the record means
  -- "a refund was requested" and keeps the payout blocked; the truth is below.
  IF p_status IN ('pending','requires_action','succeeded') THEN
    PERFORM public.record_payment_refund(p_payment_intent_id, p_stripe_refund_id, NULL, p_amount_cents, p_source);
    v_counted := true;
  END IF;

  SELECT coalesce(sum(amount_cents) FILTER (WHERE status IN ('pending','requires_action')), 0),
         coalesce(sum(amount_cents) FILTER (WHERE status = 'succeeded'), 0),
         coalesce(sum(amount_cents) FILTER (WHERE status IN ('failed','canceled')), 0)
    INTO v_req, v_ok, v_fail
    FROM public.payment_refund_state
   WHERE payment_id = v_pay.id;

  PERFORM set_config('app.refund_state_writer', 'on', true);
  UPDATE public.payments
     SET refund_requested_cents = v_req,
         refund_succeeded_cents = v_ok,
         refund_failed_cents    = v_fail
   WHERE id = v_pay.id;
  PERFORM set_config('app.refund_state_writer', 'off', true);

  RETURN jsonb_build_object(
    'recorded',        true,
    'payment_id',      v_pay.id,
    'refund_status',   p_status,
    'counted',         v_counted,
    'requested_cents', v_req,
    'succeeded_cents', v_ok,
    'failed_cents',    v_fail
  );
END; $function$;
REVOKE ALL ON FUNCTION public.record_refund_state(text, text, text, integer, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_refund_state(text, text, text, integer, text, text, text) TO service_role;

-- 5. operator visibility: 118's ops.detect_refunds, byte for byte, plus the two
--    Stripe-state branches (inserted before the sweep; new declarations after v_res)
insert into ops.setting (key, value) values ('refund_state_detection_enabled', 'false'::jsonb) on conflict (key) do nothing;
insert into ops.setting (key, value) values ('refund_state_pending_hours', '120'::jsonb) on conflict (key) do nothing;

create or replace function ops.detect_refunds()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_pending_keys text[] := array[]::text[];
  v_failed_keys  text[] := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  v_resolved integer := 0;
  r         record;
  v_res     jsonb;
  -- 150: Stripe-reported refund state, off until the owner flips it.
  v_state_on      boolean := ops.setting_bool('refund_state_detection_enabled', false);
  v_pending_hours integer := ops.setting_int('refund_state_pending_hours', 120);
begin
  for r in
    select p.id as payment_id, p.status as payment_status, p.total, p.stripe_payment_intent_id, t.id as transfer_id,
           l.event_name,
           case when t.dispute_resolution in ('resolved_buyer_refunded', 'resolved_partial_refund')
                then format('dispute resolved %s at %s', t.dispute_resolution,
                            to_char(t.dispute_resolved_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'))
                else format('transfer expired at %s and the payment is still succeeded',
                            to_char(coalesce(t.expired_at, t.expires_at) at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"')) end as why
      from public.transfers t
      join public.payments p on p.id = t.payment_id
      left join public.listings l on l.id = t.listing_id
     where p.status <> 'refunded'
       and ((t.dispute_resolution in ('resolved_buyer_refunded', 'resolved_partial_refund'))
            or (t.status = 'expired' and p.status = 'succeeded'
                and coalesce(t.expired_at, t.expires_at, t.created_at) < now() - interval '60 minutes'))
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('refund_pending', 'payment', r.payment_id, null,
               'Refund owed to buyer',
               format('Payment %s ($%s, status %s) for "%s": %s. No refund has landed (payments.status <> refunded).',
                      r.stripe_payment_intent_id, to_char(coalesce(r.total, 0) / 100.0, 'FM999999990.00'),
                      r.payment_status, coalesce(r.event_name, '?'), r.why),
               'p1', null, 'refunds');
    v_pending_keys := v_pending_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;

  -- Completion: a refund that succeeded at the provider is confirmed locally
  -- once the charge.refunded webhook has marked the payment refunded.
  for r in
    select a.id as action_id
      from ops.action a
      join public.payments p on p.id = a.subject_id
     where a.action_type = 'refund_execute' and a.state = 'succeeded_at_provider' and p.status = 'refunded'
  loop
    update ops.action set state = 'succeeded', completed_at = now(), claimed_until = null, version = version + 1
     where id = r.action_id and state = 'succeeded_at_provider';
    perform ops.audit_write('action.outcome.refund_execute', 'payment', null, null, null,
                            jsonb_build_object('state', 'succeeded_at_provider'),
                            jsonb_build_object('state', 'succeeded', 'confirmed_by', 'charge.refunded webhook'),
                            'succeeded', null, r.action_id);
  end loop;

  for r in
    select a.id as action_id, a.subject_id as payment_id, a.state, a.error, a.provider_ref, a.updated_at, a.completed_at
      from ops.action a
     where a.action_type = 'refund_execute'
       and a.subject_id is not null
       and (a.state in ('failed', 'unknown')
            or (a.state = 'succeeded_at_provider' and a.updated_at < now() - interval '60 minutes')
            -- a crash between the claim and the outcome callback leaves the
            -- action at `processing` with an expired (or no) lease
            or (a.state = 'processing'
                and ((a.claimed_until is not null and a.claimed_until < now() - interval '30 minutes')
                     or (a.claimed_until is null and a.updated_at < now() - interval '30 minutes'))))
       and not exists (select 1 from public.payments p where p.id = a.subject_id and p.status = 'refunded')
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('refund_failed', 'payment', r.payment_id, null,
               'Refund execution needs attention',
               format('ops action %s (refund_execute) is %s%s%s; the payment is not refunded locally.',
                      r.action_id, r.state,
                      case when r.provider_ref is not null then format(' (provider ref %s)', r.provider_ref) else '' end,
                      case when r.error is not null then format(': %s', left(r.error, 500)) else '' end),
               'p1', null, 'refunds');
    v_failed_keys := v_failed_keys || (v_res ->> 'dedupe_key');
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
  end loop;

  -- 150: Stripe's own refund state (public.payment_refund_state, written only by
  -- record_refund_state). Keyed per refund (subject_ref = re_…, subject_id NULL, so the
  -- dedupe key is case_type:re_…) and merged into the same sweep sets, so these cases and
  -- the payment-keyed cases above never resolve each other. A case a human closed
  -- (resolved/dismissed with resolved_by set) is not re-opened for the same refund.
  if v_state_on then
    for r in
      select s.stripe_refund_id, s.payment_id, s.status, s.failure_reason, s.amount_cents, s.source,
             p.stripe_payment_intent_id
        from public.payment_refund_state s
        join public.payments p on p.id = s.payment_id
       where s.status in ('failed', 'canceled')
         and p.refund_succeeded_cents < p.total
         and not exists (select 1 from ops."case" c
                          where c.dedupe_key = 'refund_failed:' || s.stripe_refund_id
                            and c.status in ('resolved', 'dismissed') and c.resolved_by is not null)
    loop
      v_scanned := v_scanned + 1;
      v_res := ops.detect_case('refund_failed', 'payment', null, r.stripe_refund_id,
                 'Refund failed at Stripe',
                 format('Refund %s ($%s, source %s) on payment %s (%s) is %s at Stripe%s. This refund did not reach the buyer. '
                        || 'Stripe asks the platform to arrange another way to refund the customer (docs.stripe.com/refunds#failed-refunds); '
                        || 'record what was done on this case, then close it.',
                        r.stripe_refund_id, to_char(r.amount_cents / 100.0, 'FM999999990.00'), r.source,
                        r.payment_id, r.stripe_payment_intent_id, r.status,
                        case when r.failure_reason is not null then format(' (%s)', r.failure_reason) else '' end),
                 'p1', null, 'refunds');
      v_failed_keys := v_failed_keys || (v_res ->> 'dedupe_key');
      if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
    end loop;

    for r in
      select s.stripe_refund_id, s.payment_id, s.status, s.amount_cents, s.first_observed_at,
             p.stripe_payment_intent_id
        from public.payment_refund_state s
        join public.payments p on p.id = s.payment_id
       where s.status in ('pending', 'requires_action')
         and s.first_observed_at < now() - make_interval(hours => v_pending_hours)
         and not exists (select 1 from ops."case" c
                          where c.dedupe_key = 'refund_pending:' || s.stripe_refund_id
                            and c.status in ('resolved', 'dismissed') and c.resolved_by is not null)
    loop
      v_scanned := v_scanned + 1;
      v_res := ops.detect_case('refund_pending', 'payment', null, r.stripe_refund_id,
                 'Refund still pending at Stripe',
                 format('Refund %s ($%s) on payment %s (%s) has been %s at Stripe since %s. Check it in the Stripe Dashboard.',
                        r.stripe_refund_id, to_char(r.amount_cents / 100.0, 'FM999999990.00'),
                        r.payment_id, r.stripe_payment_intent_id, r.status,
                        to_char(r.first_observed_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"')),
                 'p1', null, 'refunds');
      v_pending_keys := v_pending_keys || (v_res ->> 'dedupe_key');
      if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
    end loop;
  end if;

  v_resolved := ops.detect_sweep('refund_pending', v_pending_keys) + ops.detect_sweep('refund_failed', v_failed_keys);
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened, 'resolved', v_resolved);
end;
$ops$;
revoke all on function ops.detect_refunds() from public, anon, authenticated, service_role;
