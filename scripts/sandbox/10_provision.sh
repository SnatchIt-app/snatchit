#!/bin/bash
# Provision the SANDBOX: schema, non-secret DB settings, edges. Prints the owner-run statements (secrets) instead of executing them.
. "$(dirname "$0")/lib.sh"; need supabase psql jq curl; cd "$ROOT"
echo "=== P0.2 schema"
supabase link --project-ref "$TEST_REF" >/dev/null 2>&1 || { echo "link failed (owner: supabase login)"; exit 1; }
supabase db push --linked --include-all --yes 2>&1 | tail -3
check "P0.2 128 migration versions applied" "select count(*) from supabase_migrations.schema_migrations" "128"
check "P0.2 Gate-2 census 30|86|37|32" "select (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r')||'|'||(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e'))||'|'||(select count(*) from pg_policies where schemaname='public')||'|'||(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal)" "30|86|37|32"
echo "=== P0.3 non-secret DB provisioning (sandbox only)"
# The platform refuses ALTER DATABASE/ROLE for custom parameters (supautils), so the sandbox-only money switch is set
# per API request through PostgREST's db_pre_request hook — the same sessions the edge functions' RPC calls run in.
sql "create or replace function public.sandbox_pre_request() returns void language plpgsql as \$\$ begin perform set_config('app.allow_test_mode_money', 'on', true); end \$\$" >/dev/null
sql "revoke all on function public.sandbox_pre_request() from public; grant execute on function public.sandbox_pre_request() to authenticator, anon, authenticated, service_role" >/dev/null
sql "alter role authenticator set pgrst.db_pre_request = 'public.sandbox_pre_request'" >/dev/null && ok "P0.3 money switch app.allow_test_mode_money=on via pgrst.db_pre_request (sandbox only)" || bad "P0.3 money switch" "alter role failed"
# PostgREST exposed schemas (Dashboard → API) — the role setting is honoured by the platform's PostgREST
sql "alter role authenticator set pgrst.db_schemas = 'public, graphql_public, kernel'" >/dev/null && ok "P0.4 kernel exposed to PostgREST" || bad "P0.4 kernel schema" "alter role failed"
sql "notify pgrst, 'reload config'" >/dev/null
# the expiry cron job is UNSCHEDULED in the sandbox (no Vault bearer): the harness invokes the sweep manually with INTERNAL_CRON_SECRET
sql "select cron.unschedule(jobid) from cron.job where jobname = 'enforce-transfer-expiry'" >/dev/null
# function bodies (033 trigger, 099 ticks) hard-code the production host: re-point them in the sandbox
sql "do \$\$ declare r record; begin for r in select p.oid from pg_proc p where p.prosrc like '%$PROD_REF%' loop execute replace(pg_get_functiondef(r.oid), '$PROD_REF', '$TEST_REF'); end loop; end \$\$" >/dev/null
check "P0.3 no function body targets the production host" "select count(*) from pg_proc where prosrc like '%$PROD_REF%'" "0"
sql "select cron.alter_job(jobid, command := replace(command, '$PROD_REF', '$TEST_REF')) from cron.job where command like '%$PROD_REF%'" >/dev/null
check "P0.3 no cron job targets the production host" "select count(*) from cron.job where command like '%$PROD_REF%'" "0"
echo "=== P0.6 edges (release set + the two the matrix needs; verify_jwt off — the functions authenticate in code)"
supabase functions deploy create-payment-intent confirm-payment confirm-and-release enforce-transfer-expiry delete-account notify-report stripe-webhook create-connect-account send-push --project-ref "$TEST_REF" --no-verify-jwt 2>&1 | tail -2
n=$(supabase functions list --project-ref "$TEST_REF" 2>/dev/null | grep -cE "ACTIVE"); [ "$n" -ge 9 ] && ok "P0.6 nine functions ACTIVE" || bad "P0.6 functions" "active=$n"
cat <<TXT

>>> OWNER (after 'stripe login' into the SANDBOX): create the endpoint, then set the secrets in Dashboard → Edge Functions → Secrets:
    stripe webhook_endpoints create --url $FN/stripe-webhook --api-version 2024-09-30.acacia \\
      --enabled-events account.updated --enabled-events charge.dispute.closed --enabled-events charge.dispute.created \\
      --enabled-events charge.refunded --enabled-events payment_intent.canceled --enabled-events payment_intent.payment_failed \\
      --enabled-events payment_intent.succeeded --enabled-events payout.failed --enabled-events payout.paid \\
      --enabled-events transfer.created --enabled-events transfer.reversed
    Secrets: STRIPE_SECRET_KEY (sandbox sk_test), STRIPE_WEBHOOK_SECRET (whsec of the endpoint above), ALLOW_TEST_MODE_MONEY=1,
             INTERNAL_CRON_SECRET, STRIPE_CONNECT_REFRESH_URL=https://snatchitapp.com/payout-refresh,
             STRIPE_CONNECT_RETURN_URL=https://snatchitapp.com/payout-return, SENTRY_ENV=sandbox
    Then create three auth users (buyer, seller, u2) in the Dashboard and fill scripts/sandbox/sandbox.env.
TXT
echo "provision summary: pass=$PASS fail=$FAILN → $RESULTS"; [ "$FAILN" -eq 0 ]
