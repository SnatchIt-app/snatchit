import { Container } from "@/components/ui/Container";
import { Skeleton } from "@/components/ui/Skeleton";

export default function Loading() {
  return (
    <Container size="medium" className="pb-12 pt-3 lg:pt-6">
      <div role="status" aria-label="Loading checkout">
        <Skeleton className="size-11 rounded-full" />
        <Skeleton className="mt-5 h-10 w-56" />
        <div className="mt-7 grid gap-6 lg:grid-cols-2 lg:gap-10">
          <Skeleton className="h-80 rounded-card" />
          <Skeleton className="h-80 rounded-card" />
        </div>
      </div>
    </Container>
  );
}
