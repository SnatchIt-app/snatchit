import type { ReactNode } from "react";
import Link from "next/link";
import { requireOperator } from "@/lib/auth/session";
import { callOps } from "@/lib/ops";
import { toSettings } from "@/lib/types";
import { Sidebar } from "@/components/shell/Sidebar";
import { Header } from "@/components/shell/Header";
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
    <div role="status" aria-live="polite" className="border-b border-warning bg-card px-4 py-2 text-[13px] text-ink md:px-8">
      <span className="eyebrow mr-2 text-warning">Actions paused</span>
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
        className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[110] focus:bg-primary focus:px-4 focus:py-2 focus:text-sm focus:font-bold focus:uppercase focus:tracking-wider focus:text-black"
      >
        Skip to content
      </a>
      <div className="flex min-h-dvh">
        <aside className="hidden w-56 shrink-0 border-r border-line bg-card md:block">
          <div className="sticky top-0 h-dvh overflow-y-auto">
            <Sidebar />
          </div>
        </aside>
        <div className="flex min-w-0 flex-1 flex-col">
          <Header email={operator.whoami.email_masked ?? operator.email} role={operator.role} />
          {paused ? <PausedNotice /> : null}
          <main id="main" className="min-w-0 flex-1 px-4 py-6 md:px-8">
            {children}
          </main>
        </div>
      </div>
      <KeyboardShortcuts />
    </FreshnessProvider>
  );
}
