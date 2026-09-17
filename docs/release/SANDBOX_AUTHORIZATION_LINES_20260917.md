# Two sandbox authorization lines for the owner (A, 2026-09-17) — nothing below is executed until the owner speaks it

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
| Steps | RT1 seller uploads each file with the byte-derived contentType, `upsert:false` → expect 200 ×3 · RT2 seller re-uploads the same name → expect 409 (the server-side answer C's client now interprets via `storage.exists`) · RT3 seller signs and downloads each → 200, sha256 equal, `Content-Type` equal to the declared type · RT4 buyer signs/downloads each → denied · RT5 anonymous client → denied · **RT6 (buyer access to a referenced object) DEFERRED** — needs 140 applied on the sandbox and one attach, not in this scope · RT7 seller deletes the three objects → 200 and the folder count returns to the pre-count |
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
(If C reports D8 is reserved for another device row, the same line with `b1c3c478…` (Device D7); C's answer is pending.)

| Aspect | Exactly |
|---|---|
| Account / listing / amount / path | DV buyer `919d511e…` · listing `58cc00e3…` "Device D8", seller `2f5844b4…`, starting bid 100, current bid 100, 0 bids, buy-now on, ends **2026-09-25 02:01Z** · **$101** · the app's Place bid screen (a client insert into `public.bids` under RLS; no psql write, no service credential) |
| Affected records | `public.bids` **+1 row** (id, listing_id, bidder_id, amount 101, created_at) · `public.listings` row `58cc00e3…`: `current_bid` 100→101, `bid_count` 0→1, `highest_bidder_id` null→buyer, `updated_at` (by the bid triggers' own guard bypass, not a manual one) · `public.notifications` **+1 row** for the seller (`bid_received`, dedupe `bid_received:<bid id>`) · **nothing** in `notify.*`, `net.*`, payments, transfers, reservations |
| Side effects | no outbound notification: `notify_outbid` and `notify_bid_placed` both return early because `app.settings.supabase_url` / `service_role_key` are unset on the sandbox (read 04:40Z), and `send-push` refuses every dispatch under option (b) anyway; no payment or hold at bid time. **If retained past 2026-09-25 02:01Z:** `auto-finalize-auctions` sets the listing ended with the buyer as winner at $101 and writes one `auction_won` inbox row for the buyer; no charge follows automatically |
| Read-backs (A) | before: buyer's bids = 0, D8 = 100/0/null, seller's inbox count; after: 1 row (id, 101, created_at), D8 = 101/1/buyer, seller inbox +1 with the dedupe key, `net.http_request_queue` unchanged, `notify.notification` count unchanged |
| Cleanup | **R (recommended):** after the ST2b observation the owner, signed in as the seller, cancels D8 from the app (`cancel_listing`: seller-only, tolerates bids) — no finalisation, no winner; the bid row and the seller's inbox row remain as history. **R′:** let it end (§ above). **X (delete the bid row as postgres) is NOT proposed:** no trigger reverts the listing, and reverting it by hand is a manual guard bypass the owner has ruled out |
| Stopping conditions | the before-read shows any bid for the buyer or on D8 · D8 not `active`/`active` · `now() > ends_at` · either `app.settings.*` GUC set · a DV-ST2 revoke window is open (place the fixture before ST2a or after its verified restore, never inside) · CS-1 fails |
| Witness | D: before/after reads with UTC times |
| What it enables | DV-ST2b (cached rows stay on pull-to-refresh under a server error) as a real observation instead of UNTESTED; nothing else |

---
**Interaction of the two lines with DV-ST2:** all three are separate windows on C's triggers; none overlaps another; the
fixture, if authorized, is placed before ST2a or after ST2a's verified restore.
