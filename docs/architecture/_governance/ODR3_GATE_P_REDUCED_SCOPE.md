# `ODR-3` — Gate P REDUCED: the scope, and its three pre-authoring blockers

**2026-08-28.** Records the scope of owner ruling `OR-5` (corpus option `[C]`). Rules on nothing.
Settled inputs: `ODR-2 = [A]` BUILD · `#31`/`#32` KEEP · `#2`/`#5`/`#11` REMOVE.

> ## THE FINDING THAT RESHAPES THE SCOPE
>
> The reduction is **not** primarily a matter of product taste. It is forced by **gate
> reachability**, and the corpus already derived most of it. The ruling's clause *"transfer-related
> mandatory notices **where Phase 2 requires them**"* resolves to **the empty set**:
> `transfer_received` and `transfer_accepted` are MANDATORY, but both are triggered by `#18`/`#19`,
> which are Gate M under ratified `C43`. The qualifier is doing real work and it points at nothing.
>
> The residual custody notice that IS Gate-P mandatory is `ownership_changed` (`#17`), because it
> *"fires on issuance and on refund-void, not only on resale"*.

## 1. IN — 23 type keys (21 MANDATORY + 2 non-mandatory)

**MANDATORY (21).** `purchase_confirmed` · `ticket_ready` · `purchase_failed` ·
`ownership_changed` · `payout_released` · `payout_failed` · `payout_on_hold` ·
`staff_payout_failed` · `refund_requested` · `refund_approved` · `refund_completed` ·
`refund_failed` · `event_cancelled` · `event_time_changed` · `event_venue_changed` ·
`event_postponed` · `security_password_changed` · `security_payout_destination_changed` ·
`security_payout_method_added` · `security_org_role_granted` · `security_org_role_revoked`.

**NON-MANDATORY (2), each IN by an explicit clause of the ruling.**
`promoter_commission_accrued` (class `ON`) — the *only* consumer `#32` has, and `#32` is KEEP.
`wallet_pass_available` (class `ON`) — the only holder-facing credential notice; rides Apple
Wallet's own gate.

**A useful check on the whole exercise:** three MANDATORY types are OUT — `transfer_received`,
`transfer_accepted`, `listing_sold` — and all three are gate-deferred by ratified rulings, not by
this reduction. `24 − 3 = 21`. **The reduced gate drops no mandatory type Phase 2 can trigger.**

### 1.1 The door clause resolves to a REPORTED GAP, not a decision

The catalogue contains **no MANDATORY door type**. But `DOOR:1577–1581` names `notify` as a
consumer of **five** Gate-P door events (`#37`–`#41`), and `DOOR:1543–1545` writes the copy
verbatim — *"Your transfer was cancelled because doors opened — the ticket is back in your
account."* **None of the 40 catalogued types covers any of them**, and the nearest
(`transfer_cancelled`) addresses the wrong party and is Gate M anyway. Either these five need type
keys inside the reduced gate, or they defer with the resale rail. The ruling's *"where required"*
does not settle it, because the requiring document is DOOR, not NOTIF.

## 2. OUT — 17 types

Gate-M rail (10): `transfer_sent` · `transfer_received` · `transfer_accepted` ·
`transfer_declined` · `transfer_cancelled` · `transfer_expired` · `listing_created` ·
`listing_bid_received` · `listing_outbid` · `listing_sold`.
Scheduler-driven, excluded by the ruling (3): `event_reminder_24h` · `event_door_open` ·
`staff_sales_digest`.
Announcement surface, excluded by the ruling (1): `organizer_announcement`.
Deferred (3): `promoter_attribution_recorded` (OFF; a working promoter generates hundreds — a
digest belongs at Gate L) · `staff_low_inventory` · `staff_door_anomaly`.

> **CONSEQUENCE TO SURFACE.** With `promoter_attribution_recorded` OUT, **`#31 AttributionRecorded`
> has no Gate-P consumer** under the reduced gate — its money write is same-transaction by ratified
> `D7`. `ODR-2` ruled `#31` KEEP. Whether a kept event with no consumer is a defect or a deliberate
> placeholder is not settled here.

## 3. Required objects — reduced vs full, every number derived from the IN set

| | full | **reduced** |
|---|:-:|:-:|
| tables | 9 | **7** |
| RPCs | 23 | **16** |
| edge functions | 2 | **2** (+2 shared modules) |
| cron entries | 3 | **2** |
| dashboard surfaces | 3 | **1** |
| registry rows | 67 | **50** |
| pgTAP assertions | 44 | **35** |

