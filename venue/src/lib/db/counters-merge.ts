import type { CounterRow } from "@/lib/db/counters";
import type { InventoryBatch } from "@/lib/types";

/**
 * Put the staff counters (D's `get_inventory_counters` rows) onto the batches venue_api gave us. A batch
 * with no counters row keeps `countersKnown: false` and its `remaining`; a row never invents a batch.
 * Returns the merged batches and whether EVERY batch now has counters (only then is the counters view
 * shown; a partial set would mix real numbers with placeholders).
 */
export function mergeCounters(batches: InventoryBatch[], rows: CounterRow[]): { batches: InventoryBatch[]; complete: boolean } {
  const byId = new Map(rows.map((r) => [r.batch_id, r]));
  let complete = batches.length > 0;
  const merged = batches.map((b) => {
    const r = byId.get(b.batchId);
    if (!r) {
      complete = false;
      return b;
    }
    return { ...b, capacity: r.capacity, held: r.held, sold: r.sold, countersKnown: true };
  });
  return { batches: merged, complete };
}
