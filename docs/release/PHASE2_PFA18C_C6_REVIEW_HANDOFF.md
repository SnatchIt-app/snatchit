# PFA-18C — C6 RUNTIME SECRETS + DARK DEPLOY — FINAL PREFLIGHT AND OWNER STEPS (rev 2) — **NOT AUTHORIZED · NOTHING EXECUTED**

**Date:** 2026-09-11 · **Coordinator:** Claude B · **Companion:** `PHASE2_PFA18C_C6_DARK_DEPLOY_REVIEW_PACKAGE.md`. **C6 requires the separate exact owner phrase `AUTHORIZE PFA-18C DARK DEPLOY`**; this document is not that authorization.
**Owner decisions applied (2026-09-11):** migration 121 deferred to Claude A's integration sequence; deploy from an isolated checkout pinned to `admin/operating-console @ 562fda9`; ExternalId file validated without printing.

## 0. Preparation results (CLAUDE-OBSERVED 2026-09-11T02:0xZ)

| Item | Result |
|---|---|
| Isolated checkout | `/Users/josetascon/snatchit-c6deploy` — detached at `562fda9aba261d7929ee772a4fd1ce50485c4294`, clean; tree hashes `credential-sign 8acff3797f7d` · `door-manifest 9cd883d0bb63` · `door-session 910eef735250` · `_shared 20fda4a1eae5` (= the reviewed values); CLI link markers mirrored (`project-ref hqycwntpfoztoinemqns`) |
| ExternalId file | `~/pfa18c-local/m3_runtime_role_trust.filled.json` exists, mode `0600`, principal = the runtime user, `sts:ExternalId` present, 64 characters, format PASS — value never printed |
| Secret-name collisions | 18 existing secrets; **none** of `KMS_PROVIDER, AWS_REGION, KMS_REGION, KMS_SIGNER_ROLE_ARN, KMS_SIGNER_EXTERNAL_ID, KMS_SIGNER_SESSION_NAME, KMS_SIGNER_DURATION_SECONDS, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN` present → `secrets set` will create, not overwrite (re-check on the day) |
| Production counts | tickets 0 · door_sessions 0 · door_manifests 0 · scan_devices 0 · door_pins 0 · staff_roles 0 · orgs 0 · venues 0 · events 0 · event_sessions 0 · runtime access keys 0 · native functions 0 of 3 deployed · flags false · monitor `ok/match` |

## 1. What actually keeps each deployed endpoint inactive (evidence-based; "we will not invoke them" is not one of the controls)

Once `KMS_PROVIDER=aws` and the credentials are set, the code-level "unconfigured signer" fail-closed no longer applies. The controls below are the ones that hold **after** C6, for **any** caller.

### 1.1 `credential-sign` (`verify_jwt: true`)
1. **Gateway JWT check** — Supabase rejects any request without a valid project JWT before the function runs.
2. **In-function re-verification** — `auth.getUser(bearer)` (401 on failure), then a **fail-closed rate limiter** (`check_rate_limit`, 503 on limiter fault, 429 over limit).
3. **Atom ownership, enforced in the database** — the function calls `kernel.get_ticket_signing_context(atom_id)` (EXECUTE to `authenticated`, caller identity). It refuses `not_owner` unless `kernel.tickets` holds that atom owned by `auth.uid()`, and writes an audit row on refusal. **`kernel.tickets` has 0 rows.**
4. **Issuance flag, enforced in the database** — atoms are created only by `kernel.issue_ticket_atoms` (service_role only; callers `venue.finalize_primary_order`, `venue.issue_comp`), which reads `feature.native_issuance_enabled` from `catalog.platform_config` at call time and raises `precondition_failed: feature_disabled` while it is `false`. **So no atom can come into existence, hence no signing context, hence no `Sign`, regardless of who calls the endpoint.** This is the control the issuance flag provides; it holds until C8.

