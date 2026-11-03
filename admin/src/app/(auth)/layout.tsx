import type { ReactNode } from "react";
import { EnvBadge } from "@/components/shell/Header";

/**
 * Sign-in, two-factor and denied: the console's ivory canvas with one glass
 * sheet in the middle — the brand mark, then the single task. Nothing to
 * navigate to until you are in.
 */
export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <main className="flex min-h-dvh items-center justify-center px-4 py-10 sm:py-16">
      <div className="enter w-full max-w-[26rem]">
        <div className="mb-7 flex items-end justify-between gap-3 px-1">
          <div>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/sn-logo.svg" alt="" width={56} height={20} className="h-auto w-14" />
            <p className="serif mt-2 text-[1.75rem] leading-none tracking-[-0.02em]">Snatch It</p>
            <p className="mt-1.5 text-[0.8125rem] text-muted">Operations console</p>
          </div>
          <EnvBadge />
        </div>
        <div className="glass glass-solid rounded-[28px] p-6 sm:p-8">{children}</div>
      </div>
    </main>
  );
}
