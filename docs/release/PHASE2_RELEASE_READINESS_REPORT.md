# PHASE-2 PRODUCTION READINESS — release-candidate report (2026-09-02)

**Verdict: RELEASE CANDIDATE READY FOR OWNER DEPLOYMENT AUTHORIZATION — as a DARK DB
APPLY (Option A+C: all 17 migrations, every flag false, integrations unarmed) riding
the 077 release train (DB + three edge bodies + `kernel` API exposure).** Nothing in
this document changes production; production remains at migration 20260902003623 with
NONE of 076–092 applied. Feature activation of every rail remains separately blocked
(per-rail blockers below).

> **DEPLOYMENT-STATE CORRECTION (2026-09-02, added post-apply).** The verdict line below and §2
> describe the pre-apply world. The dark DB apply was subsequently authorized and executed on
> 2026-09-02 (apply window 20:41:58Z to 20:43:31Z; ledger 90 -> 107; V1-V18 pass; kernel exposed;
> three edge functions deployed). See `docs/release/PHASE2_DEPLOYMENT_RECORD_20260902.md`. The
> classifications, rail matrix and owner packets below remain valid; the deployment-state
> assertions are superseded.



## 1. Source integrity (proven)
- `phase2/consolidation` tip local=remote `76bda03963d631c365b48aacc14a24e8ca3d1da6`;
  tag `phase2-architecture-v2` → `06fd5ecccc405f416e8f27591ccbbf709771f8ef`.
- All 17 migrations 076–092: one commit each, hashes recomputed and matching the
  package closing records (092 = `0f8375d3…c5635`).
- PR #28 untouched at `ede72729cc81d6b6a71fcadd3e8ea4954e394186` (base `main`).

## 2. Production delta (computed against the live ledger, read-only)
- Production ledger: 90 rows; repo now covers ALL of them (the one drifted row,
  `20260902003623_admin_relist_listing_rpc` — applied to production 2026-09-02 without
  a repo commit — was reconstructed byte-verified (md5 `3919213d…0971`) from the
  ledger's recorded statements into `supabase/migrations/`; Gate-2 public-function
  census 69→70 with a dated note). MIGRATIONS TO APPLY: exactly 076–092 (17).
- Post-apply ledger: 107 rows = repo file count. `db push` needs `--include-all`
  (numeric versions sort before the four timestamped website-form rows).
- Objects added: 5 schemas · 69 relations (kernel 28, venue 29, catalog +, market,
  notify 7) · 243 five-schema routines · 72 policies · 16 cron rows (19 total) ·
  43 config keys · 2 storage buckets (083 wallet, 087 exports) · 61+31 notify seeds.
- Pre-existing objects touched: `public.push_tokens` +4 nullable columns + 1 partial
  index (092; METADATA/DDL ONLY, ~ms at 2 rows); `auth.users`/`public.profiles`
  +2 sentinel rows (078; LIVE-ROW INSERT, idempotent, IDENTITY-SENSITIVE but
  sentinel-scoped, provider='sentinel', no password). storage.buckets +2 rows.
  **No other live-row mutation exists** — proven by the production-order rehearsal's
  per-table data checksums (diff = 0 across listings/payments/transfers/push_tokens/
  non-sentinel auth.users).
- LOCK RISK: negligible. Largest production table is 240 kB / ~36 rows; the only
  ACCESS EXCLUSIVE on a live table is push_tokens (2 rows). No rewrite, no VALIDATE,
  no backfill. Rehearsed wall clock: ~1 s of SQL. EXPECTED DOWNTIME: none.

## 3. Blockers closed during this pass
1. **ROLLBACK_GUARD_ROW_SECURITY — CLOSED.** All 17 rollback guards audited; seven
   (076/077/078/079/080/088/090) counted RLS-enabled zero-policy tables without
   `set local row_security = off` and would FAIL OPEN under a non-owner runner. All
   seven patched (088 additionally locks the four tables it drops). Proof: the full
   17-package rollback battery passes with identity diff 0 at every step; a dirty
   077 world REFUSES under the owner runner and ERRORS (fail-closed) under a
   non-BYPASSRLS runner.
2. **PFA-1 production sweep — CLOSED as a standing runbook control.** The compensating
   control is the per-function revoke discipline witnessed by the suites; the
   production-side witness is now `phase2_postapply_verify.sql` V13 (zero PUBLIC/anon
   EXECUTE across the four walled schemas), run at +5M and re-run at +2H/+24H.
