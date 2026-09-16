# Support runbook — `unbind_push_token` (b2 item 8, DRAFT by B for D's review, 2026-09-16)

**Status:** draft. It describes the support route that remains after b2 ships. It authorizes nothing; running any step against production needs the owner's authorization, and the verb is service-role only.

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
4. Two-person rule for any account with an active payout destination, mirroring the payouts pattern. One agent proposes, a second approves.

## 3. Information to record, every time
- The ticket id, the requester and how identity was verified.
- Which case (lost / destroyed / no push / locked out) and the user's own words.
- The token id (never the token string in a ticket), the account it is bound to, and the last challenge id and outcome.
- The approving second agent.
- The timestamp and the operator.

## 4. The action
- The only supported verb is `public.unbind_push_token(<token>)`, service-role only, run by an authorized operator.
- One token per call. Never a bulk unbind, and never "all tokens for this user" as a shortcut.
- Confirm with the user that the app has been signed out on the lost device's behalf, and that the next sign-in on a replacement device registers a fresh token and takes the binding by proof.

## 5. After the action
- Read back the row: the binding is gone and no new binding exists until the replacement device proves possession.
- The previous owner receives a security notice, as for any ownership change.
- If the "lost" device later comes back and registers again, it goes through the ordinary challenge; the unbind does not privilege it.

## 6. What support must never do
- Never move a binding straight from one account to another. Unbind, then let the new device prove possession.
- Never read or relay a nonce, or a 6-digit code, to a user. The code reaches the device, never the agent. A user reading a code to an agent is the phishing shape the copy warns about ("never share this code").
- Never unbind because a challenge is inconvenient.
- Never accept an email alone when the account also has a phone on file and the request is to move a device.

## 7. Open points for D's review
1. Whether the two-person rule should apply to every unbind or only to accounts with a payout destination.
2. Whether a cool-down should follow an unbind (for example, no new binding on that token for N minutes) or whether proof of possession makes that unnecessary.
3. Where the audit record belongs: the `notify` audit surface used for rebinds, or the admin console's own trail.
4. Whether support should be able to see challenge history at all (it needs outcomes, not nonces); if yes, that is an admin-console read and belongs to D's surface.
