-- ============================================================================
-- ROLLBACK for 083_kernel_credential_infrastructure.sql
-- POSTURE: CLEAN-WHILE-EMPTY (plan §8/083), then forward-fix — revoked keys/certs
-- are retained post-go-live so historical credentials stay verifiable. Refuses once
-- any signing_key / pass_type_cert / wallet_pass / device / push_log row exists.
--
-- 086 ORDERING: 086 CREATE OR REPLACEs venue.append_door_manifest_delta's body and
-- adds door_manifest FKs to signing_key. If 086 is applied, ITS rollback runs first
-- (reverse-order rollout guarantees this); at 083 the stub is a no-op and no 086
-- object references these tables, so this script stands alone.
--
-- Restores post-082 state EXACTLY: kernel.deletion_blockers_wallet is put back to
-- its 077 neutral stub VERBATIM (OR-17 F-5). HARDENING-1, the 079 custody bodies,
-- the 080/081/082 objects, PFA-13/14/15 are untouched. issue_ticket_atoms is dropped
-- (it moved here by C114/R2B); kernel.tickets (079) is NOT touched.
-- ============================================================================

begin;

-- PART 0 — refusal guard. Count authoritatively regardless of role (row_security
-- off): the wallet tables are deny-all zero-policy, so a non-BYPASSRLS runner would
-- count 0 and could false-negative — with row_security off the owner/BYPASSRLS
-- runner gets the true count and REFUSES on any row; a non-privileged runner ERRORS.
do $$
declare
  v_k bigint := 0; v_c bigint := 0; v_w bigint := 0; v_d bigint := 0; v_p bigint := 0;
begin
  set local row_security = off;
  if to_regclass('kernel.signing_key')          is not null then execute 'select count(*) from kernel.signing_key'          into v_k; end if;
  if to_regclass('kernel.pass_type_cert')        is not null then execute 'select count(*) from kernel.pass_type_cert'        into v_c; end if;
  if to_regclass('kernel.wallet_pass')           is not null then execute 'select count(*) from kernel.wallet_pass'           into v_w; end if;
  if to_regclass('kernel.wallet_pass_device')    is not null then execute 'select count(*) from kernel.wallet_pass_device'    into v_d; end if;
  if to_regclass('kernel.wallet_pass_push_log')  is not null then execute 'select count(*) from kernel.wallet_pass_push_log'  into v_p; end if;
  if v_k > 0 or v_c > 0 or v_w > 0 or v_d > 0 or v_p > 0 then
    raise exception 'REFUSED: 083 holds rows (signing_key=%, pass_type_cert=%, wallet_pass=%, device=%, push_log=%). CLEAN-WHILE-EMPTY only (plan §8/083) — live credentials/passes are forward-fix territory.',
      v_k, v_c, v_w, v_d, v_p;
  end if;
end $$;

-- PART 1 — OR-17 F-5: restore the 077 neutral stub of kernel.deletion_blockers_wallet, VERBATIM.
create or replace function kernel.deletion_blockers_wallet(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$ select null::text $$;   -- BP-2; real body 083 (kernel.wallet_pass)

-- PART 2 — 083-authored functions (RPCs; deletion_blockers_wallet restored above).
drop function if exists kernel.provision_signing_key(text, uuid, text, text, timestamptz, text, text);
drop function if exists kernel.rotate_signing_key(uuid, text, text, text, text);
drop function if exists kernel.provision_pass_type_cert(text, text, text, text, text, timestamptz, timestamptz, text, text);
drop function if exists kernel.rotate_pass_type_cert(uuid, text, text, text, timestamptz, timestamptz, text, text);
drop function if exists kernel.revoke_pass_type_cert(uuid, text, text);
drop function if exists kernel.issue_ticket_atoms(jsonb, text);
drop function if exists kernel.mint_wallet_pass(uuid, text);
drop function if exists kernel.register_wallet_pass_device(text, text, text, text);
drop function if exists kernel.get_wallet_pass_build_context(text, text);
drop function if exists kernel.list_updated_wallet_passes(text, text, timestamptz);
drop function if exists kernel.unregister_wallet_pass_device(text, text, text);
drop function if exists kernel.supersede_wallet_passes_for_atom(uuid, text);
drop function if exists kernel.touch_wallet_pass(uuid);
drop function if exists kernel.revoke_wallet_pass(uuid, text, text);
drop function if exists kernel.sweep_wallet_pass_lifecycle();
drop function if exists kernel.record_wallet_push_result(uuid, uuid, text, uuid, text, integer, text);
drop function if exists venue.append_door_manifest_delta(uuid, uuid[], text, uuid);

-- PART 3 — tables (children first; dropping each removes its triggers).
drop table if exists kernel.wallet_pass_push_log;
drop table if exists kernel.wallet_pass_device;
drop table if exists kernel.wallet_pass;
drop table if exists kernel.pass_type_cert;
drop table if exists kernel.signing_key;

-- PART 4 — the private .pkpass bucket (safe: refusal guard proved the tables empty,
-- and zero storage policies were created).
delete from storage.buckets where id = 'pkpass';

-- PART 5 — the bespoke guard trigger functions (now no trigger depends on them).
drop function if exists kernel.guard_signing_key_immutable();
drop function if exists kernel.guard_pass_type_cert_immutable();
drop function if exists kernel.guard_wallet_pass_immutable();
drop function if exists kernel.guard_wallet_pass_device_immutable();

commit;
