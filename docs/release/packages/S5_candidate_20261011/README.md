# S5 combined candidate: A's §5.3 checks (A, 2026-10-11)

These are local checks and a CI trial only. Nothing has been merged into the gate or `main`, and nothing has been
deployed. S5 (`v3/midnight-app` → gate), S7 (gate → `main`) and distribution (G2/X11) each remain the owner's approval.

## The trial merge

- **Trial:** `integration/s5-trial-20261011` @ `9ed130d5`, a merge commit whose parents are the gate `abef9506` and
  `v3/midnight-app` `9bbeaec6`. Its tree is `c49160cf`. The branch is marked "test only, never merge".
- **Clean.** There are no conflicts. 0 of the 1805 blobs in the result are new to either parent, so the trial publishes
  nothing that was not already on origin.
- **Changed-surface inventory (§5.3 item 1).** `app/` and `src/` in the merge result are **identical to `9bbeaec6`**,
  the tip B and E reviewed.
  - The gate had changed `src/lib/checkout/holdState.ts` and `src/screens/checkout/CheckoutNative.tsx`: the three
    2026-09-19 escrow-line commits, `bbd3e1bf`, `9eebcac2` and `19b6fc2b`.
  - v3 rewrote both files. The merge resolves them to v3's versions **byte for byte**, so v3 already carries that
    behaviour; `showEscrowNote` is present at `9bbeaec6`.
  - S5 adds to the gate: `src` (94 files), `tests` (98), `app` (42), `native` (16), and `tools`, `assets`, `docs`,
    `scripts`, `packages`, `components` and `package.json`.
  - The gate adds to v3: `supabase` (38), `tests` (8), `scripts`, `docs` and `.github`. v3 changes nothing under
    `supabase/`.

## CI at the combined candidate (§5.3 item 2): GREEN at trial r3 (2026-10-11 18:06Z)

**r3:** `integration/s5-trial-20261011-r3` @ `5450b348`, the gate `abef9506` merged with v3 `d27aa449`. It is clean,
`app/` and `src/` are identical to `9bbeaec6`, and it adds 0 new blobs. Run
[38162239127](https://github.com/SnatchIt-app/snatchit/actions/runs/38162239127): all five jobs succeeded, and every
step was confirmed to execute:
- unit tests: 182 files / 3,084 tests;
- parity: 3 files / 108 tests, including `domain-parity` (11);
- pgTAP: 98 files / 5,605 tests.

r1 (below) and r2 (`4f162c24`, red on the parity load error that ML7 had hidden) are kept as record.

### r1 (history): RED, with one failure that predates the merge

Run [38159624076](https://github.com/SnatchIt-app/snatchit/actions/runs/38159624076) on `9ed130d5`:
- Migrations (fresh DB), Deno, Web build and Admin console: **success**.
- **Typecheck / Lint / Unit tests: failure**, from exactly one test:
  `tests/v3-mylistings-bids-stage.test.ts` › SellerListingCard › **ML7**.
  - Expected `"Sold Sat 17 Oct"`; received `"Sold Sun 18 Oct"`.
  - The input is `2026-10-17T21:00:00-04:00`, which is 01:00 UTC on 18 October. `soldOnLabel` formats in the
    runner's local zone. The CI runner is on UTC; the developer Macs are on UTC−4. So the test passes in Eastern time
    and fails in CI.
- **This is not caused by the merge.** `v3/midnight-app`'s own CI has failed the same way on every push since at
  least 2026-10-07:
  - [38028668549](https://github.com/SnatchIt-app/snatchit/actions/runs/38028668549) at `9bbeaec6`: the same ML7
    assertion; 1 of 178 test files fails;
  - `c11b4a49`, `9498080a`, `3c03778a` and `91a5a58c`.
- **Owner of the fix: C.** Either the test pins a timezone, or `soldOnLabel` formats in a fixed zone. Which zone the
  product should use for "Sold <day>" is C's call, or the owner's. After the fix, the trial must be re-merged and
  re-run.

## The static client-read check, C4 (§5.3 item 3): PASS at `9bbeaec6`

Tool: `c4_client_read_check.py` (this folder).
- **Source:** `git archive origin/v3/midnight-app@9bbeaec6` (`app/`, `src/`, `packages/`; tests excluded).
- **Schema:** the local `pkg151_rehears` clone at ledger 164, the same ledger as production after 150/151.
- **Resolved automatically:** 63 `.from()` chains and 25 `.rpc()` calls. That covers tables, selected and embedded
  columns, filter columns, `insert`/`update`/`upsert` keys, RPC names and every argument name. **MISSING: 0.**
  Output: `out/c4_run_9bbeaec6.txt`.
- **Positive controls.** Five planted defects in a copy were all caught, each with its own message: a column, a table,
  an RPC argument, an RPC name, and a **second** RPC argument (`out/c4_mutants.txt`).
  - The first two versions of the tool had bugs, both caught this way. One read no arguments at all; the other checked
    only the first key of an argument object. Both are fixed, and the second-key mutant (M5) proves the fix.
- **16 dynamic sites, resolved by hand. All exist in the production schema.**
  - `get_my_security_notices()` and `mark_security_notices_read(p_ids)`.
  - `revoke_push_token(p_token)` and `revoke_all_push_bindings()`.
  - `mark_listing_sold` and `complete_auction_payment`, each `(p_listing_id, p_user_id)`.
  - `register_push_token(p_token, p_platform, p_device_secret, p_device_name)`.
  - `push_tokens` `{user_id, token, platform, is_active, last_used}`.
  - The six `notification_preferences` toggles.
  - `LISTING_SUMMARY_COLUMNS`: 8 `listings` columns.
  - `BIDS_SELECT`: `*, profiles(display_name, avatar_url)`, over an FK from bids to profiles.
  - The three `src/lib/venue/client.ts` helpers (`schema('venue'|'catalog'|'kernel').rpc(fn, args)`) are imported
    by nothing outside `src/lib/venue/`, so they are **unreachable in this build**.
- **Limits:**
  - This checks existence, not column privileges or RLS.
  - The schema is the ledger-164 rehearsal clone, not a fresh production read.
  - It covers `9bbeaec6` without S6. If 152 and C's blocking client half join the candidate, rerun it.
  - **D verifies C4 (§5.3 item 6).**

## §5.3 status at the storage closeout (A, 2026-10-11)

- **Items 1, 2 and 3: done** (above). C4 carries over to `d27aa449`: outside `native/9bbeaec6/` evidence, the only
  changes since `9bbeaec6` are `tests/v3-mylistings-bids-stage.test.ts` and `packages/vitest.config.ts`. Neither
  reads from the database.
- **Item 5, delta acceptance: done.** B's narrow review of the four default-size frames passes (`92356c9e`, recorded
  by E at `c16c2d8f`). The ML7 fix touches only a test.
- **Item 4, a native build of the candidate from a fresh install (C/B): OUTSTANDING.** The native evidence so far
  is simulator development-build captures. No record shows a fresh-install build of `d27aa449` or `9bbeaec6`, and
  the captures are not taken as one.
- **Item 6:** D's verification of C4. Owed.
- **Item 7:** G2, an EAS production build from the exact candidate sha. In the owner's release queue
  (`RELEASE_READINESS_20261011.md`).
