import Link from "next/link";
import type { AnchorHTMLAttributes, ButtonHTMLAttributes, ReactNode } from "react";

type Variant = "primary" | "secondary" | "ghost";
type Size = "md" | "lg";

/**
 * Confident consumer buttons: bold sentence-case type, 10px radius, tactile
 * press. Disabled is a real state (muted fill), not a faded primary.
 */
const base =
  "inline-flex items-center justify-center gap-2 select-none whitespace-nowrap " +
  "rounded-[10px] font-bold transition-[background-color,border-color,color,transform] " +
  "duration-150 active:scale-[0.985] " +
  "disabled:cursor-not-allowed disabled:bg-white/[0.06] disabled:text-white/35 disabled:active:scale-100 " +
  "motion-reduce:transition-none motion-reduce:active:scale-100";

const variants: Record<Variant, string> = {
  primary: "bg-primary text-white hover:bg-primary-muted",
  secondary: "bg-white/[0.07] text-ink hover:bg-white/[0.12]",
  ghost: "text-white/70 hover:text-ink",
};

// 44px minimum touch target at every size.
const sizes: Record<Size, string> = {
  md: "h-11 px-5 text-[14px]",
  lg: "h-[52px] px-7 text-[15px]",
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
