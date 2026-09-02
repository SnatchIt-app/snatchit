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

## PFA-16 — the frozen `anon`-reads-`signing_key.public_key` arm is undeliverable under the immutable 076 kernel schema wall (the PFA-14 class, one schema over)

```
ID:                          PFA-16
FROZEN RULE:                 RLS §7.7 grades `anon` an `A` read of `kernel.signing_key`'s public projection
                             (`public_key, scope, event_id/venue_id, status, not_before, not_after`), plan
                             §8/083's RLS row calls it "world-readable", and plan §8/083's Tests row asserts
                             "Anon reads `public_key` but NOT `kms_handle_ref`."
IMPLEMENTATION CONFLICT:     migration 076 (immutable, hash-locked) grants `kernel` schema USAGE to
                             `authenticated` ONLY (for function EXECUTE) and `REVOKE ALL … FROM PUBLIC,
                             anon, authenticated`; plan §8/076's test asserts
                             `has_schema_privilege('anon','kernel','USAGE') = false`. An `anon` principal
                             hits a schema-level 42501 at the `kernel` wall BEFORE any column grant or the
                             `_sel_public` policy runs — the EXACT wall E-30 recorded for the `venue`
                             schema and the owner ratified as PFA-14. No post-freeze amendment covered the
                             `kernel`/`signing_key` instance. (Even the `authenticated` arm needs an
                             explicit column GRANT that 083 must add, since 076 revokes all kernel table
                             privileges.)
OPTIONS:                     (a) fail-closed — 083 GRANTs the public-key column projection to
                                 `authenticated` only (the deliverable half — any signed-in fan reads the
                                 verify key); anon door/verification reads the verify key via the 086
                                 door-manifest / public read surface, NOT a raw kernel table SELECT. Anon
                                 kernel access stays CLOSED. CHOSEN by owner — the PFA-14 parallel.
                             (b) grant `anon` kernel USAGE + column SELECT — widens 076's boundary.
                             (c) defer the authenticated arm only, anon TBD.
OWNER SIGNATURE REQUIRED:    YES — an external/anon access-boundary choice the corpus does not uniquely
                             determine, identical to the PFA-14 class. Raised independently by both 083
                             derivation passes (2026-08-31).
```

### PFA-16 — OWNER SIGNATURE (recorded 2026-08-31)

```
STATUS:                      SATISFIED / RATIFIED
OWNER SIGNATURE REQUIRED:    YES
OWNER SIGNATURE:             APPROVED
OWNER RULING:                Option (a) — fail-closed to `authenticated` (the PFA-14 parallel). 083 grants
                             the public-key column projection to `authenticated` only; anon door/
                             verification reads the verify key through the 086 manifest / public read
                             surface, not a raw kernel table SELECT. Direct `anon` `kernel`-schema access
                             stays CLOSED (076 boundary unchanged).
INTERPRETATION CONSTRAINTS (owner-scoped): 083 adds NO `anon` grant and does NOT widen 076's kernel
                             schema USAGE; the `kernel_signing_key_sel_public` policy + column grant are
                             scoped to `authenticated`; `kms_handle_ref` stays service_role/platform only;
                             no key material anywhere (C33). Activates nothing.
FORWARD OBLIGATION (governed): unauthenticated door/verification access to the verify key is delivered by
                             the 086 door-manifest / public read surface (which carries `public_key` in
                             the manifest), preserving the §7.7 public-projection semantics WITHOUT
                             exposing the raw `kernel` schema to `anon`. 086's review gates on it.
```

## PFA-17 — `kernel.revoke_signing_key` cannot be authored at 083 (its frozen body writes 086 `venue.door_manifest` + emits via the 092 outbox); plan §8/083 and R2/ODR2 disagree on its package

```
ID:                          PFA-17
FROZEN RULE:                 plan §8/083's Functions row lists `provision_/rotate_/revoke_signing_key`;
                             schema §1.7 write-authority and the RPC EXEC register also place
                             `revoke_signing_key` at 083.
IMPLEMENTATION CONFLICT:     RPC §20.7.5's mandated body force-closes every open `venue.door_manifest`
                             (086) episode in scope (lock order `catalog.event_session` → `door_manifest`
                             → `signing_key`) and emits #44 DoorManifestInvalidated (REQUIRED-RAISING,
                             via the 092 notify outbox). `venue.door_manifest` and the outbox drain do not
                             exist at 083, and 083 cannot depend forward on 086/092 (`083 → 086` is a
                             forward edge). R2_EMITTER row 6 and ODR2 row 12 classify `revoke_signing_key`
                             as an **086** function. Unlike `append_door_manifest_delta` and the 085 void
                             paths, NO document declares a stub-083/body-086 SEAM-2 split for it.
OPTIONS:                     (a) author `revoke_signing_key` in 086 (where `door_manifest` exists); 083
                                 ships `provision` + `rotate` only. Follows the corpus's own SEAM-1
                                 (max-over-reads/writes/calls) rule and reconciles with R2/ODR2's 086
                                 classification. CHOSEN by owner.
                             (b) stub in 083, body in 086 (a new declared SEAM-2 edge).
                             (c) full body in 083 with late-bound guards — implements 086/092 operands
                                 early, against the no-forward-reference discipline.
OWNER SIGNATURE REQUIRED:    YES — two frozen normative sources conflict on package placement and
                             precedence does not uniquely resolve it (freeze §4 / auto-merge §3.C).
                             Raised independently by both 083 derivation passes.
```

### PFA-17 — OWNER SIGNATURE (recorded 2026-08-31)

```
STATUS:                      SATISFIED / RATIFIED
OWNER SIGNATURE REQUIRED:    YES
OWNER SIGNATURE:             APPROVED
OWNER RULING:                Option (a) — `kernel.revoke_signing_key` is authored in **086** (the door
                             package), NOT 083. 083 ships `provision_signing_key` + `rotate_signing_key`
                             only. The revoke's door-episode force-close + #44 emit belong with the door
                             manifest and the outbox drain.
CONSEQUENCE:                 083's function set is the closed world MINUS `revoke_signing_key`: 17 new
                             functions (2 signing-key lifecycle + 3 pass_type_cert + 10 wallet +
                             issue_ticket_atoms + the append_door_manifest_delta stub) + the
                             deletion_blockers_wallet body-replace. schema §1.7's write-authority row and
                             the plan §8/083 function row are owed a non-blocking correction moving
                             `revoke_signing_key` to 086.
FORWARD OBLIGATION (governed → 086): `086_venue_door_and_scan` MUST author `kernel.revoke_signing_key`
                             (§20.7.5) with the door-episode force-close + #44 emit; 086's review gates on
                             it. Until 086 lands, a signing key can be provisioned/rotated but not revoked
                             — acceptable while the rail is dark (no live credentials to revoke).
```

## PFA-18 — dual-control on the signing-key trio is authored by inference (RLS §11.1 is silent; §11.7 mandates it for pass_type_cert)

```
ID:                          PFA-18
FROZEN RULE:                 RLS §11.7 mandates a second approver (via `kernel.approval_request`) for the
                             `pass_type_cert` lifecycle; RPC §20.7.3 authors dual control for
                             `provision_signing_key` "with it, and flagged" (INFERENCE — AUTHORED, R-11).
IMPLEMENTATION CONFLICT:     RLS §11.1 does not spell out dual control for the signing-key trio, so whether
                             provisioning/rotating a signing key requires a second approver is a role-
                             authority choice the corpus authored only by inference and flagged for the
                             owner (R-11).
OWNER SIGNATURE REQUIRED:    YES — a role-authority / security-boundary choice (auto-merge §3.B). Raised
                             by both derivation passes; the RPC contract itself flags it.
```

### PFA-18 — OWNER SIGNATURE (recorded 2026-08-31)

```
STATUS:                      SATISFIED / RATIFIED
OWNER SIGNATURE REQUIRED:    YES
OWNER SIGNATURE:             APPROVED
OWNER RULING:                YES — the signing-key lifecycle at 083 (`provision_signing_key`,
                             `rotate_signing_key`) is DUAL-CONTROLLED: a second `platform_admin` approver
                             via `kernel.approval_request`, parallel to `pass_type_cert`. A signing key is
                             at least as consequential; matches the RPC's authored-by-inference default.
                             (`revoke_signing_key` carries the same discipline when authored in 086 — PFA-17.)
```

## PFA-18A — PFA-18's dual-control-via-`kernel.approval_request` mechanism is STRUCTURALLY UNBUILDABLE from 083 (the PFA-4 class reaches the credential lifecycle); the affected RPCs FAIL CLOSED

```
ID:                          PFA-18A  (implementation consequence of PFA-18 × the PFA-4 impossibility class)
FROZEN RULE:                 RPC §20.7.3-4 (signing-key provision/rotate) and §17.23/§11.7 (pass_type_cert
                             lifecycle) contract dual control via `kernel.approval_request`: write the
                             approval on the first call, activate the credential on the SECOND approver's
                             approval only (SoD via `approval_request_sod_check`).
IMPLEMENTATION CONFLICT:     `kernel.approval_request` (077, immutable, hash-locked) constrains
                             `action ∈ ('refund.issue','payout.request','config.set_money_key')` and
                             `subject_kind ∈ ('order','settlement','config_key')`. NEITHER can represent a
                             `signing_key` or `pass_type_cert` approval. A credential approval INSERT would
                             VIOLATE the frozen CHECK; 083 must not mutate 077, must not extend its
                             action/subject vocabulary, and must not semantically lie (encoding a credential
                             as `config_key`/etc.). This is the exact impossibility PFA-4 recorded for
                             `grant_platform_role`'s dual-control parking — now reaching the credential trio.
OPTIONS:                     (a) fail-closed park: every affected credential lifecycle RPC keeps its frozen
                                 signature and raises a stable `precondition_failed` (dual-control
                                 unavailable), performing ZERO credential mutation/activation/partial-
                                 approval/authority-escalation, until a credential-compatible dual-control
                                 mechanism is separately ratified. CHOSEN by owner (PFA-18A). Preserves the
                                 dual-control SECURITY REQUIREMENT unchanged.
                             (b) single-control fallback (platform_admin alone) — REJECTED by owner: the
                                 unavailable approval mechanism does NOT authorize downgrading the security
                                 requirement.
                             (c) extend/overload 077's approval_request — REJECTED: 077 is immutable and
                                 semantic lying is prohibited.
OWNER SIGNATURE REQUIRED:    YES — preserving a dual-control security boundary while its ratified mechanism
                             is structurally unavailable is an owner decision (not a corpus-determined
                             correction). Discovered during 083 implementation; both derivation passes +
                             the §20.7.3 contract's own flag.
```

### PFA-18A — OWNER SIGNATURE (recorded 2026-08-31)

```
STATUS:                      SATISFIED / RATIFIED
OWNER SIGNATURE REQUIRED:    YES
OWNER SIGNATURE:             APPROVED
OWNER RULING (verbatim key points): "PFA-18A APPROVED — preserve PFA-18's dual-control requirement for
                             signing-key and pass-type-certificate credential lifecycle operations, but
                             reject extending or semantically overloading Package 077's immutable
                             kernel.approval_request closed sets from Package 083. Until a credential-
                             compatible dual-control mechanism is separately ratified and implemented, every
                             affected credential lifecycle RPC MUST FAIL CLOSED. The unavailable approval
                             mechanism does not authorize single-control fallback. … This ruling changes the
                             implementation mechanism only. It does NOT remove or weaken the dual-control
                             security requirement."
INTERPRETATION CONSTRAINTS (owner-stated): dual-control REQUIREMENT preserved · NO single-control fallback ·
                             077 NOT mutated · no credential vocabulary added to approval_request · no
                             semantic overloading (order/settlement/config_key) · fail-closed path performs
                             ZERO credential mutation / signing-key activation / cert activation / partial
                             approval / authority escalation · test rollback · PFA-4 remains intact, PFA-18
                             remains intact, PFA-18A records the newly-discovered credential application.
AFFECTED RPCS (fail-closed at 083): derived mechanically below in the 083 errata (E-41).
FORWARD OBLIGATION (governed): a credential-compatible dual-control mechanism is REQUIRED before the parked
                             credential lifecycle RPCs may become operational. OWNER: UNASSIGNED — the
                             frozen package/DAG does not uniquely assign it; it is NOT arbitrarily assigned
                             to 084–092, and 083 builds NO generalized approval framework / shadow approval
                             system. A later design chooses the mechanism through separate ratification.
STILL CLOSED:                credential provisioning/rotation (parked) · native issuance (dark) · Wallet
                             (dark) · production. A parked provisioning path must NOT make minting usable
                             with missing/uninitialized credential material (activation boundary tested).
```

