# D — present-state verification + O-R4 R0 findings (2026-10-08/09 UTC)

**Owner authorisation in force:** independent verification of the current deployment, setting and audit
entries; and the two prepared historical reconciliation reads (DB + Stripe). **No** correction writes,
refunds or other money actions. Detection stays enabled.

**Reading convention used throughout:** "PRESENT READ" = D read it in this session, timestamped.
"HISTORICAL" = taken from a record or another session, not re-observed.

## 1. Reconciliation of D's earlier deployment report

| D said earlier (now HISTORICAL) | PRESENT READ | Status |
|---|---|---|
| "nothing is deployed; the console still serves `dpl_J5Kr`" | both production aliases → **`dpl_8xPaaBYGM7xgfGsS5fgNKib4gNXp`** (alias updatedAt 1791503163048/050) | **SUPERSEDED** |
| "gap 2 unmeasured: does Redeploy re-evaluate the current pin?" | **ANSWERED YES** by measurement, below | **CLOSED** |
| "attempt 1 proves nothing about the guard" | still true of attempt 1 | stands |

**The successful deployment, PRESENT READ:**
`dpl_8xPaaBYGM7xgfGsS5fgNKib4gNXp` — `state READY`, `target production`,
`githubCommitSha f7e7e85f38c3d14e6ce38bb2fa1131fb66ec74bb`, `ref admin/operating-console`,
`source redeploy`, `aliasError null`.

**The discriminating fact that the guard admitted it and a real build ran:**
`buildingAt 1791503124312 → ready 1791503162887` = **38.6 s**.
Compare the two skips/failures: `dpl_74DoDN` 3.2 s (cancelled by the old pin) and
`dpl_iAzLKA1` 2.84 s (root-dir failure). A 38.6 s elapsed cannot be a skip. So Redeploy **did**
re-evaluate the pin as it then stood — §5 gap 2 of `D_WITNESS_C4_PIN_20261008.md` is closed
affirmatively, by timing plus a READY production state, not by assumption.

Pin unchanged at `test "$VERCEL_GIT_COMMIT_SHA" != "f7e7e85f…74bb"`; `rootDirectory` still `admin`.

**Correction to my own earlier reasoning.** I wrote that an unmoved `project.updatedAt` excludes a
settings change-and-revert. That direction holds. But `updatedAt` **also** moves when
`latestDeployment` changes — it now reads 1791503163191, ~150 ms after the alias move. So a *changed*
`updatedAt` is **not** evidence of a settings change. I used it only in the valid direction, but the
asymmetry belongs in the record.

## 2. The setting — PRESENT READ

`ops.setting` where `key = 'refund_state_detection_enabled'`:

| field | value |
|---|---|
| `value` | **`true`** |
| `updated_at` | **2026-10-08 23:54:39.887014+00** |
| `updated_by` | `2b117757-f4e3-41c1-b7df-68a4502d0fba` |

**Checked against the frozen expectations, not just read:**
`docs/release/packages/150_151_20261005/expected/post151.txt` predicts `ops_setting_rows=14` and
`setting_refund_state_detection_enabled=false`. Production reads **14** rows — exact match — and the
flag reads `true`. So the **only** divergence from the frozen post-151 state is the one authorised
flip. `setting_detectors_enabled` and `setting_refund_state_pending_hours` are unchanged from frozen.
(150 added two settings, 12→14; that is why 14 is correct and 13 would not be.)

## 3. Audit entries — PRESENT READ

`ops.action b43f81ea-1b7a-4da1-819f-40b427fd1537`: `action_type setting_set`, `state succeeded`,
`params {"value": true}`, `result {"after": true, "before": false, "status": "succeeded"}`,
`requested_by 2b117757…`, `requested_at = completed_at = 23:54:39.887014+00`, `error` empty,
**`approval_id` null**.

`ops.audit`, two rows, same actor, `actor_role platform_admin`, `subject_ref
refund_state_detection_enabled`, both at 23:54:39.887014+00:
- `1db91d63…` `action.requested`, outcome `requested`
- `7c1600d2…` `action.setting_set`, outcome `succeeded`, `before false` → `after true`

The before/after pair in the audit agrees with the live `ops.setting` value. Chain is complete:
requested → succeeded → setting reads true.

**Control that the audit mechanism discriminates:** the same query returned two *September* setting_set
actions on a different key (`actions_enabled`, actor `3b7b50af…`) with substantive reasons recorded
("Acceptance gate G7: pause rehearsal…", "un-pause after refusal check passed"). So the table does
record other actors, other keys and real reason text — the October rows are not an artifact of the filter.

