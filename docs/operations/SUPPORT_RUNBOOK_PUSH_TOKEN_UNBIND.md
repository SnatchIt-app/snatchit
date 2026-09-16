# Support runbook — `unbind_push_token` (b2 item 8, DRAFT by B for D's review, 2026-09-16)

**Status:** draft, revised 2026-09-16 after D's review (D answered the four open points; they are now rules, with D's reasons kept). It authorizes nothing; running any step against production needs the owner's authorization, and the verb is service-role only.

**Open dependency (RB-1, D, MEDIUM):** today `unbind_push_token` DELETEs the row, and under contract v3 it is the token's history that forces a proof. An unbind therefore erases the history, and the next binder gets `registered` with no proof — support would be the documented way around b2. D's fix, for A's migration 135: unbind *revokes and tombstones* (`is_active=false`, proof cleared, `revoked_reason='support_unbound'`, row kept). §5 below is written for the tombstone; if A does not take it, §5's read-back changes and this runbook must say plainly that an unbind reopens the no-proof window.

## 1. What this is for
b2 gives a device a self-service route: the server sends a one-time nonce to the token, the device echoes it, and the binding moves to the account that proved possession. That route needs **the physical device**. Support unbinding is the exception for when proof cannot reach it:

- the device is lost, stolen, destroyed or wiped;
- the device no longer receives push (permission revoked, uninstalled, provider token dead);
- the user cannot use the app at all on that device (locked out of the account that holds the binding).

It is **not** for impatience with a challenge, a user who has the phone in hand, or "the code did not arrive on the first try". Those are challenge retries, and a support unbind there is the redirection path reopened by hand.

## 2. Preconditions before any action
1. The requester is the account holder. Identity checks are the owner's policy; this runbook records them, it does not set them. At minimum, agent-verified: signed-in session on another device, or the account's registered email or phone confirmed out of band.
2. The device really is out of reach. Ask which of the three cases above applies, and record the answer.
3. Check the challenge history first: if a challenge was issued and never confirmed, prefer reissuing it. A confirmed challenge means the device answered and no unbind is needed.
4. **Two-person rule on EVERY unbind** (D): one agent proposes, a second approves. The harm here is not financial, it is a notification redirect that survives a password change, which is the thing b2 exists to stop. Volume should be tiny by design; if it is not, the pressure valve is reissuing a challenge, never a looser unbind.

## 3. Information to record, every time
- The ticket id, the requester and how identity was verified.
- Which case (lost / destroyed / no push / locked out) and the user's own words.
- The token id (never the token string in a ticket), the account it is bound to, and the last challenge id and outcome.
- The approving second agent.
- The timestamp and the operator.

## 4. The action
- The only supported verb is `public.unbind_push_token(<token>)`, service-role only, run by an authorized operator.
- One token per call. Never a bulk unbind, and never "all tokens for this user" as a shortcut.
- Tell the user plainly what the verb does: it **releases the binding**; it does not end a session and does not sign the lost device out. A replacement device registers its own token and takes the binding by proof of possession.

## 5. After the action
- Read back the row: the binding is **released and tombstoned** (inactive, proof cleared, reason recorded, row kept), so the next device must still prove possession. Under a delete-instead-of-tombstone build, that guarantee does not hold — see RB-1 at the top.
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
- **RB-1** (top of this file): whether 135 tombstones instead of deleting. A owns it; this runbook is written for the tombstone.
