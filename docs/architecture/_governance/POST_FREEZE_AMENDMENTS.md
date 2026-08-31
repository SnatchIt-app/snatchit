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

## PFA-3 — the OPEN-3 erased-marker cell is exercised: representation (i), literal `'ERASED'`

```
ID:                          PFA-3
FROZEN RULE:                 dsm-spec §4.1 (terminal write = `kernel.identity_ext.deletion_state :=
                             <terminal value>`) · §4.2 ("candidates, not an invention": (i) the ruled B3
                             deletion_state column itself reaching a terminal 'erased' value — "the
                             natural reading" — vs (i+ii) adding an `erased_at` companion; "the choice of
                             representation and the stored literals are THE ONE REMAINING ENGINEERING
                             CELL of the marker") · §6 OPEN-3 (same "engineering cell" wording, inside a
                             table headed "determined by no ruling — do not implement by guess") ·
                             schema-spec §1.1 CHECK "(ACTIVE · DELETION_PENDING + the OPEN-3 cell)".
IMPLEMENTATION CONFLICT:     077 cannot author the identity_ext CHECK, the sweep's contracted terminal
                             arm (§20.17.4 "erased marker write (OPEN-3 literal)"), or T-RPC-DEL-04/-05
                             without a concrete third literal.
WHY IMPLEMENTATION CANNOT CONFORM WITHOUT EXERCISE: the frozen contract is parameterized over a cell the
                             corpus never binds; someone must bind it to build the package the corpus
                             schedules in 077.
OPTIONS:                     (a) representation (i), literal 'ERASED' — CHOSEN: the corpus's own "natural
                             reading"; the ruled B3 substrate is EXACTLY the three columns (adding
                             erased_at would add a column no ruling authorized — the actual invention);
                             'ERASED' follows the machine's own state-naming (§1.3 header
                             "ERASED / TOMBSTONED"; ACTIVE/DELETION_PENDING are pinned SCREAMING_SNAKE);
                             (b) (i+ii) with erased_at — rejected (unruled column beyond B3);
                             (c) two-literal CHECK + terminal arm gated — rejected (under-implements the
                             frozen §20.17.4 contract; a later literal add is a live-constraint rewrite).
RECOMMENDATION:              (a). A later owner resolution of OPEN-3 that adds erased_at is ADDITIVE and
                             composes with this choice unchanged.
PACKAGE IMPACT:              077 only (the CHECK's third literal + the sweep's terminal write).
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       none — the byte spelling of a ruled state; no new state, no new column,
                             no policy choice.
OWNER SIGNATURE REQUIRED:    NO — the cell is explicitly labeled an ENGINEERING cell twice by the
                             normative machine spec; the direction is the corpus's own stated natural
                             reading and is strictly narrowing.
```

## PFA-4 — `grant_platform_role`'s dual-control parking is impossible against the frozen closed sets; the grant arm fails closed pending the owner's ruling

```
ID:                          PFA-4
FROZEN RULE:                 RPC §20.1.4 — a platform-role grant "creates a kernel.approval_request
                             (action='platform_role.grant') that a second distinct platform_admin must
                             approve, and only the approval inserts the kernel.platform_role row" (C11).
IMPLEMENTATION CONFLICT:     that row is UNINSERTABLE and that flow UNSERVICEABLE as frozen:
                             (1) schema §1.13 closes `action` to exactly
                                 {refund.issue, payout.request, config.set_money_key} (23514);
                             (2) CHECK (4) pairs actions with {order, settlement, config_key} — no
                                 platform_role arm exists;
                             (3) T-RPC-AUTHZ-15 pins the approval_request INSERT writer set to exactly
                                 {request_order_refund, request_org_payout, set_platform_config} and the
                                 corpus calls that enumeration the foundation of the accepted no-FK
                                 residual ("the moment a fourth writer appears, APPR-SUBJ-1 is a
                                 convention again");
                             (4) §1.13's write-authority list matches (3) — no platform-role writer;
                             (5) no approver verb for any action exists before 085 (§17.2), so a parked
                                 grant would be unadjudicable for eight packages regardless.
WHY IMPLEMENTATION CANNOT CONFORM: both sides are frozen; any functioning grant path either extends a
                             ratified closed authority set across five surfaces (the R-11 class the
                             OR-18 precedent routes to the owner) or invents a second dual-control
                             mechanism (forbidden).
OPTIONS:                     (a) widen action/subject/pairing/writer-set/approver arms — an owner ruling
                                 (R-11 class), and it must also decide who adjudicates before 085;
                             (b) FAIL CLOSED (implemented posture): the grant arm validates per contract
                                 (bad_role raises — T-RPC-ROLE-09; self_grant raises — I-11) and then
                                 raises 'dual_control_unavailable' naming this PFA; NO platform_role row
                                 can be minted by anyone; the public.admin_users bootstrap remains the
                                 platform_admin authority; revocation executes directly per the
                                 contract's own direction asymmetry;
                             (c) direct grants without dual control — rejected outright (removes C11).
RECOMMENDATION:              (b) until signed; the owner's signature picks (a)'s exact shape or ratifies
                             (b) as the standing posture.
PACKAGE IMPACT:              077 (grant_platform_role's grant arm; T-RPC-ROLE-07 is unimplementable and
                             deliberately absent from the 141 suite; T-RPC-ROLE-06 holds trivially and is
                             asserted). No other package binds on the platform-grant flow before 085.
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       strictly protective — with the grant arm fail-closed, NO path mints
                             platform authority (dual control's purpose is preserved maximally); the
                             plane operates on the frozen Phase-0 bootstrap exactly as it does today.
OWNER SIGNATURE REQUIRED:    YES — every functioning resolution extends a ratified closed authority set.
                             The fail-closed posture ships without relying on the signature; the
                             signature is required to OPEN the grant path, and is owed before any
                             package needs a minted platform_role row.
```

## PFA-5 — §20.17.3's "STABLE + FOR SHARE" pair is a PostgreSQL impossibility; the predicate is VOLATILE and keeps the lock

```
ID:                          PFA-5
FROZEN RULE:                 RPC §20.17.3 — kernel.is_deletion_pending is a "STABLE definer predicate"
                             whose F-11 serialization has the F-clause host "holding FOR SHARE on the
                             caller's kernel.identity_ext row (taken by the predicate itself; the
                             lazy-create path takes the insert lock)".
IMPLEMENTATION CONFLICT:     PostgreSQL rejects row locking inside non-volatile functions — proven on
                             17.11: `SELECT FOR SHARE is not allowed in a non-volatile function`
                             (0A000 class). The two words cannot both hold.
WHY IMPLEMENTATION CANNOT CONFORM: platform exception model; categorical.
OPTIONS:                     (a) VOLATILE + keep FOR SHARE — CHOSEN: F-11 is a ratified red-team-derived
                             serialization property (no three-transaction interleave can leave new
                             matter owned by an ERASED identity); STABLE costs only optimizer treatment
                             on a definer-internal, sweep-and-F-host-only callee;
                             (b) STABLE without the lock — rejected: deletes the ratified property.
                             Companion derivation, recorded here because it is the same clause: "the
                             lazy-create path takes the insert lock (taken by the predicate itself)" is
                             implemented as the predicate materializing the lazy identity_ext row when
                             absent (INSERT .. ON CONFLICT DO NOTHING, then FOR SHARE) — the inserted
                             row's exclusive lock is what closes the ROW-LESS interleave (a brand-new
                             account acquiring while a concurrent request lands); proven by a live
                             three-session race in the 077 battery.
RECOMMENDATION:              (a).
PACKAGE IMPACT:              077 (the predicate's provolatile marking, witnessed by the 141 suite);
                             later F-clause hosts inherit the same call unchanged.
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       none new — strictly preserves the frozen serialization property.
OWNER SIGNATURE REQUIRED:    NO — a platform impossibility resolved in the only direction that preserves
                             the stated purpose (the PFA-1/PFA-2 class).
```

### PFA-4 — OWNER SIGNATURE (recorded 2026-08-31)

```
STATUS:                      APPROVED
OWNER SIGNATURE REQUIRED:    SATISFIED
FAIL-CLOSED UNTIL IMPLEMENTED: YES
OWNER RULING (verbatim):     "PFA-4 APPROVED — preserve the ratified dual-control requirement for
                             platform authority. Amend the approval_request closed sets only as narrowly
                             as necessary to represent and execute that platform-grant approval path. No
                             platform role may be minted through a direct, single-actor, client-authored,
                             or bypass path. Until the approved dual-control path is implemented,
                             platform-role minting remains fail-closed."
INTERPRETATION CONSTRAINTS (owner-stated): does NOT authorize a generalized approval framework · direct
                             platform-role insertion · single-actor platform grants · client-authored
                             platform authority · any weakening of dual control · platform-role minting
                             before the approved implementation exists.
SCOPE OPENED:                exactly the narrow amendment space PFA-4 option (a) described — the
                             approval_request closed sets (action label · pairing arm · writer fence ·
                             approver arm) may be extended by the platform-grant approval path ONLY,
                             when the package that owns that path implements it. No frozen package
                             ownership places that implementation in 077; 077's grant arm therefore
                             REMAINS FAIL-CLOSED as shipped (the raise precedes any INSERT; no
                             platform_role writer exists), and the future implementation must arrive
                             dual-controlled under this ruling.
```

## STANDING RECORD — 077 RELEASE-TRAIN GATE (owner ruling, recorded 2026-08-31)

```
OWNER RULING (verbatim):     "077 RELEASE-TRAIN GATE — migration 077 must not be applied to production
                             unless the delete-account edge switch and the frozen F-5 live-rail guards
                             ship in the same authorized release train. Merge of PR #30 does not satisfy
                             or waive this production gate."
MERGE BLOCKER:               NO
PRODUCTION APPLY BLOCKER UNTIL SATISFIED: YES
ARTIFACTS REQUIRED ON THE TRAIN: supabase/migrations/077_kernel_identity_orgs_and_roles.sql · the
                             delete-account edge switch (edge §1.8a; retires the PR #28-era 409s;
                             auth.admin.deleteUser called by nothing) · the F-5 live-rail guards
                             (edge/RN — FR-9), with their PR #28 / FR-9 coupling as already frozen and
                             recorded. Deploying 077 without the switch is a compliance outage (the
                             AO/RESTRICT walls break the physical delete path).
AUTHORIZATION:               production apply of 077 is a SEPARATE owner authorization event; neither
                             the PR #30 merge nor this record grants it.
```

## PFA-6 — `set_org_connect_ref`'s EXEC class: the corpus carries two readings; the DEF reading is unbuildable (the C93 shape); the caller-authorized reading is implemented

```
ID:                          PFA-6
FROZEN RULE:                 two contradictory frozen texts about one function's EXEC class:
                             (A) RLS spec :1955 (AUTHZ-R3 ruling row): "kernel.set_org_connect_ref |
                                 ACCEPTED as proposed, NARROWED. DEF — service_role only… No human path
                                 at all" — and RLS §11's intro: "A DEF row appearing with an
                                 authenticated grant in a migration is a defect."
                             (B) RPC §20.1.1: caller-authorized — has_org_role([org_owner,org_finance]),
                                 EDGE-CALLER-JWT bound, RAISES when auth.uid() IS NULL
                                 (T-RPC-CONNECT-04); edge spec :1778 classifies connect-onboarding
                                 Class A with the same predicate.
IMPLEMENTATION CONFLICT:     the two readings are mutually exclusive; 077 must pick one to author the
                             GRANT. Surfaced by red-team E (2026-08-30) — the implementation had
                             followed (B) without filing the contradiction; this record repairs that.
WHY IMPLEMENTATION CANNOT CONFORM TO (A): the DEF configuration is UNBUILDABLE — the same shape the
                             corpus itself proved and repaired at C93/C106 (record_money_denial,
                             ratified "MECHANICAL, not an owner decision… only one value was
                             admissible"): on a service_role connection auth.uid() IS NULL, and this
                             function (i) stamps payout_destination_set_by := auth.uid() — the SoD-1
                             operand, whose whole purpose is naming the human who bound the
                             destination — and (ii) writes an org.connect_ref.bind audit row whose
                             actor_identity is NOT NULL FK→auth.users with no admissible sentinel.
                             Under (A) the INSERT cannot satisfy its own constraints and SoD-1 is
                             unevaluable from day one.
OPTIONS:                     (a) implement (B) — CHOSEN: the only buildable reading; it is also the
                                 STRONGER control (T-RPC-CONNECT-04 makes the service path raise
                                 loudly, the C93 fail-closed shape) and matches the edge spec's
                                 Class A classification of the wrapping function;
                             (b) implement (A) — impossible as shown;
                             (c) implement (A) with a nullable actor / sentinel — the two repairs C93
                                 explicitly rejected.
RECOMMENDATION:              (a); the RLS :1955 cell is the stale surface (its own document proved the
                             identical configuration unbuildable one section later) and should be
                             corrected to (B) at the next ratified doc pass.
PACKAGE IMPACT:              077 only (the GRANT + the in-body predicate, already implemented as (B);
                             tests T-RPC-CONNECT-01..04 witness it).
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       protective — (B) narrows to two named org roles with a live-table
                             predicate and a loud service-path refusal; (A) would have handed the
                             payout-destination bind to the machine identity with no attributable
                             actor, the exact anti-pattern C35/C93 forbid.
OWNER SIGNATURE REQUIRED:    NO — the C93 precedent class, ratified as mechanical: one reading is
                             unbuildable against its own constraints, so only one value is admissible.
```

