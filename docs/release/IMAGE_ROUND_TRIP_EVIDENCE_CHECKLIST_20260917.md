# Image round-trip — evidence checklist (B, 2026-09-17) — for §7 of `SANDBOX_AUTHORIZATION_LINES_20260917.md`

**Status: preparation only. Nothing here is executed or authorized.** Every step runs only after the owner speaks
the line, with A executing and D witnessing. B made **no sandbox read and no production read** for this document.
Every "expected" below comes from source. Where the live sandbox could differ from source, the checklist names the
read that settles it.

**Sources (pinned):** migrations on `fix/140-proof-upload-repair` @ `259246e` (this chain contains 133 and 135 as
the sandbox has them) · client `frontend/proof-outcome-attach` @ `5e14a68` · package `SANDBOX_AUTHORIZATION_LINES_20260917.md`
on converge @ `4dbee98`, plus A's T/P/N revision as relayed to B on 2026-09-17 (not yet committed when this was written).
Fixture ids, sandbox Vault contents and edge versions are **A's reads at 14:35:00Z / 14:35:40Z**, not B's.

Classes (A's): **T** temporary synthetic objects, removed at RT7 · **P** permanent device rows (mark sent / attach),
never removed · **N** no-write API probes.

---
## 1. Which trigger path runs on the P rows, and whether anything leaves the database (A's gap)

### 1a. Per action, from source

| Action | Triggers that run | Row change | `public.notifications` | Outbound HTTP |
|---|---|---|---|---|
| **P** mark sent, pending → seller_sent (DV-IMG-4 `92ee5156`, DV-IMG-9 `3118bd30`, DV-IMG-5 `bce07eef`) | BEFORE `trg_guard_transfer_state_columns` (bypass on, 140:91) · AFTER `trg_notify_transfer_sent` (034:101-105; `UPDATE OF status`, WHEN true) → `notify_transfer_event` as redefined by 133 · AFTER `trg_notify_transfer_state_inbox` (058:237) · statement `trg_reset_transfer_guard_bypass` · `trg_notify_dispute_opened` WHEN false | `status` seller_sent, `seller_sent_at` = now, **`auto_release_at` = now + 72 h** (140:95), `transfer_evidence_path` = the uploaded name | **+1**: buyer `919d511e`, type `buyer_confirmation_needed`, dedupe `buyer_confirmation_needed:<transfer id>` (058:171-178 via 057:65-88, which only INSERTs) | **None attempted.** 133's `notify_transfer_event` posts only `IF v_key IS NOT NULL AND v_url IS NOT NULL` (133:145); with no `service_role_key` in Vault, `net.http_post` is never called |
| **P** attach, DV-IMG-10 `8f59d37e` (seller_sent, path null) | BEFORE guard (no bypass; null → value is allowed) · AFTER `trg_notify_transfer_state_inbox` **runs** (AFTER UPDATE, no column list, no WHEN) but writes nothing, because none of its five conditions changes · statement bypass reset · `trg_notify_transfer_sent` does **not** fire (`status` is not in the SET list, 140:184-185; its WHEN would be false anyway) | `transfer_evidence_path` null → value only | **+0.** The buyer is **not** told that proof was added. That is a source fact, not a defect claim | None |
| **N** mark sent again on `92ee5156`, same path and then a different path | none: returns `already_sent` before any UPDATE; takes a `FOR UPDATE` row lock only | unchanged | +0 | None |
| **N** mark sent with a path on `8f59d37e`, **before** DV-IMG-10 | none: raises `precondition_failed: transfer already sent without evidence — use attach_transfer_evidence` | unchanged | +0 | None |
| **N** attach with the same path on `8f59d37e`, after DV-IMG-10 | none: returns `already_attached` (140:175-177) before the UPDATE | unchanged | +0 | None |
| **N** attach with a different path, after DV-IMG-10 | BEFORE guard raises `transfer_evidence_path is append-only.`, **but only if the path names an existing object** (see §4 C4) | unchanged (the statement rolls back) | +0 | None |

`public.notifications` has no trigger anywhere in the chain (grep of every `CREATE TRIGGER`), so an inbox row never
causes a push by itself. **A's expectation of "inbox rows only" holds.**

### 1b. Two corrections to A's expectation

- **C1: expect no attempt at all, not a 401.** Given 133's body, a `notify-transfer` post cannot be queued while Vault
  lacks `service_role_key`. A 401 (or any response) that traces to `notify-transfer` would mean the **live body differs
  from 133's source**. That is a stopping condition in its own right, alongside A's 2xx.
- **C2: `net._http_response` cannot show the absence of a `notify-transfer` post.** pg_net keeps the URL only in
  `net.http_request_queue`, and a row leaves the queue once the worker processes it. The response table has no URL, so
  a later read cannot attribute a response to a function. **A confirms this column list with a catalog read on the
  sandbox before relying on it.** Posts from other sources are expected during the window, per source:
  - 133's HTTP crons post whenever `project_url` exists. `enforce-transfer-expiry` runs every 2 min with
    `'Bearer ' || NULL` as its Authorization (133:363-381), and the edge refuses a token that matches neither secret
    (enforce-transfer-expiry/index.ts:151-175).
  - 135's push-token challenge posts to `send-push` with `coalesce(service_role_key, '')` (135:122-135) if the handset
    registers a push token during the window.

  So "no `notify-transfer` post" is evidenced by three things, not by response counts:
  1. the **live body of `public.notify_transfer_event` matches 133's source** (`md5(pg_get_functiondef(...))` against
     the same computed on a local replay at the pin);
  2. a **name-only Vault read** at the window's start and end shows no `service_role_key`;
  3. optionally, **zero `notify-transfer` invocations** in the sandbox edge logs over the window, read at least 10 min
     after it closes (ingestion lag).

  **Any 2xx whose origin cannot be attributed is a stop.**

