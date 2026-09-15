# Release packet — C section (consumer candidate) — TEMPLATE, fill on Fri 2026-09-18

Status: SKELETON. Every field below is empty until the candidate build exists
and the device plan has run. Nothing here is a claim.

## Pinned source and artifact
- Integrated source commit (A publishes): `________`
- C's stack rebased onto it: batches 1–4 + `frontend/candidate-recovery` — head after rebase `________`; gated diff vs the pin: `git diff --stat <pin>..<head> -- src/lib/payments.ts src/lib/checkout/setupDecision.ts src/lib/checkout/payControl.ts src/lib/checkout/holdState.ts src/lib/auth/signOut.ts` → `________` (expected: payControl.ts from ac31172 and signOut.ts from 9091397 + 6659ed9 only, both approved)
- EAS build: profile `preview` (sandbox), build id `________`, build number `________`, date `________`, device `________` (model / iOS), tester `________`

## Gates at the pinned head (run fresh, paste counts)
- `npx tsc --noEmit -p tsconfig.json` → `________`
- `npx vitest run` → `____ files / ____ tests / ____ failed`
- `npm run lint` → `____ errors / ____ warnings`

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
