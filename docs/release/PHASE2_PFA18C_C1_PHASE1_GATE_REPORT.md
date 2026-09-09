# PFA-18C — C1 PHASE-1 GATE REPORT (D2-4 … D2-8 corroboration and governance recording)

**Date:** 2026-09-09 (coordinator session, Claude A only; revision 2 after the owner re-established the `snatchit-admin` session) · **Scope:** coordinator verification + governance recording. **No mutation of any kind** (no AWS, production DB, issuance, scanning, payments, fees, Connect, transfers, refunds, payouts, migration 110–114, or secret rotation). **C2 has NOT begun.** PFA-18A remains parked.
**Artifact pin for Device 2:** `c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd` · **Handoff:** `docs/release/PFA18C_DEVICE2_RETRIEVAL_HANDOFF.md` · **Procedure:** packet §5a′ · **Prior revision of this report:** commit `570899cf…` (D2-8 blocked by an expired coordinator session — now superseded by the results below).

Evidence classes: **OWNER-RETURNED** (Device-2 operator / owner statements), **CLAUDE-OBSERVED** (coordinator read-only reads, 2026-09-09T03:41–03:45Z unless stated), **NOT OBSERVED**.

---

## 1. Gate decision

| Item | Status |
|---|---|
| D2-4 retrieval integrity | **PASS** — OWNER-RETURNED (10/10, pinned commit, no C2-only files); manifest digests CLAUDE-OBSERVED (session 11) |
| D2-5 independent read-back | **PASS** — OWNER-RETURNED; corroborated: the verifier's D2-5 read calls are present in CloudTrail (§3) and every live value re-read by the coordinator equals the artifacts/records |
| D2-6 verifier refusal probes | **PASS** — OWNER-RETURNED and **CLAUDE-OBSERVED in CloudTrail** under the verifier identity (§3): `PutBucketVersioning`, `AssumeRole`, `CreateAccessKey`, `AddTags` → `AccessDenied`; `CreateAlias` → `NotFoundException` (non-discriminating, as classified) |
| D2-7 CloudTrail read-back from Device 2 | **PASS with classified variance** — OWNER-RETURNED; variance confirmed read-only from CloudTrail flags (§4) |
| `jose-admin` mutation review | **PASS** — non-read-only events since 2026-09-08T02:40Z are exactly the authorized C1 set (§4); TOTP enrolment events at 02:37–02:38Z precede the window as recorded |
| Root / KMS safety | **PASS in the required window** — root activity since 02:40Z `[]`; `kms list-keys` `[]`; no `CreateKey`/`ScheduleKeyDeletion`/`PutKeyPolicy`/`DisableKey` events since 2026-09-08T00:00Z; **one out-of-window root observation flagged for acknowledgement (§5)** |
| Production darkness | **PASS** — unchanged (§6) |
| **Verifier authentication / MFA posture (M2 completion condition §F.2 of the handoff)** | **FAIL — BLOCKER.** Device 2's console session and its derived `aws login` session were **not MFA-authenticated**: `ConsoleLogin` for `snatchit-kms-verifier` at 2026-09-09T02:44:39Z (region **us-east-2**) shows **`MFAUsed: No`**; the passkey was enrolled *afterwards* (`EnableMFADevice` 02:47:51Z); no later MFA sign-in exists; every one of the verifier's **88** subsequent us-east-1 events (`aws login` 02:49:44Z, D2-5, D2-6, D2-7, `ListKeys`) carries **`mfaAuthenticated: "false"`**. The readiness packet (§5a′ D2-3) and the handoff (§F.2) require the verifier's working session to be passkey-authenticated (`mfaAuthenticated: true`). |
| **M2** | **NOT SATISFIED** (posture condition unmet; all other Device-2 substance passed) |
| **M1 (Model B)** | **NOT marked complete** (pending M2) |
| **C1 PHASE-1 GATE** | **OPEN** |
| **C2** | **NOT BEGUN.** Requires the separate exact owner authorization **"AUTHORIZE PFA-18C CREATEKEY"** (this report is not that). C4 (migrations 110–114) precedes the trust-root DB insert and needs its own authorization; not executed. |

