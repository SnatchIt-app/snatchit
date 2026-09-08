-- 077_kernel_identity_orgs_and_roles_rollback.sql
-- =============================================================================
-- Rollback for Phase-2 package 077.
--
-- FROZEN POSTURE (plan §8/077): CLEAN-WHILE-EMPTY. admin_audit and
-- approval_request become forward-fix once they hold real audit/adjudication
-- rows; identity_ext deletion state is a durable record once anyone has asked.
-- The guard below refuses while ANY of the twelve tables holds a row.
--
-- FROZEN ORDER (plan §8/077 Rollback cell): the OR-17 deletion machine FIRST —
-- cron.unschedule the deletion sweep; drop request/withdraw/is_deletion_pending
-- /sweep_deletion_pending and the ELEVEN 077 SEAM-2 stubs; drop the pending
-- partial index and the three identity_ext deletion columns (F-5) — then
-- identity_contact_pref_event, the contact/demographic tables, approval_request,
-- admin_audit, org_invite, platform_role, org_member, organization,
-- identity_ext, then helpers. The invite sweep's cron entry is also dropped
-- (CRON_SCHEDULE_REGISTER: "each package's rollback drops its own jobs").
--
-- Result is 076-equivalent. Nothing here touches a pre-077 object.
-- =============================================================================

-- SELF-TRANSACTIONAL (the 076 rollback's proven pattern): the guard must be
-- inseparable from the drops under plain `psql -f` — inside one explicit
-- transaction a raised guard aborts everything and the final COMMIT rolls back.
begin;

-- The guard: count every row in the twelve-table closed world. One DO block,
-- one raise. Partial-apply tolerant.
do $$
declare
  v_rows bigint := 0;
  v_tbl  text;
  v_n    bigint;
begin
  if to_regclass('kernel.identity_ext') is null then
    raise notice '077 rollback: kernel.identity_ext absent (partial apply) — proceeding with drops.';
    return;
  end if;
  -- ROLLBACK_GUARD_ROW_SECURITY (obligation opened by 091's E-151, CLOSED at the 2026-09-02
  -- release-readiness pass): the guard counts RLS-enabled zero-policy tables; run by a
  -- non-owner, non-BYPASSRLS role it would read 0 rows and FAIL OPEN. Count with row
  -- security off — same house pattern as the 091/092 rollbacks.
  set local row_security = off;
  foreach v_tbl in array array[
    'kernel.identity_ext','kernel.organization','kernel.org_member',
    'kernel.org_invite','kernel.platform_role','kernel.admin_audit',
    'kernel.approval_request','kernel.identity_demographic',
    'kernel.identity_demographic_erasure','kernel.identity_contact_pref',
    'kernel.identity_contact_pref_event','kernel.org_customer_key'
  ] loop
    if to_regclass(v_tbl) is not null then
      execute format('select count(*) from %s', v_tbl) into v_n;
      v_rows := v_rows + v_n;
    end if;
  end loop;
  if v_rows > 0 then
    raise exception
      'REFUSED: package 077 tables hold % row(s). The frozen posture is CLEAN-WHILE-EMPTY — audit/approval/identity rows are durable records (admin_audit and approval_request are forward-fix from first row; a deletion request is the durable record that a person asked). Forward-fix instead.',
      v_rows;
  end if;
end;
$$;

-- ── the OR-17 deletion machine first ─────────────────────────────────────────
do $$
begin
  begin perform cron.unschedule('sweep-deletion-pending');
  exception when others then raise notice '077 rollback: deletion-sweep cron entry absent.'; end;
  begin perform cron.unschedule('sweep-expired-org-invites');
  exception when others then raise notice '077 rollback: invite-sweep cron entry absent.'; end;
end;
$$;

drop function if exists kernel.request_account_deletion(text);
drop function if exists kernel.withdraw_account_deletion(text);
drop function if exists kernel.is_deletion_pending(uuid);
drop function if exists kernel.sweep_deletion_pending(int);
drop function if exists kernel.deletion_blockers_custody(uuid);
drop function if exists kernel.deletion_blockers_orders(uuid);
drop function if exists kernel.deletion_blockers_wallet(uuid);
drop function if exists kernel.deletion_blockers_money(uuid);
drop function if exists kernel.deletion_blockers_market(uuid);
drop function if exists kernel.on_identity_erased_staff(uuid);
drop function if exists kernel.on_identity_erased_door(uuid);
drop function if exists kernel.on_identity_erased_market(uuid);
drop function if exists kernel.on_identity_erased_promoter(uuid);
drop function if exists kernel.has_outstanding_obligations(uuid);
drop function if exists kernel.on_deletion_q5_release(uuid);

drop index if exists kernel.identity_ext_deletion_pending_idx;
alter table if exists kernel.identity_ext
  drop column if exists deletion_state,
  drop column if exists deletion_requested_at,
  drop column if exists deletion_block_reason;

-- ── tables in the frozen reverse order ───────────────────────────────────────
drop table if exists kernel.identity_contact_pref_event;
drop table if exists kernel.identity_contact_pref;
drop table if exists kernel.identity_demographic;          -- fires no trigger: empty
drop table if exists kernel.identity_demographic_erasure;
drop table if exists kernel.org_customer_key;
drop table if exists kernel.approval_request;
drop table if exists kernel.admin_audit;
drop table if exists kernel.org_invite;
drop table if exists kernel.platform_role;
drop table if exists kernel.org_member;
drop table if exists kernel.organization;
drop table if exists kernel.identity_ext;

-- ── then the 077 functions ("helpers") ───────────────────────────────────────
drop function if exists kernel.write_demographic_erasure_tombstone();
drop function if exists kernel.get_my_demographics();
drop function if exists kernel.set_my_demographics(text, text);
drop function if exists kernel.clear_my_demographics();
drop function if exists kernel.get_my_contact_prefs();
drop function if exists kernel.set_my_contact_prefs(text);
drop function if exists kernel.create_organization(text, text, text);
drop function if exists kernel.update_organization(uuid, jsonb, text);
drop function if exists kernel.set_org_status(uuid, text, text, text);
drop function if exists kernel.set_org_connect_ref(uuid, text, text);
drop function if exists kernel.invite_org_member(uuid, text, text, text);
drop function if exists kernel.accept_org_invite(uuid, text);
drop function if exists kernel.change_org_role(uuid, uuid, text, text);
drop function if exists kernel.remove_org_member(uuid, uuid, text);
drop function if exists kernel.revoke_org_invite(uuid, text);
drop function if exists kernel.sweep_expired_org_invites(int);
drop function if exists kernel.upsert_identity_ext(jsonb, text);
drop function if exists kernel.admin_set_identity_ext(uuid, jsonb, text, text);
drop function if exists kernel.grant_platform_role(uuid, text, text, text);
drop function if exists kernel.revoke_platform_role(uuid, text, text, text);
drop function if exists kernel.has_org_role(uuid, text[]);
drop function if exists kernel.is_platform(text[]);
drop function if exists kernel.is_org_affiliate(uuid);

commit;
