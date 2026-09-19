# Focused sandbox handset check — final checkout changes (A, prepared 2026-09-19)

**Status: PREPARED ONLY.** Nothing here has been run. No build, sandbox read, fixture write or handset step is authorized yet.

**Owner's instruction:** "one focused sandbox handset check of the final checkout changes before production release, with synthetic fixtures and no real charges … without repeating the completed Build 20/21 pass."

**Environment:** sandbox `ofaidukbieeekqaboscm` only. Production (`hqycwntpfoztoinemqns`) is never touched. The standing sandbox restrictions hold: no access to the D1/D2 proof files, and no L7.

**Roles:**
- **A** runs the reads and fixture writes;
- **D** witnesses the reads and reviews the fixture SQL before it runs;
- **C** guides the handset steps;
- **the owner** operates the phone.

Evidence is text: the owner reports what the screen shows. There are no screenshots unless the owner chooses to take them.

## 1. What this check covers, and what it deliberately does not

**Covered: the changes since Build 21, on a real device.**

| Change | PR | Device step |
|---|---|---|
| Refund screen for a refund whose amount is unknown (production's only shape today) | #78 | H1 |
| The back gesture from the refund screen (kept by the owner) | #78 | H2 |
| Partial and full refund screens, stating the recorded amount | #78 | H3, H4 |
| "Back to home" as the only control on every refund screen | #78 | H1, H3, H4 |
| The payment lookup failing (device offline) → the payment-status message plus "Check again", with no Pay | #79 | H5 |

**Not repeated:** everything in the Build 20/21 passes (S8only, the receipt dialog, avatars, sign-out and notices, the send/receive screens).

**Not testable on a device; covered by the local end-to-end rehearsal and unit tests only** (go/no-go §12.4, §12.11):
- the re-validation *reservation* lookup failing while the payment lookup succeeds, because a phone cannot fail one request selectively;
- a 42703 missing-column error (the sandbox already has the column), and a non-list reply;
- the deployed webhook turning a partial refund into a `refunded` row, which would need Stripe events;
- a buyer with two payment rows on the same listing.

## 2. Authorizations required, each separate
1. **The sandbox build.** One device build with **EAS `--profile preview`**. At `d75c15cc` that profile has internal distribution, `ios.autoIncrement`, the sandbox Supabase URL and a `pk_test_` publishable key; Build 16 used the same profile. *(Corrected per D: the `sandbox` profile is `ios.simulator: true`, a simulator build that cannot install on the handset.)*
   - **Built commit:** the tree that will merge. That is **`d75c15cc`** (#80's head, containing #78 and #79), or the release-gate commit after #78 → #79 → #80 merge. The merge rehearsal (go/no-go §12.12) shows the merged tree equals `d75c15cc` plus three `supabase/` files for 142, so the app bytes are identical. A records the exact built commit and verifies that `git diff <built> <gate head> -- . ':(exclude)supabase'` is empty. *(Corrected per D: the first draft named only #78 and #79, which would have left out the reservation-lookup fix.)*
   - The reservation-lookup fix (#80) is in the build but is **not exercised on the device**, because a listings-only failure cannot be induced on a phone. Its evidence stays source, test and E2E only (§1).
2. **The sandbox window:** the precondition reads (§3), the fixture writes (§4), the handset session (§5), the after-reads (§6).
3. **End-of-session step (§7), mandatory and part of the window.** It ends the four fixture listings before their 3-hour holds lapse. If the holds lapsed, `cleanup_expired_reservations` would return the listings to `active`, and four buy-now listings would be live in the sandbox marketplace for other testers (D). It runs even if the session is abandoned.
4. **H5b only** (optional, §5): it lets the sandbox create a Stripe **test-mode** PaymentIntent and a sandbox `pending` payment row. It is not a charge. Default: not run.

## 3. Precondition reads (read-only, sandbox only; D witnesses)
| # | Read | Expect / use |
|---|---|---|
| P1 | `select data_type, is_nullable, column_default from information_schema.columns where table_schema='public' and table_name='payments' and column_name='amount_refunded_cents'` | `integer`, `YES`, NULL. Records only *infer* that `20260906120000` is present on the sandbox (readiness plan §2). **If the column is absent, STOP**: the build's checkout reads would fail, and the fix would show the payment-status message on every checkout. |
| P2 | Non-internal triggers on `public.payments` and `public.listings`: name, **ROW or STATEMENT level**, timing, events | Confirms the §4 and §7 SQL: the payment guard is BEFORE UPDATE only; the listing guard needs `app.bypass_listing_guard`. A **statement-level** bypass reset on `listings` (like `trg_reset_transfer_guard_bypass` on transfers) would require the `set_config` to sit right before each guarded UPDATE, which it does. Locally (full chain) all 7 listings triggers are ROW-level (D) |
| P3 | The owner's sandbox **buyer** and **seller** user ids, resolved from the account emails the owner used in Build 20/21 (C supplies the emails) | Fills `:buyer` / `:seller` |
| P4 | `cron.job` rows whose command mentions `payments`, `listings`, `reservation` or `transfers` | Confirms no job acts on a `refunded` payment or a live hold within the window. `cleanup_expired_reservations` only releases **expired** holds; fixture holds last 3 h |
| P5 | `select count(*) from public.listings where event_name like 'HANDSET-FINAL%'` | 0 (no leftovers) |

## 4. Synthetic fixtures: one transaction, tagged, fake Stripe ids, no Stripe calls
- Four listings, all titled `HANDSET-FINAL F1..F4`, each **reserved by the buyer** for 3 h. The listing screen then shows **"Finish checkout"**, which opens checkout (`detailState.ts` `continue_reservation`).
- Three payment rows, all `total = 11000` ($110), all `status = 'refunded'`. Using `refunded` keeps every sweep away from them. The *succeeded*-row partial shape is covered by the local rehearsal (b4).
- The payment guard is BEFORE UPDATE only, so the rows are **inserted** in their final shapes.

```sql
-- D reviews before execution; A runs as postgres on the SANDBOX ref only; :buyer / :seller from P3.
begin;
insert into public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
   starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
select gen_random_uuid(), :'seller', 'HANDSET-FINAL ' || f, 'Handset Check Venue', 'wynwood', current_date + 30, '21:00', 'GA', 1,
       'mobile_transfer', 100, true, 100, 24, now() - interval '1 hour', now() + interval '1 day', 100,
       'fixtures/handset-final-no-object.jpg', 'active'   -- NOT NULL; no object at this path, so the app shows its image fallback
from unnest(array['F1','F2','F3','F4']) f;
select set_config('app.bypass_listing_guard', 'on', true);
update public.listings set status = 'reserved', reserved_by = :'buyer', reserved_until = now() + interval '3 hours'
 where event_name like 'HANDSET-FINAL F%';
insert into public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, paid_at, refunded_at, stripe_refund_id, amount_refunded_cents, stripe_livemode)
select l.id, :'buyer', :'seller', 10000, 1000, 1000, 11000, 'pi_handsetfinal_' || lower(right(l.event_name, 2)), 'refunded', 'buy_now',
       now() - interval '2 days', now() - interval '1 day', null,
       case right(l.event_name, 2) when 'F1' then null when 'F2' then 5000 when 'F3' then 11000 end, false
from public.listings l where l.event_name in ('HANDSET-FINAL F1','HANDSET-FINAL F2','HANDSET-FINAL F3');
select l.event_name, l.id, l.status, l.reserved_until > now() as live, p.status, p.amount_refunded_cents
  from public.listings l left join public.payments p on p.listing_id = l.id
 where l.event_name like 'HANDSET-FINAL F%' order by 1;
commit;
```

- **Prices are in dollars:** `buy_now_price 100` is $100, and the all-in price with the 10% buyer fee is $110 (`allInFromDollars`; checkout uses `dollarsToCents(price)`). That matches the payments' `amount 10000` / `total 11000` cents. *(D suggested 10000, which read the column as cents; verified otherwise, no change.)*
- **F1** (amount unknown, production's shape) → neutral screen.
- **F2** (5000 of 11000) → partial screen.
- **F3** (11000 = total) → full screen.
- **F4** (a live hold, no payment) → the offline step.
- No `stripe_refund_id`, and no Stripe object exists behind any `pi_handsetfinal_*` id.
- **Local dry run [REH], 2026-09-19.** The block above ran inside a rolled-back transaction on `a142_full_rehears` (the full chain, including `20260906*`, 132 and 142), with two throwaway users.
  - F1–F4 came back `reserved`, with live holds and refunded rows carrying NULL / 5000 / 11000.
  - 0 notifications were written; 0 rows were left after the rollback.
  - The first attempt caught `cover_image_path NOT NULL`, which is now fixed.
  - **Not proven for the sandbox itself:** its triggers and crons are unread until P2/P4.

## 5. Handset steps (C guides; the owner operates; the sandbox build from §2)
The expected copy is the wording at the **built commit** (`d75c15cc` unless §2.1 names another). C confirms each string from that commit before the session. The lines below are taken from `d75c15cc`.

| Step | Action | Expected | Stop if |
|---|---|---|---|
| H1 | Online. Open listing **F1** → "Finish checkout" | Kicker "Refund"; title "Refund recorded"; body "A refund was recorded for this payment. We can't confirm the refunded amount here."; one button **"Back to home"**. No amount, no Pay, no Tickets line. Tap it → the Home tab | Any Pay control, amount, "No purchase was made", "in progress" or "cancel" |
| H2 | From F1's refund screen, use the **back gesture** (kept by the owner) | Returns to the listing. "Finish checkout" again → the same refund screen; still no Pay | A Pay control, or a checkout that sets up payment |
| H3 | Listing **F2** → "Finish checkout" | "Partial refund recorded" / "A partial refund of $50 was recorded for this payment."; "Back to home" | Any other amount, or "order stands" |
| H4 | Listing **F3** → "Finish checkout" | "Full refund recorded" / "A full refund of $110 was recorded for this payment."; "Back to home" | "No purchase was made" |
| H5 | Open listing **F4** online (it shows "Finish checkout"). Turn on **Airplane Mode with Wi-Fi off**, then tap "Finish checkout". Tap "Check again" once, **still offline** | **"We couldn't check whether this has already been paid."** and one control, **"Check again"**. After tapping it offline: the same state | A Pay button; "hold ran out", "no longer held" or "Nothing was charged"; any refund screen |
| H5b *(optional, separate OK)* | Airplane Mode off → "Check again" | Normal checkout for an unpaid buyer with a live hold: summary plus the Pay control. **Do not tap Pay.** Creates one Stripe **test-mode** PaymentIntent and possibly a sandbox `pending` payment row | Any error screen |

End the session by closing the app. No other screens.

**Session amendment, 2026-09-19 (D found it; A verified at `3ff5712f`). Leaving a fixture listing's screen releases its hold.**
- `ListingDetailScreen`'s `beforeRemove` listener (`shouldReleaseReservation`, `reservationExit.ts`) calls `release_reservation` when a screen for a listing the buyer holds is removed.
- The current `release_reservation` (127) refuses only when a *succeeded* payment exists; refunded fixtures do not stop it. The listing returns to `active`, i.e. buyable.
- Hence:
  1. **Order:** do H2 (back gesture → the listing still shows "Finish checkout" → re-enter → the same refund screen) **before** tapping H1's "Back to home". After "Back to home", F1 may show "Buy now". That is still safe, because re-entering checkout shows the refund screen with no Pay.
  2. **§7 runs as soon as H5 is done, or as soon as the session is abandoned**, not near T+2h30m. A listing the buyer left is a live sandbox buy-now listing until §7. The T+2h30m timer stays only as a fallback.
  3. **§6:** a visited listing that reads `active` with no hold is the app's own release, not an anomaly. Any notification since T0 is checked against `release_reservation`, which the local dry run never exercised.
  4. H5 ends by closing the app, so F4's hold is not released; §7 ends it.
- **Baseline:** `after_check` also runs once straight after the fixture write, before H1. It prints each fixture payment's `refunded_at` and `md5(row)`, so "payments unchanged" is proven byte for byte (D's optional suggestion, adopted). Locally, the row md5s were identical before and after §7.

## 6. After-reads (read-only; D witnesses)
- The fixture payments are unchanged: status, `refunded_at` and amount as inserted.
- No new `payments` row for the buyer on F1–F4, unless H5b was run; then exactly one `pending` row on F4.
- No new notifications for the buyer or seller since the fixture write.
- Recorded in `SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md` §19, at READ / owner-reported strength.

## 7. End of session (mandatory; within the window and before the 3-hour holds lapse)
*(Corrected per D: the first draft only expired the holds, which would have let the cron put four buy-now listings live.)*
```sql
begin;
select set_config('app.bypass_listing_guard', 'on', true);
update public.listings set auction_status = 'cancelled', status = 'active', reserved_by = null, reserved_until = null, ended_at = now()
 where event_name like 'HANDSET-FINAL F%';
select event_name, status, auction_status, reserved_by is null as no_hold from public.listings where event_name like 'HANDSET-FINAL F%' order by 1;
commit;
```
- **Local dry run [REH], 2026-09-19** (fixtures plus this step, rolled back on `a142_full_rehears`): all four listings end as `active/cancelled` with no hold, and **0 notifications** are written. A `cancelled` listing is not buyable (`detailState.ts`).
- The tagged listings and payment rows stay as audit evidence. Deleting them is a further write, and `refunded` payment rows are terminal by design.
- If H5b ran, its test-mode PaymentIntent expires unused, and its `pending` row is left for the normal sweep. A reads it back in §6.
