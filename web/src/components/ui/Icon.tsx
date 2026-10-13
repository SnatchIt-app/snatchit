import type { SVGProps } from "react";

/**
 * Line icons drawn to sit with the native app's SF Symbols (house, magnifying
 * glass, plus.circle, tag, ticket, person, bell…). 24px grid, 1.8 stroke,
 * currentColor. Decorative by default: pair with visible text or an
 * aria-label on the control.
 */
const PATHS = {
  home: "M3.5 10.5 12 3.8l8.5 6.7V20a1 1 0 0 1-1 1h-5v-6.2h-5V21h-5a1 1 0 0 1-1-1v-9.5Z",
  search: "M10.8 18.1a7.3 7.3 0 1 0 0-14.6 7.3 7.3 0 0 0 0 14.6ZM16.1 16.1l4.4 4.4",
  plus: "M12 7.5v9M7.5 12h9M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z",
  tag: "M3.5 12.6V4.5a1 1 0 0 1 1-1h8.1l8 8a1.4 1.4 0 0 1 0 2l-6.1 6.1a1.4 1.4 0 0 1-2 0l-8-8ZM8 8h.01",
  ticket:
    "M3.5 8.2V6a1 1 0 0 1 1-1h15a1 1 0 0 1 1 1v2.2a2.8 2.8 0 0 0 0 5.6V16a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1v-2.2a2.8 2.8 0 0 0 0-5.6ZM14.5 5.5v2M14.5 10.5v3M14.5 16.5v.01",
  receipt: "M6 3.5h12v17l-2.4-1.5-2.4 1.5-2.4-1.5L8.4 20.5 6 19V3.5ZM9 8h6M9 11.5h6M9 15h3.5",
  user: "M12 12.2a4.1 4.1 0 1 0 0-8.2 4.1 4.1 0 0 0 0 8.2ZM4.5 20.5c.8-3.6 3.7-5.7 7.5-5.7s6.7 2.1 7.5 5.7",
  bell: "M6 16.5V11a6 6 0 1 1 12 0v5.5l1.5 1.8h-15L6 16.5ZM10 20.5a2.2 2.2 0 0 0 4 0",
  bookmark: "M6.5 3.5h11a1 1 0 0 1 1 1v16l-6.5-4.2-6.5 4.2v-16a1 1 0 0 1 1-1Z",
  chevronRight: "m9.5 5.5 6.5 6.5-6.5 6.5",
  chevronLeft: "m14.5 5.5-6.5 6.5 6.5 6.5",
  chevronDown: "m5.5 9.5 6.5 6.5 6.5-6.5",
  arrowRight: "M4.5 12h15M13.5 6l6 6-6 6",
  arrowLeft: "M19.5 12h-15M10.5 6l-6 6 6 6",
  filter: "M4 6.5h16M7 12h10M10 17.5h4",
  close: "m6 6 12 12M18 6 6 18",
  check: "m5 12.5 4.5 4.5L19 7.5",
  alert: "M12 4 2.8 19.5h18.4L12 4ZM12 10v4.5M12 17v.01",
  info: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM12 11v5.5M12 7.8v.01",
  offline: "M3 8.8a14 14 0 0 1 4.6-2.7M10.7 5.1A14 14 0 0 1 21 8.8M6.3 12.3a9 9 0 0 1 3-1.9M14.2 10.3a9 9 0 0 1 3.5 2M9.6 15.8a4.2 4.2 0 0 1 4.8 0M12 19.5v.01M3.5 3.5l17 17",
  clock: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM12 7.5V12l3 2",
  shield: "M12 3.2 19.5 6v5.6c0 4.4-3.1 8.2-7.5 9.2-4.4-1-7.5-4.8-7.5-9.2V6L12 3.2ZM8.8 12.2l2.3 2.3 4.3-4.6",
  external: "M14 4.5h5.5V10M19.5 4.5 11 13M18 14v4.5a1 1 0 0 1-1 1H5.5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1H10",
  gear: "M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4ZM19.4 13.5l1.6 1.2-1.8 3.1-1.9-.7a7.4 7.4 0 0 1-2.3 1.3l-.3 2h-3.6l-.3-2a7.4 7.4 0 0 1-2.3-1.3l-1.9.7-1.8-3.1 1.6-1.2a7.6 7.6 0 0 1 0-2.9L2.6 9.3l1.8-3.1 1.9.7a7.4 7.4 0 0 1 2.3-1.3l.3-2h3.6l.3 2a7.4 7.4 0 0 1 2.3 1.3l1.9-.7 1.8 3.1-1.6 1.2a7.6 7.6 0 0 1 0 2.9Z",
  list: "M8.5 6.5h11M8.5 12h11M8.5 17.5h11M4.5 6.5h.01M4.5 12h.01M4.5 17.5h.01",
  upload: "M12 15.5V4.5M7.5 9 12 4.5 16.5 9M4.5 15v4.5a1 1 0 0 1 1 1h13a1 1 0 0 1 1-1V15",
  image: "M4.5 4.5h15a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1v-13a1 1 0 0 1 1-1ZM3.5 16l5-5 4 4 2.5-2.5 5.5 5.5M15.5 9h.01",
  sun: "M12 16.2a4.2 4.2 0 1 0 0-8.4 4.2 4.2 0 0 0 0 8.4ZM12 2.8v1.7M12 19.5v1.7M2.8 12h1.7M19.5 12h1.7M5.5 5.5l1.2 1.2M17.3 17.3l1.2 1.2M5.5 18.5l1.2-1.2M17.3 6.7l1.2-1.2",
  moon: "M19.8 14.6A8.3 8.3 0 0 1 9.4 4.2a8.3 8.3 0 1 0 10.4 10.4Z",
  monitor: "M3.5 5h17a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1h-17a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1ZM8.5 20.5h7M12 17v3.5",
  logout: "M14.5 4.5h4a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-4M10 16.5 14.5 12 10 7.5M14.5 12H4",
  phone: "M8 3.5h8a1 1 0 0 1 1 1v15a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1v-15a1 1 0 0 1 1-1ZM11 17.5h2",
  card: "M3.5 6h17a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1h-17a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1ZM2.5 10h19M6.5 14.5h3",
  bank: "M3.5 9.5 12 4.5l8.5 5M5 10v7.5M9.5 10v7.5M14.5 10v7.5M19 10v7.5M3.5 20h17",
  mail: "M4 5.5h16a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-11a1 1 0 0 1 1-1ZM3.5 6.5 12 13l8.5-6.5",
  lock: "M6.5 10.5h11a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1ZM8.5 10.5V7.5a3.5 3.5 0 0 1 7 0v3",
  trash: "M4.5 6.5h15M9.5 6.5V4.5h5v2M6.5 6.5l1 13a1 1 0 0 0 1 1h7a1 1 0 0 0 1-1l1-13",
  pencil: "M15.5 4.5 19.5 8.5 9 19H5v-4L15.5 4.5Z",
  spark: "M12 3.5v4M12 16.5v4M3.5 12h4M16.5 12h4M6 6l2.8 2.8M15.2 15.2 18 18M6 18l2.8-2.8M15.2 8.8 18 6",
} as const;

export type IconName = keyof typeof PATHS;

export function Icon({
  name,
  size = 22,
  strokeWidth = 1.8,
  filled = false,
  className = "",
  ...rest
}: { name: IconName; size?: number; strokeWidth?: number; filled?: boolean } & Omit<SVGProps<SVGSVGElement>, "name">) {
  return (
    <svg
      aria-hidden="true"
      focusable="false"
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={`shrink-0 ${className}`}
      {...rest}
    >
      <path d={PATHS[name]} />
    </svg>
  );
}
