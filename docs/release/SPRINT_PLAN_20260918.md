# Release sprint — deployment-ready marketplace candidate by Fri 18 Sept 2026

Owner directive 2026-09-14, corrected 2026-09-15. Four sessions in parallel. **Supersedes
`RELEASE_COMPLETION_ESTIMATE_20260914.md`.** Authorized: reassigned isolated development, local testing, review,
release preparation; **SBX-1 + SBX-2 on `ofaidukbieeekqaboscm` serialized through A, after reviewed prerequisites
pass; one EAS preview/internal sandbox build from A's final reviewed pin after required checks pass** (owner,
2026-09-15). **Still requires its own authorization:** production deployment, credentials, feature activation.
**These authorizations do not accept 128's residual risk for production or waive any blocking finding.**

## Scope (frozen)
IN: approved Premium batches 1–4 + F1 root (`2ba5281`) · payment/hold: 127 **and the L1 edge coupling (B-2) —
REQUIRED** · refund: 126 (B) + F8 client state · notification privacy: 128 + client rebind · recovery/error-state:
CFT-607, F3 (D9-UX-1, F8 closed in batch 1) — **C-2 scope confirmed by the owner** · integration + verification ·
already-reviewed admin delivery on its own track.
OUT (backlog, preserved): C's remaining Premium P0/P1 and the 14 optional items; D-AN1/AN2/AN3; native
signing/scanning activation; L3/L4; F10; `auction-media` remediation (P1, separate change). Build 16 stays the
historical tested pin.

## Definition of deployment-ready (owner's, applied literally)
One pinned integrated commit + matching build artifact · required CI, migration/replay, payment, privacy and
authorization checks executed and passed, exceptions explicit · **independent review with no unresolved blocking
finding** · **targeted sandbox AND device acceptance completed** · deployment order, compatibility, rollback/recovery,
observation plan ready · remaining owner authorizations listed. **A pin and a packet alone do not qualify.**
**L1 is not a scope cut:** B-2 stays required unless an independent review demonstrates an effective mitigation
or the owner explicitly accepts a clearly explained release risk.

## Deadline-backward schedule (no waiting on merges)
| Day | Must be true by end of day |
|---|---|
| **Mon 14** ✔ | Board; B has the 126 package; C-2/C-3 delivered; A's 128 revision to D |
| **Tue 15** | D's G-1 (parity re-grant) + G-2/G-3/G-4 closed by A on the **certified harness**; D re-runs; **contract v2 frozen Wed AM** unless D blocks. B: 126 review-ready → **hands to D and starts B-2 immediately**. C: builds against the reviewed v2 spec with provisional behaviour marked. D: 128 pass 2; 126 review; O-3 independent disposition. A: O-3 brief; D-AR1 review; integrate 121→123→124→125 onto the release branch |
| **Wed 16** | A merges 126 after D's findings are closed; B-2 edge + tests review-ready **Wed EOD**; C-1 final delta on the frozen text; **SBX-1** (124, venue kit + owner MFA, previews) — venue phase may be run last, see sequencing |
| **Thu 17** | B-2 merged after review; C-4 stack rebased; **candidate pin by midday**; D-5 full chain rehearsal + regression on the pin; **SBX-2** (125→126→127→128, the two edges, DV-611 registration); **hosted build submitted Thursday** after the candidate checks |
| **Fri 18** | Handset verification (C + owner) and corrections only; re-pin only if code changes; release packet |

