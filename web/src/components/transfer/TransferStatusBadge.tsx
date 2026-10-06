import { Badge } from "@/components/ui/Badge";
import type { TransferStatus } from "@/lib/transfers";
import { transferBadgeLabel, type Audience, type OrderRowInput } from "@/lib/transfer-wording";

const VARIANTS: Record<TransferStatus, "live" | "soon" | "sold" | "buyNow"> = {
  pending: "soon",
  seller_sent: "buyNow",
  buyer_confirmed: "live",
  disputed: "sold",
  expired: "sold",
  auto_released: "live",
  reversed: "sold",
};

/**
 * The label comes from the row, not the status alone: a seller-win and a
 * decided dispute both read differently from what the bare status suggests,
 * and `auto_released` is a release decision, never payout evidence (§2i).
 */
export function TransferStatusBadge({ row, audience }: { row: OrderRowInput; audience: Audience }) {
  return <Badge variant={VARIANTS[row.status]}>{transferBadgeLabel(row, audience)}</Badge>;
}

export function transferStatusLabel(row: OrderRowInput, audience: Audience): string {
  return transferBadgeLabel(row, audience);
}
