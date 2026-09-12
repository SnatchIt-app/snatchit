============================================================
PFA-18C — SINGLE-FOUNDER INITIAL KMS BOOTSTRAP
============================================================

Governance amendment · 2026-09-04 · NO PRODUCTION MUTATION · GOVERNANCE ONLY

------------------------------------------------------------
STATUS
------------------------------------------------------------

READY FOR OWNER RATIFICATION **of the governance model**, HARD-CONDITIONED on the six mandatory additions
the adversarial review requires (M1–M6 below). EXECUTION of the bootstrap is separately gated on a
REQUIRED ceremony-artifact fix (the §6.1 `algorithm` defect, P1-ALGO) and is strengthened by a RECOMMENDED
engineering hardening (a `BEFORE INSERT` scope guard, P1-SHADOW) before issuance activation. Neither is
written in this session.

This is a COMPENSATING-CONTROL model, explicitly **NOT equivalent to human separation of duties**. The
honest guarantee it provides is **DETECTABLE, NOT PREVENTABLE**: with a non-exportable KMS private key
and an audit plane the operator cannot erase, a single-operator error or compromise is *detectable after
the fact* (and revocable while the trust root is still dark), but a fully-compromised single operator
environment cannot be *prevented* from establishing a trust root — only genuine human/environment
separation prevents that. If the owner cannot meet M1 (out-of-band audit), M2 (second clean device), or
M3 (distinct runtime IAM role), the amendment is **NOT acceptably safe → REJECTED for execution**.

Engineering did NOT self-ratify. The exact owner signature is in the final section.

ID:     PFA-18C  (amends the PFA-18A/18B signing-key lineage for the INITIAL BOOTSTRAP leg only)
CLASS:  compensating-control exception to a frozen human-separation requirement (KMS ceremony §2)

------------------------------------------------------------
OWNER DIRECTION
------------------------------------------------------------

The owner (founder) states as an owner fact: Snatch It currently has ONE technically-capable privileged
operator. The owner will NOT grant a non-technical person (e.g. Juan Fernandez) production DB superuser
or AWS KMS authority to manufacture separation of duties — fake separation LOWERS security. The owner
directs engineering to design a formal, adversarially-reviewed single-founder INITIAL bootstrap
exception under strong compensating controls, and to say plainly if it cannot be made acceptably safe.

------------------------------------------------------------
CURRENT PRODUCTION BASELINE  (READ-ONLY, 2026-09-04 15:24:48Z)
------------------------------------------------------------

ledger 124 · substrate through 109 (093–109 present) · signing keys 0 · signing.expected_key_fingerprint
null · signing.monitor_enabled false · native issuance false · native scanning false · Phase-2 native
edges NOT DEPLOYED · tickets 0 · door_pin 0 · door_session 0 · scan 0 · authenticated cannot INSERT
kernel.signing_key (superuser-only) · no drift. Substrate correctly staged to RECEIVE one dark trust root.

------------------------------------------------------------
EXISTING FROZEN RULE
------------------------------------------------------------

PRODUCTION_SIGNING_KMS_CEREMONY.md §2 requires two NAMED humans with non-shared credentials: Person A
(kms:CreateKey, NEVER DB superuser) and Person B (DB superuser, NEVER kms:CreateKey). Separation
invariant: "No single principal may both create the KMS key and write the database row." §5.3 binding
proof (A signs a challenge through the KMS handle, B verifies against B's OWN independently-exported
public key) is "the ONLY control in the entire system that detects" a KMS-handle↔public-key mismatch
(ADV-4). PFA-18A parks provision/rotate; PFA-18B un-parks emergency revoke (single platform_admin+aal2).

------------------------------------------------------------
WHY AMENDMENT IS REQUIRED
------------------------------------------------------------

The two-person ceremony is operationally unrealistic for a one-qualified-operator company (the prior
ceremony session correctly returned NO-GO). Without an amendment, Gate C is permanently blocked on an
organizational precondition Snatch It cannot honestly meet. The amendment resolves this WITHOUT weakening
any RUNTIME cryptographic control and WITHOUT pretending a non-technical witness is a verifier.

