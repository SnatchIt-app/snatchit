# B — checkout presentation reviewed at `d374bd3f`

**Candidate confirmed:** `d374bd3f` is the **tip** of `v3/midnight-app` and contains the Listing and Send
fixes as well as the new page. Zero harness patches. **B's own independent captures**, 393 × 852 × 3, signed
in, real application components through `app/_dev/v3-checkout.tsx`. **Real checkout was not opened** — no
PaymentIntent was created or reused.

**Image:** `comparisons/checkout_states.png` — 5 states × both appearances.

**The page's guard is correct:** `if (!IS_SANDBOX_BUILD && !__DEV__) return <Redirect href="/" />`.

---

## 1 · Coverage — the page shows **4 of the 11** pay-control outcomes, not 11

`STATES` in the page has **five** fixtures — `preparing`, `ready`, `auction`, `unconfirmed`, `failed` —
and across them only **four distinct pay-control outcomes** actually render:

| Rendered | CTA label observed |
|---|---|
| preparing | `Preparing…` |
| ready / auction | `Pay $99.00` |
| unconfirmed | `Checking your payment` |
| failed | `Try again` |

`src/lib/checkout/payControl.ts` has **11 return branches**. **Seven are not reachable from this page:**
`Finalizing your order` · `Confirming payment` · `Authenticating` · `Setting up payment` · `Check again` ·
`Back to listing` · `Checking your hold` · `Payment unavailable`.

**So a visual review through this page cannot establish those seven.** Either the page gains a fixture per
pay-control outcome, or those seven stay explicitly uncovered. **I am not claiming them either way.**

## 2 · Correct, and worth keeping

- Both appearances resolve properly; Light is a real light surface with dark ink.
- CTAs carry the chrome radius.
- **`Pay $99.00` names the amount on the control that moves it** — the settled rule — and no other total is
  repeated nearby.
- `auction` correctly drops the hold line and labels the figure **Winning bid**, not "Tickets".
- `unconfirmed` is the money-truth wording done well: *"Your last attempt may or may not have gone through.
  Please don't pay again. We'll keep checking; you can also check now."* It claims nothing it cannot support.
- The amber `HELD FOR YOU · 7:12 · UNTIL 7:34 PM` line reads clearly in both appearances.

## 3 · One finding — a status carried by a disabled control

In `preparing` and `unconfirmed` the CTA is `disabled: true, loading: true`, so `Button` applies
`opacity: 0.4`. In **Light** the result is pale-on-pale: the labels **"Preparing…"** and **"Checking your
payment"** are the *only* statement of what the app is doing, and they are rendered through an inactive
control at 40 % opacity.

**This is the same class as the listing-CTA finding** (state words carried by a disabled control). WCAG
exempts inactive components, so this is **not a contrast violation** — it is an information one: the
sentence the user needs is the faintest thing on the screen.

**Suggested fix, consistent with the earlier one:** keep the disabled treatment on the control, and state
the status in the **body** at full strength — `preparing` already has "Preparing your total" there, so the
pattern exists; `unconfirmed` has its panel. The CTA can then simply be disabled without carrying the news.

## 4 · Still outstanding from me

**Send transfer** — seller-side; my session is the DV buyer, so I will capture it through C's
`?screen=send` harness and label it **harness-rendered, not real data**. **Avatar** — open until the
returned derivative measures square and the same photo matches on Profile and the dock.

**Dock icons are already settled** (`V3_DECISIONS_AND_REVIEW_0677c80e.md` §4, image
`comparisons/dock_icons.png`): the approved references are **outline**; the app is **filled**; **Bids**
should be a bar chart, not a price tag; **Sell** a bare plus, not a plus in a filled circle.
