import type { InputHTMLAttributes, SelectHTMLAttributes } from "react";

/**
 * Form fields sit one tonal layer above the page — white overlays on the
 * black, hairline borders, sharp radius. Focus is a border shift, not a ring.
 */
const fieldBase =
  "h-11 w-full rounded-field bg-white/[0.04] text-[14px] text-ink " +
  "placeholder:text-placeholder border border-white/10 px-3.5 " +
  "transition-colors duration-150 motion-reduce:transition-none " +
  "hover:border-white/20 focus:border-primary focus:outline-none";

export function Input({ className = "", ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={`${fieldBase} ${className}`} {...props} />;
}

export function Select({ className = "", ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={`${fieldBase} appearance-none bg-no-repeat pr-9 ${className}`}
      style={{
        backgroundImage:
          "url(\"data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6' fill='none'%3E%3Cpath d='m1 1 4 4 4-4' stroke='%238a94a6' stroke-width='1.5' stroke-linecap='round'/%3E%3C/svg%3E\")",
        backgroundPosition: "right 0.9rem center",
      }}
      {...props}
    />
  );
}
