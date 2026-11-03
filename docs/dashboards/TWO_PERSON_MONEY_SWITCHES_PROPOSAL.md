# PROPOSAL: two-person control for money switches (`setting_set`)

**PROPOSAL. Nothing here is built, applied or authorised.** The owner asked F to propose two-person controls for the switches that gate money (owner decision, 2026-10-21). A owns the server side and has allocated **registry 178**, file `20261022002000_ops_money_switch_two_person.sql`, pgTAP 248 (registry line 82 @ `14f3e8ec`). F owns the console side. Prepared 2026-10-21 from read-only evidence: git objects and written records. No database was read and nothing was executed.

Citation key. Paths without a directory are in `supabase/migrations/` at the production gate `release/production-gate-20260918` @ `6f982f36`. Short names: `150` = `20260925000000_refund_lifecycle_state.sql`, `152` = `20261013000000_marketplace_safety_enforcement.sql` (production since 2026-10-13). A's drafts: `157` = `20261021100000_ops_money_action_unsettled_guard.sql` @ `07009ded`, `158` = `20261021110000_ops_listing_relist_expected.sql` @ `f5abd471`. Console files: live `07100a35`, admin v2 (#121) `fec26b41`. Records: `docs/release/...` @ `14f3e8ec` (`a/registry-20261021`).

## 1. How it works today

| Mechanism | What the code does | Source |
|---|---|---|
| Storage | `ops.setting(key, value jsonb, updated_at, updated_by)`. RLS is on and every client role is revoked, so the only write path is the action engine | `115:136-153` |
| Who may change a setting | `platform_admin` only, and a reason is required | `115:523`; `144:520-524` |
| Write path | `ops.execute_action` → `ops.action_run` → `ops.action_dispatch` branch `setting_set`. It checks that the key exists, that a value is present and that the jsonb type is unchanged, takes the row `FOR UPDATE`, and writes | `118:526-538`. The branch is identical in `144:926-938`, `152:704-716` and `158:776` |
| Compare-and-set | **None.** `p_expected` is stored on the action row (`144:526-530`), but nothing reads it for `setting_set`. There is no range check on numbers either | same |
| When a second founder is needed | `ops.action_requires_approval(p_action_type)` is `immutable` and receives the action type only: `payout_release` and `refund_execute`. It never sees which key is changing, so **every `setting_set` runs at once, on one founder's say** | `115:532-536`; called at `144:546` and `158:333` |
| The approval flow (where it applies) | Precheck first (`118:229-277`; `setting_set` falls through to `else null` at `118:272-273`). Then an `ops.approval` row: `action_hash` = sha256 of type, subject kind, subject id, subject ref and params (`115:504-511`), and `expires_at` = now + `approval_ttl_hours` (default 72, `115:152`; `144:556-560`). The action waits in `awaiting_approval` | `144:546-563` |
| Separation of duties | Constraint `approval_sod_ck` (decider ≠ requester) plus an explicit `self_approval` refusal | `115:283`; `118:193-195` |
| At approval | `approve_action` re-checks expiry (`118:196-201`) and the hash (`118:202-207`), records the decision, then runs the action (`118:217-220`). Expiry is lazy: it happens only when someone tries to approve (157 adds a sweep for refund and payout actions only, `157:231`) | `118:169-224`; `157:475` |
| Console pause | `actions_enabled = false` refuses every mutation (`118:42-50`). `execute_action` exempts a `setting_set` on `actions_enabled` so a founder can un-pause (`144:472-474`, `158:164-165`). **`approve_action` checks the pause unconditionally** (`118:178`, `157:489`), so while paused nothing can be approved | as cited |
| Console | `/system` → Settings renders every `ops.setting` row with its own form (v2 `admin/src/app/(console)/system/page.tsx:392-436`; live `:434`). It always sends `p_expected`, which is `{}` for settings, never null (v2 `admin/src/lib/actions.ts:75`; live `:47`). The Approvals panel renders any pending approval generically, with params, expected state and "terms unchanged" (v2 `system/page.tsx:347-389`, fed by `ops.list_approvals`, `116:1497-1522`). `ConfirmForm` already renders `awaiting_approval` (v2 `ConfirmForm.tsx:158`; live `:43`) | as cited |

