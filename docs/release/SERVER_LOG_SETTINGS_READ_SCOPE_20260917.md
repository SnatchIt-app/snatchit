# Server-log exposure — the exact settings read, prepared for the owner (A, 2026-09-17). NOTHING HERE IS AUTHORIZED OR EXECUTED

**Why (owner ruling 8 on the operator-permission proposal, rev 2):** "Record server-log exposure as unverified. Prepare the exact logging-settings read scope separately; no production read is authorized here." The open question (F11 of D's proposal): when an RPC statement errors, can Postgres write its parameters (including the raw `p_params` JSON with an invitee address) into server logs, which Supabase dashboard users can read? Stock PostgreSQL logs no bind parameters on error (`log_parameter_max_length_on_error` defaults to 0) and PostgREST binds the request body as a parameter. But the project's actual settings, including any per-role or per-database overrides, have never been read. **Status: UNVERIFIED.**

## The read (identical text for each environment; each environment needs its own authorization line)
Read-only. It returns setting **names and values** for `log_%` parameters only. It never returns other GUCs, secrets, rows, identities or log contents. `pg_db_role_setting` is filtered to `log_%` keys inside SQL **before** anything is returned, because those arrays can carry non-log keys (for example PostgREST settings) that must not be printed.

```sql
-- R-LOG-1: effective server settings (names/values only)
select name, setting, source
  from pg_settings
 where name in ('log_min_error_statement','log_statement','log_min_duration_statement',
                'log_parameter_max_length','log_parameter_max_length_on_error',
                'log_error_verbosity','log_min_messages')
 order by name;

-- R-LOG-2: per-role / per-database overrides of log_% keys only (the keys are filtered before output)
select coalesce(r.rolname, '(all roles)') as role, coalesce(d.datname, '(all databases)') as db, kv
  from pg_db_role_setting s
  left join pg_roles r on r.oid = s.setrole
  left join pg_database d on d.oid = s.setdatabase
  cross join lateral unnest(s.setconfig) as kv
 where kv like 'log\_%'
 order by 1, 2, 3;
```

## Authorization lines (separate; none granted by this document)
- **Sandbox (`ofaidukbieeekqaboscm`):** "A runs R-LOG-1 and R-LOG-2 once, read-only, on the sandbox, and records the returned names and values."
- **Production (`hqycwntpfoztoinemqns`):** "A runs R-LOG-1 and R-LOG-2 once, read-only, on production, and records the returned names and values." This is a production read and needs the owner's explicit words for exactly this read.

## What the result can and cannot establish
- If `log_parameter_max_length_on_error` = 0 and no `log_%` override sets it or `log_statement` for the API roles (`authenticator`, `anon`, `authenticated`, `service_role`), **parameters are not written to the server log on error.** That closes the parameter channel only.
- **Not established by this read:** the statement text itself when a parameter is inlined rather than bound, PostgREST's own request logging, Supabase platform log pipelines (API/edge logs), and log retention or who can view it. Each is a separate question, stated as unverified.
- An error **message** that quotes an address is a different channel. 138 sanitizes the message it records, but the server logs the ORIGINAL message when an error is not caught. 138's dispatch catches the kernel invite error, so that message never reaches the server log as an uncaught ERROR; any other uncaught error path would need its own check.

## Stopping conditions
The identity assertion for the target project fails · any query returns a non-`log_%` key · any error text contains a value outside the filtered columns (stop and redact).
