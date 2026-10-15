/**
 * src/lib/ui/appForeground.ts — did the app just come back to the foreground?
 *
 * One rule for every screen that re-reads on return (N3): the PREVIOUS AppState must be background or
 * inactive and the next one active. An 'active' event while already active (a notification banner)
 * is not a return. Callers must read the previous state before recording the new one.
 */
export function cameToForeground(previous: string | null | undefined, next: string): boolean {
  return !!previous && /inactive|background/.test(previous) && next === 'active';
}
