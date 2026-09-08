# G7 — Adversarial review of the G1–G5 train

**Posture.** Every claim was assumed wrong until it survived an attempt to break it. Findings are
ranked **P0** (money moves wrongly, PII exposed, or a terminal/irreversible act happens
incorrectly) / **P1** (must fix before activation) / **P2** (record). Reproductions were
**executed**, not argued, unless marked *(analysis)*.

**Harness.** `scripts/rehearsal_reset.sh snatchit_rehears_adv` → 108/108 migrations, GATE-2
baseline matched (`tables=27 functions=70 policies=37 triggers=24`), plus
`supabase/tests/000_helpers.sql` for the `tap` personas. The working-tree
`supabase/migrations/093_primary_ticketing.sql` was confirmed **byte-identical** to a fresh
`scripts/assemble_093.sh` run from the committed slices before any test ran, so every result
below is against the code this train actually wrote. Attack scripts live in the session
scratchpad (`atk_g2.sql`, `atk_g1.sql`, `atk_expiry.sql`, `atk_matrix.sql`, `atk_dark*.sql`);
**no repository file was modified except this report**, and nothing was applied anywhere but the
local rehearsal database.

---

## Verdict at a glance

| Claim under attack | Verdict |
|---|---|
| G2 — eight predicates, all fail-closed, no single predicate releases | **HELD** (executed, 8/8 in isolation) |
| G2 — `payout.%` rename buys real dual control | **HELD** (parks; SoD-2 forbids self-approval) |
| G2 — the `ends_at` residual is bounded to "hours, not months" | **OVERTURNED — P0-1**, unbounded |
| G1 — BP-12 independently blocks every paying buyer | **OVERTURNED — P0-3**, only while its key is unset |
| G1 — `ends_at` moved earlier expires atoms *with no guard* | **PARTLY OVERTURNED** — the `ends_at`-only form **is** refused |
| G1 — `('24'::jsonb)::interval` = 24 seconds | **HELD**, and worse than stated (P1-5) |
| G3 — key swap / immutability / deletion / rotation prevented | **HELD** (4/4, executed) |
| G3 — T1 is superuser-only | **OVERTURNED — P1-8**, reachable by `service_role` |
| G4 — gate cannot be satisfied by deleting things | **HELD** |
| G4 — 14 scenarios caught; the manifest contract is enforced | **OVERTURNED — P1-6**, four bypasses exit 0 |
| G5 — no float on the direct rail; resale unchanged | **HELD** (0/126 mismatches; 200k-case differential) |
| G5 — `$50` can never render as `$0.50` | **OVERTURNED — P1-7** |
| Ruling A4 · face-value cap · shared headroom · exact-once · Connect two-key | **ALL HELD** |
| Money darkness — no config change alone activates a rail | **HELD** (with two caveats) |

---

## P0 findings

### P0-1 — The maturity anchor is mutable by the party being paid. A payout releases for an event that has not happened.

`catalog.update_event_session`'s time guard (`079:624-659`) tests only **forward** movement
(`v_new_starts > v_starts`, `v_new_doors > v_doors`). A **backward** `starts_at`+`ends_at` pair
takes no grace check at all — only `door_open_at is null` and a `reason_code`. Because
`kernel.close_settlement`'s anchor is `max(catalog.event_session.ends_at)` over the settlement's
own lines, the seller controls its own maturity clock.

**Executed** (`atk_g2.sql`, identical settlements A and B on the same venue, policy
`payout.settlement_maturity_interval = '7 days'`):

```
CONTROL_A  close → payout_hold "maturity_not_elapsed", matures_at 2026-09-20
BACKDATE   catalog.update_event_session(sesB, {starts_at: now-400d,
             ends_at: now-400d+5h, reason_code:'rescheduled'})  →  {"status":"ok"}
           session B now 2025-07-29 → 2025-07-30
ATTACK_B   close → "payout_hold": null            hold_state = none
PAYOUTS    settlement A  5000  pending  held  maturity_not_elapsed
           settlement B  5000  pending  none  (none)
REQUEST    request_org_payout(B) → {"status":"pending_approval",
                                    "required_approver_class":"org"}
           request_org_payout(A) → ERROR payout_held
```

