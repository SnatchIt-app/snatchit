import type { ReactNode } from "react";
import { EnvBadge } from "@/components/shell/Header";

export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <main className="flex min-h-dvh items-center justify-center px-4 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-6 flex items-center justify-between">
          <div>
            <p className="text-[18px] font-bold leading-tight text-ink">
              Snatch It<span className="text-primary-ink">.</span>
            </p>
            <p className="text-[13px] text-dim">Operations console</p>
          </div>
          <EnvBadge />
        </div>
        <div className="rounded-[var(--radius-card)] border border-line bg-card p-6 shadow-[0_1px_2px_rgba(17,17,17,0.04)]">{children}</div>
      </div>
    </main>
  );
}
