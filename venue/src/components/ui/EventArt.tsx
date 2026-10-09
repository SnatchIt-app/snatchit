/**
 * Event artwork, generated from the event's own title — the identity the
 * approved concept gives the venue dashboard, without stock photography.
 *
 * A warm dark field, a red disc whose position comes from the title, a fine
 * grain, and the title stacked in the editorial serif. Decorative: the real
 * title is always in the page's heading, so this is aria-hidden. It renders
 * the same for sample and real events, and needs no stored image. Thumbnails
 * carry no lettering — at that size it cannot be read.
 */
function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

/** The title as it should read on a poster: no "(sample …)" suffix, a few words per line. */
function lines(title: string, max = 4): string[] {
  const words = title.replace(/\s*\(.*?\)\s*/g, " ").replace(/[—–-]+/g, " ").trim().split(/\s+/).filter(Boolean);
  const out: string[] = [];
  for (const w of words) {
    const last = out[out.length - 1];
    if (last && (last + " " + w).length <= 9 && out.length > 0) out[out.length - 1] = `${last} ${w}`;
    else out.push(w);
  }
  return out.slice(0, max);
}

export function EventArt({ title, variant = "poster", className = "" }: { title: string; variant?: "poster" | "thumb"; className?: string }) {
  const h = hash(title);
  const id = `g${h.toString(36)}${variant === "poster" ? "p" : "t"}`;
  const poster = variant === "poster";
  const W = poster ? 300 : 320;
  const H = poster ? 400 : 240;
  const cx = poster ? 70 + (h % 160) : 60 + (h % 200);
  const cy = poster ? 70 + ((h >> 8) % 90) : 60 + ((h >> 8) % 70);
  const r = poster ? 46 + ((h >> 16) % 20) : 54 + ((h >> 16) % 30);
  const ls = lines(title, poster ? 4 : 3);
  // Three palettes drawn from the brand (ember, amber, rose) and three
  // compositions, so neighbouring events never look like copies.
  const PALETTES = [
    { a: "#e2563a", b: "#a8301d", bg0: "#2a211c", bg1: "#120e0c" },
    { a: "#e89a3c", b: "#b0581b", bg0: "#2b231a", bg1: "#14100b" },
    { a: "#d65a6a", b: "#8f2a3a", bg0: "#271d20", bg1: "#110c0e" },
  ];
  const pal = PALETTES[h % 3];
  const comp = (h >> 4) % 3;
  const size = poster ? (ls.some((l) => l.length > 7) ? 40 : 48) : 30;
  const startY = H - 34 - (ls.length - 1) * size * 0.92;

  return (
    <svg aria-hidden="true" focusable="false" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid slice" className={className}>
      <defs>
        <linearGradient id={`${id}-bg`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={pal.bg0} />
          <stop offset="1" stopColor={pal.bg1} />
        </linearGradient>
        <radialGradient id={`${id}-sun`} cx="0.45" cy="0.4" r="0.6">
          <stop offset="0" stopColor={pal.a} />
          <stop offset="1" stopColor={pal.b} />
        </radialGradient>
        <filter id={`${id}-grain`} x="0" y="0" width="100%" height="100%">
          <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed={h % 97} result="n" />
          <feColorMatrix in="n" type="matrix" values="0 0 0 0 1  0 0 0 0 0.95  0 0 0 0 0.9  0 0 0 0.07 0" />
          <feComposite in2="SourceGraphic" operator="in" />
        </filter>
      </defs>
      <rect width={W} height={H} fill={`url(#${id}-bg)`} />
      <circle cx={cx} cy={cy} r={r} fill={`url(#${id}-sun)`} opacity="0.92" />
      <rect width={W} height={H} fill="#fff" filter={`url(#${id}-grain)`} />
      <rect x="0" y={H * 0.62} width={W} height={H * 0.38} fill="#0f0c0a" opacity="0.35" />
      {!poster && comp === 0 ? (
        <>
          <rect x="0" y={H * 0.72} width={W} height="2" fill="#f6efe6" opacity="0.16" />
          <rect x="0" y={H * 0.8} width={W} height="1" fill="#f6efe6" opacity="0.1" />
        </>
      ) : null}
      {!poster && comp === 1 ? <circle cx={W - cx / 2} cy={H * 0.9} r={r * 1.6} fill="none" stroke="#f6efe6" strokeOpacity="0.14" strokeWidth="1.5" /> : null}
      {!poster && comp === 2
        ? [0, 1, 2, 3].map((i) => <rect key={i} x={W * 0.08 + i * 18} y={H * 0.5 - i * 14} width="6" height={H} fill="#f6efe6" opacity={0.06 + i * 0.02} />)
        : null}
      {(poster ? ls : []).map((l, i) => (
        <text
          key={i}
          x={poster ? 22 : 18}
          y={startY + i * size * 0.92}
          fill="#f6efe6"
          style={{ fontFamily: "var(--font-serif), Georgia, serif", fontSize: size, letterSpacing: "-0.01em", textTransform: "uppercase" }}
        >
          {l}
        </text>
      ))}
      {poster ? (
        <text x={W - 22} y={28} textAnchor="end" fill="#f6efe6" opacity="0.7" style={{ fontFamily: "var(--font-sans), sans-serif", fontSize: 10, letterSpacing: "0.24em" }}>
          SNATCH IT
        </text>
      ) : null}
    </svg>
  );
}
