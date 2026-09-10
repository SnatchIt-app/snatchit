/**
 * Role labels and the capability predicates this PREVIEW renders against.
 *
 * Source of truth: spec §5 (49-row matrix), §5.1 (four new labels), §9.3
 * (attendee column classes), §12.4 (manifest authority, ruling O-4). Nothing
 * here is a permission — production authority is re-checked inside each RPC
 * (spec §2.2). The preview only decides what to SHOW, and it shows less, never
 * more, than the matrix grants.
 */

export const VENUE_ROLES = ["venue_manager", "venue_finance", "venue_box_office", "venue_marketing", "venue_promoter_manager", "venue_scanner"] as const;
export const ORG_ROLES = ["org_owner", "org_admin", "org_finance", "org_marketing", "org_promoter_manager", "org_member"] as const;
/** `fan` is not a role label; it stands for an authenticated user with no org/venue grant (spec §5: no dashboard at all). */
export const PREVIEW_PRINCIPALS = [...VENUE_ROLES, ...ORG_ROLES, "fan"] as const;

export type VenueRole = (typeof VENUE_ROLES)[number];
export type OrgRole = (typeof ORG_ROLES)[number];
export type Principal = (typeof PREVIEW_PRINCIPALS)[number];

export const DEFAULT_PRINCIPAL: Principal = "venue_manager";

/** The caller's verified grants for one route (venue_api.my_staff_roles / my_org_roles, filtered to the route's venue and org). */
export type GrantSet = { venueRoles: VenueRole[]; orgRoles: OrgRole[] };

/**
 * Database mode: the display principal is derived from verified grants, never
 * from a client parameter. Precedence = widest capability first (spec §5 rows:
 * owner/admin/manager hold the union; then the money plane; then the narrower
 * venue labels). A caller with no grant at this venue/org has no dashboard
 * (spec §5: "anon and fan have no dashboard at all") — returns null.
 */
const PRECEDENCE: Principal[] = [
  "org_owner", "org_admin", "venue_manager", "org_finance", "venue_finance", "venue_box_office",
  "org_marketing", "venue_marketing", "org_promoter_manager", "venue_promoter_manager", "venue_scanner", "org_member",
];
export function derivePrincipal(g: GrantSet): Principal | null {
  const held = new Set<Principal>([...g.venueRoles, ...g.orgRoles]);
  return PRECEDENCE.find((r) => held.has(r)) ?? null;
}
export function isVenueRole(x: string): x is VenueRole {
  return (VENUE_ROLES as readonly string[]).includes(x);
}
export function isOrgRole(x: string): x is OrgRole {
  return (ORG_ROLES as readonly string[]).includes(x);
}

export function isPrincipal(x: string | null | undefined): x is Principal {
  return !!x && (PREVIEW_PRINCIPALS as readonly string[]).includes(x);
}

/** Display names for the role switcher (spec §1: operators see role names; labels stay internal). */
export const PRINCIPAL_LABEL: Record<Principal, string> = {
  venue_manager: "Venue manager",
  venue_finance: "Venue finance",
  venue_box_office: "Box office",
  venue_marketing: "Marketing (venue)",
  venue_promoter_manager: "Promoter manager (venue)",
  venue_scanner: "Scanner (door staff)",
  org_owner: "Org owner",
  org_admin: "Org admin",
  org_finance: "Org finance",
  org_marketing: "Marketing (org)",
  org_promoter_manager: "Promoter manager (org)",
  org_member: "Org member",
  fan: "Fan (no venue role)",
};

const FULL_OPERATORS: Principal[] = ["org_owner", "org_admin", "venue_manager"];

