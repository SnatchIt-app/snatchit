"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { AuthCard } from "@/components/auth/AuthCard";
import { Alert } from "@/components/ui/Alert";
import { Spinner } from "@/components/ui/Button";
import { authInlineLinkCls } from "@/components/auth/styles";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { safeInternalPath } from "@/lib/auth/redirect";
import { readConfirmLink } from "@/lib/auth/confirm-link";

type Status = "processing" | "error";

function ConfirmingCard() {
  return (
    <AuthCard eyebrow="Account" title="Confirming…">
      <p role="status" className="t-body flex items-center gap-3 text-muted">
        <Spinner className="text-ink-2" />
        One moment while we verify your link.
      </p>
    </AuthCard>
  );
}

/**
 * Lands here from signup-confirmation and password-reset emails. A link from
 * an implicit-flow request carries the session as a URL hash fragment
 * (#access_token=...&refresh_token=...&type=...) — fragments never reach the
 * server, so this has to be a client page that establishes the session
 * itself, exactly like the mobile app's deep-link handler does. The web sends
 * its auth emails on the implicit flow (lib/auth/email-links.ts) so a link works
 * on any device; PKCE ?code= and token_hash links are accepted too. See
 * lib/auth/confirm-link.
 */
function ConfirmClient() {
  const [status, setStatus] = useState<Status>("processing");
  const router = useRouter();
  const searchParams = useSearchParams();

  useEffect(() => {
    let cancelled = false;

    async function run() {
      // Read the link BEFORE creating the client: after a successful PKCE exchange the client
      // deletes ?code= from the address bar (history.replaceState).
      const link = readConfirmLink(new URLSearchParams(window.location.search), window.location.hash);
      // An implicit link carries the session in the fragment: drop it from the address bar and
      // history before anything else, so the tokens are not left behind or copied. (A PKCE ?code=
      // must stay until the client has read it.)
      if (link.kind === "implicit") {
        window.history.replaceState(window.history.state, "", window.location.pathname + window.location.search);
      }
      const supabase = getSupabaseBrowserClient();

      let ok = false;
      let type: string | null = null;

      if (link.kind === "implicit") {
        const { error } = await supabase.auth.setSession({
          access_token: link.accessToken,
          refresh_token: link.refreshToken,
        });
        ok = !error;
        type = link.type;
      } else if (link.kind === "token_hash") {
        const { error } = await supabase.auth.verifyOtp({
          type: link.type as "signup" | "recovery" | "email" | "email_change" | "invite" | "magiclink",
          token_hash: link.tokenHash,
        });
        ok = !error;
        type = link.type;
      } else if (link.kind === "pkce") {
        // The browser client exchanges the code itself while it initialises (detectSessionInUrl),
        // with the verifier the reset or sign-up request left in this browser. initialize()
        // resolves with that exchange's error, if any. Before this branch the page ignored ?code=
        // and said "Link expired" right after the exchange had signed the person in.
        const { error } = await supabase.auth.initialize();
        const { data } = await supabase.auth.getSession();
        ok = !error && !!data.session;
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
      <ConfirmingCard />
    );
  }

  return (
    <AuthCard eyebrow="Account" title="Link expired">
      <div className="space-y-6">
        <Alert tone="error">This link is invalid or has already been used.</Alert>
        <p className="t-body text-muted">
          <Link href="/login" className={authInlineLinkCls}>
            Back to log in
          </Link>{" "}
          or{" "}
          <Link href="/forgot-password" className={authInlineLinkCls}>
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
        <ConfirmingCard />
      }
    >
      <ConfirmClient />
    </Suspense>
  );
}