**Tables dropped:** `notify.schedule` (its `schedule_kind` CHECK is exactly the three OUT types, so
it has no remaining producer) and `notify.announcement`.
**Tables kept that might look droppable:** `notify.identity_channel_state` — required by *"deliverability
failure is not consent"*; a hard bounce must be per-identity and persist across notifications, which
`notify.delivery` structurally cannot hold. And `notify.template` — **reduced in rows, not in shape**,
because storing `template_key` + `params` rather than a rendered string is what implements privacy
invariant `N-P1` (*the push body for custody and money types carries no counterparty name and no money
amount*), which governs four IN mandatory types.
**RPCs dropped (7):** the six announcement RPCs plus `sweep_scheduled`.
**`notify-receipts` is NOT droppable — the reduction makes it MORE necessary.** It is the first code
in this system's history that would ever mark a token inactive. With 21 mandatory types and email
unresolved, push is often the only live transport; without receipt polling a `DeviceNotRegistered`
token accepts every mandatory money notice and delivers none. That is precisely *"would otherwise
ship silent"*.

### 3.1 Two counting corrections owed to the corpus

`NOTIF` Appendix B says *"2 new pg_cron jobs"* for the **full** platform, omitting
`sweep_scheduled`. It is 3. Anyone comparing the reduced figure against Appendix B will conclude the
reduction saved no cron; **it saves one, and Appendix B undercounts the baseline.**

### 3.2 An engineering consequence the reduction CREATES — must not be lost

Dropping `notify.schedule` removes the **expansion cursor**. But four IN MANDATORY types
(`event_cancelled`, `event_time_changed`, `event_venue_changed`, `event_postponed`) use
custody-expansion recipient derivation across every active atom of a session, and `drain_outbox` is
specified as *"one set-based INSERT … SELECT … No row loop"* **with no bound**. A cancellation of a
50 000-holder event under the reduced drainer is one unbounded transaction holding one long lock.
**The reduced build must carry the cursor on `notify.outbox`, or `drain_outbox` must chunk
internally.** Engineering, not an owner decision — but it disappears with the dropped table if
nobody writes it down.

### 3.3 One thing NOT to reduce

Do not prune the `target_kind` closed set. It is a CHECK against a closed set, so adding a value
later is a migration. Pruning saves nothing at build time and buys a migration at Gate M.

## 4. The mandatory-class DDL — verified, and IN

It exists verbatim: a composite `FOREIGN KEY (type_key, delivery_class)` plus
`CHECK (delivery_class <> 'mandatory')` on `notify.preference`. Its stated property is the one that
matters: *"`service_role` bypasses RLS but **cannot bypass a CHECK constraint**, which is exactly why
the guarantee is put here and not in a policy."* Reclassifying a type to mandatory becomes a forced,
visible, failing migration via `ON UPDATE CASCADE`.

**The reduction RAISES its value.** In the full platform it protects 24 of 40 types (60%). In the
reduced set it protects **21 of 23 (91%)** — the reduced gate is very nearly *nothing but* the
mandatory class. Cheapest structural guarantee in the package, and the hardest to retrofit: doing it
later means a data migration that deletes preference rows users have already set.

## 5. Package placement — `092`. The hypothesis that reduction moves it is FALSIFIED, twice.

**Falsification 1 — the ruling itself holds the floor at `090`.** Four of the drainer's reads do drop
under the reduction (`venue.inventory_batch`, `venue.scan`, `market.p2p_transfer`, and one more) —
but **`venue.promoter_link` (`090`) STAYS**, because `promoter_commission_accrued` is IN by explicit
ruling and derives its recipient from it. `SEAM-1` takes `max()` over every table read, written, or
reached through a call. **Floor = `090`, identical to the full platform.** The prior pass's
conditional was correct as stated and is inapplicable, because the ruling keeps `#32`.

**Falsification 2 — the floor does not determine the number anyway.** The band `076`–`091` is fully
allocated, and `091` is a **protected shape**: always empty, referenced by no routine, which is what
makes its rollback unconditionally reversible. Loading nine tables into it destroys that property.
Even if the floor fell to `085`, the number would still be `092`.

**A two-package split would satisfy `SEAM-1` and is rejected:** it makes the count 18, splits one
schema's RLS posture across two rollback boundaries, and both halves still land above `091`.

