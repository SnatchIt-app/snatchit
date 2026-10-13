import { Container } from "@/components/ui/Container";
import { LinkButton } from "@/components/ui/Button";
import { Icon } from "@/components/ui/Icon";

/**
 * Native StateView (empty) look — glyph, Oswald title in its own case, muted
 * body, one action. Written out here rather than via <EmptyState> because the
 * title has to be the page's <h1>: a 404 has no other heading.
 */
export default function NotFound() {
  return (
    <Container className="py-10 sm:py-16">
      <div className="flex flex-col items-center py-14 text-center sm:py-20">
        <span className="mb-5 inline-flex size-14 items-center justify-center rounded-full bg-surface text-ink-2">
          <Icon name="ticket" size={26} />
        </span>
        <h1 className="t-name-state max-w-md text-ink">This page took the night off</h1>
        <p className="t-body mt-2.5 max-w-sm text-muted">
          The listing may have ended, or the link is off by a character. The marketplace is still going.
        </p>
        <div className="mt-7 flex flex-wrap justify-center gap-3">
          <LinkButton href="/browse" size="lg">
            Browse live listings
          </LinkButton>
        </div>
      </div>
    </Container>
  );
}
