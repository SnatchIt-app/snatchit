# PFA-18C — EXECUTION READINESS PACKET (C1 in progress; later stages prepared)

**Date:** 2026-09-08 (sessions 8–11) · **Branch:** `feature/venue-native-and-product-v2` · **Reviewed tree:** `6372538` (branch tip = `origin`; CI green) · **Coordinator:** Claude A (read-back only; C18 unchanged)
**Authorization in force (2026-09-08):** **PFA-18C M1/M2/M3 SETUP within the reviewed C1 package (§5)** — R1–R4 confirmed by the owner (below); routine setup choices delegated to the main engineer. **Not authorized:** Organizations/account creation, `CreateKey`, the signing-key DB insert, production migration application, production secrets, deployment, issuance/scanning activation. The owner executes every mutation under the ratified single-founder procedure with independent verification from the separate clean device (M2).

Evidence classes: **CLAUDE-OBSERVED**, **OWNER-RETURNED**, **OFFICIAL-DOC**, **REHEARSAL**, **NOT OBSERVED**.

---

## 0. State (fresh)

| Item | Value | Class |
|---|---|---|
| Repository | `6372538` = `origin/feature/venue-native-and-product-v2`; CI green; no PFA-18C document, artifact, migration or edge change since `1f3fc19`; `admin/operating-console` = **`2459bdc`** (docs addendum; `supabase/` **identical** to CI-green `ab3e17f`; CI green on `2459bdc`); PR #55 OPEN/CLEAN at `2459bdc` | CLAUDE-OBSERVED 02:1xZ |
| Pre-existing user edits | untouched: `M docs/release/PHASE2_PRODUCTION_KMS_SIGNING_CEREMONY_EXECUTION.md`, `?? docs/phase2/TICKETS_READ_CONTRACT_CORE_COORDINATION.md` | CLAUDE-OBSERVED |
| AWS identity / plan / summary | `arn:aws:iam::652872010073:user/jose-admin`; **PAID · ACTIVE · 100.0 USD credits**; `AccountAccessKeysPresent 0 · AccountMFAEnabled 1` | CLAUDE-OBSERVED 01:50Z (corroborates OWNER-RETURNED) |
| C1-0a baseline | trails `[]` · buckets `[]` · `SnatchIt*` roles `[]` · users `["jose-admin"]` · KMS keys `[]` · jose-admin access keys `[]` · Organizations not in use · `snatchit-audit-652872010073` free (404) | CLAUDE-OBSERVED 01:51Z |
| `jose-admin` MFA | **only the passkey** `u2f/user/jose-admin/jose-admin-touchid-…` (enabled 2026-09-05) — **C1-0b TOTP enrolment pending** | CLAUDE-OBSERVED 02:1xZ |
| Production DB | ledger **130**, numeric tip **120**, present `115…120`, **110–114 absent**, `signing_key` **0**, guard absent, tickets 0, flags dark (issuance/scanning/monitor `false`, fingerprint `null`) | CLAUDE-OBSERVED 02:14:51Z |
| Native edges / branch record | none deployed; `git_branch ""`; owner visual OFF 2026-09-07 | CLAUDE-OBSERVED (session 8) |

---

## 1. Billing and identity — VERIFIED (2026-09-08T01:50Z)

`PAID / ACTIVE / 100.0 USD remaining`; identity `jose-admin`; root 0 keys + MFA. Usage-based billing; no $100 purchase; no recurring $100 budget. Dark cost ≈ $1.06–1.15/month (§3 of the prior revision; unchanged).

---

## 2. Decisions — CONFIRMED (2026-09-08) and the R5 correction

