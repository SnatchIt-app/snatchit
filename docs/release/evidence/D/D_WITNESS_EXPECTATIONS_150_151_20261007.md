# D's witness expectations for the 150/151 execution

**Registered 2026-10-07, before A begins step 4 and before any production read of a result.** Values are
copied from the frozen package's `expected/` files, not from memory; `frozen.sha256` re-verified 14/14 at
registration. Committed so the registration cannot be adjusted to fit what arrives.

**Authorisation I am acting under, stated so it can be corrected:** the owner's "D independently witnesses
the results" for the steps named in item 4 — the transport/preflight reads, 150, 151, and the two function
deploys. I read that as authorising the read-only production reads those witnesses require, and **nothing
wider**: no read outside the package's `state.sql` key set and the two functions' metadata/source, no
Stripe call, no write of any kind.

## W0 — before anything applies

| Key | Expected |
|---|---|
| `ledger_count` | **162** |
| `ledger_max` | `20260924120000` |
| `census` | **32 \| 108 \| 37 \| 38** |
| `ledger_150` / `ledger_151` | `absent` / `absent` |
| `tbl_payment_refund_state` / `_log` | `absent` / `absent` |
| `payments_refund_cols` | `absent` |
| `record_refund_state_exec` | `absent` |
| `setting_refund_state_detection_enabled` | `absent` |
| `ops_setting_rows` | **12** |
| `setting_detectors_enabled` | `true` |
| `fn_ops.detect_refunds()` | `3098d2e6d5b3c02e94ea796d00715c0a` |
| `fn_ops.detect_release_stuck()` | `12ed7fc21fb4eccc3fac6e5865d75ee0` |
| `fn_public.record_payment_refund(...)` | `08924da572763345c38f8fe5263b5431` |

Any mismatch here is a **STOP before X2**, not a note. It would mean production is not the state the
package was frozen against.

## X1b — the transport probe

**Expected: `same_txn=true`.** Anything else — `false`, an empty row, a NULL, an error — is a **STOP**.
The whole apply shape (migration plus ledger row in one request) depends on one transaction, and this is
the only measurement of it that exists.

## W1 — after 150

Every key in `expected/post150.txt`. The ones I will treat as load-bearing:

| Key | Expected | Why it matters |
|---|---|---|
| `ledger_count` | **163** | exactly one row added |
| `ledger_max` | `20260925000000` | appended, not inserted |
| `ledger_150` | `refund_lifecycle_state\|claude-a/owner-authorised-150\|1` | the row, its tag and one statement |
| `census` | **34 \| 111 \| 37 \| 40** | +2 tables, +3 functions, +2 triggers |
| `fn_public.record_payment_refund(...)` | **`08924da5…`, unchanged from W0** | the compatibility claim: 150 does not redefine the writer v41/v42 call |
| `setting_refund_state_detection_enabled` | **`false`** | detection seeded off |
| `payment_refund_state_rows` / `_log_rows` | **0 / 0** | nothing has written state yet |
| `payments_refund_cols_nonzero` | **0** | no payment carries a refund sum yet |
| `record_refund_state_exec` | `anon:false,authenticated:false,service_role:true` | no client can call the writer |
| `tbl_payment_refund_state` / `_log` | `rls:true,anon_any:false,authenticated_any:false,service_role_select:true` | both deny-all to clients |
| `triggers_150` | both guard triggers present | the column guard and the append-only log |

## W2 — after 151

Every key in `expected/post151.txt`. Load-bearing:

| Key | Expected |
|---|---|
| `ledger_count` | **164** |
| `ledger_max` | `20260925010000` |
| `ledger_151` | `release_stuck_seller_win\|claude-a/owner-authorised-151\|1` |
| `fn_ops.detect_release_stuck()` | **`6e0a9c5d4364b352b4b8bc321931572b`** (was `12ed7fc2…`) |
| `census` | **unchanged at 34 \| 111 \| 37 \| 40** — 151 adds no object |
| everything else | identical to W1 |

**151 arms a live detector.** `setting_detectors_enabled` is `true` and `ops-detect-tick` runs every five
minutes, so within five minutes of X3 the new dating is in effect for seller-win rows. I expect no case to
open on the recorded state (no dispute resolved as of 2026-09-24 02:29Z), but **that is a record, not a
read**, and a case opening is not by itself a failure.

## W3 / W4 — the two function deploys

| | stripe-webhook | enforce-transfer-expiry |
|---|---|---|
| version before | **42** | **41** |
| version after | **43** | **42** |
| `verify_jwt` | `false`, unchanged | `true`, unchanged |
| import closure | **3 files** | **6 files** |
| changed on this deploy | `index.ts` only | `index.ts` only |
| post-download | equals the frozen manifest, 0 mismatches | equals the frozen manifest, 0 mismatches |

I will download each deployed function myself and compare to the frozen manifest, as I did for v38 and
v41 — not read A's comparison.

## Invariants across every step

These must hold at **every** witness point, not just at the end:

1. `setting_refund_state_detection_enabled` is `false` or `absent`. **If it ever reads `true`, STOP** — that
   is O-R2, which the owner has explicitly withheld.
2. `payment_refund_state_rows` and `_log_rows` are 0 or `absent` until after W4. A non-zero before the
   deploys means something is writing that should not be.
3. `payments_refund_cols_nonzero` is 0 or `absent`.
4. `fn_public.record_payment_refund(...)` md5 is `08924da5…` throughout.
5. `ledger_count` moves 162 → 163 → 164 and never otherwise.
6. `census` moves 32|108|37|38 → 34|111|37|40 and then stops.

## Stop conditions

- Any W0 mismatch, before X2.
- `same_txn` anything but `true`.
- An applied migration with no ledger row, or a ledger row with the objects absent. The package has
  `apply --ledger-only` for the first; **I do not treat either as routine** and will say which direction it
  failed in before any recovery runs.
- Any recovery that would delete data outside the package's guards. The owner excluded that explicitly.
- A function version that lands anywhere other than exactly before+1.
- A post-download mismatch of any file.

## What a PASS from me will and will not mean

**Will:** that each step's read-back matched these pre-registered values, that the two functions' deployed
source equals the frozen manifest, and that the invariants above held at every point I read.

**Will not:** that any real refund has flowed through the new path; that Stripe's webhook endpoint carries
the events we believe it does (G3 is open — never read); that production auto-deploy is off; or anything
about the combined behaviour under load. A green witness is a statement about recorded state, not about
the refund lifecycle working.
