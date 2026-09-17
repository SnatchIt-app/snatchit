# My Tickets — sandbox fixture-and-cleanup proposal (A, 2026-09-17; for the owner's approval; nothing executed)

**Purpose:** put one real ticket in the DV buyer's My Tickets tab on the sandbox so CFT-801 can run on a handset, without
enabling native issuance. **Environment:** `ofaidukbieeekqaboscm` only. **Status:** proposal; every statement below is a
shape, rehearsed on the local harness before any window, executed only inside an owner-authorized window with D witnessing.

## 1. What the read requires (from the source at the pin)

`public.get_my_tickets()` (`20260909000000`, on the sandbox at ledger 141) is `security definer` and projects
`kernel.tickets t join catalog.event_session s join catalog.event e join catalog.venue v join venue.ticket_type tt where
t.current_owner_id = auth.uid()`. So a visible ticket needs **eight rows across three schemas**, not one:

| # | Row | Required columns (NOT NULL without defaults) and guards | Note |
|---|---|---|---|
| 1 | `kernel.organization` | `legal_name`, `display_name` (status defaults `applied`) | fixture org, named `FIXTURE …` |
| 2 | `catalog.venue` | `org_id`, `name`, `neighborhood` (`approval_status` defaults `draft`; the read does not filter on it) | |
| 3 | `catalog.event` | `venue_id`, `org_id`, `title` (`status` defaults `draft`) | |
| 4 | `catalog.event_session` | `event_id`, `starts_at` (`status` defaults `scheduled`) | future `starts_at` so it lists under Upcoming |
| 5 | `venue.ticket_type` | `event_id`, `kind` (`admission`), `name`, `price_minor > 0`, `currency` | |
| 6 | **`kernel.signing_key`** | `kernel.tickets.signing_key_id` is **NOT NULL** with FK `fk_tickets_signing_key` (084). The insert guard (`kernel.guard_signing_key_insert`, 110/111) **refuses anything but**: `scope='global'`, `status='active'`, `algorithm='ES256'`, `kms_handle_ref` matching a full AWS KMS key ARN pattern, `public_key` exactly one SPKI PEM block decoding to the 91-byte uncompressed P-256 key, no private material; `not_before` required; one ACTIVE key per scope target | **a fixture key row is a syntactically valid trust root** on the sandbox: a well-formed but non-existent ARN plus a locally generated P-256 public key whose private half is discarded |
| 7 | `kernel.tickets` | `event_session_id`, `org_id`, `ticket_type_id`, `serial_no`, `current_owner_id` = the DV buyer, `signing_key_id`; `state` defaults `issued` | |
| 8 | `kernel.ticket_ownership_log` | custody constraint trigger (`tg_custody_head_is_ledger_tail`, deferred to COMMIT) demands a tail row: `sequence` 1, `to_identity` = owner, `cause` ∈ the fixed list (`issue`), `cause_ref` uuid, `actor_identity`, `command_idempotency_key`, `credential_version_after` = 0, `state_transition` jsonb | |

## 2. The finding that changes the proposal: **the fixture cannot be cleaned up**

- `kernel.ticket_ownership_log` carries `tg_ownership_log_append_only` (`079:114-117`): **UPDATE and DELETE raise**. The log
  row can never be removed.
- `kernel.ticket_ownership_log.ticket_atom_id` references `kernel.tickets` **ON DELETE RESTRICT**, so while the log row exists
  the ticket cannot be deleted; `kernel.tickets.signing_key_id` references `kernel.signing_key` ON DELETE RESTRICT, so the
  fixture key cannot be deleted either; and the catalog rows are referenced RESTRICT up the chain.
- Therefore **"cleanup returning `kernel.tickets` to 0"** (the manifest's own condition for any populated-Tickets fixture,
  §6) is **impossible by the schema's design** without a manual override — disabling an audit-immutability trigger as
  `postgres` — which is the class of act the owner has ruled out ("without a manual support override") and which would
  falsify the ownership ledger's append-only property on the sandbox.
