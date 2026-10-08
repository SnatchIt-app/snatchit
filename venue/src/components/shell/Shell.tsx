import Link from "next/link";
import type { ReactNode } from "react";
import { ORG, VENUE } from "@/fixtures/venue";
import { DEMO_DATA_SUBLABEL, demoActionLabel, statesFor, withPreview, type PreviewContext, type Surface } from "@/lib/preview";
import { sourceInfo } from "@/lib/source";
import { PREVIEW_PRINCIPALS, PRINCIPAL_LABEL } from "@/lib/roles";
import { canReadDoor, canReadEvents, canReadTicketTypes, rosterClasses, canManualLookup } from "@/lib/roles";

export type NavEvent = { eventId: string; title: string } | null;

/**
 * Spec §3.2 — xl: persistent left nav · lg: icon nav · md/sm: top drawer.
 * The "Preview data" strip is sticky and not dismissible on any breakpoint.
 */
export function Shell({ ctx, event, active, children, signedInAs }: { ctx: PreviewContext; event: NavEvent; active: "overview" | "events" | "setup" | "inventory" | "attendees" | "door"; children: ReactNode; signedInAs?: string | null }) {
  const dbMode = ctx.source === "database";
  // Database mode links to the route's own scope and offers navigation only once a role was verified.
  const base = dbMode ? (ctx.scope ? `/o/${ctx.scope.orgId}/v/${ctx.scope.venueId}` : null) : `/o/${ORG.orgId}/v/${VENUE.venueId}`;
  const navAllowed = !dbMode || (ctx.verifiedRole === true && base !== null);
  const evBase = event && base ? `${base}/events/${event.eventId}` : null;
  const items: { key: typeof active; label: string; short: string; href: string; show: boolean }[] = [
    { key: "overview", label: "Today", short: "TD", href: base ? withPreview(base, ctx) : "", show: !!base && canReadEvents(ctx.role) },
    { key: "events", label: "Events", short: "EV", href: base ? withPreview(`${base}/events`, ctx) : "", show: !!base && canReadEvents(ctx.role) },
    { key: "setup", label: "Event", short: "EV", href: evBase ? withPreview(evBase, ctx) : "", show: !!evBase && canReadEvents(ctx.role) },
    { key: "inventory", label: "Tickets", short: "TK", href: evBase ? withPreview(`${evBase}/inventory`, ctx) : "", show: !!evBase && canReadTicketTypes(ctx.role) },
    { key: "attendees", label: "Guest list", short: "GL", href: evBase ? withPreview(`${evBase}/attendees`, ctx) : "", show: !!evBase && (rosterClasses(ctx.role) !== null || canManualLookup(ctx.role)) },
    { key: "door", label: "Check-in", short: "CI", href: evBase ? withPreview(`${evBase}/door`, ctx) : "", show: !!evBase && canReadDoor(ctx.role) },
  ];
  const visible = navAllowed ? items.filter((i) => i.show) : [];

  return (
    /*
      Dark labelled rail · grey canvas · white panels (guidelines §1).
      The reference's rail is icon-only; ours carries text, because a
      first-time operator should not have to hover to learn the sections.
    */
    <div className="min-h-dvh bg-canvas">
      <PreviewStrip ctx={ctx} surface={active} />
      <div className="flex">
        <Sidebar ctx={ctx} items={visible} active={active} signedInAs={signedInAs} />
        <div className="min-w-0 flex-1">
          <MobileNav items={visible} active={active} />
          <main className="mx-auto max-w-[1180px] px-4 py-6 md:px-8 md:py-10">{children}</main>
        </div>
      </div>
    </div>
  );
}

type NavItem = { key: string; label: string; short: string; href: string; show: boolean };

/** The rail. Labelled, comfortable targets, active item marked by fill AND a red bar. */
function Sidebar({ ctx, items, active, signedInAs }: { ctx: PreviewContext; items: NavItem[]; active: string; signedInAs?: string | null }) {
  return (
    <nav aria-label="Sections" className="sticky top-9 hidden h-[calc(100dvh-2.25rem)] w-[232px] shrink-0 flex-col bg-sidebar px-3 py-5 md:flex">
      <div className="px-2">
        <p className="flex items-center gap-2 text-[0.9375rem] font-semibold tracking-tight text-white">
          <span aria-hidden="true" className="inline-block h-2 w-2 rounded-full bg-primary" />
          Snatch It
        </p>
        <p className="mt-0.5 text-[0.75rem] text-white/55">Venue dashboard</p>
      </div>
      <ul className="mt-7 space-y-1">
        {items.map((i) => {
          const on = i.key === active;
          return (
            <li key={i.key}>
              <Link
                href={i.href}
                aria-current={on ? "page" : undefined}
                className={`relative flex min-h-[2.5rem] items-center rounded-[10px] px-3 text-[0.875rem] transition-colors ${
                  on ? "bg-white/[0.10] font-semibold text-white" : "text-white/70 hover:bg-white/[0.06] hover:text-white"
                }`}
              >
                {on ? <span aria-hidden="true" className="absolute left-0 top-1/2 h-4 w-[3px] -translate-y-1/2 rounded-full bg-primary" /> : null}
                {i.label}
              </Link>
            </li>
          );
        })}
      </ul>
      <div className="mt-auto space-y-2 px-2 pt-6">
        <p className="break-words text-[0.75rem] leading-relaxed text-white/50">
          {ctx.source === "database" ? (
            signedInAs ?? "Signed in"
          ) : (
            <>
              <span className="block text-white/70">{VENUE.name}</span>
              <span className="block">{PRINCIPAL_LABEL[ctx.role]}</span>
            </>
          )}
        </p>
        {ctx.source === "database" && signedInAs ? (
          <form method="post" action="/logout">
            <button className="min-h-[2rem] rounded-full border border-white/20 px-3 text-[0.8125rem] text-white/80 transition-colors hover:border-white/40 hover:text-white" type="submit">
              Sign out
            </button>
          </form>
        ) : null}
      </div>
    </nav>
  );
}

