/**
 * Search entry point — a plain GET form to /browse, so it works without
 * JavaScript and lands on a shareable, crawlable URL (?q=…).
 * Styled in the site's form idiom: square underline field + square red button.
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
  const h = size === "lg" ? "h-14" : "h-12";
  return (
    <form action="/browse" method="get" role="search" className={`flex items-stretch gap-4 ${className}`}>
      <input
        type="search"
        name="q"
        defaultValue={defaultValue}
        placeholder="Search events, venues, artists"
        aria-label="Search listings"
        className={`${h} w-full min-w-0 rounded-none border-0 border-b border-white/25 bg-transparent px-0 text-[15px] font-medium text-ink placeholder:text-placeholder transition-colors duration-200 hover:border-white/45 focus:border-primary focus:outline-none motion-reduce:transition-none`}
      />
      <button
        type="submit"
        className={`${h} btn-glow shrink-0 bg-primary px-7 text-[13px] font-bold uppercase tracking-wider text-black transition-all duration-200 hover:bg-primary-muted active:scale-[0.99] motion-reduce:transition-none`}
      >
        Search
      </button>
    </form>
  );
}