- **Consequence:** whatever is inserted is permanent on the shared sandbox: one ticket, one ownership-log row, and **one
  active global ES256 fixture key that becomes the sandbox's trust root for as long as the sandbox exists.** The sandbox's
  standing pre-flight invariants `kernel.tickets = 0` and `signing_key = 0` would be gone for good and every later window's
  pre-flight table must change.

## 3. Options for the owner

| Option | What it is | Cost | Recommendation |
|---|---|---|---|
| **A — permanent fixture, invariants amended** | insert rows 1–8 once, in one transaction, all ids fixed and prefixed `fixture`; no cleanup; amend the sandbox invariants to `kernel.tickets = 1`, `signing_key = 1 (fixture, ARN non-existent)` and record the fixture in the manifest | a fixture trust root on the sandbox forever; a sandbox that no longer mirrors production's "no native data"; B must review the key row; two exclusions lifted for one window. **Signing-monitor consequence (D), settled by a sandbox read 2026-09-17 02:56Z:** `signing.monitor_enabled = false`, `signing.expected_key_fingerprint` null, `signing.expected_max_not_after` null (all v1, restricted); the `monitor-signing-key-invariants` cron runs daily on the sandbox (last three runs succeeded as no-ops) and `kernel.admin_audit` holds zero `invariant_alert` rows — so today a fixture key raises nothing. **The latent cost, at its real strength (D):** the sandbox is the surface on which arming the signing monitor (production ceremony C5) would be rehearsed. With a planted key present that rehearsal has two outcomes and both are bad — it surfaces a MISMATCH against a key we put there and the rehearsal is invalid, or someone "fixes" it by setting `signing.expected_key_fingerprint` to the fake key's fingerprint, at which point the sandbox's monitor configuration attests to a forged trust root and every later comparison there is meaningless. So the property is not "a risk if someone flips a switch": **the sandbox could no longer be used to rehearse trust-root monitoring honestly** — a capability spent permanently for a layout preview; and a well-formed non-existent ARN paired with a real P-256 SPKI is an object that claims KMS backing it does not have — a future reader would conclude the sandbox has a trust root, which no read distinguishes from the real thing without resolving the ARN. **This is a new category of authorization:** every window so far carried cleanup; a change that cannot be undone must be asked for as such, not as a line item | **not recommended** even if the owner accepts permanence — not for a layout preview (A and D) |
| **B — fixture with an override cleanup** | as A, then cleanup by disabling `tg_ownership_log_append_only` as `postgres`, deleting the eight rows in reverse, re-enabling | breaks the append-only guarantee once, by hand, on the sandbox; exactly the manual override the owner rejected for Path B; the trigger exists to make ownership history non-repudiable and a precedent for switching it off in a sandbox is a precedent | **never** (A and D) |
| **C — no fixture; populate through the real path later** | wait for the native issuance chain on the sandbox: a sandbox signing key provisioned by the ratified path (B), `feature.native_issuance_enabled` ON on the sandbox only by ruling, `primary-checkout` deployed to the sandbox, one primary sale by the DV buyer → `issue_ticket_atoms` writes rows 7–8 legitimately (rows 1–5 come from D's venue fixtures) | populated Tickets on the sandbox waits for Track 4/5 work (weeks); the rows are still permanent, but they are real | **recommended**: the only path where a ticket row is not a lie about the trust root |
| **D — client-side fixture on a dev client** | the `__DEV__`-only fixture toggle already in `app/(tabs)/tickets.tsx` renders sample tickets with no server row | needs a dev client build, not the preview build; proves the screen, not the contract. **Requirement (D): an on-page marker, not only a record note** — fixtures render behind a visible "fixture mode / no server data" label on the Tickets screen, the venue dashboard's `NotWiredState` precedent, so a screenshot carries its own caveat and a clean-looking populated list can never circulate as issuance working; C adds the label (small) | acceptable for **screen** verification of CFT-801's layout rows only; recorded as "fixture mode, no server evidence" **and** labelled on the page |

## 4. If the owner chooses A anyway — exact shape (rehearsed locally first; ids illustrative)

```sql
begin;
-- 1 org · 2 venue · 3 event · 4 session · 5 ticket type (D's venue fixture set has equivalents; reuse it if the venue window ran)
insert into kernel.organization (org_id, legal_name, display_name) values ('0f1c7e00-…-0001', 'FIXTURE Org (My Tickets)', 'FIXTURE Org');
insert into catalog.venue (venue_id, org_id, name, neighborhood) values ('0f1c7e00-…-0002', '0f1c7e00-…-0001', 'FIXTURE Venue', 'Sandbox');
insert into catalog.event (event_id, venue_id, org_id, title) values ('0f1c7e00-…-0003', '0f1c7e00-…-0002', '0f1c7e00-…-0001', 'FIXTURE Event (My Tickets)');
insert into catalog.event_session (session_id, event_id, starts_at) values ('0f1c7e00-…-0004', '0f1c7e00-…-0003', now() + interval '30 days');
insert into venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, currency) values ('0f1c7e00-…-0005', '0f1c7e00-…-0003', 'admission', 'FIXTURE GA', 100, 'USD');
-- 6 fixture key: well-formed ARN of a non-existent key; a real P-256 SPKI PEM generated locally, private half destroyed
insert into kernel.signing_key (key_id, scope, status, algorithm, kms_handle_ref, public_key, not_before)
values ('0f1c7e00-…-0006', 'global', 'active', 'ES256',
        'arn:aws:kms:us-east-1:000000000000:key/00000000-0000-4000-8000-000000000000',
        $pem$-----BEGIN PUBLIC KEY-----
<91-byte P-256 SPKI, base64, generated with openssl on A's machine; private key deleted>
-----END PUBLIC KEY-----$pem$, now());
-- 7 ticket · 8 custody tail (checked at commit)
insert into kernel.tickets (ticket_atom_id, event_session_id, org_id, ticket_type_id, serial_no, current_owner_id, signing_key_id)
values ('0f1c7e00-…-0007', '0f1c7e00-…-0004', '0f1c7e00-…-0001', '0f1c7e00-…-0005', 1, '<DV buyer 919d511e-…>', '0f1c7e00-…-0006');
insert into kernel.ticket_ownership_log (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref, actor_identity,
  command_idempotency_key, credential_version_after, state_transition)
values ('0f1c7e00-…-0007', 1, null, '<DV buyer>', 'issue', '0f1c7e00-…-0008', '<DV buyer>', 'fixture:my-tickets:1', 0,
        '{"from": null, "to": "issued", "fixture": true}');
commit;
-- verification: select count(*) from public.get_my_tickets() as the buyer = 1; flags all false; census unchanged; D reads the same
```
Cleanup under A: **none possible** (see §2). Under B: not proposed. The signing-key row must be reviewed by B before any
window, since it becomes the sandbox's active global key (the signing monitor is disabled on the sandbox; the door edges are
not deployed there; `get_ticket_signing_context` would nevertheless answer with the fixture key).

## 5. What this proposal does not do
It enables no flag, mints nothing through the issuance path, touches production nowhere, and authorizes nothing; it exists so
the owner can choose with the full cost visible. **Joint recommendation (A and D): D now** — a dev-client fixture mode for
layout, zero database impact, the pattern the venue dashboard already uses (`NotWiredState` in database mode), recorded as
"fixture mode, no server evidence"; **C later** — the real issuance path; **never B**; **A only if the owner explicitly accepts a
permanent, irreversible change on the shared sandbox, asked for as such**, in which case B reviews the key row, D witnesses,
and the read-back includes the monitor's next run and its alert rows, not only the eight fixture rows.
