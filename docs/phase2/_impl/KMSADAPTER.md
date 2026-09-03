# KMSADAPTER — PFA-PT-8 algorithm pinning, ES256 DER⇄raw, KMS provider adapter, sign-after-verify

DARK/local only. No production, no deploy, no real KMS call, no signing key, no secret. Owns exactly:
`supabase/functions/credential-sign/credential.ts` (MODIFY), `supabase/functions/credential-sign/kms.ts` (NEW),
`supabase/functions/credential-sign/index.ts` (MODIFY), `tests/credential-sign.test.ts` (MODIFY),
`tests/credential-sign-kms.test.ts` (NEW), this file — plus one file added mid-train to fix a `npm run typecheck`
regression the coordinator flagged: `supabase/functions/credential-sign/kms-taxonomy.ts` (NEW, pure). See §12.

## 1. Provider chosen, and why

**AWS KMS**, algorithm **ES256 (ECDSA P-256 / SHA-256)** — per `PRODUCTION_SIGNING_KMS_CEREMONY.md` D1/D2: the
sanctioned set is AWS KMS / GCP KMS / CloudHSM only; Supabase runs on AWS and `KMS_SIGNER_ROLE_ARN` is AWS-shaped,
so AWS KMS is the reference adapter. AWS KMS offers no Ed25519, hence ES256.

`KmsSigner` (`kms-taxonomy.ts`, see §12) stays provider-agnostic (`sign(kmsHandleRef, bytes, algorithm) → raw sig`)
so a future GCP KMS adapter (which does offer Ed25519) can sit alongside `AwsKmsSigner` without touching
`index.ts`'s call site beyond `selectKmsSigner`'s branch table. **Which provider/algorithm actually goes live
remains an OWNER decision** (the ceremony) — `KMS_PROVIDER` unset (or anything but `"aws"`) still resolves to
`UnconfiguredKmsSigner`, unchanged default behavior.

## 2. Why `fetch` + hand-rolled SigV4, not the AWS SDK

`AwsKmsSigner` is real, reviewable transport code (not a stub) — the brief accepted either "clearly stub the
transport" or a documented `fetch`-based SigV4 call; a full AWS SDK import (even via Deno's `npm:`/esm.sh
convention) pulls a large tree with rough edges in both the Deno edge runtime and vitest for one API call
(`kms:Sign`). SigV4 over `fetch` is ~100 lines (`signSigV4` in `kms.ts`): canonical request → string-to-sign →
derived signing key (HMAC-SHA256 chain) → `Authorization` header, using Web Crypto (`crypto.subtle`) for SHA-256/
HMAC — available in both Deno and modern Node, no library.