### 1.2 `door-manifest` (`verify_jwt: true`)
1. Gateway JWT check; in-function `auth.getUser`; fail-closed rate limiter.
2. **Venue staff role, enforced in the database** — the manifest read `venue.get_door_manifest` runs under the caller's identity and authorizes with `has_venue_role` (`venue_scanner` / `venue_manager`). **`venue.staff_role` has 0 rows.**
3. **An open episode must exist** — the edge signs only when the manifest is `open` ("open ⇒ sign · closed ⇒ 200 unsigned"); episodes are created by `venue.open_door_manifest` (gated: `venue_manager` / org owner or admin / `platform_admin`, non-terminal event session). **0 door manifests, 0 event sessions, 0 events, 0 venues, 0 organizations exist.**
4. The signing identity comes from `venue.get_manifest_signing_context()` (service_role, one read); the produced signature is verified under the row's public key before it is returned.
**Honest statement:** the scanning flag is **not** read by these database functions; "scanning disabled" is not a control for door-manifest. What prevents a manifest signature today is (a) no staff role, (b) no event/session/episode, and (c) the role gate on opening one. A `platform_admin` could create those entities, each an audited mutation. Therefore the dark window carries a **standing precondition**: the counts in §0 stay zero (re-read daily), and the first manifest signature is a post-Model-A act by policy (§5d item 3). Detection: CloudTrail `Sign` by the runtime role must stay 0.

### 1.3 `door-session` (`--no-verify-jwt`)
`verify_jwt` is off because door devices carry **no user JWT**; authentication is the device-credential model, enforced in the database:
1. `/mint` needs `venue_id`, `session_id`, a registered `scan_device` (created only by a `venue_manager` via `register_scan_device`) and a `door_pin` (created only by a `venue_manager` via `create_door_pin`, stored as a pgcrypto hash, 1–64 bytes, expiring). `venue.mint_door_session` (service_role RPC, called by the edge) verifies the PIN and returns an **opaque 401 `door_session_invalid`** on any failure. **0 devices, 0 PINs, 0 sessions exist.**
2. Every relay route requires `Authorization: DoorSession <door_session_id>.<secret>`; `kernel.assert_door_session` (service_role only) is the sole gate; device-id cross-check; opaque 401 on mismatch. **0 door sessions exist**, so no relay call can authenticate.
3. Per-device and per-session rate limits (`uuidv5` principals, 60/60 per route).
4. **This function never calls KMS** (no signer import; only a comment mentions it). Its `/keys` route returns the **public** key projection only.
**Correction recorded:** the file header still says `mint_door_session` is parked (PFA-26 `door_pin_kdf_unavailable`); production migration **107** un-parked it, so the mint path is live and the controls are the credentials above, not the parking. The scanning flag is not read by these functions either.

### 1.4 Cross-cutting
- The runtime role can only `kms:Sign` on D4 (ECDSA_SHA_256, RAW); the key policy v2 grants `Sign` to that role only; the ceremony/verifier principals cannot sign.
- Project secrets are readable by **every** function in the project; the 11 legacy functions do not reference `AWS_*`/`KMS_*` (source grep), but code review of future function changes is part of the standing control.
- Detection during the dark window: CloudTrail `AssumeRole` into the runtime role and `Sign` must both stay **0**; the monitor watches the trust root, not invocations.

## 2. Exact secret names, collision handling, rollback scope

| Secret | Value source | Notes |
|---|---|---|
| `KMS_PROVIDER` | literal `aws` | selects the AWS signer; unset/anything else ⇒ unconfigured (fail closed) |
| `AWS_REGION` | literal `us-east-1` | `KMS_REGION` is an accepted alias in code; **not set** |
| `KMS_SIGNER_ROLE_ARN` | literal `arn:aws:iam::652872010073:role/SnatchIt-CredentialSign-Runtime` | validated by regex in code |
| `KMS_SIGNER_EXTERNAL_ID` | read from the local filled trust file | never printed |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | the one runtime-user key created at C6-1 | long-lived user key; the edge exchanges it via STS for temporary role credentials |
| not set | `KMS_SIGNER_SESSION_NAME`, `KMS_SIGNER_DURATION_SECONDS`, `AWS_SESSION_TOKEN` | code defaults |

Collision handling: `supabase secrets set` overwrites silently, so C6-3 first lists names and **aborts if any of the six exists** (today: none). Rollback scope is **name-scoped**: `secrets unset` lists exactly the six names; `functions delete` lists exactly the three slugs; `delete-access-key` names the exact `AccessKeyId`; a before/after snapshot of the 18 pre-existing secret names and the 11 legacy function ids/hashes proves nothing else changed.

