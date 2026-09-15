# Release packet — C section (consumer candidate) — TEMPLATE, fill on Fri 2026-09-18

Status: IN PROGRESS (2026-09-15). Source and artifact fields are filled from verified facts; device results
stay empty until the plan has run. Nothing below claims device acceptance.

## Pinned source and artifact
- Integrated source commit (A publishes): **`aabe029`** = tag `candidate/2026-09-18-pin` on `release/candidate-20260918` (CI run 34932209458 green, five jobs; D-5 incremental PASS; SBX-2 verified by A: sandbox carries 124, 125, 127–130, 126 deferred by owner ruling; `stripe-webhook` v4 + `create-payment-intent` v4 deployed from the tag, byte-identical)
- C's stack rebased onto it: batches 1–4 + `frontend/candidate-recovery` — head after rebase **`231f120`** (33 commits on `57b3a00`, merged by A at `37213e7`; `app/` and `src/` at the tag byte-identical to the approved `db5bddf`); gated diff vs the pin: `git diff --stat aabe029..231f120 -- src/lib/payments.ts src/lib/checkout/setupDecision.ts src/lib/checkout/payControl.ts src/lib/checkout/holdState.ts src/lib/auth/signOut.ts` → **5 files, +461/−18** = batch 1's approved surface + `payControl.ts` (ac31172, approved) + `signOut.ts` (9091397, 6659ed9, 3ccdac4, 656b3ee, db5bddf — A-8 approved d90db6b..db5bddf)
- EAS build: profile `preview` (sandbox), build id **`53e5e98b-dbe9-405d-a7c8-159375c3fbc6`** (submitted 2026-09-15 from the tag with `--message "candidate 2026-09-18 pin aabe029"`; upload 140 MB; credentials: existing distribution certificate and ad-hoc profile, one provisioned device), build number `________` (remote autoIncrement; expected 17 — read from EAS when finished), device: the Build 16 handset (`________` model / iOS), tester `________`
- Compiled env (to verify from the built bundle, not `eas.json`): sandbox ref `ofaidukbieeekqaboscm`, sandbox anon key (public class), sandbox functions URL → `________`

## Gates at the pinned head (run fresh, paste counts)
- `npx tsc --noEmit -p tsconfig.json` → clean (C on 231f120's tree, identical `app/`+`src/`; A on the merged tree: 0)
- `npx vitest run` → 85 files / 1896 tests / 0 failed (C on 231f120; A on the merged tree 1896/1896)
- `npm run lint` → 0 errors / 29 warnings (both)

## Device verification results (`DEVICE_VERIFICATION_CHECKLIST.md`, plan in `CANDIDATE_BUILD_AND_DEVICE_PLAN.md`)
| Block | Rows | PASS | FAIL | UNTESTED (reason) |
|---|---|---|---|---|
| 0 smoke | — | | | |
| 1 no-window | DV-101, 103+T, 106, 107, 201, 203, 204, 206, 206b, 208, 208b, 605, 607a, 609, 611, 611L, 611C | | | |
| 2 window | DV-301, 302, 304, 305, 306, 308, 202, 203b, 205, 402, 404, 404b, 501, 502, 504, 505, 611S | | | |
| 2b sprint | DV-L1, L2, 607b, 607c, 607d, F8 | | | |
| 3 128 RPC | DV-611R (only if 128 on the sandbox was authorised) | | | |
FAIL rows: defect → fix commit → re-run row → result: `________`

## Preserved from Build 16 (closed record; not re-run unless changed)
D1–D8 as recorded; D9a PASS; D9b PASS on payment safety (D9-UX-1 open → closed in batch 1, re-verified by DV-301: `____`); D9c UNTESTED (no further attempts); D10/D11 server-side PASS (handset wording uncaptured); T PASS on Build 16 → re-run on this build: `____`; F PASS (seven dimensions not covered); populated Tickets UNTESTED (CFT-801).

## Known limitations to state plainly
- 128: client provisional against v2; RPC path verified only if 128 was applied to the sandbox under owner authorisation; otherwise the legacy insert-only path is what shipped and was verified.
- Static previews were supporting evidence only.
- Deferred Premium items: see the backlog's 54-item coverage.

## Owner authorisations that were required (record which were given, when)
- hosted candidate build: `____` · handset install: `____` · sandbox window: `____` · 128 on sandbox: `____`

## Restart instruction (if any C task was left running or unfinished)
`________` (exact branch, commit, command, and what remains)
