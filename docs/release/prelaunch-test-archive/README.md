# One-time pre-launch test archive

Status: **LOCAL CANDIDATE — NO HOSTED WRITES, NO RECORDS MOVED.**

Jose approved the one-time exception in chat on November 26, 2026. The later instruction permits a separate archive instead of irreversible erasure. This package physically moves the exact reviewed legacy records out of active tables into a private full-row snapshot. It does not implement a display-only filter or classify future sales automatically.

The approved manifest has exactly 57 payments, all older than the November 3 DD sale. The manifest contract stores only its sorted-ID digest. Production identifiers and row data remain in private evidence, not this repository. Both protected payments, their related records, the real $1.80 unpaid obligation, all identities and all native ticket custody remain active.

## Implemented local behavior

- One sealed batch, one exact manifest, seven-day execution window, platform-admin plus existing MFA gate.
- Separate private preparation and backup verification. The browser cannot prepare a batch or attest a backup. A malformed/missing RPC never unlocks cleanup.
- Row-exact snapshots of the approved payments and their directly linked transfers, cases/events/notes, retry records, refund facts, payout decisions, transfer notifications and exact case-linked alerts. Notification matching uses exact transfer IDs, not a user or listing wildcard.
- Refusal for native custody/money links, payout attempts, actionable seller obligations, privileged action history, cross-scope references, unknown cascading dependencies and unknown delete hooks.
- Source snapshot must still match the exported backup at execution. Changed data refuses the entire operation.
- Table locks surround the before-image check, move and receipt. Only the four named append-only triggers needed for copied test history are temporarily disabled under those locks; they are re-enabled before return. Any exception rolls back deletion and trigger state together. No permanent append-only function is relaxed.
- Idempotent retry returns the original exact receipt. One audit entry records the batch and reason; existing audit history is retained.
- Read-only archive history exposes limited order fields, not snapshot payloads or private contact/evidence data.

## Native settlement alarm

The predecessor detector raises a resale-transfer alarm for a valid native-primary ticket order. `native-settlement-forward.sql` suppresses only native payments with the exact completed order/payment/buyer/amount link. Missing, pending, wrong-buyer or wrong-amount native links still alert. Actual native reconciliation remains in force. The admin candidate explains that native issuance does not create a resale transfer and directs staff to native reconciliation.

## Evidence and limits

`tests/run-contract.py` starts a unique private local PostgreSQL cluster with a Unix socket only, rejects inherited database settings, stops only its own cluster and retains evidence. It uses synthetic tables, claims and manifest configuration. It is a SQL contract proof, **not full Supabase migration/RLS integration**. The production manifest digest is independently checked against the privately inventoried 57 IDs.

The actual production affected-row backup contains 756 rows across 16 relations (including 16 linked case alerts). Every row was restored into matching-column disposable local tables and round-tripped exactly. This proves backup readability and value/type preservation, **not a full application/FK/RLS restore**. The first restore attempt exposed a local/server timezone formatting mismatch; pinning the isolated restore server to UTC produced exact equality. No data comparison was weakened.

Registered as candidate 216 (`20261126200848_prelaunch_test_archive.sql`) with real-role pgTAP 284. Still required: independent review, full-chain execution, sandbox rehearsal, reviewed CLI apply, fresh prepared batch plus matching verified backup, admin execution and post-move readback. No cleanup completion or whole-application reset is claimed.

The 57-order cleanup does not delete unsold marketplace listings, user accounts, uploads, unrelated notification history, or historical report snapshots. Those need their own inspected manifests; “clean everything” must not turn into an unbounded delete.