3. **Ledger reconciliation — CLOSED.** Drift found (one uncommitted production
   migration; see §2) and repaired in-repo; 043's absence confirmed deliberate from
   production's own 042 notes (staged mobile rollout; `mobile/profile-rpc-compat` is
   the adoption branch). `phase2_preflight.sql` runs 21 read-only checks — **21/21
   PASS against live production on 2026-09-02** (ledger shape, extensions, Vault,
   cron, sentinels, legacy money integrity, deletion-surface preconditions).
4. **Vault / pg_net / pg_cron — CLOSED for the dark apply.** Production already runs
   pg_cron 1.6.4 + pg_net 0.19.5 + supabase_vault 0.3.1 with the `service_role_key`
   secret. Cron census below: every job the apply schedules is DB-only except the two
   087 CRM ticks, which are fail-closed by construction on the absent
   `crm_export_worker_secret` (they no-op; creating that secret is a CRM-activation
   step, not an apply step). The two notify edge ticks are NOT scheduled (E-158).
5. **077 release-train gate — ARTIFACTS NOW EXIST** (see §5).

## 4. Cron census (post-apply: 19 rows)
| Job | Pkg | Schedule | Target | Secret | Safe before edge deploy? | If secret absent |
|---|---|---|---|---|---|---|
| auto-finalize-auctions | legacy | */2 | DB fn | – | yes | – |
| enforce-transfer-expiry | legacy | */2 | pg_net → edge | service_role_key (Vault) | already live | job errors (existing behavior) |
| sweep-auth-password-changes | legacy | */5 | DB fn | – | yes | – |
| sweep-deletion-pending | 077 | */2 | DB fn | – | yes (empty table) | – |
| sweep-expired-org-invites | 077 | */2 | DB fn | – | yes | – |
| sweep-expired-ticket-atoms | 079 | */2 | DB fn | – | yes | – |
| sweep-expired-inventory-holds | 081 | */2 | DB fn | – | yes | – |
| sweep-expired-refund-requests | 085 | */2 | DB fn | – | yes | – |
| sweep-expired-door-sessions | 086 | */2 | DB fn | – | yes | – |
| sweep-expired-door-overrides | 086 | */2 | DB fn | – | yes | – |
| sweep-implicit-door-freezes | 086 | */2 | DB fn | – | yes | – |
| refresh-holder-mix / reconcile-holder-mix | 086 | daily | DB fns | – | yes | – |
| sweep-expired-exports | 087 | hourly | DB fn | – | yes | – |
| crm-export-build-tick | 087 | 1m | pg_net → edge | service_role_key + crm_export_worker_secret | yes — `where exists(vault…)` FAIL-CLOSED no-op | silent no-op (by design) |
| crm-export-purge-tick | 087 | 15m | pg_net → edge | same | same | same |
| market-sweep-expired-p2p-transfers / market-sweep-paid-pending-sales | 088 | */2 | DB fns | – | yes (empty) | – |
| notify-drain-outbox | 092 | */2 | DB fn | – | yes ({done:0} on empty) | – |
NOT scheduled (parked deploy artifacts): notify-dispatch (1m), notify-receipts (15m),
resale-checkout-sweep — each needs an owner-named header + Vault secret first.

## 5. Account-deletion release-train gate (the one gate that binds the apply)
**Ruling (recorded, verbatim intent):** 077 must not be applied unless the
delete-account edge switch + the F-5 live-rail guards ship on the same train.
**Status: ARTIFACT SET COMPLETE IN-REPO — gate SATISFIABLE by the runbook's train.**
- Edge switch: `supabase/functions/delete-account/index.ts` REWRITTEN to the §1.8a
  cutover (Class A caller-JWT → `kernel.request_account_deletion`; withdraw action;
  409s retired; `auth.admin.deleteUser` called by NOTHING; deployed-client
  compatible: empty body = request, `success:true` preserved).
- F-5 guards, edge layer: `create-payment-intent` (funding chokepoint for buy-now AND
  auction wins — refuses a DELETION_PENDING buyer, 403 `account_deletion_pending`);
  `confirm-and-release` (refuses confirming an inbound transfer initiated AFTER
  `deletion_requested_at`; earlier transfers stay confirmable — disposal/resolution).
  Both probe via the frozen surfaces (`kernel.is_deletion_pending` EXEC service_role;
  own-row `kernel.identity_ext` SELECT policy) and fail OPEN on probe error by design:
  the DB sweep's BP wall is the enforcement, the edge is the frozen UX layer.
