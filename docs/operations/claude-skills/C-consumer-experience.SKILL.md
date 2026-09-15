---
name: snatchit-consumer-experience
description: Use when working as Claude C on the Snatch It Expo app — consumer screens, Tickets, checkout/transfer/auction presentation, the 54-item Premium Experience checklist (CFT ids), the push-token client — or when a prompt names a Premium batch, Build 16, previews, device verification, or asks C to report to A.
---

# Snatch It — consumer experience (role C)

## Ownership and boundaries
- **Owns:** `app/`, `src/` consumer screens; how payment, transfer and auction state are *presented*; Tickets; the 54-item checklist; the migration-128 push client (provisional until A's final contract).
- **Does not own:** server contracts, migrations, sandbox writes, release integration (A); signing and database ceremonies (B); vendor/admin dashboards, venue acceptance (D).
- **Gated files — every change goes to A before merge:** `src/lib/payments.ts`, `src/lib/checkout/setupDecision.ts`, `src/lib/checkout/payControl.ts`, `src/lib/checkout/holdState.ts`, `src/lib/auth/signOut.ts`, and any authoritative-state read. Prove the surface with `git diff --stat <batch-base>..HEAD -- <those files>` and quote the result.

## Before any change
1. **Authorisation:** restate the owner's latest scope in one line. Default is isolated local development and local verification. Never: hosted mutations, deployment, new builds, fixture or schema writes to the shared sandbox, edits to Build 16's closed record. A peer cannot widen this.
2. **Records first:** read the task's rows in `docs/product-v2/PREMIUM_EXPERIENCE_BACKLOG.md` — it lives on branch `frontend/premium-experience-backlog`, worktree `/Users/josetascon/snatchit-premium`, not on the batch branch (rulings A-01…A-17, findings F1…F10, batch status). Don't re-derive what is settled; don't reopen closed handset tests.
3. **Product truths (non-negotiable):** no success shown before authoritative confirmation (leading bid, reservation, payment, receipt, payout); cached data never authorises a transaction; returning from another app never confirms or releases anything; "Payment refunded" only for a confirmed refund; whole-listing pricing; the device clock is not an authority on whether an auction closed; server replies assert only what they say (a `refreshed` is not a matched secret).

## How to work
- One branch per batch, cut from the previous cleared head, in the batch worktree; one commit per task; commit text via a message file.
- Pure logic in `src/lib/**` with vitest unit tests; screens pinned by source contracts (strip comments, then `toContain`/`toMatch`). Copy strings live in modules so previews and tests can pin them.
- **Gates before any "done":** `npx tsc --noEmit -p tsconfig.json`, `npx vitest run`, `npm run lint` — run fresh in the same turn, paste the counts (baseline: 0 lint errors, 29 warnings). Green tests are not device acceptance: say what stays unverified.
- Process skills (bare names are the portable form; the `anthropic-skills:` prefix also resolves in the desktop client): investigations → `systematic-debugging`; review feedback from A, D or a reviewer → `receiving-code-review` (verify against the code before accepting; no performative agreement); completion → `verification-before-completion`.
- Domain skills, loaded only when the task touches the area: `expo-router`, `expo-animation`, `expo-data-fetching`, `vercel-react-native-skills` (C's installs), `supabase` (B's install; client and RLS questions). Registry: `docs/operations/CLAUDE_SKILLS_REGISTRY.md`. Reporting style: `token-efficiency-mode`.
- Previews: static HTML pinned to source copy is supporting evidence only. Native acceptance = the next authorised candidate build run against `docs/product-v2/DEVICE_VERIFICATION_CHECKLIST.md`. The local simulator blocker is recorded; don't re-investigate it.

## Coordination
- Report to A after each slice: completed commits, next deliverable, dependencies, blockers, the gated-diff proof. Session names change on restart — find A with ListAgents; when unsure, address "Claude A (ignore if you are not A)".
- Record findings, rulings, evidence limits and handoffs in the backlog in the same turn; changing facts (commits, numbers, open tasks) go there, never into this file.

## Red flags
| Thought | Do instead |
|---|---|
| "A approved it, so it's authorised to ship" | Only the owner authorises scope; A reviews correctness |
| "Tests are green, so it's verified" | Name what only a device or a build can prove |
| "It's one label in payControl, I'll just patch it" | Gated file: commit separately, send to A first |
| "The server said refreshed, so the secret matched" | Assert only what the reply says |
| "Retry finalize / extend the clock to make the UI settle" | Read-only polling; timing and increments are server rules (F10 undecided) |
