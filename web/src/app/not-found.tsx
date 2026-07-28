import { Container } from "@/components/ui/Container";
import { EmptyState } from "@/components/ui/EmptyState";
import { LinkButton } from "@/components/ui/Button";

export default function NotFound() {
  return (
    <Container className="py-24">
      <EmptyState
        title="This page took the night off"
        message="The listing may have ended, or the link is off by a character. The marketplace is still going."
        action={<LinkButton href="/browse">Browse live listings</LinkButton>}
      />
    </Container>
  );
}
