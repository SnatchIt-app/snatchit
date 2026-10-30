# Real-service acceptance gates — procedures and evidence

These gates decide whether the deployed console becomes the founders'
operating portal. They run against the **real** Supabase project and the
deployed Vercel build, performed by the founders/owner. The local harness
(auth stub, no Storage, no Stripe) is **not** evidence for G1, G4 or G6.

Tools: `admin/scripts/acceptance/gates.sql` (read-only evidence queries, SQL
editor) and `admin/scripts/acceptance/gate-probe.mjs` (founder-run probe;
prompts for password/TOTP locally, never in chat, stores nothing).

| Gate | Procedure | Pass evidence | If it fails |
|---|---|---|---|
| **G1** each founder completes real MFA | Founder opens the console URL, signs in with their own account, is routed to `/mfa`, scans the TOTP QR in their authenticator, verifies; lands on Today. Repeat for the second founder. | `gates.sql` §G1 shows both operator rows with `verified_totp_factors ≥ 1`; `gate-probe.mjs` prints `PASS G1-verify … aal=aal2`. | Do not add `ops` to exposed schemas / keep it removed; keep existing SOPs. |
| **G2** non-operator denied | An ordinary account (not in `admin_users`; a founder can use a personal test account they already own) runs the probe. | `PASS G2-whoami (42501)`, `G2-read`, `G2-mutation`, `G5-unrelated 0 objects`. Visiting the console shows "Your account is not an operator". | Containment §5.4 of the runbook (un-expose `ops`). |
| **G3** lower-assurance session denied | A founder runs the probe **before** entering the TOTP code (session at aal1). | `PASS G3-protected-read` and `G3-mutation` (step-up refusals). In the browser, an aal1 session is held on `/mfa`. | Same as G2. |
| **G4** founder opens eligible evidence | On an order where the founder is neither buyer nor seller and evidence is recorded, click **Open evidence · audited**; the file opens. Prefer a clearly identified test order if one exists; otherwise a real one, viewed once, with the audit row as the record. | File renders; `gates.sql` §G4 shows an `evidence.viewed` row with that founder's role and slot; probe `PASS G4-open`. | Drop policy `proof-docs operator read` (runbook §5.5); evidence review stays in the Storage UI. |
| **G5** unrelated user refused; arbitrary paths refused | Probe as non-operator (`G5-unrelated`); probe as operator (`G5-bad-slot`, `G5-arbitrary-path`). | All three PASS. | Same as G4. |
| **G6** signed links expire | Probe with a transfer id: it signs a 60-second URL, opens it, waits 70 s, re-opens. | `PASS G6-expiry` (4xx after expiry). The console's own links use a 300 s TTL from the same signer. | Same as G4. |
| **G7** pause/containment reversible | In System → Settings set `actions_enabled = false` (reason required). Then, on any case, try to add a note — refused with the "actions are paused" banner; Today/search still render. Set it back to `true`; add the note — succeeds. Use a **synthetic case** (System → Cases → New manual case) — never a payment or payout. | `gates.sql` §G7 shows both setting changes; the note exists after un-pause. | If the switch cannot be flipped back from the console: `update ops.setting set value='true' where key='actions_enabled'` in the SQL editor. |
| **G8** refunds demonstrably disabled | Probe as operator: `G8-endpoint-absent` (404) and `G8-setting` (false). Optionally request a refund on any captured order: it must be rejected up front as `disabled`. | Both PASS; `gates.sql` §G8 shows only `rejected/disabled` refund actions (or none). | Stop: refund enablement is a separate, later authorisation. |

## Harness rehearsal (2026-09-07, local, NOT real-service evidence)

Run against the local PostgREST + auth-stub harness with the real 000→120
migrations: G2 → 403/403/403; G3 (aal1) → 400 step-up on read and mutation;
G5 bad slot / bad kind → 400; G8 refund request → `rejected / disabled`; G7
pause → mutation 400, read 200, un-pause → mutation 200. This proves the
database-side behaviour; it does not prove GoTrue MFA, Storage signing or link
expiry.

## Order of operations on release day

1. Release steps 1–5 of `RELEASE_CHECKLIST_RC3.md` (migrations, ledger, exposure, detectors, Vercel).
2. G1 for founder A, then G3 and G1 for founder B (probe before and after TOTP).
3. G2/G5 with a non-operator account.
4. G4/G6 with one evidence file.
5. G7 with a synthetic case.
6. G8.
7. Only then: retire the old deployment's privileged variables (checklist step 7). Until every gate passes, the existing SQL packs and Stripe Dashboard SOPs remain the system of action and the old portal is left untouched (it is not a fallback; it is simply not yet retired).
