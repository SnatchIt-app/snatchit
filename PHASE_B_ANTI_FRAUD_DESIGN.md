# Phase B — Anti-Fraud & Seller Risk Controls

**Date:** 2026-04-06
**Status:** Design Complete — Ready for Implementation
**Prerequisite:** Phase A (V1 Trust Layer) is complete and verified working.

---

## SECTION 1 — Phase B Scope

### Goals

Phase B adds a **passive risk detection and soft enforcement layer** to SnatchIt. The purpose is to catch bad actors before they cause harm, without disrupting legitimate sellers or adding visible UI changes.

Specifically:

1. Track risk signals per seller (account age, listing velocity, dispute rate, proof reuse, etc.)
2. Auto-generate seller flags when thresholds are breached.
3. Provide admin dashboard queries to surface flagged sellers and high-risk activity.
4. Enable soft enforcement: warnings, listing blocks, and manual review queues — no permanent auto-bans.

### Intentionally Excluded from Phase B

- Public-facing badges, reputation scores, or trust indicators (Phase C).
- OCR or automated proof verification.
- Email parsing or external integrations.
- Buyer risk scoring (Phase B focuses on seller risk only).
- Automated permanent bans.
- Any changes to existing payout, refund, or dispute resolution logic.
- Push notification alerts to sellers about flags (manual admin contact only).

---

## SECTION 2 — Risk Signals

The following minimum useful risk signals will be tracked per seller. Each signal maps directly to a detection rule in Section 4.

| Signal | Source | Description |
|--------|--------|-------------|
| `account_age_days` | `profiles.created_at` | Days since account creation. New accounts with high-value listings are higher risk. |
| `active_listing_count` | `listings` WHERE `status='active'` | Total active listings for seller. Unusually high counts suggest fraud or scalping. |
| `same_event_listing_count` | `listings` WHERE `status='active'` grouped by `event_name + event_date` | Multiple active listings for the exact same event. Strong fraud signal. |
| `total_completed_transfers` | `transfers` WHERE `status IN ('buyer_confirmed','auto_released')` | Denominator for dispute rate. Minimum sample size required before flagging. |
| `total_disputes` | `transfers` WHERE `status='disputed'` OR `dispute_resolved_at IS NOT NULL` | Total disputes filed against seller. |
| `dispute_rate` | `total_disputes / total_completed_transfers` | Percentage of completed sales that resulted in disputes. |
| `dispute_loss_rate` | Count of `dispute_resolution='resolved_buyer_refunded'` / `total_disputes` | Percentage of disputes seller lost. |
| `rapid_send_count` | `transfers` WHERE `seller_sent_at - transfers.created_at < interval '5 minutes'` | Marking tickets as sent within 5 minutes of transfer creation. Possible pre-canned fraud. |
| `duplicate_proof_usage` | `listings` grouped by `proof_of_ownership_path` | Same proof image path used across multiple active listings. |
| `duplicate_evidence_usage` | `transfers` grouped by `transfer_evidence_path` | Same transfer evidence path used across multiple transfers. |
| `missing_stripe_connect` | `profiles.stripe_connect_id IS NULL` | Seller listing without payout setup. |
| `expired_transfer_count` | `transfers` WHERE `status='expired'` AND `seller_id = X` | Number of transfers that expired because seller didn't send. |

---

## SECTION 3 — Data Model

### 3.1 seller_flags Table

Stores individual risk flags raised against sellers. Each row is one flag event.

### 3.2 seller_risk_scores Table

Optional materialized risk summary per seller. Recomputed periodically or on-demand.

### 3.3 SQL Migration — `012_seller_risk.sql`

