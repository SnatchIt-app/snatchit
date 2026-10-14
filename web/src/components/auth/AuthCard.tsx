import Image from "next/image";
import type { ReactNode } from "react";
import { Container } from "@/components/ui/Container";

/**
 * Shared shell for /login, /signup, /forgot-password, /reset-password and
 * /auth/confirm — the native auth screen (SN mark, Oswald title, underline
 * fields, full-width pill action) on phones. On desktop it becomes a split
 * layout: an atmosphere image on a rounded card to the left and the form in a
 * comfortable 440px column to the right, rather than a phone screen
 * stretched wide.
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
    <Container className="pb-16 pt-8 sm:pt-12 lg:py-10">
      <div className="lg:grid lg:min-h-[min(760px,calc(100dvh-9rem))] lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:gap-12 xl:gap-20">
        {/* Decorative artwork — fixed colours are allowed over images. */}
        <div aria-hidden="true" className="relative hidden overflow-hidden rounded-card bg-surface lg:block">
          <Image
            src="/atmosphere/club-line.jpg"
            alt=""
            fill
            sizes="(min-width: 1200px) 540px, (min-width: 1024px) 45vw, 0px"
            className="object-cover"
          />
          <div className="absolute inset-0 bg-linear-to-t from-black/70 via-black/10 to-transparent" />
          <Image
            src="/brand/sn-logo-white.svg"
            alt=""
            width={99}
            height={36}
            className="absolute bottom-8 left-8 h-9 w-auto"
          />
        </div>

        <div className="flex flex-col justify-center lg:py-6">
          <div className="mx-auto w-full max-w-[440px]">
            <p className="t-micro text-muted">{eyebrow}</p>
            <h1 className="t-display-lg mt-2 text-ink">{title}</h1>
            {subtitle ? <p className="t-body mt-3 text-muted">{subtitle}</p> : null}
            <div className="mt-8">{children}</div>
            {footer ? <div className="mt-8 border-t border-line pt-6">{footer}</div> : null}
          </div>
        </div>
      </div>
    </Container>
  );
}
