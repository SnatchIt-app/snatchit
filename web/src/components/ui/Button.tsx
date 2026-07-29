import Link from "next/link";
import type { AnchorHTMLAttributes, ButtonHTMLAttributes, ReactNode } from "react";

type Variant = "primary" | "secondary" | "ghost";
type Size = "md" | "lg";

/**
 * Buttons in the snatchitapp.com language: square, uppercase Inter bold with
 * tracking-wider, black type on brand red, red glow that deepens on hover.
 * Disabled is a real state (dark fill, no glow), not a faded primary.
 */
const base =
  "inline-flex items-center justify-center gap-2 select-none whitespace-nowrap " +
  "font-bold uppercase tracking-wider transition-all duration-200 " +
  "active:scale-[0.99] " +
  "disabled:cursor-not-allowed disabled:bg-white/[0.06] disabled:text-white/35 disabled:shadow-none disabled:active:scale-100 " +
  "motion-reduce:transition-none motion-reduce:active:scale-100";

const variants: Record<Variant, string> = {
  primary: "bg-primary text-black hover:bg-primary-muted btn-glow",
  secondary: "bg-white/[0.08] text-ink hover:bg-white/[0.14]",
  ghost: "text-white/60 hover:text-primary",
};

// 44px minimum touch target at every size.
const sizes: Record<Size, string> = {
  md: "h-11 px-6 text-[13px]",
  lg: "h-14 px-10 text-[15px]",
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

/**
 * The site's secondary-action idiom: a tracked uppercase text link with an
 * arrow, red on hover. Use for "See all →" / "Read the guarantee →" actions.
 */
export function ArrowLink({
  href,
  children,
  className = "",
  ...props
}: LinkButtonProps) {
  const cls =
    "inline-flex min-h-11 items-center gap-1.5 text-[11px] font-medium uppercase tracking-[0.3em] " +
    "text-primary transition-colors duration-200 hover:text-[#ff5f5f] motion-reduce:transition-none " +
    className;
  if (href.startsWith("http")) {
    return (
      <a href={href} className={cls} target="_blank" rel="noopener noreferrer" {...props}>
        {children}
      </a>
    );
  }
  return (
    <Link href={href} className={cls} {...props}>
      {children}
    </Link>
  );
}
