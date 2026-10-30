# KARCHV — Credential-signing architecture: transfer, offline door, rotation, first-mint, G4/G5 non-regression

**Agent:** ARCH-VERIFY (read-only). **Repo:** `/Users/josetascon/snatchit-consol`, branch
`feature/venue-native-and-product-v2`, HEAD `d16ad7f` at inspection time. **DB:** local rehearsal only —
`snatchit_rehears_archv`, built via `scripts/rehearsal_reset.sh snatchit_rehears_archv`
(116 migrations, 000–101 + 5 timestamped, LC_ALL=C order, GATE-2 parity confirmed:
tables=27 functions=70 policies=37 triggers=26). No production access, no git mutation, migration 102
and the credential-sign edge were **not touched or read as work product** (only cited where the frozen
spec already describes their contract).

---

## 1. What was inspected (file:line)

- `docs/architecture/PHASE_2_EDGE_FUNCTION_SPEC.md` §3.2 (`credential-sign` contract, 399–437), §5 (C33 full
  spec, 1264–1596), §5.4.3 (`OFFLINE-VERIFY-v1`, the single normative predicate, 1362–1479), §5.5
  (version-bump invalidation, 1481–1518), §5.6 (rotation/revocation runbook, 1520–1583).
- `docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md` §5.3–5.4 (Door Safety Theorem + its corrected scope,
  374–463), §7.5/§7.5a (`get_door_manifest` + the projection superset rule, 655–763), §7.6/§7.7 (freeze
  recheck set + `append_door_manifest_delta`, 764–834), §9.1/§9.2/§9.3 (M1/M2, sanctioned mirror of
  `OFFLINE-VERIFY-v1`, the relationship table, 941–1089).
- `supabase/migrations/079_kernel_ticket_atom_and_ownership_log.sql` (custody-head trigger, 210–249).
- `supabase/migrations/083_kernel_credential_infrastructure.sql` (`kernel.signing_key` DDL + immutability
  guard, 47–125; `provision_signing_key`/`rotate_signing_key` parked fail-closed, 375–393;
  `kernel.issue_ticket_atoms` mint engine + activation boundary, 426–560+).
- `supabase/migrations/085_kernel_money_native.sql` (`kernel.void_ticket_atom`, 339–440).
- `supabase/migrations/088_market_native_rail.sql` (`kernel.transfer_ticket_ownership`, 609–748;
  `market.finalize_market_sale`, 1308–1345; `market.create_p2p_transfer` — fail-closed, 1390–1426;
  `market.accept_p2p_transfer`, 1437–1476).
- `docs/phase2/_impl/093_parts/30_connect_org.sql` (checkout-time signing-key deliverability gate,
  700–766; `kernel.issue_ticket_atoms` 093 body — the real resolver with scope precedence and the T1
  override refusal, 1590–1710).
- `supabase/migrations/099_signing_monitor_and_executor_invokers.sql`
  (`kernel.check_signing_key_invariants`, 80–207).
- `supabase/migrations/100_venue_obligation_excludes_held_commission.sql` (G4 fix, 89–330),
  `101_recovery_venue_scope.sql` (G5 fix — `kernel.organization_obligation_recovery_guard` trigger, 49–128).
- `docs/phase2/FINAL_ACTIVATION_BLOCKER_RULINGS.md` §G3 (384–453) — the existing ruling and its own
  named residual (a per_event key silently outranking global).
- `docs/architecture/PHASE_2_APPLE_WALLET_SPEC.md`:430,1313 (`door.manifest_ttl_interval` default 12h).
- Test fixtures/patterns read (not modified): `supabase/tests/000_helpers.sql`,
  `153_phase2_market_native_rail.sql`, `166_venue_obligation_excludes_held_commission.sql`,
  `167_recovery_venue_scope.sql`.

---

## 2. What was executed and results

All execution was against `snatchit_rehears_archv`, inside `BEGIN…ROLLBACK` (nothing persisted). Script:
`/private/tmp/.../scratchpad/archv_exec.sql` (session-local, not part of the repo).

### 2.1 Transfer/void bump the credential currency (§15/§37)

Minted one atom to `buyer` under a fresh `per_event` key K1 via `kernel.issue_ticket_atoms` (the same
engine `venue.finalize_primary_order` calls). Then transferred it via
`kernel.transfer_ticket_ownership(atom, other_user, 'admin_action', …)`, then voided it via
`kernel.void_ticket_atom`.

