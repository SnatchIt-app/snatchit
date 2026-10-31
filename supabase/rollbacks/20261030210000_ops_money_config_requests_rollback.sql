-- ============================================================================
-- ROLLBACK for 20261030210000_ops_money_config_requests.sql (registry 196).
-- Restores the applied state before 196: none of the three ops functions existed. It drops them, under an
-- inverse guard: each must be absent or at 196's own md5, so a foreign body is refused, never dropped.
-- Data: 196 owns no table and writes no row. Money-key requests parked THROUGH it live in
-- kernel.approval_request and stay there (kernel.approve_refund_request can still decide them; they just
-- cannot be listed or newly requested from the console after this rollback).
-- Console: redeploy a console build without the Money settings panel BEFORE running this, or the panel shows
-- "RPC not available".
-- ============================================================================
begin;

do $rb$
declare
  v_md5 text;
  r     record;
begin
  for r in
    select * from (values
      ('ops.list_config_approvals(text)',                   '59ed8b127bfddb9136f0fdd07408a98d'),
      ('ops.request_platform_config(text,jsonb,text,text)', 'bc80b674d67d0a14e6b5416d9a234c99'),
      ('ops.money_config_key(text)',                        '6a6c96d328b248bbf031964d61da7ed3')
    ) as t(sig, want_md5)
  loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if v_md5 is not null and v_md5 <> r.want_md5 then
      raise exception 'ROLLBACK_196_REFUSED: % has md5 %, not 196''s — not dropping a foreign body', r.sig, v_md5;
    end if;
  end loop;
end $rb$;

-- request_platform_config calls money_config_key; drop the callers first (no CASCADE: a foreign dependent
-- must make this fail, not disappear).
drop function if exists ops.list_config_approvals(text);
drop function if exists ops.request_platform_config(text, jsonb, text, text);
drop function if exists ops.money_config_key(text);

do $post$
begin
  if to_regprocedure('ops.list_config_approvals(text)') is not null
     or to_regprocedure('ops.request_platform_config(text,jsonb,text,text)') is not null
     or to_regprocedure('ops.money_config_key(text)') is not null then
    raise exception 'ROLLBACK_196_FAILED: a 196 function still exists';
  end if;
end $post$;

commit;
