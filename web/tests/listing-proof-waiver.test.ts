import { readFileSync } from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

// Owner proof waiver (A's 156, 2026-10-15): an admin listing their own inventory may publish
// without a ticket-proof upload. Admin status comes only from current_user_is_admin() (the
// caller's own boolean); anything else is "no". The waiver is recorded in the same insert
// (path NULL, waived_by, reason; the database stamps waived_at), and buyers see "Ticket proof
// waived by Snatch It" — never a bare "Verified" next to it.

const h = vi.hoisted(() => ({
  admin: { data: true as unknown, error: null as unknown },
  inserts: [] as Record<string, unknown>[],
  rpcs: [] as string[],
}));

vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push: () => {} }) }));
vi.mock("@/lib/create-listing-actions", () => ({ createListingAction: async () => ({}), uploadListingImageAction: async () => ({}) }));
vi.mock("@/lib/payouts", () => ({ getPayoutStatus: async () => ({ status: "connected" }) }));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({
    auth: { getUser: async () => ({ data: { user: { phone_confirmed_at: "2026-01-01T00:00:00Z" } } }) },
    rpc: async (name: string) => {
      h.rpcs.push(name);
      if (name === "current_user_is_admin") return h.admin;
      return { data: [{ allowed: true, reason: "ok", risk_tier: null }], error: null };
    },
    from: () => ({
      insert(row: Record<string, unknown>) {
        h.inserts.push(row);
        return { select: () => ({ single: async () => ({ data: { id: "new-listing" }, error: null }) }) };
      },
    }),
  }),
}));

import { createListing, getListingGates } from "@/lib/create-listing";
import { CreateListingForm } from "@/components/sell/CreateListingForm";
import { LISTING_COLUMNS } from "@/lib/listings";
import { PROOF_WAIVED_NOTE, proofWaiverNote, sellerVerifiedLabel } from "@/lib/listing-display";
import { PROOF_WAIVER_DEFAULT_REASON, PROOF_WAIVER_LABEL } from "@/lib/proof-waiver";

const SELLER = "cccccccc-cccc-4ccc-8ccc-ccccccccccc3";

const payload = (over: Record<string, unknown> = {}) =>
  ({
    eventName: "Show",
    venue: "Club",
    neighborhood: "wynwood",
    eventDate: "2026-11-01",
    eventTime: "22:00:00",
    ticketType: "GA",
    quantity: 1,
    transferMethod: "mobile_transfer",
    restrictions: null,
    startingBid: 20,
    buyNowEnabled: false,
    buyNowPrice: null,
    durationHours: 72,
    ticketPlatform: "dice",
    coverImagePath: "c",
    proofImagePath: "",
    sellerCommitmentAccepted: true,
    category: "clubs",
    ...over,
  }) as unknown as Parameters<typeof createListing>[1];

beforeEach(() => {
  h.admin = { data: true, error: null };
  h.inserts = [];
  h.rpcs = [];
});

describe("createListing with an owner proof waiver", () => {
  it("admin: one insert records the waiver — path NULL, waived_by = seller, reason; no waived_at sent", async () => {
    const out = await createListing(SELLER, payload({ proofWaiver: { reason: `  ${PROOF_WAIVER_DEFAULT_REASON}  ` } }));
    expect(out).toEqual({ id: "new-listing" });
    expect(h.inserts).toHaveLength(1);
    const row = h.inserts[0];
    expect(row.proof_of_ownership_path).toBeNull();
    expect(row.proof_waived_by).toBe(SELLER);
    expect(row.proof_waiver_reason).toBe(PROOF_WAIVER_DEFAULT_REASON);
    expect(row).not.toHaveProperty("proof_waived_at");
    expect(row).not.toHaveProperty("proof_status");
  });

  it("a proof path sent alongside a waiver is discarded (the waiver insert carries NULL)", async () => {
    await createListing(SELLER, payload({ proofImagePath: "u/proofs/1.png", proofWaiver: { reason: "Owner-confirmed" } }));
    expect(h.inserts[0].proof_of_ownership_path).toBeNull();
  });

  it.each([
    ["not an admin", { data: false, error: null }],
    ["admin check errors (e.g. before 156 exists)", { data: null, error: { message: "function not found" } }],
    ["admin check returns something other than true", { data: "true", error: null }],
  ])("refused when %s — nothing inserted", async (_label, admin) => {
    h.admin = admin;
    const out = await createListing(SELLER, payload({ proofWaiver: { reason: "Owner-confirmed" } }));
    expect(out).toEqual({ error: "Only an admin can list without ticket proof." });
    expect(h.inserts).toHaveLength(0);
  });

  it.each(["", "   ", "x".repeat(301)])("refused without a 1–300 character reason (%#)", async (reason) => {
    const out = await createListing(SELLER, payload({ proofWaiver: { reason } }));
    expect(out.error).toMatch(/reason for the proof waiver/);
    expect(h.inserts).toHaveLength(0);
  });

  it("without a waiver the insert is unchanged: no waiver keys, no admin lookup", async () => {
    await createListing(SELLER, payload({ proofImagePath: `${SELLER}/proofs/1.png` }));
    const row = h.inserts[0];
    expect(row.proof_of_ownership_path).toBe(`${SELLER}/proofs/1.png`);
    for (const k of ["proof_waived_by", "proof_waiver_reason", "proof_waived_at"]) expect(row).not.toHaveProperty(k);
    expect(h.rpcs).not.toContain("current_user_is_admin");
  });
});

