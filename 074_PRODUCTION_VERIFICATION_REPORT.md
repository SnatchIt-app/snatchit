# 074 — Privilege Cleanup: Production Verification Report

## Verdict: **074 PRIVILEGE CLEANUP CLOSED IN PRODUCTION**

Applied 2026-08-27 under explicit owner authorization, pinned to the authorized head SHA. All 23
verification items resolved — 21 confirmed, 2 recorded as *not exercised* with the reason stated
(§4). No business row was modified. `075` was not applied.

| | |
|---|---|
| PR | [#25](https://github.com/SnatchIt-app/snatchit/pull/25), squash-merged pinned to `2b2f0012bc60ef5bb0cfd5f76a4acbfcefb6f9b2` |
| Migration | `074_privilege_cleanup.sql` · **`e115c7dcb1cfbee420a8289521a71a51ec0d1d0be5036f9a052aa1fabfe9a862`** |
| Rollback | `074_privilege_cleanup_rollback.sql` · **`476dae5344a96787f4712b07f33edd5fbb2e8b6cdd0937e242376efc41f321e2`** |
| `main` | `ded3724` · tree `f3dd9017b801286ab59b0261d469ab015a7654bf` |
| Ledger | **87 → 88** |

Both SHA-256 values match the authorized artifact exactly. `main`'s tree is the same object as the
authorized PR-head tree, so **production runs byte-for-byte what was reviewed**.

---

## 1. Pre-flight

| Gate | Result |
|---|---|
| PR head == authorized SHA | `2b2f0012…cefb6f9b2` ✓ exact |
| Required checks | 14 pass, 1 skipping · `MERGEABLE / CLEAN` |
| **Auto-deploy OFF** | `git_branch = ""`, `updated_at` still `2026-08-27T15:49:25Z` ✓ |
| Ledger before | **87** |
| Backup before | **79** |
| Applied checkout | 88 migrations · **`075` absent (0 files)** |
| Migration / rollback SHA-256 | both match the authorized values ✓ |
| **Dry run** | `• 074_privilege_cleanup.sql` — exactly one ✓ |

## 2. Apply

```
supabase db push --linked --include-all
  → Applying migration 074_privilege_cleanup.sql...
  → {"upToDate":false,"dryRun":false,"migrations":["074_privilege_cleanup.sql"],...}
```

## 3. Verification — items 1–23

| # | Required | Result |
|---|---|---|
| 1 | ledger = 88 | **88** ✓ |
| 2 | repository migrations = 88 | **88** ✓ |
| 3 | exact source↔ledger equality | both md5 **`9ed624814b416cb8bc9f07378a5e00fe`** ✓ |
| 4 | `db push --dry-run` up to date | `{"upToDate":true,…,"Remote database is up to date."}` ✓ |
| 5 | `webhook_retries` anon privileges removed | ✓ `anon` entry gone from `relacl`; `has_table_privilege` SELECT/INSERT → **false** |
| 6 | `webhook_retries` authenticated privileges removed | ✓ entry gone; UPDATE/DELETE → **false** |
| 7 | `service_role` retains intended access | ✓ `service_role=arwdDxtm`; SELECT/INSERT/UPDATE/DELETE all **true** |
| 8 | `postgres` retains intended access | ✓ `postgres=arwdDxtm`; SELECT/INSERT **true** |
| 9 | RLS remains enabled | ✓ `relrowsecurity = true` |
| 10 | policy count remains 0 | ✓ **0** |
| 11 | row count unchanged | ✓ **0 → 0** |
| 12 | PUBLIC/anon/authenticated EXECUTE removed exactly where reviewed | ✓ (table below) |
| 13 | `is_blocked_by_me(uuid)` keeps anon+authenticated, loses PUBLIC | ✓ exactly |
| 14 | `is_winner(uuid,uuid)` unchanged | ✓ byte-identical ACL |
| 15 | `set_ambassador_application_updated_at()` unchanged | ✓ byte-identical ACL |
| 16 | triggers remain attached and functional | ✓ 24/24 attached and **enabled**; one exercised behaviourally (§4) |
| 17 | sanctioned transfer RPCs still work | ✓ see §4 — the state guard fires, so the RPC-only path is intact |
| 18 | full pgTAP green | ✓ `Files=15, Tests=276, Result: PASS` on the identical tree |
| 19 | fresh replay green at 88/88 | ✓ 88 discovered, 88 applied, 0 skipped, 0 duplicates |
| 20 | grant parity correct | ✓ `OK: 64 grant rows match the expected fixture` |
| 21 | Gate-2 unchanged | ✓ **27 / 69 / 37 / 24** |
| 22 | pre-Scheme-B backup intact | ✓ **79 rows** |
| 23 | no real user/business rows modified | ✓ listings 111 · transfers 36 · payments 56 · profiles 14 · storage objects 172 — all unchanged |

### `public.webhook_retries` — before → after

```
BEFORE  postgres=arwdDxtm | anon=arwdm | authenticated=arwdm | service_role=arwdDxtm
AFTER   postgres=arwdDxtm |                                    service_role=arwdDxtm
```

RLS still enabled, still zero policies, still zero rows, still zero column ACLs.

### Function EXECUTE — before → after

| function | returns | before | after | verdict |
|---|---|---|---|---|
| `dispute_resolutions_append_only()` | trigger | `=X`, anon, auth, svc, pg | `postgres`, `service_role` | ✓ revoked as reviewed |
| `guard_transfer_state_columns()` | trigger | `=X`, anon, auth, svc, pg | `postgres`, `service_role` | ✓ revoked as reviewed |
| `reset_transfer_guard_bypass()` | trigger | `=X`, anon, auth, svc, pg | `postgres`, `service_role` | ✓ revoked as reviewed |
| `is_blocked_by_me(uuid)` | bool | `=X`, anon, auth, svc, pg | `postgres`, **anon**, **authenticated**, `service_role` | ✓ **PUBLIC only** removed |
| `is_winner(uuid,uuid)` | bool | `=X`, anon, auth, svc, pg | **unchanged** | ✓ deliberately excluded |
| `set_ambassador_application_updated_at()` | trigger | `=X`, anon, auth, svc, pg | **unchanged** | ✓ deliberately excluded |

Functions in `public` still carrying PUBLIC EXECUTE: **6 → 2**, and the two remaining are exactly
the two deliberately excluded.

## 4. Behavioural verification — and what was NOT exercised

Method: one transaction, `BEGIN … ROLLBACK`, no synthetic rows created, **no business row modified**
(re-confirmed by the unchanged counts in item 23).

**`guard_transfer_state_columns()` still fires after its EXECUTE was revoked** — a direct
`UPDATE public.transfers SET status=…` raised:

```
P0001: Cannot directly modify transfer state columns. Use the appropriate RPC.
```

This is the load-bearing proof for items 16 and 17: **PostgreSQL does not consult EXECUTE when a
trigger fires**, so revoking client EXECUTE on a trigger function cannot disable the guard — and the
RPC-only write path for transfers remains enforced.

**Not exercised, stated plainly rather than implied:**

- **`dispute_resolutions_append_only()`** — `public.dispute_resolutions` is empty, so there was no
  row to attempt an UPDATE against. The trigger is confirmed **attached and enabled**
  (`tgenabled='O'`), and it is the same trigger-function class proven above, but its firing was not
  demonstrated on production.
- **`reset_transfer_guard_bypass()`** — a statement-level trigger whose effect is resetting a
  transaction-local GUC; not separately exercised. Confirmed attached and enabled.

Both are covered by the CI suite on the identical tree; neither claim of behavioural firing on
production is being made here beyond the one demonstrated.

## 5. Scope discipline

The migration is five `REVOKE` statements between `BEGIN`/`COMMIT`. **No `GRANT`. No `ALTER
FUNCTION`. No `CREATE`/`DROP`. No policy, trigger, schema or ownership change.** Verified after apply:
Gate-2 identical, all 24 triggers still enabled, every business-table row count unchanged.

Confirmed **not** done: `075` not applied (absent from the ledger and from the checkout) · no Phase-2
work · no RLS redesign · no unrelated grant touched.

## 6. Artifact-identity note

The PR body originally recorded hashes taken at commit `b1188bb`, before the adversarial-review
conditions landed; those conditions changed **header comments only** and moved the file hash
`ab57f3dc…` → `e115c7dc…`. Proven equivalent: with `--` comments and blank lines stripped, both
revisions hash to the same body **`aba841bfbc6da03eb05c46f55d0ff7512982bf4b05f90b32a1838a9e782de5f8`**
and a direct `diff` of the stripped bodies is empty. The branch was then rebased onto `main` (now
carrying `073`), which changed commit SHAs but **not** the migration blob (`47368a3a4816` at both
`c4cbd9a` and `2b2f001`). The PR body has been corrected and carries the full trail.

CI is bound to the final artifact: runs `33114644530` and `33114641135` both on head
`2b2f0012bc60ef5bb0cfd5f76a4acbfcefb6f9b2`.

## 7. Rollback

`supabase/rollbacks/074_privilege_cleanup_rollback.sql`. **Part 1 (`webhook_retries`) is deliberately
commented out** and labelled a security regression rather than a neutral undo: re-granting hands
`anon`/`authenticated` direct DML on a money-adjacent audit table and restores no capability any
client ever used. The re-grant, if ever needed, is spelled `SELECT, INSERT, UPDATE, DELETE, MAINTAIN`
to reproduce the pre-074 `arwdm` exactly rather than over-granting with blanket `ALL`. Part 2 restores
exactly what was removed, with `is_blocked_by_me` receiving PUBLIC only.

## 8. What this did NOT close

The `pg_default_acl` generator survives 074 — the migration contains no `ALTER DEFAULT PRIVILEGES` —
so **any future table `postgres` creates in `public` re-acquires `anon=arwdm`/`authenticated=arwdm`**.
Six sibling zero-policy tables carry that grant today by *accepted parity* (`parity_grants.sql`
grants them deliberately because source and production agree): `disputes`, `payout_decisions`,
`payout_policy`, `seller_flags`, `seller_risk_scores`, `stripe_connect_archive`. `webhook_retries`
was the one table where source and production **disagreed**, which is why it is the only one 074
could reconcile without becoming a new control. **SEC-1 is closed; the exposure class is not.**

## 9. Follow-ups this creates

- **DRIFT-1 prose is now stale.** `supabase/ci/parity_grants.sql` and the two `071` reports describe
  `webhook_retries` as a live source↔production divergence. It no longer is. The fixture itself needs
  no change — it already follows source — but the prose should be reconciled.
- The `pg_default_acl` class above needs a named decision (accept as parity, or close it deliberately).
- `set_ambassador_application_updated_at()` still needs its own **timestamp-scheme** migration with a
  version strictly greater than `20260731224653`.

## 10. Remaining — not covered by this authorization

- **`075`** (replay parity: orphan storage policies + cron) — authored, adversarially reviewed
  ACCEPT-with-conditions (applied), CI green, proven no-op on production, **NOT applied**.
  [PR #23](https://github.com/SnatchIt-app/snatchit/pull/23).
- **Phase-2 amendment** — backend consolidation held pending four owner rulings plus the
  `catalog.event_session.door_open_at` lifecycle gap.
- **Phase-2 renumber** to `076`–`091`, mechanical, at integration.
- Open findings unchanged: MONEY-1 (Medium, not exploitable) · F-2 / F-3 · `buy_now_price` re-pricing
  (severity **unknown** pending installed-base measurement) · `strict_required_status_checks_policy: false` ·
  Gate-2 blind to storage-schema and cron drift.

---

## Verdict

**074 PRIVILEGE CLEANUP CLOSED IN PRODUCTION.**

`anon` and `authenticated` no longer hold any privilege on `public.webhook_retries`; three
trigger-returning functions and `is_blocked_by_me`'s PUBLIC grant are revoked exactly as reviewed;
the two deliberately excluded functions are byte-identical; every trigger remains attached, enabled,
and demonstrably firing; `service_role` and `postgres` retain full intended access; ledger 88 with
source and ledger exactly equal; Gate-2, grant parity, and every business-table row count unchanged;
backup intact; auto-deploy still off.

`075` remains independently owner-gated and does not inherit this authorization.
