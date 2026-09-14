import { DATA_SOURCE, ENV_LABEL, supabaseHost, type DataSource } from "@/lib/env";

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
  return { source: "fixtures", host: null, envLabel: ENV_LABEL, label: "Preview data — sample fixtures, not live venue operations" };
}
