# ADVERSARIAL ARCHITECTURE REVIEW — Primary Ticketing Owner Decision Packet

**Target:** `docs/phase2/PRIMARY_TICKETING_OWNER_DECISION_PACKET.md` + `docs/phase2/_decisions/{A..F}`
**Repo:** `/Users/josetascon/snatchit-consol` · branch `feature/venue-native-and-product-v2` · commit `5dd1883`
**Posture:** read-only. No migration authored, nothing committed, production untouched.
**Method:** every verdict below is checked against deployed SQL / TypeScript, not against the decision prose.
All paths are relative to the repo root; migration citations are `<migration>:<line>`.

**Headline.** Decisions **C** and **F** survive independent checking and are safe to rule on with the
corrections in this document. Decisions **A**, **B**, **D** and **E** each contain at least one
"verified" claim that does not survive, and two of them (A, D) would cost real money or real trust as
written. Separately, the packet's ordering is wrong: **none of the six decisions matters until a venue
organization can be attached to Stripe at all, and nothing in the repository can do that.**

---

## 1. FINDINGS TABLE

Ranked by consequence.

| ID | SEV | DECISION | CLAIM ATTACKED | VERDICT | EVIDENCE | CONSEQUENCE |
|---|---|---|---|---|---|---|
| X-1 | **P0** | A (packet-wide) | "No frozen text is contradicted" — Option 1 is an IMPLEMENTATION FOLLOW-UP | **OVERTURNED** | `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md:142`, `:851`; `085:908-911` | The frozen corpus says the **org** is the merchant of record for primary sales and holds refund authority. Option 1 makes the **platform** the MoR and platform-only refund authority. MoR drives tax, 1099-K, dispute liability and consumer-protection duty. The packet resolves it silently as an implementation detail. |
| X-2 | **P0** | Packet (093 EDGE / OWNER lists) | The 093 + edge + config list is what stands between here and a first paid ticket | **CONFIRMED MISS** | `077:114`; `085:1601`; grep of `supabase/functions/ web/ app/ src/ packages/` for `stripe_connect_account_ref\|set_org_payout_destination` = **0 hits** | `kernel.organization.stripe_connect_account_ref` has no edge, client or admin writer anywhere. Execute the entire packet perfectly and **no venue can be paid**, because no venue org can be onboarded to Stripe. Doc A:490 flags it; the packet's EDGE and OWNER lists omit it. |
| X-3 | **P1** | E | "the `mode` column has **zero SQL consumers anywhere**; the payment dispatch reads Stripe metadata, not the column" | **OVERTURNED** | `supabase/functions/create-payment-intent/index.ts:419-422` (`.eq('mode', mode)`), `:608`, `:615`; `src/types/index.ts:208`; `packages/types/src/index.ts:197` | `mode` is a live WHERE predicate gating the **duplicate-payment guard** and the race-recovery equality on the resale rail, and is typed non-nullable in two shipped type packages. E's own §2.4 (rows 23/25) lists these; its summary contradicts its body. This is the packet's flagship "verified" claim justifying DDL on a live money table. |
| X-4 | **P1** | B / 093 MUST #1 | "Suites 147/150 stay green unchanged" | **OVERTURNED** | `supabase/tests/147_phase2_kernel_credential_infrastructure.sql:122`; `supabase/tests/150_phase2_venue_door_and_scan.sql:105` | Both assert `count(*) = 0` on `kernel.signing_key` **database-wide**. The bootstrap key row turns both red on a replayed chain. The packet lists no test amendment for its only MUST-#1 item. |
| X-5 | **P1** | A | Recommendation covers the money lifecycle | **CONFIRMED MISS — partial refunds** | `082:80` (`partially_refunded` in the status CHECK); `085:604`, `085:711`; `A:455` (seam emits for `status='paid'` only) | An order partially refunded **before** its first close gets a negative `refund_void` line and **no positive revenue line**. Net goes negative, no payout fires, and the venue's other revenue is reduced by a refund of revenue never recognised. Silently under-pays the venue. |
| X-6 | **P1** | A | Recommendation "stays satisfied" with promoter Option B | **QUALIFIED** | `090:1519` (seam); `090:1486` (`'held','unfunded_settlement'`); `A:585` (`release_payout` takes no reason argument) | Arithmetic is right, the discharge is not. `settlement_commission_lines` is not a pure candidate generator — it calls `pay_promoter_commission`, which mints the payout **HELD**. Nothing in the 093 list releases it. After 093 the venue is paid net of commission and the promoter is paid **nothing**; the platform holds the difference indefinitely. |
| X-7 | **P1** | D | Expiry key is **OPERATIONAL CONFIG**; "No 093 required" | **OVERTURNED** | `078:1096-1098` (`unknown_key` raise); `079:467`, `079:476-485`; no seed of `ticket.expiry_grace` anywhere | `catalog.set_platform_config` refuses unregistered keys and there is no other insert path outside migrations. Setting the expiry key **requires a migration**. The packet's Decision D text ("No 093 required") contradicts its own SHOULD #7, which puts the key in 093. |
| X-8 | **P1** | D | "Dashboard plus a named write-back process is acceptable for a limited launch" | **OVERTURNED** | `085:1737`; `085:2152` (`v_svc`); `085:2165` (revoke from `public, anon, authenticated`); zero callers outside migrations/tests/rollbacks | `kernel.mark_refund_state` is **service_role only**. There is no dashboard and no authenticated RPC. The "named process" is a human holding the production service key running raw SQL against money tables — the exact practice Decision C asks the owner to prohibit in writing. |
| X-9 | **P1** | Packet 093 MUST #3 | "…together with its replacement seller-side policy in the same migration. Never one without the other." | **OVERTURNED (internal contradiction)** | Packet Decision E section: "The migration should **add no policy**"; `supabase/tests/010_rls_smoke.sql:42` pins the policy count at 2 | The same document gives opposite instructions. Following MUST #3 adds a policy Decision E proves is unimplementable (the native payment table is revoked from client roles) and breaks a deployed test. |
| X-10 | **P1** | F | "093 work: **one** required item" (column-scope `venue."order"`) | **QUALIFIED** | `082:129` (table-grain grant), `082:75` (`buyer_id`), `070:57` (`profiles … using (true)`); `supabase/tests/146_phase2_venue_orders.sql:84`, `:260`, `:13` (`plan(71)`) | The exposure is real and reachable, and no deployed **runtime** consumer breaks. But two pgTAP assertions do: `has_table_privilege(...,'SELECT')` ignores column grants, and `:260` selects `buyer_id` under `role authenticated`. `plan(71)` needs recounting. Precedent for the fix exists at `tests/143:123`, `tests/144:163-166`. |
| X-11 | **P1** | B | One bootstrap key is "sufficient and safe" | **QUALIFIED — sufficient, not safe** | `083:49-62` (no `org_id` column); `083:525`, `085:1956` (unqualified `global` arm); `083:77-78` (`signing_key_active_global_uq on ((true))`); `083:375-393` (parked raises); `084:51-61` (FK RESTRICT, VALIDATED) | Sufficiency **CONFIRMED**: one global row resolves for every event of every org. But the schema permits exactly **one** active global key platform-wide, provision/rotate are parked raises, revoke is parked and the FK blocks deletion. One key compromise forges every ticket for every tenant with **no deployed remediation path**. The packet names the "wrong key" risk, not this one. |
| X-12 | P2 | A | "Seam replacement is the established mechanism, used twice before" (used to justify replacing `close_settlement`) | **OVERTURNED as applied** | `grep "function kernel.close_settlement" *.sql` → **one** definition, `087:289`; precedents `088:319`, `090:1511` replaced the two **seam stubs** 087 authored for replacement | The precedent covers seams, not the close engine. `close_settlement` has never been replaced. Doc A:271 concedes this; the packet drops the concession. Variant **1a** needs no `close_settlement` change at all; the packet chose 1b on naming-honesty grounds — an aesthetic reason for the riskier variant on the most audited money function in the system. |
| X-13 | P2 | A | The partial unique index "is the fix for failure mode 2 and is not optional" | **QUALIFIED** | `087:318-321` (`on conflict (settlement_id, cause, cause_ref) do nothing`); `090:214-215`; `088:330`, `090:1519` (per-org advisory xact lock) | The ON CONFLICT **inference specification** arbitrates only `settlement_line_cause_uq`. A violation of the proposed `(cause_ref) WHERE cause='primary_sale'` index raises `23505` and rolls back the **entire close**. This latent abort already exists for `attribution_one_commission_line_ever`. FM-2 is in fact mitigated today by the per-org advisory lock, not by an index. The index is still worth having (service_role retains INSERT — `087:115` revokes only update/delete) but requires changing the ON CONFLICT to a bare `DO NOTHING` — a further `close_settlement` body change the packet does not list. |
| X-14 | P2 | C | Writer census; E-76 correction; stale roles; P1 severity | **CONFIRMED (all four)** | `078:701` (sole `set org_id`), `078:879`+`078:856-858` (server-derived event insert), `078:945-949` (unwritable set), `078:123-126`/`078:161-164` (SELECT-only column grants, no UPDATE/INSERT grant to any role); `087:300` + siblings `087:656-659`, `087:1300-1302`, `087:1370`, `087:1426-1428`, `088:1628-1631`, `090:1173-1175`; `080:30-45` + `080:64-73`; `078:687-695` | The E-76 conjunct compares `catalog.venue.org_id` to the **scope object's** org, so the new operator's own rows satisfy it — **Decision C's correction is right and the earlier audit is wrong.** `venue.staff_role` has **no `org_id` column**, so a stale role cannot fail to apply under a new operator, and nothing deletes roles by `venue_id`. The transfer verb is platform-admin-only with zero client callers repo-wide. |
| X-15 | P2 | C | Threat description of the residual path | **OVERTURNED (in the owner's favour)** | `076:76` (catalog USAGE to `anon, authenticated` only); `085:2091`, `085:2095` ("catalog untouched") | `service_role` is **never granted USAGE on schema `catalog`**. The residual direct-SQL path is `postgres`/superuser only, not the service key. Layer 2 of C's recommendation is still wanted; its stated threat is narrower than claimed. |
| X-16 | P2 | C | The census is exhaustive | **QUALIFIED — one path missed** | `078:856-858` (unlocked venue read in `create_event`) vs `078:655-657` (`FOR UPDATE` in `update_venue`) | Under READ COMMITTED a `create_event` concurrent with a transfer produces `event.org_id = A` with `venue.org_id = B` and **no second writer**. Only reachable alongside a transfer, so the freeze holds the invariant — but C's recommended CI invariant must tolerate/flag it, and any future atomic transfer must lock the venue against `create_event`. |
| X-17 | P2 | A × E | Where the fee decomposition lives | **CONFIRMED MISS** | `000:982-985` (`amount / buyer_fee / seller_fee / total`, cents); `082:83` (`total_minor` only); `085:1930-1934` (`v_pay.total < v_order.total_minor` — a **coverage** test, not equality) | Two uncoordinated decompositions of the same sale. A's seam derives the venue share from `venue."order"`; E leaves the `public.payments` fee columns' meaning for a direct sale undefined; finalize never checks equality, so an over-collection finalizes silently. Neither decision names the authoritative source. |
| X-18 | P2 | D | Zero-window arithmetic; tombstone refund reachability | **CONFIRMED (with one operational trap)** | `085:271-283` (strict `>`; `v_window=0` ⇒ `created_at > now()` ⇒ false); `078:1048`, `078:1145-1147` (`deletion.` not dual-controlled, no range validation); `088:1730-1740` (no `identity_ext` join); `078:1801-1858` (erasure nulls nothing on order/payment/refund) | Both claims hold. **Trap:** the value must be the JSON number `0`. `"0 days"` fails `::numeric` inside `deletion_blockers_money`, which has no exception block there, quarantining the identity in the sweep. |
| X-19 | P2 | Packet 093 MUST NOT | "A lease column on the refund table. The existing unique key makes it unnecessary." | **UNDETERMINED — argument not located** | `085:90-93` (`idempotency_key` + `refund_idempotency_uq`) | The unique key prevents duplicate refund **rows**; it does not prevent two executors claiming the same **pending** row. `stripe_refund_ref` is write-once (paired CHECK) so the second writer's differing ref raises — but only *after* Stripe has been called twice. The precedent in this repo went the other way (`a16a16d fix(payments): webhook retries no longer silently dropped (claim lease)`). I could not find this argument anywhere in Decision D. |
| X-20 | P2 | E | "Blast radius: 87 sites, 47 SQL / 40 other"; "56 production rows" | **QUALIFIED** | Independent count ≈115 raw matching lines; `019_anonymized_sentinel_user.sql:5-6` | The 47/40 split is a hand classification, not a measurement. The load-bearing conclusions **hold**: no existing row can violate a rail-pairing CHECK (NOT NULL has held since `000:973/975`; no migration ever INSERTs into payments; erasure writes a sentinel uuid, never NULL). The lock analysis exists in E §6.5 but the packet omits it. **The 56-row figure cannot be verified from the repository** — production was not queried. |
| X-21 | P2 | F | "The deployed door manifest already returns exactly this" (six facts) | **QUALIFIED** | `086:843-873` | `venue.get_door_manifest` returns **seven** per-atom columns: `ticket_atom_id, serial_no, ticket_type_id, credential_version, signing_key_id, ticket_state, resale_state`. The privacy claim (no identity, no name, no price) **holds**; "exactly six" does not, and `ticket_atom_id` is on the X-6 forbidden-export list. |
| X-22 | P2 | E | "the money test suite fabricates a fake Miami listing **and a fake seller**" | **QUALIFIED** | `supabase/tests/149_phase2_kernel_money_native.sql:160-167`, `:163`, `:170` | The listing is fabricated. The seller is `tap.seller()`, a shared `seed_core` fixture. Half the rhetoric is inflation. |
| X-23 | P2 | Packet 093 MUST #2 | The two inventory config rows exist nowhere and only a migration can create them | **CONFIRMED — and unattributed** | `081:617`, `081:633`, `081:729`; grep of `078` for `inventory.` = **0 hits**; `078:1096-1098`; `081:625` (fail-to-zero ⇒ `hold_cap_exceeded`), `081:637` (`hold_ttl_unset`) | The claim is true. It is also the **only MUST item researched by none of the six decisions** — it appears in the 093 list and nowhere in A–F. It is correct, but it entered the packet unreviewed. |
| X-24 | P3 | A | Settlement arithmetic | **CONFIRMED MISS** | `087:52` (`gross_minor integer`), `087:100` (`amount_minor integer`); `087` close casts `bigint → integer` | Candidates are `bigint`, columns are `integer`. A settlement above **$21.47M** in minor units overflows on close. Remote today; not remote for a large venue group on an annual period. |
| X-25 | P3 | B | "the admin allowlist is a single row" | **QUALIFIED** | `033:121-124` (seeded under `WHERE EXISTS`); `033:251` is a **comment in a verification block**, not a constraint or test; `supabase/ci/parity_grants.sql:53` grants `service_role` full DML on `public.admin_users` | The conclusion — no second approver exists today — survives. "Asserted" does not: nothing caps the table, and a second admin is one service-role insert away. |

---

## 2. WHAT IS ACTUALLY TRUE — overturned and qualified claims

### X-1 — Decision A picks the merchant of record and calls it an implementation detail

The frozen corpus is explicit in two places:

- `docs/architecture/SNATCH_IT_DOMAIN_ARCHITECTURE.md:142` — the organization is "**The payee** for primary sales… A person is never a primary-sale merchant of record; **an org is.**"
- `:851` — "the venue holds refund authority **because the venue is the merchant of record for primary sales**."

Decision A's recommended Option 1 makes the **platform** the merchant of record (platform PaymentIntent,
no `transfer_data`, no `on_behalf_of`, no `Stripe-Account` header) and Decision A itself identifies
Option 3 as "the venue becomes merchant of record". So the recommendation is the option that
contradicts the corpus, and A classifies it as **IMPLEMENTATION FOLLOW-UP** on the stated ground that
"**No frozen text is contradicted.**" That ground is false.

