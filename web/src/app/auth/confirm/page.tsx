"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { AuthCard } from "@/components/auth/AuthCard";
import { Alert } from "@/components/ui/Alert";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { safeInternalPath } from "@/lib/auth/redirect";

type Status = "processing" | "error";

/**
 * Lands here from signup-confirmation and password-reset emails. Supabase's
 * default templates deliver the session as a URL hash fragment
 * (#access_token=...&refresh_token=...&type=...) — fragments never reach the
 * server, so this has to be a client page that establishes the session
 * itself, exactly like the mobile app's deep-link handler does. This
 * deliberately avoids the token_hash/type query-param flow, which would
 * require editing the shared email templates mobile also depends on.
 */
function ConfirmClient() {
  const [status, setStatus] = useState<Status>("processing");
  const router = useRouter();
  const searchParams = useSearchParams();

  useEffect(() => {
    let cancelled = false;

    async function run() {
      const supabase = getSupabaseBrowserClient();
      const hashParams = new URLSearchParams(window.location.hash.replace(/^#/, ""));
      const accessToken = hashParams.get("access_token");
      const refreshToken = hashParams.get("refresh_token");
      const hashType = hashParams.get("type");

      const queryTokenHash = searchParams.get("token_hash");
      const queryType = searchParams.get("type");

      let ok = false;
      let type: string | null = null;

      if (accessToken && refreshToken) {
        const { error } = await supabase.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken,
        });
        ok = !error;
        type = hashType;
      } else if (queryTokenHash && queryType) {
        const { error } = await supabase.auth.verifyOtp({
          type: queryType as "signup" | "recovery" | "email" | "email_change" | "invite" | "magiclink",
          token_hash: queryTokenHash,
        });
        ok = !error;
        type = queryType;
      }

      if (cancelled) return;

      if (!ok) {
        setStatus("error");
        return;
      }

      if (type === "recovery") {
        router.replace("/reset-password");
        return;
      }
      if (type === "email_change") {
        router.replace("/account/settings?email_changed=1");
        return;
      }

      const next = safeInternalPath(searchParams.get("next"), "/account");
      router.replace(next);
    }

    run();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (status === "processing") {
    return (
      <AuthCard eyebrow="Account" title="Confirming…">
        <p className="text-[14px] text-white/60">One moment while we verify your link.</p>
      </AuthCard>
    );
  }

  return (
    <AuthCard eyebrow="Account" title="Link expired">
      <div className="space-y-5">
        <Alert tone="error">This link is invalid or has already been used.</Alert>
        <p className="text-[13px] text-white/50">
          <Link href="/login" className="font-semibold text-primary hover:text-[#ff5f5f]">
            Back to log in
          </Link>{" "}
          or{" "}
          <Link href="/forgot-password" className="font-semibold text-primary hover:text-[#ff5f5f]">
            request a new reset link
          </Link>
          .
        </p>
      </div>
    </AuthCard>
  );
}

export default function AuthConfirmPage() {
  return (
    <Suspense
      fallback={
        <AuthCard eyebrow="Account" title="Confirming…">
          <p className="text-[14px] text-white/60">One moment while we verify your link.</p>
        </AuthCard>
      }
    >
      <ConfirmClient />
    </Suspense>
  );
}
