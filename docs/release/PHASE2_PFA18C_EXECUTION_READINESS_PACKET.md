# PFA-18C — EXECUTION READINESS PACKET (billing step + bootstrap preparation)

**Date:** 2026-09-08 (session 8) · **Branch:** `feature/venue-native-and-product-v2` · **Reviewed tree:** `aa74cc2` (= audit `1f3fc19` + session-7 docs; still the branch tip) · **Coordinator:** Claude A (read-back only; C18 unchanged)
**Authorization in force:** the owner approved moving beyond the AWS Free plan. That approval is **pay-as-you-go billing only**. It authorizes **no** KMS key, Organization, account, IAM resource, CloudTrail trail, Object-Lock bucket, production migration, deployment, secret, or activation. The owner executes every ceremony mutation personally under the ratified single-founder procedure with independent second-device verification (M2). Paying AWS completes none of: backend integration, scanner implementation, launch validation.

Evidence classes: **CLAUDE-OBSERVED** (read this session), **OWNER-RETURNED** (typed by the owner earlier; not re-observed), **OFFICIAL-DOC** (AWS page read this session), **REHEARSAL** (local harness this session), **NOT OBSERVED**.

---

## 0. State reconciliation (what changed since the audit)

| Item | Recorded (audit/runbook, 2026-09-05) | Fresh (this session) | Class |
|---|---|---|---|
| Audit commits `1f3fc19` / `aa74cc2` | current | **still current** — `aa74cc2` is the tip of `feature/venue-native-and-product-v2` (= `origin`); CI green on both (`34002456147`/`34002458531` at `1f3fc19`; `34002649849`/`34002653888` at `aa74cc2`) | CLAUDE-OBSERVED |
| Descendant branch | — | `admin/operating-console` `ab3e17f` = `aa74cc2` + 17 commits (ops console 115–120; touches no PFA-18C doc, no 110–114 file); PR #55 draft → venue-native; CI green (`34173834884`, guard `34173839089`) | CLAUDE-OBSERVED |
| Production ledger | 124 rows, numeric tip 109 | **130 rows, numeric tip 120** — migrations **115–120** (ops console) applied 2026-09-08 ~00:2xZ by the owner-approved RC3 release (record: `docs/admin-console/DEPLOYMENT_RECORD_2026-09-08.md`, admin branch), via Management-API `db query -f` per file + explicit ledger rows; **110–114 remain unapplied** (`guard_110_present=false`, `recovery_111_present=false`, `get_signing_keys_door` absent) | CLAUDE-OBSERVED 2026-09-08T00:38Z |
| Signing substrate | 0 keys, dark | `kernel.signing_key` **0**; `feature.native_issuance_enabled=false`, `feature.native_scanning_enabled=false`, `signing.monitor_enabled=false`, `expected_key_fingerprint=null`, `expected_max_not_after=null`; tickets 0, door_session 0 | CLAUDE-OBSERVED |
| Pre-110 census | kernel fns 149 · venue fns 83 · kernel tables 31 | **149 · 83 · 31** (unchanged; `ops` schema now present, 90 fns) | CLAUDE-OBSERVED |
| Native edges | not deployed | still only the 11 legacy commerce/transfer edges; no `credential-sign` / `door-session` / `door-manifest` | CLAUDE-OBSERVED |
| Supabase branch record | `git_branch: ""` | `git_branch: ""` (mechanical read; owner visually confirmed OFF on 2026-09-07 per the RC3 record) | CLAUDE-OBSERVED |
| AWS plan | FREE, $100 remaining, expires 2027-03-05 | **NOT re-verified** — CLI session expired (`aws login` required); last state is OWNER-RETURNED 2026-09-05 | NOT OBSERVED |
| Pre-existing user edits | preserved | still present and untouched: `M docs/release/PHASE2_PRODUCTION_KMS_SIGNING_CEREMONY_EXECUTION.md`, `?? docs/phase2/TICKETS_READ_CONTRACT_CORE_COORDINATION.md` | CLAUDE-OBSERVED |

**Consequences.** (1) Runbook **NG-3** as written ("ledger 124 / tip 109") now triggers on a known, owner-approved change; the bootstrap substrate (093–109, 0 keys, dark flags, census 149/83/31) is unchanged. NG-3 is re-baselined to **ledger 130 / numeric tip 120 / 110–114 absent / 0 keys** (dated note added to the runbook). (2) Production will apply **110–114 after 115–120**, which is not the fresh-replay order CI proves; §E carries the rehearsal that settles order-independence. (3) Anything the owner runs from `feature/venue-native-and-product-v2` alone will fail `db push` ("remote migration versions not found") because that tree lacks 115–120 — see §E.

---

## 1. Billing step — status and owner guidance

**Confirmed state:** **FREE** (OWNER-RETURNED 2026-09-05: `accountPlanType FREE · ACTIVE · $100 remaining · accountPlanExpirationDate 2027-03-05T17:57:11Z`). **Not freshly verified** this session: `aws sts get-caller-identity` and `aws freetier get-account-plan-state` both returned "Your session has expired. Please reauthenticate using 'aws login'." **PAID is recorded only when a fresh `get-account-plan-state` returns `accountPlanType: PAID`.**