| # | Decision | Status |
|---|---|---|
| R1 | Region **`us-east-1`** (key, trail home region, every ARN) | **confirmed** |
| R2 | Names exactly as reviewed at `6372538`: bucket `snatchit-audit-652872010073` · trail `snatchit-audit-trail` · role `SnatchIt-KMS-Ceremony` (session `pfa18c-ceremony`) · user `snatchit-kms-verifier` · user `snatchit-credential-sign-runtime` · role `SnatchIt-CredentialSign-Runtime` · key tag `snatchit:purpose=ticket-signing` · inline policies `pfa18c-ceremony`, `pfa18c-verifier-readonly`, `pfa18c-runtime-assume-only`, `pfa18c-runtime-sign` | **confirmed** |
| D2 | Object-Lock **COMPLIANCE, 3 years** (integer in `m1_object_lock_configuration.json`) | **confirmed** |
| D3 | **O1**: runtime user authenticates STS only → assumes the restricted role → temporary role credentials sign; never signs directly; no fallback | **confirmed** |
| R3 | `652872010073` = intended future **workload/signing member**; **Model B temporary, dark bootstrap only**; **Model A operational before T3** under the canonical ratification | **confirmed** |
| R4 | Enrol an **additional TOTP authenticator on `jose-admin`**; ceremony `AssumeRole` uses `--serial-number`/`--token-code`; **keep the passkey**; **never remove or weaken the MFA trust condition** | **confirmed** |
| C4↔C3 | Apply **110–114 before** the production signing-key row, under separate production-migration authorization | **confirmed** |
| **R5 — CORRECTED** | **No pre-T3 exception exists.** The prior R5/D7 text proposing that "a throwaway credential on a non-saleable test event" be treated as a pre-issuance test, and any wording attributing such a ruling to the owner, is **withdrawn**. Canonical rule (PFA doc, maturity trigger): "**(T3) HARD BACKSTOP — the first of {a production credential is signed, native issuance is enabled}, because from that instant the trust root is load-bearing for money/tickets.**" A test event being non-saleable does not change the meaning of "a production credential is signed". **Distinction preserved:** the §5.3 **KMS binding proof** signs a Device-2-generated random *challenge* (`kms sign` over a nonce) — required by the bootstrap and named in the ratified signature (item 3) — and is **not** a production ticket credential; signing a *credential* through the deployed edge with the production key **is** T3. **C7/M5 remains PENDING** until its procedure satisfies the existing governance (§5d). No direct custody/ticket-row insert, no temporary issuance flip, no guard disable, no other bypass to obtain a test atom. | **corrected 2026-09-08** |

---

## 4. Controls status — unchanged from the prior revision (artifact sha256 at `6372538`; Years 3 filled; F1/F3 in force)

Effective permissions recheck stands: ceremony (constrained CreateKey, tag-scoped read/PutKeyPolicy, proof Sign; denies on IAM/STS/Org/audit/lifecycle), verifier (read-only + own-user MFA/password), runtime user (`sts:AssumeRole` on the runtime role only; `kms:*` denied), runtime role (trust only until C2; then Sign on the exact ARN only). No principal ever receives `kms:Sign` on `key/*`.

---

## 5. C1 package — AUTHORIZED; execution log (updated as steps complete)

Conventions unchanged (owner runs on the primary machine as `jose-admin`; `--profile snatchit-admin --region us-east-1` on every command; `ART=docs/release/pfa18c_artifacts`; ≥ 60 s after creating a principal before naming it in a policy; paste OUTPUT only; never passwords, QR codes, seeds, OTPs, ExternalId, keys, tokens, raw `assume-role` output). The coordinator may run **read-only** read-backs with the owner's `snatchit-admin` profile (as in C1-0a); every mutation is owner-executed.

