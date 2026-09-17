# Require proof before marking a transfer sent — compatibility evidence and migration proposal (A, 2026-09-17) — NOT enforced; no number allocated

**Owner's ruling (2026-09-17):** "Keep the older-client overload compatible for this repair. Record requiring proof before marking
sent as the intended future behavior once supported clients can comply; bring me the compatibility evidence and migration
proposal before enforcing it."

## 1. What 140 does today (kept)
`mark_transfer_sent(uuid,uuid)` delegates with `null::text`; the pending branch writes `transfer_evidence_path = coalesce(p, existing)`.
So a client that omits the path — the 2-key body, or a 3-key call with a null path — still transitions to `seller_sent` **without
proof**, creating the stranded state that `attach_transfer_evidence` recovers. 140 makes those clients strictly better off (a retry
that used to raise now answers `already_sent`; they ignore the return value and check only `error`), so nothing is urgent on their
behalf. The urgency is elsewhere (§3).

## 2. Compatibility evidence — what the tree shows (B, 2026-09-17, verified from source) and what it cannot
| Fact | Evidence | Limit |
|---|---|---|
| No caller in the current tree sends the 2-key body | both live callers send all three keys: `app/transfer/send/[id].tsx:130` and `web/src/lib/transfers.ts:247`; `web/src/lib/transfers.ts:233-240` documents why (omitting the third key silently hits the 2-arg overload and drops the evidence write) | tree only |
| The last 2-key caller left the tree on **2026-09-08** | `src/screens/ListingDetailScreen.tsx` no longer calls the verb; the `supabase.rpc('mark_transfer_sent', {` line was deleted in `92cfe51` ("Integrate the v2 frontend and the reservation-cancellation fix onto the payments RC") | history is squashed before 92cfe51, so the FIRST 3-key build cannot be dated from the repo |
| A shipped build sent the 2-key body | 0553's header records Build 13 sending it from that file (line 798) | which shipped builds are still **installed and calling** is App Store / TestFlight version data or a production read — **neither is held**; B could not supply it and A has not read it |
| Build 18 (`aad5f75`) sends 3 keys | C from source (`6a5b854` onward) | the sandbox build, not the store build |

**What the owner can supply that no session can:** the App Store / TestFlight distribution by build for the last 30 days.
**The alternative, a named production read (NOT executed, NOT authorized here):**
`select date_trunc('week', seller_sent_at) as wk, count(*) from public.transfers where status = 'seller_sent' and transfer_evidence_path is null group by 1 order by 1;`
— aggregate counts by week, no identities; shows whether proof-less transitions are still arriving and at what rate. (The §6 contract read, `count(*) … transfer_evidence_path is null`, sizes the backlog; this one sizes the inflow.)

## 3. Why it matters (verified by B, not inferred)
A proof-less `seller_sent` row is not only unrecoverable-without-attach; it is diverted to a human: `supabase/functions/_shared/payout-policy.ts:258`
`if (!c.has_evidence) highReasons.push('EVIDENCE_MISSING')` pushes the payout to HIGH and into manual review. Every old-client send therefore
costs a manual payout decision AND a stranded row. That, not client breakage, is the argument for requiring proof at the transition.

## 4. The migration proposal (a future number from the registry; written only when the owner asks)
- **Change:** in the pending branch of `mark_transfer_sent(uuid,uuid,text)`, when the caller is `authenticated`, refuse a null or empty
  `p_transfer_evidence_path` with `precondition_failed: evidence path is required` (P0001); the `service_role` fallback path keeps today's
  behaviour for one release so any server-side caller is not broken silently, then follows. The 2-arg overload is **kept as a
  signature** and made to raise the same error (dropping it would 404 old clients at PostgREST, which is a worse failure than a clear
  message), and is dropped in a later migration once the inflow is zero.
- **Client gate that must precede it:** a minimum supported build for the send screen (the app has no server-side min-version gate today —
  to be confirmed from source before the number is allocated); older builds must see a clear "update to send tickets" state, not a raw error.
- **Rollback:** restores 140's bodies (hash-verified, as 140's rollback restored 0550/0553's).
- **pgTAP:** 2-arg raises; 3-arg with null/empty raises; 3-arg with a path transitions; service_role fallback still transitions during the
  grace release; negative control per branch with a writing mutant (207's fidelity rule).
- **Sequence:** (1) owner supplies the installed-build data or authorizes the named read in §2; (2) inflow at or near zero for the
  agreed period; (3) client gate shipped in a candidate and observed on a device; (4) migration written, reviewed (A → D), CI green;
  (5) production window with the standing preflight — applied only on the owner's word.

**Until then:** 140 as integrated stays the behaviour; attach serves the inflow; the sprint table carries this as "future, with the owner".
