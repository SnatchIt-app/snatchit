# H7 — SIGNING-CEREMONY GAP CLASSIFICATION

Classifies the compensating-control gaps the runbook itself recorded
(`docs/phase2/PRODUCTION_SIGNING_KMS_CEREMONY.md` §7.6, §9.4, §15; evidence in
`docs/phase2/_impl/G3_signing_rehearsal.md` §5) against the bytes at
`feature/venue-native-and-product-v2` @ `7d45cbf`.

**Nothing was executed.** No KMS key, no production key, no `kernel.signing_key` row in any
environment. No rehearsal DB was built for this pass — every verdict below is a re-verification
against source, not a re-run of G3. No migration, no code and no runbook byte was modified.

**Provider is not chosen here.** D1 stays the owner's.

---

## 1. THE SIX GAPS

### GAP 1 — a database superuser bypasses dual control

**Verified.** `kernel.signing_key` carries only a column-level `SELECT` grant to `authenticated`
(`083:114-117`); no role holds `INSERT`/`UPDATE`/`DELETE`; G3 §4's measured census reads
`postgres only`. Nothing in Postgres implements a two-person rule and nothing can — ADV-1, ADV-2
and ADV-8 all PROVED the single-`postgres`-session write commits. 093 changes none of this.

**Classification: ACCEPTED OPERATIONAL RISK.**

An in-band fix needs the PFA-18A dual-control mechanism, which PFA-18A itself ruled unbuildable
(`kernel.approval_request` is money-only), and even a built one is droppable by the same superuser.
Superuser access *is* the deploy path; there is one holder.

**Compensating control.** (a) Role split in runbook §2 — Person A holds no production DB
credential, Person B holds no `kms:CreateKey`, so neither can complete the ceremony alone without
the other's plane noticing. (b) The provider audit trail (CloudTrail / Cloud Audit Logs), archived
per §9.1, is outside both operators' control and shows whether `CreateKey` ever ran under the
production principal. (c) The §9.3 five-column invariant query, run **daily**.

**Who operates it.** The owner. The §9.3 query must be armed as an actual scheduled job with an
alert destination before the first ticket. Expected result is exactly
`total_keys=1 | scoped_keys=0 | active_global=1 | bootstrap_fpr=<recorded> | max_not_after=null`;
anything else pages the owner. **Arming that job is a LAUNCH BLOCKER even though the gap it covers
is not** — a monitor that exists only in a runbook is not a control.

---

### GAP 2 — a shadow `per_event`/`per_venue` row silently outranks the `global` bootstrap key

**Verified, and the blast radius grew.** The partial unique indexes are per-target
(`signing_key_active_event_uq` / `_venue_uq` / `_global_uq`, `083:73-78`), so a scoped row never
collides with the global row. Scope resolution is
`order by case scope when 'per_event' then 1 when 'per_venue' then 2 else 3 end limit 1` and now
appears at **three** live sites: `venue.finalize_primary_order` (`085:1948-1960`, untouched by
093), `kernel.issue_ticket_atoms` (`093:3395-3407`), and — new in `fc88320` — the A8/G2b checkout
gate (`093:2506-2516`). ADV-7 PROVED the insert succeeds and the resolver flips immediately.

**Classification: ACCEPTED OPERATIONAL RISK.**

It is a strict subset of Gap 1: no client role can insert at all (ADV-3, PROVED), so this requires
superuser. It cannot be a launch blocker on its own because scoped keys are the *designed* steady
state — a `BEFORE INSERT` refusal of scoped rows would have to be conditional and would be a
migration, which does not belong to a refunds/deletion/payout train.

**Compensating control.** §9.3's `scoped_keys` column, expected `0`. This is a boolean alarm, not a
threshold: **any** `per_event` or `per_venue` row appearing while the bootstrap is the only intended
key is a page-the-owner event, not a ticket. Secondarily, the §12 rotation artifact refuses a
`kms_handle_ref` already registered on another row, so the shadow cannot be laundered into a
rotation.

**Who operates it.** Same daily job and same owner as Gap 1.

---

### GAP 3 — `not_after` sits outside the immutability guard

**Verified.** `kernel.guard_signing_key_immutable` (`083:84-102`) compares `public_key`,
`kms_handle_ref`, `scope`, `event_id`, `venue_id` and `not_before`. `not_after` is absent by
design. ADV-9 PROVED `update … set not_after = …` returns `UPDATE 1` for a superuser. 093 does not
touch the guard.

