# Sandbox harness — isolated Supabase project + Stripe Sandbox (test mode)

Runs the `rc/R4_sandbox_readiness.md` matrix against a NON-production project. Refuses the production ref
(`hqycwntpfoztoinemqns`) and live keys structurally. Nothing here is executed until the owner has provided the
environment (`11_SANDBOX_ENVIRONMENT_REQUEST.md` §3).

Files: `lib.sh` (helpers, guards) · `sandbox.env.example` (copy to `sandbox.env`, untracked) · `10_provision.sh`
(schema push, non-secret DB provisioning, edge deploy, prints the owner-run statements) · `20_matrix.sh` (S1–S12 API
steps with SQL/Stripe assertions; device-only steps are printed as manual instructions).

Results are written to `RESULTS_<timestamp>.md` in `$SANDBOX_OUT` with every assertion marked REAL (Stripe test mode)
— the mocked suites (vitest/pgTAP) are never counted as sandbox evidence.
