"use client";

import Link from "next/link";
import { useCallback, useEffect, useReducer, useRef, useState } from "react";
import { Icon } from "@/components/ui/Icon";
import { DEMO_DATA_LABEL } from "@/lib/preview";
import { readSessionScanCounters, scanAction, type SessionScanCounters } from "@/lib/scan/actions";
import { initialScanState, scanReducer, type CameraState, type ScanState } from "@/lib/scan/machine";
import { OUTCOME_TITLE, OUTCOME_TONE, outcomeDetail, type BlockedWhy, type ScanOutcome, type Tone } from "@/lib/scan/outcome";

/**
 * The online phone-web scanner (CONTRACTS.md C7 / P8): the staff member's
 * phone browser, the venue app's own session, one camera, one server call
 * per pass. Everything that decides is in lib/scan (pure, tested); this
 * component only owns the camera, the clock and the screen.
 *
 * Camera: getUserMedia on a user gesture (iOS needs it), rear camera
 * preferred, frames drawn to a small canvas every ~150 ms and decoded with
 * the browser's BarcodeDetector where it exists (feature-detected at run
 * time) or jsQR (Apache-2.0, no dependencies, loaded only on this screen)
 * otherwise. The page's route is the only one whose Permissions-Policy
 * allows the camera (next.config.ts).
 */
export type ScannerSession = { sessionId: string; label: string | null; startsAt: string; endsAt: string | null; status: string };
export type ScannerIds = { orgId: string; venueId: string; eventId: string };

const DECODE_EVERY_MS = 150;
const MAX_FRAME_WIDTH = 640;
const CLIENT_TIMEOUT_MS = 10_000;
const DEVICE_LABEL_KEY = "snatchit.venue.scanner.device_label";

type BarcodeDetectorLike = { detect(source: CanvasImageSource): Promise<{ rawValue: string }[]> };
type BarcodeDetectorCtor = { new (opts: { formats: string[] }): BarcodeDetectorLike; getSupportedFormats(): Promise<string[]> };
type JsQr = (data: Uint8ClampedArray, width: number, height: number, opts?: { inversionAttempts?: "dontInvert" | "onlyInvert" | "attemptBoth" | "invertFirst" }) => { data: string } | null;

const TONE_CLASS: Record<Tone, string> = {
  success: "bg-success-soft text-success",
  warning: "bg-warning-soft text-warning",
  danger: "bg-danger-soft text-danger",
  neutral: "bg-well text-ink",
};

const CAMERA_COPY: Record<Exclude<CameraState, "on" | "starting" | "off" | "paused">, { title: string; hint: string }> = {
  denied: { title: "Camera permission was refused", hint: "Allow the camera for this site in the browser's site settings, then tap Try again. Until then this phone cannot scan; use another phone." },
  no_camera: { title: "No camera found", hint: "This device has no usable camera. Use another phone." },
  busy_elsewhere: { title: "The camera is in use", hint: "Another app or tab holds the camera. Close it and tap Try again." },
  unsupported: { title: "This browser cannot use the camera", hint: "Open this page in Safari (iPhone) or Chrome (Android). In-app browsers often block the camera." },
  insecure: { title: "Not a secure page", hint: "The camera only works over https. Open the https address of the venue dashboard." },
};

const BLOCKED_COPY: Record<BlockedWhy, { title: string; hint: string }> = {
  signed_out: { title: "Signed out", hint: "Your session ended. Sign in again to keep scanning; nothing was admitted meanwhile." },
  no_role: { title: "This account cannot scan here", hint: "Scanning needs the venue scanner or venue manager role at this venue. Ask a manager to grant it, then sign in again." },
  config: { title: "The dashboard is not configured for a database", hint: "Tell the organiser. Nothing can be verified from this phone." },
};

function readStoredLabel(): string {
  try {
    return window.localStorage.getItem(DEVICE_LABEL_KEY) ?? "";
  } catch {
    return "";
  }
}

function storeLabel(label: string) {
  try {
    window.localStorage.setItem(DEVICE_LABEL_KEY, label);
  } catch {
    // private mode or blocked storage: the label lives for this page only
  }
}

function fmtWhen(iso: string, timeZone: string | null): string {
  try {
    return new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit", ...(timeZone ? { timeZone } : {}) }).format(new Date(iso));
  } catch {
    return iso;
  }
}

