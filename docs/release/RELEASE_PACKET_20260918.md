# Release packet — candidate `candidate/2026-09-18-pin` (`aabe029`) — DRAFT, A, 2026-09-15

Status legend: **DONE** (evidence cited) · **PENDING** (scheduled, owner-authorized) · **OWNER** (needs an
authorization or decision). This packet is the deployment-ready deliverable; it authorizes nothing.

## 1. The candidate
| | |
|---|---|
| Pinned source | `release/candidate-20260918 @ aabe029` = tag `candidate/2026-09-18-pin` (code tree `74e51cf`; docs-only above) |
| Contents | migrations 121, 123, 124, 125, 126, 127, 128, 129, 130 (amended in place); edges `stripe-webhook`, `create-payment-intent` (#64, #66, #67); client F1 + Premium batches 1–4 + recovery (33 commits, `231f120`); 193 fixtures CI-safe (#68) |
| CI at the pin | **DONE** — run 34932209458: five jobs green; migrations job through pgTAP on the real stack Files=80, Tests=4980, PASS |
| Independent review | **DONE** — D-5 incremental PASS 22/0 at `74e51cf`; 126 (D), 127/128 (D, three passes), 129 (D), 130 + #66/#67 (A, RED evidence), 193 fixtures (D); no unresolved blocking finding |
| Local certification | **DONE** — replay 149/149, census 31|96|37|35, manifest PASS, grant matrix = fixture, 4974/4974, S1–S5 + deadlock control, vitest 1911/1911, tsc 0 |
| Build artifact | **PENDING** — one EAS `preview` build from the tag (O-2), Thursday AM after SBX-2; source + build IDs recorded here on cut |
| Sandbox acceptance | **PENDING** — SBX-2 per manifest §8–§9 (O-1; **129/130 need the owner's extension**), venue phase last |
| Device acceptance | **PENDING** — C's targeted DV plan on the build, Friday; leaves open by ruling: populated Tickets (CFT-801), D9c |

## 2. Deployment order (production, when authorized — not this sprint)
1. **Pre-flight (read-only):** ledger = 135 and tip 120; `select count(*) from public.payments where status='refunded' and refunded_at is null` = 0 (126 precondition, B's L-1 — **OWNER** authorizes the read); native flags false; `AUTODEPLOY-VERIFIED-OFF` attested and `git_branch` empty (AUTODEPLOY-1).
2. **Pause** the payout cron; run legacy orphan reconciliation (release package §3, §5.7).
3. **Migrations**, `LC_ALL=C` order, each dry-run planned then applied: `121 → 123 → 124 → 125 → 126 → 127 → 128 → 129 → 130`. Verify after each: ledger +1, the object spot-check in manifest §9 row 8.
4. **Edges** (after 127 **and** 130 are applied — coupling): `stripe-webhook`, `create-payment-intent`, then the other 9 of §3b from the pin. Parity: deployed source byte-identical to the tag.
5. **Mobile** last: the build from the tag, promoted per §3c.
6. **Resume** the payout cron. **Observation** §5 below.

## 3. Compatibility and coupling (what breaks if the order is wrong)
| Pair | If reversed |
|---|---|
| 127 before the webhook deploy | webhook calls `release_reservation_for_payment` → PGRST202, logged, non-fatal; holds wait for the sweep (degraded) |
| 130 before `create-payment-intent` deploy | claim RPC absent → edge degrades to #64 behaviour (Sentry); the double-charge interleave 130 closes is open until applied |
| 128 + 129 before the new client is live | old clients keep the direct insert path (no proof, works); the new client's sign-out revoke needs 129 (PGRST202 otherwise — never blocks sign-out) |
| 125 before 126–130 | ledger order only; production applies in one window so N/A |
| Stripe `payment_intent.canceled` subscription (**OWNER**) | without it the webhook never receives cancels; L1's close is only exercised for `payment_failed` |

## 4. Rollback and recovery
- Per-migration rollbacks under `supabase/rollbacks/`, reverse order (130 → 121), each proven on the certified
  harness to restore the previous catalog byte-for-byte (127/129/130 md5-identical) with the declared exceptions:
  128 keeps the epoch table + trigger and does not restore `notify.register_push_token` EXECUTE; 126's rollback
  restores 120's bodies. Production is forward-only by policy; a rollback needs its own authorization.
- Edges roll back by redeploying from `df9e0d3` **only** if 127/130 are rolled back; otherwise the new edges are
  compatible with either state (they degrade, they do not fail).
- Client: Build 16 remains installable; the server is compatible with both clients.

## 5. Observation plan (first 24 h)
- `edge_logs` for `create-payment-intent`: `checkout-claim-refused`, `checkout-claim-lost`, `replacement-withdrawn` counts (expect ~0);
  `stripe-webhook`: `release_reservation_for_payment` reasons (expect `released`, occasional `live_sibling_attempt`).
- `payments`: any `unfulfillable:one_success_per_listing` (open money defect, 132 pending — **must alert**; today only
  Phase 0 refunds it silently); `supersede_claimed_at` older than 120 s.
- `push_tokens`: NULL-hash count (legacy tail) trending down; `revoked_reason` distribution; rule-5 rebinds count.
- Ledger stays at 144; census 31|96|37|35; no flag moved.

## 6. Remaining owner authorizations and decisions (as of this draft)
| | Needed for |
|---|---|
| O-1 extension to 129/130 | SBX-2 verification of sign-out revoke (DV-611) and the claim path (DV-L1/L2) |
| O-3 placement (b1/b2/b3) and **131** integration | production gate — not this candidate |
| **132** placement (this candidate vs production gate) | open money defect (double charge auto-refunded) |
| K-2 | product change in 131's client delta |
| P0 gates: apply/deploy authorization; `AUTODEPLOY-VERIFIED-OFF`; window schedule; Stripe `payment_intent.canceled`; PFA-32 | production deployment |
| P1: `auction-media` scope; parity-environment evidence (`notify-transfer`, `verify_jwt`, push routing); Twilio SID | production readiness |
| C's `frontend/*` push access | hygiene (integration already done from the local clone) |
| L-1 production read | 126 apply precondition |

## 7. Known open items carried, none waived
- **Open money defect:** fresh-mint concurrency (two captured charges, auto-refunded by Phase 0 if healthy) — 132 designed, placement pending.
- **Security residual:** session-compromise notification capture — 131 built and attacked, X1 slice unclosed by design, provider-side proof next.
- **Pre-existing leak closed by 131 only:** signed-out devices still receiving push.
- Promise.race timeouts do not abort the underlying Stripe fetch (orphaned intent, idempotent replay recovers).
- Evidence limits: `verify_jwt` parity, `notify-transfer`, push routing need a production-parity environment; populated Tickets and D9c stay untested by ruling.
