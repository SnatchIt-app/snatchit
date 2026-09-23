# V3 functional findings — reconciled against the release source

**B · 2026-09-22 · corrects the register published at `d6a757ab`.**

## The baseline was wrong, and two findings were wrong with it

My first inventory was read from the design worktree (`design/frontend-audit-20260917`), whose transfer screens
predate the reviewed changes. The owner was right on both counts, and I verified both in source rather than
accepting them:

**Release source: `5b255838dea3d39561714554a547a6121ab2c8ff`** — *"Merge #90 into the release gate"*,
2026-09-22, on `release/production-gate-20260918`. This replaces my earlier statement that the design target was
"Build 22 + #81 + #84"; that described an older line.

**C's V3 implementation branch: `v3/midnight-app` @ `31819593`**, six commits ahead of the release source and
already carrying the type-rule amendment, five mixed-case name tokens, the bid-CTA correction (O-2), the dock
photo (O-5) and truthful reporting (O-3).

These files **changed** between my baseline and the release source, so every finding citing them was re-read:
`app/transfer/receive/[id].tsx`, `app/transfer/send/[id].tsx`, `src/lib/transfer/transferState.ts`,
`src/screens/PlaceBidScreen.tsx`, `src/screens/checkout/CheckoutNative.tsx`, `app/(tabs)/profile.tsx`.
These are byte-identical to my baseline, so findings citing them stand as written: `app/listing/edit/[id].tsx`,
`src/screens/CreateListingScreen.tsx`, `app/settings/*`, `app/profile/[id].tsx`, `app/(auth)/*`,
`app/report/[type]/[id].tsx`, `app/(tabs)/tickets.tsx`, `src/lib/push/registration.ts`,
`src/components/TransferStatusBadge.tsx`.

### The correction to F-17

**F-17 as published was wrong for the seller and right for the buyer.** I inferred screen behaviour from the
shared status vocabulary instead of reading the render path — exactly the mistake the owner named.

At `5b255838`, `src/lib/transfer/transferState.ts:98-110`:

```ts
export function sellerWindowView(i: { status: string; countdown: string | null; checkedSincePassed: boolean }) {
  if (i.status === 'expired') return { kind: 'closed', ...SELLER_ORDER_CLOSED_COPY.expired };
  ...
```

with `SELLER_ORDER_CLOSED_COPY.expired` = **"Order expired" / "This order expired before it was marked as sent.
Don't transfer the tickets for this order."** — rendered at `app/transfer/send/[id].tsx:283`. The seller is told,
from the server fact, and is told not to transfer. That is a good state, and my finding described code that no
longer exists.

**The buyer half survives.** At the same commit, and at `v3/midnight-app`, `app/transfer/receive/[id].tsx`
contains **zero** `status === 'expired'` or `status === 'reversed'` branches (measured: 0 matches on both refs),
and `transferStatusMeta` still routes both to `default:` → a lowercase badge from
`status.replace(/_/g, ' ')`.

### The correction to F-19

**Already fixed in the release source.** `app/transfer/receive/[id].tsx:381`:

```tsx
{countdown && transfer.status === 'pending' ? (
```

The buyer's send-window countdown is restricted to `pending`. The file even carries the reason at `:175` —
*"This effect had no status condition at all, so a buyer could watch a countdown…"*. My finding described the
pre-fix code.

### The rule this establishes, which I am adopting

**Status alone is never evidence about money.** The release source already demonstrates the discipline I should
have read before writing copy — `buyerAutoReleasedCopy` (`transferState.ts`):

```ts
if (payoutReleasedAt) return transferStatusCopy('auto_released', 'buyer');
return { title: 'Review window closed',
         body: 'The review window closed without a confirmation or a report from you. This order is complete.' };
```

The money sentence waits for `payout_released_at`. **No design of mine will translate `expired` or `reversed`
into "refund issued" without payment evidence**, and the neutral copy proposed below follows this template.

---

## The register