| Step | current_owner_id | state | credential_version | signing_key_id |
|---|---|---|---|---|
| after mint | buyer | active | **0** | K1 |
| after transfer | other_user | active | **1** | K1 (unchanged) |
| after void | `SN-VOID` sentinel `…f0` | voided | **2** | K1 (unchanged) |

Transfer result: `{"status":"ok","new_owner":"33333333-…","credential_version":1}`. Void result:
`{"status":"ok","credential_version":2}`. **Proven, not assumed:** `kernel.transfer_ticket_ownership`
(088:707) computes `v_cv := v_t.credential_version + 1` and writes it in the same `UPDATE` that moves
`current_owner_id` (088:713–715) — one atomic statement, no window. `kernel.void_ticket_atom` does the
same at 085:386/401–406, additionally reassigning `current_owner_id` to the `SN-VOID` sentinel. Both are
the **only** two writers of `kernel.tickets.credential_version` besides the mint's `0` (grep confirms:
079, 083, 085, 088 are the only files touching the column; no other custody path exists).

Post-transfer, I directly evaluated the exact predicate `credential-sign`'s own authorization uses
(edge §3.2: `kernel.tickets.current_owner_id = auth.uid()`, "re-read live inside the request — never a
client claim"): `(current_owner_id = buyer)` → **false**. The old owner cannot pass this check after a
transfer; `credential-sign` would 403 them. `get_ticket_signing_context` (migration 102, not yet in the
repo, authored by a concurrent agent) is **not itself testable** here, but every existing owner-gated
verb in this codebase (`credential-sign`, `create_p2p_transfer` 088:1403, `create_listing`, `lock_ticket`)
uses this identical live-re-read pattern with no exception — there is no precedent anywhere in the frozen
corpus for caching or trusting a client-supplied owner claim. A design that follows the established
pattern will correctly refuse a transferred-away owner; I did not find, and could not construct, a code
path that would let a stale `auth.uid()` pass once `current_owner_id` has moved.

### 2.2 Rotation (§19)

Minted atom T1 under K1 (active). Rotated **manually** (`kernel.rotate_signing_key` is a parked
unconditional raise, confirmed at 083:385–393 — "credential dual-control mechanism not yet ratified
(PFA-18A)"; my rotation exercised only the DB shape the ceremony would eventually perform, not the RPC):
`UPDATE kernel.signing_key SET status='rotating' WHERE key_id = K1`. Inserted K2 (`active`, same
`event_id`) — permitted only because K1 left `active` (partial unique index
`signing_key_active_event_uq`, 083:73–74). Minted atom T2.

| Atom | pinned to K1? | pinned to K2? |
|---|---|---|
| T1 (pre-rotation) | **true** | false |
| T2 (post-rotation) | false | **true** |

K1's row after rotation: `status='rotating'`, `public_key IS NOT NULL` (still readable) — confirming the
"validity overlap" the spec promises (edge §5.6: "old key active→rotating, new key active… in-flight
credentials pinned to the old key keep verifying until their `exp`"). **T1 was never re-pinned.**

Attempted to mint **explicitly** against the now-rotating K1 (caller states `signing_key_id: K1`): refused
— `precondition_failed: signing_key_override_refused — caller supplied <K1> but <K2> resolves for this
scope; the mint resolves its own key` (093 body, `docs/phase2/_impl/093_parts/30_connect_org.sql:1657–1659`).
This is the resolver refusing a stale/wrong request, not a `no_active_signing_key`, because K2 legitimately
resolves for the scope — the mint **cannot be steered** to a non-active key even by an explicit request.

### 2.3 Scope precedence: per_event shadows global, including a rogue insert

Inserted one `global active` key. Minted on a fresh event with **no** per_event key → resolved to the
global key (confirmed `resolved_global = true`). Then inserted a **second, "rogue" per_event key** for
that same event (simulating an operator mistake or a compromised service-role insert — this requires
direct DB write access; it is not client-reachable, since `kernel.signing_key` has `revoke all … from
anon, authenticated` and only a `select` grant, 083:110–115) and minted again:

- Result: `resolved_rogue_per_event = true`, `resolved_global = false`. **The rogue per_event key
  immediately and silently shadowed the global key for every subsequent mint on that event** — exactly
  the `ORDER BY case scope when 'per_event' then 1 … else 3` most-specific-first resolution at
  `093_parts/30_connect_org.sql:1648` (and its checkout-time twin at `:756`).
- A caller that explicitly requested the (correct, intended) global key while the rogue per_event key was
  active was refused: `signing_key_override_refused — caller supplied <global> but <rogue> resolves for
  this scope`. **The override refusal cuts both ways**: it stops an attacker from *choosing* a weaker key,
  but it also means there is **no way for an honest caller to escape a wrongly-inserted scoped key** short
  of a DB fix to the `signing_key` table itself.
- **This is not a new finding** — `FINAL_ACTIVATION_BLOCKER_RULINGS.md:440-442` (the ratified G3 ruling)
  already names this exact threat: *"a `per_event` key silently outranks the `global` bootstrap key in
  scope resolution… so a second key registered at event scope takes over immediately and without
  collision."* This execution is a direct, reproduced confirmation of that named residual, not a new one.

### 2.4 The 099 monitor does detect it

With `signing.monitor_enabled` armed (dark by default) and the fixtures above still in place (4 signing
keys total: bootstrap-shape global, rotating K1, active K2, rogue per_event), `SELECT
kernel.check_signing_key_invariants()` returned:

```json
{"status":"alert","alerts":["total_keys=4","scoped_keys=3","rotating_keys=1","fingerprint=unpinned"],
 "total_keys":4,"scoped_keys":3,"active_global":1,"rotating_keys":1,"deduped":false}
```

`scoped_keys` (099:135, labeled `ADV-7 shadow` in-line) fires on **any** non-global key existing at all —
so it does flag the rogue key, and it would flag the intended `per_event` MVP posture edge §5.2 describes
as "default" equally. This is a real tension in the frozen corpus, not a bug I am introducing: the edge
spec's stated MVP default is `per_event` (§5.2: *"Default `per_event`… the MVP default and the recommended
production posture"*), while the monitor's invariant (`v_scoped <> 0` alerts) encodes an MVP posture of
**exactly one global key and zero scoped keys**. Whichever posture is intended, the monitor as written
alerts on the other. The monitor also only runs once daily (`cron.schedule('monitor-signing-key-invariants',
'23 5 * * *', …)`, 099:207) and is dark by default (`signing.monitor_enabled` seeded `false`, 099:74) — so
even where it does fire, detection lag is bounded by up to ~24h unless armed and the cron actually ticks
(this rehearsal harness stubs `cron.schedule`/`net.http_post`; a real fire was not exercised).

### 2.5 G4/G5 non-regression — full replay + targeted assertions

`scripts/rehearsal_test.sh snatchit_rehears_archv` (all `supabase/tests/*.sql`, 000→167):

```
TOTAL plan=3549 ok=3545 not_ok=4 FAILURES
RESULT: pgTAP suite matches the expected local baseline.
```

The 4 `not_ok` are the two pre-existing, documented local-only deltas (`060_payments_money.sql` F-2/F-3
TODOs, `132_replay_parity.sql` D-5 pg_cron-row-shape deltas) that the harness's own baseline classifies as
expected-local, not regressions — the harness printed `RESULT: pgTAP suite matches the expected local
baseline` for exactly this reason. **166 and 167 (the G4/G5 packages) both pass 100%:**
`166_venue_obligation_excludes_held_commission.sql plan=39 ok=39 not_ok=0 PASS`,
`167_recovery_venue_scope.sql plan=24 ok=24 not_ok=0 PASS`.

The canonical case cited in the brief is assertion **A9** at
`supabase/tests/166_venue_obligation_excludes_held_commission.sql:226`: face `10000`, promoter commission
`bps=1000` (held, funded, never paid — `A2`/`A12`, lines 208/234, amount stays `1000` throughout), venue
settlement payout **paid** `9000` (`A4`, line 213), full dispute/reversal of the original `10000` (`A5`,
line 216) produces a chargeback line of **−9000, not −10000** (`A6`, line 223) and a resulting obligation
of **9000, not 10000** (`A9`, line 226) — exactly the brief's numbers, executed and green. Conservation is
independently asserted both ways: `A14` (line 246, funding side: face = paid venue payout + held commission)
and `A15` (line 255, reversal side: disputed amount = obligation + still-held commission). Migration 101's
cross-venue refusal is exercised at `167_recovery_venue_scope.sql:264-266` — a `transfer_reversal` recovery
against an obligation whose originating venue differs from the reversed payout's venue is refused with
`reversal_venue_mismatch … no cross-venue netting, ruling G5` (the guard trigger is
`kernel.organization_obligation_recovery_guard`, `101:49-128`, refusal text at `101:111`), and the targeted
obligation is left `outstanding`, untouched (`167:266`). **100/101 semantics are intact and unrelated to
102/signing** — nothing in 100 or 101 touches `kernel.signing_key`, `kernel.tickets.credential_version`,
or `kernel.tickets.signing_key_id` (grep-confirmed: neither file references any of the three).

---

## 3. Findings, ranked

### P0 — none newly discovered
No new P0 in this train's scope: the transfer/void/void-bump mechanism is provably correct (§2.1), the
key-pin-never-re-resolves guarantee holds under rotation (§2.2), and G4/G5 are provably unaffected by
this analysis (§2.5). The one genuinely severe risk in this area (§2.3, rogue/mis-scoped key shadowing)
is **already a ratified, named residual** in `FINAL_ACTIVATION_BLOCKER_RULINGS.md` G3 — I reproduced it,
I am not the first to find it, and it is explicitly called out for "the owner's attention" there
(line 439-442). I am **not** re-flagging it as a fresh P0; I am confirming it is real and giving the
orchestrator an executed reproduction to cite alongside the existing ruling.

### P1 — open tensions worth owner attention before/alongside 102

1. **`per_event`-default vs. monitor's `zero-scoped` invariant (edge §5.2 vs. 099:135).** The edge spec's
   stated MVP posture (`per_event` keys, one per event) and the 099 monitor's alerting invariant (any
   scoped key at all is an alert, `ADV-7`) describe two different intended worlds. If `per_event` really
   is the production MVP default, the monitor will alert continuously from the first real event onward,
   training operators to ignore it — which defeats the control that is supposed to catch exactly the
   rogue-key scenario in §2.3. If the monitor's invariant is correct (bootstrap on a single `global` key
   only, `per_event` deferred to Gate-M or later), the edge spec's "default per_event… recommended
   production posture" language is stale. This is a documentation/policy reconciliation, not a code bug —
   but it should be resolved before 102 ships a signing path that assumes one or the other.
2. **No escape hatch for a wrongly-scoped key short of a DB write.** §2.3 showed the resolver's
   most-specific-first rule plus the override-refusal (093:1657-1659) together mean an honest caller has
   no in-band way to insist on a different (correct) key once *any* active scoped key resolves for an
   event — the override refusal exists to stop an attacker choosing weaker security, but it equally
   blocks a legitimate operator recovering from a mistaken/rogue insert without a direct
   `UPDATE kernel.signing_key SET status='rotating'`. Given `provision_signing_key`/`rotate_signing_key`
   are parked (PFA-18A), there is currently **no RPC path at all** to fix this — only a superuser/
   service-role DB write, which is exactly the trust boundary that would already have to be compromised
   to insert the rogue key in the first place. Not a new defect (the whole ceremony is gated on this),
   but worth naming explicitly for 102's design: any new signing-key-adjacent RPC should consider whether
   it needs a "correct a bad scoped key" verb, or whether that stays intentionally break-glass-only.
3. **`door.manifest_ttl_interval` has no seeded default in the repo** (spec default is `12h`, documented
   at `PHASE_2_DOOR_LIFECYCLE_SPEC.md:1313` and `PHASE_2_APPLE_WALLET_SPEC.md:430`, but I found no
   `INSERT INTO catalog.platform_config` seeding it in any migration). The offline revocation bound
   (§4 below) is only as tight as this value; if it ships unset, the fallback/NULL behavior of
   `now() + config('door.manifest_ttl_interval')` (door §6 step 6) needs to be confirmed fail-safe
   (i.e., a NULL interval should not silently produce an unbounded or NULL `not_after`) before Gate-M.
   I did not execute this — flagging as unverified, worth a direct check by whoever owns 102/door
   activation.

### P2 — informational, not blocking

4. **`market.create_p2p_transfer` is unconditionally fail-closed** (088:1422-1424,
   `p2p_ttl_unavailable`, PFA-9/X-12 — "the p2p transfer TTL is unnamed in the frozen corpus"). Its sibling
   `market.accept_p2p_transfer` (088:1437) is fully wired and does route through
   `kernel.transfer_ticket_ownership` (confirmed 088:1471) — so the credential_version-bump guarantee
   would hold for p2p transfers exactly as for market sales — but the path is currently **unreachable**
   in practice because no `p2p_transfer` row can ever be created. Not a defect; noted so 102's design
   doesn't need to special-case p2p (it's dark, and correctly dark).