**Credential resolution is explicitly out of scope.** `KMS_SIGNER_ROLE_ARN` *names* the IAM role; `AwsKmsSigner`
does **not** call `sts:AssumeRole` itself — it reads `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/
`AWS_SESSION_TOKEN` from the environment (the standard shape AWS-hosted compute exposes assumed-role credentials
in) and **fails closed** (`aws_kms_credentials_unavailable`, PERMANENT) before any network call if they are absent
— which they always are here. Wiring the actual AssumeRole/credential-provider mechanism is ceremony-time
infrastructure work.

Two more fail-closed gates run before that, in order, inside `AwsKmsSigner.sign`:
1. `algorithm !== 'ES256'` → `unsupported_algorithm_for_provider` (PERMANENT) — AWS KMS has no Ed25519.
2. `!region || !roleArn` → `aws_kms_env_missing` (PERMANENT) — `KMS_PROVIDER=aws` selected but incompletely
   configured.

Only after all three does credential resolution run, and only after *that* does `fetch` ever get called. As of
§12's split, all three checks are PURE functions in `kms-taxonomy.ts` (`awsSigningAlgorithmForEs256Only`,
`requireAwsProviderConfig`, `resolveAwsCredentials`) — `resolveAwsCredentials` takes an injected `getEnv` function
rather than reaching for `Deno.env`/a global itself, so the fail-closed guarantee is unit-tested directly with a
plain function (`resolveAwsCredentials(() => undefined)` throws), no `Deno` global mock needed at all. `kms.ts`
supplies the real `Deno.env.get`-backed getter (`readDenoEnv`) when it calls these at runtime.

## 3. KMS message-mode decision (RAW vs DIGEST) — and how sign-after-verify matches it

**`MessageType: 'RAW'`**, always, with `canonical.signedBytes` sent verbatim as `Message`. For
`SigningAlgorithm: 'ECDSA_SHA_256'`, `MessageType: 'RAW'` tells KMS to SHA-256-digest the message itself before
signing; `MessageType: 'DIGEST'` would require pre-hashing here and sending the digest instead. This adapter picked
RAW because it needs no local hashing step and matches how the sign-after-verify check (`index.ts` §9) already
verifies: `verifyWithWebCrypto`'s ES256 branch calls `crypto.subtle.verify({name:'ECDSA', hash:'SHA-256'}, key,
signature, message)` — WebCrypto also digests `message` internally under `hash:'SHA-256'`. Both sides operate on
`canonical.signedBytes`, both sides digest internally, by construction — there is no code path where the mode or
the bytes could drift between what KMS signed and what sign-after-verify checks. This is documented as
load-bearing in `AwsKmsSigner`'s class doc, not left as an incidental default.

## 4. DER ⇄ raw approach

AWS KMS's `Sign` response for `ECDSA_SHA_256` is ASN.1/DER `SEQUENCE{INTEGER r, INTEGER s}`; the JWS wire format
(and WebCrypto's ECDSA verify) use raw `R‖S`, 64 bytes. `derToRawEcdsaP256`/`rawToDerEcdsaP256` live in
`credential.ts` (pure, import-free, like the rest of that module — DER parsing is just byte-offset arithmetic, no
crypto library needed):

- `derToRawEcdsaP256`: validates the outer `SEQUENCE` tag and declared length matches the buffer exactly (rejects
  trailing garbage and truncation), reads two `INTEGER`s via a definite-form DER length reader (rejects BER
  indefinite length and non-minimal long-form lengths), rejects a negative integer (high bit set on the content's
  first byte with no sign-padding zero — r/s must be positive), strips any legitimate leading sign-padding zero,
  and left-pads each to exactly 32 bytes (rejecting an integer that doesn't fit — more than 32 significant bytes).
- `rawToDerEcdsaP256`: the inverse — strips leading zero bytes down to the minimal representation, re-adds exactly
  one `0x00` sign-padding byte if the minimal form's high bit is set, wraps both `INTEGER`s in a `SEQUENCE`.
- EdDSA (Ed25519) signatures are already raw 64 bytes and need no conversion (passthrough) — these two functions
  are ES256-only, and nothing calls them on an EdDSA signature.

Malformed DER is a thrown error (a `security`-class defect per the taxonomy), never a silent truncation. Round-trip
is proven both synthetically (leading-zero, short, zero, and max/`0xff` r‖s vectors) and against a real P-256
signature from `node:crypto`.

## 5. PFA-PT-8 — algorithm pinning (the verifier hardening)

`PublicKeyResolver: (kid) → string` is replaced by `TrustedKeyResolver: (kid) → TrustedKey | null`, where
`TrustedKey = { public_key: string; algorithm: SigningAlgorithm; not_before?; not_after?; status? }` (the last three
accepted for forward compatibility with an M1 resolver that projects the full `kernel.signing_key` row;
`verifyToken` does not read them — key-window/revocation admissibility stays a door/M1 concern, same split as
`credential_version`/`session_id`).

`verifyToken`'s order is now: decode → **header-alg shape check** (`alg:'none'`/unrecognized/**missing** all reject
uniformly as `unsupported_alg`, before any `kid` lookup) → resolve `kid` → `TrustedKey` (`unknown_kid` if none) →
**THE PIN**: `token.header.alg === trustedKey.algorithm` or refuse `alg_mismatch` — no fallback, no "try EdDSA then
ES256" → verify signature **under `trustedKey.algorithm`** (never the header's, though by this point they're proven
equal) with `trustedKey.public_key` → `exp` check (unchanged). `VerifyReason` gained `alg_mismatch`.

One correction made mid-implementation: the decoded-header type guard originally required `typeof alg === 'string'`
for the header to even be considered structurally valid, which made a token with **no** `alg` key fail as
`malformed_token` rather than `unsupported_alg` — contradicting the brief's "missing alg → `unsupported_alg`"
requirement and, worse, giving an attacker a way to distinguish "I sent no alg" from "I sent a bad alg" by response
shape. Fixed: the decode-time guard now only requires `kid`/`typ` as strings; `alg` decodes as `unknown` and
`verifyToken` is what turns it into an authoritative `SigningAlgorithm` (or refuses) — caught by
`tests/credential-sign-kms.test.ts`'s "missing alg" case before this doc was written.

`verifyCanonicalSignature(canonical, signatureBytes, publicKey, algorithm, verifyPrimitive)` is a small new pure
export — the literal sign-after-verify check (§7), given a testable name so `tests/credential-sign-kms.test.ts` can
exercise it in isolation without invoking `index.ts` (which uses `https://…` imports vitest cannot load).

