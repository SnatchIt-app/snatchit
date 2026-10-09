# F-CONSOLE-SETTING-STALE-1 — console setting panel shows a stale value after a successful change

**Raised by:** the owner, 2026-10-08, from the O-R2 session. **Lane:** D (admin console).
**Severity:** moderate — no incorrect write occurred; the risk is an operator misreading state and
re-submitting a money-adjacent action.

## Observed

During O-R2 the operator submitted `refund_state_detection_enabled = true` in the console. The action
**succeeded** (`ops.action b43f81ea-1b7a-4da1-819f-40b427fd1537`, `state succeeded`, 23:54:39.887014+00,
`before false → after true`), but the panel **continued to display `false`**. The operator clicked a
second time; per A that second submission reused the same idempotency key, so it did not double-apply,
and a page reload would have minted a new key.

Verified by D: the stored setting is `true` and the audit chain is complete. **The data was always
correct; only the display was stale.**

## Why it matters

The displayed value is what an operator uses to decide whether to act again. A success that still reads
`false` invites exactly the second click that happened here. The idempotency key prevented a duplicate
this time — but that is a backstop, not the intended control, and it is key-scoped: after a reload the
same misreading would produce a genuinely new action.

## Required behaviour (owner's wording, 2026-10-08)

> Successful submission should refresh the displayed setting or clearly show that its value is awaiting
> refresh.

So either is acceptable: re-read the setting after a succeeded action and show the new value, **or**
show an explicit "awaiting refresh" state. What is not acceptable is continuing to present the old value
as if it were current.

## Fix direction (not yet implemented)

1. On a `succeeded` action response, invalidate/re-fetch the settings read rather than trusting local
   state. Per D's lane rules the `ops.*` read must not be cross-request cached.
2. Until the re-read resolves, render the control as pending — never the prior value.
3. Disable re-submit while an action for that key is in flight or awaiting refresh.

## Verification this fix will need

- The asserting test for the panel state machine (succeeded → pending → refreshed value).
- A **negative control**: with the re-read removed, the test must fail. A passing test against a panel
  that happens to re-render for another reason would prove nothing.
- Typecheck + lint, and the affected console browser check.

**Not in scope:** the setting's semantics, detection behaviour, alert delivery, or refund execution —
all unchanged. This is a display-refresh defect only.
