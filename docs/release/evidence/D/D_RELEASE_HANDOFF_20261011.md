# D — independent release handoff, and closure of the reconciliation witness

2026-10-11, from the SSD. No production writes, settings changes, refunds, payouts or deployments.

## 0. An error of D's own, found by the inspection the owner asked for

The owner asked D to inspect before pushing and to keep published records sanitised. **The inspection
found that D had re-leaked the data it removed the day before.**

`78d9572a` (`D_STRIPE_EVIDENCE_20261010.md`) transcribed both real Acquirer Reference Numbers from the
refund objects' `destination_details.card.reference` into a **public** repository — the exact values
D had rewritten out of history on 2026-10-10, reintroduced by D in the course of recording the Stripe
evidence.

**Fixed:** values redacted, history rewritten over the five affected commits, force-pushed with
`--force-with-lease`. Verified **0** ARN-bearing commits on `origin/review/d-records-20261005` after a
re-fetch, with the retained local backup returning 1 as control. Remote tip `35c3e0f3`, matching local.

**The consequence D cannot undo, and must disclose.** The **already-executed, owner-approved**
correction files carry an evidence line citing `D blind check 78d9572a`. That commit no longer exists
on the published branch. The files themselves are untouched and their approved SHA-256 remains valid —
but the pointer inside them no longer resolves publicly. Mapping:

| cited | now | content |
|---|---|---|
| **`78d9572a`** | **`99e5cdea`** | D's independent Stripe reads (ARNs redacted, findings unchanged) |
| `45fbe3dd` | `fefb83a9` | D's verdict on the filled files |
| `62829249` | `f83c9bb9` | D's witness of the R3 execution |
| `1046b78e` | `6b9da194` | completion of that witness |

**The lesson, stated at full strength:** D had already written down that a redaction in a new commit
does not remove anything from history, and had already rewritten these ARNs out once. Then D put them
straight back while writing up the evidence, and only caught it because the owner's instruction forced
another inspection. A rule learned and recorded did not survive contact with the next task — which is
the same failure mode as the zsh word-splitting trap D hit three times. The durable fix is not another
note: it is to scan before every push, which is now the only reliable control.

## 1. Reconciliation witness — closed at its actual strength

**Both writes are correct, complete and confined to the two approved records.** Every value D
pre-registered matched, including two derived from reading the code rather than from rehearsal:
`refunded_at` preserved to the millisecond, and the detector's `items_scanned` unchanged.

**The timing limitation stands and is not softened.** D holds a clean independent prestate for **#7**
(`700d469b`, $2.20) taken minutes before it was written. For **#6** (`32913315`, $11.00) D's nearest
independent prestate is the verdict-stage read of **2026-10-10** — a day stale — because D's first
prestate query was malformed and the corrected read landed after the write. What backs #6 is the
file's own atomic prestate guards, which would have refused on drift. **That is the mechanism working,
not D observing it**, and the witness is recorded at that strength. D's timing failure, not A's.

**The subsequent detector run is not validation.** At 16:35:00Z `refunds` scanned **2** and opened
**0** — identical to 288 runs before detection was enabled and 255 after. A `succeeded` row is selected
by neither gated loop. **Nothing about refund-state detection was demonstrated by this reconciliation**,
and no record should imply otherwise.

**The five test-mode payments remain excluded and untouched:** all `amount_refunded_cents` NULL, cents
0/0/0, zero refund-state rows each. **Not to be expanded.**

## 2. VERIFIED — D's own reads, each with a control