The backdating actor is `venue_manager` / `org_owner`; the closer is `org_finance` — both inside
the seller's own organization, and the payout then parks for an **org**-class approver, i.e. the
same organization again. No platform human is in the path.

**What this overturns.** G2 Part 3 row #3 ("Anchor moves with it → **longer** hold"), Part 6
("Postponement: hold extends automatically"), and — decisively — G2's stated bound on the
residual: *"the most a seller can shave with an `ends_at` edit is the session's own duration —
hours, not months."* The exposure is not hours. It is unbounded, it is one contracted RPC call,
and it converts the entire eight-predicate gate into a no-op. G2 disclosed the mechanism and
then mis-sized it; the sizing is the part that matters, because it is what justified deferring
the fix out of 093.

**Fix.** Refuse a backward `starts_at` move once atoms exist (mirror the forward arm at
`079:645-652`), **or** stamp an immutable maturity anchor on the order at
`venue.finalize_primary_order` time. Until one lands, the gate is advisory against a hostile or
careless seller.

### P0-2 — The same primitive terminal-izes live tickets 30 days before the show.

`kernel.sweep_expired_ticket_atoms` (`079:487-492`) fires on `now() > s.ends_at + v_grace`.
`expired` is terminal (§7.6) with no transition back.

**Executed** (`atk_expiry.sql`): three `active` atoms on a session 30 days out.

```
A_SET_GRACE   set_platform_config('ticket.expiry_grace','24') → {"status":"ok"}   ← ONE admin
A_SWEEP       {"swept_count": 0}    A_STATES  active 3
B_MOVE        update_event_session(ses, starts_at −400d, ends_at −400d+4h) → ok
B_SWEEP       {"swept_count": 3}    B_STATES  expired 3
```

Buyers irreversibly lose tickets for an event that has not happened, by a seller-side action
with no platform in the loop.

**Correction to G1.** G1's "`ends_at` moved earlier expires live atoms with **no guard**" is
**too strong as stated**: the `ends_at`-only form is genuinely refused —
`update_event_session(ses,{ends_at: now−1h})` raised
`precondition_failed: ends_at must be after starts_at` (`event_session_time_check`). The hazard
is real only in the **paired backward move**, which is P0-1's primitive. G1 named the wrong
mechanism for the right risk.

### P0-3 — G1's BP-12 premise is overturned. BP-12's clock is the payment clock.

G1's headline claims 2 and 3, and its §6 verdict (line 514), rest on:
*"BP-12 arm 2 independently blocks **every** buyer with a paid order, fails CLOSED."* **[V]**

That is true only while `deletion.refund_possible_window_hours` is **unset**. G1 §7 item 2
instructs the owner to **set it**. Once set, `kernel.deletion_blockers_money` (`085:277-281`)
measures the window from `venue."order".created_at` — the **payment date** — which is precisely
the anchor G2 spends its own report proving is the wrong clock for event ticketing.

**Executed** (`atk_g1.sql`): a clean identity buys 60 days before a session that ends **in 10
days**.

```
STEP1  key unset            → "BP-12: refund-possible window unset … candidate orders present"
STEP2  key set to 720 (30d) → <CLEAR>
STEP3  money/orders/custody/market/wallet  →  all <CLEAR>
STEP4  request_account_deletion            →  DELETION_PENDING
STEP5  sweep_deletion_pending(10)          →  {"swept":1,"blocked":0,"tombstoned":1}
```

A buyer is **irreversibly tombstoned before their event**, while their refund and chargeback
rights are entirely live — and while G2's payout gate is simultaneously holding the venue's
money on `refund_in_flight` / `dispute_open` predicates that will no longer be able to identify
the counterparty. The two halves of this train contradict each other on the same question.

This is the error the previous report was pointing at. G1 declared it "WRONG"; the previous
report was **right about the substance** and only wrong about which key carried the defect.

**Fix.** Anchor BP-12 arm 2 on `max(event_session.ends_at)` over the identity's orders — the
identical derivation G2 built for `close_settlement` — not on `order.created_at`. The key is
also single-admin (see P1-4), so one platform_admin can make advance-purchase buyers erasable.

---

## P1 findings

