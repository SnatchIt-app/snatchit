# D — independent security, migration and transaction-safety review of migration 152 @ `6a02519d` (2026-10-13)

**Who / how assigned:** Claude D, session `9651e05a` (fork). The assignment reached me through A's message (A: "owner-directed,
2026-10-13"); I did not receive it from the owner directly, and `sprint-control/ASSIGNMENTS_RC3.md` did not yet exist when I
started. It matches the pre-registered plan (FINAL_INTEGRATION_PLAN D2 / STATUS.md: "A writes 152 … D reviews") and stays inside
my standing authorisations: read-only review, local tests on a throwaway clone, a record on my branch. **Not done:** nothing
applied to production, no merge, no settings change, no production read.
**Keyed to:** `fix/rc3-marketplace-safety-20261013` @ **`6a02519dcd441e49420149d961295946f4d458d2`** (parent `e2b9498b`, the frozen
RC2; 8 files, +1,581/−7). The changed tree is a new identity (RC3); RC2's verdict (`1e6e1e82`) is unchanged.
**Method:** code reading of the migration, rollback, pgTAP 219 and the CI/census/parity changes; a local clone
`d_152_rehears` created with `createdb -T pkg151_rehears` (the approved ledger-164 reference, untouched); apply → census → tests →
negative control → rollback → re-apply → rollback-with-history on that clone; catalog reads of the reference for the coverage
enumeration. Raw outputs: `private-evidence/D-session-9651e05a/m152_6a02519d/`.

## 0. Verdict line
**No blocking defect. Migration 152 at `6a02519d` is safe to carry into RC3 as written.** Six follow-ups, none gating (§9).

## 1. Identity, CI, ordering
- `6a02519d` is the tip of `origin/fix/rc3-marketplace-safety-20261013`; `git diff --stat e2b9498b 6a02519d`: the migration (730
  lines), its rollback (473), pgTAP `219` (318) and the `162` census pin, `ci.yml` (`EXPECT_FUNCS 111→116`, `EXPECT_TRIGGERS 40→43`),
  five `no-client-execute` grant-decision rows, `tests/server-content-parity.test.ts`, the one-word `export` in `sellState.ts`.
- **CI run 38347870842**: `headSha 6a02519d…`, `conclusion success`, 5/5 jobs (Typecheck/Lint/Unit, Migrations fresh DB, Web build,
  Admin console, Deno), 0 non-success steps.
- File order: `20261013000000_…` sorts after `20260925010000` (the newest applied file) **and after** the parked
  `20261011000000` (153) under `LC_ALL=C` — a fresh replay applies it last either way.
- **`docs/release/MIGRATION_NUMBER_REGISTRY.md` at `6a02519d` has no 152 row** (F-152-1).

## 2. Q1 — coverage: does any path that creates a NEW bid, Buy Now reservation, listing or listing-text edit escape?
**No path found.** Evidence:
- **Bids.** The guard is a `BEFORE INSERT` row trigger on `public.bids`, so it fires for every writer regardless of role or RPC. No
  SQL function inserts into `bids`: `pg_proc` search for `insert into (public.)?bids` → 0 (positive control: the same search for
  `transfers` → 3; 8 functions mention `bids` — `validate_and_apply_bid`, `finalize_auction`, notifiers, `ops.listing_detail`,
  `admin_relist_listing`, `get_profile_trust_stats` — none inserts). App (`PlaceBidScreen.tsx:241`) and web (`web/src/lib/bids.ts:19`)
  insert directly. 219 I9 shows the service path is refused too. A's statement holds.
- **Buy Now reservations.** `BEFORE UPDATE OF status, reserved_by` trigger acting only when a reservation is **created** (status
  becomes `reserved`, or the holder changes). Nine function bodies update `listings` with `reserved_by`; by reading each: only
  `reserve_buy_now` assigns `reserved_by = v_caller_id` and `status='reserved'`; `cleanup_expired_reservations`, `release_reservation`,
  `release_reservation_for_payment`, `cancel_listing`, `delete_account_cleanup`, `settle_listing_for_payment`, `admin_relist_listing`,
  `kernel.sweep_deletion_pending` set it to NULL / `active` / `sold`. `create-payment-intent` only reads the hold. A's "only writer"
  claim holds, and the trigger covers any future writer.
