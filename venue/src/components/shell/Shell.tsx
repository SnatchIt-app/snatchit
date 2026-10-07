import Link from "next/link";
import type { ReactNode } from "react";
import { ORG, VENUE } from "@/fixtures/venue";
import { DEMO_DATA_SUBLABEL, PREVIEW_STATES, demoActionLabel, withPreview, type PreviewContext } from "@/lib/preview";
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
    { key: "overview", label: "Tonight", short: "TN", href: base ? withPreview(base, ctx) : "", show: !!base && canReadEvents(ctx.role) },
    { key: "events", label: "Events", short: "EV", href: base ? withPreview(`${base}/events`, ctx) : "", show: !!base && canReadEvents(ctx.role) },
    { key: "setup", label: "Event setup", short: "SET", href: evBase ? withPreview(evBase, ctx) : "", show: !!evBase && canReadEvents(ctx.role) },
    { key: "inventory", label: "Inventory", short: "INV", href: evBase ? withPreview(`${evBase}/inventory`, ctx) : "", show: !!evBase && canReadTicketTypes(ctx.role) },
    { key: "attendees", label: "Attendees", short: "ATT", href: evBase ? withPreview(`${evBase}/attendees`, ctx) : "", show: !!evBase && (rosterClasses(ctx.role) !== null || canManualLookup(ctx.role)) },
    { key: "door", label: "Door", short: "DR", href: evBase ? withPreview(`${evBase}/door`, ctx) : "", show: !!evBase && canReadDoor(ctx.role) },
  ];
  const visible = navAllowed ? items.filter((i) => i.show) : [];

  return (
    <div className="min-h-dvh">
      <PreviewStrip ctx={ctx} />
      <ContextBar ctx={ctx} signedInAs={signedInAs} />
      <div className="mx-auto flex max-w-[1600px]">
        {/* xl persistent nav; lg icons */}
        <nav aria-label="Dashboard" className="hidden w-14 shrink-0 border-r border-line md:block xl:w-52">
          <ul className="sticky top-16 py-3">
            {visible.map((i) => (
              <li key={i.key}>
                <Link
                  href={i.href}
                  aria-current={i.key === active ? "page" : undefined}
                  className={`block px-3 py-2 text-sm transition-colors ${i.key === active ? "border-l-2 border-primary bg-primary-soft font-semibold text-ink" : "border-l-2 border-transparent text-muted hover:bg-raised hover:text-ink"}`}
                >
                  <span className="xl:hidden font-mono text-xs">{i.short}</span>
                  <span className="hidden xl:inline">{i.label}</span>
                </Link>
              </li>
            ))}
          </ul>
        </nav>
        <div className="min-w-0 flex-1">
          {/* md/sm: top drawer */}
          {visible.length > 0 ? (
          <details className="border-b border-line md:hidden">
            <summary className="cursor-pointer px-4 py-3 text-sm font-bold hover:bg-raised">Menu · {visible.find((i) => i.key === active)?.label ?? "Events"}</summary>
            <ul className="border-t border-line-neutral">
              {visible.map((i) => (
                <li key={i.key}>
                  <Link href={i.href} aria-current={i.key === active ? "page" : undefined} className={`block px-4 py-3 text-sm ${i.key === active ? "bg-primary-soft font-semibold text-primary-ink" : "hover:bg-raised"}`}>
                    {i.label}
                  </Link>
                </li>
              ))}
            </ul>
          </details>
          ) : null}
          <main className="p-4 md:p-6">{children}</main>
        </div>
      </div>
    </div>
  );
}

function PreviewStrip({ ctx }: { ctx: PreviewContext }) {
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
          <PreviewControls ctx={ctx} />
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
function PreviewControls({ ctx }: { ctx: PreviewContext }) {
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
            {PREVIEW_STATES.map((s) => (
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

/** Spec §4.3 — the switchers only list what the user is in. The preview has exactly one of each. */
function ContextBar({ ctx, signedInAs }: { ctx: PreviewContext; signedInAs?: string | null }) {
  return (
    <header className="z-40 border-b border-line bg-bg/95 backdrop-blur md:sticky md:top-9">
      <div className="mx-auto flex max-w-[1600px] flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2">
        <span className="font-bold tracking-widest">SNATCH IT</span>
        <span className="eyebrow text-dim">Venue dashboard</span>
        {ctx.source === "database" ? <DatabaseScope ctx={ctx} /> : <FixtureSwitchers ctx={ctx} />}
        {ctx.source === "database" ? (
          signedInAs ? (
            <form method="post" action="/logout" className="flex items-center gap-2 text-xs">
              <span className="text-muted">{signedInAs}</span>
              <button className="btn btn-ghost btn-sm" type="submit">
                Sign out
              </button>
            </form>
          ) : (
            <Link className="btn btn-ghost btn-sm" href="/login">
              Sign in
            </Link>
          )
        ) : null}
      </div>
    </header>
  );
}

/** Fixture mode: the sample organization and venue switchers. */
function FixtureSwitchers({ ctx }: { ctx: PreviewContext }) {
  return (
    <>
      <label className="ml-auto flex min-w-0 max-w-full items-center gap-1 text-xs text-muted">
        Organization
        <select className="field !w-auto !py-0.5 text-xs" defaultValue={ORG.orgId} aria-label="Organization">
          <option value={ORG.orgId}>{ORG.displayName}</option>
        </select>
      </label>
      <label className="flex min-w-0 max-w-full items-center gap-1 text-xs text-muted">
        Venue
        <select className="field !w-auto !py-0.5 text-xs" defaultValue={VENUE.venueId} aria-label="Venue">
          <option value={VENUE.venueId}>{VENUE.name}</option>
        </select>
      </label>
      <span className="text-xs text-dim">
        {PRINCIPAL_LABEL[ctx.role]} · {VENUE.timeZone}
      </span>
    </>
  );
}

/**
 * Database mode: no sample names. Organization/venue names are not read in this slice,
 * so the route's own ids are shown, plus the verified role (or none).
 */
function DatabaseScope({ ctx }: { ctx: PreviewContext }) {
  return (
    <span className="ml-auto flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
      {ctx.scope ? (
        <>
          <span title={ctx.scope.orgId}>
            Organization <code className="font-mono text-xs">{ctx.scope.orgId.slice(0, 8)}</code>
          </span>
          <span title={ctx.scope.venueId}>
            Venue <code className="font-mono text-xs">{ctx.scope.venueId.slice(0, 8)}</code>
          </span>
        </>
      ) : null}
      <span className="text-dim">{ctx.verifiedRole ? PRINCIPAL_LABEL[ctx.role] : "No role"}</span>
    </span>
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
