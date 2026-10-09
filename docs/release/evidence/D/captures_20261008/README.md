# D captures, 2026-10-08 — copied out of the session scratchpad for the drive migration

Copied here because the originals were in `/private/tmp/claude-501/.../scratchpad`, which a drive
migration may not carry. Each is referenced by `../D_WITNESS_C4_PIN_20261008.md` or
`../D_WITNESS_PRESENT_STATE_AND_R0_20261008.md`.

## Vercel project state — three points in time

| file | when | why it is irreplaceable |
|---|---|---|
| `vercel_project_T1.json` | 2026-10-07 23:38Z | **Pre-deployment.** Pin set, nothing deployed, `updatedAt 1791430528219`. The project has since changed, so this state **cannot be re-read**. |
| `vercel_project_T2.json` | 2026-10-08 19:42Z | After the failed redeploy attempt 1 — the read that showed `updatedAt` unmoved. |
| `vercel_project_T3.json` | 2026-10-08 20:02Z | After the successful deployment. |

**Redacted on purpose.** These are *whitelisted extracts*, not the raw API responses. A pre-commit scan
found an `env` array and five key/secret-named fields in each raw body, so the raw files were **not**
copied. No secret values are present here. The evidence actually cited — `commandForIgnoringBuildStep`,
`rootDirectory`, `nodeVersion`, `updatedAt`, `ssoProtection`, `link.productionBranch`,
`latestDeployment` — is preserved in full.

## Stripe R1 access evidence

`stripe_r1_wrong_account.stdout.txt` / `.stderr.txt` — the raw output establishing that the local CLI is
bound to `acct_1T6Fb1(truncated)` ("SNATCH IT sandbox"), a different Stripe account from the one holding
the seven refunded payments, returning `resource_missing: No such payment_intent`. This is the basis for
"R1 cannot be executed by D". Scanned clean — no keys or tokens.

## Deliberately NOT copied

`/tmp/m150.sql` and `/tmp/m906.sql` — migration bodies extracted from gate `abef9506`. **Reproducible
from git at any time**, so they are not irreplaceable and are safe to lose in the migration.
