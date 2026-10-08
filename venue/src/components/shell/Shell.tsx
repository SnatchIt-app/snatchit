import Link from "next/link";
import type { ReactNode } from "react";
import { ORG, VENUE } from "@/fixtures/venue";
import { DEMO_DATA_SUBLABEL, demoActionLabel, statesFor, withPreview, type PreviewContext, type Surface } from "@/lib/preview";
import { sourceInfo } from "@/lib/source";
import { frameAttention } from "@/lib/attention";
import { PREVIEW_PRINCIPALS, PRINCIPAL_LABEL } from "@/lib/roles";
import { canReadDoor, canReadEvents, canReadTicketTypes, rosterClasses, canManualLookup } from "@/lib/roles";
import { Icon, type IconName } from "@/components/ui/Icon";

export type NavEvent = { eventId: string; title: string } | null;
type Active = "overview" | "events" | "setup" | "inventory" | "attendees" | "door";

/**
 * The frame every venue page sits in.
 *
 *   dark frame ─┬─ rail (md+): labelled icons, active = white circle
 *               ├─ status line: sample data / database mode, always visible
 *               └─ sheet: the light workspace — page title + context pill on
 *                  the left, attention bell and account on the right, then
 *                  the page
 *   phone: the rail becomes a floating tab bar at the bottom.
 *
 * Tickets, Guests and Check-in act on one event: the page's own, or — when
 * the page is not about one event — the event the overview leads with, named
 * in the rail's tooltip and on the Today page.
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
  /** The page title, set in the serif. Omitted only by surfaces that render their own. */
  title?: string;
  /** A short pill beside the title naming what the page is about (an event, a venue). */
  context?: ReactNode;
  back?: { href: string; label: string };
}) {
  const dbMode = ctx.source === "database";
  const base = dbMode ? (ctx.scope ? `/o/${ctx.scope.orgId}/v/${ctx.scope.venueId}` : null) : `/o/${ORG.orgId}/v/${VENUE.venueId}`;
  const navAllowed = !dbMode || (ctx.verifiedRole === true && base !== null);
  const attention = base && navAllowed ? frameAttention(ctx, base) : null;
  const navEvent = event ?? attention?.stageEvent ?? null;
  const evBase = navEvent && base ? `${base}/events/${navEvent.eventId}` : null;
  const items: NavItem[] = [
    { key: "overview", label: "Today", icon: "today", href: base ? withPreview(base, ctx) : "", show: !!base && canReadEvents(ctx.role) },
    { key: "events", label: "Events", icon: "calendar", href: base ? withPreview(`${base}/events`, ctx) : "", show: !!base && canReadEvents(ctx.role), also: ["setup"] },
    { key: "inventory", label: "Tickets", icon: "ticket", href: evBase ? withPreview(`${evBase}/inventory`, ctx) : "", show: !!evBase && canReadTicketTypes(ctx.role), about: navEvent?.title },
    { key: "attendees", label: "Guests", icon: "users", href: evBase ? withPreview(`${evBase}/attendees`, ctx) : "", show: !!evBase && (rosterClasses(ctx.role) !== null || canManualLookup(ctx.role)), about: navEvent?.title },
    { key: "door", label: "Check-in", icon: "scan", href: evBase ? withPreview(`${evBase}/door`, ctx) : "", show: !!evBase && canReadDoor(ctx.role), about: navEvent?.title },
  ];
  const visible = navAllowed ? items.filter((i) => i.show) : [];
  const isOn = (i: NavItem) => i.key === active || (i.also ?? []).includes(active);
  const who = dbMode ? (ctx.verifiedRole ? PRINCIPAL_LABEL[ctx.role] : null) : PRINCIPAL_LABEL[ctx.role];
  const place = dbMode ? null : VENUE.name;
  const initials = dbMode ? (signedInAs ?? "?").slice(0, 1).toUpperCase() : "WR";

  return (
    <div className="flex min-h-dvh bg-frame">
      <Rail items={visible} isOn={isOn} />
      <div className="flex min-w-0 flex-1 flex-col md:pb-2.5 md:pr-2.5">
        <StatusLine ctx={ctx} surface={active} />
        <div className="sheet flex min-w-0 flex-1 flex-col pb-28 md:pb-0">
          <header className="flex items-start gap-3 px-4 pt-5 md:items-center md:px-8 md:pt-7">
            {back ? (
              <Link href={back.href} className="btn-icon mt-0.5 md:mt-0" aria-label={back.label} title={back.label}>
                <Icon name="back" />
              </Link>
            ) : null}
            <div className="flex min-w-0 flex-1 flex-wrap items-center gap-x-3 gap-y-2">
              {title ? <h1 className="title-page">{title}</h1> : null}
              {context ? <span className="context-pill">{context}</span> : null}
            </div>
            <div className="flex shrink-0 items-center gap-2">
              {attention && base ? (
                <Link
                  href={withPreview(`${base}#attention`, ctx)}
                  className="btn-icon"
                  aria-label={attention.count > 0 ? `${attention.count} ${attention.count === 1 ? "thing needs" : "things need"} your attention` : "Nothing needs your attention"}
                  title={attention.count > 0 ? `${attention.count} need your attention` : "Nothing needs your attention"}
                >
                  <Icon name="bell" />
                  {attention.count > 0 ? <span aria-hidden="true" className="signal-dot absolute right-2 top-2 ring-2 ring-white" /> : null}
                </Link>
              ) : null}
              <Account initials={initials} place={place} who={who} signedInAs={dbMode ? signedInAs : null} />
            </div>
          </header>
          <main id="main" className="min-w-0 flex-1 px-4 pb-8 pt-5 md:px-8 md:pb-10 md:pt-6">
            {children}
          </main>
        </div>
      </div>
      <TabBar items={visible} isOn={isOn} />
    </div>
  );
}