The deployed refund authority already follows the platform model, not the corpus:
`085:908-911` comments "**org_admin + every venue role FORBIDDEN — MONEY §6.1**" and admits only
`buyer`, `org_owner`/`org_finance`, or platform to *request* a refund; the executor
`kernel.refund_primary_order` (`085:457`) is platform-direct or dual-control-delegated only. **No venue
role can refund a ticket its own venue sold.** Decision D never surfaces this.

What is actually true: the packet is asking the owner to ratify a merchant-of-record change under the
label of a settlement-seam implementation. That is the single most consequential unlabelled decision in
the document, and it is upstream of A (who is owed), D (who may refund), F (who is the data controller)
and the entire tax question in §4.

### X-2 — nothing in the repository can attach a venue org to Stripe

`kernel.organization.stripe_connect_account_ref` (`077:114`) has exactly one writer,
`kernel.set_org_payout_destination` (`085:1601`), and a repo-wide grep across `supabase/functions/`,
`web/`, `app/`, `src/` and `packages/` finds **no caller of either**. `create-connect-account`
(`index.ts:203-206`) creates `type: 'express'`, `business_type: 'individual'`, transfers-only accounts
for individual resale sellers — the wrong shape and the wrong subject.

Doc A:490 records this in a table row. The packet's "EDGE work after 093" and "OWNER action after 093"
lists both omit it. Consequence: the packet describes a route to a first *sale*, not to a first
*payment*. Execute all of it and the money is collected, the ledger is correct, the payout row is
minted `pending` — and there is no destination for it.

