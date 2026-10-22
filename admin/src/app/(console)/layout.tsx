import type { ReactNode } from "react";
import Link from "next/link";
import { requireOperator } from "@/lib/auth/session";
import { callOps } from "@/lib/ops";
import { toSettings } from "@/lib/types";
import { Sidebar } from "@/components/shell/Sidebar";
import { SidebarFooter, TopBar } from "@/components/shell/Header";
import { MobileTabBar } from "@/components/shell/MobileNav";
import { KeyboardShortcuts } from "@/components/shell/KeyboardShortcuts";
import { PopoverDismiss } from "@/components/ui/PopoverDismiss";
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
    <div role="status" aria-live="polite" className="enter mb-6 rounded-2xl bg-white px-4 py-3 text-[0.8125rem] text-ink shadow-[0_0_0_1px_rgba(154,71,6,0.25)]">
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
      <div className="min-h-dvh">
        <aside className="glass fixed bottom-4 left-4 top-4 z-40 hidden w-[15.5rem] flex-col rounded-[26px] px-3.5 pb-3.5 pt-6 lg:flex">
          <Link href="/" className="block rounded-[14px] px-2.5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/sn-logo.svg" alt="" width={56} height={20} className="h-auto w-14" />
            <span className="serif mt-2 block text-[1.75rem] leading-none tracking-[-0.02em]">Snatch It</span>
            <span className="mt-1.5 block text-[0.75rem] text-muted">Operations console</span>
          </Link>
          <div className="mt-5 min-h-0 flex-1 overflow-y-auto border-t border-line pt-4">
            <Sidebar />
          </div>
          <SidebarFooter email={operator.whoami.email_masked ?? operator.email} role={operator.role} />
        </aside>
        <div className="flex min-h-dvh min-w-0 flex-col lg:pl-[17.5rem]">
          <TopBar email={operator.whoami.email_masked ?? operator.email} role={operator.role} />
          <main id="main" className="mx-auto w-full min-w-0 max-w-[1440px] flex-1 px-4 pb-32 pt-5 md:px-8 lg:pb-14 lg:pt-2">
            {paused ? <PausedNotice /> : null}
            {children}
          </main>
        </div>
        <MobileTabBar />
      </div>
      <KeyboardShortcuts />
      <PopoverDismiss />
    </FreshnessProvider>
  );
}
