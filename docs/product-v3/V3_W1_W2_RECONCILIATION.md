# W1 / W2 — my source trace against A's deployed sandbox reads

**B · 2026-09-24.** A's reads supersede my assumptions. Recorded claim by claim, including where I was wrong.

---

## 1 · W1 — the bid

| Claim | My source trace (2026-09-24) | A's deployed verification | Verdict |
|---|---|---|---|
| `bids` row + `current_bid` / `bid_count` / `highest_bidder_id` move | yes | yes | **agreed** |
| **`bid_received` inbox row to the seller** | yes | **yes — one row, to the DV seller** | **I was right** |
| **`outbid` inbox row to the previous leader** | stated **unconditionally** | **no row — there is no previous leader on the proposed listing** | **I over-generalised.** The row is conditional on a previous leader existing; I wrote it as a certainty |
| **Push dispatched through pg_net** | *"dispatched, not merely recorded"* | **No push and no outbound request.** Vault holds `project_url` only; the GUCs are unset; the 054 `notify_outbid` body **returns before posting**; every recent outbound request is 401 | **I was wrong about the deployed system** |
| **F-23** — no notification preference consulted | yes | not contradicted | **stands, and is moot here** — nothing dispatches to apply a preference to |
| Finalisation after `ends_at` | *"the buyer owes payment"* | job 1 sets the winner and writes an `auction_won` inbox row; **no payment, transfer, charge or push is created by finalisation** | **A's is the precise statement.** Mine described a resulting state as though it were a write |

### What actually went wrong on my side

**I traced source and asserted deployed behaviour.** Whether a `pg_net` trigger reaches anything is
**deployment configuration** — Vault contents, GUCs, the function body actually installed — and **none of
that is in the repository I read.** The trigger exists; the dispatch does not happen on this sandbox under
option (b).

**This is the same error as F-30**, where I measured a token that nothing rendered. Both times the code was
read correctly and the running system was not checked. **The dispatch configuration A verified is the fact;
my trace was a hypothesis about it.**

**What still holds from the trace:** the inbox row is real, the counters move, and the bid enters
finalisation. **What does not:** "two push dispatches leave the system."

---

## 2 · W2 — the checkout intent

| Claim | Correction |
|---|---|
| *"Entering checkout **creates** a Stripe PaymentIntent"* | **"creates *or reuses*".** `create-payment-intent` has a reuse path (`payments.ts:53` names it, and the function's own retire path cancels stale pending intents). Whether a visit creates a new intent or re-finds an existing one **depends on whether a usable one already exists for that buyer and listing** |
| *"every checkout visit creates one"* | **Not established, and not what the conditional path says.** The accurate statement: **entering checkout causes an intent to exist — new or reused — and a pending `payments` row to be present.** The count is not fixed at one per visit |

**What this changes for cleanup:** a plan that assumes exactly one new intent per visit will not match what is
there. **Cleanup must read the actual state rather than assume it**, and **releasing the reservation does not
cancel the intent** — `release_reservation` touches the hold only.

**Still true and unchanged:** the setup runs in a **mount effect**, so the checkout boards cannot be reached
in either appearance without an intent existing. That is not avoidable by being careful in the session.

---

## 3 · How I will report this class of claim from now on

| Evidence | Wording |
|---|---|
| Read in the repository | *"the code path does X"* |
| Verified against the running system | *"on this sandbox, X happens"* |

**I will not write the second sentence from the first.** Where a claim depends on Vault contents, GUCs,
deployed function bodies or job schedules, it is **A's read**, and until A has made it the claim stays
labelled as a hypothesis.
