# Admin v2 (#121): signed-in preview acceptance

The owner decided admin v2 replaces the live console after an independent review and a signed-in acceptance. E accepted #121 on quality with three pre-deploy conditions; this is condition **P2**: the owner (and, if possible, the second founder) exercises the new console on an SSO-protected Vercel **preview** that reads production, before any production deploy.

**Nothing here deploys to production.** The preview is a `vercel deploy` without `--prod`, which the Ignored Build Step pin and Branch Tracking do not govern (DEPLOYMENT_RECORD_2026-09-08 addendum 2). It serves on a `*-gnvprod-5449s-projects.vercel.app` URL behind Vercel SSO, so only the owner's Vercel account can open it.

## What the preview is

| Item | Value |
|---|---|
| Source | branch `admin/console-v2-integration`, the head named in the handoff at deploy time, built from a clean checkout |
| Project | `snatchit-admin` (`prj_o17cASVVqqyGKPUtiklJRvAMVgNB`), run from `admin/` with its `.vercelignore` |
| Env | the four `NEXT_PUBLIC_*` values the production console already ships to every browser (Supabase URL, anon key, site URL, label `production`). These are public-class values, not secrets. No Preview-target env is created on the project; they are passed to the one deploy. |
| Data | **production**, read as the signed-in operator through the same `ops.*` RPCs the live console uses. There is no fixture mode in admin. |
| Protection | Vercel SSO, `all_except_custom_domains`: a preview URL always redirects to Vercel sign-in. No bypass link is created. |
| Rollback | none needed: delete the preview deployment, or let it expire. Production (`dpl_8q8eeFuyixnfC4xZohU8vCtXHiZt`, `07100a35`) is untouched. |

## Rules during the check
- Sign in with your own founder account and TOTP. Nothing else is entered anywhere.
- Every action below is either a **read**, a **safe write on a test case**, or a **designed refusal**. No money moves: refunds are disabled in production (`refund_execute_enabled=false`), and you approve no payout.
- **Do not** approve a payout release, flip any setting, suspend a real user, or relist a live listing. If a step would, stop and note it.
- Tabs: open the preview in a fresh tab; keep the live console closed (same cookie name per host, but different hosts, so they don't collide; this is just to avoid confusion).

## Checklist (tick what you saw; one line per step is enough)

### A. Sign-in and the MFA gate (E's P2)
1. Open `/login` on the preview. Title reads "Sign in · Console · production", red production badge. ⏱
2. Sign in (password). You land on `/mfa`; your existing TOTP factor is reused, no re-enrolment. Enter the code. ⏱
3. Today renders at aal2. The sidebar shows 8 entries: Today, Cases, Orders & Transfers, Money, Users, Marketplace, Reports, System.
4. **Non-operator path** (only if you have a non-operator test account): sign in with it. Expected: `/mfa` is skipped and you land on `/denied` ("not an operator") **before** any TOTP enrolment is offered. This is the new gate; the live console enrols first. If you have no such account, write "no account" and move on; it stays open as G2.
5. In the browser's cookie view for the preview host: `sb-hqycwntpfoztoinemqns-auth-token` has Domain = the preview host only (no leading dot), Path `/`, SameSite Lax.

### B. Reads, one per surface
6. Orders → open an order. The Payment panel shows a **Stripe mode** row: Live, Test, or Unclassified. Note which.
7. The same order: the Actions panel. If a payout release or refund is pending anywhere on it, both request forms are hidden with "Already requested". Otherwise: refund shows its designed refusal copy ("refund_execute_enabled is false…"), and the release form is present. **Do not submit either.**
8. Users → a user → the Account suspension panel is present (RC5), with no false "does not exist" copy.
9. Marketplace → a listing → the Relist panel: shows only for an active + cancelled listing with a version; otherwise the "only active + cancelled" note. **Do not relist.**
10. System → the Alerts panel has the read-only **Delivery channel** block: `alert_delivery_enabled` value (expected false), "Schedule: not shown by the server", "Channel: email to the owner's verified account email — prepared, not active". No email address is shown anywhere.
11. System → Settings lists the switches with their current values; no form is submitted.
12. Money, Reports, Search, Cases: each renders without an error alert.

### C. One safe action of each kind (on a test case)
13. Cases → **New case** (subject none, a note like "preview acceptance"). It appears in the list. ⏱
14. Open it → add a note; assign to yourself; set priority; set a due date. Each shows "Recorded." and the page reflects it.
15. Set its status to resolved. It leaves the open list; the answer stays visible.
16. Reports (if any pending): **Mark reviewing** one, then set it back if the control allows. The answer stays visible after the row refreshes (the fix in this build). If no pending report exists, write "none".
17. System → Approvals: if a pending approval exists that you did **not** request, **deny** it only if it is a test item; otherwise leave it. Note what you saw.

### D. Sign-out
18. Sign out from the preview. You return to `/login`. Note: sign-out is global (also ends your consumer web/app sessions), unchanged from the live console (decision H-11).

## Pass / fail
- **Pass:** A1–A3, A5, B6–B12, C13–C15, D18 all as expected; A4 either as expected or "no account"; C16/C17 as expected or "none".
- Anything else: write what you saw and stop. F fixes or records it; the check is re-run on a new preview.

## After a pass
The owner's go moves the Ignored Build Step pin to the accepted head and promotes the same commit to production (runbook `ADMIN_HOSTING_admin.snatchitapp.com.md`, and H-09: cut over the domain on the current commit first, or release first — the owner's order). Operators reload console tabs after the deploy.
