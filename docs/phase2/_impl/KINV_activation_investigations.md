# KINV — Activation investigations: deletion clock, credential signer, on_sale/SALEABLE, tax, payout-destination replace, A9 re-proof

**Investigator INV · read-only.** Repo `/Users/josetascon/snatchit-consol`, branch `feature/venue-native-and-product-v2`,
HEAD `cf9b780` (PR #52, CI green). Migrations 093–099 authored/verified/immutable; production is at ledger 107
(through 092); 093–100 NOT applied. **Nothing deployed, no production touch, no Stripe call, no commit — this
document is the only file written.**

**Method.** Fresh local rehearsal DB `snatchit_rehears_inv` (`./scripts/rehearsal_reset.sh snatchit_rehears_inv`,
`PATH=/opt/homebrew/opt/postgresql@17/bin`): **114/114 migrations replayed, `GATE-2 tables=27 functions=70
policies=37 triggers=26`**, matching `ci.yml` `EXPECT_*` exactly. Every claim marked **[V]** below was executed
against that database in this session — `pg_get_functiondef`, `information_schema`/`pg_proc`/`aclexplode` reads,
and `catalog.platform_config` census reads. This train's most relevant prior work already exists at substantial
depth in five documents; where that is true I cite them by path and re-verify their load-bearing claims directly
against bytes rather than re-deriving the whole analysis:

| Prior doc | Covers |
|---|---|
| `docs/phase2/_impl/H2_deletion_clock.md` | item 1, deletion clock — full re-anchor, 28-scenario matrix, already **implemented and live in this tree** |
| `docs/phase2/_impl/H7_kms_gap_classification.md` | item 2, the six KMS-ceremony compensating-control gaps |
| `docs/phase2/_impl/G6_activation_gates.md` | item 3/3b, the four A8 gates, SALEABLE's five clauses, the tax finding (F-4) |
| `docs/phase2/_impl/H6_payout_destination.md` | item 4, payout destination lifecycle, the re-point gap (F-5), attack matrix |
| `docs/phase2/_impl/H1_refund_architecture.md`, `E4_refund_executor.md` | item 5, A9 executor architecture, PFA-23 direct-arm reachability, the 24h reconcile split |

None of these five documents' factual claims were found wrong on re-verification; §§1–6 below state the verdicts,
cite fresh file:line and executed evidence, and flag the one place I add material not already in the corpus
(item 2, the storage-shape gap).

---

## 1. DELETION CLOCK — event-anchored TODAY. VERIFIED LIVE, not merely designed.

### 1.1 Which key is live, which is orphaned — [V]

```sql
select key, version, value, visibility from catalog.platform_config
 where key like 'deletion.%' order by key, version;
```
```
                  key                  | version | value | visibility
---------------------------------------+---------+-------+------------
 deletion.post_event_hold_hours        |       1 | null  | restricted   <- LIVE
 deletion.refund_possible_window_hours |       1 | null  | restricted   <- ORPHANED
```

`deletion.refund_possible_window_hours` is read by exactly **one** function repo-wide, and it is not the
deletion gate:
```sql
select n.nspname, p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where prosrc ilike '%refund_possible_window_hours%';
        →  catalog | set_platform_config      -- the key's own dual-control prefix-list mention, not a read
```
`kernel.deletion_blockers_money` does not mention it at all (full body pulled below). **[V] Confirms
H2 §4/§7.3: the old key is a settable, unread residue.**

### 1.2 Which function reads the live key, and the exact anchor — [V], full body read from the replayed DB

`kernel.deletion_blockers_money(p_identity uuid)` — defined `077:1720`, replaced `085:229`, **replaced again
`093:1529`** (the H2 re-anchor; `git log` shows this landed on `cf9b780`, this branch's current tip). Pulled
directly via `pg_get_functiondef` against `snatchit_rehears_inv` — i.e. this is the **deployed-shape body in
the replayed chain**, not a document's transcription of it:

```sql
-- BP-12 arm 2 (PFA-22, re-anchored by H2):
if exists (select 1 from venue."order" o
            where o.buyer_id = p_identity and o.status in ('paid','partially_refunded')) then
  select v.value into v_raw
    from (select c.value from catalog.platform_config c
           where c.key = 'deletion.post_event_hold_hours'
           order by c.version desc limit 1) v;          -- LIMIT applied before any cast (poison-immune)
  if v_raw is null or jsonb_typeof(v_raw) = 'null' then
    return 'BP-12: post-event deletion hold unset ... with candidate orders present';
  end if;
  ... type/range guards ...
  select max(coalesce(es.ends_at, es.starts_at)) into v_anchor
    from venue."order" o join catalog.event_session es on es.session_id = o.event_session_id
   where o.buyer_id = p_identity and o.status in ('paid','partially_refunded');
  v_matures_at := v_anchor + make_interval(hours => floor(v_hold_hours)::int);
  if now() < v_matures_at then
    return 'BP-12: inside the post-event deletion hold — erasable after ' || to_char(v_matures_at, ...);
  end if;
end if;
```

**The anchor is `max(coalesce(event_session.ends_at, event_session.starts_at))` over the buyer's own
paid/partially_refunded orders — NOT `order.created_at`.** `venue."order".event_session_id` is `uuid not null
references catalog.event_session(session_id) on delete restrict` (join is total and stable). This is the exact
predicate H2 specified and it is **live in the current tree, not a proposal** — the file I read it from is the
one that will assemble into 093 (`093_parts/10_money_settlement.sql` §10j per H2 §4) and it is already the
`create or replace` body at `093:1529` in the current assembled migration.

### 1.3 Driver and the rest of the machine — re-confirmed structurally

`kernel.sweep_deletion_pending` (`077:1865`) drains BP-1..BP-12 in `coalesce` order every cron tick; every arm
except BP-12 arm 2 is a **state** predicate (drains when a real object reaches a terminal state — atom expiry,
payout terminal, dispute closed, etc.), not a clock. BP-12 arm 2 is the only elapsed-time proxy in the whole
machine, and it is now anchored to the event, not the payment. Full 12-row blocker table, full 28-scenario
executed matrix (early purchase, postponement, cancellation, refund pending, refund succeeded, dispute
open/lost, multi-session, multi-day, `ends_at` NULL, session/event deleted via FK-restrict, comp/imported
ticket with no order) is in `docs/phase2/_impl/H2_deletion_clock.md` §2/§5 — all marked **[V]**, executed
against `snatchit_rehears_del`. I re-derived the two structurally load-bearing scenarios independently this
session by reading the deployed body rather than re-running the fixture matrix (time-bounded); the body text
above is sufficient to confirm every row of that matrix mechanically, since the anchor and guard logic are the
entire mechanism the matrix exercises.

**One population still not covered by BP-12 arm 2, confirmed structurally and already named by H2 §6:**
comp/imported ticket holders with an active atom and **no `venue."order"` row** — BP-12 arm 2's `exists (...
venue."order" ...)` guard never engages for them, so they are governed only by BP-1 (atom state, drains at
`ends_at + ticket.expiry_grace`). This is a *narrower*, bounded population (no paid order exists at all), not
a payment-anchored path for paid buyers.

### 1.4 VERDICT

**Deletion is event-anchored today: YES.** No path is payment-anchored for any buyer holding a paid order.
The one payment-anchored predicate that used to exist (`085:262-284`, keyed off `order.created_at`) has been
`CREATE OR REPLACE`'d out of the live function body (`093:1529`) and its config key
(`deletion.refund_possible_window_hours`) is now an orphan, confirmed unread **[V] §1.1**.

### 1.5 Candidate `deletion.post_event_hold_hours` values — enumerated, not chosen

The key is currently seeded `null` (fails closed for every candidate order — **[V] §1.1**). Stripe's dispute
window is **~120 days (≈2880h)** post-charge (https://docs.stripe.com/disputes/how-disputes-work, cited
unchanged from H2 §7 item 5). No value in the ticketing-appropriate range fully covers it; the choice is how
much of the tail to eat as an erasure-latency cost versus leave as unbounded exposure via BP-10
(`identity_obligation` — chargebacks land there regardless of tombstone, per H2 §7 item 2, itself unbounded by
any hold).

| Candidate | Coverage of the ~120d Stripe window | Cost |
|---|---|---|
| **72h (3 days)** | Covers essentially none of the tail — only same-week disputes. Matches `ticket.expiry_grace`'s admissibility grace (G1), so it reads as "door business is done," not "money business is done." | Cheapest for the buyer erasure-rights side; leaves ~117 days of dispute exposure per identity as BP-10-only. |
| **120h (5 days)** | Same order of magnitude as 72h — trivial fraction of 120 days. | Marginal cost over 72h; marginal benefit. |
| **180h (7.5 days)** | Still a small fraction (~6%) of the dispute window. | Comparable to `payout.settlement_maturity_interval`'s existing 7-day default (G2) — internally consistent with an already-accepted "about a week" venue-money horizon, but not a refund/dispute-specific number. |
| **720h (30 days)** — H2's worked example | ~25% of the window. | This is what H2's own 28-scenario matrix was executed against; not an owner recommendation, an execution fixture (H2 §7 item 5 says so explicitly). |
| **2880h (120 days)** | Full nominal coverage of Stripe's dispute window. | Longest erasure latency of any candidate; for a buyer whose event has passed, "your account cannot be erased for 4 months" is a real UX/legal-erasure-rights cost, and BP-10 already catches the chargeback-after-tombstone case regardless (H2 §7 item 2), so full coverage here does not close that gap — it only delays it. |

**No value is selected here.** All five are architecturally identical to implement (`deletion.post_event_hold_hours`
is a single numeric config key, already dual-controlled and range/type-guarded per H2 §4 item 3/4). The trade is
entirely: erasure-request latency for a population whose event has already happened, versus fraction of the
dispute tail treated as "the account may be gone before a chargeback can land against it, and BP-10 is what
catches that." **Owner decision, recorded not resolved.**

---

## 2. CREDENTIAL SIGNER — HARD ACTIVATION BLOCKER. No component produces a signature. Confirmed by both
absence-of-code and absence-of-storage-shape.

### 2.1 No signer edge exists — [V]

```
$ ls supabase/functions/
_shared  auto-finalize-auctions  confirm-and-release  confirm-payment  connect-onboarding
create-connect-account  create-payment-intent  delete-account  enforce-transfer-expiry
notify-report  notify-transfer  payout-execute  primary-checkout  refund-execute  send-push
stripe-webhook
```
No `credential-sign`, no `wallet-pass-issue`, no `door-manifest`. `grep -rl "credential-sign\|KMS.sign\|kmsSign"
supabase/functions/` returns one file (`notify-report/index.ts`, a prose match, not a caller).

### 2.2 `kernel.issue_ticket_atoms` pins a *key reference*, never produces or reads a signature — [V], full body
pulled from the replayed DB (`093:4874`)

```sql
-- ACTIVATION BOUNDARY (§7.1): an ACTIVE signing_key must RESOLVE for the scope.
select k.key_id into v_key from kernel.signing_key k
  join catalog.event_session s on s.session_id = v_session
  join catalog.event e on e.event_id = s.event_id
 where k.status='active' and (k.not_after is null or k.not_after>now()) and k.not_before<=now()
   and (scope resolution: per_event > per_venue > global)
 order by ... limit 1;
if v_key is null then raise exception 'precondition_failed: no_active_signing_key ...'; end if;
...
insert into kernel.tickets (..., credential_version, signing_key_id)
values (..., 0, v_key)
returning ticket_atom_id into v_atom;
```

This resolves and pins **which key** would sign a future credential (`signing_key_id`, `credential_version`).
It performs no cryptographic operation, calls no KMS, and computes no canonical payload. That is correct and
intentional per the frozen spec — the mint's job is scope resolution, not signing.

### 2.3 There is nowhere to *put* a signature either — new finding, not previously stated this precisely

`\d kernel.tickets` (**[V]**, full column list pulled): `ticket_atom_id, event_session_id, org_id,
ticket_type_id, serial_no, current_owner_id, state, resale_state, credential_version, signing_key_id,
home_region, seat_ref, unit_row_id, external_seat_ref, issued_at, created_at, updated_at`. **No signature
column, no credential-token column, no digest column.** `venue.door_manifest_entry.manifest_digest`
(`086:256`) stores a **digest**, not a signature over it — the manifest-signing half of C33's design
(`docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md:963`, "M2 should be [KMS-signed] too") is equally unbuilt.
**Building the signer therefore requires, at minimum, an additive schema change (a new migration) in addition
to the edge function** — the signer is not merely "an edge that's missing," it targets a storage shape that
does not exist yet either.

### 2.4 The intended contract — from the frozen spec, not invented here

`docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §5 ("C33 — credential signing architecture … FULL SPEC",
`:1264-1789`):

- **Canonical payload** (`:412`, `:1277`): `{ atom_id, session_id, credential_version, key_id, issued_at, exp }`.
- **Operation** (`:417`, `:1278`): `KMS.sign(kms_handle_ref, canonical_payload)` — asymmetric sign.
- **Algorithm** (`:1273`): Ed25519 preferred, ECDSA-P256 acceptable, one active key per scope.
- **Edge** (`:1776`): `credential-sign`, `POST`, JWT-verified, caller must be the atom's current owner
  (`auth.uid()`), reads `kernel.tickets`/`kernel.signing_key`, calls KMS, "version-deterministic (no dedup
  row)".
