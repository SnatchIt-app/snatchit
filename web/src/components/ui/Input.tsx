import type { InputHTMLAttributes, SelectHTMLAttributes } from "react";

/**
 * Form fields in the marketing site's idiom: transparent, square,
 * underline-only (hairline bottom border) that turns brand red on focus.
 */
const fieldBase =
  "h-12 w-full rounded-none bg-transparent text-[15px] text-ink " +
  "placeholder:text-placeholder border-0 border-b border-white/20 px-0 " +
  "transition-colors duration-200 motion-reduce:transition-none " +
  "hover:border-white/40 focus:border-primary focus:outline-none";

export function Input({ className = "", ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={`${fieldBase} ${className}`} {...props} />;
}

export function Select({ className = "", ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={`${fieldBase} appearance-none bg-no-repeat pr-7 ${className}`}
      style={{
        backgroundImage:
          "url(\"data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='11' height='7' fill='none'%3E%3Cpath d='m1 1.25 4.5 4.5 4.5-4.5' stroke='%23666666' stroke-width='1.7' stroke-linecap='round'/%3E%3C/svg%3E\")",
        backgroundPosition: "right 0.15rem center",
      }}
      {...props}
    />
  );
}
