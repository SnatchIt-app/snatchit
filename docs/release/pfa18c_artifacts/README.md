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

## Validation log — 2026-09-08 (session 9; artifacts still NOT applied)

Checked against the AWS API/CLI references read that day (CreateKey, AssumeRole, put-object-lock-configuration, create-trail, create-virtual-mfa-device, MFA-protected API access, `aws login`, SignInLocalDevelopmentAccess). Findings and the two artifact corrections:

| # | Finding | Disposition |
|---|---|---|
| F1 | CreateKey refuses a key policy unless "the calling principal" keeps `kms:PutKeyPolicy` (lockout safety check, `BypassPolicyLockoutSafetyCheck=false`). v1 relied on the root→IAM delegation plus the ceremony role's **tag-conditioned** IAM allow; whether the check honours a `aws:ResourceTag` condition against tags supplied in the same CreateKey request is undocumented. | **Corrected:** v1 gains `CeremonyMayApplyV2_PolicyLockoutSafety_REMOVED_IN_V2` (ceremony role: `PutKeyPolicy`, `GetKeyPolicy`, `DescribeKey`). v2 unchanged — the ceremony role keeps only read statements after the proof; PutKeyPolicy v2 runs under v1. If v2's own lockout check refuses the ceremony role, the fallback is `jose-admin` applying v2 (logged), never `BypassPolicyLockoutSafetyCheck=true`. |
| F2 | "The principals in the key policy must exist and be visible to AWS KMS" (+ eventual-consistency delay). The same applies to S3 bucket policies (invalid principal ⇒ MalformedPolicy). The earlier stage order put the bucket policy (M1-2) before the roles/users it names. | **Order corrected in the packet:** all four IAM principals are created first (C1-1…C1-3), then the bucket and its policy, then the trail; wait ≥ 60 s after creating a principal before naming it in a policy. |
| F3 | The verifier's Deny `iam:Create*` blocks `CreateVirtualMFADevice`, and no Allow covered `EnableMFADevice`/`ChangePassword`, so Device 2 could neither enrol a passkey/authenticator nor complete a forced password change. | **Corrected:** `VerifierManageOwnMFAAndPassword` (EnableMFADevice, ResyncMFADevice, ListMFADevices, GetUser, ChangePassword — **own user ARN only**) + `VerifierReadPasswordPolicy`. None of these match a Deny wildcard (checked). `DeactivateMFADevice` and `CreateVirtualMFADevice` stay denied: Device 2 enrols a **passkey/security key or an authenticator app via the console**; a CLI-seeded virtual MFA would have to be created by `jose-admin`. |
| F4 | `m1_object_lock_configuration.json` `Years` must be an **integer** when filled (`"Years": 3`, not `"3"`); Object Lock must be enabled at bucket creation (`--object-lock-enabled-for-bucket`). | Placeholder retained (owner decision); filling rule recorded. |
| F5 | `sts assume-role` output contains credentials. | Every owner command that returns credentials carries `--query AssumedRoleUser` (or writes to the CLI profile mechanism), never raw output in chat. |
| F6 | Trust condition `aws:MultiFactorAuthPresent=true`: satisfied deterministically only by passing `SerialNumber`+`TokenCode` of a **virtual/hardware TOTP** device on `AssumeRole` ("You cannot use MFA-protected API access with U2F security keys"; passkeys are console-enrolled and console-only). Whether `aws login` console-derived credentials carry the MFA context is **not documented** — not assumed. | Decision D6 in the packet; the condition is never removed. |
| — | Unchanged after review: ceremony role trust/policy (CreateKey conditions, tag scoping, deny-set), bucket policy (CloudTrail `aws:SourceArn`, TLS-only, principal deny), runtime user/role/policy shapes, v2 key policy, trail selectors requirement (`ReadWriteType All`, management events, no `kms.amazonaws.com` exclusion). | — |

**2026-09-08 (session 10):** `m1_object_lock_configuration.json` — `<RETENTION_YEARS>` replaced by the integer **3** (owner-approved COMPLIANCE retention, explicit). Remaining placeholders by design: `<KMS_SIGNER_EXTERNAL_ID>` (local copy only, never committed) and `<PRODUCTION_KMS_KEY_ARN>` (filled after CreateKey).

## Model A (organization + audit account) — DRAFT artifacts, 2026-09-08 (session 11). NOT authorized, NOT applied.

`model_a/scp_workload_guardrails.json` — SCP for the **Workloads** OU (binds `652872010073` incl. its root): denies CloudTrail Stop/Delete/Update/selector changes; denies mutation of both audit buckets (the Model-B bucket and the org audit bucket); denies `kms:ScheduleKeyDeletion` / `DeleteImportedKeyMaterial` on the exact production key (`DisableKey` deliberately **not** denied — PFA-18B emergency path stays available); denies `organizations:LeaveOrganization`. `FullAWSAccess` stays attached alongside.
`model_a/org_audit_bucket_policy.json` — bucket policy for `snatchit-org-audit-<AUDIT_ACCOUNT_ID>` (audit account; Object Lock COMPLIANCE; SSE-S3): CloudTrail write for the **organization trail** `snatchit-org-trail` owned by the management account, org + management log prefixes, TLS-only.
Placeholders: `<MGMT_ACCOUNT_ID>`, `<AUDIT_ACCOUNT_ID>`, `<ORG_ID>` (known only after the accounts/organization exist), `<PRODUCTION_KMS_KEY_ARN>` (after C2). Package and verification: `PHASE2_PFA18C_EXECUTION_READINESS_PACKET.md` §5c.
