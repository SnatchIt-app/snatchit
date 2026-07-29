import type { ReactNode } from "react";

/**
 * Form-level status line — a red hairline block for errors, a white one for
 * neutral/success messages. Announced to screen readers via role="status"/
 * "alert" from the call site's live-region semantics.
 */
export function Alert({
  tone = "error",
  children,
}: {
  tone?: "error" | "success";
  children: ReactNode;
}) {
  const toneCls =
    tone === "error"
      ? "border-primary/40 bg-primary/[0.06] text-[#ff8f8a]"
      : "border-white/20 bg-white/[0.04] text-white/85";
  return (
    <div role={tone === "error" ? "alert" : "status"} className={`border px-4 py-3 text-[13.5px] leading-relaxed ${toneCls}`}>
      {children}
    </div>
  );
}
