# PFA-18C — C6 RUNTIME SECRETS + DARK DEPLOY — **REVIEW-ONLY PACKAGE** (NOT AUTHORIZED · NOTHING EXECUTED · NO SECRET, KEY, OR DEPLOY EXISTS)

**Date:** 2026-09-10 · **Coordinator:** Claude B · **State:** C2 COMPLETE (key `45907419…`, policy v2, runtime role bound), C3 COMPLETE (row `…b0`), C4 COMPLETE (110–114 live), **C5 paused after C5-1** (monitor disarmed). Native edges (`credential-sign`, `door-manifest`, `door-session`) exist in the repo (E2 implemented 2026-09-05, commit `72d4e90`, mocked-network tests) and are **not deployed**; the runtime user has **0 access keys**; no `KMS_*`/`AWS_*` Supabase secret exists.
**C6 requires the separate exact owner phrase `AUTHORIZE PFA-18C DARK DEPLOY`** (runbook §C). This document is review-only. **C6 deploys dark: no function is invoked.** Invoking `credential-sign` with the production key would sign a credential = **T3**, which requires Model A first; C7/M5 remains pending §5d.

Evidence classes: **CLAUDE-OBSERVED** (repo/AWS/DB reads), **DEFINITION-REVIEW** (E2 source), **OFFICIAL-DOC**.

---

## 1. What C6 provisions (exact) and what it does not

