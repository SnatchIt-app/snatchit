# G3 — SIGNING PATH REHEARSAL AND ADVERSARIAL REVIEW

Evidence for `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md`. Closes the rehearsal half of
gap-matrix row **G3** (`PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md:159`) and demonstrates the
mechanism ruling B ratified (`PRIMARY_TICKETING_OWNER_RATIFICATION.md:232-249`).

---

## 0. WHAT WAS AND WAS NOT DONE

**NOT done — no production anything.** No production KMS key was created. No production KMS
API was called. No cloud KMS mutation of any kind was performed. No production or remote
database was touched. No production KMS identifier was invented, and none appears in this
document or in the runbook. No commit was made. Migrations 000–092 were not modified;
`093_parts/40_config_privacy_freeze.sql` was **not modified** — see §7.

**Done — a full local rehearsal on non-production material.**

| Item | Value |
|---|---|
| Database | `snatchit_rehears_signing`, built by `./scripts/rehearsal_reset.sh` |
| Chain applied | **108/108** migrations, canonical order, zero errors. `GATE-2 tables=27 functions=70 policies=37 triggers=24` — matches the CI baseline exactly. |
| Server | loopback PostgreSQL 17, no Supabase platform roles (the harness refuses anything else) |
| Test key material | Ed25519 and ECDSA-P256 pairs generated **at runtime** with `openssl`, in `$TMPDIR/.../scratchpad/rehearsal-keys/` — **outside the repository**, `chmod 600`, never committed, never pasted into any file that lands in git |
| Non-production markers | key files named `NONPROD_*`; every `kms_handle_ref` written is `local-rehearsal:NON-PRODUCTION:<n>`, which is not a valid identifier for any cloud KMS |
| pgTAP fixtures | `supabase/tests/000_helpers.sql` (`tap.seed_core`), plus the org→venue→event→session→ticket_type→batch chain copied from suite 147 |

### Reproduction

The three artifacts exercised are reproduced verbatim in the runbook: the bootstrap SQL
(§6.1), the rotation SQL (§12), and the rollback SQL (§10). The fixture and the key
generation are three commands:

```bash
./scripts/rehearsal_reset.sh snatchit_rehears_signing
psql -d snatchit_rehears_signing -U postgres -f supabase/tests/000_helpers.sql
umask 077 && openssl genpkey -algorithm ED25519 -out NONPROD_k1.pem   # outside the repo
```

---

## 1. WHAT THE IMPLEMENTATION EXPECTS — the inspection result

**The implementation is provider-agnostic and format-agnostic. The runbook has to supply
everything.**

| Question | Answer, from code |
|---|---|
| Which KMS? | **None is named in any executable byte.** `kms_handle_ref text not null` (`083:56`) — no `CHECK`, no regex, no length. The only provider statement is architectural: `EDGE_SPEC:1291-1292` allows *AWS KMS asymmetric, GCP KMS, or CloudHSM*; the env var `KMS_SIGNER_ROLE_ARN` (`:1293-1295`) is AWS-shaped, which is a hint, not a decision. → Runbook §1.2 D1/D4. |
| Which algorithm? | Nothing in SQL. `EDGE_SPEC:1273-1274`: **Ed25519 preferred, ECDSA-P256 acceptable.** → Runbook §1.2 D2, which also flags that Ed25519 is not offered for asymmetric signing by every provider and must be confirmed against the provider's current key-spec list before it is chosen. |
| `public_key` format? | Unconstrained `text` (`083:55`). → Runbook D3 pins SPKI PEM. |
| Fingerprint? | **Does not exist anywhere in the codebase.** → Runbook D5 defines it: SHA-256 over the DER SPKI, lowercase hex. |
| Is the pair validated? | **No.** `guard_signing_key_immutable` is `BEFORE UPDATE` only (`083:104-105`); there is no insert-time trigger. The mint (`083:514-530`) checks only `status='active'`, `not_before <= now()`, `not_after` unset-or-future, and scope coherence. A garbage `public_key` passes every check. |
| Scope resolution | Most-specific-first: `order by case k.scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end limit 1` — `085:1948-1960`, repeated at `086:1196-1201`. **`per_event` outranks `per_venue` outranks `global`.** Rehearsed in §3 item 2 and §5 ADV-7. |
| Verification paths | All **off-database**. `venue.get_door_manifest` (M2) carries `signing_key_id` and never `public_key` (`086:860-866`, PFA-24); M1 is the `kernel.signing_key` public projection, granted to `authenticated` only, never `anon` (`083:114-124`, PFA-16). `supabase/functions/` contains **no** `credential-sign` — verified by listing. |
| Lifecycle RPCs | All six parked, zero mutation: `provision_signing_key`, `rotate_signing_key` (`083:375-393`), the three `pass_type_cert` verbs (`083:395-425`), `revoke_signing_key` (`086:714-721`). |

