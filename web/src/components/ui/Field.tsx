import type { ReactNode } from "react";

/**
 * Labeled form field — the native micro label over the field, then helper or
 * error text (bodySm). The error line is linked by id so the control's
 * aria-describedby can point at it.
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
  const labelCls = "t-micro block text-muted";
  return (
    <div className={className}>
      {htmlFor ? (
        <label htmlFor={htmlFor} className={labelCls}>
          {label}
        </label>
      ) : (
        <p className={labelCls}>{label}</p>
      )}
      {children}
      {hint && !error ? (
        <p id={hintId} className="t-body-sm mt-2 text-muted">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={errorId} role="alert" className="t-body-sm mt-2 font-medium text-danger">
          {error}
        </p>
      ) : null}
    </div>
  );
}
