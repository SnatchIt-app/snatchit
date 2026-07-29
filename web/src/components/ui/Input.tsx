import type { InputHTMLAttributes, SelectHTMLAttributes } from "react";

const fieldBase =
  "h-11 w-full rounded-[10px] bg-white/[0.05] text-[14.5px] text-ink " +
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
          "url(\"data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='11' height='7' fill='none'%3E%3Cpath d='m1 1.25 4.5 4.5 4.5-4.5' stroke='%238a94a6' stroke-width='1.7' stroke-linecap='round'/%3E%3C/svg%3E\")",
        backgroundPosition: "right 0.85rem center",
      }}
      {...props}
    />
  );
}
