# SNATCH IT — OWNER DECISION PACKET  (2026-08-28)

No owner decision is made in this document. Recommendations only.

---

## C2 — ODR-16  (deletion while holding live custody)

READY FOR OWNER RULING: **NO** — not as framed.

The brief concludes NOT READY AS FRAMED and splits the decision four ways:
  16a identity retention — already pre-decided by the data model + C95/C96 (ratify, do not re-vote)
  16b live custody at the moment of request — THE ONLY GENUINE OWNER DECISION
  16c money obligations — not asked
  16d non-custody identity roles — not asked; 26 of the 36 blocking columns

THE DECISIVE FINDING, independently corroborated in the schema spec, migration
plan and RPC contracts: **the auth.users DELETE never succeeds under A, B or C.**
ticket_ownership_log's three identity columns are RESTRICT and append-only;
tickets.current_owner_id is NOT NULL RESTRICT; no engine moves the head off a
terminal atom. So C buys destruction of the user's property and NO erasure — it
is strictly dominated.

DEADLINE CORRECTION: the real deadline is package **077**, not 079. Every
identity with a kernel.identity_ext row becomes undeletable the day 077 applies.
The register still files ODR-16 against 079 — two packages optimistic.

| | A tombstone | B refuse/pending | C forced hand-off |
|---|---|---|---|
| dispute_resolutions.actor_id | BRIEF IS SILENT | SILENT | SILENT |
| disputed transfers | untouched; `disputed` is NOT in the block list today | no effect; block predicate still omits `disputed` | void welded to money that may not exist |
| expired transfers | bounded by TTL sweeps | same | same |
| live tickets | stay with the tombstone and STILL SCAN | blocks deletion | voided; NO refund fires by construction |
| open transfers | bounded both directions | counterparty can hold deletion open | no consentless transfer RPC exists — not implementable |
| door freeze | no effect (manifest is atom-keyed, identity-free) | no effect | break-glass only; must write a revoke delta |
| Wallet credentials | pass stays `issued` and KEEPS ADMITTING | no effect | version bump kills the barcode |
| demographic deletion | cascade never fires — 5 relation families survive | same, delayed | same |
| ODR-4b cascade | INERT | same, delayed | same |

Cost: A "deceptively high" (4 specified mechanisms do not exist). B moderate.
C highest, and irreversible.