## PFA-20 — the wallet bearer-token envelope-encryption / hash mechanism is under-specified; the affected wallet RPCs FAIL CLOSED (owner: DO NOT INVENT CRYPTOGRAPHY)

```
ID:                          PFA-20
FROZEN RULE:                 `kernel.wallet_pass.auth_token_enc`/`auth_token_hash` and
                             `kernel.wallet_pass_device.push_token_enc` must be "envelope-encrypted"
                             (WALLET §11.1-§11.4, secret-custody table); `mint_wallet_pass` generates the
                             per-pass token in-DB (returns plaintext once) and `register_wallet_pass_device`
                             takes a plaintext push token and "encrypts" it; auth is a constant-time compare
                             of a token HASH (I-9).
IMPLEMENTATION CONFLICT:     the frozen corpus fixes the custody/exposure NON-NEGOTIABLES (bytea, service_role
                             only, returned by no RPC, plaintext forbidden at rest/in logs, paired hash) but
                             names NO encryption primitive and NO key-custody source; NO crypto extension is
                             installed by 076-083 (only pg_cron/pg_net); the sole DB-secret precedent is
                             Supabase Vault holding a single service_role_key (not per-row column crypto). And
                             the contract has an internal tension: it names the DB RPCs as the encryptors, yet
                             the DB has no crypto primitive, no key parameter, and is barred from calling KMS
                             (unlike the signing keys, which store an opaque KMS handle and let the edge
                             encrypt). The token-HASH primitive (`auth_token_hash`) has the same gap (no
                             installed digest). Two independent derivation passes (main + a dedicated security
                             subagent) confirmed the mechanism is nowhere specified.
AFFECTED RPCS (fail-closed at 083): the FIVE wallet RPCs that generate/encrypt OR hash-authenticate a bearer
                             token — `mint_wallet_pass`, `register_wallet_pass_device`,
                             `get_wallet_pass_build_context`, `list_updated_wallet_passes`,
                             `unregister_wallet_pass_device`. The other five wallet RPCs
                             (`supersede_wallet_passes_for_atom`, `touch_wallet_pass`, `revoke_wallet_pass`,
                             `sweep_wallet_pass_lifecycle`, `record_wallet_push_result`) carry no token-crypto
                             dependency and are IMPLEMENTED.
OPTIONS:                     (a) fail-closed park the five affected RPCs (each keeps its frozen signature,
                                 gates on `wallet.apple.enabled` [dark], then raises
                                 `token_encryption_unavailable`; ZERO token material generated/hashed/
                                 encrypted/stored). The mechanism is a governed forward obligation decided
                                 by the package/owner that activates Wallet. CHOSEN by owner.
                             (b) decide the in-Postgres key-managed mechanism now (an installed crypto
                                 extension + a managed key source) — deferred.
                             (c) move encryption to the edge/KMS with ciphertext-in — requires amending the
                                 frozen `mint_wallet_pass`/`register` contracts — deferred.
OWNER SIGNATURE REQUIRED:    YES — a cryptographic-architecture / key-custody choice the corpus does not
                             determine; the owner ruled DO NOT INVENT CRYPTOGRAPHY and to return the smallest
                             decision. Discovered during 083 implementation.
```

### PFA-20 — OWNER SIGNATURE (recorded 2026-08-31)

