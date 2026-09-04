============================================================
PFA-18C REMEDIATION + FINAL RATIFICATION READINESS
============================================================

2026-09-04 · GOVERNANCE / RUNBOOK ONLY · NO KMS · NO PRODUCTION MUTATION · NO MIGRATION

AUTHORIZATION

Authorized: fix M4/P1-ALGO in the ceremony artifact/runbook; resolve M6 wording; re-evaluate M1 for a
one-operator company; preserve/tighten M2/M3; re-run adversarial review; produce the final PFA-18C
ratification package; update governance docs. NOT authorized: KMS key creation, production DB mutation,
signing_key insert, config changes, edge deploy, activation, commerce, migration 110, secret rotation.

SOURCE OF TRUTH REVIEW

Read: PFA_SINGLE_FOUNDER_KMS_BOOTSTRAP.md, POST_FREEZE_AMENDMENTS.md, PRODUCTION_SIGNING_KMS_CEREMONY.md
(incl. §4 create, §5.2/5.3 fingerprint+binding, §6.1 artifact, §6.2 invocation, §7 post-verify, §18
package-103 note), the two prior ceremony/migration execution records, the Gate-B clearance + preflight.
Verified every load-bearing claim against real code: 083 (signing_key DDL; guard_signing_key_immutable
is BEFORE UPDATE only; unique active-global partial index), 103 (algorithm NOT NULL DEFAULT 'EdDSA';
get_ticket_signing_context returns the key's algorithm), 099 (check_signing_key_invariants; monitor
gated by signing.monitor_enabled; fingerprint recompute for key_id …b0 only), 102 (resolver
most-specific-first; issuance-flag gate), credential-sign/kms.ts + kms-taxonomy.ts (AwsKmsSigner ES256,
DER↔raw, sign-after-verify, fail-closed). An independent adversarial reviewer subagent ran round 2.

PRODUCTION READ-ONLY BASELINE (2026-09-04)

ledger 124 · substrate 109 · signing keys 0 · signing.expected_key_fingerprint null ·
signing.monitor_enabled false · native issuance false · native scanning false · native edges NOT
DEPLOYED · tickets 0 · door_pin 0 · door_session 0 · scan 0 · money 0 · UNCHANGED (no mutation). Live
schema confirms kernel.signing_key.algorithm column default = 'EdDSA'::text.

------------------------------------------------------------
M4 / P1-ALGO
------------------------------------------------------------

ORIGINAL DEFECT:  CONFIRMED (verified from source AND demonstrated off-production).
SOURCE EVIDENCE:  migration 103:56-57 — `algorithm text not null default 'EdDSA' check (algorithm in
                  ('EdDSA','ES256'))`; the §6.1 bootstrap artifact's INSERT column list omitted
                  `algorithm`; guard_signing_key_immutable (103) now includes `algorithm` → immutable.
                  Live prod schema default = 'EdDSA'::text. Consequence: an AWS ES256 key inserted by the
                  uncorrected artifact lands algorithm='EdDSA' → get_ticket_signing_context returns
                  'EdDSA' → the signer's ES256-only path throws / sign-after-verify fails → NO credential
                  signable, IMMUTABLE — a silent permanent brick (fails CLOSED: no bad ticket ships).
