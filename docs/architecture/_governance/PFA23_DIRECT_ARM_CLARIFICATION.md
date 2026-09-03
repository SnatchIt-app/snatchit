# PFA-23 — DIRECT-ARM CALLER CLARIFICATION, and the refund-execution claim verb

**Status:** CLARIFICATION RECORD. **PFA-23 is NOT amended by this document** and no frozen rule changes.
**Baseline:** `POST_FREEZE_AMENDMENTS.md` PFA-23 (OWNER-SIGNED 2026-09-01).
**Evidence:** `docs/phase2/_impl/H1_refund_architecture.md` §5, and `docs/phase2/_impl/E4_refund_executor.md` §7
(which this record supersedes on the authority question, and only on that question).
**One item below requires an owner signature: §B.**

---

## A — THE CLARIFICATION

```
ID:                          PFA-23-C1
CLASSIFICATION:              IMPLEMENTATION CLARIFICATION — no amendment required.
FROZEN RULE (UNCHANGED):     PFA-23. `kernel.refund_primary_order` is EXEC DEF: granted to service_role,
                             REVOKED from authenticated/anon/public. DIRECT arm authority =
                             is_platform([platform_support (cap ALWAYS evaluated on the cumulative
                             operand under the payment lock), platform_admin]). DELEGATED arm =
                             `req:'||request_id`, single-use via the UNIQUE refund idempotency key,
                             "reachable only definer->definer (from approve_refund_request/
                             request_order_refund, which have already enforced dual control) or via
                             the refund-execute edge as service_role".

THE APPARENT CONTRADICTION:  085's PART 14 grant-block COMMENT (085:2145-2146) describes the intended
                             caller as "the refund-execute edge (as service_role, forwarding the
                             platform JWT for the direct arm)". That caller cannot exist. PostgREST
                             derives ONE database role per request from the JWT it verifies, so a
                             request is EITHER service_role — auth.uid() is NULL, kernel.is_platform()
                             fails, 42501 — OR authenticated, and EXECUTE on refund_primary_order is
                             denied (085:2129-2130). Both refusals are already asserted: suite 149 D1
                             and 149 D8. E4_refund_executor.md §7 read that comment as the frozen
                             shape and escalated it as an open owner decision with three options.

WHY NO AMENDMENT IS NEEDED:  1. The sentence is NOT in PFA-23. PFA-23's ruling text specifies the DIRECT
                                arm only as an AUTHORITY PREDICATE and enumerates callers only for the
                                DELEGATED arm. The words "forwarding the platform JWT" appear nowhere in
                                it. They appear in a descriptive comment in an immutable migration.
                             2. The authority PFA-23 grants is fully reachable today, by the door
                                PFA-23's own text names. kernel.request_order_refund (085:850) is
                                granted to `authenticated` (085:2130, the v_auth array), is SECURITY
                                DEFINER, and therefore carries the caller's auth.uid(). It evaluates the
                                SAME kernel.is_platform predicates and the SAME
                                refund.platform_support_max_minor cap, on the SAME cumulative operand,
                                under the SAME payment lock. For platform_admin / platform_risk, and for
                                platform_support within cap, it sets v_execute := true, writes an
                                auto-approved witness kernel.approval_request, and calls
                                refund_primary_order DEFINER->DEFINER under `req:'||request_id`
                                (085:995-1036). Suite 149 D2 asserts the result is `status: 'executed'`
                                — one platform actor, no second human, no raw SQL.
                             3. refund_primary_order's DIRECT branch is therefore a DEFINER-INTERNAL
                                branch, not an edge-callable arm. Nothing is missing; a comment named a
                                caller the grant set never had.

WHAT IS CORRECTED, AND WHERE: The EDGE, not the database. supabase/functions/refund-execute/index.ts
                             `action: record` previously routed a non-`req:` command key to
                             kernel.refund_primary_order on the caller's client, which can only ever
                             return 42501. It now routes:
                               `req:<uuid>` key  -> service client -> kernel.refund_primary_order
                               any other key     -> caller  client -> kernel.request_order_refund
                             `refund-execute/executor.ts` classifyArm keeps its name and its meaning;
                             only the handler's destination changes.

WHAT IS NOT DONE (and why):  No grant is added or removed. No function body in 076-092 is touched. The
                             DIRECT branch is NOT deleted from refund_primary_order (085 is immutable,
                             and the branch is harmless: unreachable, and it re-enforces the same
                             predicates its only live caller already enforced). No raw-SQL operational
                             path, no service-role session carrying a human `sub`, no forwarded
                             arbitrary JWT, and no function trusting a user-supplied role claim — each
                             of those was considered and each is refused on principle.