**Classification: FORWARD OBLIGATION.**

**Trigger that makes it due: the first rotation — i.e. the moment a retired `rotating` row must stay
verifiable alongside an active one.** While exactly one key exists with `not_after = NULL` (D6), the
only achievable effect of moving `not_after` is to stop issuance: loud, detected within one monitor
cycle, and reversible, because `not_after` is not forward-only. Once a retired key exists, pulling
its `not_after` into the past silently ends verification of every credential pinned to it, and the
adjacent `rotating → revoked` transition is terminal. A second, equivalent trigger: the first build
of door verification (M1 / the 086 rail), which is when `not_after` acquires verification semantics
rather than issuance semantics.

**Compensating control until then.** D6 pins `not_after = NULL`, which converts the §9.3
`max_not_after` column into a boolean alarm — any non-null value at all is wrong, so no operator has
to judge a threshold. Owner-operated, daily, same job.

---

### GAP 4 — in-band revoke remains parked (PFA-18A)

**Verified.** `kernel.revoke_signing_key` (`086:714-721`) is an unconditional raise; its signature
`(uuid, text, integer, text)` is unchanged and 093 does not redefine it. ADV-11 PROVED it inert even
for a platform admin.

**Classification: ACCEPTED OPERATIONAL RISK at launch scale.**

No credential is ever produced or verified today: `supabase/functions/` has no `credential-sign`,
the 086 door rail is unbuilt, and `feature.native_scanning_enabled` is `false` (`078:1523`). A verb
that invalidates credentials has no consumer. Separately, the thing that *actually* stops a
compromised key was never the database — it is removing `kms:Sign` and scheduling deletion, which is
available today.

**Compensating control.** Runbook §13 steps 1 and 2, in that order.
Step 1, in-band, minutes:
`select catalog.set_platform_config('feature.native_issuance_enabled','false'::jsonb,'compromise','<key>')`
— re-verified this session that `feature.%` is still outside the dual-control prefix set: 093
replaces `catalog.set_platform_config` body-only (`093:4596`) and its `v_dual` line (`093:4747`) is
byte-identical to `078:1145-1147`, so this remains a single-admin act by design.
Step 2, provider-side: strip `kms:Sign` from every principal, then schedule key deletion.

