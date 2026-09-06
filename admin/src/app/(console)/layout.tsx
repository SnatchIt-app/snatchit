import type { ReactNode } from "react";
import { requireOperator } from "@/lib/auth/session";
import { Sidebar } from "@/components/shell/Sidebar";
import { Header } from "@/components/shell/Header";
import { KeyboardShortcuts } from "@/components/shell/KeyboardShortcuts";
import { FreshnessProvider } from "@/components/shell/Freshness";

// Every console page: verified session (proxy) + operator role proven by
// ops.whoami() in Postgres (requireOperator). Non-operators land on /denied.
export default async function ConsoleLayout({ children }: { children: ReactNode }) {
  const operator = await requireOperator();
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
          <main id="main" className="min-w-0 flex-1 px-4 py-6 md:px-8">
            {children}
          </main>
        </div>
      </div>
      <KeyboardShortcuts />
    </FreshnessProvider>
  );
}
