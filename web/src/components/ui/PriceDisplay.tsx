import { allInFromDollars, baseFromDollars, buyerFeeFromDollars } from "@snatchit/core";

/**
 * All-in pricing display — the FIRST price a buyer sees is always the
 * fee-inclusive total (same rule as mobile; FTC junk-fee compliant).
 * Native price token: Inter 700 with tabular figures; the caption ("all-in",
 * "total") sits beside it in the muted colour. Amounts never truncate: they
 * wrap under their label at narrow widths and large text sizes instead.
 */
export function PriceDisplay({
  baseDollars,
  size = "md",
  suffix = "total",
  className = "",
  stacked = false,
}: {
  baseDollars: number;
  size?: "sm" | "md" | "lg";
  suffix?: string | null;
  className?: string;
  /** Caption under the amount (feed rows, right-aligned price columns). */
  stacked?: boolean;
}) {
  const price = allInFromDollars(baseDollars);
  const priceCls =
    size === "lg" ? "text-[30px] leading-[1.1] lg:text-[36px]" : size === "md" ? "text-[20px] leading-tight" : "text-[17px] leading-tight";
  return (
    <span
      className={`inline-flex min-w-0 text-ink ${stacked ? "flex-col items-end" : "flex-wrap items-baseline gap-x-1.5"} ${className}`}
    >
      <span className={`t-price whitespace-nowrap ${priceCls}`}>{price}</span>
      {suffix ? <span className="text-[13px] font-normal leading-snug text-muted">{suffix}</span> : null}
    </span>
  );
}

/** Itemized breakdown rows (ticket price + fee = total). */
export function PriceBreakdown({ baseDollars }: { baseDollars: number }) {
  return (
    <dl className="text-[15px]">
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-b border-line py-3">
        <dt className="text-ink-2">Ticket price</dt>
        <dd className="t-price text-ink">{baseFromDollars(baseDollars)}</dd>
      </div>
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-b border-line py-3">
        <dt className="text-ink-2">Service &amp; buyer-protection fee</dt>
        <dd className="t-price text-ink">{buyerFeeFromDollars(baseDollars)}</dd>
      </div>
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 pt-3.5">
        <dt className="t-label text-ink">Total</dt>
        <dd className="t-price text-[20px] text-ink">{allInFromDollars(baseDollars)}</dd>
      </div>
    </dl>
  );
}