`tests/credential-sign.test.ts`'s `makeResolver` now wraps each fixture public key as `{public_key, algorithm:
'EdDSA'}` by default — every pre-existing Ed25519-only test keeps passing unchanged under the new resolver shape;
`alg_mismatch` coverage lives in the new KMS test file, which builds `TrustedKey`s directly.

## 6. KMS error taxonomy

Three classes, carried on `KmsSignError.errorClass` (`kms-taxonomy.ts`, §12), set by whichever adapter throws:

| Class | Meaning | `index.ts` response |
|---|---|---|
| `transient` | timeout, throttle, 5xx, temporarily unavailable | 503 + `Retry-After: 5` |
| `permanent` | access denied, key disabled/pending-deletion, unknown key, wrong-alg-for-provider, invalid key usage, misconfiguration | 500, alert, no `Retry-After` |
| `security` | response contradicts the request — wrong algorithm came back, response `KeyId` doesn't match the requested handle | 500, alert, no `Retry-After`, fail closed |

`classifyAwsKmsHttpError(status, bodyText)` (`kms-taxonomy.ts`, pure, exported) buckets an AWS HTTP failure:
`429`/`5xx`/a `Throttl…`/`LimitExceeded…` body → `transient`; everything else (including any 4xx shape it doesn't
specifically recognize) → `permanent` — fails closed rather than guessing a novel AWS exception name is safe to
retry. `validateAwsSignResponse` (`kms-taxonomy.ts`, pure — response `SigningAlgorithm`/`KeyId` mismatch checks)
throws `security` directly, bypassing HTTP-status classification since those are body-content checks, not status
checks. `kms.ts`'s `callSignApi` calls both, never reimplementing the classification itself.

`index.ts`'s `classifyKmsError` reads `err.errorClass` off a `KmsSignError` when present; for anything else (the
legacy `Error('kms_provider_unconfigured')` shape, or an unrecognized thrown value) it pattern-matches defensively
and **defaults to `permanent`** — never silently assumed retryable. The existing RPC-refusal → HTTP mapping
(`mapRefusalCode`, unrelated to KMS) is unchanged.

**Sign-after-verify is its own code path, not routed through `classifyKmsError`.** A `false` result from
`verifyCanonicalSignature` returns `500`, `code:'signing_unhealthy'`, a Sentry exception, logs outcome
`sign_verify_failed`, and is never retried (no `Retry-After`) — semantically the `security` bucket, implemented as
a dedicated, more explicit branch since it isn't a *thrown* KMS error at all (the KMS call succeeded; the bytes it
returned just don't verify).

## 7. Sign-after-verify (index.ts §9)

After `kmsSigner.sign(...)` returns bytes and before any credential is returned: `verifyCanonicalSignature(canonical,
signatureBytes, response.public_key, response.algorithm, verifyWithWebCrypto)`. `verifyWithWebCrypto` is a small
local `VerifyPrimitive` in `index.ts` supporting both algorithms via `crypto.subtle` (Ed25519 raw-64-byte verify;
ECDSA P-256/SHA-256 raw-`R‖S` verify — no DER conversion needed here since WebCrypto's ECDSA verify itself takes
raw signatures, matching what `derToRawEcdsaP256` already produced upstream). On `false` (or a thrown exception,
treated the same): no credential, `500`, `code:'signing_unhealthy'`, Sentry exception with `{atom_id, key_id,
algorithm}` (never the signature/key material), `logOutcome(...,'sign_verify_failed')`, never retried. This is the
last line of defense against a wrong KMS handle, wrong key version, wrong algorithm, or DER/raw encoding drift ever
reaching a client as if it verifies.

## 8. Provider selection (index.ts)

`KMS_PROVIDER` env: unset or anything but `"aws"` → `UnconfiguredKmsSigner` (unchanged: throws
`kms_provider_unconfigured` unconditionally). `KMS_PROVIDER="aws"` → `AwsKmsSigner(region, roleArn)` built from
`AWS_REGION`/`KMS_REGION` and `KMS_SIGNER_ROLE_ARN`. Selecting the provider is **not** the same as this deploy being
able to sign — `AwsKmsSigner` still fails closed without live AWS credentials (§2). None of these env vars are set
anywhere in this repo/CI/local-rehearsal environment, so the DARK guarantee holds regardless of `KMS_PROVIDER`'s
value here.

## 9. Test counts (`npx vitest run`) — post-§12 split

```
Test Files  14 passed (14)
     Tests  599 passed (599)
