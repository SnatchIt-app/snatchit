export function SearchBox({ defaultValue = "" }: { defaultValue?: string }) {
  return (
    <form action="/search" method="get" role="search" className="flex w-full max-w-md items-center">
      <label htmlFor="global-search" className="sr-only">
        Search payments, transfers, listings, users
      </label>
      <input
        id="global-search"
        name="q"
        type="search"
        defaultValue={defaultValue}
        placeholder="Search id, pi_, tr_, dp_, email, phone…  ( / )"
        autoComplete="off"
        spellCheck={false}
        className="field"
      />
    </form>
  );
}