- **Determinism note** (`:424`): "token is byte-reproducible if the signer is deterministic (Ed25519) or
  functionally equivalent (any valid signature) otherwise" — i.e. idempotency/replay is handled by
  determinism or equivalence, not a dedup table.
- **Latency budget** (`:436`, `:1587`): target < 2s, KMS sign itself single-digit ms, p99 < 500ms end-to-end.
- **Key custody** (`:1291`, C33 §5.3): the private key must never touch DB or client; only public/trust/
  bootstrap facts live in `kernel.signing_key` (confirmed by H7 §1 Gap 1: the table carries `public_key`,
  `kms_handle_ref` — a handle, not key material).

### 2.5 VERDICT

**No code today produces an actual ticket-credential signature.** The signing *key infrastructure* (bootstrap
row shape, immutability guard, scope resolution, mint-time pinning) is built and re-verified against current
bytes by H7; the signing *operation* is not. Per the brief's framing, this is correctly classified as a **HARD
activation blocker distinct from "a signing key row exists."** A bootstrap `kernel.signing_key` row alone
changes zero observable behavior for a door — nothing consumes it as a signature yet, and
`feature.native_scanning_enabled` is `false` (`078:1523`, unchanged), so no consumer exists either. H7 §3
already reaches the adjacent conclusion that the KMS *ceremony* is not the true next critical-path item because
three deploy acts and an unmade owner decision (D1, provider) sit in front of it; this section adds that the
*signer component itself*, not merely the ceremony, is unbuilt, and its target storage shape needs a migration.

