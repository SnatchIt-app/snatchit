import {
  allInFromDollars,
  baseFromDollars,
  buyerFeeFromDollars,
} from "@snatchit/core";

/**
 * All-in pricing display — the FIRST price a buyer sees is always the
 * fee-inclusive total (same rule as mobile; FTC junk-fee compliant).
 * Figures are tabular and tightly tracked: the price is a visual anchor.
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
      ? "text-[44px] font-bold leading-none tracking-[-0.03em]"
      : size === "md"
        ? "text-[19px] font-bold leading-none tracking-[-0.01em]"
        : "text-[15px] font-bold leading-none";
  return (
    <span className={`inline-flex items-baseline gap-2 text-ink ${className}`}>
      <span className={`tabular-nums ${priceCls}`}>{price}</span>
      {suffix ? (
        <span className="text-[10px] font-semibold uppercase tracking-[0.14em] text-dim">
          {suffix}
        </span>
      ) : null}
    </span>
  );
}

/** Itemized breakdown rows (ticket price + fee = total), hairline-ruled. */
export function PriceBreakdown({ baseDollars }: { baseDollars: number }) {
  return (
    <dl className="text-[13px]">
      <div className="flex items-center justify-between py-2">
        <dt className="text-muted">Ticket price</dt>
        <dd className="tabular-nums text-ink">{baseFromDollars(baseDollars)}</dd>
      </div>
      <div className="rule-t flex items-center justify-between py-2">
        <dt className="text-muted">Service &amp; buyer-protection fee</dt>
        <dd className="tabular-nums text-ink">{buyerFeeFromDollars(baseDollars)}</dd>
      </div>
      <div className="rule-t flex items-center justify-between pt-2.5">
        <dt className="font-semibold text-ink">Total</dt>
        <dd className="tabular-nums text-[15px] font-bold text-ink">
          {allInFromDollars(baseDollars)}
        </dd>
      </div>
    </dl>
  );
}
