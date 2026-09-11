# Migration and pgTAP number registry

One owner per number. Updated 2026-09-10. Check here before claiming a number.

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
