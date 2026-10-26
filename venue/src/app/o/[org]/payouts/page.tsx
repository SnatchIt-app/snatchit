import Link from "next/link";
import { ConnectActions } from "@/components/org/ConnectActions";
import { StepUpForm } from "@/components/auth/StepUpForm";
import { DeniedState } from "@/components/ui/State";
import { DATA_SOURCE } from "@/lib/env";
import { isUuid } from "@/lib/page";
import { ACTION_LABEL, FAILURE_COPY, nextConnectAction } from "@/lib/org/connect-contract";
import { readOrgConnect } from "@/lib/org/connect";

export const metadata = { title: "Payouts" };
export const dynamic = "force-dynamic";

/**
 * Organizer payouts — where the organization's money goes (readiness row 1).
 *
 * Org-scoped, not venue-scoped: a payout destination belongs to the
 * organization, so this page lives at /o/<org>/payouts and names no venue. The
 * state comes from `kernel.get_org_connect_state` under the operator's own
 * session (last4 only, never the account id). The actions go to the
 * `connect-onboarding` edge, which is not deployed on any project yet — when
 * it answers 404 the buttons say so instead of failing blankly.
 *
 * Who: org_owner or org_finance may read this page. Only an org_owner, on a
 * session that has confirmed it is them (aal2), can name the destination —
 * `kernel.set_org_connect_ref` stamps the separation-of-duties operand, so the
 * server refuses anyone else no matter what this page renders.
 */
export default async function PayoutsPage({ params, searchParams }: { params: Promise<{ org: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { org } = await params;
  const sp = await searchParams;
  const stepUp = sp.step_up === "1";
  const back = typeof sp.from === "string" && sp.from.startsWith("/o/") ? sp.from : null;
  const self = `/o/${org}/payouts`;

  if (!isUuid(org)) return <DeniedState standalone surface="This organization" reason="That link does not name an organization this dashboard can read." />;
  if (DATA_SOURCE !== "database")
    return (
      <Shell org={org} back={back}>
        <p className="panel px-5 py-4 text-sm text-muted">
          Demo — sample data. Payout setup is a real money-identity step, so it is not simulated here. Open the venue dashboard against the database to use it.
        </p>
      </Shell>
    );

  const view = await readOrgConnect(org);
  if (!view.capability.mayView)
    return (
      <Shell org={org} back={back}>
        <DeniedState
          surface="Payouts"
          reason={view.failure ? FAILURE_COPY[view.failure.kind] : "This account holds no role in this organization."}
          alternative={back ? { label: "Back to the dashboard", href: back } : undefined}
        />
      </Shell>
    );

  const { state, capability } = view;
  const action = nextConnectAction(state);

  if (stepUp)
    return (
      <Shell org={org} back={back}>
        <section className="panel mx-auto max-w-md px-5 py-5" aria-labelledby="su">
          <h2 id="su" className="text-lg font-semibold text-ink">Confirm it is you</h2>
          <p className="mt-1 text-sm text-dim">
            Naming where your organization&apos;s money is paid needs a second confirmation. This applies to the payout step only; nothing else on the dashboard asks for it.
          </p>
          <div className="mt-4">
            <StepUpForm nextHref={self} />
          </div>
        </section>
      </Shell>
    );

  return (
    <Shell org={org} back={back}>
      <section className="panel px-5 py-5" aria-labelledby="payouts-state">
        <h2 id="payouts-state" className="text-lg font-semibold text-ink">Where your money is paid</h2>
        {!state ? (
          <p role="alert" className="mt-3 border-l-2 border-warning bg-warning-soft px-3 py-2 text-sm text-warning">
            {view.failure ? FAILURE_COPY[view.failure.kind] : "The payout state could not be read."}
          </p>
        ) : (
          <dl className="mt-3 space-y-2 text-sm">
            <Row label="Payout account">
              {state.bound ? (
                <>
                  Connected · ending <span className="font-mono">{state.last4 ?? "····"}</span>
                </>
              ) : (
                "Not set up yet"
              )}
            </Row>
            <Row label="Can receive transfers">{state.transfersActive === null ? "Not checked yet" : state.transfersActive ? "Yes" : "Not yet"}</Row>
            <Row label="Organization">{state.orgStatus ?? "unknown"}</Row>
            <Row label="State last synced from Stripe">{state.syncedAt ?? "Never"}</Row>
          </dl>
        )}

        <p className="mt-3 text-xs text-dim">
          This dashboard only ever sees the last four characters of the account; the full identifier stays on the server. Nothing on this page moves money or tells you that money moved.
        </p>

        <ConnectActions orgId={org} action={action} mayBind={capability.mayBind} needsStepUp={capability.needsStepUp} stepUpHref={`${self}?step_up=1${back ? `&from=${encodeURIComponent(back)}` : ""}`} />

        {!capability.mayBind && !capability.needsStepUp ? (
          <p className="mt-3 text-sm text-muted">
            You can read this page and start the setup. {FAILURE_COPY.requires_owner}
          </p>
        ) : null}

        <details className="mt-5">
          <summary className="text-sm text-dim">What the next button does</summary>
          <p className="mt-2 text-sm text-muted">
            “{ACTION_LABEL[action]}” asks the server for a one-time Stripe link and opens it in a new tab. Snatch It never sees your bank details: they go to Stripe, and Stripe tells us only whether the account can receive
            transfers. Selling cannot be turned on until Stripe says it can.
          </p>
        </details>
      </section>
    </Shell>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-baseline justify-between gap-2 border-b border-line pb-2 last:border-0">
      <dt className="text-dim">{label}</dt>
      <dd className="font-medium text-ink">{children}</dd>
    </div>
  );
}

/** A minimal frame: this page is org-scoped, so the venue workspace shell (which needs a venue) is deliberately not used. */
function Shell({ org, back, children }: { org: string; back: string | null; children: React.ReactNode }) {
  return (
    <main id="main" className="mx-auto max-w-2xl px-4 py-8">
      <header className="mb-5">
        <p className="eyebrow text-dim">Organization</p>
        <h1 className="mt-1 text-2xl font-semibold text-ink">Payouts</h1>
        <p className="mt-1 text-sm text-dim">
          <span className="font-mono">{org.slice(0, 8)}</span>
          {back ? (
            <>
              {" · "}
              <Link href={back} className="link">
                Back to the dashboard
              </Link>
            </>
          ) : null}
        </p>
      </header>
      {children}
    </main>
  );
}
