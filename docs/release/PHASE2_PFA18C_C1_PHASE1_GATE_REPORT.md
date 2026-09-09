# PFA-18C — C1 PHASE-1 GATE REPORT (D2-4 … D2-8 corroboration and governance recording)

**Date:** 2026-09-09 (coordinator session, Claude A only; **revision 3 — gate closed** after the Device-2 remediation R-M2) · **Scope:** coordinator verification + governance recording. **No mutation of any kind** (no AWS, production DB, issuance, scanning, payments, fees, Connect, transfers, refunds, payouts, migration 110–114, or secret rotation). **C2 has NOT begun.** PFA-18A remains parked.
**Artifact pin for Device 2:** `c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd` · **Handoff:** `docs/release/PFA18C_DEVICE2_RETRIEVAL_HANDOFF.md` · **Procedure:** packet §5a′ · **Prior revisions:** `570899cf…` (D2-8 blocked, expired coordinator session), `ea9aff05…` (D2-8 corroborated; M2 blocked on verifier MFA posture; remediation R-M2 issued).

Evidence classes: **OWNER-RETURNED** (Device-2 operator / owner statements), **CLAUDE-OBSERVED** (coordinator read-only reads, 2026-09-09T04:02–04:03Z unless stated).

---

## 1. Gate decision — CLOSED

| Item | Status |
|---|---|
| D2-4 retrieval integrity | **PASS** — OWNER-RETURNED (10/10 from the pinned commit; no C2-only files); digests CLAUDE-OBSERVED (session 11). Unchanged by the remediation. |
| D2-5 independent read-back (rerun under the MFA session) | **PASS** — OWNER-RETURNED; the rerun's read calls are CLAUDE-OBSERVED under the verifier identity with `mfaAuthenticated: "true"` (§3) |
| D2-6 verifier refusal probes (rerun) | **PASS** — OWNER-RETURNED and CLAUDE-OBSERVED in CloudTrail (§3): `PutBucketVersioning`, `AssumeRole`, `CreateAccessKey`, `AddTags` → `AccessDenied`; `CreateAlias` → `NotFoundException` (non-discriminating, as classified) |
| D2-7 CloudTrail read-back (rerun) + final `kms list-keys` `[]` | **PASS** — OWNER-RETURNED; lookups and `ListKeys` CLAUDE-OBSERVED under the verifier identity |
| **Verifier authentication / MFA posture (handoff §F.2)** | **PASS (remediated).** New `ConsoleLogin` for `snatchit-kms-verifier` with **`MFAUsed: Yes`**, `MFAIdentifier = arn:aws:iam::652872010073:u2f/user/snatchit-kms-verifier/verifier-device2-passkey-6UJX6DTACNAOFIWOQQHF7RNEOA` (us-east-2, 03:51:35Z and 03:55:08Z, preceded by `CheckMfa`); new `aws login` 03:55:45Z; **84/84** subsequent verifier events in us-east-1 carry **`mfaAuthenticated: "true"`**; **0 successful verifier mutations** |
| `jose-admin` mutation review | **PASS** — unchanged from revision 2 (non-read-only events since 2026-09-08T02:40Z = the authorized C1 set); no non-read-only `jose-admin` event since 2026-09-09T03:46Z |
| Root / KMS safety | **PASS** — root since 2026-09-08T02:40Z `[]`; `kms list-keys` `[]`; no `CreateKey`/`PutKeyPolicy`/`ScheduleKeyDeletion`/`DisableKey` since 2026-09-08T00:00Z; the out-of-window root password-recovery observation (2026-09-08T01:17–01:18Z) stands as recorded in revision 2 for owner acknowledgement |
| Production darkness | **PASS** — unchanged (§5) |
| **M2** | **SATISFIED** |
| **M1 (Model B)** | **COMPLETE** |
| **C1 PHASE-1 GATE** | **CLOSED** |
| **C2** | **NOT BEGUN.** Still requires the separate exact owner authorization **"AUTHORIZE PFA-18C CREATEKEY"** — this report is not that authorization. C4 (migrations 110–114) precedes the trust-root DB insert and needs its own authorization; not executed. |

---

## 2. Remediation R-M2 — as executed (OWNER-RETURNED) and corroborated (CLAUDE-OBSERVED)

OWNER-RETURNED: Device 2 ran `aws logout --profile verifier`, signed out of the console, signed in again as the verifier with password + the enrolled passkey (`verifier-device2-passkey`), ran `aws login --profile verifier --region us-east-1`, obtained `Account 652872010073 / Arn arn:aws:iam::652872010073:user/snatchit-kms-verifier`, then re-ran D2-6, D2-5 and D2-7 and the final `kms list-keys` (`[]`).

