import type { Metadata } from "next";
import { safeInternalPath } from "@/lib/auth/redirect";
import { MfaFlow } from "@/components/auth/MfaFlow";
import { signOutAction } from "@/lib/auth/actions";

export const metadata: Metadata = { title: "Two-factor" };

type SearchParams = Record<string, string | string[] | undefined>;
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

export default async function MfaPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  const next = safeInternalPath(first(sp.next) ?? null, "/");
  return (
    <>
      <h1 className="title-page md:text-[2.25rem]">Two-factor authentication</h1>
      <p className="mt-2 text-[0.9375rem] leading-relaxed text-muted">Every console session must be verified with an authenticator app (TOTP).</p>
      <div className="mt-6">
        <MfaFlow next={next} />
      </div>
      <form action={signOutAction} className="mt-6 border-t border-line pt-4 text-right">
        <button type="submit" className="link text-[0.8125rem]">
          Sign out
        </button>
      </form>
    </>
  );
}
