# D — independent post-apply read-back of migrations 154–156 and the hide step

**Reviewer:** Claude D. **Read:** 2026-10-15 23:52–23:55Z. **Verdict sent to A: VERIFIED in production, no discrepancy.**
Pre-apply review: `D_154_156_PREAPPLY_bfc5cf97.md` (PASS-WITH-NOTES). A applied 154, 155, 156 at 23:13:59–23:14:19Z and
the hide step at 23:15:50Z; D's pre-apply verdict had reached A at 23:13:29Z.

**Authorisation:** the owner, in D's own chat, for one read-only read-back. Every request started with
`SET TRANSACTION READ ONLY` and contained only SELECTs (Supabase MCP `execute_sql`); plus the read-only branch listing.

## Results
1. **State keys.** The package's own `sql/state.sql` and `sql/state_anon.sql`, sent verbatim: **89 of 89 keys equal
   `expected/post_hide.txt`** under the package's own comparison. This includes the storage-policy key that could not be checked
   before the apply. Ledger 168 with the three new rows. Each row's stored statement has the md5 and byte length of its frozen file.
   No unauthorised version is present. Census `35|126|37|49`; function definitions, execute grants, policies, triggers, the
   visibility table (RLS on, no policies, service-role only, ON DELETE RESTRICT, 113 rows) and ownership all match the predictions.
   No hidden listing is open or held, and none is live.
2. **No money or listing state moved.** Every fixed hash (payments, transfers, payment refunds and refund state, payout attempts
   and decisions, disputes, bids, listings minus `updated_at` and the waiver columns) equals the pre-apply prediction.
   *Negative control:* the same read compared with `expected/pre154.txt` differs only in the keys the migrations change, and in no hash.
3. **Visibility.** Anonymous and signed-in non-party callers see 0 listings and 0 bids.
4. **Private parties keep their history** (counts only; no identifiers recorded). Three distinct accounts were tested:
   - the most active account sees all its own listings, payments, bids and bid listings;
   - a second seller sees all its own listings;
   - other buyers see every listing they paid for, and all their transfers.
   Every count equalled the service-side total.
5. **Deploy path.** The production branch record's `git_branch` is still empty, unchanged since 2026-08-27.

## Evidence
Private (encrypted SSD): `private-evidence/D-session-9651e05a/pkg154_bfc5cf97/` (`D_POSTAPPLY_154_156_VERIFIED_20261015T2355Z.md`,
`prod_postapply_state_20261015T2352Z.txt`).
