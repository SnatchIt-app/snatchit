# ADVERSARIAL REVIEW — venue-native + product V2

**Reviewer:** Agent J (adversarial). **Repo:** `/Users/josetascon/snatchit-consol` · branch `feature/venue-native-and-product-v2` · commit `1bfb1d0`.
**Method:** read-only. No SQL executed, no production touched, no branch created. Every verdict below carries `file:line`
evidence from the shipped bytes. Where I could not determine an answer I say so rather than guess.

**Standard applied:** overturning a claim requires proof, not doubt. Three of my own hypotheses were killed by evidence
during this review and are recorded as CLEAN in §5 rather than dressed up as findings.

---

## 1. FINDINGS TABLE

| ID | SEV | TARGET ARTIFACT | CLAIM ATTACKED | VERDICT | EVIDENCE | CONSEQUENCE |
|---|---|---|---|---|---|---|
| **J-1** | **P0** | `PHASE2_PRIMARY_ACTIVATION_GAP_MATRIX.md` §6 + commit message | "Payment collection is verified separable from settlement and payout" | **OVERTURNED** | `087:318` (sole `settlement_line` INSERT) · `088:319-360` · `090:1511` · `090:1476-1477` · `087:340` · `create-payment-intent/index.ts:511-526` | A venue that sells 400 tickets is owed money that **no schema row names** and **no code path can pay**, even with the payout rail fully lit |
| **J-2** | **P0** | Gap matrix F4 / `PUBLIC_PAYMENTS_NATIVE_SHAPE` | "`public.payments` cannot hold a native primary row" (093 reason 3) | **CONFIRMED — but the prescribed fix is unsafe as written** | `085:42` · `000_baseline_schema.sql:973,975,995` · `000:70-77` · `000:1026-1031` | The proposed nullable `seller_id` silently makes native payments **invisible to the venue** through the only seller-side RLS policy |
| **J-3** | **P1** | `src/lib/venue/client.ts`, `types.ts` | "Signatures were read from the deployed catalog, not guessed" / "These mirror the deployed Phase-2 schema" | **OVERTURNED** | `client.ts:5-6`, `types.ts:4` vs `081:37,41-42,62,63-64,1014-1016` | Three enums wrong, `sessionAvailability` cannot execute at all; fails at activation, not at compile time |
| **J-4** | **P1** | `src/lib/venue/client.ts` idempotency comment | "Every mutating RPC is idempotent on its command key; caller keys only for money-adjacent paths" | **OVERTURNED** | `client.ts:16-20` vs `:118,131,150,170,185,200` · `081:76-78` | `createInventoryBatch` double-tap creates **two batches = double capacity**; the oversell CHECK is per-batch and does not catch it |
| **J-5** | **P1** | `app/settings/index.tsx` tri-state fix | "A failed probe no longer reads as not-pending" | **QUALIFIED — mechanics correct, fix incomplete** | `077:82,98,510-512` · `delete-account/index.ts:148-160` (all correct) vs the `maybeSingle()` mapping and the optimistic withdraw | RLS-filtered rows return `data:null, error:null` → banner silently vanishes, which is the original defect |
| **J-6** | **P1** | `COMPETITIVE_AUDIT.md` + `_research/*.md` | OBSERVED/INFERRED discipline is maintained | **OVERTURNED at the synthesis layer** | `COMPETITIVE_AUDIT.md:5` (0 tags in 187 lines) · `:104` vs `crowdvolt.md:392` · `:97-99,156` vs `dice.md:805-807,799-801` · `posh.md:955-956` vs `:815,881-882` | Pricing and fee-posture recommendations rest on inferred numbers presented as fact |
| **J-7** | **P1** | `EVENT_MEDIA_SYSTEM.md` 4:5 master | "Portrait is the source of truth… it matches the source, so nothing is thrown away" | **OVERTURNED for existing content; unserviceable for new** | `CreateListingScreen.tsx:192` · `useImageUpload.ts:78` · `000:98` · `089:72` · `media_current_state.md:347,372,394` | Portrait pixels were **never uploaded** (destructive 16:9 crop); and the direct rail the system is built for has **no image source at all** |
| **J-8** | **P1** (audit says P0) | `venue_security_audit.md` V-1 | "Operatorship transfer P0 — activation-blocking" | **CONFIRMED as a defect · QUALIFIED on severity and on 'activation-blocking'** | `078:688-704` (verified: `is_platform(['platform_admin'])` + `reason_required`) · `077:477-486` · `033:112` · `083:375-383` | Not attacker-reachable. Fires only on a deliberate, audited, platform-only tenancy move; most consequences sit behind the signing-key block |
| **J-9** | **P2** | Gap matrix rows B3a, line 219, M2 | "`door.schedule_move_grace_interval` absence is a LIVE FAIL-OPEN — the only fail-open in the primary path" | **OVERTURNED** | `079:648-652` (`v_grace is null` makes the disjunct **true** → guard fires) · `079:635-637` | 093 scope overstated; the prescribed "fail-safe the guard" body change would **invert** correct behavior |
| **J-10** | **P2** | Gap matrix G1 / M1 | "No ACTIVE `kernel.signing_key` row can exist" (093 reason 1) | **CONFIRMED in practice · QUALIFIED as stated** | `083:375-393` · `083:110-115` (SELECT-only, no DML grant to any role) · only INSERTs repo-wide are pgTAP fixtures | Table owner bypasses grant and SELECT-only RLS. The absolutist framing invites a hand-run INSERT that skips the E-47(a) principal check the matrix itself demands at G6b |
| **J-11** | **P2** | Gap matrix config framing | Implied: the config surface needs 093 (093 reason 2) | **QUALIFIED — half right** | `078:1522-1524` (all three `feature.*` gates **are** seeded) · `078:1145-1147` (`feature.*` not dual-control) vs `078:1099-1103` + `081:611-635` | Flag activation needs **no** migration. Only two rows genuinely require one — which E1/E2 state correctly |
| **J-12** | **P2** | `client.ts:311-314`, `types.ts:141` | "Never expose exact remaining inventory… inventory levels are venue-private" | **OVERTURNED** | `081:1014-1024` grants `remaining` to `authenticated` for every `public`-visibility type · `081:71` | Exact remaining inventory is world-readable to any signed-in user in one PostgREST query. The band rationale is fiction |
| **J-13** | **P2** | `PRODUCT_INFORMATION_ARCHITECTURE.md` | "One event page, always" | **QUALIFIED — breaks for the majority of live inventory** | `:57`, `:117` vs `000_baseline_schema.sql` (`event_name`/`venue`/`neighborhood`/`event_date` are free text) | On day one almost no resale listing has a `catalog.event`. No ghost-event, matching or migration rule exists |
| **J-14** | **P2** | `venue_security_audit.md` C4 | Pre-flip manual ACL verification | **CONFIRMED, and the audit's own escalation is right** | `076:100-111` (PFA-1: schema-scoped default privileges for FUNCTIONS are impossible in Postgres) | A one-time pre-flip check cannot catch a *future* 093 function that forgets `REVOKE … FROM public`. Must be CI |
| **J-15** | **P2** | `is_platform` bootstrap / matrix A1 "LOW" | Legacy `public.admin_users` confers Phase-2 platform authority | **CONFIRMED · matrix under-rates but prescribes the right action** | `077:477-486` · `033:102,112` | Humans given "admin" for **listing moderation** in `033_marketplace_expansion` now hold operatorship-transfer, config-flip and comp authority over the venue plane |
| **J-16** | **P2** | `client.ts` error handling | "Never a raw Postgres string… safe to show a user" | **QUALIFIED** | `client.ts:48-68`, `:99` | Fail-closed states surface as generic "please try again"; `hasVenueRole` returns **false on network error**, silently stripping door-staff authority offline |
| **J-17** | **P3** | `client.ts:160-161` JSDoc | "Shards spread contention. 0 lets the server choose." | **OVERTURNED** | `081:355-356` — any `shard_count > 0` raises `sharding_deferred` | Comment invites a parameter value that always fails |
| **J-18** | **P3** | Gap matrix F4 citation | Line references | **QUALIFIED** | Cites `000:972-974`; actual are `:973`, `:975`, `:995` | Citation drift only; the substance holds |
| **J-19** | **P3** | `types.ts:35` + `081:37,64` | Comps are a first-class kind | **OVERTURNED** | `081:37` `kind in ('admission','table')` · `081:40` `price_minor > 0` · vs `release_kind` admitting `'comp'` (`081:64`) | A free ticket is **structurally impossible**: every ticket type must be priced > 0. Free RSVP events cannot exist |
| **J-20** | **P3** | `PRODUCT_INFORMATION_ARCHITECTURE.md:75-83` | Five tabs each map to a real recurring job | **QUALIFIED** | `:75-83` vs `:81,82` | For a supply-only user three of five tabs map to no job, and payouts appear under Sell while Profile also claims payment methods |
| **J-21** | **P1** | `venue_security_audit.md` exposure verdict | "No table becomes readable that should not be… with C1–C5 met, exposing is safe" | **CONFIRMED on tables · INCOMPLETE on functions** | Independent enumeration: 34 tables all RLS-on, category-(c) functions **empty** (audit is right) — but `086:1442`, `087:1473`, `090:1600` assume edge-fronting | Exposure converts **69 `authenticated` DEFINER RPCs into direct `POST /rpc/…` endpoints**, removing an Edge layer several bodies' own comments assume is in front of them |
| **J-22** | **P3** | `venue_security_audit.md` anon surface | "The only anon-visible item I would change is V-14" | **QUALIFIED** | `078:124` grants `catalog.venue.address` and `org_id` to **anon**; `086:538` hashes door-session tokens with `md5()` | Signed-out enumeration of every approved venue's address and operator org id; `md5` is not an acceptable token digest |