- **Listings create and text edits.** `BEFORE INSERT OR UPDATE OF event_name, venue, restrictions`. No SQL function inserts into
  `listings` except the test fixture `tap.seed_core`; none sets `event_name|venue|restrictions`. Client payloads: app edit writes
  exactly `event_name, venue, restrictions, ticket_platform` (`edit/[id].tsx`), create writes the full row; web writes the same
  three text fields. **Every other seller-editable text column is enum-constrained** (`category`, `neighborhood`,
  `ticket_platform`, `ticket_type`, `transfer_method` CHECK lists) — no free-text column escapes the check. The app's own gate
  checks the same three fields (`findBannedContent([eventName, venue, restrictions])` at `CreateListingScreen.tsx:513`,
  `edit/[id].tsx:146`). `UPDATE OF` fires when a listed column is in SET even if unchanged; the function returns early when all
  three are unchanged, so settlement/system writes pass (219 I8).
- **Exclusions — both right.** `market.place_bid` raises `precondition_failed: native_auction_not_offered` unconditionally (body
  line 4); `market.create_listing / checkout_buy_now / make_offer / respond_offer` are gated on `catalog.platform_config`
  `feature.native_resale_enabled` (false, v1, in the reference clone; the production value is A-reported); **no caller of any
  `market.*` function exists in `app/`, `src/`, `web/src` or `supabase/functions`**. Venue primary checkout: `src/lib/venue/client.ts`
  has no importer outside its own directory (re-verified at `6a02519d`); `venue.*` writes its own tables, not `public.bids/listings`.
  The header's caveat (add the rule before either rail opens) is the right one.

## 3. Q2 — transaction safety: nothing committed is touched or stranded
- The migration contains **no DML** on `bids`, `listings`, `transfers`, `payments`, refunds or payouts — only DDL and function
  bodies. Post-apply trigger inventory: the three new triggers sit on `bids` and `listings` only (219 J1 and my `pg_trigger` listing).
- **md5 of `pg_get_functiondef` before/after apply** for `complete_auction_payment`, `mark_listing_sold`, `settle_listing_for_payment`,
  `reserve_buy_now`, `validate_and_apply_bid`, `release_reservation`, `cleanup_expired_reservations`, `ops.execute_action`,
  `ops.action_allowed_roles`: **identical**; only `ops.action_dispatch` and `can_create_listing` changed. `complete_auction_payment`
  is unchanged (219 J3 adds that it mentions neither `user_blocks` nor `user_restriction`).
- **Re-calling reserve on one's own live hold:** `reserve_buy_now` locks the rows `FOR UPDATE` (body :19-21), clears expired holds
  (:27-28), and `IF v_reserved_by = v_caller_id AND v_reserved_until > now() THEN RETURN` (:53-54) **before** the `UPDATE` at :73 that
  the guard watches — so a hold taken before a block/suspension completes (219 E3/E4), and a **lapsed** hold is a new reservation
  and is refused (E5). Atomicity bonus: the caller's *other* holds are released at :68-69 in the same transaction, so a refused new
  reservation rolls that release back too — nothing is half-done.
- Pre-existing bids stand (G9); orders keep their states (G10); a refused edit writes nothing (G11).

## 4. Q3 — `ops.action_dispatch`
- Pre-apply body carries 144's markers; **diff pre→post = 3 hunks (`282a283,305`, `284c307`, `303a327,340`), 39 lines, every hunk
  inside `when 'user_restrict'` or `when 'user_unrestrict'`**; nothing else moved.
