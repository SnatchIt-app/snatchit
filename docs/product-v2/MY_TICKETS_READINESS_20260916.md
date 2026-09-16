# My Tickets readiness map (C, 2026-09-16)

**Report only.** Nothing here enables issuance, scanning or native ticket data. Source of truth: the combined stack commit `9bef640` plus the release records it carries; every claim was read from source in a sweep on 2026-09-16 (file:line relative to the repo root). Production facts come from A's release records, never from a production read.

## 0. The frame

| Fact | Evidence |
|---|---|
| Production ledger 135 rows; numeric tip 120 | `docs/release/CONVERGENCE_135_REPORT.md:35`; `docs/release/MIGRATION_NUMBER_REGISTRY.md:9-11` |
| `20260909000000_kernel_my_tickets_read` (the Tickets RPC) is **absent from production**, applied to the sandbox only | `CONVERGENCE_135_REPORT.md:388-395`; `docs/product-v2/RC_TICKETS_RPC_AND_FILTER_SHEET.md:74-79` |
| `kernel.signing_key` 0 rows, `kernel.tickets` 0 rows, all three native flags `false` | `CONVERGENCE_135_REPORT.md:390-393`; `docs/release/SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md:41-43` |
| 11 edge functions deployed; `credential-sign`, `door-manifest`, `door-session` authored dark; `primary-checkout`, `refund-execute`, `payout-execute`, `connect-onboarding` never deployed | `.github/workflows/ci.yml:1618-1656` |
| KMS/ES256 trust-root ceremony: NO-GO, not executed; PFA-18C bootstrap NOT READY | `docs/release/PHASE2_PRODUCTION_KMS_SIGNING_CEREMONY_EXECUTION.md:1-20`; `PHASE2_PFA18C_BOOTSTRAP_READINESS_REPORT.md:17-19` |
| Sandbox after the B2 window: ledger 141 (131–135 + `20260916000000`), edges v5/v4/v4, Vault `project_url` only; no push service key | A, 2026-09-16 04:57Z (backlog record) |

Two paths exist and must be kept apart: the **legacy marketplace** (a `listings` row describes a ticket the seller holds on a third-party platform; delivery happens outside the app; the buyer confirms) and the **Phase-2 native path** (`kernel.tickets` atoms, signed credentials, door scanning), which is authored and dark.

## 1. Stage by stage

### 1.1 Ticket creation / issuance
- **Implemented (legacy, live):** listing creation `app/(tabs)/create.tsx` → `src/screens/CreateListingScreen.tsx` (`can_create_listing` `:375`, `get_my_profile` `:440`, insert into `public.listings` `:509`). No ticket object is created.
- **Implemented (native, dark):** `kernel.issue_ticket_atoms` (`083:440`; writes `kernel.tickets`, ownership log, inventory, door-manifest delta `:557-579`); upstream `venue.reserve_primary_inventory` (`081:527`), `venue.create_primary_checkout` (`082:305`), `venue.finalize_primary_order` (`085:1881`), the 093 primary-ticketing package.
- **Sandbox-only:** nothing on this stage (the window excluded any `kernel.tickets` write, `SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md:19-22`).
- **Untested:** the mint with the flag genuinely on — every pgTAP flip is inside `BEGIN…ROLLBACK` (`147:172-182`, `145:391-406`, `149:196-197`).
- **Missing:** any client for native issuance (no reference to `primary-checkout`/`create_primary_checkout`/`reserve_primary_inventory` under `app/` or `src/`); `primary-checkout` edge never deployed (`ci.yml:1648`); the `venue` schema is not exposed over PostgREST (`SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md:47`).
- **Gates (exact):** `feature.native_issuance_enabled=false` (`078:1522`; read `083:494-501`, `081:581-587`, `093:4933`, `:5663`); an ACTIVE `kernel.signing_key` for the scope, never auto-created (`083:514-530`); `provision_signing_key`/`rotate_signing_key` raise (`083:375-394`; `110:17-18`); `inventory.per_user_active_hold_max=null` ⇒ `hold_cap_exceeded` (`093:5527`, `081:615-626`); `inventory.hold_ttl_interval=null` ⇒ `hold_ttl_unset` (`093:5544`); `fee.buyer_service_bps=null` ⇒ `service_fee_unset` (`093:5701`, `:4105`); `ticket.expiry_grace=null` — "OWNER STOP (D2)" (`093:5641`); `110_signing_key_insert_guard` (`110:20-40`).