### X-3 — `mode` has live consumers, and the packet's flagship verified claim is false

The dispatch does read Stripe metadata, but the **duplicate-payment guard** reads the column:

- `supabase/functions/create-payment-intent/index.ts:419-422` — `.eq('listing_id', …).eq('buyer_id', …).eq('mode', mode)`
- `:608` `.select('listing_id, buyer_id, mode, status')` → `:615` `winner.mode === mode &&`

and it is declared **non-nullable** in two shipped type packages (`src/types/index.ts:208`,
`packages/types/src/index.ts:197`).

The conclusion survives — both are equality filters and native rows simply never match — but the
premise does not, and the premise is what the packet uses to argue that widening `mode` is inert. The
practical correction: **widen the CHECK, do not drop the NOT NULL, and update both type packages in the
same change**, or the guard's typing silently diverges from the database.

### X-4 — the bootstrap key row breaks the pgTAP floor

`supabase/tests/147_phase2_kernel_credential_infrastructure.sql:122` and
`supabase/tests/150_phase2_venue_door_and_scan.sql:105` both assert the signing-key table holds **zero
rows database-wide**. Decision B cites the `throws_ok` lines immediately above these and stops short of
the assertions its own recommendation breaks. 093 must amend both suites (and re-count their plans) or
CI goes red on the migration that makes the first ticket mintable.