## 3. Local credential-file handling (accurate)
`runtime-key.json` and `c6.env` are created with mode 600 under `~/pfa18c-local` and **unlinked** after C6-3 (`rm`). Unlinking does not erase data from an SSD, and Time Machine, iCloud Drive, Spotlight caches or shell history may retain copies; no secure-erase is claimed. The effective control is that the access key is **revocable**: `aws iam update-access-key --status Inactive` / `delete-access-key` invalidates it at once, and CloudTrail records any use. Recommendation: keep `~/pfa18c-local` out of backups if practical, never open the files in an editor that autosaves, and rotate the key if the machine is ever suspected compromised.

## 4. Final preflight (day-of, read-only; all must PASS before C6-1)

| # | Check | Expected | Who |
|---|---|---|---|
| F1 | C5 COMPLETE; monitor `ok/match`; 0 alert rows | as recorded | coordinator |
| F2 | Isolated checkout `snatchit-c6deploy` at `562fda9`, clean, four tree hashes as §0 | PASS | owner pastes the hash lines; coordinator re-verifies |
| F3 | CLI link in that checkout = `hqycwntpfoztoinemqns`; `supabase --version` 2.115.0 | PASS | owner |
| F4 | Runtime user access keys **0**; runtime role inline `pfa18c-runtime-sign` bound to D4; trust `sts:ExternalId`; key policy v2; key Enabled | PASS | coordinator + Mac 2 |
| F5 | Secret-name collision check: none of the six present | PASS | owner (C6-3 pre-step) + coordinator |
| F6 | Native functions not deployed; legacy 11 ids/hashes snapshot taken | snapshot recorded | coordinator |
| F7 | ExternalId file present, mode 600, format PASS (no value) | PASS | owner |
| F8 | Production counts (§0) all zero; flags false; ledger unchanged | PASS | coordinator |
| F9 | CloudTrail: 0 `AssumeRole` into the runtime role, `Sign` total still 3, 0 lifecycle events; trail logging | PASS | coordinator |
| F10 | Owner has the local password manager ready for nothing — **no password or token is needed** for C6 (AWS via `snatchit-admin` login session; Supabase CLI via its stored access token) | — | owner |

## 5. Exact owner steps (Mac 1) — run one at a time; paste only the stated lines

**C6-0 — verify the checkout and link:**
```bash
cd /Users/josetascon/snatchit-c6deploy && git rev-parse HEAD && git status --porcelain | wc -l && for d in credential-sign door-manifest door-session _shared; do printf '%s %s\n' "$d" "$(git ls-tree HEAD supabase/functions/$d --format='%(objectname)' | cut -c1-12)"; done && cat supabase/.temp/project-ref && supabase --version
```
Expected: `562fda9aba261d7929ee772a4fd1ce50485c4294`, `0`, the four hashes of §0, `hqycwntpfoztoinemqns`, `2.115.0`.

**C6-1 — one access key, secret written only to a local file:**
```bash
umask 077 && mkdir -p "$HOME/pfa18c-local" && aws iam create-access-key --profile snatchit-admin --region us-east-1 --no-cli-pager --user-name snatchit-credential-sign-runtime --output json > "$HOME/pfa18c-local/runtime-key.json" && python3 -c 'import json,os;d=json.load(open(os.path.expanduser("~/pfa18c-local/runtime-key.json")))["AccessKey"];print("access_key_id_prefix",d["AccessKeyId"][:8],"status",d["Status"],"created",d["CreateDate"])'
```
Paste the printed line (the id prefix is not secret; the secret never prints). Coordinator read-back: exactly 1 Active key; CloudTrail `CreateAccessKey` ×1.

