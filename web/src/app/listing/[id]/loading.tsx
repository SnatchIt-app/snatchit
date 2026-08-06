import { Container } from "@/components/ui/Container";
import { Skeleton } from "@/components/ui/Skeleton";

/**
 * Highest-traffic route and the slowest: the page awaits five queries before
 * it can render anything. Without this, tapping a listing looked like a dead
 * tap on mobile until every one of them resolved.
 */
export default function ListingLoading() {
  return (
    <Container className="py-10 lg:py-14">
      <Skeleton className="h-3 w-32" />
      <div className="mt-8 grid gap-10 lg:grid-cols-[minmax(0,1fr)_360px] lg:gap-14">
        <div>
          <Skeleton className="aspect-[3/2] w-full" />
          <Skeleton className="mt-8 h-10 w-3/4" />
          <Skeleton className="mt-4 h-4 w-1/2" />
          <div className="mt-9 grid grid-cols-2 gap-6 border-y border-primary/15 py-6 sm:grid-cols-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i}>
                <Skeleton className="h-2.5 w-16" />
                <Skeleton className="mt-2 h-4 w-24" />
              </div>
            ))}
          </div>
        </div>
        <div className="space-y-4">
          <Skeleton className="h-40 w-full" />
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-12 w-full" />
        </div>
      </div>
    </Container>
  );
}
