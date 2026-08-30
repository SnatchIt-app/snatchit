# Writer Registry Parity — specification and registry

**Created 2026-08-28 under owner ruling `OR-7`; CONVERGED 2026-08-29 by the writer-parity convergence
pass.** The ruling gave the `WRITER` subject a single owner; this is the artifact that makes "every
derived list agrees exactly" a mechanical fact rather than an aspiration. Parsed by
`scripts/precedence_gate.py` (checks **H** and **H2**).

> ## STATE AFTER CONVERGENCE — divergence is CLOSED; missing contracts and build gaps are NOT.
>
> ```
> TABLES IN THIS REGISTRY    81    (was 82 — notify.schedule + notify.announcement REMOVED under OR-5, +1 `R-40` kernel.dispute_native
>                                   reduction, 2026-08-29: the schedule's kind CHECK was exactly the three
>                                   OUT types; sprint agent 3)
> DISTINCT WRITERS          175    schema-qualified names (no placeholders — the R-37 checkout is named, `OR-22`;
>                                  the Gate-M payout writer rides the ratified-gate `c` encoding, `C135`;
>                                  +9 on 2026-08-29: the OR-17 deletion machine, the dual-control parks,
>                                  emit_event_required — the writer-recompute semantic pass D1–D9)
> WRITER ENTRIES            290
> PARITY   OK 81 · DIVERGENT 0 · MISSING_CONTRACT 0           = 81
> NOT-BUILT WRITERS           0    (the R-37 placeholder discharged by `OR-22`)
> GATE ERRORS                 0    0 missing-contract · 0 not-built · 0 divergent — gate A–H GREEN
>                                  (2026-08-29, the final owner sitting: OR-17–OR-23 + C135 applied)
>
> **Sprint 2, 2026-08-29 — five more discharged:** org_invite (revoke §20.1.6 + expiry sweep §20.1.7
> authored; `declined` STRUCK — R-36 ruled B, `OR-18`, 2026-08-29) · venue.order (`cancel_pending_order` §20.7.9, with the terminal-failure
> S-16-style edge correction) · the erasure tombstone (named + contracted §17.20a after the shape derivation
> closed the UPSERT-vs-AO blocker; scheduled in 077) · notify.identity_channel_state (push arm mechanical on
> §17.25/§17.24 extensions; email arm CONDITIONAL(N1)) · notify.schedule + announcement rows REMOVED
> (OR-5 residue, not missing contracts). market.market_sale was CLOSED by `OR-22`
> (R-37 Option B: checkout §20.8.8 + bind §20.8.9 + finalize §20.8.10 + cancel §20.8.11). **ZERO owner-gated
> failures remain (final sitting, 2026-08-29):** payout native-sale reclassified to the ratified-gate `c`
> encoding (R-38 CLOSED-AS-GATED, `C135`) · org_customer_key contracted at §17.22 (`OR-19`) ·
> market_sale closed (`OR-22`) · the auction/bid family left the fence under `OR-11` (R-9 = A).
> **`CATEGORY:set_updated_at` now rides the ten R-35 fence rows** (red-team P2-13 — check H witnesses the
> attachments).
>
> **Parallel convergence sprint, 2026-08-29 — six missing contracts DISCHARGED mechanically:**
> `public.payments`/`listings`/`transfers` (one root — `delete_account_cleanup` declared at RPC §20.15,
> transcribed from the PRODUCTION SQL body; the PR #28 follow-up obligation is stated there) ·
> `market.offer` (the "088 expiry tick" was never nameless — §20.8.5 folds it into
> `market.sweep_expired_p2p_transfers`, now on §12.2's own Writes line) · `kernel.payment_native`
> (`instrument_fingerprint` writer = `venue.finalize_primary_order` §6.3, webhook-supplied parameter —
> every alternative closed by a named ruling; column moved `090 → 085` under `C112`) ·
> `catalog.event_session` (`session_version` — E-1 DISSOLVED: the bumper is
> `catalog.update_event_session`; three sites to four words, and the ratified dedupe property is
> satisfiable no other way). **`kernel.set_updated_at` contracted at §20.16 (`R-35` closed) — the census
> found TEN unattached tables across FOUR packages, not one.** Holder-mix trio scheduled to `086`
> (`R-7a`); the BUILT flags flip with that edit.
> ```
>
> **Every one of the 21 transcription divergences (RC-2) was repaired at its site** — RLS §5 ×13 rows,
> RLS §7/§9/§10 Write-RPCs lines ×16, RLS §16.5 closure set, schema spec ×6 (`§1.5`, `§1.5.1`, `§1.8` ×2,
> `§1.9` placeholder, `§3.12` ×2), door spec ×1 (`§ manifest` — the second candidate site was re-derived
> as already correct), plus the canonical document's own five internal contradictions (`R-24` "TEN",
> §0.7a's count and closure, the §7 preamble, §8.2's payment-native phrasing, §17.10's pre-`C110` direct
> write — the `RC-6` shape, closed by contracting the two `C110` hooks at §17.10a). Every derived line now
> restates the registry and says so inline.
>
> **What did NOT converge, and must not be papered over:** **16 MISSING CONTRACTS** (each a real absent
> function contract — the placeholders of `RC-4`, the webhook-facing writers, the erasure-tombstone
> trigger `J-12`, `kernel.set_updated_at` under `R-35`, `payment_native.instrument_fingerprint` failing
> OPEN on the self-deal detector) and **3 CONTRACTED-NEVER-BUILT writers** (`venue.unpublish_holder_mix`
> · `venue.unpublish_all_holder_mix` · the unnamed erasure trigger — **`kernel.mark_refund_state` left
> this list 2026-08-29: `S-24` applied**, plan `085` schedules the function + partial unique + pairing
> CHECK; **`S-25` CLOSED same day** — the registry's `085` prose row and JSON entry both name the
> function and its two constraints, `depends_on` untouched).
> **Readiness still FAILS. That is the registry telling the truth.** *(HISTORICAL as of the 2026-08-29 final sitting: the 16 missing contracts and the never-built trio were discharged across R-7a, §17.20a/`077`, §20.16/R-35, S-24/S-25 and OR-17–OR-23 + C135 — the derived header above is the live state: 0 missing, 0 not-built, 0 divergent.)*
>
> *(The 2026-08-28 header block, its corrected-counts note and the 80/82 scope defect it recorded are
> superseded by the fence itself — counts below are derived from the enumeration, `RC-1` closed.)*

