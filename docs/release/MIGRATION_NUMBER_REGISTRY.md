# Migration and pgTAP number registry

One owner per number. Updated 2026-09-12. Check here before claiming a number.

**Canonical production state:** `docs/release/PHASE2_PRODUCTION_STATE_20260912.md` (Claude B, commit
`55d37f5`, currently only on `origin/feature/venue-native-and-product-v2`). Production ledger **135**, numeric
tip **120**. That document supersedes the "current state" lines in the six historical Phase-2 records it
banners; it authorizes nothing.

| Migration | pgTAP | Owner | Subject | State |
|---|---|---|---|---|
| — | 187 | release integration | `my_tickets_read` | on the candidate |
| `20260910120000` | 188 | **Claude D** | `venue_api` read views | branch `venue/read-adapters-slice-1`, not applied |
| `121` | 189 | **Claude B** | manifest signing context STRICT | PR #58, not applied |
| `122` | **190** | **Claude B** | scanning drift fix | **RESERVED** — named in B's remaining-path report |
| `123` | 191 | **release integration** | transfers↔profiles FK parity | branch `fix/122-transfers-profiles-fk`; **applied to sandbox**, not production |
| `124` | 192 | **release integration** | bids↔profiles FK parity (F2) | proposed 2026-09-12, not written |

## How 122 was resolved

Both Claude B's remaining-path report and this line initially claimed 122. Only this branch had actually
committed the number, so the collision was prospective. B named it first and their `121` immediately precedes
it, so keeping `121`/`122` contiguous in that workstream is worth more than holding the number here; this work
renumbered to **123**, and **190 is left reserved** for B's companion test rather than taken.

Verified free across `release/convergence-135`, `venue/read-adapters-slice-1`, PR #58's branch and
`admin/operating-console` before claiming.

## Ordering note

The guard is **scheme-aware**: a `seq` migration is compared only against the highest `seq` migration, and a
`ts` one only against the highest `ts`. So `121`, `122` and `123` each need only exceed `120`, and they sort
*before* every timestamped migration in a fresh `LC_ALL=C` replay — after `120`, ahead of `20260714…`. That is
safe for all three, because each only re-creates or alters objects established earlier in the numeric block.

## CLI note

`supabase db query` **does** exist in CLI 2.115.0, with `--file/-f`, `--linked`, `--project-ref` and
`--db-url`. `supabase db --help | head -30` truncates the subcommand list after five entries; `query`, `lint`,
`start`, `advisors` and `schema` follow. Do not conclude from a truncated listing that it is unavailable.

## Apply order RESOLVED with B's plan of record (2026-09-12)

**Normal forward order, no renumbering:** `121` → `122` → `123` → `124`. Production tip is `120` and none of
the four is in production, so plain ascending order satisfies the guard and nothing needs renumbering. B's
`121` (PR #58) and `122` (086↔112/113 scanning drift) keep their numbers; `123` keeps its number, so the
sandbox apply history stays intact.

Two constraints follow:
- **`123` must not reach production before `121`/`122`.** It is sandbox-only today; nothing schedules it.
- **Sandbox is already at tip `123`**, so B's `121`/`122` rehearsals belong on a fresh replay DB (B's normal
  harness), not on the shared sandbox, or they land below its tip.

`142` in B's remaining-path report is the **count** of the combined release + venue + 121 chain, not a
migration number. Nothing claims `142`.

## Superseded: apply-order conflict as first flagged (2026-09-12)

Production tip is **120** and `121` is deferred optional hardening, applied only under
`AUTHORIZE PFA-18C MIGRATION 121` (B's state document §3). `123` is sandbox-applied only.

The conflict is ordering, not numbering: the scheme-aware guard compares a `seq` migration against the
highest `seq` already applied. If `123` reaches production first, `121` and `122` are then **below** the tip
and a strictly-increasing guard rejects them. So either B's `121`/`122` go first, or their apply has to be
cleared against a tip of `123`. Numeric gaps themselves are fine — production already carries
023/043/055/056/059/060/066.

B's "combined chain 142" is B's own chain label, not a migration number on this line; `142` is unowned here.
Confirm before anyone treats it as a claimed number.

## CORRECTION (2026-09-12): the "guard" is CLI planning, not a rejection

A's earlier wording here and in the release package — "a seq migration must exceed the highest applied seq
migration or a strictly-increasing guard rejects it" — **overstated it**. Sourced today:

- `supabase db push --help`: `--include-all  Include all migrations not found on remote history table.`
  So the DEFAULT plan contains only versions **above** the remote maximum; `--include-all` plans every version
  missing from the ledger, applied in `LC_ALL=C` order.
- There is **no** monotonic guard in `.github/workflows/ci.yml` or `supabase/ci/`. Nothing rejects a
  lower-numbered migration.
- Production has already applied out of numeric order: **115–120 (2026-09-08) before 110–114 (2026-09-09)**.

**Consequences.**
1. A lower-numbered migration is never "stranded". It is only **omitted from the default plan**, and
   `--include-all` plans it. The risk is silent omission, not rejection — which is why every apply here
   dry-runs and checks the planned list exactly.
2. Renumbering is therefore **not required** by any ordering rule. It only keeps a fresh `LC_ALL=C` replay in
   the same order production applied, which the rehearsal harness models explicitly
   (`convergence_prod_order_rehearsal.sh` replays production's real order, not the file order).
3. The owner's menu is wider than the earlier caveat suggested — see the release package.
