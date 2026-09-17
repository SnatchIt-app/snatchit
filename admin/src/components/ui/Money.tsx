import { formatMoney } from "@/lib/format";

/** Integer cents → "$1,234.56 USD". Non-integer / missing → "—". */
export function Money({ cents, className = "" }: { cents: unknown; className?: string }) {
  const text = formatMoney(cents);
  return (
    <span className={`font-mono tabular-nums ${className}`} data-cents={typeof cents === "number" ? cents : undefined}>
      {text}
    </span>
  );
}
