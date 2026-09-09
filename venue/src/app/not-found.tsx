import Link from "next/link";
import { PREVIEW } from "@/fixtures/venue";

export default function NotFound() {
  return (
    <main className="mx-auto max-w-lg p-8">
      <p className="eyebrow text-dim">Preview</p>
      <h1 className="mt-2 text-2xl font-bold">Nothing here</h1>
      <p className="mt-2 text-muted">This preview only knows the sample organization and venue.</p>
      <Link className="btn btn-primary mt-6" href={`/o/${PREVIEW.orgId}/v/${PREVIEW.venueId}/events`}>
        Open the sample venue
      </Link>
    </main>
  );
}