------------------------------------------------------------
SCOPE
------------------------------------------------------------

Authorizes ONE named, technically-qualified founder/owner to perform the INITIAL AWS KMS ES256 trust-root
bootstrap — create exactly one asymmetric KMS key, prove the handle↔key binding, insert EXACTLY ONE
global kernel.signing_key row (key_id …b0) via the (corrected) §6.1 artifact — under all controls
C1–C18 and mandatory additions M1–M6. One time only.

------------------------------------------------------------
NON-SCOPE
------------------------------------------------------------

Authorizes NONE of: future rotation/replacement/provisioning (PFA-18A stays PARKED); any second/scoped
signing key; ANY product activation (issuance, scanning, edges, config, fees, Connect, sale, scan,
money, payout); emergency recovery beyond PFA-18B revoke; delegating the exception to a non-technical
person or granting anyone dangerous authority; reuse of the exception once the maturity trigger is met.

------------------------------------------------------------
CORE PRINCIPLE (honest framing)
------------------------------------------------------------

The two-human model's real security property is ENVIRONMENTAL INDEPENDENCE — Person B's separate machine,
credentials, and eyes catch a compromise or error in Person A's environment. Most in-environment
controls (two libraries on one host; in-DB recomputation of the same input) substitute CODE independence,
which a single compromised host defeats identically. What actually stands in for Person B is (a) a KMS
private key that cannot be exported, and (b) an AUDIT PLANE the operator cannot forge or erase, plus (c)
a SECOND CLEAN DEVICE that re-verifies from a different trust domain. Those are mandatory here (M1–M3),
not optional.

------------------------------------------------------------
THREAT MODEL
------------------------------------------------------------

(Severity/likelihood for a careful single founder; existing = already enforced by the §6.1 artifact /
schema / monitor.)

A–H (wrong account/region/keyspec/usage/algorithm/pubkey/fingerprint): caught by C1 identity pin + C2
   param echo-back + C5 binding proof + PRE-FLIGHT 2 in-DB fingerprint gate. Residual negligible for
   honest error. NOTE H/G on a compromised host share the input → see M2.
I/J WRONG KMS ARN stored / DB trusts a key KMS won't sign with — S:CRITICAL. The DB NEVER calls KMS, so
   PRE-FLIGHT 3 (handle non-empty/not-placeholder) cannot detect it. **C5 binding proof is the ONLY
   detector** — and is self-attested for one operator → must run on the SECOND CLEAN DEVICE (M2). Sign-
   after-verify (C11) catches only an INCONSISTENT pair; a founder who registers a *consistent*
   attacker (handle+matching pubkey) passes it.
K TWO/SHADOW KEYS — PRE-FLIGHT 1 once-only + unique active-global index bar a second ACTIVE GLOBAL, but a
   superuser can raw-INSERT a SCOPED key later that OUTRANKS global (resolver is most-specific-first,
   ADV-7). The monitor alerts scoped_keys≠0 but the founder can DISARM the monitor. → P1-SHADOW; close
   with a BEFORE INSERT scope guard (M6/recommended).
L PRIVATE MATERIAL EXPORTED — C3 (KMS-resident) + the artifact aborts on "PRIVATE KEY" in the PEM.
M/N OVERLY BROAD IAM / SIGNER POINTS AT WRONG KEY — **retained-Sign forgery**: if the ceremony principal
   retains kms:Sign on the production key, it can sign arbitrary forged credentials DIRECTLY, bypassing
   get_ticket_signing_context's owner/terminal gates (the door verifies ANY signature under the trusted
   public_key). → close with a DISTINCT runtime IAM role, key policy granting kms:Sign to ONLY that role,
   ceremony principal drops Sign, verified from the second device (M3).
O FINGERPRINT CONFIG DRIFT — monitor recomputes+alerts; C7 sets expected==verified. Monitoring, not the
   runtime gate.
P/Q/R/S COMPROMISED ENV / SHELL / AWS CREDS / DB CREDS — the SINGLE-ENVIRONMENT RESIDUAL (below). Only
   M1 (out-of-band audit) + M2 (second device) + the DARK/REVOCABLE trust root reduce it; nothing
   removes it.
