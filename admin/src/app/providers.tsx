"use client";

import Link from "next/link";
import { Theme } from "@astryxdesign/core/theme";
import { LinkProvider } from "@astryxdesign/core/Link";
import { neutralTheme } from "@astryxdesign/theme-neutral/built";

/** Published Meta Astryx components, using the existing Next router and brand tokens. */
export function DashboardProviders({ children }: { children: React.ReactNode }) {
  return (
    <Theme theme={neutralTheme} mode="light">
      <LinkProvider component={Link}>{children}</LinkProvider>
    </Theme>
  );
}
