import Link from "next/link";
import type { AnchorHTMLAttributes, ButtonHTMLAttributes, ReactNode } from "react";

type Variant = "primary" | "secondary" | "ghost";
type Size = "md" | "lg";

/**
 * Buttons speak in the brand's uppercase micro-voice. Depth comes from tone
 * and a 1px press translation — no shadows, no scale tricks.
 */
const base =
  "inline-flex items-center justify-center gap-2 select-none whitespace-nowrap " +
  "rounded-field text-[13px] font-semibold uppercase tracking-[0.1em] " +
  "transition-[background-color,border-color,color,transform] duration-150 " +
  "active:translate-y-px motion-reduce:transition-none motion-reduce:active:translate-y-0";

const variants: Record<Variant, string> = {
  primary: "bg-primary text-white hover:bg-primary-muted",
  secondary:
    "border border-white/15 bg-transparent text-ink hover:border-white/40 hover:bg-white/[0.03]",
  ghost: "text-muted hover:text-ink",
};

// 44px minimum touch target at every size.
const sizes: Record<Size, string> = {
  md: "h-11 px-6",
  lg: "h-[52px] px-8",
};

export function buttonClasses(variant: Variant = "primary", size: Size = "md", extra = "") {
  return `${base} ${variants[variant]} ${sizes[size]} ${extra}`;
}

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: Size;
  children: ReactNode;
}

export function Button({ variant = "primary", size = "md", className = "", ...props }: ButtonProps) {
  return <button className={buttonClasses(variant, size, className)} {...props} />;
}

interface LinkButtonProps extends AnchorHTMLAttributes<HTMLAnchorElement> {
  href: string;
  variant?: Variant;
  size?: Size;
  children: ReactNode;
}

/** Real anchor semantics for navigation that looks like a button. */
export function LinkButton({
  href,
  variant = "primary",
  size = "md",
  className = "",
  ...props
}: LinkButtonProps) {
  const external = href.startsWith("http");
  if (external) {
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