**Labels:** ① present in the release source · ② already fixed in the release source · ③ addressed in C's V3
branch · ④ proposed capability · ⑤ still unverified

| # | Label | Finding | Role / state | Observable consequence | Evidence @ `5b255838` unless noted |
|---|---|---|---|---|---|
| **F-17a** | **②** | Seller expired-order explanation | seller · `expired` | Seller sees "Order expired" and is told not to transfer. **Fixed — my finding was wrong** | `transferState.ts:81-83,98-110`; rendered `send/[id].tsx:283`; tests `send-transfer-expired-window.test.ts` |
| **F-17b** | **①** | **Buyer is told nothing on `expired` / `reversed`** | buyer · `expired`, `reversed` | Badge reads lowercase "expired"/"reversed"; no state block, no explanation, no next step. A buyer who opens the app instead of tapping the push learns nothing about why the order ended | 0 matches for `status === 'expired'\|'reversed'` in `receive/[id].tsx` at **both** `5b255838` and `v3/midnight-app`; `transferStatusMeta` `default:` branch |
| **F-18** | **①** | `TransferStatusBadge.tsx` is never imported | both | The component already contains "Transfer Expired" and "Payment Reversed" and nothing renders them | 0 importers on both refs (only its own definition) |
| **F-19** | **②** | Buyer saw the seller's deadline on settled transfers | buyer | **Fixed** — countdown gated to `pending` | `receive/[id].tsx:381`, reason at `:175` |
| **F-20** | **①** | A failed proof signed-URL is silent | buyer · `seller_sent` | The proof block disappears; the buyer is not told an image existed that could not load, and may confirm without seeing it | `receive/[id].tsx:107-109` — `.catch(() => setProofUrl(null))` |
| **F-21** | **①** | Raw PostgREST text reaches the buyer | buyer · delivery-info save | Unfiltered `rpcErr.message` in an "Error" alert — the only place in these screens; the seller path filters via `userFacing` | 3 matches on **both** refs; contrast `markSent.ts` |
| **F-22** | **①** | Buyer is never shown the auto-release deadline | buyer · `seller_sent` | `auto_release_at` is not in the select list, so the one date that decides whether payment leaves is invisible to the person it affects. The seller gets a countdown | 0 matches for `auto_release_at` in `receive/[id].tsx` on **both** refs |
| **F-23** | **①** | `send-push` applies no notification preference | both | Every transfer, dispute and expiry push is delivered regardless of preference; only `stripe-webhook` consults `notify_listing_sold` | 0 preference matches in `supabase/functions/send-push/index.ts` |
| **F-24** | **①** | Any unrecognised `type` segment becomes a listing report | reporter | `/report/anything/{id}` silently files a listing report | `report/[type]/[id].tsx:40`; file unchanged |
| **F-1** | **①** | Edit listing can hang on a permanent spinner | seller | Guard paths return without clearing `loading`; dismissing any way but the alert's OK leaves a permanent spinner | `app/listing/edit/[id].tsx:72,82-94` — file byte-identical to my baseline |
| **F-2** | **①** | Edit offers 6 platforms, Create offers 16 | seller | A listing on one of the other ten shows no chip selected | `edit/[id].tsx:31-38` vs `CreateListingScreen.tsx:84-101` |
| **F-3** | **①** | Transient RPC failure shows a reputation warning | seller | A network hiccup says "We've noticed some recent issues…". Failing open is intentional; the copy misattributes | `CreateListingScreen.tsx:386-389` |
| **F-4** | **①** | Signed-out publish is silent | seller | Every field turns red with no explanation | `CreateListingScreen.tsx:410` |
| **F-5** | **①** | Neither Create picker sheet has a no-results state | seller | A non-matching search renders an empty scroll view | `CreateListingScreen.tsx:892,933-937` |
| **F-6** | **⑤** | Stripe onboarding cancellation has no UI | seller | Backing out shows nothing; result type is only logged. File unchanged, but the *consequence* was not re-observed | `settings/payout-setup.tsx:126` |
| **F-7** | **①** | Two different banned-content messages | seller | Same rule, two wordings | `CreateListingScreen.tsx:416` vs `edit/[id].tsx:114` |
| **F-8** | **①** | No offline detection on Create or payout-setup | seller | Offline surfaces only as an upload error string | files unchanged |
| **F-9** | **①** | Phone verification is not enforced | new user | Abandoning after signup step 1 leaves a usable, phone-less session | `signup.tsx:85-88,112-136` — file unchanged |
| **F-10** | **①** | Two sign-out entry points disagree on confirmation | signed-in | Settings confirms; the Profile tab signs out immediately. **Re-checked because `profile.tsx` changed** — still no dialog | `profile.tsx:218-221,322` @ `5b255838` vs `settings/index.tsx:119-140` |
| **F-11** | **①** | Two unblock entry points disagree on confirmation | signed-in | Blocked users confirms; the public profile does not | `blocked-users.tsx:95` vs `profile/[id].tsx:166` — unchanged |
| **F-12** | **①** | Web and native delete-account copy differ | web users | Different wording for the same two-step confirmation | `settings/index.tsx:248-282` — unchanged |
| **F-13** | **①** | Bare-title alerts | signed-out / reset | The message is passed as the title with no body | verified at `5b255838`: `login.tsx` match present |
| **F-14** | **①** | Delete-account obligations can leak raw tokens | deleting user | An unrecognised `kind` falls through to the server string | `settings/index.tsx:193` — unchanged |
| **F-15** | **①** | Five of six notification preferences are hidden | signed-in | Intentional (`WIRED_PREF_KEYS`); listed so it stays deliberate | `notificationPrefs.ts:29-33` — unchanged |
| **F-16** | **⑤** | A signed-out guard on the public profile may be unreachable | — | Cannot be settled from source alone | `profile/[id].tsx:148` vs `app/_layout.tsx:108-118` |

