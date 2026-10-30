# G5 — the all-in pricing contract, after owner ruling A5

**Artifact:** `src/lib/pricing/allIn.ts` (rewritten), `src/lib/pricing/provenance.ts` (one comment),
`tests/product-v2-foundation.test.ts`, `app/_dev/foundation.tsx`.
**Owner ruling:** A5 — `docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md:113`.
**Server contract:** `docs/phase2/_impl/093_parts/30_connect_org.sql` (`venue.create_primary_checkout`),
`supabase/functions/primary-checkout/index.ts`, `docs/phase2/_impl/E2_primary_checkout.md` §3.
**Closes:** E2 **AB-11**.
**Scope:** foundation only. No Tier-1 screen was designed, redesigned, or touched. No migration was
modified. Nothing was deployed, pushed, or committed.

---

## 1. The old contract, and exactly how it lied

`allIn.ts:26-30` asserted, for the venue-direct rail:

> `venue."order".total_minor` is a server-authoritative snapshot equal to the sum of
> `order_item.unit_price_minor * quantity`. There is NO buyer-fee column and NO tax column anywhere
> on this rail. So the order total IS the whole charge, and it is all-in by construction.

The reasoning was sound when written — no fee column existed, so nothing could be missing from the
total — and the API followed the reasoning: `DirectPriceInput` had a single field,
`serverTotalMinor`, which was returned verbatim as `totalMinor`.

**A5 falsified the premise.** The venue's entitlement now *starts* at ticket face value and Snatch It
earns a configurable **buyer-side** service fee. Migration 093 encodes this and is explicit that
`venue."order".total_minor` **stays face value and the fee is never added to it** — folding the fee
into that column would pay the venue the platform's own revenue through an append-only settlement
ledger. So the RPC returns three numbers instead of one:

| RPC field | Edge field | What it is |
|---|---|---|
| `total_minor` | `amount` | **FACE VALUE.** The venue's gross and the settlement basis. **Not a price.** |
| `buyer_fee_minor` | `buyer_fee` | `round(face * fee.buyer_service_bps / 10000)`, half-up. Platform revenue. |
| `charge_total_minor` | `total` | **THE CHARGE.** face + fee. The only figure a PaymentIntent is minted for. |

The old API's single field was named for the wrong one of these three. Any caller following the
module's own header passed `order.total_minor` and **under-showed the real price by exactly the
service fee** — the precise dishonesty the module was written to prevent, on the module's own advice.

The old contract had two further latent holes, both now closed: an unset `fee.buyer_service_bps`
(seeded NULL, the A5 owner STOP) had no representation at all on the client, and `formatMinor`
divided by 100 into a float.

---

## 2. The new contract

### Input — the fee is structurally impossible to forget

```ts
type DirectPriceInput = {
  rail: 'direct';
  faceValueMinor: Cents | null | undefined;      // order.total_minor — face, NOT the price
  buyerServiceFee: BuyerServiceFeeInput;         // REQUIRED — no default, no zero
  chargeTotalMinor?: Cents | null;               // charge_total_minor — authoritative, cross-checked
  currency?: string;
  tax?: TaxInput;                                // default { status: 'not-applicable' }
};

type BuyerServiceFeeInput =
  | { source: 'server-quote'; feeMinor: Cents | null | undefined }  // buyer_fee_minor — never recomputed
  | { source: 'config-rate';  bps: number | null | undefined }      // pre-checkout estimate from config
  | { source: 'unset' };                                            // the A5 owner STOP, named

type TaxInput =
  | { status: 'not-applicable' }
  | { status: 'applies'; taxMinor: Cents | null | undefined }
  | { status: 'applies-unknown' };                                  // refuse
```

There is no field a caller can populate with `order.total_minor` and get a price out of. Omitting the
fee does not compile, and does not silently mean zero at runtime either.

`MarketplacePriceInput` is unchanged except that it gained the shared optional `tax`.

### Output — the breakdown is part of the result

