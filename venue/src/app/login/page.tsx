import type { Metadata } from "next";
import { safeInternalPath } from "@/lib/auth/redirect";
import { DATA_SOURCE } from "@/lib/env";
import { sourceInfo } from "@/lib/source";
import { LoginForm } from "@/components/auth/LoginForm";

export const metadata: Metadata = { title: "Sign in" };

type SearchParams = Record<string, string | string[] | undefined>;
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

export default async function LoginPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  const next = safeInternalPath(first(sp.next) ?? null, "/");
  const info = sourceInfo();
  const dbMode = DATA_SOURCE === "database";
  return (
    <main className="flex min-h-dvh items-center justify-center px-4 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-7">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/sn-logo.svg" alt="" width={56} height={20} className="h-auto w-14" />
          <p className="serif mt-2 text-[1.75rem] leading-none tracking-[-0.02em]">Snatch It</p>
          <p className="mt-1.5 text-[0.8125rem] text-muted">Venue dashboard</p>
        </div>
        <div className="panel p-6 md:p-7">
          <h1 className="title-display text-[2.25rem]">Sign in</h1>
          <p className="mt-3 flex items-start gap-2 text-[0.8125rem] text-muted" role="status">
            <span aria-hidden="true" className={`mt-1.5 inline-block h-2 w-2 shrink-0 rounded-full ${dbMode ? "bg-sky-600" : "bg-[#2f7a3a]"}`} />
            {info.label}
          </p>
          {dbMode ? (
            <>
              <p className="mt-2 text-[0.875rem] text-muted">Venue staff and organization members. You will see exactly what your grants allow.</p>
              <div className="mt-5">
                <LoginForm next={next} />
              </div>
            </>
          ) : (
            <p className="mt-3 text-[0.875rem] leading-relaxed text-muted">Fixture mode needs no sign-in. Set NEXT_PUBLIC_VENUE_DATA_SOURCE=database to read from a rehearsal database.</p>
          )}
        </div>
      </div>
    </main>
  );
}
