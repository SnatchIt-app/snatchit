# PFA-18C — OWNER CEREMONY RUNBOOK (single-founder, C18)

**For:** the founder/owner, personally. **Coordinator:** Claude A (read-back verifier only — never runs an AWS or production mutation, never sees a secret).
**Governs:** the DARK bootstrap of the production ES256 trust root (one AWS KMS key → one `kernel.signing_key` row) and the reads that prove it. It does NOT authorize issuance, scanning, or any migration apply — those are separate owner acts listed in §C.
**Source documents:** ratification `docs/architecture/_governance/PFA_18C_OWNER_RATIFICATION.md` (the authority) · engineering runbook `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` (§6.1 artifact, §5.3 binding proof, §7 verification, §10 rollback; read its 2026-09-05 corrections at §7.3 and §13) · readiness report `docs/release/PHASE2_PFA18C_BOOTSTRAP_READINESS_REPORT.md` · artifacts `docs/release/pfa18c_artifacts/` · audit `docs/release/PHASE2_PFA18C_DARK_PRECEREMONY_AUDIT.md`.
**Rules that never relax:** every AWS command carries `--profile snatchit-admin --region us-east-1`; nothing is pasted into chat except command OUTPUT with secrets absent; access keys, session tokens, DB passwords, private keys and connection strings never appear in any file or message; one stage at a time; Claude reads back, the owner runs.

---

## §0 NO-GO conditions (check FIRST — any one ⇒ stop before §A)

| # | Condition | Why | Status today |
|---|---|---|---|
| NG-1 | Account `652872010073` is still on the **AWS Free plan** and the owner has not authorized a paid-plan upgrade or a paid member account | Free plan closes after 6 months / credit exhaustion (**2027-03-05T17:57:11Z** here), data erased after 90 more days; Object-Lock COMPLIANCE retention would end with account closure; KMS availability on the Free plan is not stated by AWS | **NO-GO** (owner decision: keep Free plan) |
| NG-2 | Model A account layout (separate audit account; workload key in a *member* account, not the Organizations management account) not settled | SCPs never bind a management account; every ARN/account id in the artifacts must be final before CreateKey | open owner decision |
| NG-3 | Production ledger/tip differ from the recorded state (ledger 124, numeric tip 109) or `kernel.signing_key` is not empty | the bootstrap is a once-only act on a known substrate | verify in §A |
| NG-4 | Any M1/M2/M3 artifact still has a placeholder (`<RETENTION_YEARS>`, `<KMS_SIGNER_EXTERNAL_ID>`, `<PRODUCTION_KMS_KEY_ARN>` except where it is filled after CreateKey) | deny-set must be code, read back by Device 2 | check before §C1 |
| NG-5 | Device 2 (M2) not physically separate, or its read-only IAM user not yet created/verified | independent read-back is a ratified precondition | check before §C1 |
| NG-6 | CI not green on the commit whose migrations will later be applied, or migrations 110–114 not merged per the `AUTODEPLOY-VERIFIED-OFF` rule | the guard (110) and recovery (111) must be the reviewed bytes | check before §C4 |

The Free-plan no-go (NG-1) is the controlling one: **while it stands, §C1–§C3 are not authorized in this account.** Everything in §A can still be done.

## §A Preflight — READ ONLY (owner runs; Claude reads back)

Run each; paste the OUTPUT only.

**A1 AWS identity, plan, region**
```bash
aws sts get-caller-identity --profile snatchit-admin --region us-east-1
aws account get-account-information --profile snatchit-admin --region us-east-1 2>/dev/null || echo "plan: read from console Billing → Free plan card"
```
Expected: account `652872010073`, principal `jose-admin`; plan state as recorded (FREE ⇒ NG-1 stands).

**A2 AWS baseline unchanged (no trail / bucket / roles / keys yet)**
```bash
aws cloudtrail describe-trails --profile snatchit-admin --region us-east-1
aws s3api list-buckets --profile snatchit-admin --region us-east-1 --query 'Buckets[].Name'
aws iam list-roles --profile snatchit-admin --region us-east-1 --query 'Roles[?starts_with(RoleName,`SnatchIt`)].RoleName'
aws iam list-users --profile snatchit-admin --region us-east-1 --query 'Users[].UserName'
aws kms list-keys --profile snatchit-admin --region us-east-1
aws iam list-access-keys --profile snatchit-admin --region us-east-1 --user-name jose-admin --query 'AccessKeyMetadata[].{Id:AccessKeyId,Status:Status,Created:CreateDate}'
```
Expected: no trail, no `snatchit-audit-*` bucket, no `SnatchIt*` roles, no customer KMS keys, no long-lived keys other than the documented baseline. Any drift ⇒ record it and stop.