**C6-2 — build and validate the env file (never displayed):**
```bash
python3 - <<'EOF'
import json, os, re, stat
p=os.path.expanduser('~/pfa18c-local')
key=json.load(open(f"{p}/runtime-key.json"))["AccessKey"]
ext=json.load(open(f"{p}/m3_runtime_role_trust.filled.json"))["Statement"][0]["Condition"]["StringEquals"]["sts:ExternalId"]
env={"KMS_PROVIDER":"aws","AWS_REGION":"us-east-1","KMS_SIGNER_ROLE_ARN":"arn:aws:iam::652872010073:role/SnatchIt-CredentialSign-Runtime","KMS_SIGNER_EXTERNAL_ID":ext,"AWS_ACCESS_KEY_ID":key["AccessKeyId"],"AWS_SECRET_ACCESS_KEY":key["SecretAccessKey"]}
ok=[re.fullmatch(r"[a-z]{2}(-[a-z]+)+-\d",env["AWS_REGION"]) is not None, re.fullmatch(r"arn:aws:iam::\d{12}:role/[\w+=,.@-]+",env["KMS_SIGNER_ROLE_ARN"]) is not None, re.fullmatch(r"[\w+=,.@:/-]{2,1224}",ext) is not None and '<' not in ext, env["AWS_ACCESS_KEY_ID"].startswith("AKIA"), len(env["AWS_SECRET_ACCESS_KEY"])>=40]
fd=os.open(f"{p}/c6.env", os.O_WRONLY|os.O_CREAT|os.O_TRUNC, 0o600)
with os.fdopen(fd,'w') as f:
    for k,v in env.items(): f.write(f"{k}={v}\n")
print("keys:", ",".join(env.keys()), "| format:", "PASS" if all(ok) else "FAIL")
EOF
```
Paste the `keys: … | format: PASS` line. FAIL ⇒ stop.

**C6-3 — collision check, set the six secrets, unlink the local files:**
```bash
cd /Users/josetascon/snatchit-c6deploy && supabase secrets list | python3 -c 'import sys,json; n={s["name"] for s in json.load(sys.stdin)["secrets"]}; c=[k for k in ["KMS_PROVIDER","AWS_REGION","KMS_SIGNER_ROLE_ARN","KMS_SIGNER_EXTERNAL_ID","AWS_ACCESS_KEY_ID","AWS_SECRET_ACCESS_KEY"] if k in n]; print("existing",len(n),"collisions",c or "none"); sys.exit(1 if c else 0)' && supabase secrets set --env-file "$HOME/pfa18c-local/c6.env" && supabase secrets list | python3 -c 'import sys,json; d=json.load(sys.stdin)["secrets"]; print("total",len(d)); print(sorted(s["name"] for s in d if s["name"].startswith(("KMS_","AWS_"))))' && rm -f "$HOME/pfa18c-local/c6.env" "$HOME/pfa18c-local/runtime-key.json" && ls "$HOME/pfa18c-local"
```
Expected: `existing 18 collisions none`, then `total 24` and the six names, then an `ls` without `c6.env`/`runtime-key.json`. (If the collision step exits non-zero, nothing is set.)

**C6-4 — dark deploy (no invocation, ever):**
```bash
cd /Users/josetascon/snatchit-c6deploy && supabase functions deploy credential-sign && supabase functions deploy door-manifest && supabase functions deploy door-session --no-verify-jwt && supabase functions list
```
Paste the `functions list` rows for the three (name, status, JWT). Do not open, curl, or test any URL.

## 6. Read-backs (coordinator, immediately and at +24 h; Mac 2 as in rev 1 §4)
14 functions: 3 new ACTIVE with `verify_jwt` true/true/false; 11 legacy ids/hashes = snapshot · secrets: 18 pre-existing names unchanged + the 6 · runtime keys = 1 Active · CloudTrail: `CreateAccessKey` ×1 (`jose-admin`); **0** runtime-role `AssumeRole`; `Sign` total still 3; 0 lifecycle · Supabase logs: no requests to the three slugs · §0 counts still zero · monitor `ok/match`, 0 alerts. **C6 COMPLETE** only after the 24-hour window.

## 7. Abort / rollback
Abort on: any secret printed; more than one key or a key on another user; env FAIL; hash mismatch; collision; deploy error; any runtime-role `AssumeRole` or new `Sign`; any legacy function or pre-existing secret changed; any §0 count non-zero; monitor not `ok`. Rollback (`AUTHORIZE PFA-18C C6 ROLLBACK`), name-scoped, in order: `supabase secrets unset KMS_PROVIDER AWS_REGION KMS_SIGNER_ROLE_ARN KMS_SIGNER_EXTERNAL_ID AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY` → `supabase functions delete credential-sign` / `door-manifest` / `door-session` → `aws iam delete-access-key --user-name snatchit-credential-sign-runtime --access-key-id <the C6-1 id>`; then verify the 18/11 snapshots unchanged. KMS, roles, trust, DB row, monitor untouched.

## 8. Phrase (when ready): **`AUTHORIZE PFA-18C DARK DEPLOY`** — scoped to §5 C6-0…C6-4 exactly, from `snatchit-c6deploy @ 562fda9`.
