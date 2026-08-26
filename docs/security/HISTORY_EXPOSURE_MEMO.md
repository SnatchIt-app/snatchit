# History Exposure Memo — confidential material in git history

**Date:** 2026-08-25 · **Status:** OPEN — awaiting owner (+ counsel) decision.
Recorded by the repository-hygiene PR (stabilization roadmap §8 / P1-5).

## What was exposed

While this repository was **public** (window ≈ the repo-public period ending
2026-08-25, when it was taken private):

1. **Confidential IP Ownership & Assignment Agreement** (JDT LLC / Founder) —
   a ~48KB `.docx` blob (filename `ziZhyOZe`), added in the repository's
   initial commit `4ba53b3`. World-readable and downloadable from git history
   for the entire public window. It is no longer tracked at `main`'s tip but
   **the blob remains in git history** and at the tips of stale branches.
2. **Class-C operational documents** (now under `docs/operations/` and
   `docs/security/`): six copy-paste admin SQL packs, manual
   refund/dispute/recovery playbooks, fraud-detection thresholds, and
   `docs/security/PHASE_0_EXECUTION.md`'s then-open findings list — all world-readable
   during the same window.
3. **Apple-review demo account credentials** (email + cleartext password +
   contact phone) in `docs/product/APP_STORE_METADATA.md`. Redacted from the tracked doc by
   the hygiene PR; the values remain in git history, and also appear in
   `scripts/seed-demo.ts` (code — untouched by this structure-only PR).

## Current posture

- The repository is now **private**; nothing above is publicly reachable going
  forward.
- A full-history secret scan (all 2,770 blobs) found **zero platform secrets**
  — no Stripe secret key, webhook secret, or service_role JWT anywhere in any
  branch's history. The exposures above are documents and demo credentials,
  not platform key material.

## Options for the IP agreement blob

| Option | Effect | Cost |
|---|---|---|
| **Accept** (repo stays private) | Blob stays in history, visible only to repo collaborators | None; exposure during the public window is already unrecoverable for anyone who cloned |
| **History rewrite** (`git filter-repo` removing the blob, force-push all branches, delete stale tips) | Blob removed from this repo's history | Breaks every clone and **every recorded SHA — including the freeze anchors** (`51cce52`/`dd960c4`, tag `phase2-architecture-v1`, and the A-1/A-2 mappings); requires re-anchoring the architecture freeze; does not un-expose anything already cloned |

**Recommendation:** this is an owner + counsel decision, weighing whether the
document's exposure has legal significance. **No automatic rewrite** — a
history rewrite may only proceed with explicit owner + counsel authorization,
scheduled as its own supervised event.

## Demo credentials

The published demo email/password/phone must be treated as burned:
**rotation of the Apple-review demo account password is an owner action**
(roadmap §19.3). Redaction in this repo does not un-publish the historical
values.