**A3 Production database — read only** (from the owner's machine; Claude never holds `$PROD_DB_URL`)
```bash
psql "$PROD_DB_URL" -tAc "select count(*) from supabase_migrations.schema_migrations;"                       # expected 124
psql "$PROD_DB_URL" -tAc "select max(version) from supabase_migrations.schema_migrations where version ~ '^[0-9]{3}$';"   # expected 109
psql "$PROD_DB_URL" -tAc "select count(*) from kernel.signing_key;"                                              # expected 0
psql "$PROD_DB_URL" -tAc "select key, value from catalog.platform_config where key in ('feature.native_issuance_enabled','feature.native_scanning_enabled','signing.monitor_enabled','signing.expected_key_fingerprint') order by key, version desc;"
# expected: issuance false, scanning false, monitor false, fingerprint null (highest version wins)
psql "$PROD_DB_URL" -tAc "select to_regprocedure('kernel.guard_signing_key_insert()') is not null as guard_110_present, to_regprocedure('kernel.approve_signing_key_recovery(uuid,text,text,text)') is not null as recovery_111_present;"
# expected today: false | false (110/111 unapplied)
```
**A4 Lifecycle parked-state check (CORRECTED — replaces runbook §7.3's six-item loop)**
```bash
for f in \
  "kernel.provision_signing_key('global',null,'-','-',now(),'p','p')" \
  "kernel.rotate_signing_key('00000000-0000-0000-0000-0000000000b0','-','-','p','p')" \
  "kernel.provision_pass_type_cert('-','-','-','-','-',now(),now()+interval '1 day','p','p')" \
  "kernel.rotate_pass_type_cert('00000000-0000-0000-0000-000000000000','-','-','-',now(),now()+interval '1 day','p','p')" \
  "kernel.revoke_pass_type_cert('00000000-0000-0000-0000-000000000000','p','p')" ; do
  echo "== $f"; psql "$PROD_DB_URL" -tAc "select $f;" 2>&1 | grep -o 'dual_control_unavailable' || echo "!! NOT PARKED — STOP"; done
# revoke_signing_key is UN-parked since 106 (in production): it must REFUSE, not succeed —
echo "== revoke"; psql "$PROD_DB_URL" -tAc "select kernel.revoke_signing_key('00000000-0000-0000-0000-0000000000b0','p',0,'p');" 2>&1 | grep -oE 'insufficient_privilege|step_up_(required|unavailable)|not_found' || echo "!! revoke did not refuse — STOP"
```
**A5 Repository state** (Claude runs; owner reads): `git rev-parse HEAD` = the audited commit; CI run green; `deno-check` job green; migration checksums equal the audit §1 table.

## §B Artifacts to capture (evidence pack; never secrets)

| When | Artifact | Where it goes |
|---|---|---|
| §A | every §A command output (identity, plan, baseline, DB counts, parked-state) | execution record `PHASE2_PFA18C_SINGLE_FOUNDER_KMS_BOOTSTRAP_EXECUTION.md`, dated session |
| §C1 | CloudTrail `TrailARN`, S3 bucket name + Object-Lock config read-back (`get-object-lock-configuration`), bucket policy read-back, IAM role/user ARNs + policy read-backs (`get-role`, `get-role-policy`, `get-user-policy`) — from **Device 2** | execution record + `pfa18c_artifacts/` diff result |
| §C2 | `KeyMetadata` (KeyId, **Arn**, KeySpec `ECC_NIST_P256`, KeyUsage `SIGN_VERIFY`, Origin `AWS_KMS`, CreationDate) — **the Arn is D4** | execution record |
| §C2 | `pub.pem` / `pub.der` from Device 2's independent `get-public-key`; D5 fingerprint computed on BOTH devices: `openssl pkey -pubin -in pub.pem -outform DER \| sha256sum` — lowercase hex, 64 chars; Device 2 states first | execution record (public material only) |
| §C2 | §5.3 binding proof: challenge, `kms sign` output (signature only), local `openssl dgst -verify` PASS; altered-message FAIL; wrong-key FAIL | execution record |
| §C3 | the three `NOTICE` lines from the §6.1 artifact and `COMMIT`; §7.1 row read-back (key_id `…b0`, scope global, status active, algorithm ES256, kms_handle_ref = D4 ARN, public_key = pub.pem, not_before, not_after) | execution record |
| §C3 | §7.4 no-shadow-key read-back; §7.5 dry-run mint rolled back | execution record |
| §C5 | config read-back after monitor arming; first `kernel.check_signing_key_invariants()` result | execution record |
| all | CloudTrail event ids for every mutation (`CreateKey`, `PutKeyPolicy` v1→v2, `Sign` for the proof, IAM writes) | execution record |

## §C Production mutations — each requires the owner's EXPLICIT written authorization, in order, one at a time

Claude issues the commands for ONE stage, the owner runs them and pastes outputs, Claude reads back, only then the next stage.

| Stage | Mutation | Authorization phrase required | Precondition |
|---|---|---|---|
| **C1** M1/M2/M3 setup | CloudTrail trail + audit bucket (Object-Lock COMPLIANCE, `<RETENTION_YEARS>` decided) + bucket policy; IAM: `SnatchIt-KMS-Ceremony` role (trust + policy), `snatchit-kms-verifier` user (M2, Device 2), `snatchit-credential-sign-runtime` user + `SnatchIt-CredentialSign-Runtime` role (M3, ExternalId decided). Apply the JSON in `pfa18c_artifacts/` verbatim, then Device 2 reads each back and diffs. | "AUTHORIZE PFA-18C M1/M2/M3 SETUP" | §0 clear (NG-1 resolved), §A green, placeholders filled |
| **C2** CreateKey + binding proof | `kms create-key` (ECC_NIST_P256 / SIGN_VERIFY / single-region, key policy **v1**); Device 2 `get-public-key`; D5 fingerprints match on both devices; §5.3 binding proof (ceremony role signs Device 2's challenge; Device 2 verifies; altered message + wrong key fail); `put-key-policy` **v2** (ceremony loses Sign; runtime role gets Sign on the exact ARN only) | "AUTHORIZE PFA-18C CREATEKEY" | C1 read back green |
| **C3** Trust-root DB commit | the §6.1 artifact with `-v ALGORITHM="ES256"` explicit, `KMS_HANDLE_REF` = the D4 ARN, `PUBLIC_KEY_PEM` = Device 2's pub.pem, `EXPECTED_FINGERPRINT` = D5; three NOTICEs; COMMIT; §7.1–§7.5 read-backs | "AUTHORIZE PFA-18C TRUST-ROOT DB COMMIT" | C2 read back green; `count(*)=0` re-confirmed seconds before |
| **C4** Apply migrations 110–114 (order 110,111,112,113,114) | `supabase db push --include-all` from the merged, CI-green commit; then read-backs: guard trigger present, recovery functions present, venue 87 / five-schema 296, `get_signing_keys_door` service_role-only | "AUTHORIZE PFA-18C MIGRATIONS 110-114" | C3 done; merge rule honoured (`AUTODEPLOY-VERIFIED-OFF`, `git_branch` empty). Note: 110's guard permits the already-present `…b0` row; applying 110 BEFORE C3 is also valid (the artifact satisfies rules 1–11) — either order is safe, but choose and record one |
| **C5** Monitor arming | `signing.expected_key_fingerprint` := D5; `signing.expected_max_not_after` only if D6 chose non-NULL; then `signing.monitor_enabled := true`; run `kernel.check_signing_key_invariants()` once | "AUTHORIZE PFA-18C MONITOR ARMING" | C3 read back green |
| **C6** Runtime secrets + dark deploy of `credential-sign` / `door-manifest` / `door-session` (E2 env: `KMS_PROVIDER=aws`, `AWS_REGION`, `KMS_SIGNER_ROLE_ARN`, `KMS_SIGNER_EXTERNAL_ID`, base credentials of the runtime USER only — never the ceremony principal) | "AUTHORIZE PFA-18C DARK DEPLOY" | C4; O1 adoption decided by the owner |
| **C7** M5 live proof | one throwaway atom on a non-saleable test event; one `credential-sign` call; one `door-manifest` call on a real open episode; CloudTrail: exactly one `Sign` per call by the runtime role; flags stay false | "AUTHORIZE PFA-18C M5" | C6 |
| **C8** *(later, separate)* flip `feature.native_issuance_enabled` / `feature.native_scanning_enabled` | owner act; outside this runbook | — | M5 + M6 + Model A green |

Not authorized by anything above: rotation, revocation drills against the production key, recovery drills, any Sign outside C2/C7, any change to ratification wording.

## §D Post-mutation verification (owner runs; Claude reads back)

- **After C1:** Device 2 read-back equals `pfa18c_artifacts/*.json` (diff empty except filled placeholders); CloudTrail logging `IsLogging=true`; bucket `ObjectLockEnabled=Enabled`, mode COMPLIANCE, retention as decided; ceremony/verifier/runtime principals denied bucket mutation (policy read-back).
- **After C2:** `describe-key` shows ECC_NIST_P256 / SIGN_VERIFY / Enabled; key policy read-back = `kms_key_policy_v2_final.json` with the real runtime role ARN; ceremony role can no longer `kms sign` (expect AccessDenied — a READ of denial, run from Device 2's perspective by attempting with the verifier user); D5 fingerprint identical on both devices; binding-proof transcript recorded.
- **After C3 (runbook §7):** §7.1 row equals the intended values; §7.2 the resolver returns `…b0` as the active global key; §7.3 as corrected in §A4; §7.4 exactly one row, no per_event/per_venue shadow; §7.5 dry-run mint in a rolled-back transaction; `feature.native_issuance_enabled` still false.
- **After C4:** `kernel.guard_signing_key_insert()` present and enabled; a rehearsal-style probe INSERT of a second global key refuses `active_global_exists` (run inside `begin; … rollback;`); `select count(*) from kernel.signing_key_recovery_approval` = 0; `venue.get_manifest_signing_context()` as service_role returns `status:'ok'`, `key_id` = `…b0`, `algorithm` ES256 (read-only, no signing); `venue.get_signing_keys_door` refuses anon/authenticated.
- **After C5:** `kernel.check_signing_key_invariants()` reports the fingerprint match and one active global key; a deliberate wrong fingerprint is NOT to be tested in production.
- **After C6/C7:** edge logs show `signed` with `key_id` = `…b0`; Sentry has no `sign_verify_failed` / `kms_security_error`; CloudTrail `Sign` count equals the number of proof calls; `/keys` from a real door session returns the `…b0` row with the same `public_key` as the DB; `verifyDoorManifestSignature` passes on the returned artifact.

## §E Abort and rollback

**Abort immediately (no mutation proceeds) if:** any §A read differs from expected; any read-back after C1/C2 differs from the artifact; the D5 fingerprints disagree between devices; the §5.3 proof fails or the altered-message/wrong-key checks PASS; the §6.1 artifact raises any `CEREMONY ABORT`; `count(*)` is not 0 immediately before C3; any command needed a credential outside the designated principal; anything asks the owner to paste a secret.

**Rollback matrix**

| After | Rollback | Availability |
|---|---|---|
| C1 | delete the IAM roles/users and trail; the audit bucket under COMPLIANCE Object-Lock **cannot be emptied before retention** — an aborted ceremony leaves it in place until the retention (or account closure on the Free plan) | partial by design |
| C2 | `kms schedule-key-deletion` (7–30 day window) after removing all Sign grants; record the pending-deletion state | yes |
| C3 | runbook §10 `signing_key_bootstrap_ROLLBACK.sql` — available ONLY while no `kernel.tickets` / `wallet_pass` / `door_manifest_entry` / `door_manifest_delta` row references `…b0` (FK RESTRICT + explicit guard); after the first mint it is unavailable — use rotation/revocation instead | until first mint |
| C4 | `supabase/rollbacks/114…110` in reverse order (rehearsed: each step inverts the census and definition hash exactly); production is forward-only by policy, so this is an emergency measure requiring its own authorization | mechanically yes; policy: forward-only |
| C5 | set `signing.monitor_enabled := false` (config append) | yes |
| C6 | remove the secrets / redeploy the previous function version | yes |
| C7 | none needed (read-only effects: one token, one artifact, CloudTrail events) | — |

**Compromise during or after the ceremony:** runbook §13 as corrected — Step 1 flip issuance false (single admin); Step 2 remove `kms:Sign` from every principal and schedule deletion (the control that actually stops signing); Step 3 `kernel.revoke_signing_key` (platform_admin + aal2, acknowledges live credentials, force-closes open episodes); re-bootstrap only through the 111 two-person recovery.

## §F Free-plan no-go — restated for the record

Under the owner's standing decision (keep the AWS Free plan): **C1–C3 are NOT authorized in account `652872010073`.** Anything created there inherits the 2027-03-05 closure horizon and Object-Lock COMPLIANCE would be defeated by account closure. Paths that would lift NG-1 (each an owner decision, none taken): upgrade to a paid plan before CreateKey (≈ $1–2/month: KMS key $1/month prorated, asymmetric Sign $0.15 per 10,000, first CloudTrail management-event copy free); or create the signing workload in a paid member account under the Model-A layout (which must be settled before CreateKey anyway). No billing change is performed or implied by this runbook.
