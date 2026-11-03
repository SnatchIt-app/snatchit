import Link from "next/link";
import { payoutsPath, type Landing } from "@/lib/org/connect-return";

/**
 * What the return and refresh routes render when they cannot send the operator
 * straight on: either a choice between the orgs they hold a payouts role in, or
 * a plain statement that they hold none. Never a guess, and every link is built
 * from a uuid this app validated.
 */
export function ConnectLanding({ landing, heading, body }: { landing: Landing; heading: string; body: string }) {
  return (
    <main id="main" className="mx-auto max-w-xl px-4 py-10">
      <h1 className="text-2xl font-semibold text-ink">{heading}</h1>
      <p className="mt-2 text-sm text-muted">{body}</p>

      {landing.kind === "choose" ? (
        <section className="panel mt-6 px-5 py-5" aria-labelledby="which-org">
          <h2 id="which-org" className="text-base font-semibold text-ink">Which organization?</h2>
          <p className="mt-1 text-sm text-dim">You hold a payouts role in more than one, and Stripe does not tell us which one you were setting up.</p>
          <ul className="mt-4 space-y-2">
            {landing.orgIds.map((orgId) => {
              const href = payoutsPath(orgId);
              return href ? (
                <li key={orgId}>
                  <Link href={href} className="link font-mono text-sm">
                    {orgId.slice(0, 8)}
                  </Link>
                </li>
              ) : null;
            })}
          </ul>
        </section>
      ) : (
        <p className="panel mt-6 px-5 py-4 text-sm text-muted">
          This account holds no payouts role in any organization, so there is nothing to show. Payouts are the organization owner&apos;s and finance&apos;s to see.
        </p>
      )}
    </main>
  );
}