### X-5 — partial refunds fall through Decision A's seam

`venue."order".status` legally includes `'partially_refunded'` (`082:80`) and
`kernel.refund_primary_order` writes it (`085:604`, `085:711`). Decision A's seam emits a `primary_sale`
line for orders with `status='paid'` (`A:455`) and its `refund_void` arm emits for every succeeded
refund "against a primary order **already lined**" (`A:464`).

Two orderings, both wrong:
1. Refund lands **before** the first close → the order is `partially_refunded`, never lined, and the
   `refund_void` arm's own precondition ("already lined") means the negative should not fire either —
   so the sale disappears from the ledger entirely. Gross under-states, and the platform keeps the
   remainder with no row naming it.
2. If the `refund_void` arm is implemented without that precondition, a negative line lands with no
   positive counterpart and the venue's *other* revenue absorbs the refund.

Either way the number is wrong in the direction that under-pays the venue, and `settlement_line` is
append-only (`087:111`) with `update, delete` revoked even from `service_role` (`087:115`), so the bad
line can only be offset by hand.

### X-6 — Option B's arithmetic is satisfied; its discharge is not

`kernel.settlement_commission_lines` (`090:1511`) is **not** the pure candidate generator the seam
contract describes (`087:192-196`, "STABLE, pure, MUST NOT raise"). It is `volatile`, takes a per-org
advisory lock (`090:1519`) and **calls `kernel.pay_promoter_commission`**, which mints the commission
payout `'held', 'unfunded_settlement'` (`090:1486`) and emits a `payout_on_hold` notice (`090:1491`).

