import { redirect } from "next/navigation";
import { PREVIEW } from "@/fixtures/venue";
import { DATA_SOURCE } from "@/lib/env";

/**
 * The demo has exactly one organization and one venue. Land on the Tonight
 * overview, not the events table: a manager arriving mid-shift needs to know
 * what is wrong before they need a list (audit §W1).
 *
 * In database mode there is no sample venue to land on — the sample ids are not
 * real ones — so the start page says where the dashboard lives instead.
 */
export default function Home() {
  if (DATA_SOURCE !== "database") redirect(`/o/${PREVIEW.orgId}/v/${PREVIEW.venueId}`);
  return (
    <main id="main" className="flex min-h-dvh items-center justify-center px-4 py-10">
      <div className="panel enter w-full max-w-xl px-6 py-12 text-center md:px-10">
        <h1 className="title-section">Open your venue&apos;s link</h1>
        <p className="mt-2 text-[0.9375rem] leading-relaxed text-muted">The dashboard opens at your venue&apos;s own address. Use the link your venue manager or organization owner gave you.</p>
      </div>
    </main>
  );
}
