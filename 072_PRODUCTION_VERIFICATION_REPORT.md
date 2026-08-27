# 072 — H-1 Production Verification Report

## Verdict: **072 H-1 CLOSED IN PRODUCTION**

Applied 2026-08-27 under explicit owner authorization, pinned to the reviewed head SHA. Every
required verification passed. **No real user listing was altered.** `073` was not applied and does
not inherit this approval.

| | |
|---|---|
| Migration | `supabase/migrations/072_fix_listing_insert_guards.sql` |
| SHA-256 | `a4501dd7541cb1fa0a0219f2aef1e6994675aa4db1b87774fcc5eec103efaf7d` (unchanged from review) |
| Rollback | `supabase/rollbacks/072_fix_listing_insert_guards_rollback.sql` · `7a6f77d4…8aed34c550` |
| PR | [#20](https://github.com/SnatchIt-app/snatchit/pull/20), squash-merged pinned to `3b36d1d41338eb9c23ec2532bee9e0449de9abed` |
| `main` | `39a1c594224f14de8512ed1c35bbcf929e531baf` |
| Ledger | **85 → 86** |

---

## 1. Pre-flight (all confirmed before any mutation)

| Gate | Result |
|---|---|
| PR head SHA equals the authorized SHA | `3b36d1d41338eb9c23ec2532bee9e0449de9abed` ✓ exact |
| PR mergeable / all 5 required checks | `MERGEABLE / CLEAN`, all pass |
| **Supabase auto-deploy OFF** | branch record `git_branch = ""`, `updated_at` still `2026-08-27T15:49:25Z` ✓ |
| Merged checkout migration count | **86** |
| `073` present in the applied checkout | **0 — absent** |
| 072 SHA-256 in the merged checkout | matches the reviewed artifact byte-for-byte |
| **Dry run proposes exactly one migration** | `Would push these migrations: • 072_fix_listing_insert_guards.sql` ✓ |

The dry-run isolation check is the one that mattered: `073` could not have ridden along, because it
does not exist on this branch at all.

**Pre-apply production snapshot:** ledger 85 (md5 `4783033000cc5cb11e03271330cbd049`), backup 79,
Gate-2 `27 / 68 / 37 / 23`, 111 listings, `guard_listing_insert_columns` **absent**.

## 2. Apply

```
supabase db push --linked --include-all
  → Applying migration 072_fix_listing_insert_guards.sql...
  → {"upToDate":false,"dryRun":false,"migrations":["072_fix_listing_insert_guards.sql"],...}
```

Exactly one migration applied. `--include-all` is required because every sequential migration sorts
before the ledger's timestamp maximum (`20260731224653`); without it `db push` fails closed with
`LegacyDbPushMissingRemoteError`. **That flag is now a permanent property of this repository's deploy
path and belongs in the runbook.**

## 3. Required post-apply verification

| # | Required | Result |
|---|---|---|
| 1 | production ledger = 86 | **86** ✓ |
| 2 | repository migrations = 86 | **86** ✓ |
| 3 | exact source↔ledger version-set equality | both md5 **`38a1bdc1533ae58edd9b3886b32689fb`** ✓ |
| 4 | `db push --dry-run` = up to date | `{"upToDate":true,…,"message":"Remote database is up to date."}` ✓ |
| 5 | `guard_listing_insert_columns()` with the reviewed definition | present · `prosecdef=false` (INVOKER) · `proconfig={search_path=public, pg_temp}` · ACL `postgres=X \| service_role=X` (anon/authenticated/PUBLIC hold none) ✓ |
| 6 | `trg_guard_listing_insert` live as BEFORE INSERT | `CREATE TRIGGER trg_guard_listing_insert BEFORE INSERT ON public.listings FOR EACH ROW EXECUTE FUNCTION guard_listing_insert_columns()` ✓ |
| 7 | Gate-2 = 27 / 69 / 37 / 24 | **27 tables / 69 functions / 37 policies / 24 triggers** ✓ |
| 8 | pgTAP green at 13 files / 234 assertions | 13 files / 234 planned on `main`; CI [33092007069](https://github.com/SnatchIt-app/snatchit/actions/runs/33092007069) `Files=13, Tests=234, Result: PASS` ✓ |
| 9 | pre-Scheme-B backup intact | **79 rows** ✓ |

`public.listings` now carries **6** non-internal triggers (was 5) — the one new BEFORE INSERT guard.

**Production runs exactly the reviewed tree:** `main` tree and the authorized PR-head tree are the
same object, `d110a25dfb0498751854b7159e4d0315b2a0fdb0`.

## 4. Controlled behavioural verification

Method: two transactions, each `BEGIN … ROLLBACK`, creating only synthetic `ZZ-072-*` rows. **No
pre-existing listing was read-modified.** Post-run re-check: **111 listings, 0 rows matching
`ZZ-072%`**, `proof_status` distribution unchanged at 8 approved / 103 pending_review, transfers 36,
payments 56.

Actor: a real onboarded, phone-verified seller — so the INSERT RLS policy genuinely admits the
statement and the **trigger** is what decides. A denial from RLS would carry a different message and
would prove nothing.

### Seeding attempts — all DENIED by the 072 guard

Every one raised `P0001: Cannot set server-controlled listing columns on insert.`

| Column | Result |
|---|---|
| `winner_user_id` | **DENIED** |
| `winning_bid_amount` | **DENIED** |
| `highest_bidder_id` | **DENIED** |
| `current_bid` inconsistent with `starting_bid` | **DENIED** |
| `bid_count` | **DENIED** |
| `auction_status` | **DENIED** |
| `status` | **DENIED** |
| `reserved_by` | **DENIED** |
| `reserved_until` | **DENIED** |
| `sold_at` | **DENIED** |
| `ended_at` | **DENIED** |
| backdated `created_at` | **DENIED** |
| **full forged-auction tuple** (`ended` + victim `winner_user_id` + `winning_bid_amount` 24999 + `bid_count` 17 + `ended_at`) | **DENIED** |

> **A test defect found and corrected mid-verification, recorded rather than hidden.** The first
> `current_bid` attempt failed with `42701: column "current_bid" specified more than once` — my
> harness listed the column twice. That is a harness error, not a guard result, and it would have
> been dishonest to count it. It was re-run specifying the column exactly once (`current_bid` 4242
> vs `starting_bid` 1000 → **DENIED by the guard**) together with a **matched positive control**
> (`current_bid` = `starting_bid` = 777 → **ALLOWED**), which proves the denial is about the *value*
> and not about the column being present.

### Legitimate paths — all still work

| Path | Result |
|---|---|
| Ordinary seller listing creation (`current_bid = starting_bid`) | **ALLOWED** |
| Buy Now listing creation (seller-set price fields) | **ALLOWED** |
| `service_role` seeding server-controlled columns (ALLOW 1) | **ALLOWED** |
| Claims-less operator session seeding (ALLOW 2) | **ALLOWED** |
| 071 `proof_status` protection still fires on INSERT | **DENIED** with `proof_status can only be changed by Snatch It review` ✓ |

### `complete_auction_payment()` can no longer be influenced through forged INSERT state

`complete_auction_payment()` reads `winner_user_id`, `winning_bid_amount` and `auction_status` from
the listing row. All three are individually rejected at INSERT, and the **combined tuple** — the
exact shape that would make a forged listing look like a won auction — is rejected as a unit.

The pre-fix impact this closes: `supabase/functions/create-payment-intent/index.ts` L320–326 gates on
`listing.winner_user_id !== buyerId` then prices from `winning_bid_amount ?? current_bid`, so a
forged INSERT served a **targeted victim a real Stripe PaymentIntent** for a listing they never bid
on, while `app/(tabs)/bids.tsx` showed them "WON". It was silent, because
`trg_notify_auction_won_inbox` is `AFTER UPDATE OF winner_user_id` and never fires for a row that
*arrives* carrying a winner. **That entire path is now closed at its only entry point.**

## 5. Scope discipline

Confirmed **not** done: `073` not applied · no Phase-2 implementation · no RLS modified · Stripe
untouched · no payout logic changed · guard not weakened.

`072` altered no existing function, trigger, policy, grant or column — Gate-2 moved by exactly
`+1 function, +1 trigger`, and money-table row counts are unchanged.

## 6. Rollback

`supabase/rollbacks/072_fix_listing_insert_guards_rollback.sql` drops the trigger and the function.
It is **exact rather than approximate**, and honestly so: 072 was purely additive, so there is no
prior definition to transcribe — before 072 neither object existed. The file states plainly that
running it reopens a HIGH, and names the most likely reason someone would reach for it (a legitimate
creation refused, surfacing as `Cannot set server-controlled listing columns on insert.` with a
`DETAIL` naming the column).

## 7. Remaining, and explicitly not covered by this approval

- **`073` (DRIFT-1)** — authored, reviewed, CI-green, **NOT applied**. It requires its own
  owner-authorization package: finding id, severity, exploitability, affected production paths, why a
  separate migration, contents, RED→GREEN, rollback, replay, pgTAP, adversarial review, blast radius.
- **Phase-2 six-feature amendment** — backend consolidation remains **held** pending four owner
  rulings (refund authority · venue role catalog · `org_owner` payout read/request mismatch · door-manifest
  open/close authority), plus the newly recorded missing contract: `catalog.event_session.door_open_at`
  is canonical to the offline transfer/refund freeze but has **no authoritative write lifecycle** in
  the frozen specs. That lifecycle must not be silently invented, and the Apple Wallet spec must state
  that its stale-pass / offline-door safety guarantee depends on it.
- **Doc drift on `main` (cosmetic, non-blocking):** `supabase/tests/README.md` on `main` still lists a
  third pinned `todo()` for the `proof_status` fail-open, which `071` fixed. The corrected text is in
  PR #22. The test files themselves carry exactly 2 `todo()` markers — CI's ratchet confirms it.
- **Open findings unchanged by this apply:** MONEY-1 (Medium, not exploitable, hardening deferred) ·
  F-2 / F-3 · the `buy_now_price` re-pricing gap (severity **unknown** until the pre-all-in installed
  base is measured) · `strict_required_status_checks_policy: false`.

---

## Verdict

**072 H-1 CLOSED IN PRODUCTION.**

The live forged-INSERT vulnerability on `public.listings` is closed at its only entry point, proven
by thirteen denied attack vectors and five working legitimate paths against the real production
database, with no user data touched. Ledger 86, source and ledger exactly equal, backup intact,
auto-deploy still off, and production running byte-for-byte the tree that was reviewed.

`073` remains a separate, owner-gated migration and does not inherit this approval.
