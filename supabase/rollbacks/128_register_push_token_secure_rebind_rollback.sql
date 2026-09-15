-- ============================================================================
-- 128_register_push_token_secure_rebind_rollback.sql — removes the device-proof
-- rebinding verb, the support unbind verb, the write guard and the proof column.
--
-- WHAT THIS RE-INTRODUCES, on the record: F7. Without the verb, a device whose
-- token is bound to another account cannot rebind at all — the client falls back
-- to its insert, `UNIQUE (token)` rejects it 409, and that handset keeps
-- receiving the other account's notifications and none of its own.
--
-- TWO THINGS ARE DELIBERATELY NOT REVERSED.
--
-- 1. `public.push_token_rebind_epoch` is KEPT. Dropping the proof column erases
--    every stored hash, so on a re-apply every hash-less row would look
--    pre-128. If the epoch moved with it, each of those rows would become
--    claimable by token knowledge again (review finding V5). Keeping the FIRST
--    epoch means rows created after it stay closed, and every device re-binds
--    its own hash on its next registration through rule 2. The table is one row
--    and costs nothing to leave behind.
--
-- 2. The REVOKE of `notify.register_push_token` from `authenticated` is NOT
--    restored. That verb rebinds on token knowledge alone; re-granting it during
--    a rollback would hand back the exact vulnerability this migration exists to
--    remove, at the moment the replacement is being withdrawn. A rollback should
--    not restore a hole. Re-grant it deliberately if it is ever genuinely needed.
--
-- Deploy order on the way back: the client must stop calling register_push_token
-- BEFORE this runs, or registration fails PGRST202/42883.
-- ============================================================================
begin;

drop trigger if exists trg_guard_push_token_secret_hash on public.push_tokens;
drop function if exists public.guard_push_token_secret_hash();
drop function if exists public.unbind_push_token(text);
drop function if exists public.register_push_token(text, text, text, text);

alter table public.push_tokens
  drop column if exists device_secret_hash;

-- Inverse of 128's column-scoped SELECT/UPDATE. REVOKE first: a table-level
-- REVOKE also drops the per-column ACL entries 128 granted (D review G-3a —
-- a GRANT alone left twelve column ACLs behind), then the pre-128 table-level
-- privileges return. Verify with information_schema.column_privileges = 0
-- rows for authenticated on push_tokens.
revoke select, update on public.push_tokens from anon, authenticated;
grant  select, update on public.push_tokens to anon, authenticated;
-- NOT restored, on purpose: notify.register_push_token EXECUTE for
-- authenticated — header item 2. A rollback does not reopen the hole.

-- public.push_token_rebind_epoch intentionally retained — see the header — and
-- so is trg_guard_push_token_rebind_epoch with its function: the trigger is what
-- keeps the retained epoch from being moved, which is the whole reason to retain it.

commit;
