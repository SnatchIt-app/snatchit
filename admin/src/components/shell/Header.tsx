import { ENV_LABEL, IS_PRODUCTION_ENV_LABEL } from "@/lib/env";
import { signOutAction } from "@/lib/auth/actions";
import { SearchBox } from "@/components/shell/SearchBox";
import { FreshnessSlot } from "@/components/shell/Freshness";
import { humanize } from "@/lib/format";
import { Icon } from "@/components/ui/Icon";

export function EnvBadge() {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[0.75rem] font-semibold ${
        IS_PRODUCTION_ENV_LABEL ? "bg-primary-ink text-white" : "bg-amber-300 text-ink"
      }`}
      title={`Environment: ${ENV_LABEL}`}
    >
      {ENV_LABEL}
    </span>
  );
}

/** Foot of the sidebar: which environment this is and who is signed in. Always visible on desktop. */
export function SidebarFooter({ email, role }: { email: string | null; role: string }) {
  return (
    <div className="mt-3 rounded-2xl bg-[#faf9f7] p-3 shadow-[0_0_0_1px_rgba(28,25,23,0.06)]">
      <div className="flex items-center justify-between gap-2">
        <EnvBadge />
        <span className="text-[0.75rem] text-muted">
          <FreshnessSlot />
        </span>
      </div>
      <p className="mt-2 truncate text-[0.8125rem] font-semibold" title="Signed-in operator">
        {email ?? "—"}
      </p>
      <p className="text-[0.75rem] text-muted">{humanize(role.replace("platform_", ""))}</p>
    </div>
  );
}

/** The sticky glass header: search first, then environment (phones), keyboard hint, account. */
export function TopBar({ email, role }: { email: string | null; role: string }) {
  return (
    <header className="glass-bar sticky top-0 z-30">
      <div className="mx-auto flex min-h-16 w-full max-w-[1440px] items-center gap-3 px-4 md:px-8">
        <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-ink lg:hidden">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/sn-logo-white.svg" alt="Snatch It" width={22} height={8} className="h-auto w-[1.35rem]" />
        </span>
        <div className="min-w-0 flex-1 md:max-w-md">
          <SearchBox />
        </div>
        <span className="hidden flex-1 md:block" />
        <span className="lg:hidden">
          <EnvBadge />
        </span>
        <p className="hidden items-center gap-1.5 text-[0.75rem] text-muted xl:flex">
          <kbd>/</kbd> search · <kbd>g</kbd> then a key to jump
        </p>
        <details data-popover className="relative shrink-0">
          <summary className="grid h-10 w-10 place-items-center rounded-full bg-ink text-[0.8125rem] font-semibold text-white transition-transform active:scale-95" aria-label="Account">
            {(email ?? "?").slice(0, 1).toUpperCase()}
          </summary>
          <div className="popover glass glass-solid right-0 w-72 p-4">
            <p className="break-words text-sm font-semibold">{email ?? "—"}</p>
            <p className="mt-0.5 text-sm text-muted">{humanize(role.replace("platform_", ""))}</p>
            <form action={signOutAction} className="mt-3">
              <button type="submit" className="btn btn-ghost btn-sm w-full">
                <Icon name="logout" size={15} />
                Sign out
              </button>
            </form>
          </div>
        </details>
      </div>
    </header>
  );
}
