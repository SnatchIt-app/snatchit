/** Orders loading: the page's own shape, so nothing jumps when the data arrives. */
export default function Loading() {
  return (
    <div role="status" aria-live="polite" aria-label="Loading orders">
      <div className="skel h-3 w-16" />
      <div className="skel mt-3 h-11 w-[min(26rem,80%)]" />
      <div className="skel mt-3 h-4 w-[min(38rem,90%)]" />
      <div className="mt-8 grid grid-cols-2 gap-4 xl:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="panel p-5">
            <div className="skel h-8 w-8 rounded-full" />
            <div className="skel mt-4 h-8 w-14" />
            <div className="skel mt-3 h-3 w-32" />
          </div>
        ))}
      </div>
      <div className="panel mt-6 p-4">
        <div className="skel h-10 w-[min(28rem,100%)] rounded-full" />
        <div className="mt-4 space-y-3">
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <div key={i} className="skel h-14" />
          ))}
        </div>
      </div>
      <span className="sr-only">Loading…</span>
    </div>
  );
}