## ERRATA — package 077 (recorded, no amendment needed)

- G-20 alias resolved by contract precedence: `change_org_role`/`remove_org_member` are the contracted
  names (§2.4/§2.5 signatures; RLS EXEC rows); plan §8/077's "grant_org_role/revoke_org_role" cell is the
  recorded stale alias for the same two contracts. Same-class: the §8 cell's `upsert_identity_ext`
  expands to the §20.1.3 contracted split pair (self/admin — T-RPC-ORG-02 requires the split).
- `identity_demographic_erasure.purge_after` is NULLABLE: the OR-16/F-P1-3/F-8 failsafe ("key absent ⇒
  purge_after = NULL = never-purgeable, never a raise") supersedes DEMOG §10.2's older NOT NULL cell.
- `kernel.organization` carries no command-key column in the frozen DDL, so `create_organization`'s C16
  replay dedupe is non-structural (a duplicate apply yields a second inert 'applied' row); the tables
  that carry the column (org_invite, approval_request) enforce it structurally.
- The org-plane column-scoped read lands as the restrictive benign set (org_id, display_name, status) to
  `authenticated`: role-split "A" cells inside one database role are grant-inexpressible; payout-ref/
  legal_name reads ride later scoped RPCs (fail-closed, additive later).
- The sweep's terminal arm writes NO admin_audit rows: §20.17.4's write list is exhaustive, the sweep has
  no human actor, and an SN-SYSTEM-actor row would forward-reference a 078 seed (the V-class defect).
  System TTL/machine transitions carry no audit per the §12.2 posture (sweep_expired_org_invites same).
- `set_my_contact_prefs`' rate-limit numeric bounds (30/hour via the production fail-closed
  public.check_rate_limit) are implementation-chosen operational thresholds; the contract mandates the
  limiter, not the numbers.
- request/withdraw against an ERASED identity raise `precondition_failed` (the contract calls the state
  "unreachable (no session exists)" while OPEN-7 leaves credential revocation unresolved — sessions can
  outlive erasure, so the defensive arm fails closed).
- Cron job-name strings (`sweep-deletion-pending`, `sweep-expired-org-invites`) and the operator-legible
  `deletion_block_reason` strings are authored under the 014/032/075 house conventions; the frozen
  register pins function, package, cadence and mechanism but no literal strings.
- Q5's `pending → expired` UPDATE from `request_account_deletion` is an approval_request STATE writer by
  §20.17.1/OR-13 Q5; the T-RPC-AUTHZ-15 INSERT fence is untouched.
- `organization_active_idx` is partial `(org_id) WHERE status='active'`; the frozen §1.2 cell reads
  "partial index on status where status='active'" — a constant-predicate column choice; the implemented
  key serves the same dashboard hot-path (red-team E P2).
- plan §8/077's T-SCHEMA-CRM-03 cell ("a second call with the same value… STILL appends") is a stale
  cell of the same class as the E-4 aliases: RPC §17.21 and RLS §16.6 rule "a no-op appends NO event —
  otherwise the log records a client's retry pattern rather than a person's decisions"; the contracts
  win and the no-append form is implemented and tested (red-team E P2).
- Completion-notice BE residual (red-team A/C, 2026-08-30): R2 row 32's "re-emitted next pass" holds for a
  failed PASS (the quarantined subtransaction re-runs terminal entry next tick, deduped by the once-ever
  key); a SWALLOWED emit beneath a COMMITTED tombstone has no retry source, because the row leaves the
  pending cursor and OR-14 forbids holding the transition for a notice. Accepted BEST-EFFORT loss,
  warning-visible — the same class as PFA-2's 57014 residual.
- dsm §1.3 ERASED acquisition refusal (red-team C blocker 2): `is_deletion_pending` stays faithful to its
  frozen name (PENDING only); the two F-6 hosts carry an explicit ERASED refusal twin of E-8, because
  OPEN-7 leaves erased sessions alive. Later F-clause host packages inherit the same obligation: the
  pending predicate alone does not bind ERASED.
- BP-11 write-skew closure (red-team C blocker 1, live-proven): the RPC-side ≥1-org_owner re-counts
  serialize on the ORGANIZATION row, so the sweep's terminal member-delete locks every org the identity
  belongs to (ascending org_id; the identity_ext→organization direction accept_org_invite already uses)
  and re-verifies BP-11 under those locks. The unlocked coalesce evaluation remains the cheap early-out;
  the locked re-check is the enforcement.
- The delete-account edge switch + F-5 live-rail guards are DEPLOY ARTIFACTS on the 077 release train
  (FR-9; edge §1.8a) and are deliberately NOT authored in the 077 package branch: they are edge/RN code
  entangled with open PR #28 (whose merge state is the §20.15 authority), and this pass is barred from
  both deploy and PR #28. STANDING OBLIGATION: the switch MUST ship on the same release train as any
  production apply of 077 — deploying 077 without it is a compliance outage (the AO/RESTRICT walls break
  the physical path). The tombstone-flow storage step remains the named engineering cell of that
  artifact.

## HARDENING-1 — sweep_deletion_pending isolation guard (recorded 2026-08-31; carried by the next band package)

