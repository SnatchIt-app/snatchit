# PFA-18C — C1-10 / M2 Device-2 retrieval and verification handoff

**Prepared:** 2026-09-09 (coordinator, read-only) · **Artifact download ref (pin):** `c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd` on `feature/venue-native-and-product-v2` · **Manifest-recording commit (do NOT use as a download ref):** `7fa960b5258124a66ee197f9daa67c2736f1bd3a`
**Standing:** M2 is NOT complete. Device 2 has (owner-returned) authenticated as `arn:aws:iam::652872010073:user/snatchit-kms-verifier` via `aws login --profile verifier` after enrolling its own passkey. Nothing below authorizes or performs an AWS mutation, a KMS key, signing, secrets, or access keys. Device 2 never uses `jose-admin` or root.

Evidence classes: **OWNER-RETURNED** (stated by the owner / Device 2 operator), **CLAUDE-OBSERVED** (coordinator read-only), **DEVICE-2 REQUIRED** (Device 2 must execute independently).

---

## A. Repository

`SnatchIt-app/snatchit` — public. Raw download URL form:
`https://raw.githubusercontent.com/SnatchIt-app/snatchit/c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd/<path>`

## B. C1-10 DEVICE-2 RETRIEVAL MANIFEST (exactly 10 entries; SHA-256 of the committed blob at `c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd`, as recorded in the execution record at `7fa960b5258124a66ee197f9daa67c2736f1bd3a` and re-verified against GitHub-served bytes)

```
89540f612449a3e540f851f1e62082b2c3263e2a9849f6b0f4fcbbec41baf4b7  docs/release/pfa18c_artifacts/m1_ceremony_role_trust.json
1fddd53beee238063da99a26db3f301c546ee9c111685c5a5f630e0f930bd4d5  docs/release/pfa18c_artifacts/m1_ceremony_role_policy.json
3082cc74824ef68c47cd2fc39caf0d45b7765f2880936cdb8bb0d08a2cb46889  docs/release/pfa18c_artifacts/m2_verifier_policy.json
a1cb864406c73fc674fc264e8a73efe93ebdbbf5f4aed0a05a9ee94641569c9f  docs/release/pfa18c_artifacts/m3_runtime_user_policy.json
8ebd036a5a71c914b5c8f44589505c9ba71dc5907e0e856403ed0961e5412fd8  docs/release/pfa18c_artifacts/m3_runtime_role_trust.json
76addba388521b9c04806ab81d560e1563ae59a75b33ea3fe61ed0cd2b4392f0  docs/release/pfa18c_artifacts/m1_audit_bucket_policy.json
9a4c5a8dad1f6bc7f6a8cb5510e3f8af9e5ec5065fedf75c0997e48698ef7ab0  docs/release/pfa18c_artifacts/m1_object_lock_configuration.json
8b11d567c758b490e3a4645e44a8f2e072e46e0b3d4e1344afd2b0bbc6ce34ae  docs/release/PHASE2_PFA18C_EXECUTION_READINESS_PACKET.md
eb8b246292105f15ef4e7ab73b75436f21ad8b6a95b513aed4ce8d8ce58c0fe7  docs/release/PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md
505fe850bdcf6cc8336d8e53d37514eea4a28df40810f24475096f76d813443c  docs/release/pfa18c_artifacts/README.md
```

Notes: `m3_runtime_role_trust.json` is the **placeholder** artifact (`<KMS_SIGNER_EXTERNAL_ID …>`); Device 2 uses it for the trust-**structure** comparison only and never learns, compares, or prints the live ExternalId. The two `.md` procedure files and the README are the copies committed at the pin; later commits (e.g. `7fa960b…`) add record entries but do not change the C1-10 procedure.

Device-2 verification of the download: `shasum -a 256 <file>` (or `openssl dgst -sha256 <file>`, LibreSSL is fine) must equal the digest above for every file. Any mismatch ⇒ stop; do not proceed to D2-5.