```sql
-- ============================================================
-- Migration 012: Phase B — Anti-Fraud & Seller Risk Controls
-- ============================================================

-- ------------------------------------------------------------
-- 1. seller_flags — individual risk flag events
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seller_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Who is flagged
  seller_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- What type of flag
  flag_type text NOT NULL CHECK (flag_type IN (
    'same_event_overload',
    'high_dispute_rate',
    'high_dispute_loss_rate',
    'duplicate_proof',
    'duplicate_evidence',
    'rapid_send',
    'new_account_high_value',
    'high_listing_velocity',
    'missing_payout_setup',
    'repeated_expiry'
  )),

  -- Severity: info, warning, critical
  severity text NOT NULL DEFAULT 'warning' CHECK (severity IN ('info', 'warning', 'critical')),

  -- Human-readable explanation
  details text,

  -- Optional reference to the listing/transfer that triggered it
  listing_id uuid REFERENCES public.listings(id) ON DELETE SET NULL,
  transfer_id uuid REFERENCES public.transfers(id) ON DELETE SET NULL,

  -- Admin resolution
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users(id),
  resolution text CHECK (resolution IN (
    'dismissed',          -- false positive
    'warned',             -- seller contacted / warned
    'listing_blocked',    -- specific listing removed
    'seller_suspended',   -- all listings paused (manual)
    'escalated'           -- needs further investigation
  )),
  resolution_notes text,

  -- Prevent exact duplicate flags within a time window
  -- (handled by application logic, not unique constraint,
  --  since the same flag_type can recur legitimately)
  CONSTRAINT seller_flags_severity_check CHECK (
    CASE
      WHEN severity = 'critical' THEN flag_type IN (
        'high_dispute_rate', 'high_dispute_loss_rate',
        'duplicate_proof', 'duplicate_evidence'
      )
      ELSE true
    END
  )
);

-- Indexes for common query patterns
CREATE INDEX idx_seller_flags_seller_id ON public.seller_flags(seller_id);
CREATE INDEX idx_seller_flags_flag_type ON public.seller_flags(flag_type);
CREATE INDEX idx_seller_flags_severity ON public.seller_flags(severity);
CREATE INDEX idx_seller_flags_unreviewed
  ON public.seller_flags(created_at)
  WHERE reviewed_at IS NULL;
CREATE INDEX idx_seller_flags_created_at ON public.seller_flags(created_at DESC);

-- RLS: Only service role can read/write (admin queries run via service role or SQL Editor)
ALTER TABLE public.seller_flags ENABLE ROW LEVEL SECURITY;

-- No client-facing policies — flags are admin-only
-- Service role bypasses RLS automatically

COMMENT ON TABLE public.seller_flags IS
  'Phase B: Individual risk flags raised against sellers. Admin-only visibility.';


-- ------------------------------------------------------------
-- 2. seller_risk_scores — materialized risk summary per seller
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seller_risk_scores (
  seller_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Raw counts
  account_age_days int NOT NULL DEFAULT 0,
  total_listings int NOT NULL DEFAULT 0,
  active_listings int NOT NULL DEFAULT 0,
  total_completed int NOT NULL DEFAULT 0,
  total_disputes int NOT NULL DEFAULT 0,
  total_dispute_losses int NOT NULL DEFAULT 0,
  total_expired int NOT NULL DEFAULT 0,
  rapid_send_count int NOT NULL DEFAULT 0,
  duplicate_proof_count int NOT NULL DEFAULT 0,
  duplicate_evidence_count int NOT NULL DEFAULT 0,

  -- Computed rates (stored as decimal 0.0 - 1.0)
  dispute_rate numeric(5,4) NOT NULL DEFAULT 0,
  dispute_loss_rate numeric(5,4) NOT NULL DEFAULT 0,
  expiry_rate numeric(5,4) NOT NULL DEFAULT 0,

  -- Composite risk tier: low, medium, high, critical
  risk_tier text NOT NULL DEFAULT 'low' CHECK (risk_tier IN ('low', 'medium', 'high', 'critical')),

  -- Active flag counts (denormalized for fast queries)
  open_flags_count int NOT NULL DEFAULT 0,
  critical_flags_count int NOT NULL DEFAULT 0,

  -- Enforcement state
  is_listing_blocked boolean NOT NULL DEFAULT false,
  listing_blocked_at timestamptz,
  listing_blocked_reason text
);

CREATE INDEX idx_seller_risk_scores_risk_tier ON public.seller_risk_scores(risk_tier);
CREATE INDEX idx_seller_risk_scores_blocked
  ON public.seller_risk_scores(seller_id)
  WHERE is_listing_blocked = true;

ALTER TABLE public.seller_risk_scores ENABLE ROW LEVEL SECURITY;
-- No client policies — admin-only

COMMENT ON TABLE public.seller_risk_scores IS
  'Phase B: Materialized risk summary per seller. Recomputed on-demand by admin queries.';


-- ------------------------------------------------------------
-- 3. Helper: refresh_seller_risk_score(p_seller_id)
-- Recomputes a single seller's risk score from source tables
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.refresh_seller_risk_score(p_seller_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_age int;
  v_total_listings int;
  v_active_listings int;
  v_total_completed int;
  v_total_disputes int;
  v_total_dispute_losses int;
  v_total_expired int;
  v_rapid_send int;
  v_dup_proof int;
  v_dup_evidence int;
  v_dispute_rate numeric(5,4);
  v_dispute_loss_rate numeric(5,4);
  v_expiry_rate numeric(5,4);
  v_risk_tier text;
  v_open_flags int;
  v_critical_flags int;
BEGIN
  -- Account age
  SELECT COALESCE(EXTRACT(DAY FROM now() - created_at)::int, 0)
    INTO v_account_age
    FROM auth.users WHERE id = p_seller_id;

  -- Listing counts
  SELECT COUNT(*) INTO v_total_listings
    FROM listings WHERE seller_id = p_seller_id;

  SELECT COUNT(*) INTO v_active_listings
    FROM listings WHERE seller_id = p_seller_id AND status = 'active';

  -- Transfer counts
  SELECT COUNT(*) INTO v_total_completed
    FROM transfers WHERE seller_id = p_seller_id
      AND status IN ('buyer_confirmed', 'auto_released');

  SELECT COUNT(*) INTO v_total_disputes
    FROM transfers WHERE seller_id = p_seller_id
      AND (status = 'disputed' OR dispute_resolved_at IS NOT NULL);

  SELECT COUNT(*) INTO v_total_dispute_losses
    FROM transfers WHERE seller_id = p_seller_id
      AND dispute_resolution = 'resolved_buyer_refunded';

  SELECT COUNT(*) INTO v_total_expired
    FROM transfers WHERE seller_id = p_seller_id
      AND status = 'expired';

  -- Rapid send (sent within 5 minutes of transfer creation)
  SELECT COUNT(*) INTO v_rapid_send
    FROM transfers WHERE seller_id = p_seller_id
      AND seller_sent_at IS NOT NULL
      AND seller_sent_at - created_at < interval '5 minutes';

  -- Duplicate proof of ownership (same path used on multiple active listings)
  SELECT COALESCE(SUM(cnt - 1), 0)::int INTO v_dup_proof
    FROM (
      SELECT proof_of_ownership_path, COUNT(*) as cnt
      FROM listings
      WHERE seller_id = p_seller_id
        AND status = 'active'
        AND proof_of_ownership_path IS NOT NULL
      GROUP BY proof_of_ownership_path
      HAVING COUNT(*) > 1
    ) sub;

  -- Duplicate transfer evidence (same path on multiple transfers)
  SELECT COALESCE(SUM(cnt - 1), 0)::int INTO v_dup_evidence
    FROM (
      SELECT transfer_evidence_path, COUNT(*) as cnt
      FROM transfers
      WHERE seller_id = p_seller_id
        AND transfer_evidence_path IS NOT NULL
      GROUP BY transfer_evidence_path
      HAVING COUNT(*) > 1
    ) sub;

  -- Compute rates
  IF v_total_completed >= 3 THEN
    v_dispute_rate := ROUND(v_total_disputes::numeric / v_total_completed, 4);
  ELSE
    v_dispute_rate := 0;
  END IF;

  IF v_total_disputes >= 2 THEN
    v_dispute_loss_rate := ROUND(v_total_dispute_losses::numeric / v_total_disputes, 4);
  ELSE
    v_dispute_loss_rate := 0;
  END IF;

  IF v_total_completed + v_total_expired >= 3 THEN
    v_expiry_rate := ROUND(v_total_expired::numeric / (v_total_completed + v_total_expired), 4);
  ELSE
    v_expiry_rate := 0;
  END IF;

  -- Flag counts
  SELECT COUNT(*) INTO v_open_flags
    FROM seller_flags WHERE seller_id = p_seller_id AND reviewed_at IS NULL;

  SELECT COUNT(*) INTO v_critical_flags
    FROM seller_flags WHERE seller_id = p_seller_id
      AND reviewed_at IS NULL AND severity = 'critical';

  -- Determine risk tier
  IF v_critical_flags > 0 OR v_dispute_rate > 0.30 OR v_dup_proof > 0 THEN
    v_risk_tier := 'critical';
  ELSIF v_open_flags >= 3 OR v_dispute_rate > 0.20 OR (v_account_age < 3 AND v_active_listings > 5) THEN
    v_risk_tier := 'high';
  ELSIF v_open_flags >= 1 OR v_dispute_rate > 0.10 OR v_rapid_send > 2 THEN
    v_risk_tier := 'medium';
  ELSE
    v_risk_tier := 'low';
  END IF;

  -- Upsert
  INSERT INTO seller_risk_scores (
    seller_id, updated_at,
    account_age_days, total_listings, active_listings,
    total_completed, total_disputes, total_dispute_losses, total_expired,
    rapid_send_count, duplicate_proof_count, duplicate_evidence_count,
    dispute_rate, dispute_loss_rate, expiry_rate,
    risk_tier, open_flags_count, critical_flags_count
  ) VALUES (
    p_seller_id, now(),
    v_account_age, v_total_listings, v_active_listings,
    v_total_completed, v_total_disputes, v_total_dispute_losses, v_total_expired,
    v_rapid_send, v_dup_proof, v_dup_evidence,
    v_dispute_rate, v_dispute_loss_rate, v_expiry_rate,
    v_risk_tier, v_open_flags, v_critical_flags
  )
  ON CONFLICT (seller_id) DO UPDATE SET
    updated_at = now(),
    account_age_days = EXCLUDED.account_age_days,
    total_listings = EXCLUDED.total_listings,
    active_listings = EXCLUDED.active_listings,
    total_completed = EXCLUDED.total_completed,
    total_disputes = EXCLUDED.total_disputes,
    total_dispute_losses = EXCLUDED.total_dispute_losses,
    total_expired = EXCLUDED.total_expired,
    rapid_send_count = EXCLUDED.rapid_send_count,
    duplicate_proof_count = EXCLUDED.duplicate_proof_count,
    duplicate_evidence_count = EXCLUDED.duplicate_evidence_count,
    dispute_rate = EXCLUDED.dispute_rate,
    dispute_loss_rate = EXCLUDED.dispute_loss_rate,
    expiry_rate = EXCLUDED.expiry_rate,
    risk_tier = EXCLUDED.risk_tier,
    open_flags_count = EXCLUDED.open_flags_count,
    critical_flags_count = EXCLUDED.critical_flags_count;
END;
$$;

COMMENT ON FUNCTION public.refresh_seller_risk_score IS
  'Phase B: Recompute risk score for a single seller from source tables.';


-- ------------------------------------------------------------
-- 4. Helper: refresh_all_seller_risk_scores()
-- Batch refresh for all sellers who have listings or transfers
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.refresh_all_seller_risk_scores()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seller_id uuid;
  v_count int := 0;
BEGIN
  FOR v_seller_id IN
    SELECT DISTINCT seller_id FROM listings
    UNION
    SELECT DISTINCT seller_id FROM transfers WHERE seller_id IS NOT NULL
  LOOP
    PERFORM refresh_seller_risk_score(v_seller_id);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
```

