"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { Alert } from "@/components/ui/Alert";

type Phase =
  | { kind: "loading" }
  | { kind: "enroll"; factorId: string; qr: string; secret: string; uri: string }
  | { kind: "verify"; factorId: string }
  | { kind: "error"; message: string };

/**
 * TOTP enrol/verify. Runs in the browser because the challenge binds to the
 * browser session cookie; after verify() the session is aal2 and the proxy
 * lets the operator through to `next`.
 */
export function MfaFlow({ next }: { next: string }) {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>({ kind: "loading" });
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Guard against React StrictMode's double effect run in development: a
  // second enrol() would create a duplicate factor (GoTrue rejects duplicate
  // friendly names and would otherwise leave an orphan).
  const started = useRef(false);
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    (async () => {
      try {
        const supabase = getSupabaseBrowserClient();
        const { data: factors, error: listErr } = await supabase.auth.mfa.listFactors();
        if (listErr) throw listErr;
        const totp: { id: string; status?: string }[] = factors?.totp ?? [];
        const verified = totp.find((f) => f.status === "verified");
        if (verified) {
          setPhase({ kind: "verify", factorId: verified.id });
          return;
        }
        // Unverified factors from an abandoned enrolment cannot be completed
        // (their secret was only shown once), so remove them before enrolling.
        for (const f of totp.filter((x) => x.status !== "verified")) {
          await supabase.auth.mfa.unenroll({ factorId: f.id });
        }
        const suffix = Math.random().toString(36).slice(2, 6);
        const { data, error: enrollErr } = await supabase.auth.mfa.enroll({
          factorType: "totp",
          friendlyName: `Snatch It console ${new Date().toISOString().slice(0, 19)} ${suffix}`,
        });
        if (enrollErr) throw enrollErr;
        {
          setPhase({
            kind: "enroll",
            factorId: data.id,
            qr: data.totp.qr_code,
            secret: data.totp.secret,
            uri: data.totp.uri,
          });
        }
      } catch (e) {
        setPhase({ kind: "error", message: e instanceof Error ? e.message : "Could not start MFA." });
      }
    })();
  }, []);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (phase.kind !== "enroll" && phase.kind !== "verify") return;
    const digits = code.replace(/\s+/g, "");
    if (!/^\d{6}$/.test(digits)) {
      setError("Enter the 6-digit code from your authenticator.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const supabase = getSupabaseBrowserClient();
      const { data: challenge, error: chErr } = await supabase.auth.mfa.challenge({ factorId: phase.factorId });
      if (chErr) throw chErr;
      const { error: vErr } = await supabase.auth.mfa.verify({
        factorId: phase.factorId,
        challengeId: challenge.id,
        code: digits,
      });
      if (vErr) throw vErr;
      router.replace(next);
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Verification failed.");
      setCode("");
    } finally {
      setBusy(false);
    }
  }

  if (phase.kind === "loading") return <Alert state="loading" title="Preparing your authenticator…" compact />;
  if (phase.kind === "error") {
    return (
      <Alert state="failed" title="MFA could not be started." compact>
        {phase.message}{" "}
        <button type="button" className="link" onClick={() => window.location.reload()}>
          Retry
        </button>
      </Alert>
    );
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      {phase.kind === "enroll" ? (
        <div className="space-y-3">
          <Alert state="info" title="First sign-in: enrol an authenticator." compact>
            Scan the QR code with your authenticator app, or enter the secret manually, then type the code it shows.
          </Alert>
          <div className="flex flex-col items-center gap-3 border border-line-neutral bg-white p-3">
            {/* qr_code is an SVG data URL from Supabase; a plain img is the correct element. */}
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={phase.qr} alt="TOTP enrolment QR code" width={180} height={180} />
          </div>
          <details className="text-[12px] text-muted">
            <summary className="cursor-pointer">Can&apos;t scan? Show the secret</summary>
            <code className="mt-2 block break-all bg-field p-2 font-mono text-[12px] text-ink">{phase.secret}</code>
            <p className="mt-1 break-all font-mono text-[11px] text-dim">{phase.uri}</p>
          </details>
        </div>
      ) : null}

      <div>
        <label htmlFor="totp" className="eyebrow block text-dim">
          6-digit code
        </label>
        <input
          id="totp"
          name="code"
          inputMode="numeric"
          pattern="[0-9]*"
          autoComplete="one-time-code"
          maxLength={6}
          required
          autoFocus
          value={code}
          onChange={(e) => setCode(e.target.value)}
          className="field mt-1 font-mono text-lg tracking-[0.4em]"
        />
      </div>
      {error ? <Alert state="failed" title={error} compact /> : null}
      <button type="submit" disabled={busy} className="btn btn-primary w-full">
        {busy ? "Verifying…" : phase.kind === "enroll" ? "Enrol and verify" : "Verify"}
      </button>
    </form>
  );
}
