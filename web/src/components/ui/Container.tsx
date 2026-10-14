import type { ReactNode } from "react";

const WIDTHS = {
  default: "max-w-[1200px]",
  medium: "max-w-[1040px]",
  narrow: "max-w-[720px]",
  tight: "max-w-[560px]",
} as const;

/**
 * Content width: native 20pt gutters on phones, then a comfortable column on
 * desktop — the full 1200px for browsing, narrower for focused flows
 * (checkout, transfers, forms) so a line of text never runs across a monitor.
 */
export function Container({
  children,
  className = "",
  size = "default",
}: {
  children: ReactNode;
  className?: string;
  size?: keyof typeof WIDTHS;
}) {
  return <div className={`mx-auto w-full ${WIDTHS[size]} px-5 sm:px-8 lg:px-10 ${className}`}>{children}</div>;
}
