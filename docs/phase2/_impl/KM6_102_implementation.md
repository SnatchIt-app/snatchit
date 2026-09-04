# KM6 — migration 102 implementation report (credential signing authority + A8a' SALEABLE + signing trust-root dual control)

> **ORCHESTRATOR CORRECTION (post-review, applied before commit).** This report was written against
> a SIX-gate draft of migration 102. On review against `FINAL_ACTIVATION_BLOCKER_RULINGS.md` ITEM (i)/(ii),
> two gates were REMOVED as unratified overreach and the migration now ships **FOUR** publish gates
> (org / connect / signing / fee — exactly the `create_primary_checkout` SALEABLE predicate ratified
> A8a′ reading B names):
> - **Gate 5 `inventory_policy_unset` — REMOVED.** Not part of create_primary_checkout's SALEABLE set,
>   so not part of ratified A8a′; inventory hold policy is dynamic quote-time config (test 145 exercises
>   it UNSET). It also collided with 145's deliberate inventory-unset fixtures.
> - **Gate 6 `tax_policy_unresolved` + the `tax.policy_resolved` seed — REMOVED.** ITEM (ii) reserves the
>   tax enforcement LOCUS as an owner/legal decision; the train constraint is a prohibition ("do NOT
>   solve tax"), not a directive to wire a publish-time tax gate. Recorded as **PFA-PT-7** (boundary held).
>
> **Census consequence:** the `catalog.platform_config` census does NOT move (no new key) — §7's
> `platform_config` bumps (54→55 / 46→47) were NOT applied. What DID apply: kernel functions **146→147**
> (`get_ticket_signing_context`), five-schema routines **280→281**, the market/kernel/catalog string
> `22/146/16`→`22/147/16`, AND — a bump §7 MISSED — the **141 F2** `authenticated`-EXECUTE exact-name set
> (**66→67**, adding `get_ticket_signing_context`) plus its `140` PFA-1 witness. Test **168** dropped its
> B6/B6b/B7 (inventory+tax) assertions accordingly (`plan(52)`→`plan(49)`). Fixtures **145/146** were
> repaired for the 4-gate publish (see `KFIX_145_146.md`). The `get_ticket_signing_context`,
> `set_platform_config` signing-dual-control, and rollback sections below remain accurate as shipped.


Repo `/Users/josetascon/snatchit-consol`, branch `feature/venue-native-and-product-v2`. Boundary: `TRAIN_BRIEF.md` — everything below is DARK/unapplied/undeployed; no production, no deploy, no KMS, no Stripe, no signing key, no secret, no git commit. Verified on my own local rehearsal DB, `snatchit_rehears_dbimpl`, per `scripts/rehearsal_reset.sh` / `scripts/rehearsal_test.sh` (`PATH=/opt/homebrew/opt/postgresql@17/bin`). Design authority: `DESIGN_102.md` §1 (fixed spec for this implementer).

## 1. Objects

| Object | Kind | Signature | Note |
|---|---|---|---|
| `kernel.get_ticket_signing_context` | **NEW** | `(uuid) returns jsonb` | the credential-sign edge's ONLY source of signing facts; `security definer set search_path=''`; grant `authenticated`, revoke `anon`/`public` |
| `catalog.publish_event` | body-only re-create (081:899) | `(uuid, text, text) returns jsonb` | adds the six-gate A8a' SALEABLE ladder to `on_sale` only; every existing check preserved verbatim |
| `catalog.set_platform_config` | body-only re-create (093:6544) | `(text, jsonb, text, text) returns jsonb` | adds `signing.expected_key_fingerprint` / `signing.expected_max_not_after` to `v_dual`; `signing.monitor_enabled` deliberately excluded |

**One new object total** (`get_ticket_signing_context`). No new table, no new column, no new trigger, no new policy. `create or replace` preserves the ACL of both re-created functions (their `revoke`/`grant` statements are unchanged from 081/093 and are not repeated in 102). Config seed: `tax.policy_resolved` v1 `false`, `restricted` (append-only insert, `on conflict (key, version) do nothing` for replay-safety, matching 078/093/099's own seed convention).

## 2. Files

- `supabase/migrations/102_credential_signing_context_and_saleable.sql` — md5 `3300f5de64484859b83bc95b4973c3ae`.
- `supabase/rollbacks/102_credential_signing_context_and_saleable_rollback.sql` — forward-fix guard (break-glass posture, matching 096/101's rollback headers). Drops `get_ticket_signing_context`; restores `catalog.publish_event` to 081:899-964 verbatim and `catalog.set_platform_config` to 093:6544-6927 verbatim. The `tax.policy_resolved` seed **cannot be removed** (`catalog.platform_config` is append-only, no UPDATE/DELETE for any role) — after rollback the row is an inert orphan read by nothing, exactly the posture 099's rollback documents for its own five seeds.
- `supabase/tests/168_credential_signing_context_and_saleable.sql` — `plan(52)`, 52/52 passing.

## 3. `kernel.get_ticket_signing_context(uuid)` — the signing authority

Reads `kernel.tickets` (`current_owner_id, state, event_session_id, credential_version, signing_key_id`) and `kernel.signing_key` (`status, not_before, not_after, public_key, kms_handle_ref`) for the atom's **pinned** key — never a fresh per_event/per_venue/global lookup (§5.2: "resolved by `kernel.tickets.signing_key_id`, pinned at issue/transfer, NOT by a fresh lookup"). Writes no custody; the one write is an optional, non-secret `kernel.admin_audit` row (`action='credential.sign_context'`, `subject_kind='ticket_atom'`, `reason_code=<outcome code>`, `after={outcome, credential_version, key_id}` — no token, no payload, no key material, ever, verified by test A26).

**Gate order and refusal shape** — `{status:'refused', code:<code>}` (jsonb return, not a raised exception, per DESIGN §1.1):
1. **ownership** — `auth.uid() = current_owner_id`, re-read live. A non-owner and a **nonexistent** atom both collapse to the identical `not_owner` refusal (test A16/A17) — existence is not leaked.
2. **terminal** — `state in ('voided','scanned','expired')` → `atom_terminal`. `resale_state` is deliberately **not** part of this gate.
3. **pinned key** — the atom's own `signing_key_id` must resolve `status='active'` and inside `[not_before, not_after)`; missing/rotating/revoked/out-of-window → `signing_key_unavailable`, never silently re-resolved to a different key (test A21/A22).
4. **ttl** — `credential.app_ttl_interval` (078 seed, `"4 hours"`, public, never null post-078) → `ttl_seconds=14400`, `exp = issued_at + ttl`.

`auth.uid() is null` (no JWT at all) still raises an exception rather than returning a refusal jsonb, matching every other SECURITY DEFINER function's auth gate in this corpus — but that path is additionally unreachable through the grant: `anon`/`public` have **zero EXECUTE** on this function (test A0b/A23 — Postgres refuses with `42501` before the function body ever runs).

**Returned jsonb keys (the edge's contract — CRYPTO-IMPL codes against this exactly):**
```
status, ticket_atom_id, session_id, credential_version, key_id, kms_handle_ref,
public_key, algorithm, not_before, not_after, issued_at, ttl_seconds, exp, domain
```
`algorithm` is always `null` (no algorithm is modeled on `kernel.signing_key`; the edge/KMS provider decides, per DESIGN §1.1). `domain` is the fixed string `'SNATCHIT-TICKET-CRED-V1'`.

### DEVIATION from DESIGN §1.1's literal wording

DESIGN §1.1 says the terminal gate covers "`state` in ('voided','scanned','expired') **or `resale_state` indicating dead**". `kernel.tickets.resale_state`'s CHECK constraint (079:45) admits exactly `('none','listed','locked','refund_hold','dispute_hold')` — **none of these values literally means "dead"**; there is no `resale_state` value that is terminal by itself (only `state` has terminal members). Gating on `resale_state` at all would also contradict DESIGN §1.1's own very next sentence — "a `listed`/`locked` atom STILL returns a context…do NOT refuse listed" — and `refund_hold`/`dispute_hold` are structurally the same case: both coexist with `state='active'` (085:1066, 088:824), exist to control **door admission** (`OFFLINE-VERIFY-v1` conjunct 3b.v, EDGE_FUNCTION_SPEC §5.4.3 — `resale_state='none'` is a **door** check, not a signing precondition), and are explicitly named alongside `listed`/`locked` in that same conjunct's rationale ("a `refund_hold` atom is `state='active'` too"). EDGE_FUNCTION_SPEC §3.2 itself states the terminal gate purely in `state` terms ("a revoked/`voided`/`scanned` atom → 409") and offers listed/locked-still-signs as the explicit worked example. **Closest honest shape implemented:** gate on `kernel.tickets.state` alone; every `resale_state` value still signs. This is the interpretation that is actually consistent with both source documents; treating the parenthetical as requiring a second, undefined "dead resale_state" predicate would have meant inventing a value the schema does not have. Tested explicitly (A20: a `listed` atom signs `ok`).

## 4. `catalog.publish_event` — the A8a' SALEABLE gate ladder

Six static, DB-knowable, publish-time gates added to the `on_sale` transition only, **in order**, each copied character-for-character from its source predicate (not approximated) so a future edit to one ladder is an obvious mismatch against the other:

| # | Code | Predicate | Mirrors |
|---|---|---|---|
| 1 | `org_not_saleable` | `kernel.organization.status not in ('approved','active')` | `create_primary_checkout` G2a, 093:3982-4021 |
| 2 | `connect_not_ready` | `stripe_connect_account_ref is null or connect_transfers_active is not true` | G2, 093:4023-4026 |
| 3 | `signing_not_ready` | no active, in-window `kernel.signing_key` resolves `per_event(event_id) → per_venue(venue) → global` | G2b, 093:4066-4076 / `issue_ticket_atoms` resolver, 093:4952-4966 |
| 4 | `fee_policy_unset` | `fee.buyer_service_bps` is null | A5, 093:4093-4105 |
| 5 | `inventory_policy_unset` | `inventory.per_user_active_hold_max` **and** `inventory.hold_ttl_interval` both null-checked | 081's seed-pattern comment, 093:5513-5544 |
| 6 | `tax_policy_unresolved` | `tax.policy_resolved` (**new key**, 102 seed) is not `true` | A8a' owner direction, no rate/model defined |

Existing checks (auth, command-key, target-status membership, row lock, role, forward-transition, `empty_inventory`) are byte-identical to 081:899-964 — confirmed by `diff` against the extracted 081 body during authoring (only the declare block and the on_sale branch differ; test B1 also proves `empty_inventory` still fires **before** any SALEABLE gate is reached).

**Explicitly NOT gated here** (stay dynamic/quote-time, unchanged in `create_primary_checkout`): live inventory remaining, the per-user active-hold cap, session timing, `feature.native_issuance_enabled`. Tests B11/B12 confirm `on_sale → live → completed` are untouched.

**No permanent guarantee.** A publish-time PASS does not survive a later config regression (e.g. an admin unsetting `fee.buyer_service_bps` after publish) — nothing re-checks `on_sale`'s prerequisites once past it; the header documents this explicitly. Checkout's own ladder is the live re-check and is unmodified by 102.

## 5. `catalog.set_platform_config` — signing.% trust-root dual control

Two-line `v_dual` widening (093:6742-6746 → 102): `or p_key = 'signing.expected_key_fingerprint' or p_key = 'signing.expected_max_not_after'`. Neither key gets a polarity map entry — both take §20.2.1's third arm (not comparable ⇒ park in **both** directions), the same posture as `ticket.%`. `signing.monitor_enabled` is **deliberately excluded** — it is the detection kill switch (WALLET §11.5b reasoning: "a kill switch that needs a quorum is not a kill switch"), not the trust root, and stays single-admin both directions (tests C6-C8: on **and** off both execute with one admin).

`diff` against the extracted 093 body confirms the reproduction is byte-identical except: (a) the two-line `v_dual` addition, (b) three new comment blocks (the header, the `v_dual` addition note, the polarity-map exclusion note) — no existing line altered.

## 6. Verification (own DB, `snatchit_rehears_dbimpl`)

- Full 000-102 replay (117 files): **REPLAY OK**. Gate-2 public: `tables=27 functions=70 policies=37 triggers=26` — unchanged from the CI baseline.
- `supabase/tests/168_*.sql`: **52/52 PASS** (fresh reset).
- Rollback applied cleanly (`BEGIN; DROP FUNCTION; CREATE FUNCTION; CREATE FUNCTION; COMMIT`); confirmed by direct query that `get_ticket_signing_context` is gone, `publish_event`'s body no longer contains `org_not_saleable`, and `set_platform_config`'s body no longer contains `signing.expected_key_fingerprint`.
- 102 re-applied cleanly on top of the rolled-back state (`INSERT 0 0` on the seed — the `on conflict` no-op is correct, since the row survived the rollback per the append-only note).
- `168_*.sql` re-run after the rollback/reapply cycle: **52/52 PASS** again.
- Did **not** run the full suite (`census` assertions listed in §7 will fail until the orchestrator applies the bumps below — expected and by design).

## 7. Census deltas the orchestrator must apply

Live counts on the rehearsal DB after 102: kernel functions **147** (was 146, `+1` = `get_ticket_signing_context`), five-schema (`kernel,venue,catalog,market,notify`) routines **281** (was 280), `catalog.platform_config` total rows **55** (was 54, `+1` = `tax.policy_resolved`), `restricted`-visibility rows **47** (was 46); `public`-visibility (8), `market` (22), `catalog` (16) function counts unchanged.

**Kernel function count 146 → 147:**
- `supabase/tests/141_phase2_identity_orgs_deletion.sql:164` — count target + label text
- `supabase/tests/142_phase2_catalog_config_and_seeds.sql:1327` (count target) and `:1361` (label 'K3')
- `supabase/tests/143_phase2_ticket_custody_kernel.sql:143` (count target) and `:175` (label 'A32'; comment above at ~173 says "136 -> 146", needs a new "146 -> 147" line)
- `supabase/tests/144_phase2_venue_staff_authz.sql:94` (count target) and `:125` (label 'A14')
- `supabase/tests/148_phase2_kernel_tickets_late_binding_fks.sql:137` (count target) and `:175` (label 'B4')

**Five-schema routine total 280 → 281:**
- `supabase/tests/148_phase2_kernel_tickets_late_binding_fks.sql:75` (count target) and `:120` (label 'B2', "146+79+16+22+17" → "147+79+16+22+17")
- `supabase/tests/156_phase2_kernel_reserve_stub.sql:45` (count target) and `:74` (label 'A20')
- `supabase/tests/157_phase2_notify_reduced.sql:197` (count target) and `:218` (label 'A46')

**Combined market/kernel/catalog census string `'22/146/16'` → `'22/147/16'`:**
- `supabase/tests/154_phase2_market_bridge_view_and_late_fk.sql:49`

**`catalog.platform_config` census (total 54 → 55, restricted 46 → 47):**
- `supabase/tests/142_phase2_catalog_config_and_seeds.sql:298` (total) and `:305` (restricted)
- `supabase/tests/156_phase2_kernel_reserve_stub.sql:115` (label 'A23', total)
- `supabase/tests/157_phase2_notify_reduced.sql:153` (label 'A20', distinct-key total)

No `v_dual` prefix-list census exists as a standalone assertion (checked `142`'s dual-control section, 093's own comment trail) — every existing dual-control test is per-key, and `signing.%`'s two new dual-controlled keys are exercised entirely inside my own new `168` file (Section C), not inside `142`. Nothing in `093-101` was touched; I did not edit any census test myself.

## 8. What I did not build (and why, per the frozen model)

No signature-storage table, no async batch signer, no `signing.executor_enabled` cron — the credential is stateless by design (TRAIN_BRIEF's frozen fact, restated in 102's own header): the signature is never stored, `credential_version` is the sole currency mechanism, and this migration touches neither `kernel.tickets`' custody columns nor the transfer/void RPCs that bump `credential_version`. G4/G5 (settlement/obligation/payout) are untouched — 102 has zero references to `venue.settlement`, `kernel.payout`, or `kernel.organization_obligation`.