**What the upgrade is (OFFICIAL-DOC, AWS Billing user guide "Choosing a plan" + Free Tier FAQ):**
- Paid account plan = "standard pay-as-you-go pricing for any usage beyond your Free Tier credit balance". There is **no $100 purchase, subscription, support plan, or credit package** involved; the "$100" the owner referred to is the existing Free Tier **credit balance**, not a charge.
- "When you upgrade to paid plan, your remaining Free Tier credits will automatically apply to future AWS bills until they expire. Free Tier credits expire 12 months after you create your account."
- "AWS will not charge your payment method until you upgrade to paid plan." After the upgrade the payment method on file is charged only for usage beyond credits (§3 estimate).
- **Do not** upgrade by joining an Organization / Control Tower: "if you upgrade to paid plan by joining an AWS Organization or setting up an AWS Control Tower landing zone, your Free Tier credits expire immediately". Free plans also "automatically upgrade to paid plan if you join AWS Organizations…" — another reason no Organization is created in this step.
- Console procedure (verbatim): "1. Sign in to the AWS Management Console. 2. Choose **Upgrade plan** (`https://console.aws.amazon.com/billing/home?#/freetier/upgrade`). 3. Review the features you gain, and choose **Upgrade account**." (FAQ: the button lives in the **Cost and Usage** widget of the console home.) Equivalent owner-run CLI exists: `aws freetier upgrade-account-plan --account-plan-type PAID` — the Console path is used here so the owner sees the displayed terms before submitting.

**Owner steps (one at a time; the coordinator reads back after each):**

| # | Owner does (primary machine) | Returns to chat (non-secret only) | Coordinator gate |
|---|---|---|---|
| B0 | `aws login --profile snatchit-admin` (browser sign-in as `jose-admin` with passkey MFA; nothing pasted) | "done" | — |
| B1 | `aws sts get-caller-identity --profile snatchit-admin --region us-east-1 --no-cli-pager` | Account, Arn, UserId | must be `652872010073` / `arn:aws:iam::652872010073:user/jose-admin` |
| B2 | `aws freetier get-account-plan-state --profile snatchit-admin --region us-east-1 --no-cli-pager` | full JSON | expected FREE before upgrade; records the credit balance and expiry |
| B3 | Console home → Cost and Usage widget → **Upgrade plan** → **read the page** → STOP and report what the page says it will charge or subscribe to (before pressing anything) | the displayed terms, verbatim | coordinator confirms it is pay-as-you-go with no product/subscription/credit purchase; if anything else is required, **stop** |
| B4 | Press **Upgrade account** (only after B3 is cleared) | confirmation text | — |
| B5 | Re-run B2 | JSON | **PAID** ⇒ NG-1 cleared; anything else ⇒ not cleared |

Passwords, MFA codes/passkeys, payment details and recovery material stay on the owner's screen only. NG-2…NG-6 remain independently applicable after NG-1 clears.

---

## 2. Proposed account layout (Model A, from the ratification — NOT created now)

Ratified constraints: Model B (same account) is acceptable **only for the initial dark bootstrap**; **Model A** (separate audit account + SCP) is REQUIRED before T3; "SCPs don't affect users or roles in the management account. They affect only the member accounts in your organization." (OFFICIAL-DOC, Organizations user guide). Therefore the production key can never be SCP-protected if it lives in the management account.

| Account | Role | Holds | Reuses `652872010073`? |
|---|---|---|---|
| **Management** (NEW, later) | Organizations/SCP administration only; root MFA; no access keys; **no workloads, no KMS keys, no trail of its own**; never a ceremony or runtime principal | nothing operational | **No** — a fresh Paid account, created only when Model A is authorized |
| **Workload / signing member** | the production KMS key (`ECC_NIST_P256`, ES256), `SnatchIt-KMS-Ceremony`, `SnatchIt-CredentialSign-Runtime` + runtime user, `snatchit-kms-verifier`; the Model-B trail + Object-Lock bucket created at C1 stay here (they are its own audit evidence); the SCP binds this account | key ARN `arn:aws:kms:us-east-1:652872010073:key/…` | **Yes — reuse as the workload member.** Rationale: the key ARN is account-bound; creating it here now and inviting this account into the future organization keeps D4/D5 and every artifact ARN stable (no re-ceremony); `jose-admin`, passkey MFA and the baseline already exist here |
| **Audit member** (NEW, later) | owns the organization trail and the durable Object-Lock bucket; no workload principals; Device-2 read-back principal for Model A | org trail, audit bucket | **No** |

Sequencing: Model B bootstrap in `652872010073` (as ratified) → before T3: create the management account, create the audit account, invite `652872010073` as a member, attach the SCP (deny `cloudtrail:Stop*/Delete*/Update*/PutEventSelectors`, audit-bucket mutation, `kms:ScheduleKeyDeletion` on the signing key — to everyone including account admins), org trail → audit bucket. **Open risk to record:** whether Free-Tier credits survive a *later* org join of an already-PAID account is not stated in the docs read this session (the stated expiry applies to upgrading *via* an org); treat credit loss as possible at Model-A time. No Organization, account, or SCP is created by anything in this packet.

