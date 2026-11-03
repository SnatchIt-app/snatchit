/**
 * JSON-LD text for a <script type="application/ld+json">. "<" is written as < so no value
 * (an event name, a venue) can close the script tag; JSON.parse reads it back unchanged.
 */
export function serializeJsonLd(data: Record<string, unknown>): string {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}