---
## 2. Preconditions: reads before the first P or N step (A reads, D witnesses)

| # | Read | Expected | If not |
|---|---|---|---|
| PC1 | CS-1 sandbox identity assertion | `ofaidukbieeekqaboscm` | stop |
| PC2 | Vault secret **names** | `project_url` present, `service_role_key` absent | stop: a present key changes §1 and C10 |
| PC3 | `md5(pg_get_functiondef)` for `notify_transfer_event`, `notify_transfer_state_inbox`, `enqueue_notification`, `guard_transfer_state_columns`, both `mark_transfer_sent` overloads, `attach_transfer_evidence` | equal to a local replay at the pin that the sandbox apply used | stop: §1 is source-derived and holds only for these bodies |
| PC4 | `pg_trigger` on `public.transfers` (name, enabled, `tgtype`) | exactly: `trg_guard_transfer_state_columns`, `trg_notify_transfer_created`, `trg_notify_transfer_sent`, `trg_notify_transfer_created_inbox`, `trg_notify_transfer_state_inbox`, `trg_notify_dispute_opened`, `trg_reset_transfer_guard_bypass` | stop: an extra trigger is an unmodelled side effect |
| PC5 | `pg_policies` on `storage.objects` whose qual or check mentions `proof-docs` (name, cmd, roles, qual, with_check) | the five in `supabase/tests/100_storage.sql:40-44`, quals equal to 033/034/049/053; no `proof-docs operator read` (production only, per the contract) | stop |
| PC6 | `storage.buckets` row `proof-docs` | `public=false`, 10 MiB, allow-list `{image/jpeg,image/png,image/webp,image/heic,image/heif,application/pdf}` | stop |
| PC7 | each P transfer: status, seller, buyer, path, `auto_release_at`, `payout_released_at`, dispute state; the buyer's count for dedupe `buyer_confirmation_needed:<id>` | as A read at 14:35:00Z; dedupe count 0 for the three pending | stop |
| PC8 | folder `2f5844b4…/transfer-evidence/`: total count, and the `rt-%` count | A's 14:35:00Z values (0 / 0), or the current values recorded as the new baseline | record; RT stops on `rt-%` ≠ 0 |