### P1-4 — Money-key dual control is incomplete, and 093 mints a **new** money key outside it.

Executed as one `platform_admin` with an `aal2` claim (`atk_dark.sql`):

| key | result |
|---|---|
| `payout.settlement_maturity_interval` | **parked** — G2's rename claim **HOLDS** ✔ |
| `refund.buyer_self_service_max_minor`, `refund.buyer_fee_refundable` | parked ✔ |
| **`fee.buyer_service_bps`** | **`{"status":"ok","version":2}`** — one admin, no second human |
| `ticket.expiry_grace` | `status: ok` |
| `deletion.refund_possible_window_hours` | `status: ok` |
| `feature.native_issuance_enabled` | `status: ok` |

`v_dual` at `078:1145-1147` covers `refund. payout. authn. comp. wallet. credential.
door.session_`. It does **not** cover `fee.%`. `fee.buyer_service_bps` — the value that decides
what **every buyer is charged** — is minted by this train at `093:3530` (slice 40) into a
namespace with no dual control. That is the *identical* defect G2 correctly diagnosed for
`settlement.refund_window_interval` and fixed by renaming; the train fixed one instance and
created another in the same migration.

`deletion.refund_possible_window_hours` and `ticket.expiry_grace` being single-admin is what
makes P0-2 and P0-3 one-statement acts.

### P1-5 — The 24-seconds trap has no second human on the keys where it bites.

G1's cast finding is **correct and verified**: `('24'::jsonb #>> '{}')::interval = 00:00:24`.
But G1 stops at the cast. Executed (`atk_dark2.sql`):

```
set_platform_config('ticket.expiry_grace','24','meant 24h')  →  {"status":"ok"}
what the sweep reads                                          →  00:00:24
```

One admin, one statement, a natural "24 hours" typo, no polarity check, no range guard, no
parked approval — and every ticket whose session ended 24 seconds ago goes terminal. The same
typo on `payout.settlement_maturity_interval` **parks** (verified). The asymmetry is the finding.

### P1-6 — Assembler gate: `--manifest` is trusted and never cross-checked against the artifact.

Executed in scratch copies (`scratchpad/g4/`); baseline passes, so each is a real state change.

* **A reviewed slice can be silently dropped.** Make `--manifest` still print four parts while
  the assembly loop uses `"${parts[@]:0:3}"`; re-assemble; the gate prints *"reproduces
  byte-for-byte from 4 slice(s)"* and **exits 0** — with `40_config_privacy_freeze.sql` (58,923
  bytes: config keys, operatorship freeze, order-column scoping) **absent from the migration**.
  Falsifies `assembled_migration_integrity.sh:44` and G4 scenario A4: the set-equality at
  `:245-251` compares manifest↔disk and never manifest↔artifact.
* **Arbitrary SQL from outside the review surface.** `build()` at `:261` does
  `cp -R scripts/. "$sb/scripts/"`, so an assembler that `cat`s `scripts/.helper_tail.sql`
  (containing e.g. `grant all on all tables in schema public to anon;`) reproduces
  byte-for-byte. **Exit 0.**
* **A slice may be a symlink.** `[ -f ]:223`, `[ -s ]:227`, `tail -c 1:234` all dereference and
  `cp -R` preserves the link. Exit 0.
* **A decoy `parts_dir`.** Manifest reports a decoy directory while the artifact is built from
  the real slices. Gate prints `parts: 2` and exits 0.
* **The self-test cannot catch this class** — `assembled_migration_integrity_selftest.sh:67`
  rebuilds each sandbox's baseline **with that sandbox's already-subverted assembler**, so it
  reports **14/14 green** on the first three bypasses above. `:159` asserts only
  `grep -qF "banner"`, a string that appears in a *passing* log — vacuous.

Minimal fix: after rebuild, assert the artifact minus the generated header equals the ordered
concatenation of the **declared** slice bytes; copy only the assembler into the sandbox; reject
`[ -h "$f" ]`; build the self-test baseline with the pristine assembler.

### P1-7 — `$50` still renders as `$0.50`. The pricing display boundary is unguarded.

