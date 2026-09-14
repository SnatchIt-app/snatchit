/**
 * src/lib/settings/coalescedSave.ts — latest-wins background save with rollback.
 *
 * CFT-204 (item 11): a reversible preference updates on screen at once and
 * syncs behind it. The saver keeps three things straight — the COMMITTED value
 * (what the server acknowledged), one save IN FLIGHT, and at most one QUEUED
 * value (the newest requested while a save ran; older ones are dropped,
 * because only the latest matters). A failed save restores the committed value
 * through `onRollback` and the screen says so briefly; it never looks like a
 * success. A failure that a newer queued value supersedes does not roll back:
 * the newer value is tried next and decides.
 *
 * Values are compared by identity, so `settle()` can say whether the LAST
 * submitted value is the one the server holds.
 */

export interface CoalescedSaverOptions<T> {
  initial: T;
  /** Persists `value`; resolves true on success. A throw counts as failure. */
  save: (value: T) => Promise<boolean>;
  onCommit?: (value: T) => void;
  /** Called with the value to show again and the one that failed. */
  onRollback?: (committed: T, failed: T) => void;
  onPendingChange?: (pending: boolean) => void;
}

export interface CoalescedSaver<T> {
  /** Records `next` as wanted and saves it as soon as the line is free. */
  submit(next: T): void;
  /** Resolves when nothing is in flight or queued; true if the last submitted value is committed. */
  settle(): Promise<boolean>;
  readonly committed: T;
  readonly pending: boolean;
}

export function createCoalescedSaver<T>(o: CoalescedSaverOptions<T>): CoalescedSaver<T> {
  let committed = o.initial;
  let lastSubmitted = o.initial;
  let queued: { value: T } | null = null;
  let running: Promise<void> | null = null;

  async function drain(first: T): Promise<void> {
    let next: { value: T } | null = { value: first };
    while (next) {
      const { value } = next;
      next = null;
      let ok = false;
      try {
        ok = await o.save(value);
      } catch {
        ok = false;
      }
      if (ok) {
        committed = value;
        o.onCommit?.(value);
      } else if (!queued) {
        o.onRollback?.(committed, value);
      }
      if (queued) {
        next = queued;
        queued = null;
      }
    }
  }

  return {
    get committed() {
      return committed;
    },
    get pending() {
      return running !== null;
    },
    submit(next) {
      lastSubmitted = next;
      if (running) {
        queued = { value: next };
        return;
      }
      o.onPendingChange?.(true);
      running = drain(next).finally(() => {
        running = null;
        o.onPendingChange?.(false);
      });
    },
    async settle() {
      while (running) await running;
      return Object.is(committed, lastSubmitted);
    },
  };
}