- F-5 guard, RN layer: `src/screens/PlaceBidScreen.tsx` guard authored (bids are a
  direct client insert; no edge exists to intercept, and a public trigger reading
  kernel is barred by FR-9).
- REMAINING NAMED CELL (does not block the DB apply; blocks calling the train
  "product-complete"): the Settings **withdraw-deletion UI** (RN). The edge route
  exists (`action:'withdraw'`); no client calls it yet. Map: app/settings/index.tsx —
  read own `kernel.identity_ext.deletion_state` on mount; if DELETION_PENDING render
  a banner + "Withdraw deletion request" button → invoke delete-account with
  `{action:'withdraw'}`. Entangled file with PR #28 — see §6. A second named cell:
  the tombstone-flow STORAGE step (avatar/media removal at ERASED, not at request) —
  post-launch operational reaper, fail-safe to defer (storage objects persist, no
  compliance text in the frozen corpus sets its deadline before Gate-L).
- Old deployed builds: POST delete-account {} → now lands in DELETION_PENDING with
  `success:true` (they show their old "deleted" copy and sign out; on re-login the
  account is pending — withdrawable once the UI cell ships). Old builds' bids
  bypass the RN guard; the sweep's BP wall still blocks erasure-with-obligations,
  so no money/custody safety depends on the client.

## 6. PR #28 — reconciliation and recommendation
PR #28 (base `main`, head `ede72729…`) is the PRE-cutover physical-delete hardening:
it keeps `auth.admin.deleteUser`, extends `public.delete_account_cleanup`
(timestamp migration 20260828041500), retains request-time 409s, and edits the same
Settings screen the cutover UI needs. Against the final 076–092 state:
- REDUNDANT once the train deploys: the physical path retires entirely (§1.8a);
  every behavior PR #28 hardens stops being reachable.
- CONFLICTING: its delete-account body and Settings edits collide with the cutover
  artifacts; its migration would land a dead function body revision post-cutover
  (harmless but noise) and would create NEW main-vs-consolidation drift.
- STILL NECESSARY only in one world: if the owner delays the Phase-2 apply AND wants
  today's physical-delete flow fixed for interim users (its bug is real pre-077).
**RECOMMENDATION: CLOSE/SUPERSEDE** at the moment the owner authorizes this train
(the cutover obsoletes it); **KEEP OPEN unmerged** only if the apply is deferred
materially and the interim deletion bug needs a hotfix first — in that case merge it
to `main` alone, never to `phase2/consolidation`, and re-run this gate's drift
reconciliation afterwards. Do not rebase it onto the cutover; nothing of it survives.

## 7. Edge-artifact census
| Function | Obligation | Code exists | Merged | Prod deployed | Needed for DB apply | Needed for activation | Secrets | Stripe |
|---|---|---|---|---|---|---|---|---|
| delete-account (cutover body) | 077 gate | YES (this pass) | this PR | NO — rides the train | YES (train) | – | none new | – |
| create-payment-intent (F-5) | 077 gate | YES (this pass) | this PR | NO — rides the train | YES (train) | – | none new | existing |
| confirm-and-release (F-5) | 077 gate | YES (this pass) | this PR | NO — rides the train | YES (train) | – | none new | existing |
| notify-dispatch / notify-receipts | NOTIFY_DISPATCH_TICK | NO | – | NO | no | push channel | INTERNAL_CRON_SECRET + names | – |
| crm-export-worker | PFA-28/X-6 | NO | – | NO | no | CRM export | crm_export_worker_secret + HMAC ruling | – |
| primary-checkout / resale-checkout | native rails | NO | – | NO | no | issuance / resale | STRIPE_SECRET_KEY | YES |
| stripe-webhook native branches | native rails | NO | – | NO | no | issuance / resale | webhook secret | YES |
| credential-sign / signing-key-provision | Wallet/issuance | NO | – | NO | no | issuance/Wallet | KMS | – |
| refund-execute / payout-execute | native money | NO | – | NO | no | money activation | Stripe | YES |
| promoter-code-preview | PROMOTER_CODE_PREVIEW_EDGE | NO | – | NO | no | promoter codes | – | – |
| send-push / stripe-webhook / others (legacy) | – | YES | main | YES | untouched | – | existing | existing |

