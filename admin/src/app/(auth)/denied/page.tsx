import type { Metadata } from "next";
import Link from "next/link";
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
      {reason ? (
        <>
          {/* The check itself failed (database or network) — that is not a decision about the account. Still fails closed. */}
          <h1 className="title-page md:text-[2.25rem]">We couldn&apos;t confirm your operator access</h1>
          <p className="mt-2 text-[0.875rem] leading-relaxed text-muted">
            {user?.email ? <span className="text-ink">{user.email}</span> : "This account"} is signed in, but the access check did not complete, so the console stays
            closed. This is not a decision about your account. Try again in a moment; if it keeps failing, the console&apos;s database may be unreachable.
          </p>
          <div className="mt-4">
            <Alert state="failed" title="Could not verify operator status." compact>
              {reason}
            </Alert>
          </div>
          <Link href="/" className="btn btn-primary mt-6 w-full">
            Try again
          </Link>
        </>
      ) : (
        <>
          <h1 className="title-page md:text-[2.25rem]">Your account is not an operator</h1>
          <p className="mt-2 text-[0.8125rem] text-muted">
            {user?.email ? <span className="text-ink">{user.email}</span> : "This account"} is signed in, but Postgres
            (<code className="font-mono">ops.whoami()</code>) did not return a platform role. Operator roles are granted in the
            database, not here.
          </p>
        </>
      )}
      <form action={signOutAction} className={reason ? "mt-2" : "mt-6"}>
        <button type="submit" className="btn btn-ghost w-full">
          Sign out
        </button>
      </form>
    </>
  );
}