> **THE CONSEQUENCE THAT RIDES WITH THE RULING.** `092` makes the registry **17 packages, range
> `076`–`092`**, falsifying registry §2's *"no gaps, no duplicates"*. **This requires re-ratifying
> `ODR-1`.** The reduction does not avoid it, and anyone hoping the reduced scope could be tucked
> into the existing band should be told plainly that it cannot.

## 6. `N1` — TRANSACTIONAL EMAIL

**The reduction does not reduce the email dependency. It CONCENTRATES it: 79% → 81%.** 17 of the 21
IN mandatory types carry an email channel (18 including `promoter_commission_accrued`). The types cut
are the resale and transfer rails; the types kept are money, refund, security and event-viability —
the four families where email is the redundant channel that survives a lost or wiped phone.

**What exists today — all four claims independently re-verified:** one flag-gated Resend `fetch` in
`notify-report`, default off, file-private, no SDK anywhere in any `package.json`; nothing in `web/`;
auth mail on a personal Gmail relay.

**One further fact, load-bearing for `N2` as well:** this project has **observed** one-time
recovery/confirmation links *"already consumed within seconds of issuance (consistent with automated
link-prescanning)"*. And `EMAIL_FROM` currently defaults to the **apex** domain while auth mail
relays through Gmail — so apex mail already originates from two unrelated sources, and any DMARC
enforcement at the apex breaks one of them.

### 6.1 The plain statement

**The personal Gmail SMTP relay is not acceptable production infrastructure for venue-native money or
ticket notices.** Not as a stopgap, not behind a flag. Six mechanical reasons: it cannot DKIM-sign
for the domain, so it cannot achieve DMARC alignment · it emits **no bounce or complaint webhook**,
which makes `notify.identity_channel_state` unwritable and the whole of *"deliverability failure is
not consent"* unimplementable · it returns **no per-message id**, so a mandatory notice's delivery
outcome stays invisible · consumer quotas are far below one event-cancellation fan-out · the observed
link-prescanning already destroys one-time content in transit · and it is a **personal credential
outside organisational control on the delivery path of money notices** — a single-person dependency
on a control, not on a convenience.

### 6.2 Provider-neutral contract

Two interfaces and one store. `send(...)` returns `{provider_message_id, accepted}` or
`{retryable, error}`, takes exactly **one** recipient (never a list — recipient lists in payloads are
forbidden), a configured sender identity never supplied by the caller, a REQUIRED `text/plain` part,
and `idempotency_key = notify.delivery.delivery_id`. `onDeliveryEvent(...)` is one **signed** webhook
— the only writer of transport facts — carrying `delivered | bounced_hard | bounced_soft |
complained | deferred`. **This is the exact shape `notify-receipts` already has for Expo**, which is
why it costs no new architecture: one adapter shape, two transports.

### 6.3 Capabilities required (10)

Synchronous per-message id · signed async delivery events (delivered/hard bounce/soft
bounce/complaint) · `text/plain` part · custom-domain DKIM on a **subdomain** · documented `429` +
`Retry-After` · **suppression list readable and clearable via API** (a provider-side list we cannot
read will silently shadow our own authority and drop mandatory notices with no local trace) · plain
HTTPS JSON, no SDK (Supabase Edge runs Deno; keeps the adapter one file wide) · sending identity
separate from auth mail · per-environment keys · idempotency honoured or documented as not.

### 6.4 SPF / DKIM / DMARC

**Send from a dedicated subdomain, not the apex** — the single most important structural choice here,
because the apex already carries Gmail-relayed auth mail and reputation must be separable so a
marketing or auth incident cannot suppress a mandatory money notice.
**SPF:** exactly one TXT `v=spf1`, provider `include:` only, ≤10 lookups, `~all` then `-all`.
**DKIM:** 2048-bit, provider-held private key, **no key material in the repo, ever**.
**Return-Path:** a subdomain we control — a provider-default bounce domain gives SPF `pass` but DMARC
`fail` on alignment.
**DMARC:** staged `p=none` → `quarantine; pct=25` → `reject`, with `rua` going somewhere a human
reads. **The apex must be resolved before enforcement**; enforcing without migrating auth mail is a
self-inflicted auth outage.

### 6.5 Secrets, failure, retry

Supabase Function secrets, referenced by name only; never in the repo, `web/`, a client bundle, or
`app.json`; distinct per environment; **scoped send-only** where possible, because a key that can
also edit DNS turns a leaked secret into a domain takeover; the webhook verifies the signature
**before** parsing. **Rotation owner is the owner** — written down explicitly, because the current
auth-mail credential is a personal Gmail account and that ownership ambiguity is what is being
corrected.