```
STATUS:                      SATISFIED / RATIFIED (fail-closed park; mechanism deferred)
OWNER SIGNATURE REQUIRED:    YES
OWNER SIGNATURE:             APPROVED
OWNER RULING:                Option (a) — fail-closed park the five affected wallet token-crypto RPCs now,
                             decide the encryption/key-custody mechanism at Wallet activation. No
                             cryptography is invented in 083. 083 meets its frozen closed world with these
                             five explicitly-ratified fail-closed objects (parallel to PFA-18A) plus the five
                             implemented non-crypto wallet RPCs.
INTERPRETATION CONSTRAINTS (owner-stated): DO NOT INVENT CRYPTOGRAPHY — no plaintext at rest, no
                             base64-as-encryption, no reversible obfuscation, no invented master key, no key
                             in SQL, no hard-coded key, no reusing signing keys for token encryption, no
                             silently choosing pgcrypto with unmanaged custody, no plaintext token in a
                             client-readable column or in logs. The parked path generates/stores NO token.
FORWARD OBLIGATION (governed): a ratified envelope-encryption mechanism (primitive + key custody + encryption
                             locus — in-Postgres managed key vs edge/KMS ciphertext-in) is REQUIRED before the
                             five affected wallet RPCs may become operational. OWNER: UNASSIGNED — the frozen
                             DAG does not uniquely assign it; it is decided by the package/owner that
                             activates Wallet, through separate review. Until then the five are parked and
                             Wallet stays dark.
STILL CLOSED:                Wallet (dark + parked crypto) · native issuance (dark) · production.
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

## ERRATA — package 083 (recorded, no amendment needed)

All corrections below are corpus-determined under the freeze §4 test (the corpus uniquely determines each);
none is a policy choice. The policy decisions 083 executes are separately owner-signed (PFA-16/17/18/18A/20).

**E-41 — the PFA-18A affected-RPC set and the `pass_type_cert` trio signatures, derived mechanically.**
PFA-18A parks "the credential lifecycle" — the affected set is derived, not chosen: every RPC whose body
would CREATE or TRANSITION a `kernel.signing_key` or `kernel.pass_type_cert` row =
`provision_signing_key` (§20.7.3), `rotate_signing_key` (§20.7.4), `provision_pass_type_cert`,
`rotate_pass_type_cert`, `revoke_pass_type_cert` (§17.23 names the cert trio without signatures).
`revoke_signing_key` is NOT in the set at 083 — it does not exist here (PFA-17 → 086). Read paths
(the PFA-16 public projection; the mint's activation-boundary SELECT) are not lifecycle and are NOT parked.
The cert trio's parameter lists are derived from the §11.3 column set they would populate (identifiers,
public certs, opaque KMS handle, validity window, reason, command key) — the §20.7.3/.4 shape applied to
§11.3; pending the real (post-dual-control) bodies these signatures are the frozen-shape projection, and the
un-parking package re-reviews them against the ratified mechanism. Referenced by PFA-18A ("derived
mechanically below in the 083 errata (E-41)") — this entry is that record.

**E-42 — `key_id` joins the §7.7 public projection of `kernel.signing_key`.** RLS §7.7 fn-13 lists "only
public_key, scope, target, status, not_before, not_after" as readable; the 083 column grant adds `key_id`.
Corpus-determined: the PFA-16 authenticated-verify path resolves the verify key BY `signing_key_id` pinned on
`kernel.tickets` (§7.1 Writes) — a projection without the join key cannot be joined to, so fn-13's list is a
spec gap, not a boundary. `key_id` is a non-secret surrogate PK already derivable via
`kernel.tickets.signing_key_id`. No secret moves; `kms_handle_ref` stays excluded.

**E-43 — WALLET §11.1/§11.2/§11.4 package tags read "084"; the governing PACKAGE_REGISTRY places
`wallet_pass`/`wallet_pass_device`/`wallet_pass_push_log` (with `pass_type_cert` + the `.pkpass` bucket) in
083, with 084 = "late-binding FKs … and nothing else."** The registry is the object-placement authority
(the E-34 class: a stale placement row in one spec vs the governing register). 083 follows the registry.
Non-blocking correction owed to the WALLET §11.x tags.

**E-44 — the mint's ownership-log rows carry `cause='issue'` for ALL business causes; the business cause
lives in `inventory_movement.cause` + `state_transition.mint_cause`.** §7.1's literal "ownership_log
`cause`" cannot hold `comp`/`door_sale`/`import`: the immutable 079 `ownership_log_from_identity_check`
REQUIRES `cause='issue'` on every from-NULL sequence-1 row. Corpus-determined reconciliation — the
constraint is the stronger, frozen artifact; the business cause is preserved losslessly one column over.

**E-45 — `kernel_signing_key_sel_public` is deliberately row-universal; I-2 interaction recorded.** The
PFA-16-signed surface is "every signing key's public projection readable by any authenticated principal"
(§7.7 verify-key distribution) — a row predicate that admits every row IS the design, not an accident. The
qual is written `public_key is not null` (row-universal under the NOT NULL constraint) rather than literal
`USING(true)` so the standing I-2 witness ("no USING(true) anywhere") keeps its power to catch ACCIDENTAL
universal exposure on tables where universality was never signed. The secret column stays grant-fenced.
Raised by red-team R2 (PR #37).

**E-46 — mint-engine hardening: five corpus-determined corrections applied at review.** (a) rank-1
Event/Session `FOR UPDATE` added before serial allocation — SPEC_FOUNDATION §5 lock order + DOOR §818 mandate
the rank-1 lock, and CDM's "all inventory draws for a session serialize within this aggregate" uniquely
determines session-scope serialization (the batch-only lock raced same-session/different-batch mints to the
same `serial_no`); it also mutually excludes `catalog.update_event_session`'s atoms-issued schedule guard.
(b) `EXCEPTION WHEN unique_violation` replay path — the frozen idempotency contract ("a replay returns the
original atoms", the 081 reserve idiom) must hold for CONCURRENT retries, not only sequential ones.
Residual (accepted): the ownership log carries no single-column unique on `cause_ref`, so the anchor is
contractual — one `cause_ref` = one mint attempt-set (the 085/finalize caller contract); a cross-session
`cause_ref` reuse is caller error and surfaces raw. (c) batch↔ctx coherence — the batch's
`event_session_id`/`ticket_type_id` must equal the ctx's (the sold counter and the atoms move together);
`ticket_type_id`+`cause_ref` join the required-context set (a NULL anchor silently defeated the replay
guard). (d) signing-key SCOPE coherence in the activation boundary — the §7.1 raise text already said "must
resolve for the event scope"; the predicate now enforces it (global | per_event=session's event |
per_venue=event's venue). (e) `record_wallet_push_result` stat-gating + `wallet_pass_push_log_dedup_uq`
NULLS NOT DISTINCT + `touch_wallet_pass` not_found — the AO ledger and the device stats must agree (one
attempt, one count; no silent-ok no-ops; a NULL dedup member must still dedup). Raised by red-teams
R1/R6 (PR #37).

**E-47 — forward obligations recorded from the 083 red team.** (a) The un-parking packages MUST add in-DB
principal checks to the parked bodies (`mint_wallet_pass`, the lifecycle five): at 083 they are
`authenticated`-granted and rely on edge-fronting (G-7) — fail-closed today, but the real bodies must not
trust the edge tier alone (raised by R2/R7). (b) 085/finalize MUST decrement `held` BEFORE (or atomically
with) invoking the mint's `sold += N` in the same transaction — the C27 CHECK `held+sold<=capacity` aborts a
mint of still-held units otherwise (the E-40 ordering corollary; raised by R6). (c) When rotation un-parks:
the mint's activation-boundary key check is not `FOR UPDATE`-locked against a concurrent status flip —
benign while rotation is parked; re-review at un-park (raised by R6).

## ERRATA — package 084 (recorded, no amendment needed)

**E-48 — the adopt pattern's recorded lock claim is corrected; the populated-table discipline is a
forward obligation on the NEXT adopt package.** Plan §8/084 states the `NOT VALID` + `VALIDATE` two-step
takes only "a brief ShareRowExclusive … VALIDATE only ShareUpdateExclusive (non-blocking)". In the
standing SINGLE-TRANSACTION migration form this is wrong for a populated table: every lock acquired is
held to COMMIT, so the ADD's `ShareRowExclusive` (taken on `kernel.tickets` AND on both referenced
tables — `venue.ticket_type`, which has live writers, and `kernel.signing_key`) is still held while
`VALIDATE` scans, giving the identical blocking profile to a plain `ADD CONSTRAINT`. The two-step's
benefit exists only when ADD and VALIDATE commit in SEPARATE transactions. 084 itself is unaffected —
`kernel.tickets` is provably empty (its sole writer, the 083 mint, is doubly dark: feature flag false
AND no activatable signing key under PFA-18A), and the plan's own "trivial on empty kernel.tickets"
carries the apply. **Forward obligation:** the next adopt-shaped package that lands on POPULATED
production tables (the registry names `089` `payment_native.sale_id` and `090`'s order-column FKs as
this construction) must either ship ADD-NOT-VALID and VALIDATE as separate transactions — a ruled
exception to the single-txn discipline, decided at that package's review — or accept the full-lock
profile explicitly. Purity invariant intact: this is a comment/record correction; 084's object list is
untouched. Raised by red-team B (PR #38).

## PFA-21 — service_role cannot reach the 085 kernel state-sync entry RPCs under the immutable 076 kernel wall (the PFA-14/15/16 class, fourth instance) — kernel USAGE granted at 085

**OWNER-SIGNED 2026-09-01.** `kernel.mark_refund_state`, `kernel.mark_payout_transfer_state` and
`kernel.record_identity_obligation` are DEF/service_role-only ENTRY functions whose sole contracted
callers are service_role edge sessions (stripe-webhook, payout-execute, refund-execute — RPC §20.7.6/.7/.10).
Immutable 076 grants kernel USAGE to `authenticated` only (076:77), and PFA-15's ruling widened venue ONLY,
stating kernel/catalog need their own ruling. Without it every Stripe state-sync silently dead-ends
(a refund stays `pending` forever once the rail activates). **RULING: 085 ships
`GRANT USAGE ON SCHEMA kernel TO service_role` — USAGE ONLY.** No table/DML grants ride along; EXECUTE
stays per-function; the deny-by-default table posture is unchanged; anon is NOT widened (PFA-14 intact);
catalog is NOT touched. 085's review gates on this grant being present and USAGE-scoped.

## PFA-22 — OPEN-2 closed: the BP-12 refund-possible window gets a DEDICATED config operand with candidate-scoped NULL semantics

**OWNER-SIGNED 2026-09-01 (verbatim semantics).** The deletion-machine spec left BP-12's "a refund is
still possible for recent orders" window with no named key or operand (DSM OPEN-2). RULING: create a
dedicated operand **`deletion.refund_possible_window_hours`** — do NOT reuse
`refund.buyer_self_service_window_hours`. Initial value NULL / owner-unset (seeded at 085,
visibility `restricted`). **NULL is fail-closed ONLY when a relevant BP-12 candidate order exists**: if
the blocker needs the refund-possible window (a qualifying candidate order is present) and the value is
NULL, deletion completion is BLOCKED; if there are NO qualifying candidate orders, NULL by itself must
NOT block deletion. The key controls DELETION SAFETY ONLY — it does not create refund eligibility and
does not change buyer refund policy. Implementation note (085): candidates = the identity's
`venue.order` rows in `paid`/`partially_refunded`; the window is measured from `created_at` (the only
stable timestamp on the immutable 082 table — it expires no later than a paid-time window would, and the
in-flight-refund arm of `deletion_blockers_money` covers active requests independently).

## ERRATA — package 085 (recorded, no amendment needed)

All corpus-determined under the freeze §4 test; the policy decisions 085 executes are separately
owner-signed (PFA-15/PFA-21/PFA-22).

**E-49 — the immature-grant failure token is `sod_violation` (C58), not schema §1.13.4's
`precondition_failed('money_role_too_new')`.** MONEY §6.7a records the conflict and RPC/RLS carry the
RATIFIED C58 form; the ratified correction governs (the E-34 class). 085's verbs raise `sod_violation`.
The §6.7a second conflict (whether `set_platform_config`'s money arm is a maturity site) is NOT 085's:
078 is applied and immutable, and adding a platform-plane maturity control would be NEW authority —
left on the MONEY §11 owner queue.

**E-50 — `kernel.payment_native` carries the standing `raise_append_only` guard.** Schema §1.8 declares
the ledger "effectively AO"; the plan's trigger row enumerates only `set_updated_at` (inapplicable — the
table has no `updated_at`). The declared property governs; the guard is its mechanical witness (the
083 push-log precedent). R-34's two writers INSERT only; nothing legitimate updates or deletes a link.

**E-51 — `kernel.payout.cause` CHECK admits the four NAMED §1.9 labels** (`settlement`, `market_sale`,
`promoter_commission`, `refund_void`) — the ellipsis in "from D3 (…)" is prose style, not a wider set:
every contracted writer (close_settlement, native-sale, pay_promoter_commission, request_org_payout)
writes one of the four. Widening is additive if a later package's writer needs a fifth label.

**E-52 — the executed refund tier is WITNESSED by an auto-approved `approval_request` row.** The
executor's delegated-authority gate recognizes an APPROVED request on the order; the parked branch's
approval satisfies it naturally. For the auto-execute tiers (buyer self-service / org auto / platform),
085 writes the SAME record class with `state='approved'`, `approved_by = SN-SYSTEM`,
`reason_code='auto_execute_tier'` — the tier check that admitted execution IS the authority, the record
is its witness, and the SoD pair (`approved_by <> requested_by`) holds by the sentinel. This closes the
delegation channel without a new mechanism (no GUC, no signature change) and improves the audit trail:
EVERY executed refund now has an intent record. Inert today: all D-3 keys are NULL, so no auto tier is
satisfiable until the owner sets values.

**E-53 — `market.on_atom_voided` ships the C117-canonical THREE-parameter stub**; the two-parameter
summaries in plan §0.4b and schema §13.2 FR-4 are ruled stale by the registry's SEVENTH AMENDMENT. The
`p_cause` VALUE SET remains uncontracted — that derivation belongs to 088's body review (the stub is a
no-op; SEAM-2a freezes names/types only). The plan's "a ruling that drops `p_cause` must be taken
BEFORE 085 is authored" is satisfied BY C117: the ruling exists and keeps it.

**E-54 — `kernel.payout.status='paid'` is built as form (a)** (the executor's synchronous transfer
result) per RPC §20.7.6's own instruction pending the O16 ruling; `mark_payout_transfer_state` refuses
`submitted` (087's request path — a second door past the money controls otherwise). Forward notes
carried: the venue_finance arm of `list_org_payouts` FAILS CLOSED (empty page) until 087's settlement
join exists; the org/venue-scoped `payment_native` read RPC named by RLS §7.8's V cells is unbuilt and
fails closed (the §20.0c shape — recorded, owed to the 087-surface review); the BP-6 kernel arm is
subsumed by BP-5's stricter `status <> 'paid'` predicate while both live only in `deletion_blockers_money`
(a held payout is definitionally unsettled) — the arm is kept for when the predicates diverge.

## PFA-23 — refund-execution authority: EXEC-DEF + single-use idempotency-bound delegation (red-team P0)

**OWNER-SIGNED 2026-09-01.** The 7-reviewer red team (fidelity R3, money-custody R7, correctness R1,
security R2, tests R5) converged on a P0: the first implementation granted
`kernel.refund_primary_order` EXECUTE to `authenticated` and gated it on
`exists(any approved refund.issue request on the order)`. Because approvals are never consumed, that
gate was a reusable, amount-unbound skeleton key — once one refund on an order was approved, any
authenticated principal could call the executor directly and drain the payment (voiding the buyer's
tickets), and `platform_support`'s cap was skipped whenever an approved row existed. This contradicted
the frozen §11.4 (EXEC: **DEF**) and §17.2 (approve executes the refund in the same transaction) and was
an invented, self-signed authority mechanism.

**RULING (owner-selected):** restore §11.4/§17.2 via a SINGLE-USE IDEMPOTENCY BINDING, no 077 mutation,
no new state, no new function:
- `kernel.refund_primary_order` is **EXEC DEF** — granted to `service_role` (edge-fronted), REVOKED from
  `authenticated`/anon/public. The bare `exists(approved)` gate is DELETED.
- **Direct arm** (`p_command_key` not `'req:%'`): authority = `is_platform([platform_support (cap ALWAYS
  evaluated, on the cumulative operand under the payment lock), platform_admin])`. A full refund
  (amount ≥ coverable order total) voids all voidable atoms; a partial platform refund is money-only
  (voids nothing — atom-specific voids go through `admin_refund(p_atom_ids)`).
- **Delegated arm** (`p_command_key = 'req:'||request_id`): reachable only definer→definer (from
  `approve_refund_request`/`request_order_refund`, which have already enforced dual control) or via the
  refund-execute edge as service_role. It loads THAT request, requires `state='approved'` +
  `subject_id = p_order_id` + `amount_minor = p_amount_minor`, voids exactly the request's payload atoms,
  and is single-execution because the inserted `kernel.refund.idempotency_key = p_command_key`
  (`'req:'||request_id`) is UNIQUE — a second attempt returns `idempotency_replay`. No `approved→executed`
  state is needed (077's state set is immutable); the refund ledger row IS the consumption record.
Recorded as the corpus-conforming remediation of the red-team P0; the executor now moves money only for
platform (capped) or a specific, once-only, amount-and-atom-bound approved request.

## ERRATA — package 085, red-team remediation addendum (E-55..E-60)

Corpus-conforming fixes for the 7-reviewer red team (the authority P0 is PFA-23, owner-signed).

**E-55 — finalize lock order: Order(3) before Inventory batch(2) (R3 P1-4).** §6.3 lists the SSCAS #1
order as Event/Session → Inventory batch → Order → Atom → Payment. The implementation acquires
Event/Session(1) → the resolved signing key → Order(3) → the (deterministically pre-locked) batches(2)
→ mint → Payment(6). This is internally consistent with the refund member (both money paths take the
ORDER lock before any inventory/atom lock), so no finalize×refund inversion exists; finalize×finalize on
one order serialize on the order lock; and finalize×finalize on DIFFERENT orders sharing batches are
serialized by the ascending-by-batch_id pre-lock (E-58). The batch-before-order literal is recorded as a
knowing deviation with this deadlock analysis rather than reordered, because order-first is the coherent
ladder across BOTH money engines.

**E-56 — force_void_ticket uses a DETERMINISTIC synthetic void cause_ref** = `md5('force:'||command_key)
::uuid`, so a replayed break-glass command returns `noop_replay` via the void engine's command-key arm
(the voided-branch now matches EITHER the refund cause_ref OR the command key) instead of raising
`state_conflict` (§11.1 idempotency; R1/R3 P1).

**E-57 — admin_refund binds atoms to the payment (R7 P3/R2 P2).** The void loop now requires each
`p_atom_ids` member to belong to an order paid by `p_payment_id` (via ownership_log seq-1 → order_item →
payment_native), and raises `precondition_failed` when none match. Break-glass latitude no longer
decouples the money leg from arbitrary tickets.

**E-58 — finalize batch attribution is HEURISTIC; exact linkage is a forward obligation (R1 P1).** 082's
`create_primary_checkout` takes `p_hold_ids` but persists no order↔hold/batch linkage, and `order_item`
(082, immutable) has no column for it. finalize therefore attributes each item to the buyer's reservation
for that ticket_type/session, PREFERRING an active-unexpired hold (`ORDER BY (active AND unexpired) DESC,
created_at DESC`). Correct for the common one-pending-order-per-buyer case; a buyer holding two concurrent
pending orders on the same tt/session cannot be perfectly disambiguated. **Forward obligation
(OWNER-owed at activation / a future checkout-successor package):** persist the chosen hold_ids/batch on
the order so finalize derives attribution from a stored fact. Inert today (dark rail); the C27 CHECK and
the TTL sweep contain any mis-attribution. Batches are pre-locked ascending by batch_id (R6 P1 — no
AB-BA deadlock); all active-unexpired holds convert WHOLE (held -= their sum; the over-held remainder
returns to free capacity), fixing the greedy-conversion false `oversell_rejected` (R1 P1).

**E-59 — PFA-21 disclosure: the kernel USAGE grant makes the pre-existing service_role EXECUTE grants
RUNTIME-live; the established ACL boundary is accepted, not narrowed (R2 P1).** PFA-21's
`GRANT USAGE ON SCHEMA kernel TO service_role` makes runtime-reachable the service_role EXECUTE grants
077/081/082/083 already authored (the deletion machinery, the sweeps, the mint/wallet DEF set) — grants
that were present in the ACL catalog all along (the F3 register and A30/A41 assert them) but inert
without schema USAGE. The red team (R2 P1) flagged the deletion machinery as an escalation surface for a
compromised service_role and offered two dispositions: revoke to a minimal boundary, OR accept and
disclose. **085 ACCEPTS the established boundary** — the 077 service_role grants are a frozen invariant
(revoking them contradicts A30/A41/F3, i.e., it would be a policy CHANGE, not corpus-conforming
remediation), the deletion functions' real callers are pg_cron (postgres) + definer-internal so the
grants are unused at runtime by service_role in practice, and service_role is already fully trusted for
the money rail (finalize, mark_*). `issue_ticket_atoms` stays service_role (its §7.1 comp/door/import
paths are contracted, non-payment issuance BY DESIGN) and darkness-gated. **Forward obligation:** at
native-issuance activation, re-verify that the comp/door/import edge callers of `issue_ticket_atoms`
enforce their own authority, and reconsider (with owner sign-off) whether the dormant deletion-machinery
service_role grants should be tightened chain-wide.

**E-60 — two recorded deferrals.** (a) SHARD COUNTERS (R3 P1-5): finalize's `held-=q` and the void
engine's `sold-=1` touch `venue.inventory_batch` only, not `inventory_batch_shard`. Inert under E-32
(sharding deferred; `is_sharded` always false; `create_inventory_batch` refuses `shard_count>0`).
Forward obligation on the sharding-activation package to mirror the deltas (083's mint shares the gap).
(b) RESULT/PROJECTION SHAPES (R3 P2-2): `request_order_refund` returns `parked`/`executed` +
`required_approver_class` and the reads return presence-boolean/scalar-filter projections; the fuller
contracted shapes (`cumulative_minor`, `atoms_voided[]`, `updated_at`, cursor pagination, the
`{hold_state}` return on hold/release) are additive and adapted by the edge tier — deferred to the
edge-integration pass rather than expanded here. Neither affects authority, money movement, or custody.

## PFA-24 — PFA-16 anon-verify surface: the verify key rides M1 (kernel.signing_key projection), NOT the 086 manifest

**OWNER-SIGNED 2026-09-01.** PFA-16's forward obligation said 086 delivers the anon verify key "through
the door-manifest / public read surface (which carries public_key in the manifest)." Three later frozen
docs (DOOR §7.5a, EDGE §5.4.2, RPC §20.6.1) instead place `public_key` in **M1** — the KMS-signed
projection of `kernel.signing_key`'s world-readable columns, served by the door-session edge — and
DELIBERATELY omit `public_key` from **M2** / `venue.get_door_manifest`, which carries only
`signing_key_id` (the join key to M1). The corpus did not uniquely resolve the conflict. **RULING:** the
door-spec reading governs. 086's `door_manifest_entry`/`door_manifest_delta` and `get_door_manifest` (M2)
carry per-atom `signing_key_id` ONLY — never `public_key`, never key material, never identity. The
offline/loginless door obtains M2 via `get_door_manifest` (token-bound through `kernel.assert_door_session`,
service_role edge, no `auth.uid()`, no kernel USAGE) and joins `signing_key_id` → M1 (the
`kernel.signing_key` public projection). 086 creates NO anon-readable table and NO anon grant; the 076
kernel-USAGE wall stays closed to anon (the PFA-14/16 fail-closed posture holds). PFA-16's
"carries public_key" phrasing is superseded (E-61). C33 intact — no verify-key material in the manifest.

## PFA-25 — `set_event_security_config` is ruled OUT of 086; the per-event door-config surface is a governed forward obligation

**OWNER-SIGNED 2026-09-01.** RPC §20.6.6 contracts `venue.set_event_security_config` and RLS §11.4 grants
it to three human roles, but its target table `catalog.event_security_config` is created by NO package,
078 (its natural home) is immutable, and schema §13.7 (S-13) flags the gap. **RULING:** 086 does NOT build
the function or an invented table for it (building a function against a non-existent table is forbidden by
the plan's own discipline). The per-event door-config surface — the table AND the function together, with
its own review — is a **governed forward obligation, OWNER-owed** at (or before) the 2B door-gate
activation; a future package (or a re-opened 078-successor) authors both. 086 ships the complete
door/scan substrate without it; the three role grants have nothing to point at until then. T-RPC-DOOR-24
(the "held" assertion) stays satisfied.

## PFA-26 — door PIN hashing parked fail-closed (no slow KDF in the chain)

```
ID:                          PFA-26  (PFA-20 class)
FROZEN RULE:                 SCHEMA_SPEC §3.10 — venue.door_pin.pin_hash entropy LOW (a human types it) →
                             requires a SLOW KDF + constant-time compare (Phase-0 §9).