## Task board (changes from Mon in bold)
| ID | Owner | Deliverable | Dep | Due | Acceptance |
|---|---|---|---|---|---|
| A-1 ✔ | A | 128 fold-ins + F1 heal (`cf73d7b`) | — | Mon | done; D pass 2 found G-1..G-4 |
| **A-1b** | A | G-1 parity re-grant; G-2 column-scoped UPDATE; G-3a rollback inverse; G-4 verbatim 0590 body; **certified-harness evidence** | — | Tue | full suite on `rehearsal_reset.sh` path; grant matrix = fixture; rollback md5 = pre-127 |
| A-2 ✔ | A | D pass 3 on `f22c1a3`: **no blocking findings** (harness PASS 17/0; 4806/4806; both orders identical) | A-1b, D-3 | Tue | done |
| A-3 ✔ | A | **Contract v2 FROZEN** — `PUSH_TOKEN_CONTRACT_V2.md` @ `f22c1a3`, sent to C **Tue** (a day early) | A-2 | Wed AM | C ack pending |
| **A-3b** | A | **O-3 decision brief** (`O3_128_RESIDUAL_DECISION_BRIEF.md`) — for the owner's release decision, **separate from test authorization** | — | Tue | brief filed; D disposition attached |
| A-5 ✔ | A | D-AR1 **APPROVED** (A re-ran gates: tsc 0, lint 0, vitest 136/136, build 0; admin/ only; existing ops reads; AN-2 mapping note) | — | Tue | package section |
| A-6 | A | Integrate 121 → 123 → 124 → 125 onto the release branch; CI green | PR #58, PR #62 | Tue/Wed | CI id |
| A-7 | A | Merge 126 after D-4 findings closed; merge B-2 after review | B-1/D-4; B-2 | Wed / Thu AM | CI green |
| A-8 ✔ | A | C-4 merged **Tue** (`37213e7`): signOut.ts reviewed line by line; app/src byte-identical to the approved head; vitest 1896/1896, tsc 0 | C-4 | Thu AM | done early |
| A-9 ✔ | A | **PINNED at `aabe029`** = tag `candidate/2026-09-18-pin` (re-pinned Tue night after the 193 CI fix): CI green at the commit (5/5 jobs, pgTAP 4980 PASS on the real stack), D-5 incremental PASS 22/0, D's 193 fixture re-review OK, C's pre-flight OK. Build tree for O-2 | — | done | done |
| A-10 ✔ | A | **SBX-2 DONE 2026-09-15** (owner path (b), O-1 extended): 124, 125, 127, 128, 129, 130 applied from the pin (ledger 136, md5-verified, D witness matches); `stripe-webhook` v4 + `create-payment-intent` v4 deployed from the tag, byte-identical (A + D). **126 and its admin surfaces are not validated on this sandbox.** Open in the window: DV rows on build 17 (C), DV-L1/L2 read-backs (A), cleanup, venue phase last | — | done | manifest §10 |
| A-10b ✔ | C/A | **Build 17 FINISHED 2026-09-15 14:05Z** from tag `candidate/2026-09-18-pin` (`aabe029`): EAS `53e5e98b-dbe9-405d-a7c8-159375c3fbc6`, iOS preview/internal, appBuildVersion 17. Compiled-env evidence = envGuard at launch + sandbox sign-in read-back + first edge call in `edge_logs` (bundle inspection needs the owner's permission to download the artifact — owner item) | — | done | packet §1 |
| **A-12** | A | **133** config-driven functions URL (Vault `project_url`; 4 bodies + 5 crons; queue purge at apply) — owner item 6 permanent fix. Written, rehearsed (150/150, census unchanged, rollback md5-identical, 200 24/24 + negative control 16 not ok; 165 C2/C3 updated). **D's review: F-133-1 HIGH + F-133-2 MEDIUM fixed at `235c839` (Vault precondition enforced; purge skips production), CI green run 34982307401; **D PASSED 133 at `235c839` (2026-09-16, fresh rerun after the outage; refusal matrix, cron behaviour, rollback identity, integrated harness)**; merged onto the production-gate stack | — | done | registry row; D's review |
| **A-13** | A | **A-131-K2** amendment on 131 (D's K2-S1 MEDIUM + K2-S2 LOW): session-stamped bindings, per-session revoke in the sessions trigger, deleted-session JWT fails closed. Rehearsed; **D's re-review closed K2-S1/K2-S2 and found F-131-K2a MEDIUM (session-end reason was rule 5's `signed_out`) — fixed at `f3963a3` (`session_ended`), 198 60/60 + negative control, full suite 5034/5034, CI green run 34982075970; **D PASSED 131 at `f3963a3`** (full harness PASS 23/0/2 declared, races KR1–KR5, B3 → 42501)** | — | done | 131 branch `f3963a3` |
| **A-14** | A | CI egress block + fails-closed gate with deterministic probe (interim for item 6) — **VERIFIED by D** (run 34979345542 probe refused; throwaway negative control 34979941133 probe answered 200 → gate failed as required); merged into the candidate | — | done | ci.yml; D's log |
| A-11 | A | Release packet | A-9, D-5, C-5 | Fri | packet section |
| B-1 | B | 126 parts 2–3 + rollback + 193 (A8 cap; `mixed` + `legacy_upper_bound_cents`) | `048eeb1` | **Tue** review-ready | certified harness full suite; negative controls vs 120/part 1 |
| B-2 ✔ | B | L1 edge (#64) merged Tue; **130** supersede claim (#65) reviewed by A and merged Tue — 4967/4967, S1–S4 concurrency, RED evidence | — | Wed EOD | done a day early |
| C-1 | C | 128 client: **provisional now**, final delta at freeze | A-3 | Wed | unit; DV-611 |
| C-3 ✔ | C | Device plan + build config (`7a5e225`) | — | Tue | done |
| C-4 ✔ | C | F1 → 1..4 → recovery rebased onto `57b3a00` (33 commits, `231f120`), merged Tue | A-9 | Thu | done |
| C-5 | C | Handset verification | A-10b | Fri | DV rows PASS with read-backs |
| D-1 | D | Automated sandbox runner incl. SBX-2 steps | — | Tue | dry run |
| D-3 | D | 128 pass 3 on A-1b commit | A-1b | Tue | findings |
| D-3b ✔ | D | **Independent O-3 disposition** — brief §12: only b2 closes the completed-redirect path, under C1–C6 | — | done | brief §11/§12 |
| **B-3** | B | **132** (REQUIRED before production, owner 2026-09-15) — Option B pre-mint group record (`checkout_group_claim`), PR #70; D's F-132-1 HIGH (cross-mode) and F-132-2 HIGH (cross-buyer best-effort retire) **fixed at `ebbd1c0`** (group key (listing, buyer); edge reads across modes, fails closed on other buyers' processing/uncancellable intents), CI green run 34982027295; D's battery partial before the outage (199/197/194, G1–G6 + controls, edge 77/77); **D ruled the processing residual NOT BLOCKING** (A's production-gate follow-up); **D added F-132-3 (LOW, money) + the reuse-order point (MEDIUM-LOW)** → B: `record_checkout_attempt` FOR SHARE + cancel-and-retire-before-hand-out, G8; ~¾ day after the outage, then CI + D's battery | B, then D | Thu | PR #70; D's review log |
| **D-7** | D | 131 re-review at `f72e2d3` → 133 review → 132 re-review (concurrency/retry/uncertain-outcome battery incl. cross-mode and cross-buyer RED→GREEN) | A-13, A-12, B-3 | Wed–Thu | review log |
| **C-6** | C | K-2 client (`frontend/logout-scope @ 7dbe940`, gated diff approved through 74b9c48; 7dbe940 F-K2-3 pending A's read) + 131 client delta (`frontend/session-bound-131-r2 @ b48f4e9`) — production-gate stack, NOT in build 17 | new pin + build authorization | — | backlog branch |
| D-4 | D | 126 review | B-1 | Tue/Wed | findings |
| D-5 ✔ | D | Incremental on `4b012fd`: PASS 22/0, WARN 2 declared; 197 45/45; S1–S5 + C1; E1–E6 RED reproduced independently; first run invalidated and redone by D | — | Wed AM | done |

## Sandbox sequencing — what genuinely couples, what doesn't
- **Genuine dependency:** SBX-2 (125→128) must follow Phase A (124) — ledger order. 125 is native-track but a
  body-only replace; it enters the sandbox only so 126–128 sort after it.
- **Genuine dependency #2 (D, confirmed by the registry's own rule):** the venue migration `20260910120000` sorts
  **above** 125–128 in `LC_ALL=C` order, so applying it first would put the sandbox tip above them and drop
  125–128 out of the default plan exactly as 128-before-125 would. **Order is therefore: Phase A (124) → SBX-2
  (125→126→127→128, the two edges, DV-611) → Phase C previews → venue Phase B last**, or venue in its own later
  window. The owner's authorization covers both phases; only their order changes. Venue/admin work never gates
  the marketplace verification. Owner MFA (venue exposure, step B4) is therefore the **last** owner act, Thursday
  at the earliest.
- Owner MFA is needed **only** at the venue exposure step (B4); A announces it.

## Critical path (revised — no merge waits)
- **Money chain:** B-1 review-ready (Tue) → D-4 + **B-2 in parallel** (Tue–Wed) → A merges 126 (Wed) → B-2 review
  → A merges (Thu AM) → pin.
- **Notification chain:** A-1b (Tue) → D pass 3 (Tue) → freeze (Wed AM) → C-1 final delta (Wed) → C-4 (Thu AM) → pin.
- Then: pin (Thu midday) → D-5 + SBX-2 (Thu) → **build Thu** → C-5 (Fri) → packet (Fri).
- Longest pole: **B-2 review-ready Wed EOD**, now decoupled from 126's merge.

## Is Friday achievable
Deployment-ready **as defined above is achievable Friday** if: (1) D's pass 3 on 128 and D's 126 review return no
design-level finding (tonight's F1 is why this is the main risk); (2) B-2 is review-ready Wed EOD; (3) the
Thursday build submits after D-5 and SBX-2; (4) Friday's handset rows pass. If any handset row fails Friday, the
candidate is **not** deployment-ready and re-pins Monday. Nothing here is a scope cut: L1 stays required.

## Disk outage 2026-09-15 (environmental, not a result)
The Mac's data volume reached 100%; local Postgres hit ENOSPC and entered recovery; every session's shell failed with ENOSPC. Nobody deleted anything; the owner moved files to an external drive. Measured on resumption: 12 GiB free (94% used), Postgres 17 up, not in recovery, rehearsal databases intact. Runs attempted in the window (D's 133 refusal matrix) are void and repeated. B's 132 close-out and A's Wednesday integration moved by about ¾ day; sandbox acceptance unaffected. Owner: "This is a resumption instruction, not production-deployment authorization."

## Owner actions
| | Status |
|---|---|
| O-1 sandbox window (SBX-1 + SBX-2) | **AUTHORIZED 2026-09-15** with conditions; A announces the MFA step |
| O-2 hosted candidate build | **AUTHORIZED 2026-09-15** (one EAS preview/internal build from the final reviewed pin) |
| O-3 128 residual — **production security gate** | **(b) chosen 2026-09-15: session-bound bindings required before production; the persistent-redirection path is NOT accepted.** Open sub-choice b1 / b2 / b3 — brief §11 (A) + §12 (D): only **b2** (provider-side proof) closes the completed-redirect path, under D's C1–C6, ~3–4 working days + one more pin/build; **b1** discloses + detects, does not close; **b3** not recommended. Tracked explicitly; sandbox acceptance does not waive it |
| O-5 132 placement | **REQUIRED before production (2026-09-15)** — B implements, D reviews (two HIGH findings open), A integrates |
| O-6 K-2 | **APPROVED 2026-09-15** |
| O-7 C's pushes | **AUTHORIZED 2026-09-15** (non-force); tool allowed them |
| O-8 production reads | the two disclosed reads stay unauthorized historical evidence; exact L-1 query + purpose in the packet §2 for the eventual preflight approval |
| O-9 production-gate pin + build | **NEEDED**: 131(+K2) + 132 + 133 + C's K-2/131 client delta = a new pin and a new build; the one-build authorization covers build 17 only |
| O-10 build-17 bundle inspection | needs the owner's permission to download the EAS artifact (C's rule); runtime evidence recorded instead |
| O-11 throwaway CI branch | `ci/egress-negcontrol-throwaway` (negative control, must stay red) — deletion of the remote branch was refused by A's tool; owner or B deletes it |
| O-4 C-2 scope | **CONFIRMED** |
Later (FL-2, in the packet): apply/deploy authorization; `AUTODEPLOY-VERIFIED-OFF`; deploy-window schedule; Stripe
`payment_intent.canceled` subscription; PFA-32; `auction-media` scope.