### 1.2 Delivery to the buyer
- **Implemented (legacy, live):** `public.transfers` written by the service role only (`002:106-112`; via `settle_verified_payment`, `20260906110000`); states `pending|seller_sent|buyer_confirmed|disputed|expired` (`002:49-63`, client adds `auto_released` `src/lib/transfer/transferState.ts:23-28`); seller screen `app/transfer/send/[id].tsx` (evidence upload, `mark_transfer_sent`); buyer screen `app/transfer/receive/[id].tsx` (`mark_transfer_viewed`, delivery info, `confirm-and-release`, `buyer_dispute_transfer`). Tickets never enter the app (`src/lib/platformInstructions.ts:267-270,486-500`).
- **Implemented (native, dark):** `kernel.transfer_ticket_ownership` (`088:597-609`, service_role only `:1858`); `kernel.get_ticket_signing_context` (`102:150-225`); `credential-sign` edge signs ES256 via KMS and self-verifies (`credential-sign/index.ts:26-37`); wallet minting parked fail-closed (`083:597-620`), `wallet.apple.enabled=false` (`078:1525`).
- **Sandbox-only:** none.
- **Untested:** live `credential-sign` ("mocked rehearsal only … requires the ceremony", `PHASE2_PFA18C_DARK_PRECEREMONY_AUDIT.md:160`).
- **Missing:** any app surface that consumes a credential (`app/(tabs)/tickets.tsx:11-12`; guarded by `tests/tickets.test.ts:178-182`); a `wallet_pass_available` producer (`POST_FREEZE_AMENDMENTS.md:2520`).
- **Gates:** `credential-sign` dark, `KMS_PROVIDER` defaults to `UnconfiguredKmsSigner` (`credential-sign/index.ts:12,17-25`); 0 signing keys ⇒ `signing_key_unavailable` (`102:199-206`).

### 1.3 Transfer between users / receiving
- **Implemented (legacy, live):** RLS buyer/seller select only, no client insert/update (`002:96-112`); entry points `app/(tabs)/bids.tsx:343`, `app/my-listings.tsx:257`, `ListingDetailScreen.tsx:1176,1181`, `CheckoutNative.tsx:1050`, push routing `NativeAppShell.native.tsx:240-246`; web mirrors under `web/src/app/transfer/*`; expiry via `enforce-transfer-expiry` (deployed).
- **Implemented (native, dark, structurally blocked):** `market.create_p2p_transfer` ends in an unconditional raise `p2p_ttl_unavailable` (`088:1422-1424`); `market.accept_p2p_transfer` (`088:1437`) has no ratified handle resolver (E-100) and refuses priced acceptance (E-101) (`088:1432-1436`); `market.*` not exposed over PostgREST.
- **Sandbox-only:** none. **Untested:** native accept/decline only in rolled-back pgTAP (`153:538-581`).
- **Missing:** any native transfer UI (`tests/transfer-state.test.ts:80` asserts the screens never query `kernel.tickets`); a p2p TTL key.
- **Gate:** `feature.native_resale_enabled=false` (`078:1524`; read `088:246,958,1100,1167,1262`).

### 1.4 The Tickets tab
- **Implemented (shipped in Build 17 and on the stack):** `app/(tabs)/tickets.tsx` calls exactly `supabase.rpc('get_my_tickets')` (`src/lib/tickets/api.ts:25-31`); the RPC returns 17 columns, owner-scoped, three stable vocabularies, data-minimised (`20260909000000:57-64,100-177`); Upcoming/Past `SectionList` with `TicketEventGroup` cards, **non-tappable by design**; states loading / offline / error (with retry, auto-retry on reconnect) / empty-as-success ("No tickets yet"); auth errors route to sign-in (`src/lib/tickets/ticketState.ts:157-161`); quiet refresh keeps rows on a failed refresh; fifth nav destination (`src/lib/nav/navItems.ts:52`). `DEV_TICKET_FIXTURES` (8 rows, `src/lib/tickets/fixtures.ts`) are `__DEV__`-only and compiled out of release builds (`PRODUCTION_RELEASE_PACKAGE.md:2473-2474`).
- **Sandbox-only:** the only real `200 []` ever returned to the tab is the sandbox (`CONVERGENCE_135_REPORT.md:353-361`).
- **Untested:** the **populated** state, excluded by ruling — it needs a `kernel.tickets` row, which the flag does not prevent via a direct fixture insert (`SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md:117-125`); carried open as CFT-801 (`RELEASE_PACKET_20260918.md:16,73`).
- **Missing:** ticket detail, Entry Pass / QR, Add to Apple Wallet, ownership history, Transfer/Sell actions — specified (`PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md:196-233`), none built; no QR/barcode/PassKit dependency in `package.json`.
- **Production today:** the RPC does not exist, so production renders the **error** state, not the empty state (`RC_TICKETS_RPC_AND_FILTER_SHEET.md:74-79`).