**Consequence for the runbook:** it must pin provider, algorithm, `public_key` wire format,
handle syntax *including version pinning*, the fingerprint function, and the canonical
signed bytes — because nothing in the database will do any of it. Runbook §1.2 does this as
seven recorded decisions D1–D7.

---

## 2. REHEARSAL RESULTS — the twelve required items

All twelve **PASS**. Each row lists the observed output.

| # | Item | Verdict | Observed |
|---|---|---|---|
| 1 | **Bootstrap row creation** | PASS | Three `NOTICE` lines then `COMMIT`; `count(*)` 0 → 1. Row: `00000000-…-b0 \| global \| active`, `not_after=null`. |
| 2 | **Active-key resolution** | PASS | The `085:1948-1960` resolver returned `resolved key_id = 00000000-…-b0 scope=global`. |
| 3 | **Ticket mint** | PASS | `{"status":"ok","atom_ids":["f05aacfb…","a53310f5…"]}`; both atoms `state=active cv=0 signing_key_id=…b0`; `venue.inventory_batch.sold = 2`. |
| 4 | **Signature production** | PASS | 64-byte Ed25519 signature over the canonical payload built **from the DB row** (`{atom_id, session_id, credential_version, key_id, issued_at, exp}`). |
| 5 | **Signature verification** | PASS | Verified against the PEM read **back out of `kernel.signing_key.public_key`** — not against the local file. `Signature Verified Successfully`. |
| 6 | **Inactive key rejected** | PASS | Mint pinned to the now-`rotating` key: `precondition_failed: no_active_signing_key — an active signing key must resolve for the event scope before any atom is minted`. |
| 7 | **Wrong key rejected** | PASS | Same signature against a different key's PEM: `Signature Verification Failure`. One-character payload tamper: `Signature Verification Failure`. |
| 8 | **Rotation preserves OLD-ticket verification** | PASS | Post-rotation the pre-rotation signature still verified against the retired key's retained `public_key`, and failed against the new key's. Atoms 1–2 still pin `…b0`; census confirmed **0 atoms re-pinned**. |
| 9 | **A second key serves future tickets** | PASS | Resolver returned `…b1`; a new mint drew and atom 3 pins `…b1`. A signature by the new key verified against `…b1` and failed against `…b0`. |
| 10 | **Bootstrap uniqueness enforced** | PASS | Second active global row: `duplicate key value violates unique constraint "signing_key_active_global_uq"`. Replay of the ceremony artifact: `CEREMONY ABORT: kernel.signing_key already holds 1 row(s) — bootstrap is a once-only act`, `count(*)` unchanged. |
| 11 | **Immutability enforced** | PASS | `UPDATE public_key`, `UPDATE kms_handle_ref`, and `UPDATE scope/event_id` each → `append_only: signing_key identity/target/public_key/kms_handle is immutable after creation`. |
| 12 | **Deletion blocked once referenced** | PASS | `DELETE` → `update or delete on table "signing_key" violates foreign key constraint "fk_tickets_signing_key" on table "tickets"`. |

### Gates on the ceremony artifact itself (all rehearsed)

