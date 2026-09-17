# Proof-upload repair (F-IMG-1 + B's stranded-proof findings) — server contract, migration allocation, test scope (A, 2026-09-17)

**Authorization in force (owner, 2026-09-17):** "Treat B's proof-upload findings and C's F-IMG-1 findings as one coordinated
repair. Authorize isolated implementation and local verification: A owns the server contract and migration allocation; B
implements the agreed server/upload changes; C owns picker, retry and submission UX; D independently reviews the combined
behaviour … This authorizes development and local tests — not database application, deployment, another build or production
changes." Build 18 (`aad5f75`) unchanged; the fixes consolidate into the next candidate after D's review and the combined checks.

**Evidence status, kept precise (owner's words):** the retry and stranded-proof findings are **locally reproduced** (B's
BEGIN/ROLLBACK probe on the rehearsal DB, 2026-09-17); the MIME-related display failure **still needs reproduction** — a MIME
allow-list match does not establish that the bytes render. Nothing below is claimed beyond that.

## 0. The applied facts the contract is written against (sandbox catalog reads 04:33–04:45Z; the chain at `e9b52ce`)
- `public.mark_transfer_sent(uuid,uuid)` and `(uuid,uuid,text)` — 0553's bodies, SECURITY DEFINER, `returns void`, executable by
  `authenticated` + `service_role`; caller = `auth.uid()`, `p_user_id` honoured only for `service_role`; seller-only; requires
  `status = 'pending'`, else raises `Transfer cannot be marked as sent from current status: %`; sets `seller_sent`,
  `seller_sent_at`, `auto_release_at = now()+72h`, `transfer_evidence_path = coalesce(p, existing)` under
  `app.bypass_transfer_guard` (the function's own bypass).
- `guard_transfer_state_columns` (BEFORE UPDATE on `public.transfers`): blocks direct changes to the state columns unless the
  bypass GUC is on; **`transfer_evidence_path` is append-only only when `OLD` is non-null** — a null→value change passes the
  guard without any bypass. `reset_transfer_guard_bypass` clears the GUC after each row.
- Notifications on the transition: `trg_notify_transfer_sent` (`notify_transfer_event`) and `trg_notify_transfer_state_inbox`
  fire on the status UPDATE; nothing fires on an evidence-path-only UPDATE.
- Bucket `proof-docs`: private, 10 MiB, MIME allow-list `{image/jpeg, image/png, image/webp, image/heic, image/heif,
  application/pdf}`; policies: owner insert / owner read / owner update (refused once referenced) / owner delete unreferenced /
  transfer party read (buyer or seller of the transfer whose `transfer_evidence_path` = object name); 118's operator read on
  production only. Storage trusts the declared `contentType`; it does not sniff bytes.
- Sandbox data: `transfers` seller_sent 2, disputed 6, pending 21, reversed 4; **12 non-pending rows with a null
  `transfer_evidence_path`** — the stranded case exists in sandbox data. Production count: **unknown, no read authorized**
  (a named read is proposed in §6).

## 1. Outcome 1 — lost-response recovery (migration **140**, B implements; pgTAP **207**)
Redefine both overloads of `public.mark_transfer_sent` from 0553's bodies (rollback restores 0553's bodies, not 002/011's):
- **Return type becomes `jsonb`** (was `void`): `{"outcome": "transitioned" | "already_sent", "status": <text>,
  "seller_sent_at": <ts>, "transfer_evidence_path": <text|null>, "evidence_replaced": false}`. A `create or replace` cannot
  change a return type, so 140 **drops and recreates both signatures** and re-issues the exact grants (`revoke … from public,
  anon; grant execute … to authenticated, service_role`) — the four-file rule applies (manifest rows updated, `expected_grants`,
  census unchanged: same two functions).
- **Older-client compatibility:** Build 18 sends the 3-key body, Build 13 the 2-key body; both overloads stay; older clients
  ignore the return value and only check `error` — a retry that used to raise now succeeds, which is the fix, and a first call
  behaves exactly as today. No client is required to change to benefit.
- **Semantics by state, caller = seller (unchanged authorization; a non-seller still raises 'Only the seller can mark a
  transfer as sent.'):**
  - `pending` → transition exactly as today (`outcome = transitioned`).
  - `seller_sent` → **no UPDATE at all**, return the recorded result (`outcome = already_sent`, the existing path). This covers
    the lost-response retry with a null path, the same path, **and a different path**: the accepted proof is never replaced
    (`evidence_replaced` is always false), the second upload is an orphan that is RETAINED — the client never deletes, and the
    owner's direction of 2026-09-17 forbids deleting an unreferenced object without a dry-run and the owner's word (§9/§11),
    and — because nothing is updated — **no notification trigger fires a second time** (pgTAP 207 asserts `public.notifications`
    and `notify.*` counts unchanged across the retry).
  - `seller_sent` with `transfer_evidence_path IS NULL` and a non-null `p` → **not written here**; raise
    `precondition_failed: transfer already sent without evidence — use attach_transfer_evidence` (the explicit path in §2). This
    keeps "mark sent" from becoming a silent backfill route.
  - any other status (`buyer_confirmed`, `disputed`, `reversed`, `expired`, `released`, …) → raise as today (**conflicting
    retry rejected**), same message shape.
- **Locking:** `select … for update` on the row as today, so two concurrent retries serialize and the second sees `seller_sent`.

## 2. Outcome 2 — explicit recovery for transfers already sent without proof (migration 140, same package)
New verb `public.attach_transfer_evidence(p_transfer_id uuid, p_transfer_evidence_path text) returns jsonb`, SECURITY
DEFINER, `search_path = ''`, `authenticated` only (no `service_role` fallback in v1; an operator route is a later `ops` wrapper):
- **Eligibility (all required):** caller = `transfers.seller_id`; `status = 'seller_sent'` (pending uses mark-sent; disputed,
  reversed, expired, confirmed and released rows are **not** eligible in v1 — evidence during a dispute is a moderation
  question, listed in §7 for the owner); `transfer_evidence_path IS NULL`; `p` non-empty, `split_part(p,'/',1) =
  caller::text` and `p like '%/transfer-evidence/%'`; **the object exists**: one row in `storage.objects` with `bucket_id =
  'proof-docs' and name = p` (so a dangling path can never be recorded).
- **Write:** `update public.transfers set transfer_evidence_path = p where id = p_transfer_id` — **without** the bypass GUC:
  the guard fires and allows it because `OLD` is null. The append-only rule is untouched; a second attach with a different path
  is refused by the guard itself (`transfer_evidence_path is append-only.`), a second attach with the same path returns
  `already_attached` without writing. **No backfill, no batch:** each attach is one seller's explicit action on one row.
- **History (corrected 2026-09-17, B):** `public.transfers` has **no `updated_at` column** — 002:35-68 and every later
  add-column, and no trigger on the table sets one. An attach therefore writes the path and nothing else, and leaves **no
  timestamp of its own**: `seller_sent_at` keeps the original mark time, so the storage object's `created_at` is the only
  record of when proof arrived. Since this is dispute evidence, the sandbox rows record that `created_at` (Line 3). No proof
  is replaced. Whether to enqueue an in-app inbox row for
  the buyer ("Seller attached proof of transfer", `dedupe transfer_evidence_attached:<id>`) is an owner decision (§7); v1 sends
  nothing, and the buyer's receive screen shows the proof on its next load.
- **Older clients:** never call it; unaffected. C adds the entry point on the sent/"needs action" screen when the path is null.
- **Reads that follow:** the buyer's `transfer party read` policy matches on the path, so attaching is exactly what restores the
  buyer's ability to see the proof (B's finding).

## 3. Outcome 3 — file handling (client, C; server side has nothing to change in 140)
- The declared `contentType` must be derived from the **bytes** (JPEG `FF D8 FF`, PNG `89 50 4E 47`, HEIC/HEIF `ftyp` brand
  `heic/heix/hevc/mif1/msf1`) or from `asset.mimeType` when the picker supplies it — never from the filename extension; the
  stored object name's extension must agree with the declared type.
- **Decision to make with B (recommendation: convert):** HEIC/HEIF originals are converted **explicitly** to JPEG at selection
  (expo-image-manipulator, quality fixed, recorded in the object metadata as `converted_from: image/heic`), because the buyer's
  web receive page and the operator console render in browsers that do not decode HEIC. Preserving HEIC is acceptable only if
  every rendering surface is shown to decode it. Either way the label matches the bytes.
- **Test matrix (owner-required):** representative iPhone HEIC, HEIF, JPEG and PNG × selection → upload → download → render, on
  the seller's device, the buyer's device and the web receive page. Device rows are **UNTESTED until a candidate build**; the
  byte-sniffing and conversion decisions get unit tests now; the sandbox round-trip (§5) covers upload/download of synthetic
  bytes with the declared type.

## 4. Outcome 4 — upload failures and abandoned files (client, C; cleanup design, B)
- **Bounded waiting:** every `storage.upload` and the RPC call run under an `AbortController` timeout (proposal 30 s upload,
  15 s RPC). **A timeout is not evidence of failure:** after an upload timeout the client checks whether the object exists
  (owner read policy: list the exact path) before re-uploading; after an RPC timeout it reads `transfers.status` before re-calling.
- **Duplicate prevention:** the object name becomes deterministic per local file —
  `<uid>/transfer-evidence/<transferId>-<sha256(bytes) first 16 hex>.<ext>` — so a retry of the same file targets the same
  name; `upsert: false` then answers 409 for an already-stored object, which the client treats as success. Still inside the
  owner folder, so no policy changes.
- **Cleanup (B designs, its own later migration, not in 140):** a SECURITY DEFINER sweep that deletes `proof-docs` objects
  older than N days whose name is referenced by **none** of `transfers.transfer_evidence_path`,
  `transfers.dispute_evidence_path`, `listings.proof_of_ownership_path` and the legacy `transfer_screenshot_path`, with the
  reference check and the delete in one statement so a concurrent attach cannot race it; a pgTAP negative control proves a
  referenced object survives. Its cron is a new scheduled job and needs the owner's separate approval.

## 5. Sandbox storage round-trip test — exact scope, **submitted for approval, NOT executed**
Actors: the DV seller and DV buyer by password grant (credentials from the sandbox env by NAME only; never in chat or records),
and an anonymous client. Files: synthetic — a 1×1 PNG, a minimal JPEG, and a HEIC produced locally from the PNG (`sips`), each
under 10 KiB, named `rt-<YYYYMMDD>-<n>.<ext>`. Every step records the HTTP status, the storage object id, and the sha256 of the
bytes; nothing touches `public.*` tables.

| # | Step | Expect | Proves |
|---|---|---|---|
| RT1 | seller uploads each file to `<seller uid>/transfer-evidence/rt-…` with the byte-derived `contentType`, `upsert:false` | 200 ×3 | owner insert policy; allow-list accepts the true types |
| RT2 | seller re-uploads the same name | 409 | the duplicate-prevention contract (§4) holds server-side |
| RT3 | seller signs and downloads each object | 200; bytes sha256 equal; `Content-Type` equals the declared type | owner read; the label survives the round trip |
| RT4 | buyer attempts a signed URL / download of each object (no transfer references them) | denied (400/403/404 as the API reports), and counted only with the seller's successful read of the same name in the same minute, since storage reports an RLS denial as not-found | that the transfer-party read needs a referencing transfer. **NOT unrelated-user denial** (corrected 2026-09-17, B): a policy that had lost its buyer/seller predicate would answer identically here. That check is U1, an authenticated non-party (U2) on a REFERENCED object |
| RT5 | anonymous client attempts the same | denied | anon has no policy on `proof-docs` |
| RT6 | buyer access to a **referenced** object | **deferred** — needs a transfer that references the object, i.e. migration 140 applied on the sandbox and one attach; not part of this scope | — |
| RT7 | seller deletes the three objects (owner delete unreferenced) | 200; the **`rt-%` count** back to 0 (corrected 2026-09-17, B: not the folder total, which Line 3's permanent objects change) | cleanup cannot touch referenced evidence (none of these are referenced) and leaves no residue |

Read-backs by A before and after: `select count(*) from storage.objects where bucket_id='proof-docs' and name like '<seller uid>/transfer-evidence/rt-%'` = 0 → 3 → 0. Abort if the pre-count is not 0, if any status differs from the expectation, or if any object survives RT7. D witnesses the before/after counts. **Authorization line:** "Run RT1–RT5 and RT7 on the sandbox as scoped, A executing, D witnessing."

## 6. What needs the owner (besides §5)
1. **A named production read, not executed:** `select count(*) from public.transfers where status = 'seller_sent' and transfer_evidence_path is null;` — how many live sellers are in the stranded state, to size the recovery. Aggregate count; no identities.
2. **Dispute-state eligibility** for `attach_transfer_evidence` (v1 excludes it).
3. **A buyer inbox row on attach** (v1 sends nothing).
4. **HEIC → JPEG conversion** versus preservation (recommendation: convert).
5. **The cleanup sweep's cron** (separate approval when B's design lands).

## 7. Allocation, ownership, gates
| Item | Owner | Number | Gate |
|---|---|---|---|
| Migration 140 — `mark_transfer_sent` idempotent (both overloads, `jsonb`), `attach_transfer_evidence`, rollback to 0553's bodies, manifest + `expected_grants` + census rows | **B** implements to this contract; A reviews | 140 / pgTAP 207 | A review → D review → CI green → next candidate |
| pgTAP 207 required assertions | B | 207 | same-path retry: success, row unchanged (xmin equal), notification counts unchanged · null-path retry: success · different-path retry: success, path NOT replaced, orphan untouched · non-seller retry: raise · retry on confirmed/disputed/reversed/expired: raise · pending: transition + notifications exactly once · attach eligible: path set, guard fired without bypass · attach with existing path: guard's append-only raise · attach on pending / by buyer / outside the caller folder / dangling object: raise · attach same path twice: `already_attached` · both overloads present with the recorded grants, anon revoked |
| Client: byte-derived type, conversion decision, deterministic names, bounded waits, status read before retry, attach entry point | **C** | — | D review; device rows UNTESTED until a build |
| Cleanup sweep design | **B** | not allocated yet | owner approval of the cron |
| Round-trip test §5 | **A** executes, **D** witnesses | — | owner's authorization line |

## 8. Adoption by the designated A session (2026-09-17, after the owner resumed the work) — amendments from C's and B's findings
The contract above (written by the fork at `bceac68`, in this branch's history) is **adopted as the server contract** with these
amendments, which are now part of it:
1. **§3 HEIC decision — CONVERT, via the picker, not a new dependency.** C and B settled it from source (expo-image-picker 17.0.10):
   the proof path uses PHPicker without editing and returns raw HEIC under the default representation mode; setting
   `preferredAssetRepresentationMode: 'compatible'` makes iOS transcode to JPEG at selection. **No `converted_from` metadata** —
   PHPicker does not report the original type in compatible mode, so it cannot be recorded truthfully; if transcoding does not
   happen the bytes still say HEIC and the object is stored honestly as `image/heic`. Browser rendering of a converted object
   stays **UNVERIFIED until DV-IMG-9** observes a JPEG from an iPhone HEIC; D does not pass outcome 3 on the conversion before that.
2. **§3 type derivation — bytes first.** `resolveContentType` takes no file name; the stored type and extension come from the
   leading bytes (JPEG, PNG, WebP, HEIC/HEIF `ftyp` brands); unrecognised bytes are refused; a reported non-allowed type is refused
   at pick; an absent reported type waits for the sniff (C `c0281aa`, D PASS on the client half).
3. **§4 bounds and duplicate prevention as implemented by C:** upload bounded at 120 s (not 30 s); after ANY upload error,
   timeout included, `storage.exists(path)` under a 30 s bound decides, so a 409 is no longer trusted on its own (B could not
   observe a 409 locally); a pick-time object name with `upsert: false` prevents duplicate objects. The sha256-derived name in §4
   is therefore not required; **RT2 in §5 stays** (a repeated same-name upload) because the server-side answer is what the client
   now interprets.
4. **§1 outcome codes are fixed for the client:** `mark_transfer_sent` → `transitioned` | `already_sent`; `attach_transfer_evidence`
   → `attached` | `already_attached`. C adapts `runMarkSent` to them when 140 lands.
5. **B's two questions, answered in the contract's own terms:** a retry carrying a DIFFERENT evidence path on a `seller_sent` row
   is **not** a conflict to reject — §1 returns `already_sent` and never replaces the accepted proof (the second upload is an
   orphan); the conflicts rejected are the other statuses. The recovery path is gated on `status = 'seller_sent'` only, i.e. **not**
   after buyer confirmation, dispute, reversal or expiry (§2 v1), so attaching proof to a completed transfer is impossible in v1.
6. **Evidence line, unchanged:** retry and stranded-proof reproduced locally; the MIME **mislabelling** is reproduced (B ran the
   real derivation from source against representative URIs); the MIME **display failure** is not — it needs real files on a
   device and viewer.
**Go-ahead:** B implements migration 140 / pgTAP 207 to §1–§2 and §7 as amended, on a branch from `e9b52ce`; A reviews first
(0553 bodies as the rollback baseline, exact grants re-issued after the drop/recreate, manifest + `expected_grants` rows, the
`storage.objects` existence check, notification counts unchanged across a retry), then D reviews the combined behaviour.

## 9. §4 cleanup sweep — superseded in two respects by B's design (`docs/release/PROOF_DOCS_CLEANUP_SWEEP_DESIGN.md` on B's branch `feature/venue-native-and-product-v2` @ `50495df` — not yet on the converge branch; A accepted 2026-09-17)
1. **An orphan is a recovery candidate.** `attach_transfer_evidence` (§2) exists so a seller can attach proof uploaded EARLIER
   and currently unreferenced — the definition of an orphan — so the age-based sweep in §4 as written would delete exactly the
   objects §2 rescues, with certainty increasing with age. The sweep therefore **excludes every object under
   `<uid>/transfer-evidence/` for any seller who has at least one transfer in `seller_sent` with a null evidence path** (per
   seller, because the server cannot know which object the seller intends to attach). That exclusion also closes the
   check-then-delete race between attach and the sweep where it has consequences; the single-statement form is kept as well.
2. **The reference set in §4 named a column that does not exist in the chain.** `transfer_screenshot_path` is defined by no
   migration (only `transfer_evidence_path`, `dispute_evidence_path` and `proof_of_ownership_path` are real); 118 reads the
   legacy name defensively as `to_jsonb(t) ->> 'transfer_screenshot_path'` (null where absent). The sweep uses that idiom, so it
   compiles where the column is absent and still honours the reference where it exists (production is not read and is not
   assumed either way).
Also in the design: v1 scope = transfer evidence only; a bounded per-run limit; a dry-run counting function; one audit row per
run; pgTAP controls "a referenced object survives" and "a recovery-candidate object survives". **Owner decisions, not made
here:** the retention N (B recommends ≥ 30 days), the cron itself (a new scheduled job), and whether a dry-run count is
reported before the job is ever scheduled (B recommends yes). No migration number allocated; nothing implemented.

## 10. D's combined review of 140 @ `912a7d6` + `c0281aa` (2026-09-17): PASS on substance, two items to close, one statement
**Statement (owner outcome 2, "older-client compatibility defined first"):** the recovery path serves an **ongoing inflow, not a
fixed backlog**. `mark_transfer_sent(uuid,uuid)` delegates with `null::text` and the pending branch writes
`transfer_evidence_path = coalesce(p, existing)`, so any client that transitions without a path — the pre-Build-18 2-key body,
and any 3-arg call whose path is null — still creates a `seller_sent` row with no proof, exactly the state `attach_transfer_evidence`
recovers. That is deliberate (refusing would strand older clients entirely) and it means eligibility and volume for §2 are
"every such transition until those clients are retired", not "the rows that exist today"; the §6 production count sizes the
current backlog only. **Owner decision added to §6:** whether, once no supported client sends the 2-key body, the pending
branch should require a non-empty path (a later migration; not in 140).
**Items to close before the candidate is tagged (B):** (1) 050's rewrite captures `transfer_evidence_path` in `_sent050` and
never asserts it — add the one-line `is(...)` so the "no replaced proof" half is pinned in 050 as well as 207 R4/R7;
(2) 207's header sentence ("each branch killed exactly ONE assertion, and no two branches killed the same one") is false while
B's table beneath it is right (5, 4, 3 for the first three branches; R8 dies under two) — rewrite the header from the matrix;
add the harness line that 207 needs a `postgres` connection locally (119's server-controlled-columns guard kills `tap.seed_core()`
as the OS user). **Batch rule adopted:** a header claim about a matrix is generated from the matrix, never written beside it —
the third summary-contradicts-data case today (179/180 prose, G11's name, 207's header), each time with the data right.
**Evidence line held by D:** outcomes 1 and 2 met by 140 + c0281aa; outcome 3 NOT passed (MIME display failure not reproduced;
HEIC conversion device-unverified until DV-IMG-9); outcome 4's device half is DV-IMG-1..8. A's disclosure: A relayed B's header
sentence to D as fact without checking it against the table — the same failure, one hop on.

## 11. Owner's rulings 2026-09-17 on §9/§10 (verbatim substance)
- **Cleanup direction:** minimum **30-day** retention in the proposal; **preserve referenced evidence and recovery candidates**;
  **require a dry-run report before any deletion**; **do not create or enable a scheduled cleanup job yet**; **D verifies the
  attach-versus-cleanup race protection before the implementation is accepted.**
- **Older-client overload:** stays compatible for this repair. **Requiring proof before marking sent is the intended future
  behaviour** once supported clients can comply; A brings the compatibility evidence (which client versions send the 2-key
  body; when they are retired) and a migration proposal before enforcing it. Not in 140.
- **Evidence limits, preserved:** database outcomes 1 and 2 passed; **image conversion and buyer display remain unverified
  until a real iPhone round trip**; the remaining device behaviour needs a build. **The whole image issue is not to be
  described as fixed.**
- **140's two closing items** (050 asserts the original evidence path unchanged; 207's summary generated from its actual
  results) close with B, D confirms the follow-up; candidate preparation then continues within the existing authorization
  (integration and local verification; no application, deployment or build).
- **Sandbox authorization lines** for the image round-trip test and the bid fixture go to the owner together, with affected
  records/files, side effects, cleanup and stopping conditions: `SANDBOX_AUTHORIZATION_LINES_20260917.md`. Not production
  work, no additional builds.
