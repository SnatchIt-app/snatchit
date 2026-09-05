# M6 — MIGRATION 110 `kernel.signing_key` INSERT GUARD — SPECIFICATION, ADVERSARIAL REVIEW, REHEARSAL EVIDENCE

**Status:** IMPLEMENTED (repository) · TESTED (local rehearsal, pgTAP suite 176 + full suite) · **NOT DEPLOYED** · **NOT operationally verified**.
**Production:** UNCHANGED — ledger 124, substrate tip 109, 0 signing keys, flags dark. Migration 110 exists only as a local/rehearsal artifact.
**Owner constraints honoured:** AWS FREE (no AWS resource, key, secret, or organization); no deploy; no production apply; no data change; no activation.
PFA-18C governance wording untouched (`docs/architecture/_governance/*` not modified by this work).

Files: `supabase/migrations/110_signing_key_insert_guard.sql` · `supabase/rollbacks/110_signing_key_insert_guard_rollback.sql` ·
`supabase/tests/176_signing_key_insert_guard.sql` · harness: `supabase/tests/000_helpers.sql` (`tap.seed_core`) · census bumps in tests
141/142/143/144/148/154/156/157.

---

## 1. What the guard enforces (BEFORE INSERT, FOR EACH ROW, `kernel.guard_signing_key_insert()`)

| # | Rule | Refusal code | Class |
|---|---|---|---|
| 1 | `scope <> 'global'` | `scoped_key_parked` | PFA-18A parked (Q7 below) |
| 2 | `status <> 'active'` | `status_must_be_active` | lifecycle states are never inserted |
| 3 | `algorithm <> 'ES256'` (explicit **or** the 103 default) | `algorithm_not_es256` | ratified D2; **no override of any kind** |
| 4 | `kms_handle_ref` not `arn:aws:kms:<region>:<12 digits>:key/<uuid>` | `kms_handle_not_key_arn` | D4 |
| 5 | `public_key` contains `PRIVATE KEY` | `public_key_private_material` | C33 |
| 6 | `public_key` not exactly one `PUBLIC KEY` PEM block whose DER is the 91-byte uncompressed P-256 SPKI | `public_key_not_spki_pem` / `public_key_not_p256_uncompressed` | D3 + PFA-PT-8 pinned to key bytes |
| 7 | `pg_advisory_xact_lock(hashtext('kernel.signing_key:global_insert'))` | — | serializes global inserts |
| 8 | `key_id` already present | `duplicate_key_id` | append-only (named, ahead of the PK) |
| 9 | an `active`/`rotating` global row exists | `active_global_exists` | exactly one active global; rotation parked |
| 10 | a `revoked` global row exists, none active | `post_revoke_recovery_parked` | **fail closed** until the two-person recovery migration — **superseded by migration 111 (E4)**, which replaces this rule with the two-approval check; see `E4_MIGRATION_111_RECOVERY_SPEC_AND_REVIEW.md` |
| 11 | keyring empty and `key_id <> …b0` | `bootstrap_key_id_required` | sanctioned lineage (ruling B) |

Reads no GUC, config key, role, or env value. Zero-grant (revoked from public/anon/authenticated/service_role). The 083/103 immutable
BEFORE UPDATE guard, the partial unique indexes, `provision_signing_key`/`rotate_signing_key` (parked) and `revoke_signing_key` (106) are untouched.
Messages never interpolate the row's values.