## C. C2-ONLY — DO NOT DOWNLOAD during this C1-10 Device-2 procedure

```
docs/release/pfa18c_artifacts/m3_runtime_role_policy.json
docs/release/pfa18c_artifacts/kms_key_policy_v1_binding_proof.json
docs/release/pfa18c_artifacts/kms_key_policy_v2_final.json
```

(They are retrieved at the separately authorized C2 stage; no KMS key exists today, so there is nothing to compare them against.)

## D. AUTHORITATIVE DEVICE-2 PROCEDURE

`docs/release/PHASE2_PFA18C_EXECUTION_READINESS_PACKET.md` at `c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd` (SHA-256 `8b11d567…`), section **§5a′ "C1-10 — Device-2 (M2) verifier setup and independent read-back"**, rows D2-4 … D2-8. The execution record (`eb8b2462…`) supplies the recorded expected values; the README (`505fe850…`) supplies the artifact-to-resource binding table and the F1/F3/F7 validation log.

## E. D2-4 THROUGH D2-7 (quoted from the reviewed artifact, then expanded into exact commands)

### E.1 Reviewed rows (verbatim from §5a′ at the pin)

| Step | Device | Action | Read-back / expected |
|---|---|---|---|
| D2-4 | Device 2 | obtain the reviewed artifacts **independently** (GitHub, commit `f8836e5` or later on `feature/venue-native-and-product-v2`, path `docs/release/pfa18c_artifacts/`) and verify sha256: `m1_ceremony_role_trust.json 89540f61…`, `m1_ceremony_role_policy.json 1fddd53b…`, `m2_verifier_policy.json 3082cc74…`, `m3_runtime_user_policy.json a1cb8644…`, `m1_audit_bucket_policy.json 76addba3…`, `m1_object_lock_configuration.json 9a4c5a8d…` | hashes match the execution record |
| D2-5 | Device 2 | **read-back + diff** (all `--profile verifier --region us-east-1`): `iam get-role SnatchIt-KMS-Ceremony` (trust diff; MaxSessionDuration 3600), `iam get-role-policy … pfa18c-ceremony` (diff), `iam list-attached-role-policies` (none); `iam get-policy` + `get-policy-version v1` for `SnatchIt-KMS-Verifier-ReadOnly` (diff), `iam list-attached-user-policies snatchit-kms-verifier` (exactly 2), `list-access-keys` (none); `iam get-user-policy snatchit-credential-sign-runtime pfa18c-runtime-assume-only` (diff); `iam get-role SnatchIt-CredentialSign-Runtime` (trust: principal = runtime user, action AssumeRole, condition key `sts:ExternalId` only — value never printed), `list-role-policies` (none), `list-access-keys snatchit-credential-sign-runtime` (none); `s3api get-bucket-policy` (diff, arrays order-insensitive), `get-public-access-block` (4×true), `get-bucket-encryption` (AES256), `get-object-lock-configuration` (COMPLIANCE, 3), `get-bucket-versioning` (Enabled); `cloudtrail describe-trails` (multi-region, validation, global events, us-east-1, no KmsKeyId), `get-trail-status` (IsLogging), `get-event-selectors` (All, mgmt, exclusions []) | every diff empty; every value as recorded |
| D2-6 | Device 2 | refusal probes as the verifier (effects if wrongly allowed in brackets): `kms create-alias --alias-name alias/pfa18c-probe --target-key-id 00000000-0000-0000-0000-000000000000` [NotFound is possible — non-discriminating, as learned at P3; record as such]; `s3api put-bucket-versioning … Status=Enabled` [no-op] → AccessDenied; `sts assume-role` into the ceremony role [none] → AccessDenied; `iam create-access-key --user-name snatchit-kms-verifier` [would create a key — explicitDeny simulated] → AccessDenied; `cloudtrail add-tags` on the trail [a tag] → AccessDenied | all denied |
| D2-7 | Device 2 | `cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=jose-admin --start-time 2026-09-08T02:40:00Z` → event names are exactly the C1 setup/read calls; `AttributeValue=root` for the window → none; also confirm the T1/T2 `AssumeRole` events and the probe `AccessDenied` events are visible from Device 2 | matches the execution record |