- **Authority.** `ops.action_requires_approval` = `payout_release, refund_execute` only, so a suspension is **not two-founder gated**:
  it executes immediately in the requester's session. `action_allowed_roles('user_restrict')` admits support (for `listing_blocked`),
  and the `suspended` kind re-checks `ops.actor_role()` (the executing session's platform role via `kernel.is_platform`) ∈
  {`platform_admin`, `platform_risk`} — support refused (F3), self refused (F5), reason required by `execute_action` (:61-64; F6),
  unknown user refused, profile existence required. Who/when/why land on `ops.user_restriction (actor, created_at, reason)`,
  `ops.action` and `ops.audit` (F7–F9).
- **Double suspension** → `stale_state` via `ON CONFLICT DO NOTHING` + `row_count`, which depends on
  `user_restriction_active_uidx UNIQUE (user_id, kind) WHERE lifted_at IS NULL` — present in the reference.
- **Unrestrict `kind=suspended` lifts only that kind:** `UPDATE … WHERE user_id=… AND kind='suspended' AND lifted_at IS NULL`;
  `seller_risk_scores` untouched (a suspension never sets `is_listing_blocked`, F test; a lift never clears it). `user_unrestrict`
  is admin/risk by `action_allowed_roles` (H1 support refused). History kept with `lifted_by/lifted_at/lift_reason` (H4).

## 5. Q4 — privacy
- Three refusal texts; **none names a direction**: the same sentence "This listing isn't available to you." is raised whether the
  actor or the counterparty placed the block (219 C/D both sides; D5 pins the text), with `HINT BLOCKED_PARTY`. The order of checks
  (actor suspended → block either way → counterparty suspended) means a blocked bidder never learns the seller is suspended.
- `public.user_blocks` RLS **unchanged** before/after apply: one policy `user_blocks: owner all`, `ALL`, qual and check
  `blocker_id = auth.uid()`; RLS enabled. The guards are `SECURITY DEFINER`, `search_path = ''`, fully-qualified reads, and return
  nothing but the refusal. Grants: the five new functions are executable by `postgres` and `service_role` only (REVOKE from
  PUBLIC/anon/authenticated took effect; `proacl` read).
- Inherent, by design: distinct HINTs (`BLOCKED_PARTY` vs `LISTING_UNAVAILABLE`) tell an actor *that* a block exists in some
  direction, or that a seller is unavailable — unavoidable for any enforcement.

## 6. Q5 — locks and ordering
- `BEGIN; SET LOCAL lock_timeout = '3s'` ✓; the constraint swap is `DROP CONSTRAINT IF EXISTS user_restriction_kind_check` +
  `ADD` in the same transaction — **the name matches the live constraint** (115's inline check got the default name
  `user_restriction_kind_check`; verified in the reference), so the DROP is not a silent no-op and no second check is left behind.
  `ACCESS EXCLUSIVE` on the small `ops.user_restriction`; `SHARE ROW EXCLUSIVE` for the three `CREATE TRIGGER`s; a 3 s wait fails the
  whole file cleanly (one transaction).
- **Order:** after apply `min(tgname)` on `bids` = `before_bid_guard_parties` (219 A3 and my query): the refusal fires before
  `validate_and_apply_bid` locks or updates the listing. On `listings` the new guards sit between `guard_listing_state` and
  `trg_guard_listing_seller_not_blocked` alphabetically; since every guard only raises or passes, their relative order cannot change
  an outcome.
- **Concurrency:** under READ COMMITTED a block or suspension that commits between a guard's read and the activity's commit lets
  that one activity through — exactly the header's "applies to activity that starts after it commits". Inside `reserve_buy_now`
  the guard runs after the `FOR UPDATE` row lock, so two buyers cannot both reserve; the window is only about the restriction
  tables. **No gap beyond the documented class found.** (`assert_marketplace_parties` is `STABLE`, correct for a per-statement read.)

## 7. Q6 — rollback, independently confirmed
On the clone: apply → rollback → **md5 of `ops.action_dispatch` and `can_create_listing` (and the whole unchanged set) identical
to pre-apply**; the five functions and three triggers gone (0 remain); census back to 111 / 40; the kind check narrowed to
`('listing_blocked')` when no `'suspended'` row exists. **Re-apply → md5 identical to the first post-apply** (exact). With a
`'suspended'` row present: rollback keeps the row, leaves the check widened and prints `NOTICE: 152 rollback: suspension history
exists; kind check left widened, rows kept`; a further re-apply over the widened check exits 0. The migration itself is idempotent
(`CREATE OR REPLACE`, `DROP … IF EXISTS`; second apply exit 0).
**Wording:** the rollback file's own header is adequate and complete — "blocks are a client-side hide again, recorded suspensions
are NOT enforced, and listing text is checked only by the app. Lift recorded suspensions through the console first, or re-apply
152." The **migration** header's ROLLBACK line mentions only suspensions — align it (F-152-3).

## 8. Q7 — tests and CI
- CI 38347870842 green on `6a02519d` (§1). Local, on the applied clone: **219 = 73/73** (`1..73`, 0 psql errors); **162 census pin
  = 86/86** at 116/43; the three guards disabled → **24 of 73 fail** (`C2 C3 C5 C6 C9 C10 D3 D4 D5 D6 E5 G1 G2 G3 G4 G7 G8 G9 G11 I1
  I2 I3 I4 I6`), re-enabled → 73/73. A reported 25 for the same control; the one-assertion difference is immaterial (every
  enforcement assertion trips either way) and likely a counting difference (F-152-5).
- Not rerun by me: the other 96 pgTAP files and the vitest suite (CI green; light-job rule) — the parity test
  (`server-content-parity.test.ts`) was read: it pins the ten `(pattern, label)` rows app ↔ server after `\y→\b`, order and the `i`
  flag, and runs each label through the app gate.

## 9. Findings
**Blocking: none.**
Follow-ups (not gating RC3):
- **F-152-1 (docs):** `MIGRATION_NUMBER_REGISTRY.md` has no 152 row at `6a02519d`; the file header says "registry 152".
- **F-152-2 (consistency, server-authoritative):** the web's client gate `web/src/lib/content-moderation.ts` is a **substring**
  match over its own 11-string list (`lower.includes(term)`): it does not catch `drug` (singular) or `open-bar`/`bottle-service`
  (hyphenated), which the server does, and it over-blocks `Weedon`, which the server allows; its comment "no server-side mirror on
  either platform" is now stale. The parity test covers app ↔ server only. Extend parity to the web list (or have web call the
  server's answer). No safety impact: the server refuses what the web lets through, and web shows the server sentence as-is.
- **F-152-3 (wording):** migration header ROLLBACK line narrower than the rollback header (§7).
- **F-152-4 (for the owner's awareness, not a defect):** suspension is a single-session action by `platform_admin`/`platform_risk`
  (reason required, audited), not two-founder gated like payouts/refunds. Consistent with the design brief; stated so it is not
  assumed otherwise.
- **F-152-5:** negative-control count 24 (mine) vs 25 (A's) — record both; immaterial.
- **F-152-6 (observation):** a suspended seller's live listings stay visible while new bids/reservations on them are refused with
  "This listing isn't available right now." — as the header states; the named follow-up (auto-release holds / hide listings of a
  suspended seller) remains open and is the owner's.

## 10. Process
- Clone `d_152_rehears` (from `pkg151_rehears`, which was not modified) used for every apply/rollback/test; dropped after this record.
- Before pushing, every blob version and commit message in the outgoing range was scanned with the standing pattern set and
  positive control; a scanner error would be a failed check. Result: first pass `scanned 1 commits, 1 blob versions, hits=0`, positive control tripped as required; the amended final version was re-scanned before the push and that result is the push note in `sprint-control/D-HANDOFF.md` — if absent, the push did not happen.
