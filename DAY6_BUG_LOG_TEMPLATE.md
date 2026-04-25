# Day 6 — Bug Log

**Tester:**
**Date:** 2026-04-__
**Build:** TestFlight build #___

---

## Bug Entry Template

Copy the block below for each bug found.

---

### BUG-001: [Short title]

| Field | Value |
|-------|-------|
| **Test Scenario** | Test # (e.g., Test 1: Happy Path) |
| **Step** | Step number where bug occurred (e.g., 1.3) |
| **Severity** | Critical / High / Medium / Low |
| **Status** | Open / In Progress / Fixed / Won't Fix |

**Description:**
One-sentence summary of what went wrong.

**Steps to Reproduce:**
1. ...
2. ...
3. ...

**Expected Behavior:**
What should have happened.

**Actual Behavior:**
What actually happened.

**Evidence:**

| Type | Value |
|------|-------|
| listing_id | `<uuid>` |
| transfer_id | `<uuid>` |
| payment_id | `<uuid>` |
| Stripe PI | `pi_xxx` |
| Screenshot | (attach or describe) |

**SQL State at Time of Bug:**
```sql
-- Paste relevant query + result
```

**Stripe Dashboard State:**
(Describe PaymentIntent status, Transfer status, Refund status as seen in Stripe)

**Resolution Notes:**
(Fill in after fix)

---

## Severity Guide

| Level | Definition | Example |
|-------|-----------|---------|
| **Critical** | Money lost, double-charged, or payout to wrong person | Payout released on disputed transfer |
| **High** | Flow blocked, user cannot proceed | Buyer cannot confirm receipt |
| **Medium** | Flow works but state is wrong or notification missing | Push notification not received |
| **Low** | Cosmetic or minor UX issue | Wrong status label displayed |

---

## Bug Log Entries

_(Copy the template above and paste below for each bug found)_

---

### BUG-001: [Title]

| Field | Value |
|-------|-------|
| **Test Scenario** | |
| **Step** | |
| **Severity** | |
| **Status** | Open |

**Description:**

**Steps to Reproduce:**
1.

**Expected Behavior:**

**Actual Behavior:**

**Evidence:**

| Type | Value |
|------|-------|
| listing_id | |
| transfer_id | |
| payment_id | |
| Stripe PI | |
| Screenshot | |

**SQL State at Time of Bug:**
```sql

```

**Stripe Dashboard State:**

**Resolution Notes:**

---
