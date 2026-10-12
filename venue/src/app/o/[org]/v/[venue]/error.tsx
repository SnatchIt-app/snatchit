"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { Icon } from "@/components/ui/Icon";

/**
 * An unexpected error while rendering a venue screen. Each screen draws its own
 * frame, so this stands alone: what happened, a retry of the same screen, a way
 * back to the venue's Today, and the reference that matches the server log.
 */
export default function VenueError({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  const params = useParams<{ org: string; venue: string }>();
  const home = params?.org && params?.venue ? `/o/${params.org}/v/${params.venue}` : "/";
  return (
    <main id="main" className="flex min-h-dvh items-center justify-center px-4 py-10">
      <div className="panel enter flex w-full max-w-xl flex-col items-center px-6 py-12 text-center md:px-10" role="alert">
        <span className="grid h-12 w-12 place-items-center rounded-full bg-[rgba(196,29,21,0.08)] text-danger">
          <Icon name="alert" size={22} />
        </span>
        <h1 className="title-section mt-4">This screen couldn&apos;t be shown</h1>
        <p className="mt-2 max-w-md text-[0.9375rem] leading-relaxed text-muted">Something unexpected went wrong while loading it. Try again; if it keeps happening, send the reference below to Snatch It support.</p>
        <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
          <button type="button" onClick={() => retry()} className="btn btn-primary">
            Try again
          </button>
          <Link href={home} className="btn btn-ghost">
            Back to Today
          </Link>
        </div>
        {error.digest ? <p className="mt-5 font-mono text-[0.75rem] text-muted">Reference {error.digest}</p> : null}
      </div>
    </main>
  );
}
