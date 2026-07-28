import { Container } from "@/components/ui/Container";
import { ListingCardSkeleton, Skeleton } from "@/components/ui/Skeleton";

export default function BrowseLoading() {
  return (
    <Container className="py-8 lg:py-10">
      <Skeleton className="h-8 w-56" />
      <Skeleton className="mt-2.5 h-4 w-72" />
      <div className="mt-6 grid gap-8 lg:grid-cols-[260px_minmax(0,1fr)] lg:gap-10">
        <div className="hidden lg:block">
          <Skeleton className="h-[480px]" />
        </div>
        <div>
          <Skeleton className="mb-5 h-11 lg:hidden" />
          <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 xl:grid-cols-3">
            {Array.from({ length: 6 }).map((_, i) => (
              <ListingCardSkeleton key={i} />
            ))}
          </div>
        </div>
      </div>
    </Container>
  );
}