The sanctioned §6.1 artifact (key_id `…b0`, global, ES256 explicit, full ARN, SPKI PEM, active, `not_after NULL`) passes all eleven rules
(suite 176 C1–C4; C4 re-derives the D5 fingerprint from the stored PEM and matches openssl's digest over the DER).

## 2. Q7 — scoped rows: rejected outright while provision/rotate are parked (no future-safe predicate)

Justification from the actual schema and resolver, not policy prose:
- The only sanctioned writers of scoped keys, `kernel.provision_signing_key` / `rotate_signing_key` (083:375-393), raise
  `dual_control_unavailable` **before any write** — there is nothing for a runtime predicate to distinguish.
- The mint resolver (093:4954-4966) is most-specific-first (`per_event` > `per_venue` > `global`, active + in-window). A scoped row with a
  valid window therefore **shadows the global trust root at the very next mint** for that event/venue — issuance silently re-pointed at key
  material nobody ceremonied. The monitor (099, §9.3 ADV-7 `scoped_keys`) already treats any scoped row as an alert, i.e. as a fault, not a
  feature.
- A "future-safe predicate" (config flag, GUC, role test) would itself be a runtime bypass — precisely what item 4 forbids for algorithm and
  what the threat model (bare superuser INSERT) forbids in general.
Therefore rule 1 is absolute. When PFA-18A is un-parked, **that migration** re-creates provision/rotate with real bodies and amends this
guard in the same reviewed change (e.g. permitting scoped inserts only from those definer bodies). Reviewed migration, never a switch.

## 3. Recovery conflict analysis (item 6) — no conflict; the guard is the required fail-closed

Governance (`PFA_18C_REMEDIATION_AND_FINAL_RATIFICATION.md`, P1-REBOOTSTRAP-FAILOPEN): post-revoke recovery must be two-person and must
**fail closed** when no second qualified operator exists; today the only path is a bare superuser INSERT with neither property.
Rule 10 is exactly that fail-closed. It encodes **no** two-person check (no ratified mechanism exists to check — inventing one would be a
bypass); it parks the path with a code naming the un-park contract: the E4 migration that ships the gated two-person recovery artifact
(e.g. two distinct `platform_admin`+aal2 approvals recorded in a `kernel.ceremony_approval` table within a window) **replaces rule 10** with
"permitted iff that approval record exists for `NEW.key_id`". A structurally valid replacement row after a revoke is refused even for a
superuser (176 F2) — that is the requirement, not a conflict with it. Rule 11 makes the first-ever global row the ruling-B `…b0` the §6.1
artifact writes; every later global row exists only through rule 10's future un-park, which is what "sanctioned bootstrap key_id lineage" means.
**No PFA-18C wording was changed.** The interim consequence stands as already stated in governance: until E4 ships, a revoke leaves zero
active keys and issuance fails closed (`no_active_signing_key`) — 176 F5 asserts exactly that state.

## 4. Transaction and concurrency behaviour (item 8) — evidence

| Scenario | Mechanism | Evidence |
|---|---|---|
| two concurrent global inserts | rule 7 advisory xact lock, then existence checks under a fresh READ COMMITTED snapshot | **probe:** session A inserted `…b0` and held the transaction 4 s; session B (started 1 s later) blocked on the lock ~3 s and, after A's COMMIT, was refused `active_global_exists` — a named refusal, not a unique-violation race |
| unique index as defense in depth | `signing_key_active_global_uq` (083) | **probe:** with the trigger disabled inside a rolled-back transaction, a second active global raised `duplicate key value violates unique constraint "signing_key_active_global_uq"` |
| revoked global + replacement | rule 10 | 176 F1–F5: revoke permitted by the UPDATE guard; valid replacement refused `post_revoke_recovery_parked`; revoked key_id re-use refused `duplicate_key_id`; revoked is terminal; zero active remain |
| duplicate key_id | rule 8 (named) then PK | 176 D2 / F3 |
| active-global uniqueness | rule 9 (named) then unique index | 176 D1 |
| refusal ⇒ rollback | BEFORE ROW `RAISE` aborts the statement/transaction; nothing partial | 176 B23 (0 rows after 22 refused inserts) |
| rollback + replay of the migration itself | rollback file drops trigger+function; 110 uses `create or replace` + `drop trigger if exists` | **probe:** rollback → guard 0 / fn 0 → rollback again (idempotent, NOTICE only) → 110 applied twice → guard 1, enabled `O`, kernel fns 150 → suite 176 51/51; 176 G1–G3 replay the same on a savepoint |

## 5. Rehearsal harness reconciliation (the one real conflict found, and how it was resolved)

22 existing suites (143–175) seed `kernel.signing_key` rows directly as superuser fixtures with placeholder values and mostly `per_event`
scope — every one of which rule 1/4/6 refuses by design. Resolution: `tap.seed_core()` (rehearsal-only `tap` schema, `000_helpers.sql`)
now `ALTER TABLE kernel.signing_key DISABLE TRIGGER tg_signing_key_insert_guard` for the duration of the calling suite's transaction (DDL is
transactional; the suite's ROLLBACK restores it). This is Postgres-native superuser administration in the test harness, **not** a bypass
in the guard's code (which reads nothing that could disable it). Suite 176 does **not** call `seed_core` and runs against the live guard; its
A4 asserts the guard ships ENABLED. Alternatives rejected: rewriting 40 fixture inserts to global ES256 rows (would erase scope-resolution
coverage); `session_replication_role=replica` (disables every trigger, including the ones other suites test).

## 6. Adversarial review (self, pre-commit)

- **Bypass surface:** none in code; superuser can `DISABLE TRIGGER`/drop the trigger — same property as the existing immutable guard; the
  threat model is the honest bare INSERT (fail closed) and the malicious one is DETECTABLE (CloudTrail/monitor), consistent with PFA-18C.
- **Check order:** value-shape rules (1–6) precede existence rules (8–11) so a refused row never depends on keyring state, and the advisory
  lock is taken only after cheap validation (no lock held while rejecting garbage).
- **PEM parsing:** exactly one block (176 B16 refuses two concatenated blocks); base64-charset body but undecodable ⇒ named refusal (B17);
  non-charset body ⇒ `public_key_not_spki_pem` (B17b); Ed25519 (B18) and compressed P-256 (B19) refused under ES256; `PRIVATE KEY` anywhere
  refused first (B20/B21). PG's base64 decoder ignores line breaks (verified: 91 bytes from the wrapped PEM).
- **ARN:** region grammar `[a-z]{2}(-[a-z]+)+-[0-9]`, 12-digit account, key UUID; alias/bare-id/11-digit/uppercase-region/non-UUID refused (B7–B11).
- **Not enforced (deliberately, documented):** `not_after IS NULL` (D6 chose NULL for the bootstrap, but the monitor supports
  `signing.expected_max_not_after`, so a future ceremony may legitimately set one); `not_before <= now()` (a future-dated key is inert, not
  dangerous); D5 fingerprint equality with `signing.expected_key_fingerprint` (that config is written AFTER the row, §9.3 arming order).
- **Residual:** rule 10 is fail-closed with no recovery until E4 — an availability trade the governance already accepted in writing.

## 7. Evidence (2026-09-05, local rehearsal, PostgreSQL 17.11 Homebrew, `scripts/rehearsal_reset.sh` + `rehearsal_test.sh`)

| Check | Result |
|---|---|
| fresh replay (drop + re-apply every migration, LC_ALL=C order) | applied through 110; no migration skipped; Gate-2 census 27/70/37/26 unchanged |
| post-replay state | guard present, `tgenabled='O'`, kernel functions 150, keyring empty |
| pgTAP suite 176 | **51/51** |
| full pgTAP | **plan 3746 · ok 3742 · not_ok 4** — the only non-ok assertions are the 4 documented local-only deltas (060 ×2, 132 ×2); zero regressions |
| concurrency probe / unique-index probe / rollback+replay probe | as in §4 |
| `npx vitest run` | 729/729 |
| `npm run typecheck` | clean |
| `npm run lint` | 0 errors (45 pre-existing warnings, unrelated) |
| G-4 assembled-migration integrity | PASS (110 is not an assembled migration) |
| `deno check` | **OUTSTANDING** — not installed on the engineering host |

## 8. Status matrix

| Item | Implemented | Tested | Deployed | Operationally verified |
|---|---|---|---|---|
| migration 110 guard + trigger | ✔ | ✔ (176 + full suite + probes) | **✘ NOT DEPLOYED** | ✘ |
| rollback file | ✔ | ✔ (file-level + savepoint) | n/a | ✘ |
| census updates | ✔ (rehearsal package only) | ✔ | n/a | n/a |
| production ledger | **unchanged (124)** | — | — | — |

**Tested commit:** `e181c3b` on `feature/venue-native-and-product-v2`.

## 9. What applying 110 to production would require (not requested, not done)

A separate owner authorization; the usual `supabase db push --linked --include-all` dry-run showing exactly `110`; ledger 124 → 125; then the
production census re-check (kernel 150). It must be applied **before** the DB bootstrap if the owner wants the §6.1 INSERT itself to run under
the guard (recommended: the guard is the P1-ALGO-DEFAULT closure), and in any case **before issuance** (M6's ratified position).
