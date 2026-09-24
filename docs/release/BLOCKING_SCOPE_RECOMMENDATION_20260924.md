# Blocking: scope recommendation (A, with C and E; 2026-09-24)

A has owned blocking since E handed it over (2026-09-24). Status: **a recommendation for the owner's decision.** C
implements the client half and A the server half; D verifies. Nothing here is built yet, except C's Home fix
(below).

## 1. What the block does today (source: app `65052bfc`, gate `037092f0`)

- **Who can be blocked:** a user can block **sellers only**, from a listing or a profile (`ListingDetailScreen.tsx:1020`,
  `profile/[id].tsx:163`). The block is **one-way**: only the blocker's own rows are ever read.
- **What the blocker stops seeing:**
  - The seller's listings in Explore/Search (`explore.tsx:169`).
  - The seller's listings in Home. Until C's fix these reappeared on every load because the block list read empty; C
    has fixed and tested it.
  - The seller's profile, which now shows a blocked notice.
- **Where it has no effect:** listing detail (from a link, push or profile), bid history, "bid received" pushes,
  checkout, orders, the Bids tab and the web app.
- **What the blocked user can still do:** see, bid on, buy from and report the blocker. **No server code reads
  `user_blocks`** (074:182; functions: 0 references).
- **What operators can do:** stop a user creating listings (119 trigger), and nothing more. Account suspension is
  refused as "not supported" (115:720).

**What can truthfully be said today:** "You can hide a seller's listings from your Home and Search." That is a hide
preference, not a block.

## 2. Recommended scope

**Principle.** A block is a safety control between two people. It hides the other person from each of them and stops
**new** contact and **new** transactions between them, in **both** directions. It never strands money or tickets
already committed.

### 2a. What a user can hide (both directions: whoever blocked whom)

| Surface | Behaviour |
|---|---|
| Home, Explore/Search, event sections, "more listings", and the web marketplace | The other person's listings don't appear. **This filter lives in the READ, on the server** (2d): a both-directions hide cannot be computed on the client |
| Listing detail reached directly (link, push, old tab) | "This listing isn't available to you." No bid, no Buy Now, no emphasis on the price panel; Report stays. **Only when I am the blocker** do I also see "You blocked this seller." with **Unblock** (my own list is the one thing I may read). The other direction is identical minus that line, so the two cases can't be told apart from the copy |
| Profile | A blocked notice; no listings or stats (exists today for the blocker) |
| Bid history on a listing | The other person's bids stay (amounts and order are the auction's facts). A user **I** blocked appears as "Blocked user". Bid rows are not navigable today and stay that way: making them link to profiles would expose bidders to every viewer, which is a product decision outside this scope |
| Push notifications | Nothing new can arrive, because new bids between the two are refused (2b) |

### 2b. New interactions and transactions refused (server-enforced, both directions)

| Interaction | Rule | Where |
|---|---|---|
| Place a bid | Refused if the bidder and the seller are blocked either way | a `BEFORE INSERT` trigger on `bids` raising **`BLOCKED_PARTY`**. It is a trigger rather than an RLS policy, because an RLS rejection arrives as a generic error the app would treat as an unknown outcome |
| Buy Now reservation | Refused likewise, with **`BLOCKED_PARTY`** | `reserve_buy_now` (SQL). **This is the single Buy Now gate.** A buy_now PaymentIntent already requires the buyer to hold the live reservation (create-payment-intent :664-673), so a separate payment-time check would only ever refuse a reservation taken *before* the block, which 2c exempts. There is therefore **no** `create-payment-intent` check |
| Report the other person | **Always allowed** | unchanged |

- `public.users_blocked(a, b)` is a `SECURITY DEFINER` helper that reads both directions without exposing any row or the
  direction. `BLOCKED_PARTY` says "refused, permanently, for this pair" and **never which way**. The app maps it to
  "This listing isn't available to you." with **no "Try again"**. Every other error stays on its unknown-outcome path
  (C, `a5c0bfc6`).
- **Bids placed before the block stand.** No money has moved, and removing a bid after the fact would change the
  auction's outcome for a third party. If such a bid wins, **settling that auction is exempt** (2c).

### 2c. What stays accessible (exempt from every block rule)

- **Any order that already exists** (a `transfers` row), for both people: seeing the order and its listing, sending
  and confirming tickets, reporting a problem, refunds, payouts, and support.
- **Settling an auction the blocked person had already won:** the winner's payment for that auction.
- **A checkout already in progress:** a live Buy Now reservation taken before the block. Checkout's listing reads
  (`CheckoutNative` :173 display, :235 setup) stay on `listings`. The display read never blocks or fails a payment,
  and the setup read fails closed, so either one going through the view would strand a legitimate order.