The gate is not closed on owner-returned evidence alone and the posture condition is not weakened: the D2-5/D2-6 *results* do not depend on MFA, but the recorded M2 condition does, and it is the one that distinguishes "Device 2 read the account" from "Device 2 read the account as the MFA-protected verifier identity the design specifies".

---

## 2. Remediation to satisfy M2 (Device 2 only; no coordinator, `jose-admin`, or root involvement; no mutation)

R-M2-1. On Device 2: `aws logout --profile verifier`; sign out of the AWS console.
R-M2-2. Sign in again at `https://652872010073.signin.aws.amazon.com/console` as `snatchit-kms-verifier` with the password **and the enrolled passkey** (`verifier-device2-passkey`). Expected CloudTrail evidence (coordinator, read-only): `ConsoleLogin` with **`MFAUsed: Yes`** and `MFAIdentifier` = `arn:aws:iam::652872010073:u2f/user/snatchit-kms-verifier/verifier-device2-passkey-…` (in the region of the sign-in endpoint used — last time us-east-2).
R-M2-3. `aws login --profile verifier` (select the new session) then `aws sts get-caller-identity --profile verifier --region us-east-1 --no-cli-pager` → the verifier ARN; expected `mfaAuthenticated: "true"` on this and all later events.
R-M2-4. Re-run **D2-6** (the five probes) and **D2-5** (the read-back script; the artifacts already verified at D2-4 are unchanged — no re-download needed) and the **D2-7** lookups, exactly as in the handoff §E.2.
R-M2-5. Reply with the outcomes; the coordinator corroborates under the verifier identity with `mfaAuthenticated: "true"` and, if everything holds, records M2 SATISFIED, M1 MODEL B COMPLETE, C1 PHASE-1 GATE CLOSED.

Nothing else in C1 needs repeating. D2-4 stands.

---

## 3. D2-8 corroboration — verifier identity, posture, probes, reads (CLAUDE-OBSERVED)

**Identity/authentication (all with `userIdentity.arn = arn:aws:iam::652872010073:user/snatchit-kms-verifier`, type `IAMUser`):**
- **`ConsoleLogin` 2026-09-09T02:44:39Z, region us-east-2, `MFAUsed: No`, result Success** (event `c6596194…`) — the only verifier ConsoleLogin in any enabled region (fan-out over all regions; verifier events exist only in us-east-1 (88) and us-east-2 (7)).
- Console background reads 02:44:44–02:47:52Z (us-east-1): many `AccessDenied` for services outside the verifier's allow-list (ce, health, uxc, account, freetier, notifications, sso, `iam:GetAccountEmailAddress/GetAccountName/GetLoginProfile/ListAccountAliases/ListSigningCertificates/ListUserTags/GetMFADevice`) — all `readOnly: true`; expected denials; non-security-impacting. `GetAccountPasswordPolicy` → `NoSuchEntityException` (no custom account password policy exists — hardening observation outside PFA-18C scope). `GetAccountSummary`, `GetUser`, `ListAccessKeys`, `ListMFADevices` allowed.
- **`EnableMFADevice` 02:47:51Z, success, `readOnly: false`** (event `4c3706e4…`) — the passkey self-enrolment permitted by F3; the **only successful verifier mutation** in the window. Live: `list-mfa-devices` → exactly `arn:aws:iam::652872010073:u2f/user/snatchit-kms-verifier/verifier-device2-passkey-6UJX6DTACNAOFIWOQQHF7RNEOA` (enabled 02:47:51Z).
- **`aws login`:** `AuthorizeOAuth2Access` + `CreateOAuth2Token` 02:49:44Z (token refreshes 03:07:28Z, 03:18:13Z, 03:29:00Z); `GetCallerIdentity` 02:50:06Z and 03:23:01Z — **`mfaAuthenticated: "false"`** (inherited from the non-MFA console session).
- **Posture summary:** 88/88 verifier events in us-east-1 have `mfaAuthenticated: "false"`; none has `"true"`. Compare `jose-admin`: `ConsoleLogin` 2026-09-08T01:45:15Z `MFAUsed: Yes` (passkey) → every derived CLI event `mfaAuthenticated: "true"`, and again 2026-09-09T03:39:49Z (`MFAUsed: Yes`) for this coordinator session.

