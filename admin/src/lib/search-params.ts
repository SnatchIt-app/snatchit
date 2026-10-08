export type SearchParams = Record<string, string | string[] | undefined>;

export function first(v: string | string[] | undefined): string | undefined {
  const s = Array.isArray(v) ? v[0] : v;
  return s === undefined || s === "" ? undefined : s;
}

/** Split a comma-separated filter param into a non-empty array, or undefined. */
export function list(v: string | string[] | undefined): string[] | undefined {
  const s = first(v);
  if (!s) return undefined;
  const parts = s
    .split(",")
    .map((p) => p.trim())
    .filter(Boolean);
  return parts.length ? parts : undefined;
}

export function cursorOf(sp: SearchParams): string | null {
  return first(sp.cursor) ?? null;
}

export function limitOf(sp: SearchParams, fallback = 50, max = 200): number {
  const n = Number(first(sp.limit));
  if (!Number.isInteger(n) || n <= 0) return fallback;
  return Math.min(n, max);
}
