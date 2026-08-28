# `ODR-16` / `O15` — Final Owner Brief

**Question as posed:** *"What should happen when a user requests account deletion while they still own or hold live ticket inventory?"*
**Corpus:** `phase2/consolidation` @ `c0d442f` · **Date:** 2026-08-28
**Method:** four independent read-only specialists — PostgreSQL/database mechanics, custody & ticket invariants, privacy & account deletion, adversarial product/security. No database contacted; no corpus file modified.

# VERDICT: **NOT READY TO RULE AS FRAMED.** Split it, and fix the deadline first.

---

## 0. The four findings that reframe the decision

All four reviewers converged on the first, independently, from different lenses. None was briefed to look for it.

### 0.1 The `auth.users` DELETE never succeeds — under A, B **or** C
For anyone who has ever transacted. The chain, each link read:

- `kernel.ticket_ownership_log`'s three identity columns are `ON DELETE RESTRICT`, the table is **append-only and permanent** — *"Never anonymized-by-deletion."*
- `kernel.tickets.current_owner_id` is `NOT NULL`, `RESTRICT`.
- **No engine moves the head off a terminal atom.** `mark_ticket_scanned` writes `state` only and appends no log row; the expiry sweep writes `state` *"and nothing else."* **Only a *voided* atom ever moves its head.**

So a fan who attended one show has a `scanned` atom pointing at them, permanently, plus three permanent log rows.

**The row is retained under all three options. The choice is only what happens to the inventory on the way there.** B and C are not alternatives to A — they are custody policies riding on top of it. Posing this as a three-way choice is what makes B look like a wait and C look like a way to actually delete. **Neither is true.**

### 0.2 The first blocker is `077`, not `079` — and the real inventory is 36 columns, which no document contains
`kernel.identity_ext.identity_id` is `PK, FK→auth.users ON DELETE RESTRICT`, and `identity_ext` is the 1:1 per-identity row. **Every identity with one is undeletable the day `077` applies** — two packages before the one this decision is filed against.

The full blocking set is **36 columns across 24 tables in 5 schemas** (`077`–`090`), of which **10 state no `ON DELETE` at all** and inherit RESTRICT by policy. `077` alone contributes 9. **No document in the corpus contains this inventory**, and every option's implementation is scoped by it.

### 0.3 There is an earlier failure still: the cascade cannot execute
`kernel.identity_contact_pref_event` and `kernel.org_contact_consent_event` carry `ON DELETE CASCADE` from `auth.users` **and** `raise_append_only()`, which raises unconditionally on DELETE. **A referential cascade is a real DELETE on the referencing table and fires row triggers.** `REVOKE DELETE` does not stop it; the trigger does.

So the DELETE aborts inside the cascade **for every identity, custody or none**, from `077` onward — before it reaches the RESTRICT cliff B and C were designed around. The corpus chose CASCADE *specifically* to avoid a deletion failure: `RESTRICT` here *"would make an account deletion fail on the log of a permission the account already withdrew."* **The chosen alternative fails harder and less legibly.** (Independently found by two reviewers, on two different decisions.)

### 0.4 The failure this decision is meant to prevent is already live in production
`public.listings.highest_bidder_id` and `winner_user_id` are `references auth.users(id)` with **no `ON DELETE` clause**, and **nothing ever clears them** — not auction end, not sale, not cancel, not `delete_account_cleanup`. There is no `BEFORE DELETE ON auth.users` trigger anywhere.

So `auth.admin.deleteUser()` raises today for **every auction winner and every final top bidder** — at step 6 of 6, after five irreversible steps have committed. **Cost to induce deliberately: one bid.**

---

## 1. The three options, per dimension

