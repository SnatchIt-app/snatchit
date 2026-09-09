# PFA-18C — C1 PHASE-1 GATE REPORT (D2-4 … D2-8 corroboration and governance recording)

**Date:** 2026-09-09 (coordinator session, Claude A only) · **Scope:** coordinator verification + governance recording. **No mutation of any kind** (no AWS, production DB, issuance, scanning, payments, fees, Connect, transfers, refunds, payouts, migration 110, or secret rotation). **C2 has NOT begun.** PFA-18A remains parked.
**Artifact pin for Device 2:** `c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd` · **Handoff:** `docs/release/PFA18C_DEVICE2_RETRIEVAL_HANDOFF.md` (`7117302b…`) · **Procedure:** packet §5a′.

Evidence classes: **OWNER-RETURNED** (Device-2 operator / owner statements), **CLAUDE-OBSERVED** (coordinator read-only reads this session), **NOT OBSERVED** (could not be read this session; stated as such).

---

## 1. Result summary

| Item | Status |
|---|---|
| D2-4 retrieval integrity (10/10 files, pinned commit, no C2-only downloads) | **PASS — OWNER-RETURNED**; the manifest digests were coordinator-verified against committed blobs and GitHub-served bytes on 2026-09-09T02:53Z (CLAUDE-OBSERVED, prior session) |
| D2-5 independent read-back + diff | **PASS — OWNER-RETURNED**; every item matches the coordinator's own C1-1 … C1-8 read-backs recorded 2026-09-08 (CLAUDE-OBSERVED then) |
| D2-6 verifier refusal probes | **PASS — OWNER-RETURNED** (CreateAlias non-discriminating, as specified) |
| D2-7 CloudTrail read-back from Device 2 | **PASS with one classified variance — OWNER-RETURNED** (see §4) |
| Final Device-2 safety check `kms list-keys` → `[]` | **PASS — OWNER-RETURNED**; coordinator corroboration of "no KMS key" from the production-DB side: `kernel.signing_key` = 0 (CLAUDE-OBSERVED 03:34:37Z) |
| **D2-8 coordinator corroboration from the primary side** | **NOT PERFORMED — BLOCKED:** the coordinator's `snatchit-admin` `aws login` session has expired ("Your session has expired. Please reauthenticate using 'aws login'"), so every read-only CloudTrail/IAM/KMS query attempted at 03:34Z failed. Re-authentication is an owner console action the coordinator cannot perform. |
| Production DB (CLAUDE-OBSERVED 2026-09-09T03:34:37Z) | **unchanged:** ledger 130, numeric tip 120, 110–114 absent, `kernel.signing_key` **0**, guard absent, tickets 0, issuance/scanning/monitor `false`, fingerprint `null` |
| **M2** | **NOT YET SATISFIED** — completion condition 4 (coordinator corroboration of Device-2 identity/MFA posture and probe outcomes from CloudTrail) and the CloudTrail-flag confirmation of the §4 variance are outstanding |
| **M1 (Model B)** | configured, ceremony-probed (C1-9), Device-2 read back (owner-returned) — **not marked complete** pending D2-8 |
| **C1 PHASE-1 GATE** | **OPEN** pending D2-8 |
| **C2** | **NOT BEGUN.** Requires the separate exact owner authorization **"AUTHORIZE PFA-18C CREATEKEY"** (and C4 migrations 110–114 under their own authorization first, per the confirmed ordering). |

The gate is not closed on owner-returned evidence alone: the reviewed M2 completion conditions (handoff §F, item 4) require the coordinator to corroborate Device 2's own activity in CloudTrail. That read requires a live `snatchit-admin` session.

---

## 2. D2-4 … D2-7 — owner-returned results as recorded (verbatim substance)

**D2-4 — PASS.** Exact 10/10 retrieval from `c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd`; all SHA-256 matched the manifest; no C2-only artifact (`m3_runtime_role_policy.json`, `kms_key_policy_v1_binding_proof.json`, `kms_key_policy_v2_final.json`) downloaded.

