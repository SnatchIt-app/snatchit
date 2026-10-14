import Link from "next/link";
import type { AnchorHTMLAttributes, ButtonHTMLAttributes, ReactNode } from "react";
import { Icon } from "@/components/ui/Icon";

type Variant = "primary" | "secondary" | "ghost" | "destructive";
type Size = "sm" | "md" | "lg";

/**
 * The native Button (src/components/ui/Button.tsx): pill shape, Inter Bold
 * 16/20, minimum heights 36 / 44 / 52.
 *   primary      brand red fill, black label (5.4:1), pressed #FF5353
 *   secondary    1px control outline, ink label
 *   destructive  1px error outline + error label — never filled
 *   ghost        no border
 * Disabled dims the whole control to 0.4. Press scales to 0.98.
 */
const base =
  "pressable relative inline-flex items-center justify-center gap-2 select-none rounded-full text-center font-bold leading-tight";
const dimmed = "disabled:cursor-not-allowed disabled:opacity-40 aria-disabled:cursor-not-allowed aria-disabled:opacity-40";

const variants: Record<Variant, string> = {
  primary: "bg-brand text-inverse hover:bg-brand-pressed",
  secondary: "border border-control text-ink hover:border-ink hover:bg-ink/[0.04]",
  ghost: "text-ink hover:bg-ink/[0.06]",
  destructive: "border border-danger text-danger hover:bg-danger/[0.06]",
};

const sizes: Record<Size, string> = {
  sm: "min-h-9 px-4 text-[14px]",
  md: "min-h-11 px-5 text-[15px]",
  lg: "min-h-[52px] px-6 text-[16px]",
};

export function buttonClasses(variant: Variant = "primary", size: Size = "md", extra = "", dimWhenDisabled = true) {
  return `${base} ${dimWhenDisabled ? dimmed : "disabled:cursor-wait"} ${variants[variant]} ${sizes[size]} ${extra}`;
}

/** A spinner that inherits the label colour (native pendingLabel treatment). */
export function Spinner({ className = "" }: { className?: string }) {
  return (
    <span
      aria-hidden="true"
      className={`inline-block size-4 shrink-0 rounded-full border-2 border-current border-r-transparent [animation:sn-spin_0.7s_linear_infinite] ${className}`}
    />
  );
}

/** Two-line pill label: action on top, the qualifying sub-line under it ("minimum $X all-in"). */
export function ButtonLabel({ label, sub }: { label: ReactNode; sub?: ReactNode }) {
  return (
    <span className="flex flex-col items-center py-1.5">
      <span>{label}</span>
      {sub ? <span className="text-[13px] font-medium leading-snug opacity-80">{sub}</span> : null}
    </span>
  );
}

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
  /** Shows a spinner and swaps the label for `pendingLabel` (the control stays full strength). */
  pending?: boolean;
  pendingLabel?: ReactNode;
  children: ReactNode;
}

export function Button({
  variant = "primary",
  size = "md",
  className = "",
  pending = false,
  pendingLabel,
  children,
  ...props
}: ButtonProps) {
  return (
    <button
      className={buttonClasses(variant, size, className, !pending)}
      aria-busy={pending || undefined}
      {...props}
    >
      {pending ? (
        <>
          <Spinner />
          {pendingLabel ?? children}
        </>
      ) : (
        children
      )}
    </button>
  );
}

interface LinkButtonProps extends AnchorHTMLAttributes<HTMLAnchorElement> {
  href: string;
  variant?: Variant;
  size?: Size;
  children: ReactNode;
}

/** Real anchor semantics for navigation that looks like a button. */
export function LinkButton({ href, variant = "primary", size = "md", className = "", ...props }: LinkButtonProps) {
  if (href.startsWith("http")) {
    return (
      <a
        href={href}
        className={buttonClasses(variant, size, className)}
        target="_blank"
        rel="noopener noreferrer"
        {...props}
      />
    );
  }
  return <Link href={href} className={buttonClasses(variant, size, className)} {...props} />;
}

/** Quiet text action with a chevron ("Browse all", "Read the full guarantee"). */
export function ArrowLink({ href, children, className = "", ...props }: LinkButtonProps) {
  const cls =
    "group inline-flex min-h-11 items-center gap-1 text-[14px] font-semibold text-ink underline-offset-4 hover:underline " +
    className;
  const inner = (
    <>
      {children}
      <Icon name="chevronRight" size={16} strokeWidth={2.2} className="transition-transform group-hover:translate-x-0.5" />
    </>
  );
  if (href.startsWith("http")) {
    return (
      <a href={href} className={cls} target="_blank" rel="noopener noreferrer" {...props}>
        {inner}
      </a>
    );
  }
  return (
    <Link href={href} className={cls} {...props}>
      {inner}
    </Link>
  );
}

/** 44pt round icon control (native IconButton). `onArt` sits over artwork. */
export function iconButtonClasses(tone: "chip" | "plain" | "onArt" = "chip", extra = "") {
  const tones = {
    chip: "bg-surface text-ink hover:bg-line",
    plain: "text-ink hover:bg-ink/[0.06]",
    onArt: "bg-black/55 text-white hover:bg-black/70",
  } as const;
  return `pressable inline-flex size-11 shrink-0 items-center justify-center rounded-full ${tones[tone]} ${extra}`;
}