---

## 3. Cost estimate (official pricing read 2026-09-08; region us-east-1; replaces the earlier unsupported "$1–2/month")

Unit prices (OFFICIAL-DOC): KMS key **$1/month prorated hourly**; KMS asymmetric `Sign` **$0.15 per 10,000** (asymmetric requests are excluded from the 20,000/month free tier; other requests $0.03/10k); CloudTrail **first copy of management events to S3 free** (multi-region trail = the one copy; additional copies $2.00/100k; data events $0.10/100k — none configured; Insights $0.35/100k — none); S3 Standard **$0.023/GB-month**, PUT **$0.005/1,000**, GET **$0.0004/1,000**, no separate Object-Lock/versioning line item on the pricing page; CloudWatch alarms **$0.10/alarm-month beyond 10 free**, custom metrics $0.30, Logs $0.50/GB ingested beyond 5 GB free; AWS Budgets **notifications free** (first two action-enabled budgets free); IAM "offered at no additional charge"; STS — no price is published on the IAM pricing/FAQ pages read (treated as $0, **inferred from absence**, not from an explicit STS statement).

| Line | Assumption | Monthly |
|---|---|---|
| KMS key (1, single-region) | created at C2; billed from creation | **$1.00** |
| KMS requests — ceremony | ≤ 20 requests (CreateKey, Describe, GetPublicKey ×2, Sign ×1 proof, PutKeyPolicy ×2, Verify by openssl not KMS) | ≈ $0.00 (one-time) |
| KMS `Sign` — runtime, dark | 0 until C7 (M5 = 2 signs) | $0.00 |
| KMS `Sign` — runtime, live | per 1,000 credentials + per manifest signature: **$0.015 / 1,000** (e.g. 50,000 credentials/month ⇒ +$0.75) | volume-driven |
| STS `AssumeRole` | one per isolate per ≤ 1 h session (E2 cache) | $0.00 |
| CloudTrail multi-region trail, management events Read+Write incl. KMS, no data events/Insights | first copy | **$0.00** |
| S3 storage (trail logs + hourly digest files) | ~1–3 MB/day ⇒ ≈ 0.05–0.1 GB/month accumulated under retention; year 1 ≈ 1 GB | $0.00 → $0.03 (grows ~$0.002/month) |
| S3 PUTs from CloudTrail | log files ≤ 10,000/month + digests ≈ 17 regions × 720/h-slots ≈ 12,000 | ≈ **$0.06–0.11** |
| S3 GETs (Device-2 read-backs, verification) | < 5,000 | ≈ $0.00 |
| CloudWatch (optional detection: `AssumeRole`/`Sign` by unexpected principal) | ≤ 10 alarms ⇒ free; Logs delivery of the trail ≤ 5 GB free | $0.00 (or $0.10/alarm beyond 10) |
| AWS Budgets (1 cost budget, e-mail alert) | notifications only | $0.00 |
| **Total, dark (post-C2, pre-issuance)** | | **≈ $1.06–$1.15/month**, rising by cents/month with log retention; **≈ $1.00 of it is the key itself** |
| **Total, live** | + $0.015 per 1,000 credentials + manifest signs | volume-driven |

**Credit treatment:** the remaining balance (OWNER-RETURNED ≈ $100 on 2026-09-05; re-read at B2) applies automatically after the upgrade until 12 months after account creation. The account-creation date is **inferred** as 2026-09-05 from the Free-plan expiry 2027-03-05 (6-month plan) ⇒ credits expire ≈ 2027-09-05 (**inferred**, verify at B2/Billing → Credits). Whether credits apply to every line above is not enumerated by AWS; assume KMS/S3/CloudTrail are eligible (unverified). If they are, expected cash outlay in year 1 ≈ $0.

**Exclusions:** Model A (two more accounts; an org trail delivering a *second* copy to a member that keeps its own trail is charged $2/100k events; a second Object-Lock bucket); any data-event logging; CloudTrail Lake; Supabase, Vercel, Stripe, Apple; taxes; support plans (none purchased); data transfer (well inside the 100 GB/month free allowance).

**Budget alerts are notifications, not caps.** AWS Budgets "monitor and receive notifications"; a budget cannot stop KMS/S3/CloudTrail charges already incurred, and budget *actions* (IAM/SCP policy application) are not configured here. The controls that bound spend are the design itself: one key, one trail, Sign-only runtime, no data events.

---

## 4. M1–M6, recovery, Model A — reconciled against the exact current artifacts

**Terminology guard.** In PFA-18C, **M1–M6** are *bootstrap controls* (audit plane, second device, runtime role, artifact algorithm fix, live sign test, insert guard). In `SCANNER_VERIFIER_CONTRACT.md` / OFFLINE-VERIFY-v1, **M1** is the *keyring manifest* delivered through `door-session /keys` (migration 114) and **M2** is the *door manifest* (migrations 112/113). The table below is the PFA meaning; the scanner manifests are covered only in §E (migrations 112–114).

