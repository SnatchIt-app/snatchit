# POST-FREEZE AMENDMENTS — Phase-2 architecture

**Baseline:** `06fd5ecccc405f416e8f27591ccbbf709771f8ef` (`phase2-architecture-v2`).
**Procedure:** `PHASE_2_ARCHITECTURE_FREEZE.md` §4. One section per amendment, ids `PFA-1`, `PFA-2`, …

## PFA-1 — the per-schema functions-default belt is IMPOSSIBLE; the compensating control is recorded

```
ID:                          PFA-1
FROZEN RULE:                 plan §8/076 Grants row — the ALTER DEFAULT PRIVILEGES belt ("future tables
                             are deny-by-default before their own RLS lands"); the wall's purpose
                             statement (deny-by-default from birth; USAGE "for function EXECUTE only").
IMPLEMENTATION CONFLICT:     security review B-F1 asked the belt to also cover FUNCTIONS (the one class
                             whose built-in default is permissive: implicit PUBLIC EXECUTE, reachable by
                             authenticated wherever it holds schema USAGE).
WHY IMPLEMENTATION CANNOT CONFORM: PostgreSQL schema-scoped ALTER DEFAULT PRIVILEGES entries are ADDITIVE
                             to the built-in default and CANNOT subtract it — proven empirically on
                             PG 17.11 (the REVOKE stores no pg_default_acl row; a subsequently created
                             function remains authenticated-executable). A GLOBAL default revoke would
                             reach every schema including public and change live-rail expectations.
OPTIONS:                     (a) global ADP revoke — rejected (blast radius outside the band);
                             (b) no belt + rely on the corpus's existing per-function explicit-REVOKE
                                 discipline (§11.1a class; every contracted function carries one),
                                 witnessed per-object by each package's pgTAP sweep — CHOSEN;
                             (c) event-trigger auto-revoker — new machinery the freeze does not authorize.
RECOMMENDATION:              (b), with the walled-function ACL sweep assertion added to 140 and required
                             (by this record) in every later package's suite over its own functions.
PACKAGE IMPACT:              076 (comment + test only); a standing test obligation for 077–092 suites.
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       none new — the protection is the already-mandated per-function revoke; the
                             sweep makes a forgotten revoke a red test instead of a silent PUBLIC grant.
OWNER SIGNATURE REQUIRED:    NO — records a platform impossibility and applies the corpus's own existing
                             discipline; no normative behavior changes.
```

## PFA-2 — emit-pair hardening: the REQUIRED no-loss guard and the BE lock_timeout

```
ID:                          PFA-2
FROZEN RULE:                 contracts §17.24a ("a failed envelope write RAISES") + §17.24 idempotency
                             ("UNIQUE(event_type, event_key)"; replay is a successful no-op) + NOTIF §4.2
                             (event_key IS the business event's §6.1 idempotency key) + NOTIF §4.3 (the
                             057:80-86 EXCEPTION WHEN OTHERS shape for BEST-EFFORT).
IMPLEMENTATION CONFLICT:     (a) as literally frozen, a REQUIRED emit whose (event_type, event_key)
                             collides with a DIFFERENT aggregate's standing row would silently no-op —
                             a REQUIRED envelope lost without a raise (hostile review E-F1; conformance
                             review F-10: the corpus admits two readings). (b) PL/pgSQL WHEN OTHERS does
                             not catch QUERY_CANCELED (57014): a producer statement_timeout firing while
                             the BE insert waits on a concurrent uncommitted duplicate pierces the
                             handler and aborts money — the §17.24 "non-raising" absolute is unattainable
                             in the pinned 057 shape (reviews C-F2/E-F2).
WHY IMPLEMENTATION CANNOT CONFORM: (a) both frozen sentences cannot hold at once for a mis-keyed
                             REQUIRED event; (b) the platform's exception model excludes 57014 from
                             WHEN OTHERS categorically.
OPTIONS:                     (a) raise on same-key/different-aggregate in the REQUIRED class only (a true
                             replay still no-ops — both frozen sentences then hold; NOTIF §4.2 makes the
                             colliding call a producer contract violation) — CHOSEN;
                             (b) silent first-wins (the literal reading) — rejected: the exact loss
                             §17.24a exists to forbid;
                             also: SET lock_timeout='2s' on emit_event so a blocked envelope becomes
                             55P03 (caught → warning) instead of consuming the producer's 57014 budget
                             — CHOSEN; the 57014 residual is documented as a known platform limit.
RECOMMENDATION:              as chosen; the canonical 7-parameter emit signature is recorded in §17.24
                             (interface-pin, review E-F4).
PACKAGE IMPACT:              076 (the two function bodies + tests). Noted separately for the 092/edge
                             author (NOT filed here): the void return makes T-EDGE-NOTIFY-01's
                             leave-lease-unconsumed-on-failure unimplementable for edge emitters
                             (review C-F1) — that amendment belongs to the package it blocks and will
                             need an owner signature (it changes an interface or an edge contract).
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       strictly protective — REQUIRED can no longer lose an envelope silently;
                             BE can no longer spend the producer's cancel budget on a lock wait.
OWNER SIGNATURE REQUIRED:    NO — resolves an internal contradiction in the only direction that
                             preserves §17.24a's stated purpose, using NOTIF §4.2's own key contract;
                             a true replay's behavior is unchanged.
```

## ERRATA (recorded, no amendment needed)

- plan §8/076 Rollback says "×4 (incl. notify)" and §5 "three private schemas" — **catalog** is enumerated
  on neither surface; the REVERSIBLE/075-equivalent posture uniquely determines dropping it (review D-F7).
- plan §8/076 Indexes row under-enumerates (omits the partial drain index the schema-spec §13.3 DDL block
  owns); implementation follows §13.3 (review D-F8).
- `notify.outbox.created_at` is implemented `not null default now()` vs §13.3's bare `timestamptz`: the
  emit pair never supplies it, so the bare column would be always-NULL dead weight (reviews A-F4/C-F6/D-F2).
- BE non-raising is not absolute under the pinned 057 shape (57014/ASSERT_FAILURE pierce WHEN OTHERS) —
  known platform residual, documented in PFA-2 (review C-F2).

*(register maintained per PHASE_2_ARCHITECTURE_FREEZE.md §4)*