CLAUDE-OBSERVED (event history, sanitized; no credentials/OTPs are ever logged):
- us-east-2: `CheckMfa` 03:50:59Z, 03:51:25Z → **`ConsoleLogin` 03:51:35Z, `MFAUsed: Yes`, `MFAIdentifier` = the verifier's `u2f/…verifier-device2-passkey-…` ARN, Success** (`96ff9126…`); `CheckMfa` 03:54:30Z → **`ConsoleLogin` 03:55:08Z, `MFAUsed: Yes`, same identifier, Success** (`64488a49…`).
- us-east-1: `AuthorizeOAuth2Access` + `CreateOAuth2Token` 03:55:45Z (`62f3281b…`, `e2d682a3…`), session `creationDate 2026-09-09T03:55:08Z`, `mfaAuthenticated: "true"`; `GetCallerIdentity` 03:56:06Z (`df3c879f…`), `mfaAuthenticated: "true"`.
- Posture distribution after 03:46Z: **`mfaAuthenticated "true"`: 84 events; `"false"`: 0; successful mutations: 0.** (Console background reads at 03:52 and 03:55 are `readOnly: true` and denied for out-of-policy services, as before.)

---

## 3. D2-8 corroboration of the rerun (CLAUDE-OBSERVED, verifier identity, us-east-1, all `mfaAuthenticated: "true"`)

**D2-6:** `PutBucketVersioning` 03:56:53Z → `AccessDenied` (`f692cf37…`); `AssumeRole` (into `SnatchIt-KMS-Ceremony`) 03:57:20Z → `AccessDenied` (`2f6579df…`); `CreateAccessKey` 03:57:43Z → `AccessDenied` (`f390806f…`); `AddTags` 03:58:44Z → `AccessDenied` (`a5fe0f75…`); `CreateAlias` 03:59:45Z → `NotFoundException` (`c9b23820…`, non-discriminating; P3′ at C2). None succeeded; no resource changed.

**D2-5:** 03:59:56–04:00:10Z — `GetRole` ×4, `GetRolePolicy`, `GetPolicyVersion`, `ListAttachedRolePolicies` ×2, `ListAttachedUserPolicies`, `ListAccessKeys` ×2, `ListMFADevices`, `GetUserPolicy`, `ListRolePolicies`; S3 `GetBucketPolicy`, `GetBucketPublicAccessBlock`, `GetBucketEncryption`, `GetBucketObjectLockConfiguration`, `GetBucketVersioning`; CloudTrail `DescribeTrails`, `GetEventSelectors`, `GetTrailStatus` — all `readOnly: true`, no errors. **Inside the expected envelope; nothing else.**

**D2-7 + final check:** `LookupEvents` ×7 04:00:45–04:00:49Z; `kms ListKeys` 04:01:00Z (`7cebef0d…`).

**Verifier state (04:03Z):** access keys `[]`; attachments exactly `SnatchIt-KMS-Verifier-ReadOnly` + `SignInLocalDevelopmentAccess`; inline `[]`; groups `[]`; MFA = the single passkey; policy default `v1`, `AttachmentCount 1`, unchanged since 2026-09-08T03:18:03Z. **No unexpected privilege change.**

---

## 4. Root / KMS / inventory (CLAUDE-OBSERVED 04:03Z)

Root since 2026-09-08T02:40Z: `[]`. KMS keys: `[]`; no `CreateKey`, `PutKeyPolicy`, `ScheduleKeyDeletion`, `DisableKey` events since 2026-09-08T00:00Z. `jose-admin`: no non-read-only events since 03:46Z. Inventory unchanged: roles `SnatchIt-KMS-Ceremony`, `SnatchIt-CredentialSign-Runtime` (no permissions); users `jose-admin`, `snatchit-kms-verifier`, `snatchit-credential-sign-runtime` (access keys `[]` on all three); local policy `SnatchIt-KMS-Verifier-ReadOnly`; bucket `snatchit-audit-652872010073`; trail `snatchit-audit-trail` logging, no delivery error.

## 5. Production darkness (CLAUDE-OBSERVED 2026-09-09T04:03:13Z, read-only)

ledger 130 · numeric tip 120 · 110–114 absent · `kernel.signing_key` **0** · guard absent · tickets 0 · door sessions 0 · issuance `false` · scanning `false` · monitor `false` · fingerprint `null` · max_not_after `null`. No trust-root bootstrap occurred.

## 6. Governance recording

- Execution record session 14: the remediated Device-2 session with timestamps/event IDs and provenance; **M2 SATISFIED · M1 MODEL B COMPLETE · C1 PHASE-1 GATE CLOSED** formally recorded.
- **C2 NOT BEGUN.** CreateKey requires the separate exact owner authorization **"AUTHORIZE PFA-18C CREATEKEY"**. Confirmed ordering preserved: **C4 (migrations 110–114, "AUTHORIZE PFA-18C MIGRATIONS 110-114") before the trust-root DB insert (C3)**; neither executed.
- Residuals carried forward: P3′ (KMS-lifecycle deny live test) at C2; Model A required before T3; C7/M5 pending governance clarification (packet §5d); root password-recovery observation of 2026-09-08T01:17–01:18Z awaiting owner acknowledgement; no account password policy (hardening note, out of scope).

## 7. Next stages (each needs its own authorization; nothing implied by this closure)

1. **C4** — apply migrations 110–114 from a checkout containing 115–120 (candidate `admin/operating-console @ 2459bdc`; re-verify on the day), dry run listing exactly 110–114 — "AUTHORIZE PFA-18C MIGRATIONS 110-114".
2. **C2** — CreateKey + §5.3 binding proof + P3′ — "AUTHORIZE PFA-18C CREATEKEY".
3. C3, C5, C6 per the packet; C7 pending clarification; Model A before T3.
