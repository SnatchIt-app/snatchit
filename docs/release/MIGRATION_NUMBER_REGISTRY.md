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
| `123` | 191 | **release integration** | transfers↔profiles FK parity | branch `fix/122-transfers-profiles-fk`, not applied |

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

## Apply-order conflict with 121/122 (flagged 2026-09-12)

Production tip is **120** and `121` is deferred optional hardening, applied only under
`AUTHORIZE PFA-18C MIGRATION 121` (B's state document §3). `123` is sandbox-applied only.

The conflict is ordering, not numbering: the scheme-aware guard compares a `seq` migration against the
highest `seq` already applied. If `123` reaches production first, `121` and `122` are then **below** the tip
and a strictly-increasing guard rejects them. So either B's `121`/`122` go first, or their apply has to be
cleared against a tip of `123`. Numeric gaps themselves are fine — production already carries
023/043/055/056/059/060/066.

B's "combined chain 142" is B's own chain label, not a migration number on this line; `142` is unowned here.
Confirm before anyone treats it as a claimed number.