### 1.5 Event-day display and offline behaviour
- **Implemented:** offline classification (`src/hooks/useNetworkStatus.ts:11-31`, `src/lib/ui/loadState.ts:27-30`), `ScreenState` auto-retry on reconnect (`src/components/ScreenState.tsx:40-47`), offline copy.
- **Sandbox-only:** n/a. **Untested:** offline Tickets on a device against the real RPC (source guards only: `tests/state-views.test.ts`, `tests/quiet-refresh.test.ts`).
- **Missing — the largest gap in the stage:** **no caching of tickets or credentials at all** (the only local stores are the auth session and the push device secret); offline shows the offline state, not cached tickets, contradicting the spec's "offline: show cached tickets" (`PHASE_2_REACT_NATIVE_PRODUCT_SPEC.md:530`); no ticket detail, so no offline detail; the app never fetches or caches a signed token (by design it never mints one, `:54`).

### 1.6 Notifications relevant to tickets
- **Implemented (legacy, live where the Vault key exists):** `transfer_created` → seller "Action needed: send the tickets", buyer "Add your transfer info" (if delivery info missing); `tickets_marked_sent` → buyer "Tickets sent — confirm once received" (`notify-transfer/index.ts:137-167`), idempotent on `(transfer_id, event_type)`. No push for `buyer_confirmed`, `auto_released` (the cron sends its own), `disputed` (the report edge does).
- **Native (dark):** `ownership_changed` has a producer (`088:726`); `ticket_ready` has **no emitter anywhere** (`primary_issuance_audit.md:36`; `POST_FREEZE_AMENDMENTS.md:2520`); `wallet_pass_available` producer would be the undeployed `credential-sign`; `venue.finalize_primary_order` emits nothing. Dispatch parked (`092:1192-1195`; `notify.delivery_lease_interval=null` `092:1187-1189`).
- **Sandbox:** no push can leave the sandbox without the deferred service key (owner decision 2026-09-16). See `NOTIFICATION_INVENTORY_AND_GAPS.md` for the full matrix.

### 1.7 Scanning handoff / door
- **Implemented (all dark):** the 086 substrate (door PINs, manifests, sessions, `record_scan`, `validate_ticket_online`, `reconcile_offline_scans`) and the 104–114 door chain, applied dark through 120; 121 and 125 unapplied; `door-session` and `door-manifest` edges authored, not deployed; `OFFLINE-VERIFY-v1` in `supabase/functions/_shared/offline-verify.ts`.
- **Missing:** a scanner client — none in this repository ("NOT claimed implemented", `docs/phase2/SCANNER_VERIFIER_CONTRACT.md:3-5`); a trust root; deployed door edges.
- **Gates before a scan can validate:** `feature.native_scanning_enabled=true` (`086:1075-1080`; seeded false `078:1523`); a `kernel.signing_key` row via the ceremony §6.1 INSERT only (`110:29-35`); the KMS ceremony (NO-GO); door edges deployed with `KMS_PROVIDER=aws`; a conforming scanner passing the golden fixtures (`tests/fixtures/scanner-contract-v1.json`).

## 2. Exact gates before **populated Tickets** can be enabled

Two different questions, kept apart.