So after 093 as recommended: the venue's `net_minor` is reduced by the commission (correct, Option B
satisfied arithmetically), the promoter's payout is minted **held**, and nothing in the packet's 093
list, config list or edge list releases it — `kernel.release_payout` is a per-payout Control-5 action
taking no reason argument (`A:585`). Doc A §5 parks this honestly. The **packet's** Decision A section
does not mention it, and the 093 list does not carry it. Net effect: venues pay commissions that
promoters cannot receive, indefinitely, and the platform holds the float.

### X-7 / X-9 — the packet contradicts itself twice

- **Expiry key.** Decision D section: "**No 093 required**". SHOULD #7: "The ticket expiry
  configuration key (Decision D)" — in 093. The 093 placement is the correct one
  (`078:1096-1098` refuses unregistered keys; `ticket.expiry_grace` is registered nowhere), and its
  classification as OPERATIONAL CONFIG is wrong. It also belongs in **MUST**, not SHOULD: Decision D's
  own text says a no-show buyer's ticket never expires and the live-custody blocker never clears, and
  that this "needs no money at all to trigger".
- **Payments policy.** MUST #3: replacement seller-side policy, "**never one without the other**".
  Decision E section: "The migration should **add no policy**." Following MUST #3 breaks
  `supabase/tests/010_rls_smoke.sql:42` (policy count pinned at 2).

### X-8 — Decision D recommends an operating process that does not exist

`kernel.mark_refund_state` (`085:1737`) is in the service_role-only grant array (`085:2152`) and
revoked from `public, anon, authenticated` (`085:2165`), with no caller outside migrations, tests and
rollbacks. `kernel.list_org_refunds` (`085:1487`) reads but does not write. There is no admin UI and no
authenticated RPC. "Dashboard plus a named write-back process" therefore means **a person with the
production service key running raw SQL against money tables** — which is the practice Decision C's
layer 2 asks the owner to prohibit in writing, on the same page.

### X-11 — one key is enough, and that is the problem

`kernel.signing_key` has **no `org_id` column** (`083:49-62`) and the mint's `global` arm is
unqualified (`083:525`, `085:1956`), so one row genuinely resolves for every event of every
organization — Decision B is right. But `signing_key_active_global_uq on ((true)) where status='active'
and scope='global'` (`083:77-78`) permits exactly one active global key **platform-wide**;
`provision_signing_key` and `rotate_signing_key` are unconditional raises (`083:375-393`); revoke is
parked; and the ticket FK is `on delete restrict` and **VALIDATED** (`084:51-61`). A compromise of that
one key forges every ticket of every tenant, and the deployed system has no rotate, no revoke and no
delete. The packet's "most serious threat" (a *wrong* key) is the smaller of the two.

### X-13 — the recommended index does not do what the packet says

`close_settlement` inserts with `on conflict (settlement_id, cause, cause_ref) do nothing`
(`087:318-321`). That is an **inference specification**: it arbitrates only `settlement_line_cause_uq`.
A conflict on the proposed `(cause_ref) WHERE cause = 'primary_sale'` index is a different index and
raises `23505`, which propagates out of `close_settlement` and rolls back the **whole close**, every
other line included. The identical latent abort already exists for `attribution_one_commission_line_ever`
(`090:214-215`) and is undocumented.

