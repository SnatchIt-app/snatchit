-- Rollback for 069. Only drops on a fresh/staging DB; NEVER run on production (the table holds
-- real webhook-retry audit rows). Guarded to require an empty table.
do $$ begin
  if (select count(*) from public.webhook_retries) = 0 then
    drop table if exists public.webhook_retries;
  else
    raise notice 'webhook_retries not empty — refusing to drop (preserve audit rows).';
  end if;
end $$;