```

The files this train owns:
- `tests/credential-sign.test.ts` — **23 passed** (unchanged count; only `makeResolver`'s signature changed to
  produce `TrustedKey`s, per §5).
- `tests/credential-sign-kms.test.ts` (new) — **74 passed** (was 65 before §12's split; the pure-function
  replacements for the former `AwsKmsSigner`-instance tests added net-new isolated cases): DER⇄raw round-trip +
  malformed-DER rejection (13), PFA-PT-8 alg-pin matrix (7), ES256 end-to-end (2), sign-after-verify in isolation
  (3), and the KMS error taxonomy (§12) — `classifyAwsKmsHttpError` pure cases (8), `UnconfiguredKmsSigner` (1),
  `awsSigningAlgorithmForEs256Only` (2), `requireAwsProviderConfig` (4), `resolveAwsCredentials` (4),
  `validateAwsSignResponse` (6), and a `KmsSignError` instance round-trip (1) — every one of them a plain function
  call against `kms-taxonomy.ts`.

**No test imports `index.ts` or `kms.ts`** (both Deno-only `https://…`/`.ts`-extension-import shells) or calls a
real network endpoint or mocks `fetch`/a `Deno` global — see §12.

## 10. `npm run typecheck` (`tsc --noEmit -p .`)

**Green: exit 0, no output.** This *is* the project's real gate (unlike an ad hoc standalone `tsc` invocation) —
`npm run typecheck` runs `tsc -p .` against the root `tsconfig.json`, and `tests/**` is INCLUDED by that config
(only `supabase/functions`, `web`, and `packages` are excluded — `tests/` is not). §12 explains the regression this
surfaced mid-train and the fix.

`supabase/functions` itself has no dedicated tsconfig and `deno` is not installed in this sandbox, so `deno check`
(the gate `kms.ts`/`index.ts` would actually run under at ceremony time, being Deno modules) could not be exercised
here — but that no longer matters for `npm run typecheck`'s purposes: after §12's split, nothing in the tsc-included
graph reaches either file, so this doc's earlier ad hoc `tsc --lib dom` probe of `kms.ts` (which surfaced TS 5.9's
`Uint8Array<ArrayBufferLike>` vs `BufferSource` lib-tightening noise, and an expected `.ts`-extension complaint) is
no longer relevant to CI — those files are simply outside the checked graph, by design, same as `index.ts` always
was.

## 11. Owner decisions left open

1. **Which KMS provider/algorithm actually goes live** (AWS KMS/ES256 vs a future GCP KMS/EdDSA adapter) — this
   train implements AWS KMS/ES256 as the *reference* adapter per the ceremony doc's AWS-shaped env var, but the
   ceremony itself is explicitly out of scope here (`UnconfiguredKmsSigner` stays the default).
2. **How `KMS_SIGNER_ROLE_ARN`'s credentials actually get into the runtime environment** — this adapter expects
   `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` to already be materialized (the Lambda/ECS
   task-role convention); whether Supabase's AWS-hosted edge runtime does this automatically, or needs an explicit
   `sts:AssumeRole` call added to `kms.ts`, is ceremony-time infrastructure work this train did not have visibility
   into.
3. **`TrustedKey.not_before`/`not_after`/`status`** are typed on `TrustedKey` (forward-compatible with an M1
   resolver projecting the full `kernel.signing_key` row) but intentionally **not** read by `verifyToken` —
   key-window/revocation admissibility is left as a door/M1-resolver concern, consistent with how
   `credential_version`/`session_id` are already split out of this module's authenticity check. Confirming that
   split holds for the real M1 resolver is for whichever train builds it.