| Input | Outcome | `count(*)` after |
|---|---|---|
| PEM of key 1 + fingerprint of key 2 | `CEREMONY ABORT: fingerprint mismatch — computed c0a79cda…, expected 628fb906…` | 0 |
| A **private** key PEM pasted by mistake | `CEREMONY ABORT: PUBLIC_KEY_PEM is not an SPKI PEM public-key block` | 0 |
| The literal template placeholder `<<< CEREMONY OUTPUT: the opaque KMS handle/ARN >>>` as the handle | `CEREMONY ABORT: KMS_HANDLE_REF looks like a placeholder or key material` | 0 |
| Matching PEM + fingerprint + a real-shaped handle | 3 × `NOTICE` + `COMMIT` | 1 |
| Replay of the same command | `CEREMONY ABORT: … once-only act` | 1 (unchanged) |

Rotation artifact: re-registering the outgoing key → `ROTATION ABORT: the new public key is
byte-identical to the outgoing one — no rotation occurred`. Genuine rotation →
`ROTATION PRE-FLIGHT PASSED` + `ROTATION POST-CHECK PASSED — new key active, old key
retained rotating, 0 atoms re-pinned` + `COMMIT`.

### What was NOT reachable without a real KMS — stated, not faked

1. **A real `KMS.sign` call.** Steps 4, 5, 8 and 9 used a locally generated private key as a
   stand-in. What that *does* prove is the whole DB-facing contract: the payload is built
   from the real row, the verify key is read back out of the real column, and rotation
   preserves old-credential verification. What it *cannot* prove is that a specific cloud
   handle signs with the key whose public half is exported. That gap is exactly ADV-4, and
   the runbook closes it with the §5.3 binding proof — rehearsed in both directions here
   with the local key acting as the KMS.
2. **Provider-specific handle syntax.** No ARN or GCP resource name was constructed. Every
   handle written was `local-rehearsal:NON-PRODUCTION:<n>`.
3. **The `credential-sign` edge and door verification.** Neither exists
   (`supabase/functions/` has no `credential-sign`; the 086 rail and M1 are unbuilt), so
   signature verification could only be rehearsed off-database — which is where it happens
   in production too (`EDGE_SPEC:405-407`).
4. **KMS IAM two-person enforcement.** That is a cloud-provider control. It was not
   exercised and cannot be exercised locally; §5 ADV-1/ADV-2 record the consequence.
5. **Vault-backed secret paths.** `vault.decrypted_secrets` is an empty stand-in table in
   this harness (`R3_rehearsal_harness.md:152`), so no secret-gated branch runs. None is on
   the signing path.

### Final rehearsal state

```
KEY  00000000-0000-0000-0000-0000000000b0 | global | rotating | local-rehearsal:NON-PRODUCTION:k1 | fpr=c0a79cda…
KEY  00000000-0000-0000-0000-0000000000b1 | global | active   | local-rehearsal:NON-PRODUCTION:k2 | fpr=628fb906…
ATOM 1 f05aacfb-… pins …b0      ATOM 2 a53310f5-… pins …b0      ATOM 3 b2af948f-… pins …b1
```

*(The fingerprints above are of throwaway Ed25519 keys generated for this rehearsal and
deleted with the scratchpad. They are not secrets and they are not production values.)*

---

## 3. THE CANONICAL PAYLOAD USED

Built directly from `kernel.tickets`, matching `EDGE_SPEC:1276-1277`:

```
{"exp": "…", "key_id": "<tickets.signing_key_id>", "atom_id": "<ticket_atom_id>",
 "issued_at": "…", "session_id": "<event_session_id>", "credential_version": 0}
```

**Finding for whoever builds `credential-sign`:** the field *set* is specified but the byte
*encoding* is not. Verification is byte-exact — the rehearsal confirmed that changing
`"credential_version": 0` to `9` makes an otherwise-valid signature fail. The signer and the
verifier must therefore share one frozen canonical encoding, chosen and recorded **before**
the first credential is issued. Carried into runbook §8.

