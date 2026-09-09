import { describe, expect, it } from "vitest";
import {
  PREVIEW_PRINCIPALS,
  canEditEvents,
  canManagePins,
  canManualLookup,
  canOperateManifest,
  canReadDoor,
  canReadEvents,
  canReleaseHold,
  canSeeCheckIn,
  exportTemplate,
  inventoryView,
  isPrincipal,
  rosterClasses,
} from "@/lib/roles";

describe("role matrix projections (spec §5, §5.1, §9.3, §12.4)", () => {
  it("fan has no dashboard at all", () => {
    expect(canReadEvents("fan")).toBe(false);
    expect(rosterClasses("fan")).toBeNull();
    expect(canReadDoor("fan")).toBe(false);
  });
  it("only owner/admin/venue manager edit events, change capacity, manage PINs", () => {
    for (const p of PREVIEW_PRINCIPALS) {
      const full = ["org_owner", "org_admin", "venue_manager"].includes(p);
      expect(canEditEvents(p)).toBe(full);
      expect(canManagePins(p)).toBe(full);
      expect(canOperateManifest(p)).toBe(full);
    }
  });
  it("the scanner may not create the security boundary it scans against (O-4)", () => {
    expect(canReadDoor("venue_scanner")).toBe(true);
    expect(canOperateManifest("venue_scanner")).toBe(false);
  });
  it("door staff and box office never get a roster; they get single-record lookup", () => {
    expect(rosterClasses("venue_scanner")).toBeNull();
    expect(rosterClasses("venue_box_office")).toBeNull();
    expect(canManualLookup("venue_scanner")).toBe(true);
    expect(canManualLookup("venue_box_office")).toBe(true);
  });
  it("finance sees money and never contact or check-in; marketing sees contact and never money", () => {
    expect(rosterClasses("venue_finance")).toEqual(["IDENT", "MONEY"]);
    expect(canSeeCheckIn("org_finance")).toBe(false);
    expect(rosterClasses("venue_marketing")).toEqual(["IDENT", "OPS", "CONTACT"]);
    expect(canManualLookup("venue_marketing")).toBe(false);
    expect(exportTemplate("venue_marketing")).toBe("audience_v1");
    expect(exportTemplate("venue_finance")).toBeNull();
    expect(exportTemplate("venue_manager")).toBe("operations_v1");
  });
  it("org_member and scanner see remaining only, never raw counters", () => {
    expect(inventoryView("org_member")).toBe("remaining_only");
    expect(inventoryView("venue_scanner")).toBe("remaining_only");
    expect(inventoryView("venue_manager")).toBe("counters");
    expect(inventoryView("venue_marketing")).toBe("none");
  });
  it("box office may release a hold but not change capacity", () => {
    expect(canReleaseHold("venue_box_office")).toBe(true);
    expect(canEditEvents("venue_box_office")).toBe(false);
  });
  it("rejects unknown principals and the removed venue_promoter label", () => {
    expect(isPrincipal("venue_promoter")).toBe(false);
    expect(isPrincipal("venue_door")).toBe(false);
    expect(isPrincipal("venue_scanner")).toBe(true);
  });
});
