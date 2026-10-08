import type { Metadata } from "next";
import { safeInternalPath } from "@/lib/auth/redirect";
import { LoginForm } from "@/components/auth/LoginForm";

export const metadata: Metadata = { title: "Sign in" };

type SearchParams = Record<string, string | string[] | undefined>;
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

export default async function LoginPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  const next = safeInternalPath(first(sp.next) ?? null, "/");
  return (
    <>
      <h1 className="text-xl font-bold text-ink">Sign in</h1>
      <p className="mt-1 text-[13px] text-muted">Operators only. An authenticator code is required after your password.</p>
      <div className="mt-5">
        <LoginForm next={next} />
      </div>
    </>
  );
}