---

## 4. ROLE-BOUNDARY CENSUS (measured, not read off the source)

```
kernel.signing_key — table privileges:  postgres only (SELECT/INSERT/UPDATE/DELETE/…)
kernel.signing_key — column privileges: authenticated SELECT on
    key_id, scope, event_id, venue_id, public_key, status, not_before, not_after
    (kms_handle_ref, created_at, updated_at are NOT granted)
service_role: rolbypassrls = true, and ZERO privileges on kernel.signing_key
anon:        no USAGE on schema kernel
```

Two consequences worth stating plainly:

- **`service_role` bypasses RLS and still cannot read, write, or create a signing key.**
  RLS bypass is worthless without a grant. A leaked service-role key can mint tickets under
  the honest key (it holds `EXECUTE` on `issue_ticket_atoms` by design) but cannot create,
  alter, or shadow a signing identity.
- **The projection is genuinely column-fenced.** `select created_at from kernel.signing_key`
  as an authenticated admin returns `permission denied for table signing_key`, while
  `select key_id, scope, status, public_key` succeeds. `kms_handle_ref` is on the wrong side
  of that fence.

---

## 5. ADVERSARIAL RESULTS

Each attempt was executed against the replayed database. "PROVED" means the listed outcome
was observed, not inferred.

### ADV-1 — Person A completes the ceremony alone · **NOT PREVENTED BY THE DATABASE (PROVED)**
The bootstrap transaction was executed by a single `postgres` session with no second party
present, and it committed. Postgres enforces no two-person rule and cannot.
**Compensating control:** Person A holds no production DB credential (runbook §2 A5), and
the transaction aborts unless the fingerprint — which A does not compute — matches the bytes
being written. The dual control lives in IAM, which is a plane where a second principal
genuinely exists (`B_signing_dual_control.md:342-344`). Detection: runbook §9.3.

### ADV-2 — Person B completes the ceremony alone · **NOT PREVENTED BY THE DATABASE (PROVED)**
Same mechanism. B could register a key created elsewhere.
**Compensating control:** B holds no `kms:CreateKey`, and the provider's own audit trail
(CloudTrail / Cloud Audit Logs) is outside both operators' control and will show no
`CreateKey` under the production principal. Runbook §9.1 makes archiving it mandatory.

### ADV-3 — An application admin swaps the public key · **PREVENTED (PROVED)**
As `authenticated` with `platform_admin` in the allowlist (`kernel.is_platform(...)` = true):

```
INSERT a shadow per_event key      → permission denied for table signing_key
UPDATE public_key                  → permission denied for table signing_key
DELETE the key                     → permission denied for table signing_key
UPDATE status  (silent disable)    → permission denied for table signing_key
UPDATE not_after (window)          → permission denied for table signing_key
SELECT kms_handle_ref              → permission denied for table signing_key
provision_signing_key(...)         → precondition_failed: dual_control_unavailable
rotate_signing_key(...)            → precondition_failed: dual_control_unavailable
revoke_signing_key(...)            → precondition_failed: dual_control_unavailable
issue_ticket_atoms(...)            → permission denied for function issue_ticket_atoms
SELECT key_id, scope, status, public_key  → ALLOWED (PFA-16, by design)
```

### ADV-4 — The KMS key id points at different material · **NOT PREVENTABLE IN THE DB (PROVED)**
Nothing validates the pair at `INSERT` — no insert-time trigger exists, and the guard is
`BEFORE UPDATE` only. A row whose handle names key X and whose `public_key` is key Y's is
accepted, mints atoms, and can then be neither corrected nor deleted.
**Compensating control (rehearsed):** the runbook §5.3 binding proof.

```
A) sign via handle k2, verify with the k2 public key   → Signature Verified Successfully
B) handle points at k2, exported public key is k1      → Signature Verification Failure
C) the key actually stored in the DB row verifies it   → Signature Verified Successfully
```

