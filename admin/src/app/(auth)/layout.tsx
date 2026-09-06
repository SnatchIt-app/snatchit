import type { ReactNode } from "react";
import { EnvBadge } from "@/components/shell/Header";

export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <main className="flex min-h-dvh items-center justify-center px-4 py-10">
      <div className="w-full max-w-sm">
        <div className="mb-6 flex items-center justify-between">
          <div>
            <p className="text-[17px] font-black uppercase tracking-[0.2em] text-primary">Snatch It</p>
            <p className="eyebrow text-dim">Operating console</p>
          </div>
          <EnvBadge />
        </div>
        <div className="border border-line bg-card p-6">{children}</div>
      </div>
    </main>
  );
}