**D2-5 — PASS.** Ceremony role metadata/trust/policy matched; no managed policies. Verifier managed policy matched; attachments exactly `SnatchIt-KMS-Verifier-ReadOnly` + `SignInLocalDevelopmentAccess`; inline `[]`; access keys `[]`; MFA/passkey present. Runtime user policy matched; access keys `[]`. Runtime role trust structure matched with `ExternalIdLength 64`; **the ExternalId value was never displayed**; runtime role inline `[]`, managed `[]`. Audit bucket policy equivalent; PAB all `true`; SSE-S3 `AES256`; Object Lock `COMPLIANCE` 3 years; versioning `Enabled`. CloudTrail multi-region, log-file validation on, no KMS key; logging active with no delivery error; event selectors correct.

**D2-6 — PASS.** (1) `kms CreateAlias` on the non-existent target → `NotFoundException` — **non-discriminating, as specified** (same finding as C1-9 P3; discriminating test P3′ is deferred to C2). (2) `s3 PutBucketVersioning` → `AccessDenied` with an explicit deny from `SnatchIt-KMS-Verifier-ReadOnly`. (3) `sts AssumeRole SnatchIt-KMS-Ceremony` → `AccessDenied`. (4) `iam CreateAccessKey snatchit-kms-verifier` → `AccessDenied` with an explicit deny. (5) `cloudtrail AddTags` → `AccessDenied`. No access key was created.

**D2-7 — PASS (variance classified in §4).** Ceremony `AssumeRole` events seen from Device 2: 2026-09-08T04:24:06Z (`jose-admin` → `SnatchIt-KMS-Ceremony`, `mfaAuthenticated true`, `serialNumber null`, no error — T1) and 04:24:43Z (same, `serialNumber arn:aws:iam::652872010073:mfa/jose-admin-totp` — T2). Root activity in the window: `[]`. Ceremony refusal events: 04:31:22Z `AddTags` AccessDenied; 04:32:02Z `PutBucketVersioning` AccessDenied; 04:32:32Z `CreateAlias` NotFoundException; 04:36:16Z `GetUser` AccessDenied; 04:36:50Z `AssumeRole` AccessDenied — all consistent with the coordinator's records (event IDs `f00a1ecf…`, `7d56dfd9…`, `a99105a8…`, `1a578c07…`, `3c27859f…`).

---

## 3. D2-8 — coordinator corroboration: what was attempted, what is outstanding

Attempted 2026-09-09T03:34Z (read-only, `--profile snatchit-admin --region us-east-1`): CloudTrail `lookup-events` for `Username=snatchit-kms-verifier` (last 30 h), for `Username=jose-admin` since 2026-09-08T02:40Z split by `readOnly`, for `Username=root`, for `CreateKey`/`ScheduleKeyDeletion`/`PutKeyPolicy`; `kms list-keys`; verifier `list-mfa-devices` / `list-access-keys` / attachments; resource inventory. **All refused: session expired.** No mutation was attempted.

Outstanding checks (to run once the owner re-establishes the session with `aws login --profile snatchit-admin`; read-only; no Device-2 action needed):
1. Verifier identity/MFA posture: `ConsoleLogin` (expect `additionalEventData.MFAUsed: Yes`), `EnableMFADevice` (the passkey enrolment), `CreateOAuth2Token` (aws login), `GetCallerIdentity` — all under `user/snatchit-kms-verifier`, `mfaAuthenticated: true`; no `CreateAccessKey` success.
2. D2-6 outcomes under the verifier identity: `PutBucketVersioning`, `AssumeRole`, `CreateAccessKey`, `AddTags` → `AccessDenied`; `CreateAlias` → `NotFoundException`.
3. D2-5 read calls present under the verifier identity (IAM/S3/CloudTrail/KMS `List/Get/Describe` only).
4. `jose-admin` non-read-only events since 2026-09-08T02:40Z = exactly the C1 set (§4), and `readOnly: true` on every event in the §4 variance list.
5. Root: none. KMS: `list-keys` `[]`; no `CreateKey` event.

---

## 4. Variance review — extra `jose-admin` read-only console/background events

