import { ACTION_STATE_LABELS, ACTION_TYPE_LABELS, PAYMENT_STATUS_LABELS, TRANSFER_STATUS_LABELS } from "@/lib/format";

/**
 * Two small static workflow diagrams for the order page (V-1 item 4): the
 * refund path as it actually is today, and the payout release path. Every step
 * is taken from a record in this repo — the console's own copy
 * (OrderActions, the order page, the action detail page), the status vocabulary
 * (lib/format.ts) and the manual refund SOP (a draft, on branch
 * admin/manual-refund-sop) — and cites
 * it; `pins` are the phrases a test checks against those sources, so the
 * diagram cannot drift from them. Nothing here is a new rule, a claim about
 * money that moved, or a promise about what will happen.
 */
export type WorkflowSource = { file: string; quote: string; at?: string };
export type WorkflowStep = { id: string; title: string; detail: string; pins: string[]; sources: WorkflowSource[] };

const ORDER_ACTIONS = "components/orders/OrderActions.tsx";
const ORDER_PAGE = "app/(console)/orders/[paymentId]/page.tsx";
const FORMAT = "lib/format.ts";
/** The action detail page: the console's own sentence on when a payment flips to refunded. */
const ACTIONS_PAGE = "app/(console)/actions/[id]/page.tsx";
/** The SOP is not in this tree; a reader finds it on its branch. */
export const SOP_SOURCE = "docs/admin-console/MANUAL_REFUND_SOP.md (branch admin/manual-refund-sop, draft)";

export const REFUND_PATH: WorkflowStep[] = [
  {
    id: "request",
    title: "Request refund",
    detail: `A founder requests it on the order page; the request is parked as ${ACTION_STATE_LABELS.awaiting_approval.toLowerCase()}. Full refund of the total only.`,
    pins: ["Request refund", "awaiting approval", "founder", "full refund"],
    sources: [
      { file: ORDER_ACTIONS, quote: "Only a founder can request a refund." },
      { file: ORDER_ACTIONS, quote: "Parked as awaiting approval" },
      { file: ORDER_ACTIONS, quote: "Full refund of" },
    ],
  },
  {
    id: "approval",
    title: "Two-founder approval",
    detail: "The other founder approves under System → Approvals; nothing changes until then.",
    pins: ["Two-founder approval", "the other founder approves", "System → Approvals", "nothing changes until then"],
    sources: [
      { file: ORDER_ACTIONS, quote: 'eyebrow="Two-founder approval" title="Execute refund"' },
      { file: ORDER_ACTIONS, quote: "after the other founder approves" },
      { file: ORDER_ACTIONS, quote: "Requires the other founder's approval under System → Approvals; nothing changes until then." },
    ],
  },
  {
    id: "disabled",
    title: "Execution disabled in production",
    detail: "ops.setting refund_execute_enabled is false, so the request is rejected as disabled. The console never calls Stripe.",
    pins: ["refund_execute_enabled is false", "rejected as disabled", "The console never calls Stripe"],
    sources: [
      { file: ORDER_ACTIONS, quote: "Disabled until ops-refund-execute is deployed." },
      { file: ORDER_ACTIONS, quote: "ops.setting refund_execute_enabled is false. Follow the Stripe Dashboard SOP; the request below will be rejected as disabled." },
      { file: ORDER_ACTIONS, quote: "The console never calls Stripe." },
    ],
  },
  {
    id: "manual",
    title: "Manual Stripe Dashboard refund (SOP, draft)",
    detail: "Per the manual refund SOP (draft — not approved for use): a full refund of the PaymentIntent in the Stripe Dashboard, the re_… id noted on the case.",
    pins: ["a full refund of the PaymentIntent in the Stripe Dashboard", "DRAFT — not approved for use", "re_"],
    sources: [
      { file: SOP_SOURCE, quote: "There is one manual money step:** a full refund of the PaymentIntent in the Stripe Dashboard", at: "The five rules, rule 1 (→ §4)" },
      { file: SOP_SOURCE, quote: "Note the `re_…` id on the case and set the case to *Waiting*", at: "At a glance, step 5 (→ §6)" },
      { file: SOP_SOURCE, quote: "DRAFT — not approved for use", at: "header note" },
    ],
  },
  {
    id: "webhook",
    title: "Webhook records the result",
    detail: `“${PAYMENT_STATUS_LABELS.refunded}” is set by the Stripe webhook (charge.refunded), never by the console. Confirm the outcome in Stripe.`,
    pins: ["set by the Stripe webhook", "never by the console", PAYMENT_STATUS_LABELS.refunded, "confirm the outcome in Stripe", "charge.refunded"],
    sources: [
      { file: ORDER_PAGE, quote: "“Refund recorded” is set by the Stripe webhook or by the expiry job when a refund is recorded — never by the console." },
      { file: ORDER_PAGE, quote: "confirm the outcome in Stripe" },
      { file: FORMAT, quote: 'refunded: "Refund recorded (not confirmed settled)"' },
      { file: ACTIONS_PAGE, quote: "the local payment flips to refunded when charge.refunded lands" },
      { file: ACTIONS_PAGE, quote: "the payment shows “refunded” only after the charge.refunded webhook lands." },
      { file: SOP_SOURCE, quote: "**`charge.refunded`**", at: "§5.1" },
    ],
  },
];