### 3.4 Schema Notes

- **seller_flags** is append-only from detection queries; admin marks reviewed via `reviewed_at` / `resolution`.
- **seller_risk_scores** is a denormalized cache, fully recomputable from source tables.
- No foreign keys to `profiles` (uses `auth.users(id)` directly) — consistent with existing schema.
- All tables are RLS-enabled with zero client policies — admin-only via service role or SQL Editor.
- The `refresh_seller_risk_score()` function reads from `auth.users` for account age, so it needs `SECURITY DEFINER`.

---

## SECTION 4 — Detection Rules

Each rule defines when a flag should be created. Detection queries are run manually (admin) or via a scheduled edge function.

### Rule 1: Same-Event Overload

**Condition:** Seller has > 3 active listings for the same `event_name + event_date` combination.

```sql
-- Detect same-event overload
SELECT seller_id, event_name, event_date, COUNT(*) as listing_count
FROM listings
WHERE status = 'active'
GROUP BY seller_id, event_name, event_date
HAVING COUNT(*) > 3;
```

**Flag:** `same_event_overload` / severity `warning` (> 3), `critical` if > 6.

---

### Rule 2: High Dispute Rate

**Condition:** Seller dispute rate > 20% with minimum 3 completed transfers.

```sql
-- Detect high dispute rate
WITH seller_stats AS (
  SELECT
    seller_id,
    COUNT(*) FILTER (WHERE status IN ('buyer_confirmed','auto_released')) as completed,
    COUNT(*) FILTER (WHERE status = 'disputed' OR dispute_resolved_at IS NOT NULL) as disputes
  FROM transfers
  WHERE seller_id IS NOT NULL
  GROUP BY seller_id
)
SELECT seller_id, completed, disputes,
  ROUND(disputes::numeric / completed, 2) as dispute_rate
FROM seller_stats
WHERE completed >= 3 AND disputes::numeric / completed > 0.20;
```

