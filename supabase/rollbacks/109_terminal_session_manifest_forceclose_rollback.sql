-- ============================================================================
-- 109_terminal_session_manifest_forceclose_rollback.sql — revert migration 109.
-- Drops the terminal-status trigger, its trigger function, and the session-scoped
-- force-close helper. CLEAN-WHILE-EMPTY: 109 changed no data.
-- ============================================================================
begin;

drop trigger if exists tg_session_terminal_force_close on catalog.event_session;
drop function if exists catalog.tg_session_terminal_force_close();
drop function if exists kernel.force_close_session_manifests(uuid,text);

commit;
