# Two items raised on the 2026-09-23 release night — assessed 2026-09-24 (A) and RETRACTED AS FINDINGS by D (2026-09-24 ~03:30Z)

**Status: neither is a finding.** F-1 is the house pattern (D: 69 kernel functions carry `authenticated` EXECUTE on the same auth.uid()-derived basis, including admin_refund, grant_platform_role and release_payout; granting service_role would make auth.uid() null and the verb raise). F-2 is housekeeping. Both records below stand as the evidence for that conclusion.

Owner instruction: "record the exact affected object, practical consequence, evidence and owner. Assess urgency from the actual access and detection paths; prepare bounded fixes where warranted, without applying production changes." No production change was made or is proposed here.

## F-1. `kernel.resolve_dispute_native` — EXECUTE granted to `authenticated`, not `service_role`

| | |
|---|---|
| **Exact object** | `kernel.resolve_dispute_native(p_dispute_id uuid, p_outcome text, p_reason_code text, p_command_key text) returns jsonb`, SECURITY DEFINER, `search_path = ''` — defined and granted by `088_market_native_rail.sql:913` (grant at :1850). Siblings `kernel.record_dispute_native(...)` and `kernel.mark_dispute_state(...)` are granted to `service_role` (:1859–1860). |
| **What it actually does** | Authority first: `auth.uid()` required, then `kernel.is_platform(array['platform_risk','platform_support','platform_admin'])` (077: a `kernel.platform_role` row for the caller, or `public.admin_users` membership for `platform_admin`) — else `42501`. Then input validation and a `kernel.dispute_native` existence check. Then it **always raises** `precondition_failed: dual_control_unavailable` (PFA-31, "PARKED FAIL-CLOSED … ZERO mutation"; header 088:905–912). It resolves nothing, by design, until the dual-control mechanism exists. |
| **Practical consequence** | None today. The grant is the design, not an inconsistency: the record/mark verbs are edge (service-role) writers; `resolve` is a human platform-staff verb (identity-checked like its "identity twin", 096 header), so `authenticated` is the correct grantee and `service_role` is deliberately absent. `kernel` is PostgREST-exposed, so any logged-in user can *call* it — and receives `42501` unless they hold a platform role; a platform-role holder receives `dual_control_unavailable`. No mutation is reachable by any caller. No edge, admin, venue or client code references it (grep across `supabase/functions`, `admin/`, `venue/`, `src/`, `app/` at the gate: none); `kernel.dispute_native` holds 0 rows (D, production read 02:29Z). |
| **Evidence** | Source lines above (gate `5b255838`, which production's kernel schema matches per the 2026-09-22 release read-backs); D's grant and row-count reads from production 2026-09-24 02:29Z. |
| **Owner** | B (kernel / native rail design, PFA-31) with the owner for the un-park decision (DISPUTE_DUAL_CONTROL). |
| **Urgency** | None. Access path: platform roles only, and even they cannot mutate. Detection path: not applicable. **No fix warranted.** The one thing to carry: when the native dispute handling is ever wired into stripe-webhook (edge, service role), it must call `record_dispute_native` / `mark_dispute_state`, never `resolve_dispute_native` — the grant split enforces that. |

## F-2. Open ops case `650e7344…` "watched by no detector"

| | |
|---|---|
| **Exact object** | `ops."case"` id `650e7344-27f2-4b5c-a4c7-9d4b2cbf3f0e`: `case_type = 'manual'`, `subject_kind = 'none'`, no subject, `priority p3`, `detector = 'manual'`, status `open`, created and last seen 2026-09-08 01:42:03Z, unassigned, title **"Acceptance probe G7 — synthetic case (safe to dismiss)"**; four events (created, action_requested, note_added, action_outcome). Read 2026-09-24 02:52Z. |
| **Practical consequence** | It is a synthetic case created by the admin-console acceptance probe G7 (2026-09-08, the console go-live) and left open. `manual` cases are, by definition, never re-detected or auto-resolved (only detector-owned case types go through `ops.detect_sweep` → `ops.case_auto_resolve`), so "no detector watches it" is the designed behaviour for its type, not a detection gap. Effect: it counts as 1 of the 19 open cases and shows in the console's open list; no money, alert, or customer impact; no alert row is tied to it. |
| **Evidence** | Production read above; 115/117 source: `case_auto_resolve` is invoked per detector case type from `detect_sweep`; `manual` has no detector. (Note for the record: a substring probe for detectors mentioning the type matched `detect_payout_review` only because its source contains `manual_review` — a false match, discarded.) |
| **Owner** | D (console acceptance; the probe's author) to dismiss it through the console's own audited action (`ops.case_dismiss`/dismiss with a note), or the owner. |
| **Urgency** | None. **Bounded fix:** one operator dismissal in the console, with note "acceptance probe G7 — synthetic". It is a production write (an audited runtime action, not SQL), so it is NOT performed under this instruction; it is queued for whoever the owner designates. No code change. |

## Not a finding, but adjacent and worth one line
The three "present but inert" features (native dispute wiring; b2 push challenge; 139 report dedupe) and their independent dependencies are recorded in SPRINT_STATUS_20260917.md (2026-09-24 entries). F-1 above is the grant note that belongs with the first of them.

## Additions from D's retraction (2026-09-24)
- **PFA-31 park = a third, independent reason the native dispute feature does nothing**, separate from the missing edge import (nothing imports native-dispute.ts) and from the notify-exposure question (irrelevant to it): native dispute RESOLUTION is parked fail-closed until a dual-control mechanism exists (DISPUTE_DUAL_CONTROL). Recorded in the inert list.
- Open-case composition at 02:29Z (D): 19 = 5 dispute_open + 8 paid_unsettled + 3 report_review + 2 refund_pending + 1 synthetic probe (650e7344). `ops-detect-tick` runs `run_all_detectors` every 5 minutes over 13 named detectors, none of which emits type `manual`.
- Rule applied: an edge function must never call resolve_dispute_native with the service key; it forwards the operator's own JWT (EA-1, as delete-account does).