TEST IMPACT:                 NONE. Suite 149 D1, D2 and D8 stay green UNMODIFIED; they already encoded
                             this reading. supabase/tests/158_refund_execution_claim.sql §J pins the
                             three grant facts that make the reading unmistakable to a future reader.

OWNER SIGNATURE REQUIRED:    NO. Records a platform impossibility in a descriptive comment and applies
                             the corpus's own existing mechanism. No normative behaviour changes.

CONSEQUENCE FOR E4 §7:       Its three options are moot. (i) granting EXECUTE to `authenticated` is
                             unnecessary and would contradict PFA-23; (ii) a service-role session with a
                             human `sub` is unnecessary and is the forged-principal shape to avoid;
                             (iii) "retire the direct arm and route platform refunds through delegated
                             control" is already the de facto state and needs no ruling.
```

---

## B — THE ONE ITEM THAT DOES NEED A SIGNATURE — **PENDING OWNER RATIFICATION**

```
ID:                          PFA-23-R1
SUBJECT:                     kernel.claim_refunds_for_execution(integer, integer) — NEW, 093 slice 10i.
                             docs/phase2/_impl/093_parts/10_money_settlement.sql §10i.
                             AUTHORED AND TESTED, NOT APPLIED ANYWHERE.

WHY IT NEEDS RATIFICATION:   E4 §3 set the standard itself: a work-list verb over pending money "IS an
                             enumeration verb over pending money, so it deserves its own ratification
                             rather than arriving as a silent passenger in the money slice". This is
                             that verb. It is also a new service_role surface on the money execution
                             path, which is the class PFA-21 exists to keep narrow.

WHAT IT IS:                  security definer, set search_path = '', service_role EXECUTE only (revoked
                             from public/anon/authenticated). Returns { refunds: [{ refund_id,
                             created_at, status, execution_mode, attempt, command_key }], lease_seconds,
                             claimed_at }.

WHAT IT CAN DO:              Exactly what its name says. It selects UNFINISHED refunds
                             (status in ('pending','submitted')) that no worker holds a live lease on,
                             oldest first, bounded; stamps one append-only kernel.admin_audit row per
                             claim (action 'refund.execute_claim', system actor); and returns handles.

WHAT IT CANNOT DO:           Move money. Transition a refund (kernel.mark_refund_state, 085:1737,
                             remains the sole writer of status). Mutate any column of kernel.refund.
                             Name or accept a refund, payment, order, venue, organization, identity,
                             amount or destination — there is NO parameter for a subject at all; p_limit
                             and p_lease_seconds are throughput only and are CLAMPED server-side
                             (1..100, 60..3600). Project a PaymentIntent, an amount or a buyer — the
                             executor must still go through kernel.get_refund_execution_context, under
                             that function's own X-6 / ruling-F projection.

WHY IT IS A CLAIM, NOT THE   A bare list hands N workers the same N refunds and leaves Stripe's
LIST E4 §3 SKETCHED:         idempotency key as the FIRST line of defence rather than the last. That key
                             is a 24-HOUR token held by a third party. The claim additionally lets the
                             DATABASE decide, per row, whether that token is still valid — returning
                             execution_mode 'create' inside the window and 'reconcile' outside it, where
                             the worker must establish what exists at Stripe (by the row's own ref, or
                             by metadata[refund_id] on the PaymentIntent) before it may create anything.
                             Without that decision, an interrupted refund replayed a day later is a
                             SECOND, REAL refund to the buyer's card. The lease idiom is 064's
                             (claim / lease timeout / attempt count), carried by an append-only audit
                             row because kernel.refund is a money-ledger table and 093 does no DDL on one.

DEFECTS IT CLOSES:           (a) refund-execute's sweep answered 501 — every refund interrupted between
                                 Stripe and the callback was UNFINDABLE;
                             (b) a refund stranded at 'submitted' was reachable by nothing, and kept
                                 BP-12 arm 1 (085:249-262) blocking that buyer's account deletion
                                 permanently;
                             (c) the 24-hour double-refund window described above, which E4 §5's
                                 failure matrix does not name.

DAG IMPACT:                  none. Additive; no dependency on any unbuilt object.
SECURITY/MONEY IMPACT:       One new service_role verb. It is read-and-lease only; the money path is
                             unchanged. Census: kernel 116 -> 117 functions, five-schema 250 -> 251
                             routines (141 A14/A14a/F3 name it; 142/143/144/148/154/156/157 updated).
EVIDENCE:                    supabase/tests/158_refund_execution_claim.sql — 39 assertions, all passing
                             on a full local replay of 000-093. Full local pgTAP suite 3016 passing,
                             4 known local-only deltas (the documented baseline, unchanged).

OWNER SIGNATURE REQUIRED:    YES — before 093 is applied anywhere.
```