5. **`resolve_organization_obligation` exists in two migrations** (`094:431` original, `096:826`
   `create or replace` per the immutability discipline) — confirmed the 096 version is the live one and
   is unrelated to signing; noted only because grep initially surfaced both and it's worth knowing which
   is authoritative for anyone reading 094/096 alongside this report.

---

## 4. Options / smallest-honest framing (per the brief's item 4, first-mint)

**Question:** given the credential is stateless (re-derivable, not stored) and `signing_key_id` is pinned
at mint, is G3's ruling ("the irreversible point is the first `kernel.issue_ticket_atoms` call") still
correct, or should it be "first signed credential delivered"?

**Analysis, not a re-ruling of G3 (which stands until the owner amends it):**

- The three properties G3's own text cites as making mint irreversible (FK `on delete restrict` from
  `kernel.tickets.signing_key_id`, 083:191; the immutability trigger blocking correction of
  `public_key`/`kms_handle_ref` even for a superuser, 083:84-102; and the fact that rotation never
  re-pins, confirmed empirically in §2.2) **all attach to the database rows at INSERT/mint time**,
  independent of whether `credential-sign` is ever subsequently called. A minted atom that nobody ever
  requests a credential for is *already* stuck with whatever `signing_key_id` was pinned at mint — the
  FK and the immutability guard do not wait for a credential fetch to engage.