| Step | Status | Evidence / notes |
|---|---|---|
| C1-0a preflight (read-only) | **DONE 01:51Z** | §0 |
| C1-0b TOTP enrolment on `jose-admin` | **DONE 02:38:37Z** (owner-returned; corroborated read-only) | `arn:aws:iam::652872010073:mfa/jose-admin-totp` + the passkey; trust condition tested at C1-9 |
| C1-1 role `SnatchIt-KMS-Ceremony` | **VERIFIED 02:42:58Z** | trust + inline policy identical to artifacts; only `pfa18c-ceremony`; no managed attachments |
| C1-2 user `snatchit-kms-verifier` | **VERIFIED 03:36:38Z** (policy packaged as customer-managed after the inline-quota refusal, F7) | `SnatchIt-KMS-Verifier-ReadOnly` v1 (default, only version) **identical** to `m2_verifier_policy.json`; attached = that ARN + `SignInLocalDevelopmentAccess` only; inline `[]`; groups `[]`; access keys `[]`; login profile present (03:32:13Z); MFA `[]` — enrolled from Device 2 at C1-10 (M2 still pending) |
| C1-3 runtime user `snatchit-credential-sign-runtime` + role `SnatchIt-CredentialSign-Runtime` (trust only) | **VERIFIED 03:53:31Z** | user policy `pfa18c-runtime-assume-only` identical to artifact; no attached policies/groups/**access keys**/login; role trust: principal = the runtime user only, action `sts:AssumeRole` only, condition operator `StringEquals`, condition key `sts:ExternalId` only (value redacted; length 64), structure identical to the artifact; role has **no** permissions policies; `jose-admin` `assume-role` → **AccessDenied** |
| C1-4 bucket `snatchit-audit-652872010073` (Object Lock at creation) | **VERIFIED 03:41:07Z** | `ObjectLockEnabled Enabled`, no rule yet; versioning `Enabled`; location us-east-1; no policy; no objects |
| C1-5 PAB ×4 + SSE-S3 | **VERIFIED 03:41:07Z** | all four `true`; `AES256`, `BucketKeyEnabled false`, no KMS key (S3 also reports SSE-C blocked by default) |
| C1-6 bucket policy | **VERIFIED 04:0xZ** | live policy equals the artifact after normalization (objects key-sorted; scalar arrays sorted — the only raw difference is S3 reordering the four-ARN `Principal.AWS` array); statements: CloudTrail `GetBucketAcl` + `PutObject` (`AWSLogs/652872010073/*`, `bucket-owner-full-control`) both conditioned on `aws:SourceArn` = the trail; `DenyInsecureTransport` (`aws:SecureTransport=false`, `s3:*`, Principal `*`); `DenyCeremonyAndVerifierFromMutatingAuditEvidence` — all four principals present, 17 mutation actions, bucket + objects |
| C1-7 Object-Lock default retention | **VERIFIED 04:01:20Z** | `ObjectLockEnabled Enabled`, `Rule.DefaultRetention = {Mode: COMPLIANCE, Years: 3}`; zero object versions / delete markers (rule still editable, bucket still deletable until the first object) |
| C1-8 trail `snatchit-audit-trail` | **VERIFIED 04:08:09Z** (first log file delivered 04:07:28Z, COMPLIANCE-locked until 2029-09-08T04:07:28Z, AES256) | `describe-trails`: exact name/bucket, home us-east-1, multi-region, global events, validation on, `KmsKeyId null`, only trail; selectors `All` / management on / exclusions `[]`; `IsLogging true` since 04:02:41Z; first objects locked `COMPLIANCE` until **2029-09-08** (verified on the prefix markers); first log-file delivery being polled |
| C1-9 MFA test + deny-set proof | **PARTIAL 04:29Z** — T1 (no explicit MFA) **succeeded** (login session is MFA-authenticated per CloudTrail; recorded as such, not as a denial pass); T2 (serial+token) succeeded with the serial logged; live trust identical; simulator: every deny-set action explicitDeny, CreateKey/Sign scoped as reviewed | probes: positive controls PASS; P1 PASS (explicit identity deny); P2 PASS (explicit bucket-policy deny); **P3 INCONCLUSIVE** (`NotFoundException` on a non-existent key — resource validation answered; deny neither proven nor disproven; discriminating test P3′ moved to C2 with the real key); P4/P5 pending |
| C1-10 Device 2 login/attestation/read-back | **VERIFIED — M2 SATISFIED 2026-09-09T04:03Z** | D2-4 10/10 at `c4f562d…`; D2-5/D2-6/D2-7 rerun under an MFA-authenticated verifier session (ConsoleLogin `MFAUsed Yes` with the Device-2 passkey; 84/84 events `mfaAuthenticated true`; 0 successful mutations); coordinator corroboration in the gate report rev 3. **M1 (Model B) COMPLETE · C1 PHASE-1 GATE CLOSED · C2 NOT BEGUN ("AUTHORIZE PFA-18C CREATEKEY" still required; C4 first).** |