**Flag:** `high_dispute_rate` / severity `warning` (> 20%), `critical` (> 40%).

---

### Rule 3: High Dispute Loss Rate

**Condition:** Seller lost > 50% of disputes with minimum 2 disputes.

```sql
-- Detect high dispute loss rate
WITH seller_disputes AS (
  SELECT
    seller_id,
    COUNT(*) FILTER (WHERE status = 'disputed' OR dispute_resolved_at IS NOT NULL) as total_disputes,
    COUNT(*) FILTER (WHERE dispute_resolution = 'resolved_buyer_refunded') as losses
  FROM transfers
  WHERE seller_id IS NOT NULL
  GROUP BY seller_id
)
SELECT seller_id, total_disputes, losses,
  ROUND(losses::numeric / total_disputes, 2) as loss_rate
FROM seller_disputes
WHERE total_disputes >= 2 AND losses::numeric / total_disputes > 0.50;
```

**Flag:** `high_dispute_loss_rate` / severity `critical`.

---

### Rule 4: Duplicate Proof of Ownership

**Condition:** Same `proof_of_ownership_path` used across multiple active listings by same seller.

```sql
-- Detect duplicate proof usage
SELECT seller_id, proof_of_ownership_path, COUNT(*) as usage_count,
  array_agg(id) as listing_ids
FROM listings
WHERE status = 'active'
  AND proof_of_ownership_path IS NOT NULL
GROUP BY seller_id, proof_of_ownership_path
HAVING COUNT(*) > 1;
```