### 2.6 What a credential-sign component must contain — recommendation only, not built here

1. **KMS Sign, no key extraction.** The private key never leaves the KMS/HSM boundary; the edge calls
   `KMS.sign(kms_handle_ref, canonical_payload)` and receives ciphertext/signature bytes only (matches C33
   §5.3, `kernel.signing_key.kms_handle_ref` already carries the handle, never key material).
2. **Canonical serialization**, fixed and versioned: exactly `{atom_id, session_id, credential_version,
   key_id, issued_at, exp}` in a defined byte order (e.g. deterministic CBOR/JSON-with-sorted-keys) so the
   signature is reproducible and auditable.
3. **Algorithm pinning**: Ed25519 preferred (deterministic, so retries are naturally idempotent) or
   ECDSA-P256; the choice must be recorded per active key, not assumed by the verifier.
4. **Key-version pinning**: the signature must embed `key_id`/`credential_version` so a verifier can select
   the correct public key without guessing, and so key rotation does not retroactively invalidate old tokens
   (ties to H7 Gap 3/5 — `not_after` and revoke-time force-close, both still forward obligations).
5. **Replay/idempotency**: per the spec, achieved through payload determinism (Ed25519) or "any valid
   signature" equivalence (ECDSA) rather than a dedup table — the component must not introduce a second,
   competing idempotency mechanism against `kernel.tickets.credential_version`.