| | **A — Tombstone** | **B — Refuse while live** | **C — Forced hand-off** |
|---|---|---|---|
| **Product UX** | Clean, instant, always succeeds | Worst — and **the refusal never lifts** (§2.2) | Instant and satisfying; destroys property. Highest regret and support load |
| **Custody safety** | Intact — writes nothing | Intact — writes nothing | Void leg is invariant-clean; **transfer leg is not implementable** |
| **Money safety** | **Weakest** — SoD degrades to a uuid inequality one human can satisfy across two accounts | **Strongest**, by accident: refusing while money is open creates no new money path | **Worst** — mints a refund per void, returns inventory to the sellable pool, lands in the ledger as an ordinary refund |
| **Privacy** | As specified: **none** — no marker, no shred, nothing deleted | Negative while refusing, and it refuses permanently | Negative — costs the subject property and achieves nothing |
| **Database/FK** | The only end state the schema can represent | Terminal condition ≠ the DELETE's condition | **Adds two permanent RESTRICT references per atom** |
| **ODR-4b** | **Five relation families go inert**, not one | Same, delayed | Same |
| **Apple Wallet** | **Pass stays `issued` and still admits** | No effect | Version bump kills the barcode; supersession runs post-commit |
| **Door/manifest** | **No effect — the door does not know identities exist** | No effect | Inoperable during a freeze except via break-glass |
| **Transfer** | Frozen as a bearer instrument — unsellable, ungiftable | No effect | **No consentless transfer RPC exists** |
| **Refund/dispute** | Cannot self-serve a refund | No effect | Welded to money that may not exist |
| **Recovery/retry** | Best — one idempotent UPDATE | Neutral — nothing succeeds | **None. Ratified: a voided atom cannot be transferred, listed, locked or scanned** |
| **Complexity** | Deceptively high — four absent mechanisms (§3) | Moderate, if scoped to the *real* predicate | **Highest** — needs a cause-registry amendment, a deletion aggregate, a freeze ruling |
| **Failure mode** | **Silent** — everything appears to work | **Loud** — its one genuine virtue | **Silent and irreversible** |
| **Reversibility** | Full (nothing was destroyed) | Full | **Zero** |

---

## 2. The twelve questions, answered

**1 · Does `auth.users` physically survive?** **Yes — under all three.** See §0.1. That is the finding, not a nuance.

**2 · What remains?** The complete `auth.users` row (email, phone, password hash, tokens), `public.profiles` (name, phone, bio, avatar — CASCADE, so it survives when the row does), `identity_ext`, the whole custody chain, audit, payouts, scans, sales, orders, roles. **Nothing is shredded.**

**3 · If forced, what happens to every FK?** Ordered: the two append-only `_event` cascades abort first (§0.3); the demographic cascade would succeed; then ~30 `RESTRICT` columns raise in turn; the `public.*` CASCADE set is never reached.

**4 · Unused paid ticket?** **A:** stays owned by the tombstone and **still scans**. **B:** blocks deletion. **C:** voided to the void-sentinel — **and no refund fires by construction.**

**5 · Ticket for an event tomorrow?** This is where C fails hardest. Once the session's freeze time passes, **transfer, routine void and the parked refund branch are all refused `frozen`.** The only path left is a platform break-glass, which can leave an offline scanner admitting a voided atom. **B's wait is bounded by the event calendar — which the venue controls, not the platform.**

**6 · Open transfer?** Bounded in both directions by TTL sweeps and the existing cancel/decline paths. **Live gap: `disputed` is not in the deletion block list**, so a user in an open chargeback can delete today, and both sides of the live dispute get pseudonymized.

**7 · During an active door freeze?** The manifest is **atom-keyed and identity-free**, and its snapshot is append-only — nothing about a deletion can edit a live manifest. **A** and **B** are unaffected. **C** must use break-glass and **must** write a revoke delta, or an unsynced device admits a voided ticket.

**8 · Apple Wallet?** **Under A the pass stays `issued` and keeps working.** The pass web service authenticates on the `.pkpass` token — **which is not a Supabase credential and is not touched by "credentials are revoked."** A person who deletes their account keeps a working door credential indefinitely.

**9 · Demographic/contact/consent data?** Under A the cascade never fires, so **five relation families survive** — the gender answer, the contact master switch *and its timestamped history of every change of mind*, per-org consent and its history. The corpus argues this for one relation. It is five.

**10 · If deletion fails halfway?** Already live and deterministic (§0.4). Five committed side effects, then a failure: history irreversibly pseudonymized, bids destroyed, media destroyed, listings cancelled — **and the account still live, still signed in** (the client only signs out on success). **Nothing records that a deletion was attempted.** No detector exists.

**11 · Can it be retried safely?** Steps are individually idempotent, so retry is **safe but convergently useless** — step 6 fails identically forever. And **the rate limit is keyed on `(user_id, action)` only**, so a fresh account resets it; `delete_account_cleanup` takes `ACCESS EXCLUSIVE` on `public.listings` **unconditionally**, even for an account with zero listings. Sign-up → delete → repeat is a marketplace-wide lock loop bounded only by the cost of an email address.

**12 · What does the user see?** Two dialogs, **no re-authentication**, then either sign-out or a raw error. The copy says *"permanently delete… all associated data"* and *"Yes, Delete Everything."* That is **false today**, and it violates the corpus's own binding prohibition on erasure language before the crypto-shred exists.

