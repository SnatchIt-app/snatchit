import type { ReactNode } from "react";
import { Container } from "@/components/ui/Container";

/**
 * Shared shell for /login, /signup, /forgot-password, /reset-password — a
 * narrow centered card in the brand's editorial voice, not a generic
 * Supabase auth widget.
 */
export function AuthCard({
  eyebrow,
  title,
  subtitle,
  children,
  footer,
}: {
  eyebrow: string;
  title: string;
  subtitle?: string;
  children: ReactNode;
  footer?: ReactNode;
}) {
  return (
    <Container className="flex min-h-[70dvh] items-center justify-center py-14 sm:py-20">
      <div className="w-full max-w-[420px]">
        <p className="eyebrow text-primary/80">{eyebrow}</p>
        <h1 className="mt-4 font-display text-[clamp(1.9rem,5vw,2.6rem)] font-bold uppercase leading-[0.95] tracking-[-0.02em] text-ink">
          {title}
        </h1>
        {subtitle ? <p className="mt-3 text-[14px] leading-relaxed text-white/60">{subtitle}</p> : null}
        <div className="mt-8">{children}</div>
        {footer ? <div className="mt-7 border-t border-primary/15 pt-6">{footer}</div> : null}
      </div>
    </Container>
  );
}