---
## 3. The checklist, by the owner's six items

For every step, record: the UTC time, the actor (seller JWT / buyer JWT / third account / anon), the HTTP status, the
exact error text, and the values listed. Never record a credential.

### Item 1: actual bytes against declared type

*Storage trusts the declared `contentType` and does not inspect bytes. A download's `Content-Type` echoes the
declaration, so it is **not** evidence of what the bytes are. Matching the MIME allow-list is not evidence that the image renders.*

| Class | Record | Expected | Stop / finding |
|---|---|---|---|
| T, at generation | first 16 bytes (hex), length, sha256 of each synthetic file; for the HEIC, the major brand at bytes 8-11 | PNG `89504e470d0a1a0a`; JPEG `ffd8ff`; HEIC `....66747970` + brand. **Derive the declared type from the bytes with the client's table** (uploadFlow.ts:77-96: `heic/heix/hevc/hevx/heim/heis` → `image/heic`; `mif1/msf1/heif` → `image/heif`), never from the file extension | if the brand maps to `image/heif`, declare `image/heif` and note that the name's `.heic` extension disagrees with the client's naming rule (not a storage stop) |
| T, RT1 | `storage.objects.metadata->>'mimetype'`, `->>'size'`, `->>'eTag'` | mimetype = declared, size = local length | stop on a mismatch |
| T, RT3 | first 16 bytes of the downloaded body, and the `Content-Type` header | bytes equal to local; header = declared | stop |
| P, each object (DV-IMG-4, -9, -5, -10) | object name, `created_at`, metadata mimetype/size/eTag; seller-signed download: length, sha256, first 16 bytes | **name extension ↔ mimetype ↔ magic bytes all agree** (the client derives the type and the extension from the bytes: useImageUpload.ts:180-190, uploadFlow.ts:135-137). **DV-IMG-9 (HEIC camera photo): expect `.jpg`, `ffd8ff`, `image/jpeg`**, because the picker is asked for the Compatible representation (useImageUpload.ts:121-122) | a disagreement means the object was not written by the 5e14a68 client: record the installed build. `.heic` with `ftyp` bytes on DV-IMG-9 means Compatible mode did not convert: a **finding for C**, not a storage failure |

### Item 2: sha256 integrity, upload against download

| Class | Record | Expected | Limit |
|---|---|---|---|
| T | sha256 local → sha256 of the RT3 download | equal ×3 | proves integrity end to end for synthetic bytes only |
| P | sha256 of the seller's download; the same from the buyer's download (item 3); `metadata.size` against download length; `metadata.eTag` against md5 of the download | seller = buyer; size equal | **Device upload integrity cannot be proven off-device.** The buffer the handset sent is not observable, and the picker may transcode. An eTag match counts as server-side receive integrity **only if the eTag is a plain 32-hex MD5**. Record the raw eTag, and claim nothing if it is in any other form |

### Item 3: seller access, and buyer access to a referenced object only

| Step | Actor | Target | Expected | Why it discriminates |
|---|---|---|---|---|
| S1 | seller | each T object (RT3), each P object | sign 200, download 200 | owner read (033:155-159) |
| RT4 | buyer | each T object (unreferenced) | denied at **signing** and at **authenticated download** | no transfer references it |
| **RT6** | buyer | DV-IMG-10's attached object (after DV-IMG-10), and each P object from DV-IMG-4/-9/-5 | sign 200, download 200, sha256 = seller's | transfer party read (034:112-122) |
| RT6-neg | buyer | an **unreferenced** object in the same folder at the same time (a T object while one exists, or an orphan from §3 item 6) | denied | same folder, same seller, same buyer. Only "referenced" differs |