### 1.1 The 2026-10-08 flip

`refund_state_detection_enabled` was turned on from the console on 2026-10-08 at 23:54:39Z by one founder, as action `b43f81ea`: `setting_set {"value": true}`, succeeded, **no approval**, before `false`, after `true` (`docs/release/SPRINT_STATUS_20260917.md:2193-2199`). It was a planned owner step, O-R2 (`docs/release/EXECUTION_SHEET_20261006.md:178`), and it did no harm. The gap it exposed is in the mechanism: nothing required or recorded a second founder's agreement. The reason field held an informal note, not a decision reference. The same path flips `refund_execute_enabled`.

## 2. Which keys are money switches (each reasoned)

Rule of thumb: **braking is one founder, releasing is two.** The dangerous direction is the one that lets money move, or that stops anyone from seeing it.

| Key (seed) | What it gates | Dangerous direction | Proposal |
|---|---|---|---|
| `refund_execute_enabled` (`115:145`) | Console refunds: checked at precheck (`118:251-255`), dispatch (`118:490`) and executor claim (`118:645-647`) | **on** (money leaves) | **on = two founders. off = one founder** (a brake: the executor re-checks it at every claim, so off stops further claims) |
| `actions_enabled` (`118:37`) | Pause of every console mutation; reads stay available | **un-pause** | **pause = one founder. un-pause = two founders.** A founder who sees a hijacked session, a wrong refund or a bug cannot wait for a second person, so pausing must be instant and solo. If one person could un-pause, the same compromised session could undo the pause seconds later, and the pause would contain nothing. Requires the `approve_action` exemption in §3 step 5 |
| `alert_delivery_enabled` (`146:97`) | `ops.dispatch_alerts` posts alerts (`146:209-213`) | **on** sends to real recipients. **off** silences paging | **on = two founders. off = one founder** (a brake for an alert storm or a wrong recipient), shown as a console banner. Residual risk: a solo off blinds paging; the banner and the daily summary are the mitigation. Runbook: `ALERT_CHANNEL_RUNBOOK.md` |
| `refund_state_detection_enabled` (`150:259`, read `150:274`) | `refund_failed` and `refund_pending` cases from Stripe refund state | **off** (a buyer's failed refund goes unseen). On was the 10-08 change | **Two founders both ways.** A detector never needs an emergency off: a failing detector fails only its own job run |
| `refund_resolution_detector_enabled` (`144:155`, read `144:349`) | Refund-resolution cases (money owed after a refund decision) | **off** hides obligations. **on** before the #89 classify screens opens cases nobody can close (O-3) | **Two founders both ways**; on also waits for O-3 |
| `detectors_enabled` (`115:146`; `117:1002`, `144:339`) | Master switch for every detector: paid-unsettled, refunds, release-stuck, disputes | **off** blinds every money detector at once | Not on the owner's list. **Recommended in: two founders both ways** (MS-1) |
| `approval_ttl_hours` (`115:152`, read `144:556`) | Lifetime of every pending approval | Very large: approvals live indefinitely. 0 or negative: they expire at once | It governs the control itself: **two founders**, plus server bounds (e.g. 1–72) |
| Thresholds: `dispute_sla_hours`, `transfer_deadline_soon_hours`, `paid_unsettled_grace_minutes`, `webhook_stuck_minutes`, `release_stuck_minutes` (`115:147-151`), `refund_state_pending_hours` (`150:260`) | Detector timing | A very large value silences a detector as surely as off | **One founder within server bounds** that A sets (out of bounds is refused). Alternative: two founders (MS-3) |
| `cron_job_first_seen` (`145:58`; written by the detector at `145:242`) | Job-monitoring bookkeeping | Any manual edit corrupts job-not-running detection | **Not operator-settable.** The server refuses it; the console shows it read-only (today v2 shows an editable JSON field) |

Summary for A's policy function: two founders for `refund_execute_enabled`, `actions_enabled`, `alert_delivery_enabled`, `refund_state_detection_enabled`, `refund_resolution_detector_enabled`, `detectors_enabled` and `approval_ttl_hours`. These brake values skip approval: `actions_enabled = false`, `refund_execute_enabled = false`, `alert_delivery_enabled = false`.

## 3. Server change sketch (for A, registry 178)

Stack 178 on the newest bodies when it is written. Today those are `execute_action` `158:142` (on `157:273`), `approve_action` `157:475`, `action_dispatch` `158:361` (setting branch `:776`), and `action_precheck` `118:229`, or 177's version if 177 lands first. Keep 157's lock order: the advisory lock first, for refund and payout actions only. `setting_set` takes no advisory lock; the `ops.setting` row lock in dispatch serialises it (`118:533`).

1. **Policy as code.** Add an immutable SQL function, `ops.setting_requires_approval(p_key text, p_new jsonb) returns boolean`, holding §2's set and brake values, plus `ops.setting_operator_settable(p_key)` and bounds for the numeric keys. Model them on `ops.action_allowed_roles` (`115:515-530`). Use a function, not a table: the policy then changes only through a reviewed migration, whereas a policy table would itself need two-person protection. Leave `ops.action_requires_approval(text)` unchanged.
2. **`execute_action`.** Replace `if ops.action_requires_approval(a.action_type) then` (`158:333`) with `... or (a.action_type = 'setting_set' and ops.setting_requires_approval(a.subject_ref, a.params -> 'value'))`. Keep the request-time pause exemption for `actions_enabled` (`158:164-165`), so both a pause and an un-pause can be requested while the console is paused.
3. **`action_precheck` gets a `setting_set` branch.** Without it a bad request parks and fails only after the second founder approves. The branch refuses: an unknown key, a key that is not settable, a missing value, a type mismatch, a value out of bounds, a missing expected value (`expected ? 'value'`; test for the key, because the console sends `{}`), a current value that differs from `expected.value` (`stale_state`), and a new value equal to the current one (`no_change`).
4. **Compare-and-set in dispatch.** After `select value into v_before ... for update` (`152:711`), refuse with `stale_state` when `a.expected ? 'value' and v_before is distinct from a.expected -> 'value'`. This applies to every `setting_set` that carries an expected value, and the expected value is required on two-founder keys. Repeat the settable and bounds checks here: precheck runs only when approval is required (`144:546-547`). Return `{before, after, expected}` so the audit row carries all three.
5. **`approve_action` pause exemption.** Today the pause check runs before the action is read (`118:177-178`, `157:488-489`). Read the action's type and subject first (157 already does an unlocked type read at `157:499-501`). Skip the pause check only when the action is `setting_set` on `actions_enabled` with value `true`. Every other approval stays refused while paused. Without this exemption a paused console can never be un-paused from the console.
6. **Hash binding.** `ops.action_hash` already binds the key (`subject_ref`) and the new value (`params`) (`115:504-511`), so "key + new value" needs no change. The old value lives in `expected`, which the hash does not cover. No function updates `ops.action.expected` or `params` after insert (checked in 115–158). Option (a), recommended: leave the hash alone and let compare-and-set read `expected`. Option (b): the console also sends the old value as `params.expected_value`, which the existing hash then binds with no hash change. **Do not change `ops.action_hash` itself.** That would make every pending approval stale at apply (refund and payout ones included), and the hash must stay identical in `approve_action`, `executor_claim` (`118:652`) and `list_approvals.hash_current` (`116:1512`).
7. **TTL.** For `setting_set` approvals, use `least(approval_ttl_hours, 24)` at the approval insert (`144:556-560`). A switch request is about a moment, and compare-and-set protects the value, not the reasoning behind it (MS-4).
8. **One pending request per key** (MS-5, recommended). Before parking, expire stale `setting_set` approvals for that key (the pattern of 157's `expire_stale_money_approvals`, `157:231`). Then refuse `duplicate_pending`, naming the pending action. A backstop partial unique index on `ops.action (subject_ref) where action_type = 'setting_set' and state = 'awaiting_approval'` enforces it. Without this, two founders can request opposite values and each approve the other's. Compare-and-set makes the second one fail, but the console would show two contradictory requests.
9. **Audit.** The existing rows already cover the flow: `action.requested` with params and expected (`144:537-539`), `approval.approved`/`denied`/`expired`/`stale` (`118:199-219`), and `action.setting_set` with the dispatch result (`115:862-863`). Add `"brake": true` to the result of a one-founder brake, so the console and the daily summary can flag it.
10. **Pre-flight and rollback.** Pre-flight: count `setting_set` actions in `awaiting_approval` (expect 0, since `setting_set` never parks today) and take the md5 of each body being replaced. Rollback: restore the previous bodies (157/158/177 as applied) and drop the helper functions and the index. There is no data to migrate.

## 4. Console (F, admin v2)

| Moment | What the founder sees |
|---|---|
| Settings row for a two-founder key | Current value, last changed by and when (`ops.settings()`, `116:1593-1601`), a "Two founders" badge, and, if a request is pending, "Requested by …: `false` → `true`, expires in …, waiting for the other founder", linked to the approval. While a request is pending, the form is disabled for that key (MS-5) |
| Submitting a change | The form posts `expected: {"value": <the value it rendered>}` (the hidden `expected` input already exists, `ConfirmForm.tsx:276`). Confirm copy: "Needs the other founder. Nothing changes until they approve on System → Approvals." |
| Brake direction | "Takes effect now. The other founder will see who changed it and when." |
| Second founder, System → Approvals | "Change setting `refund_execute_enabled`: `false` → `true`", the value now, "Current value still matches the request: yes/no (if no, it will be refused)", the requester's reason and the expiry. Approve or deny, with a reason (the existing `ApprovalCard`, v2 `system/page.tsx:347-389`) |
| Outcomes | Existing copy for `awaiting_approval` and `denied`. Add copy for `stale_state` ("the value changed since you loaded it; reload"), `approval_expired`, `no_change` and `duplicate_pending` |
| Gaps found | `SETTING_HELP` has no entry for `refund_state_detection_enabled` (v2 `system/page.tsx:47-62`). `requiresApproval()` (v2 `admin/src/lib/permissions.ts:39-42`) is unused; extend it with a key-aware mirror, used for copy only (the server decides) |

The pending-request display needs no new read: `ops.list_approvals('pending')` already returns each approval with its action row (`116:1497-1522`), and the page can match on `subject_ref`.

## 5. Failure modes

| Scenario | What happens | Mitigation |
|---|---|---|
| Only one founder is reachable | Money and detection switches cannot be turned on; brakes still work | MS-6: an owner-only break-glass, done in the SQL editor as the database owner, plus a manual `ops.audit` row, recorded afterwards |
| Console paused and an un-pause requested | Deadlock if `approve_action` still checks the pause | §3 step 5 and test T4 |
| Request approved after the value changed | Compare-and-set refuses `stale_state`; nothing changes | §3 steps 3–4 |
| Request expires unnoticed | It stays `awaiting_approval` until someone tries to approve (lazy expiry) | 24 h TTL; the sweep in §3 step 8; the existing pending count (`116:1568`). Alerts reach nobody today (`ALERT_CHANNEL_RUNBOOK.md`) |
| Founders request opposite values | Both park; the second fails at dispatch | One pending request per key (MS-5) |
| Bad input on a two-founder key | Today it would park and fail only after approval | The precheck branch (§3 step 3) |
| A third `public.admin_users` row | It silently becomes an approver. Membership changes happen outside the console and outside `ops.audit` | The runbook's step 1 read of `admin_users`, repeated periodically. Kept as residual risk |
| Database owner (SQL editor) | Can write `ops.setting` directly. `service_role` has no table grant on `ops` (`115:404-408`) | Out of scope: the control protects against a single console session, not against the database owner |
| Live console still sends `{}` after the server ships | Requests to turn two-founder keys on are refused for a missing expected value. Brakes still work, because one-founder changes do not require one | Acceptable fail-closed fallback; the console ships first (§6) |

## 6. Rollout order: console first, then server

1. **Console first, in the admin v2 release train** (inside #121 if it is still open for changes, otherwise the first release after the cutover). No extra production deploy. It is harmless on today's server: dispatch ignores `expected` for settings (`152:704-716`), precheck does not run for one-founder actions (`144:546`), and both consoles already render `awaiting_approval` generically.
2. **Server: A's 178.** Local replay plus pgTAP 248, then A and D review (the sandbox has no `ops` schema, O-7). The production apply is its own owner authorisation (one targeted file plus its ledger row), after 157/158 (and 177 if it is earlier in the merge order).
3. **Read-back** that changes nothing: the md5 of each replaced body, and one request whose new value equals the current one, which must be refused `no_change` (it writes one rejected action row and its audit row, nothing else).

Server first is also safe (see the last row of §5). Console first gives the better experience and avoids a window in which money switches cannot be turned on.

## 7. Tests

pgTAP 248 (A):
- T1 A threshold key changes at once for one founder (behaviour unchanged).
- T2 `refund_execute_enabled` false → true parks. The setting is unchanged, the requester's self-approval is refused, the second founder's approval applies it, and the audit sequence is complete.
- T3 The brake (true → false) applies at once.
- T4 Pause applies solo. While paused, an un-pause request parks, and the second founder's approval succeeds while paused. Any other approval while paused is still refused.
- T5 Compare-and-set: a mismatched expected value is refused at request. If the value changes between request and approval, the approval is refused `stale_state` and nothing changes.
- T6 A two-founder key with no expected value is refused.
- T7 `no_change` is refused.
- T8 An expired approval is refused and nothing changes.
- T9 A direct write to `params.value` after the request (as postgres) leads to `approval_stale`.
- T10 Deny is recorded and nothing changes.
- T11 `cron_job_first_seen` is refused.
- T12 A duplicate pending request is refused; after the expiry sweep a new one parks.
- T13 Type mismatch and unknown key are unchanged.
- T14 The `payout_release` and `refund_execute` approval paths are unchanged.
- T15 `platform_risk` still cannot request `setting_set`.
- Negative control: the suite against the pre-178 bodies must fail T2, T4, T5, T6 and T11.

Console (vitest, F): a settings form posts `expected.value` equal to the rendered value; a pending request renders on its key and disables the form; the approval card shows from → to and the current value; brake copy; copy for each rejection reason; `cron_job_first_seen` is read-only.

## 8. Owner decisions

| ID | Decision | Default recommendation |
|---|---|---|
| MS-1 | The two-founder set in §2, including `detectors_enabled` | Yes |
| MS-2 | Brakes stay one-founder (pause, refunds off, alert delivery off); un-pause is two-founder | Yes |
| MS-3 | Detector thresholds | One founder within server bounds |
| MS-4 | TTL for setting approvals | 24 h |
| MS-5 | One pending request per key | Yes |
| MS-6 | Break-glass when one founder is unreachable | Owner-only SQL with a manual audit row, recorded afterwards |
| MS-7 | Rollout | Console in the v2 train, then 178 under its own apply authorisation |
| MS-8 | `approval_ttl_hours` is two-founder and bounded | Yes |

## 9. Adjacent, not covered

- `dispute_resolve`: one operator's seller-win resolution makes a payout payable (O-4). It is an action type, so covering it is a one-line change to `ops.action_requires_approval` plus console copy. Not proposed here; the owner may add it.
- `payout_release` and `refund_execute` already need a second founder (`115:532-536`). Refunds stay manual (O-5).
- Membership of `public.admin_users` and the database owner's direct SQL are outside any console control (§5).
