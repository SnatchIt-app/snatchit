# Saved ticket-delivery preferences — A's review of B's plan (2026-09-19)

**Reviewed:** B's `docs/product/TICKET_DELIVERY_PREFERENCES_PLAN_20260919.md` @ `685b757f12946fc0fcec64b1d142c799c7386919`, on branch `design/frontend-audit-20260917`. B's stated evidence base, `7a1502a3`, resolves and is on `release/candidate-20260918`.

**Owner's brief (directly to A):** review the plan and its §6 questions, then verify:
- the bid, checkout and sale-settlement boundaries;
- older-app compatibility;
- provider/method validation;
- protection against changing a destination after sending.

Also reconcile the 24-hour expiry/refund claim with the deployed functions and the existing expiry findings, and return the smallest staged plan. **Planning only. It authorises no change to payment rules or production.**

**What was checked:**
- the release gate `e191cbfa`, as candidate source;
- `origin/main`, whose edge functions were synced "to the deployed source" on 2026-08-05 (`1358a218`);
- the store app, Build 9 (tag `mobile/v1.0-build9-apple-review`);
- the records named below.

Where the gate differs from B's base: `create-payment-intent` and `enforce-transfer-expiry` changed (132/134), so B's line numbers there are stale. The substance A relies on was re-read on the gate.

## Evidence limit — production was not read
A attempted a read-only production read of the deployed definitions:
- the edge-function list and source;
- `pg_get_functiondef` for the transfer functions;
- `cron.job`.

**The session's permission classifier refused it as an unauthorised production read.** A did not retry it or work around it.

"Production" below therefore rests on three sources:
- `main`'s edge source, synced to the deployed source on 08-05;
- the 2026-09-12 production-state record: "11 legacy edges, unchanged hashes";
- the production ledger at 135, which means repo bodies up to 120, with `20260906*` not applied.

**That is the strength of records, not of a fresh read.** The reads that would close the gap are in §6.

## 1. Verdict
The direction is right: confirm the destination at commitment, record it per order, copy it when the transfer is created, and freeze it once the seller has sent. **Five corrections are needed before anything is built.**

1. **Q1 is answered "no".** `settle_listing_for_payment` does not exist in production, and even in the candidate it is not the only place that creates a transfer (§2).
2. **Bids are publicly readable.** `bids_select_all … using (true)` (`070:24`). A destination must never be stored on `bids`. This confirms B's separate table (Q2).
3. **A seller can change a listing's `transfer_method` after bids exist.** 072 leaves it unfrozen on purpose (`072:123`). A destination recorded for one method can therefore meet a transfer of the other method.
4. **`set_transfer_delivery_info` has no server-side validation.** It checks neither format nor type-versus-method. It accepts both fields at once, and only COALESCE-overwrites (`0550:228-241`).
5. **S3 (hard enforcement at bid and checkout) would refuse every Build 9 user.**
   - Build 9, the store app, inserts bids directly (`PlaceBidScreen:108`).
   - It calls `create-payment-intent` with no destination (`payments.ts:64`).
   - So S3 is left out of the staged plan, pending an owner decision.

## 2. The boundaries

| Boundary | Candidate (gate `e191cbfa`) | Production (records strength) | Build 9 (store) | Consequence |
|---|---|---|---|---|
| **Bid** | Direct INSERT. `bids_insert_authenticated` checks only `bidder_id = auth.uid()` (`070:22-23`). Only AFTER INSERT triggers exist (035, 058, 0661). Bids are publicly readable (`070:24`). | Same policy (070 ≤ 120). | Inserts directly (`PlaceBidScreen:108`). | Enforcement needs a new BEFORE INSERT check (four-file rule), and that refuses every Build 9 bid. |
| **Checkout** | `create-payment-intent`. Future card use is `on_session` only; merchant-initiated charges are something "we don't do" (`:1077-1081`). | A legacy deployed edge (hash unchanged at 09-12). | Invokes it with no destination (`payments.ts:64`). | Enforcing here needs an edge deploy, and production edge deploys are held together with the RC. |
| **Sale → transfer created** | **Two writers:** `settle_listing_for_payment` (`20260906100000:140, :166`), and `ensure_transfer_exists` (061 is the final body; still called by the client at `payments.ts:380`). | **Three writers, per `main`:** `confirm-payment` inserts directly (`:258-267`); `stripe-webhook`'s fallback inserts directly (`:330-341`); and `ensure_transfer_exists`. `settle_listing_for_payment` is **absent**, because `20260906100000` is not applied and shape B is NO-GO. | Calls `ensure_transfer_exists`. | Every writer sets `expires_at = now() + 24h` and no destination. Only a BEFORE INSERT trigger on `transfers` covers all of them in both environments (Q1). |
| **Change after send** | `set_transfer_delivery_info` allows `status IN ('pending','seller_sent')` (`0550:237`). **F11 is confirmed.** | Same (0550 ≤ 120). | The receive form appears only while both fields are NULL. | Freeze the destination on the server once the status is no longer `pending` (S4). |
| **Mark as sent** | `mark_transfer_sent` checks only the caller and the status. It checks neither the destination nor `expires_at` (`0550:158-189`, and 140 on the gate). **F12 is confirmed.** | The pre-140 bodies (140 is not applied). | The button is **disabled when both fields are NULL** (`send/[id].tsx:204, :355`). | A server-side refusal (S5) does not break any honest old client. |
| **Provider / method** | `transfer_method` CHECK allows `mobile_transfer`/`email` (`000:81`). `ticket_platform` has its own CHECK (`033:49`). **Nothing ties the two** (F9 confirmed). `transfer_method` is not frozen on UPDATE (`072:123`). The client matrix is in `platformInstructions.ts`. | Same. | Any combination can be created. | The server validates the type against the transfer's method. A same-table `NOT VALID` CHECK for new listings comes later (stage 5). |