**Two observations on record quality, not on correctness:**
1. `approval_id` is null — this was a single-actor change with no second-party approval record. Expected
   with a sole operator, but the audit shows no independent approval, so it should not later be cited
   as having had one.
2. The `reason` recorded on both audit rows is **"OR 2 oct 8th claude told me to"**. It does carry the
   decision id (O-R2), which is the traceable part. But it attributes the decision to an assistant when
   the authorisation was the owner's own. For a money-adjacent flag the reason text is the thing a future
   auditor reads first; I would not rewrite history, and a later note referencing the owner's O-R2
   authorisation would correct the attribution.

## 4. O-R4 R0 — PRESENT READ (owner-authorised), read-only

**Counts.** payments total **57**; refunded (status or `refunded_at`) **7**; `payment_refund_state`
**0**; `payment_refunds` **0**; `payment_refund_state_log` **0**; **R0-eligible = 7**.

**Controls for the zeros** (a zero is evidence only if the instrument can return non-zero):
- the connection sees data: 57 payments, `distinct status = failed,pending,refunded,succeeded`;
- `transfers` total **36**, of which **23 have `payout_released_at` non-null** → that column *is*
  populated in general, so the nulls below are real;
- **vacuous control, stated as such:** `payout_attempts` is **0 rows table-wide**, so "0 payout_attempts
  for these 7" cannot discriminate and carries no weight. The 23/36 transfers control is the one that does.

**The 7 eligible records.** All seven: `amount_refunded_cents` **NULL**, ledger rows **0**,
`payout_released_at` NULL, `stripe_transfer_id` NULL, `dispute_resolution` NULL, `disputed_at` NULL.

| # | payment | PaymentIntent | livemode | total | refunded_at (UTC) | transfer |
|---|---|---|---|---|---|---|
| 1 | `50f9a2e3` | `pi_3TFPZiGdOzCmGbHw1JOFjc65` | **false** | 15750 | 2026-03-29 22:01:25 | (none) |
| 2 | `d15dd918` | `pi_3TFRdxGdOzCmGbHw1sfT7nF6` | **false** | 7875 | 2026-04-01 20:25:53 | expired |
| 3 | `4460d80f` | `pi_3THufwGdOzCmGbHw1ehCiZqd` | **false** | 3150 | 2026-04-02 23:35:02 | expired |
| 4 | `49304db7` | `pi_3THuOyGdOzCmGbHw1nGe4nXM` | **false** | 2625 | 2026-04-03 23:15:02 | expired |
| 5 | `e52c98e3` | `pi_3TpCE5GdOzCmGbHw1OWqPwF3` | **false** | 33000 | 2026-07-04 18:56:02 | expired |
| 6 | `32913315` | `pi_3U0XuwGdOzCmGbHw0WVJfW3y` | **true** | 1100 | 2026-08-04 17:20:05 | reversed |
| 7 | `700d469b` | `pi_3U0YzcGdOzCmGbHw0Z6l7bf7` | **true** | 220 | 2026-08-04 17:20:19 | reversed |

### 4a. `payments.stripe_livemode` resolves R1's mode question

The package says R1 needs "the right mode (live or test)" and took `payments.mode` as the source; A then
corrected that `mode` is `buy_now`/`auction`. **There is a separate column, `payments.stripe_livemode`
(boolean), which is exactly the Stripe mode.** It reads **false for 5** of the 7 and **true for 2**.

So R1 is **not** one undifferentiated Dashboard sweep: 5 PaymentIntents are in the account's **test**
mode and 2 in **live** mode. Only records 6 and 7 involve real money.

### 4b. Both hazards have zero members

- **Hazard 1** (same refund already in the ledger under another key): `payment_refunds` is empty
  production-wide → **no member**. Nothing for R3 to refuse on this ground.
- **Hazard 2** (refund predates the ledger): applies to **all 7**, but its dangerous branch is the
  after-payout event, which `20260906120000`:538-543 raises only when a payout is recorded. No row has a
  payout — and that null is backed by the 23/36 control. So **`REFUNDED_AFTER_PAYOUT` /
  `PARTIAL_REFUND_AFTER_PAYOUT` cannot fire** for any of the 7.
- **Chargeback exclusion** (D, 2026-10-08): the rule stands as a guard but has **zero members** —
  no row has `disputed_at`, and with `payment_refunds` empty no row carries `source='dispute_lost'`.
  Worth stating plainly: the exclusion I argued for turns out to protect nothing in this data set. It
  stays in the package because it is about what R3 must refuse, not about this one run.

