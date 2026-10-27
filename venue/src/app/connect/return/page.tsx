import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { ConnectLanding } from "@/components/org/ConnectLanding";
import { DATA_SOURCE } from "@/lib/env";
import { myPayoutOrgIds } from "@/lib/org/connect";
import { CONNECT_CONTEXT_COOKIE, CONNECT_RETURN_PATH, parseConnectContext, resolveLanding, RETURN_COPY } from "@/lib/org/connect-return";
import { probeSession } from "@/lib/auth/session";

export const dynamic = "force-dynamic";
export const metadata = { title: "Back from Stripe" };

/**
 * Stripe's `return_url` — the operator finished (or left) onboarding.
 *
 * It reads NOTHING from the URL: the edge may not put state there, and this
 * handler may not treat URL-borne values as truth (Ruling G §3). The org comes
 * from the cookie this app set when it issued the link, checked against the
 * caller's own roles, or from those roles alone. Then it sends the operator to
 * that org's payouts page, where the state is re-read from the database.
 *
 * No query parameter is read, so there is no redirect this page can be told to
 * make; the only destinations are built from a validated uuid.
 */
export default async function ConnectReturnPage() {
  if (DATA_SOURCE !== "database") redirect("/");
  const session = await probeSession();
  if (!session.ok || !session.user) redirect(`/login?next=${encodeURIComponent(CONNECT_RETURN_PATH)}`);

  const jar = await cookies();
  const hinted = parseConnectContext(jar.get(CONNECT_CONTEXT_COOKIE)?.value);
  const orgs = await myPayoutOrgIds();
  const landing = resolveLanding(hinted, orgs.ok ? orgs.orgIds : []);

  if (landing.kind === "org") redirect(landing.path);
  return <ConnectLanding landing={landing} heading={RETURN_COPY.heading} body={RETURN_COPY.body} />;
}
