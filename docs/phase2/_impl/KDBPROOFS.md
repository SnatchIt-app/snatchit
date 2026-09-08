# K-DBPROOFS — pgTAP proofs for 103 (algorithm pin), old-owner currency,
# pinned-key rotation, and double-scan first-in-wins

**Status:** implemented, green against the local rehearsal harness.
**File owned:** `supabase/tests/169_signing_key_algorithm_and_door_proofs.sql`
(new, `plan(34)`, 34/34 `ok`).
**Scope:** DB-side proofs only. This build did not touch migrations,
`supabase/functions/`, or any `*.test.ts` (vitest owns the client/offline
half of the old-owner-screenshot and token-header-algorithm stories).

---

## 1. What 169 proves, by assertion code

### Section A — migration 103 schema/authority (A1–A11)

| Code | Establishes |
|---|---|
| A1 | `kernel.signing_key.algorithm` exists |
| A2 | `algorithm` is `NOT NULL` |
| A3 | default is `'EdDSA'` (§5.1-preferred) |
| A4 | the CHECK is **exactly** `algorithm = ANY (ARRAY['EdDSA','ES256'])` — no RSA, no symmetric name, no `none` (exact `pg_get_constraintdef` match, not a substring match) |
| A5 | `authenticated` has `SELECT` on `algorithm` (103's new grant — the M1-manifest-distributable projection) |
| A6 | `authenticated` still has **no** `SELECT` on `kms_handle_ref` (103 does not touch that fence) |
| A7 | `algorithm` is immutable after creation — `UPDATE ... SET algorithm=...` raises `append_only` via the 103-recreated `guard_signing_key_immutable` |
| A8 | `active -> revoked` is still a legal forward transition post-103 (guard body unaffected outside the new `algorithm` clause) |
| A9 | `revoked` is still terminal post-103 — `revoked -> active` still raises |
| A10 | `get_ticket_signing_context` round-trips the **default** algorithm (`EdDSA`) for a key that didn't name one |
| A11 | `get_ticket_signing_context` round-trips an **explicitly** `ES256` key — not silently coerced to the default |

### Section B — old-owner screenshot currency mechanism, DB half (B1–B8)

| Code | Establishes |
|---|---|
| B1 | freshly minted atom: `validate_ticket_online` reports `credential_version=0` |
| B2 | `kernel.transfer_ticket_ownership` (A→B, cause=`admin_action`) executes `status=ok` |
| B3 | the head: `current_owner_id=B`, `credential_version` incremented by **exactly one** (0→1), `resale_state='none'` |
| B4 | `validate_ticket_online` now reports the **new** version (1) |
| B5 | OLD version ≠ NEW version — the DB-side currency fact a screenshotted old credential goes stale against (the offline vitest proves the token side; this is the source of truth it reads) |
| B6 | owner A (old) is refused `not_owner` by `get_ticket_signing_context` — no signing context for a stale-owned atom |
| B7 | owner B (new) gets `status=ok` |
| B8 | …carrying the **new** `credential_version` (1) |

### Section C — pinned-key rotation (C1–C9)

| Code | Establishes |
|---|---|
| C1 | baseline, before rotation: `get_ticket_signing_context(T1)` is `ok`, `key_id=K1` |
| C2 | `K1` active → rotating (legal transition; frees the one-active-per-event-scope slot) |
| C3 | `K2` inserts **active** for the *same* event — the slot the rotation freed |
| C4 | `T1.signing_key_id` is still `K1` — never re-pinned by the rotation |
| C5 | `T2.signing_key_id` is `K2` — the new mint pins the new active key |
| C6 | **the actual "never a fresh scope lookup" proof**: after rotation, `get_ticket_signing_context(T1)` is refused `signing_key_unavailable` — NOT silently handed `K2`'s material. A resolver that fell back to "the scope's current active key" would wrongly return `ok`/`key_id=K2` here; the frozen behavior refuses outright instead |
| C7 | `get_ticket_signing_context(T2)` still returns `key_id=K2`, unaffected by `T1`'s state |
| C8 | `K1` rotating → revoked is a legal forward transition |
| C9 | post-revoke: `T1` stays refused `signing_key_unavailable`; `T2` is wholly unaffected |

**Correction against the brief's draft wording:** the brief phrased C5/C6 as
*"`get_ticket_signing_context(T1)` still returns `key_id=K1` even though K2 is
active."* That is not what the frozen 103 body does and is not what should
happen: `kernel.get_ticket_signing_context` refuses outright
(`signing_key_unavailable`) the instant the **pinned** key's own `status`
leaves `'active'` — it never falls back to a fresh scope lookup, and it never
returns `key_id` in a refusal payload at all (168's A21/A22 already pin this
exact behavior for a rotating key). Section C is written to the actual,
stronger, and correct invariant: the pin is provably never silently
re-resolved to the new active key, proven by the refusal itself rather than
by a same-key echo. Nothing in migration 103 or the guard needed to change to
make this true — it was already true; 169 is the first place it is asserted
for a *rotation*, not just a single stale key (168 covers the single-key
case).

### Section D — double-scan first-in-wins (D1–D6)

| Code | Establishes |
|---|---|
| D1 | **the concurrency guarantee itself**: `venue.scan_admitted_in_uq` is a `UNIQUE` index on `(ticket_atom_id, event_session_id)` `WHERE result='admitted' AND direction='in'` — structural, holds under any interleaving |
| D2 | the first `record_scan` admits |
| D3 | the second (sequential) `record_scan` of the same atom/session is **not** a second admit — `kernel.mark_ticket_scanned` refuses `not_active` (state is already `'scanned'`), which `record_scan` maps to `result='invalid'` |
| D4 | exactly **one** `admitted`/`in` row exists for the (atom, session) pair |
| D5 | two scan rows total (`admitted` + `invalid`) — the repeat was appended, never silently dropped |
| D6 | the atom's lifecycle state moved exactly once (`scanned`) |

**Concurrency-guarantee note (per the brief's own framing).** Single-connection
pgTAP cannot drive a true race: two transactions both reading `state='active'`
before either commits. What 169 proves instead, and documents as the actual
guarantee, is two-part:
1. **Structurally (D1):** `scan_admitted_in_uq` is a real partial unique index
   on Postgres's own MVCC — under a true concurrent race, the loser's `INSERT`
   hits `unique_violation`, which `record_scan`'s exception handler maps to
   `result='duplicate'` (086:1070-1128). That path is unreachable from a single
   connection (the second call always finds `state<>'active'` first, via
   `mark_ticket_scanned`'s own row lock, and takes the `result='invalid'` arm
   instead of ever reaching the index) — but the index exists and is armed
   regardless of which arm a given interleaving takes.
2. **Sequentially (D2–D6):** whichever arm fires, the outcome invariant holds —
   never more than one `admitted`/`in` row, and the repeat is recorded, not
   dropped. This is what 169 actually asserts, since it is what a single
   connection can actually exercise.

---

## 2. Census

No pgTAP file in the suite asserts an exhaustive column set for
`kernel.signing_key` (`columns_are` is not used anywhere in
`supabase/tests/`; 147's B1 and 168's related checks are column-privilege
checks — `public_key`/`algorithm` granted, `kms_handle_ref` not — which are
unaffected by an additive column). **No census bump was needed or made.**
Migration 103 re-creates two functions (`kernel.guard_signing_key_immutable`,
`kernel.get_ticket_signing_context`) via `CREATE OR REPLACE` — the kernel
function-count assertion in `141_phase2_identity_orgs_deletion.sql` (147) is
unaffected (re-creates, not new functions). Gate-2 stays `27/70/37/26`,
matching the CI baseline in `ci.yml` — confirmed by a fresh
`rehearsal_reset.sh` run alongside this file.

---

## 3. Verification

```
scripts/rehearsal_reset.sh snatchit_rehears_c   # 118/118 migrations, gate-2 27/70/37/26
scripts/rehearsal_test.sh  snatchit_rehears_c
```

- `169_signing_key_algorithm_and_door_proofs.sql` — `plan=34 ok=34 not_ok=0 psql_err=0  PASS`
- `166_venue_obligation_excludes_held_commission.sql` — `PASS` (unedited, re-confirmed green)
- `167_recovery_venue_scope.sql` — `PASS` (unedited, re-confirmed green)
- `168_credential_signing_context_and_saleable.sql` — `PASS` (unedited, re-confirmed green)
- **`TOTAL plan=3632 ok=3628 not_ok=4 FAILURES`** — the 4 `not_ok` are exactly
  the two documented local-only deltas (`060_payments_money.sql` ×2,
  `132_replay_parity.sql` ×2); `rehearsal_test.sh`'s classifier reports
  `RESULT: pgTAP suite matches the expected local baseline.`

No migration, edge function, or `*.test.ts` file was touched. DARK/local
only — no production, no deploy, no git commit, no Supabase MCP.
