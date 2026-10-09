import Link from "next/link";
import type { ReactNode } from "react";
import { ORG, VENUE } from "@/fixtures/venue";
import { DEMO_DATA_LABEL, DEMO_DATA_SUBLABEL, demoActionLabel, statesFor, withPreview, type PreviewContext, type Surface } from "@/lib/preview";
import { sourceInfo } from "@/lib/source";
import { frameAttention } from "@/lib/attention";
import { PREVIEW_PRINCIPALS, PRINCIPAL_LABEL } from "@/lib/roles";
import { canReadDoor, canReadEvents, canReadTicketTypes, rosterClasses, canManualLookup } from "@/lib/roles";
import { Icon, type IconName } from "@/components/ui/Icon";
import { PopoverDismiss } from "@/components/ui/PopoverDismiss";
import { EventArt } from "@/components/ui/EventArt";

export type NavEvent = { eventId: string; title: string } | null;
type Active = "overview" | "events" | "setup" | "inventory" | "attendees" | "door";

/**
 * The venue workspace — the approved concept's frame (2026-10-09).
 *
 *   sidebar (lg+, floating glass): the brand, the venue you are in, the
 *     event's work (Today, Check-in, Guest list, Tickets, Event setup), the
 *     venue's (All events); at the foot, what this data is and who you are.
 *   top line: where you are (breadcrumb), guest search, attention, account.
 *   phone: a compact top line and a floating glass tab bar.
 *
 * When the page is not about one event, the event group points at the event
 * the overview leads with (fixture mode only), and says which one it is.
 */