**Verifier state now:** access keys `[]`; **no successful `CreateAccessKey`** (only the denied probe); attachments exactly `SnatchIt-KMS-Verifier-ReadOnly` + `SignInLocalDevelopmentAccess`; inline `[]`; groups `[]`; policy `SnatchIt-KMS-Verifier-ReadOnly` default `v1`, `AttachmentCount 1`, `UpdateDate 2026-09-08T03:18:03Z` (unchanged).

**D2-6 probes under the verifier identity (us-east-1):** `CreateAlias` 03:20:13Z → `NotFoundException` (`a7899dcf…`, non-discriminating); `PutBucketVersioning` 03:23:31Z → `AccessDenied` (`c793341a…`); `AssumeRole` 03:24:14Z → `AccessDenied` (`a6ed84a8…`); `CreateAccessKey` 03:24:49Z → `AccessDenied` (`14c7eee4…`); `AddTags` 03:25:41Z → `AccessDenied` (`12dcc545…`). None succeeded; no resource changed.

**D2-5 read activity under the verifier identity (03:07–03:19Z, CLI):** `GetRole` ×4, `GetRolePolicy`, `ListAttachedRolePolicies` ×2, `GetPolicy`, `GetPolicyVersion`, `ListAttachedUserPolicies`, `ListUserPolicies`, `ListAccessKeys` ×2, `ListMFADevices`, `GetUserPolicy`, `ListRolePolicies`; S3 `GetBucketPolicy`, `GetBucketPublicAccessBlock`, `GetBucketEncryption`, `GetBucketObjectLockConfiguration`, `GetBucketVersioning`; CloudTrail `DescribeTrails`, `GetTrailStatus`, `GetEventSelectors`; then D2-7 `LookupEvents` ×11 and `kms ListKeys` 03:32:27Z. **Nothing outside the read-only/refusal envelope.** (7 further verifier events in us-east-2 = the ConsoleLogin plus console background reads; itemized in the execution record.)

---

## 4. `jose-admin` review (CLAUDE-OBSERVED)

**Non-read-only events since 2026-09-08T02:40:00Z — exactly the authorized C1 set:** 02:41:45 `CreateRole`, 02:41:57 `PutRolePolicy` (ceremony); 02:44:06 `CreateUser`, 02:44:15 `PutUserPolicy` → `LimitExceededException` (F7); 03:18:03 `CreatePolicy`, 03:18:10 + 03:18:21 `AttachUserPolicy`; 03:32:14 `CreateLoginProfile` (console); 03:39:06 `CreateBucket`, 03:39:16 `PutBucketPublicAccessBlock`, 03:39:24 `PutBucketEncryption`; 03:47:07 `CreateUser`, 03:47:28 `PutUserPolicy`, 03:47:46 `CreateRole` (runtime); 03:56:17 `PutBucketPolicy`; 04:00:44 `PutBucketObjectLockConfiguration`; 04:02:27 `CreateTrail`, 04:02:33 `PutEventSelectors`, 04:02:41 `StartLogging`; and on 2026-09-09 03:39:38 `CheckMfa` + 03:39:49 `ConsoleLogin` (the coordinator-session re-login; authentication, not a resource change). **Nothing unexpected.** The C1-0b TOTP enrolment (`CreateVirtualMFADevice` 02:37:28Z, `EnableMFADevice` 02:38:38Z) precedes the window start, as recorded. STS `AssumeRole` T1/T2 are `readOnly: true` events.

