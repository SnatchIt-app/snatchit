import { withPreview, type PreviewContext } from "@/lib/preview";
import { AuditNote, Panel } from "@/components/ui/Bits";
import { PreviewHidden } from "@/components/events/EventSetup";

/**
 * Spec §7.2 — three steps, ends in `draft`:
 *  1 Basics → catalog.create_event (auto-creates the first session)
 *  2 First ticket type → venue.create_ticket_type
 *  3 First inventory release → venue.create_inventory_batch
 * Precondition surfaced at step 1: the venue must be approved.
 */
export function CreateEventWizard({ ctx, basePath, step, venueApproved, venueName }: { ctx: PreviewContext; basePath: string; step: 1 | 2 | 3 | 4; venueApproved: boolean; venueName: string }) {
  const self = `${basePath}/events/new`;
  const steps = ["Basics", "First ticket type", "First inventory release"];
  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <header>
        <p className="eyebrow text-dim">Create event</p>
        <h1 className="text-2xl font-bold">New event</h1>
        <ol className="mt-3 flex gap-2 text-xs">
          {steps.map((s, i) => (
            <li key={s} className={`border px-2 py-1 ${i + 1 === step ? "border-primary text-primary" : i + 1 < step ? "border-success text-success" : "border-line-neutral text-dim"}`}>
              {i + 1}. {s}
            </li>
          ))}
        </ol>
      </header>

      {!venueApproved ? (
        <p className="border border-warning bg-warning/10 px-3 py-2 text-sm text-warning">This venue isn&apos;t approved to sell yet. Snatch It has to approve it first.</p>
      ) : step === 1 ? (
        <Panel title="Basics" eyebrow="Step 1 of 3">
          <form method="get" action={withPreview(self, ctx)} className="space-y-3">
            <input type="hidden" name="step" value="2" />
            <input type="hidden" name="did" value="catalog.create_event" />
            <PreviewHidden ctx={ctx} />
            <Field label="Title" name="title" required placeholder="Saturday Music Night" />
            <Field label="Venue" name="venue" value={venueName} readOnly />
            <Field label="First session starts" name="starts_at" type="datetime-local" required />
            <Field label="Doors (optional)" name="doors_at" type="datetime-local" />
            <Field label="Session label (optional)" name="label" placeholder="Friday" />
            <AuditNote rpc="catalog.create_event" />
            <button className="btn btn-primary" type="submit">
              Continue
            </button>
          </form>
        </Panel>
      ) : step === 2 ? (
        <Panel title="First ticket type" eyebrow="Step 2 of 3">
          <p className="mb-3 text-sm text-muted">Publishing requires at least one ticket type with a release. Doing it later is allowed; doing it never means the event can never go on sale.</p>
          <form method="get" action={withPreview(self, ctx)} className="space-y-3">
            <input type="hidden" name="step" value="3" />
            <input type="hidden" name="did" value="venue.create_ticket_type" />
            <PreviewHidden ctx={ctx} />
            <label className="block text-sm">
              Kind
              <select name="kind" className="field mt-1" defaultValue="admission">
                <option value="admission">Admission</option>
                <option value="table">Table (deposit)</option>
              </select>
            </label>
            <Field label="Name (unique per event)" name="name" required placeholder="General admission" />
            <Field label="Price (USD)" name="price" type="number" required placeholder="25.00" />
            <label className="block text-sm">
              Visibility
              <select name="visibility" className="field mt-1" defaultValue="public">
                <option value="public">Public</option>
                <option value="hidden">Hidden</option>
                <option value="door_only">Door only</option>
              </select>
            </label>
            <AuditNote rpc="venue.create_ticket_type" />
            <button className="btn btn-primary" type="submit">
              Continue
            </button>
          </form>
        </Panel>
      ) : step === 3 ? (
        <Panel title="First inventory release" eyebrow="Step 3 of 3">
          <form method="get" action={withPreview(self, ctx)} className="space-y-3">
            <input type="hidden" name="step" value="4" />
            <input type="hidden" name="did" value="venue.create_inventory_batch" />
            <PreviewHidden ctx={ctx} />
            <label className="block text-sm">
              Release
              <select name="release_kind" className="field mt-1" defaultValue="public_sale">
                <option value="public_sale">Public sale</option>
                <option value="presale">Presale</option>
                <option value="promoter_hold">Promoter hold</option>
                <option value="comp">Comps</option>
                <option value="door">Door</option>
              </select>
            </label>
            <Field label="Capacity" name="capacity" type="number" required placeholder="300" />
            <p className="text-xs text-dim">Capacity is per session. There is no event-level capacity number anywhere in this product.</p>
            <AuditNote rpc="venue.create_inventory_batch" />
            <button className="btn btn-primary" type="submit">
              Create draft
            </button>
          </form>
        </Panel>
      ) : (
        <Panel title="Draft created (preview)" eyebrow="Done">
          <p className="text-sm">In the real dashboard you would now be on the new event&apos;s setup page in <strong>Draft</strong>. This preview saved nothing.</p>
          <a className="btn btn-ghost btn-sm mt-3" href={withPreview(`${basePath}/events`, ctx)}>
            Back to events
          </a>
        </Panel>
      )}
    </div>
  );
}

function Field({ label, name, type = "text", required, placeholder, value, readOnly }: { label: string; name: string; type?: string; required?: boolean; placeholder?: string; value?: string; readOnly?: boolean }) {
  return (
    <label className="block text-sm">
      {label}
      {required ? " *" : ""}
      <input className="field mt-1" name={name} type={type} required={required} placeholder={placeholder} defaultValue={value} readOnly={readOnly} />
    </label>
  );
}
