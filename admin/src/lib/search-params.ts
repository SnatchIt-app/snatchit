export type SearchParams = Record<string, string | string[] | undefined>;

export function first(v: string | string[] | undefined): string | undefined {
  const s = Array.isArray(v) ? v[0] : v;
  return s === undefined || s === "" ? undefined : s;
}

/**
 * A multi-value filter as a non-empty array, or undefined. Accepts both a
 * comma-separated value (`?a=x,y`) and repeated keys (`?a=x&a=y`, what a group
 * of checkboxes submits).
 */
export function list(v: string | string[] | undefined): string[] | undefined {
  const s = Array.isArray(v) ? v.join(",") : v;
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

/**
 * The page the operator is on, with every query parameter it was loaded with —
 * so "Try again" after a failed read reloads the same filtered view, not the
 * unfiltered default. Repeated keys are kept.
 */
export function selfHref(path: string, sp: SearchParams): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(sp)) {
    if (Array.isArray(v)) v.forEach((x) => x !== "" && q.append(k, x));
    else if (v !== undefined && v !== "") q.set(k, v);
  }
  const s = q.toString();
  return s ? `${path}?${s}` : path;
}
