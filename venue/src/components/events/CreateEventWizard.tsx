"use client";

import { useState } from "react";
import { Button } from "@astryxdesign/core/Button";
import { withPreview, type PreviewContext } from "@/lib/preview";
import { PreviewHidden } from "@/components/events/EventSetup";

/** Sample editor: one reviewable draft, never a real event or ticket write. */
export function CreateEventWizard({ ctx, basePath, step, venueApproved, venueName }: { ctx: PreviewContext; basePath: string; step: 1 | 2 | 3 | 4; venueApproved: boolean; venueName: string }) {
  const [preview, setPreview] = useState(false);
  const [title, setTitle] = useState("");
  const [starts, setStarts] = useState("");
  return <div className="space-y-6">
    <header className="flex flex-wrap items-end justify-between gap-4"><div><p className="eyebrow-caps">{venueName}</p><h1 className="title-page mt-3">New event</h1><p className="mt-3 text-muted">Start with the essentials. Save a private draft, then add tickets and publish when you are ready.</p></div><a className="btn btn-ghost" href={withPreview(`${basePath}/events`, ctx)}>Back to events</a></header>
    {!venueApproved ? <p className="panel px-5 py-4 text-sm text-warning">This venue needs Snatch It approval before it can sell tickets.</p> : step === 4 ? <section className="panel p-6"><h2 className="serif text-2xl">Draft preview complete</h2><p className="mt-3 text-sm text-muted">This demo saved nothing. In your venue workspace, saving creates a private draft where you can add details, tickets and availability.</p><a className="btn btn-ghost mt-4" href={withPreview(`${basePath}/events`, ctx)}>Back to events</a></section> : <div className="grid items-start gap-6 xl:grid-cols-[minmax(0,1fr)_20rem]">
      <form method="get" action={`${basePath}/events/new`} className="panel space-y-5 px-5 py-6 md:px-7">
        <PreviewHidden ctx={ctx} /><input type="hidden" name="step" value="4" /><input type="hidden" name="did" value="catalog.create_event" />
        <h2 className="serif text-3xl">Make it a night to remember.</h2>
        <Field label="Event name" name="title" required placeholder="Give your event a name" onChange={setTitle} />
        <Field label="Venue" name="venue" value={venueName} readOnly />
        <fieldset className="grid gap-4 border-t border-line pt-3 sm:grid-cols-2"><legend className="py-3 font-semibold">Date and time</legend>
          <Field label="Event starts" name="starts_at" type="datetime-local" required onChange={setStarts} />
          <Field label="Event ends (optional)" name="ends_at" type="datetime-local" />
          <Field label="Doors open (optional)" name="doors_at" type="datetime-local" />
          <Field label="Name for this night (optional)" name="label" placeholder="Friday night" />
        </fieldset>
        <p className="text-sm text-muted">Your draft stays private and cannot sell tickets. Add tickets and set availability after saving.</p>
        <p className="text-xs text-muted">Demo — sample data. Nothing will be saved.</p>
        <Button label="Save draft (demo)" type="submit" variant="primary" size="lg" className="min-h-11" />
      </form>
      <aside className="panel px-5 py-6"><p className="eyebrow-caps">Your event</p><div className="mt-4"><Button label={preview ? "Close preview" : "Preview draft"} clickAction={() => setPreview(!preview)} /></div>
        {preview ? <div className="mt-4 space-y-3 rounded-xl border border-line p-4"><p className="text-xs text-muted">Unsaved preview · only visible to you</p><h2 className="serif break-words text-2xl">{title || "Your event name"}</h2><p className="text-sm">{starts ? starts.replace("T", " · ") : "Date and time to be added"}</p><p className="text-sm text-muted">{venueName}</p></div> : null}
        <ol className="mt-6 space-y-4 border-t border-line pt-5 text-sm"><li><strong>1. Save draft</strong><p className="mt-1 text-muted">Start with a name and date.</p></li><li><strong>2. Add tickets</strong><p className="mt-1 text-muted">Set ticket types, prices and availability.</p></li><li><strong>3. Publish event</strong><p className="mt-1 text-muted">Announce your event when it is ready. Opening sales is a separate step.</p></li></ol>
      </aside>
    </div>}
  </div>;
}

function Field({ label, name, type = "text", required, placeholder, value, readOnly, onChange }: { label: string; name: string; type?: string; required?: boolean; placeholder?: string; value?: string; readOnly?: boolean; onChange?: (value: string) => void }) {
  return <label className="block text-sm"><span className="eyebrow block text-dim">{label}{required ? " *" : ""}</span><input className="field mt-1" name={name} type={type} required={required} placeholder={placeholder} defaultValue={value} readOnly={readOnly} onChange={onChange ? (event) => onChange(event.target.value) : undefined} /></label>;
}