**Flag:** `duplicate_proof` / severity `critical`. This is a strong fraud signal.

---

### Rule 5: Duplicate Transfer Evidence

**Condition:** Same `transfer_evidence_path` used across multiple transfers by same seller.

```sql
-- Detect duplicate transfer evidence
SELECT seller_id, transfer_evidence_path, COUNT(*) as usage_count,
  array_agg(id) as transfer_ids
FROM transfers
WHERE transfer_evidence_path IS NOT NULL
GROUP BY seller_id, transfer_evidence_path
HAVING COUNT(*) > 1;
```

**Flag:** `duplicate_evidence` / severity `critical`.

---

### Rule 6: Rapid Mark-as-Sent

**Condition:** Seller marked > 2 transfers as sent within 5 minutes of creation.

```sql
-- Detect rapid send behavior
SELECT seller_id, COUNT(*) as rapid_count
FROM transfers
WHERE seller_sent_at IS NOT NULL
  AND seller_sent_at - created_at < interval '5 minutes'
GROUP BY seller_id
HAVING COUNT(*) > 2;
```

**Flag:** `rapid_send` / severity `warning`. May be legitimate for experienced sellers, but worth monitoring.

---

### Rule 7: New Account + High Value

**Condition:** Account age < 7 days AND has active listing with `starting_bid > 200` OR `buy_now_price > 200`.

```sql
-- Detect new accounts with high-value listings
SELECT l.seller_id, p.created_at as account_created,
  EXTRACT(DAY FROM now() - p.created_at)::int as age_days,
  l.id as listing_id, l.starting_bid, l.buy_now_price
FROM listings l
JOIN auth.users p ON p.id = l.seller_id
WHERE l.status = 'active'
  AND EXTRACT(DAY FROM now() - p.created_at) < 7
  AND (l.starting_bid > 200 OR COALESCE(l.buy_now_price, 0) > 200);
```

**Flag:** `new_account_high_value` / severity `warning`.

---

### Rule 8: High Listing Velocity

**Condition:** Seller created > 5 listings in past 24 hours.

```sql
-- Detect high listing velocity
SELECT seller_id, COUNT(*) as listings_24h
FROM listings
WHERE created_at > now() - interval '24 hours'
GROUP BY seller_id
HAVING COUNT(*) > 5;
```

**Flag:** `high_listing_velocity` / severity `warning` (> 5), `critical` (> 10).

---

### Rule 9: Missing Payout Setup

**Condition:** Seller has active listings but no `stripe_connect_id`.

```sql
-- Detect sellers listing without payout setup
SELECT l.seller_id, COUNT(*) as active_listings
FROM listings l
JOIN profiles p ON p.id = l.seller_id
WHERE l.status = 'active'
  AND p.stripe_connect_id IS NULL
GROUP BY l.seller_id;
```

**Flag:** `missing_payout_setup` / severity `info`.

---

### Rule 10: Repeated Transfer Expiry

**Condition:** Seller has > 2 expired transfers (failed to send tickets on time).

```sql
-- Detect repeated expiry
SELECT seller_id, COUNT(*) as expired_count
FROM transfers
WHERE status = 'expired'
GROUP BY seller_id
HAVING COUNT(*) > 2;
```

**Flag:** `repeated_expiry` / severity `warning` (> 2), `critical` (> 4).

---

### Threshold Summary Table

| Rule | Flag Type | Trigger | Warning | Critical |
|------|-----------|---------|---------|----------|
| 1 | same_event_overload | Same event+date listings | > 3 | > 6 |
| 2 | high_dispute_rate | Dispute % (min 3 completed) | > 20% | > 40% |
| 3 | high_dispute_loss_rate | Dispute loss % (min 2 disputes) | — | > 50% |
| 4 | duplicate_proof | Same proof path on active listings | — | Any |
| 5 | duplicate_evidence | Same evidence path on transfers | — | Any |
| 6 | rapid_send | Sent < 5min after creation | > 2 | — |
| 7 | new_account_high_value | Age < 7d + listing > $200 | Any | — |
| 8 | high_listing_velocity | Listings in 24h | > 5 | > 10 |
| 9 | missing_payout_setup | Active listings, no Stripe Connect | info | — |
| 10 | repeated_expiry | Expired transfers | > 2 | > 4 |