RECOMMENDED (the brief's own, and the reviewer agrees): **B**, restated honestly,
with a pending state, terminating in A. C should not be an automatic consequence
of a privacy request.

CAVEAT ON SEQUENCING: do not rule 16b before the 36-column blocking inventory
exists. No document contains it. 26 of the 36 columns sit outside B's predicate,
so a B ruling today silently under-specifies its own refusal reason.

---

## C3 — G-25, the four unresolved events

#2  ConnectOnboardingCompleted  RECOMMENDED: **REMOVE**
    Zero producers, zero consumers, zero readers corpus-wide. The capability
    columns the brief says are written synchronously do not exist on
    kernel.organization at all — which strengthens REMOVE and exposes an
    unfiled EDGE-vs-SCHEMA divergence to file beside G-3.

#5  TicketTypeOpened            RECOMMENDED: **REMOVE**
    No consumer, and REDUNDANT: catalog.publish_event already gates on-sale and
    produces #4 EventPublished, which is retained.

#11 TicketReserved             RECOMMENDED: **REMOVE**
    No cross-context consumer. Its only "consumer" is the producing
    transaction reading its own write.

#32 PromoterCommissionAccrued  RECOMMENDED: **KEEP**
    A ratified notification type names it BY NUMBER as its trigger. Under the
    binding rule that is a proven dependency and forecloses REMOVE.

CONDITION on #32, raised by the second reviewer and not by the first: #31
AttributionRecorded is in the identical position and is WEAKER on every axis
(class OFF, channel I only), yet sits unquestioned in the base set. Either both
are carrier-forced or neither is. **Rule {#31, #32} together, not #32 alone.**

---

## C4 — ODR-2  (transactional event outbox)

*** YOUR OPTION LETTERS ARE INVERTED RELATIVE TO THE CORPUS ***

| your label | corpus label | what it actually is |
|---|---|---|
| A. NO OUTBOX | **[B] WITHDRAW** | amend DA 6.2/6.3 + CDM C12, design a transport per fact |
| B. MINIMAL OUTBOX | **[A] BUILD** | one table, one drainer, one advisory lock, package 076 |
| C. BROKER / EVENT-BUS | **DOES NOT EXIST** | prohibited by ratified text |

Option C is not merely unrecommended — DA:1168-1174 says "Do not build a broker,
do not build sagas", and a corpus-wide grep for Kafka/RabbitMQ/SQS/PubSub/NATS/
EventBridge/Redis/event bus/message broker returns exactly ONE hit: that
prohibition itself. Ruling C would be a constitutional amendment with zero
design behind it.

OUTBOX-REQUIRED EVENTS — two independent recomputations, disagreeing on METHOD:

  strict test (a named handler must exist)     MIN 20 · RECOMMENDED 21 · MAX 24
  permissive test (a context tick counts)      MIN 22 · RECOMMENDED 23 · MAX 26

The previously circulated 20/21/24 was reached by two errors of OPPOSITE SIGN
that cancelled: one unnumbered Wallet fact counted where three exist
(session-change and cert-rotation were dropped), and #3/#4 admitted on a context
tick — the same evidence used to REMOVE #2 and #5. Pick one test and apply it to
every row.

BOTH READINGS AGREE ON THE NUMBER THAT DECIDES THIS: **the Gate-L floor is 16** —
facts with a named non-notify consumer (Wallet, door, scanner, venue, market,
risk). It does not move under any ODR-3 ruling.

RECOMMENDED OWNER CHOICE: **corpus [A] BUILD** (= your label B).
The outbox is the only expensive-to-retrofit piece: adding it later reopens
eleven money/custody producers, several of them SSCAS members under the global
lock order; adding an event to an existing outbox is an INSERT. Option A is MORE
work, not less — it replaces one drainer with ~5 bespoke sweeps on a codebase
that has already silently lost two crons. And 16 facts and 26 facts buy the same
table, so the four open G-25 events do not price this decision.

REJECT ONE ARGUMENT THE BRIEF LEADS WITH: it says option A "selects the
prohibited home in which a previous owner keeps a live pass — a door-fraud
primitive." The Wallet spec's own 4 and its H-4 fix retire that: the stale-pass
guarantee rests on the door's offline-verify step 3b and a LIVE ownership check,
not on the carrier. What actually breaks is functional — a partial
UNIQUE(ticket_atom_id) WHERE status='issued' means the new legitimate owner
CANNOT add their ticket to Wallet until supersession runs. Record the corrected
reason, or it outlives the correction.

---

## C5 — ODR-3  (notification infrastructure)

*** LABELS INVERTED HERE TOO ***

| your label | corpus label |
|---|---|
| A. no notify schema | **[B] Gate L** |
| B. minimal notification infra | **[C] Gate P REDUCED** — constructed by the brief; no corpus document proposes it |
| C. full platform now | **[A] Gate P** — 9 tables, 23 RPCs, 2 edge fns, 3 crons |

Gate L is the PRE-LEGAL-SCALE gate, not "next quarter". "Defer to Gate L" means
"not in the Miami-first product".

CORPUS RECOMMENDATION: **[A] Gate P (full)** — one document, weakly, and its
dashboard argument is circular.
ENGINEERING RECOMMENDATION: **[C] Gate P REDUCED** (= your label B).

THE FACT THAT DECIDES IT: production's entire notification estate is on the P2P
RESALE rail. Phase 2 is venue-native primary ticketing, and Gate P is defined as
"before the FIRST native ticket is issued". **20 MANDATORY notification types are
reachable at Gate P and exactly ONE has a producer today. Nineteen ship silent
under a Gate-L ruling** — including: a venue cancels an event and no ticket
holder is told.

And one is not a feature gap but a RATIFIED CONTROL GAP: owner ruling O-3 was
ratified WITH its compensating control, and one of those controls is
out-of-band notification to every org money principal. Under Gate L, O-3's grant
ships without it.

Do NOT build: announcements + their abuse-control surface, templates/locale,
notify.schedule and its cron. **SMS is NOT justified anywhere in the corpus** —
zero occurrences in the notifications spec; do not build an SMS channel.

THREE BLOCKERS to rule or schedule BEFORE authoring: (1) transactional email
does not exist and 19 of 24 MANDATORY types name email — auth mail currently
runs on a personal Gmail SMTP relay; (2) O-3 Control 5's one-tap escalation
collides with a ratified invariant and cannot be built as specified without
Universal Links; (3) the money spec's eight emitters are in a different
namespace from the notification catalogue and some have no counterpart.

---

## C6 — WHAT HAPPENS AFTER THE RULINGS

1. Owner rules ODR-2, then ODR-3 (in that order — one sitting), G-25 {#31,#32}
   plus #2/#5/#11, and ODR-16 ONLY after the 36-column inventory exists.
2. Finish the remaining true Band-1 owner rulings.
3. Execute the bounded cross-document remediation.
4. Agent K adversarial consistency review.
5. Agent L final readiness.
6. If READY, write ARCHITECTURE_FREEZE.
7. Begin Phase-2 package 076.

None of these is started here.