`formatMinor(totalMinor: Cents | number, …)` (`src/lib/pricing/allIn.ts:450`) accepts a bare
`number` **by design** — the repo's own suite calls `formatMinor(6000)`
(`tests/product-v2-foundation.test.ts:551-569`). Executed: `formatMinor(50)` (a
`public.listings.buy_now_price`, whole dollars) → **`"$0.50"`**, and `tsc --noEmit` accepts it.
Claim (c) is false through the module's only display function.

Worse, the escape hatch the doc **mandates** defeats the brand: `asCents(minor: number): Cents`
(`allIn.ts:99`) is an unchecked cast, and §5 rule 6 tells callers to use it. All tsc-clean:
`allInPrice({rail:'marketplace', baseMinor: asCents(50)})` → `"$0.55"`;
`priceLadder({lastSaleMinor: asCents(120)})` → `"Last sale $1.20"`. The three
`@ts-expect-error` assertions prove the compiler rejects the mistake nobody makes, not the one
§2 describes.

Claim (a) holds on **input** only: `faceValueMinor` and `totalMinor` are both `Cents`, so
`formatMinor(r.faceValueMinor)` renders `"$60"` for a `"$66"` charge and compiles clean. In
reverse, passing the edge's `total` as `faceValueMinor` double-counts the fee
(`{faceValueMinor: 6600, feeMinor: 600}` → `totalMinor 7200` for a $66 charge); the
`chargeTotalMinor` cross-check is optional, so it never fires.

### P1-8 — Signing-key scoping is not enforced at the mint. Threat T1 is reachable with a leaked `service_role` key, not only by a superuser.

`kernel.issue_ticket_atoms` (`083:514-530`) takes `signing_key_id` **from the caller's `p_ctx`**
and validates only `status`, the validity window and internal coherence — and
`scope = 'global'` is coherent with *every* session. The function is `EXECUTE`-granted to
`service_role` (verified: `auth=false svc=true`).

**Executed** as `service_role` on a private rehearsal DB, with a `per_event` key active and the
resolver (`085:1948-1960`) returning it:

```
issue_ticket_atoms(… 'signing_key_id': <global key b0> …)     → ALLOWED
issue_ticket_atoms(… 'signing_key_id': <per_venue key d0> …)  → ALLOWED
```

A per-event key therefore cannot *contain* issuance for its event — the whole point of scoping.
G3 treats T1 only in the **outranking** direction and calls it superuser-only; the
**downranking** direction is reachable with a leaked machine credential. Fix: have the mint
recompute the resolver and reject any key that is not the winner.

### P1-9 — The KMS handle reaches the PostgreSQL server log verbatim.

`log_min_error_statement = error` and the parked provisioning RPC always raises, so the
statement text is logged:

```
STATEMENT:  SELECT kernel.provision_signing_key('global',null,'…',
            'arn:aws:kms:us-east-1:123456789012:key/SECRET-HANDLE-abc',…)
```

The RPC is `EXECUTE`-granted to `authenticated`, and on Supabase that log is not
`postgres`-fenced — Logs Explorer widens the audience for a value the schema classes
`restricted`. Not a private key, so not P0, but it is a `restricted` secret leaving its
boundary. Pass the handle out of band, or raise before it can be interpolated into a logged
statement.

---

## P2 — record

1. **Direct-push bypass of the assembler gate.** `.github/workflows/migrations-guard.yml:63-66`
   triggers on `pull_request` + `merge_group` only — **no `push:`**. A direct push to `main` is
   ungated. Material given AUTODEPLOY-1's history.
2. **CRLF, UTF-8 BOM and NUL bytes in a slice all pass the gate** and propagate into the applied
   SQL; slice encoding is never validated.
3. **Mixed-provenance settlement.** The gate's covered set filters to five causes, but
   `settlement_line_cause_check` admits thirteen. A settlement holding one matured `primary_sale`
   plus a large `door_sale` / `admin_action` / `import` credit releases the **full** net,
   including the unanchored money. Only `postgres` holds `INSERT` on `venue.settlement_line`
   (verified: `authenticated` has `SELECT` only, `service_role` nothing), so this is
   defence-in-depth, not a live path. Consider restricting the released amount to the anchored
   causes.
