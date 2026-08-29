# Writer Registry Parity — specification and registry

**Created 2026-08-28 under owner ruling `OR-7`.** The ruling gave the `WRITER` subject a single owner;
this is the artifact that makes "every derived list agrees exactly" a mechanical fact rather than an
aspiration. Parsed by `scripts/precedence_gate.py` (check **H**).

> ## THE PARITY CHECK FAILS. THAT IS THE FINDING.
>
> ```
> TABLES IN SCOPE            80    venue 30 · kernel 25 · notify 9 · market 6 · catalog 5 · public 5
> CANONICAL WRITERS         151    distinct schema-qualified functions
> PARITY   OK 43 · DIVERGENT 22 · MISSING_CONTRACT 15          = 80
> DIVERGENCE RECORDS         48
> MISSING CONTRACTS          18    (one spans three tables)
> CONTRACTED, NEVER BUILT    21    4 unconditional + 17 conditional
> CATEGORY REFERENCES        12    compliant — a derived doc pointing at the registry
> ```
>
> **Readiness FAILS.** The ruling is explicit: a structurally required writer with no function contract
> is a MISSING CONTRACT and readiness fails. There are **18**, and **4 contracted writers that no
> package builds**.

## The scope was derived, and it is not the list one would guess

The natural starting point — the RLS spec's "sensitive RPC-only tables" list — is **a subset, not the
scope**. The scope generator is RLS §4's class→posture table, which sets `INS/UPD default = R`
(RPC-only) for **all six** RLS classes. **Every Phase-2 table is an RPC-only / server-written
authoritative table.** The 19-row list is only the money/custody *sensitive* part.

## The systemic cause, and the ruling reverses it

> **RPC §20.0a states: *"Trigger functions are excluded from both sets by construction … neither the
> authority table nor a contract document is the right home for them."***
>
> **Under `OR-7` that exclusion is NON-CONFORMANT.** The ruling names trigger functions as members of
> the canonical registry. This one sentence is the root cause of three separate findings:
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

**`kernel.mark_refund_state` is contracted, assigned to `085` by the schema spec, and built by no
package.** Without it, **three of `kernel.refund.status`'s four labels and the `stripe_refund_ref`
join key have no writer in the shipped chain.** The fix is already filed as `S-24` and unapplied.

**Four webhook-facing writers exist only as prose in the edge spec** — an unnamed *"org connect
capability writer RPC"* (for columns the schema spec does not define), an *"order cancel RPC"* on
payment-failed, the `market_sale → paid_pending_transfer` transition, and a *"native dispute freeze
RPC"* that upserts a dispute table **which exists in no package**.

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

`TABLE | CANONICAL_WRITERS(;) | KIND_PER_WRITER(;) | RPC_SECTION | PARITY`

Kinds: `rpc` · `trigger` · `cron` · `helper` · `webhook`. `kernel.tickets` and
`kernel.payment_native` are derived separately in `WRITER_OWNER_RULING_CONSEQUENCE_MAP.md` (11 and 2+1
writers respectively) and are not repeated here.

