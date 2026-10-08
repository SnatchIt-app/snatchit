import type { ReactNode } from "react";
import Link from "next/link";
import { requireOperator } from "@/lib/auth/session";
import { callOps } from "@/lib/ops";
import { toSettings } from "@/lib/types";
import { Sidebar } from "@/components/shell/Sidebar";
import { SheetTools, StatusLine } from "@/components/shell/Header";
import { MobileTabBar } from "@/components/shell/MobileNav";
import { KeyboardShortcuts } from "@/components/shell/KeyboardShortcuts";
import { FreshnessProvider } from "@/components/shell/Freshness";

/**
 * ops.setting actions_enabled, read once per request for platform_admin only
 * (ops.settings() is admin-only). null = unknown / not an admin; the banner
 * only renders on a definite `false`. Other roles learn about a pause from
 * the per-form "paused" alert when they submit.
 */
async function consolePaused(role: string): Promise<boolean> {
  if (role !== "platform_admin") return false;
  const res = await callOps<unknown>("settings");
  if (!res.ok) return false;
  return toSettings(res.data).some((s) => s.key === "actions_enabled" && s.value === false);
}

function PausedNotice() {
  return (
    <div role="status" aria-live="polite" className="mx-2 mb-2.5 rounded-2xl bg-white px-4 py-3 text-[0.8125rem] text-ink md:mx-0">
      <span className="mr-2 inline-flex items-center gap-1.5 font-semibold text-warning">
        <span aria-hidden="true" className="inline-block h-2 w-2 rounded-full bg-amber-500" />
        Actions paused
      </span>
      Actions are paused by a founder — the console is read-only until <code className="font-mono">actions_enabled</code> is set back to true from{" "}
      <Link href="/system#setting-actions_enabled" className="link">
        System → Settings
      </Link>
      . Every mutation is refused as <code className="font-mono">console_actions_paused</code>; nothing is queued.
    </div>
  );
}

// Every console page: verified session (proxy) + operator role proven by
// ops.whoami() in Postgres (requireOperator). Non-operators land on /denied.
export default async function ConsoleLayout({ children }: { children: ReactNode }) {
  const operator = await requireOperator();
  const paused = await consolePaused(operator.role);
  return (
    <FreshnessProvider>
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[110] focus:rounded-[var(--radius-control)] focus:bg-primary-ink focus:px-4 focus:py-2 focus:text-sm focus:font-semibold focus:text-white"
      >
        Skip to content
      </a>
      <div className="flex min-h-dvh bg-frame">
        <aside className="hidden w-[5.75rem] shrink-0 md:block">
          <div className="sticky top-0 h-dvh overflow-y-auto">
            <Sidebar />
          </div>
        </aside>
        <div className="flex min-w-0 flex-1 flex-col md:pb-2.5 md:pr-2.5">
          <StatusLine email={operator.whoami.email_masked ?? operator.email} role={operator.role} />
          {paused ? <PausedNotice /> : null}
          <div className="sheet relative flex min-w-0 flex-1 flex-col pb-28 md:pb-0">
            <div className="px-4 pt-4 md:absolute md:right-8 md:top-7 md:z-20 md:p-0">
              <SheetTools email={operator.whoami.email_masked ?? operator.email} role={operator.role} />
            </div>
            <main id="main" className="mx-auto w-full min-w-0 max-w-[1440px] flex-1 px-4 pb-10 pt-5 md:px-8 md:pt-7">
              {children}
            </main>
          </div>
        </div>
        <MobileTabBar />
      </div>
      <KeyboardShortcuts />
    </FreshnessProvider>
  );
}