## 3. The 24-hour expiry/refund claim, reconciled
B's F2 and F3 cite **candidate** source (`20260906100000`, `0551`). Production does not run `20260906100000`. On the production-equivalent source:

- **Creation:** the three writers above each set `expires_at` to 24 hours ahead, with no destination.
- **Expiry:** `public.enforce_transfer_expiry()` (`0551:13-31`, applied, ≤ 120) moves **every** `pending` transfer with `expires_at < now()` to `expired`. There is no destination check.
- **Refund:** Phase 1 of the `enforce-transfer-expiry` edge (`main:178-262`) issues a **full** Stripe refund (no amount) for each expired transfer. It acts on live-mode payments only and skips payments already refunded.
- **Schedule:** the cron runs `*/2`, active in production. Per `GO_NO_GO_PRODUCTION_8f45e9b_20260918.md` §7 it "posts as today". The 09-15 CI hazard record shows that production's edge answers.

**So B's claim holds in substance for production, at records strength.** Two corrections:
- the writer B cites does not exist in production;
- the gate's edge adds Phase 0, settlement reconciliation, which production lacks.

**Not verified:**
- (i) that production's deployed `enforce-transfer-expiry` is byte-identical to `main`'s;
- (ii) that production's cron ticks actually succeed (a refused tick expires nothing);
- (iii) how many production transfers have expired or been refunded for want of a destination.

**Existing findings this must agree with:**
- **Sandbox, 2026-09-17** (manifest, Line 3):
  - `expires_at` gates nothing in `mark_transfer_sent` or `attach_transfer_evidence`, and is display-only in the client.
  - The sandbox's expiry cron is refused with 401 (no service key), so **sandbox transfers never expire. Sandbox behaviour is not evidence of production behaviour here.**
- **C's copy** (`DEVICE_VERIFY_BUILD_PREP_20260918.md` §4; `transferState.ts:59`, "Send window has passed — send now if you still can"):
  - This is literally true on the sandbox.
  - In production, **if the cron succeeds**, a pending transfer past `expires_at` is expired and refunded within about 2 minutes. After that, `mark_transfer_sent` raises.
  - The hedge is accurate. But a seller who then sends through the provider is sending tickets for an order that has been refunded.
  - Handed to C as an observation; it is outside this plan.

## 4. Answers to B's §6

**Q1 — No.**
- In production the writers are `confirm-payment`, `stripe-webhook`'s fallback and `ensure_transfer_exists`; `settle_listing_for_payment` does not exist there.
- In the candidate, `ensure_transfer_exists` is still live and still called.

**Recommendation: one `BEFORE INSERT` trigger on `public.transfers`.**
- When both delivery fields are NULL, it copies the `(listing_id, buyer_id)` destination **whose recorded method equals `NEW.transfer_method`**. On a mismatch, or with no row, it copies nothing, and the order falls back to the legacy receive form.
- It is `SECURITY DEFINER` with `search_path=''`.
- The delivery fields are not in `guard_transfer_state_columns` (sandbox finding, 09-17), so no bypass is needed.
- This covers every writer in both environments, **with no edge redeploy and no dependency on the RC**.
- Drop S2's explicit copy inside the RPC, so there is exactly one mechanism.

**Q2 — Yes, a separate owner-only table.**
- **Never `bids`:** bids are publicly readable.
- **Not `payments`:** no payment row exists at bid time, there are several rows per attempt, and the table is gated.
- Conditions:
  - no client DML except through the RPC;
  - RLS on own rows; no seller read;
  - `buyer_id` references `auth.users` `on delete cascade`, and the table is added to the account-deletion sweeps and residue checks;
  - `method` and `confirmed_at` are stored;
  - non-winners' rows are purged once the sale settles, and a listing's rows are purged on relist;
  - the four-file rule applies.