T OWNER IRREVERSIBLE MISTAKE — dry-run (C6) + exactly-one (C8) + a wrong DARK key is REVOKED (PFA-18B)
   before any credential is signed. But the P1-ALGO defect is a silent permanent brick → must be fixed.
U AI/TOOL WRONG INSTRUCTIONS — C18 hard stops; the coordinator NEVER executes AWS/DB mutations; every
   value echoed back and cross-checked; M2 re-derivation is out-of-tool.
V PRODUCT ACTIVATION DURING CEREMONY — C15 darkness before+after; bootstrap touches only signing_key +
   two signing config keys. (Arming the monitor starts a daily cron + net.http_post egress to
   notify-report on alert — an alert channel, NOT product activation; alert bodies carry only
   'match'/'MISMATCH', never key bytes.)
W FUTURE ROTATION VIA THE EXCEPTION — PFA-18A parked + PRE-FLIGHT 1 + the maturity trigger. BUT after a
   revoke the revoked row remains, so re-bootstrap via the artifact aborts and rotate is parked → the
   operator is pushed to a bare superuser INSERT mid-incident. → provide a gated post-revoke re-bootstrap
   artifact (P2).

THE SINGLE-ENVIRONMENT RESIDUAL (irreducible): a single principal holding KMS-admin + IAM-admin +
DB-superuser IS the trust root. If that one environment is fully compromised, it can orchestrate a
self-consistent fraudulent trust root that every IN-ENVIRONMENT check passes. No in-system control
prevents this; only human/environment separation does. This amendment makes it DETECTABLE (M1 audit,
M2 second device, the monitor as an out-of-band sink) and CONTAINED (the trust root is DARK and
REVOCABLE — it signs nothing until edge deploy + issuance flag + org onboarding, each separately
authorized, giving a long window to revoke a bad key before harm).

------------------------------------------------------------
MANDATORY ADDITIONS  (M1–M6 — required by the adversarial review; ratification is conditioned on them)
------------------------------------------------------------

M1  OUT-OF-BAND AUDIT PLANE (closes P0-AUDIT). An organization CloudTrail in a SEPARATE AWS account the
    ceremony principal has NO admin over; S3 Object-Lock (compliance mode) + MFA-delete; log-file
    validation ON. Verified present + immutable BEFORE the ceremony and re-verified AFTER. CreateKey /
    GetPublicKey / Sign event IDs + timestamps recorded (non-secret). If the trail can be disabled or
    its objects deleted by the ceremony principal, it is NOT out-of-band and M1 is UNMET → REJECTED.
