# D — independent witness record, 149 + confirm-and-release execution (package dddb93a7)

**Verdict: PASS.** No stop condition fired; every expectation registered blind at 20:29:36Z was met.

**Authorisation.** Owner, in D's session: independent read-only production witness of P1–P3 and the
apply/deploy/verification results, explicitly including direct production reads. No writes; no calls
exercising payment, payout, refund or dispute behaviour; the OPTIONS probe is A's step. D called no
`/functions/v1/*` endpoint at any point.

**Protocol.** D's expectations (sha256 `10942503…`) were registered at 20:29:36Z, before A's P1, blind
to A's own predictions (A sent only their file's hash, `528eb22f…`). A held the apply until D's W0
verdict. Every value below is tagged by evidence class: (R) D's own production read · (F) D's own
file derivation · (A) A's recorded output, witnessed not re-measured.

## W0 — starting state, two-party verified BEFORE the write
D's read at 20:30:14Z and A's P2/P3 at 20:30:12–20Z measured the same state independently:
ledger 161 / max `20260924000000` / no 149 row; 148 row intact (`stmt_md5 4eb38855…`); a3/a4 at the
pre-149 bodies — prosrc `6a8372b4…` / `d86c2b36…` (F: D's own extraction from `20260906120000`),
defn `f8ffef47…` / `e26a538c…` (A's local-replay pins, MEASURED true against production — n=2 for
that method after 148); bindings, `SECURITY DEFINER`, `search_path=public`, service_role-only ACLs;
claim148 `ce30b56c…` / notify148 `ff103b3e…`; census 32/108/37/38; alert delivery off; grants_md5
`69c662e0…`; all 14 edge functions at D's 17:03Z baseline versions. One first measurement:
`payout_decisions` = 4 (no prior baseline existed; adopted as the window invariant).

## W2 — end state, measured by D at 20:32:18Z (R except as noted)
| Check | Result |
|---|---|
| Ledger | 162; max `20260924120000`; row `…| payout_decisions_buyer_confirmed_truth | by=claude-a/owner-authorised-149 | stmts=1`; **`stmt_md5 = 7e4d3b2d…` = D's anchor computed from ref `037092f0`** (F) — reviewed blob → applied text → recorded text closed |
| 148 | Ledger row and both function bodies untouched |
| a3 / a4 | prosrc `62f74728…` / `03ea4589…` = D's own derivation from the migration (F); defn `255e9022…` / `0d692f32…`; bindings, secdef, `search_path=public`, ACLs, owner — all unchanged |
| Census / grants / switches | 32/108/37/38; grants_md5 identical to W0; alert delivery still off |
| Window invariants | payout_attempts 0→0; **payout_decisions 4→4**; dispute_resolutions 0→0; seller_win_rows 0→0. No payment, payout, refund or dispute path ran in the window, corroborated by counts |
| Edge versions | Exactly ONE function changed: confirm-and-release v37→v38, verify_jwt true, ACTIVE, updated 20:31:20.378Z (= A's millisecond figure). The other 13 byte-stable vs D's W0 snapshot — enforce-transfer-expiry stays v41 |
| Deployed source | D's OWN download: 5/5 files sha256-identical to the `037092f0` blobs (index.ts + sentry/payouts/payout-logic/stripe), no extra `_shared` file. **Control:** deployed `payouts.ts` ≠ the pre-deploy `5b255838` version, so the comparison is non-vacuous |
| GitHub | `main` unmoved at `eadd456a…`; gate tip still `037092f0` |
| Probe | (A) HTTP 200, body `ok`, `access-control-allow-methods: POST, OPTIONS` → package PASS. Witnessed from A's recorded output; D did not call the endpoint by explicit scope |

**Consequence now live:** F-CR-148-SHARED is closed in production. v38 carries the gate's
`payouts.ts`, so `PAYOUT_HELD` / `PAYOUT_UNDER_REVIEW` classify as expected refusals, and the a1/a2
audit writers record the buyer's actual confirmation. All four a1–a4 writers are at the truthful
derivation.

## Evidence boundary — what this does NOT establish
1. That v38 has served any request. Nothing invoked it except A's probe, whose version attribution is
   by timing (deploy read-back v38 at 20:31:30Z, probe at 20:31:39Z).
2. That the changed code behaves correctly in production. Zero seller-win rows and zero payout
   attempts exist; a1–a4 and the hold refusal remain exercised only by rehearsal (216 red/green,
   two-party), CI (Files=96 Tests=5543) and vitest. First production exercise remains E-5.
3. Stripe was not read. Bound: `payout_attempts` 0 before and after, and no payout Stripe call is
   reachable without a claim writing an attempt row first.
4. The 4 `payout_decisions` rows were counted, not inspected; they predate the window (attempts=0
   since the protocol landed) but their contents are unexamined.
5. The probe result is A's evidence, not D's measurement.