The pin `c4f562d…` is a descendant of `f8836e5` on the same branch, so it satisfies the reviewed "f8836e5 or later" wording exactly; this handoff pins it so the download is reproducible.

### E.2 Expanded commands (derived one-to-one from E.1; run on Device 2 only; `P="--profile verifier --region us-east-1 --no-cli-pager"` — on zsh define a function instead of an unquoted variable, e.g. `v() { aws "$@" --profile verifier --region us-east-1 --no-cli-pager; }`)

**D2-4 — retrieve and verify (all 10 files):**
```bash
mkdir -p ~/pfa18c-verify/docs/release/pfa18c_artifacts && cd ~/pfa18c-verify
B=https://raw.githubusercontent.com/SnatchIt-app/snatchit/c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd
for f in docs/release/pfa18c_artifacts/m1_ceremony_role_trust.json docs/release/pfa18c_artifacts/m1_ceremony_role_policy.json docs/release/pfa18c_artifacts/m2_verifier_policy.json docs/release/pfa18c_artifacts/m3_runtime_user_policy.json docs/release/pfa18c_artifacts/m3_runtime_role_trust.json docs/release/pfa18c_artifacts/m1_audit_bucket_policy.json docs/release/pfa18c_artifacts/m1_object_lock_configuration.json docs/release/PHASE2_PFA18C_EXECUTION_READINESS_PACKET.md docs/release/PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md docs/release/pfa18c_artifacts/README.md; do curl -fsSL "$B/$f" -o "$f"; done
shasum -a 256 docs/release/pfa18c_artifacts/*.json docs/release/pfa18c_artifacts/README.md docs/release/*.md
```
Compare every digest with section B. **Stop on any mismatch.**

