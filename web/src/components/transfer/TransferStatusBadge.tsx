import { Badge } from "@/components/ui/Badge";
import type { TransferStatus } from "@/lib/transfers";

/** Labels ported verbatim from mobile's TransferStatusBadge. */
const LABELS: Record<TransferStatus, string> = {
  pending: "Transfer Pending",
  seller_sent: "Transfer Sent",
  buyer_confirmed: "Transfer Complete",
  disputed: "Disputed",
  expired: "Transfer Expired",
  auto_released: "Payout Released",
  reversed: "Payment Reversed",
};

const VARIANTS: Record<TransferStatus, "live" | "soon" | "sold" | "buyNow"> = {
  pending: "soon",
  seller_sent: "buyNow",
  buyer_confirmed: "live",
  disputed: "sold",
  expired: "sold",
  auto_released: "live",
  reversed: "sold",
};

export function TransferStatusBadge({ status }: { status: TransferStatus }) {
  return <Badge variant={VARIANTS[status]}>{LABELS[status]}</Badge>;
}

export function transferStatusLabel(status: TransferStatus): string {
  return LABELS[status];
}
