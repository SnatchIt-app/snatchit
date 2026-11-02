import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * /users/[id] on the live console carries RC5 account suspension (#103,
 * migration 152). Dashboard v2 was branched before it, so its copy of this
 * page said suspension "does not exist", had no Suspend/Restore control, and
 * counted a suspension as a listing restriction — which made the
 * "risk row says allowed — investigate" warning fire for every suspended user
 * whose listing creation was not blocked. These render the real page with the
 * data layer mocked. StatusBadge sentence-cases its label, hence "Account suspended".
 */
const mocks = vi.hoisted(() => ({ callOps: vi.fn(), requireOperator: vi.fn() }));

vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({
  notFound: () => {
    throw new Error("notFound");
  },
  redirect: () => {
    throw new Error("redirect");
  },
  usePathname: () => "/users",
  useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }),
  useParams: () => ({}),
}));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/auth/session", () => ({ requireOperator: mocks.requireOperator }));

import UserPage from "@/app/(console)/users/[id]/page";
import type { OperatorRole, UserRestriction } from "@/lib/types";

const USER = "11111111-2222-4333-8444-555555555555";
const ME = "aaaaaaaa-0000-4000-8000-000000000001";
const OTHER_OPERATOR = "bbbbbbbb-0000-4000-8000-000000000002";
const WARNING = "Console restriction is active but the risk row says allowed — investigate.";

const suspension = (over: Partial<UserRestriction> = {}): UserRestriction => ({
  id: "r-susp",
  kind: "suspended",
  reason: "chargeback ring under review",
  actor: OTHER_OPERATOR,
  created_at: "2026-10-14T10:00:00Z",
  lifted_at: null,
  ...over,
});
const listingBlock = (over: Partial<UserRestriction> = {}): UserRestriction => ({
  id: "r-block",
  kind: "listing_blocked",
  reason: "counterfeit listings",
  actor: OTHER_OPERATOR,
  created_at: "2026-10-13T09:00:00Z",
  lifted_at: null,
  ...over,
});

async function render({
  restrictions = [],
  listingBlocked = false,
  role = "platform_risk",
  me = ME,
}: { restrictions?: Partial<UserRestriction>[]; listingBlocked?: boolean; role?: OperatorRole; me?: string } = {}) {
  mocks.requireOperator.mockResolvedValue({ id: me, label: "o***@example.test", role, aal: "aal2" });
  mocks.callOps.mockResolvedValue({
    ok: true,
    data: {
      profile: { id: USER, display_name: "Maya", created_at: "2026-01-01T00:00:00Z" },
      auth: {},
      onboarding: {},
      listings: [],
      orders_as_buyer: [],
      orders_as_seller: [],
      reports_made: [],
      reports_received: [],
      seller_flags: [],
      seller_risk_score: { risk_tier: "medium", is_listing_blocked: listingBlocked },
      restrictions,
      cases: [],
      is_operator: false,
    },
  });
  return renderToStaticMarkup(await UserPage({ params: Promise.resolve({ id: USER }) }));
}

const decode = (s: string) => s.replace(/&quot;/g, '"').replace(/&amp;/g, "&");
const forms = (html: string) => html.split("<form").slice(1).map((f) => f.slice(0, f.indexOf("</form>")));
const hidden = (form: string, name: string) => {
  const v = form.match(new RegExp(`name="${name}" value="([^"]*)"`))?.[1];
  return v === undefined ? undefined : decode(v);
};
/** The posted envelope of every console action form on the page (case creation excluded). */
const envelopes = (html: string) =>
  forms(html)
    .map((f) => ({ action: hidden(f, "action_type"), kind: (JSON.parse(hidden(f, "params") ?? "{}") as { kind?: string }).kind }))
    .filter((e) => e.action !== "case_create");
const panel = (html: string, title: string) => html.split("<section").find((s) => s.includes(`>${title}</h2>`)) ?? "";

beforeEach(() => {
  mocks.callOps.mockReset();
  mocks.requireOperator.mockReset();
});