Failure: no provider → every `E` row `suppressed/channel_unavailable`, in-app still written, push
still attempted. Hard bounce or complaint → `identity_channel_state`, **never** `notify.preference` —
a bounce is not an opt-out. Push unavailable **and** email OFF by preference on a MANDATORY type →
email attempted anyway, because *the preference governs whether the user wants to be interrupted and
the mandatory class governs whether they must be reachable*. No transport at all on a MANDATORY type
→ recorded `undelivered_mandatory`, in-app banner, Sentry. **Never aborts the producing transaction.**
Retry: the same ladder as push — +1m, +5m, +25m, +2h, +12h, then `dead`; no separate DLQ table.

### 6.6 Must provider selection be an owner decision? **YES.**

1. **It is a data-processor relationship, not a library choice** — every recipient's address leaves
   the platform to a third party on the delivery path of money and security notices.
2. **It binds production DNS on the apex**, including the Gmail conflict, which can break auth mail
   for every existing user.
3. **A ratified control depends on it.** `O-3` was ratified *with* its compensating control, specified
   as *"by push **and** email, immediately"*. **Push to the phone holding the compromised session is
   not out-of-band. Email is what makes it out-of-band.** Silently degrading a ratified control is not
   an engineering call.
4. **Because the architecture is provider-neutral, the decision is cleanly separable from the build —
   which is exactly why it must be MADE rather than DEFAULTED.** The default on silence is "use
   Resend, because a `fetch` to it already exists in `notify-report`": a vendor chosen by accident of
   a moderation prototype.

**NOT an owner decision:** the contract, the capability list, the DNS shape, the failure and retry
semantics. All derived above, identical for any provider.

## 7. `N2` — UNIVERSAL LINKS / ONE-TAP ESCALATION

### 7.1 The deep-link half RESOLVES, and the invariant is not weakened