---

## 3. Option A's mechanism does not exist

A is specified as *"the row is retained and marked erased (a `kernel.identity_ext` erasure marker); credentials are revoked, PII is crypto-shredded."* Every clause is absent:

- **The erasure marker has no column.** `identity_ext`'s complete column list is `identity_id`, `residency_region`, `kyc_ref`, `locale`, `created_at`, `updated_at`. No package adds one.
- **The crypto-shred is Gate L**, `RATIFIED-MODELED-ONLY`, explicitly *"do not create in the MVP migrations"* — and the data model states outright: *"No GDPR/CCPA erasure claim is made before C34 is implemented."*
- **No package writes `auth.users`**, so "credentials are revoked" has no owner.
- **`public.profiles` survives** and stays readable by every signed-in user — name, avatar, bio.
- **The Wallet pass survives** (§2, Q8).
- **The re-registration policy is a fork with no good branch**: keep the email and A is a permanent silent ban on that address and phone; scramble it and you free the only cross-account human key the platform has.

**This is the same defect class the corpus has already catalogued five times** — a control that is specified, ratified and relied on, with no substrate and no writer.

---

## 4. Attacks that work

**Against C — the most, and the worst.**
- **Deletion becomes a refund put option.** The void requires a refund object by construction; there is no money-free routine void. Buy a ticket, watch the value collapse, tap Delete Account, get par back — through a control that cannot be rate-limited or refused without defeating the privacy claim.
- **Inventory returns to the sellable pool** — a late scalping re-entry primitive and an occupancy hazard.
- **Account takeover now includes burning the victim's tickets.** There is **no re-authentication** on deletion today. Under C a stolen session becomes irreversible destruction, and the victim cannot even see what happened — ticket history is current-owner-only, and the current owner is now the void sentinel.
- **The ledger cannot distinguish forced from voluntary.** There is no `account_deletion` member in the closed cause registry and no deletion aggregate for `cause_ref` to point at, so a forced void records as an ordinary fan-initiated refund. Settlement, attribution, CRM and the dashboard all read that ledger.

**Against B.**
- **It never terminates** (§0.1), so the user is told to wait for something that will not help.
- **It is vacuous for 26 of the 36 blocking columns** — a promoter or staff member who never held a ticket satisfies B's predicate and the DELETE still fails, with no named reason and no copy.
- **Counterparty hostage** is real and live today: a seller who never marks a transfer sent holds the buyer's deletion open.

**Against A.**
- **Separation of duties is defeatable by delete-and-re-register.** SoD is a comparison of two `auth.users` uuids with no liveness or humanness predicate. One person sets the payout destination, deletes, re-registers, and executes the payout. Two distinct uuids; the check passes.
- **Fraud signals launder.** Risk flags and blocks are CASCADE-bound; under A they survive but bind to a uuid that will never match the new account. Evidence preserved, linkage lost.

**Checked and sound:** you cannot force custody onto someone to pin them in the system — there is no consentless transfer RPC. The trigger-disable window in the cleanup function is **not** exploitable (`ACCESS EXCLUSIVE` plus transactional DDL). The transfer freeze is total on its own terms.

---

## 5. The pending-deletion state — asked, and the answer is *small*

Nothing like it exists in the corpus (exhaustive grep: zero hits). The proposal:

**Three columns on `kernel.identity_ext`, package `077`** — `deletion_state`, `deletion_requested_at`, `deletion_block_reason`, plus a partial index on the open requests only, and one sweep on the **2-minute heartbeat that already runs in production**.

**Why not a new table** — and this argument is decisive: a queue table keyed by identity must choose `RESTRICT`, creating **a third cliff where the queue row blocks the deletion it exists to schedule**, or `CASCADE`, which **deletes the record of the request in the same statement that completes it.** The corpus already hit this and documented the escape elsewhere.

**Cost:** no new table, no new FK, no new cron entry, no new dependency edge, no new lock rank, no new SSCAS member, no new RLS policy, no package renumber. The sweep takes zero locks on custody rows.

**Two things it buys beyond UX:** a **dated, durable record that the person asked** — converting "we never received a request" from technically true into false — and **the only object in the design that can detect a half-completed deletion.** That second value is independent of which option is ruled.

**Two warnings.** It is only an improvement **if it resolves**; built on B alone it sits pending forever while holding a sensitive record and a written promise. And if a pending request *suspends* the account, a user blocked by a ticket four months out is frozen out of their own tickets — worse than a clean refusal. **The cancel path must be reachable and authenticated**, which is delicate when the request path today has no step-up at all.