/** Matrix row 7 — Events list & detail (read). `venue_scanner` is session-scoped (note 3). */
export function canReadEvents(p: Principal): boolean {
  return p !== "fan";
}
/** Matrix rows 8–10 (+§5.1 rows 8–10): create / edit draft / status / cancel. */
export function canEditEvents(p: Principal): boolean {
  return FULL_OPERATORS.includes(p);
}
/** Row 11: resale policy read. */
export function canReadResalePolicy(p: Principal): boolean {
  return ["org_owner", "org_admin", "org_finance", "venue_manager", "venue_finance", "venue_marketing", "org_marketing"].includes(p);
}
/** Row 12 (+§5.1): ticket types read. */
export function canReadTicketTypes(p: Principal): boolean {
  return ["org_member", "org_owner", "org_admin", "org_finance", "venue_manager", "venue_finance", "venue_scanner", "venue_box_office", "venue_marketing", "org_marketing"].includes(p);
}
/** Row 15 (+note 4, §5.1): full counters (capacity/held/sold) vs `remaining` only. */
export function inventoryView(p: Principal): "counters" | "remaining_only" | "none" {
  if (["org_owner", "org_admin", "org_finance", "venue_manager", "venue_finance", "venue_box_office"].includes(p)) return "counters";
  if (["org_member", "venue_scanner"].includes(p)) return "remaining_only";
  return "none";
}
/** Counters render only when the role may read them AND the data source can supply them. */
export function showCounters(p: Principal, ctx: { countersAvailable?: boolean }): boolean {
  return inventoryView(p) === "counters" && ctx.countersAvailable !== false;
}
/** Row 16: create batch / capacity change. */
export function canChangeCapacity(p: Principal): boolean {
  return FULL_OPERATORS.includes(p);
}
/** Row 17 (+note 9, §5.1 note d): holds list; release is a reversal. */
export function canReadHolds(p: Principal): boolean {
  return ["org_owner", "org_admin", "org_finance", "venue_manager", "venue_finance", "venue_scanner", "venue_box_office"].includes(p);
}
export function canReleaseHold(p: Principal): boolean {
  return ["org_owner", "org_admin", "venue_manager", "venue_box_office"].includes(p);
}

export type ColumnClass = "IDENT" | "OPS" | "CONTACT" | "MONEY";

/**
 * Spec §9.3 — what each role sees on the attendee surface. A role holds a
 * class, never an individual column; a denied class is absent, not null.
 * `null` = no roster at all (denial names the alternative in the UI).
 */
export function rosterClasses(p: Principal): ColumnClass[] | null {
  switch (p) {
    case "venue_manager":
    case "org_owner":
    case "org_admin":
      return ["IDENT", "OPS", "CONTACT", "MONEY"];
    case "venue_marketing":
    case "org_marketing":
      return ["IDENT", "OPS", "CONTACT"];
    case "org_finance":
    case "venue_finance":
      return ["IDENT", "MONEY"]; // money + counts; never contact, never check-in
    default:
      return null; // box office, scanner, promoter managers, org_member, fan
  }
}
/** Finance roles are `D` on venue.scan — check-in never renders for them (spec §9.1 col 8, note 2). */
export function canSeeCheckIn(p: Principal): boolean {
  const c = rosterClasses(p);
  return !!c && c.includes("OPS");
}
/** Spec §9.6 — the money template is the only export with MONEY; audience template for marketing. Hidden below `lg` regardless (§3.3). */
export function exportTemplate(p: Principal): "operations_v1" | "audience_v1" | null {
  if (FULL_OPERATORS.includes(p)) return "operations_v1";
  if (p === "venue_marketing" || p === "org_marketing") return "audience_v1";
  return null;
}
/** Row 35 caveat: `org_admin` on the refund list is contested (D-8) — the preview follows the spec's instruction not to render it. */
export function canReadOrders(p: Principal): boolean {
  return ["org_owner", "org_finance", "venue_manager", "venue_finance", "venue_box_office"].includes(p);
}

/** Rows 29–33 — door surfaces. */
export function canReadDoor(p: Principal): boolean {
  return ["org_owner", "org_admin", "venue_manager", "venue_scanner"].includes(p);
}
/** Row 29: PIN issue/revoke. `venue_scanner` reads PINs only (note 17: never the hash). */
export function canManagePins(p: Principal): boolean {
  return FULL_OPERATORS.includes(p);
}
/** Spec §12.4 / O-4: manifest open/close — never the scanner, never a door PIN. */
export function canOperateManifest(p: Principal): boolean {
  return FULL_OPERATORS.includes(p);
}
/** Row 31: live scan board. */
export function canReadScanBoard(p: Principal): boolean {
  return ["org_owner", "org_admin", "venue_manager", "venue_scanner"].includes(p);
}
/** Row 32 (+§5.1 row 32): manual lookup — the door's ONLY attendee read; box office too; marketing denied. */
export function canManualLookup(p: Principal): boolean {
  return ["org_owner", "org_admin", "venue_manager", "venue_scanner", "venue_box_office"].includes(p);
}
/** Row 33: flag queue view & escalate; row 34: resolve is platform-only and never rendered here. */
export function canReadFlagQueue(p: Principal): boolean {
  return ["org_owner", "org_admin", "venue_manager", "venue_scanner"].includes(p);
}
