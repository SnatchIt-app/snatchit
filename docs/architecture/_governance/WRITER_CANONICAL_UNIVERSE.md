# The Canonical Writer Universe — re-derived from first principles, 2026-08-29

**Phase A of the writer-parity convergence pass.** Source of truth: `PHASE_2_RPC_FUNCTION_CONTRACTS.md`
(owner, `OR-7`), enumerated through the registry fence in `WRITER_REGISTRY_PARITY_SPEC.md`, which checks
**H**/**H2** of `scripts/precedence_gate.py` parse. **Counts are derived from the enumeration below and
from nothing else.**

```
TABLES IN TRUE SCOPE      82
UNIQUE WRITER FUNCTIONS   156     (one is a named placeholder: kernel.UNNAMED_BEFORE_DELETE_TRIGGER)
WRITER ENTRIES            235
```

**The previously derived inventory (80 / 152 / 223) did not survive re-derivation** — the two-table scope
defect (`RC-1`) accounted for the table gap; folding `kernel.tickets` (11 entries), `kernel.payment_native`
(2), the two `C110` hooks now contracted at §17.10a, and removing `kernel.admin_refund` from `venue.order`
(`F-3`) produces the figures above. **Do not carry them; recount from the fence.**

## Scope rule

RLS §4's class→posture table sets `INS/UPD default = R` for all six classes — **every Phase-2 table is an
RPC-only / server-written authoritative table** — plus the three live `public.*` tables that
`public.delete_account_cleanup` writes and `public.push_tokens`/`public.rate_limits`. Writer categories
included per the ruling: SECURITY DEFINER RPCs, ordinary/definer helpers, **trigger functions** (§20.0a's
exclusion repaired 2026-08-29 — a trigger that writes is a writer; a raising guard is not), cron/sweep
functions, webhook-facing functions, server-only functions.

## Trigger writers — stated explicitly because their exclusion was the root cause (`RC-3`)

| trigger function | writes | attached (plan §8 Triggers rows) | status |
|---|---|---|---|
| `kernel.set_updated_at` | `updated_at` on every MUT table | `077 078 081 082 085 087 088 091` (per-package "on the MUT tables") | **NO CONTRACT (`R-35`) — and REQUIRED-NOT-ATTACHED on `kernel.tickets` (`079` attaches raise_append_only and nothing else, while schema global conventions require the maintainer wherever `updated_at` exists)** |
| `kernel.raise_append_only` | **nothing** — raises | AO tables across `077`–`090` | correctly NOT a writer |
| `catalog.tg_door_open_at_is_ledger_head` | **nothing** — raises | `086` | correctly NOT a writer |
| `kernel.tg_custody_head_is_ledger_tail` | **nothing** — raises | filed (schema §1.5.2 class) | correctly NOT a writer |
| *(unnamed)* demographic-erasure tombstone | `kernel.identity_demographic_erasure` | **NOWHERE — the plan's `077` row actively denies it** while four documents require it (`J-12`) | **MISSING CONTRACT + MISSING ATTACHMENT + PACKAGE GAP** |

## The universe — one row per writer entry

**Column limits, stated so this table cannot over-claim:** WRITE KIND is derived by a coarse verb rule
(create/issue/mint/open→INSERT · sweep/mark/set/close/approve→TRANSITION · engines/hooks→MULTIPLE) — it is
a classification aid, not a contract; the contract section governs. BUILD PACKAGE is exact where the pass
established it (the named set) and otherwise points at plan §8 — **per-entry package resolution for the
remainder is owed and is NOT claimed here.** DERIVED SITES are document-grain: RLS §5 + §7–§16 (every
Write-RPCs line now restates this registry and says so inline), schema §1–§3 per-table rows, plan §8 —
all repaired to agreement 2026-08-29; the registry is canonical and derived lists must agree exactly or point.

| table | function | write kind | fn kind | contract | build package | status |
|---|---|---|---|---|---|---|
| `kernel.identity_ext` | `kernel.upsert_identity_ext` | INSERT | rpc | §20.1.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.organization` | `kernel.create_organization` | INSERT | rpc | §2.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.organization` | `kernel.set_org_status` | TRANSITION | rpc | §20.1.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.organization` | `kernel.update_organization` | TRANSITION | rpc | §20.1.5 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.organization` | `kernel.set_org_payout_destination` | TRANSITION | rpc | §17.7 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.organization` | `kernel.set_org_connect_ref` | TRANSITION | rpc | §20.1.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.org_member` | `kernel.create_organization` | INSERT | rpc | §2.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.org_member` | `kernel.accept_org_invite` | TRANSITION | rpc | §2.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.org_member` | `kernel.change_org_role` | TRANSITION | rpc | §2.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.org_member` | `kernel.remove_org_member` | TRANSITION | rpc | §2.5 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.org_invite` | `kernel.invite_org_member` | INSERT | rpc | §2.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `kernel.org_invite` | `kernel.accept_org_invite` | TRANSITION | rpc | §2.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `kernel.platform_role` | `kernel.grant_platform_role` | INSERT | rpc | §20.1.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.platform_role` | `kernel.revoke_platform_role` | TRANSITION | rpc | §20.1.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.tickets` | `kernel.issue_ticket_atoms` | INSERT | helper | §7.1 | 081 | built/scheduled · OK |
| `kernel.tickets` | `kernel.transfer_ticket_ownership` | MULTIPLE | helper | §7.2 | 081 | built/scheduled · OK |
| `kernel.tickets` | `kernel.void_ticket_atom` | TRANSITION | helper | §7.3 | 085 | built/scheduled · OK |
| `kernel.tickets` | `kernel.lock_ticket` | TRANSITION | helper | §7.4 | 079 | built/scheduled · OK |
| `kernel.tickets` | `kernel.unlock_ticket` | TRANSITION | helper | §7.4 | 079 | built/scheduled · OK |
| `kernel.tickets` | `kernel.mark_ticket_scanned` | TRANSITION | helper | §7.5 | 079 | built/scheduled · OK |
| `kernel.tickets` | `kernel.request_order_refund` | INSERT | rpc | §17.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.tickets` | `kernel.approve_refund_request` | TRANSITION | rpc | §17.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.tickets` | `kernel.cancel_refund_request` | TRANSITION | rpc | §17.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.tickets` | `kernel.sweep_expired_refund_requests` | TRANSITION | cron | §17.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.tickets` | `kernel.sweep_expired_ticket_atoms` | TRANSITION | cron | §12.5 | 079 | built/scheduled · OK |
| `kernel.payment_native` | `venue.finalize_primary_order` | TRANSITION | webhook | §6.3 | 085 (C111) | built/scheduled · MISSING_CONTRACT |
| `kernel.payment_native` | `kernel.transfer_ticket_ownership` | MULTIPLE | helper | §7.2 | 081 | built/scheduled · MISSING_CONTRACT |
| `kernel.ticket_ownership_log` | `kernel.issue_ticket_atoms` | INSERT | rpc | §7.1 | 081 | built/scheduled · OK |
| `kernel.ticket_ownership_log` | `kernel.transfer_ticket_ownership` | MULTIPLE | rpc | §7.2 | 081 | built/scheduled · OK |
| `kernel.ticket_ownership_log` | `kernel.void_ticket_atom` | TRANSITION | rpc | §7.3 | 085 | built/scheduled · OK |
| `kernel.signing_key` | `kernel.provision_signing_key` | INSERT | rpc | §20.7.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.signing_key` | `kernel.rotate_signing_key` | TRANSITION | rpc | §20.7.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.signing_key` | `kernel.revoke_signing_key` | TRANSITION | rpc | §20.7.5 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.payout` | `kernel.close_settlement` | TRANSITION | rpc | §10.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `kernel.payout` | `kernel.pay_promoter_commission` | MULTIPLE | helper | §20.7.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `kernel.payout` | `kernel.request_org_payout` | INSERT | rpc | §10.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `kernel.payout` | `kernel.hold_payout` | TRANSITION | rpc | §11.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `kernel.payout` | `kernel.release_payout` | TRANSITION | rpc | §11.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `kernel.payout` | `kernel.mark_payout_transfer_state` | TRANSITION | webhook | §20.7.6 | 085 | built/scheduled · MISSING_CONTRACT |
| `kernel.refund` | `kernel.refund_primary_order` | MULTIPLE | rpc | §11.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.refund` | `kernel.admin_refund` | MULTIPLE | rpc | §20.7.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.refund` | `market.sweep_paid_pending_sales` | TRANSITION | cron | §12.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.refund` | `kernel.mark_refund_state` | TRANSITION | webhook | §20.7.7 | 085 (S-24 applied 2026-08-29; registry half S-25 owed) | built/scheduled · OK |
| `kernel.reserve` | *(no writer — NONE-wired-in-MVP)* | — | — | — | — | OK |
| `kernel.admin_audit` | `kernel.record_money_denial` | INSERT | rpc | §17.9 | 085 | built/scheduled · OK |
| `kernel.admin_audit` | `CATEGORY:every-privileged-RPC-in-txn` | — | rpc | §0.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.approval_request` | `kernel.request_order_refund` | INSERT | rpc | §17.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.approval_request` | `kernel.approve_refund_request` | TRANSITION | rpc | §17.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.approval_request` | `kernel.cancel_refund_request` | TRANSITION | rpc | §17.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.approval_request` | `kernel.sweep_expired_refund_requests` | TRANSITION | cron | §17.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.approval_request` | `kernel.request_org_payout` | INSERT | rpc | §10.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.approval_request` | `catalog.set_platform_config` | TRANSITION | rpc | §20.2.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.approval_request` | `kernel.grant_platform_role` | INSERT | rpc | §20.1.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.approval_request` | `kernel.revoke_platform_role` | TRANSITION | rpc | §20.1.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.identity_contact_pref` | `kernel.set_my_contact_prefs` | TRANSITION | rpc | §17.21 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.identity_contact_pref_event` | `kernel.set_my_contact_prefs` | TRANSITION | rpc | §17.21 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.org_contact_consent` | `kernel.grant_org_contact_consent` | INSERT | rpc | §17.21 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.org_contact_consent` | `kernel.withdraw_org_contact_consent` | TRANSITION | rpc | §17.21 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.org_contact_consent_event` | `kernel.grant_org_contact_consent` | INSERT | rpc | §17.21 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.org_contact_consent_event` | `kernel.withdraw_org_contact_consent` | TRANSITION | rpc | §17.21 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.org_customer_key` | *(no writer — NONE-no-writer-anywhere)* | — | — | — | — | MISSING_CONTRACT |
| `kernel.identity_demographic` | `kernel.set_my_demographics` | TRANSITION | rpc | §17.20 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.identity_demographic` | `kernel.clear_my_demographics` | TRANSITION | rpc | §17.20 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.identity_demographic_erasure` | `kernel.UNNAMED_BEFORE_DELETE_TRIGGER` | MULTIPLE | trigger | §17.20 | plan §8 (per-entry package resolution owed — see limits) | **NOT BUILT** · MISSING_CONTRACT |
| `kernel.door_freeze_override` | `kernel.grant_door_freeze_override` | INSERT | rpc | §17.11 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.door_freeze_override` | `kernel.revoke_door_freeze_override` | TRANSITION | rpc | §17.11 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.wallet_pass` | `kernel.mint_wallet_pass` | INSERT | rpc | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.wallet_pass` | `kernel.revoke_wallet_pass` | TRANSITION | rpc | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.wallet_pass` | `kernel.supersede_wallet_passes_for_atom` | TRANSITION | helper | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.wallet_pass` | `kernel.touch_wallet_pass` | TRANSITION | helper | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.wallet_pass` | `kernel.sweep_wallet_pass_lifecycle` | TRANSITION | cron | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.wallet_pass_device` | `kernel.register_wallet_pass_device` | INSERT | helper | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.wallet_pass_device` | `kernel.unregister_wallet_pass_device` | TRANSITION | helper | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.wallet_pass_device` | `kernel.revoke_wallet_pass` | TRANSITION | rpc | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.wallet_pass_device` | `kernel.record_wallet_push_result` | INSERT | helper | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.pass_type_cert` | `kernel.provision_pass_type_cert` | INSERT | rpc | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.pass_type_cert` | `kernel.rotate_pass_type_cert` | TRANSITION | rpc | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.pass_type_cert` | `kernel.revoke_pass_type_cert` | TRANSITION | rpc | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.wallet_pass_push_log` | `kernel.record_wallet_push_result` | INSERT | helper | §17.23 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `kernel.org_money_policy` | *(no writer — CONDITIONAL-D-2)* | — | — | — | — | OK |
| `catalog.venue` | `catalog.create_venue` | INSERT | rpc | §3.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `catalog.venue` | `catalog.approve_venue` | TRANSITION | rpc | §3.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `catalog.venue` | `catalog.update_venue` | TRANSITION | rpc | §3.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `catalog.event` | `catalog.create_event` | INSERT | rpc | §4.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `catalog.event` | `catalog.publish_event` | TRANSITION | rpc | §4.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `catalog.event` | `catalog.cancel_event` | TRANSITION | rpc | §4.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `catalog.event` | `catalog.update_event` | TRANSITION | rpc | §20.2.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `catalog.event_session` | `catalog.create_event_session` | INSERT | rpc | §4.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `catalog.event_session` | `catalog.create_event` | INSERT | rpc | §4.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `catalog.event_session` | `catalog.update_event_session` | TRANSITION | rpc | §20.2.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `catalog.event_session` | `catalog.cancel_event` | TRANSITION | rpc | §4.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `catalog.event_session` | `catalog.engage_door_freeze` | TRANSITION | helper | §17.12 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `catalog.event_session` | `catalog.set_session_door_schedule` | TRANSITION | rpc | §20.6.5 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `catalog.platform_config` | `catalog.set_platform_config` | TRANSITION | rpc | §20.2.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `catalog.resale_policy` | `catalog.set_resale_policy` | TRANSITION | rpc | §20.2.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.ticket_type` | `venue.create_ticket_type` | INSERT | rpc | §5.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.ticket_type` | `venue.set_ticket_type_price` | TRANSITION | rpc | §20.3.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch` | `venue.create_inventory_batch` | INSERT | rpc | §5.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch` | `venue.reserve_primary_inventory` | MULTIPLE | rpc | §5.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch` | `venue.create_inventory_hold` | INSERT | rpc | §5.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch` | `venue.release_inventory_hold` | TRANSITION | rpc | §5.5 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch` | `venue.set_batch_capacity` | TRANSITION | rpc | §20.3.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch` | `venue.sweep_expired_inventory_holds` | TRANSITION | cron | §20.3.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch` | `venue.allocate_comp` | INSERT | rpc | §20.5.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch` | `venue.issue_comp` | INSERT | rpc | §20.5.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch` | `kernel.issue_ticket_atoms` | INSERT | rpc | §7.1 | 081 | built/scheduled · OK |
| `venue.inventory_batch` | `kernel.void_ticket_atom` | TRANSITION | rpc | §7.3 | 085 | built/scheduled · OK |
| `venue.inventory_batch` | `kernel.refund_primary_order` | MULTIPLE | rpc | §11.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch` | `kernel.admin_refund` | MULTIPLE | rpc | §20.7.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch_shard` | `venue.create_inventory_batch` | INSERT | rpc | §5.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch_shard` | `venue.reserve_primary_inventory` | MULTIPLE | rpc | §5.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch_shard` | `venue.create_inventory_hold` | INSERT | rpc | §5.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch_shard` | `venue.release_inventory_hold` | TRANSITION | rpc | §5.5 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch_shard` | `venue.set_batch_capacity` | TRANSITION | rpc | §20.3.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch_shard` | `venue.allocate_comp` | INSERT | rpc | §20.5.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch_shard` | `venue.issue_comp` | INSERT | rpc | §20.5.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_batch_shard` | `kernel.issue_ticket_atoms` | INSERT | rpc | §7.1 | 081 | built/scheduled · OK |
| `venue.inventory_batch_shard` | `kernel.void_ticket_atom` | TRANSITION | rpc | §7.3 | 085 | built/scheduled · OK |
| `venue.inventory_movement` | `venue.reserve_primary_inventory` | MULTIPLE | rpc | §5.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_movement` | `venue.release_inventory_hold` | TRANSITION | rpc | §5.5 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_movement` | `venue.set_batch_capacity` | TRANSITION | rpc | §20.3.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_movement` | `venue.allocate_comp` | INSERT | rpc | §20.5.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_movement` | `venue.issue_comp` | INSERT | rpc | §20.5.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_movement` | `venue.finalize_primary_order` | TRANSITION | rpc | §6.3 | 085 (C111) | built/scheduled · OK |
| `venue.inventory_movement` | `kernel.issue_ticket_atoms` | INSERT | rpc | §7.1 | 081 | built/scheduled · OK |
| `venue.inventory_movement` | `kernel.void_ticket_atom` | TRANSITION | rpc | §7.3 | 085 | built/scheduled · OK |
| `venue.inventory_hold` | `venue.reserve_primary_inventory` | MULTIPLE | rpc | §5.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_hold` | `venue.create_inventory_hold` | INSERT | rpc | §5.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_hold` | `venue.release_inventory_hold` | TRANSITION | rpc | §5.5 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_hold` | `venue.sweep_expired_inventory_holds` | TRANSITION | cron | §20.3.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.inventory_unit` | *(no writer — EXT-C42-DO-NOT-BUILD)* | — | — | — | — | OK |
| `venue.order` | `venue.create_primary_checkout` | INSERT | rpc | §6.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `venue.order` | `venue.finalize_primary_order` | TRANSITION | rpc | §6.3 | 085 (C111) | built/scheduled · MISSING_CONTRACT |
| `venue.order` | `venue.bind_order_attribution` | TRANSITION | rpc | §17.18 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `venue.order` | `kernel.refund_primary_order` | MULTIPLE | rpc | §11.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `venue.order_item` | `venue.create_primary_checkout` | INSERT | rpc | §6.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.staff_role` | `venue.grant_staff_role` | INSERT | rpc | §20.4.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.staff_role` | `venue.revoke_staff_role` | TRANSITION | rpc | §20.4.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_pin` | `venue.create_door_pin` | INSERT | rpc | §9.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_pin` | `venue.revoke_door_pin` | TRANSITION | rpc | §9.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_session` | `venue.mint_door_session` | INSERT | rpc | §9.6 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_session` | `venue.revoke_door_session` | TRANSITION | rpc | §9.7 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_session` | `venue.sweep_expired_door_sessions` | TRANSITION | cron | §9.8 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_session` | `venue.revoke_door_pin` | TRANSITION | rpc | §9.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_session` | `venue.set_scan_device_status` | TRANSITION | rpc | §20.4.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_session` | `kernel.assert_door_session` | MULTIPLE | helper | §1.1d | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.scan_device` | `venue.register_scan_device` | INSERT | rpc | §20.4.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.scan_device` | `venue.sync_scan_device_manifest` | TRANSITION | rpc | §20.4.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.scan_device` | `venue.set_scan_device_status` | TRANSITION | rpc | §20.4.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.scan` | `venue.record_scan` | INSERT | rpc | §9.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.scan` | `venue.reconcile_offline_scans` | TRANSITION | rpc | §9.5 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.settlement` | `venue.open_settlement` | INSERT | rpc | §10.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.settlement` | `kernel.close_settlement` | TRANSITION | rpc | §10.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.settlement` | `venue.on_payout_settled` | MULTIPLE | helper | §20.11.5 | 085 stub → 087 | built/scheduled · OK |
| `venue.settlement_line` | `kernel.close_settlement` | TRANSITION | rpc | §10.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.settlement_line` | `kernel.pay_promoter_commission` | MULTIPLE | helper | §20.7.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.comp_allocation` | `venue.allocate_comp` | INSERT | rpc | §20.5.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.comp_allocation` | `venue.issue_comp` | INSERT | rpc | §20.5.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.guest_list` | `venue.create_guest_list` | INSERT | rpc | §20.5.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.guest_entry` | `venue.upsert_guest_entry` | INSERT | rpc | §20.5.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.guest_entry` | `venue.remove_guest_entry` | TRANSITION | rpc | §20.5.5 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.guest_entry` | `venue.check_in_guest_entry` | TRANSITION | rpc | §20.5.6 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.promoter` | `venue.create_promoter` | INSERT | rpc | §20.9.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.promoter` | `venue.update_promoter` | TRANSITION | rpc | §20.9.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.promoter_link` | `venue.create_promoter_link` | INSERT | rpc | §20.9.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.promoter_link` | `venue.set_promoter_link_status` | TRANSITION | rpc | §20.9.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.attribution` | `venue.resolve_order_attribution` | TRANSITION | helper | §17.14 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.promoter_code` | `venue.create_promoter_code` | INSERT | rpc | §17.15 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.promoter_code` | `venue.create_promoter_codes_bulk` | INSERT | rpc | §17.15 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.promoter_code` | `venue.set_promoter_code_status` | TRANSITION | rpc | §17.15 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.promoter_code` | `venue.set_promoter_code_window` | TRANSITION | rpc | §17.15 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.promoter_code_scope` | `venue.create_promoter_code` | INSERT | rpc | §17.15 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.promoter_code_scope` | `venue.create_promoter_codes_bulk` | INSERT | rpc | §17.15 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.promoter_code_scope` | `venue.set_promoter_code_scope` | TRANSITION | rpc | §17.15 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.attribution_review` | `venue.review_attribution_flag` | TRANSITION | rpc | §17.18 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_manifest` | `venue.open_door_manifest` | INSERT | rpc | §17.10 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_manifest` | `venue.close_door_manifest` | TRANSITION | rpc | §17.11 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_manifest` | `venue.append_door_manifest_delta` | INSERT | helper | §17.13 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_manifest_entry` | `venue.open_door_manifest` | INSERT | rpc | §17.10 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.door_manifest_delta` | `venue.append_door_manifest_delta` | INSERT | helper | §17.13 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.holder_mix_snapshot` | `venue.refresh_holder_mix` | TRANSITION | cron | §17.20 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.holder_mix_snapshot` | `venue.unpublish_holder_mix` | TRANSITION | rpc | §17.20 | plan §8 (per-entry package resolution owed — see limits) | **NOT BUILT** · OK |
| `venue.holder_mix_snapshot` | `venue.unpublish_all_holder_mix` | TRANSITION | rpc | §17.20 | plan §8 (per-entry package resolution owed — see limits) | **NOT BUILT** · OK |
| `venue.holder_mix_bucket` | `venue.refresh_holder_mix` | TRANSITION | cron | §17.20 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.export_job` | `venue.request_export` | INSERT | rpc | §17.22 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.export_job` | `venue.build_export_rows` | INSERT | helper | §17.22 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.export_job` | `venue.finalize_export` | TRANSITION | helper | §17.22 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.export_job` | `venue.revoke_export` | TRANSITION | rpc | §17.22 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.export_job` | `venue.sweep_expired_exports` | TRANSITION | cron | §17.22 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.export_job` | `venue.claim_artifacts_for_purge` | TRANSITION | helper | §17.22 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.export_job` | `venue.confirm_artifact_purged` | TRANSITION | helper | §17.22 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `venue.export_job` | `venue.reconcile_export_orphans` | TRANSITION | helper | §17.22 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `market.listing_native` | `market.create_listing` | INSERT | rpc | §20.8.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `market.listing_native` | `market.cancel_listing` | TRANSITION | rpc | §20.8.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `market.listing_native` | `market.respond_offer` | TRANSITION | rpc | §20.8.6 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `market.listing_native` | `market.on_door_freeze_engaged` | MULTIPLE | helper | §17.10 | 086 stub → 088 | built/scheduled · OK |
| `market.listing_native` | `catalog.cancel_event` | TRANSITION | rpc | §4.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `market.auction` | `market.create_auction` | INSERT | rpc | §20.8.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `market.auction` | `market.place_bid` | INSERT | rpc | §20.8.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `market.auction` | `market.cancel_listing` | TRANSITION | rpc | §20.8.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `market.auction` | `catalog.cancel_event` | TRANSITION | rpc | §4.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `market.offer` | `market.make_offer` | INSERT | rpc | §20.8.5 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `market.offer` | `market.respond_offer` | TRANSITION | rpc | §20.8.6 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `market.offer` | `market.cancel_listing` | TRANSITION | rpc | §20.8.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `market.market_sale` | `kernel.transfer_ticket_ownership` | MULTIPLE | rpc | §7.2 | 081 | built/scheduled · MISSING_CONTRACT |
| `market.market_sale` | `market.respond_offer` | TRANSITION | rpc | §20.8.6 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `market.market_sale` | `market.sweep_paid_pending_sales` | TRANSITION | cron | §12.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `market.market_sale` | `market.on_atom_voided` | MULTIPLE | helper | §20.11.3 | 085 stub → 088 | built/scheduled · MISSING_CONTRACT |
| `market.p2p_transfer` | `market.create_p2p_transfer` | INSERT | rpc | §8.1 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `market.p2p_transfer` | `market.accept_p2p_transfer` | TRANSITION | rpc | §8.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `market.p2p_transfer` | `market.cancel_p2p_transfer` | TRANSITION | rpc | §8.3 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `market.p2p_transfer` | `market.sweep_expired_p2p_transfers` | TRANSITION | cron | §12.2 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `market.p2p_transfer` | `market.on_door_freeze_engaged` | MULTIPLE | helper | §17.10 | 086 stub → 088 | built/scheduled · OK |
| `market.p2p_transfer` | `catalog.cancel_event` | TRANSITION | rpc | §4.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · OK |
| `market.bid` | `market.place_bid` | INSERT | rpc | §20.8.4 | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `notify.notification` | `notify.enqueue` | INSERT | helper | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.notification` | `notify.drain_outbox` | MULTIPLE | cron | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.notification` | `notify.mark_read` | TRANSITION | rpc | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.notification` | `notify.mark_all_read` | TRANSITION | rpc | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.notification` | `notify.dismiss` | TRANSITION | rpc | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.preference` | `notify.set_preference` | TRANSITION | rpc | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.announcement` | `notify.draft_announcement` | INSERT | rpc | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.announcement` | `notify.approve_announcement` | TRANSITION | rpc | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.announcement` | `notify.cancel_announcement` | TRANSITION | rpc | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.announcement` | `notify.revoke_announcement` | TRANSITION | rpc | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.notification_type` | *(no writer — SEED-ONLY)* | — | — | — | — | OK |
| `notify.template` | *(no writer — SEED-ONLY)* | — | — | — | — | OK |
| `notify.delivery` | `notify.drain_outbox` | MULTIPLE | cron | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.delivery` | `notify.claim_deliveries` | TRANSITION | helper | §17.25 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.delivery` | `notify.record_delivery_result` | INSERT | helper | §17.25 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.outbox` | `notify.emit_event` | INSERT | helper | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.outbox` | `notify.drain_outbox` | MULTIPLE | cron | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `notify.schedule` | `notify.sweep_scheduled` | TRANSITION | cron | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · MISSING_CONTRACT |
| `notify.identity_channel_state` | *(no writer — NONE-no-writer-anywhere)* | — | — | — | — | MISSING_CONTRACT |
| `public.payments` | `public.delete_account_cleanup` | MULTIPLE | helper | §NONE-uncontracted | LIVE (20260828041500, PR #28 pending) | built/scheduled · MISSING_CONTRACT |
| `public.payments` | `CATEGORY:frozen-stripe-webhook` | — | webhook | §NONE-uncontracted | plan §8 (per-entry package resolution owed — see limits) | built/scheduled · MISSING_CONTRACT |
| `public.listings` | `public.delete_account_cleanup` | MULTIPLE | helper | §NONE-uncontracted | LIVE (20260828041500, PR #28 pending) | built/scheduled · MISSING_CONTRACT |
| `public.transfers` | `public.delete_account_cleanup` | MULTIPLE | helper | §NONE-uncontracted | LIVE (20260828041500, PR #28 pending) | built/scheduled · MISSING_CONTRACT |
| `public.push_tokens` | `notify.register_push_token` | INSERT | rpc | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `public.push_tokens` | `notify.revoke_push_token` | TRANSITION | rpc | §17.24 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `public.push_tokens` | `notify.record_delivery_result` | INSERT | helper | §17.25 | plan §8 (per-entry package resolution owed — see limits) | conditional (COND-B/OR-5) · OK |
| `public.rate_limits` | `public.check_rate_limit` | MULTIPLE | helper | §17.17 | LIVE (005) | built/scheduled · OK |

## What fails, exactly (derived from the STATUS column)

- **16 MISSING_CONTRACT rows** — the gate errors; enumerated in `WRITER_REGISTRY_PARITY_SPEC.md`.
- **3 NOT-BUILT writers** — `venue.unpublish_holder_mix` · `venue.unpublish_all_holder_mix` · the unnamed
  erasure trigger. *(`kernel.mark_refund_state` closed 2026-08-29 — `S-24` applied to plan `085`; `S-25` owed.)*
- **0 DIVERGENT rows** — the transcription debt of `RC-2` is repaid in full.