### 4c. `amount_refunded_cents` is NULL on every refunded payment

Not just the 7 — table-wide, `count(*) where amount_refunded_cents is not null` is **0**. The column was
added by `20260906120000`:306 with `IF NOT EXISTS` and no backfill. Consequence for R3: `coalesce(…,0)`
makes `v_new_total = least(refund_amount, total)`, so a full refund sets `status='refunded'` and
`refunded_at` (:521-522) — values these rows already carry. No cents move backwards.

## 5. R1 — NOT PERFORMED. D has no access, and here is the proof

The owner authorised the Stripe read; D cannot execute it. Measured, not assumed:

```
$ stripe refunds list --payment-intent pi_3TFPZiGdOzCmGbHw1JOFjc65
▸ Running in SNATCH IT  sandbox · sandbox (acct_1T6Fb1(truncated))
{ "error": { "code": "resource_missing",
             "message": "No such payment_intent: 'pi_3TFPZiGdOzCmGbHw1JOFjc65'", … } }
```

The local CLI is bound to **`acct_1T6Fb1(truncated)` ("SNATCH IT sandbox")** — a *different* Stripe
account from the one holding these records. Corroborating identifier evidence: every PaymentIntent and
the live webhook endpoint `we_1TCqy5GdOzCmGbHwxBkCHKL2` share the fragment `GdOzCmGbHw`, which does
**not** appear in the CLI's account id; and `GlD5aqtxIw` does not appear in any PaymentIntent. So this is
the wrong account, not a missing permission — and the 5 test-mode rows are in the *real* account's test
mode, not in this sandbox.

**Note on method:** a first pass classified all five as "ACCESS FAIL" because the output was grepped for
`error`, which also matched an unrelated plugin hint string in the stream. The conclusion above rests on
the raw stdout/stderr quoted here. Flagging because the wrong reason would have been recorded.

**What R1 needs:** a read, by the owner in the Dashboard of the account whose fragment is `GdOzCmGbHw`
(or via a restricted read-only key on it) — **test mode** for records 1-5, **live mode** for records 6-7 —
returning per refund: `id`, `status`, `amount`, `created`, `failure_reason`.

## 6. Proposed handling per eligible record — for the owner's decision

**Group A — records 1-5, `stripe_livemode = false`.** Test-mode payments sitting in the production
database. **Proposed: exclude from reconciliation writes.** No real money moved and no buyer is owed
anything, whereas R3 would write synthetic rows into two money tables plus the **append-only**
`payment_refund_state_log`, which cannot be cleanly undone and which **permanently blocks rolling back
migration 150** (its guard requires `payment_refund_state_rows=0`). If the motivation is that these rows
look wrong in an account view, the proportionate fix is a display filter on `stripe_livemode` in the web
and console reads — reversible, and in D's lane. *Owner decision: exclude, or reconcile for display
consistency.*

**Group B — records 6-7, `stripe_livemode = true`** (`$11.00` and `$2.20`, both refunded 2026-08-04
17:20 UTC, ~14 s apart, both transfers `reversed`). The only real-money records. **Proposed: reconcile,
but only after R1** returns each refund's actual Stripe state — the whole point of 150 is to stop showing
a requested or failed refund as refunded, so writing a state before reading it would reintroduce the bug
it fixes. Both have no payout and no dispute, so no reversal path and no chargeback exclusion.
*Owner decision required on `source` per row:* with no ledger row the original path is **not
recoverable**, so per the package it must be the owner's recorded decision, never a script default. The
context suggests an operator-initiated refund (`admin`), but that is a judgement about what happened, not
something the data states.

**One consequence to note before any R3:** detection is now **on**. If R1 shows either live refund as
`failed` or `canceled`, reconciling it opens a p1 `refund_failed` case within 5 minutes. That is the
intended behaviour and the owner works it under O-R3 — but it should be expected, not a surprise.

## 7. First detector tick — agreeing with A on its limit

A recorded the 23:55:01 tick as `refunds succeeded, scanned 2, opened 0` and noted it ran over zero
refund-state rows. D's independent count confirms `payment_refund_state = 0`, so the tick **cannot** be
evidence that detection works — it is evidence only that the job runs and does not error. First real
evidence would be a tick over a non-empty table, which only exists after an authorised R3.

---

## 8. Provenance of `stripe_livemode` — my own concern, checked and withdrawn

Before relying on this column to exclude five money records, I traced where it is written. **It is never
inferred.** Two write paths, both grounded in Stripe's own statement:

