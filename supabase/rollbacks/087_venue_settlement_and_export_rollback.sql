-- ============================================================================
-- ROLLBACK for 087_venue_settlement_and_export.sql
-- POSTURE: CLEAN-WHILE-EMPTY, then forward-fix (plan §8/087 Rollback row).
-- Refuses once any settlement header/line, any export job, or any object in the
-- crm-exports bucket exists. Restores post-086 state EXACTLY:
--   - venue.on_payout_settled → its 085 no-op stub (SEAM-2 F-5, body-only)
--   - the two settlement seam stubs, close_settlement, open_settlement and
--     request_org_payout are DROPPED (all NEW in 087)
--   - the thirteen CRM functions are DROPPED (all NEW in 087)
--   - DROP TYPE kernel.settlement_line_candidate LAST — the two hooks and
--     close_settlement return/consume it, and DROP TYPE fails while any routine's
--     signature depends on it (C116)
--   - export_job, then settlement_line, then settlement; the crm-exports bucket
--     row (never its objects — the guard proves there are none)
-- 076-086 otherwise untouched. kernel.org_customer_key (077) is never written by
-- 087 (PFA-28 deferral of the OR-19 mint), so nothing there to undo.
-- ============================================================================

begin;

-- PART 0 — refusal guard (row_security off: export_job is deny-all zero-policy,
-- so a non-BYPASSRLS runner would under-count).
do $$
declare v_s bigint := 0; v_l bigint := 0; v_j bigint := 0; v_o bigint := 0; v_p bigint := 0; v_a bigint := 0;
begin
  set local row_security = off;
  if to_regclass('venue.settlement')      is not null then execute 'select count(*) from venue.settlement'      into v_s; end if;
  if to_regclass('venue.settlement_line') is not null then execute 'select count(*) from venue.settlement_line' into v_l; end if;
  if to_regclass('venue.export_job')      is not null then execute 'select count(*) from venue.export_job'      into v_j; end if;
  execute $q$select count(*) from storage.objects where bucket_id = 'crm-exports'$q$ into v_o;
  -- 087-only WRITERS into earlier ledgers: settlement payouts and parked payout approvals would dangle.
  execute $q$select count(*) from kernel.payout where cause = 'settlement'$q$ into v_p;
  execute $q$select count(*) from kernel.approval_request where action = 'payout.request'$q$ into v_a;
  if v_s + v_l + v_j + v_o + v_p + v_a > 0 then
    raise exception 'REFUSED: 087 holds rows (settlement=%, line=%, export_job=%, crm-exports objects=%, settlement payouts=%, payout approvals=%). CLEAN-WHILE-EMPTY only; forward-fix instead.',
      v_s, v_l, v_j, v_o, v_p, v_a;
  end if;
end $$;

-- PART 1 — cron (the three 087 schedules; CRON_SCHEDULE_REGISTER rows 087 ×3).
select cron.unschedule('sweep-expired-exports')  where exists (select 1 from cron.job where jobname = 'sweep-expired-exports');
select cron.unschedule('crm-export-build-tick')  where exists (select 1 from cron.job where jobname = 'crm-export-build-tick');
select cron.unschedule('crm-export-purge-tick')  where exists (select 1 from cron.job where jobname = 'crm-export-purge-tick');

-- PART 2 — restore the SEAM-2 stub body VERBATIM (F-5; 085 §20.11.5).
create or replace function venue.on_payout_settled(p_payout_id uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;   -- no-op until 087

-- PART 3 — the 087 functions (CRM surface, settlement engine, then the seams).
drop function if exists venue.lookup_attendee(uuid, text, text);
drop function if exists venue.list_attendees(uuid, jsonb, text, text);
drop function if exists venue.list_export_jobs(text, uuid, text);
drop function if exists venue.reconcile_export_orphans(uuid, text[]);
drop function if exists venue.confirm_artifact_purged(uuid, text);
drop function if exists venue.claim_artifacts_for_purge(integer);
drop function if exists venue.sweep_expired_exports();
drop function if exists venue.revoke_export(uuid, text);
drop function if exists venue.authorize_export_download(uuid);
drop function if exists venue.finalize_export(uuid, integer, integer, text, text);
drop function if exists venue.build_export_rows(uuid, text, integer);
drop function if exists venue.request_export(text, uuid, text, jsonb, text);
drop function if exists venue.assert_may_request(uuid, text, uuid, text, boolean);
drop function if exists kernel.request_org_payout(uuid, uuid, text);
drop function if exists kernel.close_settlement(uuid, text);
drop function if exists venue.open_settlement(uuid, uuid, uuid, jsonb, text);
drop function if exists kernel.settlement_commission_lines(uuid);
drop function if exists kernel.settlement_royalty_lines(uuid);

-- PART 4 — tables (children first). Dropping each removes its triggers/policies/indexes.
drop table if exists venue.export_job;
drop table if exists venue.settlement_line;
drop table if exists venue.settlement;

-- PART 5 — the composite type, LAST (C116: every routine depending on it is gone).
drop type if exists kernel.settlement_line_candidate;

-- PART 6 — the bucket row (its objects are proven absent by PART 0).
delete from storage.buckets where id = 'crm-exports';

commit;
