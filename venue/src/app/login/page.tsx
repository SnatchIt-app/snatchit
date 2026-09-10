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
  return (
    <main className="mx-auto max-w-sm p-8">
      <p className="preview-banner mb-6 px-3 py-1.5">◆ {info.label}</p>
      <p className="eyebrow text-dim">Venue dashboard</p>
      <h1 className="mt-1 text-xl font-bold">Sign in</h1>
      {DATA_SOURCE === "database" ? (
        <>
          <p className="mt-1 text-sm text-muted">Venue staff and organization members. You will see exactly what your grants allow; the preview role switch does not change that.</p>
          <div className="mt-5">
            <LoginForm next={next} />
          </div>
        </>
      ) : (
        <p className="mt-2 text-sm text-muted">Fixture mode needs no sign-in. Set NEXT_PUBLIC_VENUE_DATA_SOURCE=database to read from a rehearsal database.</p>
      )}
    </main>
  );
}