export const PAYOUT_RELEASE_PATH: WorkflowStep[] = [
  {
    id: "seller_sent",
    title: TRANSFER_STATUS_LABELS.seller_sent,
    detail: "The transfer is in seller_sent, no release is recorded (payout_released_at is empty) and no dispute is open (disputeOpen is false); the release form is offered only then.",
    pins: [TRANSFER_STATUS_LABELS.seller_sent, "seller_sent", "payout_released_at", "disputeOpen"],
    sources: [
      { file: FORMAT, quote: 'seller_sent: "Seller marked sent"' },
      { file: ORDER_PAGE, quote: 'const canRelease = t?.status === "seller_sent" && !t?.payout_released_at && !disputeOpen;' },
    ],
  },
  {
    id: "request",
    title: "Request release",
    detail: `A founder requests “${ACTION_TYPE_LABELS.payout_release}”; the request is parked as ${ACTION_STATE_LABELS.awaiting_approval.toLowerCase()}.`,
    pins: ["Request release", ACTION_TYPE_LABELS.payout_release, "founder", "awaiting approval"],
    sources: [
      { file: ORDER_ACTIONS, quote: 'label="Request release"' },
      { file: ORDER_ACTIONS, quote: "Only a founder can request a payout release." },
      { file: FORMAT, quote: 'payout_release: "Release held payout"' },
      { file: FORMAT, quote: 'awaiting_approval: "Awaiting approval"' },
    ],
  },
  {
    id: "approval",
    title: "Second founder approval",
    detail: "The other founder approves under System → Approvals; nothing changes until then.",
    pins: ["the other founder", "System → Approvals", "nothing changes until then"],
    sources: [
      { file: ORDER_ACTIONS, quote: 'eyebrow="Two-founder approval" title="Release held payout"' },
      { file: ORDER_ACTIONS, quote: "Requires the other founder's approval under System → Approvals; nothing changes until then." },
    ],
  },
  {
    id: "worker",
    title: "Payout worker",
    detail: "Marks the transfer released; the payout worker creates the Stripe Transfer to the seller's connected account on its next run (not a bank payout). The state then reads “Released to connected account”.",
    pins: ["Marks the transfer released", "the payout worker creates the Stripe Transfer", "connected account on its next run", "not a bank payout", "Released to connected account"],
    sources: [
      { file: ORDER_ACTIONS, quote: "Marks the transfer released; the payout worker creates the Stripe Transfer to the seller's connected account on its next run (not a bank payout)." },
      { file: FORMAT, quote: 'if (row.payout_released_at) return "Released to connected account";' },
    ],
  },
];

/** Greedy word wrap to at most `max` characters per line; a longer single word stays whole. */
export function wrapLines(text: string, max: number): string[] {
  const words = text.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let cur = "";
  for (const w of words) {
    if (!cur) cur = w;
    else if (`${cur} ${w}`.length <= max) cur = `${cur} ${w}`;
    else {
      lines.push(cur);
      cur = w;
    }
  }
  if (cur) lines.push(cur);
  return lines;
}

const W = 360;
const PAD = 12;
const TITLE_H = 18;
const LINE_H = 14;
const BOX_PAD = 10;
const ARROW_H = 22;
const CHARS = 58;

/**
 * One static diagram: numbered steps stacked top to bottom with an arrow
 * between them. The SVG is an image (role="img") named by its own <title> and
 * <desc>; the visually hidden ordered list after it is the text alternative and
 * carries each step's source. The SVG scales with its container (viewBox,
 * w-full, h-auto) so it never widens a phone layout.
 */