**Nothing in this register is ③.** C's V3 branch closes the design questions O-2, O-3 and O-5, but I found no
finding above that it fixes — F-17b, F-18, F-21 and F-22 were measured on `v3/midnight-app` as well as on the
release source and are present on both.

**Nothing in this register is ④.** The one proposed capability in the V3 work — saved delivery preferences —
is a specification, not a finding, and stays labelled as proposed wherever a mockup depicts it.

---

## Reviews requested

**C — client behaviour.** F-1 (does the spinner really persist?), F-5, F-6, F-16, F-20, F-21, and whether
F-17b's two statuses are reachable in practice.

**A — money claims.** F-22 (is `auto_release_at` the right date to show a buyer, and may it be shown?), F-23
(should transfer pushes respect preferences?), and the proposed copy below before it is used anywhere.

---

## Proposed neutral copy for the verified missing state — FOR COPY REVIEW, NOT APPROVED

For **F-17b** only, and written to the `buyerAutoReleasedCopy` template: it states what the order did, never
what the money did, because status alone is not payment evidence.

> **`expired`, buyer**
> Title: **"Order closed"**
> Body: **"This order closed before the seller marked the tickets as sent. If you were charged, any refund is
> handled automatically — check your payment method or contact support if you don't see it."**

> **`reversed`, buyer**
> Title: **"Order reversed"**
> Body: **"This order was reversed. If you were charged, any refund is handled automatically — check your
> payment method or contact support if you don't see it."**

**Deliberately not said:** "you have been refunded", "your full refund has been issued", any amount, and any
date. A refund sentence may only appear when a payment fact supports it — the same rule
`buyerAutoReleasedCopy` already applies to payouts. **If A can supply a refund field on the transfer read, the
copy should be split the same way: a definite sentence when the field is present, this neutral one when it is
not.** Until A rules, the neutral form stands and the design is marked blocked rather than shipped.

The badge for both statuses should use the words already written in the unused `TransferStatusBadge`
("Transfer Expired", "Payment Reversed") rather than a lowercase `default:` label — that is a copy fix, not a
new capability.
