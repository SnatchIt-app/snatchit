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
  const h = size === "lg" ? "h-14" : "h-11";
  return (
    <form action="/browse" method="get" role="search" className={`relative ${className}`}>
      <svg
        aria-hidden="true"
        viewBox="0 0 20 20"
        fill="none"
        className="pointer-events-none absolute left-4 top-1/2 size-[18px] -translate-y-1/2 text-muted"
      >
        <circle cx="9" cy="9" r="6.5" stroke="currentColor" strokeWidth="1.7" />
        <path d="m14 14 4 4" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
      </svg>
      <input
        type="search"
        name="q"
        defaultValue={defaultValue}
        placeholder="Search events, venues, artists"
        aria-label="Search listings"
        className={`${h} w-full rounded-[12px] border border-white/10 bg-white/[0.06] pl-11 pr-28 text-[15px] font-medium text-ink placeholder:text-placeholder transition-colors duration-150 hover:border-white/20 focus:border-primary focus:outline-none motion-reduce:transition-none`}
      />
      <button
        type="submit"
        className="absolute right-2 top-1/2 h-[calc(100%-14px)] min-h-9 -translate-y-1/2 rounded-[8px] bg-primary px-5 text-[13.5px] font-bold text-white transition-colors duration-150 hover:bg-primary-muted active:scale-[0.985] motion-reduce:transition-none"
      >
        Search
      </button>
    </form>
  );
}
