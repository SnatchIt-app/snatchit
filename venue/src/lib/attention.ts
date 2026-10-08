/**
 * What the frame needs on every page: how many things need the manager now
 * (the bell), and which event the rail's Tickets / Guests / Check-in point at
 * when the page itself is not about one event.
 *
 * Fixture mode only. Database mode has no contracted read for these signals
 * (see the overview's NotWiredState), so the frame shows neither rather than
 * sample numbers beside real ones.
 */
import { listBatches, listDevices, listEvents, listFlags, listHolds, listTicketTypes, tonightSessions } from "@/lib/data";
import { PREVIEW_NOW } from "@/fixtures/venue";
import { withPreview, type PreviewContext } from "@/lib/preview";
import { canReadEvents } from "@/lib/roles";
import { buildSignals, eventStage } from "@/lib/signals";

export type FrameAttention = { count: number; stageEvent: { eventId: string; title: string } | null };

export function frameAttention(ctx: PreviewContext, basePath: string): FrameAttention | null {
  if (ctx.source === "database" || ctx.state !== "live" || !canReadEvents(ctx.role)) return null;
  const events = listEvents("live");
  const types = events.flatMap((e) => listTicketTypes("live", e.eventId));
  const batches = events.flatMap((e) => listBatches("live", e.eventId));
  const holds = events.flatMap((e) => listHolds("live", e.eventId));
  const devices = listDevices("live");
  const tonight = tonightSessions(PREVIEW_NOW);
  const flags = tonight.length > 0 ? listFlags("live", tonight[0].session.sessionId) : [];
  const { signals } = buildSignals({ events, types, batches, holds, devices, flags, tonight, now: PREVIEW_NOW, basePath, link: (h) => withPreview(h, ctx) });
  const stage = eventStage(events, tonight, PREVIEW_NOW);
  return {
    count: signals.filter((s) => s.severity !== "worth_knowing").length,
    stageEvent: stage.event ? { eventId: stage.event.eventId, title: stage.event.title } : null,
  };
}
