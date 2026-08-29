# The Owner Decision Queue — consolidated, 2026-08-29 (parallel convergence sprint)

**One document, every genuine open owner decision.** Everything the corpus already determined was
repaired mechanically this sprint and is NOT here. **E-1 left this queue** — it dissolved on the merits
(three independent proofs; RPC §20.2.4 repaired; `DF-24` discharged). The auction finalize sweep left it
— proven downstream of R-9 in every branch. Full derivations: the seven agent reports (sprint record) and
the per-decision files cited below.

## Q-1 — `ID-6`: `venue.assert_may_request` grant class — **RULED 2026-08-29: (a) TRUE `EXEC: DEF` (`OR-10`) — applied, off the queue**

| | |
|---|---|
| Question | true `EXEC: DEF` (no client grant), or keep `GRANT EXECUTE TO authenticated`? |
| Options | **(a)** true DEF · **(b)** caller-authorized |
| Recommendation | **(a)** — no product path needs the grant (pg `SECURITY DEFINER` EXECUTE semantics validated mechanistically: definer-internal calls check the OWNER's ACL; no policy, no client route calls it); the grant's stated justification is technically false; and (b) opens two surfaces the contract's own defense does not cover — a `not_found` **existence oracle** over scope uuids for any authenticated user, and the `p_actor` **parameter as a foreign-uuid authority probe**, which partially defeats the `T-RPC-CRM-07`/C35 defense (structural assertions cannot see ad-hoc client calls) |
| Consequence | one GRANT/REVOKE line in `087`; `R-29`'s three transcription sites written with the ruled class; `T-RPC-GLOBAL-02` passes |
| Routing note | `ODR128` routes this as an RPC-owner repair; `ID6_ASSERT_MAY_REQUEST_ANALYSIS.md` escalates it as an owner bit. **One sentence from the owner settles both the class and the routing.** |

## Q-2 — R-9

OPTION A:
Ship the MVP with no native-rail auctions at all — `market.bid` is never created, `create_auction`
rejects native listings, and auctions exist only on the legacy external rail exactly as they run today.

WHAT OPTION A MEANS FOR THE PRODUCT:
A fan reselling a ticket that was issued natively by a venue in Phase 2 can sell at a fixed price,
field offers, or send peer-to-peer — but cannot run an auction on it; auctions keep working only for
tickets living on the existing legacy `public` rail (today's system, unchanged).

OPTION B:
Build the native auction ledger — a new `market.bid` table, a new custody-moving finalize sweep, and a
new bid RLS matrix — into package `088`.

WHAT OPTION B MEANS FOR THE PRODUCT:
Every ticket, including natively issued ones, can be auctioned end-to-end inside the new system — at
the cost of the largest new money-review surface any open decision would add, in the package that
already carries the heaviest load.

RECOMMENDATION:
Option A for MVP — it matches what the mobile app's ratified flows already assume, adds zero new money
surface, and leaves Option B as a clean post-MVP extension point; it must be ruled before `088` is
authored either way.

**Precision notes (the distinctions the ruling needs):** *resale* auctions on legacy-rail tickets are
untouched by either option; *primary/native venue ticketing* has no auction surface in either option
(primary sales are fixed-price checkout — auctions were only ever a resale mode); `market.bid`'s home
is "nowhere" under A and `088` under B; under A the `088` package is unchanged and three "finalize
sweep" residues are marked vacuous, under B `088` gains table+finalizer+matrix; **the auction finalize
sweep is a pure function of this ruling in every branch — folded, no separate decision.** The prior
sharpening stands: Option A's true breadth is "no native-rail auctions AT ALL" (the mirror precondition
is FK-unsatisfiable and no mirror writer exists) — stated so the signature accepts what it accepts.
**RULED 2026-08-29: OPTION A (`OR-11`) — applied, off the queue.** An MVP scope decision only; Option B preserved as the post-MVP path.

## Q-3 — `ODR-16`: account deletion — **READY FOR OWNER RULING (2026-08-29, sprint 2)**

The packet is assembled: `_governance/ODR16_RULING_PACKET.md` — the 16a ratification row (signature,
not a vote) + the 16b choice + SIX 16c money answers + TEN 16d answers, with every mechanical
prerequisite applied and the worksheets complete. Inventory 57, re-verified.

## Q-4 — `ODR-4b` — **BLOCKED BY Q-3 by name**; collapses to a documentation choice if 16a is ratified.

## Q-5 — `ODR-1` re-ratification — **the owner act the sprint prepared**

B-4 and B-5 are CLOSED (this sprint). B-6: two crisp corrections applied; the §13.6 edge-table refresh is
deferred INTO the amendment (a fresh table now would be re-stale after `092`). **B-1/B-2 are mechanical on
five of six limbs — the sixth is that numbering `092` is itself the ratification act** (registry §6.5).
B-3's deletion debt is fully enumerated (~45 sites, exact map on file; two named residues: the
`T-SCHEMA-GRANT` test disposition disjunction; annotate-vs-delete convention). **B-7 sharpened:** `092`'s
derivable in-edges are **six** (`077 078 079 082 085 090 → 092`), `076 → 092` pending one
declaration-convention call, `080 → 092` pending CONFLICT-4; **underivable until ruled/placed:**
`notify.emit_event`'s home (its own SEAM-1 says `076`, and 19 call sites across six packages forbid `092`
— no document places it), the R1–R5 emit-semantics choice, and N3's re-keying. **Floor: 53 edges
post-092. NOT an answer.** READY FOR OWNER RATIFICATION: **NO** — the signature act itself bundles: the
band `076–092/17`, the outbox split (OR-4), the B-3 revert authorization, and the `092` numbering.

## NEW QUEUE ITEMS — sprint 2 (2026-08-29)

| id | one-sentence question | options | recommendation |
|---|---|---|---|
| **R-36** | Does an invitee get a decline verb, or does an unwanted org invite simply lapse? | grant `decline_org_invite` / strike `declined` from the enum | strike — smaller surface; the corpus's own house principle is that declining is indistinguishable from silence |
| **R-39(a)** | Where is the org customer key minted — at org creation, or lazily at first export? | create_organization / request_export `ON CONFLICT DO NOTHING` | lazy — strictly smaller blast radius; no secret exists for orgs that never export |
| **R-39(b)** | What object carries the "customer references changed" fact on key rotation (and is rotation Phase-2 at all)? | rule the carrier / defer rotation to incident-response runbook | defer — CRM's own text frames it as incident response, "not a routine" |
| **N1** | Which transactional email provider (data-processor, apex-DNS-binding, O-3's out-of-band leg)? | owner selection | — (blocks email go-live, not 092 authoring) |
| **N2** | Who may execute the Control-5 payout-freeze escalation (the ratified control offers it to org roles the RPC denies)? | (a) file a request to platform · (b) org arm on hold_payout · (c) amend the control text | (a) — preserves SoD-3, uses the existing approval object |
| **R1–R5** | Does `emit_event` raise, and for whom (the one contract + one test the choice touches; placement invariant)? | R1 raise-always / R2 split / R3 registry-driven | R2 if the Wallet distinction matters, else R1 — R4 rejected on precedent, R5 moot under reduction |
| **N3-9th** | Is a buyer told when their refund request is cancelled (`cancel_refund_request` names no emitter)? | add the type / silence | add — the silent reversion of a `refund_hold` is the queue's own "told nothing" defect |
| **ODR-3 §1.1** | Do the five door-carrier notification types ride the resale-rail deferral (the stated default) or get keys now? | defer / key now | defer |
| **D-6** | The tombstone retention window `{N}` (counsel). | — | — |
