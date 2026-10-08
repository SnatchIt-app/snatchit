import type { Metadata } from "next";
import { getAuthedUser } from "@/lib/auth/session";
import { signOutAction } from "@/lib/auth/actions";
import { Alert } from "@/components/ui/Alert";

export const metadata: Metadata = { title: "Not an operator" };

type SearchParams = Record<string, string | string[] | undefined>;
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

export default async function DeniedPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  const reason = first(sp.reason);
  const user = await getAuthedUser();
  return (
    <>
      <h1 className="text-xl font-bold text-ink">Your account is not an operator</h1>
      <p className="mt-2 text-[13px] text-muted">
        {user?.email ? <span className="text-ink">{user.email}</span> : "This account"} is signed in, but Postgres
        (<code className="font-mono">ops.whoami()</code>) did not return a platform role. Operator roles are granted in the
        database, not here.
      </p>
      {reason ? (
        <div className="mt-4">
          <Alert state="failed" title="Could not verify operator status." compact>
            {reason}
          </Alert>
        </div>
      ) : null}
      <form action={signOutAction} className="mt-6">
        <button type="submit" className="btn btn-ghost w-full">
          Sign out
        </button>
      </form>
    </>
  );
}
