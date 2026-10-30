-- =============================================================================
-- 20260906130000_deletion_sweep_live_rail_obligations.sql
-- Payments reliability program (audit 2026-09-05) — converged release candidate.
--
-- WHAT. The Phase-2 tombstone deletion machine (077 request → DELETION_PENDING;
-- 078 kernel.sweep_deletion_pending terminal) evaluates blocking predicates
-- BP-1..BP-12 each pass and tombstones an identity only when none fires. Its
-- live-rail arms (BP-6..BP-9, inline in the sweep) cover payout holds,
-- open/disputed transfers, reservations and won auctions — but NOT: a succeeded
-- payment with no transfer row, an auto_released transfer never paid out, an
-- expired transfer whose payment was never refunded, an open payout attempt, an
-- open manual-review decision, or an unresolved webhook review row. Package 3
-- (20260906120000) names exactly those in public.account_deletion_blockers.
--
-- HOW. Two objects:
--   1. public.account_deletion_block_reason(uuid) RETURNS text — the BP-13
--      predicate as ONE text-returning arm (NULL = no obligation), built on
--      public.account_deletion_blockers. service_role EXECUTE only (SEC-2).
--   2. kernel.sweep_deletion_pending — BODY-ONLY CREATE OR REPLACE of the 078
--      definition, generated VERBATIM from 078_catalog_reference_data_and_flags.sql
--      (not retyped) with exactly one addition: the BP-13 arm appended AFTER
--      BP-12 inside the coalesce. Signature, attributes and ACL are unchanged;
--      BP-1..BP-12 precedence is unchanged; every hook (077 §9.2 SEAM-2 stubs
--      and their 079/082/083/085/088/093 bodies) is untouched, so 141 Q3
--      ("every hook is NULL over an empty world") and O24/O25 (BP-7/BP-6 order)
--      hold as written.
--
-- WHY NOT a request-time 409: kernel.request_account_deletion ALWAYS ACCEPTS
-- (OR-17, ratified, deployed); the terminal is the enforcement point. The
-- delete-account edge surfaces the same predicate as pending_obligations.
--
-- Gate-2 (public census): functions +1 (account_deletion_block_reason).
-- Rollback: supabase/rollbacks/20260906130000_deletion_sweep_live_rail_obligations_rollback.sql
-- (restores the 078 sweep body verbatim, drops the predicate).
-- Requires: 078 (kernel.sweep_deletion_pending) and 20260906120000
-- (public.account_deletion_blockers). Both are asserted; this migration refuses
-- to run on a chain that lacks either rather than creating an orphan.
-- =============================================================================
do $$
begin
  if to_regprocedure('kernel.sweep_deletion_pending(integer)') is null then
    raise exception '20260906130000: kernel.sweep_deletion_pending(int) is absent — this chain lacks Phase-2 077/078; refusing';
  end if;
  if to_regprocedure('public.account_deletion_blockers(uuid)') is null then
    raise exception '20260906130000: public.account_deletion_blockers(uuid) is absent — apply 20260906120000 first; refusing';
  end if;
end $$;