**Who operates it.** Step 1: any platform_admin, deliberately without quorum — stopping the bleeding
must not need two people. Step 2: the KMS IAM holder (Person A's principal, or the owner).

---

### GAP 5 — door-episode force-close on revoke is unimplemented

**Verified.** The real body of `revoke_signing_key` — force-close open episodes in key scope plus
outbox #44 `DoorManifestInvalidated` — is documented as the PFA-18A forward obligation at
`086:703-713` and is not written. The target rows exist:
`venue.door_manifest_entry.signing_key_id` (`086:335`) and
`venue.door_manifest_delta.signing_key_id` (`086:364`). Only the verb is missing.

**Classification: FORWARD OBLIGATION.**

**Trigger that makes it due: the first activation of `feature.native_scanning_enabled`, or
equivalently the first deployment of a door client or a `credential-sign` edge — whichever comes
first. It is due before the first live door scan, not before the first ticket sale.** Until a door
verifies anything, an "open door episode" carries no security meaning: nothing consumes a manifest,
so nothing can be admitted on a revoked key.

**Compensating control until then.** The flag itself (`false` at `078:1523`) plus the absence of any
scanning client. If a revocation happens inside that window, the operating rule is runbook §13 step
3: treat open door episodes as stale for their TTL and say so in the incident record.

**Who operates it.** The owner, as a written step of the §13 compromise procedure.

---

### GAP 6 — `.gitignore` lacks `*.der` / `*.sig` / `*.bin`

**Verified.** `.gitignore` at HEAD carries `*.p8` (:16), `*.key` (:18) and `*.pem` (:31), and none
of `*.der`, `*.sig`, `*.bin`.

**Classification: ACCEPTED OPERATIONAL RISK.**

The artefacts in those extensions are `pub.der` (a **public** key), `challenge.bin` (a nonce) and
`challenge.sig` (a signature over that nonce). None is secret. The private key never exists as a
file at all (§0 rule 1) and the only file extension that could ever carry key material — `.pem` — is
already covered. The worst outcome of this gap is committing a public key and a random nonce.

**Compensating control.** Runbook §3's working-directory check, which *fails the checklist* rather
than warning: `git rev-parse --is-inside-work-tree … && echo "REFUSE: inside a git repo"`. It runs
before any `LOCAL` step produces a file.

**Who operates it.** Person A and Person B, each on their own workstation, before §4.

**Not fixed here on purpose.** Adding three lines to `.gitignore` is repository hygiene and does not
belong to a refunds / deletion-clock / venue-payout train. It is worth one line in the next hygiene
commit; it is not worth a train-scope violation.

---

## 2. RUNBOOK RE-VALIDATION AGAINST CURRENT BYTES

**The runbook is still executable.** Every SQL and RPC path it names resolves.

### Verified intact after 093

| Runbook dependency | Result |
|---|---|
| Six parked RPCs, §3 preflight + §7.3 loop | All six still defined only in `083:375-425` (five) and `086:714-721` (one). Arities and types match every call the runbook makes: `provision_signing_key` 7 args, `rotate_signing_key` 5, `revoke_signing_key` 4, `provision_pass_type_cert` 9, `rotate_pass_type_cert` 8, `revoke_pass_type_cert` 3. **093 redefines none of them.** |
| `kernel.signing_key` DDL, both scope constraints, all three partial unique indexes, the column-fenced grant | Unchanged by 093. |
| §7.5's expected error text | Matches `083:93` character for character: `append_only: signing_key identity/target/public_key/kms_handle is immutable after creation`. |
| §7.2 resolver (`085:1948-1960`) | `venue.finalize_primary_order` is **not** replaced by 093 — recorded explicitly at `093:1330` ("NO `create or replace` of venue.finalize_primary_order"). Verbatim shape still correct. |
| §10 rollback's three reference checks | All exist: `kernel.wallet_pass.signing_key_id` (`083:191`), `venue.door_manifest_entry.signing_key_id` (`086:335`), `venue.door_manifest_delta.signing_key_id` (`086:364`); `fk_tickets_signing_key … on delete restrict` (`084:52-55`). |
| §13 step 1's single-admin flag flip | `feature.%` still outside the dual-control prefix set (`093:4747` byte-identical to `078:1145-1147`). |
| §9.4's claim that suite 147 asserts zero keys | Holds — `147:122` asserts `count(*) = 0` on `kernel.signing_key`. |

### Stale — reported, not edited

1. **Mint citations.** §1.1, §1.3, the §6.1 post-check comment, §8 and §11 door 3 cite
   `083:514-530` / `083:557-559`. 093 replaces `kernel.issue_ticket_atoms` (`093:3314`, same
   signature `(p_ctx jsonb, p_command_key text)`); the live envelope is `093:3390-3415` and the pin
   write is `093:3444`. The envelope's *substance* is unchanged, so nothing an operator does
   changes — but 093 adds a check the runbook never mentions: a caller-supplied
   `p_ctx->>'signing_key_id'` that disagrees with the resolved key is now refused with
   `signing_key_override_refused` (`093:3415`). **The mint no longer accepts a key; it resolves
   one.** That is a strengthening, and §8's note that `key_id` is "pinned at mint" is still true.

2. **§1.3 is materially incomplete — the one substantive staleness.** It justifies the ceremony
   solely by the mint refusing without a key. Since `fc88320`, `venue.create_primary_checkout`
   carries the A8/G2b deliverability gate (`093:2506-2516`) and raises `no_active_signing_key` at
   **quote** time. Two consequences the runbook should state and does not: (a) the "buyer charged,
   then no key, no ticket" hazard is closed *before* the charge; (b) once 093 applies to production,
   **no primary checkout can be quoted at all until this ceremony has run**, which moves the
   ceremony from a webhook-time dependency to a storefront-time one.

3. **§9.4 / ADV-13's CI claim.** It states `grep -rniE 'kms|KMS_SIGNER' .github/workflows/` returns
   "two prose comments". At HEAD it returns **nothing** — `fc88320` rewrote the workflows. Stale in
   the safe direction; the no-leak conclusion is stronger than written.

4. **Adjacent, and the more important stale document — not the runbook.**
   `PRIMARY_TICKETING_ACTIVATION_MATRIX.md:92` and `:95` (row 5, Primary sale) still read
   *"Required signing state: NOT CHECKED BY THE GATE — and it should be"* and
   *"[V] An order was created with zero signing keys in the database … G6 finding F-2"*. G2b closed
   F-2 in the same commit that wrote the matrix, so the matrix contradicts the code it describes.
   **Not edited** — flagged for the owner.

### Nothing in 093 changes what becomes irreversible

All four §11 doors hold at current bytes: FK `ON DELETE RESTRICT` (`084:52-55`); the `BEFORE UPDATE`
guard, superusers included (`083:84-102`); the pin written once at insert (`093:3444`) with no
re-pinning resolver; and a mint that validates only status/window/scope. The point of no return is
still the first `kernel.issue_ticket_atoms`, not the ceremony and not the flag flip.

The new checkout gate does **not** narrow the §10 rollback window: `093:2517-2521` states explicitly
that the key is not pinned onto `venue."order"` — the gate proves deliverability at quote time and
finalize decides which key. So an order created after the bootstrap but before the first mint holds
no reference, and the rollback's three existence checks remain exhaustive.

### Secret-material confirmation

**Confirmed: the runbook contains no example secret, no plausible-looking production key material,
and no real KMS identifier.** Grepped for ARNs, GCP resource paths, PEM blocks, hex runs of 40+,
`AKIA`, `sk_live` and `secret`. Every hit is either prose or a `<PLACEHOLDER>` inside a syntax
template — D4's `arn:aws:kms:<REGION>:<ACCOUNT_ID>:key/<KEY_ID>` and
`projects/<P>/locations/<L>/keyRings/<KR>/cryptoKeys/<K>/cryptoKeyVersions/<V>`, both of which teach
the *shape* and supply no value. No fingerprint, no key id, no account id, no algorithm spec string,
no connection string. The only real-looking hex in the pair of documents is in
`G3_signing_rehearsal.md` (`c0a79cda…`, `628fb906…`) — truncated fingerprints of throwaway rehearsal
keys, labelled as such, deleted with the scratchpad, and **not present in the runbook**. §9.2
forbids recording them in the evidence pack.

---

## 3. IS THE CEREMONY THE TRUE NEXT CRITICAL PATH?

**NO.** It is the longest-lead and only irreversible item on the critical path, but it is not next.

**Reason 1 — the signing key is the second refusal in checkout, not the first.** Inside
`venue.create_primary_checkout` the gates fire in this order: `payout_not_ready` (`093:2466`) →
`no_active_signing_key` (`093:2516`) → `service_fee_unset` (`093:2545`). `connect_transfers_active`
is written only by `kernel.sync_org_connect_state` (service_role), whose only caller is the
`account.updated` arm of `stripe-webhook` — **not deployed**. So every quote refuses
`payout_not_ready` before the resolver is ever reached. Bootstrapping the key today changes no
observable behaviour anywhere.

**Reason 2 — three deploy acts sit in front of it, and none is configuration.** 093 is not applied
to production (ledger 107 = migrations 000–092). `catalog` and `venue` are not exposed over
PostgREST in production, so no client can call `create_primary_checkout` at all. `primary-checkout`
(the only minter of a PaymentIntent) and the `stripe-webhook` native branch (the only caller of
`finalize_primary_order`) are authored and undeployed. Ruling G3's line that *"every other blocker
in this document can be resolved by configuration"* is not true against the activation matrix's own
findings.

**Reason 3 — an unmade owner decision precedes it.** D1 (provider) is unchosen, and the ceremony
additionally needs two named individuals with separated cloud IAM and a scheduled window. That lead
time is organizational, not engineering.

**What is nonetheless true, and why it must be scheduled now.** It is the only step on the list that
cannot be undone by a redeploy. Since G2b it gates the first production *quote*, not merely the
first mint — so it must complete before `primary-checkout` is enabled in production, not before the
first webhook delivery. And its lead time is human, so it parallelises cleanly with the deploy work.

**Ordering recommendation.** Next critical path: finish this train's slices → apply 093 to
production → deploy `stripe-webhook` (native branch) + `primary-checkout`, expose `catalog`/`venue`
over PostgREST, sync one org's Connect state. **Schedule the ceremony in parallel starting now**
(owner picks D1, names A and B, books the window), and land it before the first quote is served.