1. **At creation / confirmation** — `create-payment-intent/index.ts:1143-1147`:
   *"Mode boundary (migration 045): stripe_livemode is recorded from Stripe's OWN livemode field, never
   inferred"*, writing `livemode: stripeData.livemode ?? null`. Same in `confirm-payment:274` and
   `enforce-transfer-expiry:398` (`typeof pi.livemode === 'boolean' ? pi.livemode : null`).
2. **The quarantine path** — `enforce-transfer-expiry/index.ts:884-887` does
   `update({ stripe_livemode: false })`, but **only** inside
   `if (isCrossModeStripeError(msg))`, which (`_shared/payout-logic.ts:140-142`) matches Stripe's own
   message `/similar object exists in (test|live) mode/i`. So that `false` is Stripe telling us the
   object lives in the other mode, not a guess.

**I raised the worry that we would be excluding five money records on the strength of an unverified
internal flag. That worry is answered and I withdraw it** — the flag is Stripe's answer, recorded.
Supporting reads: `livemode` is `true` 8 / `false` 49 / **null 0** across 57 payments (so no pre-045
unclassified rows here), and both values are present, so the column discriminates.

**One residual, stated precisely.** On the quarantine path the `false` is a *correction* of a prior
`true`, and that correction is captured only via `captureException(... legacy_test_record: true)` — i.e.
in Sentry, not in the payments row. So the database cannot distinguish "always test" from "was marked
live until Stripe corrected us". This does **not** change the handling (Stripe classifies the object as
test mode either way), but it is why the exclusion should be worded as *"Stripe classifies these as test
mode"* rather than *"these were never live"*. D cannot read Sentry, so whether any of records 1-5 was
quarantined is unestablished.

### This strengthens the exclusion argument materially

`payout-logic.ts:144-152` defines the system's existing boundary:

> *"The mode boundary for financial automation: only rows explicitly marked live
> (payments.stripe_livemode = true) may enter refund/payout/reconciliation paths. false =
> preserved-but-inert test-era audit data; null = unclassified and therefore NOT actionable (fail
> closed)."*

`rowIsLiveActionable()` returns true only for `true` — plus a sandbox-only `ALLOW_TEST_MODE_MONEY`
switch that the release checklist asserts is absent in production. **So production code already treats
all five as inert for every refund, payout and reconciliation path.** Reconciling them through R3 would
be the only money-rail write that crosses a boundary the codebase states explicitly. Exclusion is
therefore the choice *consistent with the system's own design*, not merely the cautious one — which is a
better argument than the rollback-guard cost I gave first, and it should be the one put to the owner.

### Scope status of the exclusion — not yet decided

A's package (fda362e5) records the test-mode five as "excluded jointly" and narrows R1 to the live read
of records 6-7 only. **D's position: the exclusion is a recommendation from D that A agrees with. It is
not the owner's ruling, and the owner was explicitly offered the alternative** ("exclude, or reconcile
for display consistency"). The narrowing of R1 is downstream of that ruling: if the owner chooses
display consistency, R1 must also read records 1-5 in test mode, because writing a refund state without
first reading the real one reintroduces precisely the defect 150 fixed. The package should read
*excluded pending the owner's ruling*, with R1 narrowed *conditionally*.

---

## 9. The mode boundary, verified at function level — and R3 bypasses all of it

A's package now gives the `rowIsLiveActionable` boundary as the **primary** reason to exclude records
1-5, citing it "used at `enforce-transfer-expiry:618`, `ops-refund-execute/classify.ts:117` and
`stripe-webhook/native-dispute.ts:206`". Since that argument is now load-bearing for an owner decision,
D verified it rather than inheriting it. Read at gate tip `abef9506`.

### 9a. Only one of the three is a call site

Scanning every `.ts` under `supabase/functions/` for **call syntax** (`rowIsLiveActionable(`), excluding
comment lines, returns exactly two hits: its definition (`_shared/payout-logic.ts:150`) and **one real
invocation** — `enforce-transfer-expiry/index.ts:618`.

A's other two citations are **prose**:
- `ops-refund-execute/classify.ts:117` is inside a doc comment — *"the `rowIsLiveActionable` rule in
  _shared/payout-logic.ts"*.
- `stripe-webhook/native-dispute.ts:206` is a comment saying the code *"mirrors `rowIsLiveActionable`"*.

The substance survives — both paths **do** enforce the boundary — but by **independent
implementations**, not by calling the shared helper. That distinction matters for a claim about a money
boundary: three separate implementations can drift from one another; a single shared function cannot.
Worth noting too that a shared boundary helper with exactly one consumer, while two other paths hand-roll
equivalents, is itself a mild smell.