6. **Signature storage**: a new column (or side table) is required — none exists today (§2.3). Whether it is
   stored at all (vs. computed on demand and only cached client-side) is itself an open design question; if
   stored, it must respect the append-only/immutability posture the rest of the credential surface uses.
7. **Verifier contract**: the door-side (offline-capable per spec §5.5/§5.7) must be able to validate a token
   against a *manifest* of currently-active/recently-rotated public keys without a live call — this is the
   M1/M2 manifest distribution mechanism (`086`), itself only digest-stamped today (§2.3), not signed.
8. **Rotation and old-ticket verification**: a rotated-out key must remain verifiable for tickets already
   minted under it until they expire or the retention window closes (C33 §5.6) — this is exactly H7 Gap 3's
   forward obligation ("a retired `rotating` row must stay verifiable alongside an active one").
9. **Failure behavior**: fail closed — no signature, no admission; a KMS outage must not silently degrade to
   an unsigned or locally-signed credential. Consistent with H7 Gap 5's finding that door-episode force-close
   on revoke is also unbuilt — the two gaps compound (revoke does nothing operationally *and* nothing is
   verifying signatures yet, so there is no live attack surface today, but both must land together before
   `feature.native_scanning_enabled` flips).

**Not built. Recommendation only, as instructed.**

---

## 3. ON_SALE vs SALEABLE

### 3.1 A8's text, read in full — `docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md:198-219`

```
| SALEABLE | event may transition to `on_sale` and be purchased | Yes (Connect readiness) |
...
An event may safely be publicly visible before it becomes saleable, and that possibility is preserved.
Checkout must fail closed if the venue organization is not eligible for primary-sale collection.
```

### 3.2 Executed: does `catalog.publish_event(event, 'on_sale', key)` require SALEABLE prerequisites? — [V], full
body pulled from `snatchit_rehears_inv`, `081:899-965` (093 does **not** redefine this function — confirmed by
`grep -c publish_event supabase/migrations/093_primary_ticketing.sql` = 0 hits on a definition)

```sql
-- legal FORWARD transition only (draft→announced→on_sale→live→completed).
v_ok := (v_status='draft' and p_target_status='announced')
     or (v_status='announced' and p_target_status='on_sale')
     or (v_status='on_sale' and p_target_status='live')
     or (v_status='live' and p_target_status='completed');
...
-- on_sale requires >=1 ticket_type WITH a batch — no empty on-sale.
if p_target_status = 'on_sale' then
  if not exists (select 1 from venue.ticket_type tt join venue.inventory_batch b on ... where tt.event_id=p_event_id) then
    raise exception 'precondition_failed: empty_inventory';
  end if;
end if;
```

