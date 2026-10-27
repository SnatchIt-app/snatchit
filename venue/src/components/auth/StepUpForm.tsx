"use client";

import Image from "next/image";
import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { beginTotpEnroll, totpFactorState, verifyTotpCode } from "@/lib/auth/step-up";
import { stepUpAction } from "@/lib/auth/totp-factors";

type Phase =
  | { kind: "loading" }
  | { kind: "code"; factorId?: string }
  | { kind: "enroll"; qrSvg: string; secret: string; factorId: string; replacedUnfinished?: boolean }
  | { kind: "unavailable"; message: string };

/**
 * Confirming it is you (TOTP), for the one action that needs it: naming the
 * organization's payout destination. Every call goes to a server action — this
 * app has no browser Supabase client and its CSP allows no other origin — and
 * on success the server rewrites the session cookie, so the next request is
 * aal2. The code is never stored, and nothing here authorizes anything on its
 * own: the verb re-reads `aal` from the verified token.
 */
export function StepUpForm({ nextHref }: { nextHref: string }) {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>({ kind: "loading" });
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const started = useRef(false);

  /** Start (or restart) enrolment. Clears abandoned pending factors server-side. */
  const enrol = async (replacingUnfinished: boolean) => {
    const e = await beginTotpEnroll();
    setPhase(
      e.ok
        ? { kind: "enroll", qrSvg: e.qrSvg, secret: e.secret, factorId: e.factorId, replacedUnfinished: replacingUnfinished }
        : { kind: "unavailable", message: e.message },
    );
  };

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    void (async () => {
      const s = await totpFactorState();
      if (s.kind === "unavailable") {
        setPhase({ kind: "unavailable", message: s.message });
        return;
      }
      // Only a verified factor may be asked for a code. An unfinished enrolment
      // has no secret the operator still holds, so it must restart rather than
      // present a code box with no QR.
      if (stepUpAction(s) === "ask_code") {
        setPhase({ kind: "code", factorId: s.kind === "none" ? undefined : s.factorId });
        return;
      }
      await enrol(s.kind === "unverified");
    })();
  }, []);

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (pending) return;
    setError(null);
    start(async () => {
      // The factor the operator is actually looking at. Without this the server
      // had to re-find it, and a factor enrolled seconds ago is invisible to the
      // SDK's `data.totp` — so the answer was "no authenticator yet" and the QR
      // was replaced under the operator's hands, forever.
      const factorId = phase.kind === "enroll" || phase.kind === "code" ? phase.factorId : undefined;
      const r = await verifyTotpCode(code, factorId);
      if (r.ok) {
        router.replace(nextHref);
        router.refresh();
        return;
      }
      setError(r.message);
      // A wrong code leaves the scanned QR alone. Only a server that reports no
      // factor at all may start enrolment again.
      if (r.needsEnroll) await enrol(false);
    });
  };

  if (phase.kind === "loading") return <p className="text-sm text-muted">Checking your authenticator…</p>;
  if (phase.kind === "unavailable")
    return (
      <p role="alert" className="border-l-2 border-danger bg-primary-soft px-3 py-2 text-sm text-danger">
        {phase.message}
      </p>
    );

  return (
    <div className="space-y-4">
      {phase.kind === "enroll" ? (
        <div className="space-y-2">
          {phase.replacedUnfinished ? (
            <p className="text-sm text-muted">
              This account had an unfinished authenticator setup, so it has been cleared. Any earlier &ldquo;Snatch It venue&rdquo; entry in your
              authenticator app is now dead and its codes will not work &mdash; use the code below. Authenticators for other Snatch It apps are untouched.
            </p>
          ) : null}
          <p className="text-sm">Scan this with an authenticator app, then enter the 6-digit code it shows.</p>
          {/* The QR is a data: URI from GoTrue; the venue CSP allows img-src data:. */}
          <Image src={phase.qrSvg} alt="Authenticator QR code" width={180} height={180} unoptimized className="border border-line bg-white p-2" />
          <details>
            <summary className="text-sm text-dim">Can&apos;t scan it?</summary>
            <p className="mt-1 break-all font-mono text-xs">{phase.secret}</p>
          </details>
        </div>
      ) : (
        <p className="text-sm">
          This account already has a confirmed authenticator. Enter the 6-digit code it shows.
        </p>
      )}
      <form onSubmit={submit} noValidate className="space-y-3">
        <label className="block text-sm">
          <span className="eyebrow block text-dim">6-digit code</span>
          <input
            name="code"
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={7}
            required
            value={code}
            onChange={(e) => setCode(e.target.value)}
            className="field mt-1 w-32 tabular-nums"
          />
        </label>
        {error ? (
          <p role="alert" className="border-l-2 border-danger bg-primary-soft px-3 py-2 text-sm text-danger">
            {error}
          </p>
        ) : null}
        <div className="flex flex-wrap items-center gap-3">
          <button type="submit" disabled={pending} className="btn btn-primary min-h-11">
            {pending ? "Confirming…" : "Confirm"}
          </button>
          {phase.kind === "enroll" ? (
            <button
              type="button"
              disabled={pending}
              onClick={() => start(async () => { setError(null); setCode(""); await enrol(false); })}
              className="btn min-h-11"
            >
              Show a new code
            </button>
          ) : null}
        </div>
      </form>
    </div>
  );
}
