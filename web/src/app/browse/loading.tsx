import { Container } from "@/components/ui/Container";
import { FeedRowSkeleton, Skeleton } from "@/components/ui/Skeleton";

export default function BrowseLoading() {
  return (
    <Container className="pb-10 pt-6 lg:pb-14 lg:pt-10" >
      <div role="status" aria-label="Loading listings">
        <Skeleton className="h-10 w-48" />
        <Skeleton className="mt-3 h-4 w-72" />
        <div className="mt-8 grid gap-8 lg:grid-cols-[256px_minmax(0,1fr)] lg:gap-14">
          <div className="max-lg:hidden">
            <Skeleton className="h-[420px]" />
          </div>
          <div>
            <Skeleton className="h-[52px] rounded-full" />
            <div className="mt-6 divide-y divide-line">
              {Array.from({ length: 6 }).map((_, i) => (
                <FeedRowSkeleton key={i} />
              ))}
            </div>
          </div>
        </div>
      </div>
    </Container>
  );
}