**Counts:** 2 × P0 · 7 × P1 · 8 × P2 · 5 × P3.

---

## 2. OVERTURNED CLAIMS — WHAT IS ACTUALLY TRUE

### J-1 — Collection is not separable. It is separable *in principle* and broken *in fact*, in both directions.

The matrix's §6 headline and the commit message say the separation is **verified**. The matrix's own §6 body contains
the disproof, quoting E-138: an event settlement is "structurally empty" and turning the payout rail on later is
"additional work, not a flag flip." Two independent facts make it worse than that framing admits.

**Money-out is structurally impossible, not merely switched off.** `087:318` is the only `INSERT` into
`venue.settlement_line` in the entire repository. Its two sources are the resale royalty/chargeback seam
(`088:319-360`) and the promoter commission seam (`090:1511`), which is **negative**. Neither emits a primary-sale
line. So gross is 0, net is negative, `close_settlement`'s `if v_net > 0` (`087:340`) never fires, and no org payout
is ever minted. `090:1476-1477` states this in its own comment. Lighting the payout rail changes nothing for primary
revenue.

**Money-in is a platform charge with no obligation record.** `create-payment-intent/index.ts:511-526` builds the
PaymentIntent with no `transfer_data[destination]`, no `on_behalf_of`, no `application_fee_amount` and no
Stripe-Account header. Funds land in the **platform's** Stripe balance. Disbursement is a separate `/transfers` call
(`_shared/payouts.ts:133`) gated on a connected account with an active `transfers` capability — and for a venue org
there is no connected account, no payee identity, and no caller for `kernel.mark_payout_transfer_state` (`085:1668`).