4. **Interval overflow wedges a settlement** *(analysis)*. `v_anchor + v_maturity` is unguarded;
   an absurd interval raises `22008` out of `close_settlement`, rolling back the close and
   leaving the header `open` with zero lines — the same permanently-wedged shape the int4
   `settlement_amount_overflow` guard was added to prevent.
5. **`formatMinor` divides by 100 for every currency** — `formatMinor(asCents(5000),'JPY')` →
   `"50 JPY"`, a 100× under-display; currency is caller-supplied on the marketplace rail.
6. **`centsFromDollars` is `Math.round(dollars*100)`**, float: `1.005 → 100` (not 101),
   `8.165 → 816`, `4.475 → 447`. Doc-scoped to whole-dollar columns; unenforced by the signature.
7. **`face = 0` → `kind:'all-in', totalMinor: 0` → `"$0"`**, violating G5 §5 rule 3; the edge
   refuses `totalMinor <= 0`, so client and server disagree.
8. **Marketplace branch has no safe-integer check on its output total** (the direct branch has
   one at `allIn.ts:370`). Asymmetric; unreachable.
9. **`recoverReplayQuote`** (`supabase/functions/primary-checkout/index.ts:1361-1437`) returns
   `amount/buyer_fee/total` from the `payments` row **without** the
   `total === amount + buyer_fee` assertion the fresh path makes (`:1027-1031`), and fetches the
   PaymentIntent while discarding `pi.amount`. Client fails closed; hardening only.
10. **Anti-vacuity floors are env-overridable** — `G4_MIN_ASSEMBLERS=0 G4_MIN_GENERATED=0` makes
    a tree with no assembler, no slices and no banner exit 0. Not reachable from the committed
    workflow.
11. **Signing-key immutability guard has two column gaps G3 does not list: `key_id` and
    `created_at`.** The guard is `BEFORE UPDATE` only. Before a key is referenced, an honest
    unreferenced row can be deleted and a second row's `key_id` re-pointed at the freed id, so
    the id now carries attacker key material — guard silent. `update … set created_at =
    '1999-01-01'` is likewise ALLOWED, which falsifies ceremony forensics.
13. **Where the recommended 72 h is harmful.** The grace is a *blast radius*, not just a delay.
    (a) Combined with P0-1 it is immediate, not delayed — a backdated session terminal-izes every
    live atom on the next 2-minute sweep (executed: `swept_count: 3`). (b) A per-session
    `ends_at` that is simply wrong — a festival day entered with a 4-hour window instead of
    overnight — silently expires that day's atoms 72 h later, and `expired` is inadmissible at
    the door (`086:1125`) with no transition back. (c) The key is single-admin (P1-4) with the
    seconds trap (P1-5), so the interval an operator *intends* and the interval the sweep *runs*
    can differ by four orders of magnitude with nobody in the loop. The number is not the
    problem; the absence of a second human and of a reversal path is.
12. **No uniqueness on signing-key material.** Two rows may carry identical `public_key` *and*
    identical `kms_handle_ref`; the "handle already registered" defence is artifact-only. A
    `global`, a `per_venue` and a `per_event` key may all be active for one event at once.

---

## Drift observed (reported, not fixed)

`supabase/tests/142`, `151`, `153`, `155`, `156`, `157` are **modified in the working tree** and
now pass clean against the replayed chain — executed: `142 ok=253 not_ok=0`,
`151 ok=264 not_ok=0`, `153 ok=367 not_ok=0`, zero psql errors. G2 Part 4 states
"`supabase/tests/` **NOT edited** — reported, per scope" and predicts `142 D5a/D40`,
`151 C28a/C28b` plus **341 psql errors**, and `153 H2/H6/H11/H12`. Those deltas no longer exist;
another agent repaired the fixtures concurrently. **G2's test-delta table is stale** and should
not be relied on as a to-do list. The suite state is better than G2 claims, not worse.

**The repo is, right now, in the state the G4 gate exists to catch.** At the start of this review
`supabase/migrations/093_primary_ticketing.sql` reproduced byte-for-byte from the committed
slices. By the end, `docs/phase2/_impl/093_parts/30_connect_org.sql` and
`40_config_privacy_freeze.sql` had been edited (the A8/G2b signing-key deliverability gate) and
**the assembler had not been re-run** — a fresh `assemble_093.sh` now differs from the committed
artifact. `10_money_settlement.sql` and the artifact itself are unchanged since my snapshot, so
**every result in this report stands**; but a PR opened from this tree fails
`assembled_migration_integrity.sh`. Reported, not fixed — re-run the assembler before committing.