Control 5 says *"a one-tap … escalation that calls `kernel.hold_payout`"*. It does **not** say the
link carries the call. *"One-tap"* describes the affordance the recipient sees, not the transport.
The compliant construction is already fully specified by ratified text: `target_kind =
account_security` (already this type's declared target) → **tap navigates only**, per `N-DL-2` → the
authenticated, session-bound screen presents one prominent control → that control invokes the RPC
**on the caller's own JWT**, which the money spec already makes MANDATORY.

**No new authentication primitive. No new object. Universal Links do NOT become Gate P.**

**And a third argument specific to this system, which is decisive on its own:** this project has
observed one-time links *consumed within seconds by automated prescanning*. An emailed link that
*performs* `hold_payout` on load would be **fired by the recipient's mail scanner**, freezing every
pending payout for the org before any human saw the message. That is not a theoretical objection — it
is an observed behaviour of this system's mail path, and it rules out the link-carries-the-action
reading regardless of Universal Links.

### 7.2 THE SECOND COLLISION, which the deep-link question conceals

Resolving the transport does **not** make Control 5 buildable.

**`kernel.hold_payout` is platform-only, and explicitly so** — `is_platform([platform_risk,
platform_admin])`, annotated *"unchanged; SoD-3, **no org role, ever**"* in both the RLS spec and the
money spec, and described as *"`platform_risk`'s **entire** payout authority."* The corpus records
that the analogous org-side widening was already **corrected away**: a risk-placed hold released by
the org it was placed on is the control inverted.

**Control 5 offers the escalation to `org_owner` and `org_finance`. Neither may ever call
`kernel.hold_payout`.** Under the ratified matrix the one-tap control fails with
`insufficient_privilege` for **every principal it is offered to**. There is no edge workaround: the
money spec forbids invoking a money RPC on the service-role client on a human's behalf, and doing so
would be the client-supplied-authority pattern `C35` forbids.

**Three admissible resolutions, none of them mine to pick:** (a) the one-tap files a **request** to
platform rather than calling `hold_payout` — costs a new object nobody scheduled, and `action`'s
CHECK is a closed three-label set; (b) `hold_payout` gains an org arm — inverts SoD-3, the exact
widening already refused for `release`; (c) Control 5's text is corrected to describe what its
recipients can actually do — amends a ratified control.

This is an **authority** question — *who may stop money* — and it is named and stopped here.

## 8. `N3` — MONEY EMITTER → NOTIFICATION CATALOGUE MAP

**The count is wrong at two sites. It is EIGHT, not seven.** The money spec names eight emitter names;
two independent sites say *"seven money emitters"*. The mechanism is visible in the source:
`_approved / _denied / _expired` are slash-compressed into one bullet, so the list reads as six
bullets carrying eight names — and "seven" matches neither, which is the signature of an eyeball
count of a compressed list. `SPEC CORRECTION` owed at both sites.

| # | money emitter | type | verdict |
|---|---|---|---|
| 1 | `refund.request_parked` → org approvers | none | ❌ **ORPHAN** — Group F's four types all address the **payer** |
| 2 | `refund.request_pending` → buyer | `refund_requested` | ⚠️ **KEY MISMATCH** — keyed on `refund_id`, but the parked branch writes **no `kernel.refund` row** |
| 3 | `refund.request_approved` → both | `refund_approved` | ❌ **DUPLICATE SEMANTIC NAME** — two different facts, two recipients, two producers, one word |
| 4 | `refund.request_denied` → both | none | ❌ **ORPHAN** |
| 5 | `refund.request_expired` → both | none | ❌ **ORPHAN** — and its producer is contracted as *"not optional"* and *"emits a notification"* that **has no type key** |
| 6 | `payout.destination_changed` | `security_payout_destination_changed` | ✅ **MATCH** — name mismatch only |
| 7 | `payout.probation_hold` → org | `payout_on_hold` | ⚠️ **KEY + TRIGGER MISMATCH** — keyed on `dispute_id`, but a probation hold has no dispute, and its spec'd trigger `#29` is **Gate M** |
| 8 | `payout.request_pending_approval` | none | ❌ **ORPHAN** — a payout parked for dual control sits in a queue nobody is told about |

**Score: 1 clean match · 2 key mismatches · 1 duplicate name · 4 orphans.**

**Why all four orphans exist, diagnosed:** the catalogue was written against a refund model that
**executes or fails**, and the money spec's tiering introduced a **third outcome — parked** — that the
catalogue never absorbed. All four are mechanically closable: their recipient derivations are already
legal forms, and their aggregate (`kernel.approval_request`) is in `077`, **so closing them does not
move the package floor.**

**A ninth candidate, and it is a product choice — named, not decided.** `kernel.cancel_refund_request`
is contracted and audited, and §10.3 names **no emitter for it**. A buyer whose refund request is
cancelled by their venue — after their ticket carried a `refund_hold` overlay that made it
non-scanning, in a spec that says *"a ticket that silently stops working is the worst outcome in this
document"* — is told nothing. Whether that notifies the buyer, the org, or both is not derivable.

## 9. WHAT REMAINS UNSETTLED — ordered by what blocks authoring `092`

1. **Email provider selection** — OWNER (a ratified control is undeliverable without it).
2. **Control 5's escalation authority** — OWNER (`hold_payout` is barred to every principal it is
   offered to).
3. **The `refund.request_cancelled` notice** — OWNER (product).
4. `security_org_role_granted`/`_revoked` in or out — **boundary reading, placed IN and flagged**;
   they also depend on a per-role `is_sensitive` flag the spec assumes and never defines.
5. `wallet_pass_available` in or out — rides Apple Wallet's own gate.
6. **Five door carrier requirements with no type key** — reported gap.
7. **`#31` has no Gate-P consumer** under the reduced gate — reported consequence of two rulings
   interacting.
8. **Registry re-ratification** — `092` forces it; `ODR-1`.
9. **The expansion cursor** — engineering, must not be lost with the dropped table.
10. `O-N4` legal compulsion of the mandatory class — OWNER (counsel); the design is built so the
    answer changes one registry column.
11. `CONFLICT-5` org-role inheritance — pre-existing, carried in with `staff_payout_failed`.
12. **Corrections owed regardless of any ruling:** the "seven money emitters" miscount at two sites ·
    Appendix B's cron undercount · the *"promoter codes … unaffected"* line, falsified under **either**
    ruling.

---

```
EMAIL: OWNER DECISION
DEEP LINKS: OWNER DECISION
MONEY EMITTER MAP: NOT READY
```

**On the last line:** NOT READY rather than OWNER DECISION because seven of the eight rows are
mechanical and closable without the owner — re-key two, split one duplicated name, add four type
keys, correct one count at two sites. Only the ninth-candidate question is a product choice. One
mechanical pass plus one small ruling closes it.

**On the second line:** the deep-link question *itself* is READY and resolves cleanly with no new
primitive and without Universal Links becoming Gate P. It reads OWNER DECISION because Control 5
cannot ship on that answer alone.
