# D's reconstructed working records (2026-10-05)

**These are reconstructions, not the originals.** Four of D's working records were held only in the
session scratchpad and were lost when it was cleared between 2026-09-26 and 2026-10-05. Their absence
was confirmed by search with a positive control (a committed file of the same shape was found by the
same search). The originals cannot be recovered, and **the recorded sha256 of each original cannot be
reproduced from these reconstructions** — a reconstruction that hashed to the original would be the
original.

Each entry says what the original asserted, which committed source carries that content now, and what
is unrecoverable. Nothing here should be cited as the original record.

| Original | Recorded hash | Status |
|---|---|---|
| `D_RELEASE_INVENTORY_INDEPENDENT.md` | `f740ab73e16a65c2` (prefix) | **re-derivable**, see §1 |
| `WEB_WORDING_FINDINGS_AND_ACCEPTANCE.md` | `a6f2daf1…` | **content survives committed**, see §2 |
| `PAYMENT_TRUTH_CONDITIONS_DRAFT.md` v2 | `561287b3…` | **content survives committed**, see §3 |
| `D_REFUND_DESIGN_EXPECTATIONS.txt` | `a6324b21a8ef13e387a277810e7a29a7b8be481241182db6e154ddcb81c0437f` | **not recoverable**, see §4 |

---

## 1. `D_RELEASE_INVENTORY_INDEPENDENT.md` (`f740ab73`) — re-derivable

The plan cites it as the anchor D verified against ("verified by D against D's independent inventory
`f740ab73`"). Its load-bearing content was three measurements, all re-derived from the repository on
2026-10-05 and all reproducing:

- `main` carries **89** migration files; the gate carries **165**; **76** are on the gate and not on
  `main`. Control: 0 files are on `main` and not on the gate, so `main` ⊂ gate.
- Of the 76, **73** are in the recorded production ledger (162) and **3 are not: 121, 125, 126**.
- The ledger figure itself is not a measurement D made. It rests on the recorded read-backs after each
  apply (159 → 160 → 161 → 162). No production read.

**What is unrecoverable:** the original's own wording, its per-item table, and the ordering in which D
reached those numbers. The numbers are not lost, because they are reproducible from the repository at
the two named refs, and the reproduction is recorded here.

**Status of the citation in the plan:** still correct as a statement that D verified independently. The
hash `f740ab73` now points at nothing. A should cite this reconstruction instead, or drop the hash.

## 2. `WEB_WORDING_FINDINGS_AND_ACCEPTANCE.md` (`a6f2daf1`) — content survives committed

The findings and the eight acceptance criteria were folded into
`docs/release/PAYMENT_STATE_WORDING_TABLE_20260924.md` **§2h** (commit `cda8337b`, "web acceptance bar
(D's criteria) in §2h"), ratified by A on 2026-09-25. §2h is the authority; this file is not needed to
act.

**Unrecoverable:** the explicit mapping from each finding id (W-1a, W-1b, W-2 … W-6) to the rule it
names. §2h refers to the series ("one asserting test per finding (W-1a/b … W-6)") without listing it.
D has **reconstructed** the mapping below from §2h's own ordering and used it to name the tests on
`web/wording-truth-conditions`. **A should confirm or correct it; it is a reconstruction.**

| Id (reconstructed) | Rule in §2h |
|---|---|
| W-1a | buyer `expired` asserts a refund from status alone ("Expired — refunded in full") |
| W-1b | seller `expired` asserts the buyer's refund from status alone ("Expired — buyer refunded") |
| W-2 | `disputed` asserts a review process, and a decided dispute renders as open |
| W-3 | `auto_released` renders as "Confirmed" — the buyer confirmed nothing |
| W-4 | a seller-win (`buyer_confirmed` with `buyer_confirmed_at` NULL) renders as "Confirmed" |
| W-5 | a reversed row reads as paid: `payout_released_at` is checked before `status` |
| W-6 | "Paid out" wording, the hold with no stored end, and the missing decision-time line |

## 3. `PAYMENT_TRUTH_CONDITIONS_DRAFT.md` v2 (`561287b3`) — content survives committed

Its five sections were ratified into `PAYMENT_STATE_WORDING_TABLE_20260924.md` **§2i** (payout-completion
evidence and the losing buyer) and used in the admin label work. The owner's correction — that dispute
resolution alone does not prove a transfer occurred, so the losing buyer is told the decision only — is
carried in §2i and is the version in force.

**Unrecoverable:** the draft's intermediate v1 wording and D's own derivation notes. Neither is needed:
§2i supersedes them.

## 4. `D_REFUND_DESIGN_EXPECTATIONS.txt` (`a6324b21…`) — not recoverable

This was D's **blind registration**: eleven requirements (R1–R11) written down *before* reading A's
refund-lifecycle design, so that the review could not be fitted to the design after the fact. Registry
row 150 cites the hash.

**This one cannot be honestly reconstructed.** Its evidential value was that it existed before the
design was read; anything D writes now has been written after reading both the design and the
implementation, and would be a different kind of document with the same name. D will not reproduce it.

**What survives:** registry row 150 records that D's review PASSED against R1–R11 at `a6324b21`, that
D's finding F2 was fixed at `2eebc5bf`, and that D passed on F2 at that head. The PASS stands on that
record. The individual R1–R11 texts are gone.

**Consequence for the current round:** D's expectations for A's frozen 150/151 deployment package are
registered fresh and in the open, in
`docs/release/evidence/D/D_PACKAGE_EXPECTATIONS_150_151_20261005.md`, written before the package is
delivered. That registration is this round's equivalent and is committed rather than left in a
scratchpad.

---

## Why the originals were lost, and what changed

They lived only in the session scratchpad under `/private/tmp`, which is not durable across days. The
149 witness evidence survived because A archived it in-repo at
`docs/release/evidence/149_20260924/D/`. From now on D commits registrations and findings to the
repository at the moment they are written, not at the moment they are reviewed.