describe("restriction warning counts listing_blocked restrictions only", () => {
  it("a suspended user whose listing creation is allowed is not flagged for investigation", async () => {
    const html = await render({ restrictions: [suspension()], listingBlocked: false });
    expect(html).not.toContain(WARNING);
  });

  it("an active listing_blocked restriction with the risk row saying allowed still warns", async () => {
    expect(await render({ restrictions: [listingBlock()], listingBlocked: false })).toContain(WARNING);
  });

  it("a restriction row with no kind is a listing block (rows written before kinds existed)", async () => {
    expect(await render({ restrictions: [listingBlock({ kind: undefined })], listingBlocked: false })).toContain(WARNING);
  });

  it("a lifted listing block does not warn, alone or beside an active suspension", async () => {
    expect(await render({ restrictions: [listingBlock({ lifted_at: "2026-10-15T00:00:00Z" })] })).not.toContain(WARNING);
    expect(await render({ restrictions: [suspension(), listingBlock({ lifted_at: "2026-10-15T00:00:00Z" })] })).not.toContain(WARNING);
  });

  it("an active listing block that the risk row confirms does not warn, with or without a suspension", async () => {
    expect(await render({ restrictions: [listingBlock()], listingBlocked: true })).not.toContain(WARNING);
    expect(await render({ restrictions: [suspension(), listingBlock()], listingBlocked: true })).not.toContain(WARNING);
  });
});

describe("account suspension is offered (RC5, migration 152)", () => {
  it("never says account suspension does not exist; the block form points to it instead", async () => {
    for (const listingBlocked of [false, true]) {
      const html = await render({ listingBlocked });
      expect(html).not.toMatch(/suspension does not exist/i);
      expect(html).not.toMatch(/not offered/i);
    }
    expect(await render({ listingBlocked: false })).toContain("To stop bidding and buying as well, use Account suspension below.");
  });

  it("a risk operator can suspend a user who is not suspended", async () => {
    const html = await render({ restrictions: [], role: "platform_risk" });
    expect(envelopes(html)).toContainEqual({ action: "user_restrict", kind: "suspended" });
    expect(envelopes(html)).not.toContainEqual({ action: "user_unrestrict", kind: "suspended" });
    const p = panel(html, "Account suspension");
    expect(p).toContain(">Not suspended</span>");
    expect(p).toContain("Suspend account");
  });

  it("an active suspension shows in the header and the panel, with Restore for a founder", async () => {
    const html = await render({ restrictions: [suspension()], role: "platform_admin" });
    expect(html).toContain(">Account suspended</span>");
    expect(panel(html, "Account suspension")).toContain(">Suspended</span>");
    expect(envelopes(html)).toContainEqual({ action: "user_unrestrict", kind: "suspended" });
    expect(envelopes(html)).not.toContainEqual({ action: "user_restrict", kind: "suspended" });
    const p = panel(html, "Account suspension");
    expect(p).toContain("Restore account");
    expect(p).toContain("Reason on record: chargeback ring under review");
  });

  it("a lifted suspension is not an active one", async () => {
    const html = await render({ restrictions: [suspension({ lifted_at: "2026-10-15T00:00:00Z" })] });
    expect(html).not.toContain(">Account suspended</span>");
    expect(panel(html, "Account suspension")).toContain(">Not suspended</span>");
    expect(envelopes(html)).toContainEqual({ action: "user_restrict", kind: "suspended" });
  });

  it("support keeps listing blocks but gets no suspend or restore form", async () => {
    for (const restrictions of [[], [suspension()]]) {
      const html = await render({ restrictions, role: "platform_support" });
      expect(envelopes(html).filter((e) => e.kind === "suspended")).toEqual([]);
      expect(envelopes(html)).toContainEqual({ action: "user_restrict", kind: "listing_blocked" });
    }
    expect(await render({ role: "platform_support" })).toContain("Only founders and risk operators can suspend an account.");
    expect(await render({ restrictions: [suspension()], role: "platform_support" })).toContain("Only founders and risk operators can restore a suspended account.");
  });

  it("an operator is not offered a form to suspend themselves", async () => {
    const html = await render({ me: USER, role: "platform_admin" });
    expect(envelopes(html).filter((e) => e.kind === "suspended")).toEqual([]);
    expect(html).toContain("You cannot suspend your own account.");
  });

  it("the page uses v2's rem type scale — no px font sizes", async () => {
    const html = await render({ restrictions: [suspension()], role: "platform_admin" });
    expect(html.match(/text-\[\d+(\.\d+)?px\]/g) ?? []).toEqual([]);
    expect(panel(html, "Account suspension")).toContain("text-[0.8125rem]");
    expect(panel(html, "Account suspension")).toContain("text-[0.75rem]");
  });
});