## The scope was derived, and it is not the list one would guess

The natural starting point — the RLS spec's "sensitive RPC-only tables" list — is **a subset, not the
scope**. The scope generator is RLS §4's class→posture table, which sets `INS/UPD default = R`
(RPC-only) for **all six** RLS classes. **Every Phase-2 table is an RPC-only / server-written
authoritative table.** The 19-row list is only the money/custody *sensitive* part.

## The systemic cause, and the ruling reverses it

> **RPC §20.0a stated: *"Trigger functions are excluded from both sets by construction …"* — REPAIRED
> 2026-08-29:** §20.0a now confines the exclusion to the GRANT-difference sets and names trigger
> functions registry members with kind `trigger` (`RC-3` closed at the root; the findings it caused
> remain open below).
>
> **Under `OR-7` the old exclusion was NON-CONFORMANT.** It was the root cause of three findings:
>
> - **`kernel.set_updated_at`** writes `updated_at` on **every mutable table** and appears in no
>   per-table writer set in any of the four documents. No document enumerates its attachments.
> - **The `kernel.identity_demographic_erasure` tombstone trigger.** RPC says the tombstone *"is
>   written by a `BEFORE DELETE FOR EACH ROW` trigger … not by this function."* The migration plan
>   says `identity_demographic` carries *"exactly one trigger — the `updated_at` maintainer — and
>   nothing else"*, and builds no such trigger. **A direct contradiction, and the erasure tombstone
>   has no writer.**
> - It is why the excluded class is the class most likely to be silently absent.

## The divergences that are not bookkeeping

**Two EXTRA writers — a derived document naming a function that does not write the table.**
`kernel.issue_ticket_atoms` is listed as a `venue.order` writer by RLS **twice** and by the schema
spec; its Writes line does not name `venue.order`, and `→ paid` belongs to
`venue.finalize_primary_order`. And RLS adds *"+ door_pin path"* to `venue.scan`'s writer set — which
is not a function at all.