- Rationale: a block must never strand money or tickets, or leave an order with no way forward.

### 2d. Where enforcement belongs

- **Server (A implements; migration 152, owner-gated):**
  - the helper;
  - the `bids` trigger and `reserve_buy_now`, both returning `BLOCKED_PARTY`;
  - a **feed read that carries the hide**: a `security_invoker` view (e.g. `public.listings_feed`) filtering
    `NOT users_blocked(auth.uid(), seller_id)`. **The browse surfaces only** read it;
  - **listing detail keeps reading `listings`** and asks `public.listing_view_state(p_listing_id)` → `'ok' | 'blocked'
    | 'missing'` (`SECURITY DEFINER`; no direction, no listing content).
    - A row that is simply absent from a view can't be told apart from a deleted listing. Detail already maps a null
      row to "Listing not found · It may have been sold or taken down" (:1102-1111), which is false for a hidden
      listing.
    - Listing content is public anyway (`listings_select_all using (true)`, 070:43), so hiding on detail is a display
      rule and the refusal is the safety rule;
  - the order screens and checkout keep reading `listings` directly (2c);
  - **Do not add a payment-time block check** to `create-payment-intent`, for either mode. The paths are correct by
    construction:
    - **Buy Now:** a buy_now intent can't exist without the buyer's live reservation. The refusals run in order: sold,
      then not reserved, then reserved by another, then reservation expired (:659-674). `reserve_buy_now` is the only
      way to get a reservation, and it is gated.
    - **Auction:** a blocked user can't bid (the trigger), so can't become the winner. A block that lands between
      winning and paying is the "winning bid predates the block" exemption.
    - A payment-time check would therefore only ever refuse the exempt cases (C verified this at source, 2026-09-24).
  - **no RLS hiding on `listings` itself**, for the same reason;
  - an index on `user_blocks (blocked_id, blocker_id)`, since 0230 indexes `blocker_id` only (:83).
  - **`user_blocks` RLS stays owner-only** (0230:88-92). Letting a client read rows where it is the blocked party would
    reveal who blocked it.
- **App (C):**
  - read the feed view on the browse surfaces, and **remove `applyBlockedSellerFilter`** from Home and Explore once
    they do. The client list stays for Unblock and the optimistic hide;
  - the unavailable-listing state, keyed on `listing_view_state`: `blocked` shows the unavailable state, `missing` the
    existing not-found;
  - the "Blocked user" row;
  - block entry points on listing detail's overflow and the profile (which exist), plus **the two order screens**
    (`transfer/receive`, `transfer/send`), made safe by 2c;
  - the `BLOCKED_PARTY` refusal mapping;
  - an optimistic hide the moment the user blocks, before a refetch;
  - correcting `useBlockedUserIds`' header, which says direct-access screens stay untouched.
- **Web (web owner, not C):** switch the marketplace reads to the same view; the hide comes with it.

### 2e. Operator-level blocking (separate, recommended)

Apple 1.2 also speaks of blocking abusive users *from the service*. Today no mechanism exists. The recommendation is an
ops action `user_suspend` enforced at sign-in, via a Supabase Auth ban, and in RLS. This would be a separate package.

## 2f. C's review (2026-09-24), verified by A at source and adopted

- **The symmetric hide can't run on the client, and mustn't.** `user_blocks` RLS is owner-only (0230:88-92), and that
  is the property that stops the app leaking who blocked whom. So the hide moves into the read (2d).
- **Bid history has no navigation** (`BidActivity.tsx:51-55`: name or short id, no router), so no block entry point is
  added there.
- **The order screens were missing an entry point**; added.
- **Web isn't C's surface**; it inherits the view.
- **Refusals need a stable, direction-free code** (`BLOCKED_PARTY`), not a generic RLS error.
- The auction-settlement exemption lives entirely in the server predicate. The client never compares timestamps.
- **C's second review:**
  - A row hidden by a view reads as "not found". So listing detail uses `listing_view_state` and keeps reading
    `listings`.
  - Checkout's reads stay on `listings`: an in-progress reservation is exempt.
  - A's addition: since a payment requires the reservation, `reserve_buy_now` is the single Buy Now gate, and the
    payment-time check is dropped.

## 3. Effective behaviour after 2a–2d, and what A does not claim

- After the change: X blocks Y. Neither sees the other's listings in browsing. Neither can start a bid or purchase with
  the other. Existing orders between them work to completion, and either can report the other.
- **A does not claim Apple compliance.** Apple decides that. This section only states the behaviour the code would
  have.

## 4. Order of work

1. C's Home fix (landed).
2. The server package (A; migration number 152 reserved), after refund 150 and b2 151.
3. C's client half against the server contract.
4. D verifies both.
