import { ENV_LABEL, IS_PRODUCTION_ENV_LABEL } from "@/lib/env";
import { signOutAction } from "@/lib/auth/actions";
import { SearchBox } from "@/components/shell/SearchBox";
import { FreshnessSlot } from "@/components/shell/Freshness";

export function EnvBadge() {
  return (
    <span
      className={`inline-flex items-center border px-2 py-0.5 text-[11px] font-bold uppercase tracking-[0.2em] ${
        IS_PRODUCTION_ENV_LABEL ? "border-primary bg-primary text-black" : "border-warning bg-warning/10 text-warning"
      }`}
      title={`Environment: ${ENV_LABEL}`}
    >
      {ENV_LABEL}
    </span>
  );
}

export function Header({ email, role }: { email: string | null; role: string }) {
  return (
    <header className="sticky top-0 z-20 flex flex-wrap items-center gap-3 border-b border-line bg-bg/95 px-4 py-2 backdrop-blur">
      <EnvBadge />
      <div className="min-w-[200px] flex-1">
        <SearchBox />
      </div>
      <div className="hidden sm:block">
        <FreshnessSlot />
      </div>
      <div className="flex items-center gap-3 text-[12px]">
        <span className="text-muted" title="Signed-in operator">
          {email ?? "—"}
        </span>
        <span className="border border-line-neutral px-1.5 py-0.5 text-[10px] uppercase tracking-wider text-dim">
          {role.replace("platform_", "")}
        </span>
        <form action={signOutAction}>
          <button type="submit" className="btn btn-ghost btn-sm">
            Sign out
          </button>
        </form>
      </div>
    </header>
  );
}