### 2.1 Sandbox verification of a populated Tickets tab
What must be true to see real ticket rows on the handset against the sandbox:
1. **Build:** any build carrying the shipped Tickets tab — Build 17 (`aabe029`) already does; the combined b2 candidate (tag pending the owner's inclusion decisions on `8dc4cec` / `a609cbc`) does too. **No new client code is needed for the list itself.**
2. **Migration on the sandbox:** `20260909000000_kernel_my_tickets_read` — present (applied 2026-09-09, ledger 129; still present at ledger 141).
3. **A `kernel.tickets` row owned by the DV buyer.** By ruling this is excluded from the acceptance window because the only honest producer is the issuance path, and a direct fixture insert bypasses the flag (`SANDBOX_ACCEPTANCE_WINDOW_MANIFEST.md:117-125`). Options, both **owner decisions**: (a) an explicitly authorised, recorded fixture insert into `kernel.tickets` (+ `catalog.event_session`/`catalog.event`/`catalog.venue`/`venue.ticket_type` rows the RPC joins, `20260909000000:172-176`) for the DV buyer, reverted after the row; or (b) wait for the native issuance path (§2.2), which is far away.
4. **Device rows:** CFT-801 (populated list: Upcoming/Past grouping, quantity, ownership × fulfillment rows, large text, VoiceOver, offline with rows cached — the last of which will FAIL today by design, since nothing caches).
5. **No edge function** is involved in reading the list.

### 2.2 Production availability of populated Tickets
Everything in §2.1 plus, in order of hardness:
1. **Migration `20260909000000` applied to production** — owner-gated apply (AUTODEPLOY-1 rules; it is in the candidate's migration set). Until then production shows the error state on the tab.
2. **The native issuance chain live**, which is the only legitimate producer of rows: `feature.native_issuance_enabled` flipped by audited runtime config (a single `platform_admin` via `catalog.set_platform_config`, `078:1048-1092`; never a migration); the four null config stops set (`inventory.per_user_active_hold_max`, `inventory.hold_ttl_interval`, `fee.buyer_service_bps`, `ticket.expiry_grace`); a signing key from the executed KMS ceremony (NO-GO today); `primary-checkout` deployed (never deployed); the `venue` schema exposed or public wrappers added (A's contract); **a client for primary checkout that does not exist**.
3. **Ticket detail / Entry Pass / Wallet / offline cache** — new client work (§3), each needing its own contract from A (`20260909000000:66-67`: "a SEPARATE future contract").

### 2.3 Feature gates, complete list (seeded values; flips only by audited runtime config)
`feature.native_issuance_enabled=false` (`078:1522`) · `feature.native_scanning_enabled=false` (`078:1523`) · `feature.native_resale_enabled=false` (`078:1524`) · `wallet.apple.enabled=false` (`078:1525`) · `credential.app_ttl_interval="4 hours"` (`078:1530`) · `ticket.expiry_grace=null` (`093:5641`) · `inventory.per_user_active_hold_max=null` (`093:5527`) · `inventory.hold_ttl_interval=null` (`093:5544`) · `fee.buyer_service_bps=null` (`093:5701`) · `notify.delivery_lease_interval=null` (`092:1187`) · `signing.monitor_enabled=false` (`099:75`) · `refund.executor_enabled=false` / `payout.executor_enabled=false` (`099:221-222`). Dual control covers `refund.% payout.% authn.% comp.% wallet.% credential.% door.session_%` (`078:1145-1147`); the `feature.*` flags are not in that set.

### 2.4 Edge functions relevant to tickets
Deployed: `stripe-webhook`, `create-payment-intent`, `confirm-payment`, `confirm-and-release`, `enforce-transfer-expiry`, `notify-transfer`, `notify-report`, `send-push`, `auto-finalize-auctions`. Dark/authored: `credential-sign`, `door-manifest`, `door-session`. Never deployed: `primary-checkout`, `refund-execute`, `payout-execute`, `connect-onboarding`.

## 3. Client work that would be new (C's lane; none started, none authorised)
| ID | Item | Depends on |
|---|---|---|
| CFT-801 | Populated Tickets device rows (list, grouping, large text, VoiceOver) | a `kernel.tickets` row for the DV buyer (owner decision §2.1.3) |
| CFT-811 | Ticket detail screen (ownership × fulfillment, history) | A: detail read contract |
| CFT-812 | Entry Pass / QR view with freshness, brightness, live-valid indicator | A: credential contract; `credential-sign` live; a QR renderer dependency |
| CFT-813 | Offline cache of the list and of a signed token (spec `:530-532`) | A: cache/TTL contract (`credential.app_ttl_interval`) |
| CFT-814 | Add to Apple Wallet | `wallet.apple.enabled`, PassKit dependency, A's wallet contract |
| CFT-815 | Transfer / Sell actions from a ticket | native resale contract (blocked: `088:1422`) |
| CFT-816 | `ticket_ready` / `ownership_changed` push handling and routing | a producer for `ticket_ready`; dispatch un-parked |

## 4. Evidence limits
Source sweep of `9bef640` and the release records; no environment read. Docs with recorded conflicts against source: RN spec tap/Entry Pass (`:196-206`) vs the non-tappable card; RN spec offline cache (`:530`) vs no caching; RN spec direct `kernel.tickets` read (`:200-201`) vs `get_my_tickets`; `primary_issuance_audit.md:57,69,73` stale on file existence (deployment claims still hold); `PHASE_11_TICKETS_REPORT.md:14` cites migration 110 for the RPC (renumbered to `20260909000000`).
