# 073 — SEC-3 Storage Constraints: Production Verification Report

## Verdict: **073 SEC-3 CLOSED IN PRODUCTION**

Applied 2026-08-27 under explicit owner authorization, pinned to the reviewed head SHA. Every
verification item that is reachable from database-level access passed. **Items 8–12 (behavioural
upload accept/reject) were NOT executed** — the reason and the exact gap are stated in §5, not
glossed. No real user file was read, modified or deleted.

| | |
|---|---|
| Migration | `supabase/migrations/073_storage_bucket_upload_constraints.sql` |
| SHA-256 | `90599ebaa81bca6cd1488f46f371560a3326c1dc9021d6af377543f8bc124f3a` (unchanged from review) |
| Rollback | `073_..._rollback.sql` · `077853d8…52eef7c1` |
| PR | [#24](https://github.com/SnatchIt-app/snatchit/pull/24), squash-merged pinned to `2e56e152f01d7165895b0804608f7474ccf0b74e` |
| `main` | `ec6b60c` · tree `d9f778ed91de262453937ce499b33fc6e9dd3f3f` |
| Ledger | **86 → 87** |

---

## 1. Pre-flight (all confirmed before mutation)

| Gate | Result |
|---|---|
| PR #24 head SHA | `2e56e152f01d7165895b0804608f7474ccf0b74e` ✓ matches the reviewed package |
| Required checks | 14 pass, 1 skipping (`Supabase Preview`) · `MERGEABLE / CLEAN` |
| **Auto-deploy OFF** | branch record `git_branch = ""`, `updated_at` still `2026-08-27T15:49:25Z` ✓ |
| Production ledger before | **86** (md5 `38a1bdc1533ae58edd9b3886b32689fb`) |
| Applied checkout migrations | **87** · 073 SHA-256 matches byte-for-byte |
| **`074` / `075` absent from checkout** | **0 files** — verified by glob, both before and after merge |
| **Dry run proposes exactly one** | `• 073_storage_bucket_upload_constraints.sql` ✓ |

Pre-state: all three buckets `file_size_limit = NULL`, `allowed_mime_types = NULL`; 11
`storage.objects` policies; 172 objects; backup 79.

## 2. Apply

```
supabase db push --linked --include-all
  → Applying migration 073_storage_bucket_upload_constraints.sql...
  → {"upToDate":false,"dryRun":false,"migrations":["073_storage_bucket_upload_constraints.sql"],...}
```

Exactly one migration. `--include-all` is required on this repository because every sequential
`NNN_` migration sorts before the ledger's timestamp maximum (`20260731224653`).

## 3. Verification results

| # | Required | Result |
|---|---|---|
| 1 | production ledger = 87 | **87** ✓ |
| 2 | repository migrations = 87 | **87** ✓ |
| 3 | exact source↔ledger version-set equality | both md5 **`510f88a058ed80da23858878cb645e5a`** ✓ |
| 4 | `db push --dry-run` = up to date | `{"upToDate":true,…,"message":"Remote database is up to date."}` ✓ |
| 5 | bucket constraints live exactly as reviewed | ✓ (table below) |
| 6 | MIME types match the approved spec | ✓ exact |
| 7 | size limits match the approved spec | ✓ exact |
| 8 | legitimate avatar uploads succeed | **NOT EXECUTED — see §5** |
| 9 | legitimate auction-media uploads succeed | **NOT EXECUTED — see §5** |
| 10 | legitimate proof/document uploads succeed | **NOT EXECUTED — see §5** |
| 11 | disallowed MIME rejected | **NOT EXECUTED — see §5** |
| 12 | oversized uploads rejected | **NOT EXECUTED — see §5** |
| 13 | public/private visibility unchanged | **unchanged** ✓ — `auction-media` true, `avatars` true, `proof-docs` false; 073 sets no `public` column |
| 14 | storage RLS policies intact | **11 policies**, identical names / commands / roles before and after ✓ |
| 15 | no cross-user privilege regression | ✓ — every policy predicate is unchanged; 073 touches only `storage.buckets`, never `storage.objects` or any grant |
| 16 | full pgTAP green | ✓ `Files=14, Tests=252, Result: PASS` on the exact merged tree |
| 17 | fresh replay green | ✓ 87/87 applied, 0 skipped, 0 duplicates |
| 18 | pre-Scheme-B backup intact | **79 rows** ✓ |
| 19 | no real user file modified or deleted | ✓ — **172 objects before and after**; zero storage writes issued |

### Live bucket state after apply

| bucket | public | `file_size_limit` | `allowed_mime_types` | objects | **now violating** |
|---|---|---|---|---|---|
| `auction-media` | true | **10485760** | `{image/jpeg, image/png, image/webp, image/heic}` | 134 | **0** |
| `avatars` | true | **5242880** | `{image/jpeg, image/png, image/webp, image/heic}` | 9 | **0** |
| `proof-docs` | false | **10485760** | `{image/jpeg, image/png, image/webp, image/heic, image/heif, application/pdf}` | 29 | **0** |

Values are byte-identical to the reviewed specification.

**Zero of 172 existing objects violate the new constraints** — re-computed against the live catalog
*after* apply, joining every object's `metadata->>'size'` and `metadata->>'mimetype'` against its
bucket's new limits. **No stored file became invalid.**

Gate-2 unchanged: **27 tables / 69 functions / 37 policies / 24 triggers**.

**Production runs exactly the reviewed tree:** `main`'s tree and the authorized PR-head tree are the
same object, `d9f778ed91de262453937ce499b33fc6e9dd3f3f`.

## 4. Scope discipline

Confirmed **not** done: `074` not applied · `075` not applied · no Phase-2 work · no other migration
bundled · no grant, policy, cron or DDL change.

The migration's executed statements are **three `UPDATE storage.buckets`** plus two read-only `DO`
blocks. Ledger gained exactly one row; `074` and `075` are absent from the ledger.

## 5. Items 8–12 — what was NOT verified, and why

`file_size_limit` and `allowed_mime_types` are enforced by the **Supabase Storage API, not by
PostgreSQL.** `storage.objects` carries exactly two non-internal triggers and two constraints, and
none of them reads either column — this was verified independently by the adversarial reviewer
before apply. A direct SQL insert into `storage.objects` therefore bypasses both limits, before and
after 073.

Consequently:

- **What I verified is that the configuration is live and exact** (items 5–7). That is what the
  migration changes, and it is now true in production.
- **What I did not verify is that an upload is actually accepted or rejected at the API boundary**
  (items 8–12). Doing so requires issuing real uploads through the Storage REST API with an
  authenticated user session. I hold no user credentials, and manufacturing one would mean handling
  authentication secrets — which is outside what I will do unprompted, and outside the read-only
  posture this verification was run under.

**I am not claiming behavioural enforcement I did not demonstrate.** The pgTAP suite makes the same
distinction explicitly in its own header, by design.

### What supports the change despite that gap

1. **No legitimate path can break on size or type**, because every limit equals what its own client
   already enforces — `MAX_IMAGE_SIZE_MB=10` / `ALLOWED_IMAGE_TYPES`, `MAX_AVATAR_SIZE_MB=5`,
   `MAX_EVIDENCE_SIZE_MB=10` / `ALLOWED_EVIDENCE_TYPES` — and **zero of 172 stored objects violate
   the new values**.
2. The adversarial reviewer independently enumerated all four `.upload()` call sites plus every
   `storage.from()` reference and Edge Function, and confirmed **no shipped path can emit
   `image/heif` into a public bucket** (the one omission that could have caused an outage).
3. Enforcing these two columns is the documented purpose of the Storage API's bucket configuration.

### How to close items 8–12 (recommended, owner-runnable, ~5 minutes)

From the app or the Supabase dashboard, as a normal signed-in user:

| Test | Expect |
|---|---|
| Upload a normal JPEG/PNG avatar | succeeds |
| Upload a normal listing image | succeeds |
| Upload a proof document (image, and a PDF) | succeeds |
| Upload a `.txt`, `.html` or `.svg` to `auction-media` | **rejected** (415) |
| Upload a >10 MB image to `auction-media`, or >5 MB to `avatars` | **rejected** (413) |

If any *legitimate* upload is rejected, stop and report the exact MIME and size — do not widen the
constraints blindly. The known adjacent issue is recorded in §6.

## 6. Known behaviour change (disclosed pre-apply, not a regression in 073)

`src/utils/validateImage.ts:18` checks size only `if (file.fileSize)`. When expo-image-picker
returns no `fileSize` the client-side check is skipped, so an oversized file now receives a raw
Storage **413** surfaced through `useImageUpload`'s catch, instead of the friendly copy. All four
upload paths handle the storage error as a string — the reviewer confirmed none throws unhandled —
so this is degraded copy, not a break. Mapping 413/415 onto the friendly message is a UX follow-up.

## 7. Rollback

`supabase/rollbacks/073_storage_bucket_upload_constraints_rollback.sql` restores production's six
values to NULL **exactly**. It states plainly that on a fresh/CI database it goes *further* than
undoing 073 — stripping `000`'s limits from the two public buckets — so only the `proof-docs`
statement should be run there. Running it reopens SEC-3; it recommends a narrow forward fix instead
and names the four client files involved.

## 8. What this closed

Before 073, any authenticated user — signup is open — could upload **arbitrarily large objects of
any content type** into `auction-media` or `avatars`, both of which are world-readable via
`public read public buckets` (`roles: PUBLIC`, no auth predicate). The INSERT policies constrain
*where* a file lands, never *what* it is. Migration 049 compounds it: an uploader may delete only
*unreferenced* objects, so attaching hostile content to a listing made it **undeletable by its own
uploader**.

Root cause, verified at source: `000_baseline_schema.sql:242-250` and `:840-848` already declared
these limits, but both end `on conflict (id) do nothing` under the comment *"Skip if you already
created the bucket in the Storage UI"*, and production's bucket `created_at` values (2026-02-20,
2026-02-23) confirm UI-first creation. **The values never landed** — so a fresh replay has been more
restricted than production all along, the inverse of what source-reading audits concluded. That is
why 073 is an `UPDATE`.

