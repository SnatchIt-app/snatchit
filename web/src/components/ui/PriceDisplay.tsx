import {
  allInFromDollars,
  baseFromDollars,
  buyerFeeFromDollars,
} from "@snatchit/core";

/**
 * All-in pricing display — the FIRST price a buyer sees is always the
 * fee-inclusive total (same rule as mobile; FTC junk-fee compliant).
 * Prominent but not overpowering: the event stays the star.
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
      ? "text-[38px] font-extrabold leading-none tracking-[-0.02em]"
      : size === "md"
        ? "text-[18px] font-extrabold leading-none tracking-[-0.01em]"
        : "text-[15px] font-bold leading-none";
  return (
    <span className={`inline-flex items-baseline gap-1.5 text-ink ${className}`}>
      <span className={`tabular-nums ${priceCls}`}>{price}</span>
      {suffix ? <span className="text-[12px] font-semibold text-muted">{suffix}</span> : null}
    </span>
  );
}

/** Itemized breakdown rows (ticket price + fee = total). */
export function PriceBreakdown({ baseDollars }: { baseDollars: number }) {
  return (
    <dl className="divide-y divide-white/[0.06] text-[13.5px]">
      <div className="flex items-center justify-between py-2.5">
        <dt className="text-muted">Ticket price</dt>
        <dd className="tabular-nums font-semibold text-ink">{baseFromDollars(baseDollars)}</dd>
      </div>
      <div className="flex items-center justify-between py-2.5">
        <dt className="text-muted">Service &amp; buyer-protection fee</dt>
        <dd className="tabular-nums font-semibold text-ink">{buyerFeeFromDollars(baseDollars)}</dd>
      </div>
      <div className="flex items-center justify-between pt-3">
        <dt className="font-bold text-ink">Total</dt>
        <dd className="tabular-nums text-[16px] font-extrabold text-ink">
          {allInFromDollars(baseDollars)}
        </dd>
      </div>
    </dl>
  );
}
