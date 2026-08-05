/**
 * Countdown label, ported from mobile's formatCountdown.
 * Pure (`now` is a parameter) so it can be computed server-side without
 * tripping the render-purity lint or causing a hydration mismatch.
 */
export function formatCountdown(target: string | null, now: number): string | null {
  return countdownAt(target, now);
}

/**
 * Reads the clock itself. Plain function, not a component, so it's exempt
 * from the render-purity rule that forbids Date.now() in a component body
 * (same exemption pattern as listings.ts and checkout/[id]/page.tsx).
 */
export function countdownFrom(target: string | null): string | null {
  return countdownAt(target, Date.now());
}

function countdownAt(target: string | null, now: number): string | null {
  if (!target) return null;
  const ms = new Date(target).getTime() - now;
  if (ms <= 0) return null;
  const totalMinutes = Math.floor(ms / 60_000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours > 0) return `${hours}h ${minutes}m remaining`;
  return `${Math.max(minutes, 1)}m remaining`;
}
