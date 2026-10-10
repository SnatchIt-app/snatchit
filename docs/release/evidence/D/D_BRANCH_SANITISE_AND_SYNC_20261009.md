# D — records branch: uniqueness comparison, sanitised rewrite, push and sync confirmation

2026-10-09, under the owner's decision: *"If it contains unique useful work, rewrite the affected
commits to remove the ARNs and private evidence, verify the sanitized result, update the commit
references, and push it."*

## 1. Uniqueness comparison (required documentation either way)

Files on `review/d-records-20261005` absent from all three already-pushed D branches: **24**.
Of those, present on **any** remote ref: **0**. All 24 are D's own evidence — the eighteen `D_*.md`
records and the six files under `captures_20261008/`.

**Verdict: unique useful work.** So the owner's rewrite-and-push path applies, not the delete path.

## 2. The rewrite

Local backup taken first and **kept, never pushed**: `review/d-records-PREREWRITE-BACKUP` → `f70ca9d9`.

`git filter-branch --tree-filter` over `d375b5d8..HEAD` (8 commits), replacing both ARNs with the
synthetic `70000000000000000000001` A already uses for rehearsal controls.

**Verification of the sanitised result:**

| check | result |
|---|---|
| ARN `…64533475` in rewritten history | **0 commits** |
| ARN `…65910060` in rewritten history | **0 commits** |
| same check on the pre-rewrite backup (**control**) | **3 commits** — the method discriminates |
| file count, backup vs rewritten | 1637 vs 1637 |
| non-redaction lines changed between backup HEAD and new HEAD | **0** |

Nothing but the redacted strings moved.

## 3. The account-id truncation: reverted, and why that was the right call

D had also truncated `acct_1T6Fb1GlD5aqtxIw`. **Undone.** It is already public on
`origin/release/production-gate-20260918` and `origin/web/wording-truth-conditions` — **17 files each**
— and hard-coded in source at `src/config/envGuard.ts:35`. It is the **sandbox** account and the
project treats it as ordinary configuration. Redacting it in three D records while seventeen other
files on the same branch carried it in full was pointless and implied a sensitivity the repository
itself does not assign.

**The contrast is the control:** the same sweep returns **0** files containing either ARN on those
public refs. The ARN was a real, unique exposure; the account id never was.

## 4. Commit references for A

| old | new | subject |
|---|---|---|
| `fbe41284` | **`54430e02`** | witness the test-mode exclusion and review the owner's live Stripe screenshots |
| `addd4670` | **`c9544868`** | review A's O-R4 package at 77778156 and d4accc39 |
| `8ba6cef7` | **`dac702c1`** | re-check A's three new guards at f7595be9 |

Later shas also moved (`bab4060b`, `187f6986`, `133a6d75`, `5d439dd2`, `f70ca9d9`); the pre-rewrite
values resolve only on the local backup ref.

## 5. Push and the owner's exposure confirmation

All four D branches are on `origin`, each verified by `ls-remote` independently of the push output:

| branch | sha |
|---|---|
| `review/d-records-20261005` | `65ac8f4bbf5d` |
| `web/wording-truth-conditions` | `e7130f046a62` |
| `admin/label-console-release` | `1058c8825b97` |
| `review/d-integ-94-95` | `486c954cd918` |

**Sweep across all four published refs:**

| | result |
|---|---|
| ARNs | **0** on every branch, confirmed against `origin/…` itself, not the local copy |
| `sk_`/`rk_` + 20 or more key characters | **0** |
| service-role JWT assignment | 1 hit, investigated: it is the literal placeholder `SUPABASE_SERVICE_ROLE_KEY=eyJ…service-role-jwt…` in a usage comment in `scripts/seed-demo.ts`, blob **identical to the public gate**. Not a token; a decode attempt found none. |
| images | 74, **identical set to the public gate** (0 extra). All are App Store marketing assets. **D has committed 0 images**, so none of the owner's Stripe screenshots is in the repository. |
| production dumps | none; the only production data in D's records is payment ids, PaymentIntents, amounts and timestamps for the 7 reconciliation rows — the same identifiers A's package already published — plus event ids from the authorised ledger read. No customer names, emails, card data or exports. |

**Control that the sweep discriminates:** 6 anon-key JWT assignments are found on the records ref, which
are public-class by CLAUDE.md and expected.

**SSD ↔ GitHub:** all four in sync, working tree clean.

**A mis-specified control, recorded.** One control in the sweep — "ARNs on the local backup" via
`git grep` — returned 0 and appeared to fail. It was mis-specified: `git grep` searches a ref's **tip
tree**, and the backup's tip was already redacted at HEAD by `bab4060b`; the ARNs live in its
*history*. The valid control is the `git log -S` form, which returned 3. Recorded rather than quietly
dropped.

## 6. Preserved

- `review/d-records-PREREWRITE-BACKUP` → `f70ca9d9`, local only, never pushed, holds the pre-rewrite
  history including the real ARNs.
- The real ARNs also remain in the owner's own screenshots.
- `3787d8a2` (deleted trial branch) still resolves locally via A's retained worktree.
