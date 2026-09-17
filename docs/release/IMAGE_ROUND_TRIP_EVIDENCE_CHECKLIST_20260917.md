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

## 0. Adopted, and what the owner settled (2026-09-17)
This checklist was adopted byte-identical (sha256 `d718ec47…69a3`, from `fb25c9e`) into A's approval package and folded into
its Line 3 and package §5-§8 (converge `4516d14`). **The package governs execution.** This file keeps the source trace, and
from §7 down the matrix, the deadline tracking and the cross-checks the owner asked for on 2026-09-17. Its open items are closed:

| Was open here | Settled |
|---|---|
| C4 options for N5 (attach with a different path) | **Option (b): N5 is not run.** No delete or overwrite of attached proof. Evidence instead: PC3 body equality, the preserved local 207 R-series (mutant-verified) and 050, PC5 policy-qual equality |
| C5 third identity | **U2 `f53b8466-9571-4f41-88c3-1c33847dd8ee`**, an existing sandbox account; A's read 14:51:11Z: active, party to none of the five transfers. Until that read runs, unrelated-user denial stays **UNTESTED** |
| PC3 method | **`md5(prosrc)` + `length(prosrc)`** (PF3's method), not `pg_get_functiondef`, which the server regenerates and can differ without a code change. Values in §7b; A's harness matched all seven independently |
| §1b item 3, `notify-transfer` edge logs | **Dropped as vacuous:** `notify-transfer` is not among the sandbox's nine deployed functions (A, 14:35:40Z), so zero invocations would prove nothing |
| Activation gates for the P rows | `service_role_key`, `payout.executor_enabled`, `refund.executor_enabled`, **and** a manual `enforce-transfer-expiry` call with `INTERNAL_CRON_SECRET` (`index.ts:165-170`). The re-read is a plain SELECT on 039's predicate, never `get_auto_release_candidates()`, which PERFORMs `refresh_seller_risk_score` |
| Metadata on DV-IMG-9 (added by B) | The photo is taken with **Camera location off**, or Photos › Info shows no location before picking: expo-image-picker 17.0.10 returns `.heic` as raw data carrying the original's GPS (`ios/ImageUtils.swift`), and `exif: false` only limits what JavaScript receives. A records GPS-block present yes/no, never values |

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
| **N** attach with a different path, after DV-IMG-10 | BEFORE guard raises `transfer_evidence_path is append-only.`, **but only if the path names an existing object** (see §3 item 5, C4) | unchanged (the statement rolls back) | +0 | None |

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
  3. ~~optionally, zero `notify-transfer` invocations in the sandbox edge logs~~ — **dropped as vacuous (§0):** that
     function is not deployed on the sandbox, so its logs are silent either way.

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

---
## 7. Actor matrix and the class of every check (owner's request, 2026-09-17)

**Classes:** **T** temporary (removed in the same run) · **P** permanent (cannot be removed) · **N** no write (a verb that
answers without writing) · **R** read-only · **D-NR** destructive, deliberately **not run** · **U** must remain untested.

| # | Actor | Check | Class | Expected | If it goes the other way |
|---|---|---|---|---|---|
| RT1 | seller | upload three synthetic files, `upsert:false` | T | 200 ×3; metadata mimetype = declared, size = local length | stop |
| RT2 | seller | re-upload the same name | T | 409; the object id unchanged | stop |
| RT3 | seller | sign + download each | R | 200; sha256 and first 16 bytes equal to local; `Content-Type` = declared | stop |
| RT4 | buyer | sign + authenticated download of each T object (unreferenced) | R | denied at both, paired with the seller's 200 on the same name in the same minute | stop |
| RT5 | anon | the same | R | denied, same pairing | stop |
| RT7 | seller | delete the three T objects | T | 200 ×3; `rt-%` count 3 → 0 | report surviving names, stop |
| DV-IMG-4 | handset (seller) | offline then online Mark as sent | **P** | one object, one transition, buyer inbox +1 | record as it stands |
| DV-IMG-5 | handset (seller) | two quick taps | **P** | one upload, one verb call, one success | record |
| DV-IMG-9 + 3b | handset (seller) | synthetic screenshot, Replace with a HEIC camera photo, Mark as sent | **P** | `.jpg` / `ffd8ff` / `image/jpeg`; no GPS block | PNG bytes → 3b FAILS; `.heic` + `ftyp` → outcome 3 FAILS (a finding for C, not a storage failure) |
| DV-IMG-10 | handset (seller) | Add proof | **P** | `attached`; path null → name; **+0 notifications** | record |
| N1 | A, seller JWT | `mark_transfer_sent(92ee5156…, seller, <same name>)` | N | `already_sent`, `evidence_replaced=false` | any write is a stop |
| N2 | A, seller JWT | the same with a different path string | N | `already_sent`; returned path still DV-IMG-4's | stop |
| N3 | A, seller JWT | `mark_transfer_sent(8f59d37e…, seller, <any path>)` **before** DV-IMG-10 | N | exactly `precondition_failed: transfer already sent without evidence — use attach_transfer_evidence` | stop |
| N4 | A, seller JWT | `attach_transfer_evidence(8f59d37e…, <same name>)` after DV-IMG-10 | N | `already_attached`; row identical | stop |
| N5 | — | attach with a different existing path (append-only refusal) | **D-NR** | **not run** (owner ruling 2) | — |
| — | — | delete or overwrite a referenced object | **D-NR** | **not run**: a failing control would destroy retained evidence | — |
| RT6 | buyer | sign + download each of the four P objects | R | 200; sha256 = the seller's download | stop |
| RT6-neg | buyer | an unreferenced object in the same folder (covered by RT4) | R | denied | stop |
| U1 | **U2 account** | sign + authenticated download of DV-IMG-10's object | R | denied at both, with the pairing | stop |
| RT5-P | anon | the same object | R | denied, with the pairing | stop |
| — | — | device **upload** integrity (sha256 of the bytes the handset sent) | **U** | not observable off-device | — |
| — | — | per-transfer scoping (buyer of X reading Y's proof) | **U** | all five transfers share one buyer | — |
| — | — | render on the web receive page | **U** | its Supabase host is fixed at build time | — |
| — | — | Android (DV-IMG-8), push delivery, payout behaviour, older installed clients | **U** | out of scope | — |

**Reading discipline for every denial:** measured at signing **and** at authenticated download, never through a
seller-signed URL (a signed URL is a bearer capability by design), and only counted with the seller's positive control
alongside it, because storage reports an RLS denial as not-found.

### 7b. PC3 expected values (B's local replay at `259246e`, PG 17.11; matched independently by A's harness)
`259246e..6561d1f` changes **0 lines** under `supabase/migrations`, so these hold at the current gate head `6561d1f`.

| Function | md5(prosrc) | length |
|---|---|---|
| `notify_transfer_event()` | `49146f9f3ba9a96aaaf09c3f21492c40` | 1361 |
| `notify_transfer_state_inbox()` | `203f7c7d88c6545a9c083e037a6aa5db` | 3442 |
| `enqueue_notification(uuid,text,text,text,text,text,jsonb)` | `1e11b92d7258ea66feebbac05cf9298b` | 518 |
| `guard_transfer_state_columns()` | `c423ef62372e43e5c4c91e5e83976782` | 1951 |
| `mark_transfer_sent(uuid,uuid,text)` | `17453329765e9e0787732fd61846a399` | 2560 |
| `mark_transfer_sent(uuid,uuid)` | `d816c53e9e1e77e7de8d432d7ecf9680` | 86 |
| `attach_transfer_evidence(uuid,text)` | `67615b89040a9f60dd6082d1cf54cbcd` | 2690 |

Triggers on `public.transfers`, exactly seven, all enabled: `trg_guard_transfer_state_columns`,
`trg_reset_transfer_guard_bypass`, `trg_notify_transfer_created`, `trg_notify_transfer_created_inbox`,
`trg_notify_transfer_sent`, `trg_notify_transfer_state_inbox`, `trg_notify_dispute_opened` (which runs
`notify_moderation_event`, whose WHEN is false for these rows). `proof-docs` policies: **five** on the sandbox — 118's
`proof-docs operator read` belongs to the ledger the sandbox does not carry.

---
## 8. The five transfers: deadlines and the safeguards that keep them unprocessed

No payment state is changed by anything in this file. Deadlines for the three pending rows exist only once the handset
marks them sent; B fills them from A's read-back records, not from any read of its own.

| Transfer | Row | State before (A, 14:35:00Z) | auto_release_at | After |
|---|---|---|---|---|
| `92ee5156-7e82-40d8-ab54-73b489997797` | DV-IMG-4, N1, N2 | pending, no proof | none | `seller_sent_at` + 72 h — **to record** |
| `bce07eef-ed72-4d85-96db-8ef340838b89` | DV-IMG-5 | pending, no proof | none | `seller_sent_at` + 72 h — **to record** |
| `3118bd30-276f-4183-8579-cfea852421cb` | DV-IMG-9 + 3b | pending, no proof | none | `seller_sent_at` + 72 h — **to record** |
| `8f59d37e-52fd-4733-b311-532445ff441c` | N3, DV-IMG-10, N4, RT6, U1, RT5-P | seller_sent, no proof | **2026-09-11T01:20:24Z (past)** | proof attached; deadline unchanged (attach does not move it) |
| `83b83858-7c96-4887-bf6c-447858aec22a` | none | seller_sent, no proof | **2026-09-11T00:54:49Z (past)** | untouched; its exposure pre-dates this test |

**Why nothing is processed today** (each a read, never a change): `payout.executor_enabled` false · `refund.executor_enabled`
false · no `service_role_key` in the sandbox Vault, so the every-2-minute `enforce-transfer-expiry` post carries a null
bearer and is refused · no manual call with `INTERNAL_CRON_SECRET`.

**Safeguard that must hold** (package §5a, manifest standing precondition): any future activation of one of those four
re-reads all five transfers, plus every other transfer the sweep or the payout executor would select, with a plain SELECT on
039's predicate — `status='seller_sent' and auto_release_at is not null and auto_release_at < now() and payout_released_at
is null and (payout_hold_until is null or payout_hold_until < now()) and payout_review_status is distinct from
'manual_review'` — and carries an owner-approved disposition for each. Choosing a disposition (hold, resolve, refund, or
allow a test payout) is a payment-state decision for the owner at that time. **Not now, and not by B.**

**One consequence worth stating plainly:** attaching proof to `8f59d37e…` removes the payout policy's `EVIDENCE_MISSING`
reason (`payout-policy.ts:70-71` reads `has_evidence`) on a transfer whose deadline has already passed. It stays unprocessed
only because of the four gates above — not because of anything about the row itself.

---
## 9. The contract's expected outcomes, checked against the applied source

`PROOF_UPLOAD_REPAIR_CONTRACT.md` §1–§5 as amended by §8. Checked against migration 140 at `259246e`, the guard chain
(0550/0562/0563), the client at `6561d1f`, and the storage policies (033/034/049/053).

| Area | Contract | Source | Verdict |
|---|---|---|---|
| Mark as sent, `pending` | transition; `outcome=transitioned` | 140:91-102 sets status, `seller_sent_at`, `auto_release_at`=now+72 h, path via coalesce, under the bypass GUC | **matches** |
| Already sent | no UPDATE; `already_sent`; `evidence_replaced` always false; null, same **and** different path; no second notification | 140:76-85 returns before any UPDATE; 207 R4 asserts `xmin` unchanged | **matches** |
| Already sent with a null stored path and a non-null argument | raise `precondition_failed … use attach_transfer_evidence` | 140:76-79, that exact text | **matches** |
| Other statuses | raise as before | 140:88 | **matches** |
| Attach proof | seller; `seller_sent`; path null; non-empty; own folder; `%/transfer-evidence/%`; object exists; no bypass; `already_attached` on the same path; guard refuses a different one | 140:130-190 in that order; the existence check precedes the same-path check | **matches** |
| Attach, buyer notification | v1 sends nothing | +0 rows; the state-inbox trigger runs and writes nothing | **matches** |
| Duplicate upload | pick-time name + `upsert:false`; after any error `storage.exists` decides; a 409 is not trusted alone | useImageUpload.ts:180-205; upload 120 s, exists 30 s | **matches §8 item 3** |
| Byte/type integrity | type and extension from the bytes; unrecognised refused; a reported non-allowed type refused at pick | uploadFlow.ts:82-96, 135-137; `sniffImageType` decides; `mif1/msf1/heif` → `image/heif`, the six HEIC brands → `image/heic` | **matches §8 item 2** |
| Access denial | owner read; transfer-party read; no anon policy; operator read production-only | 033/034 + PC5; buyer reads any object referenced by a transfer where they are a party | **matches**, with §3 item 4 of this file: a non-party authenticated reader is the only check that discriminates |

**Four places where the contract's text no longer matches what shipped or what the owner ruled.** None changes 140's
behaviour; each is a sentence that would mislead a reader of the contract alone:
1. **§2 "the row's `updated_at` moves and nothing else" — there is no such column.** `public.transfers` (002:35-68, plus every
   later `add column`) has `created_at` and `seller_sent_at`, and no `updated_at`; no trigger on the table sets one. So an
   attach leaves **no timestamp of its own**: `seller_sent_at` keeps the original mark time, and the only record of when proof
   arrived is the storage object's `created_at`. Worth stating in the contract, since this is dispute evidence.
2. **§5 RT4's "Proves: unrelated-user denial"** — a buyer denied on an *unreferenced* object does not establish that. Line 1
   in the package has been corrected; the contract's own table has not.
3. **§5 RT7's "count for the folder back to the pre-count"** — must be the `rt-%` count once Line 3's objects exist (C7).
4. **§1's "the second upload is an orphan the client may delete under the owner-delete policy"** — the client never deletes,
   and the owner's 30-day direction forbids deletion without a dry-run and an explicit word.

---
## 10. F-NOTICE-1 and F-BIDS-1 against the package

**F-BIDS-1** (Bids empty state while purchases load): C's fix is integrated for the next candidate at
`release/production-gate-20260918 @ 6561d1f`, CI 35245103799. Consistency checks: `f412d10..6561d1f` touches **nothing** under
`supabase/` and `259246e..6561d1f` **nothing** under `supabase/migrations`, so the apply package's file hashes and this file's
PC3 values still hold at `6561d1f`. One wording item for A: the package certifies PC3 against `259246e..f412d10`; the gate head
is now `6561d1f`, and the statement should name it.

**F-NOTICE-1** (stale "Account deletion requested" on an ACTIVE account) — one real collision with the staged-notice step:

- `account_deletion_pending` is registered `delivery_class='mandatory'`, `target_kind='account_security'` (092:276), which is
  exactly the set `public.get_my_security_notices()` derives (136:96-99). The buyer's stale row `f3abe550…` (2026-09-14, unread,
  undismissed) is therefore **returned by that RPC**.
- The client shows **one** notice: `selectActionableNotice` takes the newest unread row of any returned type
  (`src/lib/security/notices.ts`).
- So: **DV-N-1** is unaffected (the staged notice is newer and wins). **DV-N-2** dismisses it. **DV-N-3's "relaunch → not
  shown" will show a banner titled "Account deletion requested"** (092:346, the in-app v1 template) — the pre-existing
  F-NOTICE-1 row taking the surface. Recorded as written, DV-N-3 reads as a FAIL that is not one.
- **Fix for the package, A's call:** state DV-N-3's expectation as "the *staged* notice is gone; a pre-existing
  `account_deletion_pending` banner may replace it", and have the observer record the notice **by title or id**, not by
  presence.
- **Ordering, if F-NOTICE-1 §4 is ever authorized:** that write marks the buyer's notice read and dismissed, which moves the
  buyer's notification totals. It must not land between the staged-notice step's pre-count and its restore read, nor between
  Line 3's inbox-delta reads. The safe positions are before the sequence or after it closes.
- Option A (retire the notice inside `kernel.withdraw_account_deletion`) is a kernel-verb change: it needs a migration number,
  and PC3-style body hashes for the changed verb, in whichever package carries it. Not this one.

### 10b. Review of A's F-NOTICE-1 fix branch (B, 2026-09-17, read-only)
`fix/f-notice-1-withdraw-retires-notice @ c70a9a6` — migration 141, rollback, pgTAP 208. Unapplied. Checked from source:

**Sound, and verified rather than taken on trust:**
- The retire lives in `notify.retire_account_deletion_pending(uuid)`, called from `kernel.withdraw_account_deletion`, so the
  157 A48 seam (no kernel routine touches notify's tables) holds. Revoked from public, anon, authenticated **and** service_role.
- Census pins move together: notify 22 → 23 (157 A14), the A15 signature list, definer count 20 → 21 (A16), five-schema
  305 → 306 (148 A20, 156, 157 A46, 204).
- The rollback restores 077's body **byte-identical** (both 1153 chars, diffed) and drops the notify function *after* the
  restore, so no dependency is left dangling.
- No timestamped migration redefines `kernel.withdraw_account_deletion` (only 077 and 141), so the LC_ALL=C
  overwrite trap does not apply.
- 208's fixture calls match the real signatures (`notify.enqueue(uuid,text,text,uuid,jsonb,text)`; `purchase_confirmed` is a
  registered type), and plan(19) equals the 19 assertions.

**Two findings sent to A — both closed at `ea547e5` (branch head; the fixes landed in `b865b68`, and `ea547e5` added D's `lock_timeout`). What I verified myself, by reading the source at `ea547e5`:** 208's header now enumerates the matrix, and its enumeration matches the derivation I had done independently (regression B3, C3, D4; widening controls C1, C2, D3; revoke F1–F3; the remainder pass either way) · F1/F2 pin the revoke against anon, authenticated and service_role, F3 also pins `lock_timeout=2s` · `plan(22)` equals 22 assertion lines, counted mechanically · C3 is now a delta against a pre-count, so a database carrying unrelated retired notices cannot fail it spuriously. **A's evidence, not mine:** 208 22/22 and the full suite 5319/5319 on A's harness, and the measured rollback run behind the header's matrix. **D's evidence, not mine:** the review that produced `lock_timeout`. I ran nothing on A's branch. **New observation (source-only, sent to C):** because the retire is deliberately not best-effort, a lock timeout now aborts the withdrawal, so `kernel.withdraw_account_deletion` can fail where it previously could only succeed or noop — the Withdraw deletion request screen's copy for that case is worth a look.

**The findings as sent:**
1. **208's header claim is not generated from its matrix.** It says "Every assertion here fails on 077's body". On 077's body
   only **B3, C3 and D4** fail; A1–A7, B1, B2, C1, C2, D1–D3, E1 and E2 all pass, by design — they are fixtures and
   unchanged-behaviour controls. The widening controls are C1 (by type), C2 (by user) and D3 (the coalesce). Same class as
   207's header sentence I got wrong, and the same rule applies: a header claim about a matrix is generated from it.
2. **141's revoke is unpinned.** No assertion checks that the new notify function is unreachable by anon, authenticated or
   service_role. `204:45-48` is the shape to copy (three `has_function_privilege` checks; plan 19 → 22), and without them a
   later grant would break the discipline with every test still green.

**Two observations, not defects:** the retire sits after the `noop_replay` early return, so the fix is forward-only — an
account already ACTIVE with a stale notice is never healed by it (the buyer's row stays for the owner's scoped plan); and
208 C3's "exactly ONE row in the database is retired" holds on a fresh database, which CI and the rehearsal harness give,
but would fail spuriously on a database carrying unrelated retired notices.
