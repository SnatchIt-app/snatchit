# Handoff — for A and C (from B, 2026-09-21)

**Forwardable as-is.** Two parts: the delivery-preferences work, which **A has already reviewed** and which needs
three owner decisions to move; and four baseline questions raised by V3 reconnaissance.

---

## Part 1 · Saved ticket-delivery preferences — A's review is in, and it changes the mechanism

**A answered all five questions** in `docs/release/TICKET_DELIVERY_PREFERENCES_A_REVIEW_20260919.md`, including
owner-authorised read-only production checks. I accept every correction. **Nothing is blocked on messaging any more;
it is blocked only on the three owner decisions below.**

### What A corrected — and what it changes in my plan

| # | A's finding | Effect on the plan |
|---|---|---|
| 1 | **Q1 is "no."** `settle_listing_for_payment` **does not exist in production**, and even on the candidate it is not the only transfer writer. Production has **three writers**: `confirm-payment` (`:258-267`), the `stripe-webhook` fallback (`:330-341`), and `ensure_transfer_exists` (061, called by the client at `payments.ts:380`). `20260906100000` is not applied and shape B is NO-GO | **The mechanism changes.** Attaching the destination inside one settlement function would miss two writers. It must be a **BEFORE INSERT trigger on `public.transfers`** — the only thing that covers every writer in both environments. My S2 is replaced |
| 2 | **Bids are world-readable:** `bids_select_all … using (true)` (`070:24`) | A destination must **never** be stored on `bids`. This confirms the separate owner-only table (Q2 = yes) |
| 3 | **Q3:** keep today's rule — no payment-rule change is authorised | Matches the owner's approval 8. The seller-clock question is **closed**, not deferred |
| 4 | **Q4:** off-session winner charging is **not planned in any record A holds** | The plan stays written against the current pay-after-win path |
| 5 | **Q5:** ship the freeze and the mark-sent refusal **together in one small migration, separately and before** the attach | Sequencing corrected |
| 6 | **My 24-hour expiry/refund claim "holds in substance for production, at records strength"**, with two corrections: the writer I cited does not exist in production, and production's edge lacks the candidate's Phase 0 settlement reconciliation. A's §8 adds owner-authorised verification of the deployed function, the schedule (`*/2`, active) and the last day of execution | The claim is now **[A-VERIFIED]** rather than my **[SRC]**. My original label was too strong and A's is the one to quote |

### One question I am adding for A

**A-6 · `catalog.platform_config`.** I found a versioned config table (`078`) seeding the native gates. I had wrongly
told the owner that no runtime-config mechanism existed. Per the owner, treat it as a **candidate dependency only**:
before any staged enforcement leans on it, **A confirms its intended use, who may write it, and its access
controls**. Until then, staged enforcement stays as A specified it.

### The three owner decisions — with my recommendations

| | Decision | My recommendation |
|---|---|---|
| **O-1** | **Link-based providers (Fever, Shotgun).** Our app asks these buyers for a phone, but our own research says both transfer by **shareable link**, and the seller steps tell the seller to share it "through Snatch It chat" — **the app has no chat** | **Collect a phone as the channel for the link**, relabel it honestly ("Phone number for your transfer link"), and change the seller step to "text the link to the buyer's number". Email is the alternative. Either way the chat reference must go |
| **O-2** | **Resale-sourced listings (StubHub, Vivid Seats, Gametime).** The listing's platform does not determine the real transfer method — it depends on how the seller received the ticket | **Ask the seller, at listing time, which platform delivered the ticket**, and derive the destination type from that. Cost: one field added to selling |
| **O-3** | **The enforcement threshold** for refusing a bid or checkout without a destination on older app versions | **Defer until there is data.** No app-version signal exists today, so the threshold cannot be set honestly yet. Ship the accept-and-attach stage first, add the version signal, then set the threshold |

**Provider claims, labelled.** Everything above about DICE, Posh, Fever, Shotgun, Tixr and the rest is **our app's
encoding** plus **our own research dated 2026-06-12** (`docs/product/TRANSFER_METHOD_RESEARCH.md`, ✅ official-source
marks with URLs). **None of it has been independently re-verified with the providers**, and it is three months old.
Re-verification is a named pre-implementation task, not something I have done.

---

## Part 2 · Baseline questions from V3 reconnaissance

### For A

**A-7 · Which line is the client baseline?** I started on `release/candidate-20260918` (`ee4cc12c`) and found it
**behind on client code**. Measured: the gated candidate `8f45e9bb` is **not** an ancestor of `ee4cc12c` (they diverge
at `5cfae1f3`, 15 Sep), and comparing `app/` + `src/` there are **12 consumer commits on the gate line that
`ee4cc12c` lacks** — the F-XFER-3 fix, "I got my tickets" asking before it releases payment, the sent-transfer
provider handoff, and the F-SEC / F-AVATAR fixes — with **none** going the other way.
I have moved V3 to **`integration/refund-payout-round-v2` @ `e6ebd800`**, which contains the gate line and PR #84, and
whose independent verification by D is recorded in `ee4cc12c`'s own commit message. **Please confirm that is the right
line to design against, or name the right one.**

**A-8 · How does the release gate relate to it?** The go/no-go was run against `8f45e9b` — shape A **NO-GO as
drafted**, A′ **superseded**, shape B **NO-GO now**. Since that commit is not in `e6ebd800`'s history, I am treating
the gate's verdicts as **not transferring** to the V3 baseline. Correct me if the gate is expected to be re-run
against the integration line.

### For C

**C-1 · PR #81** (`fix/checkout-escrow-note-unknown`) is the one consumer PR I can find that is **integrated
nowhere**. V3's transaction work must accommodate it. Is it still intended for integration?

**C-2 · Last tested build.** The go/no-go refers to the app being "identical to Build 21". Is **Build 21** the last
build tested on a handset, and does it correspond to `e6ebd800` or to the gate line? Every V3 statement about device
behaviour is currently **[UNVERIFIED]** — I have done no device check.

**C-3 · Display typeface.** V3 proposes Didot (iOS) with Inter, and Oswald demoted to eyebrows and the wordmark.
Android needs a serif substitute — Noto Serif is on the platform, or an OFL Google serif as a **JS-only** package.
No purchase is proposed. Before implementation the display tokens need re-measuring against
`MIN_LINE_HEIGHT_RATIO` (1.25) and the display-scale cap, because serif metrics differ from Oswald's.

---

## What is not claimed anywhere in this handoff

- No production read and no device check by me.
- Repository migration defaults (the native gates seeded `false` in `078`) are **not** verified production flag
  values, and I no longer describe them as such.
- Code present on a branch is **not** proof that it ships; every client statement is labelled with its commit.
