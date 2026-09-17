# Line 3 — D's witness checklist (prepared 2026-09-17, NOT executed)

**Status: PREPARED ONLY.** The owner authorized Line 3 to A and to D directly, then went away for about two hours
with: "Prepare the witness checklist for Line 3, but do not execute permanent transfer writes or upload proof while I
am away." D executes nothing here and takes no Line 3 witness read until the owner returns and the DV-ST2b window is
fully closed (including A's API-log check).

D's role is read-only witness. D runs no step, touches no handset, uploads nothing, and writes nothing.

## 0. Preconditions, all four required before the first read

| # | Precondition | How D confirms it |
|---|---|---|
| P1 | The owner has said Line 3 may proceed, to D, and is present | their words in D's conversation |
| P2 | DV-ST2b is fully closed | A's API-log check landed and the row is classified; D's after-read already matches |
| P3 | A's pre-check and D's pre-check agree | D's `d_img_line3_pre-l3.txt`, md5 `f66988847bc875c6c14a346b2ed94a95`, identical to the approved post-W-C3 baseline; A's PC1–PC8 agreed on every value |
| P4 | Grants work since the pre-check is re-verified | after DV-ST2b, A re-reads PC2/PC3 and the bids ACL; the seven function body md5s must equal D's pre-check values |

The revoke and restore in DV-ST2b touched grants, so P4 is not optional: a function body or ACL that moved between the
pre-check and the first write would make every later comparison meaningless.

## 1. What D reads, and when

Command (read-only, sandbox only, no-overwrite, refuses a production ref):
`bash d_img_witness.sh line3 <label>`

| Point | Label | Purpose |
|---|---|---|
| before the first row | `pre-l3` (taken) | the baseline every later read is compared against |
| after step 0 (picker-only rows) | `after-step0` | prove the picker-only rows wrote NOTHING |
| after each permanent row | `after-<row>` e.g. `after-img4` | the one intended change, and nothing else |
| at the end | `close-l3` | final state, and the disposition of every transfer |

D takes a read after every step and before A starts the next one. A has agreed not to begin a permanent row until
D's read of the previous step has landed.

## 2. The comparison D makes on every read

Each line is compared against the previous read and against `pre-l3`:

1. **The five transfers**, by row md5: `3118bd30` pending, `92ee5156` pending, `bce07eef` pending,
   `83b83858` seller_sent (auto_release 2026-09-11T00:54:49Z), `8f59d37e` seller_sent (auto_release
   2026-09-11T01:20:24Z). None disputed, none released.
2. **Exactly one transfer changes per permanent row**, and only in the fields that row is supposed to change.
3. **The dedupe counts** `0/1/1/0/0` move only for the transfer the step touched.
4. **Buyer inbox** 41 at the start; any change is attributed to a named step or it is a stop.
5. **The seven function bodies** by md5 (both `mark_transfer_sent` overloads, `attach_transfer_evidence`,
   `enqueue_notification`, `guard_transfer_state_columns`, `notify_transfer_event`, `notify_transfer_state_inbox`)
   and the **seven triggers** on `public.transfers`, all enabled.
6. **Evidence objects**: folder total and `rt-%` count, and the referenced evidence paths across all transfers.
   A new object appears only for the row that uploaded it.
7. **Executor flags** `payout.executor_enabled=false` and `refund.executor_enabled=false`.
8. **Outbound**: `net_queue=0` and `net_2xx_total=0`.
9. **Vault names**: `project_url` only — no service-role key, no push key.

## 2b. The listing pair hazard (A's navigation finding, 2026-09-17)

| transfer | listing on screen | venue | in scope |
|---|---|---|---|
| `3118bd30` | Device D1 | Club Device | yes (picker-only rows) |
| `92ee5156` | Device D6 | Club Device | yes (DV-IMG-4) |
| `bce07eef` | Device D2 | Club Device | yes |
| `8f59d37e` | Sandbox S8only | Club | yes (DV-IMG-10, reached via listing detail → "View transfer"; it is already seller_sent, so it never appears in the "Send tickets" tab) |
| `83b83858` | Sandbox L7 | Club | **NO — must not be touched** |

The last two share a venue name, so the event name is the only discriminator on screen. C has the owner read the event
name before every tap in that pair. D's part: the read taken immediately before that row records BOTH row md5s, so a
tap on the wrong listing is detectable at once and unambiguously, and `83b83858` changing at all is a stop.

## 3. Stop conditions (D says stop, and nothing proceeds until the owner rules)

- Any attached proof replaced or deleted, or an evidence path changing on a transfer that the step did not name.
- A transfer row changing outside the approved step, or a second transfer changing in one step.
- A disposition that does not match the approved scope for that row.
- Any queued outbound request, or any 2xx in the outbound log.
- An executor flag flipping, in either direction.
- The push key, or any new vault name, appearing.
- Any of the seven function bodies or seven triggers changing.
- The evidence folder holding an object no step accounts for.
- RLS or the proof-docs policy set changing (A's PC5/PC6 hold the baseline; D re-reads it at `close-l3`).

D states a stop in plain terms, names the read and the line, and does not continue reading past it.

## 4. What D's evidence can and cannot support

- D reads the database. D does not observe the handset, the picker, the upload, or anything the owner sees on screen.
  Those are C's and the owner's evidence.
- D does not observe A's transactions. What D can say is the state before and after, and whether it matches the
  approved intent of that step.
- "Not captured" is never written as "none". Anything D did not read is recorded as not read.

## 5. Explicitly not authorized, and not done by D

Permanent transfer writes; uploading or replacing proof; adding the push key; changing payout or executor flags;
outbound notifications; production reads or changes; sandbox writes of any kind; new builds; applying migration 138 or
115–120; the detection read; the server-log settings read.

---

## Outcome — Line 3 QUARANTINED (2026-09-17, owner's ruling relayed by C)

The pass stopped on a privacy incident: images uploaded during it may be the owner's real photographs.

**What the database says, from D's reads:**

| row | listing | result |
|---|---|---|
| bce07eef | Device D2 | **write completed** 21:09:22Z — evidence PNG 210,364 B, auto_release 2026-09-20 21:09Z, one buyer notice |
| 3118bd30 | Device D1 | **write completed** 21:11:36Z — evidence JPEG 5,829,677 B, auto_release 2026-09-20 21:11Z, one buyer notice |
| 92ee5156 | Device D6 | **not performed** — still pending, no object, no notice (the offline attempt wrote nothing) |
| 8f59d37e | Sandbox S8only | **not performed** — unchanged, evidence still null (an image selected is not an image attached) |
| 83b83858 | Sandbox L7 | **untouched**, as required |

Held, not failed: RT6, U1, RT5-P, N1, N2, N4. DV-IMG-9's conversion half is **UNTESTED**, not failed — the phone was on
Camera › Formats "Most Compatible", so it produced a JPEG and no HEIC conversion could occur.

**Owner's ruling (via C):** "Leave the two stored proof files in place. No deletion, overwrite, reference clearing,
service key or further storage access." D's pre-delete baseline (`d_incident_pre.txt`, md5
`f5ce8094d7e1a0f32b06ec6147f085e7`, 21:38:30Z) therefore stands as evidence of the RETAINED state, not as half of a
delete pair. No post-check exists because no delete happened. D takes no further reads of those objects.

**Access, verified by D against the project's edge logs (not taken from A):** two seller uploads; one buyer-minted
signed URL for the D1 JPEG at 21:13:40Z, fetched three times from the same device; and across 24 hours no other
identity of any kind touched the bucket. The signed URL lapsed on its own about 22:13:40Z.

**Correction to carry (C, verified against D's own earlier read of the cron command):** the claim that a service-role
delete would arm `enforce-transfer-expiry` within two minutes is FALSE. The cron and the notify trigger read the Vault
secret `service_role_key`; a storage API call carries a key in a request header and never writes it to the Vault. D's
original framing was Vault-scoped and remains accurate — *a key stored in this Vault* arms the timer — but the
extension to *any* service-role use does not follow, and must not be reused in a later decision.
