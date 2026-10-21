# The operator workflow: what the console can do, and what it still cannot

**Origin.** D wrote this on 2026-09-20 for PR #89 (`admin/refund-classification-console` @ `3dab1614`, based on
`admin/operating-console`). **This copy is the port of #89 onto console v2** (`admin/console-v2-integration`,
2026-10-21). #89 stays unmerged and is the review surface for the behaviour. Sections 1 and 3 keep #89's findings,
corrected where they had gone stale. Section 2 says where each piece lives in v2.

**Owner's instruction (2026-09-20):** "finish or explicitly identify the separate console implementation needed for
classification, obligation resolution and alert acknowledgement. **Do not describe database RPC availability as a
completed operator workflow.**"

Nothing here is deployed. The port is two local commits on the integration branch: not pushed, no PR, no CI run.

## 1. What was missing (#89's measurement, 2026-09-20)

A repo-wide search over **all 519 refs**, unscoped by path, for `case_refund_classify`, `case_refund_obligation`,
`alert_ack` and `dispatch_alerts` returned 37 files, all of them under `supabase/` or `docs/operations/`. There
were **no hits under `admin/`, `web/`, `app/`, `src/`, `components/`, `packages/` or `venue/`, on any branch.** A
control search for `execute_action` in the same shape does return console code, so the search would have found a
hit if there had been one.

So before #89:

| An operator wanted to… | Could they? |
|---|---|
| See that a refund case needs classifying | No. The case detail page showed the generic panels only. |
| Record classification A, B or C | **No control existed anywhere.** |
| Record what happened to an obligation | No control existed anywhere. |
| Close a refund case | The `case_status` form existed, but migration 144 refuses the close until a classification and every obligation are recorded. The only outcome an operator could reach was a rejection they had no way to satisfy. |
| See whether an alert had reached anyone | No. `ops.job_health` emits the delivery columns (it uses `to_jsonb`), but the console's parser dropped all of them. |
| Acknowledge an alert | No control existed anywhere. |

`ops.alert_ack` is granted to `authenticated` and gated by `ops.assert_reader()` (146), so the console's exact auth
shape can call it, and nothing did. **A callable RPC is not an operator workflow.**

## 2. What the port builds, and where it lives in v2

The port follows v2's patterns. Pages are server components and call `callOps` → `ops.<fn>` with the operator's own
JWT. `requireOperator()` (role + aal2) runs first on every page. Case changes go through `ConfirmForm` inside an
`OutcomeHost`, with a fresh idempotency key, the audit reason, and the rendered version as `expected`. The outcome
shown is always the server's answer.

**`src/lib/refund-resolution.ts`** (#89's module). It reads the case event log the way 144's close guard does: the
latest `classified` event wins, and the latest `obligation_changed` per kind wins. A case is closable only when a
classification is recorded and nothing is unsettled. `ops.case_detail` (116) returns events oldest first and does
not limit them, so "last in the list" is 144's `order by created_at desc limit 1`. This is a mirror and it
authorises nothing. If it disagreed with the database, the database would still refuse and the rejection would be
shown verbatim. The worst case is a stale panel, never a case closed over money still owed.

**Cases.** v2 moved every case form into `src/components/cases/CaseWork.tsx`, which both the split view's pane
(`/cases?open=…`) and the full page (`/cases/[id]`) render. #89's panels therefore sit there and not in the page.
For `refund_resolution` cases only:
- **`CaseRefundResolution`** shows the classification as recorded (with what Stripe showed), each obligation as
  *Recorded settled* or *Unsettled* with its note, and, while the case is open, the close refusal in the database's
  own words. The full page shows it as a panel and the pane as a section.
- **Classify** (`case_refund_classify`). Open cases only. A / B / C, the owner for any obligation, and a mandatory
  reason ("What the Stripe Dashboard shows").
- **Obligation** (`case_refund_obligation`). Shown only once an obligation has been raised, because the dispatcher
  refuses a kind that was never raised. It offers exactly the raised kinds. The note is required and doubles as the
  audit reason.
- The existing **Status** control warns that resolve/dismiss will be refused, *before* the operator tries.

**System (`/system`), Alerts.** `src/components/system/AlertList.tsx` (new) and `AlertAckForm.tsx`:
- Per alert, two separate facts:
  - **Acknowledged:** by whom and when.
  - **Delivery:**
    - *Delivery confirmed* (with the HTTP status): notify-report reported a delivery, which is not proof anyone read it.
    - *Queued*: pg_net accepted the post. Not confirmed delivered.
    - *Not delivered after N attempts*, with the last error. At 146's limit of 5, the dispatcher no longer posts it.
    - *Not sent: no delivery attempt is recorded*, with 146's error when it recorded one without an attempt (for
      example, Vault `project_url` not configured).
- An incident marker when the condition cleared and came back.
- An **Acknowledge** disclosure (`ops.alert_ack(p_alert_key, p_note)`) with an optional note that goes to the audit
  log. 146's own refusals (P0002 *no alert*, P0001 *nothing to acknowledge*) show as "Not acknowledged" in its words.
  Any other error is shown the generic way, with the database's message and code.