**And there is no consumer.** `stripe-webhook/index.ts` branches only on `metadata.mode === 'buy_now' | 'auction'`
(`:376`, `:382`, `:536`). A native charge has no webhook branch, so `finalize_primary_order` is never called and no
ticket ever mints.

**What is actually true:** collection and settlement are separable as *architecture*. As *shipped bytes* neither end
works, and the gap between them is where 400 buyers' money would sit. The harm is the word **"verified"** — a reader
acting on the headline ships a rail that takes money it cannot disburse and cannot account for.

**Real-world consequence for a venue selling 400 tickets:** the platform holds the gross in its own Stripe balance;
`venue."order"` and `kernel.payment_native` record that a sale happened but not that anyone is owed; every settlement
that venue ever opens reports zero; and the venue must be paid by manual out-of-band transfer with reconciliation
performed by hand against `venue."order".total_minor`. That is a money-transmission and bookkeeping posture, not a
feature flag.

### J-3 — The client contract does not match the schema, and its one read function cannot run.

`client.ts:5-6` asserts signatures "were read from the deployed catalog, not guessed" and `types.ts:4` that the types
"mirror the deployed Phase-2 schema." Both are false for the table-read surface:

- `TicketTypeKind` (`types.ts:35`) admits `'comp'` and `'addon'`; `081:37` is `check (kind in ('admission','table'))`.
- `TicketTypeVisibility` (`types.ts:38`) admits `'unlisted'` and **omits `'door_only'`**; `081:41-42` is
  `('hidden','public','door_only')`. Box-office/door pricing is unrepresentable in the client's type system.
- `ReleaseKind` (`types.ts:41`) uses `'hold'` and **omits `'door'`**; `081:63-64` is
  `('public_sale','promoter_hold','comp','door','presale')`.
- `sessionAvailability` (`client.ts:319-325`) filters `.eq('session_id', …)`; the column is **`event_session_id`**
  (`081:62`) → PostgREST `42703`. It also selects `capacity, held, sold`, which are **deliberately excluded** from the
  `authenticated` column grant (`081:1014-1016` grants only `batch_id, ticket_type_id, event_session_id, release_kind,
  is_sharded, remaining, created_at, updated_at`) → `42501`. The function is dead twice over, and the generated column
  built for exactly this purpose — `remaining` (`081:71`) — is unused.
- `InventoryBatch` (`types.ts:92-102`) declares `sessionId`, `capacity`, `held`, `sold` as required fields no client
  can obtain.

