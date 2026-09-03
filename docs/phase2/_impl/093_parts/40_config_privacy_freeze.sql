-- ============================================================================
-- 093 PART 40 — CONFIG · PRIVACY · OPERATORSHIP FREEZE
--
-- A FRAGMENT of migration 093, not a migration. It carries NO `begin;`/`commit;`
-- — the 093 assembler owns the transaction, so this file must remain safe to
-- concatenate in place. It creates NO table, NO enum member, NO column, and no
-- object outside the four items below.
--
-- RULINGS IMPLEMENTED (docs/phase2/PRIMARY_TICKETING_OWNER_RATIFICATION.md,
-- ratified by the owner 2026-09-02; the owner's A-numbering is canonical):
--
--   ITEM 1  ruling D2 (ticket expiry) + inventory readiness + ruling A5
--           (buyer-funded economics) + the settlement refund-window gate —
--           FIVE catalog.platform_config key rows. 093 scope items 3 and 10.
--           The fifth is routed here from the money slice so only one slice
--           writes it; its READER lives in 10_money_settlement.sql.
--   ITEM 2  ruling B (credential signing / dual control) — the signing bootstrap
--           trust row. 093 scope item 2. **BLOCKED — see the banner; this file
--           inserts NOTHING and invents no key material.**
--   ITEM 3  ruling C (venue operatorship transfer) — body-only CREATE OR REPLACE
--           of catalog.update_venue. 093 scope item 15.
--   ITEM 4  ruling F (attendee privacy) — column-scope venue."order" to omit
--           buyer identity. 093 scope item 4.
--
-- WHAT THIS FRAGMENT DOES NOT DO, deliberately:
--   * it activates nothing. Every rail stays dark; no flag is flipped.
--   * it un-parks NO signing-key RPC. kernel.provision_signing_key and
--     kernel.rotate_signing_key stay fail-closed (083:375-393) — both are
--     reachable by every signed-in user's role once granted, and ruling B
--     forbids the un-park explicitly.
--   * it revokes no EXECUTE grant. Ruling C's freeze is surgical to one patch
--     key precisely so benign venue profile edits keep working.
--
-- ACL NOTE (applies to ITEM 3): CREATE OR REPLACE FUNCTION preserves the
-- existing function ACL. catalog.update_venue keeps the grant 078 issued it;
-- this fragment must not re-grant it, and must not revoke it.
-- ============================================================================


-- ============================================================================
-- ITEM 1 — CONFIG KEY ROWS  (rulings D2 and A5; 093 scope items 3 and 10)
--
-- WHY A MIGRATION AND NOT set_platform_config: the setter resolves the key's
-- latest version under its own lock and then
--     if v_cur_ver is null then
--       raise exception 'precondition_failed: unknown_key %', p_key;
-- at 078:1102-1104, under the standing rule at 078:1093-1094 — "THIS FUNCTION
-- CREATES NO NEW KEY — a key that no code reads is a config row that lies".
-- A key that does not exist therefore cannot be created by configuration at
-- all. Only a migration can create one. There is no exception.
--
-- SHAPE: exactly 078:1520 — (key, version, value, visibility), version 1
-- (platform_config_version_check requires >= 1, 078:226), terminated with
-- `on conflict (key, version) do nothing` (the 078 seed idiom, 078:1580).
-- The table is append-only PER VERSION: tg_platform_config_append_only
-- (078:241-244) makes UPDATE and DELETE raise, even as superuser. A later
-- change is a NEW version row, never an edit of one of these.
--
-- VISIBILITY: all five are 'restricted'. None is a client-honoured span (the
-- 'public' set is the three feature flags, the two kill switches and the three
-- credential client spans, 078:1522-1530). These five are operational
-- thresholds, platform economics and a money-safety gate — PFA-8 posture.
--
-- DUAL CONTROL: FOUR of these five are not dual-controlled; the fifth now is.
-- The setter's prefix test is
--     v_dual := p_key like 'refund.%' or p_key like 'payout.%' or p_key like
--               'authn.%' or p_key like 'comp.%' or p_key like 'wallet.%' or
--               p_key like 'credential.%' or p_key like 'door.session\_%';
-- at 078:1145-1147. `ticket.%`, `inventory.%` and `fee.%` match none of them, so
-- each later set_platform_config call for those is a SINGLE platform_admin write
-- with no approval round — which is the property that makes seeding them absent
-- safe, because the owner can fill them in without a migration.
--
-- THE MONEY-SAFETY KEY IS THE EXCEPTION AND IT IS DELIBERATELY IN A DIFFERENT
-- NAMESPACE. It was 'settlement.refund_window_interval', which matched no
-- dual-control prefix — so the single most dangerous value in the train could be
-- set by one person with no countersignature. It is now
-- 'payout.settlement_maturity_interval' (G2), which matches 'payout.%' AND has no
-- polarity entry, so every set of it parks for a second platform_admin. See that
-- row's block.
--
-- TYPE WITNESS: 078:1111-1114 — "a key seeded absent-by-design (JSON null) has
-- no witness yet and accepts the first typed value, after which the witness
-- exists". So a null seed does NOT pin the type; a seeded value does.
-- ============================================================================

insert into catalog.platform_config (key, version, value, visibility) values

  -- ---- inventory: the two reservation keys (093 scope item 3) -------------
  --
  -- BOTH ARE SEEDED ABSENT (JSON null), which is the frozen
  -- retention.backup_window_days pattern (PFA-9, 078:1512-1517): the ROW exists
  -- so the setter's registry precondition holds; the VALUE is absent so every
  -- consumer takes the restrictive reading.
  --
  -- FAIL-CLOSED CLAIM — VERIFIED IN THE CONSUMER, NOT ASSUMED.
  --
  -- inventory.per_user_active_hold_max, read by venue.reserve_primary_inventory
  -- (081:527) at 081:615-621:
  --     select (c.value #>> '{}')::integer into v_cap_max
  --       from catalog.platform_config c
  --      where c.key = 'inventory.per_user_active_hold_max'
  --      order by c.version desc limit 1;
  --   exception when others then v_cap_max := null;
  --   end;
  --   v_cap_max := coalesce(v_cap_max, 0);          -- 081:621
  -- and then 081:624-626:
  --   if v_active + 1 > v_cap_max then
  --     raise exception 'precondition_failed: hold_cap_exceeded';
  -- With the value absent the cast raises, the handler sets null, the coalesce
  -- collapses the cap to ZERO, and `0 + 1 > 0` is true for the FIRST hold of
  -- every user. Every reservation is refused, loudly. FAIL-CLOSED — confirmed.
  -- 081:608-612 states the intent verbatim: "unseeded => fail-to-ZERO (AUTHZ-M8
  -- precedent), so a missing seed refuses every reserve loudly rather than
  -- admitting unbounded holds silently."
  ('inventory.per_user_active_hold_max',      1, 'null'::jsonb,       'restricted'),
  --
  -- inventory.hold_ttl_interval, read at 081:630-639 (inside
  -- venue.reserve_primary_inventory, 081:527) and again at 081:727-734 (inside
  -- venue.create_inventory_hold, 081:672):
  --     exception when others then v_ttl := null;
  --     end;
  --     if v_ttl is null then
  --       raise exception 'precondition_failed: hold_ttl_unset';     -- 081:638
  -- An absent value raises `hold_ttl_unset` outright — there is no default and
  -- no coalesce. Both call sites are identical. FAIL-CLOSED — confirmed.
  -- 081:628-629: "unseeded => REFUSE rather than invent a business policy (a
  -- TTL is policy, not a default)."
  --
  -- A null seed is therefore SAFE for both: while unset, nothing can be held,
  -- so nothing can be checked out and nothing can be minted. The owner sets
  -- both with set_platform_config before activation. NO VALUE IS INVENTED HERE.
  ('inventory.hold_ttl_interval',             1, 'null'::jsonb,       'restricted'),

  -- ---- ticket.expiry_grace — SEEDED NULL, AND IT IS THE DANGEROUS ONE ------
  --
  -- THIS KEY IS NOT LIKE THE OTHER THREE, AND THE DIFFERENCE RUNS THE OPPOSITE
  -- WAY TO WHAT YOU WOULD EXPECT. The other three are seeded absent because
  -- their consumers fail CLOSED — while unset, nothing can be held and nothing
  -- can be quoted, so an absent value is self-announcing. This consumer fails
  -- INERT: an absent value sweeps nothing, silently, forever. The row exists so
  -- the key is settable without a migration; the VALUE is absent because the
  -- number is an owner decision that is irreversible in the wrong direction.
  -- Both halves of that sentence are load-bearing; the full argument is below.
  --
  -- The consumer is kernel.sweep_expired_ticket_atoms (079:456), cron-scheduled
  -- every two minutes (079:799-803). At 079:475-479 it reads:
  --     v_grace := (select (c.value #>> '{}')::interval
  --                   from catalog.platform_config c
  --                  where c.key = 'ticket.expiry_grace'
  --                  order by c.version desc limit 1);
  -- and at 079:480-485:
  --   exception when others then
  --     v_grace := null;
  --   end;
  --   if v_grace is null then
  --     return jsonb_build_object('swept_count', 0);
  -- ABSENT, JSON-NULL and UNPARSEABLE all collapse to the same silent no-op.
  -- Nothing is swept, ever, and nothing says so.
  --
  -- WHY THAT IS FAIL-OPEN, NOT FAIL-INERT. 079:467-474 argues the inertness is
  -- safe FOR THE ATOM, and it is. It is fail-OPEN for the IDENTITY. The
  -- deletion blocker kernel.deletion_blockers_custody (079:707-717) is
  --     where exists (select 1 from kernel.tickets t
  --                    where t.current_owner_id = p_identity
  --                      and t.state in ('issued','active'))
  -- and BP-1's only three drains are scan, void and expiry. Scan is gated by
  -- feature.native_scanning_enabled, seeded false (078:1523); void is a
  -- platform break-glass (085:739-751), not a user path. So expiry is the ONLY
  -- drain a no-show buyer has. With this key unset, a buyer who simply does not
  -- attend becomes PERMANENTLY UNDELETABLE — an erasure-law failure that needs
  -- no money at all to trigger.
  --
  -- TYPE — THE SINGLE HIGHEST-RISK DETAIL IN THIS FILE. The value MUST be a
  -- jsonb STRING holding a Postgres interval literal, because 079:475 casts
  -- (c.value #>> '{}')::interval. A jsonb NUMBER (e.g. 24) fails that cast,
  -- lands in the `exception when others` arm at 079:480, and SILENTLY RE-ARMS
  -- the exact bug this row exists to close. Precedent for the string form is
  -- every door.* interval key at 078:1535-1541.
  --
  -- THE VALUE IS A JSON NULL, AND THAT IS DELIBERATE. An earlier draft of this
  -- row carried a derived '"24 hours"'. It was WITHDRAWN. The full reason, so
  -- the next reader does not re-derive it and put it back:
  --
  --   E-18 (POST_FREEZE_AMENDMENTS.md:1506-1515) is a RATIFIED erratum holding
  --   that this key is NOT seeded, and its ground is not caution for its own
  --   sake: the sweep's only effect is to write the TERMINAL label `expired`. A
  --   grace that is too short does not degrade, it irreversibly voids live
  --   tickets — and cancel_event then EXCLUDES expired atoms from its refund
  --   cascade (088:1682/1735/1783), so the buyer loses ticket AND refund.
  --   E-18's own words: "the inert direction is the only one the corpus
  --   declares harmless."
  --
  --   Ruling D2 says BOTH "do not leave the key absent/fail-open" AND "if a
  --   numeric owner value is genuinely unavoidable and not already ratified,
  --   STOP only that config value and report it." No grace duration exists
  --   anywhere in the corpus (POST_FREEZE_AMENDMENTS.md:648-649 — "in NO
  --   authoritative seed table, NO value anywhere"). The number is therefore
  --   unavoidable AND unratified, which is precisely the STOP case.
  --
  --   A ROW WITH A NULL VALUE honours both halves. The key is no longer ABSENT,
  --   so it is settable through the single sanctioned path with no migration —
  --   which is exactly PFA-9's CHOSEN option (c), "seed the ROW with a JSON null
  --   value and record the absence", already precedented by
  --   retention.backup_window_days. Deriving a number from
  --   door.session_absolute_max_interval (078:1540) remains the recommended
  --   STARTING POINT for the owner, and that derivation is preserved in the
  --   report — but it is the owner's call, not the implementer's, because it is
  --   irreversible in the wrong direction.
  --
  -- CONSEQUENCE, STATED PLAINLY RATHER THAN BURIED: until the owner sets a
  -- value, the sweep stays inert, tickets never expire, and any buyer holding an
  -- unscanned ticket stays permanently undeletable. That is a HARD ACTIVATION
  -- BLOCKER for issuance, not a nicety.
  --
  -- IT IS CHANGEABLE WITHOUT A MIGRATION. `ticket.%` matches no dual-control
  -- prefix (078:1145-1147), so
  --     select catalog.set_platform_config('ticket.expiry_grace',
  --              '"48 hours"'::jsonb, <reason>, <command key>);
  -- is one platform_admin write that inserts version 2. The owner's decision
  -- here is reversible and cheap; it is reported separately rather than
  -- presented as settled.
  --
  -- A SECOND FAIL-OPEN PATH CONFIG CANNOT REACH, surfaced not fixed: the sweep
  -- skips sessions with ends_at is null by design (079:492-493), and
  -- catalog.create_event_session requires only starts_at (078:806). A venue
  -- that omits ends_at reproduces the permanent-undeletable bug in full with
  -- this key correctly set. Carried as a separate schema decision — NOT closed
  -- by this row and NOT silently closed elsewhere in 093.
  ('ticket.expiry_grace',                     1, 'null'::jsonb,       'restricted'),  -- VALUE IS AN OWNER STOP (D2) — activation blocker until set

  -- ---- fee.buyer_service_bps — the platform's buyer-side service fee ------
  --
  -- Ruling A5, verbatim on the constraint this row must honour:
  --     "No service-fee percentage is hardcoded in migration 093."
  --     "No percentage is invented anywhere."
  --     "Fee economics remain owner/config controlled."
  -- The VALUE IS THEREFORE NULL, DELIBERATELY. This row creates the KEY and
  -- nothing else, so that the owner can set the rate later with a single
  -- set_platform_config call and no migration. That is the entire point of
  -- creating it now.
  --
  -- WHY THE KEY MUST EXIST BEFORE ANY SALE. Ruling A5 also fixes venue
  -- entitlement at "the configured ticket face value", and settlement lines are
  -- append-only while the settlement header is write-once. Revenue recognised
  -- before this key exists cannot be restated afterwards. This is the one place
  -- in 093 where "later" is unrecoverable.
  --
  -- HARD ACTIVATION CONSTRAINT, stated as ruling A5 requires: SELLING MUST NOT
  -- BE ACTIVATED WHILE THIS VALUE IS UNSET. Nothing in the database enforces
  -- that today — this fragment adds no reader — so it is a named launch
  -- precondition on feature.native_issuance_enabled, alongside the inventory
  -- keys above and payout.destination_cooldown_hours (078:1553, also null).
  --
  -- NAMING — house style, and why not one of the existing families. The corpus
  -- calls exactly this money `buyer_fee` (public.payments, 000:982-985; and the
  -- config namespace already carries refund.buyer_fee_refundable, 078:1550), so
  -- the noun is not invented. `fee.` is a new family in the same shape as every
  -- existing one (a bare lowercase domain noun: refund / payout / door / comp /
  -- resale / retention). It is deliberately NOT filed under `payout.` or
  -- `refund.`: those prefixes are dual-controlled (078:1145-1147) and this key
  -- has no declared polarity (078:1148-1196 falls through to `else null`), so
  -- filing it there would make it PARK on every write with no restrictive fast
  -- path — a rate the owner could never actually set.
  --
  -- UNITS — basis points, integer, following catalog.resale_policy.price_cap_bps
  -- and .royalty_bps (078:258-261, range 0..10000). A rate, not an amount,
  -- because the corpus already derives the buyer fee "from the base in integer
  -- cents, half-up" (docs/phase2/_decisions/A_venue_money.md:115). A single
  -- rate key is the MINIMAL shape; a rate-plus-fixed-component shape would be
  -- inventing fee economics, which A5 forbids.
  --
  -- THIS KEY HAS NO READER IN 093, AND THAT IS CORRECT — VERIFIED, NOT ASSUMED.
  -- The obvious candidate reader would be the settlement revenue seam (093 scope
  -- item 11, kernel.settlement_primary_lines), and it deliberately is NOT one:
  -- under A5 the venue's entitlement IS face value and "no platform fee is
  -- subtracted" from it, because Snatch It's revenue is buyer-funded and is
  -- collected at checkout, not deducted at settlement. The real reader is the
  -- buyer-side pricing path — venue.create_primary_checkout and the
  -- primary-checkout edge — which is outside this migration entirely.
  --
  -- So this row knowingly takes the ONE exception to 078:1093-1094 ("a key that
  -- no code reads is a config row that lies"): the key is created AHEAD of its
  -- reader. The justification is the irreversibility above — settlement lines
  -- are append-only and the header is write-once, so a rate that does not exist
  -- when the first sale settles can never be applied retroactively. Creating it
  -- early is recoverable; creating it late is not. The pricing path must adopt
  -- this exact spelling when it is built, and must fail closed (refuse to
  -- price) rather than default to zero while the value is null.
  ('fee.buyer_service_bps',                   1, 'null'::jsonb,       'restricted'),  -- A5: value is OWNER POLICY; never hardcoded here

  -- ---- payout.settlement_maturity_interval — THE PAYOUT HOLD AFTER THE -------
  -- ---- EVENT. RENAMED FROM settlement.refund_window_interval (G2). ----------
  --
  -- Routed here so slice 40 and the money slice do not both write the row. The
  -- READER is kernel.close_settlement in
  -- docs/phase2/_impl/093_parts/10_money_settlement.sql (the G2 maturity gate at
  -- the payout mint). Spelling verified against that reader.
  --
  -- THE OLD NAME WAS A LIE AND IS NOT PRESERVED. 'refund_window' names REFUND
  -- ELIGIBILITY — how long a buyer may still ask for money back. That is real
  -- policy and it is owned by an entirely different family of keys
  -- (refund.buyer_self_service_window_hours, refund.request_ttl_hours,
  -- refund.scanned_atom_policy — 078:1544-1551). This value is not that. It is:
  -- HOW LONG AFTER THE LAST COVERED SESSION ENDS THE VENUE'S MONEY MUST SIT
  -- STILL. Three separate concepts were collapsed into one name — refund
  -- ELIGIBILITY, payout MATURITY, and refund EXECUTION (kernel.mark_refund_state
  -- / the refund-execute edge) — and only the middle one is this row.
  --
  -- THE PREFIX IS LOAD-BEARING, NOT COSMETIC. This is the sentence the OLD
  -- version of this comment had to write, and the rename is what answers it:
  -- 'settlement.%' matched NONE of the dual-control prefixes at 078:1145-1147
  -- (refund. / payout. / authn. / comp. / wallet. / credential. / door.session_),
  -- so setting the most dangerous money key in the train was ONE platform_admin
  -- write with no second pair of eyes. 'payout.%' MATCHES. And because the key
  -- carries no entry in the polarity map (078:1152-1198), it has no declared
  -- restrictive direction, so EVERY set of it parks for a second platform_admin
  -- through kernel.approval_request / 'config.set_money_key' (078:1268-1285,
  -- consumed at 085:1224/1328). The rename converts a single-writer bypass into
  -- a two-person control at zero implementation cost.
  --
  -- WHAT IT GATES. A refund that succeeds AFTER its settlement has closed is
  -- never collected: the venue is paid face value, the buyer is refunded, and the
  -- debit exists NOWHERE in the ledger, permanently. Measured by the red team
  -- over five closes: lifetime net 8400 against 19000 actually paid out.
  -- **093 CREATED this exposure** by activating the credit side — pre-093 gross
  -- was structurally zero, so there was no payout to overpay.
  --
  -- HOW IT IS CLOSED: while this key is unset, close_settlement mints the
  -- settlement payout HELD — hold_state='held',
  -- hold_reason_code='unbounded_refund_exposure' (that code is retained verbatim
  -- for this arm). The ledger still records the full truth and the obligation
  -- still exists; only the MONEY is immobilised.
  --
  -- ####################################################################
  -- ##  SETTING THIS KEY IS NO LONGER SUFFICIENT TO RELEASE A PAYOUT.
  -- ##
  -- ##  That was the defect this rename ships with the fix for. The old gate
  -- ##  was `v_held := v_refund_window is null` — the ONLY predicate was
  -- ##  "is the key set", so setting it to ANY value released every payout
  -- ##  immediately with no maturity semantics implemented anywhere. The key
  -- ##  was a hidden feature flag for logic that did not exist.
  -- ##
  -- ##  The gate is now a CONJUNCTION (G2). This value is one conjunct; the
  -- ##  others are derived from the ledger and cannot be configured away:
  -- ##  the covered set must resolve, no covered event may be cancelled, the
  -- ##  last covered session's ends_at must be known and must have elapsed by
  -- ##  this interval, no refund on a covered payment may be in flight, and
  -- ##  no dispute on one may be open. Each failure has its own
  -- ##  hold_reason_code.
  -- ##
  -- ##  The DURATION remains owner policy and 093 invents none. The ANCHOR is
  -- ##  no longer policy: it is max(catalog.event_session.ends_at) over the
  -- ##  settlement's own lines. See docs/phase2/_impl/G2_settlement_maturity.md
  -- ##  for the recommended value and the evidence behind it.
  -- ####################################################################
  ('payout.settlement_maturity_interval',     1, 'null'::jsonb,       'restricted'),  -- G2: one conjunct of the maturity gate; dual-controlled by its 'payout.' prefix

  -- ---- deletion.post_event_hold_hours — HOW LONG AFTER THE EVENT AN --------
  -- ---- IDENTITY MAY NOT BE TOMBSTONED. RENAMED + RE-ANCHORED (H2). ---------
  --
  -- Routed here for the same reason the maturity key is: the READER is a kernel
  -- money verb — kernel.deletion_blockers_money, BP-12 arm 2, in
  -- docs/phase2/_impl/093_parts/10_money_settlement.sql section 10j — and slice
  -- 40 owns every platform_config row so the two slices never write the same
  -- table. Spelling verified against that reader.
  --
  -- IT REPLACES `deletion.refund_possible_window_hours` (085:2189, PFA-22).
  -- That key is NOT preserved as a fallback and is NOT read by anything after
  -- this migration. Two independent reasons, and the second is the decisive one:
  --
  --   (1) THE NAME WAS WRONG. "refund possible window" names refund
  --       ELIGIBILITY. 085:2186-2187 and PFA-22 both state in terms that this
  --       key is NOT that — "the key controls DELETION SAFETY only — never
  --       refund eligibility". Refund eligibility is owned by the `refund.%`
  --       family (078:1544-1551). This is the identical class of lie G2 removed
  --       from `settlement.refund_window_interval`.
  --
  --   (2) THE CLOCK CHANGED, SO THE CONTRACT CHANGED. The 085 arm measured its
  --       window from `venue."order".created_at` — the PAYMENT date — so ORDER
  --       AGE stood in for "the obligation is finished". Executed with the old
  --       key set to 720 (30 days), a buyer who paid 90 days before a session
  --       TEN DAYS AWAY was fully erasable and kernel.sweep_deletion_pending
  --       tombstoned them BEFORE the event, while kernel.close_settlement's G2
  --       gate was holding the venue's money for exactly that risk. The arm is
  --       re-anchored to `max(coalesce(session.ends_at, session.starts_at))`
  --       over the identity's own candidate orders — reached by the join
  --       `venue."order".event_session_id` (`not null … on delete restrict`,
  --       082:77), which is TOTAL and STABLE. Re-pointing the OLD key at the new
  --       anchor would silently re-interpret any value already stored under it.
  --
  -- THE FAMILY STAYS `deletion.`, AND THAT IS A DECISION, NOT INERTIA. Filing it
  -- under `refund.%` or `payout.%` would buy dual control for free — and would
  -- re-collapse the exact concepts this change exists to separate. TICKET EXPIRY
  -- != REFUND ELIGIBILITY != DELETION SAFETY != PAYOUT MATURITY. This is
  -- deletion safety; it is named for what it is, and the dual control is bought
  -- honestly instead, by adding `deletion.%` to the prefix list in this file's
  -- own set_platform_config body (see the `v_dual` block below). G7 P1-4 named
  -- this key as one of the two whose single-admin reachability made its attack a
  -- one-statement act; that half is closed here.
  --
  -- UNITS AND TYPE — a JSON NUMBER of hours, and the reader now ENFORCES it.
  -- Precedent: authn.money_role_maturity_hours, refund.buyer_self_service_window_hours,
  -- payout.destination_cooldown_hours (078). Hours-as-a-number is deliberately
  -- NOT an interval string: an interval-typed key carries the "'24' parses as
  -- TWENTY-FOUR SECONDS" trap that G1 §7.3 documents, whereas
  -- make_interval(hours => …) cannot be misread. A guard for this key is added
  -- alongside the interval guard in set_platform_config below, so a string can
  -- no longer be stored at all.
  --
  -- WHY THE VALUE IS NULL. Same PFA-9 shape as every other owner-STOP key here:
  -- the ROW exists so the key is settable with no migration; the NUMBER is owner
  -- policy and 093 invents none. FAIL-CLOSED, VERIFIED IN THE CONSUMER: with the
  -- value absent and a paid/partially_refunded order present, 10j returns
  -- 'BP-12: post-event deletion hold unset …' and the identity is not
  -- tombstoned. With NO candidate order the arm is skipped entirely and an
  -- absent value blocks nobody — PFA-22's owner scoping ruling, unchanged.
  --
  -- WHICH DIRECTION IS DANGEROUS, because it decides the polarity below. SHORT
  -- is the irreversible direction: a tombstone cannot be undone, and there is no
  -- force-tombstone verb to compensate a hold that is too long. LONG costs
  -- erasure LATENCY, which is recoverable. So a LONGER hold is the RESTRICTIVE
  -- direction (`higher_is_restrictive`, below): raising it executes in one
  -- statement for an operator responding to an incident, and SHORTENING it —
  -- making buyers erasable sooner — parks for a second platform_admin.
  --
  -- THE STARTING POINT FOR THE OWNER, and it is a trade, not a derivation:
  -- Stripe documents that for event ticketing "the dispute window starts on the
  -- event date, not the payment date" and runs ~120 days from it
  -- (https://docs.stripe.com/disputes/how-disputes-work), which is the same
  -- evidence G2 relied on. A 120-day post-event erasure block is not defensible
  -- against erasure law; a 30-day one (720) covers post-event refund requests,
  -- early-fraud-warning arrivals, the refund executor's own latency and a
  -- realistic postponement announcement, and it is what the H2 matrix was
  -- executed against. It is offered on those stated grounds and it is the
  -- owner's call. What it does NOT cover, plainly: a chargeback filed 60 or 110
  -- days after the event against an identity already tombstoned — which is
  -- OR-13/16c's ruled path (the chargeback lands against the TOMBSTONE) with
  -- BP-10 / kernel.identity_obligation as the blocker, not this key.
  ('deletion.post_event_hold_hours',          1, 'null'::jsonb,       'restricted')   -- H2: BP-12 arm 2's operand; EVENT-anchored; dual-controlled by the `deletion.` prefix added below

on conflict (key, version) do nothing;


-- ============================================================================
-- ITEM 2 — SIGNING BOOTSTRAP TRUST ROW  (ruling B; 093 scope item 2)
--
--                    *** STOP — NOTHING IS INSERTED BELOW. ***
--
-- This item CANNOT be completed without real key material, so it is reported
-- rather than faked. No row is written by this fragment.
--
-- THE FORCING COLUMNS, exactly. kernel.signing_key (083:49-70):
--     public_key      text not null,     -- 083:55  verify key, distributable
--     kms_handle_ref  text not null,     -- 083:56  opaque KMS handle/ARN
-- Both are NOT NULL with NO default. An INSERT must supply both, and neither
-- value exists until the two-person KMS ceremony has actually generated the
-- keypair. `public_key` is the one that forces the stop: it is not a trust
-- FACT the database can assert on its own, it is the ceremony's OUTPUT.
--
-- WHY A PLACEHOLDER IS NOT AN OPTION — three independent one-way doors:
--   1. kernel.guard_signing_key_immutable (083:84-102) raises
--      'append_only: signing_key identity/target/public_key/kms_handle is
--      immutable after creation' on any UPDATE of public_key or kms_handle_ref.
--      A placeholder can NEVER be corrected in place.
--   2. kernel.tickets.signing_key_id is
--      `not null references kernel.signing_key(key_id) on delete restrict`
--      (083:191). Once one atom pins the row, the row can never be deleted.
--   3. The mint does not validate the key material — only the trust envelope.
--      kernel.issue_ticket_atoms (083:514-530) checks status='active',
--      not_before <= now(), (not_after is null or > now()) and scope coherence,
--      then mints. A row with a garbage public_key passes every one of those
--      checks. The mint would happily issue atoms pinned to a key no door can
--      ever verify, and neither the deletion restriction nor the immutability
--      guard would let anyone undo it.
-- Inventing a public key is therefore not a harmless stub. It is a permanent,
-- unrepairable corruption of the trust root, and it is exactly the outcome
-- ruling B exists to prevent ("A single application administrator must not be
-- able to silently replace the trusted signing identity").
--
-- WHAT IS ALREADY DETERMINED, so the ceremony has nothing left to decide:
--   * scope must be 'global'. signing_key_scope_target_ck (083:64-68) requires
--     event_id and venue_id both null for 'global', and both a per_event and a
--     per_venue row would have to reference a catalog row that does not exist
--     yet at 093 time. 'global' is the only scope a bootstrap row can take.
--     signing_key_active_global_uq (083:77-78) then permits exactly ONE active
--     global key, which is the intended trust posture.
--   * key_id must be deterministic — proposed '00000000-0000-0000-0000-0000000000b0',
--     following the 078 sentinel style (…f0 / …f1 at 078:1607-1611); 'b0' for
--     ruling B. Deterministic so the ops runbook, the pgTAP fixtures and the
--     credential-sign edge all name the same row without a lookup.
--   * status 'active', not_before <= now(), not_after null — the exact envelope
--     083:514-530 requires for the mint to resolve a key.
--
-- THE TEMPLATE THE CEREMONY OPERATOR FILLS IN. Left COMMENTED OUT on purpose:
-- it must not execute with placeholder values, and it must not execute at all
-- until the KMS ceremony has produced both strings.
--
--   insert into kernel.signing_key
--          (key_id, scope, event_id, venue_id,
--           public_key, kms_handle_ref, status, not_before, not_after)
--   values ('00000000-0000-0000-0000-0000000000b0', 'global', null, null,
--           '<<< CEREMONY OUTPUT: the PUBLIC verify key, PEM/base64 >>>',
--           '<<< CEREMONY OUTPUT: the opaque KMS handle/ARN >>>',
--           'active', now(), null)
--   on conflict (key_id) do nothing;
--
-- The private key is created and stays inside KMS under two-person control and
-- is NEVER written to any column of any table (083:36-39 — "NO private key
-- material on any row"; signed tokens are produced only by the credential-sign
-- edge function calling KMS). The row above is the DATABASE'S REPRESENTATION OF
-- THAT TRUST STATE ONLY — a pointer and a verify key, never a secret.
--
-- NOT DONE HERE, AND NOT TO BE DONE: kernel.provision_signing_key and
-- kernel.rotate_signing_key stay parked and fail-closed exactly as 083:375-393
-- left them. Un-parking either one would expose a credential-lifecycle verb to
-- every signed-in user, which ruling B and the 093 scope both forbid by name.
-- ============================================================================


-- ============================================================================
-- ITEM 3 — OPERATORSHIP TRANSFER FREEZE  (ruling C; 093 scope item 15)
--
-- Body-only CREATE OR REPLACE of catalog.update_venue (born 078:623-742). The
-- signature, the language, `security definer` and `set search_path = ''` are
-- reproduced EXACTLY; every arm other than the org_id arm at 078:688-704 is
-- byte-identical to 078, including the declare block, the two authority arms,
-- the unwritable-key loop, the four profile-edit arms, the noop_replay return
-- and the kernel.admin_audit row.
--
-- WHAT CHANGES, and only this: the org_id arm no longer performs the UPDATE at
-- 078:701. It refuses.
--
-- WHY NOT A REVOKED GRANT: revoking EXECUTE on catalog.update_venue would also
-- kill the benign profile edits (name / neighborhood / address / capacity_hint)
-- that the venue arm legitimately serves at 078:706-724 and that pgTAP G22
-- asserts. The refusal must be surgical to the one patch key.
--
-- WHY NOT A CONFIG FLAG: catalog.set_platform_config cannot create the key a
-- flag would need (078:1093-1095, 078:1102-1104), so a flag-based freeze would
-- itself require a migration and would buy nothing over a direct refusal while
-- adding a runtime-mutable surface. Do not build one.
--
-- PLACEMENT: the refusal sits AFTER the unwritable-key loop, exactly as
-- docs/phase2/_decisions/C_operatorship_transfer.md:428-440 prescribes, and
-- BEFORE the is_platform([platform_admin]) check that 078:689-692 held. That
-- ordering is the point: the error is stable for every caller and carries NO
-- AUTHORITY ORACLE — a non-admin learns the transfer is frozen, not whether
-- they would otherwise have been allowed to perform it.
--
-- v_new_org is now unreferenced. Its declaration is retained so the declare
-- block stays byte-identical to 078; an unused local is inert in plpgsql.
-- v_reason is likewise no longer assigned, so the audit row's
-- coalesce(nullif(trim(coalesce(v_reason,'')),''), 'profile_edit') resolves to
-- 'profile_edit' for every remaining (benign) edit — which is precisely what
-- 078 already did for a patch with no org_id key.
--
-- PFA-10 (078:620-622) still holds: the org arm is still evaluated in its own
-- statement first, so an org_owner/org_admin caller still never parses
-- kernel.has_venue_role (080).
-- ============================================================================

create or replace function catalog.update_venue(
  p_venue_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid;
  v_org_id    uuid;
  v_before    jsonb;
  v_key       text;
  v_new_org   uuid;
  v_reason    text;
  v_allowed   boolean := false;
  v_changed   boolean := false;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'invalid_input: patch must be a json object';
  end if;

  select v.org_id,
         jsonb_build_object('name', v.name, 'neighborhood', v.neighborhood,
                            'address', v.address, 'capacity_hint', v.capacity_hint,
                            'org_id', v.org_id)
    into v_org_id, v_before
    from catalog.venue v where v.venue_id = p_venue_id for update;
  if v_org_id is null then
    raise exception 'not_found: venue %', p_venue_id using errcode = 'P0002';
  end if;

  -- Arm 1 (078-resolvable): org_owner / org_admin over the operating org.
  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  end if;
  -- Arm 2 (DEFERRED to 080 — PFA-10 / SEAM-3): venue_manager on this venue.
  if not v_allowed then
    v_allowed := kernel.has_venue_role(p_venue_id, array['venue_manager']);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  for v_key in select jsonb_object_keys(p_patch) loop
    -- reason_code is a patch-CARRIED field, not a column: the operatorship arm
    -- below REQUIRES it, so omitting it here made that arm unreachable in both
    -- directions (no reason => reason_required; reason => unwritable_key).
    -- 093/ruling C keeps 'reason_code' admissible even though the operatorship
    -- arm now refuses: dropping it would change the error a frozen transfer
    -- attempt returns from operatorship_transfer_frozen to unwritable_key,
    -- which is a worse and less honest message.
    if v_key not in ('name','neighborhood','address','capacity_hint','org_id',
                     'reason_code') then
      raise exception 'invalid_input: unwritable_key %', v_key;
    end if;
  end loop;

  -- Operatorship (org_id) is a TENANCY MOVE, not a benign profile edit. In 078
  -- it was is_platform([platform_admin]) only, and audited (RLS §11.1a).
  -- 093 / RULING C: venue operatorship transfers are FROZEN for initial launch.
  -- The transfer is not merely an authority change — it is an atomic re-scoping
  -- of venue.staff_role, door credentials and open settlements that no verb in
  -- the frozen corpus performs, so permitting the bare org_id UPDATE at 078:701
  -- leaves the departing operator holding staff grants and live credentials
  -- over a venue they no longer operate. Refuse instead of half-transferring.
  if p_patch ? 'org_id' then
    raise exception 'precondition_failed: operatorship_transfer_frozen — venue operatorship transfer is suspended pending the 093+ atomic re-scoping verb (Decision C). Contact the platform owner.'
      using errcode = 'P0001';

    -- ------------------------------------------------------------------
    -- FORWARD GUARD (ruling C, third bullet: "any future transfer attempt is
    -- refused while the departing organization holds PENDING or SUBMITTED
    -- payout facts"). kernel.payout.status is the closed set
    -- ('pending','submitted','paid','failed','reversed') at 085:125-126, and
    -- the org payee is payee_org_id under payout_payee_xor_ck (085:139-142).
    --
    -- DELIBERATELY UNREACHABLE while the raise above stands, and deliberately
    -- present. Lifting the freeze is then the deletion of exactly one raise,
    -- and ruling C's payout condition cannot be lost in that edit — which is
    -- the failure mode a "remember to add it back" note would invite.
    --
    -- IT IS ORDERED SECOND, NOT FIRST, ON PURPOSE. kernel.payout is granted to
    -- nobody: `revoke all on kernel.payout from anon, authenticated` (085:160)
    -- with no compensating grant. Probing it inside a definer function BEFORE
    -- the freeze raise would hand every caller who clears the v_allowed check
    -- above — including a venue_manager, who is not an org money principal — a
    -- working oracle on the organization's payout state. The freeze error must
    -- stay the first and only thing an org_id patch can learn.
    --
    -- if exists (select 1 from kernel.payout p
    --             where p.payee_org_id = v_org_id
    --               and p.status in ('pending','submitted')) then
    --   raise exception 'precondition_failed: operatorship_transfer_blocked_pending_payout — the departing organization holds unsettled payout facts'
    --     using errcode = 'P0001';
    -- end if;
    -- ------------------------------------------------------------------
  end if;

  if p_patch ? 'name' then
    update catalog.venue set name = p_patch ->> 'name', updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;
  if p_patch ? 'neighborhood' then
    update catalog.venue set neighborhood = p_patch ->> 'neighborhood', updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;
  if p_patch ? 'address' then
    update catalog.venue set address = p_patch ->> 'address', updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;
  if p_patch ? 'capacity_hint' then
    update catalog.venue set capacity_hint = (p_patch ->> 'capacity_hint')::integer,
                             updated_at = now()
     where venue_id = p_venue_id; v_changed := true;
  end if;

  if not v_changed then
    return jsonb_build_object('status','noop_replay');
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'venue.update', 'venue', p_venue_id,
          coalesce(nullif(trim(coalesce(v_reason,'')),''), 'profile_edit'),
          v_before,
          (select jsonb_build_object('name', v.name, 'neighborhood', v.neighborhood,
                                     'address', v.address,
                                     'capacity_hint', v.capacity_hint,
                                     'org_id', v.org_id)
             from catalog.venue v where v.venue_id = p_venue_id));

  return jsonb_build_object('status','ok');
end;
$$;

-- Layer 1 of ruling C only. Layer 2 (the no-direct-SQL owner policy) and Layer
-- 3 (the CI invariant that catalog.event.org_id never diverges from its venue's
-- org_id) are OPERATIONAL and live in the runbook and CI, not here: no SQL can
-- bind a superuser, so the direct-UPDATE path is covered detectively.


-- ============================================================================
-- ITEM 4 — COLUMN-SCOPE venue."order" TO OMIT BUYER IDENTITY
--          (ruling F; 093 scope item 4)
--
-- THE DEFECT. 082:129 grants the ORDER table at TABLE grain:
--     grant select on venue."order" to authenticated;
-- while venue_order_sel_venue (082:151-159) admits venue_manager and
-- venue_finance to every order row of their venue's sessions, and
-- venue_order_sel_org (082:144-148) admits org_owner/org_admin/org_finance to
-- every order row of their org. buyer_id (082:76) is therefore readable by all
-- of them, and ONE join to a display-name surface produces a complete attendee
-- roster with money attached — no audit row, no rate limit, no consent gate.
-- Ruling F: "The verified table-grain buyer-identity/display-name join that
-- allows an unaudited attendee roster is fixed."
--
-- THE PATTERN. This borrows the mechanism 080 applied to kernel.tickets at
-- 080:421-434. 079:735 had granted that table at table grain too; 080 revoked
-- it and re-granted every column EXCEPT current_owner_id, under I-4 / §16.10a:
--     "A row-level clause cannot express a per-policy column set (one role, one
--      grant — the platform impossibility recorded as E-24), so the discipline
--      is carried by the GRANT."  — 080:422-425
-- venue."order".buyer_id is that table's current_owner_id.
--
-- *** BUT THE ANALOGY DOES NOT TRANSFER WHOLE, AND ASSUMING IT DID WAS A BUG.
-- *** An earlier draft of this item said "the reasoning transfers verbatim" and
-- *** shipped the grant change alone. It broke venue.order_item for EVERY
-- *** client, including a buyer reading their own order lines. Recorded here in
-- *** full because the failure is subtle and the next person to column-scope a
-- *** table will walk into it.
--
--   THE TRUE RULE. A USING clause escapes the column ACL only for the table the
--   policy is ATTACHED TO. A subquery inside that clause against a DIFFERENT
--   relation is an ordinary reference, and its columns are permission-checked
--   against the INVOKING role like any other query.
--
--   SO: venue_order_sel_owner (082:140-141, `using (buyer_id = auth.uid())`) is
--   attached to venue."order" itself and keeps working — that half of the
--   original reasoning was right, and is verified below. But
--   venue_order_item_sel_owner (082:210-213) is attached to venue.order_item
--   and reaches ACROSS:
--       exists (select 1 from venue."order" o
--                where o.order_id = venue.order_item.order_id
--                  and o.buyer_id = auth.uid())
--   That `o.buyer_id` is checked against `authenticated`, which no longer holds
--   it. Reproduced on an empty table, no fixture needed:
--       select set_config('role','authenticated',true);
--       select count(*) from venue.order_item;
--       ERROR:  permission denied for table order
--
--   BLAST RADIUS IS TOTAL, not conditional. `authenticated` is the only role
--   with SELECT on venue.order_item (082:205 revokes anon; service_role holds
--   no venue-schema grant), and PostgreSQL evaluates ALL of a table's permissive
--   policies and ORs the results — so the failing one aborts the statement
--   regardless of row count, buyer identity, org role or venue role.
--
--   WHY 080 NEVER MET THIS: a census of pg_depend for objects depending on
--   kernel.tickets.current_owner_id returns no policy outside kernel.tickets
--   itself. 080's analogy held because its withheld column happened to have no
--   cross-table reader. Ours does. The fix is ITEM 4b.
--
-- THE COLUMN SET, enumerated from the CREATE TABLE at 082:74-94. Thirteen
-- columns exist; TWELVE are granted and exactly ONE is withheld:
--     order_id                       082:75   pk / the order reference itself
--     buyer_id                       082:76   ** WITHHELD — the identity **
--     event_session_id               082:77   which session (operational)
--     org_id                         082:78   which org (the RLS grain itself)
--     status                         082:79   refund/paid state (ruling F allows)
--     source                         082:81   app/web/door/promoter_link
--     total_minor                    082:83   authorized amount (ruling F allows)
--     currency                       082:84   pairs with total_minor
--     command_idempotency_key        082:85   see the note below
--     attribution_candidate_code_id  082:89   promoter attribution (ruling F allows)
--     attribution_candidate_link_id  082:90   promoter attribution (ruling F allows)
--     created_at                     082:91   purchase time (ruling F allows)
--     updated_at                     082:92   last movement
-- That is ruling F's permitted default set — "ticket status, ticket type,
-- check-in state, masked order reference, purchase time, refund state,
-- authorized financial amount, and promoter attribution where applicable" —
-- minus the one thing it forbids: "no attendee name, no attendee email, no
-- attendee phone, no individual demographic field".
--
-- command_idempotency_key IS RETAINED, and the call is deliberate. It is a
-- client-minted command key, not an identity attribute, and it is the replay
-- handle venue.create_primary_checkout resolves at 082:357 and 082:451. It
-- participates in order_buyer_command_uq (buyer_id, command_idempotency_key)
-- at 082:93, but a unique constraint discloses nothing through one of its
-- columns. RESIDUAL, RECORDED: if a client ever mints the key by deriving it
-- from the user id, the identity would leak through this column in plaintext.
-- The mitigation is a client-side invariant (command keys are opaque random
-- values), not a further grant reduction, because withholding it would break
-- the checkout replay surface for the org back office.
--
-- WHY THIS BELONGS IN 093 AND NOT AN EDGE FUNCTION: venue."order" is read
-- DIRECTLY through PostgREST by any role holding the grant. An edge function
-- cannot stand in front of a door it is not in front of. A column-level GRANT
-- is DDL and is the only control that binds the direct read.
--
-- ORDERING NOTE: this is a pure ACL change on an existing table. It takes no
-- lock beyond the catalog and is safe in any position within 093.
-- ============================================================================

revoke select on venue."order" from authenticated;
grant select (order_id, event_session_id, org_id, status, source,
              total_minor, currency, command_idempotency_key,
              attribution_candidate_code_id, attribution_candidate_link_id,
              created_at, updated_at)
  on venue."order" to authenticated;

-- anon is untouched: 082:128 already revoked everything from anon and never
-- re-granted, so anon holds no privilege on this table in either shape.
-- Writes are unaffected: 082 granted no INSERT/UPDATE/DELETE on venue."order"
-- to authenticated at all (money writes are RPC/definer-only, 082:129), so
-- there is nothing to re-issue on the write side.


-- ============================================================================
-- ITEM 4b — RE-SEAT venue.order_item's OWNER POLICY ON A DEFINER PREDICATE
--           (ruling F; mandatory companion to ITEM 4 — see the *** block above)
--
-- ITEM 4 is not shippable without this. The withheld column has exactly one
-- cross-table reader, and it must stop reading the column directly.
--
-- WHY A SECURITY DEFINER PREDICATE, AND NOT A RE-GRANT. Re-granting
-- SELECT (buyer_id) to authenticated would make order_item work again and would
-- also undo ruling F completely: the whole point is that a manager/finance role
-- must not be able to join buyer identity to money, and that join is exactly
-- what the column grant restores. The definer predicate answers the ONE
-- question the policy actually needs — "is the caller the buyer of this order?"
-- — without handing out the column that answers a thousand others.
--
-- THIS IS THE HOUSE IDIOM, NOT A NEW SHAPE. It is the same construction as
-- kernel.has_venue_role (080:60-73), which reads venue.staff_role from the
-- kernel schema so a policy never has to hold a grant on the underlying table:
--   language sql · stable · security definer · set search_path = '' ·
--   body is a bare `select exists (...)` · ACL stripped then granted to
--   authenticated (the 080:440-468 PART 7 idiom).
-- It lives in `kernel` for the same reason has_venue_role does: authority
-- predicates live in kernel regardless of which schema they read.
--
-- WHY IT IS SAFE — it grants no ability that does not already exist:
--   * auth.uid() is NOT a parameter. The predicate can only ever answer about
--     the CALLER. There is no argument that steers it at another identity.
--   * It returns true only for an order the caller already owns and can already
--     read (venue_order_sel_owner, 082:140-141). For any other order_id it
--     returns false — the identical answer the pre-093 policy gave.
--   * It is not an enumeration surface: it takes an order_id and returns a
--     boolean about the caller's own ownership. It reveals nothing about who
--     any OTHER order belongs to.
--   * No org or venue role gains anything. venue_order_item_sel_org (082:216)
--     and venue_order_item_sel_venue (082:223) are DELIBERATELY NOT TOUCHED:
--     they subquery o.order_id / o.org_id / o.event_session_id only, all of
--     which remain in the ITEM 4 grant, so they still work unchanged.
--   * The definer bypasses RLS on venue."order" exactly as has_venue_role
--     bypasses it on venue.staff_role; neither table sets FORCE ROW LEVEL
--     SECURITY (relforcerowsecurity = false, verified), so this is the same
--     trust boundary the corpus already relies on.
--
-- CENSUS — RE-CONFIRMED FROM THE LIVE CATALOG, NOT INHERITED. Every other
-- consumer of venue."order".buyer_id outside the table was enumerated three
-- ways against a rehearsal database with 093 applied:
--   (a) pg_depend on the buyer_id attnum returns exactly two policies —
--       venue_order_sel_owner (on venue."order" itself; escapes the ACL, fine)
--       and venue_order_item_sel_owner (the one fixed here) — plus an index and
--       two constraints, none of which are privilege-checked.
--   (b) every policy on every table whose expression names venue."order": four
--       total; only venue_order_item_sel_owner touches buyer_id.
--   (c) VIEWS: zero views anywhere reference venue."order" (and a view would
--       run with owner rights by default in any case).
--   (d) FUNCTIONS: 21 functions name venue."order"; exactly one is SECURITY
--       INVOKER (venue.assert_promoter_engine_consistency), it does not mention
--       buyer_id, and authenticated cannot execute it. Every function that DOES
--       read buyer_id — kernel.deletion_blockers_orders (082:656),
--       kernel.deletion_blockers_money (085:229), venue.resolve_order_attribution
--       (090:1051), and the refund/checkout RPCs — is SECURITY DEFINER, so the
--       invoker's column ACL never applies to it.
-- Conclusion: venue_order_item_sel_owner was the only break, and this is the
-- complete fix.
-- ============================================================================

create or replace function kernel.is_order_buyer(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from venue."order" o
     where o.order_id = p_order_id
       and o.buyer_id = auth.uid()
  )
$$;

-- I-7: strip PUBLIC, then grant exactly (the 080:440-468 idiom). authenticated
-- needs EXECUTE because a policy expression's function call is permission-checked
-- against the INVOKING role — the same reason has_venue_role is granted.
revoke all on function kernel.is_order_buyer(uuid) from public, anon, authenticated;
grant execute on function kernel.is_order_buyer(uuid) to authenticated;

-- The policy replacement. Identical row semantics to 082:210-213 — a buyer sees
-- the order_items of orders they bought, and nothing else — with the buyer_id
-- comparison moved inside the definer so no column grant is required.
drop policy if exists venue_order_item_sel_owner on venue.order_item;
create policy venue_order_item_sel_owner on venue.order_item for select to authenticated
  using (kernel.is_order_buyer(venue.order_item.order_id));

-- venue_order_item_sel_org and venue_order_item_sel_venue are intentionally
-- left exactly as 082 wrote them. Replacing policies that are not broken would
-- widen this migration's blast radius for no benefit.


-- ============================================================================
-- ITEM 5 — COLUMN-SCOPE venue.inventory_hold TO OMIT HOLDER IDENTITY
--          (ruling F; P0 — the attendee roster moved here after ITEM 4)
--
-- THE DEFECT, executed by the red team as venue_manager and reproduced here
-- verbatim against a fresh rehearsal database with 093 applied:
--
--   select p.display_name, o.total_minor, o.status
--     from venue.inventory_hold h
--     join public.profiles p            on p.id = h.identity_id
--     join venue.inventory_batch b      on b.batch_id = h.batch_id
--     join venue.ticket_type tt         on tt.ticket_type_id = b.ticket_type_id
--     join venue."order" o              on o.event_session_id = b.event_session_id
--                                      and o.total_minor = h.quantity * tt.price_minor;
--   -->  ATTENDEE ALICE | 10000 | paid
--        ATTENDEE BOB   | 15000 | paid
--
-- ITEM 4 closed venue."order".buyer_id and the join simply MOVED one table over:
--   1. venue.inventory_hold.identity_id is granted at TABLE grain (081:1043).
--   2. venue_inventory_hold_sel_venue (081:1049-1065) admits the SAME role set
--      ITEM 4 was closing against — org_owner/org_admin/org_finance via
--      has_org_role_over_event, plus venue_manager AND venue_scanner via
--      has_event_role.
--   3. public.profiles' policy profiles_select_all is `USING (true)`
--      (070:59), so ANY exposed identity id is a display name for free.
--   4. The order re-attaches to the hold by arithmetic:
--      order.total_minor = hold.quantity x ticket_type.price_minor.
--
-- THE LESSON, recorded because it is the second instance: closing ONE column is
-- not closing a capability. `profiles_select_all USING (true)` means the NAME is
-- never the control — the identity id is the whole vulnerability, wherever it is
-- exposed. The unit of defence is "can a venue-plane role reach any identity id
-- belonging to an attendee", not "is buyer_id readable".
--
-- NOT FIXED BY NARROWING profiles_select_all: that is a live marketplace surface
-- and out of this train, per the owner. The fix is on the venue plane.
--
-- THE COLUMN SET, enumerated from 081:141-155. Ten columns exist; NINE are
-- granted and exactly ONE is withheld:
--     hold_id                  081:142   pk
--     batch_id                 081:143   which batch (operational)
--     shard_no                 081:144   shard routing (operational)
--     identity_id              081:145   ** WITHHELD — the holder identity **
--     quantity                 081:146   how many (operational, and the arithmetic
--                                        link is harmless once identity is gone)
--     status                   081:147   active/converted/released/expired
--     expires_at               081:149   TTL, drives the sweep display
--     command_idempotency_key  081:150   replay handle (see the ITEM 4 note; it is
--                                        a client-minted key, not an identity)
--     created_at               081:151
--     updated_at               081:152
--
-- THE CROSS-TABLE TRAP — CHECKED THIS TIME, AND IT DOES NOT RECUR. The failure
-- that broke venue.order_item (see ITEM 4b) is a policy on a DIFFERENT table
-- subquerying the withheld column. Swept four ways against the live catalog:
--   (a) pg_depend on the identity_id attnum returns ONE policy,
--       venue_inventory_hold_sel_owner, which is attached to venue.inventory_hold
--       ITSELF — so it escapes the column ACL and keeps working — plus one index
--       and two constraints, none privilege-checked.
--   (b) the only other policy naming inventory_hold anywhere is
--       venue_inventory_hold_sel_venue, on the same table, and it does NOT
--       reference identity_id (it keys on batch_id).
--   (c) zero views reference inventory_hold.
--   (d) zero SECURITY INVOKER functions name inventory_hold.
-- So no definer predicate is needed here. A pure column-scope is the whole fix,
-- and the holder's own read survives on the same-table policy — proven by test.
--
-- venue_scanner — MADE DELIBERATE, NOT ACCIDENTAL. The scanner is inside
-- venue_inventory_hold_sel_venue's has_event_role arm (081:1064) and so reads
-- every hold row of its event. After this change it reads them WITHOUT the
-- holder identity, which is exactly what door admission needs: a scanner
-- validates a credential presented at the door (venue.scan / the door manifest,
-- 086), it never needs to know who reserved inventory. The role is left in the
-- policy on purpose — removing it is a door-path change this migration must not
-- make — and the column grant is what bounds it.
-- ============================================================================

revoke select on venue.inventory_hold from authenticated;
grant select (hold_id, batch_id, shard_no, quantity, status, expires_at,
              command_idempotency_key, created_at, updated_at)
  on venue.inventory_hold to authenticated;

-- anon is untouched (081:981 revoked it and never re-granted). Writes are
-- unaffected: 081 granted no INSERT/UPDATE/DELETE here — holds are RPC-only.


-- ============================================================================
-- ITEM 6 — E-76 CURRENT-OPERATOR CONJUNCT ON THE TWO ORDER VENUE ARMS
--          (ruling C adjacency / A3; red team B)
--
-- THE LEAK. venue_order_sel_venue (082:151-159) and venue_order_item_sel_venue
-- (082:223-229) call kernel.has_venue_role bare. That predicate probes
-- venue.staff_role on (venue_id, auth.uid(), role) and NOTHING else (080:60-73):
-- it knows neither who currently operates the room nor whose order this is.
-- After an operatorship divergence (event org <> venue org) the red team
-- measured, on the same fixture:
--     settlement      rows visible = 0   (10f's E-76 fix holds)
--     settlement_line rows visible = 0   (10f's E-76 fix holds)
--     venue."order"   rows visible = 1   <-- LEAK
-- so a stale or foreign venue-role holder reads another organization's order:
-- total_minor, status, org_id — and, before ITEM 4, buyer_id, which is PII the
-- settlement tables do not even carry.
--
-- WHY IT MATTERS MORE NOW: 093's open_settlement grain split makes the divergent
-- state routine rather than exotic, and this arm partially defeats ITEM 5 —
-- closing the inventory_hold roster path is worth less while a foreign venue
-- role can still read order rows directly.
--
-- THE FIX — the SAME shape the money slice used at
-- docs/phase2/_impl/093_parts/10_money_settlement.sql section 10f, so the two
-- read alike: conjoin "the venue's CURRENT operator org equals the row's own
-- org_id", proven at 087:299-300.
--
-- EFFECTS. A venue operator keeps full venue-arm visibility of its own orders at
-- its own room: zero behaviour change on every state the shipped write paths can
-- create. A promoter's order at a foreign room becomes invisible to that room's
-- staff. A departing operator's stale staff lose the venue arm over legacy
-- orders after a transfer — the intended E-76 semantics. The true owner is
-- unaffected: it reads through venue_order_sel_org (082:144-148), which already
-- keys on org_id. The buyer is unaffected: venue_order_sel_owner (082:140-141)
-- is a separate permissive policy on buyer_id = auth.uid().
--
-- CENSUS OF THE SAME OMISSION ELSEWHERE — reported, not silently fixed. Of the
-- 24 policies calling has_venue_role/has_event_role, four already carry the
-- conjunct (promoter, promoter_code, settlement, settlement_line). Of the
-- remaining twenty, only FOUR sit on a row that carries its own org_id and can
-- therefore express E-76 directly: catalog.event, catalog.venue, kernel.tickets
-- and venue."order". catalog.venue's conjunct is vacuous (v.org_id = its own
-- org_id is a tautology). venue."order" and venue.order_item are fixed here
-- because they are this slice's tables. catalog.event and kernel.tickets carry
-- the identical omission and are NOT touched here: they are 078/079 surfaces
-- owned by other slices, and kernel.tickets is additionally the door read path.
-- **Both are handed to the coordinator as open items.** The sixteen policies on
-- rows with no org_id (door_manifest*, scan*, guest_*, comp_allocation,
-- inventory_*, ticket_type, staff_role, promoter_link, event_session) cannot
-- express the conjunct without resolving event->org, which is a wider change than
-- 093 carries; recorded, not taken. Promoting E-76 into kernel.has_venue_role
-- itself would close the whole class at once but that predicate has 15+ frozen
-- call sites — the same judgement 10f recorded and declined.
-- ============================================================================

drop policy if exists venue_order_sel_venue on venue."order";
create policy venue_order_sel_venue on venue."order" for select to authenticated
  using (
    exists (
      select 1 from catalog.event_session s
        join catalog.event e on e.event_id = s.event_id
       where s.session_id = venue."order".event_session_id
         and kernel.has_venue_role(e.venue_id, array['venue_manager','venue_finance'])
         and (select v.org_id from catalog.venue v where v.venue_id = e.venue_id)
             = venue."order".org_id   -- E-76: current operator
    )
  );

drop policy if exists venue_order_item_sel_venue on venue.order_item;
create policy venue_order_item_sel_venue on venue.order_item for select to authenticated
  using (exists (
    select 1 from venue."order" o
      join catalog.event_session s on s.session_id = o.event_session_id
      join catalog.event e on e.event_id = s.event_id
     where o.order_id = venue.order_item.order_id
       and kernel.has_venue_role(e.venue_id, array['venue_manager','venue_finance'])
       and (select v.org_id from catalog.venue v where v.venue_id = e.venue_id)
           = o.org_id));   -- E-76: current operator



-- ============================================================================
-- ITEM 7 — DUAL-CONTROL THE `fee.%` NAMESPACE
--          (ruling A5; body-only CREATE OR REPLACE of catalog.set_platform_config)
--
-- THE FINDING, executed against the live setter as a single platform_admin:
-- set_platform_config('fee.buyer_service_bps', '750'::jsonb, ...) executed
-- IMMEDIATELY — status 'ok', a new version row inserted, no parking, no second
-- approver. fee.buyer_service_bps is the last surviving instance of the pattern
-- the owner banned: one person, one statement, and the platform goes from
-- "cannot sell" to "selling", with three preconditions a gate audit proved are
-- unenforced behind it (no active signing key required at checkout — the buyer
-- can be charged for a ticket that can never mint, being closed separately in
-- slice 30; refund executability checked nowhere; no tax model at all).
--
-- THE FIX IS A ONE-LINE WIDENING of the prefix test at 078:1145-1147, delivered
-- as a body-only replacement because 078 is immutable. The function body below
-- is reproduced from 078:1048-1310 MECHANICALLY (extracted, not retyped) and is
-- byte-identical except for the v_dual assignment and its adjacent comment. The
-- signature, `security definer`, `set search_path = ''`, every precondition,
-- every RANGE check, the whole polarity map, the cross-config wallet invariant,
-- the parked path, the direct path and both audit rows are untouched.
--
-- POLARITY — CHECKED, NOT ASSUMED. fee.buyer_service_bps appears NOWHERE in the
-- declared polarity map (078:1148-1196); it falls through to `else null`. With
-- v_polarity null, v_restrictive can never be set true (every arm that assigns
-- it requires a non-null polarity), so `v_dual and not v_restrictive` is
-- unconditionally true and the key PARKS ON EVERY WRITE, in both directions.
-- That is the intended behaviour: there is no "restrictive direction" for a
-- platform fee rate, so no write of it should ever bypass the second approver.
-- Verified by execution, not by reading.
--
-- NO NEW VOCABULARY: the parked path reuses action 'config.set_money_key' and
-- subject_kind 'config_key', both already in kernel.approval_request's frozen
-- closed sets and already exercised by the other seven dual-controlled
-- namespaces. Nothing is widened but the prefix list.
--
-- BLAST RADIUS: `fee.` is a namespace this train created (ITEM 1). It contains
-- exactly one key. No pre-093 key anywhere in the 41-key seed block starts with
-- `fee.`, so no existing configuration path changes behaviour — verified
-- against the seeded key list.
-- ============================================================================

create or replace function catalog.set_platform_config(
  p_key text, p_value jsonb, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_cur_ver    integer;
  v_cur_val    jsonb;
  v_visibility text;
  v_dual       boolean;
  v_polarity   text;
  v_restrictive boolean;
  v_old_num    numeric;
  v_new_num    numeric;
  v_span       interval;
  v_skew       interval;
  v_ttl        interval;
  v_probe      interval;                 -- 093: interval type guard scratch
  v_request_id uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  -- reason_code is mandatory for EVERY key, not only the money namespaces.
  if p_reason_code is null or length(trim(p_reason_code)) = 0 then
    raise exception 'precondition_failed: reason_required';
  end if;
  -- platform_support and platform_risk hold NO authority here: risk holds
  -- hold_payout, not the thresholds that decide when a payout needs approval.
  if not kernel.is_platform(array['platform_admin']) then
    raise exception 'insufficient_privilege: platform_admin required'
      using errcode = '42501';
  end if;
  if p_value is null then
    raise exception 'precondition_failed: bad_value — use the JSON null literal';
  end if;

  -- APPR-SUBJ-1: resolve the subject under its own lock, in the same transaction
  -- that writes the row. THIS FUNCTION CREATES NO NEW KEY — a key that no code
  -- reads is a config row that lies (078 seeds every key).
  select c.version, c.value, c.visibility
    into v_cur_ver, v_cur_val, v_visibility
    from catalog.platform_config c
   where c.key = p_key
   order by c.version desc
   limit 1
     for update;
  if v_cur_ver is null then
    raise exception 'precondition_failed: unknown_key %', p_key;
  end if;

  if v_cur_val = p_value then
    return jsonb_build_object('status','noop_replay','key',p_key,
                              'version',v_cur_ver,'request_id',null);
  end if;

  -- RPC §20.2.1 precondition: "p_value passes the key's declared TYPE/RANGE".
  -- TYPE: a key never changes shape. The seeded row is the type witness; a key
  -- seeded absent-by-design (JSON null) has no witness yet and accepts the first
  -- typed value, after which the witness exists.
  if jsonb_typeof(v_cur_val) <> 'null'
     and jsonb_typeof(p_value) <> jsonb_typeof(v_cur_val) then
    raise exception 'precondition_failed: bad_value — % is %, not %',
      p_key, jsonb_typeof(v_cur_val), jsonb_typeof(p_value);
  end if;
  -- RANGE: enforced for every key whose admissible range the frozen corpus
  -- actually states. A key with no stated range is not invented one here.
  if p_key = 'authn.money_role_maturity_hours'
     and jsonb_typeof(p_value) = 'number'
     and ((p_value #>> '{}')::numeric < 24 or (p_value #>> '{}')::numeric > 72) then
    -- RLS MD-14 / RPC §1.1e: "the admissible range as 24-72 hours".
    raise exception 'precondition_failed: bad_value — authn.money_role_maturity_hours is outside MD-14''s admissible 24-72 hours';
  end if;
  if p_key = 'notify.announcement_hold_seconds'
     and jsonb_typeof(p_value) = 'number'
     and (p_value #>> '{}')::numeric < 120 then
    -- NOTIF §7.5: "seed 300 s, FLOOR 120 s".
    raise exception 'precondition_failed: bad_value — notify.announcement_hold_seconds is below NOTIF §7.5''s 120 s floor';
  end if;
  if p_key = 'authn.money_action_required_aal'
     and jsonb_typeof(p_value) = 'string'
     and (p_value #>> '{}') not in ('aal1','aal2') then
    raise exception 'precondition_failed: bad_value — authn.money_action_required_aal must be aal1|aal2';
  end if;
  if p_key = 'refund.scanned_atom_policy'
     and jsonb_typeof(p_value) = 'string'
     and (p_value #>> '{}') not in ('refuse','platform_review') then
    raise exception 'precondition_failed: bad_value — refund.scanned_atom_policy must be refuse|platform_review';
  end if;

  -- 093 — INTERVAL TYPE GUARD (the second of this item's two changes).
  -- THE HOLE IT CLOSES: the TYPE witness above is skipped when the current value
  -- is JSON null (078:1111-1114 — "a key seeded absent-by-design has no witness
  -- yet and accepts the first typed value"). Every owner-STOP key in 093 is
  -- seeded null, so each one accepts ANY json type on its first write. For an
  -- interval-consumed key that is silent and severe: set_platform_config(
  -- 'ticket.expiry_grace','24') is accepted, and '24'::interval is TWENTY-FOUR
  -- SECONDS, not 24 hours (verified: select '24'::interval => 00:00:24). The
  -- sweep at 079:475 then terminal-izes every atom on every ended session within
  -- one cron tick, and `expired` is terminal and excluded from cancel_event's
  -- refund cascade. The typo reads as correct to a human, which is what makes it
  -- the dangerous shape.
  -- THE GUARD: for keys the corpus consumes with ::interval, require a jsonb
  -- STRING that actually parses. A bare number can no longer be stored.
  -- MAINTENANCE NOTE: this is a list, in the same explicit per-key style as the
  -- four RANGE checks above, and it must gain any future interval-typed key. The
  -- root cause is the missing type witness on a null seed, not the list.
  if p_key in ('ticket.expiry_grace','inventory.hold_ttl_interval',
               'payout.settlement_maturity_interval','door.schedule_move_grace_interval',
               'notify.delivery_lease_interval',
               'credential.wallet_exp_skew','credential.wallet_default_span',
               'credential.app_ttl_interval','wallet.apple.cert_expiry_warn_interval',
               'door.implicit_freeze_offset_interval','door.manifest_ttl_interval',
               'door.manifest_early_open_window','door.max_override_interval',
               'door.session_ttl_interval','door.session_absolute_max_interval',
               'door.session_post_session_grace')
     and jsonb_typeof(p_value) <> 'null' then
    if jsonb_typeof(p_value) <> 'string' then
      raise exception 'precondition_failed: bad_value — % is interval-typed and needs a JSON STRING such as "24 hours"; a bare number is read as SECONDS', p_key;
    end if;
    begin
      v_probe := (p_value #>> '{}')::interval;
    exception when others then
      v_probe := null;
    end;
    if v_probe is null then
      raise exception 'precondition_failed: bad_value — % must be a parseable interval literal', p_key;
    end if;
  end if;

  -- H2 — THE MIRROR GUARD: a key consumed as a NUMBER OF HOURS must be a JSON
  -- NUMBER. The guard above stops a number reaching an interval-typed key; this
  -- one stops a STRING reaching an hours-typed key, and it exists because the
  -- two failure modes are neighbours on the keyboard. `ticket.expiry_grace`
  -- REQUIRES the string form '"72 hours"', so '"720 hours"' is the natural typo
  -- on its sibling deletion key — and before H2's rewrite of
  -- kernel.deletion_blockers_money that one append would have raised inside the
  -- deletion blocker for EVERY identity, forever (platform_config is append-only,
  -- and 085's read cast the value in an ordered target list, so the LIMIT could
  -- not protect it). 10j is now immune by construction; this refuses the value at
  -- the door as well, so the bad version is never written in the first place.
  if p_key in ('deletion.post_event_hold_hours')
     and jsonb_typeof(p_value) <> 'null'
     and jsonb_typeof(p_value) <> 'number' then
    raise exception 'precondition_failed: bad_value — % is a NUMBER OF HOURS and needs a JSON number such as 720; "720 hours" is the interval spelling and belongs to ticket.expiry_grace', p_key;
  end if;

  -- 093 / ruling A5 — `fee.%` ADDED. This is the ONLY change to this function.
  -- WHY: fee.buyer_service_bps is the final clause of the SALEABLE chain — the
  -- statement that sets it moves the platform from "cannot sell" to "selling",
  -- and a gate audit proved three preconditions behind it are unenforced (no
  -- active signing key is required at checkout, refund executability is checked
  -- nowhere, and no tax model exists at all). A single administrator crossing
  -- that line in one un-parked statement is exactly the shape the owner banned:
  -- a config value acting as a hidden feature flag for incomplete logic.
  -- WHY THE PREFIX AND NOT A RENAME: the settlement maturity key was fixed by
  -- renaming it into `payout.%`; that is REJECTED here because this is not a
  -- payout key and the rename would reintroduce the misleading semantics the
  -- maturity rename removed. The prefix list is a policy statement about which
  -- NAMESPACES are money-critical, and buyer-facing pricing plainly is.
  -- 093 / H2 — `deletion.%` ADDED, for the same reason and by the same test.
  -- deletion.post_event_hold_hours decides when an identity becomes
  -- IRREVERSIBLY tombstoned while money obligations on their orders can still
  -- arise. G7 P1-4 executed the gap: as one platform_admin with an aal2 claim,
  -- `set_platform_config('deletion.refund_possible_window_hours', …)` returned
  -- `{"status":"ok"}` with no second human, and that single statement is what
  -- turned P0-3 from a design flaw into a one-statement act. `deletion.%`
  -- matched none of the prefixes below. It does now.
  -- WHY THE PREFIX AND NOT A RENAME INTO `refund.%`/`payout.%`: the same
  -- argument the `fee.%` note above makes. This is not a refund key and not a
  -- payout key; filing it under either would restore exactly the collapsed
  -- semantics — refund ELIGIBILITY vs payout MATURITY vs DELETION SAFETY — that
  -- G2's rename and H2's re-anchor both exist to take apart.
  -- 093 / H2 — `ticket.%` ADDED. The LAST destructive key family outside this list.
  -- The evidence is G1 §7 and the seed comment at the top of this file, and it is
  -- stronger than the case for several keys already here: setting
  -- `ticket.expiry_grace` wrongly does not DEGRADE, it writes the TERMINAL label
  -- `expired` across every atom on every ended session within one cron tick
  -- (079:456, cron */2 at 079:799-803) — and 088:1682/1735/1783 then EXCLUDE
  -- expired atoms from catalog.cancel_event's refund cascade, so the holder loses
  -- the ticket AND the money. There is no exit: no shipped function writes
  -- kernel.tickets.state back out of `expired`. A single administrator must not be
  -- able to cross that boundary alone, for the same reason `fee.%` (ruling A5) and
  -- `deletion.%` (H2) were added — an irreversible money or identity boundary takes
  -- two humans.
  -- NOTE the two controls are INDEPENDENT and both still apply. The interval TYPE
  -- guard above already refuses a bare number on this key (it is first in that
  -- list), which is what stops the '24' => TWENTY-FOUR SECONDS cast; dual control
  -- is the separate question of who may set a WELL-TYPED but wrong value. Neither
  -- shadows the other: a mistyped value is refused outright and never parks, and a
  -- well-typed one parks.
  -- `ticket.%` has NO entry in the polarity map below, so it takes §20.2.1's third
  -- arm — not comparable => PARK — in BOTH directions. That is intended and is the
  -- correct default here: the corpus declares no restrictive direction for a grace
  -- that is destructive when short and merely slow when long, so failing toward the
  -- approver is the honest reading.
  v_dual := p_key like 'refund.%' or p_key like 'payout.%' or p_key like 'authn.%'
         or p_key like 'comp.%'   or p_key like 'wallet.%' or p_key like 'credential.%'
         or p_key like 'door.session\_%' or p_key like 'fee.%'
         or p_key like 'deletion.%' or p_key like 'ticket.%';

  -- The declared polarity map. A key absent from it has NO declared polarity and
  -- therefore parks (when dual-controlled). Booleans, enums and every non-scalar
  -- are incomparable by construction and park for the same reason.
  v_polarity := case
    -- LOWER IS RESTRICTIVE: every one of these is a CEILING or a span whose
    -- reduction narrows what may happen without a second human.
    when p_key in ('refund.org_auto_execute_max_minor',
                   'refund.org_dual_control_max_minor',
                   'refund.buyer_self_service_max_minor',
                   'refund.buyer_self_service_window_hours',
                   'refund.platform_support_max_minor',
                   'payout.request_auto_max_minor',
                   -- payout.dual_control_min_minor is the amount ABOVE WHICH a
                   -- payout parks (MONEY §7.2), so RAISING it REMOVES payouts
                   -- from dual control. T-RPC-CFG-01 names this exact key:
                   -- "raising ... parks and inserts no version; lowering it
                   -- executes". It is a ceiling in disguise, not a floor.
                   'payout.dual_control_min_minor',
                   'comp.per_staff_step_up_max_units',
                   'authn.money_action_max_age_seconds',
                   'door.session_ttl_interval',
                   'door.session_absolute_max_interval',
                   'door.session_post_session_grace',
                   'credential.wallet_exp_skew',
                   'credential.wallet_default_span',
                   'credential.app_ttl_interval')          then 'lower_is_restrictive'
    -- HIGHER IS RESTRICTIVE: a longer cooldown, a longer probation and a longer
    -- maturity floor each narrow what may happen (RPC §20.2.1: "a longer
    -- probation"). comp.per_staff_step_up_window_hours is DELIBERATELY ABSENT:
    -- the window is the COUNTING period of the C39 insider-fraud gate, so
    -- shortening it counts fewer units and fires step-up LESS often — the
    -- corpus declares a direction only for its _max_units half (RLS §11.1
    -- AUTHZ-M8), so this key has NO declared polarity and takes §20.2.1's third
    -- arm: not comparable => PARK. Failing toward the approver is the whole
    -- point of that arm.
    -- H2: deletion.post_event_hold_hours joins this arm, and the direction is
    -- forced by irreversibility, not by taste. A LONGER hold blocks more
    -- tombstones, and a tombstone is TERMINAL — DSM has no exit from ERASED and
    -- the corpus carries no force-tombstone verb to compensate an over-long
    -- hold. Too long costs erasure LATENCY (recoverable, and visible in
    -- deletion_block_reason, which now carries the maturity instant). Too short
    -- destroys a live counterparty. So RAISING it executes in one statement — an
    -- operator must be able to tighten during an incident — and SHORTENING it,
    -- which is what makes advance-purchase buyers erasable sooner, parks for a
    -- second platform_admin. Note the seeded value is JSON null, so the FIRST
    -- set is not number-to-number and parks regardless: arming this key at all
    -- is the dangerous act and it takes two humans.
    when p_key in ('payout.destination_cooldown_hours',
                   'payout.destination_probation_days',
                   'authn.money_role_maturity_hours',
                   'deletion.post_event_hold_hours')       then 'higher_is_restrictive'
    -- FALSE IS RESTRICTIVE: a kill switch. WALLET §11.5b — "Setting
    -- wallet.apple.enabled := false ... needs ONE admin and no approval round.
    -- A kill switch that needs a quorum is not a kill switch."
    when p_key = 'wallet.apple.enabled'                    then 'false_is_restrictive'
    -- HIGHER AAL IS RESTRICTIVE: RPC §20.2.1 enumerates "a higher required AAL"
    -- among the restrictive directions by name, so raising it during a
    -- session-theft incident must execute in one transaction.
    when p_key = 'authn.money_action_required_aal'         then 'aal_higher_is_restrictive'
    else null
  end;

  v_restrictive := false;
  if v_polarity is not null
     and jsonb_typeof(v_cur_val) = 'number' and jsonb_typeof(p_value) = 'number' then
    v_old_num := (v_cur_val #>> '{}')::numeric;
    v_new_num := (p_value  #>> '{}')::numeric;
    v_restrictive := case v_polarity
                       when 'lower_is_restrictive'  then v_new_num < v_old_num
                       when 'higher_is_restrictive' then v_new_num > v_old_num
                     end;
  elsif v_polarity = 'false_is_restrictive'
     and jsonb_typeof(p_value) = 'boolean' then
    -- Pulling the switch is a tightening; flipping it on is the mandatory-
    -- dual-control write WALLET §11.5 describes.
    v_restrictive := (p_value = 'false'::jsonb);
  elsif v_polarity = 'aal_higher_is_restrictive'
     and jsonb_typeof(v_cur_val) in ('string','null') and jsonb_typeof(p_value) = 'string' then
    -- aal1 < aal2. An absent current value is the weakest state, so ANY named
    -- level is a tightening against it.
    v_restrictive := case
      when p_value #>> '{}' not in ('aal1','aal2') then false      -- unknown => park
      when jsonb_typeof(v_cur_val) = 'null'        then true
      else (p_value #>> '{}') > (v_cur_val #>> '{}')
    end;
  elsif v_polarity in ('lower_is_restrictive','higher_is_restrictive')
     and jsonb_typeof(v_cur_val) = 'string' and jsonb_typeof(p_value) = 'string' then
    begin
      v_restrictive := case v_polarity
        when 'lower_is_restrictive'
          then (p_value #>> '{}')::interval < (v_cur_val #>> '{}')::interval
        when 'higher_is_restrictive'
          then (p_value #>> '{}')::interval > (v_cur_val #>> '{}')::interval
      end;
    exception when others then
      v_restrictive := false;                       -- not comparable => park
    end;
  end if;

  -- The cross-config invariant (door §10.6): a Wallet token may never outlive the
  -- offline window any manifest could authorise. Validated whenever EITHER side
  -- changes, and the write is rejected otherwise. Evaluated INLINE rather than in
  -- a helper: a helper would be a catalog object the frozen closed world does not
  -- carry, and package parity is EXTRA = 0.
  if p_key in ('credential.wallet_default_span','credential.wallet_exp_skew',
               'door.manifest_ttl_interval') then
    begin
      select coalesce(
               case when p_key = 'credential.wallet_default_span' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'credential.wallet_default_span'
                 order by c.version desc limit 1)),
             coalesce(
               case when p_key = 'credential.wallet_exp_skew' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'credential.wallet_exp_skew'
                 order by c.version desc limit 1)),
             coalesce(
               case when p_key = 'door.manifest_ttl_interval' then (p_value #>> '{}')::interval end,
               (select (c.value #>> '{}')::interval from catalog.platform_config c
                 where c.key = 'door.manifest_ttl_interval'
                 order by c.version desc limit 1))
        into v_span, v_skew, v_ttl;
    exception when others then
      v_span := null; v_skew := null; v_ttl := null;    -- unparseable => reject
    end;
    -- An absent operand cannot be shown to satisfy the invariant, so it does not.
    if v_span is null or v_skew is null or v_ttl is null or v_span + v_skew > v_ttl then
      raise exception 'precondition_failed: bad_value — wallet_default_span + wallet_exp_skew must not exceed door.manifest_ttl_interval';
    end if;
  end if;

  if v_dual and not v_restrictive then
    insert into kernel.approval_request
           (action, required_approver_class, subject_kind, subject_id, org_id,
            payload, config_versions, requested_by, state, reason_code,
            expires_at, command_idempotency_key)
    values ('config.set_money_key', 'platform_admin', 'config_key',
            md5(p_key)::uuid, null,
            jsonb_build_object('key', p_key, 'proposed_value', p_value,
                               'current_value', v_cur_val),
            jsonb_build_object(p_key, v_cur_ver),
            v_uid, 'pending', trim(p_reason_code),
            now() + interval '72 hours', p_command_key)
    returning request_id into v_request_id;

    insert into kernel.admin_audit
           (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'config.money_key_proposed', 'config_key', md5(p_key)::uuid,
            trim(p_reason_code),
            jsonb_build_object('key', p_key, 'version', v_cur_ver, 'value', v_cur_val),
            jsonb_build_object('key', p_key, 'value', p_value));

    -- version UNCHANGED: the UI must say "waiting for a second approver",
    -- never "saved".
    return jsonb_build_object('status','parked','key',p_key,
                              'version',v_cur_ver,'request_id',v_request_id);
  end if;

  -- Direct path. visibility is COPIED FORWARD: set_platform_config may not change
  -- it — a function that can flip a key to public is a function that can publish
  -- the ceilings.
  insert into catalog.platform_config (key, version, value, visibility)
  values (p_key, v_cur_ver + 1, p_value, v_visibility);

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'config.change', 'config_key', md5(p_key)::uuid, trim(p_reason_code),
          jsonb_build_object('key', p_key, 'version', v_cur_ver, 'value', v_cur_val),
          jsonb_build_object('key', p_key, 'version', v_cur_ver + 1, 'value', p_value));

  return jsonb_build_object('status','ok','key',p_key,
                            'version',v_cur_ver + 1,'request_id',null);
end;
$$;



-- ============================================================================
-- ITEM 8 — GUARD BACKWARD SCHEDULE MOVEMENT (P0 — seller-controlled backdating)
--          body-only CREATE OR REPLACE of catalog.update_event_session (079:518-699)
--
-- Reproduced as executed: a seller org moves starts_at AND ends_at back 400 days
-- with a reason_code; the settlement that had closed held/maturity_not_elapsed
-- re-closes with hold_state='none' and payout_hold null, and request_org_payout
-- returns pending_approval to an org-class approver. Second repro: three active
-- atoms on a session 30 days out are all swept to 'expired' — terminal — after
-- the same backdate.
--
-- The function below is reproduced from 079:518-699 MECHANICALLY (extracted, not
-- retyped). Two changes only: one added local (v_econ) and one added guard block,
-- both marked in place. The forward guard, door.schedule_move_grace_interval, the
-- boundary_engaged / move_exceeds_grace / reason_required / session_terminal /
-- unwritable_key refusals, the authority arms, the marketing-only arm, the
-- session_version bump, the audit row and both return shapes are untouched.
-- ============================================================================

create or replace function catalog.update_event_session(
  p_session_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_org_id     uuid;
  v_venue_id   uuid;
  v_event_id   uuid;
  v_status     text;
  v_starts     timestamptz;
  v_ends       timestamptz;
  v_doors      timestamptz;
  v_door_open  timestamptz;
  v_before     jsonb;
  v_key        text;
  v_reason     text;
  v_allowed    boolean := false;
  v_marketing  boolean := false;
  v_has_atoms  boolean := false;
  v_grace      interval;
  v_new_starts timestamptz;
  v_new_doors  timestamptz;
  v_new_ends   timestamptz;
  v_econ       boolean;                 -- 093: economic-weight probe (backward arm)
  v_time_chg   boolean := false;
  v_changed    boolean := false;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required'
      using errcode = '42501';
  end if;
  if p_command_key is null or length(trim(p_command_key)) = 0 then
    raise exception 'precondition_failed: command key required';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'invalid_input: patch must be a json object';
  end if;

  select s.event_id, s.status, s.starts_at, s.ends_at, s.doors_at, s.door_open_at,
         jsonb_build_object('session_label', s.session_label, 'starts_at', s.starts_at,
                            'ends_at', s.ends_at, 'doors_at', s.doors_at)
    into v_event_id, v_status, v_starts, v_ends, v_doors, v_door_open, v_before
    from catalog.event_session s
   where s.session_id = p_session_id
   for update;                                          -- rank 1
  if v_event_id is null then
    raise exception 'not_found: session %', p_session_id using errcode = 'P0002';
  end if;

  select e.org_id, e.venue_id into v_org_id, v_venue_id
    from catalog.event e where e.event_id = v_event_id;

  -- The unwritable set FIRST, for every caller (T-RPC-CAT-02): door_open_at has
  -- a sole writer (catalog.engage_door_freeze, 086, ruling O-5); session_version
  -- is bumped by THIS BODY, never named by a client; event_id re-parents atoms.
  for v_key in select jsonb_object_keys(p_patch) loop
    if v_key not in ('session_label','starts_at','ends_at','doors_at','reason_code') then
      raise exception 'invalid_input: unwritable_key %', v_key;
    end if;
  end loop;

  if v_status in ('completed','cancelled') then
    raise exception 'precondition_failed: session_terminal';
  end if;

  -- Marketing-only patch (RLS §11.1's D3 extension for this verb): the label is
  -- display; the time columns are freeze INPUTS and never marketing.
  v_marketing := not (p_patch ? 'starts_at' or p_patch ? 'ends_at' or p_patch ? 'doors_at');

  if kernel.has_org_role(v_org_id, array['org_owner','org_admin']) then
    v_allowed := true;
  elsif v_marketing
        and kernel.has_org_role(v_org_id, array['org_marketing']) then
    v_allowed := true;
  end if;
  if not v_allowed then             -- PFA-10 deferred arm (has_venue_role, 080)
    v_allowed := kernel.has_venue_role(
      v_venue_id,
      case when v_marketing then array['venue_manager','venue_marketing']
           else array['venue_manager'] end);
  end if;
  if not v_allowed then
    raise exception 'insufficient_privilege: venue_manager or org_owner/org_admin required'
      using errcode = '42501';
  end if;

  v_new_starts := coalesce((p_patch ->> 'starts_at')::timestamptz, v_starts);
  v_new_doors  := case when p_patch ? 'doors_at'
                       then (p_patch ->> 'doors_at')::timestamptz else v_doors end;
  v_new_ends   := case when p_patch ? 'ends_at'
                       then (p_patch ->> 'ends_at')::timestamptz else v_ends end;
  if v_new_starts is null then
    raise exception 'invalid_input: starts_at cannot be null';
  end if;
  if v_new_ends is not null and v_new_ends <= v_new_starts then
    raise exception 'precondition_failed: ends_at must be after starts_at';
  end if;
  v_time_chg := (v_new_starts is distinct from v_starts)
             or (v_new_doors  is distinct from v_doors)
             or (v_new_ends   is distinct from v_ends);

  -- THE TIME GUARD — a custody property (§20.2.4). starts_at/doors_at are the
  -- inputs to catalog.effective_freeze_at, which decides when transfers stop.
  if (v_new_starts is distinct from v_starts) or (v_new_doors is distinct from v_doors) then
    -- once the boundary is taken, the schedule that produced it is evidence.
    if v_door_open is not null then
      raise exception 'precondition_failed: boundary_engaged';
    end if;
    select exists (select 1 from kernel.tickets t
                    where t.event_session_id = p_session_id)
      into v_has_atoms;
    if v_has_atoms then
      -- config('door.schedule_move_grace_interval') is a PFA-9 CLASS A key:
      -- NOT seeded, and 079 is directed to implement it FAIL-TO-SAFE — absent
      -- means NO later move is permitted (the X-12 shape, ruled in PFA-9).
      begin
        v_grace := (select (c.value #>> '{}')::interval
                      from catalog.platform_config c
                     where c.key = 'door.schedule_move_grace_interval'
                     order by c.version desc
                     limit 1);
      exception when others then
        v_grace := null;
      end;
      if (v_new_starts > v_starts
          and (v_grace is null or v_new_starts - v_starts >= v_grace))
         or (v_doors is not null and v_new_doors is not null and v_new_doors > v_doors
             and (v_grace is null or v_new_doors - v_doors >= v_grace))
         or (v_doors is null and v_new_doors is not null and v_new_doors > v_new_starts
             and (v_grace is null or v_new_doors - v_new_starts >= v_grace)) then
        raise exception 'precondition_failed: move_exceeds_grace';
      end if;
      -- any move with atoms issued is audited with a MANDATORY reason code.
      v_reason := p_patch ->> 'reason_code';
      if v_reason is null or length(trim(v_reason)) = 0 then
        raise exception 'precondition_failed: reason_required';
      end if;
    end if;
  end if;

  -- ==== 093 P0 — THE BACKWARD ends_at ARM. THIS IS THE ONLY LOGIC ADDED. ====
  -- The guard above tests FORWARD movement only: every arm at 079:646-651 is
  -- `v_new_* > v_*`, and it never inspects ends_at at all. So a seller org with
  -- org_owner/org_admin could move starts_at AND ends_at back 400 days with a
  -- reason_code and have it accepted. That single primitive:
  --   * defeats the whole eight-predicate G2 maturity gate, because every other
  --     predicate is anchored on the session's own ends_at — the settlement that
  --     closed held/maturity_not_elapsed re-closes with hold_state='none' and
  --     request_org_payout returns pending_approval to an ORG-class approver,
  --     with no platform human anywhere in the path; and
  --   * destroys live credentials — with ticket.expiry_grace set, backdating a
  --     session 30 days out makes sweep_expired_ticket_atoms terminal-ize every
  --     active atom on it within one cron tick.
  -- The bound the maturity report claimed ("the most a seller can shave is the
  -- session's own duration — hours, not months") does not hold: it is unbounded.
  --
  -- SCOPE — NARROWED TO ends_at, AND THE REASON MATTERS.
  -- The corpus's standing claim is that "an earlier move only tightens the
  -- freeze" (asserted by pgTAP 143 G10 and 144 E2). Per column, that claim is
  -- HALF right, and the half that is right is kept:
  --   * starts_at / doors_at earlier — GENUINELY SAFE, still permitted. They
  --     feed only catalog.effective_freeze_at (078:405-446); moving them earlier
  --     makes transfers freeze SOONER, which is strictly more conservative, and
  --     it touches no money anchor. 143 G10 moves starts_at alone and still
  --     passes.
  --   * ends_at earlier — NOT SAFE, and this is what the claim missed. ends_at
  --     is not a freeze input at all; it is the anchor of the two consumers that
  --     did not exist when that reasoning was written: the G2 payout-maturity
  --     gate and kernel.sweep_expired_ticket_atoms (079:494). Moving it earlier
  --     does not tighten anything — it MATURES money and EXPIRES live atoms.
  -- So this arm tests ends_at only. That is the whole exploitable surface: the
  -- red team's paired 400-day move is refused because its ends_at half is.
  --
  -- THE NULL CASE IS COVERED TOO. A session with ends_at NULL has no maturity
  -- anchor, so a two-step attack — move starts_at back (now permitted), then SET
  -- ends_at to a past value that still satisfies the 079:616-617 ends>starts
  -- check — would reach the same place. Newly setting an ends_at that has
  -- ALREADY ELAPSED is therefore refused as well. Setting a FUTURE ends_at on a
  -- session that lacked one stays permitted: it is benign, and it is the only
  -- way to close R1's separate null-ends_at fail-open.
  --
  -- WHY NOT FORBID EVERY BACKWARD MOVE: a pre-sale draft legitimately reschedules
  -- in both directions. The line is ECONOMIC WEIGHT, read from the schema:
  --   * an atom was minted for the session          (kernel.tickets)
  --   * money was actually taken                    (venue."order", paid /
  --     partially_refunded / refunded — 'pending' and 'cancelled' are not money)
  --   * the door ran                                (venue.scan)
  --   * settlement accounting began for the event   (venue.settlement.event_id)
  -- Any one of those and the schedule is evidence, not a plan.
  --
  -- THE PLATFORM CONJUNCT, AND ITS REAL REACHABILITY — MEASURED, NOT ASSUMED.
  -- The `not kernel.is_platform(...)` test below is NOT a usable escape hatch on
  -- its own, and must not be described as one. This verb's authority arms
  -- (079:591-606) admit only org_owner / org_admin / org_marketing and
  -- venue_manager / venue_marketing; kernel.is_platform is not among them. A
  -- platform_admin holding no org or venue role is therefore refused EARLIER, at
  -- 079:603-606, and never reaches this block. Verified by execution:
  --   pure platform_admin           -> insufficient_privilege (the 079 arm)
  --   platform_admin + org_owner    -> ok
  -- So in practice, for an economically-weighted session, a backward move is
  -- REFUSED OUTRIGHT for every principal who can reach this verb — the
  -- fail-closed end of "refused, or restricted to platform authority".
  -- The conjunct is kept because it is correct, costs nothing, and becomes a
  -- real hatch the moment platform authority is added to this verb's arms.
  -- WIDENING THOSE ARMS IS DELIBERATELY NOT DONE HERE: it would change who may
  -- call a frozen 079 verb, which is a bigger decision than this fix, and a
  -- genuine data-entry correction still has the service_role / superuser path
  -- that every other break-glass repair uses. Flagged, not taken.
  --
  -- FAIL CLOSED: if the probe itself raises, v_econ is forced true and the move
  -- is refused. A move we cannot prove is safe is not safe.
  if v_new_ends is not null
     and ( (v_ends is not null and v_new_ends < v_ends)      -- moved EARLIER
        or (v_ends is null     and v_new_ends <= now()) )    -- newly set, ALREADY elapsed
  then
    if not kernel.is_platform(array['platform_admin']) then
      begin
        select exists (select 1 from kernel.tickets t
                        where t.event_session_id = p_session_id)
            or exists (select 1 from venue."order" o
                        where o.event_session_id = p_session_id
                          and o.status in ('paid','partially_refunded','refunded'))
            or exists (select 1 from venue.scan sc
                        where sc.event_session_id = p_session_id)
            or exists (select 1 from venue.settlement st
                        where st.event_id = v_event_id)
          into v_econ;
      exception when others then
        v_econ := true;                                  -- fail closed
      end;
      if v_econ is null or v_econ then
        raise exception 'precondition_failed: backward_schedule_move_frozen — this session carries economic weight (an issued atom, a paid order, a door scan or a settlement), so its schedule may not be moved earlier; contact the platform owner'
          using errcode = 'P0001';
      end if;
    end if;
    -- a backward move is audited with a MANDATORY reason code, exactly as the
    -- forward arm demands one once atoms exist (079:654-658).
    v_reason := p_patch ->> 'reason_code';
    if v_reason is null or length(trim(v_reason)) = 0 then
      raise exception 'precondition_failed: reason_required';
    end if;
  end if;
  -- ==== end 093 backward arm ===============================================

  if p_patch ? 'session_label' then
    update catalog.event_session
       set session_label = p_patch ->> 'session_label', updated_at = now()
     where session_id = p_session_id;
    v_changed := true;
  end if;
  if v_time_chg then
    update catalog.event_session
       set starts_at = v_new_starts, doors_at = v_new_doors, ends_at = v_new_ends,
           -- Δ-N1 (NOTIF Group E): bumped IN THIS TRANSACTION, under the row's
           -- FOR UPDATE, whenever starts/doors/ends change — never a patch key.
           session_version = session_version + 1,
           updated_at = now()
     where session_id = p_session_id;
    v_changed := true;
  end if;

  if not v_changed then
    return jsonb_build_object('status','noop_replay','session_id',p_session_id,
                              'effective_freeze_at', catalog.effective_freeze_at(p_session_id));
  end if;

  insert into kernel.admin_audit
         (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'session.update', 'event_session', p_session_id,
          coalesce(nullif(trim(coalesce(p_patch ->> 'reason_code','')),''), 'self_service'),
          v_before,
          (select jsonb_build_object('session_label', s.session_label, 'starts_at', s.starts_at,
                                     'ends_at', s.ends_at, 'doors_at', s.doors_at,
                                     'session_version', s.session_version)
             from catalog.event_session s where s.session_id = p_session_id));

  -- the recomputed boundary is returned, so the operator sees the consequence
  -- of the edit in the same round trip rather than discovering it at the door.
  return jsonb_build_object('status','ok','session_id',p_session_id,
                            'effective_freeze_at', catalog.effective_freeze_at(p_session_id));
end;
$$;


-- ============================================================================
-- END PART 40
-- ============================================================================