---

## 6. CORPUS RECOMMENDATION

**None.** `ODR-16` is recorded `OPEN — OWNER` with *"Recommendation: None."*

**But half the question is already ratified.** The data model states, as constitution: *"No hard delete. Deletion is anonymization: PII is stripped/tombstoned, the `IdentityID` is retained… so no ledger reference is orphaned."* Its escape hatch — *"or repointed to a shared sentinel"* — was **closed by ratified `C95`/`C96`** for every custody column.

**So the identity-retention half is decided; only the custody-disposition half is open.**

---

## 7. ENGINEERING RECOMMENDATION — *distinct from the corpus's*

**Split into four, rule one, and fix the deadline.**

| | Question | Status |
|---|---|---|
| **16a** | Is the `auth.users` row retained? | **Effectively pre-decided** by the data model + `C95`/`C96`. Needs ratification as such, not a fresh vote. |
| **16b** | What happens to **live custody** at the moment of request — refuse, or force-resolve? | **The only genuine owner decision here.** |
| **16c** | What happens to **money obligations** — open dispute, chargeback, held payout, negative settlement line? | **Not asked by any option.** The money authority spec has zero hits for account deletion. |
| **16d** | What happens to **non-custody identity roles** — staff, promoter, approver, payout-setter, pass holder? | **Not asked. 26 of the 36 blocking columns.** |

**On 16b, the recommendation is B — restated honestly — with the pending state, terminating in A.**

Not because B is elegant, but because it is the only option that is **truthful, bounded and reversible**, and the only one that leaves the person able to fix their own situation. Its terminal action must be stated as **a tombstone, not a DELETE**, so nobody implements a DELETE that cannot succeed. **C should not be an automatic consequence of a privacy request** — at most a separate, opt-in *"void my remaining tickets"* action with its own consent, its own copy and its own refund answer.

**And B only works with the acquisition freeze:** nothing currently stops a pending-deletion user buying another ticket and resetting their own clock. Without it, the wait is unbounded by the user's own action.

---

## 8. What must be true before this can be ruled

1. **Produce and ratify the 36-column blocking inventory.** No document has it; 10 columns state no `ON DELETE` at all. **Ruling 16b without it is ruling on 10 of 36 columns.**
2. **Correct the deadline from `079` to `077`** everywhere it appears. If the schedule was built on `079`, it is two packages optimistic.
3. **Resolve the cascade/append-only contradiction** (§0.3) — otherwise every option's terminal step aborts for every identity.
4. **Decide 16c and 16d, or state explicitly that they ride on 16b's answer** — they do not.

---

## 9. Severable now — five live fixes that depend on no ruling

None of these waits for `ODR-16`:

1. **Storage deletion deletes nothing** for proofs, covers and transfer evidence — a non-recursive list against two-level paths, with the error discarded. Proof documents carry names, order numbers, barcodes, seats and emails; the covers bucket is **public**.
2. **`cover_image_path` retains the raw user uuid** on a world-readable row that `020` has just pseudonymized. Re-identification is a string split.
3. **`highest_bidder_id` / `winner_user_id` / `reserved_by` are never cleared** — the live cause of §0.4. Plus no reconciler for deleted bids, leaving **a phantom high bid nobody can outbit or win**.
4. **`disputed` is not in the deletion block list**, and the check is an unlocked read four statements before the mutation.
5. **No re-authentication on an irreversible destructive action**, and **no test coverage of the deletion path at all** — 18 pgTAP files cover custody, money, payouts, admin and webhooks; **zero** cover `delete_account_cleanup`.

---

## 10. Owner choice — presented, not made

```
THE QUESTION AS POSED IS NOT RULABLE. Recommended shape:

16a  Retain the auth.users row (tombstone)
       -> RATIFY AS ALREADY DECIDED (data model + C95/C96), not re-voted

16b  Live custody at the moment of request:
     [A] tombstone immediately, leave custody as-is
     [B] refuse while live custody exists, with a pending state,
         an acquisition freeze, and a tombstone as the terminal action
     [C] force-resolve custody through the engine
     RECOMMENDED: B  (C not as an automatic consequence of a privacy request)

16c  Money obligations on deletion            -> NOT YET ASKED. Needs its own pass.
16d  Non-custody identity roles (26 of 36)    -> NOT YET ASKED. Needs its own pass.

BEFORE ANY OF IT:  the 36-column inventory, the 077 deadline correction,
                   and the cascade/append-only contradiction.
```

**No ruling is made in this document.**
