/**
 * Idempotency keys for `ops.execute_action`. One key is minted per form
 * render (in the Server Component) and carried as a hidden input, so a
 * double-click or a retry after a network blip replays the same durable
 * action row instead of creating a second one.
 */
export const IDEMPOTENCY_FIELD = "idempotency_key";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function newIdempotencyKey(): string {
  return crypto.randomUUID();
}

export function isIdempotencyKey(v: unknown): v is string {
  return typeof v === "string" && UUID_RE.test(v);
}

/** Props for the hidden input that carries the key through the form post. */
export function idempotencyField(key: string = newIdempotencyKey()): {
  type: "hidden";
  name: typeof IDEMPOTENCY_FIELD;
  value: string;
} {
  if (!isIdempotencyKey(key)) throw new Error("idempotency key must be a v4 UUID");
  return { type: "hidden", name: IDEMPOTENCY_FIELD, value: key };
}