## 12. `npm run typecheck` regression — mid-train fix, `kms-taxonomy.ts`

**The regression.** The root `tsconfig.json` excludes `supabase/functions` from its own root-file glob, but
`tests/**` is NOT excluded — so once `tests/credential-sign-kms.test.ts` imported `kms.ts` (to reach
`AwsKmsSigner`/`classifyAwsKmsHttpError`/etc.), `tsc -p .` was forced to type-check `kms.ts` too (TS resolves and
checks anything transitively imported by an included root file, regardless of that file's own exclude status).
`kms.ts` failed on two counts that are perfectly fine under Deno but not under this tsconfig:
- `TS5097` — `import { … } from './credential.ts'` (the `.ts` extension Deno *requires* for local imports; this
  project does not set `allowImportingTsExtensions`, and the coordinator's instruction was explicit: don't set it).
- `TS2345`/`TS2769` — `Uint8Array<ArrayBufferLike>` not assignable to `BufferSource` in the `crypto.subtle`
  (WebCrypto SigV4 HMAC/SHA-256) calls — a TypeScript 5.9 `lib.dom.d.ts` strictness tightening.

`npx vitest run` stayed green throughout (vitest transpiles per-file with esbuild; it never did a whole-project
`tsc` pass), which is why this only surfaced once CI's separate `npm run typecheck` step ran.

**The fix — split `kms.ts` into a pure half and a Deno-only half**, mirroring `credential.ts`'s own existing
pattern (zero imports, so it is safely importable from anywhere, including a tsc-included test):

- **`supabase/functions/credential-sign/kms-taxonomy.ts` (NEW, pure, zero imports)** — every DECISION worth
  unit-testing: `KmsErrorClass`/`KmsSignError`, the `KmsSigner` interface, `UnconfiguredKmsSigner`,
  `awsSigningAlgorithmForEs256Only` (algorithm→AWS-spec mapping), `requireAwsProviderConfig` (region/role
  presence), `resolveAwsCredentials` (credential presence — now takes an injected `getEnv: (name) => string |
  undefined` instead of reaching for a `Deno`/`process` global itself, which is what makes it directly
  unit-testable with a plain function and no global-mocking hack), `classifyAwsKmsHttpError` (HTTP-status
  taxonomy), and `validateAwsSignResponse` (the response `KeyId`/`SigningAlgorithm` security checks). `tests/
  credential-sign-kms.test.ts` imports ONLY from here (and from `credential.ts`) — never from `kms.ts`.
  `SigningAlgorithm` is duplicated here (not imported from `credential.ts`) because even `import type {…} from
  './credential.ts'` trips the same `TS5097` — it is a frozen, DB-pinned 2-value enum (migration 103's `check`
  constraint), so the duplication is not a drift risk, and TS compares the two structurally anyway.
- **`kms.ts` (unchanged role, thinner)** — stays the Deno-only SigV4-over-`fetch` transport (`AwsKmsSigner`,
  `signSigV4`, `sha256Hex`/`hmacSha256` via `crypto.subtle`, the real `.ts`-extension imports), now calling the
  pure functions above for every decision rather than inlining them. It re-exports the taxonomy pieces so
  `index.ts`'s import line (`from './kms.ts'`) needed NO changes. **Nothing in `tests/` imports `kms.ts`** — it is
  untested-by-tsc for the exact same structural reason `index.ts` always has been (a thin Deno-only shell around
  pure, separately-tested logic, invisible to a project tsconfig that excludes `supabase/functions` as long as
  nothing included re-imports it).

**Test-file consequence:** the former `AwsKmsSigner`-instance tests (which needed a temporary `globalThis.Deno`
shim and a stubbed `globalThis.fetch`, restored in `afterEach`, to exercise fail-closed/HTTP-response behavior)
were replaced with direct calls to the now-pure functions — `resolveAwsCredentials(() => undefined)` throws
without any mock; `validateAwsSignResponse({...}, requestedKeyId, expectedAlg)` is asserted directly for the
KeyId-mismatch/algorithm-mismatch SECURITY cases and the missing-signature PERMANENT case. This is not a coverage
reduction — the same decision logic is exercised, now as isolated pure-function tests instead of an
integration-style test that also depended on mocking global state; test count went from 65 → 74 (net +9: the old
5-test mocked-transport block became 18 pure-function tests, i.e. finer-grained, not fewer).

**Verified:** `npm run typecheck` → exit 0, no output. `npx vitest run` → 14 files, 599 passed (up from 590 before
this fix, matching the 65→74 delta in the KMS test file).

## 13. Adversarial-review fixes (P0/P2), post-§12

Four findings from an adversarial pass over `credential.ts`/`kms-taxonomy.ts`, fixed in place:

1. **[P0] `verifyToken` never enforced `typ === DOMAIN`.** The docstring's domain-separation argument ("a forged
   `typ` breaks the signature, since `typ` is inside the signed bytes") only defends against FORGERY — it does
   nothing against REPLAY of a genuinely-signed DIFFERENT-typ credential (e.g. a wallet/door manifest) whose
   payload happens to shape-match `{atom,exp,iat,sess,ver}`; that token's signature is real and would otherwise
   verify. Fixed: `verifyToken` now checks `decoded.header.typ !== DOMAIN` FIRST — before the alg-shape check,
   before any key resolution — refusing `wrong_typ` (new `VerifyReason` member). The existing forgery-direction
   test's expectation moved from `signature_invalid` to `wrong_typ` (caught earlier now); a new REPLAY-direction
   test proves the actual gap this closes: it mints a token for a *different* `typ` with a real key and a
   genuinely valid signature (asserted valid directly against the raw bytes before calling `verifyToken`, so the
   test cannot be satisfied by an accidentally-broken signature), then confirms `verifyToken` still refuses it as
   `wrong_typ`.
2. **[P2] `decodeTokenStructure` had no size cap.** Added `MAX_TOKEN_LENGTH = 8192` (exported), checked first,
   before any base64/JSON work — the DoS bound now lives in the one function every caller goes through, not as an
   unstated caller obligation. Tests: an over-cap token → `malformed_token`; a boundary proof that a well-formed
   token AT exactly the cap still decodes while one byte over is unconditionally rejected (proves `>`, not `>=`).
3. **[P2] `validateAwsSignResponse` skipped its `KeyId`/`SigningAlgorithm` checks when the field was ABSENT**
   (`if (json.KeyId && …)` / `if (json.SigningAlgorithm && …)` — "no check needed"). Fixed: both checks are now
   unconditional — a 200 response that OMITS either field is a `security`-class `KmsSignError`, same as a
   present-but-wrong one, since an absent field gives no way to confirm AWS used the requested key/algorithm at
   all (defense-in-depth behind sign-after-verify, §7). The one existing test asserting the old "skip" behavior
   was replaced (not deleted-and-forgotten) with three tests covering the new behavior: KeyId absent, algorithm
   absent, and both absent.
4. **[P2] `readDerLength` accepted some non-minimal long-form lengths and could misreport an overflow.** Two
   non-minimality shapes are now both rejected, with distinct messages: a leading `0x00` length byte (padding
   that contributes nothing — value fits in fewer bytes), and a long-form length whose VALUE still resolves under
   `0x80` (should have used short form at all). Length accumulation switched from bitwise (`<<`/`|`, which can
   wrap a large 4-byte value into a negative 32-bit int) to plain arithmetic (`length * 256 + byte`), and a
   syntactically-minimal-but-too-large length now gets its OWN "exceeds buffer size (out of range)" message
   rather than falling through to a generic/misleading one. Three new tests: leading-zero-byte non-minimality,
   short-form-eligible non-minimality, and a minimal-but-out-of-range length. Only affects parsing AWS's own
   `Sign` response (already `security`-class, fail-closed input) — hardening to match the code's own stated
   minimal-encoding claim, not a change in what's reachable from a real signing flow.

**Verified:** `npm run typecheck` → exit 0. `npx vitest run` → 14 files, **609 passed** (up from 599 at the start
of this round — `tests/credential-sign.test.ts` 23→26, `tests/credential-sign-kms.test.ts` net +7 driven by the
`validateAwsSignResponse` behavior-flip (6→8 tests, one replaced by three) and the three new DER-minimality
tests). No existing assertion was deleted without a same-scope replacement; the two assertions whose EXPECTED
VALUE changed (the forgery-direction `typ` test, the `validateAwsSignResponse` absent-KeyId test) changed because
the underlying behavior was intentionally hardened by this round's fixes, not because coverage was narrowed.