**Q3 — A's framing for the owner.**
- **Today** (production, records strength): with no destination, the transfer expires at 24 hours and the buyer gets a **full refund**. The buyer is made whole and the seller loses the sale. This fails safe for money.
- **Pausing the clock** leaves paid funds held with no deadline, so it would need an outer cap. That is a new money rule.
- **Recommendation: no change.** The owner has not authorised any payment-rule change.
  - Capturing at commitment removes the case for new orders.
  - Revisit with the counts in §6 R4, which need the owner's authorisation.

**Q4 — Not planned in any record A holds.**
- The code is explicitly `on_session` (gate `create-payment-intent:1077-1081`).
- Off-session charging would be a payment-rule change, involving consent wording and Stripe's customer-authentication and stored-card consent requirements. That is the owner's decision and outside this scope.
- B's correction 2 stands: the plan is written against pay-after-win.

**Q5 — Separately, and before S2.** S4 and S5 go together in one small migration:
- **S4.** Refuse any change unless the status is `pending`. Accept only the field for the transfer's method (`mobile_transfer` → phone, `email` → email). Normalise to a US 10-digit number, and do a basic email shape check.
- **S5.** `mark_transfer_sent` refuses when the destination for the method is absent.
- **Sequencing:** S5 must be built on 140's body. 140 is on the gate but not in production, so this follows 140's production apply, and its rollback restores 140's body.
- **Compatibility with Build 9:** unaffected. Its send button already requires a destination, and its form appears only while both fields are NULL.
- **Optional, not recommended now:** a compare-and-set, where the seller passes the destination they saw. Adding a parameter to `mark_transfer_sent` risks the overload ambiguity that 0553 fixed. The simpler guard is a re-read before sending, plus B's in-app "buyer updated" notice.

## 5. Smallest staged plan
- **Stage 0 — owner decisions only, no code:**
  - Q3: keep today's rule;
  - S3: deferred;
  - whether to authorise the §6 reads.
- **Stage 1 — harden the existing paths (A, one migration, after 140 is applied in production):**
  - S4 freeze and validation, plus S5.
  - pgTAP with negative controls, one test per path through the real entry point.
  - No new object, so no census change. The rollback restores the applied bodies.
  - Build 9 is unaffected on every honest path.
- **Stage 2 — capture store and copy (one migration):**
  - `order_delivery_destinations`;
  - `confirm_delivery_for_listing(listing_id, method, destination)`, which validates the method against the listing's current `transfer_method`, and the format;
  - the `BEFORE INSERT` trigger on `transfers`;
  - **freeze `listings.transfer_method` once a bid, reservation or destination exists**, by extending `guard_listing_state_columns`. Without this, a method change silently drops the copy.
  - It is additive and optional, so it is harmless to old apps.
- **Stage 3 — client (C; gated by A; needs a build):**
  - the capture step and the "Tickets go to" row on bid, checkout and pay-after-win;
  - on the receive screen, Change while `pending` and read-only afterwards;
  - listing-form method chips limited to each provider's methods (C5);
  - the legacy form kept as the fallback.
- **Stage 4 — Settings defaults:** `buyer_delivery_defaults`. Optional, and pre-fill only.
- **Stage 5 — new-listing validation:** a platform/method CHECK, `NOT VALID` so existing rows aren't checked, after C5 is live. Existing mismatches need an R4 count first.
- **Not staged:** S3 hard enforcement (it refuses Build 9, and no minimum-version gate is known to A), off-session charging, and any change to the clock.

**Existing bids and orders with no delivery details:**
- **Pending transfers:** unchanged. The legacy receive form stays; the 24-hour rule stays; S5 matches what clients already do.
- **Active bids and pending payments placed before stage 3, or from Build 9:**
  - no destination row exists;
  - a new client asks once on the pay-after-win or checkout screen, before any money moves;
  - on an old client, the transfer is created without a destination, and the legacy form applies.
- **Never backfill from profiles.** The seller must never see an unconfirmed profile value, and the destination must match the buyer's **provider** account (F8).
- **A legacy transfer that was marked sent with no destination** (possible only by bypass): after S4 the buyer cannot add one. That is acceptable, because the seller has already sent.

## 6. Production reads that need the owner's authorisation (read-only, exact)
- **R1 (code only):** `list_edge_functions`, plus `get_edge_function` for `enforce-transfer-expiry`, `confirm-payment` and `stripe-webhook`. Compare against `main`.
- **R2 (catalog only):** `pg_get_functiondef` md5 and body for:
  - `enforce_transfer_expiry`;
  - `set_transfer_delivery_info`;
  - both `mark_transfer_sent` overloads;
  - `ensure_transfer_exists`;
  - every function whose body inserts into `public.transfers`.
- **R3 (aggregate only):** the `enforce-transfer-expiry` row in `cron.job`, plus status-code counts for its posts over the last 24 hours (`function_edge_logs`).
- **R4 (customer-data aggregates; a separate decision):**
  - pending transfers with no destination;
  - transfers expired in the last 30 days, split by whether a destination was present;
  - listings whose platform and method don't match.

## 7. Where the numbers stand
Nothing is allocated. Stage 1 and stage 2 numbers come from A's registry when they are written.