type NavItem = { key: string; label: string; icon: IconName; href: string; show: boolean; also?: string[]; about?: string };

/** Desktop rail: the reference's narrow dark column, with labels under the icons. */
function Rail({ items, isOn }: { items: NavItem[]; isOn: (i: NavItem) => boolean }) {
  return (
    <nav aria-label="Sections" className="on-frame sticky top-0 hidden h-dvh w-[5.75rem] shrink-0 flex-col items-center py-4 md:flex">
      <span className="grid h-11 w-11 place-items-center rounded-full bg-white" title="Snatch It · Venue dashboard">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/sn-logo.svg" alt="Snatch It" width={26} height={10} className="h-auto w-[1.6rem]" />
      </span>
      <ul className="mt-8 flex flex-col items-center gap-3">
        {items.map((i) => {
          const on = isOn(i);
          return (
            <li key={i.key}>
              <Link
                href={i.href}
                aria-current={on ? "page" : undefined}
                title={i.about ? `${i.label} · ${i.about}` : i.label}
                className="group flex w-[4.75rem] flex-col items-center gap-1 rounded-2xl py-1.5"
              >
                <span
                  className={`grid h-11 w-11 place-items-center rounded-full transition-colors ${
                    on ? "bg-white text-[#0f0f10]" : "text-white/70 group-hover:bg-white/10 group-hover:text-white"
                  }`}
                >
                  <Icon name={i.icon} size={19} />
                </span>
                <span className={`text-[0.6875rem] leading-tight ${on ? "font-semibold text-white" : "text-white/70 group-hover:text-white"}`}>{i.label}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

/** Phone: the same sections as a floating tab bar — thumb reach, always labelled. */
function TabBar({ items, isOn }: { items: NavItem[]; isOn: (i: NavItem) => boolean }) {
  if (items.length === 0) return null;
  return (
    <nav aria-label="Sections" className="on-frame fixed inset-x-3 bottom-3 z-40 rounded-[1.75rem] bg-frame/95 px-1.5 py-1.5 shadow-[0_8px_30px_rgba(0,0,0,0.25)] backdrop-blur md:hidden">
      <ul className="flex items-stretch justify-around">
        {items.map((i) => {
          const on = isOn(i);
          return (
            <li key={i.key} className="min-w-0 flex-1">
              <Link
                href={i.href}
                aria-current={on ? "page" : undefined}
                className={`flex min-h-[3.25rem] flex-col items-center justify-center gap-0.5 rounded-[1.375rem] px-1 ${on ? "bg-white text-[#0f0f10]" : "text-white/75"}`}
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

/** The account circle. Opens a small card: where you are, who you are, sign out. */
function Account({ initials, place, who, signedInAs }: { initials: string; place: string | null; who: string | null; signedInAs?: string | null }) {
  return (
    <details className="relative">
      <summary className="grid h-10 w-10 place-items-center rounded-full bg-frame text-[0.8125rem] font-semibold text-white" aria-label="Account">
        {initials}
      </summary>
      <div className="absolute right-0 top-12 z-50 w-64 rounded-2xl bg-white p-4 shadow-[0_12px_40px_rgba(0,0,0,0.14)]">
        {place ? <p className="text-sm font-semibold text-ink">{place}</p> : null}
        {signedInAs ? <p className="break-words text-sm text-ink">{signedInAs}</p> : null}
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

/**
 * Always visible, never dismissible: what this data is. It sits on the dark
 * frame, above the workspace, so it is unmistakable without shouting over the
 * page the way a striped banner did.
 */
function StatusLine({ ctx, surface }: { ctx: PreviewContext; surface: Surface }) {
  const dbMode = ctx.source === "database";
  const info = sourceInfo();
  const label = dbMode ? (info.source === "database" ? info.label : "Database mode") : info.label;
  return (
    <div className="on-frame relative z-30 flex min-h-11 flex-wrap items-center justify-between gap-x-4 gap-y-1 px-4 py-2 text-[0.75rem] text-white/75 md:px-2" role="status" aria-live="polite">
      <p className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-0.5">
        <span aria-hidden="true" className={`inline-block h-2 w-2 shrink-0 rounded-full ${dbMode ? "bg-sky-400" : "bg-amber-400"}`} />
        <span className="font-semibold text-white">{label}</span>
        {dbMode ? null : <span className="hidden text-white/65 lg:inline">{DEMO_DATA_SUBLABEL}</span>}
      </p>
      {dbMode ? (
        <p className="text-white/75">
          {ctx.verifiedRole ? (
            <>
              Capabilities come from your grants: <strong className="text-white">{PRINCIPAL_LABEL[ctx.role]}</strong>. Write actions are not available in this mode.
            </>
          ) : (
            <>No verified role at this venue. Write actions are not available in this mode.</>
          )}
        </p>
      ) : (
        <DemoControls ctx={ctx} surface={surface} />
      )}
    </div>
  );
}

/**
 * Who is looking, and which state to force — GET form, so every surface is
 * linkable in a given persona and state. Demo instruments, not product
 * controls: they live on the frame, never inside the workspace.
 */
function DemoControls({ ctx, surface }: { ctx: PreviewContext; surface: Surface }) {
  return (
    <details className="relative">
      <summary className="inline-flex min-h-8 items-center gap-1.5 rounded-full border border-white/25 px-3 font-semibold text-white hover:border-white/50">
        Viewing as {PRINCIPAL_LABEL[ctx.role]}
        <Icon name="down" size={14} />
      </summary>
      <form method="get" className="absolute right-0 top-10 z-50 grid w-[min(20rem,calc(100vw-2rem))] gap-3 rounded-2xl bg-white p-4 text-ink shadow-[0_12px_40px_rgba(0,0,0,0.3)]">
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
    <p className="mb-5 flex items-start gap-3 rounded-2xl bg-white px-4 py-3 text-sm" role="status">
      <span aria-hidden="true" className="mt-1.5 inline-block h-2 w-2 shrink-0 rounded-full bg-amber-500" />
      <span>
        <strong>Nothing was saved.</strong> This is the demo: no ticket moved, no money moved, nobody was emailed.{" "}
        {what ? <>In the real dashboard you would just have {what}.</> : <>In the real dashboard that button does the thing it says; here it does nothing at all.</>}
      </span>
    </p>
  );
}