**Finding (merge review C of PR #30, non-blocking).** The BP-11 re-check-under-org-locks in
`kernel.sweep_deletion_pending`'s terminal arm is correct ONLY under READ COMMITTED, where each statement
takes a fresh snapshot. Under REPEATABLE READ the re-check reads the transaction snapshot and the
zero-owner write skew returns — **live-reproduced twice** (the reviewer's schedule, and independently on
2026-08-31 with a sequential RR-snapshot schedule: snapshot fixed → external owner-demote commits →
stale-snapshot sweep tombstoned the identity and left the org with ZERO owners). Unreachable today by
contract: EXECUTE is service_role-only, the sole contracted caller is the CRON_SCHEDULE_REGISTER entry,
and pg_cron runs under default isolation. This record converts that convention into structure.

**Why this rides a later package.** Migration 077 is merged and immutable (its reviewed SHA-256 is the
governance artifact identity). The sweep is NOT a SEAM-2 hook, so §0.4b's stub-replacement discipline
does not cover a body change — **this record is the explicit rationale and authorization trail for a
later `CREATE OR REPLACE` of the sweep body with EXACTLY the block below inserted and no other change.**
Carrier: the next Phase-2 band package PR (078 at the earliest; 079 is the first to touch the deletion
machine), as its own commit, with the pgTAP witness added to that package's suite (plan +1; ratchet +1).

**The guard block, VALIDATED VERBATIM** — inserted at the top of the function body, immediately after
`begin` (top-of-function placement is strictly stronger than the terminal-arm placement the review
suggested: one check per call, and it also covers the live-arm coalesce pass, which shares the
per-statement-snapshot dependency):

```sql
  -- HARDENING-1 (merge review C of PR #30, recorded in the 077 errata): the
  -- BP-11 re-check-under-org-locks below is correct ONLY under READ COMMITTED,
  -- where each statement takes a fresh snapshot — under REPEATABLE READ the
  -- re-check reads the transaction snapshot and the zero-owner write skew
  -- returns (live-reproduced). The sweep's sole contracted caller is the cron
  -- register entry under default isolation; this guard makes the dependency
  -- structural instead of conventional.
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'sweep_deletion_pending requires read committed isolation (the BP-11 re-check depends on per-statement snapshots)';
  end if;
```

**The pgTAP witness, VALIDATED VERBATIM** (for the carrying package's suite):

```sql
SELECT ok(
  (SELECT pg_get_functiondef(k.oid) LIKE '%transaction_isolation%'
      AND pg_get_functiondef(k.oid) LIKE '%read committed%'
     FROM (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'kernel' AND p.proname = 'sweep_deletion_pending'
            OFFSET 0) k),
  'HARDENING-1: the deletion sweep carries the isolation guard (BP-11 re-check depends on per-statement snapshots)');
```

### HARDENING-1 — OWNER APPROVAL (recorded 2026-08-31)

```
STATUS:                      APPROVED
OWNER RULING (verbatim):     "HARDENING-1 APPROVED — merge the governance record. The validated
                             isolation guard and its pgTAP witness are authorized to be carried into the
                             next appropriate Phase-2 band migration via CREATE OR REPLACE, without
                             modifying immutable migration 077. The carrier must make the recorded guard
                             and witness executable before any supported caller may invoke
                             kernel.sweep_deletion_pending outside its current READ COMMITTED-only
                             operating contract."
BINDING CARRIER CONDITION:   any change that would let a supported caller invoke the sweep outside the
                             READ COMMITTED-only operating contract (a new caller, a new mechanism, a
                             non-default-isolation invocation path) REQUIRES the guard + witness to be
                             live FIRST. Until the carrier lands, the cron register's default-isolation
                             entry remains the sole supported caller.
```

**Validation record (2026-08-31, scratch pg17 battery, merged 077 bytes + this block):** (a) the RR
schedule that produced owners=0 on the unhardened body now RAISES the guard error and leaves state
intact (identity still DELETION_PENDING, owners=1); (b) normal READ COMMITTED sweeps behave identically
(BP-11 recorded, terminal entry unchanged); (c) the original concurrent write-skew attack remains
defeated (owners_after=1); (d) the full 141 suite passes 188/188 against the hardened body; (e) the
witness above passes. Until the carrier lands, the gap remains unreachable by contract, and the
CRON_SCHEDULE_REGISTER's default-isolation mechanism is the standing control.

*(register maintained per PHASE_2_ARCHITECTURE_FREEZE.md §4)*

## PFA-7 — the frozen `credential.*`/`door.*` seed constants VIOLATE the frozen cross-config invariant they are asserted against

```
ID:                          PFA-7
FROZEN RULE:                 THREE surfaces assert one invariant OVER THE SEEDED VALUES:
                             door §10.6 — "config('credential.wallet_default_span') +
                               config('credential.wallet_exp_skew') <= config('door.manifest_ttl_interval')
                               … CI asserts it over the seeded values";
                             plan §8/078 Tests — "Cross-config invariant asserted over the seeded values:
                               credential.wallet_default_span + credential.wallet_exp_skew <=
                               door.manifest_ttl_interval";
                             RPC §20.14 :5703 — the same expression, same wording.
                             The SEED VALUES are equally frozen:
                               credential.wallet_default_span = '12 hours'   (WALLET §11.5)
                               credential.wallet_exp_skew     = '6 hours'    (WALLET §11.5)
                               door.manifest_ttl_interval      = '12 hours'   (DOOR §10.6)
IMPLEMENTATION CONFLICT:     12h + 6h = 18h > 12h. The frozen constants FALSIFY the frozen invariant.
                             078 is the package that seeds all three AND the package whose Tests row
                             carries the assertion, so the contradiction is not deferrable: seeding the
                             frozen values ships a RED test, and dropping the test drops a frozen gate.
                             Nothing in the corpus evaluated the arithmetic; door §10.6's own SPEC
                             CORRECTION re-scopes the invariant as "necessary-but-not-sufficient" and
                             explicitly KEEPS it ("stays as an early warning on the operator"), so it is
                             not superseded by the Wallet §5.2a computed-value clamp.
OPTIONS:                     (a) door.manifest_ttl_interval := '18 hours' — REJECTED. It widens how long
                                 a door may admit on stale data, i.e. the width of the offline duplicate-
                                 admission window (schema §2.4.1's own reason for classing door.*
                                 restricted). A security LOOSENING to satisfy a consistency check.
                             (b) credential.wallet_exp_skew := '0 hours' — REJECTED. The skew exists for
                                 clock drift at sign time (WALLET §5.2); zeroing it makes correct passes
                                 expire early at the door.
                             (c) credential.wallet_default_span := '6 hours' — CHOSEN. Derived, not
                                 chosen: 6h is the MAXIMUM value the frozen invariant admits with the
                                 other two constants left EXACTLY frozen
                                 (manifest_ttl - exp_skew = 12h - 6h = 6h). It moves in the TIGHTENING
                                 direction, which RLS §11.3's direction asymmetry rules may execute
                                 without a second approver; it binds ONLY the ends_at IS NULL branch
                                 (WALLET §11.5's own description of the key); and it changes ONE of the
                                 three constants rather than two.
RECOMMENDATION:              (c). Two of the three constants ship byte-exact; the third takes the largest
                             value the frozen invariant permits. Recorded PROVISIONAL and pinned to the
                             owner's OD-25 ("Ratify the session-bounded wallet token profile … the
                             credential.wallet_* seeds"), which is still open.
PACKAGE IMPACT:              078 only (one seed row's value). No object, no signature, no DAG change.
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       protective. Under (c) a wallet pass minted for a session with no ends_at
                             expires at starts_at + 6h + 6h = starts_at + 12h, exactly the offline window
                             any manifest could authorise, instead of 18h — 6 hours of bearer-credential
                             life removed from the branch the invariant exists to bound.
WHY IMPLEMENTATION CANNOT CONFORM: seeding all three constants at their frozen values is arithmetically
                             possible, so this is NOT an impossibility record — it is a record that the
                             frozen values falsify a frozen assertion. Shipping them turns plan §8/078's
                             own Tests-row invariant RED; dropping the assertion drops a frozen gate.
                             There is no conforming option that also ships green, which is precisely the
                             state freeze §2.6 says to STOP on.
OWNER SIGNATURE REQUIRED:    YES. CORRECTED 2026-08-31 after red-team lens E — this field originally read
                             "NO for the merge of 078", reasoning that the Wallet rail is dark
                             (wallet.apple.enabled seeds false) and WALLET §13 items 10a/10b already gate
                             the enable. Both facts are true and neither is freeze §4's test, which
                             admits NO only for corrections the frozen corpus ALREADY UNIQUELY
                             DETERMINES. The OPTIONS block lists THREE arithmetically admissible
                             resolutions, rejecting two on security-direction judgement rather than on
                             any corpus statement foreclosing them — and the value is pinned to OD-25,
                             which is OPEN. A provisional value pinned to an open owner decision is by
                             definition not one the corpus determines. Contrast PFA-8, which earns its NO
                             by showing the alternative reading fails two frozen tests. Merge of 078 was
                             BLOCKED on this signature; see the signature record below.
```

### PFA-7 — OWNER SIGNATURE (recorded 2026-08-31)

```
STATUS:                      APPROVED
OWNER SIGNATURE REQUIRED:    SATISFIED
OWNER VALUE:                 credential.wallet_default_span = '6 hours'
OWNER RULING (verbatim):     "PFA-7 APPROVED — set `credential.wallet_default_span = '6 hours'`.
                             This value is the ratified Phase-2 default for Wallet credential validity,
                             subject to the invariant
                             `wallet_default_span + wallet_exp_skew <= door.manifest_ttl_interval`.
                             This ruling selects the missing seed value only; it does not activate the
                             Wallet rail, expand Wallet scope, change manifest TTL, or waive any later
                             Wallet go-live gate."
INTERPRETATION CONSTRAINTS (owner-stated): credential.wallet_default_span = 6 hours · Wallet rail remains
                             DARK · no Wallet go-live authorization · no change to
                             door.manifest_ttl_interval · no change to wallet_exp_skew (frozen 078
                             requires none) · the invariant must remain mechanically proven · this ruling
                             does not generalize to other TTL choices · no unrelated config modified ·
                             migrations 076/077 untouched.
SCOPE OPENED:                exactly one seed value. The 078 migration already carries '6 hours' under
                             the fail-pending PFA (chosen as the maximum the invariant admits); this
                             signature BINDS that existing value to the owner ruling. No implementation
                             byte changes: the pre-signature migration hash
                             0821dc23c1d77913fb64cffff3ac1632778c8d26ee5fbeaad4a3b9ad03d216a3 remains
                             the ratified hash. OD-25's wallet_default_span component is RESOLVED by this
                             ruling; OD-25's remaining scope (the token profile itself) stays open, as
                             does every WALLET §13 go-live item.
STILL CLOSED:                Wallet activation (wallet.apple.enabled stays false, and flipping it true
                             remains a dual-controlled config write gated on WALLET §13 items 10a/10b) ·
                             any change to the other two invariant constants · any inference from this
                             ruling to any other TTL.
```

## PFA-8 — `visibility` classification: the corpus carries a six-namespace rule and a seven-namespace rule; the six-namespace rule + the explicit public list govern

```
ID:                          PFA-8
FROZEN RULE:                 (A) RLS §8.4 AUTHZ-CFG1 — "restricted covers, AT MINIMUM, the namespaces
                                 refund.* · payout.* · authn.* · comp.* · crm.* · door.*. Everything else
                                 is public ONLY IF A SEED ROW SAYS SO." Schema §2.4.1's ruling table is
                                 identical and names the public class explicitly: the three native flags
                                 + wallet.apple.enabled + notify.announcements_enabled, the fee values,
                                 and "credential.*/wallet.* client spans a client must honour to render a
                                 pass".
                             (B) RLS §11.3 (and RPC §20.2.1's quotation of it) — "All SEVEN namespaces
                                 are also visibility='restricted' under §8.4 AUTHZ-CFG1", the seven being
                                 refund.*, payout.*, authn.*, comp.*, wallet.*, credential.*,
                                 door.session_*.
IMPLEMENTATION CONFLICT:     (B) makes wallet.apple.enabled restricted. That directly falsifies TWO
                             frozen tests 078 must ship: plan §8/078 ("an anon SELECT … DOES return the
                             five feature flags") and schema §2.4.1's non-vacuity guard, where the five
                             are the three native flags + wallet.apple.enabled +
                             notify.announcements_enabled. (B) also makes the three credential client
                             spans unreadable by the client that must honour them to render a pass.
OPTIONS:                     (a) follow (B) — REJECTED: it fails two frozen tests and dark-ends the pass
                                 renderer.
                             (b) follow (A) — CHOSEN. (B) is read as what it is: a sentence about the
                                 DUAL-CONTROL namespace set (which IS seven — RPC §20.2.1 is unambiguous
                                 that wallet.*/credential.*/door.session_* need two approvers to raise)
                                 that over-reached when it appended the visibility claim. Dual-control
                                 membership and read-visibility are separate properties, and §8.4 is the
                                 sentence "an implementer writes the USING clause from" (its own words).
RULING APPLIED:              8 keys ship visibility='public': feature.native_issuance_enabled,
                             feature.native_scanning_enabled, feature.native_resale_enabled,
                             wallet.apple.enabled, notify.announcements_enabled, credential.wallet_exp_skew,
                             credential.wallet_default_span, credential.app_ttl_interval.
                             33 ship 'restricted', including BOTH non-span wallet ops keys
                             (wallet.apple.push_retry_max, wallet.apple.cert_expiry_warn_interval) — they
                             are not client spans, §2.4.1's default is restricted, and "the default is the
                             design". WALLET §11.5's blanket "public-read like every other config value"
                             predates AUTHZ-CFG1 and is the stale surface.
                             The seven-namespace DUAL-CONTROL set is implemented in full and unchanged.
WHY IMPLEMENTATION CANNOT CONFORM: (B) is unbuildable against the corpus's own tests. Seeding
                             wallet.apple.enabled restricted makes plan §8/078's "an anon SELECT ...
                             DOES return the five feature flags" and schema §2.4.1's non-vacuity guard
                             both fail, and it dark-ends the pass renderer that §2.4.1 names as the
                             reason the credential client spans are public. Only one value is admissible.
RECOMMENDATION:              (b) — and the ruling applied below IS that recommendation. RLS §11.3's
                             visibility clause should be struck at the next ratified doc pass; its
                             dual-control claim, which is the sentence's actual subject, stands.
PACKAGE IMPACT:              078 only (the visibility column of 41 seed rows).
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       protective on the two wallet ops keys (fail-closed default applied);
                             neutral elsewhere — the eight public keys are the exact set the frozen
                             non-vacuity test requires a signed-out client to read.
OWNER SIGNATURE REQUIRED:    NO — one reading fails two frozen tests; only one value is admissible
                             (the C93/PFA-6 precedent class). The door.* row remains the one an owner
                             could reasonably move (§8.4 / schema §13.7 S-9); it is seeded restricted.
```

## PFA-9 — the 078 config-key closed world CANNOT be closed from frozen bytes: three classes of gap, recorded rather than invented over

```
ID:                          PFA-9
FROZEN RULE:                 plan §8/078 Purpose: 078 is "every seed row in the chain — the single
                             auditable answer to 'is every gate seeded and every flag OFF?'", and
                             RPC §20.2.1's precondition binds it: "p_key is a MEMBER OF THE SEEDED KEY
                             REGISTRY (078 seeds every key; THIS FUNCTION CREATES NO NEW KEY)". A key
                             078 does not seed can therefore never be set through the only sanctioned
                             path — plan §4: "flips are never a migration".
IMPLEMENTATION CONFLICT:     three classes of key are CONSUMED by the frozen corpus and CANNOT be seeded
                             from it. 078 must not invent them (mission §9's rule generalised).
WHY IMPLEMENTATION CANNOT CONFORM: a key cannot be seeded without a spelling, and a value cannot be
                             seeded without a value. CLASS A keys have a spelling and no authoritative
                             seed row or value; CLASS B has neither a spelling nor a package that agrees
                             with plan §8; CLASS C names a closed set whose members appear nowhere in the
                             corpus. Every one of them would have to be INVENTED, which RPC §20.2.1
                             forbids by name ("a key an implementer invents at 2 a.m. is worse").
OPTIONS:                     (a) invent the missing spellings, values and CHECK members — REJECTED: it is
                                 the defect class the whole corpus exists to prevent, and an invented key
                                 becomes load-bearing the moment a later package reads it;
                             (b) seed nothing for the value-open keys — REJECTED: RPC §20.2.1's registry
                                 precondition then makes those keys unsettable through the only
                                 sanctioned path, and plan §4 forbids a migration flip, so the value
                                 could never be set at all;
                             (c) seed the ROW with a JSON null value and record the absence — CHOSEN. It
                                 is the frozen retention.backup_window_days pattern, applied to the keys
                                 that are in the same position.
RECOMMENDATION:              (c), with each open decision named beside its key so the owner can rule per
                             key rather than per package.
  CLASS A — spelled, consumed, in NO authoritative seed table, NO value anywhere:
                             door.session_touch_interval      — read by schema §3.10a.4 and RPC §1.1d;
                               absent from DOOR §10.6's seed table. The consolidation report §8 item 3
                               files it as a MISSING OBJECT ("create … the door.session_touch_interval
                               seed") and the freeze shipped with it still missing.
                             door.schedule_move_grace_interval — read by catalog.update_event_session
                               (079, RPC §20.2.4) and RLS §14; absent from DOOR §10.6.
                               **FAIL-OPEN EXPOSURE, filed against 079:** the guard is "may move only
                               earlier or by less than config(...)"; a NULL config makes that comparison
                               NULL, so the guard NEVER FIRES and a published session's schedule moves
                               freely once atoms exist — the exact X-12 shape, on a key X-12 does not
                               name. 079 must implement it fail-to-safe (absent ⇒ no later move
                               permitted), not merely seed it.
                             notify.delivery_lease_interval   — read by notify.claim_deliveries (092,
                               RPC §20.10); ODR1_AMENDMENT_DRAFT records it verbatim as "the unseeded
                               notify.delivery_lease_interval" among the open authoring items.
                             inventory.per_user_active_hold_max · inventory.hold_ttl_interval
                               — ADDED 2026-08-31 (completeness correction, package 081; erratum
                               E-28): read by venue.reserve_primary_inventory /
                               create_inventory_hold (RPC §5.3/§5.4); NO frozen spelling, seeded by
                               nobody. Fail-safe: the cap is fail-to-ZERO (AUTHZ-M8 precedent), the TTL
                               REFUSES rather than invent policy. Unreachable while
                               feature.native_issuance_enabled is false. Values owner-owed forward.
                             ticket.expiry_grace              — ADDED 2026-08-31 (completeness
                               correction, package 079; erratum E-18): read by
                               kernel.sweep_expired_ticket_atoms (schema §1.5.1, RPC §12.5); in NO
                               authoritative seed table, NO value anywhere. Same CLASS A disposition:
                               NOT seeded; the consumer is fail-to-safe. The safe direction for THIS
                               consumer is INERT (sweep expires nothing while the key is absent):
                               'expired' is a TERMINAL label, so stamping it on a guessed grace could
                               terminal-ize an atom a later refund path still needs, while not stamping
                               it is the direction the corpus itself declares harmless ("lateness is
                               harmless by construction", plan §8/079; §4.3.1 forbids any path trusting
                               the label). The VALUE is owner-owed forward like the rest of CLASS A.
  CLASS B — cited as a family, NO key spelling exists anywhere:
                             the CRM rate limits/caps/retention (CRM §7.1's fifteen rows are ACTIONS and
                               NUMBERS — "crm_export_request per actor 5/24h" — never platform_config key
                               strings). CRM §7.1 and its §11 traceability row 20 assign these seeds to
                               package **087/I**, which CONTRADICTS plan §8/078's "and the CRM
                               limits/caps/retention/constraint_set_version".
                             the resale platform ceiling read by catalog.set_resale_policy (RPC §20.2.2:
                               "within the platform ceiling read from catalog.platform_config") — no key.
  CLASS C — a CHECK whose closed set has no members:
                             catalog.event.category (schema §2.2): "CHECK against a closed set (Miami
                               MVP; the set is a config value, not a new lookup table)". The members are
                               enumerated nowhere in the corpus.
RULING APPLIED:              (1) CLASS A + CLASS B are NOT seeded. Only keys with an exact frozen
                                 spelling ship; `crm_export.constraint_set_version` is the one CRM key
                                 that has one (CRM §X-9 / §8.3), so it ships here and the unnamed CRM
                                 limits stay with 087, resolving the 078/087 contradiction in the
                                 direction that invents nothing.
                             (2) CLASS C ships as `category text` NULLABLE with NO membership CHECK. A
                                 CHECK cannot read config, and a fabricated member list would be exactly
                                 the "invented at 2 a.m." key RPC §20.2.1 forbids. The column is a display
                                 facet carrying no authority (schema §2.2), like genre_tags beside it.
                             (3) VALUE-OPEN KEYS ARE SEEDED AS ROWS WITH A JSON `null` VALUE — the frozen
                                 retention.backup_window_days pattern generalised ("restricted namespace
                                 row created with NULL value … key-or-value absent ⇒ failsafe"). The ROW
                                 exists, so set_platform_config's registry precondition is satisfied and
                                 the value is one audited config change away; the VALUE is absent, so
                                 every X-12 fail-to-safe consumer takes the restrictive reading. NO
                                 NUMBER IS FABRICATED. SIXTEEN keys ship this way (count corrected
                                 2026-08-31 — this line read "15" against its own enumeration of 16):
                                 refund.* ×7,
                                 payout.* ×4, authn.* ×2, comp.* ×2 (X-12's own pair), and
                                 retention.backup_window_days.
                             (4) FOUR keys take a value the corpus itself states (count corrected
                                 2026-08-31 — the enumeration was always four), and are marked
                                 PROVISIONAL: authn.money_role_maturity_hours = 72 (RPC §1.1e's explicit
                                 instruction — "seed the key at the RESTRICTIVE END of the range and
                                 record the seed as provisional — never leave it unseeded"; RLS MD-14's
                                 range is 24–72h and 72 is the restrictive end);
                                 notify.announcement_hold_seconds = 300 and
                                 notify.announcement_dual_control_threshold = 500 (ODR-56 "Silence.
                                 Seeds ship at 300 s / 500 recipients"); refund.scanned_atom_policy =
                                 'platform_review' (MONEY §7.2 "recommended default").
PACKAGE IMPACT:              078 (what is seeded and what is not); FILED FORWARD against 079
                             (schedule_move_grace fail-to-safe), 086 (session_touch), 087 (the CRM key
                             registry + the resale ceiling key), 092 (delivery_lease).
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       protective — every unresolved value is absent rather than guessed, and every
                             consumer of an absent value is contractually fail-to-safe (X-12). The one
                             residual is 079's schedule_move_grace guard, filed above as a fail-open the
                             consuming package must close in code, not by seeding.
OWNER SIGNATURE REQUIRED:    NO for 078 — 078 relies on none of the missing keys and fabricates none of
                             the missing values. YES, per key, before the consuming package's gate goes
                             live: D-3 (the money numbers), MD-14 (the maturity window), OR-16/DEMOG §8.5
                             (the retention window — OPS VERIFICATION REQUIRED), ODR-56 (the announcement
                             pair), and a new owner cell for the CLASS A/B/C gaps above.
```

## PFA-10 — five 078 RPCs call `kernel.has_venue_role`, authored in 080: SEAM-1's own arithmetic and plan §8's placement disagree

```
ID:                          PFA-10
FROZEN RULE:                 SEAM-1 (schema §13.2, as CORRECTED by R2B): "A function is authored in the
                             package equal to max() of the packages creating every table it reads or
                             writes" — and the R2B correction extends it: "SEAM-1 is corrected to take
                             max() over reads, writes AND CALLS." §13.2's method paragraph states the
                             same reduction, "max( package of every table it reads or writes, package of
                             every function it calls )".
IMPLEMENTATION CONFLICT:     five functions plan §8/078 places in 078 call kernel.has_venue_role
                             (created in 080) in their authority predicate:
                               catalog.update_venue          (RPC §3.3 / RLS §11.1a)
                               catalog.create_event          (RPC §4.1)
                               catalog.create_event_session  (RPC §4.3, "Role: as §4.1")
                               catalog.update_event          (RPC §20.2.3 / RLS §11.1b)
                               catalog.set_resale_policy      (RPC §20.2.2 / RLS §11.1)
                             Under the corrected SEAM-1 each scores max(078, 080) = 080. §13.2's sweep
                             caught the IDENTICAL edge for four RLS POLICIES (FR-10…FR-13, all four the
                             has_venue_role/has_event_role call) and created SEAM-3 for them — and did
                             not re-run the function rows against the widened definition, so these five
                             were never scored. plpgsql bodies are not validated at CREATE FUNCTION
                             (the corpus's own R2B finding), so the chain replays GREEN and the venue arm
                             raises 42883 at first execution until 080 lands.
OPTIONS:                     (a) move the five to 080 — REJECTED: it rewrites the object sets of two
                                 packages, one of which (078) is the package being built and the other
                                 (080) is not authorised; registry, plan §8 and the parity spec all place
                                 them in 078.
                             (b) SEAM-2 stub kernel.has_venue_role in 078 — INADMISSIBLE: the SEAM-2 hook
                                 registry is closed at hook_count 19, a ratified constant (OR-21), and
                                 has_venue_role is not a member. Adding a 20th hook is an owner amendment.
                             (c) re-inline the venue-role join inside the five bodies — FORBIDDEN by RM-3,
                                 explicitly, and it is the failure mode SEAM-3 exists to make unnecessary.
                             (d) KEEP the placement per plan §8 and ORDER the predicate so the org arm is
                                 evaluated in its own statement FIRST — CHOSEN. plpgsql prepares each
                                 statement lazily on first execution, so an org_owner/org_admin caller
                                 never parses the deferred name and the function is fully live and fully
                                 testable in 078; a venue_manager caller raises 42883 until 080. That is
                                 the posture SEAM-3 assigns to exactly this seam: "A deferred [artifact]
                                 FAILS CLOSED for exactly the packages it is deferred across", and it
                                 closes one package later, as SEAM-3's own deferral does.
RULING APPLIED:              (d), with the deferral stated in this package's header (so nobody "fixes" it
                             by re-inlining) and filed against 080 (so nobody forgets that the venue arm
                             of these five first becomes reachable there). No exception handler swallows
                             the 42883: an undefined-function catch would mask a genuine typo forever.
PACKAGE IMPACT:              078 (statement ordering + header note); 080 (the arm becomes reachable).
                             No object moves, no package is added, renamed or renumbered.
DAG IMPACT:                  none — 078 → 080 would run BACKWARDS and is not declarable; this is why the
                             deferral, not an edge, is the repair. 080 already declares 078.
SECURITY/MONEY IMPACT:       fail-closed. Between 078 and 080 the venue plane cannot create or edit
                             catalog objects — the same intended dark window RLS §16.10a already
                             describes for the three deferred read policies ("Between this package and 080
                             the venue plane cannot read these tables — intended, fail-closed, and it
                             closes one package later").
WHY IMPLEMENTATION CANNOT CONFORM: the name kernel.has_venue_role does not exist at 078 and cannot be
                             made to. Option (b) is closed by a ratified constant (hook_count 19),
                             option (c) by a named prohibition (RM-3), and option (a) rewrites two
                             packages' object sets. What is left is WHERE in the body the name is
                             mentioned, which is what this record decides.
RECOMMENDATION:              (d), and the deferral should be stated in 080's plan entry at the next
                             ratified doc pass, exactly as SEAM-3 requires for the three read policies
                             it already covers.
SECOND ARM — RM-3 / has_org_role_over_venue (ADDED 2026-08-31, red-team B):
                             the same five functions also resolve the ORG-over-scope arm by reading the
                             row's own denormalised org_id and calling kernel.has_org_role. RLS §11.1a
                             (update_venue) and RPC §20.2.2 (set_resale_policy, verbatim: "resolved
                             through has_org_role_over_venue, §1.1a, NEVER a re-inlined join") name
                             kernel.has_org_role_over_venue / _over_event for that arm, and RM-3 forbids
                             re-inlining the inheritance join by name. BOTH helpers are authored in 080.
                             The corpus contradicts itself here: RPC §3.3's own Role line for the SAME
                             function writes the re-inlined form, "has_org_role(org_of_venue, [org_owner,
                             org_admin])". Taken together with the venue arm, EVERY authority arm of
                             these five functions resolves only at 080 — which is SEAM-1 saying they
                             belong there, against a plan §8 row that places them here.
                             RULING APPLIED: the re-inlined org arm is kept, because the alternative is
                             that 078 can author no venue-scoped or event-scoped write verb at all, and
                             because RPC §3.3 writes that exact form. It is now DISCLOSED rather than
                             asserted-away: the in-body comment that claimed "never a re-inlined
                             inheritance join (RM-3)" said the opposite of what the code does and has
                             been corrected to state the deferral.
OWNER SIGNATURE REQUIRED:    NO — the placement is the frozen plan's; only the evaluation ORDER inside
                             the body is decided here, and it is decided in the direction that makes the
                             authorised org path work and leaves the deferred path fail-closed. The
                             SECOND ARM is a disclosure of a contradiction between two frozen texts about
                             the same function, resolved toward the one that is buildable at 078.
```

### PFA-10 — DISCHARGED (recorded 2026-08-31, package 080)

```
STATUS:                      DISCHARGED — no body replacement was owed and none occurred. The deferred
                             name kernel.has_venue_role was AUTHORED by 080 (its frozen owner), plpgsql
                             late-binding resolved every deferred arm in the six 078/079 RPC bodies
                             UNCHANGED, and suite 144 §E asserts the activation boundary behaviourally
                             (venue_manager live on update_event/update_venue/create_event_session/
                             update_event_session; venue_marketing on marketing-only columns; scanner,
                             box_office and wrong-venue denied; the time/freeze guards and reason-code
                             requirements unmoved). Every label array in those arms was verified against
                             the canonical six of ROLE_MODEL §3.4 before activation — all conform.
                             No owner signature was required (the record's own NO verdict), and the
                             SECOND-ARM (RM-3) disclosure stands unchanged: the re-inlined ORG arms in
                             078/079 remain as disclosed; has_org_role_over_venue/_over_event now exist
                             for every FUTURE authority arm, which is where RM-3 binds them.
```

## PFA-11 — `catalog.effective_freeze_at`'s frozen `authenticated` grant publishes a `restricted` config value by subtraction

```
ID:                          PFA-11
FROZEN RULE:                 (A) RLS §11.4 EXEC table: "catalog.effective_freeze_at · kernel.is_transfer_frozen
                                 | authenticated (STABLE reads; is_transfer_frozen is already the RN
                                 eligibility boolean, §14.3)". An explicit, unconditional grant.
                             (B) schema §2.4.1 / RLS §8.4 AUTHZ-CFG1 classify door.* RESTRICTED, and §8.4
                                 states the rule that governs client reads: "The RN client and the web
                                 client read only public keys — and if a screen needs a restricted value,
                                 the answer is a scoped RPC that returns the DECISION, never the
                                 THRESHOLD."
IMPLEMENTATION CONFLICT:     the two cannot both hold. effective_freeze_at returns
                             LEAST(door_open_at, COALESCE(doors_at, starts_at) + config(
                             'door.implicit_freeze_offset_interval')). doors_at, starts_at and door_open_at
                             are all column-granted to anon/authenticated on a world-readable table, so any
                             signed-in client calls the function on a visible session, subtracts the
                             publicly-readable COALESCE(doors_at, starts_at), and recovers
                             door.implicit_freeze_offset_interval EXACTLY — one call, no trace, no
                             probing phase. §2.4.1's own threat model is that these values are "an attack
                             calibration table" stating "how long a door may operate on stale data".
                             Surfaced by red-team lens B (2026-08-31).
WHY IMPLEMENTATION CANNOT CONFORM: the leak is a property of the FUNCTION'S RETURN VALUE, not of its
                             implementation. No body satisfies both (A) and (B): the offset is what the
                             function is for. Only the grant class or the key's classification can move,
                             and both are frozen.
OPTIONS:                     (a) implement (A) verbatim and disclose — CHOSEN for this package. The grant
                                 is what §11.4 says; changing it is the reinterpretation.
                             (b) make effective_freeze_at DEF and route clients through
                                 kernel.is_transfer_frozen's boolean — the shape §8.4 prescribes and RPC
                                 §12.4a implies ("is_transfer_frozen is the ONLY freeze read for RPC
                                 rechecks, the RN eligibility boolean, and the edge layer"). Contradicts
                                 §11.4's explicit row and may break an RN countdown that needs the
                                 timestamp.
                             (c) reclassify door.implicit_freeze_offset_interval as public — honest, since
                                 under (A) it is already derivable, but it publishes a value §2.4.1 ruled
                                 restricted after argument.
RECOMMENDATION:              (b). It is the only option under which the restricted classification means
                             anything, and §8.4 states the substitution ("a scoped RPC that returns the
                             decision") as the general answer to exactly this shape. Requires the owner to
                             strike or narrow §11.4's row.
PACKAGE IMPACT:              078 (the grant), 079 (is_transfer_frozen is the client surface under (b)).
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       a restricted door parameter is readable by every authenticated client today,
                             under the frozen grant. Not money; it is the width of the offline
                             duplicate-admission window. A second, weaker leg: the function carries no
                             authority predicate (none is contracted), so it also answers for sessions of
                             draft events — an existence oracle that needs a known session_id.
OWNER SIGNATURE REQUIRED:    YES to CHANGE anything — moving the grant class or the key's classification
                             is normative. NO to merge 078, which implements (A), the frozen text, and
                             relies on no unsigned amendment.
```

## PFA-12 — two frozen surfaces disagree on whether `visibility` can ever change; under the implemented reading no reclassification path exists at all

```
ID:                          PFA-12
FROZEN RULE:                 (A) schema §2.4 Write authority: "visibility is set at key creation and
                                 set_platform_config MAY NOT CHANGE IT — a function that can flip a key to
                                 public is a function that can publish the ceilings", with T-SCHEMA-CFG-03
                                 asserting it.
                             (B) RLS §8.4 footnote 20: "visibility is set at seed time and is itself
                                 CHANGED ONLY THROUGH set_platform_config — publishing a restricted key is
                                 a config change like any other, and in a dual-controlled namespace it
                                 takes two approvers." RLS §17 X-16 leans the same way ("private until
                                 someone deliberately publishes it").
IMPLEMENTATION CONFLICT:     (A) forbids the function the capability (B) says is its job. 078 implements
                             (A): set_platform_config copies visibility forward and cannot change it.
                             The consequence is that NO path to reclassify a key exists anywhere — not
                             through the RPC (A forbids it) and not through a migration (plan §4: "flips
                             are never a migration"). A key seeded into the wrong class is stuck there
                             until a package is written to move it.
WHY IMPLEMENTATION CANNOT CONFORM: a single function cannot both be barred from writing a column and be
                             the only writer of it.
OPTIONS:                     (a) implement (A) — CHOSEN. It is the reading a frozen TEST pins
                                 (T-SCHEMA-CFG-03), it is the fail-closed direction, and its failure mode
                                 is loud (a client cannot read a value it needs) rather than silent (a
                                 ceiling leaked).
                             (b) implement (B) — a reclassification path exists, but the function that can
                                 publish the ceilings exists too, which is the exposure §2.4.1 was written
                                 to close.
RECOMMENDATION:              (a) for the code; the owner should decide whether reclassification needs a
                             path at all, and if so whether it is a dual-controlled arm of
                             set_platform_config or a deliberate one-off migration.
PACKAGE IMPACT:              078 only.
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       protective — (a) is the direction that cannot publish a ceiling. The cost is
                             operational rigidity, disclosed here rather than discovered later.
OWNER SIGNATURE REQUIRED:    NO for 078 — a frozen test pins (a), so only one value is admissible (the
                             C93/PFA-6 precedent class). YES before any reclassification path is built.
```

## PFA-13 — `kernel.unlock_ticket`'s R-40 dispute re-arm reads an `088` table from a `079` function, and no seam is recorded

```
ID:                          PFA-13
FROZEN RULE:                 (A) RPC §7.4 (and RLS §11's unlock row, verbatim): "an unlock resolves the
                                 overlay to `dispute_hold` — not `none` — while an open
                                 `kernel.dispute_native` row joins the atom's originating payment
                                 (`R-40` re-arm)". §7.4 is a 079-authored function's contract.
                             (B) `kernel.dispute_native` and the whole R-40 dispute surface are `088`
                                 objects (plan §8/088; registry: "kernel.record_dispute_native …
                                 SEAM-1 max(077,079,085,087,088)=088"), and `kernel.payment_native`
                                 (the join's other leg) is `085`.
                             (C) The corpus's own no-forward-reference discipline (SEAM-1/SEAM-2,
                                 §0.4b; FR-7's withdrawal of the tolerate-missing-operand hatch) and
                                 the mission rule that a package must not implement later-package
                                 operands early.
IMPLEMENTATION CONFLICT:     the arm's operands do not exist at 079. A static reference is 42P01 at
                             creation-world replay; a runtime to_regclass probe would IMPLEMENT 088's
                             dispute predicate early (against (C)); a new SEAM-2 hook
                             (dispute_freeze_active stub) is an object the frozen closed world does not
                             carry (parity EXTRA = 0); and 088's recorded replacement list
                             (settlement_royalty_lines, on_atom_voided, on_door_freeze_engaged,
                             door_freeze_drain_preview) does NOT name unlock_ticket — the corpus
                             mandates the behaviour and records no mechanism for it to become live.
WHY IMPLEMENTATION CANNOT CONFORM: no body writable at 079 satisfies (A), (B) and (C) simultaneously.
OPTIONS:                     (a) runtime to_regclass-guarded dynamic check — REJECTED by (C): it is
                                 088's operand implemented at 079, and the corpus resolves forward
                                 shapes structurally (the §13.5-B precedent), never by runtime probes;
                             (b) a new SEAM-2 stub pair — REJECTED: EXTRA = 0; and C110 shows hooks are
                                 added only where a RECORDED caller needs them;
                             (c) author unlock at 079 releasing to 'none' — the TRUE value over the
                                 empty world (no dispute can exist before 088; every native release
                                 path that could observe one arrives at 085+) — and record that 088
                                 OWES a body-only CREATE OR REPLACE of kernel.unlock_ticket (SEAM-2a
                                 discipline: signature, parameter names, return type verbatim) adding
                                 the dispute_hold arm. CHOSEN. This is the same shape as every §20.17.5
                                 stub ("the neutral result is the true value over an empty world; the
                                 replacing package asserts the stub body is no longer live") applied to
                                 one arm of a real body, and the same declaration-only transcription
                                 class as the SEAM-1 edge corrections.
RECOMMENDATION:              (c). 088's implementer adds the arm and a T-RPC-DISP-09-family witness that
                                 the release resolves to dispute_hold while a dispute is open.
PACKAGE IMPACT:              079 (the body ships without the arm, disclosed in-body); 088 (owes the
                             replacement).
DAG IMPACT:                  none — 088 already depends on 079.
SECURITY/MONEY IMPACT:       none at 079 (the arm is unreachable: no dispute object exists, and unlock's
                             callers all arrive at 085+). At 088, failing to carry the replacement would
                             weaken the R-40 persist-until-resolve property — which is why the
                             obligation is recorded HERE, where the arm is visibly absent.
OWNER SIGNATURE REQUIRED:    NO — the corpus uniquely determines the correction: the arm is mandated
                             (A), its operands' package is fixed (B), body-only replacement is the
                             corpus's own mechanism (SEAM-2a/C110's "a CREATE OR REPLACE that ran
                             before its stub would be silently overwritten" discipline), and (a)/(b)
                             are each closed by a named rule. The only admissible resolution is (c).
```

## PFA-14 — the frozen RLS `anon`-public-availability arm is undeliverable at the venue-schema layer; the delivery boundary is amended to a separately reviewed public read surface (E-30 ratified)

```
ID:                          PFA-14  (ratifies E-30 — reclassified from an ownerless erratum)
FROZEN RULE:                 RLS §9.1 grants `anon` a SELECT of `public`-visibility ticket types and
                             §9.2 the `remaining` availability projection — an UNAUTHENTICATED public
                             browsing arm at the `venue`-schema layer.
IMPLEMENTATION CONFLICT:     migration 076 (immutable, hash-locked, merged) grants `venue` schema USAGE
                             to `authenticated` ONLY (076:78) and not to `anon`. An anon principal
                             cannot reach the `venue` schema at all — a schema-level 42501 fires before
                             any §9.1/§9.2 policy is evaluated. The frozen anon arm is therefore
                             undeliverable from 081 without widening 076's schema-USAGE boundary, a
                             security-boundary change 076 owns and did not make.
OPTIONS:                     (a) grant `venue` USAGE to `anon` from 081 — REJECTED. It reaches into an
                                 immutable, hash-locked earlier package's security boundary and widens
                                 raw-schema reach for the unauthenticated role; the corpus does not
                                 uniquely determine that 076's omission was an error rather than a
                                 deliberate boundary choice.
                             (b) leave the anon arm undelivered at the venue-schema layer, scope the two
                                 `_sel_public` policies and their grants to `authenticated` (the
                                 deliverable half — any logged-in fan reads public availability under
                                 §9.1/§9.2 semantics), and route unauthenticated public browsing through
                                 a separately reviewed public storefront / server / edge read surface
                                 that projects the same public semantics without exposing the raw
                                 `venue` schema. CHOSEN by owner.
WHY IMPLEMENTATION CANNOT CONFORM: 076 is hash-locked; 081 cannot conform to §9.1/§9.2's anon arm without
                             mutating 076's grant, and whether the anon arm belongs at the venue-schema
                             layer or at a public read surface is a delivery-boundary choice the frozen
                             corpus does not settle — exactly freeze §4's "not uniquely determined" test.
PACKAGE IMPACT:              081 only (the two `_sel_public` policies + their grants scoped to
                             `authenticated`; no `anon` grant). No object added or removed; NO SQL
                             behaviour change from the 55d06c5 implementation — this ratifies the posture
                             already shipped, it does not alter it.
DAG IMPACT:                  none.
SECURITY/MONEY IMPACT:       protective. Fail-closed: no unauthenticated raw-schema access is opened.
                             Native issuance and Buy Now are both dark, so no public purchase path
                             depends on the anon arm today.
OWNER SIGNATURE REQUIRED:    YES — the resolution is a delivery-boundary choice (venue-schema layer vs a
                             separately reviewed public read surface) that the frozen corpus does not
                             uniquely determine, and it AMENDS a frozen §9.1/§9.2 requirement. This was
                             recorded first as E-30 "no amendment needed"; that classification was WRONG
                             — amending the delivery boundary is precisely what fail-closed did, and
                             freeze §4 admits NO only for corrections the corpus already uniquely
                             determines. Corrected here and escalated. See the signature record below.
```

### PFA-14 — OWNER SIGNATURE (recorded 2026-08-31)

```
STATUS:                      SATISFIED / RATIFIED
OWNER SIGNATURE REQUIRED:    YES
OWNER SIGNATURE:             APPROVED
OWNER RULING (verbatim):     "PFA-14 APPROVED — direct anonymous PostgREST access to the `venue` schema
                             remains CLOSED for Phase 2. Package 081 must not widen the 076 schema-USAGE
                             boundary to `anon`. The frozen §9.1/§9.2 anonymous public-availability
                             requirement is amended so that unauthenticated public ticket-type and
                             availability browsing is delivered through a separately reviewed public
                             storefront/server/edge read surface, not direct `anon` table access.
                             Authenticated fans may continue to receive the 081 RLS-governed public
                             projections. This ruling changes only the delivery boundary; it does not
                             broaden venue data visibility, activate native issuance, activate Buy Now,
                             or authorize production."
INTERPRETATION CONSTRAINTS (owner-stated): direct `anon` `venue`-schema access stays CLOSED for Phase 2 ·
                             081 must NOT grant `venue` USAGE to `anon` · the §9.1/§9.2 anon arm is
                             amended as a delivery-boundary change only · unauthenticated public browsing
                             is delivered by a separately reviewed public storefront/server/edge read
                             surface, NOT direct anon table access · authenticated fans keep the 081
                             RLS-governed public projections · no broadening of venue data visibility ·
                             native issuance stays OFF · Buy Now stays OFF · no production authorization.
SCOPE OPENED:                the delivery boundary only. NO implementation byte changes: the ratified 081
                             migration hash
                             15d018d6a1ecfc8cf2188d4fec6f3bc94892077ff28a81789192300b1442a55d is
                             unchanged by this ratification. E-30 is reclassified from an ownerless
                             erratum to a ratified PFA record and now references PFA-14.
FORWARD OBLIGATION (governed): the eventual unauthenticated public storefront / server / edge read
                             surface MUST preserve the frozen §9.1/§9.2 public projection semantics
                             (public-visibility ticket types + the `remaining` availability projection)
                             WITHOUT exposing the raw `venue` schema to `anon`. OWNER: UNASSIGNED — the
                             frozen migration DAG (076–092) identifies NO package that owns a public
                             web/edge read surface, so this is NOT assigned to an arbitrary package; it
                             remains a GOVERNED FORWARD OBLIGATION until the corpus or a later owner
                             ruling names its owner. It must be a separately reviewed surface
                             (owner-stated).
STILL CLOSED:                direct `anon` `venue`-schema USAGE (076's boundary is unchanged) · native
                             issuance (dark) · Buy Now (dark) · Wallet (dark) · production.
```

## PFA-15 — `venue.cancel_pending_order`'s contracted `service_role` invocation is undeliverable under the immutable 076 schema boundary (the PFA-14 class)

```
ID:                          PFA-15
FROZEN RULE:                 RLS §11 grades `venue.cancel_pending_order` "DEF — `service_role` only;
                             `stripe-webhook` on a TERMINAL payment failure only", and the edge registry
                             names it the `payment_intent.payment_failed` writer for `native_primary`. Its
                             sole contracted caller is the stripe-webhook acting as `service_role`.
IMPLEMENTATION CONFLICT:     migration 076 (immutable, hash-locked) grants `venue` schema USAGE to
                             `authenticated` ONLY (076:78); plan §8/076 states "service_role is a machine
                             identity, never a human grant target." A `service_role` session therefore hits
                             a schema-level 42501 at the `venue` wall BEFORE any policy or the function's own
                             EXECUTE grant is consulted (the exact wall E-30/PFA-14 record). The
                             `grant execute … to service_role` 082 adds is INERT — the caller cannot reach
                             the schema. (081's DEF hold-sweep carries the same grant but is genuinely
                             reachable because `pg_cron` invokes it as the postgres owner;
                             `cancel_pending_order` has NO cron and no in-package postgres-context caller —
                             so the "same as 081's sweep" test-comment disposition was wrong, red-team F.)
OPTIONS:                     (a) grant `service_role` USAGE on `venue` (at the payment-rail package, or by
                                 amending 076) — widens the machine role's raw-schema reach;
                             (b) ratify a postgres-owner DB connection for the stripe-webhook edge fn;
                             (c) front the webhook with an authenticated edge-caller holding venue USAGE;
                             (d) make it cron-driven like the 081 sweep — but that adds a cron object the
                                 frozen 082 closed world does not carry.
                             Each changes the external/service-role access boundary differently; the corpus
                             does NOT uniquely determine which.
WHY IMPLEMENTATION CANNOT CONFORM: the function is a frozen 082 object (parity spec + §20.7.9) that 082 MUST
                             ship; its body is correct; but the frozen contract's caller (service_role)
                             cannot reach it under the immutable 076 boundary, and how it is reached is a
                             delivery-boundary choice the corpus leaves open — freeze §4's "not uniquely
                             determined" test, identical to the anon arm escalated to PFA-14.
PACKAGE IMPACT:              082 ships the function (body correct) + the service_role EXECUTE grant; the
                             reachability mechanism is deferred to the owner. No 082 SQL behaviour change is
                             needed for any option except (a)/(d), which touch other packages.
SECURITY/MONEY IMPACT:       none while native issuance is dark (no orders ⇒ no webhook ⇒ the path is never
                             exercised). Uncaught, it ships a dead terminal-failure writer to the payment
                             rail once the rail activates.
OWNER SIGNATURE REQUIRED:    YES — the resolution changes the external/service-role access boundary, a policy
                             choice the corpus does not determine, and the identical class the anon arm was
                             escalated to PFA-14 (owner-signed) for. Recorded here rather than disposed of by
                             a test comment (red-team F, PR #36).
```

### PFA-15 — OWNER SIGNATURE (recorded 2026-08-31)

```
STATUS:                      SATISFIED / RATIFIED
OWNER SIGNATURE REQUIRED:    YES
OWNER SIGNATURE:             APPROVED
OWNER RULING:                Option (a) — the payment-rail package (085) GRANTS `service_role` USAGE on
                             schema `venue`. The frozen "service_role stripe-webhook" caller contract for
                             `venue.cancel_pending_order` (and the other `venue` DEF money functions) is
                             kept literally; `service_role`'s `venue` reach is widened to exactly the DEF
                             functions it already holds EXECUTE on. 076 stays immutable; the grant lands in
                             085.
INTERPRETATION CONSTRAINTS (owner-scoped): the widening is `GRANT USAGE ON SCHEMA venue TO service_role`
                             ONLY — NOT table/DML grants (the DEF functions stay the sole write path; RLS
                             and the deny-all postures are unchanged); it does NOT grant `service_role`
                             USAGE on `kernel`/`catalog` unless those packages separately require it; it
                             does NOT widen `anon` (PFA-14 unchanged); it activates nothing (native
                             issuance stays dark).
SCOPE OPENED:                one schema-USAGE grant, owned by 085. 082 ships unchanged — its
                             `grant execute … to service_role` becomes reachable once 085's USAGE grant
                             lands. NO 082 SQL byte changes: the 082 migration hash
                             3a97e3d956f75691bc35e850282fbef94146bce65dc46f4f3e9d99b334cd3db4 is unchanged.
FORWARD OBLIGATION (governed → 085): `085_kernel_money_native` MUST include `GRANT USAGE ON SCHEMA venue
                             TO service_role` so the stripe-webhook can reach `venue.cancel_pending_order`
                             and `venue.finalize_primary_order` (both DEF/`service_role` in `venue`).
                             085's review gates on this grant being present and scoped to USAGE-only.
                             Until 085 lands, cancel is inert (dark rail).
```

## ERRATA — package 078 (recorded, no amendment needed)

**E-1 — `public.profiles` seed uses `ON CONFLICT DO UPDATE`, not `DO NOTHING`.** Schema §1.16 requires
both *"`ON CONFLICT DO NOTHING`, exactly as `019` does"* and *"a `public.profiles` row for each **carrying
the display label above**"*. Those are incompatible on this database: the production trigger
`on_auth_user_created` fires on the `auth.users` INSERT and creates the `profiles` row FIRST with a NULL
`display_name`, so `DO NOTHING` makes the explicit label a no-op and the Transfer View renders exactly the
blank §1.16 says it must never render. **Verified live: at the frozen spelling all three sentinels —
including `019`'s own — carry a NULL `display_name`.** The seed uses `ON CONFLICT (id) DO UPDATE SET
display_name = excluded.display_name`, scoped to the two sentinel ids and converging on replay, so the
replay-safety property `DO NOTHING` was chosen *for* is preserved in full while the label requirement is
actually met.

**E-2 — `auth.users.role` for the two sentinels is `'sentinel'`, not `'authenticated'`.** §1.16's fourth
reason for refusing the `019` sentinel is that it is *"person-shaped (`role='authenticated'`, a real
profiles row, an email address)"* and that a custody sink *"must be non-authenticable by construction"*.
Reproducing `role='authenticated'` would reproduce the property the section rejects. The four required
properties (no password hash, `email_confirmed_at` NULL, `.internal` address, no role grant) are all
implemented and asserted; the role label is the mechanical expression of the fourth reason.

**E-3 — `catalog.resale_policy.mode` uses schema §2.5's SEVEN labels; RPC §20.2.2's `{off, capped, free}`
is the stale surface.** The RPC sketch names three modes that are not in the storage CHECK (`capped` is
§2.5's `fixed_cap`; `free` has no analogue). The schema spec is the storage authority and the versioned
snapshot reference depends on the stored label, so the seven-label set governs. `set_resale_policy`
validates against it and refuses `capped` with `bad_mode`.

**E-4 — `set_resale_policy`'s `p_scope_kind` admits `venue|event` only.** RPC §20.2.2 lists
`{org, venue, event}`, but `catalog.resale_policy` has no `org_id` column and its coherence CHECK requires
exactly one of `venue_id`/`event_id` to match `scope_kind` (schema §2.5). An `org` scope has nowhere to
land; it is refused with `bad_scope`.

**E-5 — `subject_id` for `subject_kind='config_key'` is `md5(key)::uuid`.** `kernel.approval_request.subject_id`
and `kernel.admin_audit.subject_id` are both `uuid NOT NULL`; a config key is text. The corpus specifies
the pairing (`APPR-SUBJ-1`) but not the derivation. A deterministic `md5(key)::uuid` is used and the
literal key travels in `payload`, which is where the approving verb in `085` must read it from. There is
no FK to satisfy — RPC §17.0a accepts that residual on the record.

**E-6 — a parked config request expires 72 hours after creation.** `kernel.approval_request.expires_at` is
`NOT NULL` with `CHECK (expires_at > created_at)`, and the frozen corpus specifies no parking horizon for
`config.set_money_key` (`refund.request_ttl_hours` governs refunds, not config). 72 hours is authored here
and recorded; a later package may make it a config key.

**E-7 — `catalog.platform_config` uses the composite PK `(key, version)`**, plan §7's primary option, as
that section requires the choice to be documented in the `078` header. It is.

**E-8 — the "visibility is constant across every version of a key" property is enforced in the WRITER, not
by a constraint.** A CHECK cannot span rows and a trigger would be an object the frozen closed world does
not carry (parity `EXTRA = 0`). `set_platform_config` copies `visibility` forward from the current version
and cannot change it; `T-SCHEMA-CFG-02` asserts the property over the table. The residual — a direct
superuser INSERT with a different `visibility` — is accepted here on the record, the same class as
`APPR-SUBJ-1`'s no-FK residual, and it must never be described as equivalent to a constraint.

**E-9 — `catalog.event.category` ships with NO membership CHECK.** See PFA-9 CLASS C: the frozen corpus
enumerates no members for the closed set schema §2.2 names. A fabricated list would be exactly the key
RPC §20.2.1 forbids an implementer from inventing.

**E-10 — three `141` assertions were re-scoped by this package.** `A14` (kernel function count 40 → 41),
`F2` (the `authenticated` EXECUTE closure) and `F3` (the `service_role` closure) each gain
`kernel.money_role_grant_matured`, which `078` authors by SEAM-1 `max(077, 078) = 078`. Both closures
remain exact-by-name, so nothing was weakened; the count rose by exactly one and by exactly the function
the frozen placement puts here.

**E-11 — the `kernel.sweep_deletion_pending` body replacement is APPROVED CROSS-PACKAGE HARDENING, not a
078 architecture object.** `PACKAGE_OBJECT_PARITY_SPEC.md` files the sweep under `077`, so a parity
extractor that scores *created* objects will read 078's `CREATE OR REPLACE` as `EXTRA`. It is not: the
object is 077's, the body change is authorized by the HARDENING-1 owner approval, and 078 creates no
object of that name. A parity harness needs a REPLACE exemption keyed to this record; the frozen parity
spec carries none because it predates the ruling. Raised by red-team lens C.

**E-12 — the two `service_role` EXECUTE grants this package originally issued have been REMOVED.**
`catalog.effective_freeze_at` (RLS §11.4) and `kernel.money_role_grant_matured` (RPC §1.1e, RLS §11.2)
each carry exactly one frozen EXEC class, `authenticated`. The `service_role` grants were reasoned from
"definer RPCs in later packages call them", which is wrong twice over: a definer callee runs as its owner
and needs no grant (RLS §1.3 `GP-3a`), and `076` gives `service_role` no `USAGE` on `catalog` or `kernel`
at all, so the grants were inert as well as uncontracted. Raised by red-team lenses A and B.

**E-13 — `catalog_resale_policy_sel_public` cannot express "the version in force".** RLS §8.5's cell reads
`A(policy in force)`. A "greatest version for this scope target" conjunct must read
`catalog.resale_policy` itself, which re-enters the policy and raises `42P17 infinite recursion` (observed,
not predicted). The two ways out — an `is_current` column or a `SECURITY DEFINER` helper — are both objects
the frozen closed world does not carry, and parity is `EXTRA = 0`. The predicate implemented is the
PARENT'S VISIBILITY, which is narrow (satisfying `I-2` and `T-RLS-POL-02`) and closes the real exposure
red-team lens B found: `set_resale_policy` never checks the parent's status, so a policy set on a draft
event or an unapproved venue was world-readable while the parent row was hidden. Every version of a
*visible* parent remains readable, which is what a client needs to interpret the `(policy_id, version)`
pair `market.listing_native` snapshots.

**E-14 — `set_platform_config` does not dedupe on `p_command_key`.** RPC §20.2.1 states *"Idempotency.
`p_command_key` + `UNIQUE(key, version)`"*, but `catalog.platform_config` carries no command-key column in
the frozen DDL, so replay dedupe on the direct path is non-structural: it is value equality
(`noop_replay`). A replay of the same command key carrying a DIFFERENT value inserts a new version, which
is the correct outcome for a real change but is not idempotency. The parked path IS structurally
idempotent — `kernel.approval_request` carries `UNIQUE(requested_by, command_idempotency_key)`. Same class
as the `077` errata `E-3` for `kernel.organization`.

**E-15 — `T-SCHEMA-SENTINEL-05` cannot be asserted at 078 and is filed forward to 079.** The frozen
assertion is that the `019` anonymization sentinel appears in zero rows of
`kernel.tickets.current_owner_id` and of every `kernel.ticket_ownership_log` identity column. Both tables
arrive in `079`. Suite 142 asserts the nearest reachable property instead (the sentinel holds no
`kernel.identity_ext` row and appears as actor in zero `kernel.admin_audit` rows) and labels it as such;
the real `-05` is owed by `079`. Likewise `T-SCHEMA-SENTINEL-03`'s `has_venue_role` clause, which is owed
by `080`. Raised in review as an undisclosed substitution; disclosed here.

**E-16 — the HARDENING-1 guard refuses `READ UNCOMMITTED`, which PostgreSQL implements as READ
COMMITTED.** Verified live on PostgreSQL 17.11: `BEGIN ISOLATION LEVEL READ UNCOMMITTED` yields
`current_setting('transaction_isolation') = 'read uncommitted'`, and the guard raises. That caller is
snapshot-safe — PostgreSQL maps READ UNCOMMITTED onto READ COMMITTED semantics — so the refusal is
over-strict. It is fail-closed, availability-only, and unreachable under the cron-only operating contract.
**The guard text is owner-approved VERBATIM, so it is NOT edited here**; correcting it needs a new
governance record. Raised by red-team lens F.

**E-17 — the recorded HARDENING-1 witness cannot detect a NEUTERED guard.** It is a substring match on
`pg_get_functiondef` for `transaction_isolation` and `read committed`. Appending `and false` to the guard
condition leaves both strings present and the suite green. The witness is mandated verbatim and is kept
verbatim; the behavioural half — that a REPEATABLE READ call actually raises — cannot be added to suite
142 because pgTAP runs inside one transaction and PostgreSQL refuses `SET TRANSACTION ISOLATION LEVEL`
after the first query. It was proven out-of-suite instead, on the merged bytes: RR raises with state
intact, READ COMMITTED is unchanged, and the concurrent write skew stays defeated at every schedule tried.
Raised by red-team lens F.

## ERRATA — package 079 (recorded, no amendment needed)

**E-18 — `ticket.expiry_grace` is a PFA-9 CLASS A key the register missed; the consumer ships
fail-INERT.** Spelled and consumed by `kernel.sweep_expired_ticket_atoms` (schema §1.5.1, RPC §12.5), in
no authoritative seed table, no value anywhere — the exact CLASS A definition, absent from PFA-9's
enumeration. Corrected in place (the tally-fix precedent) and applied under PFA-9's own ruling: NOT
seeded; the sweep returns `{swept_count: 0}` while the key is absent, NULL, or unparseable, because
`expired` is a terminal label and the inert direction is the only one the corpus declares harmless.
Additionally disclosed: the contract writes the signature as `(p_limit int)`; the implementation carries
`DEFAULT 100` (mirroring `kernel.sweep_deletion_pending(p_limit int DEFAULT 100)`) so the register's bare
`cron.schedule` call form is invocable — identity `(integer)` is unchanged. And a session with
`ends_at IS NULL` expires nothing: "ended by more than the grace" is unevaluable without an end, and the
sweep never guesses one.

**E-19 — two DOOR §8.1 clauses are platform impossibilities, each resolved in its only admissible
direction.** (1) The CHECK `expires_at <= granted_at + config('door.max_override_interval')` cannot exist:
a CHECK cannot read a table. The ceiling is enforced as precondition 2 of
`kernel.grant_door_freeze_override` (`086`), the table's sole contracted INSERT writer; the static half
(`expires_at > granted_at`) ships as a real CHECK. (2) The partial index `(session_id) WHERE revoked_at IS
NULL AND expires_at > now()` cannot exist: an index predicate must be immutable. Shipped as
`(session_id, expires_at) WHERE revoked_at IS NULL` — the expiry comparison lives in the reader
(`is_transfer_frozen`), which still walks only unrevoked rows of the session. Both are the PFA-1/PFA-2
impossibility class: no owner bit, one admissible direction each.

**E-20 — `kernel.tg_custody_head_is_ledger_tail` evaluates the LIVE head at fire time, not the queued
row-version's `NEW`.** Schema §1.6.2 writes the clauses over `NEW.current_owner_id` /
`NEW.credential_version`. A deferred constraint-trigger queue holds one event per ROW VERSION, so a
transaction performing two correct custody moves on the same atom (each properly paired) queues an
intermediate version whose `NEW` no longer matches the final tail — the literal reading RAISES ON A
CORRECT TRANSACTION (observed live before correction). The invariant the record states is over the state
"at COMMIT", and the shipped body reads `kernel.tickets`' current row for `NEW.ticket_atom_id`, which is
exactly that state; the three clauses, the firing columns (`current_owner_id`, `credential_version` — and
nothing else), and DEFERRABLE INITIALLY DEFERRED are all verbatim. A row deleted before commit (possible
only in the pre-go-live window, where the rollback's emptiness guard lives) is skipped.

**E-21 — the corpus's "no new cron entry" phrases for the atom-expiry sweep are SUPERSEDED text, disclosed
here so a reader of schema §1.5.1 / RPC §12.5 alone is not misled.** Both sections say the sweep "rides the
2-minute heartbeat that already runs — no new cron entry". The P0-1 correction (2026-08-29) found no shared
heartbeat exists; plan §8/079's own row carries the correction ("this package creates its OWN explicit
cron.schedule entry — register row: 079, 2 min") and `_governance/CRON_SCHEDULE_REGISTER.md` line 35 corrects
"every 'rides the existing heartbeat' phrase in the corpus". 079 ships the dedicated entry, per the register.
Raised by red-team F (PR #33) because the correction lived only in the plan row and the register, not here.

**E-22 — FORWARD OBLIGATION (083/085/088, the ledger-writing engines): the MB-4 verify trigger is not
self-sufficient under concurrency; the engine atom-lock invariant is load-bearing.**
`kernel.tg_custody_head_is_ledger_tail` fires only on head writes (`current_owner_id`/`credential_version`)
and compares to the MAX(sequence) tail. Red-team B (PR #33) demonstrated with real interleavings that (a) a
NAKED ledger append — a log row with no head write — never fires it and can commit a silent head≠tail
desync, and (b) a concurrent naked append can make the trigger FALSE-REJECT a correct move. Unreachable at
079: the ledger is deny-all and no ledger-writing engine exists. The closure is the construction §1.6.1
already describes: **every engine that appends `kernel.ticket_ownership_log` MUST hold the atom's
`kernel.tickets` row `FOR UPDATE` across both the head write and the append, in the same transaction.**
Recorded here so 083's mint, 085's void and 088's transfer engines implement that invariant as load-bearing,
not stylistic; a defense-in-depth guard on the ledger side is admissible future hardening, not shipped here
(EXTRA = 0).

**E-23 — FORWARD OBLIGATION (082/085/088, the acquisition engines): `kernel.is_deletion_pending` is a
pending-flag, not a recipient-validity gate.** It returns FALSE for an ERASED identity, so the F-11 lock
closes the read→tombstone window but does not stop new matter landing on an ALREADY-TOMBSTONED identity.
Every acquisition path (checkout buyer, p2p recipient, market buyer) must independently refuse a
non-ACTIVE counterparty — which is what the dsm §1.3 ERASED refusals already contract; this erratum pins
that the refusal cannot be discharged by calling `is_deletion_pending` alone. Raised by red-team B (PR #33).

## ERRATA — package 080 (recorded, no amendment needed)

**E-24 — per-policy column scoping does not exist in PostgreSQL; the I-4 discipline on `kernel.tickets`
is carried by the role's ONE column grant, which therefore reaches the owner read too.** RLS §16.10a:
*"I-4 column discipline is carried by the GRANT, not by the USING. Footnote 8 of §7.5 scopes the
issuing-venue read so that current_owner_id is NOT among the granted columns"* — while §7.5's owner cell
reads *"owner reads own atom in full"*. One role (`authenticated`), one column set: both cannot hold.
Resolved in the direction §16.10a itself states (it is the later, DDL-directive text, written for the
package that creates the venue policy): 080 re-issues `kernel.tickets`' authenticated grant as the sixteen
non-PII columns, excluding `current_owner_id`. The owner's ROW visibility is unaffected (`sel_owner`'s
predicate is a policy expression, outside column ACLs), and an owner client never needs to SELECT the
column — it is by definition their own `auth.uid()`. The 079 suite's one column-referencing client probe
was re-scoped (143 I13). Platform/postgres reads are unaffected. The PFA-1/PFA-2 impossibility class: one
admissible direction, no owner bit.

**E-25 — the "079-deferred venue policy" and the SEAM-3/FR-10..12 deferrals DISCHARGED on schedule.**
The four AUTHZ-PKG1 policies (`catalog_venue_sel_venue`, `catalog_event_sel_venue`,
`catalog_event_session_sel_venue`, `kernel_tickets_sel_venue`) were created by 080 with the §16.10a USING
clauses verbatim — including the R3-3a corrected `status <> 'draft'` second tier, the OPEN-1 deliberate
absence of the `venue_scanner` arm on `event_session` (filed to the RLS owner, not guessed), and the
GP-3-NOTE unsplit org arm on `kernel_tickets_sel_venue`. Suites 142/143's deferral assertions inverted to
presence-pinned-to-080; suite 144 asserts the predicates behaviourally per label (T-RLS-POL-03's positive
half).

**E-26 — a staff grant could resurrect a tombstone's authority; closed with the F-11 construction and a
terminal-state refusal.** `venue.grant_staff_role`'s frozen preconditions require only a live `auth.users`
row — an ERASED identity still has one (the tombstone never calls `auth.admin.deleteUser`), so a manager
could re-grant authority the INV #23 cleanup had just removed, making the CLEANED disposition
non-terminal. Worse, the pure static check races: a grant that OBSERVED `DELETION_PENDING` could commit
after the tombstone (proven with a real two-session interleave: `ERASED ∧ holds-authority`). Both closed:
the grant refuses an `ERASED` target (`identity_erased` — dsm §1.3's terminality applied to the one 080
verb that confers authority on a counterparty; the E-23 principle, discharged here for this verb rather
than owed forward), and the check takes `FOR SHARE` on the target's `kernel.identity_ext` row — the F-11
construction — so the sweep's terminal-entry `FOR UPDATE` serializes against it in both orders
(grant-first: the next pass's INV #23 cleanup removes the fresh row; tombstone-first: the check reads
ERASED and refuses). `DELETION_PENDING` targets are deliberately NOT refused: staff roles are not
blockers, and dsm §3.2's freeze surface names no staff-grant refusal. Verified live in both orders;
zero-integrity `ERASED ∧ authority = ∅` held.

**E-27 — DISCLOSURE (RLS owner): `catalog_event_session_sel_venue` reveals a DRAFT event's SESSION timing
to non-manager venue ops, while `catalog_event_sel_venue` hides the event row from them.** The frozen
§16.10a clause for the session policy names five labels
(`venue_manager·venue_finance·venue_box_office·venue_marketing·venue_promoter_manager`) with NO
parent-event-status filter, whereas the sibling event policy's R3-3a two-tier split withholds a `draft`
event from every label except `venue_manager`. Consequently `venue_finance`/`box_office`/`marketing`/
`promoter_manager` at the venue can read a draft event's `event_session` rows (start/doors/label — which
disclose the show date) even though the `catalog.event` row itself is hidden from them. The anon path is
safe (it resolves *through* `catalog.event`, inheriting the corrected predicate); the venue-staff path does
not. **080 ships the ratified clause VERBATIM — this is a gloss-vs-clause inconsistency in the spec (§16.10's
gloss "sessions of visible events" vs the written §16.10a clause, which carries no such join), NOT an
implementation defect, and NOT changed here.** Exposure is to trusted same-venue staff and is metadata only.
Filed for the RLS owner beside OPEN-1/OPEN-2: if the board wants draft-event session timing withheld from
non-manager venue labels, that is a new ratification (an added `EXISTS (visible parent event)` conjunct),
not a clarification. Raised independently by two red-team reviewers on PR #34.

## ERRATA — package 081 (recorded, no amendment needed — EXCEPT E-30, escalated and ratified as PFA-14)

**E-28 — two config keys the inventory-hold path reads have NO frozen spelling; they are PFA-9 CLASS A,
seeded by nobody, and the path fails SAFE without them.** `venue.reserve_primary_inventory` and
`venue.create_inventory_hold` read a per-user active-hold cap (RPC §5.3: *"per-user cap read from
catalog.platform_config"*) and a hold TTL (RPC §5.3: *"expires_at := now() + server_max_ttl"*). Neither key
has a spelling anywhere in the corpus — the same CLASS A shape as `ticket.expiry_grace` (E-18). 081 reads
them as **`inventory.per_user_active_hold_max`** and **`inventory.hold_ttl_interval`**, seeds NEITHER, and
ships fail-safe in the frozen directions: the cap is **fail-to-ZERO** (`COALESCE(config, 0)` — the AUTHZ-M8
precedent: a missing seed refuses every reserve loudly, never admits unbounded holds silently), and the TTL
**REFUSES** (`hold_ttl_unset`) rather than invent a business policy (a TTL is policy, not a default — the
one direction PFA-9 forbids is inventing a value). Both are unreachable while native issuance is dark:
reserve/create-hold check `feature.native_issuance_enabled` (false for all of 081's life) and refuse
`feature_disabled` BEFORE either key is read — proven by flipping the flag inside a rolled-back test txn
(suite 145 §G) and observing the fail-to-zero and refuse-unset behaviours. The VALUES are owner-owed
forward, exactly like the rest of PFA-9 CLASS A; PFA-9's CLASS A list is extended by these two keys (the
E-18 tally-fix precedent).

**E-29 — the raw inventory counters cannot be shown to venue staff but hidden from fans via a column ACL;
the E-24 impossibility, recomplicated by two visibility tiers.** RLS §9.2 footnote 23 wants
`capacity`/`held`/`sold` *"col-scoped to venue staff + platform"* while `remaining` is *"world-readable"*.
PostgreSQL column ACLs are per-(relation, role), and venue staff, fans and platform staff are ALL the single
`authenticated` role (staff/platform status lives in `kernel.*_role` rows, not in Postgres roles) — so no
column grant can split them. Resolved the fail-closed way, the direction §9.2's own hot-path discipline
points: `remaining` is a GENERATED column; `authenticated` is granted SELECT on every column EXCEPT the three
raw counters; and venue staff read the counters through the batch/capacity RPC **result JSON**
(`create_inventory_batch`/`set_batch_capacity` return `{capacity, held, sold, remaining}`), never a table
SELECT — the same construction the money plane uses. The `venue_inventory_batch_sel_venue` row policy still
governs WHICH rows a staff member sees. Same class as E-24 (`kernel.tickets.current_owner_id`): one
admissible direction, no owner bit.

**E-30 — RLS §9.1/§9.2's `anon`-public-availability arm is undeliverable: migration 076 (immutable) grants
schema `venue` USAGE to `authenticated` only. RECLASSIFIED → ratified as PFA-14 (owner-signed 2026-08-31);
this is NOT an ownerless erratum and NOT "no amendment needed" — the delivery boundary was amended under
owner signature.** §9.1 grants `anon` a read of `public`-visibility ticket
types (and §9.2 the `remaining` projection), but `076_create_phase2_schemas_and_grants.sql:78` grants
`venue` USAGE to `authenticated` and not `anon`, so an anon principal cannot reach the venue schema at all —
a schema-level `42501` fires before any policy runs. 076 is hash-locked and merged; widening `anon`'s
schema access from 081 would be a security-boundary change 076 owns and did not make, so 081 scopes the two
`_sel_public` policies and their grants to `authenticated` (the deliverable half — any logged-in fan reads
public availability) and does NOT touch anon's access. The delivery boundary — whether the frozen anon arm
lives at the venue-schema layer or at a separately reviewed public read surface — is NOT one the frozen
corpus uniquely determines, so it was escalated to the owner and is governed by **PFA-14**: direct `anon`
`venue`-schema access stays CLOSED for Phase 2, and unauthenticated public browsing is delivered through a
separately reviewed public storefront/server/edge read surface that preserves the §9.1/§9.2 public
projection semantics WITHOUT exposing the raw `venue` schema (a GOVERNED FORWARD OBLIGATION, owner
UNASSIGNED — the migration DAG 076–092 names no owner for a public web/edge read surface). Fail-closed;
disclosed rather than silently widened, then owner-ratified. Suite 145 §H asserts the anon wall and the
authenticated-fan delivery.

**E-31 — `venue.inventory_movement.movement_kind` needs a fifth value, `capacity_change`, that schema §3.4's
enum omits but RPC §20.3.2 mandates.** §3.4 lists `movement_kind` ∈ `{hold, release, issue, void_return}`,
while RPC §20.3.2 contracts `set_batch_capacity` to write *"a cause-keyed `capacity_change` row, so the
counter still reconciles to its ledger"*. The two frozen texts disagree; the CHECK ships with the fifth
value because a capacity edit that wrote no ledger row would break the C27 discipline §20.3.2 states (every
delta has a ledger row). §20.3.2 (the writer's contract) governs over §3.4's enumeration. Raised by
red-team A and F (PR #35). Also recorded here: the four inventory-config RPCs (`create_ticket_type`,
`set_ticket_type_price`, `create_inventory_batch`, `set_batch_capacity`) express their org arm through
`kernel.has_org_role_over_venue` — the RM-3 sanctioned helper — rather than a direct
`has_org_role(catalog.event.org_id)`; §5.1/§5.2's `has_org_role(org)` spelling is reconciled toward RM-3's
helper-derived discipline (functionally identical: `catalog.event.org_id` is denormalised from
`catalog.venue.org_id` and always resolves the same org).

**E-32 — sharding (the MVP-optional hot-row mitigation, schema §3.3) is DEFERRED; the unsharded aggregate
counter delivers full oversell-safety.** Schema §3.3 introduces `venue.inventory_batch_shard` as *"MVP-optional
hot-row mitigation"* and §3.3.1 point 4 + plan §8/081's Tests row describe a sharded draw. Implementing it
partially (creating shard rows that the reserve/hold/release path never draws from) would leave the shards
inert and break the §3.3 *"Σshard == batch"* reconciliation the moment a sharded batch took a hold — the
defect red-team A and C found in the first cut. Resolved by the schema's own *"MVP-optional"*: 081
`create_inventory_batch` refuses `shard_count>0` (`sharding_deferred`), so `is_sharded` is always false and no
shard rows are ever created; the `venue.inventory_batch_shard` table stays as the frozen schema object for
when sharding is built later. Oversell-safety is unaffected — the aggregate `inventory_batch` row's
`CHECK + FOR UPDATE + single-writer` is the authoritative guard (§3.3.1), and there is no thundering herd to
relieve while native issuance is dark. The plan §8/081 sharded-draw test defers with the feature; schema §3.3
(the subject-matter owner, O11) is the authority that it is optional. A later ratification builds the shard
draw + the single-shard last-unit fallback + a Σshard==batch reconciliation job. Raised by red-team A/C.

**E-33 — `venue.create_inventory_batch`'s frozen `p_command_key` idempotency has no persistence surface;
RPC §5.2 and schema §3.2 conflict.** §5.2 contracts *"Idempotency: `p_command_key`"*, but §3.2 gives
`venue.inventory_batch` no command-key column and *"no unique beyond PK (a type/session may have several
batches by release_kind)"* — the table is DELIBERATELY non-unique, so there is no surface on which to dedup a
replayed create. 081 validates `p_command_key` for presence (the frozen signature) but cannot enforce
idempotency: a retried create over-provisions (a second batch of extra capacity). This is **benign** — it is
capacity OVER-provision, not oversell (each batch is independently oversell-safe by its own CHECK), the path
is admin-frequency, and the duplicate is operator-visible. Adding a `command_idempotency_key` column + UNIQUE
would deviate from §3.2's stated columns and its *"no unique beyond PK"* — so the tension is disclosed rather
than resolved by inventing a surface, exactly as E-28/29/30 do. Filed for the owner: if create idempotency is
required, it is a ratified §3.2 schema addition, not a clarification. Raised by red-team F (PR #35).

## ERRATA — package 082 (recorded, no amendment needed)

**E-34 — schema §13.2's parity row still credits the `venue.order` attribution-candidate columns + freeze
trigger to `090`; the governing `R2B`/`C112` amendment births them in `082`.** §13.2 (`PHYSICAL_..._SCHEMA_SPEC.md`)
lists *"`090 | venue.order.attribution_candidate_code_id / _link_id (+ freeze trigger) | … ✓ — FK targets are
090`"*, but the ratified `R2B`/`C112` repair (registry §2.1, defect `V3`; plan §8/082) moves the **columns and
their freeze guard IN to `082`** as plain `uuid NULL`, keeping only the FK **adoption** (`NOT VALID`+`VALIDATE`)
in `090`. The registry itself flags §13.2 as the stale end: *"§13.2's 090 row reads '✓ — FK targets are 090',
correctly, about the wrong end of the edge. The **writer** was never asked"* — `venue.create_primary_checkout`
(082) is the writer, and a body writing a column a later package `ADD COLUMN`s is a `42703`. 082 therefore
creates the two columns as plain `uuid NULL` (no FK), authors the freeze guard, and leaves them **inert (NULL)**
— the promoter tables the FKs target (`venue.promoter_code`/`_link`) do not exist until 090, so nothing at 082
can populate them and no forward reference is emitted. The corpus uniquely determines the placement (the
governing amendment vs a stale record row), so this is an erratum, not a PFA. §13.2's parity row is owed a
non-blocking correction by the schema-spec owner.

**E-35 — `PACKAGE_OBJECT_PARITY_SPEC`'s 082 required-object list omits `kernel.list_my_org_contact_consents`.**
The spec's `082|…` required rows (8: the four tables + `create_primary_checkout` · `cancel_pending_order` ·
`grant_`/`withdraw_org_contact_consent`) do not include the read RPC `kernel.list_my_org_contact_consents`,
although plan §8/082, CRM §11.1-8, and RPC §17.21 all author it in 082 (the third of *"`kernel.org_contact_consent`
+ its three RPCs"*, §13.2:4068). The spec is a *"DEMO seed … re-derive every row from plan §8 by hand"* and
already carries `list_my_org_contact_consents` on its `MENTION-OK` list, so the implemented read RPC is NOT
flagged EXTRA — but the required-list is genuinely short by one row. 082 builds the RPC per the three governing
contracts; the parity spec is owed a required-row addition. The two bespoke trigger functions and the
`deletion_blockers_orders` body-replacement (a 077-born object) are likewise below the spec's coarse
tables+writers grain and are covered by suite 146's structural assertions. Corpus-determined; erratum.

**E-36 — `WRITER_CANONICAL_UNIVERSE`'s `venue.order` writer set omits `venue.cancel_pending_order`.** The
canonical universe lists four writers for `venue.order` (`create_primary_checkout`, `finalize_primary_order`,
`bind_order_attribution`, `refund_primary_order`), but schema §3.7's write-authority registry (corrected
2026-08-29, `OR-7`), RLS §6/§9.7, RPC §20.7.9, and `PACKAGE_OBJECT_PARITY_SPEC` all carry the fifth writer
`venue.cancel_pending_order` (→`cancelled`, the webhook terminal-failure writer). 082 authors it as a
`service_role`-only definer (no human path; actor = the `SN-SYSTEM` sentinel). At the 082 checkpoint the
`venue.order` writers that EXIST are `create_primary_checkout` + `cancel_pending_order` (both 082); the other
three are forward (085/090) — the writer fence at 082 is therefore exact, and the canonical universe is owed a
fifth-writer row. Corpus-determined (four frozen surfaces name the writer, one omits it); erratum. **The
STRUCTURAL writer fence (which functions may write `venue.order`) is exact; the writer's REACHABILITY — its
sole contracted caller (`service_role`/stripe-webhook) cannot reach `venue` under the 076 boundary — is the
separate PFA-15 (owner-signed) concern, not a writer-fence defect (red-team F, PR #36).**

**E-23 082-arm — SATISFIED (recorded).** `venue.create_primary_checkout` proves the buyer ACTIVE, not merely
not-pending: the F-1 `kernel.is_deletion_pending` refusal PLUS an explicit `deletion_state='ERASED'` refusal,
using the exact idiom 077's F-6 acquisition gate uses (the E-8 defensive twin). `buyer_id = auth.uid()` (the
frozen §6.1 signature carries no buyer parameter), and an ERASED identity cannot authenticate, so the ERASED
arm is defensive — mandated present by E-23 ("cannot be discharged by `is_deletion_pending` alone"), fired
early (before any order work). Suite 146 §E proves both refusals and the mutation-resistance (an ACTIVE buyer
clears the gate and fails later on `no_items`, so the gate — not luck — stops the non-ACTIVE cases). **E-23
remains a forward obligation for 085 and 088.** The `source` column is server-tagged `'web'` — an
**owner-owed-forward** classification (E-39, corrected from "settled"): with no source hint in the frozen §6.1
signature it is the inert placeholder while the rail is dark, resolved before native issuance activates.

**E-37 — RLS §9.7's `venue_scanner = A(own-session orders)` is not expressible with the frozen role model; 082
fails closed (no direct scanner order read).** §9.7 (footnote 28) grades `venue_scanner` a read of its
**own-session** orders — narrower than `venue_manager`/`venue_finance` (venue-wide). But `venue_scanner` is a
venue-grain `staff_role` (080) with no session-membership concept, so `kernel.has_venue_role(venue,
[venue_scanner])` would grant every session's orders at the venue — a cross-session over-read, the exact
over-exposure §9.7 avoided by scoping scanner narrower. Venue-scope is INADMISSIBLE (it erases §9.7's
deliberate narrowing); session-scope is inexpressible at 082. Resolved **fail-closed**: `venue_scanner` is NOT
in the `venue_order[_item]_sel_venue` arm, so a scanner gets NO direct order read — the tightening direction
(RLS §11.3, single-approver), disclosed rather than over-granted. Suite 146 §I5 regression-pins that no order
policy references `venue_scanner`. The §9.7 "own-session order read" is a **governed forward obligation**:
delivered by a session-scoped read RPC / session-membership mechanism in a later package, or blessed to
venue-scope by an owner ruling. (`platform_support` — graded V, redacted-RPC-only — was likewise removed from
the direct policy arm; that is a plain §9.7-conformance fix, not a deviation.) Raised by red-team D (PR #36).

**E-38 — RPC §17.21's `p_notice_version` "validated against the known list" has no registry to validate against
at 082.** `grant_org_contact_consent` is contracted to validate `p_notice_version` *"against the known list"*,
but no notice-version registry object exists at the 082 checkpoint (none is created by 076–082, none is a
frozen 082 object). 082 validates PRESENCE (non-empty) — the deliverable, fail-safe half — and the known-list
check is a **governed forward obligation** (the E-28 shape): the spec owner supplies a notice-version registry
(or relaxes the clause) before consent capture goes live. Never invented. Raised by red-team A (PR #36).

**E-39 — `venue."order".source` server default `'web'` is an owner-owed-forward classification, not a settled
default.** §6.1's frozen signature carries no source hint, yet `source` CHECKs the closed set `{app, web, door,
promoter_link}`, so the server MUST tag a value, and `create_primary_checkout` is callable from both the native
app and web. Tagging every native checkout `'web'` mis-classifies app/door/promoter_link origins; nothing in
the corpus forecloses the other labels (the PFA-7 shape — a value chosen among admissible options on
judgement). **Inert today** (dark rail ⇒ no order is written), so not a blocker, but the honest disposition is
PFA-9 CLASS-A: an **owner-owed-forward** value (or a client `source` param added when §6.1 is next opened),
resolved BEFORE native issuance activates — not "settled." Raised by red-team F (PR #36).

**E-40 — 082 creates SOFT pending orders and never converts/locks holds; oversell-safety is a forward
obligation on 085's finalize.** `create_primary_checkout` validates hold coverage as a pure READ, takes ZERO
batch/hold locks and issues ZERO counter DML (081 stays the single writer). It does not transition holds to
`converted` or reserve them against a specific order, so: (a) the same active holds can back multiple pending
orders (distinct command keys); (b) the 081 TTL sweep can `expired`-release a hold while a pending order still
references it; (c) `cancel_pending_order` releases no holds (capacity returns via the TTL sweep). At 082 NO
oversell is reachable — `finalize_primary_order`/`issue_ticket_atoms` are absent and the rail is dark; this is
the frozen SSCAS #1 design (finalize is the choke-point, §6.3). **Forward obligation on 085**:
`venue.finalize_primary_order` MUST re-read the hold `status='active'` + `expires_at > now()` and re-derive
capacity from the batch counter under the batch `FOR UPDATE`, honoring the 081 oversell CHECK
(`held+sold<=capacity`) — a blind `held -= q` on a swept/converted hold would double-decrement and abort as
oversell (buyer paid, no ticket). Recorded so 085's review gates on it. Raised by red-team C (PR #36).

*(register maintained per PHASE_2_ARCHITECTURE_FREEZE.md §4)*