The `as any` casts at `client.ts:72, 78, 84, 286, 320` suppress every check that would have caught this at build time.
The module would fail on the day of activation, in front of buyers, not in CI.

### J-4 — The idempotency guidance is inverted, and one default is an oversell primitive.

`client.ts:16-20` states every mutating RPC "is idempotent on" its command key and that callers need supply their own
key only "for anything money-adjacent." Given idempotency-on-key, a **fresh** key on retry is a **new command** — so
the correct default for any non-repeatable verb is a caller-owned stable key. The code does the opposite for six
verbs: `createEvent` (`:118`), `publishEvent` (`:131`), `createTicketType` (`:150`), `createInventoryBatch` (`:170`),
`setTicketTypePrice` (`:185`), `setBatchCapacity` (`:200`).

`createInventoryBatch` is the dangerous one and it fails the header's own "money-adjacent" test only on a technicality.
A double-tap, or a retry after a lost response, on "create batch, capacity 400" creates **two batches totalling 800
sellable seats**. `inventory_batch_oversell_check` (`081:76-78`) is per-batch and does not catch it. The venue then
owes 400 refunds or 400 seats that do not exist.

Secondary, and **undetermined**: `commandKey` (`client.ts:40`) falls back to `Date.now().toString(36)` when
`crypto.randomUUID` is absent. `react-native-get-random-values` polyfills `getRandomValues` but not `randomUUID`, so
the millisecond-predictable fallback may be the live path on device. I could not determine from this repo whether a
`randomUUID` polyfill is installed. **Verify before use.**

### J-6 — The research is honest; the synthesis is not.

The three research files make real, unforced admissions of ignorance (`posh.md:815`, `:881-882`; `dice.md:799-801`;
`crowdvolt.md:9-12`), and body tagging is genuinely applied. Discipline collapses precisely where claims become
decisions:

- `COMPETITIVE_AUDIT.md` carries **zero** OBSERVED/INFERRED tokens across 187 lines while asserting at `:5` that the
  underlying research is tagged.
- **Fee rate.** `crowdvolt.md:392` correctly tags the "~4% per side" take INFERRED and states "the actual fee rate is
  **never disclosed**"; it is arithmetic over ~4 observed spreads. `COMPETITIVE_AUDIT.md:104` states it as fact and
  `crowdvolt.md:655` recommends pricing against it.
- **DICE's fee posture.** `dice.md:805-807` observes only the *absence* of the string "fee" from a ~1,328-key
  dictionary. `COMPETITIVE_AUDIT.md:97-99` becomes "DICE deleted the concept… Prices are all-in," and `:156`
  recommends adopting it — a pricing decision made by people who never reached a DICE checkout, as `dice.md:799-801`
  admits.
- **Auth-gated surfaces tagged OBSERVED.** `posh.md:955-956` tags OBSERVED an organizer-composer behavior whose own
  source (`posh.md:837-839`) is INFERRED from two tooltip strings, contradicting `posh.md:815`/`:881-882`.
- `dice.md:1204-1335` and `crowdvolt.md:613-655` — the two recommendation sections — carry zero tags.

### J-7 — The 4:5 master cannot be derived, and the rail it serves has no images.

`EVENT_MEDIA_SYSTEM.md:58` and `:177` argue portrait "matches the source, so nothing is thrown away." For the existing
corpus the opposite is true: the mobile picker performs a **destructive** 16:9 crop before upload
(`CreateListingScreen.tsx:192`; default `useImageUpload.ts:78`) and `cover_image_path` is NOT NULL (`000:98`). The
portrait pixels do not exist in storage and cannot be recovered. Migration day therefore letterboxes **every legacy
listing** into the blurred-self backdrop — the fallback specified at `EVENT_MEDIA_SYSTEM.md:110-114`, which is
calibrated for nightlife flyers. `media_current_state.md`'s own evidence is that the seller base uploads screenshots
of ticket confirmations; blurring a white confirmation email at `blur(54px)` yields a grey smear with a faint dark
band, not a backdrop.

Worse, the direct rail the whole system exists to serve has **no image source**: `market.listing_unified` hard-codes
`null::text as cover_image_path` on the native arm (`089:72`, restated `media_current_state.md:347`, `:372`), and
`catalog.event_media` does not exist — it is proposed as a 093+ (`media_current_state.md:394`). On day one every direct
event renders with no image at all.

### J-9 — The "only fail-open in the primary path" is fail-closed.

Matrix row B3a (line 69), restated at line 219 and folded into M2, files the absence of
`door.schedule_move_grace_interval` as "the only fail-OPEN found in the whole primary path" requiring a 093 body
change. The shipped guard is `079:648-652`:

