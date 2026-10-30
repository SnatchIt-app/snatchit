# KCRYPTO — `credential-sign` implementation report (edge + pure builder + PFA-PT-6)

**Agent CRYPTO-IMPL.** Repo `/Users/josetascon/snatchit-consol`, branch
`feature/venue-native-and-product-v2`. Scope per `DESIGN_102.md` §2: the `credential-sign` edge
(DARK, `https://` imports, NOT deployed), its import-free pure module, the vitest suite, and
`PFA-PT-6` (the wire-encoding amendment). **No production, no deploy, no KMS, no signing key, no
secret, no migration, no `supabase/tests/*.sql`, no DB touched** — this train's boundary
(`TRAIN_BRIEF.md`). `kernel.get_ticket_signing_context` (migration 102) is authored concurrently by
DB-IMPL against the same `DESIGN_102.md` §1.1 contract; this report codes against that contract's
`jsonb` shape and does not assume the migration has landed or run.

Sources read in full before authoring: `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §3.2 (the
request/response contract) and §5 in full (C33 — key hierarchy §5.1, key scope §5.2, KMS custody
§5.3, the M1/M2 manifests and `OFFLINE-VERIFY-v1` §5.4, offline token behavior §5.5, rotation/
revocation §5.6, signer HA/throughput/fallback §5.7); `supabase/functions/stripe-webhook/{index,native}.ts`
and `supabase/functions/_shared/{sentry,stripe}.ts` (house patterns); `supabase/functions/
primary-checkout/index.ts` in full (the closest analog: owner-JWT auth, `check_rate_limit`,
CORS/security headers, `parseBody`/UUID validation, structured stage logging — all copied in shape);
`supabase/functions/payout-execute/{executor,index}.ts` (the pure-module/edge-shell split this
package follows); migration `079` (`kernel.tickets` DDL — confirms `current_owner_id`, `state`,
`resale_state`, `credential_version`, `signing_key_id`, `event_session_id` column names) and `083`
(`kernel.signing_key` DDL — confirms the table has **no `algorithm` column**, which is why the
canonical builder defaults to `EdDSA` rather than reading one); `docs/architecture/_governance/
POST_FREEZE_AMENDMENTS.md` (PFA-PT-4/PFA-PT-5 as the filing template, confirmed `PFA-PT-6`
unclaimed).

## 1. Objects built

| # | File | Contents |
|---|---|---|
| 1 | `supabase/functions/credential-sign/credential.ts` (≈400 lines) | The pure, import-free module: base64url encode/decode (hand-rolled, no `Buffer`/`btoa`), canonical JSON stringify (recursive key-sort, no whitespace), `toUnixSeconds`, `buildHeader`/`buildPayload`/`buildCanonicalPayload`, `encodeToken`, `decodeTokenStructure`, `verifyToken` (pluggable `VerifyPrimitive` + `PublicKeyResolver`), `buildCredentialSignLogLine`. |
| 2 | `supabase/functions/credential-sign/index.ts` (≈300 lines) | The edge I/O shell: auth, rate limit, body parse, calls `kernel.get_ticket_signing_context` as the owner (JWT-forwarded, `SUPABASE_ANON_KEY` client), maps refusal codes, signs via a `KmsSigner` provider-adapter interface (default throws `kms_provider_unconfigured`), responds, logs, Sentry. |
| 3 | `tests/credential-sign.test.ts` (23 cases) | Determinism, domain separation, tamper detection ×3, K1/K2 rotation ×2, exp/iat/ttl ×5, base64url round-trip ×3, log shape ×2, canonical shape ×3. Ed25519 via `node:crypto` (test-only). |
| 4 | `docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` | `PFA-PT-6` appended (PENDING OWNER SIGNATURE) — pins the wire encoding. |
| 5 | `docs/phase2/_impl/KCRYPTO_credential_sign.md` | This file. |

## 2. The canonical payload spec

Full normative text is filed as `PFA-PT-6` (§ above); this section is the implementation-facing
summary plus the one interpretation note the frozen spec left implicit.

**Wire shape** (JWS-compact, three base64url segments):

```
token = b64url(header) . b64url(payload) . b64url(signature)
```

**Header** (canonical JSON, sorted keys, no whitespace) — 3 keys:

```json
{"alg":"EdDSA","kid":"<key_id, lowercase uuid>","typ":"SNATCHIT-TICKET-CRED-V1"}
```

**Payload** (canonical JSON, sorted keys, no whitespace) — 5 keys:

```json
{"atom":"<ticket_atom_id>","exp":<unix seconds>,"iat":<unix seconds>,"sess":"<session_id>","ver":<credential_version>}
```

The six frozen claims (`atom_id, session_id, credential_version, key_id, issued_at, exp`) split
1 (header: `key_id` → `kid`) + 5 (payload). `alg` and `typ` are not claims from the frozen list —
`alg` is signer metadata (needed to select a verify algorithm before the payload is even parsed)
and `typ` is the domain separator (§3 below), added deliberately, not smuggled in.

**Canonical JSON** — `canonicalJSONStringify` sorts object keys recursively and emits no
whitespace, so the byte sequence is identical regardless of the source object's literal key
order (proven: `tests/credential-sign.test.ts` "is insensitive to the object literal key
insertion order"). All uuids are lowercased before serialization (`normalizeUuid`). All
timestamps are `Math.floor(unix milliseconds / 1000)` — **integers only**; `toUnixSeconds`
throws on an unparseable string rather than silently emitting `NaN` into a signed payload.

**Interpretation note (not a deviation, but stated for traceability):** `kernel.
get_ticket_signing_context`'s `jsonb` (DESIGN_102.md §1.1) carries both a **key window**
(`not_before`/`not_after` — the signing key's own validity, from `kernel.signing_key`) and a
**token window** (`issued_at`/`exp` — this specific credential's validity, `issued_at = now()`,
`exp = issued_at + credential.app_ttl_interval`). The edge response contract (§3.2) has a single
`not_after` field with no `exp` field alongside it. This implementation reads the edge's
`not_after` as **the token's own expiry** (`ctx.exp`, restated as a timestamp) — the natural
reading of "when does this credential stop being valid," and the same fact `ttl_seconds` already
carries in duration form — rather than the signing key's window bound (`ctx.not_before`/
`ctx.not_after`, which is never surfaced to the client in this implementation, matching §5.3's
non-exposure posture for the key's own operational metadata). `supabase/functions/
credential-sign/index.ts`'s response-assembly comment states this explicitly at the point of use.

## 3. Domain-separation proof

**Claim:** a signature minted for a ticket credential (`typ:"SNATCHIT-TICKET-CRED-V1"`) cannot be
reinterpreted as a signature over any other signed-object type this system mints (a wallet
manifest, a door manifest, a future refund receipt, …), and this holds **structurally** — no
`if (typ === …)` branch is required anywhere in the verifier for the separation to hold.

**Mechanism:** `typ` lives inside the **protected header**, and the protected header is part of
the **signed bytes**:

```
signedBytes = ASCII( b64url(header) + "." + b64url(payload) )
```

Changing any header field — including `typ` — changes `b64url(header)`, which changes
`signedBytes`, which the original signature no longer covers. A verifier that recomputes
`signedBytes` from the token's own header/payload segments (rather than trusting a claim about
them) will therefore reject any token whose header was altered after signing, `typ` included.

**Constructed proof** (`tests/credential-sign.test.ts`, "domain separation — the typ claim"):

1. Build a canonical ticket credential for a fixture context, sign it with a throwaway Ed25519
   keypair. Confirm it verifies (`{authentic:true, reason:'ok'}`).
2. Forge a second header: **identical** `alg` and `kid`, **different** `typ`
   (`SNATCHIT-WALLET-MANIFEST-V1`). Base64url-encode it. Assemble a "forged token" using this new
   header, the **original, unmodified payload segment**, and the **original, unmodified
   signature** — i.e., attempt to replay a genuine ticket-credential signature as if it signed a
   wallet-manifest object.
3. Verify the forged token against the SAME trusted public key. Result:
   `{authentic:false, reason:'signature_invalid'}`. Assert `forgedHeaderB64 !== canonical.headerB64`
   — the header bytes did change, which is *why* the signature no longer matches.

This is the general case, not a special-cased test of one string: any two headers differing only
in `typ` produce different `signedBytes`, so the argument generalizes to every present and future
`typ` this system or a sibling system defines. The one operational obligation this places on future
work: **every new signed-object family must mint its own `typ` constant and never reuse
`SNATCHIT-TICKET-CRED-V1`.** `PFA-PT-6` states this as the entirety of the domain-separation
contract — no registry needed, only distinct constants.

**Scope note:** this proof is about `typ` domain separation specifically. `session_id` binding and
`credential_version` currency are separate, already-frozen checks (`OFFLINE-VERIFY-v1` §5.4.3,
checks 3 and 3b.iii) that this package does not implement (they are door/live-read concerns, not
signer concerns) and does not claim to prove here.

## 4. The failure model

| Condition | Source | HTTP | Sentry | Notes |
|---|---|---|---|---|
| Missing/malformed `Authorization` | edge | 401 | — | Before any DB call. |
| Invalid/expired JWT | `auth.getUser` | 401 | — | |
| Rate limit RPC errors | `check_rate_limit` | 503 + `Retry-After: 30` | — | Fail CLOSED (mirrors `primary-checkout`). |
| Rate limit exceeded | `check_rate_limit` | 429 + `Retry-After: 60` | — | 30/60s per spec §3.2. |
| Body not JSON / missing `ticket_atom_id` | edge | 400 | — | |
| `get_ticket_signing_context` RPC-level error (not a refusal) | Postgres/PostgREST | 500 | exception | Genuinely unexpected — a defect, not a business refusal. |
| `status:'refused', code:'not_owner'` | DB authority | 403 | **message** (fraud signal, per spec §3.2's "capture … owner-mismatch spikes") | Actor is not `current_owner_id`. |
| `status:'refused', code:'atom_terminal'` | DB authority | 409 | — | Voided/scanned/expired atom — not an ops alert, an expected user-facing state. |
| `status:'refused', code:'signing_key_unavailable'` | DB authority | 500 | exception | Ops-critical: an event with issued atoms but no active/in-window key. |
| `status:'refused', code:'<anything else>'` | DB authority | 500 | exception | Defensive — an unrecognized code from the DB is treated as a defect, not guessed at. |
| Malformed `status:'ok'` response (missing a required field) | edge validation | 500 | exception | `isSigningContextOk` is a runtime type guard, not just a TS cast. |
| `KmsSigner.sign` throws `kms_provider_unconfigured` | edge (this train's only reachable path) | 500 | exception | Permanent config error — no signer wired in at all. |
| `KmsSigner.sign` throws a transient-looking error (throttling/timeout/unavailable, matched by name) | edge | 503 + `Retry-After: 5` | exception | Spec §3.2 "KMS down → 503"; §5.7's stated fallback is the client's cached token, not a retry loop here. |
| Any other unhandled exception | edge | 500 | exception | Outer `try/catch`, generic message, no internals leaked. |

**What is deliberately NOT re-derived here:** ownership, atom liveness, key resolution/pinning, and
version/TTL derivation are 100% `kernel.get_ticket_signing_context`'s job (DESIGN_102.md §1.1). This
file contains no ownership check, no atom-state check, and no key-lookup query of its own — the
single DB call is the only source of those facts, matching the frozen spec's "the edge does NOT
pick facts itself."

**Logging** — every outcome above logs exactly `{tag:'credential-sign', atom_id, credential_version,
key_id, outcome}` via `buildCredentialSignLogLine` (pure, in `credential.ts`), which structurally
admits only those four fields plus the fixed tag — there is no parameter through which a token,
a canonical payload, or `kms_handle_ref` could be logged. `tests/credential-sign.test.ts`'s "log
shape" cases assert this both by exact key-set (`Object.keys(parsed).sort() === [...]`) and by
substring-absence of a real constructed token/payload/signature in the emitted line.

## 5. The idempotency argument (business-level, not byte-identical)

The frozen model (§5.5, restated in `DESIGN_102.md` §0) is **stateless**: no dedup row, no
"already signed" table, no async claim/lease. Idempotency is defined over
**`(ticket_atom_id, credential_version)`**, not over the signature's bytes:

- **Why not byte-identical:** ECDSA-P256 signing is nondeterministic by construction (a fresh
  random `k` per signature) — two calls to `KMS.sign` over the identical bytes produce two
  *different*, both-valid signatures. Even for Ed25519, which IS deterministic per RFC 8032, this
  module never relies on that property — `verifyToken` does not compare one token's bytes to
  another's, it verifies each token independently against the trusted public key.
- **What makes re-signing safe, not what makes it byte-stable:** for a fixed `(atom_id,
  credential_version)`, `buildCanonicalPayload` is a **pure function** of the DB-derived context —
  proven by the determinism tests (`tests/credential-sign.test.ts` §1: identical `signingInput`
  for two independently-built canonical payloads over the same context, and insensitivity to
  object-literal key order). Two signs of the same `(atom_id, version)` therefore produce two
  tokens that are byte-different (different signature) but **semantically equivalent** — both
  carry the identical `atom`, `sess`, `ver`, and (modulo the request's own `now()`) an
  `iat`/`exp` pair from the same TTL policy. Both verify. Neither is "more correct" than the
  other. A client may re-call `credential-sign` freely (spec: "safe/read-only; client may re-sign
  freely").
- **What actually invalidates a token is the version, not a dedup mechanism:** a custody move
  (`transfer_ticket_ownership`, `void_ticket_atom`) bumps `kernel.tickets.credential_version` in
  the RPC layer (already shipped, untouched by this package). The NEXT call to
  `get_ticket_signing_context` returns the NEW version; a cached OLD token still carries the OLD
  `ver` claim, so `OFFLINE-VERIFY-v1` conjunct 3b.iii (or the online live-read equivalent)
  rejects it as `version_stale`. This package's only obligation toward that mechanism is to sign
  whatever version the DB hands it — it does, unconditionally (`ctx.credential_version` flows
  straight from the RPC response into `buildPayload`'s `ver` field, with no caching, no "have I
  signed this atom before" check, and no version arithmetic of its own).
- **No new state, no new failure mode:** because there is nothing to dedupe, there is nothing to
  leak, orphan, or double-write. A KMS outage mid-request degrades to "the caller gets a 503 and
  retries, or falls back to a still-cached, still-verifiable earlier token" (§5.7) — never to a
  half-written row, because no row is written.

## 6. vitest results

```
Test Files  1 passed (1)
     Tests  23 passed (23)
