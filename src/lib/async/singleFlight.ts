/**
 * src/lib/async/singleFlight.ts — one submission at a time, held outside render.
 *
 * A React `submitting` state protects a button only after the re-render that
 * disables it; two taps that land before that re-render both run the handler.
 * This lock closes the gap: the second call returns `false` at once and does
 * nothing. The lock is released when the run settles, whether it resolved or
 * threw (CFT-205). The server keeps its own duplicate guards (A-06); this is
 * the client's half, and it never blocks navigation — only the same action.
 */

export interface SingleFlight {
  /** True while a run is in progress. */
  readonly inFlight: boolean;
  /** Runs `fn` unless a run is in progress; resolves `false` when skipped. */
  run(fn: () => Promise<void>): Promise<boolean>;
}

export function createSingleFlight(): SingleFlight {
  let busy = false;
  return {
    get inFlight() {
      return busy;
    },
    async run(fn) {
      if (busy) return false;
      busy = true;
      try {
        await fn();
      } finally {
        busy = false;
      }
      return true;
    },
  };
}