Also, FM-2 is already mitigated: both live seams take `pg_advisory_xact_lock('settlement.seam.org:'||org_id)`
(`088:330`, `090:1519`), which serializes concurrent closes of the same org and, being `volatile`, gives
the second close a fresh snapshot that sees the first's committed line. The packet's "no constraint
stops it" is imprecise. The index remains worth adding — `service_role` retains INSERT on
`settlement_line` (`087:115` revokes only `update, delete`), so a manual insert bypasses the lock — but
it must land **together with a change of the ON CONFLICT to a bare `DO NOTHING`**, which is a further
body change to `close_settlement` the packet does not list.

### X-15 / X-16 — Decision C is right, for slightly different reasons

The census holds: one `set org_id` site (`078:701`), a server-derived event insert (`078:879` with the
org read at `078:856-858`), an unwritable-key refusal covering `org_id`/`venue_id`/`status`
(`078:945-949`), SELECT-only column grants with **zero** UPDATE/INSERT grants to any role on
`catalog.venue` or `catalog.event` (`078:123-126`, `078:161-164`), select-only RLS throughout, and no
`INSTEAD OF` triggers. The E-76 correction is **right** — `087:300` and six siblings compare the
venue's org to the **scope object's** org, so the new operator's own rows pass for the previous
operator's staff — and the stale-role analysis is right because `venue.staff_role` (`080:30-45`) has no
`org_id` column at all and `kernel.has_venue_role` (`080:64-73`) matches on `venue_id + auth.uid()`.

Two corrections: the residual path is **superuser only, not `service_role`** (`076:76`, `085:2095`), so
the threat is narrower than described; and there is **one divergence path the census misses** — a
`create_event` reading the venue's org unlocked (`078:856-858`) concurrently with a transfer that holds
`FOR UPDATE` (`078:655-657`) produces divergence under READ COMMITTED with no second writer.

---

## 3. CROSS-DECISION CONFLICTS

The six were researched independently and they collide in six places.

**1. B × D — the second approver problem propagates into refunds.**
Decision B proves the in-database second approver does not exist (`kernel.platform_role` unmintable,
`077:1591`; zero `INSERT INTO kernel.platform_role` repo-wide). Decision D's non-platform refund path
is the **delegated** arm of `kernel.refund_primary_order`, which binds to an approved
`kernel.approval_request` (`085:495-510`). If dual control cannot be satisfied, every refund funnels
through the single `platform_admin` direct arm — the exact single point of failure Decision B calls a
defect. D never notices; the packet never connects them.

**2. C × D — the packet asks the owner to sign two contradictory operating rules.**
C layer 2: "a written **no-direct-SQL policy** and an admin roster review." D's fallback: "dashboard
plus a named write-back process", which X-8 shows is unavoidably direct SQL with the service key
against `kernel.refund`. Ratifying both is incoherent.

**3. A × E — E's recommendation kills A's stated fallback.**
`A:487` hedges that `primary-checkout` "must supply a `listing_id` (**or** rely on the amendment
above)". E's rail-pairing CHECK makes a native row carrying a `listing_id` **unstorable**. A's escape
hatch closes the moment E is implemented; only the amendment path remains.

**4. A × E — two decompositions of one sale, with no reconciliation (X-17).**
`public.payments` carries `amount / buyer_fee / seller_fee / total` in cents (`000:982-985`);
`venue."order"` carries only `total_minor` (`082:83`); `finalize_primary_order` checks coverage, not
equality (`085:1930-1934`). A derives the venue share from the order; E leaves the payments fee columns
undefined for a direct sale. Nobody names the authoritative source, and the discrepancy is invisible.

**5. B × 093 test floor (X-4), and E × F × 093 test floor.**
Three of the five MUST items break deployed pgTAP assertions: MUST #1 breaks `147:122` and `150:105`;
MUST #3, if MUST #3's policy clause is followed, breaks `010_rls_smoke.sql:42`; MUST #5 breaks
`146:84` and `146:260` and requires re-counting `plan(71)` at `146:13`. The packet lists no test work at
all. A single 093 must land all of these amendments together.

**6. A × C — the freeze is a load-bearing dependency of A, unnamed.**
A's seam scopes revenue by `o.org_id` / `s.org_id`. What keeps an order's org aligned with the venue
being settled is precisely C's freeze. If the freeze is ever lifted without an atomic transfer, primary
revenue lines land in the **former** operator's settlement. The packet's MUST list happens to include
C, but A does not declare the dependency, so a future re-ordering could drop it silently.