```

Full suite (baseline **489**, confirmed by an `npx vitest run` immediately before this package was
authored): **512 passed (512)** — 489 + 23, no regression, no skip.

`npm run typecheck` (`tsc --noEmit -p .`): clean. (`supabase/functions` is excluded from the
project's `tsconfig.json`, matching every other edge function — the `.ts` files there are Deno
modules with `https://` imports `tsc` cannot and does not attempt to resolve; `credential.ts` and
`index.ts` are typechecked implicitly by `tests/credential-sign.test.ts`'s import of `credential.ts`,
which IS inside the vitest/tsc project boundary.)

`npm run lint` (`expo lint`, scope: `/src`, `/app`, `/components` only — confirmed via `expo lint
--help`; `supabase/functions` has never been in this command's scope, for any edge function in the
repo): **0 errors, 45 warnings** — identical to the pre-existing baseline (unrelated
`react-hooks`/`no-unused-vars` warnings in mobile screens; nothing under `supabase/functions/
credential-sign` or `tests/credential-sign.test.ts` is flagged, because nothing under
`supabase/functions` is scanned by this command). A direct `npx eslint
supabase/functions/credential-sign/*.ts` (outside the project's actual lint gate) reports two
`import/no-unresolved` errors on the two `https://` imports in `index.ts` — this is identical to
running the same direct command against `primary-checkout/index.ts` or any other existing edge
function (verified), confirming it is a pre-existing property of every Deno-style edge module in
this repo, not a defect introduced here, and not part of the `npm run lint` gate this train's
verification step actually runs.

## 7. Boundary confirmation

No `supabase functions deploy`, no Supabase MCP call, no network call to any KMS endpoint, no
`.env`/secret file read or written, no migration authored or edited, no `supabase/tests/*.sql`
touched, no `git commit`. `UnconfiguredKmsSigner.sign` is the only KMS-shaped code path in
`index.ts` and it throws unconditionally — there is no configuration, flag, or code path in this
package that would let it reach a real KMS endpoint even if one were reachable from this
environment.
