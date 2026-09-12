# PFA-18C — C6 DARK DEPLOY EXECUTION RECORD — **COMPLETE** (T+0 verified 2026-09-11T02:35Z; Mac 2 independent read-back PASS, owner-returned 2026-09-11; T+24 verified 2026-09-12T03:41–03:46Z)

**Authorization:** owner phrase **"AUTHORIZE PFA-18C DARK DEPLOY"** (2026-09-11), scoped to `PHASE2_PFA18C_C6_REVIEW_HANDOFF.md` rev 2 §5 steps C6-0…C6-4 from the isolated checkout `snatchit-c6deploy @ 562fda9` (source review at `b5bbcf621ce7900f0ca85a36257c73d1842da570`): one runtime access key, exactly six secrets, three functions; stop on any mismatch; zero-data preconditions maintained; production venue/staff/manifest/device/PIN creation outside this authorization (relayed to Claude A/D via the execution record). **Coordinator:** Claude B. **C18:** the owner ran every mutation on Mac 1; the coordinator read back; Mac 2 read back independently.
**Not done (standing prohibitions, verbatim):** "No test invocations, production signing, issuance/scanning activation, migration 121, or Model A changes are authorized." No secret value, key secret, ExternalId, nonce or signature was ever collected or printed.

## 1. Result

| Item | Value |
|---|---|
| Functions | 14 (11 legacy + 3 new). `credential-sign` id `633b416b-3c3d-46ef-9054-3964cc33ee0d` v1 `ezbr_sha256` `1318b969…` `verify_jwt` **true** (created 2026-09-11T02:34:48Z) · `door-manifest` `e1ab7ddd-08ba-4acd-8477-578becb54661` v1 `ab317c3d…` **true** · `door-session` `38258c87-fd2b-412e-98b2-b198ba682e9a` v1 `40666efb…` **false** (deployed `--no-verify-jwt`; device + hashed PIN + `DoorSession` bearer via `kernel.assert_door_session`; never calls KMS) |
| Legacy functions | ids, code hashes, `verify_jwt`, `updated_at` unchanged vs the F6 pre-deploy snapshot; `version` +1 each (platform secret-injection re-bundle, as after the password reset) |
| Secrets | **24 names** = 18 pre-existing (all preserved) + `AWS_ACCESS_KEY_ID, AWS_REGION, AWS_SECRET_ACCESS_KEY, KMS_PROVIDER, KMS_SIGNER_EXTERNAL_ID, KMS_SIGNER_ROLE_ARN` (E2 contract; values never displayed) |
| Runtime key | user `snatchit-credential-sign-runtime`: **exactly 1**, Active, created 2026-09-11T02:13:02Z, prefix `AKIAZQAR`; `CreateAccessKey` eventID `930208b0-3f16-420b-a596-4dbef0b459c9` by `jose-admin` (MFA true); admin/verifier users 0 keys |
| Runtime role | `SnatchIt-CredentialSign-Runtime` inline `pfa18c-runtime-sign`: Allow `kms:Sign` on D4 only; Deny statement present; no lifecycle/policy events since deploy |
| KMS D4 | `arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e` Enabled, `ECC_NIST_P256`, single-region; 0 `DisableKey`/`ScheduleKeyDeletion`/`PutKeyPolicy`/`UpdateAlias`/`CreateGrant` since 2026-09-11T02:00Z |
| CloudTrail | **0** `AssumeRole` into the runtime role (all 249 `AssumeRole` events 2026-09-11T02:00Z→2026-09-12T03:45Z are the `AWSServiceRoleForResourceExplorer` service-linked role); runtime-user events ever **0**; `Sign` total **3** unchanged (2026-09-09T06:20:13Z ceremony proof ok; 06:34:09Z verifier AccessDenied; 2026-09-10T17:11:30Z ceremony AccessDenied); 0 new `Sign` |
| Edge logs | **0** rows for the three slugs/function ids in any log source, 2026-09-11T02:30Z→2026-09-12T03:45Z (coverage present: thousands of edge/function/postgres rows per window) |
| Database | monitor `{status ok, fingerprint match, total 1, active_global 1, alerts []}`; `signing_key.invariant_alert` rows 0; counts tickets/door_session/door_manifest/scan_device/door_pin/staff_role/organization/catalog.venue/event/event_session = `0/0/0/0/0/0/0/0/0/0`; `feature.native_issuance_enabled` false, `feature.native_scanning_enabled` false; ledger 135 (tip `20260902003623`); `kernel.signing_key` `1|1`; `admin_audit` rows written during the window 0 |
| Monitor cron | job 27 `monitor-signing-key-invariants` `23 5 * * *` active; run 2026-09-11T05:23:00.214Z→05:23:00.302Z `succeeded` (`1 row`) — the only scheduled run inside the window |
| Config | `signing.expected_key_fingerprint` v2 = D5 `562b5e87…f64415`; `signing.expected_max_not_after` v1 null; `signing.monitor_enabled` v2 true |
| Local files | `~/pfa18c-local`: key file and env file unlinked after C6-3 (not securely erased; key revocable); placeholder artifacts (mode 600) and the C3 directory remain |

