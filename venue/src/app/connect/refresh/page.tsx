import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { ConnectLanding } from "@/components/org/ConnectLanding";
import { DATA_SOURCE } from "@/lib/env";
import { myPayoutOrgIds } from "@/lib/org/connect";
import { CONNECT_CONTEXT_COOKIE, CONNECT_REFRESH_PATH, parseConnectContext, resolveLanding, REFRESH_COPY } from "@/lib/org/connect-return";
import { probeSession } from "@/lib/auth/session";

export const dynamic = "force-dynamic";
export const metadata = { title: "Setup link expired" };

/**
 * Stripe's `refresh_url` — the link was spent or expired before onboarding
 * finished. Same rules as the return route: nothing is read from the URL, and
 * the org comes from the cookie checked against the caller's roles.
 *
 * It does NOT mint a new link by itself. This is a GET that Stripe navigates
 * the browser to, and a GET must not make an outbound money-identity call on
 * its own; the operator presses the button on the payouts page instead. The
 * `retry` flag on that redirect is decoration for the copy — the page's state
 * still comes from the database read, never from the URL.
 */
export default async function ConnectRefreshPage() {
  if (DATA_SOURCE !== "database") redirect("/");
  const session = await probeSession();
  if (!session.ok || !session.user) redirect(`/login?next=${encodeURIComponent(CONNECT_REFRESH_PATH)}`);

  const jar = await cookies();
  const hinted = parseConnectContext(jar.get(CONNECT_CONTEXT_COOKIE)?.value);
  const orgs = await myPayoutOrgIds();
  const landing = resolveLanding(hinted, orgs.ok ? orgs.orgIds : []);

  if (landing.kind === "org") redirect(`${landing.path}?retry=1`);
  return <ConnectLanding landing={landing} heading={REFRESH_COPY.heading} body={REFRESH_COPY.body} />;
}