DEFECT:                      086 authored create_door_pin / mint_door_session with md5('door_pin:'||pin) —
                             a fast, unsalted digest over a >=4-char PIN. A leaked hash brute-forces the
                             PIN; identical PINs collide. No crypto extension (pgcrypto crypt()/gen_salt())
                             is installed 076-086, so a real slow KDF is unbuildable in-DB. Red team (086
                             corpus/PFA lens) flagged it as a silent security-boundary downgrade.
FREEZE §4 TEST:              policy/security-boundary decision the corpus does not let the DB build →
                             OWNER SIGNATURE required (not self-signed).
OWNER RULING (2026-09-01):   PARK fail-closed. create_door_pin and mint_door_session RAISE
                             'precondition_failed: door_pin_kdf_unavailable … (PFA-26)' with ZERO mutation,
                             signatures frozen for un-park. Consistent with the parked credential trio
                             (PFA-18A) and wallet crypto (PFA-20). NOTE: door_session.token_hash md5 is
                             corpus-COMPLIANT (§3.10: 256-bit token → plain digest sufficient) and stays;
                             assert_door_session stays live (no sessions to assert). Suite 150 §E asserts
                             the park (E1/E2 throw; E3/E4 zero-mutation).
FORWARD OBLIGATION:          un-park with a ratified slow-KDF mechanism (edge-side hashing, or a sanctioned
                             crypto extension) at native-scanning activation.
```

## PFA-27 — holder-mix read audit + reconciliation alarm deferred to demographics activation

```
ID:                          PFA-27  (forward obligation)
FROZEN RULE:                 DEMOGRAPHICS_PRIVACY_SPEC §10.4 — get_holder_mix writes one read-audit row
                             per call (actor, event_session_id, dimension, occurred_at, §11), is
                             rate-limited per principal (005/021 pattern), and raises a reconciliation
                             alarm when the read-side re-derivation fails.
086 POSITION:                the fail-closed re-derivation itself (R1 k>=25, R2 min>=5, R4 Σ=responded,
                             R5 count>=2, responded<=total → {suppressed:true}), the constant suppressed
                             shape (R6), and the live §5.5 kill switch ARE authored here (E-64). The audit
                             sink + rate-limit + alarm are NOT — no demographic-read audit table exists in
                             the chain, and the function is STABLE. get_holder_mix fails CLOSED without
                             them (suppresses); it does not fail open. Delivered at demographics activation.
```

## Errata (corpus-determined corrections) — 086 red-team remediation

- **E-62** — `kernel.revoke_signing_key` is the third leg of the credential trio; PFA-18A ruled the dual-control mechanism unbuildable, so it ships FAIL-CLOSED (ZERO mutation), signature frozen, exactly as 083 parked provision/rotate. Real body (force-close open episodes in key scope + outbox #44) is the PFA-18A un-park obligation.
- **E-63** — `kernel.on_identity_erased_door` was authored with the INVERSE of the ratified ODR16 dispositions (it scrubbed `comp_allocation.granted_to_name`, which #29 says SURVIVES, and touched none of the three ops FKs). Corrected to ODR16 INV #29/#30/#31: SET NULL `comp_allocation.granted_to_identity`, `.granted_by`, and `guest_list.created_by`. `granted_by`/`created_by` relaxed from NOT NULL to nullable (the SET-NULL disposition requires it, and their RESTRICT FK to `auth.users` otherwise makes right-to-erasure fail hard). AO ledgers keep bare refs (INV #28/#32/#33 TOMBSTONED). Suite 150 §F rewritten.
- **E-64** — `venue.get_holder_mix` corrected to the DEMOGRAPHICS §10.4 read contract: the suppressed shape is the CONSTANT `{suppressed:true}` (was leaking `suppression_reason` and a distinct `no_published_snapshot` status — "a reason is the same leak in words", R6); the §5.5 kill switch is read live every call; the §5.2 read-side re-derivation (R1/R2/R4/R5 + responded<=total) fails closed to `{suppressed:true}`. Audit/alarm → PFA-27. Suite 150 §G extended (G4-G7).
- **E-65** — `venue.guard_door_manifest_transition` converted from a blocklist to an ALLOWLIST. The blocklist named only identity/base columns, leaving `venue_id` (the denormalized authz key driving the entry/delta RLS joins), `not_after`, and `command_idempotency_key` service_role-mutable — an UPDATE could silently flip a whole episode + its ledger to another tenant with the digest untouched. Now every column except the close trio, `max_delta_seq`, and the `open→closed` status flip is immutable.
- **E-66** — three linkage/ceiling corrections (the "check authority on object A, write to object B" anti-pattern): `upsert_guest_entry` UPDATE now binds `guest_entry.guest_list_id = p_guest_list_id` (was a cross-tenant IDOR write); `issue_comp` now caps issuance at the allocation quantity (was mintable up to batch capacity); `sync_scan_device_manifest` returns the COMPLETE manifest (delta cursor 0) — it was passing the episode VERSION as `get_door_manifest`'s delta-SEQ cursor, silently dropping deltas (a revoke could be lost). Incremental delta sync (needs a real delta-seq parameter) is a native-scanning-activation forward obligation.

## Forward obligations opened by 086 (native-scanning / demographics activation gate)

`record_scan` full result classification (`duplicate`/`frozen`/`fraud_review`, currently all non-admit → `invalid`; the `when others` also masks transient faults) + offline metadata (`offline_pending`, `device_boot_id`, `scan_sequence`, `manifest_version`, `direction`, `scan_type`) + command-key idempotency (RPC §20.4.3); `mint_door_session` command-key idempotency (moot while parked, PFA-26); `manifest_digest` should commit to the ordered entry set, not metadata; the `scan_admitted_in_uq` predicate vs `re_entry` re-admission; `record_scan` actor-device venue validation; and the loginless/token-bound door edge wiring (`get_door_manifest`/`record_scan` do not yet call `assert_door_session`; fails closed). All behind the dark gate.

## PFA-28 — CRM `customer_ref` HMAC mechanism: the three customer-data readers parked FAIL-CLOSED (no pgcrypto, no weak fallback)

```
ID:                          PFA-28  (PFA-20 class)
FROZEN RULE:                 CRM_EXPORT_SPEC §4.3 — customer_ref = base32(HMAC-SHA256(org_customer_key(:job_org_id),
                             identity_id)[0..9]) (80 bits, 16 chars); §2.2 field 1 is IDENT and is carried by EVERY
                             roster projection ("every role that may read the roster"); §11.4 build_export_rows /
                             list_attendees / lookup_attendee emit it; OR-19 — request_export mints the org's
                             kernel.org_customer_key lazily ("server-generated random 32 B").
DEFECT / GAP:                repository bytes prove pgcrypto is NOT installed (076-086 install only pg_cron + pg_net;
                             PFA-20 rejected "silently choosing pgcrypto with unmanaged custody"); no other approved DB
                             HMAC primitive exists; md5 is the only built-in digest and is not an HMAC;
                             gen_random_bytes (the only in-DB CSPRNG byte source) is pgcrypto's. The frozen
                             customer_ref therefore cannot be computed in-DB without a NEW crypto dependency, and
                             the frozen key material cannot be generated without one either.
IMPLEMENTATION CONFLICT:     the frozen CRM contract requires an HMAC the chain cannot compute without a
                             cryptographic mechanism no document selects (primitive, custody, location).
OPTIONS:                     (a) install pgcrypto in 087 and compute in-DB — REJECTED by ruling (PFA-20 class:
                                 unmanaged custody, a security decision made by an implementer);
                             (b) use the Supabase platform-default pgcrypto (present on every fresh replay —
                                 see NOTE) — REJECTED by the ruling's own §3 clause "MUST NOT install pgcrypto
                                 OR SELECT A NEW CRYPTOGRAPHIC MECHANISM solely to implement customer_ref":
                                 selecting the platform's copy IS selecting the mechanism; it is an input to
                                 the ratification (items 1-5), not a licence;
                             (c) edge-side HMAC with the key read from the DB — REJECTED for now: location
                                 of computation is item 2 of the ratification;
                             (d) md5 / unkeyed sha256 / uuid truncation / random — FORBIDDEN outright;
                             (e) PARK the three readers fail-closed, keep the lifecycle live — CHOSEN.
PACKAGE IMPACT:              087 only. No object added or removed; three bodies park; OR-19 mint deferred.
DAG IMPACT:                  none (no edge, no package, no renumbering).
SECURITY / MONEY IMPACT:     strictly tighter — no customer datum, no key material, no substitute identifier
                             exists; money engine untouched (suite 151 C40).
FREEZE §4 TEST:              security/privacy-boundary mechanism the corpus does not uniquely determine →
                             OWNER SIGNATURE REQUIRED: YES.
