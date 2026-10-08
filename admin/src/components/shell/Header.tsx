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
        IS_PRODUCTION_ENV_LABEL ? "bg-primary-ink text-white" : "bg-amber-400 text-[#0f0f10]"
      }`}
      title={`Environment: ${ENV_LABEL}`}
    >
      {ENV_LABEL}
    </span>
  );
}

/**
 * The line on the dark frame above the workspace: which environment this is,
 * how fresh the page's data is, and the keyboard hint. Always visible.
 */
export function StatusLine({ email, role }: { email: string | null; role: string }) {
  return (
    <div className="on-frame flex min-h-11 flex-wrap items-center justify-between gap-x-4 gap-y-1 px-4 py-2 text-[0.75rem] text-white/75 md:px-2">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <EnvBadge />
        <span className="text-white/75 [&_*]:!text-inherit">
          <FreshnessSlot />
        </span>
      </div>
      <p className="hidden items-center gap-1.5 lg:flex">
        <kbd className="border-white/20 bg-white/10 text-white/80">/</kbd> search
        <span aria-hidden="true">·</span>
        <kbd className="border-white/20 bg-white/10 text-white/80">g</kbd> then a key to jump
      </p>
      <p className="truncate text-white/75" title="Signed-in operator">
        {email ?? "—"} · {humanize(role.replace("platform_", ""))}
      </p>
    </div>
  );
}

/** Top right of the workspace: search, and the account. */
export function SheetTools({ email, role }: { email: string | null; role: string }) {
  return (
    <div className="flex items-center gap-2">
      <div className="min-w-0 flex-1 md:w-[19rem] md:flex-none">
        <SearchBox />
      </div>
      <details className="relative shrink-0">
        <summary className="grid h-10 w-10 place-items-center rounded-full bg-frame text-[0.8125rem] font-semibold text-white" aria-label="Account">
          {(email ?? "?").slice(0, 1).toUpperCase()}
        </summary>
        <div className="absolute right-0 top-12 z-50 w-64 rounded-2xl bg-white p-4 shadow-[0_12px_40px_rgba(0,0,0,0.14)]">
          <p className="break-words text-sm font-semibold text-ink">{email ?? "—"}</p>
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
  );
}