- A standing note: 146 sends nothing by itself, and turning delivery on and scheduling a caller are both owner
  decisions.

**Nothing is enabled by this port.** `refund_resolution_detector_enabled` and `alert_delivery_enabled` stay owner
decisions. Their setting help says so and tells nobody to switch them on, and the port changes no setting.

**Checked against the gate branch** (`release/production-gate-20260918`):
- Migration 144's `execute_action` allow-list names both action types.
- The case arms of 144's `action_dispatch` and of `20261013000000` (the latest redefinition) are byte-identical.
- The params the dispatcher reads (`classification`, `assignee`, `kind`, `settled`, `note`) are the ones the forms
  post.
- `ops.alert_ack(text, text default null)` returns `acknowledged_at` and `incident_seq`.
- `action_allowed_roles` gives `case_*` to admin, risk and support.

**Evidence (targeted only; the shared machine slot was held):**
- vitest on the touched files only. #89's 11 derivation tests and its labels and payload-guard additions, plus
  `refund-case-work.test.ts` (13: which forms render where, and what each posts through the real `submitActionForm`
  path) and `alert-ack.test.ts` (18).
- #89's **4 negative controls**, re-planted on the ported module. Each fails the same number of tests as in #89:
  - an unclassified case treated as closable: 3;
  - unsettled obligations ignored: 3;
  - the earliest obligation record winning over the latest: 2;
  - the text form of `settled` unrecognised: 1.
- 31 further planted mutants in the port's own wiring and wording, all caught.
- eslint on the changed files.
- **Not run here:** full typecheck, full test suite, lint across the project and `next build` (see the handoff's
  gates owed).

## 3. What is STILL missing: read this before calling the workflow done

1. **Applied state is not read here.** #89 recorded on 2026-09-20 that 144 and 146 were applied to no database, and
   so does `docs/operations/OPS_ALERT_ROLLOUT_PREREQUISITES.md` on the gate branch (2026-09-21). The brief for this
   port describes both as applied in production. This branch read no production database to confirm
   that, and no production read is authorised. Wherever they are missing, `ops.alert_ack` comes back as `RPC
   ops.alert_ack not available yet` (PGRST202 → `unavailable`), and `execute_action` refuses the two case types
   with its own message. The console degrades honestly rather than crashing.
2. **These controls have not been exercised against a database.** They are verified by unit tests with negative
   controls and by reading the migrations. They have not been clicked through, either on #89 or on the port. The
   local replay that will exercise them is a later step:
   - classify A (no obligation), B (raises `payout_owed`) and C (raises `remainder_refund_owed`);
   - the assignee refusal when nobody is named;
   - record an obligation settled, and then outstanding again;
   - resolve refused (unclassified, then with an unsettled obligation), then allowed once everything is recorded
     settled, with the `[class]` prefix on the resolution note;
   - `alert_ack` on a firing alert, the two refusals (unknown key; recovered alert), and a recurrence opening
     incident #2 with its own acknowledgement.

   Treat section 2 as *built and statically verified*, not as *proven in use*.
3. **No alert reaches a person unless an owner makes two separate decisions:** turn `alert_delivery_enabled` on,
   *and* schedule a caller for `ops.dispatch_alerts`. 146 schedules nothing, and other prerequisites also apply
   (`OPS_ALERT_ROLLOUT_PREREQUISITES.md` §2). Until then, the Acknowledge button records that someone saw an alert
   *they found by opening this page*.
4. **Recovered alerts are invisible.** `ops.job_health` selects only `state = 'firing'`, so once a condition clears
   the incident leaves the console entirely. The acknowledgement survives in `ops.audit`. The delivery record does
   not survive a recurrence at all (146 clears it, by design). There is no alert detail view and no alert history.
   A durable per-incident delivery history would need its own table, which was deliberately not built.
5. **No aggregate view of undelivered alerts.** An operator can see the delivery state of each alert, but nothing on
   the dashboard says "N firing alerts have never been delivered". That needs a tile and a `job_health` field.
6. **The obligation control records a human decision. It moves no money.** Recording `payout_owed` settled does not
   pay anyone, and F-PAYOUT-PARTIAL-1 remains: nothing in the platform releases a partial payout. The same is true
   of `remainder_refund_owed`. The console is a book of record here, and its text says so.
7. **Re-acknowledging overwrites the alert row.** `ops.alert_ack` does not refuse an alert that is already
   acknowledged. It re-stamps `acknowledged_at` and `acknowledged_by` on the row, so if two tabs or two operators
   acknowledge the same alert, the row keeps only the second. `ops.audit` keeps both. The console hides the button
   once the row is acknowledged, but a stale tab can still send it. Changing this is a server rule (A).
8. **Not attempted, and outside D's area:** #89 recorded that the `notify-report` edge function's `ops_alert` branch
   was not deployed (not re-checked here). While that holds, even with everything switched on a post is answered
   200 with no delivery count, which 146 correctly records as *not* delivered.