This is the **only** detector in the entire system, and it works only before the write.

### ADV-5 — The DB public key diverges from the KMS key · **PARTIALLY PREVENTED (PROVED)**
The fingerprint gate rejects any PEM that does not hash to the independently-computed
expected value:
`CEREMONY ABORT: fingerprint mismatch — computed c0a79cda…, expected 628fb906…`, `count(*)` 0.
It cannot catch a *consistently wrong* pair — that is ADV-4. Runbook D4 additionally
requires a version-pinned GCP handle, closing the "right key, wrong version" case: GCP
`cryptoKeys/<K>` without `cryptoKeyVersions/<V>` would silently change signer on the
provider's own rotation schedule while `public_key` stays immutable.

### ADV-6 — A stale fingerprint is accepted · **PREVENTED (PROVED)**
See ADV-5's abort. The gate runs inside the same transaction that writes, so there is no
window between checking and writing.

### ADV-7 — The same key registered twice · **SPLIT VERDICT (both PROVED)**
*As a second active global row:* prevented —
`duplicate key value violates unique constraint "signing_key_active_global_uq"`.
*As a `per_event` shadow carrying the identical `public_key` and `kms_handle_ref`:* **NOT
PREVENTED.** The insert succeeded, and the resolver flipped immediately:

```
rows now: 3
resolver for the event now returns: 00000000-…-c0 (scope per_event)
```

This is threat T1 (`B_signing_dual_control.md:239-247`): the partial unique indexes are
per-target, so a `per_event` row never collides with the `global` row, and `per_event`
outranks it. **Compensating controls:** no client role can insert at all (ADV-3), so this
requires superuser; the runbook §9.3 monitor treats **any** `per_event`/`per_venue` row as a
page-the-owner event; and the rotation artifact refuses a `kms_handle_ref` already
registered on another row.

### ADV-8 — Unauthorized activation · **PREVENTED for every client role (PROVED); NOT PREVENTED for a superuser**
`authenticated`, `platform_admin` and `service_role` all → `permission denied`. A
`postgres`/superuser session can insert an active key at will — that is the deploy path
itself. Compensating control: §9.3's `active_global` count and bootstrap-fingerprint
invariants, plus the no-direct-SQL policy Ruling C already imposes.

### ADV-9 — An old key silently disabled · **PREVENTED for client roles (PROVED); NOT PREVENTED for a superuser (PROVED)**
Client roles: `permission denied`. Superuser: two live gaps, both confirmed by execution.

1. **`not_after` is mutable.** It is deliberately absent from the guard's immutability list
   (`083:88-93`). `update … set not_after = now() + interval '1 day'` returned `UPDATE 1`.
   Pulling `not_after` into the past silently ends issuance and, once door verification
   exists, silently ends verification of every credential pinned to that key.
2. **`rotating → revoked` is a legal forward transition** (`083:96-99`) and `revoked` is
   terminal.

No in-band control exists for either. **Compensating control: detection only** — the §9.3
monitor watches `max_not_after` and the per-key status. Recorded in runbook §7.6 as a
live gap, not fixed.

### ADV-10 — Malicious rotation · **PREVENTED for client roles (PROVED); artifact-level defences PROVED**
Client roles cannot rotate at all (`dual_control_unavailable`, `permission denied`). Against
the runbook's rotation artifact: byte-identical key → `ROTATION ABORT`; already-registered
handle → `ROTATION ABORT`; non-`global` or non-`active` outgoing key → `ROTATION ABORT`; any
atom re-pinned → `ROTATION ABORT`. A superuser who declines to use the artifact is not
prevented; the §9.3 fingerprint invariant surfaces the result.

### ADV-11 — A compromised KMS key · **CONTAINED, NOT PREVENTED (PROVED)**
`kernel.revoke_signing_key` is inert:
`precondition_failed: dual_control_unavailable … no key state changes and no episode is
force-closed`. The in-band control that *does* work was rehearsed:

```
flag now = false
kernel.issue_ticket_atoms(...) → precondition_failed: feature_disabled
```

