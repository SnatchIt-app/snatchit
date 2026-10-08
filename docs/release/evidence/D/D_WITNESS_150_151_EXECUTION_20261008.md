# D's witness record: the 150/151 execution

Against the expectations registered at `cc94532c` (amendment `04d756be`). Pre-apply record: `9434cbf7`.
**All witness points PASS.** Two corrections of D's own are disclosed at the end.

## W0 — PASS (D's own read)

21 keys identical to `expected/pre150.txt`, zero mismatches, with a **19-mismatch control** against
`post150.txt`. Recorded in full at `9434cbf7`.

## W1 — A's observation only, and now unrepeatable

By the time D read production, **151 was already applied**, so the post-150/pre-151 intermediate state is
**not independently observable**. A's W1 — 24 rows identical to `post150.txt`, sha256 `26cd383c…` — is the
sole observation of that moment and carries its own authority, not D's.

What D *can* corroborate about W1 from the end state: `ledger_150` present with the expected tag, the
census at `34|111|37|40`, and `record_payment_refund` unchanged — all of which W1 asserted and all of which
survive into W2. The intermediate ledger count of 163 is A's alone.

## W2 — PASS (D's own read)

**24 rows, identical to `expected/post151.txt`. Zero mismatches, zero unexpected keys.**

Controls, both discriminating:
- vs `post150.txt`: **exactly 4 mismatches** — `detect_release_stuck` `12ed7fc2…`→`6e0a9c5d…`, `ledger_151`
  present, `ledger_count` 163→164, `ledger_max`→`20260925010000`. Precisely the four keys 151 changes and
  nothing else, which is the measurement that 151 added no object.
- vs `pre150.txt`: 18 mismatches + 3 keys that did not exist before.

### The six registered invariants, checked on D's own read

| | Invariant | Read | |
|---|---|---|---|
| 1 | detection off | `false` | **OK** |
| 2 | refund-state rows / log rows | `0` / `0` | **OK** |
| 3 | `payments_refund_cols_nonzero` | `0` | **OK** |
| 4 | `record_payment_refund` md5 | `08924da572763345c38f8fe5263b5431` | **OK — identical to W0** |
| 5 | ledger | `164` (162→163→164) | **OK** |
| 6 | census | `34\|111\|37\|40` | **OK** |

Invariant 4 is the compatibility claim, now measured on production before and after rather than grepped
from the migration.

## W3 — stripe-webhook, PASS (D's own download)

- Version **43**, `verify_jwt` **False**, status **ACTIVE** — D's own Management API read.
- **D downloaded the deployed function and compared it to the frozen manifest: 3/3 identical, 0 mismatches**
  (`_shared/sentry.ts`, `_shared/stripe.ts`, `stripe-webhook/index.ts` `2a5c4631…`).
- **Control:** 2 of the 3 files still equal the *previous* manifest — the two shared files, unchanged by
  design — and **`index.ts` is not among them.** So the download reflects a deploy that landed, rather than
  returning what was there before.

## W4 — enforce-transfer-expiry, PASS (D's own download)

- Version **42**, `verify_jwt` **True**, status **ACTIVE**.
- **6/6 identical to the frozen manifest, 0 mismatches** (`index.ts` `24bde557…`).
- **Control:** 5 of 6 still equal the previous manifest — the five shared files — and `index.ts` is not.

## Package integrity, re-anchored outside the package

`frozen.sha256` verifies **16/16**. Rather than trust the package's own manifest, D re-checked the four
load-bearing SQL files against the pull-request heads directly:

| | PR head blob | frozen copy | |
|---|---|---|---|
| 150 | `b7ef57fa63eb` | `b7ef57fa63eb` | MATCH |
| 151 | `cb9fa6aa5c14` | `cb9fa6aa5c14` | MATCH |
| 150 rollback | `7122bcc12cbe` | `7122bcc12cbe` | MATCH |
| 151 rollback | `3b06fb0e2aeb` | `3b06fb0e2aeb` | MATCH |

`sql/state.sql` re-confirmed read-only before each use: one statement, and zero write keywords outside
`has_table_privilege(...)` literals.

## Two corrections of D's own

**1. "frozen.sha256 re-verified 14/14 at registration" was a carried-forward count, not a measurement.**
The file has **16** entries; the two beyond D's earlier reading are `rehearsal/predictions_v2.txt` and
`rehearsal/run_v2_20261006.log` — rehearsal evidence, not execution inputs. At registration D ran the
verification and recorded zero failures, which was true, but wrote the entry count from a read taken a day
earlier instead of counting again. A caught it. The substance is unaffected, because the load-bearing files
are anchored to the PR heads above rather than to the package's own manifest — but a number was asserted
that had not been re-measured, which is the error regardless of the outcome.

**2. D's "digest convention difference" explanation was wrong in its specifics.** D reported digest
`a4572949…` against A's `f1a0d18c…` and attributed it to convention. In fact `f1a0d18c08f3` is the sha256
of `expected/pre150.txt` itself — it is a line in `frozen.sha256`. A reported the expected file's hash;
D hashed the read rows. Two different objects, both correct. The conclusion (not a content difference) held,
but the reason D gave for it was a guess.

## Evidence boundary

This record establishes: the recorded state before and after each apply matched the pre-registered values;
the two functions' deployed source is byte-identical to the frozen manifest, downloaded by D; the versions
and `verify_jwt` are as expected; and the six invariants held at every point D read.

It does **not** establish: that any real refund has flowed through the new path; that Stripe's webhook
endpoint carries the events we believe it does (**G3 remains open — never read**); that the new
`enforce-transfer-expiry` runs without error, which needs the two post-deploy runs A is waiting for; or
anything about W1's intermediate state beyond A's observation of it.
