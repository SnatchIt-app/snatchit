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

/** Foot of the sidebar: the environment and data freshness, then the operator (opens sign-out). */
export function SidebarFooter({ email, role }: { email: string | null; role: string }) {
  return (
    <div className="mt-3 border-t border-line pt-3">
      <div className="flex items-center justify-between gap-2 px-2.5 pb-2">
        <EnvBadge />
        <span className="text-[0.75rem] text-muted">
          <FreshnessSlot />
        </span>
      </div>
      <AccountMenu email={email} role={role} placement="sidebar" />
    </div>
  );
}

function Avatar({ email }: { email: string | null }) {
  return (
    <span aria-hidden="true" className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-[#2f2924] text-[0.8125rem] font-semibold text-[#fffdfa] ring-2 ring-white/70">
      {(email ?? "?").slice(0, 1).toUpperCase()}
    </span>
  );
}

function AccountMenu({ email, role, placement }: { email: string | null; role: string; placement: "sidebar" | "top" }) {
  const card = (
    <div className={`popover glass glass-solid w-72 p-4 ${placement === "sidebar" ? "bottom-14 left-0" : "right-0"}`}>
      <p className="break-words text-sm font-semibold">{email ?? "—"}</p>
      <p className="mt-0.5 text-sm text-muted">{humanize(role.replace("platform_", ""))}</p>
      <form action={signOutAction} className="mt-3">
        <button type="submit" className="btn btn-ghost btn-sm w-full">
          <Icon name="logout" size={15} />
          Sign out
        </button>
      </form>
    </div>
  );
  return (
    <details data-popover className="relative">
      {placement === "sidebar" ? (
        <summary aria-label="Account" className="flex items-center gap-3 rounded-[14px] px-2 py-2 transition-colors hover:bg-white/50">
          <Avatar email={email} />
          <span className="min-w-0 flex-1">
            <span className="block truncate text-[0.8125rem] font-medium" title="Signed-in operator">
              {email ?? "—"}
            </span>
            <span className="block truncate text-[0.75rem] text-muted">{humanize(role.replace("platform_", ""))}</span>
          </span>
          <Icon name="chevron" size={15} className="text-dim" />
        </summary>
      ) : (
        <summary aria-label="Account" className="rounded-full">
          <Avatar email={email} />
        </summary>
      )}
      {card}
    </details>
  );
}

/** The sticky glass header: search first, then environment (phones), keyboard hint, account. */
export function TopBar({ email, role }: { email: string | null; role: string }) {
  return (
    <header className="sticky top-0 z-30 lg:static">
      <div className="glass-bar lg:!border-0 lg:!bg-transparent lg:![backdrop-filter:none]">
        <div className="mx-auto flex min-h-16 w-full max-w-[1440px] items-center gap-3 px-4 md:px-8 lg:min-h-[4.5rem]">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/sn-logo.svg" alt="Snatch It" width={40} height={14} className="h-auto w-10 lg:hidden" />
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
          <span className="lg:hidden">
            <AccountMenu email={email} role={role} placement="top" />
          </span>
        </div>
      </div>
    </header>
  );
}