and a **single** `platform_admin` can flip it through the RPC in both directions —
`catalog.set_platform_config('feature.native_issuance_enabled','false'::jsonb,…)` returned
`{"status":"ok"}`. `feature.%` is not in the dual-control prefix set (`078:1145-1147`).
That asymmetry is right for a compromise response (stopping the bleeding must not need a
quorum) and is a standing risk in the other direction (one admin can re-enable issuance).
Real revocation is a KMS/IAM act. The DB-side residual — revocation does not force-close
open door episodes — is PFA-18A's open forward obligation (`086:703-713`).

### ADV-12 — `service_role` bypass · **PREVENTED (PROVED)**

```
current_user=service_role  bypassrls=true
SELECT count(*) from kernel.signing_key → permission denied for table signing_key
INSERT …                               → permission denied for table signing_key
UPDATE …                               → permission denied for table signing_key
issue_ticket_atoms(…)                  → ok        (granted by design, 083:876-886)
```

### ADV-13 — CI secret leakage · **NO LEAK FOUND (PROVED by inspection); ONE HYGIENE GAP**
`grep -rniE 'kms|KMS_SIGNER' .github/workflows/` returns two prose comments and nothing
executable. No workflow touches key material; the ceremony runs no CI step. Test fixtures
use the literal non-keys `'PUBKEY'` / `'kms-handle-opaque'` (suite 147), which is why 147's
assertion that the production-shaped DB holds **zero** signing keys is load-bearing.
**Gap:** `.gitignore` covers `*.pem`, `*.key`, `*.p8` but **not** `*.der`, `*.sig`, `*.bin` —
and the ceremony produces `.der` and `.sig` files. Mitigation adopted in runbook §3: every
`LOCAL` step runs in a directory that is checked, at the start, not to be a git working tree.

### ADV-14 — Logs leaking KMS references or key material · **KEY MATERIAL: IMPOSSIBLE. HANDLE: A REAL CHANNEL (PROVED as a mechanism)**
*Key material:* the private key never reaches the database or any application process, so no
log can contain it. Confirmed structurally, not just by policy: no column, no RPC return, no
env var holds it.
*Handle:* `grep -rn kms_handle_ref` over `supabase/migrations/`, `supabase/functions/`,
`src/`, `packages/`, `app/` finds **no** write into `kernel.admin_audit`, no `notify` event
payload, no RPC return value, and no edge-function reference — outside 083's own DDL and
093's commented template. **But** `provision_signing_key` and `rotate_signing_key` take the
handle as a `text` parameter, and this cluster reports `log_min_error_statement = error`,
which is the Postgres default: a failing call logs its own statement text. Since those
bodies raise immediately, passing a real handle to them writes it to the server log for zero
benefit. Countermeasures adopted: runbook §0 rule 4 (never pass the handle to a parked RPC),
§6.2 (the ceremony passes values as `psql` variables from files, and forbids the Supabase SQL
editor), and §7.1 (verification never prints the handle). Residual exposure is bounded by
`EDGE_SPEC:1293-1297` — the handle *"is a handle, so even its leak yields no signing ability
without KMS IAM."*

### Summary

| Attack | Verdict |
|---|---|
| ADV-1 Person A alone | NOT PREVENTED by DB — IAM + fingerprint gate + audit trail |
| ADV-2 Person B alone | NOT PREVENTED by DB — no `CreateKey` + provider audit trail |
| ADV-3 App admin swaps the public key | **PREVENTED** |
| ADV-4 Handle points elsewhere | NOT PREVENTABLE in DB — §5.3 binding proof is the only detector |
| ADV-5 DB key diverges from KMS key | PARTIALLY PREVENTED — fingerprint gate + version-pinned handle |
| ADV-6 Stale fingerprint | **PREVENTED** |
| ADV-7 Same key registered twice | PREVENTED as a second global; **NOT PREVENTED** as a `per_event` shadow |
| ADV-8 Unauthorized activation | **PREVENTED** for all client roles; not for a superuser |
| ADV-9 Old key silently disabled | **PREVENTED** for client roles; **NOT PREVENTED** for a superuser (`not_after` mutable) |
| ADV-10 Malicious rotation | **PREVENTED** for client roles; artifact refuses every dishonest shape |
| ADV-11 Compromised KMS key | CONTAINED via the issuance flag; in-band revocation does not exist |
| ADV-12 `service_role` bypass | **PREVENTED** |
| ADV-13 CI secret leakage | NO LEAK; one `.gitignore` hygiene gap, mitigated procedurally |
| ADV-14 Log leakage | Key material impossible; handle exposure real but bounded and avoidable |

