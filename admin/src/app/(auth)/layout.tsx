import type { ReactNode } from "react";
import { EnvBadge } from "@/components/shell/Header";

/**
 * Sign-in, MFA and denied: the same dark frame and light sheet as the console,
 * with one card in the middle. Nothing to navigate to until you are in.
 */
export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <main className="flex min-h-dvh items-stretch bg-frame p-0 md:p-2.5">
      <div className="sheet flex flex-1 items-center justify-center px-4 py-10">
        <div className="w-full max-w-sm">
          <div className="mb-6 flex items-center justify-between gap-3">
            <div className="flex items-center gap-3">
              <span className="grid h-11 w-11 place-items-center rounded-full bg-frame">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src="/sn-logo-white.svg" alt="" width={26} height={10} className="h-auto w-[1.6rem]" />
              </span>
              <div>
                <p className="text-[1rem] font-semibold leading-tight text-ink">Snatch It</p>
                <p className="text-[0.8125rem] text-muted">Operations console</p>
              </div>
            </div>
            <EnvBadge />
          </div>
          <div className="panel p-6 md:p-7">{children}</div>
        </div>
      </div>
    </main>
  );
}
