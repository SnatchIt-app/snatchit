import type { DoorRejectReason, EventSession, ScanDevice, ScanResult } from "@/lib/types";

/** Spec §12.5 — the scan-result enum with operator labels. */
export const SCAN_RESULT_LABEL: Record<ScanResult, string> = {
  admitted: "Admitted",
  duplicate: "Already used",
  invalid: "Not recognised",
  frozen: "Blocked — check-in list is open",
  fraud_review: "Needs review",
};

/** The plain name for each refusal, for staff reading it off a screen at the door. */
export const REJECT_TITLE: Record<DoorRejectReason, string> = {
  version_stale: "Out-of-date pass",
  voided: "Ticket no longer valid",
  listed_locked: "Listed for resale or being transferred",
  refund_hold: "Refund under review",
  duplicate: "Already used",
  wrong_session: "Wrong night",
};

/** Spec §12.5 — the six door reject reasons and their operator copy (binding). */
export const REJECT_COPY: Record<DoorRejectReason, string> = {
  version_stale: "This pass is out of date. Ask them to open the Snatch It app.",
  voided: "This ticket was refunded or cancelled.",
  listed_locked: "This ticket is listed for resale or mid-transfer.",
  refund_hold: "A refund is being reviewed on this ticket, so it can't be used yet. If they don't want the refund, it has to be cancelled in the Snatch It app — then this ticket works again.",
  duplicate: "Already used",
  wrong_session: "Right event, wrong night.",
};

/** Spec §22.5 — three backend names for one thing; the dashboard says "Already used" and uses `duplicate` internally. */
export function normaliseReason(backend: string): DoorRejectReason | "active" | "unknown" {
  if (backend === "already_scanned" || backend === "duplicate") return "duplicate";
  if (backend === "active") return "active";
  if ((Object.keys(REJECT_COPY) as string[]).includes(backend)) return backend as DoorRejectReason;
  return "unknown";
}

export const WALLET_STALENESS_NOTE = "A pass shown from a wallet can be out of date. The Snatch It app screen is the one that counts.";

/**
 * Spec §12.4 — the freeze is session-wide, monotone and terminal, with an
 * implicit backstop: effective_freeze_at = LEAST(door_open_at, COALESCE(doors_at, starts_at) + offset).
 * Returns the instant and which input produced it, so an operator whose
 * transfers froze with no manifest open can learn why.
 */
export function effectiveFreeze(session: Pick<EventSession, "doorOpenAt" | "doorsAt" | "startsAt">, backstopOffsetMinutes = 0): { at: string; source: "manifest_open" | "doors_time_backstop" } {
  const anchor = new Date(session.doorsAt ?? session.startsAt).getTime() + backstopOffsetMinutes * 60 * 1000;
  if (session.doorOpenAt && new Date(session.doorOpenAt).getTime() <= anchor) return { at: session.doorOpenAt, source: "manifest_open" };
  return { at: new Date(anchor).toISOString(), source: "doors_time_backstop" };
}

export type ManifestState = "closed" | "open" | "closed_after_open";
export function manifestState(session: Pick<EventSession, "doorOpenAt">, openEpisode: boolean): ManifestState {
  if (!session.doorOpenAt) return "closed";
  return openEpisode ? "open" : "closed_after_open";
}
/** Spec §12.4 — the copy after opening and after closing (transfers never resume). */
export const MANIFEST_COPY: Record<ManifestState, string> = {
  closed: "Check-in list not open yet",
  open: "Check-in open — tickets can no longer be passed on",
  closed_after_open: "Doors closed — tickets still can't be passed on",
};

/**
 * Whether the door-manifest control should be offered, and which way round.
 *
 * Built on the existing `manifestState` rules plus the session's own status —
 * no new concept. The defect this closes: a **completed** session still
 * offered "Open door manifest" with a confirm about freezing transfers for a
 * night that had already happened.
 *
 * Re-opening a session whose manifest was opened and closed stays available
 * while the night is still running (doors genuinely reopen, and the episode
 * history is per-episode). What is never offered is opening the door on a
 * session that is over or cancelled. Closing an episode someone left open is
 * always offered, including after the night ends — an open episode is a loose
 * end, not a door.
 */
export type ManifestAction = { kind: "open" } | { kind: "close" } | { kind: "none"; why: string };

export function manifestAction(session: Pick<EventSession, "status">, state: ManifestState): ManifestAction {
  if (state === "open") return { kind: "close" };
  if (session.status === "cancelled") return { kind: "none", why: "This session was cancelled, so there is no door to open. Transfers stay closed." };
  if (session.status === "completed") return { kind: "none", why: "This night is over. The manifest is closed and transfers stay closed — nothing here can be reopened." };
  return { kind: "open" };
}

/** Spec §12.3 — staleness as a duration with a threshold chip, never a raw version number. */
export function manifestAge(device: Pick<ScanDevice, "lastSyncAt">, now: Date): { minutes: number; stale: boolean } {
  const minutes = Math.max(0, Math.round((now.getTime() - new Date(device.lastSyncAt).getTime()) / 60000));
  return { minutes, stale: minutes > 10 };
}