CORRECTION:       the §6.1 CEREMONY ARTIFACT now (a) takes an explicit `-v ALGORITHM="ES256"`, (b) carries
                  a new PRE-FLIGHT 2b that aborts if ALGORITHM is empty, not in (EdDSA|ES256), or (for
                  this AWS ceremony) ≠ ES256, (c) lists `algorithm` in the INSERT from the explicit var,
                  and (d) asserts it in the POST-CHECK. §6.2 invocation adds `-v ALGORITHM="ES256"` and a
                  fourth required NOTICE. §6.1 is now consistent with §18.1 ("algorithm MUST be 'ES256'
                  for an AWS key"); the prior §6.1↔§18.1 contradiction is RESOLVED. This is a runbook /
                  ceremony-artifact change, NOT a production migration.
FILES CHANGED:    docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md (§6.1 artifact + §6.2 invocation/output).
TESTS (off-production, rehearsal DB at tip 109; NO production, NO KMS):
                  • control: the OLD (no-algorithm) insert lands `EdDSA` — the brick reproduced.
                  • corrected artifact: N1 empty ALGORITHM → ABORT; N2 ALGORITHM=EdDSA → ABORT (AWS
                    requires ES256); N3 ALGORITHM=RSA → ABORT (unsanctioned); N4 fingerprint mismatch →
                    ABORT (PRE-FLIGHT 2); N5 empty handle → ABORT (PRE-FLIGHT 3); rows after all
                    negatives = 0. Happy ALGORITHM=ES256 → NOTICEs + COMMIT; row = 1 / algorithm=ES256 /
                    global / active / key_id …b0. Second run → ABORT (once-only). Signing suite still
                    green: pgTAP 169 (34/34), vitest kms (56/56).
RESULT:           M4 FIXED + off-production PROVEN. The EdDSA brick is closed for the §6.1 artifact path.
                  (Residual on OTHER insert paths → P1-ALGO-DEFAULT below.)

------------------------------------------------------------
M6
------------------------------------------------------------

FINAL CLASSIFICATION:        MANDATORY PRE-ISSUANCE HARDENING (unambiguous; not "optional").
REQUIRED BEFORE BOOTSTRAP:   NO.
REQUIRED BEFORE ISSUANCE:    YES.
RATIONALE:                   the round-2 reviewer VERIFIED that no dark path signs or resolves a scoped
                             shadow key into a credential: kernel.issue_ticket_atoms checks
                             feature.native_issuance_enabled BEFORE resolving any key (no mint while
                             dark → no atom pinned to a shadow); get_ticket_signing_context serves only
                             an atom's already-pinned key and never re-runs the resolver; the
                             most-specific-first resolver only gates quoting/publishing, never signs. So
                             a superuser-inserted per_event/per_venue shadow that outranks global is
                             INERT while issuance is dark. Deferring the BEFORE INSERT guard to
                             before-issuance is therefore safe. TIMING NOTE: M6 AND monitor-armed must
                             both precede the issuance flip; M6 should land WITH the bootstrap PR (not
                             rely on later operator diligence), since between bootstrap-commit and monitor
                             arming a shadow is insertable-and-invisible (harmless while dark).
FUTURE ENGINEERING REQUIREMENT (specified, NOT implemented — no migration 110):
                             invariant: "while PFA-18A provision/rotate remain parked, kernel.signing_key
                             may contain ONLY the sanctioned global trust-root lineage (key_id …b0,
                             scope='global'); reject any INSERT that is scoped (per_event/per_venue) or a
                             second key or, for the global bootstrap row, whose algorithm ≠ ES256." A
                             BEFORE INSERT trigger (the missing companion to guard_signing_key_immutable)
                             is the mechanism. Must be reviewed against all legitimate FUTURE lifecycle
                             paths (post-maturity two-person rotation/re-bootstrap) before it is written,
                             so it does not itself block a sanctioned future op.

------------------------------------------------------------
M1 PRACTICALITY REVIEW
------------------------------------------------------------

The KEY PROPERTY M1 must provide: the ACTIVE CEREMONY PRINCIPAL / SESSION cannot silently delete or
rewrite the ceremony audit evidence DURING the ceremony. This is distinct from ULTIMATE OWNER AUTHORITY:
the founder ultimately owns AWS root and cannot be made independent of themselves — no cloud policy
achieves that — but the ceremony SESSION can be tightly constrained even when the owner controls the
company. That distinction is the whole point.

MODEL A (separate audit account + org CloudTrail + Object-Lock + SCP): strongest. Catches: same-account
   compromise of the ceremony principal, AND founder-as-root stopping FUTURE logging (an SCP denies even
   the account's admins cloudtrail:Stop*/s3:Delete*). Defeated by: org-management-account compromise.
   Cost/burden: an extra AWS account + org setup — real but modest.
MODEL B (SAME account; dedicated trail + dedicated log bucket, Object-Lock COMPLIANCE + retention, a
   tightly-scoped ceremony principal): sufficient for the DARK bootstrap ONLY IF a concrete deny-set is
   TRUE (below), and even then leaves a founder-as-root "stop FUTURE logging / delete-after-retention"
   residual that Model A closes. As prose alone it is theater.
MODEL C (export ceremony evidence to an external trust domain, e.g. a signed governance commit in this
   repo + a copy on the second device): a useful ADJUNCT (immutable-ish, out-of-session), not a
   substitute for A/B — it records what the operator SHOWS, not what AWS actually did.
MODEL D (two humans): the original; not available (one operator).

SELECTED MODEL:  **Model B for the DARK bootstrap, HARD-CONDITIONED on the concrete deny-set + Object-Lock
                 compliance below and M2 read-back; PLUS Model A REQUIRED before T3 (first signed
                 credential / issuance enabled).** Model C evidence copy is required as an adjunct.
SECURITY PROPERTY: the ceremony session cannot erase/rewrite the CreateKey/GetPublicKey/Sign audit trail
                 during the ceremony.
WHY ACCEPTABLE:  the bootstrap is DARK, REVOCABLE, and pre-commerce; it signs nothing until edge deploy +
                 issuance flag (separately authorized), giving a long window in which a bad key is
                 detected (CloudTrail, second device, monitor) and revoked before harm. For that window,
                 "detectable, not preventable" is the honest and correct guarantee for a solo founder.
RESIDUAL:        same-account cannot prevent the founder-as-root from STOPPING FUTURE logging or deleting
                 objects after their Object-Lock retention elapses. ACCEPTED for the dark bootstrap;
                 CLOSED by Model A, which is REQUIRED before commerce (T3).
SETUP REQUIREMENTS — the Model-B deny-set that MUST be concretely written and READ BACK from the second
                 device (M2) before the ceremony (as prose it does not satisfy M1):
   • CloudTrail: a dedicated MULTI-REGION trail with log-file validation ON; the ceremony principal
     explicitly DENIED cloudtrail:StopLogging/DeleteTrail/UpdateTrail/PutEventSelectors/RemoveTags (and
     no cloudtrail:*). If an org trail, the ceremony account is NOT the org management account.
   • S3 log bucket: Object-Lock COMPLIANCE mode with an actual RETENTION PERIOD applied to objects (NOT
     merely "enabled", NOT legal-hold-only, NOT governance mode). Ceremony principal DENIED
     s3:DeleteObject/DeleteObjectVersion/PutBucketPolicy/PutLifecycleConfiguration/PutBucketVersioning/
     PutObjectRetention/PutObjectLegalHold/BypassGovernanceRetention/PutEncryptionConfiguration/
     PutReplicationConfiguration.
   • LOG-BUCKET ENCRYPTION (the sharpest same-account gap): use SSE-S3, OR if SSE-KMS, the CMK must be
     one the ceremony principal CANNOT administer — deny kms:ScheduleKeyDeletion/DisableKey/PutKeyPolicy
     on the log CMK. (Object-Lock protects the objects, not the key; deleting/disabling the log CMK
     erases evidence AROUND the lock.)
   • IAM SELF-ESCALATION fully denied on the ceremony principal: no iam:PutUserPolicy/PutRolePolicy/
     AttachRolePolicy/CreatePolicyVersion/CreateAccessKey, no sts:AssumeRole into any admin role, no
     iam:PassRole. (Any one of these makes every deny above moot — self-re-grant reopens the audit gap.)
   • ROOT + a break-glass/security authority are MFA-protected and are NOT the ceremony principal.

------------------------------------------------------------
M2
------------------------------------------------------------

SECOND DEVICE:  REQUIRED (unchanged, tightened). A different device/session, not part of the ceremony
                host, with its OWN read-only AWS IAM principal.
INDEPENDENCE REQUIREMENTS: it independently calls AWS GetPublicKey DIRECTLY (not a value passed from the
                ceremony host), derives the canonical SPKI + the D5 fingerprint, runs the §5.3 binding
                proof (challenge → KMS Sign via the ARN → verify against ITS OWN exported pubkey;
                altered-message FAILS, wrong-key FAILS), reads back the committed KMS key policy AND the
                Model-B deny-set (M1), and its fingerprint is the value fed to the in-DB PRE-FLIGHT 2. It
                must NOT share the ceremony host's shell, temp files, AWS session, or helper output.
IAM (minimum): kms:GetPublicKey on the key ARN; cloudtrail:LookupEvents + GetTrailStatus; s3:GetObject +
                GetBucketObjectLockConfiguration on the log bucket; iam:GetUserPolicy/GetRolePolicy/
                ListAttachedRolePolicies + kms:GetKeyPolicy (to read back the deny-set/key policy).
                NOTHING mutating. No kms:Sign (the binding proof's Sign is made BY the ceremony principal
                through the handle; the second device VERIFIES).

------------------------------------------------------------
M3
------------------------------------------------------------

DISTINCT RUNTIME ROLE:  REQUIRED (unchanged). The long-lived credential-sign runtime signer is a
                        DIFFERENT IAM role from the ceremony/CreateKey principal.
CEREMONY PRINCIPAL:     narrowly scoped to CreateKey/DescribeKey/GetPublicKey/PutKeyPolicy for the ONE
                        key + the §5.3 Sign; NO long-lived kms:Sign after the binding proof; root is NOT
                        used for ceremony operations.
RUNTIME PRINCIPAL:      kms:Sign (+ kms:GetPublicKey if the runtime needs it) on the EXACT key ARN only;
                        no kms:Decrypt, no kms:*, no other keys.
KEY POLICY:             grants kms:Sign to ONLY the runtime role (+ GetPublicKey to the M2 read-only
                        principal); enforced by BOTH the KMS key policy AND the runtime role's IAM policy;
                        read back from the second device (M2).
POST-CEREMONY PERMISSIONS: the ceremony principal retains NO kms:Sign on the production key.
                        RESIDUAL (P3-REGRANT): the founder owns IAM and can re-add kms:Sign at will — M3
                        makes retained/re-granted Sign DETECTABLE (CloudTrail PutKeyPolicy/PutUserPolicy
                        via M1), not PREVENTABLE. Honest single-environment residual; correctly disclosed.

------------------------------------------------------------
M5
------------------------------------------------------------

REQUIRED BEFORE ISSUANCE:  YES.
EXECUTION TIMING:          after the credential-sign edge is (dark) deployed and BEFORE any
                           feature.native_issuance_enabled flip: issue ONE credential through the deployed
                           edge for a throwaway atom and confirm sign-after-verify passes.
                           check_signing_key_invariants never calls KMS, so it cannot catch a wrong pair
                           or a surviving EdDSA row; this end-to-end test can. Separate, later, authorized.

------------------------------------------------------------
M6 ENGINEERING PLAN
------------------------------------------------------------

REQUIRED BEFORE ISSUANCE:  YES.   MIGRATION REQUIRED:  YES (a BEFORE INSERT scope/algorithm guard).
NO MIGRATION WRITTEN THIS SESSION. Invariant + review scope specified above (M6). It also mitigates
P1-ALGO-DEFAULT (reject a global row whose algorithm ≠ ES256).

------------------------------------------------------------
MATURITY TRIGGER
------------------------------------------------------------

FINAL RULE:  the single-founder bootstrap exception is CONSUMED ONCE and cannot be reused. Completing the
             bootstrap is valid forever; T3 (first production credential signed OR native issuance
             enabled) does NOT retroactively invalidate the already-completed bootstrap. After the FIRST
             of {T1 a second qualified technical operator appointed / T2 institutional funding with
             technical oversight / T3 as above}, ALL future signing-key lifecycle operations (rotation,
             replacement, post-revoke re-bootstrap) MUST use two-person control and FAIL CLOSED if no
             second qualified operator exists (no silent reuse of PFA-18C). GAP FOUND
             (P1-REBOOTSTRAP-FAILOPEN): today the ONLY post-revoke recovery path is a bare superuser
             INSERT (provision/rotate parked), which has neither two-person enforcement NOR fail-closed —
             so the trigger's guarantee does not bind the one path it most needs to. REQUIRED FORWARD
             WORK (not this session): a GATED post-revoke re-bootstrap artifact (PRE-FLIGHT: exactly one
             revoked global, zero active; sets algorithm='ES256' explicitly) classified TWO-PERSON-
             MANDATORY post-T3. Until it exists, post-T3 recovery has NO compliant mechanism — stated
             plainly so it is not discovered mid-incident.

------------------------------------------------------------
ADVERSARIAL REVIEW ROUND 2  (independent subagent + self-review; findings integrated)
------------------------------------------------------------

Note: the subagent read the runbook BEFORE this session's §6.1 fix landed, so its "M4 unwritten" is now
stale — M4 IS written + off-production-proven this session. Its genuinely-new findings stand and are
integrated below.

P0:  none NEW. The prior P0-AUDIT / P0-BIND are closed ONLY IF M1/M2/M3 are met as concrete, verified
     infrastructure (procedural, not demonstrable in-repo) → P0=0 is CONDITIONAL on execution-time proof.
P1 (all pre-bootstrap / pre-issuance; all fail CLOSED — issuance stays blocked):
     • P1-ALGO (M4): RESOLVED this session (artifact fixed + tested).
     • P1-ALGO-DEFAULT (NEW): the schema default 'EdDSA' bricks ANY non-artifact insert (post-revoke bare
       INSERT; future scoped inserts). MITIGATION: M6's guard rejects a global row whose algorithm≠ES256;
       any re-bootstrap/scoped artifact sets algorithm explicitly; a future migration could drop the
       column default (103's own comment concedes the default is "never a substitute for the ceremony
       stating the truth"). Documented; not fixed via migration this session.
     • P1-MODELB (NEW): Model B (same account) does NOT meet M1 unless the full deny-set + Object-Lock
       compliance + log-CMK control is concretely written and M2-read-back. RESOLVED IN GOVERNANCE by the
       M1 section above (deny-set enumerated + Model-A-before-T3); it becomes a hard EXECUTION
       precondition, verified from the second device.
     • P1-REBOOTSTRAP-FAILOPEN (NEW): post-T3 recovery fails open. RESOLVED IN GOVERNANCE (maturity
       section: gated two-person re-bootstrap artifact required; interim state disclosed). Not written.
P2:  M6 deferral CONFIRMED SAFE (no dark path signs a shadow); monitor-arming timing note (land M6 with
     the bootstrap PR); monitor watches only …b0's fingerprint (adequate for the single-bootstrap model).
P3:  P3-REGRANT (M3 residual, detectable-not-preventable — disclosed); P3-AI-DRIVES-PSQL (NEW): in the
     single-founder path there is no Person B, so the AI must NOT be allowed to drive the bootstrap psql
     or any AWS/DB mutation — C18 is strengthened: the FOUNDER types/runs every AWS and DB mutation; the
     AI coordinator reads back non-secret output ONLY. No accidental activation / two-active-global /
     private-key-exposure / fingerprint-drift regressions found.

BOOTSTRAP BLOCKERS (must be TRUE before the bootstrap runs): M4 applied (DONE); M1 Model-B deny-set +
Object-Lock compliance + log-CMK control CONCRETELY implemented and M2-read-back; M2 second device with
read-only IAM; M3 distinct runtime role + key policy; C18 founder-runs-mutations.
ISSUANCE BLOCKERS (must be TRUE before native issuance): M6 guard migration landed; M5 end-to-end sign
test; Model A audit account (before T3); the gated two-person post-revoke re-bootstrap artifact.

------------------------------------------------------------
RATIFICATION READINESS
------------------------------------------------------------

STATUS: READY FOR OWNER RATIFICATION **of the governance model**, conditioned on the execution
preconditions above. The model is sound and honestly framed ("detectable, not preventable"); M4 is fixed
and proven; M6/M5/Model-A/re-bootstrap are correctly sequenced as pre-issuance (not pre-bootstrap) items
that fail closed. It is NOT "ready to execute" until the BOOTSTRAP BLOCKERS are concretely met and
read-back-verified from the second device. Owner ratification remains PENDING (this prompt carries no
signature). PFA-18C is recorded as PROPOSED / READY FOR OWNER RATIFICATION, not owner-approved.

------------------------------------------------------------
EXACT OWNER SIGNATURE
------------------------------------------------------------

"PFA-18C APPROVED (YYYY-MM-DD). I authorize a single technically-qualified Snatch It founder/owner to
execute the INITIAL AWS KMS ES256 production trust-root bootstrap under PFA-18C.
 REQUIRED BEFORE THE (DARK) BOOTSTRAP: the M4-corrected §6.1 artifact that sets algorithm='ES256'
 explicitly; the M1 audit plane as Model B in a single account with the concrete deny-set (CloudTrail
 Stop/Delete/Update denied; S3 delete/policy/lifecycle/retention/legal-hold/bypass/encryption denied;
 Object-Lock compliance mode with a retention period; log-bucket encryption SSE-S3 or a CMK the ceremony
 principal cannot administer; all IAM self-escalation denied) READ BACK from the second device; the M2
 second clean device with its own read-only IAM principal performing the fingerprint derivation, the
 §5.3 binding proof, and the deny-set/key-policy read-back; the M3 distinct runtime IAM role with the
 key policy granting kms:Sign only to that role and the ceremony principal retaining no Sign; and C18
 (I, the founder, run every AWS and DB mutation myself — no AI or non-technical person executes them).
 REQUIRED AFTER THE BOOTSTRAP BUT BEFORE ANY NATIVE ISSUANCE: the M6 BEFORE INSERT scope/algorithm guard
 migration; the M5 end-to-end credential-sign test; a Model A separate audit account with an SCP; and a
 gated two-person post-revoke re-bootstrap artifact.
 I acknowledge this is a compensating-control model that is NOT equivalent to human separation of duties,
 whose honest guarantee is DETECTABLE, NOT PREVENTABLE, with a stated single-environment residual (and,
 for Model B, a same-account future-logging residual closed only by Model A). This exception applies ONLY
 to the initial bootstrap of exactly one global signing key and authorizes NO provision, rotation,
 replacement, product activation, ticket issuance, scanning, money movement, or payout. PFA-18A remains
 parked; PFA-18B revoke remains the abort path. The exception is consumed once; all future signing-key
 lifecycle operations return to two-person control (fail closed if no second qualified operator exists)
 on the PFA-18C maturity trigger (T1 second qualified technical operator / T2 institutional funding with
 technical oversight / T3 first production credential signed or issuance enabled, whichever first)."

------------------------------------------------------------
WHAT OWNER SIGNATURE AUTHORIZES
------------------------------------------------------------

Only the INITIAL dark, single-founder KMS trust-root bootstrap (one global ES256 signing_key row) under
all controls, executed interactively with the founder running every AWS/DB mutation. Nothing else.

------------------------------------------------------------
WHAT OWNER SIGNATURE DOES NOT AUTHORIZE
------------------------------------------------------------

Provision/rotate/replacement of keys; edge deployment; native issuance/scanning; fee/deletion/tax/config;
Connect; PaymentIntent/charge/transfer/refund/payout; ticket issuance; door PIN/session; scans; money
movement; primary-sale/venue-payout/promoter-payout activation; migration 110; secret rotation.

------------------------------------------------------------
NEXT OPERATION AFTER OWNER RATIFICATION
------------------------------------------------------------

The next operation is the SINGLE-FOUNDER DARK AWS KMS / ES256 TRUST-ROOT BOOTSTRAP under the ratified
PFA-18C — executed interactively with the founder running every AWS/DB command and the AI as
read-back coordinator only, ONLY after the BOOTSTRAP BLOCKERS are concretely met and second-device
verified. DO NOT execute it here.

------------------------------------------------------------
PRODUCTION MUTATION
------------------------------------------------------------

NONE. (Read-only baseline only; all artifact tests ran on a local rehearsal DB; no KMS; no migration; no
production write.)

------------------------------------------------------------
FINAL STATUS
------------------------------------------------------------

PFA-18C:                 PROPOSED / READY FOR OWNER RATIFICATION (model), CONDITIONED on execution preconditions
M4:                      FIXED + off-production PROVEN (runbook §6.1/§6.2; no migration)
M1:                      Model B for the dark bootstrap (concrete deny-set + Object-Lock compliance +
                         log-CMK control + M2 read-back) ; Model A REQUIRED before T3
M2:                      REQUIRED (second clean device, own read-only IAM, independent GetPublicKey +
                         binding proof + deny-set read-back)
M3:                      REQUIRED (distinct runtime role; key policy Sign-only-to-runtime; ceremony drops Sign)
M5:                      REQUIRED BEFORE ISSUANCE (end-to-end credential-sign test)
M6:                      MANDATORY PRE-ISSUANCE (BEFORE INSERT scope/algorithm guard; migration; not written)
P0 OPEN:                 0 (conditional on M1/M2/M3 concrete + verified at execution)
P1 BOOTSTRAP OPEN:       0 blocking that is not now specified as a hard pre-bootstrap/pre-issuance
                         precondition (M4 resolved; P1-ALGO-DEFAULT / P1-MODELB / P1-REBOOTSTRAP-FAILOPEN
                         resolved in governance, execution-gated, fail closed)
OWNER RATIFICATION:      PENDING (no signature in this prompt)
PRODUCTION:              UNCHANGED (ledger 124, 0 keys, dark)
NEXT:                    on ratification + met bootstrap blockers, a separate single-founder dark bootstrap session

============================================================

STOP. DO NOT EXECUTE KMS. DO NOT INSERT A SIGNING KEY. DO NOT CHANGE PRODUCTION CONFIG. DO NOT DEPLOY
EDGES. DO NOT ENABLE ISSUANCE/SCANNING. DO NOT SET FEES. DO NOT ONBOARD CONNECT. DO NOT CREATE A SALE.
DO NOT ISSUE A TICKET. DO NOT SCAN. DO NOT MOVE MONEY. DO NOT ACTIVATE PAYOUT.

============================================================
