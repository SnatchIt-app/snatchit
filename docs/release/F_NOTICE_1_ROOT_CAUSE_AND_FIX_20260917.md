# F-NOTICE-1 — stale "Account deletion requested" notice: root cause and the smallest safe fix (A, 2026-09-17)

**Nothing is applied or changed by this document.** The owner's instruction today: *"Investigate the underlying server path and prepare the smallest safe fix; do not alter the buyer's existing notice without a scoped plan."* §4 is that scoped plan, and it is not authorized.

## 1. The symptom
On Build 19 the DV buyer (`919d511e`) sees "Account deletion requested" while the account is ACTIVE with no pending deletion. A's read-only evidence, 2026-09-17: `kernel.identity_ext` deletion_state ACTIVE, `deletion_requested_at` null, 0 rows in `public.account_deletions`, and one `notify.notification` row `f3abe550…` of type `account_deletion_pending` dated 2026-09-14, unread and undismissed, with 2 pre-existing delivery rows.

## 2. Root cause — confirmed by reproduction, not by reading alone
`kernel.request_account_deletion` (077) emits `account_deletion_pending` to the outbox as its last write; `notify.drain_outbox` (092) turns that into a `notify.notification` row for the identity. `kernel.withdraw_account_deletion` (077:1824) sets `deletion_state='ACTIVE'`, clears `deletion_requested_at` and `deletion_block_reason` — and **does nothing about the notice already delivered**. It emits no withdrawal event and retires nothing.

**A's reproduction on a local replay** (rolled back; `scratchpad/line3/fnotice1_repro.sql`, DB `snatchit_a138e/f_rehears` at the candidate chain):
- request → `ok`; outbox holds `account_deletion_pending:<uid>:<ts>`;
- `notify.drain_outbox` → `{"done":1,"resolved":1}`; one `notify.notification` row for the identity;
- withdraw → `ok`; state back to ACTIVE, `deletion_requested_at` null;
- outbox has no withdrawal event; a second drain does nothing;
- **the notice is still there, unread and undismissed: 1 unread.**
That is exactly the sandbox buyer's state, so the stale notice is the ordinary consequence of request-then-withdraw, not a data accident.

Two things checked and cleared while tracing:
- the notification row carries NULL title/body locally: **not a defect** — `notify.get_inbox` renders the title and body from the highest template version at read time, which is also why DV-N-1 saw v2's wording;
- CI's 141 warning "notify.emit_event(...) does not exist" is **unrelated and pre-existing**: it appears identically on 0cfa8ba and on the marketplace candidate 6561d1f, and `notify.emit_event(text,text,uuid,text,jsonb,uuid,uuid)` does exist in the replayed chain.

## 3. The smallest safe fix (proposed; not written)
**Option A — retire the notice inside the withdrawal verb (A's recommendation).** In `kernel.withdraw_account_deletion`, after the state update and in the same transaction, mark that identity's live `account_deletion_pending` notices as no longer actionable. Scoped to `recipient_id = auth.uid()`, to that one type, and only where not already read or dismissed; idempotent; no new notify type, no template, no new job, nothing outbound. Cost: it writes to `notify.notification` from a kernel verb, and "dismissed" slightly overstates what the user did — the record should say the system retired it on withdrawal.
**Option B — emit a withdrawal notice as well.** Add an in-app-only type (`allowed_channels {}`, the shape 136 used for `security_device_rebound`) plus templates, emit it on withdrawal, and retire the pending one. Honest and visible, but it is a notify-catalog change with new templates, so it is not the smallest fix. Recommended only if the owner wants the user told.
**Not recommended:** hiding the notice in the client. The server would still hold a false statement about the account, and every other surface would keep showing it.
**Open, for whichever option:** undelivered push/email rows for the retired notice are not cancelled by either option. If the owner wants that too, it is a separate, larger change and a separate decision.

## 4. Scoped plan for the buyer's existing notice (NOT authorized; needs the owner's explicit go)
The same shape as the accidental-report cleanup, which the owner approved and D witnessed:
- **Pre-read (A and D independently, must match):** the single row `f3abe550…`, type `account_deletion_pending`, recipient `919d511e`, read_at null, dismissed_at null, its created date, its row md5; buyer notification total; `kernel.identity_ext` ACTIVE with `deletion_requested_at` null; 0 `account_deletions`.
- **Write:** one transaction, keyed by that notification id and recipient, that marks it read and dismissed (or, if the owner prefers, deletes nothing at all and waits for Option A to ship and be applied). It raises unless exactly one row changes.
- **Post-read (A and D):** that row no longer live; every other notice, the delivery rows, the buyer account and the totals unchanged.
- **Stop:** any difference in the pre-read, more than one matching row, or any other notice changing.
- **Alternative the owner may prefer:** leave the notice untouched until Option A is applied, then let the fix retire it on the next withdrawal — except that this buyer has already withdrawn, so the row would persist until touched directly. That is why the plan exists.

## 5. Status
Severity MEDIUM as C proposed: a misleading account-security statement, not a money or access defect. It does not block Build 19 or the marketplace candidate. Waiting on the owner's choice between Option A and Option B, and separately on §4.

## 6. OWNER'S DECISION — 2026-09-17. Option A adopted; Option B declined; nothing applied.

The owner's words: *"F-NOTICE-1: use the minimal fix. When a user withdraws account deletion, retire only that user's pending deletion notice. Do not add a new notification type or outbound message. Keep the reviewed branch and migration 141 unapplied unless a separate apply decision is made."*

- **Option A is the decision**, and it is exactly what was built: `fix/f-notice-1-withdraw-retires-notice @ ea547e5`, migration 141 + rollback + pgTAP 208. It adds one internal routine `notify.retire_account_deletion_pending(uuid)` (SECURITY DEFINER, owned by postgres, `search_path = ''`, `lock_timeout = 2s`, EXECUTE revoked from public, anon, authenticated **and** service_role) and one call inside `kernel.withdraw_account_deletion`, whose body is otherwise 077's verbatim. The retire lives in `notify` because 157 A48 forbids a kernel routine from referencing notify's tables.
- **"No new notification type or outbound message" is satisfied structurally, not by intention:** 208 E2 asserts the withdrawal emits no event of its own, no `notify.notification_type` row is added, no template is added, no job is created. That constraint is now pinned by a test rather than by this sentence.
- **Option B is declined.** The user is not told that the notice was retired; the notice simply stops asserting something false.
- **Not applied anywhere, and no apply is scheduled.** The branch is reviewed (D PASS, B reviewed) with CI 35263537823 SUCCESS on five jobs (pgTAP Files=89, Tests=5325, PASS), and it sits at `ea547e5` awaiting a separate apply decision that has not been made.
- **§4 remains unauthorized and un-run.** The buyer's existing stale row `f3abe550…` in the sandbox is untouched. The fix is forward-only, so that row will persist until either 141 is applied *and* that identity withdraws again — which it will not, having already withdrawn — or §4 is separately authorized. Today's instruction ("do not touch … any hosted data") bars running it now. **Open, owned by the owner.**