**D2-5 — independent read-back + diff** (`ART=docs/release/pfa18c_artifacts`; `jq -S` normalizes key order; for the bucket policy also sort scalar arrays — S3 reorders `Principal.AWS`):
```bash
v() { aws "$@" --profile verifier --region us-east-1 --no-cli-pager --output json; }; ART=docs/release/pfa18c_artifacts
# ceremony role
v iam get-role --role-name SnatchIt-KMS-Ceremony --query 'Role.{Arn:Arn,MaxSessionDuration:MaxSessionDuration}'
v iam get-role --role-name SnatchIt-KMS-Ceremony --query Role.AssumeRolePolicyDocument | jq -S . | diff - <(jq -S . $ART/m1_ceremony_role_trust.json) && echo TRUST-IDENTICAL
v iam get-role-policy --role-name SnatchIt-KMS-Ceremony --policy-name pfa18c-ceremony --query PolicyDocument | jq -S . | diff - <(jq -S . $ART/m1_ceremony_role_policy.json) && echo POLICY-IDENTICAL
v iam list-role-policies --role-name SnatchIt-KMS-Ceremony --query PolicyNames          # expect ["pfa18c-ceremony"]
v iam list-attached-role-policies --role-name SnatchIt-KMS-Ceremony --query AttachedPolicies   # expect []
# verifier user (managed policy, F7)
v iam get-policy --policy-arn arn:aws:iam::652872010073:policy/SnatchIt-KMS-Verifier-ReadOnly --query 'Policy.{DefaultVersionId:DefaultVersionId,AttachmentCount:AttachmentCount}'   # expect v1, 1
v iam get-policy-version --policy-arn arn:aws:iam::652872010073:policy/SnatchIt-KMS-Verifier-ReadOnly --version-id v1 --query PolicyVersion.Document | jq -S . | diff - <(jq -S . $ART/m2_verifier_policy.json) && echo VERIFIER-POLICY-IDENTICAL
v iam list-attached-user-policies --user-name snatchit-kms-verifier --query 'AttachedPolicies[].PolicyArn'   # expect exactly the two ARNs: …policy/SnatchIt-KMS-Verifier-ReadOnly and arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess
v iam list-user-policies --user-name snatchit-kms-verifier --query PolicyNames             # expect []
v iam list-access-keys --user-name snatchit-kms-verifier --query AccessKeyMetadata          # expect []
v iam list-mfa-devices --user-name snatchit-kms-verifier --query 'MFADevices[].SerialNumber'   # expect one u2f/… entry (the Device-2 passkey)
# runtime user + role (O1; trust structure only — the ExternalId VALUE is never printed or compared)
v iam get-user-policy --user-name snatchit-credential-sign-runtime --policy-name pfa18c-runtime-assume-only --query PolicyDocument | jq -S . | diff - <(jq -S . $ART/m3_runtime_user_policy.json) && echo RUNTIME-USER-POLICY-IDENTICAL
v iam list-access-keys --user-name snatchit-credential-sign-runtime --query AccessKeyMetadata   # expect []
v iam get-role --role-name SnatchIt-CredentialSign-Runtime --query 'Role.AssumeRolePolicyDocument' | jq '{StatementCount:(.Statement|length), Principal:.Statement[0].Principal.AWS, Action:.Statement[0].Action, ConditionOperators:(.Statement[0].Condition|keys), ConditionKeys:[.Statement[0].Condition[]|keys[]], ExternalIdLength:(.Statement[0].Condition.StringEquals["sts:ExternalId"]|length)}'
#   expect: 1 statement; Principal = arn:aws:iam::652872010073:user/snatchit-credential-sign-runtime; Action sts:AssumeRole; ["StringEquals"]; ["sts:ExternalId"]; length 64
diff <(v iam get-role --role-name SnatchIt-CredentialSign-Runtime --query Role.AssumeRolePolicyDocument | jq -S '.Statement[0].Condition.StringEquals["sts:ExternalId"]="<REDACTED>"') <(jq -S '.Statement[0].Condition.StringEquals["sts:ExternalId"]="<REDACTED>"' $ART/m3_runtime_role_trust.json) && echo RUNTIME-TRUST-STRUCTURE-IDENTICAL
v iam list-role-policies --role-name SnatchIt-CredentialSign-Runtime --query PolicyNames; v iam list-attached-role-policies --role-name SnatchIt-CredentialSign-Runtime --query AttachedPolicies   # expect [] and []
# audit bucket
aws s3api get-bucket-policy --bucket snatchit-audit-652872010073 --query Policy --output text --profile verifier --region us-east-1 --no-cli-pager | jq -S 'walk(if type=="array" and all(.[]; type!="object") then sort else . end)' | diff - <(jq -S 'walk(if type=="array" and all(.[]; type!="object") then sort else . end)' $ART/m1_audit_bucket_policy.json) && echo BUCKET-POLICY-EQUIVALENT
v s3api get-public-access-block --bucket snatchit-audit-652872010073 --query PublicAccessBlockConfiguration     # expect four true
v s3api get-bucket-encryption --bucket snatchit-audit-652872010073 --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault'   # expect {"SSEAlgorithm":"AES256"} and no KMSMasterKeyID
v s3api get-object-lock-configuration --bucket snatchit-audit-652872010073 | jq -S . | diff - <(jq -S '{ObjectLockConfiguration: .}' $ART/m1_object_lock_configuration.json) && echo OBJECT-LOCK-IDENTICAL   # COMPLIANCE, Years 3
v s3api get-bucket-versioning --bucket snatchit-audit-652872010073 --query Status                                 # expect "Enabled"
# trail
v cloudtrail describe-trails --trail-name-list snatchit-audit-trail --query 'trailList[0].{Name:Name,S3BucketName:S3BucketName,HomeRegion:HomeRegion,IsMultiRegionTrail:IsMultiRegionTrail,IncludeGlobalServiceEvents:IncludeGlobalServiceEvents,LogFileValidationEnabled:LogFileValidationEnabled,KmsKeyId:KmsKeyId}'
#   expect: snatchit-audit-trail / snatchit-audit-652872010073 / us-east-1 / true / true / true / null
v cloudtrail get-trail-status --name snatchit-audit-trail --query '{IsLogging:IsLogging,LatestDeliveryError:LatestDeliveryError}'   # expect true, null
v cloudtrail get-event-selectors --trail-name snatchit-audit-trail --query 'EventSelectors[0].{ReadWriteType:ReadWriteType,IncludeManagementEvents:IncludeManagementEvents,ExcludeManagementEventSources:ExcludeManagementEventSources}'   # expect All / true / []
```

