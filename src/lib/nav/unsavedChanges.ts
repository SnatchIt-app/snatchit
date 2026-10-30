/**
 * src/lib/nav/unsavedChanges.ts — should leaving this screen ask first?
 *
 * CFT-208 (item 52): back gestures must preserve unfinished work. The decision
 * is pure so it can be tested; the hook in src/hooks/useUnsavedChangesGuard.ts
 * wires it to React Navigation's `beforeRemove`.
 *
 *  - A successful save or submit navigates on its own; it never asks.
 *  - While a submit is in flight the submit's own flow decides; no dialog.
 *  - Otherwise ask exactly when there is something to lose.
 */

export interface LeaveInput {
  /** Something typed or chosen that has not been saved. */
  dirty: boolean;
  /** A save or submit is in flight. */
  submitting?: boolean;
  /** A save or submit succeeded; the screen is on its way out. */
  saved?: boolean;
}

export function shouldAskBeforeLeaving(i: LeaveInput): boolean {
  if (i.saved) return false;
  if (i.submitting) return false;
  return i.dirty;
}

export interface UnsavedCopy {
  title: string;
  message: string;
  stayLabel: string;
  leaveLabel: string;
}

/** One voice for every "you're about to lose this" dialog. Calm and exact. */
export const UNSAVED_COPY = {
  listingEdit: {
    title: 'Discard changes?',
    message: "Your edits to this listing haven't been saved.",
    stayLabel: 'Keep editing',
    leaveLabel: 'Discard',
  },
  report: {
    title: 'Discard this report?',
    message: "What you've entered won't be sent.",
    stayLabel: 'Keep writing',
    leaveLabel: 'Discard',
  },
  stillSaving: {
    title: 'Still saving',
    message: 'Your last change is still saving. If you leave now it may not stick.',
    stayLabel: 'Wait',
    leaveLabel: 'Leave anyway',
  },
} as const satisfies Record<string, UnsavedCopy>;
