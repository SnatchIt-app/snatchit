# Writer Parity — Root-Cause Map (Phase B of the convergence pass, 2026-08-29)

**Every true-scope finding re-derived from HEAD, then classified.** Raw findings and root defects are
different numbers and are never conflated.

> ```
> TRUE-SCOPE FINDINGS BEFORE THIS PASS   38    22 DIVERGENT + 16 MISSING_CONTRACT
> RAW FINDINGS INCL. CANONICAL-INTERNAL  45    38 + the 5 canonical internal contradictions + F-3 + RC-6
> ROOT DEFECTS                            9    RC-1 … RC-6 (re-confirmed) + RD-7 RD-8 RD-9 (new)
> MECHANICALLY REPAIRED THIS PASS        29    every class-A/RC-6 finding + F-3 + the canonical five
> REMAINING                              20    16 missing contracts + 4 not-built (gate-visible)
> ```

## Classification of the 38 true-scope findings

| class | n before | n repaired | n remaining | disposition |
|---|:--:|:--:|:--:|---|
| **A** — stale derived restatement (`RC-2`) | 21 | **21** | **0** | MECHANICAL — repaired at every located site; each line now restates the registry and says so |
| **B** — canonical contract omission | 9 | 0 | **9** | ENGINEERING — real contracts to write (webhook writers, `session_version` producer, invite-revoke, `org_customer_key` mint/rotation, `notify.schedule` producer, `identity_channel_state`, `delete_account_cleanup` declaration, `instrument_fingerprint`, dispute-freeze RPC) |
| **C** — trigger/sweep/internal exclusion (`RC-3`) | 4 | 1 *(root repaired: §20.0a; sweep folded into §0.7a + `R-24`)* | **3** | `set_updated_at` contract (`R-35`) · erasure trigger (`J-12`) · `mark_refund_state` build (`S-24`) — each also counted in its surface class below |
| **D** — package-placement gap | 2 | **1** *(`S-24` CLOSED — MECHANICAL REMEDIATION, 2026-08-29: plan `085` schedules the function + constraints + tests; schema had already selected `085`, `C101`/`C102` had already ratified the writers, no owner decision occurred, no migration was created; **`S-25` registry naming CLOSED later the same day, as a separate remediation event**)* | **1** | `set_updated_at`→`kernel.tickets` (`R-35`) — filed, not built (hard stop) |
| **E** — actual missing behavior | 2 | 0 | **2** | erasure tombstone (`J-12`, see D4) · `instrument_fingerprint` writer (fails OPEN on the self-deal detector) |
| **F** — owner decision required | 2 | 0 | **2** | `E-1` `catalog.event_session.session_version` (who bumps it) · `E-2` `market.bid` home (`R-9`) — **not decided here** |
| **G** — parser/gate defect | 4 (`F-1`…`F-4`) | **4** | **0** | `F-1`/`F-2`/`F-4` corrected by the prior triage; **`F-3` resolved THIS pass**: `kernel.admin_refund` removed from `venue.order`'s writer set — §20.7.1's own Writes line does not name the table and the contract states it is *not order-scoped* |

*(Row counts intersect — C/D/E name the same three physical defects from different faces; the
non-overlapping remaining set is the 16 + 4 the gate prints.)*

## The root defects

- **`RC-1` scope drift (three table sets) — CLOSED.** The fence now carries all 82; check `H2` makes the
  two previously-external tables' absence a hard error.
- **`RC-2` restatement-instead-of-pointer — CLOSED.** 21/21 divergences repaired; every repaired line is
  marked *"restates the canonical registry (`OR-7`)"*.
- **`RC-3` trigger exclusion "by construction" — ROOT CLOSED** (§20.0a repaired), consequences open
  (`R-35`, `J-12`).
- **`RC-4` placeholder writers (a phrase, not a function) — OPEN, now annotated at every site** ("native-sale
  payout path", "finalize sweep", "088 expiry tick", "a revoke RPC", four webhook prose entries). These are
  the bulk of the 16 missing contracts.
- **`RC-5` contracted-but-never-built — MADE GATE-VISIBLE** (the `BUILT` field; 4 flags).
- **`RC-6` ratified correction landed in derived docs, not the canonical — CLOSED** (`C110` hooks contracted
  at §17.10a; §17.10's Writes row re-routed).
- **`RD-7` (new) — the canonical document contradicted itself about its own writer set.** Five instances,
  all repaired: `R-24` "TEN" (→ eleven, derived), §0.7a "six" + "nothing is added to it" (→ seven-row closed
  table incl. the §12.5 sweep), §7's "No other code writes custody" (→ the enumerated form), §8.2's
  payment-native phrasing (→ delegation form, closing X-1's "2 or 3" at **2**).
- **`RD-8` (new) — the registry itself committed an extra-writer error** (`F-3`, `admin_refund`) while
  diagnosing the same error one column over. Repaired against the canonical Writes line.
- **`RD-9` (new) — `ID-6`**: `venue.assert_may_request`'s grant class is stated two ways in one Authority
  line. NOT a writer defect (the function writes nothing); see `ID6_ASSERT_MAY_REQUEST_ANALYSIS.md`.
