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

## 2b. 2026-09-03 native dispute / reversal train — no client contract changed

**From:** the native-dispute-wiring + reversal-lifecycle train (migrations 096-099, the
`stripe-webhook` native dispute arms and `transfer.reversed` routing, and a `payout-execute` reconcile
pass). **Scope of this note:** same as above — concrete contract changes only, checked against the
implementation reports (`docs/phase2/_impl/KM1`-`KM4`, `KW`, `KT`).

**Nothing here is deployed either.** As with everything above, these are contracts that will exist the
day the edges ship, not behaviour observable anywhere today.

**No client-visible contract changed this train. Say so explicitly, so you don't go looking:**

- The native dispute writers (`kernel.record_dispute_native`, `kernel.mark_dispute_state`) now have
  real callers — the new `charge.dispute.*` branches in `stripe-webhook/index.ts` — and
  `kernel.record_payout_reversal` now has a real caller — the new `transfer.reversed` native branch.
  Both are `stripe-webhook` internals: Stripe calls the webhook, the webhook calls `service_role`
  RPCs. No buyer- or venue-facing endpoint, screen, or return shape sits anywhere near this path.
- The reversal/recovery facts (096: `kernel.payout_reversal`, `kernel.organization_obligation_
  recovery`) and the failed-payout reconcile pass (096's `claim_failed_payouts_for_reconcile` /
  `reconcile_payout_transfer`, called from a second phase inside `payout-execute`) are entirely
  `service_role`-gated and machine-invoked. Same category as "refund claim primitive, payout
  executor, payout-destination verbs" above — nothing to build against.
- The signing-key invariant monitor and the two invoker crons (099: `check_signing_key_invariants`,
  `refund-execute-tick`, `payout-execute-tick`) are cron jobs calling `service_role` functions and
  posting to internal edge endpoints on a schedule. They page `platform_risk` through
  `notify-report`'s new `signing_invariant_alert` branch — an internal alerting path, not a client
  surface.
- **Checkout, ticket states, and refund/payout client surfaces are unchanged** — same return shape
  (`total_minor`, `buyer_fee_minor`, `charge_total_minor`, `org_id`), same refusal codes
  (`no_active_signing_key`, `payout_not_ready`, `service_fee_unset`), same ticket-state enum, and the
  refund/payout primitives remain `service_role`-only and unreachable from any client session, exactly
  as stated in §2 above.

**One nuance, checked rather than assumed, that does not change the conclusion.** Two of 096's new
verbs — `kernel.record_obligation_recovery` and the re-created `kernel.resolve_organization_obligation`
— are granted to `authenticated`, not `service_role` (KM1 §1, R-5/R-6; a deliberate KD P1-1 fix, moving
`resolve_organization_obligation` off a `service_role`-only grant it held since 094). That makes them
PostgREST-reachable in principle once `kernel` is exposed. Both are internally gated to
`platform_risk`/`platform_admin` role plus an aal2 step-up (`insufficient_privilege` / `step_up_required`
otherwise) — the same admin-only shape `resolve_organization_obligation` already had before this train,
now just reachable by role check instead of by grant. This is an internal risk/ops surface, not a
buyer- or venue-facing one; it does not change anything the primary ticketing UI (buyer checkout, venue
dashboard, ticket screens) needs to build against.

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

## 2c. 2026-09-03 credential-signing + A8a′ SALEABLE train (package 102) — one client contract ADDED, DARK

Nothing existing changed for the client. One NEW capability is authored but DARK (undeployed, no KMS):