**Variance events — confirmed read-only, non-mutating (`readOnly: true`, `managementEvent: true`, `errorCode` null, console user agent):** `DescribeEventAggregates` (health) ×6, `ListNotificationHubs` ×3 and `ListManagedNotificationEvents` ×42 (User Notifications — the console polls every ~2 min while a tab is open), `GetAccountPlanState` (freetier) ×3, `DescribeRegions` (ec2) ×2, `GetAccountColor` (uxc) ×3. **Classification: acceptable variance — console background/telemetry reads from the `jose-admin` console sessions (TOTP enrolment, verifier password step, billing verification).** Other read-only `jose-admin` activity in the window: the coordinator's `Get*/List*/Describe*/LookupEvents` reads, 22 × `SimulatePrincipalPolicy`, `DescribeOrganization` (NotInUse) ×3, console IAM-page reads (`ListServiceSpecificCredentials`, `ListSSHPublicKeys`, `ListPolicyGenerations`), and `ce:GetCostAndUsage/GetCostForecast` → `AccessDenied` (Cost Explorer not enabled for IAM access; read-only). The D2-7 expectation is amended in the record to: *non-read-only `jose-admin` events must equal the C1 set; read-only console background reads are acceptable.*

---

## 5. Root / KMS / inventory (CLAUDE-OBSERVED)

- Root activity since 2026-09-08T02:40:00Z: **none**.
- **Out-of-window root observation (flagged, not a gate item):** `PasswordRecoveryRequested` 2026-09-08T01:17:49Z and `PasswordRecoveryCompleted` 01:18:21Z by Root (sign-in events; before the C1 window and before the trail existed; visible in event history). Consistent with the owner's statement that root was used for the billing step on 2026-09-08 (Paid-plan upgrade verified 01:50Z); root still has 0 access keys and MFA enabled. Owner acknowledgement requested in the record; no action within the ceremony window.
- KMS: `list-keys` → `[]`; no `CreateKey`, `ScheduleKeyDeletion`, `PutKeyPolicy`, `DisableKey` events since 2026-09-08T00:00Z by any principal. **No production KMS key exists.**
- Inventory: roles `SnatchIt-KMS-Ceremony`, `SnatchIt-CredentialSign-Runtime` (runtime role: no inline, no attached policies); users `jose-admin`, `snatchit-kms-verifier`, `snatchit-credential-sign-runtime` (access keys `[]` for all three); local policy `SnatchIt-KMS-Verifier-ReadOnly`; bucket `snatchit-audit-652872010073`; trail `snatchit-audit-trail` (`IsLogging true`, no delivery error, digest delivered 2026-09-09T03:13:09Z); account summary `AccessKeysPresent 0`, `MFA 1`, `Users 3`, `Roles 5` (3 service-linked + 2), `Policies 1`.

## 6. Production darkness (CLAUDE-OBSERVED 2026-09-09T03:42:25Z, read-only)

ledger 130 · numeric tip 120 · 110–114 absent · `kernel.signing_key` **0** · guard absent · tickets 0 · door sessions 0 · `feature.native_issuance_enabled false` · `feature.native_scanning_enabled false` · `signing.monitor_enabled false` · `signing.expected_key_fingerprint null` · `signing.expected_max_not_after null`. **No trust-root bootstrap occurred.**

## 7. Governance recording

- Execution record: session 13 appended — D2-8 results with timestamps/event IDs and provenance; the MFA-posture blocker; the remediation R-M2; the root out-of-window observation; the amended D2-7 expectation.
- **Not recorded:** M2 SATISFIED · M1 MODEL B COMPLETE · C1 PHASE-1 GATE CLOSED (conditions not met).
- **C2 NOT BEGUN** — requires the separate exact owner authorization **"AUTHORIZE PFA-18C CREATEKEY"**; C4 (110–114) first, under its own authorization.

## 8. Next smallest action

Device 2 operator: R-M2-1 … R-M2-4 (§2). Then reply; the coordinator re-corroborates and closes the gate if the posture condition is met.
