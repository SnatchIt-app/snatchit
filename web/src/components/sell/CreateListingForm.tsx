"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import {
  CATEGORIES,
  CATEGORY_LABELS,
  NEIGHBORHOOD_GROUPS,
  PLATFORM_INSTRUCTIONS,
  APP_CONFIG,
} from "@snatchit/core";
import { createListingAction, uploadListingImageAction } from "@/lib/create-listing-actions";
import { findBannedTerm } from "@/lib/content-moderation";
import { Field } from "@/components/ui/Field";
import { Input, Select, Textarea } from "@/components/ui/Input";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";

const DURATION_OPTIONS = [1, 3, 6, 12, 24, 48] as const;
const TICKET_PLATFORMS = Object.values(PLATFORM_INSTRUCTIONS);

const RISK_MESSAGES: Record<string, string> = {
  high_risk_warning:
    "Your account has flagged activity — you can still list, but it may be reviewed more closely.",
  medium_risk_warning: "Heads up: recent account activity may lead to extra review on this listing.",
};

function durationLabel(hours: number): string {
  return hours < 24 ? `${hours}h` : `${hours / 24}d`;
}

type ImageState = {
  previewUrl: string | null;
  path: string | null;
  uploading: boolean;
  error: string | null;
};

const EMPTY_IMAGE: ImageState = { previewUrl: null, path: null, uploading: false, error: null };