The two independent enforcements, read directly:
- `ops-refund-execute/classify.ts:120-138` — `checkModeConsistency(keyMode, stripeLivemode)` rejects
  `key_mode_unknown`; `row_mode_unclassified` when not a boolean; and `cross_mode` when
  `(keyMode === 'live') !== stripeLivemode`. **Stricter than `rowIsLiveActionable`**: on a live key a
  `false` row is refused outright. Fails closed for records 1-5.
- `stripe-webhook/native-dispute.ts:211-232` — `resolveDisputeRail` step (3) requires
  `eventLivemode === true && paymentRow.stripe_livemode === true`, else routes `not_livemode` with
  ack + alert and no native write. Its own comment records that `record_dispute_native` "enforces neither
  rail nor livemode … the edge is the only guard and it fails closed."

### 9b. The database functions R3 would call are mode-blind

Function bodies mapped by parsing `create … function` boundaries (not by grep line numbers — see 9d):

| function | lines | livemode in body |
|---|---|---|
| `public.record_refund_state` (150) | :125-261 | **none** |
| `public.record_payment_refund` | :457-558 | **none** |
| `ops.detect_refunds` (150) | :262-406 | **none** |
| `public.claim_payout_attempt` | :559-677 | :633,636,637 — **raises `PAYMENT_NOT_LIVE`** |

So `PAYMENT_NOT_LIVE` guards the **payout claim** path only. **Neither function in R3's call path
checks `stripe_livemode`.** R3 is `select public.record_refund_state(…)`, which at :224 calls
`record_payment_refund` — both mode-blind. Nothing in the database would refuse to write test-mode rows
into `payment_refund_state`, `payment_refund_state_log` and `payment_refunds`.

**This inverts the shape of the argument, in the direction of exclusion.** The earlier framing was "R3
would be the only money-rail write crossing a stated boundary". The accurate framing is stronger: the
boundary that keeps records 1-5 inert lives **at the edge** (one `rowIsLiveActionable` call plus two
independent equivalents) and, in the database, only on the payout path. **A direct SQL call bypasses
every one of them.** R3 is not constrained by the mechanism that currently makes these rows harmless.

### 9c. New consequence: the live detector has no mode filter

`ops.detect_refunds` (:262-406) contains **no livemode reference**. Detection is now **on**. So if R3
wrote refund-state rows for the five test-mode payments, the live detector would scan them like any
other, and a reconciled `failed`/`canceled` test-mode refund could open a **p1 case** — an alert about
money that never moved, in the queue the owner has committed to working daily under O-R3.

This was not stated anywhere before. It is an operational cost of reconciling the test rows that falls on
the owner personally, and it is independent of the rollback-guard cost.

### 9d. Method note — a near-miss of my own

I first read `20260906120000` lines 625-660 off a grep hit list and was about to report that
`record_payment_refund` carries a `PAYMENT_NOT_LIVE` gate. It does not: that region belongs to
`claim_payout_attempt` (:559-677). Caught before reporting by mapping function boundaries and testing
containment instead of trusting grep line numbers. Same class as the earlier `:52-54` / `:508-510`
citation error — a line number means nothing until the enclosing object is established.

### 9e. Limit on completeness

A sweep intended to enumerate *every* edge money path and its gate **failed** (malformed paths, partial
output) and its results are discarded, not reported. So D makes **no** exhaustive claim of the form
"every money path gates on mode". What is claimed is only the function-level facts in 9a-9c, each read
directly at `abef9506`. A full enumeration remains undone.

### 9f. Function-extent discrepancy with A — decomposed, not left open

A reported `record_payment_refund` as `:457` + 97 lines (= :457-553); D's parser reported :457-558. The
5-line gap is fully explained:

```
553	  );
554	END; $function$;          <- true terminator
555	(blank)
556-558	-- ── 5. Payout attempt protocol ──   <- section header, not body
559	CREATE OR REPLACE FUNCTION public.claim_payout_attempt(
```

True body is **:457-554**. A's window stops one line short of the terminator; D's over-includes four
lines of blank + section comment, because D's parser split on the *next* `create function` line rather
than matching to the dollar-quote end — A's instrument is the tighter one. **Neither affects the
finding:** both windows strictly contain the real body and both returned zero `livemode` hits, and D's
wider window is the conservative direction for a zero-hit claim. Recorded because an unexplained numeric
difference between two sessions' reads is exactly what should not be left sitting in a record.
