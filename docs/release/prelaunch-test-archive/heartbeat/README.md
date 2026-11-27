# Archive heartbeat correction (217)

The216 archive refused a real owner attempt because scheduled detectors advanced only case `last_seen_at` and `updated_at`. All57 payments,16 case identities/counts and every other linked row remained unchanged. Refreshing the page could not refresh the sealed backup.

217 permits only forward movement of those two timestamps. Case fields such as title/status/priority/identity, every financial/custody field, all other relations and all record counts still require exact equality with the restored reviewed snapshot. Null/malformed inventories, duplicates and timestamp rewinds refuse. Existing manifest, role/MFA, backup/hash/window, lock, FK/hook and protected-purchase guards remain.

Under the same transaction/table locks, the full current rows are retained separately in private `execution_snapshot` plus SHA256 before the transaction commits. The original reviewed snapshot and external backup digest remain intact. A constraint requires an execution copy for archived batches, so a queued old216 invocation cannot delete records without it. Both forward217 and rollback217 acquire the executor advisory lock. Rollback refuses completed history; it cannot erase an execution copy. No rows are archived by applying this schema change.

Validation: local `run-contract.py --heartbeat` reproduces old-code refusal, rejects business-data drift, succeeds for heartbeat-only drift, verifies exact current execution copy/hash, queued-old-executor atomic refusal, protected records, rollback history retention and a two-connection rollback/advisory-lock negative control. Full-chain pgTAP286 covers actual Supabase tables, roles and triggers; its positive move rolls back synthetic data.
