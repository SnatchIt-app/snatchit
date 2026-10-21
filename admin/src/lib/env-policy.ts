/**
 * Pure environment rules, kept apart from env.ts so they can be tested with
 * any input. env.ts reads each `process.env.NEXT_PUBLIC_*` by its literal
 * name (that is what Next.js inlines into the browser bundle) and passes the
 * values in here.
 */

/**
 * Labels that mean "this console is wired to the local synthetic harness".
 * Exact values only: anything else — unset, "preview", "staging", "sample",
 * a typo — is not a claim that the figures are fixtures.
 */
export const SAMPLE_DATA_LABELS = ["local", "harness", "rehearsal"] as const;

/**
 * The label to show in the "Sample data" notice, or null for no notice.
 * The notice says the figures are not Snatch It business data, so it needs an
 * explicitly set allowlisted label, and it never appears on a Vercel
 * production or preview deployment (both can point at a real database).
 */
export function sampleDataLabel(input: { label: string | undefined; vercelEnv: string | undefined }): string | null {
  const vercel = (input.vercelEnv ?? "").trim();
  if (vercel === "production" || vercel === "preview") return null;
  const label = (input.label ?? "").trim();
  return (SAMPLE_DATA_LABELS as readonly string[]).includes(label) ? label : null;
}