- Statelessness argues for mint being the correct line, not against it: because the signed token is a
  **pure re-derivation** of already-fixed DB state (`atom_id, session_id, credential_version, key_id` —
  edge §3.2:412) rather than a new independent commitment, "first credential delivered" is not a
  *different* commitment point — it is a *later, silent* one. Moving the line there would mean a
  wrongly-keyed atom (§2.3's rogue-key scenario, for example) could sit minted-but-uncredentialed for an
  arbitrary period with nobody having "committed" anything by the ruling's own definition, even though the
  FK and immutability guard have already locked in the mistake. That is a **detection gap**, not a safety
  margin — the harm is already irreversible at mint; delaying the labeled "point of no return" to
  credential delivery would just delay when anyone is required to notice.
- Mint is also provably no later than any credential delivery: `credential-sign` reads `kernel.tickets`
  (edge §3.2:413) and therefore requires the atom to already exist. There is no ordering under which a
  credential could be delivered before the mint that created the row it signs over.

**Recommendation to the orchestrator/owner:** G3's irreversible point should **stand unchanged** at the
first `kernel.issue_ticket_atoms` call. The stateless-signer detail does not weaken the ruling; if
anything it removes the one plausible argument for a later point (that the credential itself might be
the "real" commitment) by showing the credential is a projection of state that was already fixed at
mint. I am not recommending an amendment to G3.

---

## 5. Open questions for the orchestrator/owner

1. Reconcile the `per_event`-default (edge §5.2) vs. `zero-scoped`-invariant (099 monitor) tension (P1-1)
   before 102/signing-key-provision design assumes one posture.
2. Confirm `door.manifest_ttl_interval`'s unset-default behavior is fail-safe (P1-3) — I did not execute
   this; it's a direct, cheap DB check (`SELECT config('door.manifest_ttl_interval')` behavior when the
   key is absent from `catalog.platform_config`) that whoever owns door/102 activation should run.
