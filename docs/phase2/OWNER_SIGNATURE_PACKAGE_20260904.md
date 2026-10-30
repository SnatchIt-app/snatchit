# SNATCH IT — OWNER SIGNATURE PACKAGE (2026-09-04)

**These signatures ratify ENGINEERING / GOVERNANCE decisions only. They DO NOT authorize applying
migrations, running the KMS ceremony, deploying edges, configuring production, moving money, or
activating anything. Production authorization is a SEPARATE, later, explicit owner instruction.**

Signature mechanism (repo convention): the owner records approval INLINE in
`docs/architecture/_governance/POST_FREEZE_AMENDMENTS.md` on the relevant PFA block, in the established
form `OWNER SIGNATURE: APPROVED (YYYY-MM-DD). STATUS: SATISFIED / RATIFIED.` This package is a
convenience index; the amendments file is the system of record.

**STATUS: SIGNED.** The owner provided these approvals in-session on **2026-09-04** and they are recorded
verbatim in POST_FREEZE_AMENDMENTS.md under "OWNER SIGNATURES RECORDED — 2026-09-04" (and reflected on
each PFA's STATUS line as SATISFIED / RATIFIED). The signature lines below are filled from the owner's
explicit in-session approval — not self-signed by engineering. Each decision's exact approval text is in
its PFA block and in the "OWNER GATE RATIFICATION TRAIN — 2026-09-03" addendum.

Each item authorizes **DEVELOPMENT/GOVERNANCE ONLY** unless stated otherwise. None authorizes production.

---

**PFA-18B — emergency signing-key REVOKE un-park.**
Decision: `kernel.revoke_signing_key` un-parks under a SINGLE `platform_admin` + aal2 (an emergency
tightening — it reduces authority). It revokes the key, force-closes dependent open door episodes, emits
DoorManifestInvalidated (#44), blocks a new episode opening on revoked trust, and the signer refuses the
revoked pinned key. `provision_signing_key` / `rotate_signing_key` REMAIN parked under PFA-18A — this
signature MUST NOT un-park them.
Consequence: a compromised key can be killed fast without a quorum; arming (provision/rotate) still needs
the future dual-control build. Engineering landed DARK as migration 106.
Authorizes: DEVELOPMENT ONLY.
**OWNER SIGNATURE: APPROVED (owner, in-session)  DATE: 2026-09-04**

**PFA-26-UNPARK — door PIN launch KDF.**
Decision: `venue.create_door_pin` / `venue.mint_door_session` un-park using pgcrypto **bcrypt cost 12**,
per-hash random salt, stored verifier only (never plaintext/reversible, never returned). The door-session
edge rate-limiter (venue‖device, 5/60, fail-closed) is the brute-force control. Argon2id is optional
future hardening, NOT a launch requirement.
Consequence: door PINs become usable at launch with a real slow KDF. Engineering landed DARK as
migration 107.
Authorizes: DEVELOPMENT ONLY.
**OWNER SIGNATURE: APPROVED (owner, in-session)  DATE: 2026-09-04**

**PFA-PT-6 — credential wire format.**
Decision: the ticket credential stays JWS-compact `b64url(header).b64url(payload).b64url(signature)`;
header `{alg,kid,typ}`; payload `{atom,sess,ver,iat,exp}`; NO PII, NO display fields, NO embedded
verification key, NO KMS handle; `typ`/domain enforcement mandatory. No redesign.
Consequence: locks the on-the-wire credential shape the signer stamps and the verifier checks.
Authorizes: DEVELOPMENT ONLY.
**OWNER SIGNATURE: APPROVED (owner, in-session)  DATE: 2026-09-04**

**PFA-PT-8 — algorithm pinning.**
Decision: verification authority is the trusted key's metadata resolved by `kid`; token `alg` MUST equal
`kernel.signing_key.algorithm`. No `alg=none`, no fallback, no try-multiple, no attacker-selected
algorithm, no symmetric/asymmetric confusion.
Consequence: a token cannot choose its own verification primitive. Engineering landed as migration 103.
Authorizes: DEVELOPMENT ONLY.
**OWNER SIGNATURE: APPROVED (owner, in-session)  DATE: 2026-09-04**

**PFA-PT-9 — terminal-session / scan rulings (items 1 & 3 need signature).**
Decision: (1) migration 104's terminal-session `record_scan` gate is ratified — a cancelled/completed
session cannot commit an online scan; (3) NO `credential_version` backstop is added to `record_scan` —
currency stays at C37 / the verifier. (Item 2 — terminal transition force-closes manifests — is
engineering-landed in migration 109; item 4 — the bounded offline `not_after` residual — is accepted;
item 5 — break-glass admin transfer during an open episode requires force-close/refresh — is a runbook
step.)
Consequence: fixes the "cancelled session still admits" gap without deviating the frozen `record_scan`
signature.
Authorizes: DEVELOPMENT ONLY.
**OWNER SIGNATURE (items 1 & 3): APPROVED (owner, in-session)  DATE: 2026-09-04**

**KMS D1 / D2 — provider + algorithm (already recorded; countersignature optional).**
Decision: D1 = **AWS KMS** (asymmetric); D2 = **ES256 / ECDSA P-256 (SHA-256)**. Recorded in
`PRODUCTION_SIGNING_KMS_CEREMONY.md` §1.2. Selecting the provider/algorithm is a decision, not a
production action — no key is created here.
Authorizes: DEVELOPMENT/GOVERNANCE ONLY (the ceremony is a separate later production operation).
**OWNER SIGNATURE: APPROVED (owner, in-session)  DATE: 2026-09-04**

---

**NOT IN THIS PACKAGE (do not sign here):**
- **PFA-PT-7 (TAX):** a **LEGAL/TAX decision**, not an engineering signature. The owner must either affirm
  the current "compute-none / client-advisory-refuse" posture or decide the enforcement locus + rate/model
  with counsel. This blocks the FIRST CONTROLLED SALE (the client will not quote), NOT the dark migration.
- **`deletion.post_event_hold_hours`:** an owner business/legal value. It gates account-erasure timing
  only; it does NOT block migration / KMS / edge deploy / event publish / first sale.
- **Production authorization** to apply 093→109, run the ceremony, deploy edges, configure, or activate —
  a separate explicit owner instruction issued AFTER the preflight.
