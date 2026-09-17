# Sandbox authorization lines for the owner (A, 2026-09-17; Line 3 added the same day) — nothing below is executed until the owner speaks it

**Classes (package §5):** Line 1 is TEMPORARY (every object it creates is deleted in the same run). Line 2 and Line 3 are PERMANENT: their rows cannot be removed, only superseded or left to end. Line 3b writes nothing by design but invokes a transfer verb, so it is named separately.

Both are **sandbox `ofaidukbieeekqaboscm` only**, both are A-executed with D witnessing, and neither touches production, a
build, a flag, a secret or an outbound notification. Each is one line to say, plus the constraints it carries.

---
## Line 1 — Sandbox image round-trip test (proof-docs storage; contract §5 as amended by §8 item 3)

**Authorization line:** "Run RT1–RT5 and RT7 of the proof-docs round-trip on the sandbox as scoped, A executing as the DV
seller, the DV buyer and an anonymous client, D witnessing the before/after object counts; synthetic files only; no table
writes; abort on the listed stopping conditions."

| Aspect | Exactly |
|---|---|
| Actors | DV seller `2f5844b4…` and DV buyer `919d511e…` by password grant (credentials from the sandbox env by NAME only, never in chat or records); one anonymous client (anon key) |
| Files | three synthetic files under 10 KiB each, generated locally: a 1×1 PNG, a minimal JPEG, and a HEIC made from the PNG with `sips`; named `rt-20260917-1.png`, `rt-20260917-2.jpg`, `rt-20260917-3.heic`; sha256 of each recorded |
| Affected records/files | **only** `storage.objects` rows in bucket `proof-docs` at `<seller uid>/transfer-evidence/rt-20260917-{1,2,3}.<ext>` — three rows created at RT1 and deleted at RT7. **No row in any `public.*`, `notify.*`, `kernel.*`, `market.*` or `net.*` table.** No transfer references them, so no policy other than the owner's own is exercised for the seller, and the transfer-party read is exercised only in its denial form |
| Steps | RT1 seller uploads each file with the byte-derived contentType, `upsert:false` → expect 200 ×3 · RT2 seller re-uploads the same name → expect 409 (the server-side answer C's client now interprets via `storage.exists`) · RT3 seller signs and downloads each → 200, sha256 equal, `Content-Type` equal to the declared type · RT4 buyer signs/downloads each → denied · RT5 anonymous client → denied · **RT6 (buyer access to a referenced object) is not in this line** — it needs 140 applied and one attach, and it runs as Line 3's RT6 after DV-IMG-10 · RT7 seller deletes the three objects → 200 and the folder count returns to the pre-count |
| Side effects | storage access logs on the sandbox project; nothing else. No notification of any kind (no table write, no trigger, no edge call) |
| Read-backs (A) | `select count(*) from storage.objects where bucket_id='proof-docs' and name like '<seller uid>/transfer-evidence/rt-%'` = 0 before → 3 after RT1 → 0 after RT7; each step's HTTP status, object id and sha256 recorded as values in the manifest |
| Cleanup | RT7 itself (the owner-delete-unreferenced policy). If RT7 fails for any object, A reports the surviving object names and stops; deletion by any other route needs the owner's word |
| Stopping conditions | pre-count ≠ 0 · any status differs from expectation · RT3 bytes or Content-Type differ · any object survives RT7 · a DV-ST2 revoke window is open (the two never overlap) · the sandbox identity assertion (CS-1) fails · any credential appears in an error message (abort and redact) |
| Witness | D: independent before/after counts with UTC times, compared to D's own pre-read |
| What it proves / does not | proves the bucket policies and allow-list behave as the contract states for the true types, that a same-name re-upload is refused, and that unrelated users and anon are denied; **does not** prove HEIC conversion, buyer display of a referenced proof (RT6), or anything on a device |

---
## Line 2 — Cached-bids fixture (one sandbox bid so DV-ST2b can be observed; `CACHED_BIDS_FIXTURE_PROPOSAL.md`)

**Authorization line:** "Place one $101 bid as the DV buyer on listing `58cc00e3…` (Device D8) through the app's Place bid
screen on the owner's handset, A reading back before and after; retain the row for the DV-ST2b observation; afterwards
[R: the seller cancels D8 from the app | R′: let the listing end on 2026-09-25]."
**C's constraints (2026-09-17), now part of the line:** no open device row of C's is reserved on D8. **Device D7 is NOT named as an alternate** — the owner's standing instruction is "Do not retry Device D7 or modify any payment state". A listing with a bid loses its Edit action, and the owner may be editing D8 during DV-S2 now, so **the bid is placed only after DV-S2 completes**, and **one bid-free seller listing is kept** (Phone P1 `c343406e…` stays untouched) for the next candidate's F-SELL-2 re-check on Edit listing. D8's fixture image serves DV-106 (image fallback), which a bid does not affect.

| Aspect | Exactly |
|---|---|
| Account / listing / amount / path | DV buyer `919d511e…` · listing `58cc00e3…` "Device D8", seller `2f5844b4…`, starting bid 100, current bid 100, 0 bids, buy-now on, ends **2026-09-25 02:01Z** · **$101** · the app's Place bid screen (a client insert into `public.bids` under RLS; no psql write, no service credential) |
| Affected records | `public.bids` **+1 row** (id, listing_id, bidder_id, amount 101, created_at) · `public.listings` row `58cc00e3…`: `current_bid` 100→101, `bid_count` 0→1, `highest_bidder_id` null→buyer, `updated_at` (by the bid triggers' own guard bypass, not a manual one) · `public.notifications` **+1 row** for the seller (`bid_received`, dedupe `bid_received:<bid id>`) · **nothing** in `notify.*`, `net.*`, payments, transfers, reservations |
| Side effects | no outbound notification: `notify_outbid` and `notify_bid_placed` both return early because `app.settings.supabase_url` / `service_role_key` are unset on the sandbox (read 04:40Z), and `send-push` refuses every dispatch under option (b) anyway; no payment or hold at bid time. **If retained past 2026-09-25 02:01Z:** `auto-finalize-auctions` sets the listing ended with the buyer as winner at $101 and writes one `auction_won` inbox row for the buyer; no charge follows automatically |
| Read-backs (A) | before: buyer's bids = 0, D8 = 100/0/null, seller's inbox count; after: 1 row (id, 101, created_at), D8 = 101/1/buyer, seller inbox +1 with the dedupe key, `net.http_request_queue` unchanged, `notify.notification` count unchanged |
| Cleanup | **R (recommended):** after the ST2b observation the owner, signed in as the seller, cancels D8 from the app (`cancel_listing`: seller-only, tolerates bids) — no finalisation, no winner; the bid row and the seller's inbox row remain as history. **R′:** let it end (§ above). **X (delete the bid row as postgres) is NOT proposed:** no trigger reverts the listing, and reverting it by hand is a manual guard bypass the owner has ruled out |
| Stopping conditions | DV-S2 not yet complete (C confirms) · the before-read shows any bid for the buyer or on D8 · D8 not `active`/`active` · `now() > ends_at` · either `app.settings.*` GUC set · a DV-ST2 revoke window is open (place the fixture before ST2a or after its verified restore, never inside) · CS-1 fails |
| Witness | D: before/after reads with UTC times |
| What it enables | DV-ST2b (cached rows stay on pull-to-refresh under a server error) as a real observation instead of UNTESTED; nothing else |

---
## Line 3 — Permanent transfer writes by the next build's device tests (DV-IMG-4, -5, -9, -10), the 3b no-write probe, and RT6

**Authorization line:** "On the next build, with 140 applied on the sandbox, the owner's handset may mark sandbox transfers
`92ee5156…`, `3118bd30…` and `bce07eef…` sent with proof and add proof to `8f59d37e…`, as DV-IMG-4, -9, -5 and -10; A reads back and
runs the 3b no-write probe and RT6; D witnesses. These writes are permanent."

| Aspect | Exactly |
|---|---|
| Actors | the owner's handset signed in as the DV seller `2f5844b4-5144-4cd6-936d-4b59d8d5c6a0` (device rows) and as the DV buyer `919d511e-c4e6-4422-a71d-e2bc0139de65` (RT6 view); A via the API as the same two accounts (credentials by NAME only) and one unrelated account + anon for RT6's denials |
| Transfers (read 2026-09-17 14:35:00Z; all seller 2f5844b4, buyer 919d511e, not disputed, not released, path null) | DV-IMG-4 `92ee5156-7e82-40d8-ab54-73b489997797` (pending) · DV-IMG-9 `3118bd30-276f-4183-8579-cfea852421cb` (pending) · DV-IMG-5 `bce07eef-ed72-4d85-96db-8ef340838b89` (pending) · DV-IMG-10 `8f59d37e-52fd-4733-b311-532445ff441c` (seller_sent, auto_release 2026-09-11T01:20:24Z, past) · **untouched:** `83b83858-7c96-4887-bf6c-447858aec22a` |
| Affected records | per Mark as sent: `public.transfers` status pending→seller_sent, `seller_sent_at`, `auto_release_at` = now + 72 h, `transfer_evidence_path` null→path; one referenced `proof-docs` object under the seller's `transfer-evidence/`; buyer inbox rows from `trg_notify_transfer_sent` / `trg_notify_transfer_state_inbox`. Per Add proof: `transfer_evidence_path` null→path (written with the guard armed); one referenced object; a refused different-photo attempt leaves one unreferenced object |
| Permanence | **nothing is removed.** The state guard forbids reverting a status, the append-only guard forbids replacing a path, referenced objects are evidence, and unreferenced objects from refused or failed attempts are retained under the owner's 30-day direction (no deletion without a dry-run and the owner's word) |
| Side effects | inbox rows only. Any outbound attempt must be refused: Vault holds `project_url` only (no `service_role_key`), and `app.settings.*` is unset. **Consequences that outlive the test:** these four transfers become release candidates if either `payout.executor_enabled` (false, read 14:35:00Z) or a Vault `service_role_key` is ever enabled on the sandbox; Add proof removes `8f59d37e…`'s `EVIDENCE_MISSING` reason while its deadline has already passed |
| 3b no-write probe (A, after DV-IMG-4, before DV-IMG-10) | as the DV seller via the API: `mark_transfer_sent(92ee5156…, <seller>, <same path>)` then `(…, <different path>)` → `already_sent`; the row's md5 and the buyer's inbox count unchanged. `mark_transfer_sent(8f59d37e…, <seller>, <a path>)` → `precondition_failed …use attach_transfer_evidence`; row unchanged. Any write is a stopping condition |
| RT6 (A, after DV-IMG-10) | the buyer signs and downloads `8f59d37e…`'s attached object → 200, sha256 = the seller's upload, magic bytes and Content-Type recorded; an unrelated account and anon → denied |
| Read-backs (A) | before each row: the transfer's status/path/timestamps; after: one object, one transition (or one attach), the object's sha256 + magic bytes + Content-Type, inbox delta; `net._http_response` no 2xx; executors still false |
| Stopping conditions | 140 not applied or its S3 read-back not recorded · a named transfer not in its 14:35:00Z state (no silent switch to another transfer; A reports) · any 2xx outbound response · either executor true or a `service_role_key` present in the Vault · the buyer taps Confirm received or Report a problem on a Line 3 transfer · a DV-ST2 revoke window open · CS-1 fails · the 3b probe writes anything · a HEIC-byte object labelled JPEG (record and FAIL DV-IMG-9; continue the other rows only on C's word) |
| Witness | D: before/after reads of each named transfer with UTC times |
| What it proves / does not | proves on a real applied database that the client's Mark as sent and Add proof reach 140's verbs, write once, answer retries without writing, and that the stored bytes are what the label says; with the owner's observation, whether a HEIC camera photo arrives as JPEG and renders (outcome 3). It does **not** prove Android (DV-IMG-8), push delivery, payout behaviour, or anything about installed older clients |

---
**Interaction of the lines with DV-ST2:** all are separate windows on C's triggers; none overlaps another; the
fixture, if authorized, is placed before ST2a or after ST2a's verified restore.