```
if (v_new_starts > v_starts and (v_grace is null or v_new_starts - v_starts >= v_grace)) … then
  raise exception 'precondition_failed: move_exceeds_grace';
```

`v_grace is null` makes the disjunct **true**, so the guard **fires**. Absent config is fail-**closed**, exactly as
`079:635-637` says in its own comment. The genuine residual is narrower and different: the predicate tests
`v_new_starts > v_starts`, so an event can be moved **earlier** without limit. Consequence of the error is not
academic — a 093 written to the matrix's description ("absent ⇒ no later move," i.e. make it fail-safe) would be
written against behavior that already holds, and a careless author could invert it.

### J-11 — Feature-flag activation needs no migration.

`feature.native_issuance_enabled`, `feature.native_scanning_enabled` and `feature.native_resale_enabled` are all
seeded at `078:1522-1524`, and `feature.*` is **not** in the dual-control namespace list (`078:1145-1147`). A
`platform_admin` flips them single-handed through `catalog.set_platform_config`. The genuine migration requirement is
exactly two rows — `inventory.hold_ttl_interval` and `inventory.per_user_active_hold_max` — which have no registry
row, are read on every reserve (`081:611-635`), and cannot be created because `set_platform_config` raises
`unknown_key` (`078:1099-1103`). Matrix rows E1/E2 state this correctly; the surrounding framing overstates it.

### J-12 — Exact remaining inventory is public to every signed-in user.

`client.ts:311-314` and `types.ts:141` assert that exact counts are never exposed because "the corpus treats inventory
levels as venue-private." `081:1014` grants `remaining` — a stored generated column, `capacity - held - sold`
(`081:71`) — to `authenticated`, and `081:1020-1024` opens it for every `public`-visibility ticket type. Any signed-in
user can read exact remaining inventory for every public tier at every venue in one query. The audit notes this at
V-12 and calls it correct *per spec*, so the spec and the client comments disagree and the client comments are wrong.
The band logic is not a privacy control; it is a rendering choice with a false rationale attached.

---

## 3. QUALIFIED — WHERE SEVERITY, NOT SUBSTANCE, IS WRONG

### J-8 — V-1 is real, and it is not a P0, and it is not activation-blocking.

The mechanism is exactly as the audit describes and I verified each link: `catalog.update_venue` repoints
`catalog.venue.org_id` (`078:688-704`), `catalog.event.org_id` is stamped at create and never re-derived
(`078:877-881`), `has_venue_role` is venue-keyed with no operator test (`080:60-73`), and the only writer that ever
deletes `staff_role` is the erasure hook (`080:314-324`). Stale staff do keep authority across a tenancy move.

But the exploit requires an authority no attacker has. The `org_id` arm is gated
`kernel.is_platform(array['platform_admin'])` and additionally requires a non-empty `reason_code` (verified at
`078:688-695`). `platform_admin` derives only from `kernel.platform_role` or the `public.admin_users` allowlist
(`077:477-486`), and `admin_users` is `REVOKE ALL ON public.admin_users FROM PUBLIC, anon, authenticated` (`033:112`)
with no client write path anywhere in the repo. `kernel.grant_platform_role` is itself a hard-raise stub
(`077:1591`).

So V-1 is **not attacker-initiated**. It fires when the platform performs a deliberate, audited, platform-only tenancy
move. Furthermore most of its enumerated consequences — reading orders, door manifests and scan ledgers, minting comps
— are unreachable behind G1: no signing key can be provisioned (`083:375-383`), so no ticket, order or manifest exists
to leak. The subset reachable today is pricing and capacity writes on the ex-tenant's events.

**Correct classification: a correctness defect in a contracted operation, P1, not activation-blocking.** The audit's
own mitigation (c) — "operationally freeze operatorship transfers" — costs nothing precisely *because* the verb is
platform_admin-only. Making V-1 a gate on activation misallocates the schedule; it must be fixed before the first
operatorship transfer, which is a different and much later deadline.

### J-5 — The deletion-banner fix is right where it was checked and wrong where it was not.

Verified **correct**: the literal `'DELETION_PENDING'` matches the CHECK (`077:82`); `grant select on
kernel.identity_ext to authenticated` (`077:98`) with an owner-scoped policy (`077:510-512`); the `withdraw` action
genuinely exists (`delete-account/index.ts:148-160`, dispatching to `kernel.withdraw_account_deletion`). The tri-state
does fix the error case.

Remaining holes:

