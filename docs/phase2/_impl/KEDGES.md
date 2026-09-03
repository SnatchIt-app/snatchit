# KEDGES — `door-session` + `door-manifest` (DARK, undeployed)

Repo `snatchit-consol`, branch `feature/venue-native-and-product-v2`. This
implements `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §3.9a
(`door-session`) and §3.9b (`door-manifest`) — the door plane. **DARK/local
only: no deploy, no KMS call, no git commit, no Supabase MCP, no
production.** The RPCs these edges wrap are dark/parked (`mint_door_session`
is PFA-26-parked, fail-closed, zero mutation), so the flow is authored but
cannot function end-to-end — that is the stated, expected state.

## Files touched

- `supabase/functions/door-session/index.ts` (NEW, per brief)
- `supabase/functions/door-session/pure.ts` (NEW, **not** on the brief's
  4-file list — see "Deviation from the file list" below)
- `supabase/functions/door-manifest/index.ts` (NEW, per brief)
- `tests/door-session.test.ts` (NEW, per brief)
- `docs/phase2/_impl/KEDGES.md` (this file, NEW, per brief)

No migration, no other edge function, and no other test file was modified.
`git status` at the end of this session shows unrelated concurrent changes
(`POST_FREEZE_AMENDMENTS.md`, `CLAUDE_B_BACKEND_HANDOFF.md`,
`PRIMARY_TICKETING_ACTIVATION_MATRIX.md`, several `supabase/tests/*.sql`
files, migration `105`, test `171`) — none of these were touched by this
work; they predate or are concurrent with this session.

## Deviation from the file list: `pure.ts`

The brief's own Tests section says: *"if you need Deno-only imports in
index.ts, DON'T import index.ts from a test — test only pure helpers,
ideally factored into a small pure module the test imports."* `index.ts` has
a remote `serve` import and a `createClient` from esm.sh that `tsc -p .`
cannot resolve; the root `tsconfig.json` excludes `supabase/functions` from
its own root-file glob, but `tests/**` is not excluded, so a test importing
anything from `index.ts` — even one named function — forces tsc to
type-check the whole file and fails. There is no way to satisfy "pure-logic
unit tests, no `.ts`-extension imports reaching tsc" while keeping the
testable logic physically inside `index.ts`. `credential-sign` solved this
exact problem with `credential.ts`/`kms-taxonomy.ts` (pure siblings, zero
imports, imported by both `index.ts` and tests). I added one file,
`door-session/pure.ts`, following that precedent — new path, nobody else's
ownership, zero conflict surface. Flagging this explicitly since the brief's
file list was otherwise exact and this is the one place I went beyond it.

`door-manifest` needed no equivalent split — it has no pure logic complex
enough to warrant one, and the brief requires no test file for it.

## `door-session` (§3.9a) — routes, auth model, DARK behavior

- **`verify_jwt: false`, Class B (B-iii).** No `auth.uid()` anywhere on this
  path. `kernel.assert_door_session` is the ONLY gate on every relay call;
  its constant-time compare and dummy-compare-on-unknown-id anti-enumeration
  behavior live in the DB, never re-implemented in the edge.
- **`/mint`, `/refresh`** — both call `venue.mint_door_session` (there is no
  `venue.refresh_door_session`, per RPC §1.1d `AUTHZ-H3a`(b)). Body
  `{venue_id, session_id, device_id, pin, command_key}`. **PFA-26: every
  call today raises `precondition_failed: door_pin_kdf_unavailable`, zero
  mutation** — caught via `isDoorPinKdfUnavailable` and surfaced as a clean
  `503 {code:"pin_unavailable"}`, never a crash. The success/`noop_replay`
  branches are written to the full §9.6 contract for when PFA-26 un-parks,
  but are **currently unreachable** in this environment.
- **`/manifest/sync`, `/scan`, `/offline-batch`** — shared preamble
  (`admitRelayCall`): parse the `DoorSession <id>.<secret>` bearer → rate
  limit (fail closed) → `kernel.assert_door_session(p_device_id, p_session_id,
  p_door_session_id, p_session_token)` → cross-check the **returned**
  `device_id` against the body's (EDGE-4c: the returned value is the only
  one ever passed downstream as `p_actor_device_id`; the body's is a
  defense-in-depth cross-check only, a mismatch is an opaque 401 + Sentry
  event). `/scan` and `/offline-batch` additionally reject any
  `scan_meta`/batch-row carrying a `device_id` key (`invalid_input`, RPC
  §9.4/§9.5 X-5) **before** calling `assert_door_session` — cheap input
  validation ahead of the DB round trip. Since `assert_door_session` can
  never resolve a live row while no session can ever be minted (PFA-26),
  every relay call in this environment fails at the assert step with the
  opaque 401 — also expected.
- **Rate limits** (fail closed, `check_rate_limit` RPC): `/mint` + `/refresh`
  share ONE principal, `uuidv5(NS_DOOR_PIN, venue_id||':'||device_id)`, one
  action bucket (`door-pin:mint`), 5/60 — refresh cannot be a limiter-free
  path to unlimited PIN attempts. Each relay route uses
  `uuidv5(NS_DOOR_SESSION, door_session_id)` with a per-route action
  (`door-session:scan` etc.), 60/60 each — a separate budget from the PIN
  principal by construction (namespace separation), asserted in tests.
- **Data minimization / logging.** Every handler returns only what the
  wrapped RPC returns (mint's success shape is hand-restricted to
  `{door_session_id, secret, expires_at}` even though the RPC result carries
  more). `logOutcome` only ever writes `route`, `door_session_id` (the
  non-secret PK selector — explicitly loggable per §3.9a),
  `session_id`, `venue_id`, `outcome` — never the PIN, the secret, the full
  bearer header, or PII.

## `door-manifest` (§3.9b) — routes, auth model, DARK behavior

- **`verify_jwt: true`, Class A, single route.** Staff JWT
  (`venue_scanner`/`venue_manager`). `venue.get_door_manifest` is called on
  a client built from the CALLER's forwarded `Authorization` header — never
  service_role — so `has_venue_role` rides the caller's own JWT. The
  formerly-specified PIN/door-session route is deleted, not split (EDGE-2):
  `door-session`'s `/manifest/sync` already serves that traffic at
  `verify_jwt: false`.
- **KMS signing** reuses `credential-sign/kms.ts` /
  `credential-sign/kms-taxonomy.ts` (`KmsSigner`/`UnconfiguredKmsSigner`/
  `AwsKmsSigner`) unmodified, imported not copied. Provider selection
  mirrors `credential-sign/index.ts`'s `selectKmsSigner` exactly: unset/
  non-`aws` `KMS_PROVIDER` → `UnconfiguredKmsSigner`, which throws
  `kms_provider_unconfigured` unconditionally. **In this environment that is
  always the path taken** — surfaced as a clean `500 {code:"kms_unconfigured"}`,
  never a crash, never a silent unsigned fallback. (The brief's §3.9b text
  also notes a TLS-only unsigned-fallback is "acceptable for MVP" as an
  alternative the owner could choose; I implemented the clean-500-degrade
  branch, per the brief's own explicit steer for the parallel door-session
  PFA-26 case, and did not add the unsigned-fallback branch. It is a single
  `if` away if the owner prefers graceful degradation over a hard failure —
  flagged as a product decision, not made here.)
- **No open episode** (`get_door_manifest` returns
  `{open:false, status:'no_open_manifest'}`) is treated as a legitimate
  state, not an error — returned as `{manifest, signature: null}`, `200`,
  with nothing to sign.
- **Data minimization.** The response is `{manifest, signature}` where
  `manifest` is exactly what `get_door_manifest` returned (it already
  excludes `public_key`/identity per PFA-24) and `signature` is
  `{value: base64, algorithm}` only — no key handle, no public key returned
  to the client.
- **Rate limit** (30/60, `check_rate_limit` keyed on the caller's
  `auth.uid()`): not literally named by §3.9b, added per the parent brief's
  general "rate-limit-fail-closed" shell requirement and mirroring
  `credential-sign`'s own 30/60 on the same Class-A/staff-JWT shape.

## Spec ambiguities hit (all flagged inline in the files, summarized here)

1. **UUIDv5 namespace values.** The frozen contract names the scheme —
   `uuidv5(NS_DOOR_PIN, …)` / `uuidv5(NS_DOOR_SESSION, …)` — but no document
   in the corpus specifies the two namespace UUIDs themselves. `pure.ts`
   defines two fixed constants (`NS_DOOR_PIN`, `NS_DOOR_SESSION`); what
   matters for correctness is that they are fixed and distinct, which is
   what the tests assert. An owner ceremony should ratify (or replace) these
   values before any real deploy, since changing them later silently resets
   every derived rate-limit bucket.
2. **`door-manifest`'s KMS key handle/algorithm.** Unlike M1
   (`kernel.get_ticket_signing_context` resolves a per-atom pinned key), no
   RPC in the corpus resolves a manifest-signing key/handle/algorithm for
   M2. I read an inferred env var (`DOOR_MANIFEST_KMS_HANDLE_REF`, default
   empty) and hardcode `ES256` (AWS KMS's only offered algorithm per
   `kms.ts`'s own header). Both are inert while `KMS_PROVIDER` is unset
   (the only reachable state here) — flagged as an open question for
   whichever change first sets `KMS_PROVIDER=aws` for this function.
3. **`/mint` vs `/refresh` rate-limit action key.** §3.9a describes them as
   one combined "`/mint`+`/refresh` … 5/60" line item; I read that as one
   shared action bucket (`door-pin:mint`) rather than two separate 5/60
   budgets, since a re-mint is the identical underlying operation. If the
   owner intended two independent 5/60 budgets, that's a one-string change
   (`'door-pin:refresh'` for the refresh route).
4. **`mint_door_session`'s `noop_replay` response shape on idempotent
   replay** is under-specified beyond "returns the ORIGINAL `door_session_id`
   — but NOT the secret." I return `{door_session_id, expires_at, replayed:
   true}`, defensively reading `expires_at` from the RPC response if present
   (it is not explicitly promised on the replay branch). This branch is
   unreachable while PFA-26 is parked, so it has not been exercised.
5. **`assert_door_session`'s PostgREST return shape** (single row vs.
   composite vs. one-element array for a `RETURNS (device_id, event_session_id)`
   function) is not pinned by the corpus. `admitRelayCall` accepts either a
   bare object or a one-element array defensively; unverifiable without a
   live RPC.

## Test counts / verification

- `npx vitest run tests/door-session.test.ts` — **63 passed**, 0 failed. All
  cases are plain function calls against `pure.ts`: bearer parsing (13
  malformed-input cases, all null-not-throw), route dispatch (9 positive + 6
  negative), device-id cross-check, forbidden-`device_id` detection (single
  + batch), the token_hash wire contract (validated against NIST's SHA-256
  test vectors for `""` and `"abc"`), `uuidv5` (validated against the
  canonical RFC4122 DNS-namespace/`"python.org"` worked example — an
  independent correctness check of the hand-rolled SHA-1, distinct from this
  system's own namespace constants), rate-limit principal derivation
  (determinism + namespace separation), the PFA-26 park detector, and the
  `assert_door_session` opaque-error classifier.
- `npx vitest run` (full suite) — **672 passed**, 15 files, 0 failed.
- `npm run typecheck` (`tsc --noEmit -p .`) — **exit 0**, no output. Neither
  `index.ts` file is reachable from any included root file (both are
  Deno-only and never imported by a test), so neither is type-checked by
  design — same posture `credential-sign/index.ts` and `kms.ts` already
  have. `pure.ts` IS type-checked (imported by the test) and passes cleanly:
  no `.ts`-extension import reaches tsc (`pure.ts` is import-free), and no
  WebCrypto/`BufferSource` call exists anywhere in it — both SHA-1 and
  SHA-256 are hand-rolled in plain bitwise JS specifically to avoid that
  trap, per its own file header.

## What remains genuinely untestable here

Nothing beyond pure logic could be exercised: `mint_door_session` always
raises PFA-26's park before any real precondition check runs, so the
opaque-mint-failure and success/replay branches, the `/refresh` re-mint-
revokes-prior-row behavior, and every `assert_door_session`-gated relay call
are all inert by construction in this environment — exactly as the brief
states to expect. Wiring/integration verification (a real Supabase branch,
a real `mint_door_session` call, a real `assert_door_session` round trip)
is out of scope for this DARK/local pass.
