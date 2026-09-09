/**
 * Spec §19.1 — amounts are integer minor units; the client only formats.
 * Spec §19.2 — venue local time with the zone named on anything an operator
 * will act on; relative times only for freshness.
 */

export function usd(minor: number): string {
  const sign = minor < 0 ? "-" : "";
  const abs = Math.abs(minor);
  const dollars = Math.floor(abs / 100);
  const cents = abs % 100;
  return `${sign}$${dollars.toLocaleString("en-US")}.${cents.toString().padStart(2, "0")}`;
}

export function venueTime(iso: string, timeZone: string, opts: { date?: boolean; zone?: boolean } = { date: true, zone: true }): string {
  const d = new Date(iso);
  const parts: Intl.DateTimeFormatOptions = { hour: "numeric", minute: "2-digit", timeZone };
  if (opts.date !== false) Object.assign(parts, { weekday: "short", month: "short", day: "numeric" });
  if (opts.zone !== false) Object.assign(parts, { timeZoneName: "short" });
  return new Intl.DateTimeFormat("en-US", parts).format(d);
}

export function venueDate(iso: string, timeZone: string): string {
  return new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric", timeZone }).format(new Date(iso));
}

export function relative(iso: string, now: Date): string {
  const diff = now.getTime() - new Date(iso).getTime();
  const abs = Math.abs(diff);
  const m = Math.round(abs / 60000);
  const label = m < 1 ? "just now" : m < 60 ? `${m} min` : m < 60 * 48 ? `${Math.round(m / 60)} h` : `${Math.round(m / 1440)} d`;
  if (label === "just now") return label;
  return diff >= 0 ? `${label} ago` : `in ${label}`;
}

export function daysUntil(iso: string, now: Date): number {
  return Math.ceil((new Date(iso).getTime() - now.getTime()) / 86400000);
}

export function pct(n: number, d: number): string {
  if (d <= 0) return "—";
  return `${Math.round((n / d) * 100)}%`;
}
