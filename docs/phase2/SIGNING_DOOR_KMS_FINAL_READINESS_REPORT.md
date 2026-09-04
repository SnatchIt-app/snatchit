============================================================
SNATCH IT — SIGNING / DOOR / KMS FINAL READINESS
============================================================

Package 103 + 104 · 2026-09-03 · DARK / UNAPPLIED / UNDEPLOYED

> **THIS IS NOT PRODUCTION AUTHORIZATION.** No migration was applied to production; no edge was
> deployed; no KMS key was created; no KMS Sign was called; no ceremony was run; no signing_key row was
> inserted; no production config/Stripe/secret was changed; no money moved; no ticket was minted; no
> flag was flipped. Production inspection was READ-ONLY. The `AwsKmsSigner` is authored but cannot reach
> AWS in this environment (no credentials/region/role; EdDSA request refused) and the provider defaults
> to `UnconfiguredKmsSigner`, which throws. Deletion post-event hold stays owner-unset. Tax stays
> unsolved and fail-closed.

REPOSITORY

BRANCH:      feature/venue-native-and-product-v2
ENTRY HEAD:  75159ce (package 102) — pushed to origin, CI green
FINAL HEAD:  85a9fc9 (packages 103+104) — PUSHED to origin (75159ce..85a9fc9); CI runs on the push
REMOTE:      origin = SnatchIt-app/snatchit; origin/feature/venue-native-and-product-v2 = 85a9fc9 (pushed)
PR:          #52 — OPEN, MERGEABLE
CI:          GREEN on 75159ce (CI: Typecheck/Lint/Unit, Migrations-apply-fresh-DB, Web build all SUCCESS;
             Migrations guard SUCCESS; Supabase Preview correctly SKIPPED — autodeploy off)
WORKTREE:    packages 103+104 authored (new migrations/rollbacks/tests/functions/docs); 093-102 byte-
             untouched (git diff 75159ce over 093-102 = empty)

PRODUCTION  (READ-ONLY, via Supabase MCP)

LEDGER:        107 rows, tip 20260902003623 — through 092 (076-092 LIVE-but-DARK; 093-104 unapplied)
SIGNING KEYS:  0
NATIVE EDGES:  NOT DEPLOYED — no credential-sign, primary-checkout, refund-execute, payout-execute,
               door-session, or door-manifest edge exists in production (11 legacy resale edges only)
MUTATIONS:     NONE

------------------------------------------------------------
ENTRY STATE
------------------------------------------------------------

102 PRESENT:         YES
PUSHED:              YES (origin/feature/venue-native-and-product-v2 = 75159ce; local 0/0)
CI GREEN:            YES
UNCONFIGURED SIGNER: YES — `UnconfiguredKmsSigner` was the deliberate hard stop this train addresses

------------------------------------------------------------
PFA-PT-6  (credential wire format)
------------------------------------------------------------

WIRE FORMAT:              JWS-compact `b64url(header).b64url(payload).b64url(sig)`; header
                         `{alg,kid,typ:"SNATCHIT-TICKET-CRED-V1"}`; payload `{atom,exp,iat,sess,ver}`;
                         canonical (sorted keys, no whitespace), no float/locale/display/PII/embedded-key.
ADVERSARIAL RESULT:      One P0 found AND FIXED — `verifyToken` did not compare `header.typ` to `DOMAIN`,
                         so the claimed domain separation held only against forgery, not against replay
                         of a genuinely-signed different-`typ` token whose payload shape-matched. Now
                         `wrong_typ` is refused FIRST, before alg-shape and any key lookup, in BOTH
                         `credential.ts` and the offline core; a replay-direction test proves it. Every
                         other §31 crypto attack verified safe (alg-pin order, no-oracle, tamper
                         detection, base64 leniency harmless, request-body isolation, cross-protocol
                         forgery defended, DER/raw sub-cases).
READY FOR OWNER SIGNATURE: YES
OPEN ISSUE:              None blocking. Owner signature pending; it is a DEPLOY precondition, not an
                         authoring/testing one.

