import type { ReactNode } from "react";

/**
 * Labeled form field — tracked uppercase micro-label (the brand's existing
 * label voice) over the field, with an accessibly-associated error line.
 */
export function Field({
  label,
  htmlFor,
  error,
  hint,
  children,
  className = "",
}: {
  label: string;
  /**
   * Omit when the field wraps a radiogroup rather than a single control:
   * there is no one element to point at, and a label with a dangling htmlFor
   * is worse than none — it claims an association that does not exist. Those
   * callers pass role="radiogroup" + aria-label instead.
   */
  htmlFor?: string;
  error?: string;
  hint?: string;
  children: ReactNode;
  className?: string;
}) {
  const errorId = error ? `${htmlFor}-error` : undefined;
  const hintId = hint ? `${htmlFor}-hint` : undefined;
  return (
    <div className={className}>
      {htmlFor ? (
        <label htmlFor={htmlFor} className="mb-2.5 block text-[10px] font-medium uppercase tracking-[0.25em] text-white/50">
          {label}
        </label>
      ) : (
        <p className="mb-2.5 block text-[10px] font-medium uppercase tracking-[0.25em] text-white/50">
          {label}
        </p>
      )}
      {children}
      {hint && !error ? (
        <p id={hintId} className="mt-2 text-[12.5px] text-white/45">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={errorId} role="alert" className="mt-2 text-[12.5px] font-medium text-primary">
          {error}
        </p>
      ) : null}
    </div>
  );
}