---

## What HELD

Proved by execution unless noted.

* **The eight predicates are a real conjunction.** Each was failed in isolation with all others
  satisfied; every one held, with its own code (`atk_matrix.sql`):
  `unbounded_refund_exposure` · `maturity_policy_invalid` · `covered_set_unresolvable` ·
  `event_cancelled` · `maturity_instant_unknown` · `maturity_not_elapsed` · `refund_in_flight` ·
  `dispute_open`; and the all-satisfied control **released**. No single satisfied predicate
  releases anything.
* **Fail-closed initialisation is genuine.** Every operand is declared pre-set to the holding
  value and every branch is `coalesce(…, hold)`. A settlement whose lines resolve to no session,
  to a nonexistent session, or only to non-seam causes lands on `maturity_instant_unknown`; a
  garbage `cause_ref` lands on `covered_set_unresolvable`. I could not make an uncomputable
  operand resolve to "satisfied".
* **The dual-control claim on the renamed key is real, not cosmetic.**
  `set_platform_config('payout.settlement_maturity_interval', …)` returned
  `{"status":"parked","version":1,"request_id":…}` with the version **unchanged**, and
  `kernel.approve_request`'s SoD-2 (`085:1147-1149`) refuses `v_uid = v_ar.requested_by`. A
  second, distinct `platform_admin` is genuinely required. Only `postgres` holds any grant on
  `catalog.platform_config`, so there is no direct-write bypass.
* **`kernel.release_payout` is genuinely the sole exit from a hold.** It is the only writer of
  `hold_state = 'none'` in the whole corpus (`085:830`; the other three writers —
  `085:796`, `087:489`, `088:846` — only *add* holds), and it refuses anything that is not
  `platform_risk` / `platform_admin` (`085:817`). A held payout is therefore recoverable only by
  a platform human.
* **Ruling A4 survives.** No `UPDATE`/`DELETE` on `kernel.payout`, no `release_payout`, no
  `pay_promoter_commission` anywhere in `close_settlement`'s body; the only `venue.attribution` /
  promoter references are read-only subqueries in the covered-set derivation.
* **Refund/chargeback shared headroom is internally consistent.** Both the 10b credit arm
  (`:447`) and the 10h headroom operand (`:1169`) read `kernel.refund` at `status = 'succeeded'`,
  so the face-value cap is computed on the same population it is enforced against.
* **`('24'::jsonb)::interval = 00:00:24`** — G1's correction of the previous report is right
  (the danger is the missing dual control, P1-5, not the cast analysis).
* **Exact-once webhook anchoring** — the three structural uniques the argument rests on all
  exist in the replayed database: `payment_native_payment_uq (payment_id)`,
  `payments_stripe_payment_intent_id_key`, `ownership_log_command_uq`.
* **Connect staging two-key property is real, at grant level and at runtime.**
  `kernel.stage_org_connect_ref` is `service_role` only (`authenticated=false`);
  `kernel.set_org_connect_ref` is `authenticated` only (`service_role=false`); the two grants are
  disjoint, so no single credential holds both keys. Executed: an `org_owner` with an `aal2`
  session calling `set_org_connect_ref(org,'acct_EVIL')` on an unstaged org raised
  `precondition_failed: no_pending_connect_ref`. Bind-without-staging is refused in the RPC, as
  E1 §6.3 claims.