function mapCameraError(e: unknown): CameraState {
  const name = e instanceof Error ? e.name : "";
  if (name === "NotAllowedError" || name === "SecurityError") return "denied";
  if (name === "NotFoundError" || name === "OverconstrainedError") return "no_camera";
  if (name === "NotReadableError" || name === "AbortError") return "busy_elsewhere";
  return "unsupported";
}

export function ScannerClient({
  demo,
  ids,
  eventTitle,
  sessions,
  defaultSessionId,
  staff,
  timeZone,
  loginHref,
}: {
  demo: boolean;
  ids: ScannerIds;
  eventTitle: string;
  sessions: ScannerSession[];
  defaultSessionId: string | null;
  staff: { label: string | null; role: string };
  /** The venue's zone where the dashboard knows it; null = show the phone's zone and say so. */
  timeZone: string | null;
  loginHref: string;
}) {
  const [state, dispatch] = useReducer(scanReducer, defaultSessionId ?? "", initialScanState);
  const [step, setStep] = useState<"setup" | "scan">("setup");
  const [sessionId, setSessionId] = useState(defaultSessionId ?? "");
  const [deviceLabel, setDeviceLabel] = useState("");
  const [counters, setCounters] = useState<{ kind: "idle" } | { kind: "loading" } | { kind: "ok"; data: SessionScanCounters | null } | { kind: "unavailable"; message: string }>({ kind: "idle" });

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const rafRef = useRef<number | null>(null);
  const detectorRef = useRef<BarcodeDetectorLike | null>(null);
  const jsQrRef = useRef<JsQr | null>(null);
  const lastDecodeAtRef = useRef(0);
  const decodingRef = useRef(false);
  const stateRef = useRef<ScanState>(state);
  const frameRef = useRef<(ts: number) => void>(() => undefined);
  const lastSentRef = useRef<string | null>(null);
  const wantCameraRef = useRef(false);

  useEffect(() => {
    stateRef.current = state;
  }, [state]);

  // The stored label is read after mount (never during render: the server has no storage), off the render tick.
  useEffect(() => {
    const id = setTimeout(() => setDeviceLabel(readStoredLabel()), 0);
    return () => clearTimeout(id);
  }, []);

  const session = sessions.find((s) => s.sessionId === state.sessionId) ?? null;

  // ── counters (measured on the server; unavailable is said, never shown as zero) ──
  const refreshCounters = useCallback(() => {
    if (demo || !stateRef.current.sessionId) return;
    setCounters((c) => (c.kind === "ok" ? c : { kind: "loading" }));
    readSessionScanCounters({ ...ids, sessionId: stateRef.current.sessionId }).then(
      (r) => setCounters(r.ok ? { kind: "ok", data: r.data } : { kind: "unavailable", message: r.kind === "not_exposed" ? "Attendance counts are not available on this project yet." : r.message }),
      () => setCounters({ kind: "unavailable", message: "Attendance counts could not be read." }),
    );
  }, [demo, ids]);

  // ── camera ──
  const stopCamera = useCallback((next: CameraState) => {
    wantCameraRef.current = false;
    if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
    rafRef.current = null;
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    dispatch({ type: "camera", state: next });
  }, []);

  const decodeFrame = useCallback(async (): Promise<string | null> => {
    const v = videoRef.current;
    const c = canvasRef.current;
    if (!v || !c || v.readyState < 2 || !v.videoWidth) return null;
    const scale = Math.min(1, MAX_FRAME_WIDTH / v.videoWidth);
    const w = Math.round(v.videoWidth * scale);
    const h = Math.round(v.videoHeight * scale);
    if (!w || !h) return null;
    c.width = w;
    c.height = h;
    const g = c.getContext("2d", { willReadFrequently: true });
    if (!g) return null;
    g.drawImage(v, 0, 0, w, h);
    if (detectorRef.current) {
      const codes = await detectorRef.current.detect(c);
      return codes[0]?.rawValue ?? null;
    }
    if (!jsQrRef.current) jsQrRef.current = (await import("jsqr")).default as unknown as JsQr;
    const img = g.getImageData(0, 0, w, h);
    return jsQrRef.current(img.data, w, h, { inversionAttempts: "dontInvert" })?.data ?? null;
  }, []);

  // The frame loop lives in a ref so requestAnimationFrame always calls the latest closure.
  useEffect(() => {
    frameRef.current = (ts: number) => {
      if (!wantCameraRef.current) return;
      rafRef.current = requestAnimationFrame((t) => frameRef.current(t));
      if (decodingRef.current || ts - lastDecodeAtRef.current < DECODE_EVERY_MS) return;
      const s = stateRef.current;
      if (s.phase !== "ready" || s.camera !== "on" || s.blocked) return;
      lastDecodeAtRef.current = ts;
      decodingRef.current = true;
      decodeFrame()
        .then((wire) => {
          if (wire && stateRef.current.phase === "ready") dispatch({ type: "decoded", wire, commandKey: crypto.randomUUID(), now: Date.now() });
        })
        .catch(() => {
          // a failed decode of one frame is not an outcome; the next frame tries again
        })
        .finally(() => {
          decodingRef.current = false;
        });
    };
  }, [decodeFrame]);

  const startCamera = useCallback(async () => {
    if (typeof window === "undefined") return;
    if (!window.isSecureContext) return dispatch({ type: "camera", state: "insecure" });
    if (!navigator.mediaDevices?.getUserMedia) return dispatch({ type: "camera", state: "unsupported" });
    dispatch({ type: "camera", state: "starting" });
    wantCameraRef.current = true;
    try {
      const Detector = (window as unknown as { BarcodeDetector?: BarcodeDetectorCtor }).BarcodeDetector;
      if (Detector && !detectorRef.current) {
        const formats = await Detector.getSupportedFormats().catch(() => [] as string[]);
        if (formats.includes("qr_code")) detectorRef.current = new Detector({ formats: ["qr_code"] });
      }
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false });
      if (!wantCameraRef.current) {
        stream.getTracks().forEach((t) => t.stop());
        return;
      }
      streamRef.current = stream;
      const v = videoRef.current;
      if (v) {
        v.srcObject = stream;
        await v.play().catch(() => undefined);
      }
      dispatch({ type: "camera", state: "on" });
      lastDecodeAtRef.current = 0;
      rafRef.current = requestAnimationFrame((t) => frameRef.current(t));
    } catch (e) {
      wantCameraRef.current = false;
      dispatch({ type: "camera", state: mapCameraError(e) });
    }
  }, []);

  useEffect(() => () => stopCamera("off"), [stopCamera]);

  // Background / resume (S03): the camera stops when the tab is hidden and restarts when it is shown.
  useEffect(() => {
    const onVis = () => {
      if (document.visibilityState === "hidden" && stateRef.current.camera === "on") stopCamera("paused");
      else if (document.visibilityState === "visible" && stateRef.current.camera === "paused" && !stateRef.current.blocked) void startCamera();
    };
    document.addEventListener("visibilitychange", onVis);
    return () => document.removeEventListener("visibilitychange", onVis);
  }, [startCamera, stopCamera]);

  // Online / offline (S10): known offline means CANNOT VERIFY before anything is sent.
  useEffect(() => {
    dispatch({ type: "online", online: navigator.onLine });
    const on = () => dispatch({ type: "online", online: true });
    const off = () => dispatch({ type: "online", online: false });
    window.addEventListener("online", on);
    window.addEventListener("offline", off);
    return () => {
      window.removeEventListener("online", on);
      window.removeEventListener("offline", off);
    };
  }, []);

  // The clock for auto-clearing a shown result.
  useEffect(() => {
    if (state.phase !== "result") return;
    const id = setInterval(() => dispatch({ type: "tick", now: Date.now() }), 250);
    return () => clearInterval(id);
  }, [state.phase]);

  // One send per (command key, retry count); a late answer for an older key is dropped by the reducer.
  useEffect(() => {
    const a = state.phase === "busy" ? state.attempt : null;
    if (!a) return;
    const tag = `${a.commandKey}:${a.retries}`;
    if (lastSentRef.current === tag) return;
    lastSentRef.current = tag;
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      dispatch({ type: "failed", commandKey: a.commandKey, why: "timeout", now: Date.now() });
    }, CLIENT_TIMEOUT_MS);
    scanAction({ ...ids, sessionId: state.sessionId, wire: a.wire, commandKey: a.commandKey, deviceLabel, retried: a.retries > 0 }).then(
      (r) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (r.kind === "blocked") {
          dispatch({ type: "blocked", why: r.why });
          stopCamera("paused");
          return;
        }
        dispatch({ type: "result", commandKey: a.commandKey, outcome: r.outcome, now: Date.now() });
        if (r.outcome.kind === "admitted") refreshCounters();
      },
      () => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        dispatch({ type: "failed", commandKey: a.commandKey, why: "transport", now: Date.now() });
      },
    );
  }, [state.phase, state.attempt, state.sessionId, ids, deviceLabel, refreshCounters, stopCamera]);

  const begin = (e: React.FormEvent) => {
    e.preventDefault();
    if (!sessionId) return;
    const label = deviceLabel.trim().slice(0, 40);
    storeLabel(label);
    setDeviceLabel(label);
    dispatch({ type: "session", sessionId });
    dispatch({ type: "blocked", why: null });
    setStep("scan");
    refreshCounters();
    void startCamera();
  };

  const change = () => {
    stopCamera("off");
    setStep("setup");
  };

  // ── render ──
  if (step === "setup") {
    return (
      <section className="panel mx-auto max-w-md px-5 py-5 md:px-6" aria-labelledby="scan-setup-title">
        {demo ? <p className="chip mb-3 inline-flex">{DEMO_DATA_LABEL}</p> : null}
        <h2 id="scan-setup-title" className="text-lg font-semibold text-ink">Set up this phone</h2>
        <p className="mt-1 text-sm text-dim">
          {eventTitle}. Signed in as {staff.label ?? "unknown"} ({staff.role}). The server checks the role on every scan.
        </p>
        <form onSubmit={begin} className="mt-4 space-y-4">
          <label className="block text-sm">
            <span className="eyebrow block text-dim">Session</span>
            <select name="session" required value={sessionId} onChange={(e) => setSessionId(e.target.value)} className="field mt-1">
              {sessions.length === 0 ? <option value="">No sessions on this event</option> : null}
              {sessions.map((s) => (
                <option key={s.sessionId} value={s.sessionId}>
                  {s.label ?? "Session"} · {fmtWhen(s.startsAt, timeZone)} · {s.status}
                </option>
              ))}
            </select>
            <span className="mt-1 block text-xs text-dim">{timeZone ? `Times in ${timeZone}.` : "Times in your phone's time zone (the venue's zone arrives with the venue timezone setting)."}</span>
          </label>
          <label className="block text-sm">
            <span className="eyebrow block text-dim">This phone&apos;s label</span>
            <input name="device_label" maxLength={40} value={deviceLabel} onChange={(e) => setDeviceLabel(e.target.value)} placeholder="Door A phone" className="field mt-1" autoComplete="off" />
            <span className="mt-1 block text-xs text-dim">Recorded with each scan so another door can see where a pass was admitted. Not a name.</span>
          </label>
          <button type="submit" disabled={!sessionId} className="btn btn-primary btn-lg w-full min-h-11">
            Start scanning
          </button>
          <p className="text-xs text-dim">Starting asks for the camera. A camera scan checks the pass only; the 21+ ID check stays with you.</p>
        </form>
      </section>
    );
  }

  const o = state.outcome;
  const camErr = state.camera !== "on" && state.camera !== "starting" && state.camera !== "off" && state.camera !== "paused" ? CAMERA_COPY[state.camera] : null;
  const statusWord = state.blocked ? "Blocked" : !state.online ? "Offline" : state.phase === "busy" ? "Checking…" : state.camera === "on" ? "Ready" : state.camera === "starting" ? "Starting camera…" : "Camera off";

  return (
    <div className="mx-auto max-w-md space-y-3">
      <section className="panel px-4 py-3" aria-label="Where you are">
        {demo ? <p className="chip mb-2 inline-flex">{DEMO_DATA_LABEL}</p> : null}
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0 text-sm">
            <p className="truncate font-semibold text-ink">{eventTitle}</p>
            <p className="truncate text-dim">
              {session ? `${session.label ?? "Session"} · ${fmtWhen(session.startsAt, timeZone)}` : "No session"}
              {timeZone ? "" : " (phone’s zone)"}
            </p>
            <p className="truncate text-dim">
              {deviceLabel || "Unlabelled phone"} · {staff.label ?? "unknown"} · {staff.role}
            </p>
          </div>
          <button type="button" onClick={change} className="btn btn-ghost btn-sm min-h-11 shrink-0">
            Change
          </button>
        </div>
      </section>

      <section className="panel overflow-hidden p-0" aria-label="Camera">
        <div className="relative aspect-[3/4] max-h-[55vh] w-full bg-frame">
          <video ref={videoRef} playsInline muted autoPlay aria-hidden="true" className={`h-full w-full object-cover ${state.camera === "on" ? "" : "opacity-40"}`} />
          <canvas ref={canvasRef} hidden aria-hidden="true" />
          <p className="absolute left-3 top-3 rounded-full bg-overlay px-3 py-1 text-xs font-medium text-card" aria-live="polite">
            {statusWord}
          </p>
          {camErr ? (
            <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 bg-overlay p-6 text-center text-card" role="alert">
              <Icon name="alert" size={28} />
              <p className="text-base font-semibold">{camErr.title}</p>
              <p className="text-sm">{camErr.hint}</p>
              <button type="button" onClick={() => void startCamera()} className="btn btn-soft min-h-11">
                Try again
              </button>
            </div>
          ) : null}
          {state.camera === "paused" && !state.blocked ? (
            <div className="absolute inset-0 flex items-center justify-center bg-overlay p-6 text-center text-card">
              <button type="button" onClick={() => void startCamera()} className="btn btn-soft min-h-11">
                Resume camera
              </button>
            </div>
          ) : null}
        </div>
      </section>

      <section role="status" aria-live="assertive" aria-atomic="true" className={`panel px-5 py-5 ${o ? TONE_CLASS[OUTCOME_TONE[o.kind]] : ""}`} aria-label="Result">
        {state.blocked ? (
          <div>
            <p className="text-2xl font-semibold">{BLOCKED_COPY[state.blocked].title}</p>
            <p className="mt-2 text-sm">{BLOCKED_COPY[state.blocked].hint}</p>
            {state.blocked === "signed_out" ? (
              <Link href={loginHref} className="btn btn-primary mt-4 min-h-11">
                Sign in again
              </Link>
            ) : null}
          </div>
        ) : o ? (
          <ResultCard o={o} timeZone={timeZone} onDismiss={() => dispatch({ type: "dismiss", now: Date.now() })} onRetry={() => dispatch({ type: "retry", now: Date.now() })} online={state.online} />
        ) : (
          <p className="text-sm text-dim">{state.phase === "busy" ? "Checking the pass with the server…" : !state.online ? "Offline: a pass cannot be verified until the connection is back." : "Point the camera at the guest's pass."}</p>
        )}
      </section>

      <section className="panel px-5 py-4 text-sm" aria-label="Attendance">
        <p>
          <span className="font-semibold text-ink">{state.admittedHere}</span> admitted from this phone since it started scanning.
        </p>
        <p className="mt-1 text-dim">
          {demo
            ? "Demo — sample data: no server counts."
            : counters.kind === "ok" && counters.data
              ? `This session, every door: ${counters.data.admitted} admitted, ${counters.data.duplicate} already used, ${counters.data.invalid} refused.`
              : counters.kind === "ok"
                ? "This session, every door: no scans recorded yet."
                : counters.kind === "unavailable"
                  ? counters.message
                  : counters.kind === "loading"
                    ? "Reading this session's counts…"
                    : "Counts not read yet."}
        </p>
        {state.history.length > 0 ? (
          <ol className="mt-3 space-y-1 text-xs text-dim" aria-label="Recent results">
            {state.history.map((h, i) => (
              <li key={`${h.at}-${i}`}>
                {OUTCOME_TITLE[h.outcome.kind]} · {fmtWhen(new Date(h.at).toISOString(), timeZone)}
              </li>
            ))}
          </ol>
        ) : null}
      </section>
    </div>
  );
}

function ResultCard({ o, timeZone, onDismiss, onRetry, online }: { o: ScanOutcome; timeZone: string | null; onDismiss: () => void; onRetry: () => void; online: boolean }) {
  const retry = o.kind === "cannot_verify" && o.retrySameKey;
  return (
    <div>
      <p className="text-4xl font-semibold tracking-tight">{OUTCOME_TITLE[o.kind]}</p>
      <p className="mt-2 text-base">{outcomeDetail(o, timeZone)}</p>
      {o.kind === "cannot_verify" && o.detail ? <p className="mt-1 text-xs opacity-80">{o.detail}</p> : null}
      <div className="mt-4 flex flex-wrap gap-2">
        {retry ? (
          <button type="button" onClick={onRetry} disabled={!online} className="btn btn-primary min-h-11">
            Check again (same key)
          </button>
        ) : null}
        <button type="button" onClick={onDismiss} className="btn btn-soft min-h-11">
          Ready for the next pass
        </button>
      </div>
    </div>
  );
}
