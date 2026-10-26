import { classifyToken, type BlockedWhy, type ScanOutcome } from "@/lib/scan/outcome";

/**
 * The scanner's state, as a pure reducer with the clock passed in, so every
 * rule here is a unit test: one attempt in flight at a time, a repeated frame
 * of the same pass is ignored, a lost answer is CANNOT VERIFY with "check
 * again" on the SAME command key (the server answers duplicate for a
 * re-sent admission, never a second admitted), a green never comes from a
 * timeout, and nothing is sent while blocked, offline-known, or not ready.
 */
export type CameraState = "off" | "starting" | "on" | "paused" | "denied" | "no_camera" | "busy_elsewhere" | "unsupported" | "insecure";
export type Phase = "ready" | "busy" | "result";

export type Attempt = { wire: string; atomId: string; commandKey: string; sentAt: number; retries: number };
export type HistoryRow = { outcome: ScanOutcome; at: number };

export type ScanState = {
  sessionId: string;
  camera: CameraState;
  phase: Phase;
  online: boolean;
  blocked: BlockedWhy | null;
  attempt: Attempt | null;
  outcome: ScanOutcome | null;
  outcomeAt: number | null;
  /** wire → when it was last decoded or answered; the same pass is not re-sent inside SAME_WIRE_COOLDOWN_MS */
  seen: Record<string, number>;
  /** server-confirmed admissions from THIS phone since the screen opened (measured, not estimated) */
  admittedHere: number;
  history: HistoryRow[];
};

export type ScanEvent =
  | { type: "camera"; state: CameraState }
  | { type: "online"; online: boolean }
  | { type: "blocked"; why: BlockedWhy | null }
  | { type: "session"; sessionId: string }
  | { type: "decoded"; wire: string; commandKey: string; now: number }
  | { type: "result"; commandKey: string; outcome: ScanOutcome; now: number }
  | { type: "failed"; commandKey: string; why: "timeout" | "transport"; now: number }
  | { type: "retry"; now: number }
  | { type: "dismiss"; now: number }
  | { type: "tick"; now: number };

export const SAME_WIRE_COOLDOWN_MS = 6000;
export const ADMITTED_SHOW_MS = 2500;
export const REFUSAL_SHOW_MS = 8000;
export const HISTORY_MAX = 5;

export function initialScanState(sessionId: string): ScanState {
  return { sessionId, camera: "off", phase: "ready", online: true, blocked: null, attempt: null, outcome: null, outcomeAt: null, seen: {}, admittedHere: 0, history: [] };
}

function withOutcome(s: ScanState, outcome: ScanOutcome, now: number, keepAttempt: boolean): ScanState {
  const history = [{ outcome, at: now }, ...s.history].slice(0, HISTORY_MAX);
  const seen = s.attempt ? { ...s.seen, [s.attempt.wire]: now } : s.seen;
  return { ...s, phase: "result", outcome, outcomeAt: now, history, seen, attempt: keepAttempt ? s.attempt : null, admittedHere: outcome.kind === "admitted" ? s.admittedHere + 1 : s.admittedHere };
}

export function scanReducer(s: ScanState, e: ScanEvent): ScanState {
  switch (e.type) {
    case "camera":
      return { ...s, camera: e.state };
    case "online":
      return { ...s, online: e.online };
    case "blocked":
      return e.why ? { ...s, blocked: e.why, phase: "ready", attempt: null, camera: s.camera === "on" ? "paused" : s.camera } : { ...s, blocked: null };
    case "session":
      return { ...initialScanState(e.sessionId), camera: s.camera, online: s.online };
    case "decoded": {
      if (s.blocked || s.phase !== "ready" || s.camera !== "on") return s;
      const last = s.seen[e.wire];
      if (last !== undefined && e.now - last < SAME_WIRE_COOLDOWN_MS) return s;
      const seen = { ...s.seen, [e.wire]: e.now };
      const c = classifyToken(e.wire, s.sessionId);
      if (c.kind === "invalid") return withOutcome({ ...s, seen }, { kind: "invalid", why: c.why }, e.now, false);
      if (c.kind === "wrong_event") return withOutcome({ ...s, seen }, { kind: "wrong_event", atomId: c.atomId, tokenSessionId: c.tokenSessionId }, e.now, false);
      if (!s.online) return withOutcome({ ...s, seen }, { kind: "cannot_verify", why: "offline", retrySameKey: false }, e.now, false);
      return { ...s, seen, phase: "busy", outcome: null, outcomeAt: null, attempt: { wire: e.wire, atomId: c.claims.atomId, commandKey: e.commandKey, sentAt: e.now, retries: 0 } };
    }
    case "result": {
      if (!s.attempt || s.attempt.commandKey !== e.commandKey) return s; // a late answer for an attempt that is no longer the current one
      return withOutcome(s, e.outcome, e.now, false);
    }
    case "failed": {
      if (!s.attempt || s.attempt.commandKey !== e.commandKey) return s;
      return withOutcome(s, { kind: "cannot_verify", why: e.why, retrySameKey: true }, e.now, true);
    }
    case "retry": {
      if (!s.attempt || s.phase !== "result" || s.outcome?.kind !== "cannot_verify" || !s.outcome.retrySameKey) return s;
      if (!s.online) return s;
      return { ...s, phase: "busy", outcome: null, outcomeAt: null, attempt: { ...s.attempt, sentAt: e.now, retries: s.attempt.retries + 1 } };
    }
    case "dismiss":
      if (s.phase === "busy") return s;
      return { ...s, phase: "ready", outcome: null, outcomeAt: null, attempt: null };
    case "tick": {
      if (s.phase !== "result" || !s.outcome || s.outcomeAt === null) return s;
      if (s.outcome.kind === "cannot_verify") return s; // never auto-cleared: a person decides
      const ttl = s.outcome.kind === "admitted" ? ADMITTED_SHOW_MS : REFUSAL_SHOW_MS;
      return e.now - s.outcomeAt >= ttl ? { ...s, phase: "ready", outcome: null, outcomeAt: null, attempt: null } : s;
    }
  }
}

/** The action the UI should take after a reduce: send the attempt attempt (with its key) or nothing. */
export function pendingSend(before: ScanState, after: ScanState): Attempt | null {
  if (after.phase !== "busy" || !after.attempt) return null;
  if (before.phase === "busy" && before.attempt?.commandKey === after.attempt.commandKey && before.attempt.retries === after.attempt.retries) return null;
  return after.attempt;
}