------------------------------------------------------------
PFA-PT-8  (algorithm pinning)
------------------------------------------------------------

ALGORITHM AUTHORITY: the TRUSTED key's own algorithm, resolved by `kid` — NOT the token header.
SCHEMA:              migration 103 adds `kernel.signing_key.algorithm` (`EdDSA|ES256`, NOT NULL default
                     EdDSA, CHECK-constrained, IMMUTABLE via the re-created guard, granted to
                     authenticated as public verification metadata — never a private field).
TOKEN ALG:           informational/consistency only.
TRUSTED ALG:         `M1[kid].algorithm` / `get_ticket_signing_context.algorithm` (now real, not null).
MISMATCH:            refused `alg_mismatch` BEFORE the signature check — no fallback, no "try EdDSA then
                     ES256", no `none`, no key-type/symmetric confusion. Both the online verifier and the
                     offline core also whitelist the algorithm on both sides (adversarial P1 fix).
READY FOR OWNER SIGNATURE: YES

------------------------------------------------------------
KMS PROVIDER
------------------------------------------------------------

PROVIDER DETERMINED:     REFERENCE = AWS KMS (evidenced); FINAL = owner/ops decision (open).
PROVIDER:                AWS KMS.
WHY:                     env is AWS-shaped (`KMS_SIGNER_ROLE_ARN`), Supabase runs on AWS, and the ceremony
                         sanctions only AWS KMS / GCP KMS / CloudHSM (D1). AWS KMS offers NO Ed25519, so
                         its algorithm is ES256 (ECDSA_SHA_256) — a consequential pairing surfaced, not
                         buried: GCP would allow EdDSA. The provider abstraction (`KmsSigner`) keeps a
                         GCP/CloudHSM adapter addable; the credential AUTHORITY (which key, which bytes,
                         which algorithm) is fixed regardless of transport.
ADAPTER IMPLEMENTED:     YES (DARK) — `AwsKmsSigner` (SigV4-over-fetch, ES256-only, `MessageType:'RAW'`),
                         `UnconfiguredKmsSigner` default, pure `kms-taxonomy.ts` (error taxonomy, response
                         validation, DER glue). `KMS_PROVIDER` unset ⇒ Unconfigured (throws).
PRIVATE KEY LEAVES KMS:  NO — only `kms_handle_ref` (an ARN) crosses the process; `kms:Sign` only.
ARBITRARY SIGNING:       NO — body carries only `ticket_atom_id`; signed bytes come entirely from the
                         DB-derived context; key handle/algorithm come from the atom's PINNED key; no
                         request path into signed bytes or key selection.

------------------------------------------------------------
SIGN AFTER VERIFY
------------------------------------------------------------

KMS RESULT VERIFIED LOCALLY: YES — `index.ts` re-verifies every KMS signature against the DB
                             `public_key`/`algorithm` over the EXACT signed bytes BEFORE returning a
                             credential.
WRONG KEY:                   caught → `signing_unhealthy` 500, Sentry exception, no retry.
WRONG ALG:                   caught (same).
WRONG ENCODING:              caught (DER/raw drift fails local verify).
SECURITY FAILURE:            fail-closed, never a credential returned; also defends the (now-unconditional)
                             `validateAwsSignResponse` KeyId/algorithm check.

------------------------------------------------------------
M1  (cryptographic verification)
------------------------------------------------------------

