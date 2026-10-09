import Link from "next/link";
import type { ReactNode } from "react";
import { ORG, VENUE } from "@/fixtures/venue";
import { DEMO_DATA_LABEL, DEMO_DATA_SUBLABEL, demoActionLabel, statesFor, withPreview, type PreviewContext, type Surface } from "@/lib/preview";
import { sourceInfo } from "@/lib/source";
import { frameAttention } from "@/lib/attention";
import { PREVIEW_PRINCIPALS, PRINCIPAL_LABEL } from "@/lib/roles";
import { canReadDoor, canReadEvents, canReadTicketTypes, rosterClasses, canManualLookup } from "@/lib/roles";
import { Icon, type IconName } from "@/components/ui/Icon";

export type NavEvent = { eventId: string; title: string } | null;
type Active = "overview" | "events" | "setup" | "inventory" | "attendees" | "door";

/**
 * The venue workspace.
 *
 *   sidebar (lg+, floating glass): the venue you are in, then the event you are
 *     working on — its own group, named, with Check-in / Guest list / Tickets /
 *     Setup under it — then everything else. The product's mental model is the
 *     navigation: a venue has events; an event has a door, guests and tickets.
 *   header (sticky glass): where you are as a breadcrumb, the data-source pill,
 *     the attention bell, the account.
 *   phone: the same sections as a floating glass tab bar.
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

  return (
    <div className="min-h-dvh">
      <aside className="glass fixed bottom-3 left-3 top-3 z-40 hidden w-[16.5rem] flex-col rounded-[28px] p-3 lg:flex">
        <div className="flex items-center gap-2.5 px-2 pb-4 pt-1.5">
          <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-ink">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/sn-logo-white.svg" alt="" width={22} height={8} className="h-auto w-[1.35rem]" />
          </span>
          <span className="min-w-0">
            <span className="block text-[0.9375rem] font-semibold leading-tight tracking-[-0.01em]">Snatch It</span>
            <span className="block text-[0.75rem] text-muted">Venue dashboard</span>
          </span>
        </div>

        {place ? (
          <div className="mb-4 rounded-2xl bg-[#faf9f7] px-3 py-2.5 shadow-[0_0_0_1px_rgba(28,25,23,0.06)]">
            <p className="overline">Venue</p>
            <p className="truncate text-[0.875rem] font-semibold">{place}</p>
            <p className="text-[0.75rem] text-muted">{VENUE.neighborhood}</p>
          </div>
        ) : null}

        <nav aria-label="Sections" className="flex min-h-0 flex-1 flex-col gap-5 overflow-y-auto px-0.5">
          {venueNav.length > 0 ? (
            <ul className="flex flex-col gap-0.5">
              {venueNav.slice(0, 1).map((i) => (
                <NavLink key={i.key} i={i} on={active === i.key} />
              ))}
            </ul>
          ) : null}
          {eventNav.length > 0 && navEvent ? (
            <div>
              <p className="nav-group mb-1.5 flex items-center gap-1.5">
                {attention?.stageEvent?.eventId === navEvent.eventId && attention.live ? <span aria-hidden="true" className="live-dot" /> : null}
                {attention?.stageEvent?.eventId === navEvent.eventId ? (attention.live ? "Tonight" : "Next up") : "This event"}
              </p>
              <p className="mb-2 truncate px-3 text-[0.8125rem] font-semibold" title={navEvent.title}>
                {navEvent.title}
              </p>
              <ul className="flex flex-col gap-0.5">
                {eventNav.map((i) => (
                  <NavLink key={i.key} i={i} on={active === i.key} />
                ))}
              </ul>
            </div>
          ) : null}
          {venueNav.length > 1 ? (
            <div>
              <p className="nav-group mb-1.5">Venue</p>
              <ul className="flex flex-col gap-0.5">
                {venueNav.slice(1).map((i) => (
                  <NavLink key={i.key} i={i} on={active === i.key} />
                ))}
              </ul>
            </div>
          ) : null}
        </nav>

        <DataSource ctx={ctx} surface={active} />
      </aside>

      <div className="flex min-h-dvh min-w-0 flex-col lg:pl-[18rem]">
        <header className="glass-bar sticky top-0 z-30">
          <div className="mx-auto flex min-h-16 w-full max-w-[1320px] items-center gap-3 px-4 md:px-8">
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-ink lg:hidden">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/sn-logo-white.svg" alt="Snatch It" width={22} height={8} className="h-auto w-[1.35rem]" />
            </span>
            <nav aria-label="Breadcrumb" className="min-w-0 flex-1">
              <ol className="flex min-w-0 items-center gap-1.5 text-[0.8125rem] text-muted">
                {crumbs.map((c, n) => (
                  <li key={c} className={`flex min-w-0 items-center gap-1.5 ${n === 0 && crumbs.length > 1 ? "hidden sm:flex" : ""}`}>
                    {n > 0 ? <Icon name="chevron" size={13} className="shrink-0 text-dim" /> : null}
                    <span className={`truncate ${n === crumbs.length - 1 ? "font-semibold text-ink" : ""}`}>{c}</span>
                  </li>
                ))}
              </ol>
            </nav>
            <details className="relative lg:hidden">
              <summary aria-label="About this data">
                <DataPill ctx={ctx} />
              </summary>
              <div className="popover right-0 w-[min(20rem,calc(100vw-2rem))]">
                <DataSource ctx={ctx} surface={active} />
              </div>
            </details>
            {attention && base ? (
              <Link
                href={withPreview(`${base}#attention`, ctx)}
                className="btn-icon"
                aria-label={attention.count > 0 ? `${attention.count} ${attention.count === 1 ? "thing needs" : "things need"} your attention` : "Nothing needs your attention"}
                title={attention.count > 0 ? `${attention.count} need your attention` : "Nothing needs your attention"}
              >
                <Icon name="bell" />
                {attention.count > 0 ? <span aria-hidden="true" className="count count-alert absolute -right-1 -top-1 h-[1.125rem] min-w-[1.125rem] px-1 text-[0.625rem]">{attention.count}</span> : null}
              </Link>
            ) : null}
            <Account initials={initials} place={place} who={who} signedInAs={dbMode ? signedInAs : null} />
          </div>
        </header>

        <main id="main" className="mx-auto w-full min-w-0 max-w-[1320px] flex-1 px-4 pb-32 pt-6 md:px-8 md:pt-8 lg:pb-12">
          {title || back ? (
            <div className="enter mb-6 flex flex-wrap items-center gap-x-3 gap-y-2">
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

      <TabBar items={[...venueNav.slice(0, 1), ...eventNav.slice(0, 3), ...venueNav.slice(1)].slice(0, 5)} active={active} />
    </div>
  );
}

type NavItem = { key: string; label: string; icon: IconName; href: string; show: boolean };

function NavLink({ i, on }: { i: NavItem; on: boolean }) {
  return (
    <li>
      <Link href={i.href} aria-current={on ? "page" : undefined} className="nav-item ml-3 mr-0">
        <Icon name={i.icon} size={18} />
        {i.label}
      </Link>
    </li>
  );
}

/** Phone: a floating glass tab bar. Labels always visible; the selected tab is a white pill. */
function TabBar({ items, active }: { items: NavItem[]; active: string }) {
  if (items.length === 0) return null;
  return (
    <nav aria-label="Sections" className="glass fixed inset-x-3 bottom-3 z-40 rounded-[26px] p-1.5 lg:hidden">
      <ul className="flex items-stretch">
        {items.map((i) => {
          const on = i.key === active;
          return (
            <li key={i.key} className="min-w-0 flex-1">
              <Link
                href={i.href}
                aria-current={on ? "page" : undefined}
                className={`flex min-h-[3.25rem] flex-col items-center justify-center gap-0.5 rounded-[20px] px-1 transition-colors ${
                  on ? "bg-ink text-white" : "text-[rgba(28,25,23,0.72)] hover:bg-[rgba(28,25,23,0.05)]"
                }`}
              >
                <Icon name={i.icon} size={19} />
                <span className={`truncate text-[0.6875rem] leading-tight ${on ? "font-semibold" : ""}`}>{i.label}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

function Account({ initials, place, who, signedInAs }: { initials: string; place: string | null; who: string | null; signedInAs?: string | null }) {
  return (
    <details className="relative">
      <summary className="grid h-10 w-10 place-items-center rounded-full bg-ink text-[0.8125rem] font-semibold text-white transition-transform active:scale-95" aria-label="Account">
        {initials}
      </summary>
      <div className="popover glass right-0 w-72 p-4">
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
    </details>
  );
}

/** Compact data-source pill for the phone header (the sidebar card carries the full text on desktop). */
function DataPill({ ctx }: { ctx: PreviewContext }) {
  const dbMode = ctx.source === "database";
  return (
    <span className="context-pill min-h-8 px-2.5 text-[0.75rem]">
      <span aria-hidden="true" className={`inline-block h-2 w-2 rounded-full ${dbMode ? "bg-sky-500" : "bg-amber-500"}`} />
      {dbMode ? "Database" : "Sample data"}
    </span>
  );
}

/**
 * What this data is — always visible, never dismissible — and, in fixture
 * mode, who is looking. Sits at the foot of the sidebar on desktop and at the
 * top of the page on phones.
 */
function DataSource({ ctx, surface }: { ctx: PreviewContext; surface: Surface }) {
  const dbMode = ctx.source === "database";
  const info = sourceInfo();
  const label = dbMode ? (info.source === "database" ? info.label : "Database mode") : info.label;
  return (
    <div className="mt-3 rounded-2xl bg-[#faf9f7] p-3 shadow-[0_0_0_1px_rgba(28,25,23,0.06)]" role="status" aria-live="polite">
      <p className="flex items-center gap-2 text-[0.8125rem] font-semibold">
        <span aria-hidden="true" className={`inline-block h-2 w-2 shrink-0 rounded-full ${dbMode ? "bg-sky-500" : "bg-amber-500"}`} />
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
        <>
          <p className="mt-1 text-[0.75rem] leading-relaxed text-muted">{DEMO_DATA_SUBLABEL}</p>
          <DemoControls ctx={ctx} surface={surface} />
        </>
      )}
    </div>
  );
}

function DemoControls({ ctx, surface }: { ctx: PreviewContext; surface: Surface }) {
  return (
    <details className="relative mt-2">
      <summary className="inline-flex min-h-8 items-center gap-1.5 rounded-full bg-white px-3 text-[0.75rem] font-semibold shadow-[0_0_0_1px_rgba(28,25,23,0.1)] hover:shadow-[0_0_0_1px_rgba(28,25,23,0.25)]">
        Viewing as {PRINCIPAL_LABEL[ctx.role]}
        <Icon name="down" size={13} />
      </summary>
      <form method="get" className="popover glass bottom-10 left-0 grid w-[min(19rem,calc(100vw-3rem))] gap-3 p-4 lg:bottom-auto">
        <p className="text-sm font-semibold">Demo controls</p>
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
    <p className="enter mb-5 flex items-start gap-3 rounded-2xl bg-white px-4 py-3 text-sm shadow-[0_0_0_1px_rgba(28,25,23,0.06)]" role="status">
      <span aria-hidden="true" className="mt-1.5 inline-block h-2 w-2 shrink-0 rounded-full bg-amber-500" />
      <span>
        <strong>Nothing was saved.</strong> This is the demo: no ticket moved, no money moved, nobody was emailed.{" "}
        {what ? <>In the real dashboard you would just have {what}.</> : <>In the real dashboard that button does the thing it says; here it does nothing at all.</>}
      </span>
    </p>
  );
}
