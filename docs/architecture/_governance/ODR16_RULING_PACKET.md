# ODR-16 — THE RULING PACKET (assembled 2026-08-29, sprint 2)

**STATUS: READY FOR OWNER RULING.** The mechanical prerequisites are applied (schema §0 `ON DELETE
RESTRICT` default — value derived four independent ways; the corpus-derived `venue.promoter.identity_id`
nullability + CHECK; the three "day `079`" glosses; the inventory's 8→7 off-by-one). The 16c and 16d
worksheets are complete (sprint agent 5's derivation, full object tables with citations in the sprint
record). The J-12 tombstone shape is closed by derivation (§17.20a) and two of the six standing OR-2
blockers are discharged. **Inventory re-verified: 57. Nothing mechanical remains between this packet and
the ruling.**

## What the owner signs — the packet

**1. The 16a ratification row** — tombstone-terminal in Phase 2 is *"effectively pre-decided by the data
model + C95/C96 — ratify, do not re-vote."* Load-bearing: it renders the AO-CASCADE contradiction INERT
(precondition 3 stops blocking the ruling; the documentary reconciliation before `077` authoring is
already half-done via the J-12 shape fixes) and collapses `ODR-4b` to a documentation choice. Ride-along
one-liners: `identity_ext` totality; `SN-VOID`/`SN-SYSTEM` intended undeletability.

**2. The 16b choice** — the pending/BLOCK predicate, terminating in the ratified tombstone (the reframed
brief's model B stands; C dominated; A is the terminal, not an alternative).

**3. The SIX 16c money answers:**
Q1 open dispute (may a `disputed`/`expired`-transfer account delete — today it may, deliberately) ·
Q2 chargeback landing on a tombstoned buyer (acceptable residue vs a chargeback-window gate — corpus
silent) · Q3 held payout (may a payee under `hold_state='held'`/probation delete before resolution) ·
Q4 negative settlement (may an identity owing money delete) · Q5 pending approval_request naming the
deleter (auto-denied/expired vs left pending against a tombstone; decided rows untouchable either way) ·
Q6 accrued-unpaid identity payouts (paid, held, or forfeited — jointly with 16d's promoter question).

**4. The TEN 16d answers:**
`payout_destination_set_by` tombstone-retained (SoD-1 operand, never nulled) · sole-`org_owner` deletion
(refuse-until-transfer vs force-transfer/orphan) · the consent/pref event ledgers surviving a tombstoned
identity (one ruling, both relations; folds with precondition 3 + ODR-4b) · `export_job.requested_by`
(early artifact purge vs normal `purge_after`) · promoter deletion (commissions paid/held/forfeited +
the row as entitlement key; jointly with Q6) · `promoter_code.created_by` tombstone-retained (codes
outlive their issuer) · sold-vs-cancelled listings/offers split (hard-delete never-solds, retain solds;
one ruling, two tables) · the `dispute_resolutions.actor_id` "contact support" refusal lifting under
tombstone-terminal (PR #28 hard-codes it) · seller fraud/risk history surviving deletion (today CASCADE
erases it — delete-and-re-register clears a record; automatic under tombstone, interim exposure until
16b ships) · blocks surviving the blocked account's deletion (today silently removed; same fold + same
interim exposure).

## Residuals that do NOT block the ruling
Precondition-3 documentary reconciliation before `077` DDL (half-done; fully re-blocks only a
physical-delete ruling) · D-6 `{N}` (owner/counsel; blocks copy, not the signature) · the
`inventory_movement.actor_identity` nullability call (one engineering cell) · the five 16d-dependent
nullabilities (become mechanical with the answers) · the reaper + its ODR-4a class amendment (Gate-L).