IMPLEMENTED:   YES — `credential-sign/credential.ts` `verifyToken` (pure, DI'd verify primitive).
TOKEN PARSING: strict — exactly 3 segments, strict base64url, strict JSON, `MAX_TOKEN_LENGTH=8192` cap.
DOMAIN:        `typ === DOMAIN` enforced first (P0 fix).
KID:           resolved against a TRUSTED keyring only — never a key inside the token.
ALG PINNING:   `header.alg === trusted.algorithm` or refuse, with a `{EdDSA,ES256}` whitelist.
SIGNATURE:     verified over the token's OWN literal segment bytes (canonicalization-confusion-proof).
EXP:           `exp <= now` → expired. (Version/session are M2's, not collapsed here.)
TRUST ROOT:    the M1 key manifest = a projection of `kernel.signing_key`'s granted columns (now incl.
               `algorithm`); `kms_handle_ref` never exposed to the verifier.

------------------------------------------------------------
M2  (live admissibility / currency)
------------------------------------------------------------

IMPLEMENTED:    YES — two layers. OFFLINE core: `_shared/offline-verify.ts` implements OFFLINE-VERIFY-v1
                (§5.4.3) exactly: step 0 domain+alg → 1 M1 key → 2 signature → 3 session → 3a exp±skew →
                manifest-authority gate → 3b(i–v) → 3c signing-key match → 4 first-in-wins; applied-set
                (base ⊕ deltas) reducer; pure/no-mutation. ONLINE: `venue.validate_ticket_online` (C37
                live read) + `venue.record_scan` atomic admit; the door manifest ledger
                (`open/get/close_door_manifest`, base/entry/delta) is the offline M2 source.
VERSION:        3b.iii `credential_version` currency (offline core + DB validate_ticket_online).
TERMINAL STATE: 3b.iv `ticket_state='active'` (voided/scanned/expired refused).
REFUND HOLD:    3b.v `resale_state='none'` — refund_hold refused.
DISPUTE HOLD:   3b.v — dispute_hold refused.
RESALE:         3b.v — listed/locked (incl. paid_pending_transfer) refused.
SESSION:        3 session binding (offline) + `mark_ticket_scanned` wrong_session (online).
CANCELLATION:   migration 104 — `record_scan` refuses a terminal (cancelled/completed) session
                (online). Offline residual documented (bounded by manifest not_after; see OFFLINE).
SCAN:           4 first-in-wins (offline local set; online partial-unique `scan_admitted_in_uq`).

M1 PASS + M2 FAIL = AUTHENTIC BUT NOT ADMISSIBLE — the split is real in code (verifyToken never reads
session/version; offlineVerify/validate_ticket_online own currency).

------------------------------------------------------------
OLD OWNER SCREENSHOT
------------------------------------------------------------

V1 BEFORE TRANSFER: token minted at credential_version=1 (valid signature).
TRANSFER:           `kernel.transfer_ticket_ownership` bumps credential_version and sets resale_state='none'.
VERSION BUMP:       +1 (proven DB-side, test 169 B-series; validate_ticket_online surfaces the new value).
OLD TOKEN M1:       PASS — it was authentically signed (proven independently in offline-verify test).
OLD TOKEN M2:       FAIL — `stale_version` (offline core) / stale vs C37 live read (online). The old QR is
                    refused though its signature is valid.
NEW TOKEN:          the new owner fetches a credential at version 2 → M1 PASS + M2 PASS.
NOTE:               the old owner cannot even MINT a stale credential — `get_ticket_signing_context` as
                    the old owner returns `not_owner` (169 B6). Door P0-2 (record_scan takes no version)
                    is BY DESIGN — the frozen contract (§7.5/§1223) places version-currency at C37/the
                    verifier; a rogue-STAFF scanner bypassing C37 is a trust-boundary residual, not a
                    credential defect (PFA-PT-9 item 3 offers an optional DB backstop).

------------------------------------------------------------
OFFLINE
------------------------------------------------------------

SUPPORTED:         YES (M1 fully; M2 with bounded staleness — the frozen model).
M1:                fully current offline — the key manifest is a static projection; no network needed.
M2:                bounded-stale offline — the device evaluates the APPLIED set (base ⊕ downloaded
                   deltas); currency is only as fresh as the last sync.
MANIFEST:          `venue.door_manifest`/`_entry`/`_delta`; opened by `open_door_manifest`; freshness
                   bounded by `not_after = now + door.manifest_ttl_interval` (seeded "12 hours").
FRESHNESS:         a device MUST refuse when it has no M2, an M2 past not_after, or an M2 for another
                   session (proven in offline-verify tests).
DOUBLE-SCAN RISK:  ONLINE: none — `scan_admitted_in_uq` + `record_scan`'s unique_violation makes admit
                   atomic first-in-wins (169 D). OFFLINE across two devices: an inherent residual — each
                   device admits locally; the ledger still records exactly one `admitted` row, so no
                   double-spend is PERSISTED, but two doors can physically admit before reconcile.
BOUNDED HOW:       by manifest not_after (12h) + `reconcile_offline_scans` folding every offline scan
                   through `record_scan` (the unique index rejects the second admit).
OPEN RISK:         (1) §5.6 revocation force-close is UNIMPLEMENTED — `kernel.revoke_signing_key` is
                   parked fail-closed (PFA-18A); revoking a key does not force-close open episodes, so
                   until it lands the Wallet 12h session-bound profile is not safe to enable (P1-1). (2)
                   A terminal (cancelled/completed) session's PRE-DOWNLOADED offline M2 is not reached by
                   migration 104's online gate — bounded by not_after, couples to (1) (PFA-PT-9). (3)
                   `reconcile_offline_scans` ignores its documented ordering and discards per-item
                   outcomes — data invariant holds, ordering-credit + observability drift (P2-1). (4)
                   break-glass `admin_action` transfer while an episode is open leaves the M2 stale until
                   not_after (spec-acknowledged §5.5 residual; P1-2, document in the break-glass runbook).

------------------------------------------------------------
ROTATION
------------------------------------------------------------

K1:               active, pins T1 (per_event).
K2:               becomes active (K1 → rotating) in one txn; pins T2.
OLD TICKET:       T1 verifies under trusted K1 public material; T1.signing_key_id stays K1 forever (never
                  re-pinned) — proven DB-side (169 C) and at the offline core (in-window old key admits).
NEW TICKET:       T2 verifies under K2; never uses K1.
HISTORICAL VERIFY: an in-window rotating/old key still verifies its own atoms; unknown key fails.
SCOPED KEY:       per_event > per_venue > global precedence honored; a rogue per_event key shadowing
                  global is the ratified G3 concern (empirically reproduced, not new).
FINGERPRINT:      the 099 monitor (`check_signing_key_invariants`) compares each active key's fingerprint
                  to `signing.expected_key_fingerprint`, now dual-controlled (102 P3). alg/fingerprint
                  mismatch → refuse (offline core + monitor).

------------------------------------------------------------
KEY LIFECYCLE
------------------------------------------------------------

ACTIVE FOR SIGN:     status='active', in-window — `get_ticket_signing_context` signs new credentials only
                     under the atom's PINNED active key; a revoked pinned key → `signing_key_unavailable`
                     (169 C).
TRUSTED FOR VERIFY:  the M1 manifest — an old/rotating/revoked-but-in-window key's public material stays
                     verifiable for atoms pinned to it; verification trust lives in the manifest, NOT the
                     signer path. Do not delete historical public material prematurely.
ROTATED:             active → rotating → (active|revoked); forward-only, immutable identity/algorithm.
EXPIRED:             not_after passes → out of window → stops signing; still parseable by verifiers within
                     their cached window.
MODEL SUFFICIENT:    YES for this train (active/rotating/revoked + window + pin). The one gap is §5.6
                     force-close on revocation (P1-1) — a lifecycle ACTION, not a state — needed before
                     the Wallet 12h profile.

------------------------------------------------------------
FIRST IRREVERSIBLE POINT
------------------------------------------------------------

OLD RULING:        G3 — "the FIRST issue_ticket_atoms call = point of no return."
CURRENT FINDING:   G3 STANDS. Traced: `issue_ticket_atoms` mints an IMMUTABLE atom and PINS
                   `signing_key_id`/`credential_version=0`; the pin is immutable (no re-pin verb). The
                   credential is STATELESS and re-derivable, so "first returned signed credential" (B)
                   creates NO persistent state and is NOT a stronger line than (A). Delivering a
                   credential is downstream and reversible-in-effect (a version bump or void supersedes
                   it). The structural point of no return is (A): the first atom pinned to a PRODUCTION
                   signing key — that key must then remain trusted-for-verify as long as any live atom
                   pins it. (Money-wise the first PaymentIntent is the earlier irreversible event, but the
                   SIGNING/ticketing commitment is the atom-pin.)
AMENDMENT REQUIRED: NO.

------------------------------------------------------------
KMS CEREMONY
------------------------------------------------------------

EXECUTED:                        NO
PREFLIGHT COMPLETE:              YES (engineering items) — see PRODUCTION_SIGNING_KMS_CEREMONY.md §18.4:
                                 adapter complete + tests green, PFA-PT-6/8 authored, trusted-key schema
                                 (103) + M1 + M2 + rotation + sign-after-verify + dual-control + monitor
                                 all in place, hashes pinned, CI green, production observed unchanged.
ENGINEERING READY:               YES
OWNER AUTHORIZATION STILL REQUIRED: YES — plus PFA-PT-6/8 signatures and the final provider/algorithm
                                 (D1/D2) decision. The ceremony is a separate owner-authorized operation.

------------------------------------------------------------
A8a′
------------------------------------------------------------

NON-REGRESSION:  PASS (test 168, unchanged; full suite baseline).
PUBLISH GATES:   the four ratified SALEABLE gates — org_not_saleable / connect_not_ready /
                 signing_not_ready / fee_policy_unset — on the on_sale transition.
CHECKOUT RECHECK: unchanged (`create_primary_checkout` re-evaluates dynamic state; not touched).
TAX ADDED:       NO.

------------------------------------------------------------
TAX
------------------------------------------------------------

STATUS:              unsolved, fail-closed (backend computes no tax; client refuses to quote).
ACTIVATION BLOCKER:  YES.
OWNER/LEGAL DECISION: PFA-PT-7 OPEN — locus (publish-time / checkout-time / status quo) and any
                     rate/model remain owner+counsel. Nothing invented or assumed here.

------------------------------------------------------------
MONEY NON-REGRESSION
------------------------------------------------------------

G4:              PASS (test 166 — venue obligation excludes held commission; canonical 9000 case).
G5:              PASS (test 167 — cross-venue recovery refusal).
CROSS-VENUE:     refused (venue-scoped recovery; 101 untouched).
REFUND:          engineering-ready, DARK, undeployed — unchanged.
PAYOUT:          engineering-ready, DARK, undeployed — unchanged.
PROMOTER PAYOUT: DARK, out of scope.
(103/104 touch nothing in the money path — `algorithm` is signing-only; `record_scan` is door-only.)

------------------------------------------------------------
MIGRATIONS
------------------------------------------------------------

PREVIOUS TIP:          102
NEW TIP:               104
FILES:                 103_signing_key_algorithm_pin.sql (+rollback), 104_scan_session_status_gate.sql
                       (+rollback)
HASHES:                103 = 94d8b9a57001d612f3f1db9b5006a77d
                       104 = 2d94ac4ff5f2ad83f65af8856ad8b70b
CENSUS DELTA:          NONE — 103 re-creates two functions (get_ticket_signing_context, guard_signing_key_
                       immutable) + adds one column to kernel.signing_key; 104 re-creates one function
                       (record_scan). No new function, no public object. Kernel fn count stays 147,
                       Gate-2 stays 27/70/37/26. No pgTAP census assertion moved (verified).
EXISTING ROW MUTATION: NONE.

------------------------------------------------------------
SECURITY
------------------------------------------------------------

P0:   0 OPEN. Two P0s FOUND + FIXED this train: (a) crypto `typ` not enforced → `wrong_typ` now refused
      first (credential.ts + offline core); (b) door session-status gate missing → migration 104
      (record_scan refuses terminal sessions; test 170). A third P0-rated finding (record_scan takes no
      credential_version) is BY DESIGN per the frozen contract (currency at C37/verifier) — documented,
      not a live defect.
P1:   1 OPEN — §5.6 revocation force-close unimplemented (`kernel.revoke_signing_key` parked, PFA-18A):
      blocks enabling the Wallet 12h session-bound profile specifically; native scanning is dark so no
      live exposure. One P1 FIXED: offline alg-pin now whitelists the algorithm. One P1 (break-glass
      admin_action manifest residual) is a documented spec-acknowledged residual.
P2:   FIXED — kms KeyId/algorithm absent-field check made unconditional; token size cap; DER
      minimal-length. OPEN (tracked, mitigated) — reconcile_offline_scans ordering/outcome drift;
      `signing_key.algorithm` default not correlated to public_key format (unreachable today: provision/
      rotate parked; sign-after-verify + ceremony discipline are the live nets; a format CHECK is
      deferred to when the ceremony insert mechanism un-parks, as it would break the fake-key fixtures).

ARBITRARY SIGN:        NO (body = ticket_atom_id only; signed bytes from DB context).
KEY SUBSTITUTION:      prevented (kid → trusted keyring; sign-after-verify; immutable pinned key).
ALG CONFUSION:         prevented (pin from trusted key + whitelist, before signature; alg immutable).
OLD OWNER:             defended (verifier currency; version bump; not_owner on re-mint).
DOUBLE SCAN:           online prevented (atomic unique index); offline bounded (documented residual).
PRIVILEGE ESCALATION:  none found — signing_key mutation surface is zero-grant + parked lifecycle +
                       immutability guard; kms_handle_ref owner-gated; dual-control on trust-root config.

------------------------------------------------------------
ADVERSARIAL
------------------------------------------------------------

CLAIMS OVERTURNED: (1) "domain separation is enforced by code" — it was not (typ unchecked) → FIXED.
                   (2) the 169 old-owner section "proves the door rejects a stale screenshot" — it proves
                   the currency SOURCE (version bump + C37 surfacing); the door REJECTION is proven at the
                   verifier (offline core `stale_version`) — clarified, both layers now explicit.
DEFECTS FOUND:     2 P0 (crypto typ; door session gate) + 1 by-design P0-rated (record_scan version) + 2
                   P1 (offline alg-whitelist FIXED; §5.6 force-close OPEN) + 1 documented P1 residual +
                   ~5 P2.
DEFECTS FIXED:     crypto typ (P0), door session gate (P0), offline alg-whitelist (P1), kms absent-field
                   (P2), token size cap (P2), DER minimality (P2).
OPEN:              §5.6 revocation force-close (P1, Wallet-12h blocker); record_scan DB version backstop
                   (by-design, optional PFA-PT-9 item); reconcile ordering (P2); algorithm/key-format
                   CHECK (P2, mitigated); break-glass manifest residual (P1, documented).

------------------------------------------------------------
TESTING
------------------------------------------------------------

FRESH DB:    PASS — fresh replay 000→104, Gate-2 27/70/37/26 (== CI baseline).
PGTAP:       PASS — TOTAL plan=3638 ok=3634 not_ok=4; RESULT "matches the expected local baseline" (the 4
             are the documented local-only deltas: 060_payments_money ×2, 132_replay_parity ×2). 169
             PASS (34), 170 PASS (6), 166/167/168 PASS.
VITEST:      PASS — 14 files, 609 tests (offline-verify 38, credential-sign 26, credential-sign-kms
             ~49, + baseline).
TYPECHECK:   PASS — `npm run typecheck` exit 0.
LINT:        PASS — 0 errors (45 baseline warnings).
WEB:         shared TS contract compiles (typecheck covers the tests that import the functions); web
             build was green in CI on 75159ce; the new commit's web build runs on push.
MOBILE:      no mobile-facing contract changed by 103/104 (edges/cores are backend); handoff updated.
ASSEMBLER:   PASS — G-4 (093 byte-identical to its slices).
GATE-2:      27/70/37/26 (unchanged).
KMS:         adapter unit tests green (DER↔raw, alg map, taxonomy, sign-after-verify, fail-closed).
M1:          verifyToken tests (parse/domain/kid/alg-pin/signature/exp) green.
M2:          offline-verify OFFLINE-VERIFY-v1 tests green (all conjuncts, real Ed25519).
OFFLINE:     manifest freshness / applied-set / two-device residual tests green.
ROTATION:    169 C + offline rotation tests green.
CONCURRENCY: 169 D (first-in-wins unique index) green.
MONEY:       166/167 green.
CI:          GREEN on entry (75159ce); the new commit's CI runs on push.

------------------------------------------------------------
ACTIVATION MATRIX  (see PRIMARY_TICKETING_ACTIVATION_MATRIX.md — package 103 re-derivation)
------------------------------------------------------------

EVENT DRAFT:          code ✓ · ratified ✓ · migrated ✓(dark) · NOT ACTIVATED
EVENT PUBLISH (A8a′): code ✓ · ratified ✓ · NOT migrated (102-103) · NOT ACTIVATED
PRIMARY SALE:         code ✓ · ratified ✓ · NOT migrated (093) · edge NOT deployed · NOT ACTIVATED
PAYMENT CONFIRMATION: code ✓ · NOT migrated · edge NOT deployed (native) · NOT ACTIVATED
TICKET ISSUANCE:      code ✓ · migrated ✓(dark, 083) · KMS NOT configured (0 keys) · NOT ACTIVATED
CREDENTIAL SIGN:      code ✓ (102/103) · PFA-PT-6/8 PENDING · NOT migrated · edge NOT deployed · KMS not
                      configured · NOT ACTIVATED
DOOR VERIFY:          M1/M2 cores ✓ · door RPCs migrated ✓(086 dark) · door-session/manifest edges NOT
                      built · scanner SDK NOT built · NOT ACTIVATED
REFUND:               code ✓ · migrated ✓(dark) · edge NOT deployed · NOT ACTIVATED
SETTLEMENT:           code ✓ · migrated ✓(dark) · NOT ACTIVATED
VENUE PAYOUT:         code ✓ · migrated ✓(dark) · edge NOT deployed · NOT ACTIVATED
PROMOTER PAYOUT:      DARK / out of scope · NOT ACTIVATED

------------------------------------------------------------
OWNER DECISIONS REMAINING
------------------------------------------------------------

PFA-PT-6:      sign the credential wire format (or select another).
PFA-PT-8:      sign the algorithm-pin (schema shipped in 103).
KMS PROVIDER:  D1/D2 — AWS KMS (⇒ ES256) vs GCP Cloud KMS (allows EdDSA) vs CloudHSM; and the algorithm.
TAX:           PFA-PT-7 — enforcement locus + any rate/model (owner + counsel).
DELETION HOLD: deletion.post_event_hold_hours stays owner-unset (untouched).
G1:            (prior) ratified — no new item.
G2:            (prior) ratified — no new item.
G3:            first-irreversible-point — CONFIRMED STANDS this train (no amendment).
G4:            (prior) ratified — non-regression PASS.
G5:            (prior) ratified — non-regression PASS.
GATE-M:        (prior) — no new item.
OTHER:         PFA-PT-9 — ratify the terminal-status reading of door admit-gate (1) (migration 104), and
               decide (a) the offline terminal-session residual handling and (b) whether a DB-side
               credential_version backstop in record_scan is wanted beyond C37. §5.6 revocation
               force-close (PFA-18A) must land before the Wallet 12h session-bound profile.

------------------------------------------------------------
FIRST SAFE SALE  (exact remaining steps — DO NOT EXECUTE)
------------------------------------------------------------

1.  Owner signs PFA-PT-6 (wire format), PFA-PT-8 (alg pin), PFA-PT-9 (door admit reading).
2.  Owner/counsel resolve TAX (PFA-PT-7) — or affirm the compute-none posture as intended.
3.  Owner sets deletion.post_event_hold_hours (still unset; needed for the deletion path, not sale).
4.  Owner selects KMS provider + algorithm (D1/D2); if not AWS, author the GCP/CloudHSM adapter to the
    `KmsSigner` contract and re-run adapter tests.
5.  Production observation closeout re-confirmed (ledger 107, 0 keys, native edges undeployed, CI green).
6.  Apply migrations 093→104 to production (forward-only; hashes pinned; AUTODEPLOY-VERIFIED-OFF).
7.  Run the KMS ceremony (two-person): create the asymmetric key, insert ONE `kernel.signing_key` row
    (public_key SPKI, kms_handle_ref pinned to a version, algorithm matching the key) — a global
    bootstrap key at minimum.
8.  Verify the trusted key: fingerprint pinned (dual-control), monitor sees status=ok.
9.  Deploy the DARK edges (credential-sign; primary-checkout; and the door-session/door-manifest edges
    once their parked KDF is ratified and built) with `KMS_PROVIDER` + role env set.
10. Arm the signing monitor (`signing.monitor_enabled`).
11. Onboard a real org: Connect bound + transfers active; set fee.buyer_service_bps.
12. Expose the kernel/venue RPC surface to PostgREST as the activation plan specifies.
13. Publish an event to on_sale (A8a′'s four gates now satisfiable).
14. First quote → first PaymentIntent → first `issue_ticket_atoms` (THE irreversible point, G3) → first
    `credential-sign` (M1) → first door M1 verify → first C37/M2 check → first controlled scan.
15. Prove a refund end-to-end before widening.

------------------------------------------------------------
FIRST SAFE PAYOUT  (separate; exact remaining steps — DO NOT EXECUTE)
------------------------------------------------------------

1.  First safe sale proven (above) and settled.
2.  Deploy the `payout-execute` edge (DARK today) with its risk gates.
3.  Confirm settlement close is correct (venue obligation excludes held commission — G4) for the real
    event.
4.  Enable the payout executor flag (`payout.executor_enabled`) under dual control.
5.  Request → (dual-control park if over threshold) → execute ONE venue payout; verify the transfer and
    the ledger.
6.  Confirm reversal/obligation-recovery path (G5 venue-scoped) on a test reversal before widening.
(Promoter payout stays COMPLETELY out of scope and DARK.)

------------------------------------------------------------
FINAL STATUS
------------------------------------------------------------

SIGNING ARCHITECTURE COMPLETE:                        YES
PRODUCTION KMS ADAPTER COMPLETE:                      YES (DARK; AWS reference; provider choice open)
M1 COMPLETE:                                          YES
M2 COMPLETE:                                          YES (core + online DB authority; offline residuals documented)
OLD-OWNER SCREENSHOT SAFE:                            YES
ROTATION SAFE:                                        YES
OFFLINE CONTRACT SAFE:                                YES WITH BOUNDED, DOCUMENTED RESIDUALS (M1 fully; M2
                                                     currency bounded by manifest freshness; §5.6
                                                     force-close is the one P1 blocker, and only for the
                                                     Wallet 12h profile)
P0 OPEN:                                              NO
P1 OPEN:                                              YES (§5.6 revocation force-close — Wallet-12h profile only)
ENGINEERING READY FOR KMS CEREMONY:                   YES
KMS CEREMONY SHOULD RUN NOW:                          NO (owner authorization + PFA-PT-6/8 signatures +
                                                     provider decision + migrate-to-prod required first)
ENGINEERING READY FOR DARK PRODUCTION DEPLOYMENT:     YES (the code; deployment gated on owner/PFA/migrate/ceremony)
ENGINEERING READY FOR FIRST CONTROLLED SALE AFTER OWNER/PRODUCTION GATES: YES
PRIMARY SALE ACTIVATION AUTHORIZED:                   NO
VENUE PAYOUT ACTIVATION AUTHORIZED:                   NO
PROMOTER PAYOUT ACTIVATION AUTHORIZED:                NO

RECOMMENDED NEXT CLAUDE A ACTION:  Land the §5.6 revocation force-close for `kernel.revoke_signing_key`
(force-close open episodes + `not_after:=now()` + `DoorManifestInvalidated` + audit) together with the
door-session/door-manifest edges' parked slow-KDF (PFA-26) — the two remaining engineering blockers
between "verifier cores built" and "door plane fully activatable" — then present PFA-PT-6/7/8/9 and the
KMS provider/algorithm decision to the owner as the gate to the ceremony.

============================================================

STOP. DO NOT DEPLOY. DO NOT APPLY MIGRATIONS. DO NOT RUN KMS. DO NOT CONFIGURE PRODUCTION. DO NOT MOVE
MONEY. DO NOT ACTIVATE.

============================================================