1. **RLS-filtered is not an error.** `maybeSingle()` on a row the policy hides returns `data: null, error: null`,
   which the code maps to `'active'`. The banner vanishes silently — the exact defect the tri-state was introduced to
   eliminate. The tri-state guards *errors*; zero-rows is the likelier failure and is unguarded.
2. **Optimistic withdraw.** `handleWithdrawDeletion` sets `deletionView = 'active'` locally rather than re-probing. A
   200 response with an unmoved state machine loses the withdraw route again. Fix: `await refreshDeletionState()`.
3. **The probe runs once** (`useEffect(…, [])`), so "keeps whatever we last knew" is unreachable in practice — the
   Retry control only renders when *not* pending.
4. **First-load failure still strands a pending user**: they see only "We could not check your account status," with
   no indication that a deletion is pending.
5. **The new copy self-contradicts.** The native dialog now contains both "you can sign back in and withdraw it from
   Settings" and "This cannot be undone." in one string, and states no duration for the pending window. Apple 5.1.1(v)
   expects in-app deletion to be initiated and completed; an unbounded, contradictorily-described "request" is
   reviewable. This is a **new** risk introduced by this change, not a pre-existing one.

### J-21 — The exposure verdict is right about what it checked and silent about the actual delta.

I enumerated the surface independently rather than accepting the audit's verdict. On tables it is **correct**: all 34
`venue`/`catalog` tables have RLS enabled, none has a `USING (true)` policy, none has grants without RLS, and the nine
that must be invisible are deny-all with zero policies and no grants. On the function-ACL question the audit's own
category of concern is **empty** — I signature-matched all 98 `create … function` definitions against every REVOKE
sweep (`078:1494`, `079:780`, `080:464`, `081:1105`, `082:696`, `083:868`, `085:2165`, `086:1484`, `087:1499`,
`088:1834`, `090:1583`) and found no function retaining implicit `PUBLIC EXECUTE`. All 98 carry `set search_path = ''`.
The audit's C4 is therefore a control against **future** 093 functions, which is exactly why it must be CI (J-14) and
not a pre-flip checklist item.

What the verdict does not say plainly: exposure converts **69 RPCs already granted to `authenticated`** into direct
`POST /rpc/…` endpoints. Several of those bodies carry comments that assume an Edge function sits in front of them
("EDGE-FRONTED", "EDGE-CALLER-JWT bound" — `086:1442`, `087:1473`, `090:1600`). After exposure a browser calls
`venue.set_ticket_type_price` (`081:246`), `set_batch_capacity` (`081:408`), `grant_staff_role` (`080:121`),
`issue_comp` (`086:1172`), `record_scan` (`086:1070`), `open_settlement` (`087:227`) and
`catalog.set_platform_config` (`078:1048`) directly. I read the bodies: in-body authorization is genuinely present and
fail-closed in each case, so the wall holds — **but the wall is now the only wall**, and any rate limiting, request
shaping, logging or anomaly detection that lived in the Edge layer is gone. That is the change to plan for, and no
artifact plans for it.

Two residuals the audit's anon review missed: `078:124` grants `catalog.venue.address` **and `org_id`** to `anon`,
allowing signed-out enumeration of every approved venue's street address and its operating org; and `086:538` hashes
door-session tokens with `md5()`.

**Could not determine:** live `pg_proc.proacl`/`relacl` in production. This is a static read of migrations, and
`create or replace` preserves pre-existing ACLs. The audit's C4 pre-flip verification against the deployed database
remains necessary and I could not substitute for it.

### J-2 — The 093 prescribed for `public.payments` needs a policy it does not mention.

The blocker is confirmed and is worse than the matrix's citation suggests. `kernel.payment_native.payment_id` is a
NOT NULL FK to `public.payments` (`085:42`); `public.payments.listing_id` is NOT NULL → `public.listings`
(`000:973`), `seller_id` NOT NULL → `auth.users` (`000:975`), `mode` is `check (mode in ('buy_now','auction'))`
(`000:995`). The matrix rules out a fake listing by amendment; it is also **geographically impossible** —
`public.listings.neighborhood` is constrained to nine Miami neighborhoods (`000:70-77`), with `ticket_type` limited to
GA/VIP/TABLE, `duration_hours` to `(1,3,6,12,24,48)`, and `cover_image_path` NOT NULL.

The unenumerated consequence: `public.payments`' only seller-side policy is `seller_id = auth.uid()`
(`000:1026-1031`). Make `seller_id` nullable and that predicate evaluates NULL for every native row — the row becomes
invisible. **A venue would have zero visibility into its own primary payments,** and no org-scoped policy exists to
grant it. Any 093 taking the nullable route must ship a replacement policy in the same migration, and must audit every
consumer that joins through `listing_id`.

---

## 4. WHAT EVERYBODY MISSED

