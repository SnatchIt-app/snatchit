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
      <h1 className="title-page md:text-[2.25rem]">Sign in</h1>
      <p className="mt-2 text-[0.9375rem] leading-relaxed text-muted">Operators only. An authenticator code is required after your password.</p>
      <div className="mt-6">
        <LoginForm next={next} />
      </div>
    </>
  );
}
