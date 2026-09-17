# E4 — MIGRATION 111 GATED TWO-PERSON POST-REVOKE RE-BOOTSTRAP — SPECIFICATION, ADVERSARIAL REVIEW, REHEARSAL EVIDENCE

**Status:** IMPLEMENTED (repository) · TESTED (local rehearsal: pgTAP suite 177 + 176 + full suite + probes) · **NOT DEPLOYED** · **NOT operationally verified**.
**Production:** UNCHANGED — ledger 124, substrate tip 109, 0 signing keys, flags dark. Migrations 110 and 111 exist only as local/rehearsal artifacts.
**Owner constraints honoured:** AWS FREE; no AWS resource, KMS key, secret, organization, deployment, activation, or money movement. No owner ratification text changed.

Files: `supabase/migrations/111_signing_key_recovery_two_person.sql` · `supabase/rollbacks/111_signing_key_recovery_two_person_rollback.sql`
(generated; embeds 110's guard body verbatim) · `supabase/tests/177_signing_key_recovery_two_person.sql` · suite 176 F2 updated · census bumps
(141/142/143/144/147/148/149/154/156/157). Predecessor: `docs/phase2/M6_MIGRATION_110_SPEC_AND_REVIEW.md` (rule 10 of 110 is superseded by 111).

---

## 1. What 111 adds

| Object | Purpose | Access |
|---|---|---|
| `kernel.signing_key_recovery_approval` | durable, **append-only** record of approvals keyed by (key_id, D5 fingerprint), with approver identity, `aal2`, session id (evidence), reason, command key, `approved_at`, `expires_at ≤ approved_at + 30 min` | RLS on, **zero policies, zero grants** to anon/authenticated/service_role; `raise_append_only` on UPDATE/DELETE; only the SECURITY DEFINER functions (owner) or a superuser touch it |
| `kernel.signing_key_p256_pem_fingerprint(text)` | pure helper: D5 fingerprint iff exactly one uncompressed-P-256 SPKI PEM block, else NULL; never raises | zero-grant; SECURITY DEFINER + empty search_path (066 invariant) |
| `kernel.approve_signing_key_recovery(key_id, fingerprint, reason, command_key)` | records ONE approval; platform_admin + aal2 (106 idiom); preconditions; distinct-identity rule; 30-min window; idempotent replay; audit row | authenticated-callable definer (authz inside); anon/service_role revoked |
| `kernel.execute_signing_key_recovery(key_id, pem, kms_arn, reason, command_key)` | inserts the recovery key (algorithm **ES256 explicit**, scope global, active, not_after NULL) iff ≥2 distinct unexpired approvals match key_id + fingerprint of the supplied PEM, caller is one of the approvers, zero active + exactly one revoked; audit row; idempotent replay | same |
| `kernel.guard_signing_key_insert()` (re-created) | rules 1–9 and 11 unchanged from 110; **rule 10** now: a revoked global exists ⇒ exactly one revoked (else `recovery_lineage_exceeded`) AND ≥2 distinct `aal2` approvals for `NEW.key_id` + `sha256(DER of NEW.public_key)` unexpired (else `post_revoke_recovery_unapproved`) | zero-grant trigger fn |

Why a dedicated table rather than `kernel.approval_request` (the repository's established dual-control substrate): its `action`/`subject_kind` CHECK
constraints are frozen money vocabularies (077:267-297); extending them would alter 077's immutable semantics and every money function that lists/approves
those rows. The separation-of-duties pattern (distinct identities, bounded expiry, command idempotency) is copied, not the table.

## 2. Requirement-by-requirement

| Requirement | How it is met | Test |
|---|---|---|
| two-person mandatory after the maturity trigger | two DISTINCT identities (`approver_identity`), each platform_admin, each on its own aal2 session; same identity twice ⇒ `duplicate_approver`; executor must be one of the approvers | 177 D4–D6, D11, E1 |
| exactly one revoked global, zero active | `recovery_not_applicable` (0 revoked), `recovery_lineage_exceeded` (>1), `active_global_exists` — checked in approve, execute, AND the guard under the same advisory lock | 177 B1/B2/B4, F1, F6/F7, G1 |
| independently authenticated platform-admin + AAL2 approvals in a durable table | `kernel.is_platform(['platform_admin'])` + `request.jwt.claims.aal = 'aal2'` (106 idiom verbatim); `approver_aal` CHECK; session id recorded | 177 A1–A9, D1–D2, D12, E2 |
| bounded window; duplicate/same-principal rejected | `expires_at` CHECK ≤ 30 min; guard/execute count only `expires_at > now()`; one expired + one live ⇒ refused | 177 D6, G2/G3 |
| algorithm ES256 explicit | execute inserts `'ES256'` literally; the guard refuses anything else even with two approvals | 177 E12, G4 |
| reuse M6 strict checks | the guard is re-created with rules 1–9/11 intact; execute re-derives the PEM fingerprint with the same parser | 177 E4/E5, G4–G6; 176 51/51 still green |
| reject when active key / missing-expired-duplicate approval / scoped / wrong algorithm / fingerprint mismatch | `active_global_exists`, `post_revoke_recovery_unapproved`, `duplicate_approver`, `scoped_key_parked`, `algorithm_not_es256`, `fingerprint_mismatch` | 177 B4, D9/D10, D6, G5, G4, E3/G6 |
| preserve PFA-18A parking + PFA-18B revoke | provision/rotate untouched (still `dual_control_unavailable`); 106 revoke untouched and exercised on the recovered key | 177 F2–F4b |
| cannot be used for initial bootstrap / single-founder bypass | empty keyring ⇒ approve/execute refuse `recovery_not_applicable`; guard rule 11 ignores approvals for the first row; distinctness + executor-is-approver; no GUC/config/role override | 177 B1–B3; §4 residual |
| rollback/replay | rollback file regenerated from the 110 file (guard body verbatim) — restores `post_revoke_recovery_parked`; 111 re-applied twice cleanly | probe §3; 177 H1–H3 |
| concurrency + transaction rollback | advisory xact lock shared by approve/execute/guard; refused/rolled-back inserts leave nothing | probe §3; 177 E7, G8 |
| approval table exposes no client/service-role path | RLS on, 0 policies, 0 grants; append-only; functions revoked from service_role | 177 A5–A9, F8/F9 |

## 3. Evidence (local rehearsal, PostgreSQL 17.11)

| Check | Result |
|---|---|
| fresh replay through 111 (drop + re-apply every migration, LC_ALL=C) | no migration skipped; Gate-2 27/70/37/26 unchanged; kernel 32 tables / 153 functions |
| pgTAP suite 177 | **67/67** |
| pgTAP suite 176 (110 guard, under 111) | **51/51** (F2 now expects `post_revoke_recovery_unapproved`) |
| full pgTAP | **plan 3813 · ok 3809 · not_ok 4** — only the 4 documented local-only deltas (060 ×2, 132 ×2) |
| transaction-rollback probe | `BEGIN; <valid recovery insert>; ROLLBACK` ⇒ 0 active keys, approvals intact |
| concurrency probe | session A inserted the approved recovery key `…b1` and held its transaction 4 s; session B (own two approvals for `…b2`, started 1 s later) blocked on the advisory lock and, after A committed, was refused **`active_global_exists`** — a named refusal, no race, no unique-violation |
| 111 rollback → 110 semantics → re-apply ×2 | approval table gone, kernel fns 150; a post-revoke insert refused **`post_revoke_recovery_parked`** (110 behaviour restored); 111 re-applied twice cleanly (table back, fns 153); 176/177 green on a final fresh replay |
| `npx vitest run` / `npm run typecheck` / `npm run lint` / G-4 | 729/729 · clean · 0 errors · PASS |
| `deno check` | **OUTSTANDING** — not installed on the engineering host |

## 4. Adversarial review

- **Guard is the authority, functions are the ergonomics.** A bare superuser INSERT with two valid approvals passes (the approvals are the control);
  without them it is refused. The functions add audit rows, idempotency, and the executor-is-approver rule; they cannot widen what the guard admits.
- **No override surface**: no GUC, config key, role exemption, or env value is read anywhere on the path (grep-verified in the migration).
- **Fingerprint binding**: approvals bind to `sha256(DER SPKI)`; a different valid key for the same key_id is refused by both execute
  (`fingerprint_mismatch`) and the guard (`post_revoke_recovery_unapproved`) — an approver cannot be tricked into approving one key and inserting another.
- **Window**: both approvals must be unexpired *at execution*; `expires_at` is CHECK-bounded, so a forged far-future expiry is impossible even by
  direct insert; an expired approval cannot be revived (append-only).
- **Lineage**: exactly-one-revoked means this path is single-use per lineage; a second-generation recovery is refused `recovery_lineage_exceeded`
  and needs its own ratification + migration — deliberately NOT widened here.
- **Residual (disclosed)**: one human controlling two platform_admin identities defeats distinctness. That is the residual of every two-account
  scheme; it is DETECTABLE (audit rows carry both identities and session ids), not preventable. The organisational half of the maturity trigger
  ("a second qualified operator exists") is governance, not code — consistent with PFA-18C's stated guarantee.
- **Harness note**: the 22 legacy suites still disable the insert guard in `tap.seed_core()`; suite 177 calls `seed_core` (it needs identities) and
  immediately re-enables the guard (A0 asserts it), so every recovery assertion runs against the live guard.

## 5. Status matrix

| Item | Implemented | Tested | Deployed | Operationally verified |
|---|---|---|---|---|
| migration 111 (table, 3 fns, guard re-create) | ✔ | ✔ | **✘ NOT DEPLOYED** | ✘ |
| rollback 111 (generated, embeds 110 guard) | ✔ | ✔ (file-level + savepoint) | n/a | ✘ |
| census updates | ✔ (rehearsal package only) | ✔ | n/a | n/a |
| production ledger | **unchanged (124)** | — | — | — |

**Tested commit:** `927a02a` on `feature/venue-native-and-product-v2`.

## 6. Governance position (no ratification changed)

PFA-18C's maturity-trigger rule ("all future signing-key lifecycle operations MUST use two-person control and FAIL CLOSED if no second qualified
operator exists") is now backed by code: 110 fails closed, 111 provides the compliant two-person mechanism. Applying 110+111 to production is a
separate owner authorization (ledger 124 → 126) and remains **required before issuance** (M6 position). Owner ratification records are untouched.
