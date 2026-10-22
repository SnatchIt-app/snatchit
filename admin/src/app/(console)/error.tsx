"use client";

import Link from "next/link";
import { Icon } from "@/components/ui/Icon";

/**
 * An unexpected error while rendering a console page. The console frame stays
 * (it is the layout above this boundary); the page says what happened, offers
 * a retry of the same page, and gives the reference that matches the server log.
 * Failed database reads never reach here — pages render those themselves.
 */
export default function ConsoleError({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  return (
    <div className="panel enter mx-auto mt-6 flex max-w-xl flex-col items-center px-6 py-12 text-center md:px-10" role="alert">
      <span className="grid h-12 w-12 place-items-center rounded-full bg-[rgba(196,29,21,0.08)] text-danger">
        <Icon name="alert" size={22} />
      </span>
      <h1 className="title-section mt-4">This page couldn&apos;t be shown</h1>
      <p className="mt-2 max-w-md text-[0.9375rem] leading-relaxed text-muted">Something unexpected went wrong while loading it. Try again; if it keeps happening, send the reference below to whoever looks after the console.</p>
      <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
        <button type="button" onClick={() => retry()} className="btn btn-primary">
          Try again
        </button>
        <Link href="/" className="btn btn-ghost">
          Go to Today
        </Link>
      </div>
      {error.digest ? <p className="mt-5 font-mono text-[0.75rem] text-muted">Reference {error.digest}</p> : null}
    </div>
  );
}
