"use client";

import { Suspense, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Link from "next/link";
import { AuthCard } from "@/components/auth/AuthCard";
import { Alert } from "@/components/ui/Alert";
import { Spinner } from "@/components/ui/Button";
import { authInlineLinkCls } from "@/components/auth/styles";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { readConfirmLink } from "@/lib/auth/confirm-link";
import { completeConfirm } from "@/lib/auth/complete-confirm";

type Status = "processing" | "first_confirmation" | "error";

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
        // null state, not history.state: Next's patched replaceState then also updates the router
        // URL; passing its own state would skip that and the router could write the fragment back.
        window.history.replaceState(null, "", window.location.pathname + window.location.search);
      }
      const supabase = getSupabaseBrowserClient();
      const outcome = await completeConfirm(link, supabase.auth, searchParams.get("next"));

      if (cancelled) return;
      if (outcome.status === "signed_in") router.replace(outcome.route);
      else setStatus(outcome.status === "first_confirmation" ? "first_confirmation" : "error");
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

  if (status === "first_confirmation") {
    return (
      <AuthCard eyebrow="Account" title="One more step">
        <Alert tone="success">First confirmation accepted. Open the link we sent to your other email address to finish.</Alert>
      </AuthCard>
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
