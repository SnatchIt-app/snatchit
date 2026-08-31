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