**Checked and found clean:** D's zero window does not conflict with A's refund arm — the deletion
predicate reads `venue."order"` (`085:271-283`), which erasure does not touch (`078:1801-1858`), so the
seam still sees a tombstoned buyer's order. B's bootstrap key and C's freeze are independent: the key
table has no `org_id` and no venue coupling (`083:49-62`).

---

## 4. WHAT EVERYBODY MISSED

Absent from all six decisions and from the packet.

**1. No organization can be onboarded to Stripe (X-2).** The gating item. Everything else is downstream
of a payout destination that no code path can populate.

**2. Tax and 1099 reporting do not exist anywhere.** Grep for `1099`, `tax_id`, `sales tax`, `taxable`
across `supabase/migrations/`, `docs/architecture/` and `docs/phase2/` returns **zero hits**.
`kernel.organization` (`077:105-124`) has no tax-registration column despite
`SNATCH_IT_DOMAIN_ARCHITECTURE.md:142` listing "tax registration" as an organization attribute, and
`venue."order"` has no tax column (`082:83`) — Doc A:211 already marks tax "UNREPRESENTABLE" and moves
on. If the platform is the merchant of record it owes 1099-K reporting to every org it settles and, in
several US ticketing jurisdictions, amusement-tax collection and remittance. This is not a new
observation: `docs/product-v2/ADVERSARIAL_REVIEW.md:318` raised "amusement-tax collection and
remittance, or which entity is the merchant of record for a direct ticket" **before** these six
decisions were written, and all six dropped it. That is a regression, not an oversight.

**3. Merchant of record and terms of service (X-1).** Beyond the corpus contradiction: there is **no
terms-of-service document anywhere in the repository** (`find -iname "*terms*"` returns nothing outside
`node_modules`). Nothing states who the buyer contracts with, who owes the refund, or whose consumer
obligations apply to a venue-direct ticket. Decision F's privacy posture also assumes an answer to
"who is the data controller for attendee identity" that the MoR question determines.

**4. Partial refunds (X-5).** A concrete arithmetic hole in the recommendation, not a policy gap.

**5. Chargeback after the venue has been paid.** `088:351-362` books the negative into the org's
**next** settlement — recovery by netting only. `kernel.identity_obligation` (`085:161`) is
identity-scoped; org-side clawback is Gate-M by `PHASE_2_MONEY_AUTHORITY_SPEC.md:1486-1505` ("No
reserve. No clawback. No instant payout."). If the event is over and the venue has no further primary
revenue, the loss is unrecoverable — and the venue sees an unexplained negative `settlement_line` whose
`cause_ref` is a `dispute_id` with no dispute-facing surface, no notice and no appeal. Doc A:188 records
the mechanic; the packet drops it, and the 093 list contains no reserve, no hold-back and no
notification. There is no answer to "what does a venue see when a buyer charges back after settlement".

**6. A restricted or disconnected Connect account.** `_shared/payouts.ts:81-96` correctly returns
`destination_not_ready` without spending the idempotency key, so the payout stays `pending` — forever,
with no alert, no ageing, no expiry and no operator surface. Nothing in the packet names who watches
for a payout that has been pending for a month, which is the failure a venue notices before you do.

**7. Two venues sharing a physical space.** Nothing prevents two organizations creating two
`catalog.venue` rows at one address. `venue.staff_role` is keyed on `venue_id` only (`080:30-45`), so a
shared door team needs duplicate role rows and a stale role at one venue-row confers nothing at the
other — that part is safe. What cannot be expressed is a co-promoted night at one address: settlement
scope is `e.venue_id = s.venue_id` (`088:344-350`, `090:1524-1528`), so revenue can settle to exactly one
venue row. **Undetermined whether this matters commercially** — it is a product question, not a defect.

**8. Integer overflow on settlement close (X-24).** `gross_minor`/`amount_minor` are `integer`
(`087:52`, `087:100`) while candidates are `bigint`. $21.47M per settlement.

---

## 5. THE PROPOSED 093 LIST

**Is anything in MUST actually optional?** No. All five are genuinely blocking. But **MUST #2** (the
inventory config rows) is the only MUST item researched by **none** of the six decision documents — it
appears in the 093 list and nowhere in A–F. It happens to be correct (X-23), but it entered the packet
unreviewed, which is itself a process finding.

**Is anything in SHOULD actually blocking?**
- **SHOULD #6** (the settlement seam) is blocking **if any direct money is collected**. Decision A's own
  text says "do not switch collection on until the line writer exists." Its SHOULD placement is safe
  only because the issuance flag is flipped last; if that flag does not in fact gate collection, SHOULD
  #6 is the difference between selling with a ledger and selling without one. Verify the flag's scope
  before relying on the ordering.
- **SHOULD #7** (the expiry key) is blocking and mis-classified (X-7): without it tickets never expire,
  the live-custody blocker never clears and deletion is permanently blocked — with no money required to
  trigger it. **Promote to MUST**, and note it needs a migration, not config.