**`kernel.mark_refund_state` was contracted, assigned to `085` by the schema spec, and built by no
package.** Without it, **three of `kernel.refund.status`'s four labels and the `stripe_refund_ref`
join key had no writer in the shipped chain.** **`S-24` APPLIED 2026-08-29** — plan `085` now schedules
the function, the partial unique and the pairing CHECK, and `T-SCHEMA-REFUND-01`…`-04`. **`S-25` APPLIED
later the same day** — registry `085` prose + JSON both name it; all four surfaces now agree.

**Four webhook-facing writers exist only as prose in the edge spec** — an unnamed *"org connect
capability writer RPC"* (for columns the schema spec does not define), an *"order cancel RPC"* on
payment-failed, the `market_sale → paid_pending_transfer` transition, and a *"native dispute freeze
RPC"* that upserts a dispute table **which exists in no package**. *(HISTORICAL — closed by `OR-24`/`R-40`, 2026-08-30: `kernel.dispute_native` in `088`, §20.7.13–§20.7.15.)*

**`public.delete_account_cleanup` is live in production and appears in no write-authority row of any
spec.** It repoints `listings.seller_id`, `payments.buyer_id/seller_id` and
`transfers.buyer_id/seller_id`. The schema spec says so itself.

**One write-authority breach, recorded not resolved:** `venue.remove_guest_entry` performs a DELETE,
while the RLS global reminder says `DEL = D` for all roles and all tables, and the demographics DELETE
is called *"the single GP-2 exception … A second such exception must not be granted by analogy."*

## What the check detects, and the fixtures that prove it detects them

| detects | fixture |
|---|---|
| missing writer · extra writer | writer/kind length mismatch, unqualified names |
| **trigger writer omitted** · **cron writer omitted** · **server-only writer omitted** | every writer carries a `KIND`, and a row whose writer count ≠ kind count fails — **this is how a trigger or cron writer would otherwise vanish silently** |
| renamed without mapping | schema-qualified names only; the corpus's eight alias pairs are mapped in the RPC naming register and are therefore compliant, not divergences |
| function contracted but never scheduled | `PARITY = DIVERGENT` |
| **missing contract** | `PARITY = MISSING_CONTRACT` fails readiness outright |
| an empty registry row sneaking through as "fine" | a table with no writer needs a stated reason (`NONE` / `SEED-ONLY` / `EXT-` / `CONDITIONAL` / `NOT-BUILT`) |

`CATEGORY:` writers are permitted: a derived document (or the registry itself) may say *"every
privileged RPC writes its own audit row in-txn"* rather than maintain a list the ruling would then
require to be exact. **12 such references exist and are compliant.** Note the contrast the corpus
already demonstrates: the two RLS matrices that *do* enumerate are precisely the two that caught the
schema spec's omissions.

## THE REGISTRY

`TABLE | CANONICAL_WRITERS(;) | KIND_PER_WRITER(;) | RPC_SECTION | BUILT_PER_WRITER(;) | PARITY`

BUILT: `y` built/scheduled · `n` **contracted, built by NO package — a gate error** · `c` conditional
(deferred by a ratified gate, `COND-B`/`OR-5`) · `-` no-writer row.