| Control | Requirement (ratification, verbatim intent) | Exact artifact(s) | Implemented | Tested | Deployed / applied | Operationally verified |
|---|---|---|---|---|---|---|
| **M1** audit plane (Model B for the dark bootstrap) | dedicated multi-region trail, validation ON, Read+Write incl. KMS; Object-Lock **COMPLIANCE + real retention**; SSE-S3; ceremony principal denied CloudTrail/S3/IAM/KMS-lifecycle mutation; read back from Device 2 | `pfa18c_artifacts/m1_*.json` (4 files); trail `snatchit-audit-trail`; bucket `snatchit-audit-652872010073` | drafted (deny-set is code) | n/a (policy JSON; rehearsal not possible without AWS) | **no** — nothing in AWS (baseline: no trail, no bucket, no roles) | no |
| **M2** second clean device + read-only principal | physically separate device; own read-only IAM user; independent `GetPublicKey`, SPKI, D5 fingerprint, §5.3 binding proof, altered-message/wrong-key FAIL, deny-set + key-policy read-back | `m2_verifier_policy.json`; user `snatchit-kms-verifier` + `SignInLocalDevelopmentAccess` | drafted | n/a | **no** (user not created; device not provisioned) | no |
| **M3** distinct runtime role | Sign only on the exact key ARN; no Decrypt/`kms:*`; ceremony principal retains no Sign (key policy v2) | `m3_runtime_user_policy.json`, `m3_runtime_role_trust.json` (ExternalId placeholder), `m3_runtime_role_policy.json` (ARN placeholder); key policies v1/v2; E2 provider code (`kms-taxonomy.ts`, `kms.ts`) | policies drafted; **E2 code implemented** | E2: 28 mocked-STS/KMS cases + redaction suite (in the 803-vitest run at `1f3fc19`; CI Deno type-check green) | **no** (no user/role/key/secret; O1 not owner-approved) | no |
| **M4** artifact algorithm fix | §6.1 artifact writes `algorithm='ES256'` explicitly | `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` §6.1 L428–536 | **yes** | off-production proven (2026-09-04; negatives N1–N5) | n/a (ceremony artifact) | pending the ceremony (C3) |
| **M5** end-to-end sign test | one credential + one manifest through the deployed edges with the real key; exactly one CloudTrail `Sign` each | `tests/m5-mocked-signer-rehearsal.test.ts` (7); live proof = runbook C7 | mocked rehearsal only | yes (mocked) | **no** (edges not deployed) | **no — requires C6/C7** |
| **M6** BEFORE INSERT guard | global-only, active-only, ES256-only, full KMS ARN, P-256 SPKI PEM, one active global, post-revoke parked, first row `…b0` | `110_signing_key_insert_guard.sql` (+ rollback) | yes | pgTAP 176 (51), concurrency probe, reverse-chain rehearsal; **this session: production-order rehearsal (§E)** | **no** — `guard_110_present=false` in production (fresh) | no |
| **Recovery** (gated two-person post-revoke re-bootstrap) | two distinct `platform_admin`+aal2 approvals, 30-min window, fingerprint-bound, fail closed | `111_signing_key_recovery_two_person.sql` (+ rollback) | yes | pgTAP 177 (67); transaction-rollback + concurrency probes | **no** — `recovery_111_present=false` (fresh) | no |
| **Model A** | separate audit account + SCP before T3 | §2 layout | recommendation only | — | **no** | no |
| **C18** | founder runs every AWS/DB mutation; AI read-back only | this packet, runbook §C | in force | — | — | — |

**Ceremony model preserved:** the ratified single-founder compensating-control procedure (C18) with the mandatory **independent second-device verification (M2)** is the model in force. The uncommitted two-person coordinator draft in `PHASE2_PRODUCTION_KMS_SIGNING_CEREMONY_EXECUTION.md` (user edit, preserved) is the *prior* NO-GO record and is not substituted for it.

---

## 5. Prepared execution package (D) — names, bindings, order, verification, abort

**Bindings (all ARNs assume the §2 decision to reuse `652872010073` as the workload member):**