```writer-registry
kernel.identity_ext|kernel.upsert_identity_ext|rpc|20.1.3|OK
kernel.organization|kernel.create_organization;kernel.set_org_status;kernel.update_organization;kernel.set_org_payout_destination;kernel.set_org_connect_ref|rpc;rpc;rpc;rpc;rpc|2.1;20.1.2;20.1.5;17.7;20.1.1|DIVERGENT
kernel.org_member|kernel.create_organization;kernel.accept_org_invite;kernel.change_org_role;kernel.remove_org_member|rpc;rpc;rpc;rpc|2.1;2.3;2.4;2.5|DIVERGENT
kernel.org_invite|kernel.invite_org_member;kernel.accept_org_invite|rpc;rpc|2.2;2.3|MISSING_CONTRACT
kernel.platform_role|kernel.grant_platform_role;kernel.revoke_platform_role|rpc;rpc|20.1.4|OK
kernel.ticket_ownership_log|kernel.issue_ticket_atoms;kernel.transfer_ticket_ownership;kernel.void_ticket_atom|rpc;rpc;rpc|0.7a;7.1;7.2;7.3|OK
kernel.signing_key|kernel.provision_signing_key;kernel.rotate_signing_key;kernel.revoke_signing_key|rpc;rpc;rpc|20.7.3;20.7.4;20.7.5|OK
kernel.payout|kernel.close_settlement;kernel.pay_promoter_commission;kernel.request_org_payout;kernel.hold_payout;kernel.release_payout;kernel.mark_payout_transfer_state|rpc;helper;rpc;rpc;rpc;webhook|10.2;20.7.2;10.3;11.2;11.3;20.7.6|MISSING_CONTRACT
kernel.refund|kernel.refund_primary_order;kernel.admin_refund;market.sweep_paid_pending_sales;kernel.mark_refund_state|rpc;rpc;cron;webhook|11.4;20.7.1;12.3;20.7.7|DIVERGENT
kernel.reserve|-|-|NONE-wired-in-MVP|OK
kernel.admin_audit|kernel.record_money_denial;CATEGORY:every-privileged-RPC-in-txn|rpc;rpc|17.9;0.3|DIVERGENT
kernel.approval_request|kernel.request_order_refund;kernel.approve_refund_request;kernel.cancel_refund_request;kernel.sweep_expired_refund_requests;kernel.request_org_payout;catalog.set_platform_config;kernel.grant_platform_role;kernel.revoke_platform_role|rpc;rpc;rpc;cron;rpc;rpc;rpc;rpc|17.1;17.2;17.3;17.4;10.3;20.2.1;20.1.4|DIVERGENT
kernel.identity_contact_pref|kernel.set_my_contact_prefs|rpc|17.21|OK
kernel.identity_contact_pref_event|kernel.set_my_contact_prefs|rpc|17.21|OK
kernel.org_contact_consent|kernel.grant_org_contact_consent;kernel.withdraw_org_contact_consent|rpc;rpc|17.21|OK
kernel.org_contact_consent_event|kernel.grant_org_contact_consent;kernel.withdraw_org_contact_consent|rpc;rpc|17.21|OK
kernel.org_customer_key|-|-|NONE-no-writer-anywhere|MISSING_CONTRACT
kernel.identity_demographic|kernel.set_my_demographics;kernel.clear_my_demographics|rpc;rpc|17.20|OK
kernel.identity_demographic_erasure|kernel.UNNAMED_BEFORE_DELETE_TRIGGER|trigger|17.20|MISSING_CONTRACT
kernel.door_freeze_override|kernel.grant_door_freeze_override;kernel.revoke_door_freeze_override|rpc;rpc|17.11|OK
kernel.wallet_pass|kernel.mint_wallet_pass;kernel.revoke_wallet_pass;kernel.supersede_wallet_passes_for_atom;kernel.touch_wallet_pass;kernel.sweep_wallet_pass_lifecycle|rpc;rpc;helper;helper;cron|17.23|OK
kernel.wallet_pass_device|kernel.register_wallet_pass_device;kernel.unregister_wallet_pass_device;kernel.revoke_wallet_pass;kernel.record_wallet_push_result|helper;helper;rpc;helper|17.23|OK
kernel.pass_type_cert|kernel.provision_pass_type_cert;kernel.rotate_pass_type_cert;kernel.revoke_pass_type_cert|rpc;rpc;rpc|17.23|OK
kernel.wallet_pass_push_log|kernel.record_wallet_push_result|helper|17.23|OK
kernel.org_money_policy|-|-|CONDITIONAL-D-2|OK
catalog.venue|catalog.create_venue;catalog.approve_venue;catalog.update_venue|rpc;rpc;rpc|3.1;3.2;3.3|DIVERGENT
catalog.event|catalog.create_event;catalog.publish_event;catalog.cancel_event;catalog.update_event|rpc;rpc;rpc;rpc|4.1;4.2;4.4;20.2.3|DIVERGENT
catalog.event_session|catalog.create_event_session;catalog.create_event;catalog.update_event_session;catalog.cancel_event;catalog.engage_door_freeze;catalog.set_session_door_schedule|rpc;rpc;rpc;rpc;helper;rpc|4.3;4.1;20.2.4;4.4;17.12;20.6.5|MISSING_CONTRACT
catalog.platform_config|catalog.set_platform_config|rpc|20.2.1|OK
catalog.resale_policy|catalog.set_resale_policy|rpc|20.2.2|OK
venue.ticket_type|venue.create_ticket_type;venue.set_ticket_type_price|rpc;rpc|5.1;20.3.1|OK
venue.inventory_batch|venue.create_inventory_batch;venue.reserve_primary_inventory;venue.create_inventory_hold;venue.release_inventory_hold;venue.set_batch_capacity;venue.sweep_expired_inventory_holds;venue.allocate_comp;venue.issue_comp;kernel.issue_ticket_atoms;kernel.void_ticket_atom;kernel.refund_primary_order;kernel.admin_refund|rpc;rpc;rpc;rpc;rpc;cron;rpc;rpc;rpc;rpc;rpc;rpc|5.2;5.3;5.4;5.5;20.3.2;20.3.3;20.5.1;20.5.2;7.1;7.3;11.4;20.7.1|DIVERGENT
venue.inventory_batch_shard|venue.create_inventory_batch;venue.reserve_primary_inventory;venue.create_inventory_hold;venue.release_inventory_hold;venue.set_batch_capacity;venue.allocate_comp;venue.issue_comp;kernel.issue_ticket_atoms;kernel.void_ticket_atom|rpc;rpc;rpc;rpc;rpc;rpc;rpc;rpc;rpc|5.2;5.3;5.4;5.5;20.3.2;20.5.1;20.5.2;7.1;7.3|DIVERGENT
venue.inventory_movement|venue.reserve_primary_inventory;venue.release_inventory_hold;venue.set_batch_capacity;venue.allocate_comp;venue.issue_comp;venue.finalize_primary_order;kernel.issue_ticket_atoms;kernel.void_ticket_atom|rpc;rpc;rpc;rpc;rpc;rpc;rpc;rpc|5.3;5.5;20.3.2;20.5.1;20.5.2;6.3;7.1;7.3|DIVERGENT
venue.inventory_hold|venue.reserve_primary_inventory;venue.create_inventory_hold;venue.release_inventory_hold;venue.sweep_expired_inventory_holds|rpc;rpc;rpc;cron|5.3;5.4;5.5;20.3.3|DIVERGENT
venue.inventory_unit|-|-|EXT-C42-DO-NOT-BUILD|OK
venue.order|venue.create_primary_checkout;venue.finalize_primary_order;venue.bind_order_attribution;kernel.refund_primary_order;kernel.admin_refund|rpc;rpc;rpc;rpc;rpc|6.1;6.3;17.18;11.4;20.7.1|MISSING_CONTRACT
venue.order_item|venue.create_primary_checkout|rpc|6.1|OK
venue.staff_role|venue.grant_staff_role;venue.revoke_staff_role|rpc;rpc|20.4.1;20.4.2|OK
venue.door_pin|venue.create_door_pin;venue.revoke_door_pin|rpc;rpc|9.1;9.2|OK
venue.door_session|venue.mint_door_session;venue.revoke_door_session;venue.sweep_expired_door_sessions;venue.revoke_door_pin;venue.set_scan_device_status;kernel.assert_door_session|rpc;rpc;cron;rpc;rpc;helper|9.6;9.7;9.8;9.2;20.4.3;1.1d|DIVERGENT
venue.scan_device|venue.register_scan_device;venue.sync_scan_device_manifest;venue.set_scan_device_status|rpc;rpc;rpc|20.4.3;20.4.4;20.4.3|DIVERGENT
venue.scan|venue.record_scan;venue.reconcile_offline_scans|rpc;rpc|9.4;9.5|DIVERGENT
venue.settlement|venue.open_settlement;kernel.close_settlement;venue.on_payout_settled|rpc;rpc;helper|10.1;10.2;20.11.5|DIVERGENT
venue.settlement_line|kernel.close_settlement;kernel.pay_promoter_commission|rpc;helper|10.2;20.7.2|DIVERGENT
venue.comp_allocation|venue.allocate_comp;venue.issue_comp|rpc;rpc|20.5.1;20.5.2|OK
venue.guest_list|venue.create_guest_list|rpc|20.5.3|OK
venue.guest_entry|venue.upsert_guest_entry;venue.remove_guest_entry;venue.check_in_guest_entry|rpc;rpc;rpc|20.5.4;20.5.5;20.5.6|OK
venue.promoter|venue.create_promoter;venue.update_promoter|rpc;rpc|20.9.1;20.9.2|OK
venue.promoter_link|venue.create_promoter_link;venue.set_promoter_link_status|rpc;rpc|20.9.3;20.9.4|OK
venue.attribution|venue.resolve_order_attribution|helper|17.14|OK
venue.promoter_code|venue.create_promoter_code;venue.create_promoter_codes_bulk;venue.set_promoter_code_status;venue.set_promoter_code_window|rpc;rpc;rpc;rpc|17.15|OK
venue.promoter_code_scope|venue.create_promoter_code;venue.create_promoter_codes_bulk;venue.set_promoter_code_scope|rpc;rpc;rpc|17.15|OK
venue.attribution_review|venue.review_attribution_flag|rpc|17.18|OK
venue.door_manifest|venue.open_door_manifest;venue.close_door_manifest;venue.append_door_manifest_delta|rpc;rpc;helper|17.10;17.11;17.13|DIVERGENT
venue.door_manifest_entry|venue.open_door_manifest|rpc|17.10|DIVERGENT
venue.door_manifest_delta|venue.append_door_manifest_delta|helper|17.13|OK
venue.holder_mix_snapshot|venue.refresh_holder_mix;venue.unpublish_holder_mix;venue.unpublish_all_holder_mix|cron;rpc;rpc|17.20|DIVERGENT
venue.holder_mix_bucket|venue.refresh_holder_mix|cron|17.20|OK
venue.export_job|venue.request_export;venue.build_export_rows;venue.finalize_export;venue.revoke_export;venue.sweep_expired_exports;venue.claim_artifacts_for_purge;venue.confirm_artifact_purged;venue.reconcile_export_orphans|rpc;helper;helper;rpc;cron;helper;helper;helper|17.22|OK
market.listing_native|market.create_listing;market.cancel_listing;market.respond_offer;market.on_door_freeze_engaged;catalog.cancel_event|rpc;rpc;rpc;helper;rpc|20.8.1;20.8.2;20.8.6;17.10;4.4|DIVERGENT
market.auction|market.create_auction;market.place_bid;market.cancel_listing;catalog.cancel_event|rpc;rpc;rpc;rpc|20.8.3;20.8.4;20.8.2;4.4|MISSING_CONTRACT
market.offer|market.make_offer;market.respond_offer;market.cancel_listing|rpc;rpc;rpc|20.8.5;20.8.6;20.8.2|MISSING_CONTRACT
market.market_sale|kernel.transfer_ticket_ownership;market.respond_offer;market.sweep_paid_pending_sales;market.on_atom_voided|rpc;rpc;cron;helper|7.2;20.8.6;12.3;20.11.3|MISSING_CONTRACT
market.p2p_transfer|market.create_p2p_transfer;market.accept_p2p_transfer;market.cancel_p2p_transfer;market.sweep_expired_p2p_transfers;market.on_door_freeze_engaged;catalog.cancel_event|rpc;rpc;rpc;cron;helper;rpc|8.1;8.2;8.3;12.2;17.10;4.4|DIVERGENT
market.bid|market.place_bid|rpc|20.8.4|MISSING_CONTRACT
notify.notification|notify.enqueue;notify.drain_outbox;notify.mark_read;notify.mark_all_read;notify.dismiss|helper;cron;rpc;rpc;rpc|17.24|DIVERGENT
notify.preference|notify.set_preference|rpc|17.24|OK
notify.announcement|notify.draft_announcement;notify.approve_announcement;notify.cancel_announcement;notify.revoke_announcement|rpc;rpc;rpc;rpc|17.24|OK
notify.notification_type|-|-|SEED-ONLY|OK
notify.template|-|-|SEED-ONLY|OK
notify.delivery|notify.drain_outbox;notify.claim_deliveries;notify.record_delivery_result|cron;helper;helper|17.24;17.25|OK
notify.outbox|notify.emit_event;notify.drain_outbox|helper;cron|17.24|OK
notify.schedule|notify.sweep_scheduled|cron|17.24|MISSING_CONTRACT
notify.identity_channel_state|-|-|NONE-no-writer-anywhere|MISSING_CONTRACT
public.payments|public.delete_account_cleanup;CATEGORY:frozen-stripe-webhook|helper;webhook|NONE-uncontracted|MISSING_CONTRACT
public.listings|public.delete_account_cleanup|helper|NONE-uncontracted|MISSING_CONTRACT
public.transfers|public.delete_account_cleanup|helper|NONE-uncontracted|MISSING_CONTRACT
public.push_tokens|notify.register_push_token;notify.revoke_push_token;notify.record_delivery_result|rpc;rpc;helper|17.24;17.25|OK
public.rate_limits|public.check_rate_limit|helper|17.17|OK
```

## THE 18 MISSING CONTRACTS — the list that fails readiness

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

## CONTRACTED BUT NEVER BUILT — 4 unconditional

`kernel.mark_refund_state` (`085` per the schema spec; the plan omits it; `S-24` filed and unapplied) ·
`venue.unpublish_holder_mix` · `venue.unpublish_all_holder_mix` · `venue.reconcile_holder_mix`.
Plus **17 conditional** `notify.*` writers, deliberately deferred by `COND-B`.
