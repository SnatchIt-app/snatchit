/**
 * src/lib/design/rowMetrics.ts — V3 row layout rules that must not drift per-screen (§3).
 * Rows are content-driven: heights are never hard-coded; this is the one fixed promise.
 */

/** Minimum clear space between a row's last metadata line and the divider below it. */
export const ROW_META_CLEARANCE = 12;