- **`credential-sign` edge (NEW, not deployed).** `POST` `{ ticket_atom_id }`, `verify_jwt: true`, called
  as the ticket's owner. On success returns `{ token, credential_version, signing_key_id, not_after,
  ttl_seconds }` — `token` is a JWS-compact string (PFA-PT-6): `b64url(header).b64url(payload).b64url(sig)`,
  header `{alg,kid,typ:"SNATCHIT-TICKET-CRED-V1"}`, payload `{atom,exp,iat,sess,ver}`. Short TTL
  (`credential.app_ttl_interval`, seed "4 hours"). STATELESS: no signature is stored; re-fetch on demand;
  `credential_version` (bumped on transfer/void) is the currency mechanism. Refusals: `403 not_owner`,
  `409 atom_terminal`, `500 signing_key_unavailable`, `503` on KMS-down/rate-limiter fault, `429` over
  rate limit (30/60s). **Do not build UI against this yet** — it throws `kms_provider_unconfigured` until
  a KMS provider is wired and the ceremony run.
- **Door/scan SDK (NOT built).** When built it MUST: (M1) resolve `kid` against a trusted public-key
  manifest — NEVER a key inside the token — and pin `alg` per `kid` (PFA-PT-8), rejecting a mismatched
  header alg; (M2) check `credential_version` currency + `session_id` binding + `resale_state='none'`
  live/manifest (OFFLINE-VERIFY-v1, §5.4.3). **Signature authenticity ≠ admissibility** — a valid
  signature is necessary, not sufficient.
- **A8a′: `on_sale` now demands SALEABLE.** `catalog.publish_event(..., 'on_sale', ...)` refuses
  `org_not_saleable` / `connect_not_ready` / `signing_not_ready` / `fee_policy_unset` (the same predicate
  checkout enforces, moved earlier). A promoter now discovers a broken config when opening sales, not at
  the first buyer's failed mint. Surface these four refusal codes in the publish UI. NO tax gate
  (PFA-PT-7) and NO inventory-policy gate — those stay dynamic/owner-legal.
- **Owner items before this can go live:** PFA-PT-6 signature (adopt the wire format), KMS provider
  selection + ceremony, PFA-PT-8 door alg-pinning, and the tax-locus decision (PFA-PT-7). All tracked in
  `POST_FREEZE_AMENDMENTS.md`.

## 2d. 2026-09-03 signing / door / KMS train (package 103) — verifier + algorithm pin, DARK

No existing client contract changed. New backend surfaces for the door/scanner client (all DARK):

- **Algorithm pin (PFA-PT-8, migration 103).** `credential-sign`'s response and the token header now
  carry a real `alg` (`EdDSA` or `ES256`) sourced from `kernel.signing_key.algorithm`. A verifier MUST
  pin the algorithm from the TRUSTED key (resolved by `kid`), NOT from the token header, and refuse
  `alg_mismatch` if they disagree. The header `alg` is informational only.
- **M1 verifier core** — `supabase/functions/credential-sign/credential.ts` `verifyToken(token,
  resolveTrustedKey, nowSeconds, verifyPrimitive)`. `resolveTrustedKey(kid) → { public_key, algorithm,
  … }` from the M1 key manifest (a projection of `kernel.signing_key`'s granted columns — now including
  `algorithm`; never a key inside the token). Proves AUTHENTICITY only (signature + exp), NOT
  admissibility. Reason codes: `malformed_token`, `unsupported_alg`, `unknown_kid`, `alg_mismatch`,
  `signature_invalid`, `expired`, `ok`.
- **M2 / OFFLINE-VERIFY-v1 core** — `supabase/functions/_shared/offline-verify.ts`
  `offlineVerify(token, ctx)` implements the NORMATIVE §5.4.3 predicate exactly (M1 key checks →
  alg pin → signature → session → exp±skew → manifest authority → 5 currency conjuncts → signing-key
  match → first-in-wins). Reasons include `stale_version`, `not_active`, `listed_locked`,
  `atom_absent`, `atom_revoked`, `wrong_session`, `wrong_signing_key`, `already_admitted`,
  `manifest_expired`, `manifest_other_session`, `no_manifest`. The scanner SDK implements THIS text;
  do not narrow it. **Signature authenticity ≠ admissibility** — a valid signature is necessary, not
  sufficient; the currency conjuncts (credential_version, ticket_state='active', resale_state='none')
  are what defeat the old-owner screenshot after a transfer.
- **Online path** — `venue.validate_ticket_online(atom, session)` (the C37 live read) substitutes for
  M2 when connected; `venue.record_scan` is the atomic admission (first-in-wins via a partial unique
  index). Offline uses the door manifest (`venue.get_door_manifest`, base ⊕ deltas).
- **Still DARK / not for UI yet:** `credential-sign` is undeployed and throws `kms_provider_unconfigured`
  until the KMS ceremony runs; the `door-session`/`door-manifest` edges are specified but NOT built
  (and `create_door_pin`/`mint_door_session` are parked pending a slow-KDF ratification). Build door
  UI against these contracts, but nothing is live.
