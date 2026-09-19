# Go / No-Go: production release of candidate `8f45e9b` (A, 2026-09-18)

**Authority (owner):** gather the eleven live facts read-only; complete the compatibility review and the local rehearsal with reviewers; return one go/no-go plan.

**Not authorized, and not done:** hosted writes, migrations, secret changes, deploys, production builds, merge into `main`. The phone-testing sandbox was not touched. 121 stays deferred, 125 and 126 stay out, and no Vault or signing restriction was lifted.

**Evidence marks used in this document:**
- **[LIVE]** read from production today, read-only;
- **[REH]** local rehearsal;
- **[SRC]** source at `8f45e9b`;
- **[TEST]** app tests or a throwaway probe;
- **[D]** D's independent review.

## Verdict

| Shape | Verdict |
|---|---|
| ~~**A. Two migrations (`140`, `20260909000000`)**~~ | ~~GO~~ → **NO-GO as drafted. D found a break, and A verified it LIVE (§10):** the candidate app's checkout selects `payments.amount_refunded_cents`, which production lacks. The candidate's settled-first and refund-display checkout logic therefore reads "nothing", **silently**. |
| **A′. App release. `140` + `20260909000000` + one new additive migration adding `payments.amount_refunded_cents int` (nullable), no edge deploy, then a production app build** | **Superseded by §12.8.** ~~**GO only together with the refund-classification fix in §11 (or the owner's explicit acceptance of its operating rule), once the migration is authored, tested, CI-green and reviewed, and the §9 decisions are made.** ~~The app stays byte-identical to Build 21~~: with the §11 fix, one pure function in the gated `setupDecision.ts` changes. Every step is compatible with the installed store app and the deployed edges. Rollback is data-safe at any point [REH].~~ **§12.6: data-safe, but its cutoff is the app release.** |
| **B. The server line** (the other required-by-edge migrations plus a redeploy of the candidate's edge functions) | **NO-GO now.** 133 cannot apply without a Vault change, which stays restricted. Old-client checkout timing under the payments RC is not demonstrated. The rollback cutoff is minutes after apply, not at redeploy (§6). It needs its own plan. |

## 1. The eleven live facts [LIVE]

| # | Fact | Result |
|---|---|---|
| L1 | Migration ledger | **Exactly 135 rows:** 000–120 with gaps, 16 four-digit, 5 early timestamped. **Nothing from 121 on.** So 22 are pending, as derived |
| L2 | Bodies and constraints the pending set touches | md5 of the 17 functions the 22 redefine, recorded. The three FKs already point at `profiles`, with bids ON DELETE CASCADE. None of the new objects exists, except `notify.register_push_token` and `notify.revoke_push_token` in an unexposed schema |
| L3 | Vault secret **names** | `service_role_key` only. **No `project_url`** |
| L4 | Deployed edge functions | 14. **All 11 legacy functions matched exact git commits by content** (helper agent; A re-verified 4 by `git hash-object`). Only `auto-finalize-auctions` equals the candidate. The other 10 are 2026-04 to 2026-09-02 versions |
| L5 | Edge secret **names** | 24. The candidate's edge code also reads `EMAIL_ENABLED` and `EXPO_PUSH_URL`, which do not exist; this matters only for shape B |
| L6 | Scheduled jobs | 24, all active. The five http jobs 133 rewrites already exist and post using the literal production host plus the Vault key. The refund and payout jobs are gated by `refund.executor_enabled` and `payout.executor_enabled`, and **both are `false`**. `net._http_response`, 7 days: 179 × 200, 1 null |
| L7 | Backups | **PITR OFF.** Daily WAL-G backups, 7 kept, newest 2026-09-18T13:47Z, all COMPLETED. A restore loses up to ~24 h |
| L8 | Auto-deploy | `git_branch ""` (connector and CLI). CLAUDE.md still requires the owner's **visual** dashboard confirmation |
| L9 | Installed app versions | **Unverifiable from here.** The only store-tagged client in the records is build 9, `mobile/v1.0-build9-apple-review` = `4740091` (2026-07-15). App Store status stays unverified (owner's restriction) |
| L10 | Minimum counts | bids with no profile: 0; duplicate `stripe_transfer_id` groups: 0; `rollback_archive` absent; `kernel.sweep_deletion_pending` overloads: 1; **push tokens in total: 2 (0 new in 30 days)** |
| L11 | Exposed schemas | `public`, `graphql_public`, `kernel`, `ops`. `notify`, `venue`, `catalog`, `payments`, `market` and `signing` are **not** exposed |

## 2. The smallest required migration set: `140` + `20260909000000` + the A′ column migration (`payments.amount_refunded_cents`)

The candidate app's runtime needs were established by **runtime behaviour**, not by name references.

| App call (production today) | If absent | Evidence | Needed? |
|---|---|---|---|
| `get_my_tickets` (**Tickets tab ships unconditionally**) | A first load lands on the **error screen** | [TEST] probe PT1; [SRC] `tickets.tsx:79-88` | **YES → `20260909000000`** |
| `attach_transfer_evidence` ("Add proof" on a sent transfer with no proof) | "Couldn't add the screenshot" | [SRC] `markSent.ts`, send screen | **YES → `140`** |
| `mark_transfer_sent` (Mark as sent) | works: success is decided by a status read-back, not by the reply | [SRC] `markSent.ts:132-162` | no (140 also makes retries idempotent) |
| `register_push_token`, challenge RPCs (128/131/135) | PGRST202 → the legacy insert-only path, once per process | [TEST] `push-registration.test.ts` | no |
| `revoke_push_token`, `revoke_all_push_bindings` (129/131) | PGRST202 is logged and ignored; sign-out proceeds. **Precisely (D):** there is **no** legacy revoke, so the device's `push_tokens` row stays active after sign-out. That is **the same as build 9**, which never touches it (2 tokens exist). Record it as an **existing gap left unchanged**, not as graceful degradation | [TEST] `auth-sign-out`, `logout-scope` | no |
| `get_my_security_notices` (136) | no notice, no error, nothing logged | [TEST] probe PN1, with discriminating control PN2 | no. **Keep it out:** 136 would surface `account_deletion_pending` rows while F-NOTICE-1's fix (141) is unapplied |
| `record_payment_refund` | the name appears only in a **comment** in `setupDecision.ts`; there is no call | [SRC] | no (a false positive of name matching) |
| `venue.ticket_type`, `venue.inventory_batch` | `venue` is not exposed | [SRC] `src/lib/venue/client.ts` has **no importers** | no (dead code) |

~~All other RPCs and tables the app uses exist in production [LIVE, catalog names only].~~ **Corrected (D):** a catalog-names check cannot see a **missing column**. D's column-level check covered all 64 `.from()` chains over 10 tables (select, eq, in, order, update and insert columns, column privileges, embeds) and 24 `.rpc()` calls (argument names, EXECUTE). It found **exactly one** gap: `payments.amount_refunded_cents` (§10). After shape A′ the only missing RPCs are the 7 proven to degrade safely.

**Excluded, and why:**

| Migration(s) | Reason |
|---|---|
| 121 | deferred |
| 125, 126 | kept out |
| **123, 124** | a **no-op** on production's exact FK state (md5 unchanged) [REH]. Their rollbacks would re-point the FKs to `auth.users` and drop the CASCADE, breaking the `seller:profiles!seller_id` embed. **Never run those rollbacks in production** |
| 133 | refuses without Vault `project_url` [REH] |
| 135 | needs `project_url` to deliver challenges |
| 136 | not needed, and harmful before 141 |
| 127–132, 139, RC×4, `20260916000000` | needed only by the candidate's **edge** code, which shape A does not deploy. **The exception, found by D:** the app needs one column that `20260906120000` creates. A′ supplies that column alone, without the RC's triggers, tables or rollback archive |

## 3. Introduced by this candidate, or an existing production gap?

- **PRs #72–#76 introduced no database dependency** (no added RPC or table calls, verified earlier and by D).
- Both shape-A dependencies came into the release line **before** this phase: the Tickets tab at `92cfe51c` (2026-09-08) and "Add proof" at `5e9c80be` (2026-09-17). They were already at `6561d1f`, and **neither is in the store client** (`4740091`).
- **Existing production gaps that shape A leaves in place, unchanged:**
  - the payments RC fixes (F01/F03/F04: settlement authority, unpaid mark-sold, unbounded holds);
  - the checkout claims (130/132, including D's money defect);
  - push proof of possession (128/131/135);
  - security notices (136);
  - report-delivery idempotency (139);
  - the processing sweep (`20260916000000`).
- These are **gaps today with the store client too.** Shipping the candidate app neither creates nor closes them.

## 4. Rehearsal results [REH] (local loopback Postgres 17; superuser harness, whereas CI is non-superuser; CI is green on the full chain at `8f45e9b`)

1. **Production-shaped base:** 135 migrations in production's historical order. **16 of the 17 functions the pending set touches are md5-identical to production.** The exception, `public.cleanup_expired_reservations`, is cosmetic (keyword case), confirmed by reading both bodies. That makes the rehearsal a faithful model of the objects in play.
2. **Shape A:**
   - Apply: 140 and `20260909000000` apply cleanly.
   - pgTAP: **207 37/37, 187 20/20.** Negative control without them: 2/37 and 0/20.
   - **Old-client probe** (store build 9's exact calls): a first 2-argument and 3-argument `mark_transfer_sent` behave **identically to today**. The retries that raise today now answer `already_sent`.
   - **Rollback after a committed attach:** data kept, and both `mark_transfer_sent` bodies return to **production's exact md5**. Re-apply after rollback works.
3. **The server line without 133/135/136:**
   - Applies cleanly on the production shape.
   - pgTAP: **732 ok, 8 not ok** (788 planned). The failures are two census pins (162, 204) and "(under 135)" assertions (195, 198). **All pass on the full line** with a local dummy `project_url` (362/362, including 200/202/203).
   - The full reverse rollback runs cleanly, and 16/17 bodies return to production md5.
4. **133 against production's Vault names** refuses: "Vault carries service_role_key but no project_url".
5. **A's two process errors, both caught before they affected a result:**
   - A zsh word-split voided one pgTAP run. The runner also counts a **missing file as PASS**, so re-runs checked for a numeric plan.
   - A zsh glob voided one "no callers" search. It was redone with a positive witness.

## 5. Compatibility during each step of shape A

| Step | Installed store app (build 9) | Deployed edge functions | Candidate app |
|---|---|---|---|
| After `140` | ✓ its `mark_transfer_sent` calls behave as today (probe) | ✓ **no deployed edge file calls** `mark_transfer_sent`, `attach` or `get_my_tickets` (29 files; search with a witness) | not yet released |
| After `20260909000000` | ✓ additive; the old app never calls it | ✓ | not yet released |
| After the app release (old and new apps side by side) | ✓ unchanged | ✓ unchanged | ✓ **contract-compatible with every edge it calls** (below); ✓ runtime DB needs met (§2) |

**Candidate app ↔ deployed edges [SRC]:**
- `create-payment-intent` (deployed `d0b155da`): accepts `expected_total_cents`, returns `server_total_cents` on a price change, and returns the exact success fields the app reads.
- `confirm-payment` (`b98f5aff`): returns `{success, stripe_verified}` and no `outcome`. The app's `classifySettlement` then relies on the legacy `mark_listing_sold` / `complete_auction_payment` result, which is **the same sequence build 9 uses** → `completed`.
- `confirm-and-release` (`d0b155da`): same `transfer_id` request and the same `{error}` shape.
- `delete-account` (`74479b81`): supports `withdraw`; errors are read generically.
- `create-connect-account`: a type-only difference.

**Limit:** this combination (candidate app + production's edges) has **never run end to end**. It is proven at contract level only, because no isolated environment carries production's edge versions.

## 6. Rollback limits, demonstrated

**Shape A:**
- No data loss at any time.
- The rollback scripts restore production's exact bodies (md5).
- Rows written through the new functions stay valid under the old ones.
- The cutoff is **none**.
- Ledger note: 140 and `20260909000000` land above 121–139, so later applies of those need `--include-all`. That is a tidiness cost, as already recorded.

**Shape B, the reason it is NO-GO now:**
- **The cutoff is minutes after apply, not at redeploy.**
  - Cron `sweep-deletion-pending` (every 2 min) calls `kernel.sweep_deletion_pending`, which `20260906130000` replaces.
  - Cron `enforce-transfer-expiry` (every 2 min) runs the **deployed** edge, which calls functions that 127 and the RC replace.
  - **Added by D:** cron `auto-finalize-auctions` (every 2 min) calls `public.auto_finalize_expired_auctions`, which calls `public.cleanup_expired_reservations`, **redefined by `20260906110000`**. Also reachable: the daily `monitor-signing-key-invariants` → `kernel.check_signing_key_invariants` (133); `ops-daily-summary` / `ops-detect-tick` → ops functions (126, out of scope).
  - All run new semantics against production data within about 2 minutes.
  - **A future interplay:** `20260906120000`'s rollback drops `payments.amount_refunded_cents`. If A′'s column migration is applied first, that rollback would remove A′'s column too.
- **Rollbacks that drop data:**
  - 128 drops device-proof hashes;
  - 130 drops checkout claim tokens;
  - 131 drops session bindings, and its auth triggers' effects on tokens persist;
  - 132 drops the claim table.
- **`20260906120000`:** archives into `rollback_archive` (10 tables left behind), **refuses** in "unsafe" payout states, and restores only on re-apply.
- **123/124:** their rollbacks harm production (§2).
- **PITR is off:** a restore loses up to ~24 h.

## 7. What `project_url` and the signing-monitor change would switch on (assessment only; no restriction lifted)

- **With `project_url` = the production host, 133 is behaviour-preserving in production:**
  - the five jobs keep their targets and gates (refund and payout stay off, flags `false`; crm-export stays off, its secret is absent; `enforce-transfer-expiry` posts as today);
  - the notify triggers and the signing monitor post to the same host they post to today.
- **The monitor's body changes** (a new md5): B's review is required.
- **Only 135 would switch on something new:** challenge pushes through `send-push` to devices. The deployed `send-push` is the 2026-04 version, and its handling of that payload is not verified.
- **None of this is needed for shape A.**

## 8. Deployment order for shape A (each step owner-authorized; none authorized yet)

1. **Preconditions:**
   - the owner's visual AUTODEPLOY confirmation;
   - confirm a fresh daily backup exists (L7).
   - **Do not use `supabase db push`:** it would push all 22.
2. **Apply the A′ column migration** (additive: `ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS amount_refunded_cents int`). Read back that the column exists and `has_column_privilege('authenticated', …, 'SELECT')` is true. Nothing in production writes it (0 of 29 deployed edge files; 0 production-chain SQL), so it stays NULL and its rollback (drop column) loses nothing.
3. **Apply `140`** by targeted apply (the sandbox-window method: file + ledger row). **Read back:** the ledger row; the md5 of both overloads and `attach_transfer_evidence` equal the rehearsal values; the grants.
4. **Apply `20260909000000`** the same way; read back.
5. **Read-only smoke:** catalog checks only (no invocations, per the standing restriction).
6. **Production app build** from a candidate tag (EAS `production`: `pk_live`, production project), then TestFlight, then the App Store: owner steps.
   - DB first, then the app: an app shipped first would open Tickets on an error screen.
7. **No edge deploy. No merge into `main`.**

## 9. Remaining owner decisions

0. **Choose the refund-classification remedy (§11):** (i) the app treats a `refunded` row with no amount as `refund_pending` (A and D recommend this), or (ii) accept it with an operating rule: no partial refunds from the Stripe Dashboard while this build runs without the payments RC.
1. **Choose how to close D's break.**
   - **A′** (A recommends): a new additive column migration, with the app unchanged and identical to Build 21. It needs a registry number from A (next free: 142), a pgTAP test, CI, D's review and your authorization to author it.
   - **Client tolerance:** changes the device-tested, gated checkout code, so it needs a new review and a new build.
   - **Include `20260906120000`:** brings shape-B risks, including payment guard triggers under the deployed edges.
   - **Accept and record:** the candidate's checkout fixes stay inert in production. D assesses the outcomes as no worse than build 9 and the server guards still prevent a double charge; A has not independently verified the build-9 comparison.
   Then choose **A′** (GO as above), or wait for a full server-line release.
2. **Accept contract-level evidence** for candidate app ↔ deployed edges, or require an end-to-end run in an isolated environment that carries production's edge versions. That needs the deferred new project.
3. **The unknown-outcome wording** (deferred): decide before step 5, because it ships in the build.
4. **Authorize the two applies** (steps 2–3) and later the production build (step 5), each separately.
5. **Shape B** as its own plan later: the Vault `project_url` decision (restricted), B's monitor review, the RC old-client checkout timing, and the rollback cutoff.
6. **Record:** 123/124 must never be rolled back in production. 136 waits for 141.

**Status of this plan:** reviewers are D (requested; see the addendum when it lands). B is not reachable in this session, and B's sign-off is needed only for shape B (133/monitor).

## 10. D's independent review (2026-09-18), and A's verification of it

- **BREAK, verified LIVE by A:**
  - Production `public.payments` has **no** `amount_refunded_cents` column (column-name read). It is created only by `20260906120000:306`.
  - The candidate app selects it at `CheckoutNative.tsx:228` (`fetchSettledPayment`) and `:595` (`revalidateAgainstServer`). **Both discard the error** (`return data ?? null`; `pickSettled(rows ?? null)`), so PostgREST's 42703 turns every settled or refunded payment into "none", **silently**.
  - Reproduced locally: *"column amount_refunded_cents does not exist"* on the production-shaped database.
  - The status filter values (`succeeded`, `refunded`) are valid under production's `payments_status_check`, so the column is the only gap.
- **Effect under shape A (D, from source):**
  - A buy-now buyer whose charge landed can get `not_held` (the fixed "reservation expired" outcome).
  - An auction winner is refused by the deployed `create-payment-intent` ("Payment already completed"), so there is no double charge.
  - Refund states never show.
- **Provenance:** `0590f3e0` (2026-09-14, Premium batch 1). It was already at `6561d1f` and is **not** in build 9. Not introduced by #72–#76.
- **The fix A proposes (A′), prototyped [REH]:**
  - The column is added; `authenticated` may select it (table-level grant).
  - The app's exact query runs with no error under RLS.
  - Dropping it reverses it.
  - `20260906120000` still applies afterwards (its `ADD COLUMN IF NOT EXISTS` is a no-op).
- **Shape-B cutoff:** `auto-finalize-auctions` → `cleanup_expired_reservations` is added (§6).
- **The `cleanup_expired_reservations` drift, proven harmless by an exact check:**
  - the quoted values are **byte-identical** (`'public'`, `'app.bypass_listing_guard'`, `'on'`, `'active'`, `'reserved'`);
  - there are no quoted identifiers;
  - the remaining text is identical after case-folding and whitespace normalisation.
- **Rollback ACLs (D's gap):** production's EXECUTE grantees on both `mark_transfer_sent` overloads are `authenticated`, `service_role` and `postgres` [LIVE]. The rehearsal's grantees are **the same set** on the base, after 140 and after its rollback [REH].
- **Contract claims:** D confirms create-payment-intent and confirm-payment at source. D did not check delete-account's withdraw or the connect types; A checked both (§5).
- **D's method:** `client_deps_check.py` and `client_tables_check.py` (D's scratchpad), on local copies of A's production-shaped database. D had no production access.

## 11. D's second finding: A′ lets a PARTIAL refund read as "No purchase was made" (verified by A)

- **The mechanism, verified at source against production's code:**
  - The **deployed** `stripe-webhook` (`b98f5aff` line; `deployed_edges/…/stripe-webhook/index.ts:705-724`) handles `charge.refunded`, which Stripe also sends for **partial** refunds, by setting `status='refunded'` and `refunded_at=now()`. **It never looks at the amount.**
  - Under A′ the new column exists but **nothing in production writes it**, so it is NULL.
  - The candidate's `isRefundConfirmed` (`setupDecision.ts`) returns **true** for status `refunded`, `refunded_at` set and amount NULL. The kind becomes `refunded`, and `holdState.ts` shows *"This payment was refunded … No purchase was made."*
  - **For a partial refund the order stands. So that is a false statement about money**, against the product truth "Payment refunded only for a confirmed refund".
- **New, or pre-existing?**
  - **New under A′.** Under A without the column the query fails and no refund state shows; build 9 has no refund states.
  - The root, the old webhook marking partial refunds as `refunded`, **is pre-existing in production data**.
- **Exposure [LIVE, counts only]:**
  - production holds **7 `refunded` payments** (all dated, 4 with a refund id), 37 `succeeded`, 11 `pending` and 2 `failed`;
  - **whether any of the 7 was partial is not knowable from the database** (no amount is stored; it would need Stripe, which was not read).
  - The trigger is rare: a buyer re-entering checkout for that listing.
- **Remedies:**
  - **(i) Recommended by A and D:** in `isRefundConfirmed`, a `refunded` row with a NULL amount is **not** confirmed, ~~so it becomes `refund_pending`, which promises nothing~~. **Struck (§12.1): `refund_pending`'s copy also said "No purchase was made" and "being processed".**
    - ~~It is safe in both worlds: under `20260906120000`'s writer every refunded row carries the amount, so behaviour there is unchanged.~~ **Struck (§12.1): the RC never backfills, so existing refunded rows stay NULL for good.**
    - **Cost:** a gated-surface client change (C implements, A reviews, D tests), a test that fails without it, and the app is no longer byte-identical to Build 21 (one pure function).
  - **(ii)** Accept and record it, with an operating rule: no Dashboard partial refunds while this build runs without the payments RC.
  - **(iii)** The RC's writer (shape B), out of scope now.
- **D confirmed A′ closes the query break with D's checker:** the column is no longer flagged; the only missing RPCs are the 7 in the degrade set; the column is integer, nullable, with no default, and SELECT is granted. D has dropped its local copies.

## 12. Remedy (i) implemented, `142` authored, focused end-to-end rehearsal (2026-09-18)

**Owner's decision (A's session):**
- Remedy (i), but not "refund in progress": an unknown amount does not establish processing status.
- Wording such as "A refund was recorded for this payment. We can't confirm the refunded amount here."
- Preserve the order's independently established status, and don't invite another payment.
- Cover unknown, partial and full amounts.
- A authors the column migration locally. A focused end-to-end rehearsal is required before any release recommendation.
- No production writes, deploys or builds.

**Owner's correction, given to C directly and relayed by C.** A adopts it because it narrows what may be claimed; A does not treat a relay as authorization:
- no refund message says "No purchase was made" unless separate order evidence establishes it, because even a confirmed full refund can follow a completed purchase;
- confirmed partial or full refunds describe only what the recorded amounts establish.

### 12.1 Corrections to §11 (struck in place above)
- **Remedy (i) was wrongly specified.**
  - §11 said a NULL amount → `refund_pending` "promises nothing". False: at `8f45e9b`, `refund_pending`'s copy (`holdState.ts:96-101`) said "A refund is being processed … No purchase was made".
  - A found this while scoping and D confirmed it. D asked for it to be recorded as D's error. It was equally A's: A wrote §11 and recommended it without reading that copy.
- **"Unchanged under the RC writer" was incomplete.**
  - `20260906120000` never backfills (its lines 303-304: "a refund we did not observe is not a fact we may invent").
  - The 7 existing refunded rows, and every refund written before the RC ships, stay NULL permanently. **The neutral state is permanent for them, not interim.**

### 12.2 The client change: C implements, A reviews the payment boundary, D reviews behaviour
- **Where:** `fix/refund-amount-unknown @ 9f85c7be` (base `8f45e9bb`; local only; worktree `snatchit-refund`).
- **Files:** `setupDecision.ts`, `holdState.ts`, `CheckoutNative.tsx`, 4 test files, and the static preview.
- **Untouched:** `payments.ts`, `payControl.ts`, `signOut.ts`, `supabase/`.
- **Kinds.** One mapping, `refundStateFor`, serves both setup and revalidation:
  - `refunded`: status `refunded`, dated, and a recorded amount ≥ a known total;
  - `partially_refunded`: 0 < recorded amount < known total, on either status;
  - `refund_unconfirmed`: everything else. That includes every production refund today, succeeded rows carrying the full amount, and amounts with an unknown total;
  - `already_settled`: succeeded with no recorded amount;
  - `isRefundConfirmed`'s fallback is now `false`.
- **Copy:**
  - kicker "Refund";
  - titles "Refund recorded", "Partial refund recorded", "Full refund recorded";
  - bodies: "A refund was recorded for this payment. We can't confirm the refunded amount here." / "A partial refund of $X was recorded for this payment." / "A full refund of $X was recorded for this payment.";
  - pointer "Check Tickets for this order's current status.";
  - the only control is "Go to Tickets". There is no Pay, no retry and no route to the listing.
  - No kind says "No purchase was made", "order stands", processing, cancellation or bank timing.
- **A's payment-boundary review: PASS.**
  - Fresh on a clean detached checkout, dependencies identical: typecheck exit 0; lint 0 errors / 29 warnings (the gate `8f45e9b` also has 29); vitest 121 files / 2400 tests passed.
  - Every non-null settled row returns before `fetchListing` and `createIntent`.
  - Pay is re-armed only on the ready path (:375) or a `held` revalidation (:635), and a refund row reaches neither.
  - `refundState` is never cleared.
- **C's negative controls:** 9/9 as predicted, (a)–(i). (a), (b) and (c) fail differently.
- **Nit, now closed:** `refundViewModel`'s null-amount fallback swapped only the body, so a full-refund kind without an amount kept the title "Full refund recorded". `refundStateFor` made that unreachable; mutant (a2) showed it.
  - **Fixed at `b061c077`** (holdState.ts + test only): a confirmed kind with no amount now renders exactly as the neutral kind. K5 pins it; C's mutant (j) kills K5 alone.
  - A re-verified `b061c077` fresh: typecheck 0; lint 0 errors / 29 warnings; vitest 121 files / 2401 tests; end-to-end check 10/10.
  - Still possible: `refundViewModel(confirmed kind, 0)` would print "$0". It is unreachable, because `recordedRefundCents` maps 0 to null. Left to D.
- **Final head: `fix/refund-amount-unknown @ b061c077`.**
- **D's behavioural review:** pending at the time of writing; see §12.9.

### 12.3 Migration `142` (A)
- **Where:** `fix/142-payments-amount-refunded-cents @ e3c03d51` (base `8f45e9bb`; local only; not pushed).
- **Files:**
  - `supabase/migrations/142_payments_amount_refunded_cents.sql`;
  - `supabase/rollbacks/142_payments_amount_refunded_cents_rollback.sql`;
  - `supabase/tests/209_payments_amount_refunded_cents.sql`.
- **Number:** 142 and 209 are free across every ref and 119 worktrees (a positive control found 140/207). Now registered.
- **What it does:**
  - `ADD COLUMN IF NOT EXISTS amount_refunded_cents int`, byte-identical to `20260906120000:306`, so either may apply first with the same result;
  - a post-check refuses any other same-named shape;
  - `lock_timeout 3s`;
  - no writer, trigger, grant or index; never backfilled.
- **The four files:** none of the others moves.
  - `payments` has table-level grants only (209 S5 pins that).
  - The Gate-2 census after replay is 32|108|37|38, equal to `ci.yml`'s `EXPECT_*`.

### 12.4 Rehearsal results [REH]
Setup:
- **Database:** local production shape, built in production's historical order: ledger 135, 16/17 function md5s identical to production (the 17th is the known keyword-case drift).
- **Data:** synthetic rows seeded **before** 142, including an existing refunded row with no amount.
- **Stack:** local PostgREST 16.2 with JWT roles and RLS, and supabase-js.
- **Client:** the app's own `decideCheckoutSetup` and copy, with the screen's exact query text drift-guarded.
- **No charges:** `createIntent` is a spy, and nothing calls Stripe.

| Step | Result |
|---|---|
| Full chain with 142 (fresh replay) | 89/89 pgTAP files PASS; 209 11/11 |
| 209 on the production shape **without** 142 | S1–S4 fail; S6 errors (42703) and aborts the file (negative control) |
| 209 on the production shape with 142 only | 11/11. Re-applying 142 is a no-op (NOTICE) |
| 142's shape guard | refuses a pre-existing `bigint`, `int default 0` and `int not null default 0` column |
| Before 142 | the checkout read fails 42703; the error is swallowed. A paid buyer and a refunded buyer both get `not_held` with **"Nothing was charged"**; 0 intents only because the listing is sold |
| Apply 142 → 140 → 20260909000000 under a live PostgREST | relfilenode unchanged (no rewrite); the existing refunded row stays NULL (10/10 NULL); 12 concurrent `select('*')` readers show no error before or after, with or without a schema reload; the buyer's checkout read works at once; `get_my_tickets` answers **PGRST202 until `notify pgrst, 'reload schema'`**, then works |
| The deployed webhook's `charge.refunded` branch, run verbatim, on a $50-of-$110 partial refund | the row becomes `refunded`, dated, amount **NULL**; a second partial refund changes nothing |
| Buyer PATCH of `amount_refunded_cents` on their own row | 0 rows updated; value unchanged |
| Check, **C's fix** (9 buyers; `9f85c7be`, re-run at `b061c077`) | **10/10 PASS** at both. Both production-reachable rows show "Refund recorded / A refund was recorded for this payment. We can't confirm the refunded amount here." Known partials show "$50"; the known full refund shows "$110"; no amount appears for unknown rows. The CTA is Tickets everywhere. 0 intents, 0 listing reads. Revalidation gives the same kind |
| Check, **gate `8f45e9b`** (negative control and witness) | **7/10 FAIL.** b1 and b2 show "Payment refunded … No purchase was made" with "Back to listing"; b6 and b7 show "Refund in progress … No purchase was made"; b4 and b8 show "Your order stands" (b8: "$110 … Part of this payment") |
| Check, C's fix with mutant (a2) (both safeguards removed) | exactly b1 and b2 fail: "Full refund recorded" for a partial refund |

The harness is scratch-only and never committed: `…/scratchpad/reh/wt/tests/zzprobe/e2e_refund_unknown.test.ts`; results in `…/scratchpad/e2e/*.jsonl`.

### 12.5 Compatibility, step by step, with 142
- **Store app (build 9, `4740091`):** its client code (`src`, `app`, `hooks`, `lib`, `components`) never reads the `payments` table (witness: 11 files read `listings`). The column is invisible to it.
- **Deployed edges:** every `payments` read uses an explicit column list, and the insert uses explicit fields, so they are unaffected. The webhook's refund branch was exercised verbatim above.
- **Database functions:**
  - `payments%rowtype` and `select * into` adapt;
  - no function returns the payments rowtype, and no view depends on the table;
  - `ops.payment_json`/`order_detail`/`user_detail` gain a null `amount_refunded_cents` key. The admin console source has no reference to it; D is checking the rendering.
- **PostgREST schema cache:** after each apply, run `notify pgrst, 'reload schema'` as a runbook step. Hosted Supabase normally reloads on DDL through its event trigger, but that was not verified on production.
- **Limit:** production's PostgREST version was not read, and the local one is 16.2.

### 12.6 Rollback limits, demonstrated
- **R2:** with any value present, the rollback refuses (4 rows) and the column stays.
- **R1:** with `20260906120000` applied (full chain), the rollback refuses and the column stays.
- **The state A′ can actually reach** (all NULL: the webhook's partial refund applied, no RC writer): the rollback succeeds, leaving 19 columns and an identical ACL. No row data is lost, because nothing but NULL ever lived in the column.
- **Cutoff = the app release.** After that rollback, the new client's read breaks again, and paid buyers are told "Nothing was charged" [REH, `afterRollback`]. Before release, rollback is safe; after release, fix forward. Re-applying 142 restores the column, all NULL.
- **Hazard recorded for shape B, not changed now:** `20260906120000`'s rollback drops `amount_refunded_cents` (its rollback's final block). Once 142 has shipped with the app, rolling back the payments RC would recreate the column break. **Precondition for shape B:** amend that rollback to keep the column when 142 is in the ledger.

### 12.7 New finding F-CHK-READERR (A, demonstrated; not fixed)
- **What:** both settled-payment reads discard their error (`CheckoutNative.tsx:226-233`, `:593-599`).
- **Effect:** any failure of that read falls through to the hold check. For a buyer who paid (the listing is sold), the result is `not_held`: **"Nothing was charged. Go back to the listing…"** — a false statement about money. The `pre` and `afterRollback` phases above demonstrate it with 42703.
- **With 142 applied**, that cause is gone. A server-side error on this one read, while the listings read succeeds, still reaches it.
- **Origin:** introduced by the candidate (build 9 has no such copy), and triggered only by errors.
- **Suggested fix, not implemented:** a settled-read error → `reservation_unverifiable` ("Unable to verify … try again"), with no intent.
- **Owner decision:** include it in this change, or defer.

### 12.8 Verdict and deployment order (A′, revised)
- **A′ = `142` + `140` + `20260909000000`, no edge deploy, then a production app build containing C's fix. Recommended for release once the following hold:**
  - D's behavioural review passes (§12.9);
  - CI is green on both branches, which needs the owner's authorization to push and open draft PRs;
  - both branches are merged into `release/production-gate-20260918`, which needs its own authorization;
  - the owner decisions in §12.10 are made.
- **Order (each step owner-authorized; none authorized):**
  1. Preconditions: the owner's visual AUTODEPLOY confirmation; a fresh backup; never `db push`.
  2. Targeted apply of **`142`**. Read back: column `integer`/nullable/no default; `relfilenode` unchanged; `count(*) where amount_refunded_cents is not null` = 0; `has_column_privilege('authenticated', …, 'SELECT')`.
  3. Targeted apply of `140`; read back.
  4. Targeted apply of `20260909000000`; read back.
  5. `notify pgrst, 'reload schema'`; read-only catalog smoke.
  6. Production app build from a tag that contains C's fix; TestFlight; App Store. These are owner steps.
- **Rollback:** 142 can be rolled back only before step 6's release. 140 and `20260909000000` are as in §6.
- **Ledger note:** 142 lands above 121–141 (as 140 already does). The default `db push` would silently omit the lower pending versions; targeted applies are unaffected.
- **Shape B stays NO-GO**, and now carries the §12.6 rollback precondition.

### 12.9 D's behavioural review of `b061c077` — behaviour PASS, with one owner-level finding (verified by A)
- **D's own evidence:**
  - full suite on D's own worktree, run alone: 121 files / 2401 tests;
  - C's harness re-pointed at D's worktree: 10/10;
  - D's probes DP1–DP6 all hold: 0 intents on every mixed row set; the neutral state never shows an amount; the CTA is Tickets; no forbidden claims. A's nit is confirmed closed.
- **D's checkers on `a142_e2e_rehears`:**
  - the only missing RPCs are the 7 in the degrade set;
  - tables and columns are clean, also against C's source;
  - the column is integer and nullable, and `authenticated` has SELECT;
  - witness: `a142_e2epre_rehears` still flags the column at both checkout sites.
- **D's review of A's E2E:** sound. **Limit:** the revalidate branch is re-implemented in the harness rather than run in the RN screen; C's S2 source pin covers the wiring.
- **Admin console:** no effect. `toPayment` (`admin/src/lib/types.ts:581`, live `ab3e17f`) picks explicit fields, and unknown keys are ignored.
- **Live ADD COLUMN** [D, local]:
  - plpgsql `select * into` a payments variable adapts;
  - an open session's PREPARED `select * from public.payments` fails once with "cached plan must not change result type". Only direct database clients holding such a statement are exposed; PostgREST is not.
- **FINDING D-TKT, verified by A: "Go to Tickets" cannot show this order, so the pointer is false.**
  - `app/(tabs)/tickets.tsx` → `fetchMyTickets` → `rpc('get_my_tickets')`, which reads only `kernel.tickets`. Marketplace purchases never appear there.
  - A's own witness: the paid marketplace buyer b3 got **0 rows** from `get_my_tickets` in §12.4.
  - The empty state reads "No tickets yet / Tickets you own will show up here", which implies the buyer owns nothing. That contradicts the owner's "preserve the order's independently established status".
  - D says production has 0 `kernel.tickets` rows; A did not read that count, and the finding holds without it.
  - **Origin: A's spec (R5 said "Tickets (preferred)") without checking what Tickets shows. A's E2E encoded the same wrong expectation.** It is the fourth "check the system you name" error in this sprint.
  - **Where the order's status lives:** `/transfer/receive/<transferId>`. The Bids tab lists purchases, but only transfers in `pending`, `seller_sent`, `disputed`, `buyer_confirmed` or `auto_released` status, so a cancelled order is silently absent there.
  - **C is holding `b061c077` unchanged pending the owner's choice.**
- **D's minor findings:**
  - (1) render precedence (`if (refundState)` at :695) is pinned by nothing; D's mutant DM1 left 0 of 2400 tests failing. A asked C to add a pin with the next change;
  - (2) with two refunded rows, the one shown depends on database order (no ORDER BY). This matters only once amounts are written (the RC). Deferred;
  - (3) the settled read still swallows its error. This is the same as A's F-CHK-READERR (§12.7).

**Decision added to §12.10 (item 0): the refund screen's destination.**
- **(b) A recommends:** remove the pointer and make the CTA "Back to home". It is the smallest change and makes no claim.
- **(a)** When a transfer exists for this payment, "View order" → `/transfer/receive/<id>`; otherwise Home with no pointer. This adds one more buyer-own read, which is an authoritative-state read that A reviews.
- **(c)** The Bids tab. Not recommended.

### 12.10 Remaining owner decisions (replaces §9 items 0–1)
0. **The refund screen's destination (D-TKT, §12.9):** (b) remove the pointer and go Home (A recommends), (a) the order's transfer page when one exists, or (c) the Bids tab. Until this is decided, `b061c077` is not merge-ready.
1. **Push and draft PRs for CI.** Authorize pushing `fix/142-payments-amount-refunded-cents` and `fix/refund-amount-unknown` and opening draft do-not-merge PRs against `release/production-gate-20260918`.
   - CI's pgTAP job is non-superuser, and 209 has only run under the superuser harness.
   - A push also starts a snatchit-web preview, which the ignore step cancels; canceled builds still count toward the Vercel quota.
2. **Merge.** After CI is green and D passes the change, authorize merging both into the release gate (merge commits), then a new candidate tag.
3. **Device evidence for the new refund screen.** Accept unit, end-to-end and static-preview evidence, or require a sandbox preview build with a handset check. The app is no longer byte-identical to Build 21. A handset check also needs a refunded sandbox row, which is a sandbox data write with its own authorization. Phone testing is currently not authorized.
4. **F-CHK-READERR (§12.7):** include the fail-closed read in this change, or defer.
5. **The unknown-outcome wording** (deferred): decide before the build.
6. **§9 item 2 still stands:** contract-level evidence for the rest of the app ↔ deployed edges, beyond this refund path.
7. **Applies and build:** authorize the three applies, and later the production build, each separately.
8. **Legacy refunds:** the 7 existing refunded rows will always show the neutral state (no backfill). A Stripe-reconciled amount would be a production data write, needing its own authorization; A does not recommend it for this release.
