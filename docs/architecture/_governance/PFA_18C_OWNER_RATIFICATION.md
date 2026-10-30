# PFA-18C — OWNER RATIFICATION RECORD

**Single-founder INITIAL AWS KMS ES256 trust-root bootstrap exception (compensating-control model)**

```
AMENDMENT:            PFA-18C
STATUS:               OWNER-RATIFIED (model APPROVED, execution-gated)
RATIFICATION DATE:    2026-09-04
RATIFIED BY:          Owner (Snatch It), via governance ratification train (CLAUDE A)
SESSION SCOPE:        GOVERNANCE RATIFICATION ONLY — no KMS execution, no production mutation
PRODUCTION MUTATION:  NONE
KMS KEY CREATED:      NO
SIGNING KEYS IN PROD: 0
NATIVE ISSUANCE:      FALSE
NATIVE SCANNING:      FALSE
SOURCE OF MODEL:      docs/architecture/_governance/PFA_SINGLE_FOUNDER_KMS_BOOTSTRAP.md
REMEDIATION PACKAGE:  docs/architecture/_governance/PFA_18C_REMEDIATION_AND_FINAL_RATIFICATION.md
REGISTRY ENTRY:       docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md → "PFA-18C"
```

---

## 1. What was ratified

The owner reviewed the PFA-18C proposal and its remediation/final-ratification package and **APPROVED the governance model** for a single-founder INITIAL AWS KMS ES256 production trust-root bootstrap, under the compensating TECHNICAL controls, with the honest guarantee stated as **DETECTABLE, NOT PREVENTABLE**.

The owner explicitly accepted the remediation findings:

- **M4 / P1-ALGO** is fixed and off-production proven (the §6.1 artifact sets `algorithm='ES256'` explicitly; never inherits the `EdDSA` column default).
- **M1 Model B** is acceptable **for the INITIAL DARK bootstrap only**, under the concrete deny-set / Object-Lock / read-back requirements. **Model A** (separate audit account) is REQUIRED before T3.
- **M2** second clean device remains mandatory.
- **M3** distinct runtime IAM role remains mandatory.
- **M5** is mandatory before issuance.
- **M6** is mandatory before issuance but does **not** block the initial dark bootstrap.
- PFA-18C is **consumed once** and may not be reused.
- Future signing-key lifecycle operations **return to two-person governance**.
- Production remains **dark and unchanged** until separately authorized.

The owner acknowledged that this is a compensating-control model that is **NOT equivalent to human separation of duties**, with the documented single-environment residual and the Model-B same-account residual until Model A is established.

---

## 2. Owner signature (verbatim, as supplied)

> **PFA-18C APPROVED (2026-09-04).**
>
> I authorize a single technically-qualified Snatch It founder/owner to execute the INITIAL AWS KMS ES256 production trust-root bootstrap under PFA-18C.
>
> **REQUIRED BEFORE THE DARK BOOTSTRAP:**
> 1. The M4-corrected §6.1 artifact that sets `algorithm='ES256'` explicitly.
> 2. The M1 audit plane using Model B in the current AWS account with the concrete deny-set: CloudTrail Stop/Delete/Update denied to the ceremony principal; S3 delete/policy/lifecycle/retention/legal-hold/bypass/encryption mutation denied to the ceremony principal; Object-Lock COMPLIANCE mode with an actual retention period; log-bucket encryption using SSE-S3 or a KMS key the ceremony principal cannot administer; IAM self-escalation denied; all controls read back and verified from the M2 second device.
> 3. The M2 second clean device with its own read-only IAM principal performing: independent GetPublicKey; canonical SPKI derivation; independent fingerprint derivation; §5.3 KMS binding proof; altered-message failure verification; wrong-key failure verification; audit deny-set read-back; KMS key-policy read-back.
> 4. The M3 distinct runtime IAM role: separate from the ceremony/CreateKey principal; kms:Sign only on the exact production signing-key ARN; kms:GetPublicKey only if required; no kms:Decrypt; no kms:*; no unrelated key access; ceremony principal retains no long-lived kms:Sign after bootstrap.
> 5. C18: I, the founder, personally run every AWS and production DB mutation. Claude/AI acts only as coordinator and read-back verifier. No AI system, non-technical witness, or other person executes the mutation on my behalf.
>
> **REQUIRED AFTER THE BOOTSTRAP BUT BEFORE ANY NATIVE ISSUANCE:**
> - M6 BEFORE INSERT scope/algorithm guard migration.
> - M5 end-to-end credential-sign test.
> - Model A separate audit account / stronger audit isolation before T3.
> - compliant gated two-person post-revoke re-bootstrap mechanism.
>
> I acknowledge this is a compensating-control model that is NOT equivalent to human separation of duties. Its honest guarantee is DETECTABLE, NOT PREVENTABLE, with the documented single-environment residual and the Model-B same-account residual until Model A is established.
>
> This exception applies ONLY to the INITIAL bootstrap of exactly one global signing key. It authorizes NO: future provision, rotation, replacement, product activation, ticket issuance, scanning, fee activation, Connect onboarding, PaymentIntent, charge, transfer, refund, payout, money movement, migration 110, secret rotation.
>
> PFA-18A remains PARKED. PFA-18B revoke remains the emergency abort path. PFA-18C is CONSUMED ONCE after successful bootstrap. All future signing-key lifecycle operations return to two-person control under the defined maturity trigger and must fail closed if the required second qualified operator does not exist.

