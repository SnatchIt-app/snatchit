import { Badge, type Tone } from "@/components/ui/Badge";
import type { TransferStatus } from "@/lib/transfers";
import { transferBadgeLabel, type Audience, type OrderRowInput } from "@/lib/transfer-wording";

// Colour carries only the broad state; the words always come from the row
// (transferBadgeLabel). Neutral where the label differs by audience or outcome.
const TONES: Record<TransferStatus, Tone> = {
  pending: "warning",
  seller_sent: "info",
  buyer_confirmed: "success",
  disputed: "warning",
  expired: "neutral",
  auto_released: "neutral",
  reversed: "neutral",
};

/**
 * The label comes from the row, not the status alone: a seller-win and a
 * decided dispute both read differently from what the bare status suggests,
 * and `auto_released` is a release decision, never payout evidence (§2i).
 */
export function TransferStatusBadge({ row, audience }: { row: OrderRowInput; audience: Audience }) {
  return <Badge tone={TONES[row.status]}>{transferBadgeLabel(row, audience)}</Badge>;
}

export function transferStatusLabel(row: OrderRowInput, audience: Audience): string {
  return transferBadgeLabel(row, audience);
}
