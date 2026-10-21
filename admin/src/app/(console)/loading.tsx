/**
 * Console-wide loading state (any page without its own): the shape every page
 * shares — eyebrow, serif title, a row of grouped figures, a panel of rows —
 * so nothing jumps when the data arrives.
 */
export default function Loading() {
  return (
    <div role="status" aria-live="polite" aria-label="Loading">
      <div className="skel h-3 w-20" />
      <div className="skel mt-4 h-12 w-[min(24rem,80%)]" />
      <div className="skel mt-4 h-4 w-[min(34rem,90%)]" />
      <div className="mt-8 grid grid-cols-2 gap-px overflow-hidden rounded-[20px] border border-[rgba(70,50,30,0.09)] bg-[rgba(70,50,30,0.09)] xl:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="bg-[#fffdfa] p-5">
            <div className="skel h-3 w-28" />
            <div className="skel mt-4 h-9 w-16" />
          </div>
        ))}
      </div>
      <div className="panel mt-6 space-y-3 p-5">
        {[0, 1, 2, 3, 4].map((i) => (
          <div key={i} className="skel h-12" />
        ))}
      </div>
      <span className="sr-only">Loading…</span>
    </div>
  );
}