OWNER SIGNATURE:             APPROVED (2026-09-01).            STATUS: SATISFIED / RATIFIED.
OWNER RULING (substance):    DO NOT install pgcrypto in 087. DO NOT invent an alternate in-DB crypto mechanism.
                             DO NOT weaken HMAC-SHA256 to md5/sha/simple digest. The frozen customer_ref requirement
                             REMAINS MANDATORY (algorithm, truncation, key source, identity input, encoding, output
                             semantics unchanged). Every 087 function that must emit customer_ref FAILS CLOSED
                             rather than emit a weaker, placeholder, reversible, deterministic-unkeyed or
                             non-conforming identifier — never identity_id, never an unkeyed hash, never a
                             truncated uuid, never NULL, never a random substitute. The export lifecycle,
                             settlement engine, purge/orphan machinery, bucket, cron, gate_as_of storage, cell
                             counters and deletion composition CONTINUE. X-6 is not relaxed. This ruling defers
                             ONLY the crypto implementation mechanism.
CUSTOMER_REF CRYPTO:         RATIFIED IMPLEMENTATION: NO   ·  PGCRYPTO INSTALLED: NO   ·  WEAK FALLBACK: NO
AFFECTED READERS:            FAIL-CLOSED: YES
AFFECTED SET (derived):      of the 13 CRM entry points, EXACTLY the three whose projection carries field 1:
                             venue.build_export_rows · venue.list_attendees · venue.lookup_attendee. The other ten
                             (assert_may_request, request_export, finalize_export, authorize_export_download,
                             revoke_export, list_export_jobs, sweep_expired_exports, the three purge definers)
                             touch no customer row and are LIVE. Corollary: request_export's OR-19 mint is
                             DEFERRED with the mechanism — key generation/custody are items 3/4/8 of the
                             forward obligation and the only in-DB byte generator is pgcrypto's — so NO
                             kernel.org_customer_key row is written at 087 (no key material exists to leak;
                             suite 151 D18).
FAIL-CLOSED DERIVATION:      build_export_rows: claims the job (queued→running, lease, gate_as_of stamped,
                             counters zeroed — the frozen claim semantics are exercised), re-derives authority
                             from the job row, then records the FROZEN failure state — state='failed',
                             failure_code='build_error' (the schema §3.18 closed set's member for a build that
                             could not be performed), crm_export.fail reason customer_ref_crypto_unavailable —
                             and returns ZERO rows; finalize_export refuses any non-running job, so no artifact
                             can ever exist for a parked build. list_attendees / lookup_attendee: authz, closed
                             filter grammar, reason-code enum (platform arm) and prefix_too_short are enforced
                             FIRST, then RAISE precondition_failed(customer_ref_crypto_unavailable) with ZERO
                             mutation and NO rate budget consumed (the call reached no data). Frozen signatures
                             and the builder's return shape (row_cursor, columns[], cells[]) are fixed so the
                             un-park is body-only.
TESTS:                       suite 151 §E (E1-E17: fail-closed, no raw identity / unkeyed hash / uuid /
                             random substitute, authz before park, zero mutation, no budget, no pgcrypto symbol
                             in any 087 routine + no `create extension` in 087 (gate), greppable park); D23-D27 (job → failed/build_error, cannot finalize, cannot
                             download); D18 (no key minted); C40 (settlement subsystem unaffected); suite 152
                             (X-6 closure stays disjoint). Ruling §11 A-H all covered.
FORWARD OBLIGATION:          CRM_CUSTOMER_REF_CRYPTO — see "Forward obligations opened by 087". OWNER: UNASSIGNED
                             (frozen bytes assign it to no package; NOT arbitrarily assigned to 088-092).
NOTE (2026-09-01, CI fact):  the Supabase local stack — and the platform — PRE-INSTALL pgcrypto as a default
                             extension (CI run 33575394319 found pg_extension.pgcrypto present on a fresh
                             replay that installs only pg_cron + pg_net). The ruling's condition is therefore
                             enforced as "087 creates no extension AND no 087 routine references a pgcrypto
                             symbol" (suite 151 E16 + the x6_gate no-`create extension` check), not as
                             "absent from the cluster". Platform availability of hmac()/gen_random_bytes()
                             is an INPUT to the CRM_CUSTOMER_REF_CRYPTO ratification (items 1-5), not a
                             licence to use them before it.
