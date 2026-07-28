/**
 * Search entry point — a plain GET form to /browse, so it works without
 * JavaScript and lands on a shareable, crawlable URL (?q=…).
 */
export function SearchForm({
  defaultValue = "",
  size = "md",
  className = "",
}: {
  defaultValue?: string;
  size?: "md" | "lg";
  className?: string;
}) {
  const h = size === "lg" ? "h-13" : "h-11";
  return (
    <form action="/browse" method="get" role="search" className={`relative ${className}`}>
      <svg
        aria-hidden="true"
        viewBox="0 0 20 20"
        fill="none"
        className="pointer-events-none absolute left-4 top-1/2 size-[18px] -translate-y-1/2 text-muted"
      >
        <circle cx="9" cy="9" r="6.5" stroke="currentColor" strokeWidth="1.8" />
        <path d="m14 14 4 4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
      </svg>
      <input
        type="search"
        name="q"
        defaultValue={defaultValue}
        placeholder="Search events, venues, artists…"
        aria-label="Search listings"
        className={`${h} w-full rounded-chip border border-line-strong bg-field pl-11 pr-28 text-[15px] text-ink placeholder:text-placeholder focus:border-primary focus:outline-none`}
      />
      <button
        type="submit"
        className="absolute right-1.5 top-1/2 h-[calc(100%-12px)] min-h-9 -translate-y-1/2 rounded-chip bg-primary px-5 text-sm font-semibold text-white transition-colors hover:bg-primary-muted motion-reduce:transition-none"
      >
        Search
      </button>
    </form>
  );
}