---

## 3. Signature-conformance verification

The supplied signature was checked against the exact signature text required by the remediation/final-ratification package
(`PFA_18C_REMEDIATION_AND_FINAL_RATIFICATION.md`, "EXACT OWNER SIGNATURE", lines 271–296). Conformance:

| Required element | Present in owner signature |
|---|---|
| `PFA-18C APPROVED (date)` with concrete date | YES — 2026-09-04 |
| Authorizes ONE technically-qualified founder, INITIAL AWS KMS ES256 bootstrap only | YES |
| Before-bootstrap: M4-corrected §6.1 artifact `algorithm='ES256'` | YES (item 1) |
| Before-bootstrap: M1 Model B concrete deny-set (CloudTrail / S3 mutation / Object-Lock compliance + retention / log-CMK / IAM self-escalation), read back from second device | YES (item 2) |
| Before-bootstrap: M2 second clean device — GetPublicKey, SPKI, fingerprint, §5.3 binding proof, altered-message + wrong-key failure, deny-set + key-policy read-back | YES (item 3) |
| Before-bootstrap: M3 distinct runtime role — Sign only on exact ARN, no kms:Decrypt / kms:*, ceremony principal drops Sign | YES (item 4) |
| Before-bootstrap: C18 — founder runs every AWS/DB mutation; AI is read-back coordinator only | YES (item 5) |
| Before-issuance: M6 BEFORE INSERT guard migration | YES |
| Before-issuance: M5 end-to-end credential-sign test | YES |
| Before-issuance/T3: Model A separate audit account | YES |
| Before-issuance: gated two-person post-revoke re-bootstrap | YES |
| Compensating-control acknowledgment — DETECTABLE-NOT-PREVENTABLE + residuals | YES |
| Scope: exactly one global signing key; consumed once | YES |
| Full non-authorization list (provision/rotate/replace/activate/issue/scan/fee/Connect/PaymentIntent/charge/transfer/refund/payout/money/migration 110/secret rotation) | YES |
| PFA-18A parked; PFA-18B abort path; future lifecycle → two-person, fail closed | YES |

**Result: the owner signature exactly satisfies PFA-18C.** Engineering did not self-ratify; the signature was owner-supplied.

---

## 4. Control status at ratification

```
M4:        FIXED (off-production proven; runbook §6.1/§6.2; no migration)
M1:        REQUIRED BEFORE BOOTSTRAP (Model B same-account deny-set + Object-Lock compliance +
           log-CMK control + M2 read-back). Model A REQUIRED BEFORE T3.
M2:        REQUIRED BEFORE BOOTSTRAP (second clean device, own read-only IAM, independent
           GetPublicKey + §5.3 binding proof + deny-set/key-policy read-back)
M3:        REQUIRED BEFORE BOOTSTRAP (distinct runtime role; key policy Sign-only-to-runtime;
           ceremony principal drops Sign)
M5:        REQUIRED BEFORE ISSUANCE (end-to-end credential-sign test)
M6:        REQUIRED BEFORE ISSUANCE (BEFORE INSERT scope/algorithm guard migration; not written)
MODEL A:   REQUIRED BEFORE T3
C18:       founder runs every AWS/DB mutation; AI is read-back coordinator only
```

Maturity trigger (returns lifecycle to two-person control, fail closed if no second qualified operator):
**T1** second qualified technical operator / **T2** institutional funding with technical oversight /
**T3** first production credential signed or issuance enabled — whichever first.

---

## 5. Lineage state

```
PFA-18A (provision / rotate):   PARKED
PFA-18B (revoke un-parked):     AVAILABLE — emergency abort path
PFA-18C (initial bootstrap):    OWNER-RATIFIED — CONSUMED ONCE after successful bootstrap
```

---

## 6. Production state (unchanged this session)

```
PRODUCTION MUTATION:      NONE
LEDGER (last verified):   124 (substrate 093–109 LIVE-but-DARK)
SIGNING KEYS:             0
FEATURE FLAGS:            dark (issuance / scanning FALSE)
NATIVE EDGES:             not deployed
KMS KEY:                  not created
CONFIG:                   unchanged (fee.buyer_service_bps unset; deletion.post_event_hold_hours
                          owner-unset; tax PFA-PT-7 open/fail-closed)
```

No AWS KMS key was created; no `kernel.signing_key` row was written; `signing.expected_key_fingerprint`
was not set; `signing.monitor_enabled` was not enabled; no IAM principals were created; no CloudTrail/S3/
Object-Lock change was made; no edge was deployed; no flag was flipped; no migration 110 exists; no money
moved; no ticket issued; no scan created.

---

## 7. Next gate (separate authorization required)

```
NEXT GATE:                SINGLE-FOUNDER KMS BOOTSTRAP INFRASTRUCTURE PREPARATION + CEREMONY
SEPARATE AUTHORIZATION:   YES — a new explicit owner-authorized operation
PRECONDITION:             the BOOTSTRAP BLOCKERS (M1/M2/M3 concretely met + second-device verified,
                          M4-corrected artifact in hand) must be satisfied before the dark bootstrap;
                          M5/M6/Model A before any native issuance.
```

The actual infrastructure setup and KMS bootstrap is a SEPARATE owner-authorized operation, executed
interactively with the founder running every AWS/DB command and the AI acting as read-back coordinator
only. It was NOT performed in this ratification session.