```

## Owner rulings ratified in the 087 authorization (recorded)

- **ODR16 #34 — `venue.export_job.requested_by` (OWNER DECISION → RULED, 2026-09-01):** the column is RETAINED through the ordinary `purge_after` lifecycle; erasure of the requester does NOT immediately NULL, rewrite or hard-delete it; this is NOT a new permanent retention class (the job row already purges at 13 months). Physical form: `NOT NULL`, FK → `auth.users` `ON DELETE RESTRICT` (never CASCADE), untouched by `kernel.on_identity_erased_*`. Asserted structurally (suite 151 A18: `confdeltype='r'`).
- **CRM export privacy ruling (2026-09-01; PROVENANCE: the owner's PACKAGE 087 IMPLEMENTATION AUTHORIZATION, section "CRM EXPORT PRIVACY RULING APPROVED" — an owner-issued ruling recorded here, not a decision 087 opened; no new signature was required because its §11 nuance resolved corpus-determined):** eligibility/consent are evaluated against the boundary the FROZEN contract defines — membership at `as_of` (request), the consent gate at `gate_as_of` (CRM §5.1 (1)/(3), K-19: stamped at CLAIM, re-stamped on re-claim, one instant for the whole build). X-6 preserved; NO demographic expansion. The §11 potential stop ("what happens when consent is revoked after request but before finalization") is CORPUS-DETERMINED and needed no owner decision: a withdrawal before the claim suppresses the cell; a withdrawal after the claim is honoured by the NEXT build (§5.3 binding copy: "takes effect at the next export build"); a re-claim after lease expiry re-stamps and rebuilds from page 1. 087 stores `gate_as_of` and stamps it at claim (suite 151 D15/D24); the gate's evaluation itself lands with the un-park.

## Errata (corpus-determined corrections) — package 087

- **E-67** — `kernel.close_settlement`'s R-40 chargeback arm reads `kernel.dispute_native`, a table created by 088 (schema §1.10b): a SEAM-1 forward reference that 087 cannot author. 087's close already books `chargeback`-cause lines into `refunds_minor` (sign-derived, E-73); the SOURCE of those lines is 088's. **The mechanism is NOT determined by the corpus and 087 asserts neither:** §0.4b says the caller is "authored once and never rewritten by another package" (→ a third SEAM-2 hook `kernel.settlement_chargeback_lines`, stub 087 / body 088), while plan §8/087 lists exactly two hooks and plan §8/088 schedules no rewrite of `close_settlement` (→ either resolution edits a frozen row). **FILED as an owner/architect decision for 088's authoring** (hook vs body rewrite; a plan/registry amendment either way), together with the fee/royalty split and C31 rounding-bearer assignment (they need the first seam that produces a split) and the R-40 `open_dispute` gate on `request_org_payout`. 087 ships the arithmetic complete over whatever lines exist. The two settlement seams return zero rows at 087 exactly as plan §8/087 states.
- **E-68** — CRM §12 24a asks `authorize_export_download` to `raise insufficient_privilege(42501)` AND write a `crm_export.denied` row in one call. Unbuildable in one transaction (the raise rolls the row back). The corpus's own answer to this shape is the R-28 client-recorded denial witness (`kernel.record_money_denial`), whose action vocabulary is money-only and lives in immutable 085. 087 RAISES on denial (fail closed, never fail open); the CRM denial witness is a recorded forward obligation, not an invented object.
- **E-69** — The X-6 assurance plan names its pgTAP file `140_crm_export_x6.sql`; `140` is the outbox-foundation suite. It lands as `152_crm_export_x6.sql`. The plan's SCANNED_PATHS include the frozen spec documents with `-- x6-allow: naming-only` markers on every naming line; those documents carry 1 + 2 markers and hundreds of naming lines, and adding markers would be an edit to frozen documents. The T-CI-X6-01 scan set is therefore the SQL/TS export sources (§10.2's globs + `*settlement_and_export*.sql`); the documents remain in rule 3's rename-tripwire corpus. `T-CI-X6-05` (the committed closure lock) needs a verify run that does not exist without staging → deferred; its database-side twin `T-RPC-CRM-19` runs on every PR in suite 152. pgTAP cannot read the JSON manifests, so suite 152 embeds the two lists between markers and `scripts/ci/x6_gate.sh` DIFFS them against the manifests on every PR (one truth, drift detected).
- **E-70** — The corpus asks for "a `platform_risk` signal" (blank-column canary, purge stalled > 3 attempts, a `ready` job with no object) and names no carrier; the ratified notification type set is closed (OR-20 note). The carrier is a `kernel.admin_audit` row, `action='crm_export.signal'` (schema §1.12: the action vocabulary is deliberately open), `reason_code ∈ {blank_column_canary, purge_stalled, ready_without_object}`, `after.audience='platform_risk'` — readable by platform roles, never by a venue.
- **E-71** — Schema §3.18 A4 names `venue.build_export_rows` as the CLAIM writer (`gate_as_of`, the counters); the worker holds no table access (§16.6: `service_role` UPD is `R(def)`). The claim is therefore page 1 of `build_export_rows` (`p_cursor IS NULL`): queued→running under a 10-minute `lease_until` (longer than the worker's 15 s page timeout), and a re-claim after lease expiry re-stamps `gate_as_of` and rebuilds from page 1; a live-leased job refuses a second claim. CRM §7.3's "2 concurrent running jobs per org — queued behind" is enforced AT CLAIM (a third build raises and the cron retries).
- **E-72** — The X-6 plan's `gate_evaluations` fifth counter (`T-SCHEMA-CRM-10`) is NOT added: it is absent from the frozen schema §3.18 column list, the plan "edits no contract", and its only writer is the parked builder — an unwritten column is the dumping-ground shape. It is folded into the CRM_CUSTOMER_REF_CRYPTO un-park (where the writer lands).
- **PFA-9 applied** — CRM §7.1's "all limits live in `catalog.platform_config`" has no frozen key spellings and 078 seeds none (PFA-9 CLASS B); the frozen §7.1 NUMBERS are enforced in-RPC through the fail-closed 005 limiter (`public.check_rate_limit`), per actor AND per org (the org row is keyed on the org id). `crm_export.constraint_set_version` IS seeded by 078 and is read live (X-9), NULL ⇒ refuse (X-12).

### Errata — 087 red-team remediation (money · privacy · parity lenses, 2026-09-01)

- **E-73** — The settlement buckets are derived from the FROZEN SIGN CONVENTION, not from an invented cause→bucket table. Schema §3.14 lines are signed (credits +, debits −) and §3.13.1 defines gross = Σ positive revenue lines, fees = Σ the fee/royalty lines, refunds = Σ the refund lines; no document maps D3 causes to buckets. `close_settlement` derives gross = Σ(amount > 0, non-refund cause), fees = −Σ(amount < 0, non-refund cause), refunds = −Σ(refund causes `refund_void`, `chargeback`), so net = Σ ALL lines exactly (T-SCHEMA-SETTLE-04 asserts the header against its own lines, 151 C16a). The seams inherit the §3.14 convention — a debit candidate (royalty, commission) is emitted NEGATIVE — and a candidate in a foreign currency is refused. The first draft's cause-list mapping would have booked an 088 `market_sale` royalty as gross; removed.
- **E-74** — MONEY §9.2 says the approve verb's payout branch "performs the advance"; 085's `payout.request` arm (immutable) records the approval and moves nothing, so the parked dual-control loop had no exit. The contracted writer of `pending → submitted` — `kernel.request_org_payout` — advances a payout whose parked request is `approved` and unexpired (audit `payout.request` / `approved_request`, citing the request), returns the existing pending request instead of parking a duplicate, pins the threshold key's version in `config_versions`, writes `payout.request` on every arm and replays `noop_replay` on an already-submitted payout. The approval row's 72 h `expires_at` mirrors 085's shape; no frozen payout-approval TTL key exists (PFA-9 class).
- **E-75** — RPC §10.1 contracts `open_settlement` idempotency on `p_command_key`; schema §3.13 carries no key column and 087 adds none. The replay rides the `settlement.open` audit row written in the same transaction (`actor_identity`, `reason_code = p_command_key` → `subject_id`), serialized by a transaction-scoped advisory lock on (actor, key). Scope binding (AUTHZ-C1C, the same two-identifier shape §10.3 closes): the venue must belong to `p_org_id` and the event to that venue and org, else `not_found` — otherwise org B's finance could open, close and be PAID for a settlement over org A's venue once the seams fill (151 C2a-C2c).
- **E-76** — `venue.staff_role` is keyed on the venue as a PLACE while `catalog.venue.org_id` is mutable, and RPC §20.7.8's venue arm authorized the place. CRM §4.1/§4.4(e) prove isolation only for the atom predicate; the AUTHZ arm would have handed the prior operator's event/session exports, history and rosters to the new operator's venue staff. Every venue-role arm (`assert_may_request`, `list_export_jobs`, `list_attendees`, `lookup_attendee`) also requires the venue's CURRENT operator to equal the scope's org (151 C41-C44, the re-operation fixture).
- **E-77** — The claim (`queued → running`) is a state transition and CRM §12 32 requires a row per transition; §8.2's action list has none for it. `build_export_rows` writes `crm_export.claim` (schema §1.12 open vocabulary) carrying `gate_as_of` and the lease.
- **E-78** — Schema §3.18's state machine has no `failed → purged` edge while CRM §6.6 gives every job row 13 months; under PFA-28 every built job is `failed`, so rows would accumulate forever. The sweep purges `failed` jobs that never held bytes (`artifact_state ∈ {absent, deleted}`) at `purge_after`, audited `job_row_retention`.
- **E-79** — The two pg_net ticks fire ONLY when the Vault secret `crm_export_worker_secret` exists; an absent secret previously sent an empty `X-Crm-Export-Worker` header and delegated fail-closed to an unauthored worker.
- **E-80** — Text that lands in the immutable audit is bounded: `p_command_key` (request_export, open_settlement), `p_reason_code` (revoke_export) and every filter membership value must match `^[A-Za-z0-9._:-]{1,64}$` (CRM §8.3: never a name, an email, a customer_ref in an audit row). `refund_state`'s "derived enum" has no frozen spelling (PFA-9 class): bounded identifiers, never free text, until spelled.
- **E-81** — `list_export_jobs`, `list_attendees` and `lookup_attendee` raised `not_found` before authorization — an existence oracle for draft-event sessions (CRM §4.2(5) "fails identically whether the scope exists or not"); RPC §20.7.8's "`not_found` in both modes" conflicts with §4.2(5) and 087 keeps the non-oracle reading: an unresolvable scope fails as `insufficient_privilege`, identically to an unauthorized one.
- **E-82** — X-6 scanners: unquoted SQL identifiers fold to lower case and quoted ones are verbatim, so `Kernel.Identity_Demographic` / `"venue"."holder_mix_snapshot"` were invisible to a case-sensitive `grep -F` and a lowercase-only tokenizer. The gate scans case-insensitively; suite 152's walker tokenizes case-insensitively and captures quoted identifiers; mixed-case and quoted poison controls (152 C8b, `poison_mixedcase.sql`) prove both are caught. `scan_device_id` (§2.3 door internals) joins the term list.
- **E-83** — Schema §3.18.1 says `confirm_artifact_purged` "increments `purge_attempts` on a non-success outcome" while RPC §17.22 makes both outcomes (`deleted`, `not_found`) success; no non-success outcome exists. Attempts are counted at CLAIM (a claim is an attempt; a worker that never confirms is exactly the stalled case the counter exists for), and the > 3 signal fires at claim.
- **E-84** — RPC §20.7.8 admits exactly ONE non-raising caller of `assert_may_request` (`list_export_jobs`). `build_export_rows` (job-row re-derivation → `scope_unreachable`) and `revoke_export` (the template-scoped arm) both call it in RAISING mode — the builder under an `insufficient_privilege` handler that records the frozen failure state, revoke behind its requester/platform arms — so T-RPC-CRM-06 holds as frozen (151 B10). RLS §9.13 grants `venue_manager` EXECUTE on `open_settlement` while RPC §10.1 does not; the migration follows RPC (OR-6 subject-matter precedence), noted.

- **E-85** — A dual-control approval binds to the destination it was approved against (MONEY §9.2 applies the setter exclusion to the approver "otherwise the destination-setter could simply approve"; an approval honoured after a later change would route the money to a destination nobody approved). The parked row records `payload.destination_ref`; an approved request is honoured only if that ref equals the org's current destination AND the approval postdates the last destination change — otherwise it is marked `stale` (audited `payout.request_stale`) and the payout parks anew; a pending request whose ref no longer matches is staled the same way (151 C31j-C31r).
- **E-86** — The probation operand: the change instant is the latest of the 085 `org.payout_destination.change` audit and the 077 `org.connect_ref.bind` audit (a first bind is a fresh destination — the restrictive X-12 reading; the owner may loosen it); "the first payout" is decided by the `payout.state_sync` audit (`after.status='paid'` after the change), never `updated_at`, which a later hold overlay may bump; a release suppresses the arm only when it released THIS probation (`payout.release` with `reason_code='destination_probation'` at/after the change) — a risk-hold release does not. The probation arm also writes `payout.request` (§10.3 Writes lists both).
- **E-87** — `request_org_payout` refuses an org with no Stripe Connect destination (`precondition_failed: no_payout_destination` — a `submitted` payout with nowhere to go strands the settlement: Stripe fails it, `failed` is terminal, the close's idempotency key prevents a re-mint); a payout under a platform RISK hold is refused (`precondition_failed: payout_held` — `held` is not a member of §10.3's result set); the payout pick prefers a pending sibling over a submitted one. A pre-existing ABBA (`mark_payout_transfer_state` locks Payout → the hook locks Settlement, vs Settlement → Payout here) can only surface as a 40P01 retry, never a double disbursement; it is 085's lock order and is filed for the 088 pass. `pending_platform_review` / class `platform` are never produced (no frozen operand key; X-12 parks to `org`).
- **E-88** — The E-76 operator binding applies to the money arms: `close_settlement`'s venue_finance arm requires the venue's current operator to equal the settlement's org (151 C40a); `open_settlement` already binds venue→org (C40b). `open_settlement`'s replay refuses a command key reused with different parameters (`idempotency_conflict`) rather than aliasing the original header.

### Forward obligations added by the remediation

- **088 authoring decision (owner/architect, filed):** the chargeback-arm mechanism — a third SEAM-2 hook vs a body rewrite of the authored-once `close_settlement` (E-67); either amends plan §8 / the registry. Not a 087 stop: 087's arithmetic is complete over whatever lines exist.
- `reconcile_export_orphans` trusts the listing's completeness (the frozen signature admits no completeness flag): the `crm-export-worker` `/purge` contract must pass the COMPLETE `{org_id}/` listing (all pages) before the (←) direction runs — recorded against the worker deployment obligation.
- The worker's `X-Crm-Export-Worker` compare must reject an empty/missing header with a constant-time compare (§12 31e); E-79 removes the empty-header cycle, the worker still owes the check.
- A `payout.request` approval never re-requested expires after 72 h; the approve verb does not advance (E-74). The un-park/088 pass may move the advance into an approve-side hook if "the sibling branch performs the advance" is ratified as the mechanism.
- MB-1b (the caller-minted payout tier subject) is the money spec's own OPEN owner decision D-10; payouts are splittable today by the corpus's admission. Not opened by 087, not closable by it.
- `T-RPC-CRM-14`'s OR-19 mint concurrency assertion joins the CRM_CUSTOMER_REF_CRYPTO deferred-test list (with the mint).

## Forward obligations opened by 087

- **`CRM_CUSTOMER_REF_CRYPTO` (OWNER-recorded; OWNER: UNASSIGNED)** — before any customer_ref-emitting read or export becomes operational, explicitly ratify: (1) crypto primitive, (2) location of computation, (3) key custody, (4) `org_customer_key` handling, (5) whether DB, edge or server computes the HMAC, (6) base32 encoding implementation, (7) truncation exactness, (8) key rotation semantics (OR-20 runbook), (9) backward compatibility of existing customer_ref values, (10) cross-export stability, (11) backup/restore behaviour, (12) logging/redaction, (13) service_role exposure, (14) test vectors. The un-park then delivers, body-only: the three readers, the OR-19 lazy mint, the `gate_evaluations` counter (E-72), and the deferred assertions `T-RPC-CRM-16/17/18`, `T-SCHEMA-CRM-10/11`, CRM §12 3-13c/18-18c/22-22c/23/34a-34h, `T-RLS-CRM-04`, `T-VERIFY-X6-01..06`.
- **CRM denial witness** (E-68): a client-recorded `crm_export.denied` path (an `R-28`-shaped witness with a CRM vocabulary, or a widening of `record_money_denial` in a future package).
- **`T-CI-X6-05` closure lock** (E-69): needs a verify step that commits `supabase/ci/x6_closure.lock`.
- **The two edge deployments** `crm-export` (`/download`) and `crm-export-worker` (`/build`, `/purge`) with `CRM_EXPORT_WORKER_SECRET` in Vault as `crm_export_worker_secret` — deploy artifacts, not SQL; 087's two pg_net ticks target the worker URL and send the header from Vault (an absent secret sends an empty header → the worker refuses). Until deployed, the ticks 404 harmlessly each cycle.
- **Staging verify** for 087 (no staging plan) — as for every prior package.

## PFA-29 — chargeback → settlement mechanism: the 088-owned `settlement_royalty_lines` seam carries BOTH 088 line classes (royalty + chargeback)

```
ID:                          PFA-29  (SEAM/plan amendment class)
FROZEN RULE:                 RPC §10.2 places the R-40 chargeback-lines arm INSIDE kernel.close_settlement
                             ("the close additionally writes one negative venue.settlement_line with
                             cause='chargeback' … idempotent on the cross-settlement unique"); plan §8/087
                             "close_settlement (authored once, here)"; plan §0.4b / schema §13.2 "the caller
                             is authored once and is never rewritten by another package"; hook_count = 19
                             (REG:594, PLAN:185, SCHEMA:4200, RAT:598); plan §8/088 schedules no rewrite of
                             close_settlement and "no hook, no edge" for R-40 (OR-24: "ZERO hooks, ZERO edges").
IMPLEMENTATION CONFLICT:     the arm's source (kernel.dispute_native) is an 088 table; the merged 087 body
                             iterates EXACTLY the two seams, so no frozen byte authorizes a rewrite, none
                             authorizes a third hook, and a pure third hook would be called by nothing.
OPTIONS:                     O-A body-only CREATE OR REPLACE of close_settlement in 088 (breaks "never
                             rewritten"); O-B a third hook + O-A (hook_count 19→20, dominated); O-C emit the
                             chargeback candidates from the EXISTING 088-owned settlement_royalty_lines body
                             (zero objects, count 19, no rewrite, rollback restores the 087 stub; the hook's
                             name under-describes it); O-D defer the arm (new money policy — owner-only).
OWNER RULING (2026-09-02):   O-C APPROVED. Do NOT rewrite kernel.close_settlement; do NOT add a third
                             settlement hook; hook count stays 19. kernel.settlement_royalty_lines'
                             088 body is the canonical 088 settlement-line-source seam for BOTH native
                             resale royalty candidates AND native chargeback candidates. The naming
                             mismatch is accepted as a governance/documentation erratum (E-89); do not
                             "clean up" the name by introducing a hook.
ACCOUNTING (corpus-determined, unchanged): a chargeback is an APPEND-ONLY negative settlement line,
                             cause='chargeback', cause_ref = the native dispute id, in the org's NEXT
                             eligible settlement (PROMOTER §5.3, RPC §10.2), booked into the refunds bucket
                             by 087's sign-derived rollup (E-73); a closed settlement is never mutated, no
                             header is rewritten, no clawback (MONEY §9.4), no org identity obligation
                             (schema §1.10a). Duplicate booking is prevented by NOT EXISTS over
                             settlement_line (cause='chargeback', cause_ref) evaluated under the
                             settlement's FOR UPDATE — the partial unique is a Gate-M structural property
                             (schema §3.14.1), so no Indexes-row amendment.
PACKAGE IMPACT:              088 only (the seam body it already owned). DAG IMPACT: none.
SECURITY / MONEY IMPACT:     none loosened; the seam stays STABLE, pure, never raises (§20.11.1).
OWNER SIGNATURE REQUIRED:    YES.    OWNER SIGNATURE: APPROVED.    STATUS: SATISFIED / RATIFIED.
```

- **E-89** — `kernel.settlement_royalty_lines` (RPC §20.11.1 "adds the market_sale royalty arm"; plan §8/088 "adds the market_sale royalty arm") is, by PFA-29, the 088 line-source seam for royalty AND chargeback candidates. The name is retained (SEAM-2a freezes it); the Purpose is read as "the 088 settlement-line sources". Its determinism/no-raise posture is unchanged and now also binds the chargeback arm.
- **E-90 (royalty sign; owner-ruled 2026-09-02 in the PFA-29 packet)** — schema §3.13.1's bucket sentence ("`fees_minor` — Σ the platform-fee and royalty lines") conflicts with the ratified product/subject-matter economics (DA §683 "venue gets: venue_royalty → event settlement → org payout"; dashboard §1075 "your sold-out event keeps earning"). **RULING: a native resale royalty owed to the venue is a POSITIVE venue earning** — the 088 royalty candidate is emitted as a CREDIT (+) and lands in GROSS under 087's sign-derived buckets (E-73). §3.13.1's sentence is read as naming fee lines (and any royalty the org PAYS), not the royalty the org earns. No other bucket changes. Test: a royalty candidate of +100 raises the settlement's gross/net by exactly 100.

## PFA-30 — the native resale 3-way split (platform / venue / seller) PARKED fail-closed

```
ID:                          PFA-30  (PFA-9/PFA-26 class — money policy the corpus does not fix)
FROZEN RULE:                 market_sale carries platform_fee_minor / venue_royalty_minor /
                             seller_proceeds_minor with a split-sums CHECK "(± the named rounding bearer)"
                             (schema §4.4); checkout_buy_now ⑦ and respond_offer(accept) write the split
                             from "the listing's immutable policy snapshot" (RPC §20.8.8, §20.8.6); C31 names
                             settlement_line.is_rounding_bearer.
IMPLEMENTATION CONFLICT:     no platform-fee key or value exists anywhere (PFA-9 CLASS B: "the resale
                             platform ceiling … no key"); the royalty basis (full price vs above-face
                             delta) is unstated; NO byte names which party bears the rounding residual.
                             088 owns the split arithmetic and none of its inputs is frozen.
OPTIONS:                     (a) PARK the split-writing paths fail-closed until the policy is ratified;
                             (b) the owner names key/value/basis/bearer now.
OWNER RULING (2026-09-02):   (a) PARK FAIL-CLOSED. Do NOT invent a platform fee rate/key/value, a royalty
                             basis or percentage, a rounding bearer, fallback percentages, an implicit zero
                             fee or zero royalty. Every 088 path that must author the split FAILS CLOSED
                             before any money/state is committed — zero guessed fee/royalty/proceeds,
                             zero partial split row, zero sale terminalization or payout on invented
                             economics. The feature flag stays dark. Tests may drive downstream engines
                             with explicitly controlled fixtures; production-shaped client paths never
                             synthesize a split.
AFFECTED SET (derived):      the two frozen split WRITERS — market.checkout_buy_now (step ⑦, the
                             market_sale INSERT) and market.respond_offer (accept: the market_sale INSERT
                             before the engine call). finalize_market_sale / transfer_ticket_ownership /
                             on_atom_voided consume a stored split and compute none; p2p transfers carry
                             no platform split (RPC §8.x). Error: precondition_failed
                             ('resale_split_unavailable … PFA-30') — the frozen §0.5 vocabulary, no new
                             taxonomy.
OWNER SIGNATURE REQUIRED:    YES.    OWNER SIGNATURE: APPROVED.    STATUS: SATISFIED / RATIFIED.
```

## PFA-31 — `kernel.resolve_dispute_native` dual control PARKED fail-closed (PFA-18A principle, applied explicitly to disputes)

```
ID:                          PFA-31  (PFA-18A class — dual-control mechanism unbuildable under immutable bytes)
FROZEN RULE:                 RPC §20.7.15 / RLS §11: platform_risk / platform_support PROPOSE ONLY (park a
                             kernel.approval_request with required_approver_class='platform_admin');
                             platform_admin EXECUTES with step-up + dual control.
IMPLEMENTATION CONFLICT:     077's immutable kernel.approval_request CHECKs admit action ∈ {refund.issue,
                             payout.request, config.set_money_key} and subject_kind ∈ {order, settlement,
                             config_key} with a pairing CHECK — no dispute action/subject exists; OR-24
                             ratified "ZERO edges … NOT authorized: new money policy, SQL".
OPTIONS:                     (a) PARK fail-closed (zero terminal resolution mutation) until a
                             dispute-compatible dual-control mechanism is ratified; (b) overload an
                             existing action label — FORBIDDEN; (c) single-control platform_admin —
                             FORBIDDEN (downgrade); (d) a shadow approval table — FORBIDDEN.
OWNER RULING (2026-09-02):   (a) PARK FAIL-CLOSED. resolve_dispute_native raises
                             'precondition_failed: dual_control_unavailable … (PFA-31)' with ZERO
                             mutation for every caller class, signature frozen for the un-park. Independent
                             dispute behaviour CONTINUES where frozen: record_dispute_native (upsert +
                             freeze legs), mark_dispute_state (processor-driven, forward-only), dispute
                             holds on atoms and payouts, deletion blocking (BP-7 twin), audit. While
                             parked an unresolved dispute STAYS HELD: no auto-release of dispute_hold, no
                             payout finalization, no custody unlock, no resolved marking, no fabricated
                             approval, no silent expiry — unless a separate frozen terminal transition
                             independently authorizes it (mark_dispute_state's Stripe-reported terminal
                             is a STATE fact and releases nothing).
OWNER SIGNATURE REQUIRED:    YES.    OWNER SIGNATURE: APPROVED.    STATUS: SATISFIED / RATIFIED.
NOTE:                        PFA-18A did not change the dispute architecture; this is its principle
                             applied to a new surface, recorded on its own id.
```

## Forward obligations opened by the 088 rulings (OWNER: UNASSIGNED unless frozen bytes assign them; not arbitrarily assigned to 089-092)

- **`NATIVE_RESALE_SPLIT_POLICY`** — before native resale activation, ratify at minimum: (1) platform fee key, (2) platform fee value/rule, (3) venue royalty key, (4) venue royalty value/rule, (5) royalty basis (full resale price · above-face delta · another explicit basis), (6) seller proceeds formula, (7) rounding mode, (8) rounding bearer, (9) zero/negative edge cases, (10) refunds, (11) chargebacks, (12) partial reversal behaviour, (13) settlement bucket mapping. Un-park = the two split writers (PFA-30) + the `is_rounding_bearer` assignment the royalty seam then carries.
- **`DISPUTE_DUAL_CONTROL`** — a credential/dispute-compatible dual-control mechanism (not a second generalized approval framework, not a shadow table) before dispute resolution activation; un-park = `resolve_dispute_native`'s body (PFA-31).
- **`NEGATIVE_SETTLEMENT_CARRY`** — 087's close mints a payout only when net > 0 (kernel.payout.amount_minor > 0) and the corpus provides no carry-forward for excess negative settlement value; a chargeback larger than the next settlement's positive balance is absorbed beyond one settlement. NOT authorization for the platform to absorb such losses in production — a dark-rail residual that must be resolved before native money activation. 088 invents no carry account.
- **`PUBLIC_PAYMENTS_NATIVE_SHAPE`** (filed, non-blocking for 088 SQL) — `public.payments.listing_id NOT NULL → public.listings` (frozen Phase-0) has no native-sale writer while `market_sale.payment_id` and `kernel.dispute_native.payment_id` FK `public.payments`; the native money path cannot record a payment without a live-rail listing row. No fake listing row, no opportunistic Phase-0 mutation, no activation: a deployment/live-rail compatibility decision owed before native money activation.
- **`P2P_TRANSFER_TTL`** (088 implementation park, PFA-9/X-12) — RPC §8.1 writes `expires_at := now()+TTL` and names no key for the TTL anywhere in the frozen corpus. `market.create_p2p_transfer` runs every validation (owner, atom state, freeze, policy, cap) and then FAILS CLOSED with `precondition_failed: p2p_ttl_unavailable` — zero mutation; the accept / decline / cancel / sweep verbs are real and exercised over directly-seeded rows. Un-park = the named key (a `catalog.platform_config` seed, restricted) + the one `expires_at` line. Owner: UNASSIGNED.
- **`PAID_PENDING_DWELL_SLO`** (088 implementation park, PFA-9/X-12) — RPC §12.3's C25 dwell bound is "named in the Edge/ops spec"; no key exists in any byte. `market.sweep_paid_pending_sales` is INERT (selects nothing, writes nothing, returns `{completed:0, compensated:0, status:'inert', reason:'dwell_slo_unnamed'}`); the webhook-prompt completer `finalize_market_sale` and the C26 compensate hook are real. Un-park = the named key + the sweep body (complete-XOR-compensate under the listing → atom → payment/refund ladder, freeze on the complete branch only, lost/charge_refunded refund-leg-satisfied arm). Owner: UNASSIGNED.
- **`RESALE_CHECKOUT_SWEEP_TICK`** (088 deploy artifact park, PFA-9/E-79) — the Edge spec names the worker's env var `INTERNAL_CRON_SECRET` for `resale-checkout /sweep-lapsed` but no Vault secret name and no header name exist in any byte (notify-dispatch's tick is not in migration bytes either). 088 schedules the two pure-DB sweeps and NO pg_net tick; nothing is lost while `checkout_buy_now` is parked (no initiated reservation can exist). Un-park = the Vault name + header (with the edge deployment) + one `cron.schedule` row (2-minute cadence per the register). Owner: UNASSIGNED (ops/edge).
- **`REQUEST_ORG_PAYOUT_OPEN_DISPUTE_GATE`** (E-96) — RPC §10.3 / R-40 name an `open_dispute` refusal on `kernel.request_org_payout`; that function is 087's authored-once body and 088 may not rewrite it (the same principle as PFA-29 O-C). Today the refusal is delivered by `record_dispute_native`'s payout leg (every reachable pending/submitted payout → `hold_state='held'` → `request_org_payout` raises `payout_held`, E-87) for disputes recorded while the payout exists; a settlement CLOSED AFTER the dispute opened mints an unheld payout. Un-park = a body-only amendment to 087's `request_org_payout` (an owner-signed PFA, since it touches an authored money verb) or a settlement-close-time hold. Owner: UNASSIGNED.

## ERRATA recorded by package 088 (no amendment needed; frozen bytes win as stated)

- **E-89** — the 087-stub name `kernel.settlement_royalty_lines` under-describes its 088 body: per PFA-29 O-C the seam returns BOTH the native-resale royalty candidates AND the native chargeback candidates. Name frozen (SEAM-2a); recorded, not renamed.
- **E-90** — a venue royalty is a POSITIVE venue earning: the candidate is a credit (+) and lands in GROSS under 087's sign-derived buckets (E-73). Owner-ruled 2026-09-02; tested (153 §H: +100 candidate → gross +100).
- **E-91** — schema §4.1's column list for `market.listing_native` omits `listing_mode` and `reason_code`, both required by RPC §20.8.1/§20.8.2 (the mode the seller chose; the cancel reason). Implemented as `listing_mode text CHECK (buy_now|auction|offer)` and `reason_code text`.
- **E-92** — plan §8/088 asks for a DROP/ADD CHECK pair adding `'dispute_hold'` to `kernel.tickets.resale_state` and `venue.door_manifest_entry.resale_state`; the 079 and 086 bytes ALREADY carry the five-label form. 088 verifies (fail-loud DO block) instead of re-adding; the rollback does not regress the CHECKs.
- **E-93** — `kernel.dispute_native.resolved_by` is an ODR-16 SPEC-SILENT identity-FK class: implemented `ON DELETE RESTRICT` (TOMBSTONED — auth.users terminal state is the tombstone, never a physical delete); the resolution quadruple carries a pairing CHECK (all four NULL ⇔ none set).
- **E-94** — the chargeback arm books ORDER-linked disputes (`payment_native.order_id → venue.order.org_id`) against the org in full (PROMOTER §5.3: the org absorbs; commission not pursued). A NATIVE-RESALE (sale-arm) dispute is NOT booked against the org: the org held only the royalty share and RPC §20.7.14 assigns org-held resale proceeds to "BP-11's org's (C31, Gate-M)". Fail-closed; dark rail; C31 owes the resale-side clawback shape.
- **E-95** — RPC §20.11.3's "a completed sale raises conflict_locked" cannot hold in `market.on_atom_voided`: the hook runs on EVERY void, including `catalog.cancel_event` voiding a successfully-resold atom, and a raise there would abort every event cancellation with resold inventory. Implemented: pending → compensated; completed → NO-OP (never flipped — the C26 XOR holds); the void's own cause_ref is the refund, not the sale. Tested (153 §J).
- **E-96** — see `REQUEST_ORG_PAYOUT_OPEN_DISPUTE_GATE` above.
- **E-97** — `kernel.transfer_ticket_ownership` "re-pins signing_key_id" per RPC §7.2, but no ratified resolver exists (`kernel.resolve_active_signing_key` is MENTION-OK, built nowhere; E-47's rotation un-park owns key selection). The engine keeps the atom's pinned key; the credential-version bump alone supersedes the old credential.
- **E-98** — the resale-policy → listing rule is derived from the 078 CHECK set (`off · transfers_only · fixed_cap · face_value_queue · buy_now · auction · offer`; 078's own comment marks RPC §20.2.2's `{off, capped, free}` sketch stale): off/transfers_only/face_value_queue/auction refuse a native listing; buy_now/offer bind `listing_mode`; fixed_cap requires a cap; any present `price_cap_bps` binds as `price ≤ floor(face × bps / 10000)` in integer minor units (bps ∈ [0,10000] by CHECK ⇒ at-or-below face). Governing policy = the event-scope latest version, else the venue's; none ⇒ refused (C11 default off). p2p: `off` refuses; a priced send honours a present cap.
- **E-99** — RPC §8.2 `accept_p2p_transfer(p_transfer_id, p_command_key)` and §8.3's "`accept_p2p_transfer` with `p_decision='decline'`" are reconciled by a DEFAULTED third parameter `p_decision text default 'accept'`: the two-argument shape stays callable, the overload count stays 1, the decline branch is the contracted owner of `declined`.
- **E-100** — a handle-addressed transfer (`to_identity NULL, to_handle set`) has no ratified handle→identity resolver; acceptance is refused `handle_resolution_unavailable` (fail-closed). No transfer can be created with a handle in 088 anyway (P2P_TRANSFER_TTL).
- **E-101** — a PRICED p2p acceptance has no contracted binding between the transfer and its `public.payments` row (§8.2 says "a verified public.payments row for the recipient" with no key); refused `payment_unverified`. Gifts complete.
- **E-102** — `catalog.cancel_event` voids only atoms with a refund lineage (seq-1 `issue` row → `venue.order_item` → order → `payment_native`); comp/import mints (no order item; a synthetic cause_ref) have nothing to refund and are skipped with an `event.cancel_skip` audit (`no_refund_lineage`). The cancelled session already denies their scan. Refunds are ONE per originating ORDER (amount = Σ voided items' unit prices, §11.4 sum-guarded against prior refunds AND lost/charge_refunded disputes), idempotency key `<command_key>:order:<order_id>`.
- **E-103** — the unlock re-arm (PFA-13) and the engine's open-dispute refusal bind an open dispute to the atom ONLY while the CURRENT holder is that payment's buyer (order arm: the holder is the order's buyer; sale arm: the holder is that completed sale's buyer) — the same custody-moved rule `record_dispute_native` applies on the freeze side (custody moved ⇒ skip + alert). A primary buyer's chargeback after a completed resale does not hold the new holder's atom.
- **E-104** — `kernel.settlement_royalty_lines` is VOLATILE (the 087 stub was STABLE; volatility is not part of the SEAM-2a freeze — signature, parameter names, return type and overload count are unchanged) and takes a per-org TRANSACTION advisory lock before emitting candidates. Reason: two settlements of one org closing concurrently would both pass the `NOT EXISTS` dedupe (PFA-29 relies on the caller's settlement lock, which does not serialize a sibling settlement); a STABLE body keeps the calling statement's snapshot and cannot see a line committed while it waited, so the lock alone would not suffice. The lock is released at commit; the loser's queries take fresh snapshots (VOLATILE) and see the sibling's line. PFA-29 defers the structural cross-settlement partial unique to Gate-M (§3.14.1) — `CHARGEBACK_CROSS_SETTLEMENT_UNIQUE` below is that successor. Proven by race R8 (two live sessions).
- **E-105** — `market.market_sale` carries a partial UNIQUE on `payment_id` (`WHERE payment_id IS NOT NULL`): one succeeded payment settles ONE sale (C35 / R-34 "one link born at transfer" / §20.8.7 write-once). Not in schema §4.4's index list; the engine additionally refuses a payment already linked to another order/sale (`payment_unverified`) and `mark_sale_paid_state` refuses `payment_reused` / `payment_intent_mismatch` / a second payment on a paid sale.
- **E-106** — the anon discovery arm for `market.listing_native` (RLS §10.1/§10.2, plan §8/088 Tests "to anon only when the flag is ON") is undeliverable at the market-schema layer: 076's wall grants `anon` no USAGE on `market`. PFA-14 (owner-signed) ruled exactly this class for the venue layer and moved the delivery boundary to a separately reviewed public read surface; 088 applies the same ruling — no anon grant is written (a dormant grant would only invite a later accidental USAGE), the flag-gated public arm is delivered to `authenticated`. Recorded for owner countersignature as a PFA-14 extension. **OWNER COUNTERSIGNATURE (2026-09-02): APPROVED — CLOSED.** PFA-14 remains controlling: direct anonymous venue/market schema access stays closed; any future unauthenticated marketplace read surface must be explicitly designed and ratified as a public projection/API; anon schema USAGE is not widened; no broad anon SELECT policy is added merely to support future discovery. The dark native-resale rail requires no anon exception.
- **E-107** — the money-landing arms of `market.mark_sale_paid_state` (a payment on a cancelled / terminal / already-paid sale, a PI mismatch, a reused payment) are NON-RAISING: they write one idempotent `market_sale.alert` audit row per (sale, payment) and return `{status: state_conflict | conflict_locked, reason, action: reverse_payment}`. §20.8.7 names `conflict_locked` as an error; a raise would roll the alert back and make the webhook retry forever with no reversal signal — the label is preserved in the result, the alert survives.
- **E-108** — recorded deviations without an owner-level ambiguity: (a) `respond_offer` implements `accept | decline`; the `counter` decision (§20.8.6) has no ratified shape (a counter is a seller-authored offer with no table for it) — `OFFER_COUNTER_DECISION` below; (b) authority readings taken where RPC and RLS differ: `cancel_event` admits `platform_admin` (RPC §4.4; RLS §11.1 omits it) and `cancel_listing` excludes `platform_support` (RPC §20.8.2; RLS §10.1 lists it) — EXEC-DERIVED / §5.3: the RPC authority line governs; (c) error-label drift kept as implemented and named here: `cancel_listing` on a reserved listing → `sale_in_flight`; `cancel_buy_now_sale` on a non-initiated sale → `state_conflict`; `checkout_buy_now` on a reserved listing → `listing_reserved`; `mark_sale_paid_state` success returns `ok` (not `updated`); (d) client-supplied reason codes and command keys that land in `kernel.admin_audit` are bounded to `^[A-Za-z0-9._:-]{1,64}$` (E-80) and clients may not write the system reasons `door_freeze` / `event_cancelled` / `expired`; (e) `cancel_event`'s per-atom void keeps 085's `void_ticket_atom` batch lock (rank 2 inside the void) — 088 pre-locks the session's batches (rank 2) before the atom loop, so 088's own path is ascending; a deadlock remains possible against 085's `refund_primary_order` (payment → atom → batch, immutable) — `VOID_PATH_LOCK_LADDER` below.
- **E-110** — `catalog.cancel_event` refund routing for a RESOLD atom: an atom acquired through a COMPLETED native sale refunds the LATEST such sale's PAYER (the last money-in for that atom); atoms with no completed native sale refund the originating order's payer (a gift/p2p chain leaves the original payer out of pocket). The reseller's proceeds/royalty clawback is `NATIVE_RESALE_SPLIT_POLICY` (10). RPC §4.4 says "void + refund all issued atoms" without naming the payee for a resold atom; refunding the originating order would pay a reseller who already received proceeds. Dark under PFA-30; tested on the seeded completed sale (153 L21a/L21b). **OWNER COUNTERSIGNATURE (2026-09-02): APPROVED — CLOSED.** Requirements ratified: the latest completed sale wins for buyer-side refund routing (the current economic buyer); prior historical buyers are not refunded again; exactly-once money-return semantics remain mandatory (per-sale idempotency key bound to the payment, §11.4 sum guard incl. chargebacks); paid-pending / incomplete sales follow their separately frozen handling (the paid-pending arm and the C26 compensate hook); custody/history remains append-only; no historical sale record is rewritten (E-95).
- **E-111** — `listing_native_atom_active_uq` spans `status IN ('active','reserved')` (schema §4.1 pre-dates R-37's `reserved`; "an atom is listed once at a time" must include a reservation in flight), and `create_listing` treats an atom whose overlay is not `none` — or 079 `lock_ticket`'s same-target `noop_replay` — as `conflict_locked` (a new listing is never a replay of another listing's lock).
- **E-112** — X-6 vocabulary: 088 introduces the Stripe-reference spellings `stripe_dispute_ref` / `stripe_charge_ref` / `stripe_pi_ref` / `payment_intent_ref`; they join `x6_forbidden.json` (floor 32 → 36) so the rule-3 tripwire catches the synonyms, not only Phase-0's `stripe_payment_intent_id` / `stripe_charge_id`. `p2p_transfer.to_handle` is scrubbed on erasure of its addressee.
- **E-109** — the chargeback amount booked against the org is the FULL disputed amount (the org received the primary sale; PROMOTER §5.3 "the org absorbs it"); whether any platform-retained buyer fee inside that amount should be netted is an economics decision the corpus does not fix — filed under `NATIVE_RESALE_SPLIT_POLICY` items (11)/(13).

## Forward obligations opened by the 088 red team (OWNER: UNASSIGNED unless frozen bytes assign them)

- **`CHARGEBACK_CROSS_SETTLEMENT_UNIQUE`** (Gate-M; PFA-29 / §3.14.1) — the partial unique `ON venue.settlement_line (cause_ref) WHERE cause IN ('chargeback')` (and the royalty analogue if the period semantics are ratified) is the structural successor to E-104's advisory lock. Until it lands, E-104 is the only cross-settlement dedupe.
- **`LISTING_EXPIRY_SWEEP`** — `market.listing_native.status = 'expired'` has no writer; `kernel.sweep_expired_ticket_atoms` (079) expires a listed atom and leaves its listing `active` (publicly visible while the flag is ON; 16d deletes only draft/cancelled). Owed: a listing sweep (or a body-only amendment to 079's sweep) that cancels/expires the listing and withdraws its offers when the atom expires.
- **`REFUND_HOLD_RELEASE_REARM`** — 085's refund-hold release paths write `kernel.tickets.resale_state = 'none'` directly instead of through `kernel.unlock_ticket`, so the PFA-13 dispute re-arm does not run on them (the engine's R-40 mirror still refuses the move, so custody is safe; the overlay is merely not re-labelled). Owed: an owner-signed body-only amendment to 085 or a 088+ release primitive those paths adopt.
- **`PROMOTER_COMMISSION_PAYOUT_HOLD`** (090) — `record_dispute_native`'s payout leg reaches settlement and sale payouts by `cause_ref`; 090's `promoter_commission` payouts are reached only if they carry `cause_ref = settlement_id` (§20.7.13 A-F5). 090 must keep that shape or extend the leg.
- **`OFFER_COUNTER_DECISION`** — §20.8.6's `counter` decision: shape to ratify (a seller-authored counter-offer row? a new offer table state?) before native resale activation.
- **`VOID_PATH_LOCK_LADDER`** — 085's `refund_primary_order` locks Payment (6) → Atom (5) → (inside the void) Inventory batch (2); 088's `cancel_event` locks Session (1) → Inventory (2) → Atom (5) → Payment (6) per the contract. The two can deadlock on a concurrent refund + cancellation of the same order (40P01 — one side aborts and retries; no money moves). Owed: an owner-signed body-only amendment to 085 (batch pre-lock) or a serialization rule in the ops runbook.
- **`RESALE_CHECKOUT_LATE_PAYMENT_DWELL`** — the door drain and `cancel_event` cancel a `reserved` listing over an `initiated` sale; a payment landing afterwards meets `mark_sale_paid_state`'s cancelled arm (alert + reversal) — but a listing cancelled BETWEEN mark and finalize leaves a `paid_pending_transfer` sale whose completer requires `reserved`; until `PAID_PENDING_DWELL_SLO` names the bound, that sale dwells with a `compensation_refund_missing` / manual reversal path only.

*(register maintained per PHASE_2_ARCHITECTURE_FREEZE.md §4)*
