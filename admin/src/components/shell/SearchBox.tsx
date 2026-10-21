import { Icon } from "@/components/ui/Icon";

export function SearchBox({ defaultValue = "" }: { defaultValue?: string }) {
  return (
    <form action="/search" method="get" role="search" className="search-pill w-full">
      <Icon name="search" size={16} className="text-dim" />
      <label htmlFor="global-search" className="sr-only">
        Search payments, transfers, listings, users
      </label>
      <input
        id="global-search"
        name="q"
        type="search"
        defaultValue={defaultValue}
        placeholder="Search id, pi_, tr_, email…"
        autoComplete="off"
        spellCheck={false}
      />
      <kbd aria-hidden="true" className="hidden md:inline">
        /
      </kbd>
    </form>
  );
}