---

## SECTION 5 — Enforcement Plan

Phase B uses **soft enforcement only**. No automated permanent bans.

### 5.1 Enforcement Actions (Admin-Initiated)

| Action | Who Decides | Effect | Reversible |
|--------|-------------|--------|------------|
| **Dismiss flag** | Admin | Mark flag as false positive | N/A |
| **Warn seller** | Admin | Record warning, contact seller externally | N/A |
| **Block specific listing** | Admin | Set listing `status='cancelled'` (new status or manual SQL update) | Yes — admin re-activates |
| **Temporary listing block** | Admin | Set `seller_risk_scores.is_listing_blocked = true` | Yes — admin unsets |
| **Escalate** | Admin | Flag marked for deeper investigation | N/A |

### 5.2 Soft Enforcement Flow

```
Detection query finds violation
  → seller_flags row created (severity: info/warning/critical)
  → refresh_seller_risk_score(seller_id) updates risk tier
  → Admin reviews flagged sellers dashboard
  → Admin decides: dismiss / warn / block listing / suspend / escalate
  → Resolution recorded in seller_flags.resolution
```

### 5.3 Optional: Pre-Listing Check (Future Hook)

When ready, a pre-listing check can be added:

```sql
-- Check if seller is blocked before allowing new listing
-- Called from listing creation RPC or edge function
SELECT is_listing_blocked
FROM seller_risk_scores
WHERE seller_id = $1;
```

This is **not required for initial Phase B** but is the natural enforcement hook point. The app would check this before `INSERT INTO listings` and return an error if blocked.

### 5.4 What We Explicitly Do NOT Do in V1

- No automated permanent bans.
- No automated listing removal (admin must review first).
- No buyer-facing warnings ("this seller is risky").
- No automated payout holds based on risk score.
- No appeal flow (handled manually via admin contact).

---

## SECTION 6 — Ops / Dashboard Queries

These queries are designed for the Supabase SQL Editor. Run them as needed or on a daily cadence.

### Q1: All Unreviewed Flags (Priority Dashboard)

```sql
-- Q1: Unreviewed flags, newest first, with seller info
SELECT
  sf.id as flag_id,
  sf.created_at,
  sf.severity,
  sf.flag_type,
  sf.details,
  sf.seller_id,
  p.display_name as seller_name,
  p.phone_number as seller_phone,
  sf.listing_id,
  sf.transfer_id
FROM seller_flags sf
LEFT JOIN profiles p ON p.id = sf.seller_id
WHERE sf.reviewed_at IS NULL
ORDER BY
  CASE sf.severity
    WHEN 'critical' THEN 1
    WHEN 'warning' THEN 2
    WHEN 'info' THEN 3
  END,
  sf.created_at DESC;
```

### Q2: Repeat Dispute Losers

```sql
-- Q2: Sellers who lost multiple disputes
SELECT
  t.seller_id,
  p.display_name,
  COUNT(*) FILTER (WHERE t.dispute_resolution = 'resolved_buyer_refunded') as disputes_lost,
  COUNT(*) FILTER (WHERE t.status = 'disputed' OR t.dispute_resolved_at IS NOT NULL) as total_disputes,
  COUNT(*) FILTER (WHERE t.status IN ('buyer_confirmed','auto_released')) as completed
FROM transfers t
JOIN profiles p ON p.id = t.seller_id
WHERE t.seller_id IS NOT NULL
GROUP BY t.seller_id, p.display_name
HAVING COUNT(*) FILTER (WHERE t.dispute_resolution = 'resolved_buyer_refunded') >= 2
ORDER BY disputes_lost DESC;
```

### Q3: Duplicate Proof Usage

```sql
-- Q3: Active listings sharing the same proof image
SELECT
  seller_id,
  p.display_name,
  proof_of_ownership_path,
  COUNT(*) as listing_count,
  array_agg(l.id) as listing_ids,
  array_agg(l.event_name) as events
FROM listings l
JOIN profiles p ON p.id = l.seller_id
WHERE l.status = 'active'
  AND l.proof_of_ownership_path IS NOT NULL
GROUP BY l.seller_id, p.display_name, l.proof_of_ownership_path
HAVING COUNT(*) > 1
ORDER BY listing_count DESC;
```

### Q4: Same-Event Overload