## 8. Client compatibility census
Deployed RN build calls: 13 public RPCs (get_my_profile, reserve_buy_now, transfer
writers, cancel_listing, finalize_auction, complete_auction_payment, disputes,
can_create_listing, trust stats) + 2 edges (delete-account, create-connect-account)
+ direct table reads/writes (bids insert, listings, payments, push_tokens,
notifications). Web calls no RPCs beyond PostgREST table reads (notifications,
favorites). The 076–092 delta changes NONE of these surfaces: public grants proven
identical to the production fixture; push_tokens delta additive (old upserts leave
`revoked_at` NULL = live under the new predicate); no public function is replaced.
**Old apps are safe after the apply; new-app behavior (kernel reads) is safe before
activation because the guards fail open pre-exposure. An App Store release is NOT
required to precede the DB apply; the next release should carry the two RN cells.**
The 042→043 profiles-restriction rollout stays an INDEPENDENT track
(`mobile/profile-rpc-compat`): 043 must not be applied until that adoption ships —
unchanged by this gate.

## 9. Stripe census (code-only; nothing to change while dark)
Required TODAY (already live): the legacy webhook events consumed by
`stripe-webhook` v39 (payment_intent.succeeded/failed, charge.refunded, account.updated,
etc.), `STRIPE_SECRET_KEY`/webhook secret in edge env, 7 live Connect accounts.
Required ONLY at activation (FEATURE-ACTIVATION ONLY, per rail): native-rail PI
metadata contracts (rail=native_primary/native_resale), webhook branches for
finalize/transfer custody, refund-execute/payout-execute Connect transfers with
`source_transaction`, promoter-payout transfers (after COMMISSION funding lands),
dispute webhooks for `kernel.record_dispute_native`. The dark apply makes NO Stripe
call and changes NO webhook routing.

## 10. Config-key matrix (the load-bearing rows; 43 keys total post-apply)
| Key | Default | NULL/false safe? | Needed before apply | Needed before activation | Owner value |
|---|---|---|---|---|---|
| feature.native_issuance_enabled / native_scanning / native_resale / wallet.apple.enabled / notify.announcements_enabled | false | YES — every consumer refuses | seeded by 078 | flip per rail | owner flips |
| retention.backup_window_days | NULL | YES — purge stamp never set; deletion still tombstones | no | before purge/reaper only | YES (packet A) |
| deletion.refund_possible_window_hours | NULL | YES — BP-12 fail-closed | no | before deletion-with-refund windows tighten | YES |
| notify.delivery_lease_interval | NULL | YES — claim_deliveries refuses | no | before push dispatch | YES (packet B) |
| refund.* (7 keys) / payout.* (4) / authn.* (3) | NULL or seeded | YES — money RPCs fail closed on NULL where owner-gated | no | money activation | YES (088/085 packets) |
| door.session_touch_interval / door.schedule_move_grace_interval | NOT SEEDED (PFA-9 CLASS A) | absent = fail-closed | no | scanning activation | YES |
| credential.* spans, crm_export.constraint_set_version, comp.*, notify.announcement_* | seeded v1 | yes | no | per rail | – |

## 11. Backup / PITR
Not independently verifiable from this session's read surface (no Management-API
backup endpoint exposed here). Therefore: `retention.backup_window_days` STAYS NULL
(reaper fail-closed — verified as postapply V9), the runbook's T-24H step reads the
answer off the dashboard, and packet A asks the owner to set it afterwards. This
blocks NOTHING on the apply.

## 12. Security + money conservation (final pass)
- Security: suites 140–157 green on the production-order catalog (2 622 assertions),
  grant parity with production identical (public), PFA-1 sweep 0 hits, anon walls
  proven, IDOR/EXEC-posture suites green, the three redeployed edge bodies keep
  fail-closed rate limiting and Class A auth. **P0 = 0 · P1 = 0.**
- Money: the dark apply moves no money and exposes no money verb (all money RPCs are
  behind false flags, NULL owner keys, or service_role walls; every promoter payout
  path mints HELD; V17). Legacy-rail money invariants preflight-checked on live data
  (M1–M5 PASS). **Money conservation: PASS for every rail that can run (= legacy
  only). Open economics (resale split, commission funding implementation, negative
  settlement carry) remain ACTIVATION blockers by design.**