| Item | Value / rule |
|---|---|
| Runtime base identity | IAM user `snatchit-credential-sign-runtime` (C1-3; inline policy `pfa18c-runtime-assume-only`: may **only** `sts:AssumeRole` the runtime role; `kms:*` explicitly denied) — **one** access key created **only at C6**, by the owner, never earlier |
| Runtime role | `arn:aws:iam::652872010073:role/SnatchIt-CredentialSign-Runtime` — trust: the runtime user + `sts:ExternalId` (value only in the owner's local filled trust file from C1-3, never printed); permissions: `kms:Sign` on **exactly** D4 with `ECDSA_SHA_256` + `RAW`, everything else in KMS explicitly denied (C2-8) |
| Key policy v2 | `RuntimeSignOnly` → the runtime role only; ceremony/verifier read-only; nobody has `Verify` |
| Supabase secrets (E2 contract, DEFINITION-REVIEW of `parseAssumeRoleConfig` + `readBaseCredentials`) | required: `KMS_PROVIDER=aws` · `AWS_REGION=us-east-1` (or `KMS_REGION`) · `KMS_SIGNER_ROLE_ARN=<runtime role ARN>` · `KMS_SIGNER_EXTERNAL_ID=<ExternalId>` · `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` of the runtime **user**; optional: `KMS_SIGNER_SESSION_NAME` (default in code; `RoleSessionName`), `KMS_SIGNER_DURATION_SECONDS` (900–3600; default in code), `AWS_SESSION_TOKEN` (**not set** — base credentials are the user's long-lived key; the edge obtains temporary role credentials itself via STS). Missing region/role ⇒ `aws_kms_env_missing` (permanent); malformed ⇒ `aws_sts_config_invalid:*` |
| Runtime behaviour (E2) | on cold start the edge calls `sts:AssumeRole` (`RoleArn`, `RoleSessionName`, `ExternalId`, `DurationSeconds`) at `sts.us-east-1.amazonaws.com`, checks the returned `AssumedRoleUser.Arn` **exactly** equals `arn:aws:sts::652872010073:assumed-role/SnatchIt-CredentialSign-Runtime/<session name>`, caches the temporary triple in module scope, refreshes before expiry, signs at `kms.us-east-1.amazonaws.com` with `ECDSA_SHA_256`/`RAW`, and verifies every signature under the row's public key before responding; any STS/KMS failure fails closed |
| Key identity source | `venue.get_manifest_signing_context()` / `kernel.get_ticket_signing_context` (114/102): key_id `…b0`, `kms_handle_ref` = D4, ES256, public_key — the former `DOOR_MANIFEST_KMS_HANDLE_REF` env inference is gone; the signer scope check requires the role's account+region to equal the ARN's (us-east-1 / 652872010073 — satisfied) |
| Deploy set | `credential-sign` (verify_jwt **true**), `door-manifest` (verify_jwt **true**), `door-session` (**`--no-verify-jwt`**: machine/door callers per packet §5b) — from the reviewed, CI-green commit, CLI pin 2.115.0 |
| **Not done at C6** | no invocation of any deployed function; no flag change; no issuance/scanning; no ceremony-role or verifier credential; no second access key; no KMS change; no migration; Model A unchanged |

## 2. Prerequisites (read-only checks before authorization)

| # | Prerequisite | Status today |
|---|---|---|
| P1 | C5 COMPLETE (monitor armed, ok/match) — so the trust root is watched before any signer exists | **not yet** (paused after C5-1) |
| P2 | **Forward fix 114 L121** (non-STRICT `select … into v_k` in `get_manifest_signing_context`; body-only migration; edge fails closed today) — recorded "before C6" | **open** — needs its own reviewed migration + authorization before C6 |
| P3 | Forward fix 086 ↔ 112/113 expired-episode drift | required before **scanning activation**, not before C6 (record) |
| P4 | Runtime user access keys = 0; runtime role policy bound to D4 only; trust has `sts:ExternalId`; key policy v2 | **PASS** (2026-09-10 reads) |
| P5 | No `KMS_*`/`AWS_*` secrets in `supabase secrets list` (names only) | **PASS** (2026-09-10) |
| P6 | Native edges not deployed (11 legacy ACTIVE only) | **PASS** |
| P7 | Deploy commit = CI-green tip of the admin worktree branch containing the E2 code and the C4 migrations; `AUTODEPLOY-VERIFIED-OFF` rule honoured (edges are deployed by CLI, not by the GitHub integration) | verify on the day |
| P8 | Owner-side: the ExternalId file and the C1-3 filled trust exist locally; the env-file for `supabase secrets set --env-file` is written **outside** any repo, mode 600, deleted after use | owner |
| P9 | Detection ready: CloudTrail alarm/lookup plan for `AssumeRole` into the runtime role by any principal other than the runtime user, and for any `Sign` by a non-runtime principal | plan in the readiness report §7; implement as part of C6 verification |
| P10 | Decision on record: O1 adopted (packet D3 confirmed) | confirmed |

## 3. Procedure outline (owner runs; coordinator reads back) — for review, not for execution

1. **C6-1 access key (owner, `jose-admin`):** `aws iam create-access-key --user-name snatchit-credential-sign-runtime` with the output written **only** to a local file (`--output json > $HOME/pfa18c-local/runtime-key.json`, mode 600); the secret never appears on screen or in chat. Read-back: `list-access-keys` → exactly one key, `Active`. CloudTrail `CreateAccessKey` ×1 by `jose-admin`.
2. **C6-2 env file (owner, local):** build `$HOME/pfa18c-local/c6.env` from the key file + the local ExternalId file: `KMS_PROVIDER=aws`, `AWS_REGION=us-east-1`, `KMS_SIGNER_ROLE_ARN=arn:aws:iam::652872010073:role/SnatchIt-CredentialSign-Runtime`, `KMS_SIGNER_EXTERNAL_ID=…`, `AWS_ACCESS_KEY_ID=…`, `AWS_SECRET_ACCESS_KEY=…` (optionally `KMS_SIGNER_SESSION_NAME`, `KMS_SIGNER_DURATION_SECONDS=3600`). Validate locally with a script that prints only key names and format PASS/FAIL (region regex, role-ARN regex, ExternalId regex, session-name regex — the same regexes as `parseAssumeRoleConfig`).
3. **C6-3 secrets (owner):** `supabase secrets set --env-file $HOME/pfa18c-local/c6.env` (project-linked). Read-back: `supabase secrets list` shows the names with digests only. Then `shred`/delete `c6.env` and `runtime-key.json` (the key is retrievable only by rotation).
4. **C6-4 dark deploy (owner):** `supabase functions deploy credential-sign` · `supabase functions deploy door-manifest` · `supabase functions deploy door-session --no-verify-jwt` from the reviewed commit. Read-back (coordinator, read-only): `list_edge_functions` shows the three new functions ACTIVE with the expected `verify_jwt` values; the 11 legacy functions unchanged.
5. **C6-5 dark verification (no invocation):** edge logs show only boot lines (no request handled); Supabase `query_logs` for the three slugs = no requests; CloudTrail: **0** `AssumeRole` into the runtime role, **0** `Sign` beyond the C2 proof; production DB unchanged (signing_key 1 row; flags false; tickets 0).
6. **Record** and stop. **No test call** — the first real `credential-sign` invocation is C7/M5 territory and, with the production key, T3.

## 4. Verification of a successful C6 (all read-only)
`list-access-keys` runtime user = 1 (Active) · `secrets list` names = the E2 contract (digests only) · three functions ACTIVE with correct `verify_jwt` · zero invocations · CloudTrail 0 `AssumeRole`/`Sign` by the runtime identities · KMS key unchanged · DB unchanged · monitor (if armed) still `ok`.

## 5. Rollback (own phrase `AUTHORIZE PFA-18C C6 ROLLBACK`)
`supabase secrets unset KMS_PROVIDER AWS_REGION KMS_SIGNER_ROLE_ARN KMS_SIGNER_EXTERNAL_ID AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY …` · `supabase functions delete credential-sign door-manifest door-session` · `aws iam delete-access-key --user-name snatchit-credential-sign-runtime --access-key-id <id>` (CloudTrail `DeleteAccessKey`). Order: secrets first (nothing can sign), then functions, then the key. The KMS key, role, trust and DB row are untouched by a C6 rollback.

## 6. Residuals and decisions for the owner
- O1 keeps a **static** user access key in Supabase secrets (readiness report §7: no documented federation for Edge Functions). Mitigations in place: the key can only `AssumeRole`; the role is bound to one KMS key; `Sign` requires the role session; CloudTrail records session names; rotation plan (two-key overlap, 90 days). O4 (Lambda with ambient role) remains the zero-static-secret alternative — an architecture decision, not C6.
- P2 (114 L121) must be fixed and applied by its own migration before C6.
- **T3 boundary:** C6 is dark. Any invocation of `credential-sign` against a real atom = a production credential signed = T3 → Model A first; M5 procedure pending §5d.
- `door-session --no-verify-jwt` is deliberate (machine callers) — confirm on review.

## 7. Authorization phrase (when the prerequisites pass)
**`AUTHORIZE PFA-18C DARK DEPLOY`** — scoped to §1 (one access key; the listed secrets; the three functions; no invocation).
