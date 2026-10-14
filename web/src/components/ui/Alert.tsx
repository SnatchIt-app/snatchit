import type { ReactNode } from "react";
import { Icon, type IconName } from "@/components/ui/Icon";

type AlertTone = "error" | "success" | "warning" | "info";

/**
 * Inline status panel (native NoticeBlock / StateBlock): radius 14, surface
 * fill, a 3px accent in the tone colour on the leading edge. Errors are
 * announced (role="alert"); everything else is a polite status.
 */
const accents: Record<AlertTone, { bar: string; icon: IconName; iconCls: string }> = {
  error: { bar: "bg-danger", icon: "alert", iconCls: "text-danger" },
  success: { bar: "bg-success", icon: "check", iconCls: "text-success" },
  warning: { bar: "bg-warning", icon: "clock", iconCls: "text-warning" },
  info: { bar: "bg-info", icon: "info", iconCls: "text-info" },
};

export function Alert({
  tone = "error",
  title,
  children,
  className = "",
}: {
  tone?: AlertTone;
  title?: ReactNode;
  children?: ReactNode;
  className?: string;
}) {
  const a = accents[tone];
  return (
    <div
      role={tone === "error" ? "alert" : "status"}
      className={`relative flex gap-3 overflow-hidden rounded-panel bg-surface py-3.5 pl-5 pr-4 text-[14px] leading-relaxed text-ink ${className}`}
    >
      <span aria-hidden="true" className={`absolute inset-y-0 left-0 w-[3px] ${a.bar}`} />
      <Icon name={a.icon} size={18} strokeWidth={2} className={`mt-0.5 ${a.iconCls}`} />
      <div className="min-w-0 flex-1">
        {title ? <p className="font-semibold">{title}</p> : null}
        {children ? <div className={title ? "mt-0.5 text-ink-2" : ""}>{children}</div> : null}
      </div>
    </div>
  );
}