## 13. Rail matrix
| Rail | DB Apply Ready | Feature Ready | Money Ready | Blocker (for the NO/PARTIAL) |
|---|---|---|---|---|
| ACCOUNT DELETION | YES | PARTIAL | – | withdraw-UI RN cell; storage reaper cell (post-launch) |
| VENUE CORE (orgs/venues/events) | YES | PARTIAL | – | kernel exposed on this train; venue/catalog exposure + dashboard deferred |
| PRIMARY INVENTORY / ISSUANCE | YES | NO | NO | flag; primary-checkout + webhook branch + credential-sign + KMS |
| DOOR / SCANNING | YES | NO | – | flag; PFA-25/26; door config keys; scanner app |
| WALLET | YES | NO | – | flag; PFA-20; Apple cert; credential-sign |
| NATIVE RESALE | YES | NO | NO | flag; PFA-30; RESALE_CHECKOUT_SWEEP_TICK; resale-checkout edge; 088 owner forks |
| P2P | YES | NO | – | flag (rides resale rail); TTL owner fork |
| DISPUTES | YES | NO | NO | PFA-31 dual control; webhook branch |
| CRM EXPORT | YES | NO | – | PFA-28 HMAC ruling; worker edge; Vault secret |
| PROMOTER ATTRIBUTION | YES | NO | – | needs issuance live (orders); code-preview edge + checkout params |
| PROMOTER PAYOUT | YES | NO | NO | COMMISSION_FUNDING_SOURCE implementation (Option B, 13-proof list); lifecycle + hold + affiliate packets |
| NOTIFICATIONS (in-app) | YES | PARTIAL | – | works at activation of any producer rail + notify exposure; producer parity E-161 |
| NOTIFICATIONS (push) | YES | NO | – | lease value (packet B); dispatch ticks; Expo creds |
| SETTLEMENT | YES | NO | NO | rides money activation |
| PAYOUTS (native) | YES | NO | NO | payout-execute edge; Stripe; money keys |

## 14. Owner decision packets (bundled; NONE blocks the dark DB apply)
**A. `retention.backup_window_days`** — current safe state NULL/fail-closed. Needed
before the deletion PURGE stamp is ever computed. Read the dashboard's actual
backup/PITR window (T-24H step); set the key to that number of days via
`catalog.set_platform_config`. Recommendation: set within a week of apply; if PITR=7d,
value 7.
**B. `notify.delivery_lease_interval`** — NULL keeps push claim fail-closed. Options:
'2 minutes' (tight, more double-sends on slow providers) · **'5 minutes' (recommended:
> Expo timeout, < user-noticeable redelivery)** · '10 minutes' (strands a crashed
sender's rows longer). Blocks push activation only.
**C. EMAIL_GO_LIVE (N1)** — stays OFF; requires sending-domain + DMARC decision,
provider key, templates. Blocks the email channel only.
**D. PR #28 disposition** — recommendation §6 (CLOSE/SUPERSEDE on train
authorization). Owner call because it deletes an open workstream.
**E. Money/resale forks (unchanged from 088/090 registers)** — NATIVE_RESALE_SPLIT
(PFA-30), DISPUTE_DUAL_CONTROL (PFA-31), NEGATIVE_SETTLEMENT_CARRY,
P2P_TRANSFER_TTL, PAID_PENDING_DWELL_SLO, LISTING_EXPIRY_SWEEP,
OFFER_COUNTER_DECISION, PUBLIC_PAYMENTS_NATIVE_SHAPE, COMMISSION_PAYOUT_LIFECYCLE,
AFFILIATE_PAYOUT_DESTINATION, PROMOTER_MANAGER_CODE_READ. Block their rails'
activation only.
**F. Door config values** (PFA-9 CLASS A pair + PFA-25 surface + PFA-26 KDF) — block
scanning activation only.
**G. RN train cells** — approve authoring the Settings withdraw UI (map in §5) on the
active mobile line, and schedule the next App Store build to carry it + the bid
guard. Blocks product-completeness of deletion, not the apply.
**H. NOTIFY_DEVICE_LOCALE_COLUMN / INBOX_COMPOSITE_CURSOR / DRAIN_THROUGHPUT** —
optional-future; no action proposed now.

## 15. Rehearsal record (all local, nothing touched production beyond read-only SQL)
- Rollback battery: 17/17 identity-0 (post-patch); dirty-guard fail-closed proof both
  runner classes. Production-order rehearsal: preflight world → 076–092 in 1 s →
  zero live-row mutation → verify 18/18 PASS → 18 suites 2 622/2 622.
- Production read-only: preflight 21/21 PASS (2026-09-02); ledger/extension/Vault/
  cron/table-size census recorded in this report.
- Staging: none exists (no Pro-plan branch); the production-order local rehearsal is
  the certified substitute, per the gate's fallback clause.