**How denial is measured:** Storage typically reports an RLS-denied read as *object not found*, which looks the same as
a missing object. A denial therefore counts **only when paired with the seller's successful read of the same name
within the same minute** (the positive control). **Never test denial by fetching a URL the seller signed.** A signed
URL works for whoever holds it until it expires, by design, so its success says nothing about the policy.

### Item 4: denial for an unrelated user and for anon

| Step | Actor | Target | Expected |
|---|---|---|---|
| RT5 | anon | each T object | denied (with the positive control) |
| RT5-P | anon | one referenced P object | denied (with the positive control) |
| **U1** | **third authenticated account: not the buyer, not the seller, not an evidence operator** | one **referenced** P object | denied at signing and at authenticated download |

**C5: without U1, item 4 is not established.** With only the seller, the buyer and anon, a transfer-party policy
that **lost its party predicate** (`EXISTS (a transfer with that path)`, with no buyer or seller check) produces the
same result on every other check here:
- the seller is allowed through owner read;
- the buyer is allowed on referenced objects;
- the buyer is denied on unreferenced objects, because no transfer references them;
- anon is denied, because the policy is `TO authenticated`.

All five P transfers also share one buyer, so per-transfer scoping (buyer of X reading Y's proof) is not exercised
either. **Whether a third account is used, and which one, is the owner's call.** Without it, record item 4 as
"anon denied; unrelated authenticated user UNTESTED". Local coverage does not close the gap:
`supabase/tests/100_storage.sql:34-45` asserts that the policies **exist**, not how they behave for a non-party.

### Item 5: retry after a lost response, and explicit Add proof

| Step | Class | Call (seller JWT, the handset's path; not service_role, not psql) | Expected reply | Row read-back | Inbox |
|---|---|---|---|---|---|
| N1 | N | `mark_transfer_sent(92ee5156, seller, <DV-IMG-4 path>)` after DV-IMG-4 | `outcome=already_sent`, `evidence_replaced=false`, path = DV-IMG-4's | status, `seller_sent_at`, `auto_release_at`, path all equal to the post-DV-IMG-4 read | +0 |
| N2 | N | same, with a **different** path string | same as N1; returned path is still DV-IMG-4's | unchanged | +0 |
| N3 | N | `mark_transfer_sent(8f59d37e, seller, <any path>)` **before** DV-IMG-10 | error text exactly `precondition_failed: transfer already sent without evidence — use attach_transfer_evidence` | unchanged (path null) | +0 |
| DV-IMG-10 | P | handset Add proof | device shows "Proof added"; RPC `outcome=attached` | path null → the uploaded name; nothing else changes | +0 |
| N4 | N | `attach_transfer_evidence(8f59d37e, <DV-IMG-10 path>)` | `outcome=already_attached` | unchanged | +0 |
| N5 | N | `attach_transfer_evidence(8f59d37e, <a different path that names an EXISTING object in the seller's transfer-evidence folder>)` | error `transfer_evidence_path is append-only.` | unchanged | +0 |

**C3: on the handset, DV-IMG-10 can only produce `attached`.** The Add proof block renders only while
`status === 'seller_sent' && !transfer_evidence_path` (send/[id].tsx:372). After `attached`, the handler re-reads the
transfer (send/[id].tsx:209-211), so the block disappears. `already_attached` and the append-only refusal cannot be
reached from one handset screen, which is why they are N4 and N5 above. The device row's own evidence is `attached`
plus the read-back.

**C4: N5 is vacuous unless its path names an existing object.** 140 checks existence (140:169-171) before it checks
the path against the current value (140:175) or reaches the UPDATE. A path to nothing is refused with
`no such object in proof-docs`, so the guard is never exercised. That is the "fixture must let the branch vary" rule.
The owner chooses:

- **(a) Name a T object while it exists (between RT1 and RT7).** No new object is created. **Failure mode:** if the
  guard does not refuse, the T object becomes referenced (RT7 can no longer delete it) and `8f59d37e`'s evidence is
  replaced. Both are permanent, so it is a stop.
- **(b) Do not run N5 live.** Rely on PC3's body-hash equality with the tested 207 (R-series, mutant-verified) and 050.
- B's recommendation is **(b)**, unless the owner wants the live refusal. PC3 already ties the sandbox bodies to
  tested code, and (b) risks nothing.

**Ordering constraint:** N3 must run before DV-IMG-10, and N1/N2 after DV-IMG-4.

### Item 6: what is removed and what is retained

| Object class | Fate in this window | Evidence to record |
|---|---|---|
| T `rt-20260917-{1,2,3}` | deleted at RT7 by the seller (owner delete unreferenced, 049:37-52) | 200 ×3; **`rt-%` count** 3 → 0 |
| P referenced (DV-IMG-4, -9, -5, -10) | retained | names and sha256 at the window's end |
| Orphans: objects uploaded by a refused, failed or unconfirmed device attempt (a retry reuses the same name, useImageUpload.ts:165-170; a new selection makes a new name) | **retained**, no deletion (owner's 30-day direction) | every non-`rt-` name in the folder not referenced by any transfer, with `created_at`: the input the future dry-run will see |

**Closing equation** (end of window): folder total = baseline (PC8) + referenced P objects (4) + listed orphans, and
`rt-%` = 0. An object that fits none of these terms is a stop.

**C7:** RT7's read-back must use the **`rt-%` count**. The package says "the folder count returns to the pre-count",
which is false as soon as a P object lands between RT1 and RT7.

**C8: do not test "referenced objects cannot be deleted or overwritten" live against P objects.** A failing control
would destroy retained evidence. The evidence is PC5's policy-qual equality with 049 (delete) and 053 (update), plus
the RT2 409 for `upsert:false`. B knows of no local behavioural test of those two policies against a referenced
object. That is a gap, which B can write locally if asked.

---
## 4. Consequences of the P rows beyond the window

- **C10:** each mark sets `auto_release_at` = now + 72 h, and attaching evidence sets the payout-policy input
  `has_evidence` (payout-policy.ts:70-71). While the expiry sweep cannot authenticate, nothing happens; the two
  already-sent fixtures, past 2026-09-11 and still unreleased, fit that. If `service_role_key` ever appears in the
  sandbox Vault, or the cron's secret matches, all five P transfers become **auto-release candidates**. Record this
  in the package as a property of the P class, and treat PC2 at the window's end as part of the evidence.
- **Contract precision** (`PROOF_UPLOAD_REPAIR_CONTRACT.md`, "nothing fires on an evidence-path-only UPDATE"): the state-inbox
  trigger and the guard **run** on that UPDATE. What is true is that **nothing is written and nothing is posted**. §1a
  gives the exact form.

## 5. Evidence limits (what none of this proves)

- That the image **renders** on the seller's thumbnail, the buyer's receive screen, the web receive page or the
  operator console. That is C's device rows and the owner's eyes.
- HEIC conversion on devices other than the handset used, or on builds other than the one installed. Record that build.
- That the device's uploaded buffer equals the stored object (item 2 limit).
- Anything about production.

## 6. Local check B ran (scratchpad only; no shared environment)

Generated a 1×1 PNG, then a JPEG and a HEIC from it with `sips`, on macOS 26.5.2:

```
rt-local-1.png    69B  89504e470d0a1a0a0000000d
rt-local-2.jpg   777B  ffd8ffe000104a4649460001
rt-local-3.heic  552B  000000186674797068656963  brand=heic
```

On this machine, `sips` writes major brand `heic`, which the client's table maps to `image/heic`, and all three files
are under 10 KiB. A's files may come from another Mac, so **record the brand of the actual file** instead of relying
on this line.