| Name | Value |
|---|---|
| Account / region | `652872010073` / `us-east-1` (region pin: **owner confirmation required**, §6) |
| Setup administrator | `arn:aws:iam::652872010073:user/jose-admin` (creates M1/M2/M3 resources; **never** the ceremony session) |
| Audit bucket / trail | `snatchit-audit-652872010073` (Object Lock enabled at creation, SSE-S3 AES256, all public access blocked, TLS-only) / `snatchit-audit-trail` (multi-region, validation ON, `ReadWriteType=All`, KMS events included) |
| Object-Lock default retention | `COMPLIANCE`, `Years=<RETENTION_YEARS>` — **owner decision, irreversible** (§6) |
| Ceremony role | `SnatchIt-KMS-Ceremony`; trust = `jose-admin` + `aws:MultiFactorAuthPresent=true` + `sts:RoleSessionName=pfa18c-ceremony`; max session 1 h; inline policy `pfa18c-ceremony` = `m1_ceremony_role_policy.json` |
| Verifier (Device 2) | user `snatchit-kms-verifier`; inline `m2_verifier_policy.json` + managed `SignInLocalDevelopmentAccess`; console password + MFA set by the owner in the console; **no access key ever** |
| Runtime | user `snatchit-credential-sign-runtime` (inline `m3_runtime_user_policy.json`; access key only at C6 under O1) → role `SnatchIt-CredentialSign-Runtime` (trust `m3_runtime_role_trust.json` with `<KMS_SIGNER_EXTERNAL_ID>` = `openssl rand -hex 32`, generated on the owner's machine, stored only in the trust policy and Supabase secrets; permissions `m3_runtime_role_policy.json` with `<PRODUCTION_KMS_KEY_ARN>` filled after C2) |
| KMS key | `KeySpec=ECC_NIST_P256`, `KeyUsage=SIGN_VERIFY`, `Origin=AWS_KMS`, single-region, tag `snatchit:purpose=ticket-signing`, policy **v1** at create (`kms_key_policy_v1_binding_proof.json`) → **v2** after the proof (`kms_key_policy_v2_final.json`); description "Snatch It ticket-signing trust root (PFA-18C)" |
| DB row (C3) | `key_id …b0`, `scope=global`, `status=active`, `algorithm=ES256` (explicit), `kms_handle_ref` = D4 full key ARN, `public_key` = Device-2 `pub.pem` (SPKI PEM), fingerprint D5 = sha256 over DER SPKI (lowercase hex), `not_after=NULL` (D6) |
| Filled placeholders | live **only** in the owner's local ceremony directory; committed artifacts keep the placeholders; secrets never in any file |

**Execution order (each row = one owner turn; STOP after each; Claude reads back; every command carries `--profile snatchit-admin --region us-east-1` unless a different profile is named):**

| Stage | Owner command(s) — device | Read-back (non-secret) | Abort if |
|---|---|---|---|
| A1–A5 preflight | runbook §A (identity/plan; baseline; DB read-only — with the **re-baselined** expectations: ledger 130, numeric tip 120, `guard_110_present=false`, 0 keys; parked-state loop) | outputs | any value differs from this packet §0 |
| M1-1 | `aws s3api create-bucket --bucket snatchit-audit-652872010073 --object-lock-enabled-for-bucket` — primary | `Location` | bucket name taken / not `ObjectLockEnabled` |
| M1-2 | `put-public-access-block … BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true` · `put-bucket-encryption … SSEAlgorithm=AES256` · `put-bucket-policy --policy file://m1_audit_bucket_policy.json` — primary | `get-public-access-block`, `get-bucket-encryption`, `get-bucket-policy` | any read-back ≠ artifact |
| M1-3 | `put-object-lock-configuration --object-lock-configuration file://m1_object_lock_configuration.json` (Years filled) — primary | `get-object-lock-configuration` = `COMPLIANCE`, chosen Years | mode ≠ COMPLIANCE — **this step is irreversible** |
| M1-4 | `cloudtrail create-trail --name snatchit-audit-trail --s3-bucket-name snatchit-audit-652872010073 --is-multi-region-trail --enable-log-file-validation` · `put-event-selectors --trail-name snatchit-audit-trail --event-selectors '[{"ReadWriteType":"All","IncludeManagementEvents":true,"ExcludeManagementEventSources":[]}]'` · `start-logging` — primary | `describe-trails` (multi-region, validation), `get-trail-status` (`IsLogging=true`), `get-event-selectors` (no KMS exclusion) | any exclusion / not logging |
| M1-5 | `iam create-role --role-name SnatchIt-KMS-Ceremony --assume-role-policy-document file://m1_ceremony_role_trust.json --max-session-duration 3600` · `iam put-role-policy --role-name SnatchIt-KMS-Ceremony --policy-name pfa18c-ceremony --policy-document file://m1_ceremony_role_policy.json` — primary | `get-role`, `get-role-policy` | diff vs artifact non-empty |
| M1-6 (MFA test) | `sts assume-role --role-arn arn:aws:iam::652872010073:role/SnatchIt-KMS-Ceremony --role-session-name pfa18c-ceremony --query AssumedRoleUser` — primary (**`--query AssumedRoleUser` is mandatory: the raw output contains credentials**) | `AssumedRoleUser.Arn` | `AccessDenied` ⇒ `aws login` credentials do not carry `aws:MultiFactorAuthPresent` — STOP; decide §6(f) before continuing |
| M2-1 | `iam create-user --user-name snatchit-kms-verifier` · `put-user-policy … --policy-name pfa18c-verifier-readonly --policy-document file://m2_verifier_policy.json` · `attach-user-policy … --policy-arn arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess` (verify the managed-policy name in the IAM console); console password + MFA via console — primary | `get-user`, `get-user-policy`, `list-attached-user-policies`, `list-mfa-devices` | any Allow beyond the artifact |
| M2-2 / M2-3 | Device 2: `aws login --profile verifier`; `sts get-caller-identity`; denied-mutation probe `kms create-alias --alias-name alias/probe --target-key-id 00000000-0000-0000-0000-000000000000` ⇒ **AccessDenied** (not NotFound); full M1 read-back diffed against `pfa18c_artifacts/` — **Device 2** | identity, probe result, diff result | probe not denied; any diff |
| M3-1 | `iam create-user --user-name snatchit-credential-sign-runtime` · `put-user-policy … file://m3_runtime_user_policy.json` · generate ExternalId locally · `iam create-role --role-name SnatchIt-CredentialSign-Runtime --assume-role-policy-document file://<local filled trust>` (exact-ARN permissions deferred to after C2; **no access key now**) — primary | `get-role` (principal + ExternalId condition present, value not pasted), `get-user-policy` | — |
| PHASE-1 GATE | Device 2 confirms zero `jose-admin`/root management events outside the setup window are unexplained; all read-backs match | — | — |
| **C2** CreateKey | as the ceremony role session (CLI profile `[profile snatchit-ceremony] role_arn=… source_profile=snatchit-admin role_session_name=pfa18c-ceremony`): `kms create-key --key-spec ECC_NIST_P256 --key-usage SIGN_VERIFY --origin AWS_KMS --description "Snatch It ticket-signing trust root (PFA-18C)" --tags TagKey=snatchit:purpose,TagValue=ticket-signing --policy file://kms_key_policy_v1_binding_proof.json --profile snatchit-ceremony` → **Arn = D4**. Device 2: `kms get-public-key --key-id <D4> --query PublicKey --output text \| base64 -d > pub.der`; `openssl pkey -pubin -inform DER -in pub.der -out pub.pem`; `shasum -a 256 pub.der` = **D5** (Device 2 states first; primary recomputes independently). Binding proof: Device 2 mints `challenge.bin`; ceremony `kms sign --key-id <D4> --message fileb://challenge.bin --message-type RAW --signing-algorithm ECDSA_SHA_256 --query Signature --output text \| base64 -d > sig.der`; Device 2 `openssl dgst -sha256 -verify pub.pem -signature sig.der challenge.bin` ⇒ `Verified OK`; altered message ⇒ FAIL; throwaway key ⇒ FAIL. Then `kms put-key-policy --key-id <D4> --policy-name default --policy file://kms_key_policy_v2_final.json`; `iam put-role-policy --role-name SnatchIt-CredentialSign-Runtime --policy-name pfa18c-runtime-sign --policy-document file://<m3_runtime_role_policy.json with D4>`; ceremony `kms sign` again ⇒ **AccessDenied** | `KeyMetadata`, D5 (both devices), proof transcript, `get-key-policy` = v2, CloudTrail event ids (`CreateKey`, `Sign`, `PutKeyPolicy` ×2) | fingerprints disagree; proof fails; altered/wrong-key PASS; v2 read-back ≠ artifact; any credential outside the designated principal |
| **C3** DB commit | runbook §6.2 with `-v ALGORITHM="ES256"`, `KMS_HANDLE_REF=<D4>`, `PUBLIC_KEY_PEM=<Device-2 pub.pem>`, `EXPECTED_FINGERPRINT=<D5>`; `count(*)=0` re-checked seconds before | 3 NOTICEs + COMMIT; §7.1–§7.5 read-backs | any `CEREMONY ABORT`; count ≠ 0 |
| **C4** migrations 110–114 | §E | census 153/87/32; guard + recovery present | order/rehearsal evidence missing |
| **C5** monitor arming | `signing.expected_key_fingerprint := D5`; `signing.monitor_enabled := true`; `kernel.check_signing_key_invariants()` once | config read-back; invariants result | mismatch |
| **C6** dark deploy | secrets + `credential-sign` / `door-manifest` / `door-session` with `KMS_PROVIDER=aws` (O1 decided) | function versions; no `kms_*` errors | — |
| **C7** M5 live proof | one throwaway atom; one manifest; CloudTrail `Sign` ×2 by the runtime role only; flags stay false | edge logs `signed`; event ids | any other principal signs |
| **C8** activation | separate owner act, outside this packet (M5 + M6 + Model A) | — | — |

Rollback matrix: runbook §E (unchanged). Post-mutation verification: runbook §D (unchanged), with §0 re-baselined values for the DB counts.

---

## 6. Remaining owner decisions (each blocks a specific stage; none is made here)

| # | Decision | Blocks | Engineering note (not a decision) |
|---|---|---|---|
| (a) | **Pin region `us-east-1`** | every ARN, M1-1 | only signal is the saved CLI region |
| (b) | **Object-Lock retention years** — irreversible under COMPLIANCE; cannot be shortened; account closure is the only exit | M1-3 | prior recommendation 3 years; 1 year is defensible for the *interim* Model-B bucket now that Model A is the durable plane; 7 years is the financial-records horizon |
| (c) | **Runtime-credential design: O1** (IAM user → AssumeRole → Sign-only role; one static AWS secret in Supabase) **or O4** (signer on AWS compute, zero static secret; architecture change) | C6 (and the M3-1 user/role shape) | O1 is implemented and tested (E2); O4 is not built |
| (d) | **Confirm the account layout** in §2 (reuse `652872010073` as the workload member; management + audit accounts created later) | NG-2, C2 | the alternative (fresh workload account) means every artifact ARN changes and the ceremony happens there |
| (e) | **Confirm resource names** in §5 | M1-1 onward | — |
| (f) | **MFA mechanism for the ceremony trust policy** if M1-6 is denied: register a virtual MFA (TOTP) on `jose-admin` for CLI use, or amend the trust condition (artifact change, dated) | M1-6 | unknown until M1-6 is attempted |
| (g) | **C3-before-C4 or C4-before-C3** (runbook C4 note: both are safe; choose one and record it) | C3/C4 | this packet's §E assumes C4 (110–114) may precede C3 |

---

## 7. Release sequence for migrations 110–114 (E) — against the current repository rules

**Repository facts (CLAUDE-OBSERVED):** `origin/main` (`eadd456`, 2026-09-01) contains migrations only through `075` + timestamped web-form files; it is **not** an ancestor of `phase2/consolidation` or `feature/venue-native-and-product-v2`. Production (076–109, 115–120) was applied from the venue-native lineage under the practiced rule: reviewed PR + `AUTODEPLOY-VERIFIED-OFF: <date>` in the PR body + owner visual confirmation in the dashboard + owner-executed apply from a checkout of the exact commit (093–109: `supabase db push --linked --include-all`, CLI 2.115.0; 115–120: Management-API `db query -f` per file + explicit ledger rows). **A "merge to main" of this lineage is a separate ~375-commit reconciliation program; it is not on the 110–114 critical path and is not implied by the billing approval.** PR #52 (`venue-native → phase2/consolidation`, MERGEABLE/CLEAN, head `aa74cc2`) carries 110–114 with `AUTODEPLOY-VERIFIED-OFF: 2026-09-02` — **stale for apply day**; PR #55 (`admin → venue-native`) carries `2026-09-07` and the RC3 record carries the owner's visual confirmation of 2026-09-07.

**Deployment dependencies:**
1. **Tree must contain 115–120.** Production's ledger has them; a checkout without those files makes `db push` refuse ("Remote migration versions not found in local migrations directory" — the 2026-08-27 failure mode). Candidate apply trees: `admin/operating-console @ ab3e17f` (110–120 present, CI green) or `feature/venue-native-and-product-v2` **after** PR #55 merges. The five files are byte-identical on both (sha256 prefixes per audit §1: `3134f6f6…`, `d13cf6cb…`, `97d33d08…`, `32d42324…`, `9974eb91…`).
2. **Apply order in production is 115–120 → 110–114**, not the CI fresh-replay order. Static check: 115–120 reference none of `signing_key`, `get_door_manifest`, `_get_door_manifest_core`, `get_signing_keys_door`, `get_manifest_signing_context`, `signing_key_recovery`, `guard_signing_key_insert`; 110–114 reference nothing in `ops`. **Rehearsal (this session, local harness):** see §7.1 — the production-order database must equal the canonical-order database on every function/trigger/policy definition and routine grant, and pass the full pgTAP plan.
3. **Guard rule:** the PR that lands them must carry a fresh `AUTODEPLOY-VERIFIED-OFF: <apply date>`; `migrations-guard` is green on both candidate trees; `git_branch` is `""` (fresh) **and** the owner re-confirms visually on apply day.
4. **CLI pin 2.115.0** for `db push`; `--include-all` is mandatory (110–114 sort below the remote tip 120); a `--dry-run` must list **exactly** `110, 111, 112, 113, 114` and nothing else before the real push. Fallback path = the per-file Management-API method used for 115–120 (`supabase db query --linked -f <file>` + ledger row), one file at a time, in order.
5. **Rollbacks staged:** `supabase/rollbacks/114…110` (reverse order; rehearsed to invert census and definitions exactly).

**Sequence (owner-executed; "AUTHORIZE PFA-18C MIGRATIONS 110-114"):**
1. Choose the tree (dependency 1) and record its commit SHA; confirm CI run ids for that SHA.
2. Fresh preflight: ledger 130 / tip 120 / 110–114 absent / `git_branch ""` / owner visual OFF confirmation dated today.
3. `supabase db push --linked --include-all --dry-run` from that checkout ⇒ exactly 110–114.
4. `supabase db push --linked --include-all` (or the per-file fallback), 110 → 114.
5. Read-backs (runbook §D "After C4"): `kernel.guard_signing_key_insert()` present + trigger enabled; probe INSERT of a second global key inside `begin … rollback` refuses `active_global_exists` (only meaningful after C3); `kernel.signing_key_recovery_approval` count 0; census kernel fns **153**, venue fns **87**, kernel tables **32**; `venue.get_signing_keys_door` refuses anon/authenticated; ledger 135, numeric tip 120 (numeric tip is unchanged because 120 > 114 — record this explicitly so the next preflight is not misread).
6. Record in the execution record with the ledger `created_by` semantics (`NULL` for both CLI push and Management-API paths).

**Dark deployment vs activation (kept separate):** C4 (migrations) and C6 (edge deploy with `KMS_PROVIDER=aws`) are **dark**: no credential can be signed until a `kernel.signing_key` row exists (C3), the edges are deployed (C6) *and* called; `feature.native_issuance_enabled` / `feature.native_scanning_enabled` remain `false` and are flipped only at **C8**, a separate owner act gated on M5 + M6 + Model A. Nothing in this packet moves those flags.

### 7.1 Production-order rehearsal evidence (local harness, this session — REHEARSAL, 2026-09-08T00:46Z)

Method: local Homebrew PostgreSQL 17 (loopback only; harness refuses non-local servers), admin tree `ab3e17f` (identical 110–120 bytes).
- **A) Production order:** replayed the full chain **without** 110–114 (130 files: 001…109, 115…120, timestamped) ⇒ census `kernel_fns=149 venue_fns=83 ops_fns=90 kernel_tables=31 guard110=false recovery111=false` — **byte-for-byte the production census read at 00:38Z**. Then applied `110 → 111 → 112 → 113 → 114` with `ON_ERROR_STOP` ⇒ all five OK ⇒ `kernel_fns=153 venue_fns=87 ops_fns=90 kernel_tables=32 guard110=true recovery111=true`. (The first reset run reported `exit=1` only because the scratch tree lacked `supabase/ci/parity_grants.sql` for the harness's *post-replay* parity check; the migration replay itself completed — the census proves it — and the leg was re-run with the file present: exit 0, Gate-2 27/71/37/27, census 149/83/90/31.)
- **B) Canonical order:** fresh replay of the admin tree (110–114 before 115–120) ⇒ Gate-2 `tables=27 functions=71 policies=37 triggers=27` (= CI baseline); census `153 / 87 / 90 / 32`, guard + recovery present.
- **C) Definition equality:** dump of every function/procedure definition (`md5(pg_get_functiondef)`) **plus routine grants**, every non-internal trigger definition, and every RLS policy (`USING`/`WITH CHECK`) across `kernel, venue, ops, catalog, market, notify, public` — 682 lines each — **IDENTICAL** between the production-order and canonical-order databases (sha256 `c369c8a32ce5b35d…`).
- **D) Full pgTAP on the production-order database:** `plan=4320 ok=4316 not_ok=4` — the four are the documented local-only deltas (060×2 / 132×2); suites 176–180 (51/67/41/45/42) and 181–186 (ops) all PASS; harness verdict "matches the expected local baseline".

