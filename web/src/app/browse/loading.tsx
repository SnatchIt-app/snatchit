import { Container } from "@/components/ui/Container";
import { ListingCardSkeleton, Skeleton } from "@/components/ui/Skeleton";

export default function BrowseLoading() {
  return (
    <Container className="py-12 lg:py-16">
      <Skeleton className="h-11 w-72" />
      <Skeleton className="mt-5 h-3 w-64" />
      <div className="mt-12 grid gap-12 lg:grid-cols-[248px_minmax(0,1fr)] lg:gap-16">
        <div className="hidden lg:block">
          <Skeleton className="h-[480px]" />
        </div>
        <div>
          <Skeleton className="mb-8 h-11 lg:hidden" />
          <div className="grid grid-cols-1 gap-x-5 gap-y-12 sm:grid-cols-2 xl:grid-cols-3">
            {Array.from({ length: 6 }).map((_, i) => (
              <ListingCardSkeleton key={i} />
            ))}
          </div>
        </div>
      </div>
    </Container>
  );
}