**Is the ordering safe?** Mostly, with three corrections:
1. **Put the `public.payments` ALTER last, with a short `lock_timeout`.** MUST #3 takes
   `ACCESS EXCLUSIVE` on the live resale rail's hottest table inside a migration that also does a key
   INSERT, two function replacements and a grant rewrite. A failure late in 093 must not have been
   holding the resale rail since the top.
2. **Drop MUST #3's policy clause** (X-9) — it contradicts Decision E and breaks `010_rls_smoke.sql:42`.
3. **Land the pgTAP amendments in the same migration package** (X-4, X-10): `147:122`, `150:105`,
   `146:84`, `146:260`, `146:13`.

**Rollback.** The packet states no rollback posture at all, and 093 is **one-way in two places**:
- Once one direct sale writes a NULL `listing_id`, re-adding the NOT NULL fails. 093 is irreversible
  from the first direct sale — which is the declared FORWARD-FIX-ONLY posture (`085:29-31`) but is
  nowhere stated.
- The bootstrap key row becomes undeletable the moment the first ticket is minted (`084:51-61`, FK
  RESTRICT, VALIDATED). The CONFIG-after-093 ordering (issuance flag flipped last) is what preserves the
  window; that ordering is therefore not merely tidy, it is the only rollback the design has. Say so.

**Lock ordering / deadlock.** No new inversion. The recommended seam runs inside `close_settlement`
(SSCAS #4, Settlement → Payout, `087:295`) and Decision A correctly requires it to take the same per-org
advisory lock as the live seams (`088:330`, `090:1519`). This is a real advantage of variant 1a/1b over
Option 2, and the packet is right about it.

**MUST NOT.** Sound, except the refund-lease entry (X-19), whose justification I could not locate in
Decision D and which the repository's own recent history contradicts (`a16a16d fix(payments): webhook
retries no longer silently dropped (claim lease)`).

---

## 6. FINAL VERDICT — is the packet safe to rule on?

**Decisions C and F: YES**, with the corrections in X-14/X-15/X-16 (narrow the residual threat to
superuser; note the `create_event` race; C's core reasoning and the E-76 correction are confirmed) and
X-10/X-21 (F's fix is right, its test cost is unstated and its "exactly six facts" is seven columns).

**Decision E: YES ON THE CONCLUSION, NO ON THE EVIDENCE.** Constrained relaxation is the right call and
the rail-pairing CHECK is provably satisfiable against every row the repository can account for. But the
headline claim the packet uses to sell it — that `mode` has no consumers — is **false** (X-3), and a
reviewer who accepts a false premise once will accept it again. Correct the claim, add "update both
type packages", drop the policy clause, and it is rulable.

**Decisions A, B and D: NOT AS WRITTEN.**
- **A** classifies a **merchant-of-record change** as an implementation follow-up on a stated ground
  that is false (X-1); its seam mis-handles partial refunds (X-5); it leaves promoter commissions
  deducted-but-undischargeable (X-6); its precedent argument for replacing `close_settlement` does not
  exist (X-12); and its "not optional" index introduces an abort path it does not name (X-13).
- **B** is analytically correct and recommends the right ceremony, but asserts that two deployed test
  suites stay green when they do not (X-4), and understates the risk of a single, unrotatable,
  unrevocable, platform-wide key (X-11).
- **D** mis-classifies a key that requires a migration (X-7) and recommends a fallback operating process
  that has no implementation and contradicts Decision C (X-8).

**And above all: the packet is asking the wrong question first.** It presents six decisions as what
stands between the owner and a first venue-direct ticket. Two things sit upstream of all six:

1. **Who is the merchant of record** — which the frozen corpus answers one way (`SNATCH_IT_DOMAIN_ARCHITECTURE.md:142`, `:851`) and the recommendation answers the other, and which determines Decision A's classification, Decision D's refund authority, Decision F's controller posture, and a tax and 1099 exposure nobody has costed.
2. **How a venue organization is attached to Stripe at all** — for which no code exists anywhere in the repository (X-2).

Rule on those two first. Then A–F become tractable, and four of the six need edits before they are worth
a signature.

---

### Could not determine

- Whether production's catalog and grants match the repository DDL (`create table if not exists` plus
  the `022` rename guard prove the payments table predates its current file text). Production was not
  queried; this review is repo-only, per the read-only constraint.
- The **56 production rows** figure in Decision E (X-20).
- Whether `public.admin_users` truly holds one row in production (X-25).
- Whether CI replays 093 as part of the pgTAP chain — the only way `147:122` and `150:105` survive
  the bootstrap row without amendment (X-4).
- The justification for the "no lease column on the refund table" MUST NOT (X-19).
- Whether the inability to settle a co-promoted night at a shared address is a commercial problem.