Conclusion: applying 110–114 **after** 115–120 yields the same catalog (definitions, grants, triggers, policies) as the CI-proven order and passes the full suite. Order-independence is established for this exact pair of packages; it is not a general property.

---

## 8. Next exact action requiring authorization

**Billing (now, no authorization phrase — already approved):** owner runs **B0** (`aws login --profile snatchit-admin`), then B1/B2; coordinator reads back; then B3 (read the upgrade page and report its terms) before anything is pressed.

**First ceremony mutation (after NG-1 clears and decisions (a)(b)(d)(e) are recorded):** **C1 / M1-1** — `aws s3api create-bucket --bucket snatchit-audit-652872010073 --object-lock-enabled-for-bucket --profile snatchit-admin --region us-east-1`, authorized by the phrase **"AUTHORIZE PFA-18C M1/M2/M3 SETUP"**. Reviewed artifacts: `docs/release/pfa18c_artifacts/m1_audit_bucket_policy.json`, `m1_object_lock_configuration.json` (Years filled by the owner), this packet §5. **Not authorized by the billing approval.**

---

## 9. Status ledger

| Item | Implemented | Tested | Deployed / applied | Operationally verified |
|---|---|---|---|---|
| Paid-plan upgrade | n/a | n/a | **not yet** (FREE last seen 2026-09-05; not re-read) | pending B5 |
| Migrations 110–114 | yes | rehearsal + CI + **production-order rehearsal (§7.1)** | **no** (fresh: absent) | no |
| Migrations 115–120 (ops console, not PFA-18C) | yes | CI | **yes** (2026-09-08, owner-approved) | per admin record; out of scope here |
| E2 runtime provider + corrected verifiers (P1-PUBKEY-FORMAT) | yes | vitest 803 + Deno CI | no | no |
| M1/M2/M3 AWS resources | drafted | n/a | no | no |
| KMS key / DB trust root | n/a | M4 artifact proven off-production | no (0 keys) | no |
| Monitor / edges / M5 | code present | mocked | no | no |
| Model A | recommendation | — | no | no |
| Backend integration, scanner (external SDK), launch validation | **not completed by paying AWS** | — | — | — |
