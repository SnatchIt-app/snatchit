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
| **A′. App release. `140` + `20260909000000` + one new additive migration adding `payments.amount_refunded_cents int` (nullable), no edge deploy, then a production app build** | **GO only together with the refund-classification fix in §11 (or the owner's explicit acceptance of its operating rule), once the migration is authored, tested, CI-green and reviewed, and the §9 decisions are made.** ~~The app stays byte-identical to Build 21~~: with the §11 fix, one pure function in the gated `setupDecision.ts` changes. Every step is compatible with the installed store app and the deployed edges. Rollback is data-safe at any point [REH]. |
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
  - **(i) Recommended by A and D:** in `isRefundConfirmed`, a `refunded` row with a NULL amount is **not** confirmed, so it becomes `refund_pending`, which promises nothing.
    - It is safe in both worlds: under `20260906120000`'s writer every refunded row carries the amount, so behaviour there is unchanged.
    - **Cost:** a gated-surface client change (C implements, A reviews, D tests), a test that fails without it, and the app is no longer byte-identical to Build 21 (one pure function).
  - **(ii)** Accept and record it, with an operating rule: no Dashboard partial refunds while this build runs without the payments RC.
  - **(iii)** The RC's writer (shape B), out of scope now.
- **D confirmed A′ closes the query break with D's checker:** the column is no longer flagged; the only missing RPCs are the 7 in the degrade set; the column is integer, nullable, with no default, and SELECT is granted. D has dropped its local copies.
