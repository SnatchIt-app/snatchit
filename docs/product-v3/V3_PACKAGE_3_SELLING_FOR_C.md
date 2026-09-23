# V3 Package 3 — selling, listing creation/editing and listing management

**B → C · 2026-09-22.** Read against release source `5b255838`; `CreateListingScreen.tsx`,
`app/listing/edit/[id].tsx`, `app/my-listings.tsx` and `app/settings/payout-setup.tsx` are **byte-identical**
between that commit and the inventory baseline, so every string below is current.

**Artifacts:** `pkg3-create-{clean,annotated}.png` · `pkg3-create-invalid.png` ·
`pkg3-my-listings-{clean,annotated}.png` · `pkg3-my-listings-empty.png` · `pkg3-selling-dialogs.png`.

One listing runs through every screen: **Neon Choir, 2 × GA, $90.00 ask → buyer pays $99.00, seller receives
$81.00** (10% buyer fee + 10% seller fee, `src/lib/money.ts`).

---

## 1 · Create listing

**A scroll strip, not a viewport.** The form is ~1,320pt tall on a 844pt screen, so the board renders the whole
thing with a dashed rule marking where the viewport ends. **That rule is an annotation. It is not a claim that
all of this is visible at once.**

**Structure is the shipped structure:** one page, five sections — Event · Ticket · Selling method · Photos ·
Confirm. **No wizard, no steps, no progress bar, no draft saving**, because the app has none of those.

| Section | Contents |
|---|---|
| Event | Event name, Venue, Neighborhood (sheet), Date (sheet), Time (sheet) |
| Ticket | Ticket type GA/VIP, Quantity (min 1, **no maximum**), Transfer method, Ticket platform (**16 options**), Restrictions (optional) |
| Selling method | the shipped blurb, Starting bid, Buy Now toggle + price, Auction duration `1h/3h/6h/12h/1d/2d` |
| Photos | **exactly two** — one 16:9 cover and one private proof to `proof-docs`. Max 10 MB; JPEG/PNG/WebP/HEIC |
| Confirm | *"I confirm I own these tickets and will transfer them within 24 hours of sale."* |

**Money is shown from the seller's side, once:** *"You get $81.00 · Buyers pay $99.00 total"*, with the sticky
bar repeating **"You get for 2 tickets · $81.00 · after the seller fee"** — the figure actually being decided.
The review card (Event · Tickets · Selling · Buyer pays · You receive) appears **only when the form is valid**,
so it is never a preview of something that cannot be listed.

### Validation — `pkg3-create-invalid.png`

Nothing is red until the seller has submitted once (the shipped `submitted` gate). Then:

- every failing field is marked **in place**, keeping its label — the label never becomes the placeholder;
- a chip group cannot carry an inline rule, so its error sits under the group;
- **no failure is communicated by colour alone** — each has a sentence;
- one summary at the action: *"Fix the highlighted fields before listing."*
- the action pluralises truthfully: **"List tickets"** for 2, **"List ticket"** for 1.

**Green is not used for an upload.** "Image added" is secondary ink — green stays reserved for confirmed
payment and completed money states.

### Keyboard

Text fields are Event name, Venue, Starting bid and Buy Now price; everything else opens a sheet or is a chip,
so the keyboard appears only for those four. The sticky bar must ride above the keyboard, and the focused field
must stay visible — the shipped `KeyboardAvoidingView` pattern already used on the transfer screens.

---

## 2 · My listings

Five filters — **All / Active / Send tickets / Sold / Ended** — each with **its own empty sentence**, because
"nothing here" means something different in each. **Only the All empty offers an action** (*Create a listing*);
a filtered empty offers nothing to press, because clearing the filter is the fix and the chips are directly
above.

Six statuses, each carried by a **word**: Active · Ending soon · Ended · Reserved · Sold · Cancelled. A
cancelled row stays legible at reduced opacity — a seller needs to see what they cancelled.

**Row routing is unchanged:** a sold listing with a pending transfer opens Send transfer; everything else opens
the listing.

Loading is four skeleton rows; offline and error use `ScreenState` with auto-retry on reconnect.

---

## 3 · Every dialog, sheet and gate — `pkg3-selling-dialogs.png`

**22 dialogs** across Create, My listings and Edit, with the shipped copy verbatim. Rules they follow:

- the destructive choice is **`status.error` text, never a filled red block**, and never the rightmost default;
- the safe choice keeps its own words — *"Keep listing"*, *"Keep editing"* — so a tap is a decision, not a dismissal;
- **a gate offers the route that clears it**: Verify phone · Set Up Now · Open Settings. A gate with no exit is a dead end;
- copy is the shipped string, styled as the OS dialog. **Selling has no toast**: the only animated notice in the app is `OutbidToast`, which belongs to listing detail (see `pkg6-system-surfaces.png`).

**The picker sheet's missing state is designed and marked PROPOSED.** Today a non-matching search renders an
empty scroll view in both Create pickers (**F-5**). The design reuses the shipped `noMatch` state rather than
inventing one, and offers the escape the platform list already has.

---

## 4 · Payout setup, return and refresh

Three status views, all shipped copy: **Set up payouts** (not connected) · **Complete payout setup**
(onboarding incomplete) · **Payouts connected**. Plus *Refresh status* while not connected, and the footnote
*"Your banking details are never stored on our servers."*

The status probe has a **6-second timeout and never regresses on a blip** — on error or unknown it keeps the
current value. **Preserve that**: a transient failure must not tell a connected seller they are not connected.

`/payout-return` is the success landing; `/payout-refresh` is **the one true "expired" state in this flow** —
an onboarding link that expired or did not finish.

**Cancellation has no UI today (F-6)** — backing out of the Stripe sheet shows nothing. Designing that is a
functional change, so it is listed as a finding, not drawn here.

---

## 5 · Implementation criteria

1. Create keeps one page and five sections; no wizard, no progress indicator, no draft saving is introduced.
2. Validation appears only after the first submit; every failure has a sentence; the summary sits at the action.
3. Both fee sides appear once, from the seller's perspective, and the sticky bar carries the seller's net.
4. The review card renders only when the form is valid.
5. Exactly two images; the shipped size and type limits and the eight classified upload error strings are unchanged.
6. The commitment checkbox is required and its sentence is unchanged.
7. Five filters, five distinct empty states, action only on All.
8. Six status words; a cancelled row is dimmed but readable; row routing unchanged.
9. Destructive dialogs use error-coloured text, never a filled block; the safe option is named, not "Cancel", where the shipped copy names it.
10. The payout status probe still never regresses on a timeout.
11. Verified at the largest supported text size, at the narrowest width, with a 66-character event name, and with a missing cover image.
12. `typecheck` · `lint` · `test` green; real screenshots beside the boards.

## 6 · Findings that touch this flow — not redesign work

**F-1** Edit can hang on a permanent spinner · **F-2** Edit offers 6 platforms where Create offers 16 ·
**F-3** a transient RPC failure shows an account-reputation warning · **F-4** signed-out publish is silent ·
**F-5** no no-results state in either picker · **F-6** Stripe cancellation has no UI · **F-7** two different
banned-content messages · **F-8** no offline detection on Create or payout-setup.

All are ① present in the release source. **C validates; none are fixed by this package.**