Absent from every artifact:

1. **The first paid order arms an erasure blocker, and there is no refund executor or dispute path to disarm it.**
   `kernel.deletion_blockers_money` BP-12 arm 2 (`085:261-286`) blocks account deletion for any buyer holding a `paid`
   order whenever `deletion.refund_possible_window_hours` is NULL — and it is seeded NULL (`085:2188-2190`). 400 direct
   sales therefore make up to 400 buyers **undeletable**: the app cannot honor a GDPR/CCPA or App Store erasure request
   for them, at the same moment `app/settings/index.tsx` is being changed to promise a withdrawable deletion. The
   matrix names the key (E4) but files it as a caveat; it is a consumer-rights failure armed by the first sale.
   Compounding it, nobody wrote down what a venue **does when a buyer disputes a direct charge**:
   `kernel.refund.reason_code` admits `'dispute'` (`085:76+`) but no executor exists, and the chargeback settlement
   line comes from the **resale** rail (`088:319-360`), not the primary one.

2. **Nobody specified what happens to a direct ticket when its holder deletes their account.** The credential is a
   `kernel.tickets` row keyed to `current_owner_id`; the deletion machine has a terminal `ERASED` tombstone
   (`077:82`); V-3 shows custody can even be *added* to a pending-deletion identity. No artifact says whether the
   ticket is voided, transferred, refunded, or orphaned — nor what the door scanner sees when it scans a tombstone's
   credential on the night. This sits at the intersection of the settings change, the venue rail and the deletion
   machine, and it is written down nowhere.

3. **Offline door behavior and credential accessibility are asserted, never designed.**
   `PRODUCT_INFORMATION_ARCHITECTURE.md:81` and `:117` promise Tickets is "offline-tolerant, because venue doors have
   bad signal." Every venue read in the shipped client is a live PostgREST call with no cache (`client.ts:71-87`), and
   `hasVenueRole` returns **false on any error including a network failure** (`client.ts:99`) — silently stripping door
   staff of authority the moment signal drops, which is the failure mode it claims to tolerate. No artifact specifies
   credential caching, on-device clock-skew tolerance, what the door does during an outage, or reconciliation
   afterwards. And there is **no accessible alternative to the QR credential** — no numeric code, NFC, or manual
   box-office lookup path — which is a hard barrier for blind attendees at the single moment that matters most.

Also unwritten, in descending order of consequence:

4. **Tax and reporting.** The platform takes **platform charges** (`create-payment-intent/index.ts:511-526`), which
   makes it the payment facilitator for venue revenue. No artifact addresses 1099-K issuance to venue orgs, sales-tax
   or amusement-tax collection and remittance, or which entity is the merchant of record for a direct ticket.
5. **App Store review posture for a ticketing app.** Apple exempts real-world event admission from IAP, but that
   exemption does not extend to comps, digital add-ons, or anything consumed in-app. No artifact draws the boundary,
   and `TicketTypeKind` proposes an `'addon'` value (`types.ts:35`) that lands squarely on it.
6. **Free events are structurally impossible.** `venue.ticket_type.price_minor` carries `check (price_minor > 0)`
   (`081:40`) while `release_kind` admits `'comp'` (`081:64`). Free RSVP events and guest lists — table stakes for
   nightlife, and shipped by both benchmarked competitors — cannot be represented.
7. **The IA's unhandled cases.** An event with only resale inventory *is* handled
   (`PRODUCT_INFORMATION_ARCHITECTURE.md:70-71`). The other three are not. **A resale listing whose event is not in
   the catalog** is the serious one: the doc requires sellers to pick from the event catalog (`:117`), but today's
   listing is free text and `catalog.event` holds only onboarded venues — so on day one nearly every resale listing has
   no event to attach to, and "one event page, always" (`:57`) breaks for the majority of live inventory. There is no
   ghost-event concept, no matching or dedup rule, and no migration path for the existing corpus. **Direct sold out
   while resale is live** has the copy (`:67-68`) but not the mechanic — "sold out" is undefined when a `hidden` or
   `door_only` tier still has capacity, which is the normal state (`081:41-42`). **A supply-only user** gets three of
   five tabs mapping to no job, with payouts under Sell (`:81`) while Profile also claims payment methods (`:82`).
8. **`source` is hardcoded `'web'`** (`082:433`), which silently disables door attribution — the matrix does catch
   this at F10, to its credit, but no design artifact reflects it.

---

## 5. CHECKED AND CLEAN — HYPOTHESES I COULD NOT SUSTAIN

Recorded so they are not re-investigated, and because a review that only reports hits is not a review.