* **No config change alone activates a money rail.** Every key in `catalog.platform_config` was
  set and no rail moved: with `feature.native_issuance_enabled=true` **and**
  `fee.buyer_service_bps=250` there is still no deployed checkout edge, no payout executor, and
  no client-reachable path that mints a paid order — `venue.finalize_primary_order`,
  `kernel.issue_ticket_atoms` and `kernel.refund_primary_order` are all `service_role`-only
  (`authenticated=false`), and every payout release is platform-only. The darkness claim
  survives. Two caveats: P1-4 (the *fee the buyer pays* is one admin's single statement away)
  and P1-8 (a leaked `service_role` key reaches the mint directly).
* **Signing keys: the four "prevented" claims all hold.** Re-proved by execution on a private
  rehearsal DB. (1) A 19-attempt × 6-persona matrix (`platform_admin`, `platform_support`,
  `platform_risk`, `authenticated`, `service_role`, `anon`) — INSERT / UPDATE of every column /
  DELETE / TRUNCATE / TRUNCATE CASCADE / `ALTER … DISABLE TRIGGER` / `GRANT` — was denied in
  every cell; only `postgres` holds table privileges, `authenticated` has column-SELECT on 8
  columns with `kms_handle_ref` **excluded**, and no function anywhere writes the table
  (`pg_proc.prosrc` scan). (2) The immutability guard fires on `public_key`, `kms_handle_ref`,
  `scope` and `not_before`, for `postgres` too, and `revoked` is terminal. (3) Deletion of a
  referenced key is blocked by `fk_tickets_signing_key`, as is `UPDATE key_id`, a bare TRUNCATE
  and a parent `catalog.event` DELETE. (4) Rotation preserves verification: after b0→`rotating`
  with b1 active, **0 atoms were re-pinned**, the retired key's `public_key` was still readable,
  and `openssl pkeyutl -verify` returned `Signature Verified Successfully` against it while
  failing against the new key and against a `credential_version` tamper. **No secret or PII
  exposure on any row, RPC return, audit row or error message** — 0 of 11 `kernel.admin_audit`
  rows matched handle/PEM patterns. 093 changes nothing here.
* **Expired atoms are refused at the door.** `admissible = (state = 'active' and resale_state =
  'none')` (`086:1125`), so a terminal-ized atom cannot be admitted — G1's "exactly one live
  thing" claim holds on the door side. A refund over an expired atom still completes (the atom
  is skipped as already-terminal, `085:581`/`085:686`), so a set grace does not destroy refund
  eligibility.
* **Assembler gate — the deletion arms hold.** Assembler deleted, migration deleted, slices
  deleted, banner stripped → exit 1 in every case. Hand-edits rejected byte-for-byte, including
  a trailing-newline-only change. A slice as a directory → exit 1. A second migration whose
  banner names a nonexistent assembler → exit 1 (orphan). No shell injection through a part
  name. No repo writes and no TOCTOU: every build under `mktemp -d` with an EXIT trap, and
  `shasum` of every tracked file identical before and after. CI wiring is real —
  `migrations-guard.yml:91-117`, first step, unconditional, `set -euo pipefail`, zero
  `continue-on-error`, zero `|| true`.
* **Pricing: no float math on the direct rail.** `feeMinorFromBps` matched a BigInt half-up
  reference on 126 face×bps pairs (faces 0…2147483647, bps 0…10000) with **0 mismatches**; the
  SQL twin (`30_connect_org.sql:733`) is `round(numeric * bps / 10000)`, exact and identically
  half-up. `formatMinor` splits with `%` and an exact `/100`. No `parseFloat` / `toFixed` /
  float rate anywhere on that rail.
* **Pricing fails closed on an unset fee.** 17 hostile fee inputs all refused:
  unset/null bps and absent `buyer_fee` → `service-fee-unset`; `NaN`/`"600"`/`-600`/`600.5`
  → `invalid-base` (never a zero fee); bad bps → `service-fee-out-of-range`;
  `{amount:10000,buyer_fee:1000,total:10000}` → `quote-incoherent`. No all-in price is
  obtainable without a configured fee.
* **Resale pricing is genuinely unchanged.** Differential old-HEAD vs working tree over 200,001
  bases plus 9 hostile inputs: marketplace totals and refusals **identical**; the single
  divergence (base `1e17`) is the new code refusing where the old emitted a number.
  `provenance.ts` diff is comment-only. Repo `tsc --noEmit` clean; `vitest run` 310/310.
* **Unit consistency at the DB seam.** `public.payments.amount` holds **minor units** on both
  rails (`create-payment-intent` writes `amountCents`; `primary-checkout:1201` writes
  `faceMinor`), matching `kernel.payment_native.amount_minor`. The refund cap reads
  `public.payments.total` — the charge, not face (`085:540,552`).
