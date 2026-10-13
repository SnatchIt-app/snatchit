import type { InputHTMLAttributes, SelectHTMLAttributes, TextareaHTMLAttributes } from "react";

/**
 * Native Input: underline-only field, minimum height 50. The underline is the
 * control colour at rest, ink on hover, brand red on focus and the error
 * colour when invalid (aria-invalid). Text is 16px so iOS Safari never zooms.
 */
const fieldBase =
  "min-h-[50px] w-full rounded-none border-0 border-b bg-transparent px-0 text-[16px] text-ink " +
  "border-control placeholder:text-muted transition-colors duration-150 " +
  "hover:border-ink focus:border-brand focus:shadow-[inset_0_-1px_0_var(--sn-brand)] focus:outline-none focus-visible:outline-none " +
  "aria-[invalid=true]:border-danger disabled:cursor-not-allowed disabled:opacity-50";

export function Input({ className = "", ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={`${fieldBase} ${className}`} {...props} />;
}

export function Textarea({ className = "", ...props }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea className={`${fieldBase} min-h-28 resize-y py-3 leading-relaxed ${className}`} {...props} />;
}

export function Select({ className = "", ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <span className="relative block">
      <select className={`${fieldBase} appearance-none pr-8 ${className}`} {...props} />
      <svg
        aria-hidden="true"
        viewBox="0 0 24 24"
        className="pointer-events-none absolute right-1 top-1/2 size-4 -translate-y-1/2 text-muted"
        fill="none"
        stroke="currentColor"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="m6 9 6 6 6-6" />
      </svg>
    </span>
  );
}
