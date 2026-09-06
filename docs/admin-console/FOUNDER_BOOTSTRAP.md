# Founder access bootstrap

The operating console has **no self-service path to admin**. Nothing a user can
edit (profile columns, metadata, signup forms) grants operator access. The
authority chain is:

```
auth.users (individual founder account, email + password + TOTP)
   └─ public.admin_users (row inserted by the owner, service_role only)
         └─ kernel.is_platform(['platform_admin'])  ← every ops.* RPC checks this
               └─ + JWT claim aal = 'aal2'            ← and this (MFA)
```

`profiles.is_admin` is **not** consulted anywhere by the console (the old portal
used it; it is a user-adjacent column and is being retired as an authority).

## One-time procedure per founder

Performed by the project owner in the Supabase dashboard (SQL editor runs as
`postgres`, which can write `public.admin_users`). Never from the console, never
from application code, never with the anon key.

1. **Create the individual account.** Each founder signs up with their own
   email through the normal Snatch It auth (mobile or web) or the owner creates
   the user in Authentication → Users. No shared login.
2. **Confirm the account is the right one.**
   ```sql
   select id, email, created_at from auth.users where email = '<founder email>';
   ```
3. **Grant operator membership** (the only escalation path; audited by the
   dashboard's own SQL history):
   ```sql
   insert into public.admin_users (user_id, label)
   values ('<auth.users.id from step 2>', 'Founder — <name>')
   on conflict (user_id) do nothing;
   ```
4. **Verify**
   ```sql
   select a.user_id, a.label, a.created_at, u.email
     from public.admin_users a join auth.users u on u.id = a.user_id;
   ```
   Exactly the founders should be listed. Production had **one** row on
   2026-09-06 (`SNATCH IT APP ADMIN`); the second founder must be added before
   any approval-gated action (payout release override, refund execution) can be
   completed, because approvals require a *different* founder.
5. **Enrol MFA.** The founder opens the console, signs in, and is taken to
   `/mfa`, where they enrol an authenticator app (TOTP) and verify a code.
   Every console page and every mutation requires an `aal2` session; a session
   without MFA can sign in but sees nothing.

## Revocation

```sql
delete from public.admin_users where user_id = '<id>';
```
Takes effect on the next request (membership is evaluated per RPC call, not
cached in the session). Also revoke the user's sessions in Authentication →
Users → "Sign out user" if the device may be compromised.

## Support / risk staff (future)

`kernel.platform_role` carries `platform_support` and `platform_risk`, and every
console RPC already applies the role matrix
(`ops.action_allowed_roles`). Granting those roles is **fail-closed today**
(`kernel.grant_platform_role` raises `dual_control_unavailable` pending owner
signature on PFA-4). Until that amendment lands, the only operator class that
can exist is `platform_admin` via `admin_users`.

## What the bootstrap does NOT do

- It does not create Supabase auth accounts (owner or the founder does that).
- It does not bypass MFA: an `admin_users` row without an enrolled factor is a
  founder who can sign in and be redirected to enrol — nothing else.
- It grants nothing to the anon key or to any client bundle: `admin_users` is
  service_role-only (RLS on, zero policies), and `ops.*` functions only ever
  read it through `kernel.is_platform()`.