export function Shell({
  ctx,
  event,
  active,
  children,
  signedInAs,
  title,
  context,
  back,
}: {
  ctx: PreviewContext;
  event: NavEvent;
  active: Active;
  children: ReactNode;
  signedInAs?: string | null;
  /** A standard page title. Rebuilt pages render their own header and omit it. */
  title?: string;
  context?: ReactNode;
  back?: { href: string; label: string };
}) {
  const dbMode = ctx.source === "database";
  const base = dbMode ? (ctx.scope ? `/o/${ctx.scope.orgId}/v/${ctx.scope.venueId}` : null) : `/o/${ORG.orgId}/v/${VENUE.venueId}`;
  const navAllowed = !dbMode || (ctx.verifiedRole === true && base !== null);
  const attention = base && navAllowed ? frameAttention(ctx, base) : null;
  const navEvent = event ?? attention?.stageEvent ?? null;
  const evBase = navEvent && base ? `${base}/events/${navEvent.eventId}` : null;

  const venueItems: NavItem[] = [
    { key: "overview", label: "Today", icon: "today", href: base ? withPreview(base, ctx) : "", show: !!base && canReadEvents(ctx.role) },
    { key: "events", label: "All events", icon: "calendar", href: base ? withPreview(`${base}/events`, ctx) : "", show: !!base && canReadEvents(ctx.role) },
  ];
  const eventItems: NavItem[] = [
    { key: "door", label: "Check-in", icon: "scan", href: evBase ? withPreview(`${evBase}/door`, ctx) : "", show: !!evBase && canReadDoor(ctx.role) },
    { key: "attendees", label: "Guest list", icon: "users", href: evBase ? withPreview(`${evBase}/attendees`, ctx) : "", show: !!evBase && (rosterClasses(ctx.role) !== null || canManualLookup(ctx.role)) },
    { key: "inventory", label: "Tickets", icon: "ticket", href: evBase ? withPreview(`${evBase}/inventory`, ctx) : "", show: !!evBase && canReadTicketTypes(ctx.role) },
    { key: "setup", label: "Event setup", icon: "settings", href: evBase ? withPreview(evBase, ctx) : "", show: !!evBase && canReadEvents(ctx.role) },
  ];
  const vis = (xs: NavItem[]) => (navAllowed ? xs.filter((i) => i.show) : []);
  const venueNav = vis(venueItems);
  const eventNav = vis(eventItems);
  const who = dbMode ? (ctx.verifiedRole ? PRINCIPAL_LABEL[ctx.role] : null) : PRINCIPAL_LABEL[ctx.role];
  const place = dbMode ? null : VENUE.name;
  const initials = dbMode ? (signedInAs ?? "?").slice(0, 1).toUpperCase() : "SM";
  const SECTION: Record<Active, string> = { overview: "Today", events: "Events", setup: "Event setup", inventory: "Tickets", attendees: "Guest list", door: "Check-in" };
  const crumbs = [place, active === "overview" || active === "events" ? null : navEvent?.title, SECTION[active]].filter(Boolean) as string[];

  const roleLabel = who ?? "No verified role";
  return (
    <div className="min-h-dvh">
      <a href="#main" className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[100] focus:rounded-xl focus:bg-ink focus:px-4 focus:py-2 focus:text-sm focus:font-semibold focus:text-white">
        Skip to content
      </a>
      <aside className="glass fixed bottom-4 left-4 top-4 z-40 hidden w-[15.5rem] flex-col rounded-[26px] px-3.5 pb-3.5 pt-6 lg:flex">
        <div className="px-2.5">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/sn-logo.svg" alt="" width={56} height={20} className="h-auto w-14" />
          <p className="serif mt-2 text-[1.75rem] leading-none tracking-[-0.02em]">Snatch It</p>
        </div>

        {place ? (
          <div className="mt-6 flex items-center gap-3 border-y border-line px-2.5 py-3.5">
            <EventArt title={place} variant="thumb" className="h-11 w-11 shrink-0 overflow-hidden rounded-[10px]" />
            <span className="min-w-0">
              <span className="block truncate text-[0.8125rem] font-medium">{place}</span>
              <span className="block text-[0.75rem] text-muted">{VENUE.neighborhood}</span>
            </span>
          </div>
        ) : (
          <div className="mt-6 border-t border-line" />
        )}

        <nav aria-label="Sections" className="mt-4 flex min-h-0 flex-1 flex-col overflow-y-auto">
          <ul className="flex flex-col gap-1">
            {venueNav.slice(0, 1).map((i) => (
              <NavLink key={i.key} i={i} on={active === i.key} />
            ))}
            {eventNav.map((i) => (
              <NavLink key={i.key} i={i} on={active === i.key} about={navEvent?.title} />
            ))}
          </ul>
          {venueNav.length > 1 ? (
            <div className="mt-5 border-t border-line pt-5">
              <p className="nav-group mb-2">Venue</p>
              <ul className="flex flex-col gap-1">
                {venueNav.slice(1).map((i) => (
                  <NavLink key={i.key} i={i} on={active === i.key} />
                ))}
              </ul>
            </div>
          ) : null}
        </nav>

        <DataSource ctx={ctx} surface={active} />
        <div className="mt-2 border-t border-line pt-3">
          <Account initials={initials} place={place} who={who} roleLabel={roleLabel} signedInAs={dbMode ? signedInAs : null} placement="sidebar" />
        </div>
      </aside>

      <div className="flex min-h-dvh min-w-0 flex-col lg:pl-[17.5rem]">
        <header className="sticky top-0 z-30 lg:static">
          <div className="glass-bar lg:!border-0 lg:!bg-transparent lg:![backdrop-filter:none]">
            <div className="mx-auto flex min-h-16 w-full max-w-[1340px] items-center gap-2 px-4 md:px-8 lg:min-h-[4.5rem]">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/sn-logo.svg" alt="Snatch It" width={40} height={14} className="h-auto w-10 lg:hidden" />
              <nav aria-label="Breadcrumb" className="min-w-0 flex-1 pl-2 lg:pl-0">
                <ol className="flex min-w-0 items-center gap-2 text-[0.875rem] text-muted">
                  {crumbs.map((c, n) => (
                    <li key={c} className={`flex min-w-0 items-center gap-2 ${n < crumbs.length - 1 ? "hidden sm:flex" : ""}`}>
                      {n > 0 ? <span aria-hidden="true" className="text-dim">/</span> : null}
                      <span className={`truncate ${n === crumbs.length - 1 ? "text-ink" : ""}`} aria-current={n === crumbs.length - 1 ? "page" : undefined}>
                        {c}
                      </span>
                    </li>
                  ))}
                </ol>
              </nav>
              <details data-popover className="relative lg:hidden">
                <summary aria-label="About this data" className="rounded-full">
                  <DataPill ctx={ctx} />
                </summary>
                <div className="popover glass glass-solid right-0 w-[min(20rem,calc(100vw-2rem))] p-2">
                  <DataSource ctx={ctx} surface={active} where="menu" />
                </div>
              </details>
              {evBase && canManualLookupOrRoster(ctx) ? (
                <details data-popover className="relative">
                  <summary className="btn-icon" aria-label="Search the guest list">
                    <Icon name="search" size={20} />
                  </summary>
                  <form method="get" action={`${evBase}/attendees`} role="search" className="popover glass glass-solid right-0 w-[min(20rem,calc(100vw-2rem))] p-3">
                    <label htmlFor="guest-q" className="mb-2 block text-[0.75rem] font-medium text-muted">
                      Search {navEvent?.title ? `the guest list for ${navEvent.title}` : "the guest list"}
                    </label>
                    <div className="search-pill">
                      <Icon name="search" size={16} className="text-dim" />
                      <input id="guest-q" name="q" type="search" placeholder="Name, email or customer ref" autoComplete="off" />
                    </div>
                    {ctx.source !== "database" ? (
                      <>
                        <input type="hidden" name="role" value={ctx.role} />
                        {ctx.state !== "live" ? <input type="hidden" name="state" value={ctx.state} /> : null}
                      </>
                    ) : null}
                  </form>
                </details>
              ) : null}
              {attention && base ? (
                <Link
                  href={withPreview(`${base}#attention`, ctx)}
                  className="btn-icon"
                  aria-label={attention.count > 0 ? `${attention.count} ${attention.count === 1 ? "thing needs" : "things need"} your attention` : "Nothing needs your attention"}
                  title={attention.count > 0 ? `${attention.count} need your attention` : "Nothing needs your attention"}
                >
                  <Icon name="bell" size={20} />
                  {attention.count > 0 ? <span aria-hidden="true" className="signal-dot absolute right-2 top-2 ring-2 ring-[#f6f1ea]" /> : null}
                </Link>
              ) : null}
              <span className="lg:hidden">
                <Account initials={initials} place={place} who={who} roleLabel={roleLabel} signedInAs={dbMode ? signedInAs : null} placement="top" />
              </span>
              <span className="hidden lg:inline">
                <Avatar initials={initials} />
              </span>
            </div>
          </div>
        </header>

        <main id="main" className="mx-auto w-full min-w-0 max-w-[1340px] flex-1 px-4 pb-32 pt-5 md:px-8 lg:pb-14 lg:pt-1">
          {title || back ? (
            <div className="enter mb-7 flex flex-wrap items-center gap-x-3 gap-y-2">
              {back ? (
                <Link href={back.href} className="btn-icon" aria-label={back.label} title={back.label}>
                  <Icon name="back" />
                </Link>
              ) : null}
              {title ? <h1 className="title-page">{title}</h1> : null}
              {context ? <span className="context-pill">{context}</span> : null}
            </div>
          ) : null}
          {children}
        </main>
      </div>

      <PopoverDismiss />
      <TabBar items={[...venueNav.slice(0, 1), ...eventNav.slice(0, 3), ...venueNav.slice(1)].slice(0, 5)} active={active} />
    </div>
  );
}