**D2-6 — refusal probes as the verifier** (each is a mutation *attempt*; the effect if wrongly allowed is in brackets; expected result `AccessDenied` except where noted):
```bash
aws kms create-alias --alias-name alias/pfa18c-probe --target-key-id 00000000-0000-0000-0000-000000000000 --profile verifier --region us-east-1 --no-cli-pager
#   NotFoundException is possible (no key exists) — NON-DISCRIMINATING; record the exact error text, do not count as pass or fail
aws s3api put-bucket-versioning --bucket snatchit-audit-652872010073 --versioning-configuration Status=Enabled --profile verifier --region us-east-1 --no-cli-pager   # [no-op if allowed] expect AccessDenied
aws sts assume-role --role-arn arn:aws:iam::652872010073:role/SnatchIt-KMS-Ceremony --role-session-name probe --profile verifier --region us-east-1 --no-cli-pager --query AssumedRoleUser   # [none] expect AccessDenied
aws iam create-access-key --user-name snatchit-kms-verifier --profile verifier --region us-east-1 --no-cli-pager   # [would create a key; explicit deny simulated] expect AccessDenied — if it ever succeeds, STOP and report the AccessKeyId only (never the secret); the coordinator will have it deactivated by the owner
aws cloudtrail add-tags --resource-id arn:aws:cloudtrail:us-east-1:652872010073:trail/snatchit-audit-trail --tags-list Key=pfa18c-probe,Value=d2-6 --profile verifier --region us-east-1 --no-cli-pager   # [a tag] expect AccessDenied
```

**D2-7 — CloudTrail read-back from Device 2** (event history; index lag ≤ 15 min; contents are metadata only):
```bash
v() { aws "$@" --profile verifier --region us-east-1 --no-cli-pager --output json; }
v cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=jose-admin --start-time 2026-09-08T02:40:00Z --max-results 50 | jq -c '.Events[] | {EventTime, EventName, EventSource}'
#   expect ONLY the C1 setup/read calls (CreateRole, PutRolePolicy, CreateUser, CreatePolicy, AttachUserPolicy, CreateLoginProfile, CreateBucket, PutBucketPublicAccessBlock, PutBucketEncryption, PutBucketPolicy, PutObjectLockConfiguration, CreateTrail, PutEventSelectors, StartLogging, AssumeRole ×2, the coordinator's Get*/List*/Describe*/LookupEvents/SimulatePrincipalPolicy reads, CreateOAuth2Token) — anything else ⇒ report it
v cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=root --start-time 2026-09-08T02:40:00Z --max-results 50 --query 'Events[].{T:EventTime,N:EventName}'   # expect []
v cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole --start-time 2026-09-08T04:20:00Z --max-results 50 | jq -c '.Events[] | .CloudTrailEvent | fromjson | select((.requestParameters.roleArn // "")|test("SnatchIt-KMS-Ceremony")) | {eventTime, mfa: .userIdentity.sessionContext.attributes.mfaAuthenticated, serialNumber: .requestParameters.serialNumber, errorCode}'
#   expect: 04:24:06Z (mfa true, serialNumber null = T1) and 04:24:43Z (mfa true, serialNumber arn:aws:iam::652872010073:mfa/jose-admin-totp = T2)
for EN in AddTags PutBucketVersioning CreateAlias GetUser AssumeRole; do v cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=$EN --start-time 2026-09-08T04:30:00Z --max-results 50 | jq -c --arg en $EN '.Events[] | .CloudTrailEvent | fromjson | select((.userIdentity.arn // "")|test("assumed-role/SnatchIt-KMS-Ceremony")) | {eventTime, eventName, errorCode}'; done
#   expect: AddTags 04:31:22Z AccessDenied; PutBucketVersioning 04:32:02Z AccessDenied; CreateAlias 04:32:32Z NotFoundException; GetUser 04:36:16Z AccessDenied; AssumeRole 04:36:50Z AccessDenied
```

