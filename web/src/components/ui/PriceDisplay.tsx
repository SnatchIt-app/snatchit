import {
  allInFromDollars,
  baseFromDollars,
  buyerFeeFromDollars,
} from "@snatchit/core";

/**
 * All-in pricing display — the FIRST price a buyer sees is always the
 * fee-inclusive total (same rule as mobile; FTC junk-fee compliant).
 * Figures are set in Oswald, the brand's display face.
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
      ? "font-display text-[44px] font-bold leading-none tracking-[-0.01em]"
      : size === "md"
        ? "font-display text-[22px] font-bold leading-none"
        : "font-display text-[17px] font-bold leading-none";
  return (
    <span className={`inline-flex items-baseline gap-2 text-ink ${className}`}>
      <span className={priceCls}>{price}</span>
      {suffix ? (
        <span className="text-[10px] font-medium uppercase tracking-[0.25em] text-white/45">
          {suffix}
        </span>
      ) : null}
    </span>
  );
}

/** Itemized breakdown rows (ticket price + fee = total). */
export function PriceBreakdown({ baseDollars }: { baseDollars: number }) {
  return (
    <dl className="divide-y divide-primary/10 text-[13.5px]">
      <div className="flex items-center justify-between py-2.5">
        <dt className="text-muted">Ticket price</dt>
        <dd className="tabular-nums font-semibold text-ink">{baseFromDollars(baseDollars)}</dd>
      </div>
      <div className="flex items-center justify-between py-2.5">
        <dt className="text-muted">Service &amp; buyer-protection fee</dt>
        <dd className="tabular-nums font-semibold text-ink">{buyerFeeFromDollars(baseDollars)}</dd>
      </div>
      <div className="flex items-center justify-between pt-3">
        <dt className="text-[11px] font-medium uppercase tracking-[0.25em] text-white/60 self-center">
          Total
        </dt>
        <dd className="font-display text-[19px] font-bold text-ink">
          {allInFromDollars(baseDollars)}
        </dd>
      </div>
    </dl>
  );
}
