import {
  allInFromDollars,
  baseFromDollars,
  buyerFeeFromDollars,
} from "@snatchit/core";

/**
 * All-in pricing display — the FIRST price a buyer sees is always the
 * fee-inclusive total (same rule as mobile; FTC junk-fee compliant).
 */
export function PriceDisplay({
  baseDollars,
  size = "md",
  suffix = "total",
  className = "",
}: {
  baseDollars: number;
  size?: "sm" | "md" | "lg";
  suffix?: string | null;
  className?: string;
}) {
  const price = allInFromDollars(baseDollars);
  const priceCls =
    size === "lg"
      ? "text-3xl font-bold tracking-tight"
      : size === "md"
        ? "text-lg font-bold"
        : "text-[15px] font-bold";
  return (
    <span className={`inline-flex items-baseline gap-1.5 text-ink ${className}`}>
      <span className={priceCls}>{price}</span>
      {suffix ? <span className="text-xs font-medium text-muted">{suffix}</span> : null}
    </span>
  );
}

/** Itemized breakdown rows (ticket price + fee = total). */
export function PriceBreakdown({ baseDollars }: { baseDollars: number }) {
  return (
    <dl className="space-y-2 text-sm">
      <div className="flex items-center justify-between">
        <dt className="text-muted">Ticket price</dt>
        <dd className="text-ink">{baseFromDollars(baseDollars)}</dd>
      </div>
      <div className="flex items-center justify-between">
        <dt className="text-muted">Service &amp; buyer-protection fee</dt>
        <dd className="text-ink">{buyerFeeFromDollars(baseDollars)}</dd>
      </div>
      <div className="flex items-center justify-between border-t border-line pt-2">
        <dt className="font-semibold text-ink">Total</dt>
        <dd className="font-bold text-ink">{allInFromDollars(baseDollars)}</dd>
      </div>
    </dl>
  );
}
