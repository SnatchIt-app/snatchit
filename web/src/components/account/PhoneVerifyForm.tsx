"use client";

import { useEffect, useState, useTransition } from "react";
import { useRouter, usePathname } from "next/navigation";
import { sendPhoneOtpAction, verifyPhoneOtpAction } from "@/lib/phone-actions";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";

const RESEND_COOLDOWN_S = 30; // matches mobile's VerifyPhoneScreen
const PHONE_DISPLAY_MAXLENGTH = 14; // "(305) 555-1234".length — matches mobile's utils/phone.ts

type Step = "enter_phone" | "enter_code" | "verified";

/**
 * Digit-accumulating input formatter, ported from mobile's
 * src/utils/phone.ts (toPhoneDigits/formatPhoneDisplay/isValidUSPhone).
 * Kept local since web has no shared utils module for this.
 *
 * Note: mobile's onChangeText actually wires up normalizeUSPhone (which
 * only returns non-null once a FULL valid number is typed, clearing the
 * field on every partial keystroke) even though its own doc comment
 * prescribes toPhoneDigits for this exact spot. That's a mobile call-site
 * bug, not a page of the "exact mechanics" worth reproducing — a text
 * <input> here needs to accept partial input while typing, so this uses
 * the digit-accumulating helper mobile's utils module documents as the
 * intended one for onChangeText.
 */
function toPhoneDigits(input: string): string {
  const digits = input.replace(/\D+/g, "");
  const trimmed = digits.length === 11 && digits.startsWith("1") ? digits.slice(1) : digits;
  return trimmed.slice(0, 10);
}

function formatPhoneDisplay(digits: string): string {
  if (digits.length === 0) return "";
  if (digits.length < 4) return `(${digits}`;
  if (digits.length < 7) return `(${digits.slice(0, 3)}) ${digits.slice(3)}`;
  return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
}

// NANP: matches mobile's isValidUSPhone() exactly.
function isValidUSPhone(digits: string): boolean {
  return /^[2-9]\d{2}[2-9]\d{6}$/.test(digits);
}

/**
 * Two-step phone verification form (phone → code → verified), mirroring
 * mobile's VerifyPhoneScreen mechanics: supabase.auth.updateUser({ phone })
 * to send an OTP, supabase.auth.verifyOtp({ phone, token, type:
 * 'phone_change' }) to confirm it. Both calls go through the server actions
 * in @/lib/phone-actions so the Supabase Auth calls stay server-side.
 */
export function PhoneVerifyForm() {
  const router = useRouter();
  const pathname = usePathname();

  const [step, setStep] = useState<Step>("enter_phone");
  const [phone, setPhone] = useState(""); // 10 digits, no +1 — mirrors mobile's state shape
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [cooldown, setCooldown] = useState(0);
  const [isPending, startTransition] = useTransition();

  // Self-scheduling countdown: re-runs as `cooldown` decreases and clears
  // its own timeout on cleanup/unmount. Equivalent to mobile's
  // setInterval+ref pair, without needing a ref — the effect only ever
  // schedules an async callback, it never calls setState synchronously
  // during its own execution.
  useEffect(() => {
    if (cooldown <= 0) return;
    const timer = setTimeout(() => setCooldown((c) => Math.max(0, c - 1)), 1000);
    return () => clearTimeout(timer);
  }, [cooldown]);

  function sendCode() {
    if (!isValidUSPhone(phone)) {
      setError("Enter a valid US mobile number.");
      return;
    }
    setError(null);
    startTransition(async () => {
      const result = await sendPhoneOtpAction(phone);
      if (result.error === "AUTH_REQUIRED") {
        router.push(`/login?next=${encodeURIComponent(pathname)}`);
        return;
      }
      if (result.error) {
        setError(result.error);
        return;
      }
      setCooldown(RESEND_COOLDOWN_S);
      setStep("enter_code");
    });
  }

  function verifyCode() {
    if (code.trim().length !== 6) {
      setError("Enter the 6-digit code from the text message.");
      return;
    }
    setError(null);
    startTransition(async () => {
      const result = await verifyPhoneOtpAction(phone, code);
      if (result.error === "AUTH_REQUIRED") {
        router.push(`/login?next=${encodeURIComponent(pathname)}`);
        return;
      }
      if (result.error) {
        setError(result.error);
        return;
      }
      setStep("verified");
    });
  }

  if (step === "verified") {
    return (
      <div className="max-w-[380px] space-y-4">
        <Alert tone="success">
          {formatPhoneDisplay(phone)} is verified on your account. You&apos;re all set to sell tickets.
        </Alert>
        <Button variant="primary" className="w-full" onClick={() => router.push("/account/settings")}>
          Done
        </Button>
      </div>
    );
  }

  if (step === "enter_code") {
    return (
      <form
        onSubmit={(e) => {
          e.preventDefault();
          verifyCode();
        }}
        className="max-w-[380px] space-y-4"
      >
        <p className="text-[13.5px] leading-relaxed text-white/60">
          We sent a 6-digit code to {formatPhoneDisplay(phone)}.
        </p>
        {error ? <Alert tone="error">{error}</Alert> : null}
        <Field label="Verification code" htmlFor="code">
          <Input
            id="code"
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
            placeholder="••••••"
            inputMode="numeric"
            autoComplete="one-time-code"
            maxLength={6}
            autoFocus
            className="text-center text-[22px] tracking-[0.5em]"
          />
        </Field>
        <Button type="submit" variant="primary" className="w-full" disabled={isPending || code.trim().length !== 6}>
          {isPending ? "Verifying…" : "Verify"}
        </Button>
        <div className="flex items-center justify-between gap-4 text-[13px]">
          <button
            type="button"
            onClick={sendCode}
            disabled={isPending || cooldown > 0}
            className="min-h-11 font-semibold text-primary hover:text-[#ff5f5f] disabled:cursor-not-allowed disabled:text-white/35 disabled:hover:text-white/35"
          >
            {cooldown > 0 ? `Resend code in ${cooldown}s` : "Resend code"}
          </button>
          <button
            type="button"
            onClick={() => {
              setStep("enter_phone");
              setCode("");
              setError(null);
            }}
            className="min-h-11 font-semibold text-white/50 hover:text-white/80"
          >
            Use a different number
          </button>
        </div>
      </form>
    );
  }

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        sendCode();
      }}
      className="max-w-[380px] space-y-4"
    >
      <p className="text-[13.5px] leading-relaxed text-white/60">
        We&apos;ll text you a 6-digit code. Verifying your number keeps the marketplace safe — it&apos;s never shown
        on your profile or used for marketing.
      </p>
      {error ? <Alert tone="error">{error}</Alert> : null}
      <Field label="Phone number" htmlFor="phone">
        <Input
          id="phone"
          type="tel"
          value={formatPhoneDisplay(phone)}
          onChange={(e) => setPhone(toPhoneDigits(e.target.value))}
          placeholder="(305) 555-1234"
          inputMode="tel"
          autoComplete="tel-national"
          maxLength={PHONE_DISPLAY_MAXLENGTH}
          autoFocus
        />
      </Field>
      <Button type="submit" variant="primary" className="w-full" disabled={isPending || !isValidUSPhone(phone)}>
        {isPending ? "Sending…" : "Send code"}
      </Button>
    </form>
  );
}
