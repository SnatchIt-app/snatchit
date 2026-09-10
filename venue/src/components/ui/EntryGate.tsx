import type { Entry } from "@/lib/page";
import { DataSourceError } from "@/components/ui/DataSourceError";
import { DeniedState } from "@/components/ui/State";

/**
 * Renders the database-mode entry outcome, or nothing when the caller may
 * proceed (fixture mode, or a signed-in caller with a grant at this scope).
 */
export function EntryGate({ entry, loginHref, retryHref }: { entry: Entry; loginHref: string; retryHref: string }) {
  if (entry.kind === "failure") return <DataSourceError failure={entry.failure} loginHref={loginHref} retryHref={retryHref} />;
  if (entry.kind === "denied") {
    return (
      <div className="mx-auto max-w-md space-y-3 text-center">
        <DeniedState />
        <p className="text-xs text-dim">You are signed in, but this account holds no staff or organization role at this venue. Public event listings stay available in the Snatch It app.</p>
        <form method="post" action="/logout">
          <button className="btn btn-ghost btn-sm" type="submit">
            Sign out
          </button>
        </form>
      </div>
    );
  }
  return null;
}
