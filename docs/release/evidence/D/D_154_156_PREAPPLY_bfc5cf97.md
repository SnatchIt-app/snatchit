# D — independent pre-apply review of migrations 154–156 (PR #110 @ bfc5cf97)

**Reviewer:** Claude D (independent release-safety review). **Date:** 2026-10-15, ~22:20–23:15Z.
**Subject:** `fix/154-listing-visibility-20261015` @ `bfc5cf97b15bf1eed524633de93e3e9c93cc1630` (PR SnatchIt-app/snatchit#110 into
`release/production-gate-20260918` @ `6f982f36`), package `docs/release/packages/154_20261015/`.
**Verdict sent to A: PASS-WITH-NOTES.** No STOP condition was found. Nothing here authorises an apply; each step is the owner's.

## Limit, stated first
D made **no production read**. The owner had not answered D's read question in D's own chat, and a peer cannot pass that
authorisation on. The predicted states were therefore checked against A's logical backup, snapshot `0000002F-000261A7-1`
(2026-10-15 22:21:02Z), only. The package runner re-reads all 79 state keys live before every step, so a drift since the
snapshot makes it stop (exit 3, nothing sent).

## Method and results
1. **Identity.** The six frozen files pass `frozen.sha256`, are byte-identical to their `supabase/` copies and match the README md5s.
   `MODE=DRY` reproduces every request byte for byte (the README sha256 table and the committed `rehearsal/out/`). `pkg.py` is
   `305d2739…`; its diff against the executed 152 runner (`02537f62…` on `origin/release/candidate-20260918`) is limited to the
   changes its docstring lists. A's private production wrapper pins that hash, a clean package directory and HEAD `bfc5cf97`.
   CI on #110: the first "Immutability + ordering" run failed only because the PR body lacked the AUTODEPLOY-1 line; the rerun
   (38816342986) and every other check are green.
2. **Predicted pre-state vs the snapshot.** The dump was restored into a local PostgreSQL 17 scratch database (checksums 26/26 OK;
   no restore error other than missing Supabase-internal roles). `pkg.py check expected/pre154.txt` (LOCALDB, the identical code
   path): **77 of 79 keys equal.** `owner_role` differs only because the local `postgres` is a superuser; A's role inventory at
   the same snapshot shows production `postgres` as non-superuser with BYPASSRLS, which is the predicted value. `storage_policies`
   cannot be checked offline (the storage schema is not in the dump); only the runner's live prestate covers it.
   *Method note:* a first restore showed two extra grant differences caused by the local shim's default privileges; they vanish
   when those defaults are cleared before the restore, so they were an artefact, not a finding.
3. **Predicted post-states, on real data.** On a copy of the restored snapshot, the package runner was driven through apply 154 →
   155 → 156 → `step hide` → `check post_hide` → unhide → hide → rollback 156 → 155 → 154 → a negative re-apply with kept rows,
   against A's **production** `expected/*` with only the two local-cluster keys above substituted. **12 of 12 exit codes as
   registered, 0 unexpected.** Every fixed money and listing hash stayed equal at every step; the hide step's own assertions passed
   on the real rows.
4. **Rollbacks restore the applied bodies.** A full catalog fingerprint (7,024 lines: every function's definition hash, ACL,
   settings and comment; policies; constraints; triggers; relation ACLs and RLS flags; columns and column privileges; indexes;
   publication membership; default privileges; types) was taken before, after each apply and after each rollback.
   156's rollback returns exactly the post-155 catalog; 155's returns exactly the post-154 catalog; after 156 → 155 → 154 the only
   difference from production is the deliberately kept `listing_visibility` table (and its rows). Archival data is kept: 154's
   rollback keeps that table; 155's refuses while any 72 h listing exists; 156's refuses while any waiver exists.
   The snapshot → post-156 diff contains exactly the objects the README lists and nothing else.
5. **Money untouched.** No statement in 154–156 changes an existing row; the data step inserts only `listing_visibility` rows.
   The fixed hashes (payments, transfers, payment refunds and refund state, payout attempts and decisions, disputes, bids, listings
   minus `updated_at` and the waiver columns) were equal before and after on real data.
6. **Hide-step preconditions.** The preimage equals the set of all listings in the snapshot; `hide_legacy.sql` embeds exactly that
   set plus one fixed non-party test subject that is not a user. The snapshot holds no state that the two-minute cron jobs act on
   during the window (no expiring transfer, no payment in processing, no recent pending payment, no reservation, no unfinalised
   auction, no pending account deletion).
7. **Producer and reader enumeration** (eight read-only sub-reviews; every non-informational finding re-verified adversarially on
   synthetic local clones, never on production data):
   - 155: no production function or client is refused or silently changed; the one function that moves `ends_at` arms the
     existing listing-guard bypass; clients never send `ends_at` or the duration on update.
   - 154: every listing writer, including settle, release, cancel, finalize, account deletion and the deletion sweep, passes on a
     hidden row; the visibility predicate covers every party column; no policy recursion; the role narrowing affects no
     operational role.
   - 156: every shipped listing creator sends a proof path or runs trusted; the trust test cannot be reached by a client; the new
     builds send the capability header on both the bid insert and the Buy Now reservation.
   - pgTAP 221/222/223 and the re-pinned 010/030/040/045/162/185/219 pass on the PR head.

## Notes sent with the verdict (none blocks the apply)
- **N1 (medium, documentation).** The 154 rollback states no client order for the next native build, which filters on
  `is_public`. Once that build ships, rolling 154 back breaks its discovery reads (400). It needs the same kind of client order as
  155/156 (a successor build or the owner's written acceptance), and the client-order check script should cover 154.
- **N2.** The README's native client gate names only 154; that build also needs 155 and 156 applied.
- **N3.** 155's rollback "end or migrate" step: ending a 72 h listing never clears the refusal, so after the first 72 h listing 155
  is effectively one-way. Two header wording inaccuracies are also noted.
- **N4 (0 production exposure).** Two wording gaps in the hidden-row invariant (an expired but unfinalised auction can be hidden and
  then finalised to its existing top bidder; a sold row with an active auction status is not treated as open). Neither state exists
  in the snapshot.
- **N5.** The 156 rollback counts waivers before locking, so a waiver committed during the rollback could be dropped; add a table
  lock at the next re-freeze. The documented client order removes the only waiver producer first.
- **N6–N8.** Record no waiver before the web release that shows the disclosure is live; the waiver reason is publicly readable, so
  the web form's hint should say so and the reason should stay neutral; a hide-step assertion failure surfaces as exit 5 (nothing
  commits).
- **N9.** The hide step asserts only zero visibility; the post-apply read-back should add a positive control that a seller and a
  buyer of a hidden listing still see their own rows.
- **N10.** Test gaps found by planted mutations, and minor items, are listed in D's private evidence.

## Evidence
Private (encrypted SSD): `private-evidence/D-session-9651e05a/pkg154_bfc5cf97/` — restore and sequence logs, catalog fingerprints,
sub-review results. All local scratch databases holding production rows were dropped after use.
