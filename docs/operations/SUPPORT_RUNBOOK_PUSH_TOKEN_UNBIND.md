# Support runbook — `unbind_push_token` (b2 item 8, DRAFT by B for D's review, 2026-09-16)

**Status:** draft, revised 2026-09-16 after D's review, and again after D's 135 review (D-135-5: RB-1 closed; this file is docs-only and changes nothing that was applied) (D answered the four open points; they are now rules, with D's reasons kept). It authorizes nothing; running any step against production needs the owner's authorization, and the verb is service-role only.

**RB-1 is CLOSED (D, MEDIUM — taken into migration 135).** An unbind does **not** erase the token's history. `unbind_push_token` revokes and tombstones: `is_active=false`, `device_secret_hash` cleared, `revoked_reason='support_unbound'`, `session_id` cleared, **the row kept**, and any open challenge on that token consumed; the reply is `{unbound, contract_version: 3}`. Because the row survives, the next account to claim that token still gets `challenge_required` and must prove possession — so support is **not** a way around b2. Verified at the stack pin (135 §6b; `release/production-gate-20260918` @ `9bef640`). Before 135 the verb deleted the row, which is what made this an open risk; §5 keeps that caveat for anyone reading against an older build.

## 1. What this is for
b2 gives a device a self-service route: the server sends a one-time nonce to the token, the device echoes it, and the binding moves to the account that proved possession. That route needs **the physical device**. Support unbinding is the exception for when proof cannot reach it:

- the device is lost, stolen, destroyed or wiped;
- the device no longer receives push (permission revoked, uninstalled, provider token dead);
- the user cannot use the app at all on that device (locked out of the account that holds the binding).

It is **not** for impatience with a challenge, a user who has the phone in hand, or "the code did not arrive on the first try". Those are challenge retries, and a support unbind there is the redirection path reopened by hand.

## 2. Preconditions before any action
1. The requester is the account holder. Identity checks are the owner's policy; this runbook records them, it does not set them. At minimum, agent-verified: signed-in session on another device, or the account's registered email or phone confirmed out of band.
2. The device really is out of reach. Ask which of the three cases above applies, and record the answer.
3. **Challenge history — a gate you can only half-pass today (D-135-6).** *When the console read exists (§8):* check it first; if a challenge was issued and never confirmed, prefer reissuing it, and a confirmed challenge means the device answered and no unbind is needed. *Until it exists:* do not treat this step as passed, and do not guess whether the device already answered. Ask the user instead whether a confirmation prompt or a code reached the device, and whether the replacement device has tried to register — asking **whether** one arrived is allowed; asking them to read it to you is not (§6). If the device can still receive it, have them complete the challenge and do not unbind. If you cannot establish that, proceed and record under §3 that the challenge history was unavailable. An engineer-run read of the challenge rows is **not** a routine substitute: it is a production read and needs the owner's authorization for that specific read, so it belongs to an escalation, not to an ordinary ticket.
4. **Two-person rule on EVERY unbind** (D): one agent proposes, a second approves. The harm here is not financial, it is a notification redirect that survives a password change, which is the thing b2 exists to stop. Volume should be tiny by design; if it is not, the pressure valve is reissuing a challenge, never a looser unbind.

## 3. Information to record, every time
- The ticket id, the requester and how identity was verified.
- Which case (lost / destroyed / no push / locked out) and the user's own words.
- The token id (never the token string in a ticket) and the account it is bound to.
- The last challenge id and outcome **when the console read exists (§8)**; until then record the literal words "challenge history unavailable" plus what the user said about a prompt or code reaching the device (§2.3). A blank here is indistinguishable from a skipped gate, which is the failure this note exists to prevent.
- The approving second agent.
- The timestamp and the operator.

## 4. The action
- The only supported verb is `public.unbind_push_token(<token>)`, service-role only, run by an authorized operator.
- One token per call. Never a bulk unbind, and never "all tokens for this user" as a shortcut.
- Tell the user plainly what the verb does: it **releases the binding**; it does not end a session and does not sign the lost device out. A replacement device registers its own token and takes the binding by proof of possession.

## 5. After the action
- Read back the row: the binding is **released and tombstoned** (inactive, proof cleared, `revoked_reason='support_unbound'`, row kept), so the next device must still prove possession. This holds **from migration 135 onward**. On any build without 135 the verb DELETEs the row instead, the token's history goes with it, and the next binder registers with no proof — if you are working against such a build, stop and escalate rather than unbinding.
- Record the action in `kernel.admin_audit` under `push_token.unbind` (D: the durable trail belongs there, the 083 append-only pattern the signing monitor already uses). The admin console reads that trail; it does not keep a second one.
- The previous owner receives the existing in-app security notice, as for any ownership change.
- **No cool-down** (D): proof of possession already gates the next bind, and a cool-down would only delay the legitimate replacement device.
- If the "lost" device later comes back and registers again, it goes through the ordinary challenge; the unbind does not privilege it.

## 6. What support must never do
- Never move a binding straight from one account to another. Unbind, then let the new device prove possession.
- Never read or relay a nonce, or a 6-digit code, to a user. The code reaches the device, never the agent. A user reading a code to an agent is the phishing shape the copy warns about ("never share this code").
- Never unbind because a challenge is inconvenient.
- Never accept an email alone when the account also has a phone on file and the request is to move a device.

## 7. The four open points, answered by D (2026-09-16)
1. **Two-person rule:** every unbind, not only payout accounts. Folded into §2.
2. **Cool-down:** none. Proof of possession already gates the next bind. Folded into §5.
3. **Audit record:** `kernel.admin_audit`, action `push_token.unbind`, plus the existing in-app notice. Folded into §5.
4. **Challenge history for support:** yes, outcomes only — token id, created, expires, confirmed, attempts, delivery outcome. Never the nonce, the nonce hash or the token string. It is an admin-console read on D's surface, to be specced when 135 lands, owner-gated like the rest.

## 8. Still open
- **RB-1 — closed** (see the top): 135 tombstones instead of deleting, so this runbook's read-back in §5 is the behaviour of the stack, not an assumption about it.
- **The support-facing challenge history** (§7.4) is specced but not built, and §2.3 and §3 are written around its absence (D-135-6). D owns the read: it is an admin-console read on D's surface, owner-gated, and §3 points at it. Until it exists, an agent cannot see challenge outcomes and must not infer them from anything else.
