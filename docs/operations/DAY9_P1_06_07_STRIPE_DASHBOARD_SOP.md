# DAY 9 — P1-06 / P1-07 Stripe Dashboard SOP

Two one-time operational steps. Both require Stripe Dashboard access on the platform account `acct_1T6FarGdOzCmGbHw` (SNATCH IT).

---

## P1-06 — Enable debit on negative Connect balances

**What it does:** if a chargeback or refund leaves a seller's Connected Stripe account in negative balance after their payout has already been released, Stripe debits the next payout to recover the funds. Without this, every lost chargeback comes out of the platform balance.

**Pair with:** the Terms language in `app/settings/legal.tsx` (already updated this PR — sections "Chargebacks and refunds" and "6a. Chargebacks, Refunds & Negative Balances").

**Steps**

1. https://dashboard.stripe.com/settings/connect → switch to **Live mode** (top-right toggle) for production; repeat in **Test mode** afterward.
2. Under **Connect** → **Onboarding options** → **Negative balances**, choose:
   - **Default debit behavior for new accounts:** *Debit Express accounts*.
3. Click **Save**.
4. *(Optional retroactive fix)* For pre-existing Express sellers created before this toggle: a per-account API update is required. Either ignore (the default applies to new chargebacks going forward) or run a one-off:
   ```bash
   curl -X POST https://api.stripe.com/v1/accounts/<acct_xxx> \
     -u sk_live_xxx: \
     -d "settings[payouts][debit_negative_balances]=true"
   ```

**Verification**

- Reload the Connect Settings page; the **Negative balances** row reads "Debit Express accounts."
- Spot-check via API:
  ```
  GET /v1/accounts/<seller_acct>
  → settings.payouts.debit_negative_balances === true
  ```

---

## P1-07 — Enable Stripe 1099-K filing on behalf of the platform

**What it does:** Stripe issues Form 1099-K to qualifying US sellers each January and files directly with the IRS. Without this, the platform is legally responsible for filing 1099-Ks for every US seller crossing the IRS threshold.

**Cost:** ~$2 per filed form (Stripe Tax Reporting pricing). Trivial at beta scale.

**Pair with:** Terms language section "6b. Tax Reporting (Form 1099-K)".

**Steps**

1. https://dashboard.stripe.com/tax/forms → Live mode.
2. If prompted, complete **Platform tax settings**:
   - **Platform legal name:** JDT LLC
   - **Platform EIN:** (your federal EIN)
   - **State filing scope:** US — all states + DC
3. Under **Filing settings**, select **Stripe files on your behalf**.
4. Confirm and Save.
5. Re-check during November of each tax year that all sellers have completed tax information collection (Stripe shows a banner if any are missing W-9 data).

**Verification**

- https://dashboard.stripe.com/tax/forms shows the platform configured for automatic 1099-K filing.
- A test seller account that has crossed the threshold appears in the **Pending tax forms** queue.

---

## Notes

- Both steps are **Dashboard-only** — no API automation exposed (or required) for the toggles themselves.
- No app code changes required for either ticket.
- Re-running the steps is idempotent.
