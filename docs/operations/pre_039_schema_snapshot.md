# Pre-039 production snapshot — 2026-07-15 02:01 ET
- migration_count: 39 applied (through 038)
- transfers columns: 27 (no payout_* / buyer_viewed_at columns)
- payout_policy / payout_decisions: absent
- enforce_auto_release prosrc md5: fa329f32197bced6b458521fec15347b (migration 016 body — restore source: supabase/migrations/016_fix_auto_release_payout.sql)
- Full dump not taken: no Docker/pg_dump/db-password on this machine; 039 is additive-only. Rollback SQL: docs/payout-rollout.md.