```ts
type AllInResult =
  | { kind: 'all-in';
      totalMinor: Cents;             // THE charge — the only number shown as "the price"
      faceValueMinor: Cents;         // labelled breakdown row only
      buyerServiceFeeMinor: Cents;   // labelled breakdown row only
      taxMinor: Cents | null;        // null = no tax applies (never "unknown")
      currency: string; rail: PriceRail }
  | { kind: 'unavailable'; reason: AllInUnavailableReason };
```

### The one supported reader

```ts
allInFromPrimaryCheckout(res)   // res = the primary-checkout 200 body
```

It maps `amount → faceValueMinor`, `buyer_fee → server-quote fee`, `total → chargeTotalMinor`, so no
screen ever has to choose between `amount` and `total` — a choice one identifier wide with a
silent under-show on the wrong side.

### Refusal reasons

Pre-existing (unchanged, none weakened): `missing-base`, `invalid-base`, `unknown-rail`,
`tax-unmodelled`, `server-total-missing` (now: the direct rail's **face value** is absent).

Added:

| Reason | Server twin | When |
|---|---|---|
| `service-fee-unset` | RPC `service_fee_unset` / edge **503** | `{ source: 'unset' }`, a null `bps`, an absent `buyer_fee`, or a missing `buyerServiceFee` field entirely. **No zero fallback.** |
| `service-fee-out-of-range` | RPC `service_fee_out_of_range` | `bps` is not an integer `0..10000`. |
| `quote-incoherent` | edge `quote_incoherent` (500) | `chargeTotalMinor !== face + fee + tax`. |

### Arithmetic

Direct-rail money math is integer-only. The fee derivation matches the RPC exactly —
`product = face * bps`; refuse if not a safe integer; `rem = product % 10000`;
`whole = (product - rem) / 10000` (an exact multiple, so an exact division);
`rem * 2 >= 10000 ? whole + 1 : whole`. That is half-up, matching Postgres `round(numeric)`
(half-away-from-zero, both operands non-negative). Verified against a BigInt reference over a
13 × 12 grid of faces and rates. `formatMinor` now splits with `%` and an exact `/100`, prints
`-$60` rather than `$-60`, and returns an em dash for anything that is not a safe integer of minor
units instead of `$1e+23` or a silently rounded lie.

**One documented divergence.** The *marketplace* fee still comes from `money.ts`'s
`buyerFeeCents` = `Math.round(base * 0.10)` — a float rate. It is deliberately untouched: `money.ts`
is a byte-identical mirror of the server's `_shared/money.ts`, parity is asserted by
`tests/money.test.ts`, and `create-payment-intent` rejects a client total that disagrees. Converting
it to integer basis points would fork the client from the server for no behavioural gain. The direct
rail, which has no such mirror, is integer-only.

### The units collision, in both directions — CLOSED AT THE TYPE LEVEL

`Cents` already existed because `public.listings.buy_now_price` is **whole dollars** while this module
works in cents ($50 rendering as $0.55). The direct rail adds the mirror image: every venue column is
**already minor units**, so double-converting turns $60 into $6,000.

**A brand alone was not enough, and review proved it.** The brand stops accidental *mixing*, but it
left two tsc-clean routes back into the exact bug it exists to prevent:

1. `formatMinor` was typed `Cents | number`, so `formatMinor(50)` — and `50` is what a
   `public.listings` price column literally hands a screen — returned `"$0.50"`. A silent 100×
   understatement on the primary conversion surface.
2. `asCents` is an **unchecked cast**, and the guidance pointed callers at it. `asCents(50)` on the
   resale rail quoted `"$0.55"`.

The `$50 → $55` test passed through both, because it converted correctly first: it proved the happy
path, not the trap. Two compile-time closures now stand behind the brand:

| Closure | Effect |
|---|---|
| `centsFromDollars` returns **`DollarDerivedCents`**, a subtype of `Cents`, and `MarketplacePriceInput.baseMinor` accepts only that | `asCents(50)` on the resale rail no longer compiles. `asCents` cannot produce the type. |
| **`formatMinor(totalMinor: Cents)`** | `formatMinor(50)` no longer compiles. A caller holding whole dollars converts at its own call site, which is where the conversion belongs. |

`marketplaceCentsFromMinorColumn()` is the named, deliberately long escape for a resale price that is
genuinely already minor units — **no such column exists today** — so that closing the hole does not
push a future caller toward `as unknown as`, which would defeat all of it.

**The heuristic was weighed and rejected.** A magnitude guard inside `asCents` ("a two-digit cents
value is probably dollars") would fire on correct code: a 10% `buyer_fee_minor` on a $5 face **is 50**,
and a tax line can be 25. Its false positives land squarely on the fields ruling A5 introduced, and a
guess that rejects real money is not safer than a type that cannot be wrong. There is likewise no
runtime magnitude guard in `formatMinor`, and there cannot be one — `50` is a legitimate cent amount,
so the units are knowable only from the type.

**What is still open, stated honestly:** an untyped JS caller bypasses the brand entirely. For that,
`formatMinor`'s runtime guard is the backstop — it returns an em dash for anything that is not a safe
integer (including `null`, `undefined`, and a string) rather than printing `$NaN` — but it cannot
detect wrong *units*. `priceLadder`'s `lastSaleMinor` remains plain `Cents`, since it serves both
rails and a direct last-sale is genuinely minor units.

**Differential proof, not documentation.** Six `@ts-expect-error` assertions are enforced by
`tsc --noEmit`. Verified empirically: reverting only the three type narrowings and re-running the
typecheck fails with **three `TS2578: Unused '@ts-expect-error' directive`** errors, at
`formatMinor(50)`, `formatMinor(listingPriceFromColumn)`, and
`allInPrice({ rail: 'marketplace', baseMinor: asCents(50) })`. The trap is closed, not described.

---

## 3. Call sites touched

| File | Change |
|---|---|
| `src/lib/pricing/allIn.ts` | Rewritten direct rail (above), plus the two units closures: `formatMinor` narrowed to `Cents`, `centsFromDollars` → `DollarDerivedCents` required by the resale rail, and the named `marketplaceCentsFromMinorColumn` escape. Marketplace rail behaviour byte-for-byte unchanged: the total is still produced by *calling* `buyerTotalCents(base)`. |
| `src/lib/pricing/provenance.ts` | Comment only. `provenanceSortWeight`'s doc called direct inventory "the cheaper … option" — A5 makes that unprovable (direct now carries its own configurable fee), so the claim is removed and the ordering is restated as a provenance rule. No behaviour change. |
| `app/_dev/foundation.tsx` | The only runtime caller; its resale row now reads `centsFromDollars(50)` — fifty dollars — instead of `asCents(5000)`. Dev harness rows updated to the three-number quote, plus a new "direct, fee rate unset" row — which is what the harness actually shows today, since `fee.buyer_service_bps` is seeded null. Now prints the face + fee breakdown beside the total. |
| `tests/product-v2-foundation.test.ts` | Pricing block rewritten and expanded (§4). |
| `docs/phase2/_impl/E2_primary_checkout.md` | §3 now documents `allInFromPrimaryCheckout`; **AB-11 marked CLOSED**. |
| `supabase/functions/primary-checkout/index.ts` | **Comments only, no code.** Two comments referenced the removed `serverTotalMinor` field and stale line numbers. |

Nothing else in the repo imports the pricing module. No Tier-1 screen calls `allInPrice` yet — the
adversarial review's F-01 finding was that F-01 had to be fixed *before* one did, and that ordering
still holds.

---

## 4. Tests

`tests/product-v2-foundation.test.ts`, three blocks (marketplace / direct / display):

- **face + fee = total**, and `totalMinor !== faceValueMinor` — the regression for the exact bug.
- `allInFromPrimaryCheckout` reads `total`, not `amount`.
- **fee unset → `service-fee-unset`**, via all four routes (`unset`, null `bps`, absent `buyer_fee`,
  missing field), asserting a refusal and never a zero-fee price.
- rate out of range (`-1`, `10001`, `250.5`, `NaN`, `Infinity`) → `service-fee-out-of-range`;
  `0` and `10000` accepted as the inclusive bounds.
- **tax applicable but unknown → `tax-unmodelled`** on both rails, including `{ applies, taxMinor: null }`;
  a known amount joins the total and the charge cross-check.
- `charge ≠ face + fee` → `quote-incoherent`.
- **rounding**: nine hand-checked half-up cases (including `0.5 → 1` and `100.5 → 101`), plus
  integer-exactness against a BigInt reference across 156 face/rate pairs.
- **units**: `$50` renders `$55` and never `$0.55`/`$0.50`; the double-conversion mistake is pinned at
  exactly 100×; the two readings of the literal `50` are pinned side by side
  (`formatMinor(asCents(50)) === '$0.50'` vs `formatMinor(centsFromDollars(50)) === '$50'`); six
  `@ts-expect-error` compile-time assertions, three of which **fail on the pre-fix code**.
- **direct-rail small amounts** still quote correctly (a 10% fee on a $5 face is 50 cents), which is
  the false-positive case that ruled out a magnitude heuristic.
- **negative and non-finite paths**, re-checked after the rewrite: `-$0.01`, `-$60`, `-42 EUR`,
  `-0 → "$0"` (never `-$0`), `±Infinity`/`NaN`/`12.5`/`1e23`/`null`/`undefined`/`'50'` → em dash, and
  `±MAX_SAFE_INTEGER` formatted exactly.
- **resale regression**: `totalMinor === buyerTotalCents(base)` and
  `buyerServiceFeeMinor === buyerFeeCents(base)` across ten bases including the rounding boundaries.
- display: negatives, non-safe integers, separators, `EUR`.

`npx vitest run` → **314 passed (314)**, 9 files (was 299; +15 net).

### Independent adversarial review (separate from this suite)

An adversarial review ran its own differentials against this module and reported two results worth
keeping on the record. They were produced by that review's harness, not by the suite above:

- **no float arithmetic on the direct rail** — **0 divergences across 126 cases**;
- **resale behaviour unchanged** — **0 divergences across 200,000 cases** against `buyerTotalCents`.

The same review found the one gap this document's units section now closes.
`npx tsc --noEmit -p .` → **clean**.

---

## 5. What a UI must do to display an honest price

1. **Never render `faceValueMinor` as the price.** On the direct rail it is the venue's entitlement;
   showing it alone under-quotes by the service fee. It may appear only in a labelled breakdown row
   next to its own label.
2. **Lead with `totalMinor`.** The first price a buyer sees anywhere — card, list, event page,
   checkout — is `formatMinor(result.totalMinor, result.currency)`.
3. **Handle `kind: 'unavailable'` as a first-class state, not an error toast.** Render the price
   surface with no all-in claim, or fall through `priceLadder` to the last sale. Never substitute a
   base price, and never print `$0`.
4. **Map the refusal reason to what the buyer should do.** `service-fee-unset` and
   `service-fee-out-of-range` are activation blockers (the edge answers 503) — "tickets aren't on
   sale yet", plus an operational alert; they are not the buyer's problem and must not read as one.
   `quote-incoherent` means re-fetch the quote. `tax-unmodelled` means this event cannot be quoted
   at all until tax is modelled.
5. **Itemize from the result, never by re-deriving.** A receipt shows `faceValueMinor`,
   `buyerServiceFeeMinor` and, when non-null, `taxMinor`. They sum to `totalMinor` by construction.
   A screen must not recompute a fee, apply a percentage, or read a rate.
6. **Convert once, at the boundary.** `centsFromDollars` for `public.*` whole-dollar columns,
   `asCents` for `*_minor` and edge fields. Never both.
7. **Use `allInFromPrimaryCheckout(res)`** rather than destructuring the checkout response by hand.

---

## 6. Not done here, deliberately

- No Tier-1 screen was designed or migrated onto this primitive.
- `fee.buyer_service_bps` remains **unset**; every direct quote refuses today, by design (A5 STOP).
- Processing-cost allocation (E2 **AB-10**) is still an open owner item and is not encoded anywhere.
- Tax remains unmodelled on both rails; the `{ status: 'applies', taxMinor }` branch exists so the
  primitive is ready, not because a schema carries it.
- `money.ts` and its server mirror were not touched.