## 2. Step ledger

| Step | Who | Evidence | Status |
|---|---|---|---|
| F1–F10 final preflight | coordinator | 2026-09-11T02:0xZ all PASS (execution record session 27) | PASS |
| C6-0 checkout | owner (Mac 1) | HEAD `562fda9`, clean, four tree hashes (credential-sign `8acff3797f7d`, door-manifest `9cd883d0bb63`, door-session `910eef735250`, _shared `20fda4a1eae5`), project ref, CLI 2.115.0 | PASS |
| C6-1 access key | owner | `AKIAZQAR… Active 02:13:02Z`; CLAUDE-OBSERVED 02:14:44Z: 1 key; `CreateAccessKey` ×1 | PASS |
| C6-2 env file | owner | six keys, `format: PASS`, file outside any repo, mode 600 | PASS |
| C6-3 secrets | owner | first attempt halted safely (list output not JSON → collision step failed closed, no `secrets set`); corrected `--output json`; 24 names, 18 preserved (CLAUDE-OBSERVED 02:33:45Z) | PASS |
| C6-4 deploy | owner | three functions ACTIVE v1, total 14 (CLAUDE-OBSERVED 02:35:36–43Z) | PASS |
| T+0 read-backs | coordinator | §1 values at 02:35Z (functions, AWS, logs, DB) | PASS |
| Mac 2 read-back | founder B / owner (Dashboard Option A + `verifier` profile) | OWNER-RETURNED 2026-09-11: signing_key 1; checker ok/[]; counts 0/0/0/0/0/0; one Active runtime key; exact `kms:Sign` binding; key Enabled `ECC_NIST_P256` single-region; no runtime `AssumeRole`/`Sign`; only the expected `CreateAccessKey`; signed out | PASS |
| 24-hour window | — | 2026-09-11T02:35:36Z → 2026-09-12T02:35:36Z; no invocation, signing, flag, secret, AWS or migration change | quiet |
| T+24 read-backs | coordinator | 2026-09-12T03:41–03:43Z Supabase/DB/logs/cron (session 28 table); AWS first attempt 03:42Z blocked (admin session expired), owner re-authenticated, AWS reads 03:45:33–03:45:48Z — all §1 values reproduced | PASS |

## 3. Facts recorded
- Inactivity of the dark endpoints rests on: credential-sign → JWT + `getUser` + rate limit + `kernel.get_ticket_signing_context` owner gate (0 atoms; `issue_ticket_atoms` raises `feature_disabled`); door-manifest → JWT + `has_venue_role` + open episode (all counts 0; the scanning flag is **not** a DB control here); door-session → device + hashed PIN, never calls KMS. Zero-data preconditions are therefore a live control and must hold until C8.
- The platform re-bundles every function when secrets change (`version` +1, hash and `updated_at` unchanged) — expected on future `secrets set`; not a code change.
- Supabase unified-logs queries are capped at 24 h per call; the window was covered by two calls plus the pre-window T+0 query. Retention/sampling is platform-controlled; a request that never reaches the edge router is not observable there (CloudTrail `AssumeRole`/`Sign` is the independent second signal and stayed at 0).
- `AssumeRole` lookups are noisy with AWS service-linked-role activity (Resource Explorer); filter by `userIdentity.type != AWSService` and the runtime role ARN.
- The admin CLI profile uses a browser-based `aws login` session that expires; coordinator AWS read-backs need the owner to re-authenticate first (prohibited for the coordinator).

## 4. Rollback (not exercised)
`AUTHORIZE PFA-18C C6 ROLLBACK`, name-scoped, in order: `secrets unset` the six names → `functions delete` the three slugs → `iam delete-access-key` the C6-1 key; verify the 18/11 snapshots. KMS, roles, trust, DB row, monitor untouched.

## 5. Next (each separately authorized)
See `PHASE2_PFA18C_FINAL_COORDINATOR_HANDOFF.md`: migration 121 (after Claude A's integration; `AUTHORIZE PFA-18C MIGRATION 121`), M5 ruling, Model A, M5-live (T3), C8 issuance flip, migration 122 (086↔112/113) before the scanning flip, live commerce checks; weekly dark posture reads (§2.7 of the remaining-path document) until T3.