describe("waiver wording (the reason is readable through the public API)", () => {
  it("default reason and field hint are neutral and say so", async () => {
    const { PROOF_WAIVER_REASON_HINT } = await import("@/lib/proof-waiver");
    expect(PROOF_WAIVER_DEFAULT_REASON).toBe("Owner inventory; ticket proof waived by Snatch It.");
    expect(PROOF_WAIVER_REASON_HINT).toBe(
      "Recorded on the listing and readable through the public API. Keep it neutral. Buyers see “Ticket proof waived by Snatch It”.",
    );
    expect(PROOF_WAIVER_DEFAULT_REASON).not.toMatch(/DICE|account|platform owner|confirmed/i);
    const form = readFileSync(path.resolve(__dirname, "../src/components/sell/CreateListingForm.tsx"), "utf8");
    expect(form).toContain("hint={PROOF_WAIVER_REASON_HINT}");
  });
});

describe("normal listings keep the proof requirement (owner: keep it intact)", () => {
  it.each([
    ["empty", ""],
    ["missing", undefined],
    ["null", null],
    ["another seller's proof", "dddddddd-dddd-4ddd-8ddd-ddddddddddd4/proofs/1.png"],
    ["a cover, not a proof", `${SELLER}/covers/1.png`],
    ["the folder alone", `${SELLER}/proofs/`],
    ["a traversal", `${SELLER}/proofs/../covers/1.png`],
  ])("no waiver and %s proof path → refused, nothing inserted", async (_label, proofImagePath) => {
    expect(await createListing(SELLER, payload({ proofImagePath }))).toEqual({ error: "Upload proof of ownership." });
    expect(h.inserts).toHaveLength(0);
  });

  it("the seller's own proof upload is accepted", async () => {
    expect(await createListing(SELLER, payload({ proofImagePath: `${SELLER}/proofs/own-upload.png` }))).toEqual({ id: "new-listing" });
  });
});

describe("who sees the waiver option", () => {
  it("getListingGates: canWaiveProof only on a literal true from current_user_is_admin()", async () => {
    expect((await getListingGates(SELLER)).canWaiveProof).toBe(true);
    h.admin = { data: false, error: null };
    expect((await getListingGates(SELLER)).canWaiveProof).toBe(false);
    h.admin = { data: null, error: { message: "function public.current_user_is_admin() does not exist" } };
    expect((await getListingGates(SELLER)).canWaiveProof).toBe(false);
  });

  it("the /sell form shows the checkbox to admins only, and a non-admin keeps the proof upload", () => {
    const html = (canWaiveProof: boolean) =>
      renderToStaticMarkup(createElement(CreateListingForm, { riskWarning: null, canWaiveProof }));
    const label = PROOF_WAIVER_LABEL.replace(/[()]/g, (c) => `\\${c}`);
    expect(html(false)).not.toMatch(new RegExp(label));
    expect(html(false)).toContain('aria-label="Proof of ownership"');
    expect(html(true)).toMatch(new RegExp(label));
    // Unchecked by default: the proof upload is still there until the admin opts in.
    expect(html(true)).toContain('aria-label="Proof of ownership"');
  });

  it("the sell page passes the gate through", () => {
    const src = readFileSync(path.resolve(__dirname, "../src/app/sell/page.tsx"), "utf8");
    expect(src).toContain("canWaiveProof={gates.canWaiveProof}");
  });
});

describe("what buyers see", () => {
  it("a waived listing says so plainly; others say nothing", () => {
    expect(proofWaiverNote({ proof_waived_at: "2026-10-15T03:00:00Z" })).toBe("Ticket proof waived by Snatch It");
    expect(PROOF_WAIVED_NOTE).not.toMatch(/verif/i);
    expect(proofWaiverNote({ proof_waived_at: null })).toBeNull();
    expect(proofWaiverNote({})).toBeNull();
  });

  it("the seller badge never reads a bare 'Verified' next to a waiver", () => {
    expect(sellerVerifiedLabel(true, true)).toBe("Verified seller");
    expect(sellerVerifiedLabel(true, false)).toBe("Verified");
    expect(sellerVerifiedLabel(false, true)).toBeNull();
    expect(sellerVerifiedLabel(null, false)).toBeNull();
  });

  it("only the waiver timestamp is read publicly — never who waived it or why", () => {
    const cols = LISTING_COLUMNS.split(",").map((c) => c.trim());
    expect(cols).toContain("proof_waived_at");
    expect(cols).not.toContain("proof_waived_by");
    expect(cols).not.toContain("proof_waiver_reason");
  });

  it("the listing page renders the note and the badge through these helpers", () => {
    const src = readFileSync(path.resolve(__dirname, "../src/app/listing/[id]/page.tsx"), "utf8");
    expect(src).toContain("proofWaiverNote(listing)");
    expect(src).toContain("sellerVerifiedLabel(seller?.is_verified_seller, proofNote !== null)");
    expect(src).not.toMatch(/>Verified<\/Badge>/);
  });
});