/** Phone: the same labelled sections in a disclosure, so nothing is icon-only. */
function MobileNav({ items, active }: { items: NavItem[]; active: string }) {
  if (items.length === 0) return null;
  const current = items.find((i) => i.key === active)?.label ?? "Menu";
  return (
    <details className="border-b border-line bg-sidebar md:hidden">
      <summary className="flex min-h-[2.75rem] cursor-pointer items-center gap-2 px-4 text-[0.875rem] font-semibold text-white">
        <span aria-hidden="true" className="inline-block h-2 w-2 rounded-full bg-primary" />
        Snatch It · {current}
      </summary>
      <ul className="px-3 pb-3">
        {items.map((i) => (
          <li key={i.key}>
            <Link
              href={i.href}
              aria-current={i.key === active ? "page" : undefined}
              className={`flex min-h-[2.5rem] items-center rounded-[10px] px-3 text-[0.875rem] ${i.key === active ? "bg-white/[0.10] font-semibold text-white" : "text-white/70"}`}
            >
              {i.label}
            </Link>
          </li>
        ))}
      </ul>
    </details>
  );
}

function PreviewStrip({ ctx, surface }: { ctx: PreviewContext; surface: Surface }) {
  // The context (not the process env) decides the mode, so a rendered tree is self-describing.
  const dbMode = ctx.source === "database";
  const info = sourceInfo();
  const label = dbMode ? (info.source === "database" ? info.label : "Database mode") : info.label;
  return (
    <div className={`preview-banner px-3 py-1.5 ${dbMode ? "preview-banner-db" : ""}`} role="status" aria-live="polite">
      <div className="mx-auto flex max-w-[1600px] flex-wrap items-center justify-between gap-x-3 gap-y-1">
        <span className="flex flex-wrap items-baseline gap-x-2">
          <span>◆ {label}</span>
          {dbMode ? null : <span className="font-normal normal-case tracking-normal">{DEMO_DATA_SUBLABEL}</span>}
        </span>
        {dbMode ? (
          <span className="text-xs normal-case tracking-normal">
            {ctx.verifiedRole ? (
              <>
                Capabilities come from your grants: <strong>{PRINCIPAL_LABEL[ctx.role]}</strong>. Write actions are not available in this mode.
              </>
            ) : (
              <>No verified role at this venue. Write actions are not available in this mode.</>
            )}
          </span>
        ) : (
          <PreviewControls ctx={ctx} surface={surface} />
        )}
      </div>
    </div>
  );
}

/**
 * Role and state switchers — GET form so every surface is linkable in a given
 * persona/state. These are demo instruments, not product controls, so they sit
 * behind a disclosure and never compete with the page's own actions.
 */
function PreviewControls({ ctx, surface }: { ctx: PreviewContext; surface: Surface }) {
  const select = "min-h-7 w-full min-w-0 border border-black/30 bg-white px-1 py-1 text-ink";
  return (
    <details className="w-full text-xs normal-case tracking-normal sm:w-auto">
      <summary className="flex min-h-6 cursor-pointer items-center px-1 font-bold underline decoration-black/40 underline-offset-2">Demo controls</summary>
      {/* A grid, not a flex row: each control gets a column of its own, so a
          narrow screen or doubled text can never squeeze one to a sliver. */}
      <form method="get" className="mt-1 grid gap-2 border border-black/25 bg-white/70 px-2 py-2 [grid-template-columns:repeat(auto-fit,minmax(min(9rem,100%),1fr))]">
        <label className="grid gap-0.5">
          <span>{ctx.source === "database" ? "Display as" : "Viewing as"}</span>
          <select name="role" defaultValue={ctx.role} className={select}>
            {PREVIEW_PRINCIPALS.map((p) => (
              <option key={p} value={p}>
                {PRINCIPAL_LABEL[p]}
              </option>
            ))}
          </select>
        </label>
        <label className="grid gap-0.5">
          <span>Screen state</span>
          <select name="state" defaultValue={ctx.state} className={select}>
            {statesFor(surface).map((s) => (
              <option key={s} value={s}>
                {s === "nodata" ? "no matches" : s}
              </option>
            ))}
          </select>
        </label>
        <button className="min-h-7 self-end border border-black bg-black px-2 py-1 font-bold text-white hover:bg-[#333]" type="submit">
          Apply
        </button>
        <span className="text-dim">Changes who is looking, and lets you force a loading / empty / error screen. Display only — it never changes what a real role is allowed to do.</span>
      </form>
    </details>
  );
}




/** Rendered after any preview "action" form submits with ?did=… */
export function PreviewOutcome({ did }: { did: string | undefined }) {
  if (!did) return null;
  const what = demoActionLabel(did);
  return (
    <p className="mb-4 border border-warning bg-warning/10 px-3 py-2 text-sm" role="status">
      <strong>Nothing was saved.</strong> This is the demo: no ticket moved, no money moved, nobody was emailed.{" "}
      {what ? <>In the real dashboard you would just have {what}.</> : <>In the real dashboard that button does the thing it says; here it does nothing at all.</>}
    </p>
  );
}