## F. M2 COMPLETION CONDITIONS (all must pass; none is satisfied by authentication alone)

1. **Retrieval integrity (D2-4, DEVICE-2 REQUIRED):** all ten digests in section B reproduced on Device 2 from the pinned commit; none of the three C2-only files downloaded.
2. **Verifier-profile restrictions (D2-3/D2-6, DEVICE-2 REQUIRED + CLAUDE-OBSERVED corroboration):** identity = `arn:aws:iam::652872010073:user/snatchit-kms-verifier` (already OWNER-RETURNED; corroborated by the coordinator from CloudTrail `ConsoleLogin`/`CreateOAuth2Token`/`GetCallerIdentity` events with the verifier identity and `mfaAuthenticated: true`); no access key exists for the verifier before or after (the owner/coordinator re-reads `list-access-keys` → `[]`); the four discriminating probes return `AccessDenied` (`PutBucketVersioning` citing the explicit bucket-policy or identity deny, `AssumeRole` into the ceremony role, `CreateAccessKey`, `AddTags`); the `CreateAlias` probe is recorded as non-discriminating whatever it returns.
3. **Independent audit read-back (D2-5, DEVICE-2 REQUIRED):** every diff empty and every value equal to the recorded expectation: ceremony trust + policy; verifier managed policy v1 + exactly two attachments; runtime user policy; runtime role trust **structure** (principal, action, `StringEquals`, key `sts:ExternalId`, length 64 — the value is never printed, transmitted or compared); no permissions on the runtime role; no access keys on either user; bucket policy equivalent (arrays order-insensitive); PAB 4×true; SSE-S3; Object Lock COMPLIANCE 3 years; versioning Enabled; trail multi-region / validation / global events / us-east-1 / no KMS key / logging / selectors `All` + management + no exclusions.
4. **CloudTrail corroboration (D2-7 from Device 2 + D2-8 by the coordinator):** Device 2 sees exactly the C1 `jose-admin` activity and no root activity in the window, the T1/T2 `AssumeRole` events (serial present only on T2) and the C1-9 probe outcomes; the coordinator then corroborates Device 2's own D2-3/D2-6 activity in CloudTrail under the verifier identity with `mfaAuthenticated: true`.
5. **KMS / key-policy checks — not applicable at this stage:** no KMS key exists; `kms list-keys` from the verifier must return `[]`. Key-policy read-back (`get-key-policy`, `get-public-key`, `describe-key`) belongs to the separately authorized C2, when Device 2 also derives D5 independently and runs the §5.3 binding-proof verification.
6. **ExternalId treatment:** Device 2 compares only the trust structure (E.2 redacted diff); the live value is never displayed, copied, or compared; the placeholder artifact is the only reference.
7. **Recording:** the coordinator records D2-4…D2-7 results with event IDs in `PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md`; only then are **M2 satisfied** and **M1 (Model B) complete** recorded, closing C1 (PHASE-1 GATE). The next stage, C2 (CreateKey + binding proof + P3′), requires its own authorization phrase ("AUTHORIZE PFA-18C CREATEKEY") and is not implied by M2.

Out of scope for Device 2 at any time in C1-10: `jose-admin`, root, any mutation, any key, any secret.
