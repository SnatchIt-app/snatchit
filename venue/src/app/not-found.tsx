import Link from "next/link";
import { PREVIEW } from "@/fixtures/venue";
import { DATA_SOURCE } from "@/lib/env";

export default function NotFound() {
  const sample = DATA_SOURCE !== "database";
  return (
    <main id="main" className="flex min-h-dvh items-center justify-center px-4 py-10">
      <div className="panel enter w-full max-w-xl px-6 py-12 text-center md:px-10">
        <p className="eyebrow-caps">{sample ? "Preview" : "Not found"}</p>
        <h1 className="title-section mt-3">Nothing here</h1>
        <p className="mt-2 text-[0.9375rem] leading-relaxed text-muted">
          {sample ? "This preview only knows the sample organization and venue." : "This link doesn't match a page of the venue dashboard. Use the link your venue gave you."}
        </p>
        {sample ? (
          <Link className="btn btn-primary mt-6" href={`/o/${PREVIEW.orgId}/v/${PREVIEW.venueId}/events`}>
            Open the sample venue
          </Link>
        ) : null}
      </div>
    </main>
  );
}
