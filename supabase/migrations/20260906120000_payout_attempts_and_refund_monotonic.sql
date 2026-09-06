-- ============================================================================
-- 20260906120000_payout_attempts_and_refund_monotonic.sql
-- PAYMENTS_RELIABILITY_2026-09 · Package 3 — refund, dispute, payout and
-- account-deletion integrity (findings F05 refund half, F07, F08, F10;
-- pgTAP 060 F-2/F-3).
--
-- PURPOSE
--   1. Payouts are ledgered PER ATTEMPT (public.payout_attempts). Every
--      Stripe /v1/transfers POST is preceded by a claim that freezes the
--      request parameters (destination, amount, currency, idempotency key)
--      and hands the caller a lease; a transfer that Stripe reports is
--      ALWAYS recorded, even when a chargeback landed between the claim and
--      the record (state reversal_required + manual_review PAID_DURING_DISPUTE)
--      — F07 (dispute mid-payout dropped the tr_ id) and F08 (24h key expiry /
--      destination change → second real transfer) are closed by construction.
--   2. transfers.stripe_transfer_id becomes UNIQUE (partial, non-NULL) — 060 F-2.
--   3. Refund/dispute facts on public.payments are MONOTONIC: BEFORE UPDATE
--      guard (refunded is terminal; money/identity columns immutable once
--      succeeded — 060 F-3; refund references never change once set;
--      amount_refunded_cents non-decreasing and ≤ total), append-only
--      public.payment_refunds, payments.amount_refunded_cents, and the single
--      writer public.record_payment_refund(). A lost dispute is a chargeback:
--      recorded with the dispute id, never as stripe_refund_id.
--   4. Account deletion fails closed: public.account_deletion_blockers(uuid)
--      names every open money obligation; public.account_deletions is the
--      restartable phase ledger the delete-account edge advances.
--
-- FORWARD BEHAVIOR (edges that ship with this package)
--   confirm-and-release / enforce-transfer-expiry Phase 2/2b:
--     claim_payout_attempt → (needs_reconcile? search Stripe by transfer_group,
--     reconcile_payout_attempt, STOP) → Stripe pre-flights → mark_payout_requested
--     → POST /v1/transfers (Idempotency-Key = payout_<transfer_id>_a<attempt_no>,
--     transfer_group = transfer id, metadata[attempt_id]) → record_payout_attempt_result.
--   stripe-webhook: charge.refunded / charge.dispute.closed(lost) →
--     record_payment_refund; transfer.created → record_payout_attempt_result
--     via metadata.attempt_id (idempotent on the unique stripe_transfer_id).
--   delete-account: account_deletion_blockers gate (409 / 503) then the
--     account_deletions phase ledger.
--
-- COMPATIBILITY
--   * record_transfer_payout(uuid, text) is UNTOUCHED: the deployed
--     confirm-and-release v34 / enforce-transfer-expiry v36 keep working in
--     either deploy order. They simply do not write payout_attempts rows.
--   * payments guard vs the existing writers (each proven in pgTAP 123):
--       stripe-webhook payment_intent.succeeded  pending|processing|failed → succeeded  OK
--                                                refunded → succeeded                  RAISES (desired:
--                                                Package 2 moves the claim to NOT IN ('succeeded','refunded'))
--       stripe-webhook payment_failed            pending|processing → failed (neq guards)  OK
--       confirm-payment                          any → succeeded (no predicate): same-status
--                                                no-op OK; refunded → succeeded RAISES (desired,
--                                                Package 2 adds the predicate)
--       create-payment-intent retire             pending → failed                          OK
--       enforce-transfer-expiry Phase 1/1b       succeeded → refunded + refunded_at +
--                                                stripe_refund_id                          OK
--       enforce-transfer-expiry quarantine       stripe_livemode                           OK (unguarded)
--       delete_account_cleanup (0563)            buyer_id/seller_id → sentinel: it arms
--                                                app.bypass_transfer_guard before its two
--                                                payments UPDATEs and never resets it, so
--                                                the guard honours EITHER app.bypass_payment_guard
--                                                OR app.bypass_transfer_guard for the
--                                                sentinel-only party rewrite. Its body is
--                                                NOT changed here.
--       ensure_transfer_exists (061)             no payments write since 061               n/a
--   * The claim predicate requires payments.stripe_livemode = true (045):
--     NULL/false rows are not payable by automation (same rule as
--     rowIsLiveActionable in _shared/payout-logic.ts). They surface as
--     PAYMENT_NOT_LIVE → manual review, never a silent skip.
--
-- LOCKS & RUNTIME
--   CREATE TABLE ×3, CREATE INDEX (transfers: SHARE lock for the duration of a
--   scan of a few-hundred-row table — milliseconds), ALTER TABLE payments ADD
--   COLUMN (NULL default, metadata only), CREATE TRIGGER ×6 (brief
--   ACCESS EXCLUSIVE on payments / payout_attempts / payment_refunds),
--   CREATE FUNCTION ×12. No data is rewritten. Whole file runs in one
--   transaction; expected < 1 s.
--
-- PRE-APPLY QUERY (must return zero rows, or the DO block below aborts):
--   SELECT stripe_transfer_id, count(*) FROM public.transfers
--    WHERE stripe_transfer_id IS NOT NULL GROUP BY 1 HAVING count(*) > 1;
--
-- REVIEW ROUND 1 (2026-09-06) — changes folded into this file BEFORE its
-- first apply (it has never been applied anywhere):
--   MAJOR-1  account_deletion_blockers: kind 'unresolved_review' — any
--            webhook_retries row with resolved IS NOT TRUE on one of the
--            user's payments blocks; 'pending_payment' keeps its 24h bound
--            ONLY for payments without such a row (Package 2 parks a captured-
--            but-mismatched charge there with the payment still pending).
--   MAJOR-2  'open_manual_review' blocks regardless of payout_released_at:
--            any manual_review decision on a transfer the user is party to,
--            not superseded by a LATER 'release' decision, while the transfer
--            is not 'reversed' (catches DISPUTE_LOST_AFTER_PAYOUT rows from
--            flag_payout_reversal_required, whose evidence.attempt_id is NULL).
--   MINOR-2  Lock order is transfers → payout_attempts in EVERY writer:
--            claim_payout_attempt, record_payout_attempt_result (now reads the
--            attempt's transfer_id unlocked — immutable by guard — then locks
--            transfers, then the attempt), reconcile_payout_attempt (delegates
--            to record_…) and flag_payout_reversal_required.
--   MINOR-3  payout_attempts is append-only: BEFORE DELETE (row) and BEFORE
--            TRUNCATE (statement) triggers raise, service_role included.
--   MINOR-1  (delete-account edge) the gate AND delete_account_cleanup run on
--            EVERY attempt while phase < done; only the archive / storage /
--            auth-delete steps resume from the recorded phase.
--   MINOR-5  (stripe-webhook edge) transfer.created with an unknown
--            metadata.attempt_id is acknowledged after a webhook_retries
--            review row (rpc_name 'transfer.created') instead of retrying.
--
-- PRE-ENABLE OPS QUERY (MINOR-4) — run BEFORE the new confirm-and-release /
-- enforce-transfer-expiry edges are enabled. The first attempt on a
-- pre-migration transfer cannot search Stripe by transfer_group (legacy POSTs
-- sent none), so a legacy lost-response duplicate is only bounded by Stripe's
-- source_transaction ceiling. List every live transfer that already FAILED a
-- legacy payout and reconcile each by hand (Stripe dashboard: transfers to the
-- seller's account for the charge) before automation retries it:
--   SELECT t.id, t.seller_id, t.payment_id, d.decided_at, d.evidence
--     FROM public.transfers t
--     JOIN public.payments p ON p.id = t.payment_id
--     JOIN public.payout_decisions d ON d.transfer_id = t.id
--    WHERE t.stripe_transfer_id IS NULL
--      AND p.stripe_livemode = true
--      AND 'PAYOUT_TRANSFER_FAILED' = ANY(d.reason_codes)
--    ORDER BY d.decided_at;
--   Also list manual_review decisions on ALREADY-PAID transfers with no later
--   release row: after MAJOR-2 they block those users' account deletion until
--   ops inserts a 'release' decision or the transfer is reversed:
--   SELECT d.transfer_id, d.reason_codes, d.decided_at
--     FROM public.payout_decisions d JOIN public.transfers t ON t.id = d.transfer_id
--    WHERE d.decision = 'manual_review' AND t.payout_released_at IS NOT NULL
--      AND t.status <> 'reversed'
--      AND NOT EXISTS (SELECT 1 FROM public.payout_decisions r
--                       WHERE r.transfer_id = d.transfer_id AND r.decision = 'release'
--                         AND r.decided_at > d.decided_at);
--
-- NOTE-3 (FK follow-up, recorded here next to the lead's disposition):
--   public.stripe_connect_archive.profile_id → profiles has NO ON DELETE. The
--   delete-account edge therefore keeps the Connect id on
--   account_deletions.connect_id instead of writing an archive row. Users who
--   ALREADY have an archive row (044 backfill, create-connect-account:251)
--   cannot delete at all — the auth.users cascade into profiles hits the FK.
--   Follow-up: relax that FK (ON DELETE SET NULL, keep the Stripe id) in its
--   own migration; until then those deletions surface as the auth-delete 500
--   and need ops.
--
-- ROLLBACK
--   supabase/rollbacks/20260906120000_payout_attempts_and_refund_monotonic_rollback.sql
--   drops every object created here (tables, indexes, triggers, functions,
--   the payments column). No pre-existing function body is changed by this
--   migration, so nothing has to be restored.
--
-- VERIFICATION QUERY
--   SELECT (SELECT count(*) FROM pg_tables WHERE schemaname='public'
--            AND tablename IN ('payout_attempts','payment_refunds','account_deletions')) AS tables,   -- 3
--          (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
--            ('claim_payout_attempt','mark_payout_requested','record_payout_attempt_result',
--             'reconcile_payout_attempt','flag_payout_reversal_required','record_payment_refund',
--             'account_deletion_blockers','guard_payout_attempt_columns','guard_payment_transitions',
--             'reset_payment_guard_bypass','payment_refunds_append_only',
--             'payout_attempts_no_delete')) AS functions,                                          -- 12
--          (SELECT count(*) FROM pg_trigger WHERE tgname IN ('trg_guard_payout_attempt_columns',
--            'trg_guard_payment_transitions','trg_reset_payment_guard_bypass',
--            'trg_payment_refunds_append_only','trg_payout_attempts_no_delete',
--            'trg_payout_attempts_no_truncate')) AS triggers,                                      -- 6
--          (SELECT count(*) FROM pg_indexes WHERE indexname='transfers_stripe_transfer_id_uniq') AS idx, -- 1
--          (SELECT count(*) FROM information_schema.columns WHERE table_schema='public'
--            AND table_name='payments' AND column_name='amount_refunded_cents') AS col;              -- 1
--
-- Gate-2 delta: tables +3, functions +12, triggers +6, policies +0.
-- (ci.yml EXPECT_FUNCS / EXPECT_TRIGGERS must be raised by +1 / +2 relative to
--  the round-0 values that counted 11 functions and 4 triggers for this file.)
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. payout_attempts
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payout_attempts (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id        uuid        NOT NULL REFERENCES public.transfers(id),
  payment_id         uuid        NOT NULL REFERENCES public.payments(id),
  attempt_no         int         NOT NULL CHECK (attempt_no > 0),
  -- claimed → requested → unknown → succeeded | failed ; succeeded → reversal_required
  state              text        NOT NULL CHECK (state IN ('claimed','requested','unknown','succeeded','failed','reversal_required')),
  -- Frozen request parameters (immutable after INSERT — see guard below).
  destination        text        NOT NULL,
  amount_cents       int         NOT NULL CHECK (amount_cents > 0),
  currency           text        NOT NULL DEFAULT 'usd',
  source_charge_id   text,
  idempotency_key    text        NOT NULL UNIQUE,          -- payout_<transfer_id>_a<attempt_no>
  stripe_transfer_id text        UNIQUE,
  actor              text        NOT NULL,
  error              jsonb,
  claimed_at         timestamptz NOT NULL DEFAULT now(),
  requested_at       timestamptz,
  resolved_at        timestamptz,
  lease_expires_at   timestamptz NOT NULL,
  UNIQUE (transfer_id, attempt_no)
);

CREATE UNIQUE INDEX IF NOT EXISTS payout_attempts_one_open
  ON public.payout_attempts (transfer_id)
  WHERE state IN ('claimed','requested','unknown');
CREATE UNIQUE INDEX IF NOT EXISTS payout_attempts_one_success
  ON public.payout_attempts (transfer_id)
  WHERE state = 'succeeded';
CREATE INDEX IF NOT EXISTS payout_attempts_open_lease_idx
  ON public.payout_attempts (lease_expires_at)
  WHERE state IN ('claimed','requested','unknown');

ALTER TABLE public.payout_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payout_attempts FROM PUBLIC, anon, authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.payout_attempts TO service_role;

COMMENT ON TABLE public.payout_attempts IS
  'One row per Stripe transfer attempt for a seller payout. Request parameters are '
  'frozen at claim time and immutable; state only advances; one open and one '
  'succeeded attempt per transfer (20260906120000).';

-- Frozen parameters immutable; state may only advance.
CREATE OR REPLACE FUNCTION public.guard_payout_attempt_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_old int; v_new int;
BEGIN
  IF NEW.transfer_id      IS DISTINCT FROM OLD.transfer_id
  OR NEW.payment_id       IS DISTINCT FROM OLD.payment_id
  OR NEW.attempt_no       IS DISTINCT FROM OLD.attempt_no
  OR NEW.destination      IS DISTINCT FROM OLD.destination
  OR NEW.amount_cents     IS DISTINCT FROM OLD.amount_cents
  OR NEW.currency         IS DISTINCT FROM OLD.currency
  OR NEW.idempotency_key  IS DISTINCT FROM OLD.idempotency_key
  OR NEW.claimed_at       IS DISTINCT FROM OLD.claimed_at
  OR (OLD.source_charge_id IS NOT NULL AND NEW.source_charge_id IS DISTINCT FROM OLD.source_charge_id)
  OR (OLD.stripe_transfer_id IS NOT NULL AND NEW.stripe_transfer_id IS DISTINCT FROM OLD.stripe_transfer_id)
  THEN
    RAISE EXCEPTION 'payout_attempts request parameters are immutable (20260906120000).';
  END IF;

  IF NEW.state IS DISTINCT FROM OLD.state THEN
    v_old := CASE OLD.state WHEN 'claimed' THEN 0 WHEN 'requested' THEN 1 WHEN 'unknown' THEN 2
                            WHEN 'failed' THEN 3 WHEN 'succeeded' THEN 4 WHEN 'reversal_required' THEN 5 END;
    v_new := CASE NEW.state WHEN 'claimed' THEN 0 WHEN 'requested' THEN 1 WHEN 'unknown' THEN 2
                            WHEN 'failed' THEN 3 WHEN 'succeeded' THEN 4 WHEN 'reversal_required' THEN 5 END;
    -- failed means "no transfer known"; Stripe evidence of a transfer may still
    -- promote it (failed → succeeded/reversal_required). succeeded may only
    -- become reversal_required. reversal_required is terminal.
    IF v_new <= v_old THEN
      RAISE EXCEPTION 'payout_attempts.state may only advance: % -> % (20260906120000).', OLD.state, NEW.state;
    END IF;
  END IF;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_guard_payout_attempt_columns ON public.payout_attempts;
CREATE TRIGGER trg_guard_payout_attempt_columns
  BEFORE UPDATE ON public.payout_attempts
  FOR EACH ROW EXECUTE FUNCTION public.guard_payout_attempt_columns();

-- Append-only ledger (review round 1 MINOR-3): the attempt trail is the audit
-- record decision 7 relies on. service_role holds DELETE/TRUNCATE and
-- BYPASSRLS, so the guard is a trigger, not a grant. Row-level for DELETE,
-- statement-level for TRUNCATE (row triggers do not fire on TRUNCATE).
CREATE OR REPLACE FUNCTION public.payout_attempts_no_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  RAISE EXCEPTION 'payout_attempts is append-only: rows are never deleted (20260906120000).';
END; $function$;

DROP TRIGGER IF EXISTS trg_payout_attempts_no_delete ON public.payout_attempts;
CREATE TRIGGER trg_payout_attempts_no_delete
  BEFORE DELETE ON public.payout_attempts
  FOR EACH ROW EXECUTE FUNCTION public.payout_attempts_no_delete();

DROP TRIGGER IF EXISTS trg_payout_attempts_no_truncate ON public.payout_attempts;
CREATE TRIGGER trg_payout_attempts_no_truncate
  BEFORE TRUNCATE ON public.payout_attempts
  FOR EACH STATEMENT EXECUTE FUNCTION public.payout_attempts_no_delete();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. transfers.stripe_transfer_id unique (060 F-2)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_dupes text;
BEGIN
  SELECT string_agg(stripe_transfer_id || ' x' || cnt, ', ')
    INTO v_dupes
    FROM (SELECT stripe_transfer_id, count(*) AS cnt FROM public.transfers
           WHERE stripe_transfer_id IS NOT NULL GROUP BY 1 HAVING count(*) > 1) d;
  IF v_dupes IS NOT NULL THEN
    RAISE EXCEPTION 'transfers.stripe_transfer_id has duplicates (%). Resolve them (DAY5 reversal playbook) before applying 20260906120000.', v_dupes;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS transfers_stripe_transfer_id_uniq
  ON public.transfers (stripe_transfer_id)
  WHERE stripe_transfer_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. payments monotonicity
-- ─────────────────────────────────────────────────────────────────────────────
-- NULL = legacy/unknown; never backfilled (a refund we did not observe is not
-- a fact we may invent).
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS amount_refunded_cents int;

CREATE TABLE IF NOT EXISTS public.payment_refunds (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id        uuid        NOT NULL REFERENCES public.payments(id),
  stripe_refund_id  text        UNIQUE,
  stripe_dispute_id text,
  amount_cents      int         NOT NULL CHECK (amount_cents >= 0),
  source            text        NOT NULL CHECK (source IN ('expiry','dispute_lost','dashboard','admin','unfulfillable')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  CHECK (stripe_refund_id IS NOT NULL OR stripe_dispute_id IS NOT NULL)
);
CREATE UNIQUE INDEX IF NOT EXISTS payment_refunds_payment_dispute_uniq
  ON public.payment_refunds (payment_id, stripe_dispute_id)
  WHERE stripe_dispute_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS payment_refunds_payment_idx ON public.payment_refunds (payment_id);

ALTER TABLE public.payment_refunds ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payment_refunds FROM PUBLIC, anon, authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.payment_refunds TO service_role;

CREATE OR REPLACE FUNCTION public.payment_refunds_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  RAISE EXCEPTION 'payment_refunds is append-only (20260906120000).';
END; $function$;

DROP TRIGGER IF EXISTS trg_payment_refunds_append_only ON public.payment_refunds;
CREATE TRIGGER trg_payment_refunds_append_only
  BEFORE UPDATE OR DELETE ON public.payment_refunds
  FOR EACH ROW EXECUTE FUNCTION public.payment_refunds_append_only();

-- Status transitions (documented, exact):
--   pending    → processing | succeeded | failed | refunded
--   processing → succeeded | failed | refunded
--   failed     → pending | succeeded | refunded
--   succeeded  → refunded
--   refunded   → (nothing: TERMINAL)
-- refunded is reachable from every non-terminal status because a captured
-- charge can be refunded while our row lags (webhook missed); failed → pending
-- is the fresh-PI re-mint on an existing row.
CREATE OR REPLACE FUNCTION public.guard_payment_transitions()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  v_sentinel     constant uuid := '00000000-0000-0000-0000-000000000000';
  v_bypass       boolean;
  v_party_only   boolean;
BEGIN
  IF current_setting('app.bypass_payment_guard', true) = 'on' THEN
    RETURN NEW;
  END IF;

  -- delete_account_cleanup (0563) arms app.bypass_transfer_guard before its
  -- payments UPDATEs; honouring it here keeps that body untouched. Either GUC
  -- opens ONLY the sentinel anonymization, nothing else.
  v_bypass := current_setting('app.bypass_transfer_guard', true) = 'on';
  v_party_only :=
        (NEW.buyer_id  IS DISTINCT FROM OLD.buyer_id  OR NEW.seller_id IS DISTINCT FROM OLD.seller_id)
    -- NULL-safe (review round 2, MAJOR-1): production (093) admits payments
    -- rows with seller_id / listing_id NULL (mode 'native_primary'); a plain
    -- `=` on those yields NULL and the anonymisation UPDATE would be refused.
    AND (NEW.buyer_id  IS NOT DISTINCT FROM OLD.buyer_id  OR NEW.buyer_id  = v_sentinel)
    AND (NEW.seller_id IS NOT DISTINCT FROM OLD.seller_id OR NEW.seller_id = v_sentinel)
    AND NEW.status IS NOT DISTINCT FROM OLD.status
    AND NEW.amount IS NOT DISTINCT FROM OLD.amount AND NEW.buyer_fee IS NOT DISTINCT FROM OLD.buyer_fee
    AND NEW.seller_fee IS NOT DISTINCT FROM OLD.seller_fee
    AND NEW.total IS NOT DISTINCT FROM OLD.total AND NEW.mode IS NOT DISTINCT FROM OLD.mode
    AND NEW.listing_id IS NOT DISTINCT FROM OLD.listing_id
    AND NEW.stripe_payment_intent_id IS NOT DISTINCT FROM OLD.stripe_payment_intent_id
    AND NEW.refunded_at IS NOT DISTINCT FROM OLD.refunded_at
    AND NEW.stripe_refund_id IS NOT DISTINCT FROM OLD.stripe_refund_id
    AND NEW.amount_refunded_cents IS NOT DISTINCT FROM OLD.amount_refunded_cents;
  IF v_bypass AND v_party_only THEN
    RETURN NEW;
  END IF;

  -- Status machine.
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF OLD.status = 'refunded' THEN
      RAISE EXCEPTION 'payments.status transition % -> % is not allowed: refunded is terminal (20260906120000).', OLD.status, NEW.status;
    END IF;
    IF NOT (
         (OLD.status = 'pending'    AND NEW.status IN ('processing','succeeded','failed','refunded'))
      OR (OLD.status = 'processing' AND NEW.status IN ('succeeded','failed','refunded'))
      OR (OLD.status = 'failed'     AND NEW.status IN ('pending','succeeded','refunded'))
      OR (OLD.status = 'succeeded'  AND NEW.status = 'refunded')
    ) THEN
      RAISE EXCEPTION 'payments.status transition % -> % is not allowed (20260906120000).', OLD.status, NEW.status;
    END IF;
  END IF;

  -- Money and identity are frozen once the charge succeeded (060 F-3).
  IF OLD.status IN ('succeeded','refunded') AND (
        NEW.amount     IS DISTINCT FROM OLD.amount
     OR NEW.buyer_fee  IS DISTINCT FROM OLD.buyer_fee
     OR NEW.seller_fee IS DISTINCT FROM OLD.seller_fee
     OR NEW.total      IS DISTINCT FROM OLD.total
     OR NEW.mode       IS DISTINCT FROM OLD.mode
     OR NEW.listing_id IS DISTINCT FROM OLD.listing_id
     OR NEW.buyer_id   IS DISTINCT FROM OLD.buyer_id
     OR NEW.seller_id  IS DISTINCT FROM OLD.seller_id
     OR NEW.stripe_payment_intent_id IS DISTINCT FROM OLD.stripe_payment_intent_id
  ) THEN
    RAISE EXCEPTION 'payments money/identity columns are immutable once succeeded (20260906120000).';
  END IF;

  -- Refund references: set once, never changed.
  IF (OLD.refunded_at IS NOT NULL      AND NEW.refunded_at      IS DISTINCT FROM OLD.refunded_at)
  OR (OLD.stripe_refund_id IS NOT NULL AND NEW.stripe_refund_id IS DISTINCT FROM OLD.stripe_refund_id) THEN
    RAISE EXCEPTION 'payments refund facts are monotonic: refunded_at/stripe_refund_id cannot change once set (20260906120000).';
  END IF;

  -- Refunded amount: non-decreasing, bounded by total.
  IF (OLD.amount_refunded_cents IS NOT NULL AND (NEW.amount_refunded_cents IS NULL OR NEW.amount_refunded_cents < OLD.amount_refunded_cents))
  OR (NEW.amount_refunded_cents IS NOT NULL AND (NEW.amount_refunded_cents < 0 OR NEW.amount_refunded_cents > NEW.total)) THEN
    RAISE EXCEPTION 'payments.amount_refunded_cents is non-decreasing and bounded by total (20260906120000).';
  END IF;

  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_guard_payment_transitions ON public.payments;
CREATE TRIGGER trg_guard_payment_transitions
  BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.guard_payment_transitions();

-- One-statement bypass window, exactly like 056c for transfers.
CREATE OR REPLACE FUNCTION public.reset_payment_guard_bypass()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  PERFORM set_config('app.bypass_payment_guard', 'off', true);
  RETURN NULL;
END; $function$;

DROP TRIGGER IF EXISTS trg_reset_payment_guard_bypass ON public.payments;
CREATE TRIGGER trg_reset_payment_guard_bypass
  AFTER INSERT OR UPDATE ON public.payments
  FOR EACH STATEMENT EXECUTE FUNCTION public.reset_payment_guard_bypass();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. record_payment_refund — the ONE writer of refund facts
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.record_payment_refund(
  p_payment_intent_id text,
  p_stripe_refund_id  text,
  p_stripe_dispute_id text,
  p_amount_cents      int,
  p_source            text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_pay        public.payments%ROWTYPE;
  v_amount     int;
  v_sum        int;
  v_new_total  int;
  v_inserted   int := 0;
  v_paid       record;
BEGIN
  IF p_source IS NULL OR p_source NOT IN ('expiry','dispute_lost','dashboard','admin','unfulfillable') THEN
    RAISE EXCEPTION 'INVALID_REFUND_SOURCE' USING DETAIL = coalesce(p_source, '<null>');
  END IF;
  IF nullif(p_stripe_refund_id, '') IS NULL AND nullif(p_stripe_dispute_id, '') IS NULL THEN
    RAISE EXCEPTION 'REFUND_REFERENCE_REQUIRED';
  END IF;
  IF p_source = 'dispute_lost' AND nullif(p_stripe_dispute_id, '') IS NULL THEN
    RAISE EXCEPTION 'REFUND_REFERENCE_REQUIRED' USING DETAIL = 'dispute_lost needs a dispute id';
  END IF;

  SELECT * INTO v_pay FROM public.payments
   WHERE stripe_payment_intent_id = p_payment_intent_id
   FOR UPDATE;
  IF NOT FOUND THEN
    -- Unknown to us (test-mode / foreign charge): acknowledged, never retried.
    RETURN jsonb_build_object('payment_id', NULL, 'status', NULL, 'amount_refunded_cents', NULL,
                              'recorded', false, 'reason', 'unknown_payment');
  END IF;

  -- NULL amount = full refund of what the charge captured (Stripe's
  -- amount-less POST /refunds). Capped at total so a chargeback on an already
  -- refunded charge cannot push the fact past the money that existed.
  v_amount := least(coalesce(p_amount_cents, v_pay.total), v_pay.total);
  IF v_amount < 0 THEN
    RAISE EXCEPTION 'INVALID_REFUND_AMOUNT';
  END IF;

  IF nullif(p_stripe_refund_id, '') IS NOT NULL THEN
    INSERT INTO public.payment_refunds (payment_id, stripe_refund_id, stripe_dispute_id, amount_cents, source)
    VALUES (v_pay.id, p_stripe_refund_id, nullif(p_stripe_dispute_id, ''), v_amount, p_source)
    ON CONFLICT (stripe_refund_id) DO NOTHING;
  ELSE
    INSERT INTO public.payment_refunds (payment_id, stripe_refund_id, stripe_dispute_id, amount_cents, source)
    VALUES (v_pay.id, NULL, p_stripe_dispute_id, v_amount, p_source)
    ON CONFLICT (payment_id, stripe_dispute_id) WHERE stripe_dispute_id IS NOT NULL DO NOTHING;
  END IF;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  SELECT coalesce(sum(amount_cents), 0) INTO v_sum FROM public.payment_refunds WHERE payment_id = v_pay.id;
  v_new_total := least(greatest(coalesce(v_pay.amount_refunded_cents, 0), v_sum), v_pay.total);

  UPDATE public.payments
     SET amount_refunded_cents = v_new_total,
         -- a dispute is a chargeback, never a refund reference
         stripe_refund_id      = coalesce(stripe_refund_id, nullif(p_stripe_refund_id, '')),
         status                = CASE WHEN v_new_total >= total THEN 'refunded' ELSE status END,
         refunded_at           = CASE WHEN v_new_total >= total THEN coalesce(refunded_at, now()) ELSE refunded_at END
   WHERE id = v_pay.id
   RETURNING * INTO v_pay;

  -- Refund AFTER payout (review round 2, MAJOR-2): the seller already holds
  -- money that has just gone back to the buyer. Flag every paid transfer of
  -- this payment for reversal (manual_review decision; deletion blocker
  -- open_manual_review) — once per reason, idempotent. dispute_lost is
  -- excluded: the webhook's charge.dispute.closed branch flags that case as
  -- DISPUTE_LOST_AFTER_PAYOUT itself.
  IF v_inserted = 1 AND p_source <> 'dispute_lost' THEN
    FOR v_paid IN
      SELECT t.id FROM public.transfers t
       WHERE t.payment_id = v_pay.id
         AND (t.payout_released_at IS NOT NULL OR t.stripe_transfer_id IS NOT NULL)
    LOOP
      PERFORM public.flag_payout_reversal_required(
        v_paid.id,
        CASE WHEN v_new_total >= v_pay.total THEN 'REFUNDED_AFTER_PAYOUT' ELSE 'PARTIAL_REFUND_AFTER_PAYOUT' END,
        jsonb_build_object('source', p_source, 'stripe_refund_id', nullif(p_stripe_refund_id, ''),
                           'stripe_dispute_id', nullif(p_stripe_dispute_id, ''),
                           'refund_amount_cents', v_amount, 'amount_refunded_cents', v_new_total));
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'payment_id',            v_pay.id,
    'status',                v_pay.status,
    'amount_refunded_cents', v_pay.amount_refunded_cents,
    'total',                 v_pay.total,
    'recorded',              v_inserted = 1
  );
END; $function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Payout attempt protocol
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.claim_payout_attempt(
  p_transfer_id uuid,
  p_actor       text,
  p_lease       interval DEFAULT '10 minutes'
) RETURNS TABLE(
  attempt_id        uuid,
  attempt_no        int,
  idempotency_key   text,
  destination       text,
  amount_cents      int,
  source_charge_id  text,
  payment_intent_id text,
  needs_reconcile   boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_t     public.transfers%ROWTYPE;
  v_p     public.payments%ROWTYPE;
  v_open  public.payout_attempts%ROWTYPE;
  v_dest  text;
  v_pi    text;
  v_no    int;
  v_amt   int;
  v_lease interval := coalesce(p_lease, interval '10 minutes');
BEGIN
  IF v_lease <= interval '0' OR v_lease > interval '1 hour' THEN
    v_lease := interval '10 minutes';
  END IF;

  SELECT * INTO v_t FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TRANSFER_NOT_FOUND';
  END IF;

  -- An open attempt always wins: it is reconciled, never duplicated. This
  -- check precedes eligibility so an attempt stuck 'unknown' on a transfer
  -- that has since been disputed is still reconciled (F07 compounding).
  SELECT * INTO v_open FROM public.payout_attempts a
   WHERE a.transfer_id = p_transfer_id AND a.state IN ('claimed','requested','unknown')
   FOR UPDATE;
  IF FOUND THEN
    IF v_open.lease_expires_at > now() THEN
      -- Another worker owns it. Handing it out could let this caller mark a
      -- POST that is in flight elsewhere as failed.
      RAISE EXCEPTION 'PAYOUT_ATTEMPT_IN_PROGRESS' USING DETAIL = v_open.id::text;
    END IF;
    UPDATE public.payout_attempts SET lease_expires_at = now() + v_lease WHERE id = v_open.id;
    SELECT p.stripe_payment_intent_id INTO STRICT v_pi FROM public.payments p WHERE p.id = v_open.payment_id;
    RETURN QUERY SELECT v_open.id, v_open.attempt_no, v_open.idempotency_key, v_open.destination,
                        v_open.amount_cents, v_open.source_charge_id, v_pi, true;
    RETURN;
  END IF;

  -- Eligibility (the 056d predicate plus the payment-side truths).
  IF v_t.payout_released_at IS NOT NULL OR v_t.stripe_transfer_id IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.payout_attempts a WHERE a.transfer_id = p_transfer_id AND a.state IN ('succeeded','reversal_required')) THEN
    RAISE EXCEPTION 'ALREADY_RELEASED';
  END IF;
  IF v_t.disputed_at IS NOT NULL AND v_t.dispute_resolution IS DISTINCT FROM 'resolved_seller_paid' THEN
    RAISE EXCEPTION 'DISPUTED';
  END IF;
  IF v_t.status NOT IN ('buyer_confirmed','auto_released') THEN
    RAISE EXCEPTION 'TRANSFER_NOT_RELEASABLE' USING DETAIL = 'status=' || v_t.status;
  END IF;

  SELECT * INTO v_p FROM public.payments WHERE id = v_t.payment_id;
  IF NOT FOUND OR v_p.status <> 'succeeded' THEN
    RAISE EXCEPTION 'PAYMENT_NOT_SUCCEEDED' USING DETAIL = coalesce(v_p.status, '<missing>');
  END IF;
  IF v_p.stripe_livemode IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'PAYMENT_NOT_LIVE';
  END IF;
  IF v_p.stripe_payment_intent_id IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_SUCCEEDED' USING DETAIL = 'no payment intent id';
  END IF;
  -- A partially refunded charge (review round 2, MINOR-3): the platform no
  -- longer retains amount - seller_fee, and who bears a partial refund is an
  -- operator decision. Never pay automatically; the transfer stays an
  -- unpaid_seller_obligation until an operator settles it (DAY5 playbook).
  IF coalesce(v_p.amount_refunded_cents, 0) > 0 THEN
    RAISE EXCEPTION 'PAYMENT_PARTIALLY_REFUNDED'
      USING DETAIL = v_p.amount_refunded_cents::text || '/' || v_p.total::text;
  END IF;

  SELECT pr.stripe_connect_id INTO v_dest FROM public.profiles pr WHERE pr.id = v_t.seller_id;
  IF v_dest IS NULL OR v_dest = '' THEN
    RAISE EXCEPTION 'SELLER_NOT_ONBOARDED';
  END IF;

  -- 10/10 fee model: seller net = amount − seller_fee (integer cents).
  v_amt := v_p.amount - coalesce(v_p.seller_fee, 0);
  IF v_amt <= 0 THEN
    RAISE EXCEPTION 'PAYOUT_AMOUNT_INVALID' USING DETAIL = v_amt::text;
  END IF;

  SELECT coalesce(max(a.attempt_no), 0) + 1 INTO v_no FROM public.payout_attempts a WHERE a.transfer_id = p_transfer_id;

  INSERT INTO public.payout_attempts
    (transfer_id, payment_id, attempt_no, state, destination, amount_cents, currency, source_charge_id,
     idempotency_key, actor, lease_expires_at)
  VALUES
    (p_transfer_id, v_p.id, v_no, 'claimed', v_dest, v_amt, 'usd', NULL,
     'payout_' || p_transfer_id::text || '_a' || v_no::text, coalesce(p_actor, 'unknown'), now() + v_lease)
  RETURNING * INTO v_open;

  RETURN QUERY SELECT v_open.id, v_open.attempt_no, v_open.idempotency_key, v_open.destination,
                      v_open.amount_cents, v_open.source_charge_id, v_p.stripe_payment_intent_id, false;
END; $function$;

CREATE OR REPLACE FUNCTION public.mark_payout_requested(p_attempt_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_updated int;
BEGIN
  -- Last-moment re-check (review round 2, MINOR-5): the claim's eligibility
  -- read and the POST are separated by pre-flights; a dispute, a refund or a
  -- competing payout that landed in between must stop the POST. Returning
  -- false leaves the attempt 'claimed' (nothing was sent); the lease lapses
  -- and the next claim reconciles it to failed, then re-evaluates eligibility.
  UPDATE public.payout_attempts a
     SET state = 'requested', requested_at = now()
   WHERE a.id = p_attempt_id AND a.state = 'claimed'
     AND EXISTS (SELECT 1 FROM public.transfers t
                  WHERE t.id = a.transfer_id
                    AND t.payout_released_at IS NULL AND t.stripe_transfer_id IS NULL
                    AND t.status IN ('buyer_confirmed','auto_released')
                    AND (t.disputed_at IS NULL OR t.dispute_resolution = 'resolved_seller_paid'))
     AND EXISTS (SELECT 1 FROM public.payments p
                  WHERE p.id = a.payment_id AND p.status = 'succeeded'
                    AND coalesce(p.amount_refunded_cents, 0) = 0);
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END; $function$;

-- Shared write path for "Stripe has this transfer". Money already moved, so
-- the transfer row is ALWAYS written; eligibility drift becomes a review item.
CREATE OR REPLACE FUNCTION public.record_payout_attempt_result(
  p_attempt_id         uuid,
  p_stripe_transfer_id text,
  p_outcome            text,
  p_error              jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_a        public.payout_attempts%ROWTYPE;
  v_t        public.transfers%ROWTYPE;
  v_tid      uuid;
  v_state    text;
  v_reasons  text[];
  v_recorded boolean := false;
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('succeeded','failed_not_created','unknown') THEN
    RAISE EXCEPTION 'INVALID_OUTCOME' USING DETAIL = coalesce(p_outcome, '<null>');
  END IF;

  -- Lock order (review round 1 MINOR-2): transfers FIRST, then the attempt —
  -- the same order as claim_payout_attempt / flag_payout_reversal_required,
  -- so a transfer.created webhook racing the 2b sweep serialises on the
  -- transfer row instead of deadlocking (40P01). The attempt's transfer_id is
  -- immutable (guard_payout_attempt_columns), so the unlocked read is safe.
  SELECT a.transfer_id INTO v_tid FROM public.payout_attempts a WHERE a.id = p_attempt_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ATTEMPT_NOT_FOUND';
  END IF;
  SELECT * INTO v_t FROM public.transfers WHERE id = v_tid FOR UPDATE;
  SELECT * INTO v_a FROM public.payout_attempts WHERE id = p_attempt_id FOR UPDATE;

  IF p_outcome = 'unknown' THEN
    IF v_a.state IN ('claimed','requested','unknown') THEN
      UPDATE public.payout_attempts
         SET state = 'unknown', error = coalesce(p_error, error),
             lease_expires_at = now() + interval '10 minutes'
       WHERE id = p_attempt_id
       RETURNING * INTO v_a;
    END IF;
    RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                              'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', false);
  END IF;

  IF p_outcome = 'failed_not_created' THEN
    IF v_a.state IN ('claimed','requested','unknown') THEN
      UPDATE public.payout_attempts
         SET state = 'failed', error = coalesce(p_error, error), resolved_at = now()
       WHERE id = p_attempt_id
       RETURNING * INTO v_a;
    END IF;
    RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                              'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', false);
  END IF;

  -- succeeded
  IF p_stripe_transfer_id IS NULL OR p_stripe_transfer_id = '' THEN
    RAISE EXCEPTION 'STRIPE_TRANSFER_ID_REQUIRED';
  END IF;
  IF v_a.stripe_transfer_id IS NOT NULL AND v_a.stripe_transfer_id <> p_stripe_transfer_id THEN
    RAISE EXCEPTION 'ATTEMPT_TRANSFER_MISMATCH' USING DETAIL = v_a.stripe_transfer_id || ' <> ' || p_stripe_transfer_id;
  END IF;

  IF v_a.state IN ('succeeded','reversal_required') THEN
    -- Idempotent replay (transfer.created webhook after the edge recorded).
    RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                              'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', false);
  END IF;

  -- Always record the money movement on the transfer row (056d refused here — F07).
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers
     SET payout_released_at = coalesce(payout_released_at, now()),
         stripe_transfer_id = p_stripe_transfer_id
   WHERE id = v_a.transfer_id
     AND (stripe_transfer_id IS NULL OR stripe_transfer_id = p_stripe_transfer_id);
  v_recorded := FOUND;

  v_state   := 'succeeded';
  v_reasons := ARRAY[]::text[];
  IF v_t.disputed_at IS NOT NULL AND v_t.dispute_resolution IS DISTINCT FROM 'resolved_seller_paid' THEN
    v_state   := 'reversal_required';
    v_reasons := array_append(v_reasons, 'PAID_DURING_DISPUTE');
  END IF;
  IF NOT v_recorded THEN
    -- The transfer row already carries a DIFFERENT Stripe transfer: two real
    -- transfers exist for one obligation. Never silent.
    v_state   := 'reversal_required';
    v_reasons := array_append(v_reasons, 'DUPLICATE_TRANSFER');
  END IF;

  UPDATE public.payout_attempts
     SET state = v_state, stripe_transfer_id = p_stripe_transfer_id,
         resolved_at = now(), error = coalesce(p_error, error)
   WHERE id = p_attempt_id
   RETURNING * INTO v_a;

  IF v_state = 'reversal_required' THEN
    INSERT INTO public.payout_decisions
      (transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision, reason_codes, evidence,
       buyer_confirmed, dispute_open, actor)
    SELECT v_t.id, v_t.payment_id, v_t.seller_id, v_t.buyer_id, 'high', 'manual_review', v_reasons,
           jsonb_build_object('attempt_id', v_a.id, 'attempt_no', v_a.attempt_no,
                              'stripe_transfer_id', p_stripe_transfer_id,
                              'existing_stripe_transfer_id', v_t.stripe_transfer_id,
                              'amount_cents', v_a.amount_cents, 'destination', v_a.destination),
           v_t.status = 'buyer_confirmed', v_t.disputed_at IS NOT NULL, v_a.actor
    WHERE NOT EXISTS (
      SELECT 1 FROM public.payout_decisions d
       WHERE d.transfer_id = v_t.id AND d.decision = 'manual_review'
         AND d.evidence->>'attempt_id' = v_a.id::text
         AND d.reason_codes && v_reasons);
  END IF;

  RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                            'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', v_recorded,
                            'transfer_id', v_a.transfer_id);
END; $function$;

-- Reconcile after a Stripe search by transfer_group: found → same write path
-- as a success; not found (caller proved it) → the attempt is closed so a
-- fresh attempt can open.
CREATE OR REPLACE FUNCTION public.reconcile_payout_attempt(
  p_attempt_id        uuid,
  p_found_transfer_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF nullif(p_found_transfer_id, '') IS NOT NULL THEN
    RETURN public.record_payout_attempt_result(p_attempt_id, p_found_transfer_id, 'succeeded',
             jsonb_build_object('reconciled', true));
  END IF;
  RETURN public.record_payout_attempt_result(p_attempt_id, NULL, 'failed_not_created',
           jsonb_build_object('reconciled', true, 'reason', 'not_found_on_stripe'));
END; $function$;

-- A paid transfer whose dispute was later LOST: flag the succeeded attempt
-- and queue the reversal for an operator (one decision per reason).
CREATE OR REPLACE FUNCTION public.flag_payout_reversal_required(
  p_transfer_id uuid,
  p_reason_code text,
  p_evidence    jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_t   public.transfers%ROWTYPE;
  v_att uuid;
  v_ins int := 0;
BEGIN
  IF p_reason_code IS NULL OR p_reason_code = '' THEN
    RAISE EXCEPTION 'REASON_CODE_REQUIRED';
  END IF;
  SELECT * INTO v_t FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TRANSFER_NOT_FOUND';
  END IF;
  IF v_t.payout_released_at IS NULL AND v_t.stripe_transfer_id IS NULL THEN
    RETURN jsonb_build_object('transfer_id', p_transfer_id, 'paid_out', false, 'flagged', false);
  END IF;

  UPDATE public.payout_attempts
     SET state = 'reversal_required',
         error = coalesce(error, '{}'::jsonb) || jsonb_build_object('reversal_reason', p_reason_code)
   WHERE transfer_id = p_transfer_id AND state = 'succeeded'
   RETURNING id INTO v_att;

  INSERT INTO public.payout_decisions
    (transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision, reason_codes, evidence,
     buyer_confirmed, dispute_open, actor)
  SELECT v_t.id, v_t.payment_id, v_t.seller_id, v_t.buyer_id, 'high', 'manual_review', ARRAY[p_reason_code],
         coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('stripe_transfer_id', v_t.stripe_transfer_id, 'attempt_id', v_att),
         v_t.status = 'buyer_confirmed', true, 'edge:stripe-webhook'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.payout_decisions d
     WHERE d.transfer_id = v_t.id AND d.decision = 'manual_review' AND p_reason_code = ANY(d.reason_codes));
  GET DIAGNOSTICS v_ins = ROW_COUNT;

  RETURN jsonb_build_object('transfer_id', p_transfer_id, 'paid_out', true, 'flagged', true,
                            'attempt_id', v_att, 'decision_inserted', v_ins = 1,
                            'stripe_transfer_id', v_t.stripe_transfer_id);
END; $function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Account deletion gate + ledger
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.account_deletion_blockers(p_user_id uuid)
RETURNS TABLE(kind text, ref_id uuid)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO 'public'
AS $function$
  WITH party_transfers AS (
    SELECT t.*, p.status AS pay_status, p.total AS pay_total, p.amount_refunded_cents AS pay_refunded
      FROM public.transfers t
      JOIN public.payments p ON p.id = t.payment_id
     WHERE t.seller_id = p_user_id OR t.buyer_id = p_user_id
  ),
  unsettled AS (
    -- settled := paid out, or the buyer's money fully returned
    SELECT * FROM party_transfers pt
     WHERE NOT (pt.payout_released_at IS NOT NULL
                OR (pt.pay_status = 'refunded' AND coalesce(pt.pay_refunded, pt.pay_total) >= pt.pay_total))
  )
  SELECT CASE
           WHEN u.disputed_at IS NOT NULL AND u.dispute_resolved_at IS NULL THEN 'open_dispute'
           WHEN u.status IN ('pending','seller_sent')                          THEN 'active_transfer'
           WHEN u.status IN ('buyer_confirmed','auto_released')                THEN 'unpaid_seller_obligation'
           WHEN u.status IN ('expired','reversed')                             THEN 'pending_refund'
           ELSE 'unsettled_transfer'
         END AS kind, u.id AS ref_id
    FROM unsettled u
  UNION ALL
  SELECT 'paid_no_transfer', p.id
    FROM public.payments p
   WHERE (p.buyer_id = p_user_id OR p.seller_id = p_user_id)
     AND p.status = 'succeeded'
     -- external rail only (review round 2, MAJOR-1): native_primary rows
     -- (093; listing_id NULL) settle on the kernel rail, whose own BP arms
     -- (deletion_blockers_money native arms) cover them.
     AND p.listing_id IS NOT NULL AND p.mode IN ('buy_now','auction')
     AND NOT EXISTS (SELECT 1 FROM public.transfers t WHERE t.payment_id = p.id)
  UNION ALL
  SELECT 'pending_payment', p.id
    FROM public.payments p
   WHERE (p.buyer_id = p_user_id OR p.seller_id = p_user_id)
     AND p.status IN ('pending','processing')
     AND p.listing_id IS NOT NULL AND p.mode IN ('buy_now','auction')
     -- A fresh pending row may still be captured by Stripe; an aged one is an
     -- abandoned checkout UNLESS a review row says the charge WAS captured but
     -- could not be settled (Package 2 binding_mismatch) — then age proves
     -- nothing and the row blocks until the review is resolved (MAJOR-1).
     AND (p.created_at > now() - interval '24 hours'
          OR EXISTS (SELECT 1 FROM public.webhook_retries w
                      WHERE w.payment_id = p.id AND w.resolved IS NOT TRUE))
  UNION ALL
  -- MAJOR-1: every unresolved review row on one of the user's payments is an
  -- open obligation — the platform may be holding captured money for it.
  -- (Rows without a payment_id have no party and cannot be attributed.)
  SELECT DISTINCT 'unresolved_review', w.payment_id
    FROM public.webhook_retries w
    JOIN public.payments p ON p.id = w.payment_id
   WHERE w.resolved IS NOT TRUE
     AND (p.buyer_id = p_user_id OR p.seller_id = p_user_id)
  UNION ALL
  SELECT 'open_dispute', d.id
    FROM public.disputes d
    LEFT JOIN public.payments p ON p.id = d.payment_id
    LEFT JOIN public.transfers t ON t.id = d.transfer_id
   WHERE d.status NOT IN ('won','lost','warning_closed','charge_refunded')
     AND (p.buyer_id = p_user_id OR p.seller_id = p_user_id OR t.buyer_id = p_user_id OR t.seller_id = p_user_id)
  UNION ALL
  SELECT 'open_payout_attempt', a.id
    FROM public.payout_attempts a
    JOIN public.transfers t ON t.id = a.transfer_id
   WHERE a.state IN ('claimed','requested','unknown')
     AND (t.seller_id = p_user_id OR t.buyer_id = p_user_id)
  UNION ALL
  -- MAJOR-2: a manual_review decision blocks BEFORE and AFTER a payout —
  -- PAID_DURING_DISPUTE, DUPLICATE_TRANSFER and DISPUTE_LOST_AFTER_PAYOUT all
  -- land on PAID transfers (a reversal is owed) — until a LATER 'release'
  -- decision supersedes it or the transfer is 'reversed'. Party is taken from
  -- the transfer, so decisions with attempt_id NULL (legacy, flag_…) count.
  SELECT DISTINCT 'open_manual_review', d.transfer_id
    FROM public.payout_decisions d
    JOIN public.transfers t ON t.id = d.transfer_id
   WHERE d.decision = 'manual_review'
     AND (t.seller_id = p_user_id OR t.buyer_id = p_user_id)
     AND t.status <> 'reversed'
     AND NOT EXISTS (SELECT 1 FROM public.payout_decisions r
                      WHERE r.transfer_id = d.transfer_id AND r.decision = 'release' AND r.decided_at > d.decided_at)
  UNION ALL
  SELECT 'open_payout_attempt', a.id
    FROM public.payout_attempts a
    JOIN public.transfers t ON t.id = a.transfer_id
   WHERE a.state = 'reversal_required'
     AND (t.seller_id = p_user_id OR t.buyer_id = p_user_id)
     AND NOT EXISTS (SELECT 1 FROM public.transfers tt WHERE tt.id = a.transfer_id AND tt.status = 'reversed');
$function$;

CREATE TABLE IF NOT EXISTS public.account_deletions (
  user_id     uuid        PRIMARY KEY,
  phase       text        NOT NULL CHECK (phase IN ('gate','archived','cleaned','storage','auth','done')),
  connect_id  text,
  started_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz
);
ALTER TABLE public.account_deletions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_deletions FROM PUBLIC, anon, authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.account_deletions TO service_role;

COMMENT ON TABLE public.account_deletions IS
  'Restartable account-deletion ledger: gate → archived → cleaned → storage → auth → done. '
  'The blocker gate and delete_account_cleanup run on EVERY attempt until done (both idempotent; '
  'after cleanup the gate only sees obligations created since); archive / storage / auth-delete '
  'resume from the recorded phase (20260906120000, review round 1 MINOR-1).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Privileges (SEC-2): every new function is service_role-only or internal.
-- ─────────────────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.guard_payout_attempt_columns()                                   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_payment_transitions()                                      FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reset_payment_guard_bypass()                                     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.payment_refunds_append_only()                                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.payout_attempts_no_delete()                                      FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_payment_refund(text, text, text, int, text)               FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_payout_attempt(uuid, text, interval)                       FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_payout_requested(uuid)                                      FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_payout_attempt_result(uuid, text, text, jsonb)            FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reconcile_payout_attempt(uuid, text)                             FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.flag_payout_reversal_required(uuid, text, jsonb)                 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_deletion_blockers(uuid)                                  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.record_payment_refund(text, text, text, int, text)            TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_payout_attempt(uuid, text, interval)                    TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_payout_requested(uuid)                                   TO service_role;
GRANT EXECUTE ON FUNCTION public.record_payout_attempt_result(uuid, text, text, jsonb)         TO service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_payout_attempt(uuid, text)                          TO service_role;
GRANT EXECUTE ON FUNCTION public.flag_payout_reversal_required(uuid, text, jsonb)              TO service_role;
GRANT EXECUTE ON FUNCTION public.account_deletion_blockers(uuid)                               TO service_role;