Kinds: `rpc` · `trigger` · `cron` · `helper` · `webhook`. **`kernel.tickets` (the canonical eleven) and
`kernel.payment_native` (the `R-34` pair) are now rows 6–7 of the fence** — previously derived in a side
document, which is how their parity never reached the gate (`RC-1`); check `H2` now makes their absence a
hard error. `venue.order` no longer lists `kernel.admin_refund` (`F-3` resolved against §20.7.1's own
Writes line: it refunds a payment, possibly with no order behind it). **`kernel.set_updated_at` is a
registry-level CATEGORY writer** — contracted at RPC **§20.16** (2026-08-29, `R-35` CLOSED), kind
`trigger`, attachment map = the schema census, carried once rather than repeated on ~40 rows. *(This
sentence previously claimed `kernel.tickets` was the ONLY required-but-not-attached site — the census
refuted that: TEN tables across `079`/`083`/`086`/`090` lacked the maintainer the schema's own global
convention requires; all ten attachments are now scheduled in the plan's Triggers rows.)*

```writer-registry
kernel.identity_ext|kernel.upsert_identity_ext;kernel.request_account_deletion;kernel.withdraw_account_deletion;kernel.sweep_deletion_pending|rpc;rpc;rpc;cron|20.1.3;20.17.1;20.17.2;20.17.4|y|OK
kernel.organization|kernel.create_organization;kernel.set_org_status;kernel.update_organization;kernel.set_org_payout_destination;kernel.set_org_connect_ref|rpc;rpc;rpc;rpc;rpc|2.1;20.1.2;20.1.5;17.7;20.1.1|y|OK
kernel.org_member|kernel.create_organization;kernel.accept_org_invite;kernel.change_org_role;kernel.remove_org_member;kernel.sweep_deletion_pending|rpc;rpc;rpc;rpc;cron|2.1;2.3;2.4;2.5;20.17.4|y|OK
kernel.org_invite|kernel.invite_org_member;kernel.accept_org_invite;kernel.revoke_org_invite;kernel.sweep_expired_org_invites;kernel.sweep_deletion_pending|rpc;rpc;rpc;cron;cron|2.2;2.3;20.1.6;20.1.7;20.17.4|y|OK
kernel.platform_role|kernel.grant_platform_role;kernel.revoke_platform_role;kernel.sweep_deletion_pending|rpc;rpc;cron|20.1.4;20.1.4;20.17.4|y|OK
kernel.tickets|kernel.issue_ticket_atoms;kernel.transfer_ticket_ownership;kernel.void_ticket_atom;kernel.lock_ticket;kernel.unlock_ticket;kernel.mark_ticket_scanned;kernel.request_order_refund;kernel.approve_refund_request;kernel.cancel_refund_request;kernel.sweep_expired_refund_requests;kernel.sweep_expired_ticket_atoms;kernel.record_dispute_native;kernel.resolve_dispute_native;kernel.on_deletion_q5_release;CATEGORY:set_updated_at|helper;helper;helper;helper;helper;helper;rpc;rpc;rpc;cron;cron;webhook;rpc;helper;trigger|7.1;7.2;7.3;7.4;7.4;7.5;17.1;17.2;17.3;17.4;12.5;20.7.13;20.7.15;20.17.5;20.16|y|OK
kernel.payment_native|venue.finalize_primary_order;kernel.transfer_ticket_ownership|webhook;helper|6.3;7.2|y|OK
kernel.ticket_ownership_log|kernel.issue_ticket_atoms;kernel.transfer_ticket_ownership;kernel.void_ticket_atom|helper;helper;helper|7.1;7.2;7.3|y|OK
kernel.signing_key|kernel.provision_signing_key;kernel.rotate_signing_key;kernel.revoke_signing_key;CATEGORY:set_updated_at|rpc;rpc;rpc;trigger|20.7.3;20.7.4;20.7.5;20.16|y|OK
kernel.payout|kernel.close_settlement;kernel.pay_promoter_commission;kernel.request_org_payout;kernel.hold_payout;kernel.release_payout;kernel.mark_payout_transfer_state;kernel.record_dispute_native;kernel.resolve_dispute_native;kernel.GATEM_NATIVE_SALE_PAYOUT|rpc;helper;rpc;rpc;rpc;webhook;webhook;rpc;rpc|10.2;20.7.2;10.3;11.2;11.3;20.7.6;20.7.13;20.7.15;R-38|y;y;y;y;y;y;y;y;c|OK
kernel.refund|kernel.refund_primary_order;kernel.admin_refund;market.sweep_paid_pending_sales;kernel.mark_refund_state;kernel.force_void_ticket;catalog.cancel_event|rpc;rpc;cron;webhook;rpc;rpc|11.4;20.7.1;12.3;20.7.7;11.1;4.4|y|OK
kernel.identity_obligation|kernel.record_identity_obligation;kernel.resolve_identity_obligation|webhook;rpc|20.7.10;20.7.11|y|OK
kernel.dispute_native|kernel.record_dispute_native;kernel.mark_dispute_state;kernel.resolve_dispute_native;CATEGORY:set_updated_at|webhook;webhook;rpc;trigger|20.7.13;20.7.14;20.7.15;20.16|y|OK
kernel.reserve|-|-|NONE-wired-in-MVP|-|OK
kernel.admin_audit|kernel.record_money_denial;CATEGORY:every-privileged-RPC-in-txn|rpc;rpc|17.9;0.3|y|OK
kernel.approval_request|kernel.request_order_refund;kernel.approve_refund_request;kernel.cancel_refund_request;kernel.sweep_expired_refund_requests;kernel.request_org_payout;catalog.set_platform_config;kernel.grant_platform_role;kernel.revoke_platform_role;kernel.request_account_deletion;kernel.provision_signing_key;kernel.rotate_signing_key;kernel.revoke_signing_key|rpc;rpc;rpc;cron;rpc;rpc;rpc;rpc;rpc;rpc;rpc;rpc|17.1;17.2;17.3;17.4;10.3;20.2.1;20.1.4;20.1.4;20.17.1;20.7.3;20.7.4;20.7.5|y|OK
kernel.identity_contact_pref|kernel.set_my_contact_prefs|rpc|17.21|y|OK
kernel.identity_contact_pref_event|kernel.set_my_contact_prefs|rpc|17.21|y|OK
kernel.org_contact_consent|kernel.grant_org_contact_consent;kernel.withdraw_org_contact_consent|rpc;rpc|17.21|y|OK
kernel.org_contact_consent_event|kernel.grant_org_contact_consent;kernel.withdraw_org_contact_consent|rpc;rpc|17.21|y|OK
kernel.org_customer_key|venue.request_export|rpc|17.22|y|OK
kernel.identity_demographic|kernel.set_my_demographics;kernel.clear_my_demographics|rpc;rpc|17.20|y|OK
kernel.identity_demographic_erasure|kernel.write_demographic_erasure_tombstone|trigger|17.20a|y|OK
kernel.door_freeze_override|kernel.grant_door_freeze_override;kernel.revoke_door_freeze_override|rpc;rpc|17.11|y|OK
kernel.wallet_pass|kernel.mint_wallet_pass;kernel.revoke_wallet_pass;kernel.supersede_wallet_passes_for_atom;kernel.touch_wallet_pass;kernel.sweep_wallet_pass_lifecycle;CATEGORY:set_updated_at|rpc;rpc;helper;helper;cron;trigger|17.23;17.23;17.23;17.23;17.23;20.16|y|OK
kernel.wallet_pass_device|kernel.register_wallet_pass_device;kernel.unregister_wallet_pass_device;kernel.revoke_wallet_pass;kernel.record_wallet_push_result|helper;helper;rpc;helper|17.23|y|OK
kernel.pass_type_cert|kernel.provision_pass_type_cert;kernel.rotate_pass_type_cert;kernel.revoke_pass_type_cert;CATEGORY:set_updated_at|rpc;rpc;rpc;trigger|17.23;17.23;17.23;20.16|y|OK
kernel.wallet_pass_push_log|kernel.record_wallet_push_result|helper|17.23|y|OK
kernel.org_money_policy|-|-|CONDITIONAL-D-2|-|OK
catalog.venue|catalog.create_venue;catalog.approve_venue;catalog.update_venue|rpc;rpc;rpc|3.1;3.2;3.3|y|OK
catalog.event|catalog.create_event;catalog.publish_event;catalog.cancel_event;catalog.update_event|rpc;rpc;rpc;rpc|4.1;4.2;4.4;20.2.3|y|OK
catalog.event_session|catalog.create_event_session;catalog.create_event;catalog.update_event_session;catalog.cancel_event;catalog.engage_door_freeze;catalog.set_session_door_schedule|rpc;rpc;rpc;rpc;helper;rpc|4.3;4.1;20.2.4;4.4;17.12;20.6.5|y|OK
catalog.platform_config|catalog.set_platform_config|rpc|20.2.1|y|OK
catalog.resale_policy|catalog.set_resale_policy|rpc|20.2.2|y|OK
venue.ticket_type|venue.create_ticket_type;venue.set_ticket_type_price|rpc;rpc|5.1;20.3.1|y|OK
venue.inventory_batch|venue.create_inventory_batch;venue.reserve_primary_inventory;venue.create_inventory_hold;venue.release_inventory_hold;venue.set_batch_capacity;venue.sweep_expired_inventory_holds;venue.allocate_comp;venue.issue_comp;kernel.issue_ticket_atoms;kernel.void_ticket_atom;kernel.refund_primary_order;kernel.admin_refund;venue.finalize_primary_order|rpc;rpc;rpc;rpc;rpc;cron;rpc;rpc;helper;helper;rpc;rpc;webhook|5.2;5.3;5.4;5.5;20.3.2;20.3.3;20.5.1;20.5.2;7.1;7.3;11.4;20.7.1;6.3|y|OK
venue.inventory_batch_shard|venue.create_inventory_batch;venue.reserve_primary_inventory;venue.create_inventory_hold;venue.release_inventory_hold;venue.set_batch_capacity;venue.allocate_comp;venue.issue_comp;kernel.issue_ticket_atoms;kernel.void_ticket_atom;venue.finalize_primary_order|rpc;rpc;rpc;rpc;rpc;rpc;rpc;helper;helper;webhook|5.2;5.3;5.4;5.5;20.3.2;20.5.1;20.5.2;7.1;7.3;6.3|y|OK
venue.inventory_movement|venue.reserve_primary_inventory;venue.release_inventory_hold;venue.set_batch_capacity;venue.allocate_comp;venue.issue_comp;venue.finalize_primary_order;kernel.issue_ticket_atoms;kernel.void_ticket_atom|rpc;rpc;rpc;rpc;rpc;webhook;helper;helper|5.3;5.5;20.3.2;20.5.1;20.5.2;6.3;7.1;7.3|y|OK
venue.inventory_hold|venue.reserve_primary_inventory;venue.create_inventory_hold;venue.release_inventory_hold;venue.sweep_expired_inventory_holds|rpc;rpc;rpc;cron|5.3;5.4;5.5;20.3.3|y|OK
venue.inventory_unit|-|-|EXT-C42-DO-NOT-BUILD|-|OK
venue.order|venue.create_primary_checkout;venue.finalize_primary_order;venue.bind_order_attribution;kernel.refund_primary_order;venue.cancel_pending_order|rpc;webhook;rpc;rpc;webhook|6.1;6.3;17.18;11.4;20.7.9|y|OK
venue.order_item|venue.create_primary_checkout|rpc|6.1|y|OK
venue.staff_role|venue.grant_staff_role;venue.revoke_staff_role;kernel.on_identity_erased_staff|rpc;rpc;helper|20.4.1;20.4.2;20.17.5|y|OK
venue.door_pin|venue.create_door_pin;venue.revoke_door_pin|rpc;rpc|9.1;9.2|y|OK
venue.door_session|venue.mint_door_session;venue.revoke_door_session;venue.sweep_expired_door_sessions;venue.revoke_door_pin;venue.set_scan_device_status;kernel.assert_door_session|rpc;rpc;cron;rpc;rpc;helper|9.6;9.7;9.8;9.2;20.4.3;1.1d|y|OK
venue.scan_device|venue.register_scan_device;venue.sync_scan_device_manifest;venue.set_scan_device_status;CATEGORY:set_updated_at|rpc;rpc;rpc;trigger|20.4.3;20.4.4;20.4.3;20.16|y|OK
venue.scan|venue.record_scan;venue.reconcile_offline_scans|rpc;rpc|9.4;9.5|y|OK
venue.settlement|venue.open_settlement;kernel.close_settlement;venue.on_payout_settled|rpc;rpc;helper|10.1;10.2;20.11.5|y|OK
venue.settlement_line|kernel.close_settlement;kernel.pay_promoter_commission|rpc;helper|10.2;20.7.2|y|OK
venue.comp_allocation|venue.allocate_comp;venue.issue_comp;kernel.on_identity_erased_door;CATEGORY:set_updated_at|rpc;rpc;helper;trigger|20.5.1;20.5.2;20.17.5;20.16|y|OK
venue.guest_list|venue.create_guest_list;kernel.on_identity_erased_door;CATEGORY:set_updated_at|rpc;helper;trigger|20.5.3;20.17.5;20.16|y|OK
venue.guest_entry|venue.upsert_guest_entry;venue.remove_guest_entry;venue.check_in_guest_entry;CATEGORY:set_updated_at|rpc;rpc;rpc;trigger|20.5.4;20.5.5;20.5.6;20.16|y|OK
venue.promoter|venue.create_promoter;venue.update_promoter;CATEGORY:set_updated_at|rpc;rpc;trigger|20.9.1;20.9.2;20.16|y|OK
venue.promoter_link|venue.create_promoter_link;venue.set_promoter_link_status;kernel.on_identity_erased_promoter;CATEGORY:set_updated_at|rpc;rpc;helper;trigger|20.9.3;20.9.4;20.17.5;20.16|y|OK
venue.attribution|venue.resolve_order_attribution|helper|17.14|y|OK
venue.promoter_code|venue.create_promoter_code;venue.create_promoter_codes_bulk;venue.set_promoter_code_status;venue.set_promoter_code_window|rpc;rpc;rpc;rpc|17.15|y|OK
venue.promoter_code_scope|venue.create_promoter_code;venue.create_promoter_codes_bulk;venue.set_promoter_code_scope|rpc;rpc;rpc|17.15|y|OK
venue.attribution_review|venue.review_attribution_flag|rpc|17.18|y|OK
venue.door_manifest|venue.open_door_manifest;venue.close_door_manifest;venue.append_door_manifest_delta;kernel.revoke_signing_key|rpc;rpc;helper;rpc|17.10;17.11;17.13;20.7.5|y|OK
venue.door_manifest_entry|venue.open_door_manifest|rpc|17.10|y|OK
venue.door_manifest_delta|venue.append_door_manifest_delta;kernel.revoke_signing_key|helper;rpc|17.13;20.7.5|y|OK
venue.holder_mix_snapshot|venue.refresh_holder_mix;venue.unpublish_holder_mix;venue.unpublish_all_holder_mix|cron;rpc;rpc|17.20|y|OK
venue.holder_mix_bucket|venue.refresh_holder_mix|cron|17.20|y|OK
venue.export_job|venue.request_export;venue.build_export_rows;venue.finalize_export;venue.revoke_export;venue.sweep_expired_exports;venue.claim_artifacts_for_purge;venue.confirm_artifact_purged;venue.reconcile_export_orphans|rpc;helper;helper;rpc;cron;helper;helper;helper|17.22|y|OK
market.listing_native|market.create_listing;market.cancel_listing;market.respond_offer;market.on_door_freeze_engaged;catalog.cancel_event;market.checkout_buy_now;market.finalize_market_sale;market.cancel_buy_now_sale;kernel.on_identity_erased_market|rpc;rpc;rpc;helper;rpc;rpc;webhook;webhook;helper|20.8.1;20.8.2;20.8.6;17.10a;4.4;20.8.8;20.8.10;20.8.11;20.17.5|y|OK
market.auction|market.create_auction;market.place_bid;market.cancel_listing;catalog.cancel_event|rpc;rpc;rpc;rpc|20.8.3;20.8.4;20.8.2;4.4|y|OK
market.offer|market.make_offer;market.respond_offer;market.cancel_listing;market.sweep_expired_p2p_transfers;market.finalize_market_sale;kernel.on_identity_erased_market|rpc;rpc;rpc;cron;webhook;helper|20.8.5;20.8.6;20.8.2;12.2;20.8.10;20.17.5|y|OK
market.market_sale|kernel.transfer_ticket_ownership;market.respond_offer;market.sweep_paid_pending_sales;market.on_atom_voided;market.mark_sale_paid_state;market.checkout_buy_now;market.bind_checkout_payment_ref;market.finalize_market_sale;market.cancel_buy_now_sale|rpc;rpc;cron;helper;webhook;rpc;helper;webhook;webhook|7.2;20.8.6;12.3;20.11.3;20.8.7;20.8.8;20.8.9;20.8.10;20.8.11|y|OK
market.p2p_transfer|market.create_p2p_transfer;market.accept_p2p_transfer;market.cancel_p2p_transfer;market.sweep_expired_p2p_transfers;market.on_door_freeze_engaged;catalog.cancel_event|rpc;rpc;rpc;cron;helper;rpc|8.1;8.2;8.3;12.2;17.10a;4.4|y|OK
notify.notification|notify.enqueue;notify.drain_outbox;notify.mark_read;notify.mark_all_read;notify.dismiss|helper;cron;rpc;rpc;rpc|17.24|y|OK
notify.preference|notify.set_preference|rpc|17.24|y|OK
notify.notification_type|-|-|SEED-ONLY|-|OK
notify.template|-|-|SEED-ONLY|-|OK
notify.delivery|notify.drain_outbox;notify.claim_deliveries;notify.record_delivery_result|cron;helper;helper|17.24;17.25;17.25|y|OK
notify.outbox|notify.emit_event;notify.emit_event_required;notify.drain_outbox|helper;helper;cron|17.24;17.24;17.24|y|OK
notify.identity_channel_state|notify.record_delivery_result;notify.register_push_token|helper;rpc|17.25;17.24|y|OK
public.payments|public.delete_account_cleanup;CATEGORY:frozen-stripe-webhook|helper;webhook|20.15;20.15|y|OK
public.listings|public.delete_account_cleanup|helper|20.15|y|OK
public.transfers|public.delete_account_cleanup|helper|20.15|y|OK
public.push_tokens|notify.register_push_token;notify.revoke_push_token;notify.record_delivery_result|rpc;rpc;helper|17.24;17.24;17.25|y|OK
public.rate_limits|public.check_rate_limit|helper|17.17|y|OK
```

## THE MISSING CONTRACTS — re-derived 2026-08-29 (red-team P2-8: this list had gone stale in both directions)

**Current (0): the missing-contract class is EMPTY — 2026-08-29 final sitting.** `kernel.payout` native-sale → ratified-gate `c` (`C135`, Gate-M amendment owes the contract) · `kernel.org_customer_key` → §17.22 (`OR-19`) · `market.market_sale` → §20.8.8–§20.8.11 (`OR-22`) · auction/bid → `OR-11` · the `charge.dispute` freeze RPC + table → §20.7.13–§20.7.15 / schema §1.10b (`R-40`, 2026-08-30). **Everything below this line is the HISTORICAL 2026-08-28 list, preserved as the record of what the ruling first surfaced:**

### THE 18 MISSING CONTRACTS — as first enumerated (historical)

`kernel.organization` Stripe capability-flag writer (for columns the schema spec does not define) ·
`kernel.org_invite` invite-revoke (a phrase appearing **once corpus-wide**) · `kernel.payout`
"native-sale payout path" (a phrase, not a function) · an **executable** writer of the money-denial
audit row · the `kernel.identity_demographic_erasure` BEFORE-DELETE trigger · `kernel.org_customer_key`
mint **and** rotation · `catalog.event_session.session_version` · `venue.order` cancel-on-payment-failed
· `market.auction` "finalize sweep" · `market.offer` `088` expiry tick · `market.market_sale →
paid_pending_transfer` · the `market.bid` ledger (table **and** writer, owner ruling `R-9` open) ·
`public.delete_account_cleanup` as declared writer of three live tables · `notify.identity_channel_state`
· the `notify.schedule` producer · `kernel.set_updated_at` · the `charge.dispute.created` freeze RPC
**and the dispute table it upserts, which exists in no package**.

Adjacent: `venue.set_event_security_config` is scheduled and marked **⛔ BLOCKED** — it writes
per-event door-config rows and no such table exists in any package.

## CONTRACTED BUT NEVER BUILT — 0 *(HISTORICAL LIST — was 4; `S-24` applied 2026-08-29; the holder-mix trio scheduled into `086` by `R-7a` the same day, its fence rows ride `y`)*

~~`kernel.mark_refund_state`~~ (**closed** — `S-24` plan + `S-25` registry, both 2026-08-29) ·
~~`venue.unpublish_holder_mix` · `venue.unpublish_all_holder_mix` · `venue.reconcile_holder_mix`~~ (**closed** — `R-7a`, plan `086` Functions row).
The **`notify.*` writers are BUILT `y` since `OR-12` scheduled `092_notify_reduced`** (BUILT flags flipped 2026-08-29, the R-7a precedent; the former "17 conditional / COND-B" framing is history).
