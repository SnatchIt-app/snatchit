-- ============================================================================
-- ROLLBACK for 20261031180000_ops_operational_config.sql (registry 197).
-- Restores the applied state before 197: neither ops function existed. It drops them, under an inverse guard:
-- each must be absent or at 197's own md5, so a foreign body is refused, never dropped.
-- Data: 197 owns no table and writes no row. Values set THROUGH it are ordinary catalog.platform_config versions
-- (with their admin_audit rows) and stay; this rollback removes the path, not any value. To change a value back,
-- set it back BEFORE rolling back.
-- Console: redeploy a console build without the Operational settings form BEFORE running this, or the form shows
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
      ('ops.set_operational_config(text,jsonb,text,text)', '994691ae418af4cc3b79bac3912ebe8b'),
      ('ops.list_operational_config()',                    'a0415b34eb17f66b9698d63aa83d7b5c')
    ) as t(sig, want_md5)
  loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if v_md5 is not null and v_md5 <> r.want_md5 then
      raise exception 'ROLLBACK_197_REFUSED: % has md5 %, not 197''s — not dropping a foreign body', r.sig, v_md5;
    end if;
  end loop;
end $rb$;

-- no CASCADE: a foreign dependent must make this fail, not disappear
drop function if exists ops.set_operational_config(text, jsonb, text, text);
drop function if exists ops.list_operational_config();

do $post$
begin
  if to_regprocedure('ops.set_operational_config(text,jsonb,text,text)') is not null
     or to_regprocedure('ops.list_operational_config()') is not null then
    raise exception 'ROLLBACK_197_FAILED: a 197 function still exists';
  end if;
end $post$;

commit;