-- 1. The BP-13 predicate: one text arm over the Package 3 obligation set.
create or replace function public.account_deletion_block_reason(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when count(*) = 0 then null
              else 'BP-13: unsettled live-rail money obligation ('
                   || string_agg(distinct b.kind, ',' order by b.kind)
                   || ') — settles via payout, refund, review resolution or dispute close'
         end
    from public.account_deletion_blockers(p_user_id) b
$$;
comment on function public.account_deletion_block_reason(uuid) is
  'BP-13 arm for kernel.sweep_deletion_pending (20260906130000): NULL when public.account_deletion_blockers(user) is empty, else an operator-legible reason naming the obligation kinds. External rail only.';
revoke all on function public.account_deletion_block_reason(uuid) from public, anon, authenticated;
grant execute on function public.account_deletion_block_reason(uuid) to service_role;

-- 2. The sweep: 078 body verbatim + the BP-13 arm after BP-12.
create or replace function kernel.sweep_deletion_pending(p_limit int default 100)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row        record;
  v_reason     text;
  v_swept      integer := 0;
  v_blocked    integer := 0;
  v_tombstoned integer := 0;
begin
  -- HARDENING-1 (merge review C of PR #30, recorded in the 077 errata): the
  -- BP-11 re-check-under-org-locks below is correct ONLY under READ COMMITTED,
  -- where each statement takes a fresh snapshot — under REPEATABLE READ the
  -- re-check reads the transaction snapshot and the zero-owner write skew
  -- returns (live-reproduced). The sweep's sole contracted caller is the cron
  -- register entry under default isolation; this guard makes the dependency
  -- structural instead of conventional.
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'sweep_deletion_pending requires read committed isolation (the BP-11 re-check depends on per-statement snapshots)';
  end if;

  for v_row in
    select e.identity_id, e.deletion_requested_at
      from kernel.identity_ext e
     where e.deletion_state = 'DELETION_PENDING'
     limit p_limit
     for update skip locked   -- SKIP LOCKED over the pending partial index;
                              -- FOR UPDATE is the F-11 terminal-entry lock
  loop
    begin
      v_swept := v_swept + 1;

      -- BP-1..BP-12 in order (dsm §2; routing per §20.17.4 + hooks §20.17.5).
      -- First true predicate is recorded; the pass moves on.
      v_reason := coalesce(
        -- BP-1 live custody (hook; kernel.tickets is 079)
        kernel.deletion_blockers_custody(v_row.identity_id),
        -- BP-2 live wallet pass (hook; 083)
        kernel.deletion_blockers_wallet(v_row.identity_id),
        -- BP-3/BP-4 (+ BP-7/BP-8 native twins from 088) (hook)
        kernel.deletion_blockers_market(v_row.identity_id),
        -- BP-5 (+ BP-6 kernel arm, BP-12 refund/window arm from 085) (hook)
        kernel.deletion_blockers_money(v_row.identity_id),
        -- BP-6 live arm: unresolved payout hold/probation on the live rail
        (select 'BP-6: unresolved payout hold/probation on a live transfer — resolves via review resolution or hold lapse'
          where exists (select 1 from public.transfers t
                         where t.seller_id = v_row.identity_id
                           and (t.payout_review_status in ('held','manual_review')
                                or t.payout_hold_until > now()))),
        -- BP-7 live arm: open or disputed transfer (incl. expired-in-dispute)
        (select 'BP-7: an open or disputed live transfer must reach a terminal state first'
          where exists (select 1 from public.transfers t
                         where (t.seller_id = v_row.identity_id or t.buyer_id = v_row.identity_id)
                           and (t.status in ('pending','seller_sent','disputed')
                                or (t.status = 'expired'
                                    and exists (select 1 from public.disputes d
                                                 where d.transfer_id = t.id
                                                   and d.status not in ('won','lost','warning_closed','charge_refunded')))))),
        -- BP-8 live arm: in-flight buy-now reservation
        (select 'BP-8: a live buy-now reservation is in flight — it must land or be released'
          where exists (select 1 from public.listings l
                         where l.reserved_by = v_row.identity_id)),
        -- BP-9 live arm: won-unsettled auction, plus live-auction high bidder
        (select 'BP-9: a won auction has not settled (or a live auction carries this account as high bidder)'
          where exists (select 1 from public.listings l
                         where l.winner_user_id = v_row.identity_id
                           and not exists (select 1 from public.transfers t
                                            where t.listing_id = l.id
                                              and t.status in ('buyer_confirmed','auto_released')))
             or exists (select 1 from public.listings l
                         where l.highest_bidder_id = v_row.identity_id
                           and l.auction_status = 'active')),
        -- BP-10 negative settlement obligation (hook predicate, OR-21)
        (select 'BP-10: an outstanding settlement obligation must be recovered or written off'
          where kernel.has_outstanding_obligations(v_row.identity_id)),
        -- BP-11 sole org_owner (direct — 077 tables)
        (select 'BP-11: sole org_owner of organization ' || m.org_id::text
                || ' — transfer ownership or close the org first'
           from kernel.org_member m
          where m.identity_id = v_row.identity_id and m.role = 'org_owner'
            and not exists (select 1 from kernel.org_member m2
                             where m2.org_id = m.org_id and m2.role = 'org_owner'
                               and m2.identity_id <> m.identity_id)
          limit 1),
        -- BP-12 pending-order arm (hook; venue.order is 082)
        kernel.deletion_blockers_orders(v_row.identity_id),
        -- BP-13 (20260906130000, payments reliability program): UNSETTLED
        -- LIVE-RAIL MONEY OBLIGATION — a succeeded payment with no transfer,
        -- an auto_released transfer never paid out, an expired transfer never
        -- refunded, an open payout attempt, an open manual review, an
        -- unresolved webhook review row, an open dispute, an active transfer.
        -- Evaluated LAST: BP-1..BP-12 keep their precedence exactly. The
        -- predicate is public.account_deletion_block_reason (external rail
        -- only; native rows are the kernel arms' business). If it raises, this
        -- identity's pass fails closed in the handler below (no tombstone).
        public.account_deletion_block_reason(v_row.identity_id)
      );

      if v_reason is not null then
        v_blocked := v_blocked + 1;
        update kernel.identity_ext
           set deletion_block_reason = v_reason
         where identity_id = v_row.identity_id;
        continue;
      end if;

      -- ===== TERMINAL ENTRY (idempotent; dsm §4) ============================
      -- (a0) close the BP-11 write-skew (red-team C blocker 1): the RPC-side
      --     last-owner re-counts serialize on the ORGANIZATION row, so the
      --     terminal member-delete must too — lock every org the identity
      --     belongs to (ascending org_id; identity_ext -> organization is the
      --     existing accept_org_invite direction, no new deadlock class) and
      --     RE-VERIFY BP-11 under those locks. The unlocked coalesce pass
      --     above is the cheap early-out; THIS is the enforcement.
      perform 1
        from (select o.org_id
                from kernel.organization o
               where o.org_id in (select m.org_id from kernel.org_member m
                                   where m.identity_id = v_row.identity_id)
               order by o.org_id
                 for update) locked_orgs;
      if exists (select 1
                   from kernel.org_member m
                  where m.identity_id = v_row.identity_id and m.role = 'org_owner'
                    and not exists (select 1 from kernel.org_member m2
                                     where m2.org_id = m.org_id
                                       and m2.role = 'org_owner'
                                       and m2.identity_id <> m.identity_id)) then
        v_blocked := v_blocked + 1;
        update kernel.identity_ext
           set deletion_block_reason =
               'BP-11: sole org_owner (re-verified under the org locks) — transfer ownership first'
         where identity_id = v_row.identity_id;
        continue;
      end if;

      -- (a) the erased marker write — PFA-3: deletion_state := 'ERASED';
      --     deletion_requested_at is RETAINED (the durable record).
      update kernel.identity_ext
         set deletion_state        = 'ERASED',
             deletion_block_reason = null
       where identity_id = v_row.identity_id;

      -- (b) 077-plane role/invite clears (dsm §4.5 class 1; INV #1/#4-#8).
      --     BP-11 just proved no sole-ownership under this transaction's lock.
      --     No admin_audit rows: the sweep has no human actor and the
      --     SN-SYSTEM sentinel is a 078 seed (forward reference — E-5).
      delete from kernel.org_member    where identity_id = v_row.identity_id;
      delete from kernel.platform_role where identity_id = v_row.identity_id;
      update kernel.org_invite
         set status = 'revoked'
       where status = 'pending'
         and (invitee_identity_id = v_row.identity_id
              or invited_by = v_row.identity_id);

      -- (c) live public.* clears: the PR#28/020 cleanup semantics MINUS every
      --     sentinel repointing (dsm §4.5/§5; §20.15 write set transcribed —
      --     the own-live-auction cancel arm; CUSTODY-DEL-1 untouched; storage
      --     is the edge layer's step; auth.admin.deleteUser called by NOTHING).
      perform set_config('app.bypass_listing_guard', 'on', true);
      update public.listings
         set auction_status = 'cancelled',
             status         = 'active',
             reserved_by    = null,
             reserved_until = null,
             ended_at       = now()
       where seller_id = v_row.identity_id
         and auction_status in ('active','ended');
      perform set_config('app.bypass_listing_guard', 'off', true);

      -- (d) the four terminal cleanup hooks (no-ops until their packages)
      perform kernel.on_identity_erased_staff(v_row.identity_id);
      perform kernel.on_identity_erased_door(v_row.identity_id);
      perform kernel.on_identity_erased_market(v_row.identity_id);
      perform kernel.on_identity_erased_promoter(v_row.identity_id);

      -- (e) OPEN-6a: whether ERASED entry hard-deletes the demographic row is
      --     unruled — recorded here, deliberately NOT implemented.

      -- (f) BE-emit account_deletion_completed (R2 row 32) — last write. A
      --     failed PASS (quarantined exception above) re-runs terminal entry
      --     next tick and re-emits, collapsed by the once-ever key. A
      --     SWALLOWED emit beneath a committed tombstone is the accepted
      --     BEST-EFFORT loss (OR-14: the notice never gates the machine) —
      --     warning-visible; recorded in the 077 errata.
      begin
        perform notify.emit_event(
          'account_deletion_completed', 'identity', v_row.identity_id,
          'account_deletion_completed:' || v_row.identity_id::text,
          jsonb_build_object('deletion_requested_at', v_row.deletion_requested_at));
      exception when others then
        raise warning 'sweep_deletion_pending: best-effort completion emit failed for %: %',
          v_row.identity_id, sqlerrm;
      end;

      v_tombstoned := v_tombstoned + 1;
    exception when others then
      -- half-completion is re-detected next pass (the sweep is the detector);
      -- one poison identity never stops the tick
      raise warning 'sweep_deletion_pending: identity % failed: %', v_row.identity_id, sqlerrm;
    end;
  end loop;

  return jsonb_build_object('swept', v_swept, 'blocked', v_blocked,
                            'tombstoned', v_tombstoned);
end;
$$;

-- Witness: exactly one routine of this name in kernel, same signature (body-only replace).
do $$
declare v_n int;
begin
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'kernel' and p.proname = 'sweep_deletion_pending';
  if v_n <> 1 then
    raise exception '20260906130000: expected exactly 1 kernel.sweep_deletion_pending, found %', v_n;
  end if;
end $$;

-- GRANTS on the sweep: none here (CREATE OR REPLACE preserves the 077/078 ACL —
-- cron definer entry, unreachable from clients).
