"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { NAV, isNavActive, type NavGroup } from "@/lib/nav";
import { Icon } from "@/components/ui/Icon";

export { NAV };

const GROUPS: NavGroup[] = ["Work", "Money", "People", "Platform"];

/**
 * The console's sections, grouped by the job they serve: the operational
 * queue first, then casework, money movement, people, and the platform
 * itself. Each item shows its `g` shortcut on hover.
 */
export function Sidebar() {
  const pathname = usePathname();
  const item = (n: (typeof NAV)[number]) => {
    const active = isNavActive(pathname, n.href);
    return (
      <li key={n.href}>
        <Link href={n.href} aria-current={active ? "page" : undefined} title={`${n.label} — press g then ${n.key}`} className="nav-item group">
          <Icon name={n.icon} size={20} strokeWidth={1.5} />
          <span className="min-w-0 flex-1 truncate">{n.label}</span>
        </Link>
      </li>
    );
  };
  return (
    <nav aria-label="Console sections" className="flex flex-col gap-4">
      <ul className="flex flex-col gap-1">{NAV.filter((n) => !n.group).map(item)}</ul>
      {GROUPS.map((g) => (
        <div key={g}>
          <p className="nav-group mb-1.5">{g}</p>
          <ul className="flex flex-col gap-1">{NAV.filter((n) => n.group === g).map(item)}</ul>
        </div>
      ))}
    </nav>
  );
}