Reported by Device 2 in a broader `jose-admin` lookup: `DescribeEventAggregates`, `ListNotificationHubs`, `ListManagedNotificationEvents`, `GetAccountPlanState`, `DescribeRegions`, `GetAccountColor`.

| Event | Service | What it is | Security impact |
|---|---|---|---|
| `DescribeEventAggregates` | AWS Health | console dashboard health-event counter read | none (read) |
| `ListNotificationHubs`, `ListManagedNotificationEvents` | AWS User Notifications | console notification-bell reads | none (read) |
| `GetAccountPlanState` | AWS Free Tier | plan-state read (the same API the owner and coordinator used for V2) | none (read) |
| `DescribeRegions` | EC2 | region list read (console region selector) | none (read) |
| `GetAccountColor` | Console settings | account-colour preference read | none (read) |

**Classification: acceptable variance — console background/telemetry reads generated by the `jose-admin` console sessions used for C1-0b (TOTP enrolment), the C1-2 password step and the billing verification.** All six APIs are read-only by definition; none can create, modify or delete a resource, policy, key, trail or bucket. The reviewed D2-7 expectation ("event names are exactly the C1 setup/read calls") was written for CLI activity and omitted console-generated reads; that expectation is amended by this report to: *non-read-only (`readOnly: false`) `jose-admin` events must be exactly the C1 setup set; read-only events may include console background reads.* **Confirmation still required (D2-8 item 4):** CloudTrail shows `readOnly: true` and `errorCode` null for each of these events, and the `jose-admin` mutation list is exactly: `CreateRole`, `PutRolePolicy` (ceremony); `CreateUser`, `CreatePolicy`, `AttachUserPolicy` ×2, `CreateLoginProfile` (verifier; plus the failed `PutUserPolicy` LimitExceeded); `CreateUser`, `PutUserPolicy`, `CreateRole` (runtime); `CreateBucket`, `PutBucketPublicAccessBlock`, `PutBucketEncryption`, `PutBucketPolicy`, `PutObjectLockConfiguration`; `CreateTrail`, `PutEventSelectors`, `StartLogging`; `AssumeRole` ×2 (T1/T2); and the console-side `EnableMFADevice`/`CreateVirtualMFADevice` for `jose-admin-totp`. Anything else ⇒ report before closure.

---

## 5. No unauthorized mutation, no KMS key — evidence available this session

- Production DB (CLAUDE-OBSERVED 03:34:37Z): unchanged since 2026-09-08 — ledger 130, tip 120, 110–114 absent, 0 signing keys, guard absent, tickets 0, flags dark.
- KMS: Device 2 `list-keys` → `[]` (OWNER-RETURNED, 2026-09-09). Coordinator-side `list-keys` and the `CreateKey` event search: **NOT OBSERVED** this session (session expired); last coordinator read 2026-09-08 → `[]`.
- No secret, access key, migration, deployment, flag or configuration was touched by the coordinator at any time; the coordinator's only actions were failed read-only calls, one read-only production query, and repository writes.

---

## 6. Governance recording

- Execution record (`PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md`): D2-4 … D2-7 recorded as OWNER-RETURNED PASS with the timestamps/event IDs above; D2-8 recorded as **PENDING (coordinator session expired)**; the §4 variance recorded with its classification and the amended D2-7 expectation.
- **Not recorded** (conditions not yet met): M2 SATISFIED; M1 MODEL B COMPLETE; C1 PHASE-1 GATE CLOSED. These three lines are written only after D2-8 items 1–5 pass.
- **C2 has NOT begun** and requires the separate exact owner authorization **"AUTHORIZE PFA-18C CREATEKEY"**; per the confirmed ordering, C4 (migrations 110–114) precedes the trust-root DB insert and needs its own authorization.

## 7. Next smallest action

Owner, primary machine: `aws login --profile snatchit-admin` (Safari Private Window if needed), reply "done". The coordinator then runs the five D2-8 read-only checks in §3, and — if all pass — records M2 SATISFIED, M1 MODEL B COMPLETE, C1 PHASE-1 GATE CLOSED, and presents the C4/C2 packages for their separate authorizations.
