import type { Metadata } from "next";
import { DATA_SOURCE, ENV_LABEL, supabaseHost, type DataSource } from "@/lib/env";
import { DEMO_DATA_LABEL } from "@/lib/preview";

export type SourceInfo = {
  source: DataSource;
  /** Exact wording for the banner — never claims "live". */
  label: string;
  host: string | null;
  envLabel: string;
};

export function sourceInfo(): SourceInfo {
  if (DATA_SOURCE === "database") {
    const host = supabaseHost();
    return { source: "database", host, envLabel: ENV_LABEL, label: `Database (${ENV_LABEL}) — ${host ?? "no host configured"} · reads as your own sign-in; what you see comes from your grants` };
  }
  return { source: "fixtures", host: null, envLabel: ENV_LABEL, label: DEMO_DATA_LABEL };
}

/**
 * Root <title>/<meta description>. The fixture build says DEMO in every tab title so nobody
 * mistakes it for live operations; a database build is the real dashboard and must not.
 * Neither build is meant to be indexed.
 */
export function siteMetadata(source: DataSource): Metadata {
  const robots = { index: false, follow: false };
  if (source === "database") {
    return {
      title: { default: "Venue dashboard · Snatch It", template: "%s · Venue dashboard · Snatch It" },
      description: "Snatch It venue dashboard for venue staff and organization members.",
      robots,
    };
  }
  return {
    title: { default: "Venue dashboard · DEMO", template: "%s · Venue dashboard · DEMO" },
    description: "Snatch It venue dashboard — preview over sample data. Not live venue operations.",
    robots,
  };
}