- **`public.admin_users` is not client-writable.** I expected a weak root of trust behind `kernel.is_platform`. It is
  `REVOKE ALL … FROM PUBLIC, anon, authenticated` (`033:112`) with no INSERT path from any client role. The matrix's
  A1 rating of LOW stands on reachability; my J-15 finding is about *scope creep*, not exploitability.
- **`listTicketTypes` column names are correct.** All seven match `081:35-44` exactly. Only the *table-read* surface in
  `sessionAvailability` is wrong, not this one.
- **The venue authorization predicates are sound.** All four `080` predicates are `stable security definer set
  search_path = ''` with fully-qualified references (`080:60-73, 78-88, 93-103, 105-115`); no JWT-claim role test
  exists anywhere; passing a foreign `venue_id` probes that venue's roster and returns false. I tried to forge a scope
  pair and could not. The audit's assessment here is accurate and I confirm it.
- **Buyer PII is genuinely unreachable.** `list_attendees` (`087:1400-1402`), `lookup_attendee` (`087:1439-1441`) and
  `build_export_rows` (`087:910-919`) all raise after authz and before touching data. This is the strongest part of the
  build.
- **`catalog` exposure to `anon` is correctly column- and policy-scoped** (`078:124-126, 162-164, 204-207, 236-237`),
  and no `catalog` function carries an `anon` EXECUTE grant (`078:1490-1500`).

---

## 6. IS THIS PLAN SAFE TO BUILD?

**Verdict: the design work is safe to build on. The activation plan is NOT safe to execute as written, and the client
module is not safe to ship at all.**

Split the answer three ways, because the artifacts do not share a risk profile:

**(a) The research and design corpus — SAFE TO BUILD, with one correction.** `CURRENT_PRODUCT_AUDIT.md`,
`DESIGN_SYSTEM_V2.md`, `media_current_state.md`, the IA documents and the security audit are high-quality, evidenced
work. The security audit in particular is the best artifact in the set and I confirmed its clean list independently.
The correction: **strip `COMPETITIVE_AUDIT.md` of every untagged claim before any pricing or fee decision cites it**
(J-6), and re-open the 4:5 decision against the actual content corpus (J-7).

**(b) `src/lib/venue/client.ts` and `types.ts` — NOT SAFE. Do not build on this module.** It does not compile against
reality (J-3), its idempotency defaults contain an oversell primitive (J-4), and its comments assert privacy
guarantees the schema contradicts (J-12) and API contracts that always fail (J-17). It must be regenerated from the
deployed catalog — with generated types, not `as any` — before any screen imports it.

**(c) The activation plan — NOT SAFE TO EXECUTE until the money question is answered.** The plan's shape survives:
a 093 is genuinely required, and two of its three stated reasons hold (J-2, J-10), with the third half right (J-11).
What does not survive is the framing that sales can start ahead of settlement.

**Conditions that must hold before the first direct ticket is sold:**

1. **An owner decision on how a venue actually gets paid** — J-1. Either a primary-revenue settlement line is designed
   and built (a new package, not a flag), or out-of-band settlement is adopted **explicitly**, in writing, with a named
   reconciliation process and a named human. Selling first and deciding later is the failure mode.
2. **`deletion.refund_possible_window_hours` is set, and a refund executor exists** — J-4 in §4. Not "technically
   separable." The first paid order arms an erasure blocker, and taking money with no refund path is a
   consumer-protection exposure regardless of what the DB supports.
3. **The 093 for `public.payments` ships a replacement seller-side RLS policy** in the same migration — J-2 — and every
   consumer joining through `listing_id` is audited before it lands.
4. **The client module is regenerated and the six command-key defaults are made caller-owned** — J-3, J-4.
5. **The deletion banner handles zero-rows, and re-probes after withdraw** — J-5 — before the copy change reaches
   App Store review.
6. **PFA-1's function-ACL trap becomes a CI assertion, not a pre-flip checklist item** — J-14. The audit is right that
   this is the highest-risk class; a manual check cannot catch a future 093. Alongside it, **budget for the loss of the
   Edge layer** — J-21: after exposure, 69 RPCs whose comments assume edge-fronting are directly callable, and whatever
   rate limiting, logging and anomaly detection lived there must be rebuilt at the database or gateway.
7. **Operatorship transfers are frozen** — J-8 — which is free, and which correctly **de-escalates** V-1 off the
   activation path rather than gating on it.
8. **The B3a fail-open finding is withdrawn from the 093 scope** — J-9 — and replaced with the real residual
   (backward moves are unguarded).

Conditions 1 and 2 are owner decisions, not engineering tasks, and neither has been made. Until they are, every other
item on the roadmap is building a rail toward a money boundary nobody has agreed how to cross.