| area | result |
|---|---|
| Console deployment | live on the reviewed commit `f7e7e85f`; both production aliases moved; a **38.6 s** build against 3.2 s and 2.8 s skips proves the pin was evaluated |
| Web wording | deployed via #97; serving deployment and rollback target confirmed before the merge |
| Migrations 150 / 151 | applied; ledger 162→164; census 32\|108\|37\|38 → 34\|111\|37\|40 |
| Edge function deploys | verified against frozen source by **D's own downloads**, with previous-manifest controls |
| O-R2 setting | `true`; **only** the authorised key moved, checked against the frozen post-151 expectations (`ops_setting_rows` 14) |
| Audit chain | requested → succeeded → stored value, with a September control proving the table discriminates |
| Owner sign-in | login 23:48:03 → **verified TOTP** challenge 23:48:42 → setting change 23:54:39, **same account** |
| Stripe webhook endpoint | full **13/13** event list read directly; the three refund events subscribed; one endpoint, enabled |
| The two refunds | ids, `succeeded`, 1100/220 usd, created, no failure reason; **count 1 each, conclusive** (`has_more false`) |
| Live mode | `livemode: true` from Stripe on both PaymentIntents and the charge — our own column externally validated |
| R3 execution | §1 |
| Webhook ledger gap | **explained and benign** — no events in retention, and the only 2 live PaymentIntents since were abandoned before payment |
| Seller fee | **0** affected, with 8/8 live payments carrying one as control |
| Branches | four published, sanitised, SSD and GitHub in sync |

## 3. WAIVED — the owner's decision. Recorded as waived, **not** as passed

- **Rendered web wording** on `/account/purchases`, `/account/sales` and one transfer screen.
- **Authenticated console label rendering** on the deployed build.
- **VoiceOver** — explicitly optional and **not a release blocker**.

No record may later describe any of these as verified. They were not tested by anyone.

## 4. UNEVIDENCED — distinct from waived, because nobody waived it

**Refund-state detection has never fired in production.** It is **on**, the owner works a daily queue,
and no case has ever been opened by it. The mitigation is real but indirect: A's rehearsal includes a
positive control showing a `failed` state row opens exactly one `refund_failed` case. So the mechanism
is demonstrated **locally**, never in production.

D's assessment: **a live operational gap, not a release blocker.** It becomes evidenced the first time
a refund is genuinely pending or failed — or sooner, if the hardening item in §5 is done.

## 5. OPTIONAL HARDENING — none blocking, in rough order of value

1. **F-DETECT-REFUNDS-UNOBSERVABLE-1** — have `ops.detect_refunds` record `state_on` in its `detail`,
   as `refund_resolution` already does for its skip reason. Converts a run log that proves nothing into
   one that shows the gated branch executed, and is the cheapest route to closing §4. **It changes a
   SQL function, so it is a migration**, not console work: four-file set, rollback restoring 150's body,
   owner-gated apply, number through A. D implements when scheduled.
2. **F-CONSOLE-SETTING-STALE-1** — the console settings panel kept showing the old value after a
   succeeded change. Data was always correct; the display lagged. Requires a negative control, since a
   panel that re-renders for another reason would pass a naive test. D's lane.
3. **F-MODE-BOUNDARY-DUPLICATED-1** — one money boundary implemented three times
   (`rowIsLiveActionable` with a single call site, plus two independent equivalents). They agree today;
   three implementations can drift. A full enumeration of edge money paths has **not** been done.

## 6. NOT blockers

VoiceOver (owner: optional). The five excluded payments (owner ruling, closed). The webhook ledger gap
(explained). The redaction incident in §0 (resolved; published records clean).

## 7. Pending the owner, not defects

The **final merge to `main`** has never been authorised, and `AUTODEPLOY-1` governs it — merging applies
pending `supabase/migrations/**` to production outside CI. Scheduling of the three §5 items is also the
owner's.

## 8. Preservation

- Private originals, **local only, never pushed**: `review/d-records-PREREWRITE-BACKUP` (`f70ca9d9`)
  and `review/d-records-PREREWRITE2-BACKUP` (`1046b78e`). Both hold the real ARNs; both confirmed
  absent from every remote.
- Published records sanitised: **0** ARN-bearing commits on the remote, re-verified after fetch.
- Mac originals untouched; no deletions.
- All four D branches in sync between the SSD and GitHub.

## 9. D's answer on release blockers

**From D's lane: none.** The console and web releases are live and verified; the reconciliation is
closed; the excluded set is settled; the ledger gap is explained. What remains is one unevidenced
behaviour (§4), three optional hardening items (§5), three waived checks (§3) and one owner decision
(§7). D reports no unresolved blocker rather than manufacturing one.