## 9. Remaining — not covered by this authorization

- **`074`** (privilege cleanup: `webhook_retries` grants + EXECUTE cleanup) — authored, adversarially
  reviewed ACCEPT-with-conditions (applied), CI green, **NOT applied**. [PR #25](https://github.com/SnatchIt-app/snatchit/pull/25).
- **`075`** (replay parity: orphan policies + cron) — same status, proven no-op on production.
  [PR #23](https://github.com/SnatchIt-app/snatchit/pull/23).
- **Phase-2 amendment** — backend consolidation held pending four owner rulings (refund authority ·
  venue role catalog · `org_owner` payout read/request · door-manifest open/close authority) and the
  `catalog.event_session.door_open_at` lifecycle gap that the Apple Wallet offline-safety claim
  depends on.
- **Phase-2 renumber** to `076`–`091` — pending, mechanical, to be done at integration.
- **Gate-2 blindness** — it counts `pg_policies WHERE schemaname='public'` only, so storage-schema
  drift is invisible to every existing gate. Follow-up recorded, deliberately not bundled.
- Open findings unchanged: MONEY-1 (Medium, not exploitable) · F-2 / F-3 · the `buy_now_price`
  re-pricing gap (severity **unknown** pending installed-base measurement) ·
  `strict_required_status_checks_policy: false`.

---

## Verdict

**073 SEC-3 CLOSED IN PRODUCTION.**

All three buckets now carry the reviewed size limits and MIME allowlists; no stored object was
invalidated; storage RLS, bucket visibility, object count and Gate-2 are unchanged; ledger 87 with
source and ledger exactly equal; backup intact; auto-deploy still off; production running
byte-for-byte the reviewed tree.

**Behavioural upload verification (items 8–12) was not performed and is not claimed** — see §5 for
the reason and a five-minute owner-runnable procedure to close it.

`074` and `075` remain separately owner-gated and do not inherit this authorization.