```sql
-- Q4: Sellers with many active listings for the same event
SELECT
  l.seller_id,
  p.display_name,
  l.event_name,
  l.event_date,
  COUNT(*) as listing_count,
  array_agg(l.id) as listing_ids
FROM listings l
JOIN profiles p ON p.id = l.seller_id
WHERE l.status = 'active'
GROUP BY l.seller_id, p.display_name, l.event_name, l.event_date
HAVING COUNT(*) > 3
ORDER BY listing_count DESC;
```

### Q5: High-Risk New Sellers

```sql
-- Q5: Accounts < 7 days old with active high-value listings
SELECT
  l.seller_id,
  p.display_name,
  u.created_at as account_created,
  EXTRACT(DAY FROM now() - u.created_at)::int as age_days,
  COUNT(*) as active_listings,
  MAX(GREATEST(l.starting_bid, COALESCE(l.buy_now_price, 0))) as max_price
FROM listings l
JOIN profiles p ON p.id = l.seller_id
JOIN auth.users u ON u.id = l.seller_id
WHERE l.status = 'active'
  AND u.created_at > now() - interval '7 days'
GROUP BY l.seller_id, p.display_name, u.created_at
ORDER BY age_days ASC, max_price DESC;
```

### Q6: Sellers with Payout Issues

```sql
-- Q6: Sellers with active listings but no Stripe Connect setup
SELECT
  l.seller_id,
  p.display_name,
  p.stripe_connect_id,
  COUNT(*) as active_listings,
  SUM(CASE WHEN l.buy_now_price IS NOT NULL THEN l.buy_now_price ELSE l.starting_bid END) as total_value
FROM listings l
JOIN profiles p ON p.id = l.seller_id
WHERE l.status = 'active'
  AND (p.stripe_connect_id IS NULL OR p.stripe_connect_id = '')
GROUP BY l.seller_id, p.display_name, p.stripe_connect_id
ORDER BY total_value DESC;
```

### Q7: Risk Score Summary (after scores are computed)

```sql
-- Q7: All sellers by risk tier
SELECT
  srs.risk_tier,
  srs.seller_id,
  p.display_name,
  srs.active_listings,
  srs.total_completed,
  srs.dispute_rate,
  srs.dispute_loss_rate,
  srs.open_flags_count,
  srs.critical_flags_count,
  srs.is_listing_blocked,
  srs.updated_at
FROM seller_risk_scores srs
JOIN profiles p ON p.id = srs.seller_id
ORDER BY
  CASE srs.risk_tier
    WHEN 'critical' THEN 1
    WHEN 'high' THEN 2
    WHEN 'medium' THEN 3
    WHEN 'low' THEN 4
  END,
  srs.open_flags_count DESC;
```

### Q8: Admin Flag Resolution

```sql
-- Mark a flag as reviewed
UPDATE seller_flags
SET
  reviewed_at = now(),
  reviewed_by = '<admin_user_id>',
  resolution = 'warned',  -- or 'dismissed', 'listing_blocked', 'seller_suspended', 'escalated'
  resolution_notes = 'Contacted seller via phone. Warning issued.'
WHERE id = '<flag_id>';

-- After resolution, refresh the seller's risk score
SELECT refresh_seller_risk_score('<seller_id>');
```

### Q9: Full Detection Sweep (Run All Rules)

```sql
-- Run this to detect and insert new flags for all rules
-- Wrap in a DO block or create as a function

-- Rule 1: Same-event overload
INSERT INTO seller_flags (seller_id, flag_type, severity, details, listing_id)
SELECT
  seller_id,
  'same_event_overload',
  CASE WHEN COUNT(*) > 6 THEN 'critical' ELSE 'warning' END,
  'Seller has ' || COUNT(*) || ' active listings for ' || event_name || ' on ' || event_date,
  (array_agg(id))[1]
FROM listings
WHERE status = 'active'
GROUP BY seller_id, event_name, event_date
HAVING COUNT(*) > 3
  -- Skip if already flagged for this in past 24h
  AND NOT EXISTS (
    SELECT 1 FROM seller_flags sf
    WHERE sf.seller_id = listings.seller_id
      AND sf.flag_type = 'same_event_overload'
      AND sf.created_at > now() - interval '24 hours'
  );

-- Rule 4: Duplicate proof
INSERT INTO seller_flags (seller_id, flag_type, severity, details, listing_id)
SELECT
  seller_id,
  'duplicate_proof',
  'critical',
  'Same proof image used on ' || COUNT(*) || ' active listings: ' || proof_of_ownership_path,
  (array_agg(id))[1]
FROM listings
WHERE status = 'active' AND proof_of_ownership_path IS NOT NULL
GROUP BY seller_id, proof_of_ownership_path
HAVING COUNT(*) > 1
  AND NOT EXISTS (
    SELECT 1 FROM seller_flags sf
    WHERE sf.seller_id = listings.seller_id
      AND sf.flag_type = 'duplicate_proof'
      AND sf.created_at > now() - interval '24 hours'
  );

-- (Add remaining rules following the same pattern)
-- After inserting flags, refresh all scores:
SELECT refresh_all_seller_risk_scores();
```

