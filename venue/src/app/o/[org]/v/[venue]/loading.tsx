import { Skeleton } from "@/components/ui/State";

/**
 * Route loading state for every venue screen. Next.js wraps page.tsx (and everything below this
 * segment) in a Suspense boundary with this as the fallback, so it shows at once on navigation
 * while the page streams in.
 *
 * Database mode reads the session, the caller's grants and the venue before a page can render,
 * and before this existed a slow read left the previous screen frozen with no feedback. It runs
 * before the page knows who is looking, so it shows no role, no venue name, no navigation and no
 * data source. It keeps the workspace's shape (the Shell's floating sidebar, top line and content
 * column) so a navigation does not blank the frame; each page's own `?state=loading` preview stays
 * as it was.
 *
 * data-route-loading: the acceptance kit waits for this to disappear before it reads a page.
 */
export default function VenueLoading() {
  return (
    <div className="min-h-dvh" data-route-loading="">
      <aside aria-hidden="true" className="glass fixed bottom-4 left-4 top-4 z-40 hidden w-[15.5rem] flex-col rounded-[26px] px-3.5 pb-3.5 pt-6 lg:flex">
        <div className="px-2.5">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/sn-logo.svg" alt="" width={56} height={20} className="h-auto w-14" />
          <p className="serif mt-2 text-[1.75rem] leading-none tracking-[-0.02em]">Snatch It</p>
        </div>
        <div className="mt-6 space-y-3 border-t border-line px-2.5 pt-5">
          {[0, 1, 2, 3].map((i) => (
            <div key={i} className="skel h-4" style={{ width: `${80 - i * 12}%` }} />
          ))}
        </div>
      </aside>

      <div className="flex min-h-dvh min-w-0 flex-col lg:pl-[17.5rem]">
        <div aria-hidden="true" className="glass-bar lg:!border-0 lg:!bg-transparent lg:![backdrop-filter:none]">
          <div className="mx-auto flex min-h-16 w-full max-w-[1340px] items-center gap-2 px-4 md:px-8 lg:min-h-[4.5rem]">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/sn-logo.svg" alt="" width={40} height={14} className="h-auto w-10 lg:hidden" />
          </div>
        </div>
        <main id="main" className="mx-auto w-full min-w-0 max-w-[1340px] flex-1 px-4 pb-32 pt-5 md:px-8 lg:pb-14 lg:pt-1">
          <div aria-hidden="true" className="pb-8">
            <div className="skel h-3 w-40" />
            <div className="skel mt-4 h-10 w-[min(22rem,80%)]" />
          </div>
          <section aria-label="Loading" className="panel px-5 pb-5 pt-5 md:px-6">
            <Skeleton rows={6} />
          </section>
        </main>
      </div>
    </div>
  );
}