function canManualLookupOrRoster(ctx: PreviewContext): boolean {
  return rosterClasses(ctx.role) !== null || canManualLookup(ctx.role);
}

type NavItem = { key: string; label: string; icon: IconName; href: string; show: boolean };

function NavLink({ i, on, about }: { i: NavItem; on: boolean; about?: string }) {
  return (
    <li>
      <Link href={i.href} aria-current={on ? "page" : undefined} title={about ? `${i.label} · ${about}` : undefined} className="nav-item">
        <Icon name={i.icon} size={20} strokeWidth={1.5} />
        {i.label}
      </Link>
    </li>
  );
}

/** Phone: a floating glass tab bar. Labels always visible; the selected tab is a warm-black tile. */
function TabBar({ items, active }: { items: NavItem[]; active: string }) {
  if (items.length === 0) return null;
  return (
    <nav aria-label="Sections" className="glass fixed inset-x-3 bottom-3 z-40 rounded-[24px] p-1.5 lg:hidden">
      <ul className="flex items-stretch">
        {items.map((i) => {
          const on = i.key === active;
          return (
            <li key={i.key} className="min-w-0 flex-1">
              <Link
                href={i.href}
                aria-current={on ? "page" : undefined}
                className={`flex min-h-[3.25rem] flex-col items-center justify-center gap-0.5 rounded-[18px] px-1 transition-colors ${
                  on ? "bg-[#26211d] text-[#fffdfa]" : "text-[rgba(35,30,26,0.78)] hover:bg-white/50"
                }`}
              >
                <Icon name={i.icon} size={19} strokeWidth={1.6} />
                <span className={`truncate text-[0.6875rem] leading-tight ${on ? "font-semibold" : ""}`}>{i.label}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

function Avatar({ initials }: { initials: string }) {
  return (
    <span aria-hidden="true" className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-[#2f2924] text-[0.8125rem] font-semibold text-[#fffdfa] ring-2 ring-white/70">
      {initials}
    </span>
  );
}

function Account({
  initials,
  place,
  who,
  roleLabel,
  signedInAs,
  placement,
}: {
  initials: string;
  place: string | null;
  who: string | null;
  roleLabel: string;
  signedInAs?: string | null;
  placement: "sidebar" | "top";
}) {
  const card = (
    <div className={`popover glass glass-solid w-72 p-4 ${placement === "sidebar" ? "bottom-14 left-0" : "right-0"}`}>
      {place ? <p className="text-sm font-semibold">{place}</p> : null}
      {signedInAs ? <p className="break-words text-sm">{signedInAs}</p> : null}
      {who ? <p className="mt-0.5 text-sm text-muted">{who}</p> : <p className="mt-0.5 text-sm text-muted">No verified role at this venue</p>}
      {signedInAs ? (
        <form method="post" action="/logout" className="mt-3">
          <button className="btn btn-ghost btn-sm w-full" type="submit">
            <Icon name="logout" size={15} />
            Sign out
          </button>
        </form>
      ) : null}
    </div>
  );
  if (placement === "top")
    return (
      <details data-popover className="relative">
        <summary aria-label="Account" className="rounded-full">
          <Avatar initials={initials} />
        </summary>
        {card}
      </details>
    );
  return (
    <details data-popover className="relative">
      <summary aria-label="Account" className="flex items-center gap-3 rounded-[14px] px-2 py-2 transition-colors hover:bg-white/50">
        <Avatar initials={initials} />
        <span className="min-w-0 flex-1">
          <span className="block truncate text-[0.8125rem] font-medium">{signedInAs ?? roleLabel}</span>
          <span className="block truncate text-[0.75rem] text-muted">{signedInAs ? roleLabel : place ? "Sample account" : "Signed in"}</span>
        </span>
        <Icon name="chevron" size={15} className="text-dim" />
      </summary>
      {card}
    </details>
  );
}

/** Compact data-source pill for the phone top line. */
function DataPill({ ctx }: { ctx: PreviewContext }) {
  const dbMode = ctx.source === "database";
  return (
    <span className="context-pill min-h-8 px-2.5 text-[0.75rem]">
      <span aria-hidden="true" className={`inline-block h-2 w-2 rounded-full ${dbMode ? "bg-sky-600" : "bg-[#2f7a3a]"}`} />
      {dbMode ? "Database" : "Sample data"}
    </span>
  );
}

/**
 * What this data is — always present, never dismissible — and, in fixture
 * mode, who is looking. The concept's quiet "Sample data •" line, which opens
 * the full explanation and the demo controls.
 */
function DataSource({ ctx, surface, where = "sidebar" }: { ctx: PreviewContext; surface: Surface; where?: "sidebar" | "menu" }) {
  const dbMode = ctx.source === "database";
  const info = sourceInfo();
  const label = dbMode ? (info.source === "database" ? info.label : "Database mode") : info.label;
  return (
    <div className="rounded-[14px] px-2.5 py-2" role="status" aria-live="polite">
      <p className="flex items-center gap-2 text-[0.8125rem] font-medium">
        <span aria-hidden="true" className={`inline-block h-2 w-2 shrink-0 rounded-full ${dbMode ? "bg-sky-600" : "bg-[#2f7a3a]"}`} />
        <span className="min-w-0 break-words">{dbMode ? label : DEMO_DATA_LABEL}</span>
      </p>
      {dbMode ? (
        <p className="mt-1 text-[0.75rem] leading-relaxed text-muted">
          {ctx.verifiedRole ? (
            <>
              Capabilities come from your grants: <strong className="text-ink">{PRINCIPAL_LABEL[ctx.role]}</strong>. Write actions are not available in this mode.
            </>
          ) : (
            <>No verified role at this venue. Write actions are not available in this mode.</>
          )}
        </p>
      ) : (
        <DemoControls ctx={ctx} surface={surface} where={where} />
      )}
    </div>
  );
}

function DemoControls({ ctx, surface, where }: { ctx: PreviewContext; surface: Surface; where: "sidebar" | "menu" }) {
  return (
    <details data-popover className="relative mt-2">
      <summary className="ml-4 mt-1 inline-flex min-h-8 max-w-full items-center gap-1.5 rounded-[10px] px-2 text-[0.75rem] text-muted hover:bg-white/60 hover:text-ink" title="Demo controls: who is looking, and which screen state to force">
        <span className="sr-only">Viewing as </span>
        <span className="truncate">{PRINCIPAL_LABEL[ctx.role]}</span>
        <Icon name="down" size={13} className="shrink-0" />
      </summary>
      <form method="get" className={where === "sidebar" ? "popover glass glass-solid bottom-10 left-0 grid w-[min(19rem,calc(100vw-3rem))] gap-3 p-4" : "mt-2 grid gap-3 rounded-[14px] bg-white/70 p-3"}>
        <p className="text-sm font-semibold">Demo controls</p>
        <p className="-mt-1 text-[0.75rem] leading-relaxed text-muted">{DEMO_DATA_SUBLABEL}</p>
        <label className="grid gap-1 text-[0.8125rem]">
          <span className="text-muted">Viewing as</span>
          <select name="role" defaultValue={ctx.role} className="field">
            {PREVIEW_PRINCIPALS.map((p) => (
              <option key={p} value={p}>
                {PRINCIPAL_LABEL[p]}
              </option>
            ))}
          </select>
        </label>
        <label className="grid gap-1 text-[0.8125rem]">
          <span className="text-muted">Screen state</span>
          <select name="state" defaultValue={ctx.state} className="field">
            {statesFor(surface).map((s) => (
              <option key={s} value={s}>
                {s === "nodata" ? "no matches" : s}
              </option>
            ))}
          </select>
        </label>
        <button className="btn btn-primary" type="submit">
          Apply
        </button>
        <p className="text-[0.75rem] leading-relaxed text-muted">Changes who is looking, or forces a loading, empty or error screen. Display only — it never changes what a real role is allowed to do.</p>
      </form>
    </details>
  );
}

/** Rendered after any demo "action" form submits with ?did=… */
export function PreviewOutcome({ did }: { did: string | undefined }) {
  if (!did) return null;
  const what = demoActionLabel(did);
  return (
    <p className="panel enter mb-5 flex items-start gap-3 px-4 py-3 text-sm" role="status">
      <span aria-hidden="true" className="mt-1.5 inline-block h-2 w-2 shrink-0 rounded-full bg-amber-500" />
      <span>
        <strong>Nothing was saved.</strong> This is the demo: no ticket moved, no money moved, nobody was emailed.{" "}
        {what ? <>In the real dashboard you would just have {what}.</> : <>In the real dashboard that button does the thing it says; here it does nothing at all.</>}
      </span>
    </p>
  );
}
