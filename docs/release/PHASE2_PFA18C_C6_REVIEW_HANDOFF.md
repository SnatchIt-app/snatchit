# PFA-18C — C6 RUNTIME SECRETS + DARK DEPLOY — REVIEW HANDOFF (rev 1) — **NOT AUTHORIZED · NOTHING EXECUTED**

**Date:** 2026-09-11 · **Coordinator:** Claude B · **Companion:** `PHASE2_PFA18C_C6_DARK_DEPLOY_REVIEW_PACKAGE.md` (design, E2 env contract, rollback). This handoff turns it into the owner/Mac 2 action list.
**C6 requires the separate exact owner phrase `AUTHORIZE PFA-18C DARK DEPLOY`.** This document is not that authorization. **C6 is dark: no deployed function is ever invoked under C6.** An invocation of `credential-sign` with the production key would sign a credential = **T3** (Model A first; M5 ruling pending §5d).

## 0. State at handoff (CLAUDE-OBSERVED 2026-09-11T01:49–01:50Z)
C1–C5 COMPLETE (monitor armed, pin v2 = D5, first check `ok/match`, cron daily 05:23Z) · KMS key `45907419…` Enabled, policy v2, runtime role bound to the exact ARN · **runtime user access keys 0** · **no `KMS_*`/`AWS_*` Supabase secret** · **11 legacy edge functions only; `credential-sign`/`door-manifest`/`door-session` not deployed** · flags issuance/scanning **false** · migration 121 review-only (PR #58 draft; hardening, not a C6 blocker) · Model A not started.

## 1. Prerequisites — status and owner decisions

| # | Prerequisite | Status | Owner action |
|---|---|---|---|
| P1 | C5 COMPLETE | **done** (record) | — |
| P2 | Migration 121 (hardening) | draft PR #58; **not required** for C6 | decide sequencing with Claude A (after Build 16); C6 may precede or follow 121 |
| P3 | 086↔112/113 drift (122) | needed before **scanning flip** only | — |
| P4 | Runtime identities: user policy assume-only; role trust `sts:ExternalId`; role policy `Sign` on D4 only; key policy v2 | **PASS** | — |
| P5 | No `KMS_*`/`AWS_*` secrets present | **PASS** | — |
| P6 | Native edges not deployed | **PASS** | — |
| P7 | **Deploy source** | the four function trees are byte-identical on `admin/operating-console @ 562fda9` and `feature/venue-native-and-product-v2 @ HEAD` (`credential-sign` `8acff379…`, `door-manifest` `9cd883d0…`, `door-session` `910eef73…`, `_shared` `20fda4a1…`); E2 commit `72d4e90` is an ancestor of both; CI `deno check` covers `_shared/offline-verify.ts`, `credential-sign/credential.ts`, `credential-sign/kms-taxonomy.ts` | **choose the checkout to deploy from** (recommended: the admin worktree at the CI-green tip used for C4; re-verify the four tree hashes on the day) |
| P8 | Local inputs on Mac 1: `$HOME/pfa18c-local/m3_runtime_role_trust.filled.json` (ExternalId, from C1-3) present; `$HOME/pfa18c-local/` mode 700 | owner-side | confirm the file exists (`ls -l`, never `cat` in chat) |
| P9 | Detection plan | coordinator daily CloudTrail lookups: `AssumeRole` into `SnatchIt-CredentialSign-Runtime` by any principal, `Sign` by any principal; alert on any non-zero count | — |
| P10 | O1 adopted (packet D3) | confirmed | — |
| P11 | Supabase CLI linked to `hqycwntpfoztoinemqns` in the deploy checkout; CLI 2.115.0 pin | PASS (admin worktree) | — |

## 2. Owner actions (Mac 1, `jose-admin` + Supabase CLI), in order — each pastes only the stated read-back lines

**C6-1 — one access key for the runtime user (secret written only to a local file):**
```bash
umask 077 && mkdir -p "$HOME/pfa18c-local" && aws iam create-access-key --profile snatchit-admin --region us-east-1 --no-cli-pager --user-name snatchit-credential-sign-runtime --output json > "$HOME/pfa18c-local/runtime-key.json" && python3 -c 'import json;d=json.load(open("'"$HOME"'/pfa18c-local/runtime-key.json"))["AccessKey"];print("access_key_id_prefix",d["AccessKeyId"][:8],"status",d["Status"],"created",d["CreateDate"])'
```
Return: the `access_key_id_prefix … status Active` line (the key id prefix is not secret; the secret never prints). Coordinator read-back: `list-access-keys` → 1 Active; CloudTrail `CreateAccessKey` ×1 by `jose-admin`.

**C6-2 — build and validate the env file (never displayed):**
```bash
python3 - <<'EOF'
import json, os, re, stat
home=os.environ['HOME']; p=f"{home}/pfa18c-local"
key=json.load(open(f"{p}/runtime-key.json"))["AccessKey"]
trust=json.load(open(f"{p}/m3_runtime_role_trust.filled.json"))
ext=trust["Statement"][0]["Condition"]["StringEquals"]["sts:ExternalId"]
env={"KMS_PROVIDER":"aws","AWS_REGION":"us-east-1","KMS_SIGNER_ROLE_ARN":"arn:aws:iam::652872010073:role/SnatchIt-CredentialSign-Runtime","KMS_SIGNER_EXTERNAL_ID":ext,"AWS_ACCESS_KEY_ID":key["AccessKeyId"],"AWS_SECRET_ACCESS_KEY":key["SecretAccessKey"]}
ok=[re.fullmatch(r"[a-z]{2}(-[a-z]+)+-\d",env["AWS_REGION"]) is not None, re.fullmatch(r"arn:aws:iam::\d{12}:role/[\w+=,.@-]+",env["KMS_SIGNER_ROLE_ARN"]) is not None, re.fullmatch(r"[\w+=,.@:/-]{2,1224}",ext) is not None, env["AWS_ACCESS_KEY_ID"].startswith("AKIA"), len(env["AWS_SECRET_ACCESS_KEY"])>=40]
with open(f"{p}/c6.env","w") as f:
    for k,v in env.items(): f.write(f"{k}={v}\n")
os.chmod(f"{p}/c6.env", stat.S_IRUSR|stat.S_IWUSR)
print("keys:", ",".join(env.keys()), "| format:", "PASS" if all(ok) else "FAIL")
EOF
```
Return: the `keys: … | format: PASS` line. (Optional keys `KMS_SIGNER_SESSION_NAME`, `KMS_SIGNER_DURATION_SECONDS` are left to code defaults.)

**C6-3 — set the secrets from the file, then destroy the local secrets:**
```bash
cd /Users/josetascon/snatchit-admin-console && supabase secrets set --env-file "$HOME/pfa18c-local/c6.env" && supabase secrets list | awk 'NR==1 || /KMS_|AWS_/ {print $1}' && rm -P "$HOME/pfa18c-local/c6.env" "$HOME/pfa18c-local/runtime-key.json" 2>/dev/null || rm -f "$HOME/pfa18c-local/c6.env" "$HOME/pfa18c-local/runtime-key.json"; ls "$HOME/pfa18c-local"
```
Return: the secret **names** printed and the final `ls` (neither file present). The secret value is now recoverable only by rotating the key.

**C6-4 — dark deploy from the chosen checkout (re-verify the tree hashes first; owner pastes the hash lines):**
```bash
cd /Users/josetascon/snatchit-admin-console && git rev-parse --short HEAD && for d in credential-sign door-manifest door-session _shared; do printf '%s %s\n' "$d" "$(git ls-tree HEAD supabase/functions/$d --format='%(objectname)' | cut -c1-12)"; done
```
Expected: `credential-sign 8acff3797f7d`, `door-manifest 9cd883d0bb63`, `door-session 910eef735250`, `_shared 20fda4a1eae5`. Then:
```bash
cd /Users/josetascon/snatchit-admin-console && supabase functions deploy credential-sign && supabase functions deploy door-manifest && supabase functions deploy door-session --no-verify-jwt && supabase functions list
```
Return: the `functions list` table rows for the three (name, status, verify_jwt).

**C6-5 — dark verification (owner runs nothing further; coordinator + Mac 2 read back, §3–§4).** Do not open, curl, or "test" any of the three URLs.

## 3. Coordinator read-backs (read-only) — immediately and at +24 h
`list_edge_functions` → 14 functions: the 3 new ACTIVE with `verify_jwt` true/true/false, the 11 legacy unchanged (ids, hashes) · `supabase secrets list` names include the six E2 keys (digests only) · runtime user access keys = 1 (Active) · CloudTrail: `CreateAccessKey` ×1 (`jose-admin`); **0** `AssumeRole` into the runtime role; **0** new `Sign`; 0 lifecycle/policy events · Supabase `query_logs` for the three slugs: no requests · production DB unchanged (`signing_key` `1|1`; flags false; ledger unchanged) · monitor `ok/match`, 0 alert rows · key `Enabled`, policy v2, tags 3. **C6 COMPLETE** is recorded only after the 24-hour quiet window shows the same.

## 4. Mac 2 checks (founder B or owner; verifier profile for AWS, Dashboard Option A for Supabase; read-only by procedure)
```bash
aws iam list-access-keys --profile verifier --region us-east-1 --no-cli-pager --user-name snatchit-credential-sign-runtime --query 'AccessKeyMetadata[].[Status,CreateDate]' --output text
aws iam get-role-policy --profile verifier --region us-east-1 --no-cli-pager --role-name SnatchIt-CredentialSign-Runtime --policy-name pfa18c-runtime-sign --query 'PolicyDocument.Statement[0].[Action,Resource]' --output text
aws kms describe-key --profile verifier --region us-east-1 --no-cli-pager --key-id arn:aws:kms:us-east-1:652872010073:key/45907419-8894-4582-ba79-71e9c29c549e --query 'KeyMetadata.[KeyState,KeySpec,MultiRegion]' --output text
for ev in AssumeRole Sign CreateAccessKey; do echo -n "$ev: "; aws cloudtrail lookup-events --profile verifier --region us-east-1 --no-cli-pager --lookup-attributes AttributeKey=EventName,AttributeValue=$ev --start-time <C6 start UTC> --query 'Events[].[Username]' --output text | tr '\n' ' '; echo; done
```
Expected: one `Active` key; `kms:Sign` on the exact D4 ARN; `Enabled ECC_NIST_P256 False`; `AssumeRole:` empty (no runtime-role session), `Sign:` empty, `CreateAccessKey: jose-admin`. Dashboard (Supabase, Option A): Edge Functions page lists the three with the expected JWT settings; Secrets page shows the six names (values hidden); SQL editor read-only: `select count(*) from kernel.signing_key` = 1, flags false, `select kernel.check_signing_key_invariants()` → `ok`. Sign out afterwards.

## 5. Abort conditions
Any secret value printed anywhere; `create-access-key` returning more than one key or for another user; env-file format FAIL; tree hashes differ from §2 C6-4; a deploy error; a function invoked by anyone (any `AssumeRole` into the runtime role or any new `Sign`); a fourth function or a legacy function changed; monitor not `ok`; any flag not false.

## 6. Rollback (own phrase `AUTHORIZE PFA-18C C6 ROLLBACK`)
Order: `supabase secrets unset KMS_PROVIDER AWS_REGION KMS_SIGNER_ROLE_ARN KMS_SIGNER_EXTERNAL_ID AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY` → `supabase functions delete credential-sign door-manifest door-session` → `aws iam delete-access-key --user-name snatchit-credential-sign-runtime --access-key-id <id>`. KMS key, role, trust, DB row and monitor untouched.

## 7. Boundary
C6 changes: one IAM access key, six Supabase secrets, three dark functions. It does not change flags, the DB, KMS, or the monitor, and signs nothing. The first invocation is T3 territory (M5-live after Model A and the M5 ruling).

## 8. Phrase (when the owner is ready): **`AUTHORIZE PFA-18C DARK DEPLOY`** — scoped to §2 C6-1…C6-4 exactly, from the checkout named in P7.
