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
1. **Merges and the sandbox build.** A merge of #78 and #79 into `release/production-gate-20260918` (the merge recommendation), then **one sandbox preview build** (EAS profile `sandbox`, `pk_test_` publishable key per `eas.json`) from the resulting gate commit. That commit becomes the source of truth. Alternatively, build from #79's head before merging; A then verifies the merged tree is byte-identical to the built one.
2. **The sandbox window:** the precondition reads (§3), the fixture writes (§4), the handset session (§5), the after-reads (§6).
3. **Clean-up (§7).** Optional; a separate decision.
4. **H5b only** (optional, §5): it lets the sandbox create a Stripe **test-mode** PaymentIntent and a sandbox `pending` payment row. It is not a charge. Default: not run.

## 3. Precondition reads (read-only, sandbox only; D witnesses)
| # | Read | Expect / use |
|---|---|---|
| P1 | `select data_type, is_nullable, column_default from information_schema.columns where table_schema='public' and table_name='payments' and column_name='amount_refunded_cents'` | `integer`, `YES`, NULL. Records only *infer* that `20260906120000` is present on the sandbox (readiness plan §2). **If the column is absent, STOP**: the build's checkout reads would fail, and the fix would show the payment-status message on every checkout. |
| P2 | Non-internal triggers on `public.payments` and `public.listings` (name, timing, events) | Confirms the §4 SQL: the payment guard is BEFORE UPDATE only, and the listing guard needs `app.bypass_listing_guard` to set a hold |
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
The expected copy is the final wording at the head that is built. C confirms the exact strings from that commit before the session; the lines below match `df3572a1`/`eba8b208` except the payment-status line, which the final commit rewords.

| Step | Action | Expected | Stop if |
|---|---|---|---|
| H1 | Online. Open listing **F1** → "Finish checkout" | Kicker "Refund"; title "Refund recorded"; body "A refund was recorded for this payment. We can't confirm the refunded amount here."; one button **"Back to home"**. No amount, no Pay, no Tickets line. Tap it → the Home tab | Any Pay control, amount, "No purchase was made", "in progress" or "cancel" |
| H2 | From F1's refund screen, use the **back gesture** (kept by the owner) | Returns to the listing. "Finish checkout" again → the same refund screen; still no Pay | A Pay control, or a checkout that sets up payment |
| H3 | Listing **F2** → "Finish checkout" | "Partial refund recorded" / "A partial refund of $50 was recorded for this payment."; "Back to home" | Any other amount, or "order stands" |
| H4 | Listing **F3** → "Finish checkout" | "Full refund recorded" / "A full refund of $110 was recorded for this payment."; "Back to home" | "No purchase was made" |
| H5 | Open listing **F4** online (it shows "Finish checkout"). Turn on **Airplane Mode with Wi-Fi off**, then tap "Finish checkout". Tap "Check again" once, **still offline** | The payment-status message (final wording) and one control, **"Check again"**. After tapping it offline: the same state | A Pay button; "hold ran out", "no longer held" or "Nothing was charged"; any refund screen |
| H5b *(optional, separate OK)* | Airplane Mode off → "Check again" | Normal checkout for an unpaid buyer with a live hold: summary plus the Pay control. **Do not tap Pay.** Creates one Stripe **test-mode** PaymentIntent and possibly a sandbox `pending` payment row | Any error screen |

End the session by closing the app. No other screens.

## 6. After-reads (read-only; D witnesses)
- The fixture payments are unchanged: status, `refunded_at` and amount as inserted.
- No new `payments` row for the buyer on F1–F4, unless H5b was run; then exactly one `pending` row on F4.
- No new notifications for the buyer or seller since the fixture write.
- Recorded in `SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md` §19, at READ / owner-reported strength.

## 7. Clean-up (separate decision; proposed)
- Release the fixture holds: `update public.listings set reserved_until = now() … where event_name like 'HANDSET-FINAL F%'`, with the listing-guard bypass.
- Leave the tagged rows as audit evidence. Deleting them is a further write, and `refunded` payment rows are terminal by design.
- If H5b ran, its test-mode PaymentIntent expires unused, and its `pending` row is left for the normal sweep. A reads it back.
