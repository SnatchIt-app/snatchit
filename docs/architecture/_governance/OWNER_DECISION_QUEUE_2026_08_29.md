# The Owner Decision Queue — consolidated, 2026-08-29 (parallel convergence sprint)

**One document, every genuine open owner decision.** Everything the corpus already determined was
repaired mechanically this sprint and is NOT here. **E-1 left this queue** — it dissolved on the merits
(three independent proofs; RPC §20.2.4 repaired; `DF-24` discharged). The auction finalize sweep left it
— proven downstream of R-9 in every branch. Full derivations: the seven agent reports (sprint record) and
the per-decision files cited below.

## Q-1 — `ID-6`: `venue.assert_may_request` grant class — **ONE BIT**

| | |
|---|---|
| Question | true `EXEC: DEF` (no client grant), or keep `GRANT EXECUTE TO authenticated`? |
| Options | **(a)** true DEF · **(b)** caller-authorized |
| Recommendation | **(a)** — no product path needs the grant (pg `SECURITY DEFINER` EXECUTE semantics validated mechanistically: definer-internal calls check the OWNER's ACL; no policy, no client route calls it); the grant's stated justification is technically false; and (b) opens two surfaces the contract's own defense does not cover — a `not_found` **existence oracle** over scope uuids for any authenticated user, and the `p_actor` **parameter as a foreign-uuid authority probe**, which partially defeats the `T-RPC-CRM-07`/C35 defense (structural assertions cannot see ad-hoc client calls) |
| Consequence | one GRANT/REVOKE line in `087`; `R-29`'s three transcription sites written with the ruled class; `T-RPC-GLOBAL-02` passes |
| Routing note | `ODR128` routes this as an RPC-owner repair; `ID6_ASSERT_MAY_REQUEST_ANALYSIS.md` escalates it as an owner bit. **One sentence from the owner settles both the class and the routing.** |

## Q-2 — `R-9`/`E-2` (`ODR-27`): `market.bid`'s home — **ONE BIT, with a SHARPENED consequence**

| | |
|---|---|
| Question | accept "native auctions not offered in MVP" (`public.bids` stays the ledger; `market.bid` never exists), or schedule `market.bid` into `088`? |
| **Sharpened fact the register understates** | Meaning 1 as contracted is **no native-rail auctions AT ALL**: `create_auction`'s mirror precondition is **FK-unsatisfiable** (`public.bids.listing_id NOT NULL → public.listings`; the only bridge is the read-only `089` VIEW; **no document specifies a mirror-row writer**). Auctions survive only on the frozen external rail. |
| Options | **(a)** Meaning 1 with the true consequence stated (registry cleanup: `market.bid` fence row deleted; three "finalize sweep" residues marked vacuous; RN sell-flow must not offer auction mode on native listings) · **(b)** Meaning 2: new AO table + native finalizer (a custody-moving `EXEC: DEF` cron) + a new RLS matrix in `088` · **(c)** build the physical mirror writer — present but nowhere proposed, dual-writes a frozen table, riskiest |
| Recommendation | **(a)** — most consistent with §16.5/I-10/the freeze posture and what the RN spec already assumes; (b) is the largest new money-review surface any open decision would add |
| Downstream | the **auction finalize sweep** is a pure function of this ruling (vacuous under (a); R-9-shaped under (b)) — no separate bit. `market.auction`'s MC row resolves with this ruling either way. |
| Deadline | **before `088` is authored** (RPC §20.8.4's own words) |

## Q-3 — `ODR-16`: account deletion — **NOT READY; two mechanical acts would make it rulable**

Preconditions 3/4/5 re-derived at HEAD (Agent G): the AO-CASCADE contradiction is two relations
(`077`/`082`) and circular with `ODR-4b`; 16c/16d have no decision artifact; 16 SPEC-SILENT `ON DELETE`
columns (8 with unknown nullability). Inventory re-verified **57**, zero new dependencies from this week.

**The two ready-to-sign mechanical acts (owner-adjacent, NOT taken this sprint):**
1. the one-line schema §0 global `ON DELETE` default + the 8 nullability statements (closes precondition 5);
2. **ratify 16a as already-decided** (tombstone terminal in Phase 2 — data model + C95/C96; a ratification
   row, not a vote). This is load-bearing: it renders the AO-CASCADE contradiction inert and collapses
   `ODR-4b` per the split map.

Then the ruling reduces to **16b** (the pending/BLOCK predicate) plus a ~6-question 16c money worksheet
and a ~15-row 16d worksheet. `J-12`'s trigger contract stays blocked on the tombstone-UPSERT-vs-AO
standing blocker inside the `ODR-4` family regardless.

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