**The entire `on_sale`-target precondition is: legal forward transition + role check + non-empty inventory.**
No read of `kernel.signing_key`, no read of `catalog.platform_config` (fee), no read of
`kernel.organization.connect_transfers_active` or `stripe_connect_account_ref`. `select count(*) from
kernel.signing_key` returned `0` in the same session and `fee.buyer_service_bps` is seeded `null` — i.e. the
"nothing configured" state is exactly what the current tree's `publish_event` would let through to `on_sale`.

**Contrast: `venue.create_primary_checkout` DOES enforce SALEABLE**, in the current 093 assembled file:
`payout_not_ready` (org's `connect_transfers_active`/`stripe_connect_account_ref`), `no_active_signing_key`,
`service_fee_unset` — grepped and confirmed present at `93:4026`/`:4076`/`:4105` in the current assembled
migration (exact line numbers shift slice-to-slice as the file is regenerated; the refusal strings and their
ordering are unchanged from H6/G6's citations, re-confirmed by grep this session).

### 3.3 Does A8 settle WHERE the gate lives, or is it ambiguous? — AMBIGUOUS, on the enforcement locus only

A8's SALEABLE row conjoins two clauses under one "Requires Connect readiness: Yes": *"event may transition to
`on_sale` **and** be purchased."* Read literally, that pairs the *state transition* and the *purchase* as one
capability gated together — which would mean `publish_event(...,'on_sale')` itself should refuse without
Connect readiness (reading **B**). But the same section's very next sentence singles out a **different**
enforcement point by name: *"Checkout must fail closed if the venue organization is not eligible for
primary-sale collection."* That sentence names checkout specifically and says nothing about the transition
verb — consistent with reading **A**, where `on_sale` is a commercial/marketing label and the money gate lives
only at the point money actually moves.

A8 does **not** resolve this either way with a sentence that names `publish_event` or the transition RPC by
name. **This is a genuine gap, not a disagreement to adjudicate — the ruling text supports both readings and
the shipped code (§3.2) implements reading A by omission** (checkout enforces, the transition does not),
which was a **deliberate build decision, not an accident**: 093's own scope notes explicitly declined to gate
`publish_event` on Connect readiness (cited in `docs/phase2/_impl/G6_activation_gates.md:41`,
`docs/phase2/PRIMARY_TICKETING_ACTIVATION_MATRIX.md:137`), reasoning that `announced` is harmless — reasoning
that (per G6 §5.4, and independently observed here) does not obviously extend to `on_sale`, because `on_sale`
is the state the rest of the product treats as "tickets are live."

### 3.4 VERDICT

**(A) on_sale = commercially published but checkout may be unavailable** is what is **implemented today**, and
it is a coherent, cheap position *provided* the client treats `payout_not_ready` /
`no_active_signing_key` / `service_fee_unset` as a first-class "not actually on sale yet" state rather than a
raw error (G5 §5.4 already specifies that copy). **(B) on_sale must satisfy SALEABLE** is what A8's literal
grammar most naturally reads as, and is not what is built. **A8 does not settle which is intended — it is
ambiguous on enforcement locus, unambiguous only that checkout must fail closed (which it does).**

### 3.5 Draft narrow ruling text (not selected, offered for the owner)

> **A8a — SALEABLE enforcement locus (narrow amendment).** A8's SALEABLE row is clarified: the
> "event may transition to `on_sale`" clause and the "be purchased" clause are DECOUPLED. `on_sale` is a
> **display/marketing state** and carries no Connect-readiness precondition of its own; the storefront and any
> other display surface MUST treat an `on_sale` event whose organization is not SALEABLE-eligible (per
> `venue.create_primary_checkout`'s five clauses) as **"not yet purchasable"**, not as a broken listing. The
> money-side SALEABLE gate is, and remains, enforced exclusively at the point of primary-sale collection
> (`venue.create_primary_checkout` / `venue.reserve_primary_inventory`). No change to `catalog.publish_event`
> is required or authorized under this amendment.
>
> *(Alternative, if the owner instead intends reading B):* **A8a′ — SALEABLE gates the transition.**
> `catalog.publish_event(event_id, 'on_sale', command_key)` MUST additionally refuse with a named precondition
> (e.g. `precondition_failed: org_not_saleable`) unless the organization satisfies the same Connect-readiness
> predicate `venue.create_primary_checkout` enforces, evaluated at transition time. A body-only replacement of
> `catalog.publish_event`, no DDL required.

**Do not choose between A8a and A8a′ here** — that is the owner decision this document exists to surface, not
resolve.

---

## 3b. TAX — zero anywhere in the schema. OWNER/LEGAL activation item, not an architectural blocker.

### 3b.1 Grep, executed against the replayed DB and the source tree — [V]

```sql
select count(*) from catalog.platform_config where key ilike '%tax%';        -- 0
select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('kernel','venue','catalog','public') and p.proname ilike '%tax%';   -- 0
```
Source-level: `grep -rniE '\btax\b' supabase/migrations/*.sql` returns exactly two hits, both **prose comments
recording the absence** (`093:6514`, `:6704`: *"…refund executability checked nowhere; no tax model at all…"*).
No column on `venue."order"` or `public.payments`. The only representation anywhere is client-side and
advisory: `src/lib/pricing/allIn.ts` has an `{status:'applies-unknown'}` branch that refuses to quote (cited
by G6 §5.5, re-confirmed present at that path).

### 3b.2 Classification

**Architecturally, initial launch CAN operate with tax = not-applicable**, given the currently ratified product
scope: A5 fixes venue entitlement at face value "subject only to explicitly modeled adjustments" and nothing
in the frozen corpus (093–099) claims to model tax, so there is no half-built or silently-wrong tax logic to
disable — the absence is total and consistent, not a partial implementation masquerading as complete.

**This is an OWNER/LEGAL decision, not an engineering gate**, for one specific reason: no SQL predicate exists
that could enforce "tax is not applicable here" versus "tax is required here and we are not collecting it" —
there is no gate to configure, no flag to flip, and therefore no way for the system itself to surface a
jurisdiction where zero-tax is legally wrong. That determination (which US states/jurisdictions require sales
tax collection on ticket sales, and whether Snatch It's merchant-of-record structure creates nexus) is outside
what any migration in this corpus can answer, and no rate is invented here. **Recorded and classified, not
solved — matches G6 §5.5's F-4 exactly, independently re-confirmed at zero rows/functions this session.**

---

## 4. PAYOUT DESTINATION REPLACE — Day-2 gap, re-confirmed live in current tree; not launch-blocking.

### 4.1 Current state, re-verified against current bytes — [V] grants, [V] refusal strings

`kernel.set_org_payout_destination` (`093:2995`-ish current assembled position, refusal text
`no_pending_connect_ref` grepped and confirmed present twice — once for first-bind, once explicitly labelled
"a re-point must run through the connect-onboarding edge function", `docs/phase2/_impl/093_parts/30_connect_org.sql:1071,1244`)
has **zero non-comment callers** anywhere in the repo — re-confirmed this session by the same grep H6 ran.

The only path that establishes a destination end-to-end is `supabase/functions/connect-onboarding/index.ts`:
mint (Stripe `POST /accounts`) → stage (`kernel.stage_org_connect_ref`, `service_role`) → bind
(`kernel.set_org_connect_ref`, caller JWT, `org_owner`+aal2) → verify (Stripe `GET /accounts/{id}`) → mirror
(`kernel.sync_org_connect_state`). This sequence is **inside `if (!accountId)`** (`index.ts:1393`, re-confirmed
this session) — i.e. it runs **only when the org has no account yet.** A bound org's re-point has no staging
producer at all: the mint-and-stage block by design (H6's "no-re-mint rule", ruling G T-1) never runs for an
already-bound org.

The `409 destination_unusable` arm exists and is reachable (`index.ts:1512-1513`, re-confirmed this session)
and its message tells the operator to "contact support to change your payout destination" — support's only
route today is a manual `service_role` `stage_org_connect_ref` call plus an out-of-band Stripe mint, which is
not a shipped verb or edge path.

**Two F-3/F-4 hardenings from H6 have already landed in this tree** (confirmed present, `30_connect_org.sql`
§9 `kernel.authorize_org_payout_dashboard` at line `1793`, §10 `kernel.guard_connect_id_not_org_bound`
triggers) — these close the Express-Dashboard bank-account bypass and the reverse cross-plane org-bricking bug,
but do **not** touch the re-point gap itself (H6 §9 explicitly records both as deliberately not built this
train).

### 4.2 Specification of the intended `mode:'replace'` flow — recommendation only, per H6 §2.3/§9, restated
with the requested checklist explicit

A `connect-onboarding` branch, reachable only for an **already-bound** org, must:

1. **`org_owner` only, aal2 required up front** — matching the first-bind authority (SoD-1), not the wider
   `org_owner`-or-`org_finance` gate the reconnect/dashboard branches use, because this changes *which* account
   is the payee.
2. **Audited**: write an `kernel.admin_audit` row (`org.connect_ref.bind`-shaped, mirroring the existing bind
   event) and emit `security_payout_destination_changed`, matching what the first bind already does
   (H6 §1.2, §8.1).
3. **Explicit reason required** — a `reason_code` parameter, not inferred, so "why was this org re-pointed" is
   never reconstructed after the fact.
4. **Safe staging**: mint a *second* Stripe account, stage it via `kernel.stage_org_connect_ref`
   (`service_role`) exactly as first-bind does — no reuse of a `profiles`-plane or another org's account
   (`kernel.guard_connect_id_not_org_bound`, already built this train, would refuse the reverse case).
5. **No arbitrary acct binding**: `kernel.set_org_payout_destination` already enforces
   `connect_ref_not_platform_minted` / `no_pending_connect_ref` (provenance-locked to what *this* flow staged)
   — the existing verb needs no change (H6 §2.2's conclusion stands: "do not build a caller for it" was about
   *not building a caller casually*, not "the verb is wrong").
6. **Stripe-side org verification**: re-run the same `readAccount`/`detailsSubmitted`/`transfersActive` check
   the first bind performs before the org can sell on the new destination — a re-point must not silently
   inherit "verified" status from the old account.
7. **Cooldown/probation interaction**: H6 §4 documents `payout.destination_cooldown_hours` (seeded NULL, fails
   open — F-9) and the probation arm (`087:475-482`, disarmable by a raced paid-after-change payout — F-7).
   Both defects predate and are independent of building a replace flow, but a replace flow that does not also
   close F-1 (no `destination_ref` bound to a payout at claim time, H6 §5) would let a re-point during a
   submitted-but-unexecuted payout silently redirect it — **the replace flow must not ship before F-1's fix
   (bind destination at claim, cross-check-only at execution) lands**, or it inherits an existing race rather
   than merely adding a new door onto it.
8. **Old destination cannot race a payout**: direct consequence of point 7 — this is F-1's fix, a prerequisite
   dependency, not a new requirement invented for replace.
9. **New destination not payable until checks pass**: point 6 restated as a state machine requirement — the
   staged replacement must not become `stripe_connect_account_ref` until verify succeeds, matching the
   MINT→STAGE→BIND→VERIFY ordering H6 §2.1 already establishes as deliberate and correct for first-bind.
10. **Security notification**: `security_payout_destination_changed` to every `org_owner`/`org_finance`,
    matching the existing emit shape at bind time and at the F-3 dashboard-authorization fix (H6 §8.1).

### 4.3 VERDICT: Day-2, not launch-blocking

**Day-2.** No shipped path can reach a bound org's re-point today at all (§4.1) — it is not merely weakly
guarded, it is **structurally unreachable**, which is safer than a half-built replace flow, not less safe. It
becomes urgent the first time a venue rotates a bank/entity or Stripe disables an account (H6 §2.3). **The edge
currently advertises a recovery that does not exist** (`409 destination_unusable` → "contact support" with no
working support verb) — this should stop being advertised (or should be implemented) before it is hit in
practice, but neither action gates the ability to sell tickets at launch. Recorded per H6 §9 as agreed, not
re-litigated.

---

## 5. REFUND EXECUTOR / A9 RE-PROOF — ENGINEERING READY (DARK / UNDEPLOYED).

### 5.1 Existence and dark state, re-confirmed against the replayed DB — [V]

```sql
select key, value from catalog.platform_config where key in ('refund.executor_enabled','payout.executor_enabled');
   refund.executor_enabled  | false
   payout.executor_enabled  | false
```
Both seeded at `099_signing_monitor_and_executor_invokers.sql` PART 2 (`refund-execute-tick` cron `*/2 * * *`,
`payout-execute-tick` cron `*/10 * * *`, both a no-op `CASE` while the key reads `false` — cited from
`docs/phase2/_impl/KM4_099_implementation.md:34`, unchanged).

`supabase/functions/refund-execute/{index.ts,executor.ts}` and `tests/refund-executor.test.ts` (66 tests)
exist and are undeployed (H1/E4, unchanged this session — file presence confirmed by `ls
supabase/functions/refund-execute/`, present).

### 5.2 `claim_refunds_for_execution` and the missing `list_pending_refunds` — [V]

```sql
select proname, pronamespace::regnamespace from pg_proc
 where proname in ('claim_refunds_for_execution','get_refund_execution_context','list_pending_refunds');
     claim_refunds_for_execution  | kernel
     get_refund_execution_context | kernel
     -- list_pending_refunds: 0 rows
```
`kernel.claim_refunds_for_execution` (a **leased claim**, `docs/phase2/_impl/093_parts/10_money_settlement.sql:1236`,
`093:1311`) and `kernel.get_refund_execution_context` (`093:1038`-ish, confirmed present) both exist and are
`service_role`-only (confirmed via `aclexplode` this session, §5.3). `kernel.list_pending_refunds` was
deliberately not built — `claim_refunds_for_execution` replaces it as a leased-claim primitive rather than a
plain list, closing E4's originally-flagged self-heal/sweep gap (H1 §1, superseding note (b)).

### 5.3 Grant surface, re-verified via `aclexplode` this session — [V]

```
claim_refunds_for_execution  → postgres, service_role
mark_refund_state            → postgres, service_role
refund_primary_order         → postgres, service_role
request_order_refund         → postgres, authenticated       <-- reachable directly
```

**`kernel.request_order_refund` is granted to `authenticated`** — confirmed directly by grant, not inferred.
This is the PFA-23 direct-arm reachability H1 §5 establishes: the DIRECT arm's authority is reachable
**through `request_order_refund`**, not through `refund_primary_order` (which is `service_role`-only and
therefore correctly unreachable directly by a platform-admin session, resolving the original E4 "PFA-23's
direct arm is unreachable" claim as **overturned** — it is reachable, just through the request verb rather
than the execute verb, and H1 §5.2's authority table shows why: `request_order_refund` already enforces
`auth.uid()` + role class + rate limiting + reason-code policy, so it is the correct entry point).

### 5.4 The >24h reconcile split — confirmed present, not re-executed (time-bounded; cited, not re-derived)

`docs/phase2/_impl/H1_refund_architecture.md` §4.3: Stripe retains an idempotency key's result for exactly 24h;
inside that window a replay of `refund_<refund_id>` returns the original Stripe object safely, outside it the
executor's `reconcile` mode is required — `reconcileOne` **establishes before it creates** (looks up by
`metadata[refund_id]` before issuing a new refund), closing the double-refund hole E4's original failure
matrix missed for cases 2/3/13. This is a documented code-path distinction inside
`supabase/functions/refund-execute/executor.ts` (`executeOne` vs `reconcileOne`), not re-read line-by-line this
session — flagging as **cited from H1, not independently re-executed** per the evidence-first instruction.

### 5.5 VERDICT

**A9 is ENGINEERING READY (DARK/UNDEPLOYED)**, not blocked. Every named component exists and is internally
coherent: the executor edge, the leased-claim primitive, the execution-context reader, the direct-arm
authority path through `request_order_refund`, and the 24h reconcile split. What remains before A9 is
*satisfied in production* is deployment plus arming an invoker — `refund.executor_enabled=false` and no cron
job is scheduled from a migration (per KI §7, cited unchanged: "no cron, no `net.http_post`, no schedule" for
the automated disjunct), so today a `sweep` action would have to be triggered manually. That is an activation
step (deploy the edge, decide invoker option A — a 096-style cron migration — or option B — a written human
process, per `KI_activation_sequencing.md` §6.1/§7), not an unbuilt architecture. **Not deployed here, per
scope.**

---

## 6. OPEN QUESTIONS FOR THE ORCHESTRATOR/OWNER

1. **§1.5** — `deletion.post_event_hold_hours` value: 72h / 120h / 180h / 720h / 2880h or another. No default
   fully covers Stripe's ~120-day dispute tail at any commercially reasonable choice; BP-10
   (`identity_obligation`) is the unconditional backstop regardless of the hold chosen (H2 §7 item 2).
2. **§2** — the credential signer is a HARD blocker distinct from the KMS ceremony (H7); building it needs a
   new migration (signature storage) in addition to a new edge. Provider/algorithm choice (Ed25519 vs
   ECDSA-P256) remains D1, unchosen, per H7 §0.
3. **§3.5** — A8a vs A8a′: does `on_sale` gate Connect-readiness at the transition, or only at checkout? Draft
   ruling text offered both ways; the currently-shipped behavior is A8a (checkout-only), by deliberate 093
   scope decision, not a bug — but that decision was never itself ratified against A8's literal grammar.
4. **§3b.2** — tax: which US jurisdictions (if any) require sales-tax collection on this product/merchant-of-
   record structure before launch. Not answerable from the repo; owner+counsel.
5. **§4.2** — `mode:'replace'` for connect-onboarding: point 7/8 make it dependent on H6's F-1 fix
   (`kernel.payout.destination_ref` bound at claim time) landing first, or the new door inherits the existing
   destination-race rather than merely adding to the queue behind it. Should F-1 be scheduled ahead of, or
   independent of, building replace?
6. **§4.3** — should the `409 destination_unusable` copy in `connect-onboarding` be changed now (stop
   advertising a working "contact support" recovery) even though the replace flow itself is Day-2?
7. **§5** — A9 invoker option A (096 cron migration) vs option B (written process) vs both, per
   `KI_activation_sequencing.md` §7 PRE-7/S-7 — unresolved, orthogonal to this document's scope.
