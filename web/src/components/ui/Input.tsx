import type { InputHTMLAttributes, SelectHTMLAttributes } from "react";

const fieldBase =
  "h-11 w-full rounded-field bg-field text-ink placeholder:text-placeholder " +
  "border border-line-strong px-3.5 text-[15px] " +
  "focus:border-primary focus:outline-none";

export function Input({ className = "", ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={`${fieldBase} ${className}`} {...props} />;
}

export function Select({ className = "", ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={`${fieldBase} appearance-none bg-no-repeat pr-9 ${className}`}
      style={{
        backgroundImage:
          "url(\"data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' fill='none'%3E%3Cpath d='M1 1.5 6 6.5 11 1.5' stroke='%238a94a6' stroke-width='1.8' stroke-linecap='round'/%3E%3C/svg%3E\")",
        backgroundPosition: "right 0.9rem center",
      }}
      {...props}
    />
  );
}
