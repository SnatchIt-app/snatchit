# Phase C — Manual Review & Controlled Flag Operations

**Date:** 2026-04-06
**Status:** Design Complete — Ready for Implementation
**Prerequisite:** Phase B V1 is complete and verified (012_seller_risk.sql applied, detection queries functional, scoring functions tested).

---

## SECTION 1 — Phase C Scope

### What Phase C Includes

Phase C bridges the gap between passive detection (Phase B) and future automated enforcement. It provides a disciplined, manual admin workflow for acting on detection query results.

1. A complete SQL operations pack for manual flag lifecycle management (insert, inspect, resolve, refresh).
2. Formal severity classification rules tied to Phase B detection signals.
3. Formal resolution rules defining when each resolution type applies.
4. A documented step-by-step admin review workflow.
5. An audit trail via existing `reviewed_at`, `reviewed_by`, `resolution`, and `resolution_notes` columns.

### What Phase C Excludes

- No automatic flag insertion (flags are created manually by admin after reviewing detection query output).
- No enforcement hooks in application code (no middleware, no RLS enforcement, no API changes).
- No admin UI or dashboard (all operations run via Supabase SQL Editor).
- No background jobs, cron tasks, or scheduled functions.
- No buyer-facing or seller-facing changes of any kind.
- No changes to existing transfer, payout, dispute, or listing logic.
- No new database tables or schema migrations (Phase B tables are sufficient).
- No email or notification systems.

### Safety Principles

- Everything is additive: no existing behavior changes.
- Every flag insertion is a deliberate manual act by a named admin.
- Every resolution requires a human decision and written notes.
- Score refreshes are explicit, never triggered by application events.
- All operations are reversible (flags can be dismissed, scores re-refreshed).

---

## SECTION 2 — Admin Review Workflow

### Prerequisites

- Admin has access to Supabase SQL Editor with write permissions.
- Phase B migration `012_seller_risk.sql` has been applied.
- Detection queries from `PHASE_B_DETECTION_QUERIES.sql` are available.

### Step-by-Step Workflow

**Step 1 — Run Detection Sweep**

Run all 10 detection queries from `PHASE_B_DETECTION_QUERIES.sql` in the SQL Editor. Copy results to a working document or spreadsheet. Note which sellers appear in multiple rules.

**Step 2 — Deduplicate Against Existing Flags**

For each seller surfaced by the detection sweep, check whether an open (unreviewed) flag already exists for the same `flag_type`. Use the "Fetch Seller Open Flags" query from the operations pack. If a matching open flag already exists, skip — do not create a duplicate.

**Step 3 — Inspect Seller Context**

For each seller who needs a new flag, run the "Seller Context Inspection" query from the operations pack. This provides a single-row snapshot of account age, listing counts, transfer history, dispute rates, current risk tier, and existing flags. Use this to confirm the detection signal is genuine and to determine severity.

**Step 4 — Determine Severity**

Apply the severity rules in Section 4. The detection query output includes a `suggested_severity` column for most rules. The admin may override the suggestion based on context (e.g., a warning-level duplicate proof where the seller clearly has legitimate reasons).

**Step 5 — Insert Flag**

Use the "Manual Flag Insert" template from the operations pack. Fill in `seller_id`, `flag_type`, `severity`, `details` (human-readable explanation of why this flag was raised), and optionally `listing_id` or `transfer_id`.

**Step 6 — Refresh Seller Score**

Immediately after inserting the flag, run `SELECT refresh_seller_risk_score('<seller_uuid>')` to update the seller's risk tier. Verify the new `risk_tier` and `open_flags_count` look correct.

**Step 7 — Decide on Resolution (if immediate action warranted)**

For critical-severity flags or sellers at critical risk tier, the admin may resolve the flag immediately with an enforcement resolution (`listing_blocked`, `seller_suspended`, `escalated`). For warning/info flags, the flag remains open for monitoring. Apply the resolution rules in Section 5.