---

## SECTION 7 — Smallest Implementation Order

### Step 1: Migration (Day 1)
Run `012_seller_risk.sql` migration.
- Creates `seller_flags` and `seller_risk_scores` tables
- Creates `refresh_seller_risk_score()` and `refresh_all_seller_risk_scores()` functions
- Creates all indexes
- Zero impact on existing app — purely additive

**Verification:** `SELECT COUNT(*) FROM seller_flags;` returns 0. `SELECT refresh_all_seller_risk_scores();` runs without error.

### Step 2: Detection Queries (Day 1-2)
Copy detection queries from Section 4 into a saved SQL file (`PHASE_B_DETECTION_QUERIES.sql`).
- Run each query manually to validate against current data
- Verify no false positives on existing legitimate sellers
- Tune thresholds if needed based on actual data

**Verification:** Each query returns expected results. No crashes or permission errors.

### Step 3: Dashboard Queries (Day 2)
Copy dashboard queries from Section 6 into admin SQL pack.
- Add Q1-Q9 to existing `DAY5_ADMIN_SQL_PACK.sql`
- Run Q7 (risk score summary) to verify scores computed correctly
- Run Q1 (unreviewed flags) to verify flag display works

**Verification:** All queries return results. Risk tiers make sense for known sellers.

### Step 4: Optional — Admin Surfacing (Day 3+)
If building an admin panel (not required for V1):
- Simple list view of unreviewed flags
- One-click resolution buttons
- Seller detail view with risk score

For now, Supabase SQL Editor is sufficient.

### Step 5: Enforcement Hooks (Day 3+, Optional for V1)
Add pre-listing check to listing creation:
- Query `seller_risk_scores.is_listing_blocked` before allowing new listing
- Return user-friendly error if blocked
- This is the only app-code change needed

**Implementation:** Add to listing creation edge function or RPC:
```sql
-- Add to listing creation logic
IF EXISTS (
  SELECT 1 FROM seller_risk_scores
  WHERE seller_id = auth.uid() AND is_listing_blocked = true
) THEN
  RAISE EXCEPTION 'Your account is temporarily restricted from creating new listings. Please contact support.';
END IF;
```

---

## SECTION 8 — Exact Implementation Prompt

Copy-paste this prompt to Claude Code to implement Phase B:

---

```
You are implementing Phase B of SnatchIt's anti-fraud layer. Phase A is complete and working. Do NOT modify any existing tables, RPCs, or app logic — all changes are additive.

STEP 1: Create migration file
Create /supabase/migrations/012_seller_risk.sql with the exact contents from the PHASE_B_ANTI_FRAUD_DESIGN.md Section 3.3 migration SQL. Do not modify the SQL — use it exactly as written.

STEP 2: Create detection queries file
Create /PHASE_B_DETECTION_QUERIES.sql containing all 10 detection rule queries from Section 4 of PHASE_B_ANTI_FRAUD_DESIGN.md. Each query should be clearly labeled with a comment header. Include the full sweep query (Q9 from Section 6) at the end.

STEP 3: Update admin SQL pack
Append to /DAY5_ADMIN_SQL_PACK.sql a new section header "-- ============ PHASE B: RISK & FRAUD QUERIES ============" followed by queries Q1-Q8 from Section 6 of PHASE_B_ANTI_FRAUD_DESIGN.md.

STEP 4: Update TypeScript types
Add to /src/types/index.ts:
- SellerFlag type matching the seller_flags table columns
- SellerRiskScore type matching the seller_risk_scores table columns
- FlagType union type for the flag_type CHECK constraint values
- FlagSeverity union type: 'info' | 'warning' | 'critical'
- FlagResolution union type for the resolution CHECK constraint values
- RiskTier union type: 'low' | 'medium' | 'high' | 'critical'

STEP 5: Verify
- Read the migration file back and confirm it matches the design doc
- Read the types file and confirm new types are syntactically correct
- Do NOT run the migration (that's done manually in Supabase)

CONSTRAINTS:
- Do NOT touch existing migration files
- Do NOT modify existing RPCs, tables, or RLS policies
- Do NOT add any client-facing UI or components
- Do NOT modify any screen files in /app/
- All new tables must have RLS enabled with no client policies
- Use gen_random_uuid() for primary keys (consistent with existing schema)
```

---

STEP COMPLETE — WAITING FOR NEXT RUN