export function CreateListingForm({ riskWarning }: { riskWarning: string | null }) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();

  const [eventName, setEventName] = useState("");
  const [venue, setVenue] = useState("");
  const [category, setCategory] = useState<string>("nightlife");
  const [neighborhood, setNeighborhood] = useState("");
  const [eventDate, setEventDate] = useState("");
  const [eventTime, setEventTime] = useState("");
  const [ticketType, setTicketType] = useState<"GA" | "VIP" | "">("");
  const [quantity, setQuantity] = useState(1);
  const [ticketPlatform, setTicketPlatform] = useState("other");
  const [transferMethod, setTransferMethod] = useState<"mobile_transfer" | "email" | "">("");
  const [restrictions, setRestrictions] = useState("");
  const [startingBid, setStartingBid] = useState("");
  const [buyNowEnabled, setBuyNowEnabled] = useState(false);
  const [buyNowPrice, setBuyNowPrice] = useState("");
  const [durationHours, setDurationHours] = useState<number | null>(null);
  const [commitmentAccepted, setCommitmentAccepted] = useState(false);

  const [cover, setCover] = useState<ImageState>(EMPTY_IMAGE);
  const [proof, setProof] = useState<ImageState>(EMPTY_IMAGE);

  const [attemptedSubmit, setAttemptedSubmit] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [minDate] = useState(() => new Date().toISOString().slice(0, 10));

  const startingBidNum = Number(startingBid);
  const buyNowPriceNum = Number(buyNowPrice);

  function validate(): string[] {
    const errors: string[] = [];
    if (!eventName.trim()) errors.push("Event name is required.");
    if (!venue.trim()) errors.push("Venue is required.");
    if (!neighborhood) errors.push("Choose a neighborhood.");
    if (!eventDate) errors.push("Event date is required.");
    if (!eventTime) errors.push("Event time is required.");
    if (!ticketType) errors.push("Choose a ticket type.");
    if (!transferMethod) errors.push("Choose a transfer method.");
    if (!Number.isInteger(startingBidNum) || startingBidNum < 1) errors.push("Starting bid must be at least $1.");
    if (startingBidNum > 25000) errors.push("Starting bid can't exceed $25,000.");
    if (buyNowEnabled) {
      if (!Number.isInteger(buyNowPriceNum) || buyNowPriceNum <= startingBidNum) {
        errors.push("Buy Now price must be a whole number greater than the starting bid.");
      }
      if (buyNowPriceNum > 25000) errors.push("Buy Now price can't exceed $25,000.");
    }
    if (!durationHours) errors.push("Choose how long the listing runs.");
    if (!cover.path) errors.push("Upload a cover photo.");
    if (!proof.path) errors.push("Upload proof of ownership.");
    if (!commitmentAccepted) errors.push("Confirm the seller commitment to continue.");

    const flagged = findBannedTerm(`${eventName} ${venue} ${restrictions}`);
    if (flagged) errors.push("Listing details can't mention prohibited content — please rephrase.");

    return errors;
  }

  const errors = validate();

  function handleImagePick(kind: "cover" | "proof", file: File | undefined) {
    if (!file) return;
    const setState = kind === "cover" ? setCover : setProof;
    const previewUrl = URL.createObjectURL(file);
    setState({ previewUrl, path: null, uploading: true, error: null });
    startTransition(async () => {
      const result = await uploadListingImageAction(kind, file);
      if (result.error) {
        setState({ previewUrl, path: null, uploading: false, error: result.error });
        return;
      }
      setState({ previewUrl, path: result.path ?? null, uploading: false, error: null });
    });
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setAttemptedSubmit(true);
    setFormError(null);
    if (errors.length > 0) return;

    startTransition(async () => {
      const result = await createListingAction({
        eventName,
        venue,
        neighborhood,
        category,
        eventDate,
        eventTime: `${eventTime}:00`,
        ticketType,
        quantity,
        transferMethod,
        restrictions: restrictions.trim() || null,
        startingBid: startingBidNum,
        buyNowEnabled,
        buyNowPrice: buyNowEnabled ? buyNowPriceNum : null,
        durationHours: durationHours!,
        ticketPlatform,
        coverImagePath: cover.path!,
        proofImagePath: proof.path!,
        sellerCommitmentAccepted: commitmentAccepted,
      });
      if (result.error === "AUTH_REQUIRED") {
        router.push("/login?next=/sell");
        return;
      }
      if (result.error) {
        setFormError(result.error);
        return;
      }
      router.push(`/listing/${result.id}`);
    });
  }

  return (
    <form onSubmit={handleSubmit} noValidate className="mt-8 space-y-10">
      {riskWarning ? <Alert tone="error">{RISK_MESSAGES[riskWarning] ?? riskWarning}</Alert> : null}
      {formError ? <Alert tone="error">{formError}</Alert> : null}
      {attemptedSubmit && errors.length > 0 ? (
        <Alert tone="error">
          <ul className="list-disc space-y-1 pl-4">
            {errors.map((err) => (
              <li key={err}>{err}</li>
            ))}
          </ul>
        </Alert>
      ) : null}

      <section className="space-y-5">
        <p className="eyebrow text-primary/80">Event details</p>
        <Field label="Event name" htmlFor="eventName">
          <Input id="eventName" value={eventName} onChange={(e) => setEventName(e.target.value)} maxLength={120} required />
        </Field>
        <Field label="Venue" htmlFor="venue">
          <Input id="venue" value={venue} onChange={(e) => setVenue(e.target.value)} maxLength={120} required />
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Category" htmlFor="category">
            <Select id="category" value={category} onChange={(e) => setCategory(e.target.value)}>
              {CATEGORIES.map((c) => (
                <option key={c} value={c}>
                  {CATEGORY_LABELS[c]}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Neighborhood" htmlFor="neighborhood">
            <Select id="neighborhood" value={neighborhood} onChange={(e) => setNeighborhood(e.target.value)}>
              <option value="">Select…</option>
              {NEIGHBORHOOD_GROUPS.map((group) => (
                <optgroup key={group.title} label={group.title}>
                  {group.items.map((n) => (
                    <option key={n} value={n}>
                      {n.replace(/\b\w/g, (c) => c.toUpperCase())}
                    </option>
                  ))}
                </optgroup>
              ))}
            </Select>
          </Field>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Event date" htmlFor="eventDate">
            <Input id="eventDate" type="date" min={minDate} value={eventDate} onChange={(e) => setEventDate(e.target.value)} required />
          </Field>
          <Field label="Event time" htmlFor="eventTime">
            <Input id="eventTime" type="time" value={eventTime} onChange={(e) => setEventTime(e.target.value)} required />
          </Field>
        </div>
      </section>

      <section className="space-y-5 border-t border-primary/15 pt-8">
        <p className="eyebrow text-primary/80">Ticket info</p>
        <Field label="Ticket type" htmlFor="ticketType">
          <div className="flex gap-3">
            {(["GA", "VIP"] as const).map((t) => (
              <RadioPill key={t} selected={ticketType === t} onClick={() => setTicketType(t)}>
                {t}
              </RadioPill>
            ))}
          </div>
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Quantity" htmlFor="quantity">
            <Input
              id="quantity"
              type="number"
              min={1}
              step={1}
              value={quantity}
              onChange={(e) => setQuantity(Math.max(1, Number(e.target.value) || 1))}
            />
          </Field>
          <Field label="Ticket platform" htmlFor="ticketPlatform">
            <Select id="ticketPlatform" value={ticketPlatform} onChange={(e) => setTicketPlatform(e.target.value)}>
              {TICKET_PLATFORMS.map((p) => (
                <option key={p.platform} value={p.platform}>
                  {p.displayName}
                </option>
              ))}
            </Select>
          </Field>
        </div>
        <Field label="Transfer method" htmlFor="transferMethod">
          <div className="flex gap-3">
            <RadioPill selected={transferMethod === "mobile_transfer"} onClick={() => setTransferMethod("mobile_transfer")}>
              Mobile transfer
            </RadioPill>
            <RadioPill selected={transferMethod === "email"} onClick={() => setTransferMethod("email")}>
              Email
            </RadioPill>
          </div>
        </Field>
        <Field label="Restrictions" htmlFor="restrictions" hint="Optional — age limits, dress code, etc.">
          <Textarea id="restrictions" value={restrictions} onChange={(e) => setRestrictions(e.target.value)} maxLength={500} />
        </Field>
      </section>

      <section className="space-y-5 border-t border-primary/15 pt-8">
        <p className="eyebrow text-primary/80">Pricing</p>
        <Field label="Starting bid ($)" htmlFor="startingBid">
          <Input id="startingBid" type="number" min={1} max={25000} step={1} value={startingBid} onChange={(e) => setStartingBid(e.target.value)} required />
        </Field>
        <label className="flex items-center gap-3 text-[13.5px] text-white/80">
          <input
            type="checkbox"
            checked={buyNowEnabled}
            onChange={(e) => setBuyNowEnabled(e.target.checked)}
            className="size-4 accent-primary"
          />
          Also allow Buy Now
        </label>
        {buyNowEnabled ? (
          <Field label="Buy Now price ($)" htmlFor="buyNowPrice">
            <Input
              id="buyNowPrice"
              type="number"
              min={1}
              max={25000}
              step={1}
              value={buyNowPrice}
              onChange={(e) => setBuyNowPrice(e.target.value)}
            />
          </Field>
        ) : null}
        <Field label="Listing duration" htmlFor="duration">
          <div className="flex flex-wrap gap-2">
            {DURATION_OPTIONS.map((h) => (
              <RadioPill key={h} selected={durationHours === h} onClick={() => setDurationHours(h)}>
                {durationLabel(h)}
              </RadioPill>
            ))}
          </div>
        </Field>
      </section>

      <section className="space-y-5 border-t border-primary/15 pt-8">
        <p className="eyebrow text-primary/80">Media</p>
        <div className="grid grid-cols-2 gap-4">
          <ImageUploadTile
            label="Cover photo"
            hint={`Up to ${APP_CONFIG.MAX_IMAGE_SIZE_MB}MB`}
            state={cover}
            onPick={(file) => handleImagePick("cover", file)}
          />
          <ImageUploadTile
            label="Proof of ownership"
            hint="Screenshot of your ticket"
            state={proof}
            onPick={(file) => handleImagePick("proof", file)}
          />
        </div>
      </section>

      <section className="space-y-4 border-t border-primary/15 pt-8">
        <p className="eyebrow text-primary/80">Seller commitment</p>
        <label className="flex items-start gap-3 text-[13.5px] leading-relaxed text-white/80">
          <input
            type="checkbox"
            checked={commitmentAccepted}
            onChange={(e) => setCommitmentAccepted(e.target.checked)}
            className="mt-0.5 size-4 shrink-0 accent-primary"
          />
          I confirm I own these tickets and will transfer them to the buyer through the
          official platform transfer within the required window after the sale.
        </label>
      </section>

      <Button type="submit" variant="primary" size="lg" className="w-full" disabled={isPending || cover.uploading || proof.uploading}>
        {isPending ? "Publishing…" : "Publish listing"}
      </Button>
    </form>
  );
}

function RadioPill({
  selected,
  onClick,
  children,
}: {
  selected: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`border px-4 py-2 text-[13px] font-semibold transition-colors ${
        selected ? "border-primary bg-primary/[0.12] text-primary" : "border-white/15 text-white/70 hover:border-white/30"
      }`}
    >
      {children}
    </button>
  );
}

function ImageUploadTile({
  label,
  hint,
  state,
  onPick,
}: {
  label: string;
  hint: string;
  state: ImageState;
  onPick: (file: File | undefined) => void;
}) {
  return (
    <div>
      <p className="mb-2.5 text-[10px] font-medium uppercase tracking-[0.25em] text-white/50">{label}</p>
      <label className="flex aspect-square cursor-pointer flex-col items-center justify-center gap-2 border border-dashed border-white/20 bg-white/[0.02] p-3 text-center transition-colors hover:border-primary/40">
        {state.previewUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- local object URL preview, not a remote asset
          <img src={state.previewUrl} alt="" className="size-full object-cover" />
        ) : (
          <span className="text-[12px] text-white/40">{hint}</span>
        )}
        <input
          type="file"
          accept="image/jpeg,image/png,image/webp,image/heic"
          aria-label={label}
          // sr-only, not `hidden`: `hidden` removes the input from the tab order
          // entirely, so keyboard-only users could not reach either required
          // upload and therefore could not list a ticket at all.
          className="sr-only"
          onChange={(e) => onPick(e.target.files?.[0])}
        />
      </label>
      {state.uploading ? <p className="mt-2 text-[12px] text-white/50">Uploading…</p> : null}
      {state.error ? <p className="mt-2 text-[12px] font-medium text-primary">{state.error}</p> : null}
      {state.path && !state.uploading ? <p className="mt-2 text-[12px] text-white/50">✓ Uploaded</p> : null}
    </div>
  );
}
