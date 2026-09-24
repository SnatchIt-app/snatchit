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
| Buy Now reservation | Refused likewise, with **`BLOCKED_PARTY`** | `reserve_buy_now` (SQL) |
| Buy Now payment | Refused likewise (defence in depth): an error code `BLOCKED_PARTY` | `create-payment-intent`, buy_now mode only |
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
- Rationale: a block must never strand money or tickets, or leave an order with no way forward.

### 2d. Where enforcement belongs

- **Server (A implements; migration 152, owner-gated):**
  - the helper;
  - the `bids` trigger, `reserve_buy_now` and the `create-payment-intent` check, all returning `BLOCKED_PARTY`;
  - a **feed read that carries the hide**: a `security_invoker` view (e.g. `public.listings_feed`) filtering
    `NOT users_blocked(auth.uid(), seller_id)`. The browse surfaces and listing detail read it; order screens keep
    reading `listings` directly, so existing orders are untouched (2c);
  - **no RLS hiding on `listings` itself**, for the same reason;
  - an index on `user_blocks (blocked_id, blocker_id)`, since 0230 indexes `blocker_id` only (:83).
  - **`user_blocks` RLS stays owner-only** (0230:88-92). Letting a client read rows where it is the blocked party would
    reveal who blocked it.
- **App (C):**
  - read the feed view;
  - the unavailable-listing state;
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
