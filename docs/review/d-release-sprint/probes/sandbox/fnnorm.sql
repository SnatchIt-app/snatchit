select p.oid::regprocedure::text as sig,
       left(md5(pg_get_functiondef(p.oid)),8) as raw_md5,
       left(md5(regexp_replace(regexp_replace(regexp_replace(pg_get_functiondef(p.oid), 'https://[a-z0-9]+\.supabase\.co', 'URL', 'g'), '--[^\n]*', '', 'g'), '\s+', ' ', 'g')),8) as norm_md5,
       (pg_get_functiondef(p.oid) ~ 'hqycwntpfoztoinemqns') as mentions_prod_ref
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='public' and p.proname in ('get_my_tickets','notify_bid_placed','notify_moderation_event','notify_transfer_event'))
    or (n.nspname='kernel' and p.proname='check_signing_key_invariants')
 order by 1;
