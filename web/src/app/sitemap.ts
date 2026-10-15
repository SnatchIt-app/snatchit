import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/env";
import { getActiveListings } from "@/lib/listings";

// Metadata routes are static by default. The listing read is cookieless, so
// without this the sitemap would be frozen at build time and keep listing
// hidden or ended listings until the next deploy.
export const dynamic = "force-dynamic";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const staticEntries: MetadataRoute.Sitemap = [
    { url: SITE_URL, changeFrequency: "daily", priority: 1 },
    { url: `${SITE_URL}/browse`, changeFrequency: "hourly", priority: 0.9 },
  ];

  let listingEntries: MetadataRoute.Sitemap = [];
  try {
    const listings = await getActiveListings({}, 50);
    listingEntries = listings.map((l) => ({
      url: `${SITE_URL}/listing/${l.id}`,
      lastModified: l.created_at ? new Date(l.created_at) : undefined,
      changeFrequency: "hourly" as const,
      priority: 0.7,
    }));
  } catch {
    // Sitemap stays static if the marketplace query fails.
  }

  return [...staticEntries, ...listingEntries];
}
