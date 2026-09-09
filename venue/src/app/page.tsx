import { redirect } from "next/navigation";
import { PREVIEW } from "@/fixtures/venue";

/** The preview has exactly one organization and one venue; land on its events list. */
export default function Home() {
  redirect(`/o/${PREVIEW.orgId}/v/${PREVIEW.venueId}/events`);
}
