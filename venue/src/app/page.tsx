import { redirect } from "next/navigation";
import { PREVIEW } from "@/fixtures/venue";

/**
 * The demo has exactly one organization and one venue. Land on the Tonight
 * overview, not the events table: a manager arriving mid-shift needs to know
 * what is wrong before they need a list (audit §W1).
 */
export default function Home() {
  redirect(`/o/${PREVIEW.orgId}/v/${PREVIEW.venueId}`);
}