M2  SECOND CLEAN DEVICE (closes P0-BIND + makes C4 real). A DIFFERENT device/session, not part of the
    ceremony host, with its OWN read-only IAM principal: independently GetPublicKey, derive the D5
    fingerprint, and run the §5.3 binding proof (challenge → KMS Sign via the ARN → verify against the
    device's own exported pubkey; altered msg FAILS, wrong key FAILS). Its 'Verified OK' and the
    CloudTrail Sign event ID go in the evidence pack. This is the ONLY mechanical stand-in for Person B;
    "two libraries on one host" does NOT count. The in-DB PRE-FLIGHT 2 must be fed the SECOND-DEVICE
    fingerprint, not one recomputed from the ceremony host's pub.der.
M3  DISTINCT RUNTIME IAM ROLE (closes P0-BIND retained-Sign). The long-lived credential-sign runtime
    principal is a DIFFERENT IAM role from the ceremony/CreateKey principal. The production key policy
    grants kms:Sign to ONLY that runtime role (+ kms:GetPublicKey if needed); the ceremony principal
    holds NO kms:Sign on the production key after the ceremony; never kms:Decrypt, never kms:*, never
    other keys. Prove by reading the committed key policy from the second device (M2).
M4  FIX THE §6.1 ALGORITHM DEFECT (P1-ALGO — REQUIRED before execution). The frozen §6.1 artifact's
    INSERT omits `algorithm`; migration 103 defaults it NOT NULL to 'EdDSA'. Bootstrapping an AWS ES256
    key with the verbatim artifact stores algorithm='EdDSA' → every credential fails sign-after-verify →
    NO ticket signable, IMMUTABLE (guard forbids algorithm change) — a silent permanent brick. FIX: the
    §6.1 ceremony artifact must insert `algorithm` explicitly (from a `-v ALGORITHM='ES256'`), with a
    PRE-FLIGHT asserting it matches the provider (AWS ⇒ ES256). This is a CEREMONY-ARTIFACT / runbook
    correction, NOT a production migration; it is NOT written in this session (per the no-code rule) and
    MUST be applied before any bootstrap. It also affects the two-person ceremony (same artifact).
M5  MANDATORY END-TO-END SIGN TEST BEFORE ISSUANCE (P2-E2E). Between trust establishment and any
    feature.native_issuance_enabled flip (a later, separately-authorized step), issue ONE credential
    through the DEPLOYED credential-sign edge for a throwaway atom and confirm sign-after-verify passes.
    check_signing_key_invariants never calls KMS, so it cannot catch a wrong pair; this test can, and
    would also catch a surviving P1-ALGO. (Downstream of this bootstrap; named here so it is not lost.)
M6  BEFORE INSERT SCOPE GUARD (P1-SHADOW — RECOMMENDED engineering hardening before issuance). Add the
    missing BEFORE INSERT companion to guard_signing_key_immutable: refuse any signing_key INSERT whose
    scope is not the single bootstrapped global (or refuse scoped rows entirely while provision/rotate
    are parked). This closes the founder-superuser scoped-shadow-key path that outranks global and that
    the (disarmable) monitor cannot prevent. This IS a code/migration change; it is documented here and
    NOT written this session (no migration 110). It does not block the initial DARK bootstrap (PRE-FLIGHT
    1 + the unique active-global index hold at bootstrap time) but SHOULD land before issuance activation.

------------------------------------------------------------
COMPENSATING CONTROLS  (C1–C18 — all mandatory; strengthened by M1–M6)
------------------------------------------------------------

C1  AWS IDENTITY PINNING — account/region/IAM-principal ARN recorded + verified; mismatch = STOP.
C2  EXACT KEY PARAMS — ECC_NIST_P256 / SIGN_VERIFY / ECDSA_SHA_256 / ES256; echoed from describe-key.
C3  NON-EXPORTABLE PRIVATE KEY — KMS-resident; nothing private locally / in Supabase / in env.
C4  TWO INDEPENDENT FINGERPRINT DERIVATIONS — openssl over DER SPKI + a different-library implementation;
    both = 64-hex equal + equal to PRE-FLIGHT 2. ON ONE HOST THIS IS NOT A CONTROL (P1-THEATER): the
    second derivation MUST run on the second device (M2).
C5  KMS BINDING PROOF — §5.3; the ONLY handle↔key detector; MANDATORY and run on the second device (M2).
C6  DRY-RUN — validate the (corrected) artifact inserts one row, changes nothing else.
C7  TRANSACTIONAL DB BINDING — insert the key AND set signing.expected_key_fingerprint (to the M2-verified
    fingerprint) in the same transaction (config write, existing mechanics), so there is no trusted-but-
    unpinned window; else set immediately after commit and run C10 to confirm 'match' (brief, revocable).
C8  EXACTLY ONE KEY — PRE-FLIGHT 1 + POST-CHECK + unique active-global index (global-vs-global only;
    scoped guarded by M6).
C9  ALGORITHM PIN — DB algorithm='ES256' (via M4), pinned at runtime (PFA-PT-8); no fallback/none.
C10 INVARIANT MONITOR — run check_signing_key_invariants (must be all-clear); arm signing.monitor_enabled
    at the runbook point. HONEST FRAMING: the monitor is DISARMABLE by the founder (single platform_admin;
    signing.monitor_enabled is deliberately NOT dual-controlled) → it is NOT a control against the
    operator; its value is an out-of-band alert SINK (notify-report egress) the founder cannot suppress,
    firing on scoped_keys≠0 / fingerprint MISMATCH.
C11 SAFE LIVE KMS SIGN TEST — sign a non-business message, verify ES256 against the STORED public_key;
    altered/wrong-key FAIL. Catches an inconsistent pair (not a consistent attacker key — see M2/M3).
C12 IAM LEAST PRIVILEGE — subsumed and strengthened by M3 (distinct runtime role; ceremony principal
    holds no runtime Sign; key policy Sign-only-to-runtime; ARN-scoped; no Decrypt/*).
C13 CLOUDTRAIL — subsumed and strengthened by M1 (separate account, Object-Lock, log-file validation,
    out of the ceremony principal's admin).
C14 DATABASE AUDIT EVIDENCE — before (0)/after (1), key id/ARN, fingerprint, algorithm, timestamps,
    invariant result. Never secrets.
C15 PRODUCT-DARKNESS — prove before + after: issuance false, scanning false, edges undeployed, tickets 0,
    scans 0, money 0.
C16 EMERGENCY REVOKE — PFA-18B available; a wrong DARK key is REVOKED, not deleted. Log a global-scope
    revoke to the out-of-band sink (it force-closes all door manifests — availability-destructive).
C17 PROVISION/ROTATE PARKED — PFA-18A unchanged; the exception is bootstrap-only.
C18 HARD-STOP CHECKLIST — interactive, hard stop after each stage (identity/env → CreateKey → M2
    fingerprint+binding → dry-run → transactional commit → invariants → live sign → M2 re-verify →
    darkness). No blind script; the AI coordinator never executes AWS/DB mutations.
Post-revoke re-bootstrap (P2): provide a GATED artifact (PRE-FLIGHT: exactly one revoked global, zero
    active) so the incident recovery path is not a bare superuser INSERT.

------------------------------------------------------------
PFA-18A / PFA-18B / RUNTIME NON-REGRESSION
------------------------------------------------------------

PFA-18A: UNCHANGED — provision/rotate PARKED; PFA-18C does not un-park or use them (the bootstrap is the
frozen direct §6.1 superuser insert, always the sanctioned bootstrap path). PFA-18B: UNCHANGED and RELIED
UPON as the abort path (revoke → "no active key" → issuance fails closed). RUNTIME NON-REGRESSION: this
amendment changes only WHO performs the human ceremony; it changes NO runtime byte — ES256/KMS
non-exportability, algorithm pin (PFA-PT-8), JWS wire format (PFA-PT-6), get_ticket_signing_context
resolution, guard_signing_key_immutable, AwsKmsSigner sign-after-verify + fail-closed — all unchanged
(signing code diff vs RC 5721a41 = empty). Runtime IAM (M3) is TIGHTER.

------------------------------------------------------------
OPTIONAL HUMAN WITNESS  (Juan Fernandez)
------------------------------------------------------------

PERMITTED but OPTIONAL, and only as a WITNESS (occurrence/intent/liveness) attestation ("I observed the
owner perform the ceremony on <date>, saw the two fingerprint values displayed equal, and saw the owner
approve the final transaction"), NEVER as a cryptographic verifier or as separation of duties, and with
NO AWS/DB/KMS/production authority. It adds thin anti-repudiation value; it reduces no P-level. If the
owner deems it theater, omit it — it is not required for ratification.

------------------------------------------------------------
FUTURE TWO-PERSON MATURITY TRIGGER
------------------------------------------------------------

The exception retires on the FIRST of: (T1) a SECOND qualified technical operator with production
responsibility is appointed (primary, security-based); (T2) institutional/priced-round funding brings a
security/technical stakeholder with production oversight; (T3) HARD BACKSTOP — the first of {a production
credential is signed, native issuance is enabled}, because from that instant the trust root is
load-bearing for money/tickets. After any trigger, ALL signing-key lifecycle ops (including post-revoke
re-bootstrap and future rotation) MUST use two-person control. The bootstrap itself is always performed
pre-commerce (T3 is downstream of and separately authorized from it).

------------------------------------------------------------
CODE / MIGRATION IMPACT
------------------------------------------------------------

The GOVERNANCE MODEL needs no migration. EXECUTION requires TWO changes, NEITHER written this session
(per the no-code rule; no migration 110 created):
  • REQUIRED (M4, P1-ALGO): correct the §6.1 CEREMONY ARTIFACT to set `algorithm='ES256'` explicitly with
    a provider-match PRE-FLIGHT. This is a runbook/ceremony-artifact fix (SQL embedded in the runbook),
    NOT a deployed migration. Without it, an ES256 bootstrap is a silent permanent brick.
  • RECOMMENDED (M6, P1-SHADOW): a BEFORE INSERT scope-guard trigger on kernel.signing_key (a migration).
    It closes the founder-superuser scoped-shadow-key path; it should land before issuance activation. It
    does not block the initial DARK bootstrap.
C7's atomic expected_fingerprint write uses the existing config-write path (not a new object). Everything
else (C4/C5/M1/M2/M3 tooling, CloudTrail) is procedural/infra, not code.

------------------------------------------------------------
ADVERSARIAL REVIEW  (self-review + one independent reviewer subagent; findings integrated)
------------------------------------------------------------

P0 FINDINGS  (RESOLVED ONLY by making M1–M3 mandatory; UNMET → REJECTED for execution)
  P0-AUDIT — the CloudTrail "immutable, outside the operator's control" premise is FALSE for a single
    founder unless architected: the same principal could StopLogging/DeleteTrail or delete the S3 objects,
    erasing the only after-the-fact detector; and could retain kms:Sign to forge credentials directly.
    CLOSE: M1 (separate-account Object-Lock trail) + M3 (distinct runtime role, key policy Sign-only-to-
    runtime, ceremony principal drops Sign).
  P0-BIND — the §5.3 binding proof (the ONLY handle↔pubkey detector) is self-attested for one operator;
    a compromised shell can fabricate 'Verified OK', and sign-after-verify does NOT catch a CONSISTENT
    attacker key (attacker handle + that key's real pubkey). CLOSE: M2 (run the binding proof + the
    fingerprint derivation on a second clean device with its own read-only IAM principal, recording
    'Verified OK' + the CloudTrail Sign event ID).

P1 FINDINGS
  P1-ALGO (REQUIRED fix, M4) — §6.1 omits `algorithm`; 103 defaults 'EdDSA'; ES256 bootstrap bricks
    immutably, fail-closed. Verified: 103:56-57 default 'EdDSA'; §6.1 insert column list has no algorithm.
  P1-SHADOW (RECOMMENDED, M6) — no BEFORE INSERT guard on signing_key (only BEFORE UPDATE exist, 083);
    a superuser can raw-insert a SCOPED shadow key that outranks global (resolver most-specific-first);
    the monitor is disarmable by the same founder. Verified: no `before insert on kernel.signing_key`.
  P1-THEATER — "two independent implementations on one host" share PATH/libcrypto/input → defeated
    identically by a trojaned lib. CLOSE: the second derivation runs on the second device (M2); do not
    count two-libs-on-one-host as a control.
  P1-PREFLIGHT2 — the in-DB PRE-FLIGHT 2 hashes the same host's PEM against a fingerprint computed from
    the same host's pub.der → self-consistency, not KMS binding. CLOSE: feed it the M2 second-device
    fingerprint.

P2/P3 FINDINGS
  P2-E2E (M5) — no mandated end-to-end credential-sign test before the issuance flip; a wrong pair (or
    P1-ALGO) reaches "buyer charged, atom minted, credential unsignable". CLOSE: M5.
  P2-MONITOR — the sole detection control (monitor) is disarmable by the operator it must catch. Framed
    honestly in C10: value = an un-suppressible out-of-band alert sink, not a control against the founder.
  P2-REVOKE — a single-admin global revoke is platform-wide door-plane destructive; log to the sink.
  P2-REBOOTSTRAP — post-revoke recovery is pushed to a bare superuser INSERT; provide a gated artifact.
  P3-DARKNESS — holds; note that arming the monitor begins a cron + notify-report egress (alert channel,
    not product activation).

RESIDUAL RISK
  Reduced to the SINGLE-ENVIRONMENT residual under M1–M6: the single operator IS the trust root;
  detectable (non-exportable key + operator-non-erasable audit + second device + dark/revocable window),
  NOT preventable. Materially smaller than single-founder MONEY authority — the bootstrap signs nothing
  and is revocable before any downstream, separately-authorized commerce step. This is a compensating-
  control model, not two-person separation of duties.

------------------------------------------------------------
RATIFICATION RECOMMENDATION
------------------------------------------------------------

READY FOR OWNER RATIFICATION of the governance model, CONDITIONED on ALL of M1–M6 and C1–C18. Concretely:
  • If M1 (out-of-band audit) AND M2 (second clean device) AND M3 (distinct runtime role + key policy)
    can be met → the two P0s are resolved and the model is acceptably safe for an early-stage,
    one-operator, pre-commerce bootstrap, on the honest "detectable-not-preventable" guarantee.
  • M4 (§6.1 algorithm artifact fix) is a REQUIRED pre-execution correction (P1-ALGO); the bootstrap must
    NOT run until it is applied.
  • M6 (BEFORE INSERT scope guard) is REQUIRED before issuance activation (P1-SHADOW), not before the
    dark bootstrap.
  • If the owner CANNOT or WILL NOT meet M1, M2, or M3 → NOT ACCEPTABLY SAFE → REJECTED for execution
    (the single-environment residual becomes an unmitigated P0, not an accepted residual).
Engineering does not self-ratify.

------------------------------------------------------------
EXACT OWNER SIGNATURE  (record in POST_FREEZE_AMENDMENTS.md if ratified)
------------------------------------------------------------

"PFA-18C APPROVED (YYYY-MM-DD). I authorize a single technically-qualified Snatch It founder/owner to
execute the INITIAL AWS KMS ES256 production trust-root bootstrap under PFA-18C's controls C1–C18 and its
mandatory additions M1–M6 — specifically INCLUDING an out-of-band CloudTrail in a separate AWS account
with Object-Lock (M1), a second clean device with its own read-only IAM principal performing the
fingerprint derivation and the binding proof (M2), a distinct runtime IAM role with the key policy
granting kms:Sign only to that role and the ceremony principal retaining no Sign (M3), the corrected §6.1
artifact that sets algorithm='ES256' (M4), the end-to-end sign test before any issuance flip (M5), and
the BEFORE INSERT scope guard before issuance activation (M6). I acknowledge this is a compensating-
control model that is NOT equivalent to human separation of duties and whose honest guarantee is
DETECTABLE, NOT PREVENTABLE, with a stated single-environment residual. This exception applies ONLY to
the initial bootstrap of exactly one global signing key and authorizes NO future provision, rotation,
replacement, product activation, ticket issuance, scanning, money movement, or payout. PFA-18A remains
parked; PFA-18B revoke remains the abort path. Future signing-key lifecycle operations return to
two-person control on the PFA-18C maturity trigger (T1 second qualified technical operator / T2
institutional funding with technical oversight / T3 first production credential signed or issuance
enabled, whichever first)."

------------------------------------------------------------
NEXT OPERATION AFTER RATIFICATION
------------------------------------------------------------

On owner signature AND after M4 (the §6.1 algorithm artifact fix) is applied, the next owner-authorized
operation is the single-founder INITIAL KMS bootstrap, executed interactively under C18's hard stops with
M1/M2/M3 in place and the AI acting as coordinator only (never executing the AWS/DB mutations). That is a
SEPARATE authorization; this document authorizes nothing to run.

------------------------------------------------------------
FINAL STATUS
------------------------------------------------------------

AMENDMENT:                     PFA-18C — single-founder initial KMS bootstrap (compensating-control model)
STATUS:                        READY FOR OWNER RATIFICATION of the model, CONDITIONED on M1–M6 + C1–C18;
                               REJECTED for execution if M1/M2/M3 cannot be met
HONEST GUARANTEE:              DETECTABLE, NOT PREVENTABLE (not equivalent to two-person SoD)
CODE / MIGRATION CHANGE:       REQUIRED §6.1 ceremony-ARTIFACT fix (M4/P1-ALGO) + RECOMMENDED BEFORE
                               INSERT scope-guard migration (M6/P1-SHADOW) — NEITHER written here; no migration 110
RUNTIME CRYPTO NON-REGRESSION: PROVEN (no runtime byte changed)
PFA-18A:                       UNCHANGED — provision/rotate PARKED
PFA-18B:                       UNCHANGED — revoke available (abort path)
PFA-PT-6 / PFA-PT-8:           UNCHANGED
PRODUCTION MUTATION THIS SESSION: NONE (read-only baseline only)
P0 OPEN:                       2 (P0-AUDIT, P0-BIND) — RESOLVED iff M1/M2/M3 are met; else BLOCKING
P1 OPEN:                       P1-ALGO (required fix, M4) · P1-SHADOW (required-before-issuance, M6) ·
                               P1-THEATER / P1-PREFLIGHT2 (resolved by M2)
OWNER RATIFICATION:            PENDING (owner signs separately)
NEXT:                          apply M4, meet M1/M2/M3, then a separate single-founder bootstrap session

============================================================

STOP. GOVERNANCE ONLY. DO NOT EXECUTE KMS. DO NOT CHANGE PRODUCTION. DO NOT DEPLOY EDGES. DO NOT ACTIVATE.

============================================================

------------------------------------------------------------
REMEDIATION ADDENDUM — 2026-09-04 (supersedes the conflicting points above)
------------------------------------------------------------

Full detail + evidence: docs/architecture/_governance/PFA_18C_REMEDIATION_AND_FINAL_RATIFICATION.md.

  • M4 / P1-ALGO — now FIXED + off-production PROVEN. The §6.1 ceremony artifact (PRODUCTION_SIGNING_KMS_
    CEREMONY.md) sets algorithm EXPLICITLY via `-v ALGORITHM="ES256"` with a PRE-FLIGHT 2b gate; §6.2 and
    the expected NOTICEs updated; §6.1↔§18.1 reconciled. Rehearsal proof: corrected artifact stores
    ES256, old column list stored EdDSA; 5 negatives abort; once-only holds; pgTAP 169 34/34, vitest kms
    56/56. Runbook/artifact change only — NO migration.
  • M6 — CLASSIFICATION FIXED: MANDATORY PRE-ISSUANCE HARDENING (not "optional", not pre-bootstrap). The
    round-2 reviewer VERIFIED no dark path signs/resolves a scoped shadow key, so deferring the BEFORE
    INSERT guard to before-issuance is safe; it should land WITH the bootstrap PR. Not written this session.
  • M1 — DECISION: Model B (same AWS account) for the DARK bootstrap ONLY, HARD-CONDITIONED on the
    concrete deny-set (CloudTrail Stop/Delete/Update denied; S3 delete/policy/lifecycle/retention/
    legal-hold/bypass/encryption denied; Object-Lock COMPLIANCE + retention period; log-bucket SSE-S3 or a
    CMK the ceremony principal cannot administer; all IAM self-escalation denied) READ BACK from the
    second device; Model A (separate audit account + SCP) REQUIRED before T3/commerce. Distinguishes
    ceremony-session authority (constrained) from ultimate owner/root authority (unconstrainable).
  • NEW FINDINGS integrated: P1-ALGO-DEFAULT (the schema default 'EdDSA' bricks any non-artifact insert →
    mitigated by M6's guard enforcing ES256 on the global row + any re-bootstrap artifact setting it
    explicitly; a future migration could drop the default); P1-REBOOTSTRAP-FAILOPEN (post-T3 recovery has
    no compliant mechanism → a gated two-person post-revoke re-bootstrap artifact is required forward
    work); P3-AI-DRIVES-PSQL (single-founder path: the FOUNDER runs every AWS/DB mutation; the AI is
    read-back coordinator ONLY — C18 strengthened).
  • Maturity trigger — the exception is consumed ONCE; T3 does not invalidate the completed bootstrap;
    future lifecycle ops are two-person + fail-closed; the post-T3 recovery gap is disclosed.
  • STATUS: PROPOSED / READY FOR OWNER RATIFICATION of the model, conditioned on the execution
    preconditions. NOT owner-approved (no signature supplied). Production UNCHANGED.
