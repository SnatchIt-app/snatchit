# Backend → UI handoff: client-visible contract changes

**From:** the backend session (Claude A), refund + deletion clock + venue payout train, 2026-09-03.
**Scope:** concrete contract changes only. No design advice, no UI work, no opinions about screens.

**Nothing here is deployed.** Every function below is authored and dark. These are the contracts to
build against, not behaviour you can observe in any running environment today.

---

## 1. `connect-onboarding` — the Stripe payout dashboard link is now owner-only and step-up gated

This is the **only** client-visible behaviour change in this train.

**What changed.** The `login_links` arm — the one that opens the venue's Stripe Express Dashboard —
previously ran under the same gate as the rest of the endpoint (`org_owner` OR `org_finance`, no
step-up). It now requires `org_owner` **and** an aal2 session, because that link is how the bank
account inside the connected account is changed. Every other control in the system protects *which*
connected account is bound; this link changes *where the money in it lands*, and it was the weakest
door to it.

**The `account_onboarding` arm is unchanged.** It resumes an unfinished flow on an account that is not
yet transfers-active, so there is no money to redirect. Only the dashboard link moved.

**New refusal codes on that arm:**

| HTTP | `code` | Meaning |
|---|---|---|
| 403 | `dashboard_requires_owner` | Caller holds `org_finance` (or another role), not `org_owner`. |
| 403 | `step_up_required` | Caller is an owner but the session is not aal2. |
| 409 | `org_not_bindable` | Organization status is not `approved` or `active`. |
| 503 | `dashboard_authorization_unavailable` | The authorization verb is unreachable; fail-closed. |

**Contract note for whoever builds the venue surface:** payment *status* remains available without any
of this. Only opening the dashboard is gated. The 403 message text already says so, and a surface that
hides status behind the same gate would be stricter than the backend intends.

---

## 2. Nothing else changed for the client

Stated explicitly so you do not go looking:

- **Pricing:** unchanged this train. The `allInPrice` contract, the `direct` rail input shape, and the
  `service-fee-unset` / `quote-incoherent` refusal reasons are exactly as handed over previously.
- **Checkout:** `venue.create_primary_checkout`'s return shape is unchanged — `total_minor` (face),
  `buyer_fee_minor`, `charge_total_minor`, `org_id`. Its refusal codes are unchanged, including
  `no_active_signing_key`, `payout_not_ready`, `service_fee_unset`.
- **Ticket states:** unchanged. No new state, no changed enum.
- **Deletion:** the account-deletion *clock* changed substantially in the backend, but the block
  reasons are internal to `kernel.sweep_deletion_pending` and are not returned to the client by
  `delete-account`. No client contract moved. If a future surface wants to explain *why* a deletion is
  pending, that is a new contract and should be requested rather than inferred from the internal
  reason strings, which are diagnostic text and not a stable API.
- **Refunds and payouts:** the refund claim primitive, the payout executor, and the payout-destination
  verbs are all machine-only (`service_role`) and unreachable from any client session. Nothing to
  build against.

---

## 3. Two things that will affect UI work later, flagged now rather than at the last minute

Neither is a contract change today. Both are states a venue-facing surface will eventually have to
render, and both are the resting state until the owner acts.

- **No organization can be paid.** `set_org_payout_destination` has no caller, and a mis-bound
  organization is currently **permanently** mis-bound — bind-once plus an unreachable re-point. The
  edge's `409 destination_unusable` currently advertises a recovery path that does not exist. If you
  build a payout-settings surface, do not promise a "change account" action; the backend cannot honour
  it yet.
- **Two owner values gate selling** and both are unset by design: the buyer service fee rate and the
  ticket expiry grace. `service_fee_unset` surfaces as a 503 with a Sentry `activation_blocker`, not a
  400 — treat it as an environment state, not as user error.
