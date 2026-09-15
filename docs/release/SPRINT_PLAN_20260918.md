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
| A-10 ◐ | A | SBX-2 begun Tue night from the pin: **124 ✔, 125 ✔** (ledger 130 → 132, md5-verified); **126 STOPPED — the sandbox lacks 110–120 (no `ops` schema)**; 127/128 not attempted; owner rules (a) parity 110–120 first or (b) skip 126 on the sandbox and continue; 129/130 still need the O-1 extension; venue last | owner | Wed | manifest §10 |
| **A-10b** | A | **Hosted build** (EAS `preview`, sandbox) from the pin; verify compiled env; record source + build IDs | **authorized**; A-9, D-5 | **Thu** | build record in the packet |
| A-11 | A | Release packet | A-9, D-5, C-5 | Fri | packet section |
| B-1 | B | 126 parts 2–3 + rollback + 193 (A8 cap; `mixed` + `legacy_upper_bound_cents`) | `048eeb1` | **Tue** review-ready | certified harness full suite; negative controls vs 120/part 1 |
| B-2 ✔ | B | L1 edge (#64) merged Tue; **130** supersede claim (#65) reviewed by A and merged Tue — 4967/4967, S1–S4 concurrency, RED evidence | — | Wed EOD | done a day early |
| C-1 | C | 128 client: **provisional now**, final delta at freeze | A-3 | Wed | unit; DV-611 |
| C-3 ✔ | C | Device plan + build config (`7a5e225`) | — | Tue | done |
| C-4 ✔ | C | F1 → 1..4 → recovery rebased onto `57b3a00` (33 commits, `231f120`), merged Tue | A-9 | Thu | done |
| C-5 | C | Handset verification | A-10b | Fri | DV rows PASS with read-backs |
| D-1 | D | Automated sandbox runner incl. SBX-2 steps | — | Tue | dry run |
| D-3 | D | 128 pass 3 on A-1b commit | A-1b | Tue | findings |
| **D-3b** | D | **Independent O-3 disposition** | A-3b | Tue | written, attached to the brief |
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

## Owner actions
| | Status |
|---|---|
| O-1 sandbox window (SBX-1 + SBX-2) | **AUTHORIZED 2026-09-15** with conditions; A announces the MFA step |
| O-2 hosted candidate build | **AUTHORIZED 2026-09-15** (one EAS preview/internal build from the final reviewed pin) |
| O-3 128 residual — **production release** acceptance | **OPEN** — decision brief `O3_128_RESIDUAL_DECISION_BRIEF.md`; D's independent disposition attached when in; test authorization does not decide it |
| O-4 C-2 scope | **CONFIRMED** |
Later (FL-2, in the packet): apply/deploy authorization; `AUTODEPLOY-VERIFIED-OFF`; deploy-window schedule; Stripe
`payment_intent.canceled` subscription; PFA-32; `auction-media` scope.
