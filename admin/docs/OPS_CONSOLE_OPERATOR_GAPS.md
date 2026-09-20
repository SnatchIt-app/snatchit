# The operator workflow: what the console can do, and what it still cannot (D, 2026-09-20)

**Owner's instruction (2026-09-20):** "finish or explicitly identify the separate console implementation needed for
classification, obligation resolution and alert acknowledgement. **Do not describe database RPC availability as a
completed operator workflow.**"

This note is the record of that. Section 1 is what was missing, section 2 is what this branch builds, section 3 is
what is *still* missing — including the things that no amount of console code can fix.

Branch `admin/refund-classification-console`, based on `admin/operating-console`. Nothing merged, nothing deployed.

## 1. What was missing (measured, not assumed)

A repo-wide search over **all 519 refs**, unscoped by path, for `case_refund_classify`, `case_refund_obligation`,
`alert_ack` and `dispatch_alerts` returned 37 files — every one of them under `supabase/` or `docs/operations/`.
**Zero hits under `admin/`, `web/`, `app/`, `src/`, `components/`, `packages/` or `venue/`, on any branch.** A
control search for `execute_action` in the same shape does return console code, so the search would have found a hit
had there been one.

So before this branch:

| An operator wanted to… | Could they? |
|---|---|
| See that a refund case needs classifying | No. The case detail page showed the generic panels only. |
| Record classification A, B or C | **No control existed anywhere.** |
| Record what happened to an obligation | No control existed anywhere. |
| Close a refund case | The `case_status` form was there, but migration 144 refuses the close until a classification and every obligation are recorded — so the only outcome available to an operator was a rejection they had no way to satisfy. |
| See whether an alert had reached anyone | No. `ops.job_health` emits the delivery columns (it uses `to_jsonb`), but the console's parser dropped all of them. |
| Acknowledge an alert | No control existed anywhere. |

That last row is the one the owner's instruction is really about: `ops.alert_ack` has been granted to `authenticated`
and gated by `ops.assert_reader()` since 146 — the DB side is callable by the console's exact auth shape — and
nothing called it. **A callable RPC is not an operator workflow.**

## 2. What this branch builds

One new module, two new controls on the case page, one new control on the system page. It follows the console's
existing pattern exactly: server components, `callOps` → `ops.<fn>` with the operator's own JWT, `requireOperator()`
(role + aal2) first in every page, `ConfirmForm` with an idempotency key, a mandatory reason, the rendered version as
`expected` for optimistic concurrency, and an outcome that is the server's answer and never an optimistic "done".

**`src/lib/refund-resolution.ts`** — reads the case event log the way 144's close guard reads it: the latest
`classified` event wins, the latest `obligation_changed` per kind wins, and a case is closable only with a
classification recorded and nothing unsettled. This is a *mirror*, deliberately one-directional: it authorises
nothing. If it ever disagreed with the database, the database still refuses the close and the rejection is shown
verbatim — the worst case is a stale panel, never a case closed over money still owed.

**Case detail (`/cases/[id]`), refund-resolution cases only:**
- a **Refund resolution** panel — the classification and what Stripe showed, every obligation with settled/outstanding
  and its note, and, when the case cannot be closed, the reason in the database's own words;
- a **Classify** control (A / B / C, the owner to carry any obligation, a mandatory reason);
- a **Record an obligation** control, shown only when an obligation has actually been raised, because the dispatcher
  refuses a kind that was never raised;
- a line on the existing Status control warning that resolve/dismiss will be refused, *before* the operator tries.

**System page (`/system`), Alerts panel:**
- per alert, what actually happened — acknowledged (by whom, when), delivered (with the HTTP status), queued but
  **not** confirmed, not delivered after N attempts with the last error, or "nobody has been notified";
- an incident marker when the condition cleared and came back, so a recurrence is not read as the one already dealt
  with;
- an **Acknowledge** control, with an optional note that goes to the audit log;
- a standing note that nothing is scheduled to send these alerts.

**Evidence:** typecheck, lint, `npm test` 109/109 across 16 files, and a production build of all 19 routes with CI's
placeholder env. The new derivation has 11 tests of its own and **4 negative controls**, each failing a different
set: an unclassified case treated as closable (3 tests fail), unsettled obligations ignored (3), the earliest
obligation record winning instead of the latest (2), and the text form of `settled` unrecognised (1).

## 3. What is STILL missing — read this before calling the workflow done

1. **Nothing is applied anywhere.** Migrations 144 and 146 exist on feature branches and have been applied to no
   database. Every control above will fail with `PGRST202` (function not found) until an owner applies them. The
   console handles that class of failure (`ops-errors.ts` flags it `unavailable`), so it degrades honestly rather
   than crashing — but it does not work.
2. **These controls have not been exercised against a live database.** They are verified by typecheck, lint, unit
   tests with negative controls, and a production build. They have **not** been clicked through, because no
   environment has 144/146 applied and applying one is not authorised. Treat section 2 as *built and statically
   verified*, not as *proven in use*.
3. **No alert reaches a person unless an owner does two separate things** — turn `alert_delivery_enabled` on *and*
   schedule a caller for `ops.dispatch_alerts`. 146 schedules nothing. Until the second of those, the Acknowledge
   button records that someone saw an alert *they found by opening this page*.
4. **Recovered alerts are invisible.** `ops.job_health` selects only `state = 'firing'`, so once a condition clears
   the incident leaves the console entirely. The acknowledgement survives in `ops.audit`; the delivery record does
   not survive a recurrence at all (146 clears it, by design). There is no alert detail view and no alert history —
   a durable per-incident delivery history would need its own table, which was deliberately not built.
5. **No aggregate view of undelivered alerts.** An operator can see delivery state per alert, but nothing on the
   dashboard says "N firing alerts have never been delivered". That is a tile and a `job_health` field away.
6. **The obligation control records a human decision; it moves no money.** Recording `payout_owed` settled does not
   pay anyone — F-PAYOUT-PARTIAL-1 remains: nothing in the platform releases a partial payout. The same is true of
   `remainder_refund_owed`. The console is a book of record here, and the text says so.
7. **Not attempted, and out of D's lane:** the `notify-report` edge function is not deployed with its `ops_alert`
   branch, so even with everything switched on a post is answered 200 with no delivery count — which 146 correctly
   records as *not* delivered.
