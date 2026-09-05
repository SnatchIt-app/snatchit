# PFA-18C bootstrap — reviewable policy/configuration artifacts (NOT APPLIED)

Status: **DRAFT FOR REVIEW — nothing here has been applied to AWS.** These files are the concrete,
read-back-able form of the M1/M2/M3 requirements in `docs/architecture/_governance/PFA_18C_OWNER_RATIFICATION.md`.
They exist so that (a) the deny-set is code, not prose, and (b) Device 2 (M2) can diff the live AWS
configuration against these files during read-back. The founder applies them personally, one stage at a
time, under C18 — Claude never applies them.

Account `652872010073` · region `us-east-1` (pinned by owner confirmation, see readiness report) ·
audit bucket `snatchit-audit-652872010073` · trail `snatchit-audit-trail`.

| File | Attaches to | Stage |
|---|---|---|
| `m1_ceremony_role_trust.json` | IAM role `SnatchIt-KMS-Ceremony` — trust policy (jose-admin, MFA required, fixed session name) | M1 |
| `m1_ceremony_role_policy.json` | IAM role `SnatchIt-KMS-Ceremony` — inline permissions (CreateKey constrained to ECC_NIST_P256 / SIGN_VERIFY / AWS_KMS / single-region; tag-scoped key access; explicit deny-set) | M1 |
| `m1_audit_bucket_policy.json` | S3 bucket `snatchit-audit-652872010073` (CloudTrail write w/ `aws:SourceArn`; TLS-only; ceremony/verifier/runtime principals denied all mutation) | M1 |
| `m1_object_lock_configuration.json` | S3 bucket default retention — **COMPLIANCE mode; `Years` is an OWNER DECISION placeholder** | M1 |
| `m2_verifier_policy.json` | IAM user `snatchit-kms-verifier` — read-only (no `kms:Sign`/`Verify`/admin; explicit deny on all mutation) + needs AWS-managed `SignInLocalDevelopmentAccess` for `aws login` | M2 |
| `m3_runtime_user_policy.json` | IAM user `snatchit-credential-sign-runtime` — may ONLY `sts:AssumeRole` the runtime role; all direct KMS denied | M3 |
| `m3_runtime_role_trust.json` | IAM role `SnatchIt-CredentialSign-Runtime` — trust: runtime user + `sts:ExternalId` | M3 |
| `m3_runtime_role_policy.json` | IAM role `SnatchIt-CredentialSign-Runtime` — `kms:Sign` on the **exact** key ARN (ECDSA_SHA_256, RAW) only; `NotAction kms:Sign` denied. ARN filled AFTER CreateKey | M3 |
| `kms_key_policy_v1_binding_proof.json` | KMS key policy at `CreateKey` — account root may administer but can NEVER delegate crypto ops via IAM (`NotAction` on Sign/Verify/Decrypt/…); ceremony role has `kms:Sign` ONLY for the §5.3 binding proof | CreateKey |
| `kms_key_policy_v2_final.json` | Same minus the ceremony `kms:Sign` statement — applied via `PutKeyPolicy` immediately after the binding proof (§24) | post-proof |

**Account-layout caveat (Model A, readiness report §9 E6):** SCPs never bind an Organizations *management* account, so the production key must
be created in a *member* (workload) account. If the owner adopts that layout, every `652872010073` above becomes the workload member's account id
— settle this BEFORE CreateKey. Every owner-run AWS command carries `--profile snatchit-admin --region us-east-1` explicitly.

Placeholders that MUST be replaced before use: `<RETENTION_YEARS>`, `<KMS_SIGNER_EXTERNAL_ID>`,
`<PRODUCTION_KMS_KEY_ARN>`. Never put a secret value into a committed file.

Design notes
- The key policy's `root … NotAction [crypto ops]` statement keeps the key manageable (avoids the AWS
  "unmanageable key / contact Support" trap documented in the KMS default-key-policy guide) while making
  `kms:Sign` grantable ONLY by an explicit key-policy statement — IAM policies alone can never confer Sign.
- The ceremony role can call `PutKeyPolicy` (needed for v1→v2) but is DENIED `ScheduleKeyDeletion`,
  `DisableKey`, aliases, grants, and all other crypto ops for the duration of the ceremony.
- Residual (disclosed in PFA-18C, P3-REGRANT): `jose-admin` keeps AdministratorAccess and could re-add Sign
  or alter these policies. That is DETECTABLE (CloudTrail `PutKeyPolicy`/`PutRolePolicy`), not preventable,
  until Model A (separate audit account + SCP) exists. Device 2's read-back must therefore also confirm
  that NO `jose-admin` or root management events occur inside the ceremony window.
