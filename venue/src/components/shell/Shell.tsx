import Link from "next/link";
import type { ReactNode } from "react";
import { ORG, VENUE } from "@/fixtures/venue";
import { PREVIEW_STATES, withPreview, type PreviewContext } from "@/lib/preview";
import { sourceInfo } from "@/lib/source";
import { PREVIEW_PRINCIPALS, PRINCIPAL_LABEL } from "@/lib/roles";
import { canReadDoor, canReadEvents, canReadTicketTypes, rosterClasses, canManualLookup } from "@/lib/roles";

export type NavEvent = { eventId: string; title: string } | null;

/**
 * Spec §3.2 — xl: persistent left nav · lg: icon nav · md/sm: top drawer.
 * The "Preview data" strip is sticky and not dismissible on any breakpoint.
 */
export function Shell({ ctx, event, active, children, signedInAs }: { ctx: PreviewContext; event: NavEvent; active: "events" | "setup" | "inventory" | "attendees" | "door"; children: ReactNode; signedInAs?: string | null }) {
  const base = `/o/${ORG.orgId}/v/${VENUE.venueId}`;
  const evBase = event ? `${base}/events/${event.eventId}` : null;
  const items: { key: typeof active; label: string; short: string; href: string; show: boolean }[] = [
    { key: "events", label: "Events", short: "EV", href: withPreview(`${base}/events`, ctx), show: canReadEvents(ctx.role) },
    { key: "setup", label: "Event setup", short: "SET", href: evBase ? withPreview(evBase, ctx) : "", show: !!evBase && canReadEvents(ctx.role) },
    { key: "inventory", label: "Inventory", short: "INV", href: evBase ? withPreview(`${evBase}/inventory`, ctx) : "", show: !!evBase && canReadTicketTypes(ctx.role) },
    { key: "attendees", label: "Attendees", short: "ATT", href: evBase ? withPreview(`${evBase}/attendees`, ctx) : "", show: !!evBase && (rosterClasses(ctx.role) !== null || canManualLookup(ctx.role)) },
    { key: "door", label: "Door", short: "DR", href: evBase ? withPreview(`${evBase}/door`, ctx) : "", show: !!evBase && canReadDoor(ctx.role) },
  ];
  const visible = items.filter((i) => i.show);

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
                  className={`block px-3 py-2 text-sm ${i.key === active ? "border-l-2 border-primary text-ink" : "text-muted hover:text-ink"}`}
                >
                  <span className="xl:hidden font-mono text-[11px]">{i.short}</span>
                  <span className="hidden xl:inline">{i.label}</span>
                </Link>
              </li>
            ))}
          </ul>
        </nav>
        <div className="min-w-0 flex-1">
          {/* md/sm: top drawer */}
          <details className="border-b border-line md:hidden">
            <summary className="cursor-pointer px-4 py-3 text-sm font-bold uppercase tracking-wider">Menu · {visible.find((i) => i.key === active)?.label ?? "Events"}</summary>
            <ul className="border-t border-line-neutral">
              {visible.map((i) => (
                <li key={i.key}>
                  <Link href={i.href} className={`block px-4 py-3 text-sm ${i.key === active ? "text-primary" : ""}`}>
                    {i.label}
                  </Link>
                </li>
              ))}
            </ul>
          </details>
          <main className="p-4 md:p-6">{children}</main>
        </div>
      </div>
    </div>
  );
}

function PreviewStrip({ ctx }: { ctx: PreviewContext }) {
  const info = sourceInfo();
  return (
    <div className={`preview-banner px-3 py-1.5 ${info.source === "database" ? "preview-banner-db" : ""}`} role="status" aria-live="polite">
      <div className="mx-auto flex max-w-[1600px] flex-wrap items-center justify-between gap-2">
        <span>◆ {info.label}</span>
        <PreviewControls ctx={ctx} />
      </div>
    </div>
  );
}

/** Role and state switchers — GET form so every surface is linkable in a given persona/state. */
function PreviewControls({ ctx }: { ctx: PreviewContext }) {
  return (
    <form method="get" className="flex flex-wrap items-center gap-2 text-[11px] normal-case tracking-normal">
      <label className="flex items-center gap-1">
        {ctx.source === "database" ? "Display as" : "Viewing as"}
        <select name="role" defaultValue={ctx.role} className="border border-black/40 bg-black/80 px-1 py-0.5 text-white">
          {PREVIEW_PRINCIPALS.map((p) => (
            <option key={p} value={p}>
              {PRINCIPAL_LABEL[p]}
            </option>
          ))}
        </select>
      </label>
      <label className="flex items-center gap-1">
        State
        <select name="state" defaultValue={ctx.state} className="border border-black/40 bg-black/80 px-1 py-0.5 text-white">
          {PREVIEW_STATES.map((s) => (
            <option key={s} value={s}>
              {s === "nodata" ? "no matches" : s}
            </option>
          ))}
        </select>
      </label>
      <button className="border border-black/60 bg-black px-2 py-0.5 font-bold text-white" type="submit">
        Apply
      </button>
    </form>
  );
}

/** Spec §4.3 — the switchers only list what the user is in. The preview has exactly one of each. */
function ContextBar({ ctx, signedInAs }: { ctx: PreviewContext; signedInAs?: string | null }) {
  return (
    <header className="sticky top-8 z-40 border-b border-line bg-bg/95 backdrop-blur">
      <div className="mx-auto flex max-w-[1600px] flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2">
        <span className="font-bold tracking-widest">SNATCH IT</span>
        <span className="eyebrow text-dim">Venue dashboard</span>
        <label className="ml-auto flex items-center gap-1 text-xs text-muted">
          Organization
          <select className="field !w-auto !py-0.5 text-xs" defaultValue={ORG.orgId} aria-label="Organization">
            <option value={ORG.orgId}>{ORG.displayName}</option>
          </select>
        </label>
        <label className="flex items-center gap-1 text-xs text-muted">
          Venue
          <select className="field !w-auto !py-0.5 text-xs" defaultValue={VENUE.venueId} aria-label="Venue">
            <option value={VENUE.venueId}>{VENUE.name}</option>
          </select>
        </label>
        <span className="text-xs text-dim">
          {PRINCIPAL_LABEL[ctx.role]} · {VENUE.timeZone}
        </span>
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

/** Rendered after any preview "action" form submits with ?did=… */
export function PreviewOutcome({ did }: { did: string | undefined }) {
  if (!did) return null;
  return (
    <p className="mb-4 border border-warning bg-warning/10 px-3 py-2 text-sm" role="status">
      <strong>Preview only.</strong> The real dashboard would call <code className="font-mono">{did}</code> here. Nothing was saved and no backend was contacted.
    </p>
  );
}
