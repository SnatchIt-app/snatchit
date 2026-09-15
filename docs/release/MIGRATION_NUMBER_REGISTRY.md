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
| ~~`122`~~ → `125` | **190** | **Claude B** | scanning drift fix (086↔112/113) | **REASSIGNED 2026-09-12**; written + rollback + pgTAP 190 (30 assertions), **PR #62** (`fc4f1130` → `admin/operating-console`), rehearsed 121→123→124→125; **A-reviewed 2026-09-14, review-only**; not applied |
| `123` | 191 | **release integration** | transfers↔profiles FK parity | branch `fix/122-transfers-profiles-fk`; **applied to sandbox**, not production |
| `124` | 192 | **release integration** | bids↔profiles FK parity (F2) | written with pgTAP 192 and rehearsed P1–P6 (2026-09-12); applied nowhere; sandbox apply awaits authorization |
| `126` | 193 | **Claude B** (reassigned from A 2026-09-14) | ops refund exactness (`refund_facts` + `daily_summary`/`money_overview`/`refresh_metrics`; A8 capped running-sum slice; `mixed` + `legacy_upper_bound_cents` + `legacy_count`) | **PR #63 draft** (`fix/126-refund-exactness @ db2f95f1`, base `c55ea50`), **review-only, D reviewing**; certified harness 141/141 replay, full suite 4755/4755; tests 184/186 amended in place with dated notes (120's vocabulary); not applied. Number stays `126`; `129` withdrawn |
| `127` | 194 | **release integration** | release guards — **L1** stale cancellation frees a newer hold + **L2** release frees a paid order's hold | written + rehearsed; **three adversarial review rounds** (`d3761c4` → `a85bbb0` → `6383b8f`); pgTAP 194 **30/30**; applied nowhere. **Not integration-ready** until a review round returns clean. L1 is closed only together with the webhook/checkout edge change recorded in the release package — 127 alone delivers L2 |
| `128` | 195 | **release integration** | `public.register_push_token` — device-proof token rebinding (F7); `notify` stays unexposed | **contract v2 FROZEN 2026-09-15** (`PUSH_TOKEN_CONTRACT_V2.md`) at **`f22c1a3`** after D's pass 3: **no blocking findings**; three D passes total (F1 HIGH heal regression fixed; G-1 parity re-grant, G-2 UPDATE oracle, G-3/G-4 rollback inverses closed). Certified harness 4806/4806; 195 **58/58**; 157 294/294 on the public verb; census 31/93/37/35; `push_tokens` client SELECT and UPDATE column-scoped. Applied nowhere; **residual risk (session compromise) is O-3, the owner's production decision** |

| `129` | 196 | **release integration (A)** | `public.revoke_push_token(text)` — the client's sign-out revoke, reachable through `public` (the `notify` schema is not PostgREST-exposed; contract v2 §2.4 erratum) | **written 2026-09-15**, in the Friday candidate (`57b3a00`); census +1 function (94); rollback true inverse; **D adversarial review: NO FINDINGS** (IDOR, caller identity through the delegate, anon/service_role refused, notify ACLs unchanged, rule-5 spillover, rollback) |
| `130` | 197 | **Claude B** | checkout supersede claim — per-(listing, buyer, mode) serialization of PaymentIntent secret hand-out (PR #64 residual, pre-existing in `df9e0d3`); lock order payments → listings; token-bound release; 120 s stale window | **written + reviewed 2026-09-15** (PR #65 `d5ee036`), **A review APPROVED, merged into the candidate**; certified harness 4967/4967, 197 40/40 (RED 38/40 without 130), two-session S1–S4 + deadlock control, edge tests RED 7/21 against #64, rollback exact; census **96**; applied nowhere |
| `131` | 198 | **release integration (A)** | session-bound push bindings — owner O-3 decision (b): password change / sign-out-everywhere invalidate bindings and proofs; old sessions cannot re-register | **allocated 2026-09-15** (moved from 129 so the wrapper could take the lower number ahead of it in the same candidate — the merge guard requires an added migration to exceed the base's highest); design `SESSION_BOUND_PUSH_BINDINGS_131_DESIGN.md` under D review (X1 reclaim rejected by D; owner choice pending); **production gate, not in the Friday candidate**; not written |

> **126 vs. the `129` proposal — kept distinct (2026-09-14).** `129` is now allocated to session-bound bindings (above); the renumber never happened. 126's *progress* is part 1 of 3, committed. Separately, A *proposed* reassigning the refund-exactness work from `126` to `129` so that `127`/`128` (security fixes) would not be held behind it. **That proposal is UNAPPROVED** and the owner has ruled the other way: 126 must be resolved before 127/128 merge, or an explicit registry/sequencing change must be proposed and approved. Until the owner says otherwise the number is `126`, the file is `126_ops_console_refund_exactness.sql`, and the merge order is 126 → 127 → 128 behind 121 → 123 → 124. Nothing claims `129`.

> **L1's server half landed in `127`** (payment-scoped release). **L3 and L4 still claim no number** — L3 is a product tradeoff (holding inventory longer on `payment_failed` vs. occasional charge-then-refund) and L4 needs a Stripe-calling path at hold expiry, which `cleanup_expired_reservations` cannot be since it is SQL-only. Neither is reserved speculatively.
>
> **Sandbox ordering consequence:** `126`/`127`/`128` must NOT be applied to the shared sandbox before `125` either. The GitHub guard is base-branch-relative, but the sandbox ledger is not — applying 128 there would put the sandbox tip above 125 and break the same ordering for any later sandbox apply.

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

## Merge order approved by the owner (2026-09-12) — sequencing only

**Intended merge order: `121` → `123` → `124`.** The unwritten scanning fix reserved as `122` is reassigned to
**`125`**, the next free number above `124`. Its companion pgTAP number **190 stays with it** — the guard scopes
to `supabase/migrations/**`, so test numbering is unaffected.

Why the renumber is required rather than cosmetic: `.github/workflows/migrations-guard.yml` §4 fails any PR
whose newly **added** migration is not strictly greater than the base branch's highest version of the same
scheme. Once `124` is in the base, a PR adding `122` fails. `121` is written and reviewed in PR #58, so it
merges **first** and needs no renumber; the unwritten fix costs nothing to move.

`125` verified free across `release/convergence-135`, `feature/venue-native-and-product-v2`,
`venue/read-adapters-slice-1` and this branch on 2026-09-12.

**This is sequencing approval only** — not authorization to apply any migration, and not a Build 16 change.
Claude B owns `121` and `125`; the registry and B's references need to agree before either is merged.
