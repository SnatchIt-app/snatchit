import { Skeleton } from "@/components/ui/State";

/**
 * Route loading state for every venue screen. Next.js wraps page.tsx (and everything below this
 * segment) in a Suspense boundary with this as the fallback, so it shows at once on navigation
 * while the page streams in.
 *
 * Database mode reads the session, the caller's grants and the venue before a page can render,
 * and before this existed a slow read left the previous screen frozen with no feedback. It runs
 * before the page knows who is looking, so it shows no role, no venue name and no data source:
 * only that the screen is on its way. Each page's own `?state=loading` preview stays as it was.
 */
export default function VenueLoading() {
  return (
    // data-route-loading: the acceptance kit waits for this to disappear before it reads a page.
    <main id="main" data-route-loading="" className="flex min-h-dvh items-center justify-center px-4 py-10">
      <div className="panel enter w-full max-w-xl px-6 py-10 md:px-10">
        <p className="eyebrow-caps">Venue dashboard</p>
        <p className="title-section mt-3 text-[1.25rem]">Loading this screen</p>
        <Skeleton rows={5} className="mt-6" />
      </div>
    </main>
  );
}
