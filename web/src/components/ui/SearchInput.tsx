import { Icon } from "@/components/ui/Icon";

/**
 * Search field (native Search screen: pill, min height 52, elevated fill,
 * "Event or venue"). A plain GET form to /browse, so it works without
 * JavaScript and lands on a shareable URL (?q=…). Hidden filters carry over.
 */
export function SearchForm({
  defaultValue = "",
  size = "md",
  className = "",
  keep = {},
  autoFocus = false,
}: {
  defaultValue?: string;
  size?: "sm" | "md";
  className?: string;
  keep?: Record<string, string | undefined>;
  autoFocus?: boolean;
}) {
  const h = size === "sm" ? "h-10 text-[14px]" : "h-[52px] text-[16px]";
  return (
    <form action="/browse" method="get" role="search" className={`relative ${className}`}>
      <Icon name="search" size={size === "sm" ? 18 : 20} className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-muted" />
      <input
        type="search"
        name="q"
        defaultValue={defaultValue}
        placeholder="Event or venue"
        aria-label="Search listings by event or venue"
        autoFocus={autoFocus}
        enterKeyHint="search"
        className={`${h} w-full min-w-0 rounded-full border border-transparent bg-surface pl-11 pr-5 text-ink placeholder:text-muted transition-colors focus:border-control focus:bg-elevated [&::-webkit-search-cancel-button]:appearance-none`}
      />
      {Object.entries(keep).map(([k, v]) => (v ? <input key={k} type="hidden" name={k} value={v} /> : null))}
    </form>
  );
}
