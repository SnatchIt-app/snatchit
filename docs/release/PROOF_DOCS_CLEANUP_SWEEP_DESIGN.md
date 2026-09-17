# `proof-docs` orphan cleanup — design (B, 2026-09-17)

**Status: DESIGN ONLY.** No migration number requested, nothing implemented, no cron. A's contract §4 assigns the design to B and
its scheduled job to the owner's separate approval. **The sweep must never be scheduled on the strength of this document alone.**

## 0. What it is for, and the one thing it must never do
Retries leave `proof-docs` objects nothing references — B's F1: a seller whose response was lost re-uploads, and the second object
is stranded. Nothing anywhere deletes them today (no cron, no edge function, no migration; the owner-delete policy permits it and
nothing invokes it). The sweep reclaims those.

**It must never delete evidence that is referenced, or that could still legitimately BE referenced.** Deleting a referenced object
destroys the proof behind a live dispute. That is a worse outcome than storing orphans forever, so every choice below is biased
toward keeping bytes.

## 1. The hazard that shapes the whole design: an orphan is a RECOVERY CANDIDATE
`attach_transfer_evidence` (140 §2) exists so a seller whose transfer was marked sent without proof can attach proof **that was
uploaded earlier and is currently unreferenced**. That is precisely the shape of an orphan. **An age-based sweep would delete
exactly the objects the recovery path exists to rescue** — and the older the stranded transfer, the more certain the deletion.
This is not a corner case: it is the intersection of the two defects 140 repairs.

**Therefore the sweep excludes any object in `<uid>/transfer-evidence/` where that `<uid>` has at least one transfer in
`seller_sent` with `transfer_evidence_path IS NULL`** — a seller with an open recovery keeps every candidate until the recovery is
done or the transfer leaves that state. The exclusion is per seller, not per object, because the server cannot know which object
the seller means to attach.

**This also closes the race**, which is why it is better than a lock. The unguarded window is: attach checks the object exists →
sweep deletes it (still unreferenced) → attach records a path to bytes that are gone. With the exclusion, the only folders where
attach can be running are the folders the sweep will not touch, so the window does not exist for the case that has consequences.
For an ordinary orphan — a seller with no open recovery — nothing can reference the object, so the race has no effect.

## 2. Reference set — all of it, and one correction to the contract
An object survives if its name appears in ANY of:
- `public.transfers.transfer_evidence_path`
- `public.transfers.dispute_evidence_path`
- `public.listings.proof_of_ownership_path`
- the legacy `transfer_screenshot_path`

**Correction (measured):** `transfer_screenshot_path` **does not exist** in the replayed chain — `information_schema.columns` has
no such column in any schema. Migration 118 already accesses it defensively as `to_jsonb(t) ->> 'transfer_screenshot_path'`, which
yields NULL when the column is absent. **The sweep will use that same idiom rather than a direct reference.** A direct reference
would fail to compile where the column is absent; worse, silently dropping the clause would let the sweep delete referenced
evidence in any environment where the column *does* exist. The defensive read costs nothing and fails safe in both directions.

## 3. Shape
- One `SECURITY DEFINER` function, `search_path = ''`, service_role EXECUTE only, in its own migration.
- **The reference check and the delete are ONE statement** — `delete from storage.objects o where … and not exists (…) and not
  exists (…) …` — so no snapshot is carried between checking and deleting.
- Scope: `bucket_id = 'proof-docs'` only, names under `%/transfer-evidence/%` only, `o.created_at < now() - <N days>`.
  Listing proofs and dispute evidence are **out of scope in v1**: they have different lifecycles and no known orphan source.
- **Bounded:** a `limit` argument with a conservative default, returning the count deleted, so a first run cannot remove
  everything at once and a mistake is small and visible.
- **Dry-run first:** the same predicate exposed as a counting function that deletes nothing, so the population can be inspected
  before anything is scheduled. The owner should see a count before a cron exists.
- **Audited:** one `kernel.admin_audit` row per run with the count and the parameters (the 083 append-only pattern the signing
  monitor already uses), so a deletion is never invisible.

## 4. The pgTAP controls (the ones that make it trustworthy)
1. A referenced object **survives** — the contract's required control.
2. A **recovery-candidate** object survives: an unreferenced object whose owner has a `seller_sent` transfer with a null path.
   *(This is the control B added; without it the suite would pass while the sweep destroyed the recovery path.)*
3. An ordinary orphan, old enough and with no open recovery, **is** deleted — or the sweep does nothing at all.
4. An object **younger than N** survives regardless.
5. Objects in other buckets and other folders are untouched.
6. Negative control per predicate: remove each `not exists` clause in turn and confirm exactly one assertion dies.

## 5. What needs the owner (nothing here is approved)
1. **N** — how long an unreferenced object is kept. B's recommendation: **at least 30 days**, because the recovery path is manual
   and a seller may take days to notice the proof never attached.
2. **The cron itself** — a new scheduled job, which is a separate approval from the migration.
3. Whether a **dry-run count** should be reported to the owner before the job is ever scheduled. B recommends yes.