**C1-0b — owner console procedure (no secret ever leaves the owner's screen):** IAM console → Users → `jose-admin` → **Security credentials** → **Multi-factor authentication (MFA)** → **Assign MFA device** → Device name e.g. `jose-admin-totp` → **Authenticator app** → Next → scan the QR code with the authenticator app on the owner's phone (or "Show secret key" — never pasted anywhere) → enter two consecutive codes → **Add MFA**. The existing passkey entry stays listed. Read-back (coordinator or owner, read-only): `aws iam list-mfa-devices --profile snatchit-admin --region us-east-1 --user-name jose-admin --query 'MFADevices[].{Serial:SerialNumber,Enabled:EnableDate}'` → two devices; the new **SERIAL** = `arn:aws:iam::652872010073:mfa/<name>`. Nothing else is required from the owner for this step.

The C1 step table (C1-1…C1-10 with purpose, prerequisites, commands, read-backs, refusal tests, abort conditions, cleanup limits) is unchanged from `6372538` §5a and is not repeated here; it remains the reviewed reference.

**C1-2 packaging correction (dated 2026-09-08T03:12Z, within scope — permissions unchanged):** IAM rejects `PutUserPolicy` for `m2_verifier_policy.json` (`LimitExceeded: maximum user inline policy size 2048`; the artifact is 2544 characters compacted). The **exact same document** is applied as the customer-managed policy **`SnatchIt-KMS-Verifier-ReadOnly`** (`arn:aws:iam::652872010073:policy/SnatchIt-KMS-Verifier-ReadOnly`; managed-policy size quota 6144) and attached to the user. Nothing is removed, broadened or split. Revised C1-2: `aws iam create-policy --policy-name SnatchIt-KMS-Verifier-ReadOnly --policy-document file://$ART/m2_verifier_policy.json` → `attach-user-policy` (that ARN) → `attach-user-policy` `SignInLocalDevelopmentAccess` → console password. **Read-backs:** `get-policy` (`AttachmentCount 1`, `DefaultVersionId v1`) and `get-policy-version --version-id v1 --query PolicyVersion.Document | jq -S .` diff vs the artifact → empty; `list-attached-user-policies` → exactly the two ARNs; `list-user-policies` → `[]`; `list-groups-for-user` → `[]`; `list-access-keys` → `[]`; `get-login-profile` → exists. **Device-2 read-back (C1-10)** uses `iam get-policy` + `get-policy-version` (already allowed by `VerifierIamDenySetReadBack`). **Cleanup:** `detach-user-policy` ×2, `delete-policy` (after detaching), `delete-login-profile`, `delete-user`. The bucket policy and both key policies name the user ARN, which is unchanged.

### 5a′. C1-10 — Device-2 (M2) verifier setup and independent read-back — PREPARED (runs only after the owner confirms Device 2)

**Device-2 requirements (readiness §6, ratification M2):** physically separate hardware from the ceremony host (not a second OS user on the same Mac, not CloudShell), clean — no shared shell, files, `~/.aws`, browser profile, clipboard or account session with the ceremony host; needs a browser, AWS CLI v2 ≥ 2.32.0, `jq`, `openssl`, `git` (or a browser download) — nothing is copied from the ceremony host.

**MFA enrolment method for `snatchit-kms-verifier` (policy-checked):** **passkey or security key, self-enrolled in the console from Device 2** (Touch ID/Face ID/Windows Hello, or a hardware key). The verifier policy allows `iam:EnableMFADevice`, `iam:GetUser`, `iam:ListMFADevices`, `iam:ResyncMFADevice` on its own user — the exact set the IAM guide lists for managing one's own passkey; it explicitly denies `iam:CreateVirtualMFADevice`, so an **authenticator-app device cannot be self-enrolled** (an admin-seeded virtual MFA would route the seed through the primary machine and is not used). `DeactivateMFADevice` is not granted (replacement is an admin act).

| Step | Device | Action | Read-back / expected |
|---|---|---|---|
| D2-0 | owner | confirm Device 2 meets the requirements; note its type (e.g. separate Mac/iPhone/iPad/PC) — recorded, not verified remotely | — |
| D2-1 | Device 2 (browser) | sign in at `https://652872010073.signin.aws.amazon.com/console` as IAM user `snatchit-kms-verifier` with the password the owner set at C1-2 (typed on Device 2 only) | console loads |
| D2-2 | Device 2 (browser) | IAM → Users → `snatchit-kms-verifier` → Security credentials → Assign MFA device → name `verifier-device2-passkey` → **Passkey or Security Key** → complete the platform prompt | *(coordinator, read-only)* `aws iam list-mfa-devices --user-name snatchit-kms-verifier` → one `u2f/user/snatchit-kms-verifier/…` entry |
| D2-3 | Device 2 (terminal) | `aws login --profile verifier` (region us-east-1; sign in as the verifier with the passkey in Device 2's browser); then `aws sts get-caller-identity --profile verifier --no-cli-pager` | `Arn` = `arn:aws:iam::652872010073:user/snatchit-kms-verifier` |
| D2-4 | Device 2 | obtain the reviewed artifacts **independently** (GitHub, commit `f8836e5` or later on `feature/venue-native-and-product-v2`, path `docs/release/pfa18c_artifacts/`) and verify sha256: `m1_ceremony_role_trust.json 89540f61…`, `m1_ceremony_role_policy.json 1fddd53b…`, `m2_verifier_policy.json 3082cc74…`, `m3_runtime_user_policy.json a1cb8644…`, `m1_audit_bucket_policy.json 76addba3…`, `m1_object_lock_configuration.json 9a4c5a8d…` | hashes match the execution record |
| D2-5 | Device 2 | **read-back + diff** (all `--profile verifier --region us-east-1`): `iam get-role SnatchIt-KMS-Ceremony` (trust diff; MaxSessionDuration 3600), `iam get-role-policy … pfa18c-ceremony` (diff), `iam list-attached-role-policies` (none); `iam get-policy` + `get-policy-version v1` for `SnatchIt-KMS-Verifier-ReadOnly` (diff), `iam list-attached-user-policies snatchit-kms-verifier` (exactly 2), `list-access-keys` (none); `iam get-user-policy snatchit-credential-sign-runtime pfa18c-runtime-assume-only` (diff); `iam get-role SnatchIt-CredentialSign-Runtime` (trust: principal = runtime user, action AssumeRole, condition key `sts:ExternalId` only — value never printed), `list-role-policies` (none), `list-access-keys snatchit-credential-sign-runtime` (none); `s3api get-bucket-policy` (diff, arrays order-insensitive), `get-public-access-block` (4×true), `get-bucket-encryption` (AES256), `get-object-lock-configuration` (COMPLIANCE, 3), `get-bucket-versioning` (Enabled); `cloudtrail describe-trails` (multi-region, validation, global events, us-east-1, no KmsKeyId), `get-trail-status` (IsLogging), `get-event-selectors` (All, mgmt, exclusions []) | every diff empty; every value as recorded |
| D2-6 | Device 2 | refusal probes as the verifier (effects if wrongly allowed in brackets): `kms create-alias --alias-name alias/pfa18c-probe --target-key-id 00000000-0000-0000-0000-000000000000` [NotFound is possible — non-discriminating, as learned at P3; record as such]; `s3api put-bucket-versioning … Status=Enabled` [no-op] → AccessDenied; `sts assume-role` into the ceremony role [none] → AccessDenied; `iam create-access-key --user-name snatchit-kms-verifier` [would create a key — explicitDeny simulated] → AccessDenied; `cloudtrail add-tags` on the trail [a tag] → AccessDenied | all denied |
| D2-7 | Device 2 | `cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=jose-admin --start-time 2026-09-08T02:40:00Z` → event names are exactly the C1 setup/read calls; `AttributeValue=root` for the window → none; also confirm the T1/T2 `AssumeRole` events and the probe `AccessDenied` events are visible from Device 2 | matches the execution record |
| D2-8 | coordinator | corroborate D2-2/D2-3/D2-6 from CloudTrail (verifier identity, `mfaAuthenticated`), record M2 satisfied and **M1 complete**; PHASE-1 GATE | — |

Not part of C1-10: any KMS key, signing, secrets, migrations, deployment. The verifier never receives an access key.

### 5b. Later stages — packages (each needs its own authorization)

| Stage | Package status |
|---|---|
| **C4 — migrations 110–114** | **APPLIED 2026-09-09T04:22:52Z and VERIFIED** (authorization "AUTHORIZE PFA-18C MIGRATIONS 110-114"; commit `562fda9…`; ledger 130→135, tip 120; guard + recovery live; census 153/87/32; darkness intact). Record: `PHASE2_PFA18C_C4_EXECUTION_RECORD.md`. |
| **C2 — CreateKey + §5.3 binding proof** ("AUTHORIZE PFA-18C CREATEKEY") | **+ P3′ (added 2026-09-08):** immediately after CreateKey, as the ceremony role: `kms create-alias --alias-name alias/pfa18c-probe --target-key-id <D4>` → expected `AccessDenied` (explicit identity deny; if wrongly allowed: one removable alias, no lifecycle effect) and `kms verify` with the proof signature → expected `AccessDenied`. Otherwise unchanged from `6372538` §5b (ceremony role session; v1 policy with F1; Device 2 `get-public-key` → D5; challenge signed by the ceremony role, verified by Device 2 with its own exported key; altered-message + wrong-key FAIL; v2 policy; exact-ARN runtime policy; ceremony `Sign` → AccessDenied). **The challenge signature is not a production credential (R5).** |
| **C3 — trust-root DB commit** | unchanged (§6.1 artifact verbatim, §6.2 invocation, four NOTICEs + COMMIT, §7 read-backs; after C4). |
| **C5 — monitor arming** | unchanged. |
| **C6 — O1 secrets + dark deploy** | unchanged (access key created **only at C6**, secret to a local file; `supabase secrets set --env-file`; deploy `credential-sign` / `door-manifest` with verify_jwt true, `door-session --no-verify-jwt`; no call made). |
| **C7 — M5** | **PENDING governance clarification — see §5d.** Not executable as written. |
| **Model A** | package prepared — §5c; **not authorized**. |

### 5c. Model A package — organization + audit account (prepared; account/Organizations creation remains separately authorized)

**Responsibilities.**

| Account | Purpose | Holds | Never holds |
|---|---|---|---|
| **Management** (NEW; e.g. `snatchit-org-mgmt`, own e-mail alias, Paid plan at sign-up, root passkey + TOTP, **0 access keys**) | Organizations + SCP administration; owner of the **organization trail** | one IAM admin user with MFA for org administration (or root-only, MFA) | workloads, KMS keys, application resources, ceremony/runtime principals — **SCPs do not bind this account** (OFFICIAL-DOC) |
| **Audit member** (NEW via `organizations create-account`, e.g. `snatchit-audit`) | durable evidence plane: org-trail destination bucket `snatchit-org-audit-<AUDIT_ACCOUNT_ID>` (Object Lock COMPLIANCE — **retention years: owner decision, propose 3**, SSE-S3, PAB, TLS-only, policy `model_a/org_audit_bucket_policy.json`); Device-2 read-only principal `snatchit-org-verifier` (m2 policy shape, cross-account read of the trail) ; optional CloudTrail delegated administrator | the audit bucket, the verifier | workload principals, keys |
| **Workload member** = **`652872010073`** (existing; invited) | production key, ceremony/verifier/runtime principals, the Model-B trail + bucket (kept; its evidence stays locked 3 years) | everything created in C1/C2 | org administration |

**Structure & policies.** `create-organization --feature-set ALL`; enable the SCP policy type on the root; OUs `Security` (audit) and `Workloads` (652872010073); SCP `SnatchIt-WorkloadGuardrails` = `model_a/scp_workload_guardrails.json` attached to **Workloads** (denies CloudTrail Stop/Delete/Update/selectors; mutation of both audit buckets; `kms:ScheduleKeyDeletion`/`DeleteImportedKeyMaterial` on the exact production key — `DisableKey` **stays allowed** as the PFA-18B emergency path; `organizations:LeaveOrganization`); `FullAWSAccess` remains attached. Org trail in the management account: `create-trail --name snatchit-org-trail --s3-bucket-name snatchit-org-audit-<AUDIT_ACCOUNT_ID> --is-organization-trail --is-multi-region-trail --enable-log-file-validation`, selectors `ReadWriteType All`, management events, no exclusions; `start-logging`.

**Execution order (owner; each its own step):** M-A1 create the management account (sign-up; Paid; root MFA) → M-A2 `create-organization` → M-A3 `create-account` (audit) → M-A4 in the audit account: bucket (Object Lock at creation) + PAB + SSE-S3 + retention rule + policy (with the org id and management account id filled) → M-A5 `invite-account-to-organization` (652872010073) → M-A6 from `652872010073` as `jose-admin`: `accept-handshake` (**consequence: consolidated billing — the management account becomes the payer; Free-Tier credit behaviour on join is not documented — read `get-account-plan-state` + Billing → Credits before and after**) → M-A7 OUs + move accounts → M-A8 enable SCPs, create + attach `SnatchIt-WorkloadGuardrails` → M-A9 org trail + selectors + start → M-A10 verification (below) → M-A11 Device 2 read-back from the **audit** account.

**Verification / refusal tests.** `describe-organization` → `FeatureSet ALL`; `list-accounts` → 3 × ACTIVE; `list-policies-for-target --target-id <Workloads OU>` → the guardrail SCP; in `652872010073`: `cloudtrail describe-trails --include-shadow-trails` → the org trail shadow (`IsOrganizationTrail true`); refusal probes as `jose-admin` (AdministratorAccess, in the member): `cloudtrail stop-logging --name <org trail ARN>` → **AccessDenied (SCP)**; `s3api put-object` into the org audit bucket → AccessDenied; `kms schedule-key-deletion --key-id <D4> --pending-window-in-days 30` → **AccessDenied (SCP)** — run this probe only while dark (before C7/T3) with `kms cancel-key-deletion --key-id <D4>` + `kms enable-key --key-id <D4>` pre-staged as the recovery if the SCP were misattached; `organizations leave-organization` from the member → AccessDenied. Device 2 reads the org trail's `get-trail-status`/`get-event-selectors` and the audit bucket configuration from the audit account and diffs against the artifacts.

**Costs (official pricing, 2026-09-08):** accounts $0; org trail = a **second copy** of the workload account's management events while the Model-B trail also runs → $2.00 per 100,000 events (dark volume: well under $0.10/month; stopping the Model-B trail later is an owner choice, not required); audit bucket storage/requests ≈ cents; **≈ +$0.05–0.20/month**. Exclusions: any data events, Lake, additional regions' trails.

**Owner decisions inside Model A (later):** e-mail aliases for the two new accounts; org audit bucket retention years; whether to register the audit account as CloudTrail delegated administrator; whether to keep or stop the Model-B trail after cut-over.

### 5d. M5 test plan — prepared for review (no ruling invented; nothing implemented)

**The exact conflicting requirements.**
- M5 (PFA_SINGLE_FOUNDER_KMS_BOOTSTRAP.md, MANDATORY ADDITIONS): "**MANDATORY END-TO-END SIGN TEST BEFORE ISSUANCE (P2-E2E). Between trust establishment and any feature.native_issuance_enabled flip … issue ONE credential through the DEPLOYED credential-sign edge for a throwaway atom and confirm sign-after-verify passes.**"
- T3 (same document, maturity trigger): "**(T3) HARD BACKSTOP — the first of {a production credential is signed, native issuance is enabled}** …"; Model A is "REQUIRED before T3/commerce".
- Substrate (migration 093 L4931–4937, `kernel.issue_ticket_atoms`): "**NATIVE ISSUANCE GATE — the mint is inert while the flag is false … raise exception 'precondition_failed: feature_disabled'**"; its only callers are `venue.finalize_primary_order` (085, paid primary order) and `venue.issue_comp` (086, comp allocation).

**Inconsistency (genuine):** M5 requires signing a credential *before* the issuance flip, but (i) no sanctioned path can produce an atom before the flip, and (ii) the credential it would sign is, by T3's definition, "a production credential is signed", which requires Model A first and retires the exception. As written, M5 cannot be satisfied without a bypass. **Smallest clarification proposed for review (owner decides):** read M5 as two parts — **M5-iso** (before any issuance): the same edge code, on isolated non-production infrastructure, with a **non-production KMS key**, proving the full chain the invariants check cannot (STS AssumeRole → KMS `Sign` ES256 → DER→raw → sign-after-verify → token → offline verify via `/keys`); **M5-live**: the first credential signed by the production key through the deployed edge **is T3**, executed only after Model A is operational and under the activation authorization, as the controlled first issuance. This preserves T3's meaning and touches no gate.

1. **Provable locally / on isolated infrastructure (now or after small separately-authorized setup):** already done — vitest mocked-signer rehearsal (7), STS/KMS provider suite (28), redaction suite, pgTAP 176–180, CI Deno type-check; production-order migration rehearsal. **M5-iso** requires: a non-production KMS key (`ECC_NIST_P256`, tagged `snatchit:purpose=test-signing`, ≈ $1/month) + a test runtime user/role pair of the same shape (own authorization; not in this package) and a non-production edge host — a **Supabase staging project** (not present today) or a CI job (`supabase start` + Deno `functions serve` in GitHub Actions with scoped AWS credentials as repository secrets). Evidence: token verifies offline; CloudTrail `Sign` by the test role only; zero production rows.
2. **KMS binding proof the canonical bootstrap permits:** §5.3 — the ceremony role signs a **Device-2-generated random challenge** (`kms sign --message-type RAW --signing-algorithm ECDSA_SHA_256`); Device 2 verifies against its independently exported public key; altered-message and wrong-key FAIL; plus the DB PRE-FLIGHT 2 fingerprint gate at C3 and `kernel.check_signing_key_invariants()` after C5. It proves key ↔ handle ↔ public-key ↔ fingerprint binding for the production key. It is **not** a production credential and does not trigger T3.
3. **Must wait for Model A + the activation authorization:** any `credential-sign` call returning a token signed by the production key (= T3); door-manifest signing on production episodes (production signing of an admission artifact; treated conservatively as post-Model-A); therefore C7 as written.
4. **Legitimate test atom through sanctioned paths:** only `kernel.issue_ticket_atoms` via `venue.finalize_primary_order` (a paid primary order) or `venue.issue_comp` (a comp allocation, cause `comp`, zero money) — both refuse while issuance is dark. The first atom therefore exists only after the issuance flip (itself T3). Recommended first atom for M5-live: **`venue.issue_comp` on an internal test event** under the activation authorization with Model A operational, M6 (110) applied and the monitor armed. Never: direct custody inserts, temporary flag flips, guard disables.
5. **Live results still required before customer rollout:** Model A operational and probe-verified; first live credential (M5-live) with exactly one CloudTrail `Sign` by the runtime role, verified offline through `/keys` from a real door session; a signed door manifest verified by the door path; monitor green; controlled commerce checks (Stripe live checkout on an internal event, payout posture) per the primary-ticketing activation runbook; scanner SDK readiness (external, not in this repository). **Launch readiness is not claimed until these are proven.**

---

## 6. Status ledger

| Item | Implemented | Rehearsal-tested | Deployed / applied | Operationally verified |
|---|---|---|---|---|
| Paid plan | n/a | n/a | **VERIFIED (API)** | yes |
| C1-0a preflight | — | — | done (read-only) | evidence §0 |
| C1-0b TOTP enrolment | — | — | **in progress (owner)** | pending read-back |
| C1-1 … C1-10 | artifacts final | n/a | **not started** | no |
| Migrations 110–114 | yes | yes (+ production order) | **no** (fresh: absent) | no |
| KMS key / DB trust root | n/a | M4 proven | no | no |
| O1 secrets / edges | code present | mocked | no | no |
| M5 | plan §5d (pending clarification) | mocked only | no | no |
| Model A | package §5c + 2 draft artifacts | — | no | no |
| Product launch readiness | **not claimed** | — | — | — |