3. Whether 102's `get_ticket_signing_context` needs an explicit regression test asserting the owner
   check is a **live** re-read (not a cached/JWT-claim value) — I could not execute this against 102
   itself since it doesn't exist in the repo yet, but §2.1's empirical proof that `current_owner_id`
   changes atomically with `credential_version` under transfer gives the exact fixture shape (mint →
   transfer → assert old-owner's `auth.uid()` fails) that such a test should use.

---

## 6. Confirmed-safe vs. unverified — summary

**Confirmed-safe (executed, this report):** transfer and void both bump `credential_version` atomically
with the custody/state change (§2.1); a transferred-away owner's `auth.uid()` fails the live owner check
`credential-sign` uses (§2.1); rotation never re-pins an already-minted atom, and the old key's public
material remains readable during the overlap window (§2.2); the resolver's most-specific-first scope
precedence is exactly as documented, including the override-refusal (§2.2, §2.3); the 099 monitor does
detect an unexpected scoped key, with the caveat about its default-posture ambiguity (§2.4); G4's
9000-not-10000 canonical case and G5's cross-venue refusal both pass green under full replay, and neither
migration touches signing/credential machinery (§2.5).

**Unverified (stated, not executed):** `door.manifest_ttl_interval`'s behavior when unset; anything about
migration 102 or the `credential-sign` edge's actual implementation (out of scope by the train boundary —
analyzed only via the frozen spec's contract text, never read as WIP); the 099 monitor's cron actually
firing and posting (this harness stubs `pg_cron`/`net.http_post`).