**The three irreducible residuals:** (1) Postgres cannot verify that a key is real — only
the ceremony's binding proof can, and only before the write; (2) nothing constrains a
database superuser; (3) in-band revocation does not exist while PFA-18A is unclosed.

---

## 6. THE IRREVERSIBLE POINT

**The first successful `kernel.issue_ticket_atoms` call** — in production, the first
`venue.finalize_primary_order` on a paid order. Not the ceremony; not the flag flip.

Four doors close simultaneously, all four rehearsed:

1. `DELETE` → `violates foreign key constraint "fk_tickets_signing_key"` (`084:52-55`).
2. `UPDATE public_key` / `kms_handle_ref` / scope / target → `append_only: … is immutable
   after creation` (`083:84-102`), for superusers too.
3. Atoms are pinned permanently; rotation does not re-pin (0 atoms moved), and no re-pinning
   resolver exists (`088:606`, E-97).
4. The mint validates only status/window/scope, so a wrong key mints unverifiable atoms and
   doors 1–3 make that permanent.

The owner has accepted this on the record
(`PRIMARY_TICKETING_FINAL_OWNER_RULINGS.md:711-717`). Until that first atom, the runbook §10
rollback applies and was rehearsed to be structurally unavailable afterwards.

---

## 7. FILES

**Written:**
- `docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` — the runbook.
- `docs/phase2/_impl/G3_signing_rehearsal.md` — this file.

**Not modified:** migrations 000–093, including
`docs/phase2/_impl/093_parts/40_config_privacy_freeze.sql` and
`supabase/migrations/093_primary_ticketing.sql`.

**Why slice 40 needed no change.** ITEM 2 (`40_config_privacy_freeze.sql:341-465`) is
already correct and complete: it determines `scope='global'`, `key_id=…b0`,
`status='active'`, `not_before <= now()`, `not_after` NULL, and it leaves the `INSERT`
commented out on purpose. The rehearsal writes exactly that row and confirms it resolves.
The ceremony deliberately supplies the row as a **separate, single-purpose, parameterised
artifact executed at ceremony time** rather than by uncommenting the template, for three
reasons the rehearsal makes concrete:

1. **The template cannot carry the gates.** The bootstrap must recompute the fingerprint
   from the bytes it is about to write and abort on mismatch. That check consumes a value
   that does not exist when the migration is authored; a migration file would have to
   hard-code either the key or the fingerprint.
2. **A migration replays.** `db push --include-all` re-applies files. `on conflict (key_id)
   do nothing` would silently no-op, hiding a divergence; the ceremony artifact instead
   *aborts loudly* on a second run (`… once-only act`), which is the behaviour you want for
   a trust root.
3. **Uncommenting means the real public key and handle are committed to git.** The public
   key is harmless there; the handle is `restricted`-class and the diff review surface for a
   trust-root change should be a signed evidence pack, not a merge.

**One open item this leaves.** `supabase/rollbacks/` has no `093_*` file. Runbook §10
supplies the rollback SQL for the signing row specifically; whether the wider 093 rollback
file is authored is out of scope here and worth tracking separately.

**Deleted after the rehearsal:** every `NONPROD_*.pem` / `.der`, every signature, and every
challenge file, all of which lived outside the repository for their whole lifetime.
