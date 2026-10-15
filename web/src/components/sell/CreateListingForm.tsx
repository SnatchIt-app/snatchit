"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import {
  CATEGORIES,
  CATEGORY_LABELS,
  NEIGHBORHOOD_GROUPS,
  PLATFORM_INSTRUCTIONS,
  APP_CONFIG,
  allInFromDollars,
} from "@snatchit/core";
import { createListingAction, uploadListingImageAction } from "@/lib/create-listing-actions";
import { findBannedTerm } from "@/lib/content-moderation";
import { LISTING_DURATION_HOURS, durationLabel } from "@/lib/listing-durations";
import { prohibitedContentMessage } from "@/lib/server-refusal";
import { Field } from "@/components/ui/Field";
import { Input, Select, Textarea } from "@/components/ui/Input";
import { Button } from "@/components/ui/Button";
import { Alert } from "@/components/ui/Alert";
import { Icon } from "@/components/ui/Icon";

const TICKET_PLATFORMS = Object.values(PLATFORM_INSTRUCTIONS);

const RISK_MESSAGES: Record<string, string> = {
  high_risk_warning:
    "Your account has flagged activity — you can still list, but it may be reviewed more closely.",
  medium_risk_warning: "Heads up: recent account activity may lead to extra review on this listing.",
};

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

    const flagged = findBannedTerm([eventName, venue, restrictions]);
    if (flagged) errors.push(prohibitedContentMessage(flagged));

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
    <form onSubmit={handleSubmit} noValidate className="mt-8 space-y-9">
      {riskWarning ? <Alert tone="warning">{RISK_MESSAGES[riskWarning] ?? riskWarning}</Alert> : null}
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

      <section className="space-y-6">
        <SectionLabel>Event details</SectionLabel>
        <Field label="Event name" htmlFor="eventName">
          <Input id="eventName" value={eventName} onChange={(e) => setEventName(e.target.value)} maxLength={120} required />
        </Field>
        <Field label="Venue" htmlFor="venue">
          <Input id="venue" value={venue} onChange={(e) => setVenue(e.target.value)} maxLength={120} required />
        </Field>
        <div className="grid gap-6 sm:grid-cols-2 sm:gap-5">
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
        <div className="grid grid-cols-2 gap-5">
          <Field label="Event date" htmlFor="eventDate">
            <Input id="eventDate" type="date" min={minDate} value={eventDate} onChange={(e) => setEventDate(e.target.value)} required />
          </Field>
          <Field label="Event time" htmlFor="eventTime">
            <Input id="eventTime" type="time" value={eventTime} onChange={(e) => setEventTime(e.target.value)} required />
          </Field>
        </div>
      </section>

      <section className="space-y-6">
        <SectionLabel>Ticket info</SectionLabel>
        <Field label="Ticket type">
          <div className="mt-2.5 flex gap-2" role="radiogroup" aria-label="Ticket type">
            {(["GA", "VIP"] as const).map((t) => (
              <RadioPill key={t} selected={ticketType === t} onClick={() => setTicketType(t)}>
                {t}
              </RadioPill>
            ))}
          </div>
        </Field>
        <div className="grid gap-6 sm:grid-cols-2 sm:gap-5">
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
        <Field label="Transfer method">
          <div className="mt-2.5 flex flex-wrap gap-2" role="radiogroup" aria-label="Transfer method">
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

      <section className="space-y-6">
        <SectionLabel>Pricing</SectionLabel>
        <Field
          label="Starting bid ($)"
          htmlFor="startingBid"
          hint={Number.isInteger(startingBidNum) && startingBidNum >= 1 ? `Buyers pay from ${allInFromDollars(startingBidNum)}` : undefined}
        >
          <Input id="startingBid" type="number" min={1} max={25000} step={1} value={startingBid} onChange={(e) => setStartingBid(e.target.value)} required />
        </Field>
        <label className="flex min-h-11 cursor-pointer items-center gap-3 text-[15px] text-ink">
          <input
            type="checkbox"
            checked={buyNowEnabled}
            onChange={(e) => setBuyNowEnabled(e.target.checked)}
            className="size-5 accent-brand"
          />
          Also allow Buy Now
        </label>
        {buyNowEnabled ? (
          <Field
            label="Buy Now price ($)"
            htmlFor="buyNowPrice"
            hint={Number.isInteger(buyNowPriceNum) && buyNowPriceNum >= 1 ? `Buyers pay ${allInFromDollars(buyNowPriceNum)}` : undefined}
          >
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
        <Field label="Listing duration">
          <div className="mt-2.5 flex flex-wrap gap-2" role="radiogroup" aria-label="Listing duration">
            {LISTING_DURATION_HOURS.map((h) => (
              <RadioPill key={h} selected={durationHours === h} onClick={() => setDurationHours(h)}>
                {durationLabel(h)}
              </RadioPill>
            ))}
          </div>
        </Field>
      </section>

      <section className="space-y-6">
        <SectionLabel>Media</SectionLabel>
        <div className="grid grid-cols-2 gap-4 sm:gap-6">
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

      <section className="space-y-4">
        <SectionLabel>Seller commitment</SectionLabel>
        <label className="flex cursor-pointer items-start gap-3 rounded-panel bg-surface p-4 text-[15px] leading-relaxed text-ink">
          <input
            type="checkbox"
            checked={commitmentAccepted}
            onChange={(e) => setCommitmentAccepted(e.target.checked)}
            className="mt-1 size-5 shrink-0 accent-brand"
          />
          I confirm I own these tickets and will transfer them to the buyer through the
          official platform transfer within the required window after the sale.
        </label>
      </section>

      <Button
        type="submit"
        variant="primary"
        size="lg"
        className="w-full"
        disabled={isPending || cover.uploading || proof.uploading}
        pending={isPending}
        pendingLabel="Publishing…"
      >
        Publish listing
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
      // These are radios rendered as buttons. Without role/aria-checked a
      // screen reader announces "button" with no indication of which option is
      // selected — the choice is conveyed by colour alone.
      role="radio"
      aria-checked={selected}
      onClick={onClick}
      className={`pressable min-h-10 rounded-full border px-4 text-[14px] font-semibold ${
        selected ? "border-ink bg-ink text-canvas" : "border-control text-ink hover:border-ink"
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
      <p className="t-micro mb-2.5 text-muted">{label}</p>
      <label className="relative flex aspect-[4/5] cursor-pointer flex-col items-center justify-center gap-2 overflow-hidden rounded-panel border border-dashed border-control bg-surface p-3 text-center transition-colors hover:border-ink has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-ink">
        {state.previewUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- local object URL preview, not a remote asset
          <img src={state.previewUrl} alt="" className="poster absolute inset-0 size-full object-contain" />
        ) : (
          <>
            <Icon name="image" size={26} className="text-muted" />
            <span className="t-body-sm text-muted">{hint}</span>
          </>
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
      {state.uploading ? <p className="t-body-sm mt-2 text-muted">Uploading…</p> : null}
      {state.error ? <p className="t-body-sm mt-2 font-medium text-danger">{state.error}</p> : null}
      {state.path && !state.uploading ? <p className="t-body-sm mt-2 text-success">✓ Uploaded</p> : null}
    </div>
  );
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return <h2 className="t-section border-b border-line pb-2.5 text-ink-2">{children}</h2>;
}
