/**
 * src/lib/a11y/spoken.ts — durations as a screen reader should say them.
 *
 * VoiceOver reads "4:32" as a time of day. On a hold countdown that is the wrong fact, so the
 * visible m:ss keeps its formatter and the accessibility label says "4 minutes 32 seconds".
 * Floored to the second, like the visible countdown, so the two never disagree.
 */
export function spokenDuration(ms: number): string {
  if (!Number.isFinite(ms) || ms <= 0) return 'no time';
  const total = Math.floor(ms / 1000);
  if (total === 0) return 'less than a second';
  const m = Math.floor(total / 60);
  const s = total % 60;
  const parts: string[] = [];
  if (m > 0) parts.push(`${m} ${m === 1 ? 'minute' : 'minutes'}`);
  if (s > 0) parts.push(`${s} ${s === 1 ? 'second' : 'seconds'}`);
  return parts.join(' ');
}