**Step 8 — Resolve Flag (when ready)**

Use the "Resolve Flag" template from the operations pack. Fill in the flag `id`, `resolution` type, `resolution_notes` (mandatory — explain the decision), and `reviewed_by` (the admin's user UUID).

**Step 9 — Post-Resolution Score Refresh**

After resolving, refresh the seller's score again. The open/critical flag counts will decrease, potentially lowering the risk tier.

**Step 10 — Record-Keeping**

The `seller_flags` table serves as the permanent audit log. No external record-keeping is required. The `reviewed_by` field links to the admin who made the decision. The `resolution_notes` field captures the rationale.

---

## SECTION 3 — SQL Operations Pack

The following queries form the complete operational toolkit for Phase C. All are designed to be run manually in the Supabase SQL Editor.

### 3.1 Manual Flag Insert Template

```sql
-- MANUAL FLAG INSERT
-- Fill in all <placeholder> values before running.
-- details field is REQUIRED — explain what triggered this flag.
INSERT INTO seller_flags (
  seller_id,
  flag_type,
  severity,
  details,
  listing_id,
  transfer_id
) VALUES (
  '<seller_uuid>',
  '<flag_type>',           -- one of the 10 flag_type values
  '<severity>',            -- 'info', 'warning', or 'critical'
  '<human readable explanation of why this flag was raised>',
  NULL,                    -- set to listing UUID if flag is listing-specific
  NULL                     -- set to transfer UUID if flag is transfer-specific
);
```

### 3.2 Seller Context Inspection

```sql
-- SELLER CONTEXT INSPECTION
-- Provides a full risk snapshot for one seller.
-- Run this BEFORE creating a flag to understand the seller's situation.
SELECT
  u.id as seller_id,
  p.display_name,
  u.created_at as account_created,
  EXTRACT(DAY FROM now() - u.created_at)::int as account_age_days,
  (SELECT COUNT(*) FROM listings WHERE seller_id = u.id) as total_listings,
  (SELECT COUNT(*) FROM listings WHERE seller_id = u.id AND status = 'active') as active_listings,
  (SELECT COUNT(*) FROM transfers WHERE seller_id = u.id AND status IN ('buyer_confirmed','auto_released')) as completed_transfers,
  (SELECT COUNT(*) FROM transfers WHERE seller_id = u.id AND (status = 'disputed' OR dispute_resolved_at IS NOT NULL)) as total_disputes,
  (SELECT COUNT(*) FROM transfers WHERE seller_id = u.id AND dispute_resolution = 'resolved_buyer_refunded') as dispute_losses,
  (SELECT COUNT(*) FROM transfers WHERE seller_id = u.id AND status = 'expired') as expired_transfers,
  p.stripe_connect_id,
  rs.risk_tier,
  rs.open_flags_count,
  rs.critical_flags_count,
  rs.dispute_rate,
  rs.dispute_loss_rate,
  rs.updated_at as score_last_updated
FROM auth.users u
JOIN profiles p ON p.id = u.id
LEFT JOIN seller_risk_scores rs ON rs.seller_id = u.id
WHERE u.id = '<seller_uuid>';
```

### 3.3 Fetch Seller Open Flags

```sql
-- FETCH ALL OPEN (UNREVIEWED) FLAGS FOR A SELLER
SELECT
  id,
  created_at,
  flag_type,
  severity,
  details,
  listing_id,
  transfer_id
FROM seller_flags
WHERE seller_id = '<seller_uuid>'
  AND reviewed_at IS NULL
ORDER BY
  CASE severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 WHEN 'info' THEN 3 END,
  created_at DESC;
```

### 3.4 Fetch Seller Risk Summary

```sql
-- COMPLETE RISK SUMMARY: score + all flags (open and resolved)
SELECT
  rs.*,
  (SELECT COUNT(*) FROM seller_flags WHERE seller_id = rs.seller_id AND reviewed_at IS NULL) as current_open_flags,
  (SELECT COUNT(*) FROM seller_flags WHERE seller_id = rs.seller_id AND reviewed_at IS NOT NULL) as resolved_flags,
  (SELECT COUNT(*) FROM seller_flags WHERE seller_id = rs.seller_id AND severity = 'critical' AND reviewed_at IS NULL) as current_critical_flags
FROM seller_risk_scores rs
WHERE rs.seller_id = '<seller_uuid>';
```

### 3.5 Resolve Flag Template

```sql
-- RESOLVE A FLAG
-- resolution_notes is MANDATORY. Explain your decision.
UPDATE seller_flags
SET
  reviewed_at = now(),
  reviewed_by = '<admin_user_uuid>',
  resolution = '<resolution>',       -- dismissed | warned | listing_blocked | seller_suspended | escalated
  resolution_notes = '<explain why this resolution was chosen>'
WHERE id = '<flag_uuid>'
  AND reviewed_at IS NULL;           -- safety: only resolve unreviewed flags
```

### 3.6 Refresh One Seller Score

```sql
-- REFRESH RISK SCORE FOR ONE SELLER
-- Run after inserting or resolving flags.
SELECT refresh_seller_risk_score('<seller_uuid>');

-- Verify the result:
SELECT seller_id, risk_tier, open_flags_count, critical_flags_count, updated_at
FROM seller_risk_scores
WHERE seller_id = '<seller_uuid>';
```

### 3.7 Refresh All Scores (Batch)

```sql
-- REFRESH ALL SELLER RISK SCORES
-- Use during periodic review sweeps. Returns count of sellers processed.
SELECT refresh_all_seller_risk_scores();
```

### 3.8 Dashboard View — All Open Flags Across All Sellers

```sql
-- ADMIN DASHBOARD: All open flags, ordered by severity then age
SELECT
  sf.id as flag_id,
  sf.created_at,
  sf.seller_id,
  p.display_name as seller_name,
  sf.flag_type,
  sf.severity,
  sf.details,
  rs.risk_tier as current_risk_tier,
  rs.open_flags_count,
  sf.listing_id,
  sf.transfer_id
FROM seller_flags sf
JOIN profiles p ON p.id = sf.seller_id
LEFT JOIN seller_risk_scores rs ON rs.seller_id = sf.seller_id
WHERE sf.reviewed_at IS NULL
ORDER BY
  CASE sf.severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 WHEN 'info' THEN 3 END,
  sf.created_at ASC;
```

### 3.9 Recently Resolved Flags (Audit Trail)

```sql
-- AUDIT: Recently resolved flags (last 30 days)
SELECT
  sf.id as flag_id,
  sf.seller_id,
  p.display_name as seller_name,
  sf.flag_type,
  sf.severity,
  sf.resolution,
  sf.resolution_notes,
  sf.reviewed_at,
  sf.reviewed_by,
  admin_p.display_name as reviewed_by_name
FROM seller_flags sf
JOIN profiles p ON p.id = sf.seller_id
LEFT JOIN profiles admin_p ON admin_p.id = sf.reviewed_by
WHERE sf.reviewed_at IS NOT NULL
  AND sf.reviewed_at > now() - interval '30 days'
ORDER BY sf.reviewed_at DESC;
```

---

## SECTION 4 — Severity Rules

Severity is assigned when a flag is manually created. The detection queries suggest a severity, but the admin makes the final call based on context.

### Important Policy Notes

1. **high_dispute_rate can NEVER be critical.** Only `high_dispute_loss_rate` drives critical classification for dispute-related signals. A high dispute rate alone (even > 40%) means buyers are complaining, but the seller may be winning those disputes. Only confirmed losses to buyers justify critical.
2. **rapid_send is informational only.** It does not contribute to risk tier calculations. The only exception: if `account_age_days < 3` AND `rapid_send_count > 5`, treat as a warning-level signal during manual review. Otherwise, rapid_send is context — not a risk driver.
3. **same_event_overload is only critical for new accounts.** More than 6 listings for the same event is only critical if the seller's account is less than 7 days old. Established sellers (account_age_days >= 7) cap at warning severity regardless of listing count.
4. **Trust stabilization rule.** If a seller has `account_age_days > 30` AND `dispute_loss_rate = 0`, their risk tier cannot exceed `medium`, regardless of other signals. This prevents established, clean sellers from being over-penalized by volume-based signals.

### INFO

Assign `info` when the signal indicates a potential configuration issue or low-risk anomaly that does not suggest fraud.

| Flag Type | Info Criteria |
|-----------|--------------|
| `missing_payout_setup` | Always info — seller may simply not have completed onboarding yet. |
| `new_account_high_value` | Account is 4-7 days old AND listing value is $200-$300 AND seller has completed Stripe setup. |
| `repeated_expiry` | Seller has exactly 3 expired transfers AND has a history of successful completions too. |
| `rapid_send` | Default severity for rapid_send. Informational signal only — does not drive risk tier. |

### WARNING

Assign `warning` when the signal suggests a pattern that could indicate fraud or negligence, but is not immediately dangerous.

| Flag Type | Warning Criteria |
|-----------|-----------------|
| `same_event_overload` | 4-6 active listings for the same event+date. Also applies to >6 listings if account_age_days >= 7 (established sellers cap at warning). |
| `high_dispute_rate` | Dispute rate > 20% with at least 3 completed transfers. **Max severity for this flag type is always warning — never critical.** |
| `rapid_send` | Only escalate to warning if account_age_days < 3 AND rapid_send_count > 5. Otherwise stays info. |
| `new_account_high_value` | Account < 3 days old OR listing value > $300. |
| `high_listing_velocity` | 6-10 listings created in the past 24 hours. |
| `repeated_expiry` | 3-4 expired transfers OR expiry rate > 30%. |

### CRITICAL

Assign `critical` when the signal strongly suggests fraud, abuse, or imminent buyer harm.

| Flag Type | Critical Criteria |
|-----------|-------------------|
| `same_event_overload` | More than 6 active listings for the same event+date AND account_age_days < 7. Established accounts (>= 7 days) cap at warning. |
| `high_dispute_loss_rate` | Loss rate > 50% with at least 2 disputes. Always critical — this seller is losing disputes and buyers are being harmed. |
| `duplicate_proof` | Always critical — same proof image on multiple active listings is a strong fraud indicator. |
| `duplicate_evidence` | Always critical — same transfer evidence on multiple transfers strongly suggests fabricated transfers. |
| `high_listing_velocity` | More than 10 listings in 24 hours. |
| `repeated_expiry` | More than 4 expired transfers. |

**Explicitly excluded from critical:** `high_dispute_rate` (max = warning) and `rapid_send` (max = warning, informational only).

### Trust Stabilization Rule

When evaluating risk tier during manual review, apply this override **after** all other severity rules:

- **Condition:** `account_age_days > 30` AND `dispute_loss_rate = 0`
- **Effect:** Risk tier cannot exceed `medium`, regardless of open flag count, listing velocity, or other volume-based signals.
- **Rationale:** A seller with 30+ days of history and zero dispute losses has demonstrated trustworthiness. Volume-based signals (high listing velocity, same-event overload) are more likely to reflect legitimate high-volume selling than fraud for these accounts.
- **Exception:** Trust stabilization does NOT apply if the seller has any open `duplicate_proof` or `duplicate_evidence` flags. These are hard fraud indicators that override trust history.

### Override Guidance

The admin may downgrade severity by one level if there is a clear legitimate explanation (e.g., a venue reseller with a known business relationship). The `details` field must document the override reasoning. The admin should never upgrade `info` directly to `critical` — investigate further first.

---

## SECTION 5 — Resolution Rules

Resolution is set when an admin reviews and closes a flag. Every resolution requires `resolution_notes` explaining the decision.

### DISMISSED

Use when the flag is a false positive or the situation has been explained.

- The seller provided a legitimate explanation (e.g., they are a registered reseller for same-event-overload).
- The detection signal was triggered by a data anomaly (e.g., duplicate proof path due to a re-upload of the same image for the same listing).
- The signal no longer applies (e.g., the listings have since been removed by the seller).
- The admin investigated and found no actual risk.

### WARNED

Use when the signal is real but does not yet warrant enforcement action. The admin plans to contact the seller directly (outside the system) or monitor them.

- First offense for a warning-level flag with no prior history.
- Seller has a mixed record (some successful transfers, some flags).
- The flag is `new_account_high_value` and the seller appears legitimate but bears watching.
- Admin sent the seller a manual message (email, in-app, etc.) advising them about the behavior.

### LISTING_BLOCKED

Use when the admin has decided this seller's ability to create new listings should be restricted. Since Phase C has no enforcement hooks, this is a manual record — the admin must separately take action in Supabase to enforce it (e.g., setting `is_listing_blocked = true` on `seller_risk_scores`).

- Seller has multiple warning-level flags for the same flag_type (repeat pattern).
- Seller has a critical flag for `same_event_overload` or `high_listing_velocity`.
- Seller has confirmed duplicate proof across different events.
- Dispute loss rate is high but not high enough for suspension.

### SELLER_SUSPENDED

Use when the admin has decided this seller should be fully suspended. Phase C has no enforcement hook — the admin must manually deactivate the seller's listings and block their account outside this system.

- Seller has critical flags for `duplicate_proof` AND `duplicate_evidence` (strong fraud pattern).
- Dispute loss rate > 50% with 3+ disputes.
- Seller has 3+ critical-severity open flags simultaneously.
- Seller has been previously warned (has a prior `warned` resolution) and the behavior continued.

### ESCALATED

Use when the admin cannot make a decision alone and needs a second opinion or executive review.

- Seller is a high-volume, high-revenue account with critical flags (business risk of false positive is high).
- The flag type is novel or does not clearly fit existing severity rules.
- Legal or regulatory implications (e.g., potential ticket scalping law violations).
- The seller has disputed the flag and the admin is unsure.

---

## SECTION 6 — Files To Produce

Phase C requires exactly **one new file** and **zero schema changes**.

| # | File | Type | Description |
|---|------|------|-------------|
| 1 | `PHASE_C_ADMIN_SQL_PACK.sql` | New | Complete SQL operations pack containing all queries from Section 3 (flag insert template, context inspection, open flags query, risk summary, resolve template, score refresh, dashboard view, audit trail). Header comments explain the workflow. |

No migrations are needed — the Phase B schema (`seller_flags`, `seller_risk_scores`, scoring functions) is sufficient for all Phase C operations.

The design document (`PHASE_C_MANUAL_REVIEW_DESIGN.md`, this file) serves as the operational runbook.

---

## SECTION 7 — Exact Claude Code Prompt

```
You are implementing Phase C of the SnatchIt marketplace trust-and-safety system.

Phase B V1 is complete:
- seller_flags table exists (see 012_seller_risk.sql)
- seller_risk_scores table exists
- refresh_seller_risk_score() and refresh_all_seller_risk_scores() functions exist
- PHASE_B_DETECTION_QUERIES.sql contains 10 read-only detection queries

SEVERITY POLICY (MUST be encoded in comments throughout the SQL pack):
1. high_dispute_rate can NEVER be assigned critical severity. Max = warning.
   Only high_dispute_loss_rate drives critical for dispute signals.
2. rapid_send is informational only. Default severity = info.
   Only escalate to warning if account_age_days < 3 AND rapid_send_count > 5.
   rapid_send does NOT contribute to risk tier calculations.
3. same_event_overload is only critical if >6 listings AND account_age_days < 7.
   Established sellers (>= 7 days) cap at warning regardless of listing count.
4. Trust stabilization: if account_age_days > 30 AND dispute_loss_rate = 0,
   risk tier cannot exceed 'medium' — UNLESS seller has open duplicate_proof
   or duplicate_evidence flags (hard fraud indicators override trust history).

TASK: Create exactly ONE file: PHASE_C_ADMIN_SQL_PACK.sql

This file must contain the following query blocks, each with clear header comments:

1. MANUAL FLAG INSERT TEMPLATE
   - INSERT into seller_flags with placeholders for seller_id, flag_type, severity, details, listing_id, transfer_id
   - Include a comment block listing all valid flag_type and severity values
   - Include a SEVERITY GUIDE comment block that encodes the 4 severity policy rules above
     (so the admin sees the rules every time they open this file)

2. SELLER CONTEXT INSPECTION
   - Single query that returns: seller_id, display_name, account_created, account_age_days, total_listings, active_listings, completed_transfers, total_disputes, dispute_losses, expired_transfers, stripe_connect_id, current risk_tier, open_flags_count, critical_flags_count, dispute_rate, dispute_loss_rate, score_last_updated
   - Joins auth.users, profiles, seller_risk_scores
   - Parameterized by seller_id placeholder

3. FETCH SELLER OPEN FLAGS
   - All unreviewed flags for one seller, ordered by severity (critical first) then created_at DESC
   - Parameterized by seller_id placeholder

4. FETCH SELLER RISK SUMMARY
   - Full seller_risk_scores row plus computed current_open_flags, resolved_flags, current_critical_flags counts
   - Parameterized by seller_id placeholder

5. RESOLVE FLAG TEMPLATE
   - UPDATE seller_flags SET reviewed_at, reviewed_by, resolution, resolution_notes
   - WHERE id = placeholder AND reviewed_at IS NULL (safety guard)
   - Include comment listing all valid resolution values

6. REFRESH ONE SELLER SCORE
   - SELECT refresh_seller_risk_score(placeholder)
   - Followed by verification SELECT showing the updated row

7. REFRESH ALL SCORES (BATCH)
   - SELECT refresh_all_seller_risk_scores()

8. DASHBOARD: ALL OPEN FLAGS
   - All unreviewed flags across all sellers
   - Join profiles and seller_risk_scores for context
   - Order by severity (critical first) then created_at ASC (oldest first)

9. AUDIT TRAIL: RECENTLY RESOLVED FLAGS
   - Resolved flags from last 30 days
   - Include reviewer display_name via profiles join
   - Order by reviewed_at DESC

10. TRUST STABILIZATION CHECK
   - Query that identifies sellers who qualify for trust stabilization
     (account_age_days > 30 AND dispute_loss_rate = 0)
     but currently have risk_tier = 'high' or 'critical'
   - Excludes sellers with open duplicate_proof or duplicate_evidence flags
   - Purpose: admin runs this to find sellers whose tier should be manually reviewed downward

FILE HEADER must include:
- Title: Phase C — Admin SQL Operations Pack
- Date
- Warning: "All operations are MANUAL. No automatic flag insertion. No enforcement hooks."
- Brief workflow summary referencing the steps: detect → inspect → flag → refresh → resolve → refresh
- The 4 severity policy rules listed prominently

CRITICAL RULES:
- Do NOT create any new tables or alter existing tables
- Do NOT create any new functions
- Do NOT add any RLS policies
- Do NOT add any triggers or background jobs
- Every query uses '<placeholder>' style for parameterized values
- Include comments explaining when and why to use each query

Save the file to the project root as PHASE_C_ADMIN_SQL_PACK.sql
```

---

STEP COMPLETE — WAITING FOR NEXT RUN