export function WorkflowDiagram({ id, title, description, steps }: { id: string; title: string; description: string; steps: WorkflowStep[] }) {
  const laid = steps.map((s) => ({ step: s, lines: wrapLines(s.detail, CHARS) }));
  const heights = laid.map(({ lines }) => BOX_PAD * 2 + TITLE_H + lines.length * LINE_H);
  const total = heights.reduce((n, hgt) => n + hgt, 0) + ARROW_H * (steps.length - 1) + PAD * 2;
  // Each box starts below the ones before it plus one arrow gap each (pure: nothing is reassigned during render).
  const tops = heights.map((_, i) => PAD + heights.slice(0, i).reduce((n, hgt) => n + hgt, 0) + ARROW_H * i);
  const boxes = laid.map(({ step, lines }, i) => ({ step, lines, top: tops[i], h: heights[i], i }));
  return (
    <figure className="min-w-0">
      <svg role="img" aria-labelledby={`${id}-title ${id}-desc`} viewBox={`0 0 ${W} ${total}`} focusable="false" className="block h-auto w-full max-w-full text-ink">
        <title id={`${id}-title`}>{title}</title>
        <desc id={`${id}-desc`}>{description}</desc>
        {boxes.map(({ step, lines, top, h, i }) => (
          <g key={step.id}>
            <rect x={PAD} y={top} width={W - PAD * 2} height={h} rx={12} fill="var(--color-card)" stroke="var(--color-line-strong)" />
            <circle cx={PAD + BOX_PAD + 10} cy={top + BOX_PAD + 9} r={9} fill="var(--color-solid)" />
            <text x={PAD + BOX_PAD + 10} y={top + BOX_PAD + 9} dy="0.35em" textAnchor="middle" fontSize="10" fontWeight="600" fill="var(--color-card)">
              {i + 1}
            </text>
            <text x={PAD + BOX_PAD + 26} y={top + BOX_PAD + 9} dy="0.35em" fontSize="12.5" fontWeight="600" fill="currentColor">
              {step.title}
            </text>
            {lines.map((line, k) => (
              <text key={k} x={PAD + BOX_PAD} y={top + BOX_PAD + TITLE_H + 10 + k * LINE_H} fontSize="10.5" fill="var(--color-muted)">
                {line}
              </text>
            ))}
            {i < boxes.length - 1 ? (
              <g data-arrow="" aria-hidden="true">
                <line x1={W / 2} y1={top + h} x2={W / 2} y2={top + h + ARROW_H - 6} stroke="var(--color-axis)" strokeWidth={1.5} />
                <path d={`M${W / 2 - 5},${top + h + ARROW_H - 10} L${W / 2},${top + h + ARROW_H - 4} L${W / 2 + 5},${top + h + ARROW_H - 10}`} fill="none" stroke="var(--color-axis)" strokeWidth={1.5} />
              </g>
            ) : null}
          </g>
        ))}
      </svg>
      <ol className="sr-only">
        {steps.map((s, i) => (
          <li key={s.id}>
            Step {i + 1}: {s.title}. {s.detail} Source: {s.sources.map((src) => `${src.file}${src.at ? ` ${src.at}` : ""}`).join("; ")}.
          </li>
        ))}
      </ol>
      <figcaption className="mt-2 text-[0.75rem] leading-relaxed text-dim">
        {title}. Steps are taken from this console&apos;s own copy, its status vocabulary and the manual refund SOP (draft — not approved for use); nothing here is a new rule.
      </figcaption>
    </figure>
  );
}

/** The order page's disclosure: collapsed by default, in the actions column, after the action panels. */
export function HowThisWorks() {
  return (
    <details className="panel px-5 py-4 md:px-6">
      <summary className="inline-flex min-h-9 items-center gap-2 rounded-lg text-[0.9375rem] font-medium text-ink">How this works</summary>
      <div className="reveal mt-4 space-y-6">
        <WorkflowDiagram id="refund-path" title="Refund path (today)" description="How a refund happens today: a founder's request, the other founder's approval, execution disabled in production, the manual Stripe Dashboard refund per the draft SOP, and the webhook recording the result." steps={REFUND_PATH} />
        <WorkflowDiagram id="payout-release-path" title="Payout release path" description="How a held payout is released: a transfer the seller marked sent, a founder's release request, the second founder's approval, and the payout worker's Stripe Transfer to the connected account." steps={PAYOUT_RELEASE_PATH} />
      </div>
    </details>
  );
}
