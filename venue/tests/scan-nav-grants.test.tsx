import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { Shell } from "@/components/shell/Shell";
import { canScan, canScanGrants, derivePrincipal, type GrantSet } from "@/lib/roles";
import type { PreviewContext } from "@/lib/preview";

/**
 * E-F11 — the Scanner nav must ask the same question the scan page asks.
 *
 * 31272d2c fixed the authority question at the PAGE (`canScanGrants(p.entry.grants)`) and left the NAV on
 * the derived principal (`canScan(ctx.role)`). Those disagree for exactly one common account: an org owner
 * who also holds venue_manager so they can work the door. `PRECEDENCE` puts org_owner first, so
 * `derivePrincipal` returns "org_owner", `canScan("org_owner")` is false, and the nav entry vanishes —
 * while the page admits them. The scanner was reachable only by typing the URL.
 *
 * Wired but unreachable is the class that stopped an owner acceptance pass at step 1 of 12, so the
 * discriminating account is pinned here rather than left to a demo to discover.
 */
const ORG = "0b150d75-2a79-4f68-bdf8-5786c6a52406";
const VENUE = "7a9430e9-4d6f-474c-92cc-99bc56ea0b1e";
const EVENT = "12477b06-23bb-4fe8-a3eb-2a7ad643a086";

const html = (el: React.ReactElement) => renderToStaticMarkup(el);
const dbCtx = (grants: GrantSet): PreviewContext => ({
  role: derivePrincipal(grants)!,
  state: "live",
  source: "database",
  countersAvailable: false,
  writesEnabled: false,
  verifiedRole: true,
  mayScan: canScanGrants(grants),
  scope: { orgId: ORG, venueId: VENUE },
});
const shell = (ctx: PreviewContext) =>
  html(<Shell ctx={ctx} event={{ eventId: EVENT, title: "A night" }} active="setup" signedInAs="organizer@example.test"><p>x</p></Shell>);

describe("the Scanner nav asks the grants, like the page does (E-F11)", () => {
  const ownerWhoWorksTheDoor: GrantSet = { venueRoles: ["venue_manager"], orgRoles: ["org_owner"] };

  it("the discriminating account exists: its principal says no while its grants say yes", () => {
    expect(derivePrincipal(ownerWhoWorksTheDoor)).toBe("org_owner");
    expect(canScan("org_owner")).toBe(false); // what the nav used to ask
    expect(canScanGrants(ownerWhoWorksTheDoor)).toBe(true); // what the page asks
  });

  it("an org owner who also holds venue_manager is OFFERED the scanner", () => {
    expect(shell(dbCtx(ownerWhoWorksTheDoor))).toContain(`/events/${EVENT}/scan`);
  });

  it("negative control — a grant set that may not scan is not offered it", () => {
    const financeOnly: GrantSet = { venueRoles: ["venue_finance"], orgRoles: ["org_finance"] };
    expect(canScanGrants(financeOnly)).toBe(false);
    expect(shell(dbCtx(financeOnly))).not.toContain(`/events/${EVENT}/scan`);
  });

  it("negative control — a plain venue_scanner IS offered it, so the fix did not simply open the nav to everyone", () => {
    const scanner: GrantSet = { venueRoles: ["venue_scanner"], orgRoles: [] };
    expect(shell(dbCtx(scanner))).toContain(`/events/${EVENT}/scan`);
  });

  it("fixtures mode still follows the preview role, because there are no grants to ask", () => {
    const fx = (role: PreviewContext["role"]): PreviewContext => ({ role, state: "live", source: "fixtures", countersAvailable: true, writesEnabled: true });
    expect(shell(fx("venue_manager"))).toContain("/scan");
    expect(shell(fx("org_owner"))).not.toContain("/scan");
  });
});
