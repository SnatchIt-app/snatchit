import { Container } from "@/components/ui/Container";
import { ListingCardSkeleton, Skeleton } from "@/components/ui/Skeleton";

export default function BrowseLoading() {
  return (
    <Container className="py-10 lg:py-14">
      <Skeleton className="h-10 w-72" />
      <Skeleton className="mt-3.5 h-4 w-64" />
      <div className="mt-9 grid gap-10 lg:grid-cols-[264px_minmax(0,1fr)] lg:gap-12">
        <div className="hidden lg:block">
          <Skeleton className="h-[520px] rounded-[14px]" />
        </div>
        <div>
          <Skeleton className="mb-6 h-11 lg:hidden" />
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
